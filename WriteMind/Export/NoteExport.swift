import AppKit
import SwiftUI

/// A note on paper: the rendered page, the drawing over it, cut into sheets
/// (Sean, 2026-09-19: "export as pdf").
///
/// **Why the preview's own views render the text.** The alternative was an
/// `NSAttributedString` through an `NSLayoutManager`, which would mean a
/// second renderer for headings, lists, tables, code and maths — two
/// descriptions of one look, drifting apart from the first change. SwiftUI's
/// `ImageRenderer` draws the very views the preview draws, straight into the
/// PDF's `CGContext`, and what lands there is real text (`BT … TJ`) rather
/// than a picture of text: it can be selected, searched and printed at any
/// size. The drawing layer does NOT go through it — see `DrawingInk` for
/// why a traced capture has to be stamped in by Core Graphics to stay
/// vector.
///
/// The seam is `NotePDF.Piece`: a rectangle in the document and a closure
/// that paints it. Everything above the seam is measurement, everything
/// below it is `PagePlan`, and both can be tested without a window.
@MainActor
enum NoteExport {
    /// The pane a note is measured against before the window has said how
    /// wide it is — a note can be exported without ever having been shown.
    static let fallbackPane = CGSize(width: 900, height: 600)

    /// Paper is white whatever the window is.
    static let paperHex = "#FFFFFF"

    /// The note as PDF bytes, or nil if a context could not be opened.
    ///
    /// `pane` is the editor pane the drawing's objects were placed against:
    /// the text is laid out at that width and the whole column is then
    /// shrunk onto the paper. Folded sections are NOT folded here — a note
    /// printed short of the words it holds would be a note lost.
    ///
    /// The objects are kept in the MARKDOWN pane's frame, and the paper is
    /// laid out the rendered way, so each one goes onto the paper through
    /// a `PaneMapping` from the markdown pane's cells to the paper's: a
    /// picture put beside a paragraph is beside it on paper. `markers` and
    /// `folds` are how that pane is laying the note out — its markers
    /// shown or hidden, its sections closed — because that is the layout
    /// the objects were put beside.
    static func pdf(markdown: String, drawing: Drawing, media: URL?, pane: CGSize,
                    markers: Bool = true, folds: Set<String> = [],
                    paper: CGSize = PagePlan.paper, margin: CGFloat = PagePlan.margin) -> Data? {
        let size = pane.width > 40 && pane.height > 40 ? pane : fallbackPane
        let column = max(1, size.width - MarkdownPreview.sideInset * 2)

        var data: Data?
        // Light, always. The colours in this app answer the appearance they
        // are drawn in, and the dark ones are white-on-black: rendered in a
        // dark window they would come out as white text on white paper.
        let onPaper = {
            var pieces: [NotePDF.Piece] = []
            let blocks = MarkdownParser.positioned(from: markdown)
            let renderers = blocks.map { renderer(for: $0.block, width: column) }
            var heights: [CGFloat] = []
            for renderer in renderers {
                var height: CGFloat = 0
                renderer.render { measured, _ in height = measured.height }
                heights.append(height)
            }

            // The same column the preview builds: the cells in order, one
            // gap apart, and nothing on the drawing layer in it.
            let places = PreviewLayout.positions(
                rows: zip(blocks, heights).map { (id: $0.range.location, height: $1) },
                spacing: MarkdownPreview.blockGap,
                top: MarkdownPreview.topInset + MarkdownPreview.gapHeight)

            var cells: [CellSeams.Box] = []
            for (index, block) in blocks.enumerated() {
                guard heights[index] > 0, let place = places[block.range.location] else { continue }
                cells.append(CellSeams.Box(top: place.top, bottom: place.bottom, offset: block.range.location))
                let frame = CGRect(x: MarkdownPreview.sideInset, y: place.top,
                                   width: column, height: heights[index])
                let renderer = renderers[index]
                pieces.append(NotePDF.Piece(frame: frame) { context in
                    context.translateBy(x: frame.minX, y: frame.minY)
                    // The renderer draws downwards from the origin, which
                    // is what the document's coordinates already are.
                    renderer.render { _, draw in draw(context) }
                })
            }

            // Then the drawing, one object at a time, each in its own box.
            // `PagePlan` keeps a piece whole and welds pieces that overlap
            // onto one sheet, which is all the bands were ever buying.
            //
            // What floating costs the paper, so it is not read as a bug:
            // ink now goes OVER the text rather than beside it, so a stroke
            // drawn across three paragraphs welds itself and all three into
            // one unbreakable unit, and a stroke dragged from the top of a
            // long note to the bottom puts the whole note on one shrunken
            // sheet. That is the rule Sean asked for (2026-09-20: "free
            // floating… don't push other cells around") followed through.
            let placed = drawingOnPaper(drawing, markdown: markdown, cells: cells, pane: size,
                                        markers: markers, folds: folds)
            for item in placed.visibleItems {
                let box = item.bounds(in: size)
                guard box.width.isFinite, box.height.isFinite, box.height > 0 else { continue }
                pieces.append(NotePDF.Piece(frame: box) { context in
                    DrawingInk.draw(item, in: context, size: size, media: media)
                })
            }

            data = NotePDF.data(pieces, documentWidth: size.width, paper: paper, margin: margin)
        }

        if let light = NSAppearance(named: .aqua) {
            light.performAsCurrentDrawingAppearance(onPaper)
        } else {
            onPaper()
        }
        return data
    }

    /// The drawing as it goes on paper: kept in the markdown pane's frame
    /// — that pane laying the note out with `markers` and `folds` — and
    /// put beside the same words among the paper's own `cells`.
    static func drawingOnPaper(_ drawing: Drawing, markdown: String, cells: [CellSeams.Box], pane size: CGSize,
                               markers: Bool, folds: Set<String>) -> Drawing {
        let source = MarkdownTextView.cellBoxes(of: markdown, pane: size, showMarkers: markers, collapsed: folds)
        let mapping = PaneMapping(from: source.cells, to: cells,
                                  fromColumn: MarkdownTextView.column(width: source.width),
                                  toColumn: MarkdownPreview.column(width: size.width))
        return drawing.shown(through: mapping, in: size)
    }

    /// One cell, as the preview draws it, on white paper.
    private static func renderer(for block: MarkdownBlock, width: CGFloat) -> ImageRenderer<AnyView> {
        let view = AnyView(
            MarkdownPreview.BlockView(block: block)
                .frame(width: width, alignment: .leading)
                .padding(.vertical, 3)
                .environment(\.notePaper, paperHex)
                .environment(\.colorScheme, .light))
        let renderer = ImageRenderer(content: view)
        renderer.isOpaque = false
        return renderer
    }

    // MARK: - The file

    /// What the save panel should offer: the note's own name, as a PDF.
    static func suggestedName(for note: URL) -> String {
        note.deletingPathExtension().lastPathComponent + ".pdf"
    }
}
