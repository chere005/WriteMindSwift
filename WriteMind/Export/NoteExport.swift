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
    ///
    /// A DRAWING CELL goes on paper the way the layer does, as vectors:
    /// painted by the cell's own painter on white (`DrawingCellPainter`),
    /// at the size the page shows it in this column — never through an
    /// `ImageRenderer`. A folded one is printed, as every fold is.
    static func pdf(markdown: String, drawing: Drawing, cells: DrawingCellsShown = DrawingCellsShown(),
                    media: URL?, pane: CGSize, markers: Bool = true, folds: Set<String> = [],
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
            var renderers: [Int: ImageRenderer<AnyView>] = [:]
            let frames = layOut(blocks, column: column, cells: cells) { index, block in
                let renderer = renderer(for: block, width: column)
                renderers[index] = renderer
                var height: CGFloat = 0
                renderer.render { measured, _ in height = measured.height }
                return height
            }

            var boxes: [CellSeams.Box] = []
            for (index, block) in blocks.enumerated() {
                guard let frame = frames[index] else { continue }
                boxes.append(CellSeams.Box(top: frame.minY, bottom: frame.maxY, offset: block.range.location))
                if case .drawing(let id, _) = block.block {
                    let look = cells.look(id)
                    pieces.append(NotePDF.Piece(frame: frame) { context in
                        DrawingCellPainter.paint(look, in: context, at: frame.origin, column: column, paper: .white,
                                                 media: cells.media)
                    })
                } else if let renderer = renderers[index] {
                    pieces.append(NotePDF.Piece(frame: frame) { context in
                        context.translateBy(x: frame.minX, y: frame.minY)
                        // The renderer draws downwards from the origin,
                        // which is what the document's coordinates already
                        // are.
                        renderer.render { _, draw in draw(context) }
                    })
                }
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
            let placed = drawingOnPaper(drawing, markdown: markdown, cells: boxes, pane: size,
                                        markers: markers, folds: folds, drawings: cells)
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
                               markers: Bool, folds: Set<String>,
                               drawings: DrawingCellsShown = DrawingCellsShown()) -> Drawing {
        let source = MarkdownTextView.cellBoxes(of: markdown, pane: size, showMarkers: markers, collapsed: folds,
                                                drawings: drawings)
        let mapping = PaneMapping(from: source.cells, to: cells,
                                  fromColumn: MarkdownTextView.column(width: source.width),
                                  toColumn: MarkdownPreview.column(width: size.width))
        return drawing.shown(through: mapping, in: size)
    }

    /// THE COLUMN ON PAPER: where each block goes, the way the rendered
    /// page stacks them — in order, one gap apart, from the page's top — or
    /// nil for one with no height. A drawing cell is as tall as the page
    /// shows it in this column, at the column's left, and is never handed
    /// to `measure`: that is an `ImageRenderer`, and a drawing goes on
    /// paper as vectors. `measure` is given the block's index and the block.
    static func layOut(_ blocks: [PositionedBlock], column: CGFloat, cells: DrawingCellsShown,
                       measure: (Int, MarkdownBlock) -> CGFloat) -> [CGRect?] {
        let sizes: [CGSize] = blocks.enumerated().map { index, block in
            if case .drawing(let id, _) = block.block { return cells.look(id).shown(column: column).size }
            return CGSize(width: column, height: measure(index, block.block))
        }
        let places = PreviewLayout.positions(
            rows: zip(blocks, sizes).map { (id: $0.range.location, height: $1.height) },
            spacing: MarkdownPreview.blockGap,
            top: MarkdownPreview.topInset + MarkdownPreview.gapHeight)
        return zip(blocks, sizes).map { block, size in
            guard size.height > 0, let place = places[block.range.location] else { return nil }
            return CGRect(x: MarkdownPreview.sideInset, y: place.top, width: size.width, height: size.height)
        }
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
