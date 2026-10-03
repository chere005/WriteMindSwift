import AppKit

/// THE DRAWING CELLS AS THE MARKDOWN PANE LAYS THEM OUT — one object read by
/// the typesetter that makes room under each drawing line, the layout
/// manager that paints the cell into that room, and the text view whose
/// caret stands in for the bar under a cell. It lives on the
/// `FoldingLayoutManager`, as the folds do, so all three read one list.
///
/// A cell is a row of the page: its line, at the top, and the drawing under
/// it in the same line fragment, so the drawing moves with the text in the
/// very frame the text moves — the panes paint cells, and nothing has to
/// catch up with them.
final class CellLines {
    struct Line: Equatable {
        var id: UUID
        /// The line's characters, without its newline.
        var range: NSRange
    }

    /// The note's drawing lines, in order — read again after every edit
    /// (`read`), before anything is laid out.
    private(set) var lines: [Line] = []
    /// What each cell shows (`NoteStore.cellLooks`).
    private(set) var shown = DrawingCellsShown()
    /// The cell the caret is in: its outline is lit.
    var lit: UUID?
    /// OFF FOR THE MARKDOWN PANE, which is pure text (Sean, 2026-10-02:
    /// "don't show or allow drawings in markdown mode on the notebook
    /// itself, only pure text"): no drawing line is read, so none is given
    /// room, painted, framed or stood in for by the caret — the line is the
    /// line of text it is in the file. The offscreen layout the two panes'
    /// mapping and the PDF are measured by keeps it on, because that is where
    /// a cell has its height.
    var enabled = true

    /// The note's lines read again after an edit to its characters at
    /// `edited`. Nil when every cell is the cell it was, moved along by the
    /// edit at most — TextKit lays out what the edit touched by itself —
    /// and otherwise where the layout has to be done again: from the edit
    /// to the end. A drawing line can stop being one without a character
    /// of it changing (a fence opened above it makes it code), and its room
    /// would stay under a line of code until something else laid it out.
    /// The parse can only change at or after an edit, never above it.
    func read(_ text: String, edited: Int) -> NSRange? {
        let fresh = enabled && text.contains(DrawingCells.relativeFolder)
            ? DrawingCells.lines(in: text).map { Line(id: $0.id, range: $0.range) } : []
        let before = lines
        lines = fresh
        guard fresh.map(\.id) != before.map(\.id) else { return nil }
        let length = (text as NSString).length
        let from = min(max(edited, 0), length)
        return NSRange(location: from, length: length - from)
    }

    /// What the cells show, handed over again. Which lines need laying out
    /// again because their cell is another size in this `column`, and
    /// which only need painting again — a stroke drawn in a cell changes
    /// what it shows and not how tall it is, and redoing the layout for it
    /// would be a relayout on every frame of the pen.
    func show(_ shown: DrawingCellsShown, column: CGFloat) -> (relayout: [NSRange], repaint: [NSRange]) {
        let before = self.shown
        self.shown = shown
        guard before != shown else { return ([], []) }
        var relayout: [NSRange] = [], repaint: [NSRange] = []
        for line in lines {
            let old = before.look(line.id), new = shown.look(line.id)
            guard old != new || before.media != shown.media else { continue }
            if old.shown(column: column).size != new.shown(column: column).size {
                relayout.append(line.range)
            } else {
                repaint.append(line.range)
            }
        }
        return (relayout, repaint)
    }

    /// The room a line fragment gets under its text: its drawing cell,
    /// shown in this column — but only on the LAST fragment of a drawing
    /// line, so a line that wraps (the markers shown, a narrow pane) has
    /// its drawing under it once. Zero for every other fragment.
    func room(under characters: NSRange, column: CGFloat) -> CGFloat {
        guard let line = lines.first(where: {
            NSIntersectionRange($0.range, characters).length > 0 && NSMaxRange(characters) >= NSMaxRange($0.range)
        }) else { return 0 }
        return shown.look(line.id).shown(column: column).size.height
    }
}

extension FoldingLayoutManager {
    /// The column a drawing is shown in: the text container's width less
    /// its padding either side — the width the words wrap at.
    static func column(of container: NSTextContainer) -> CGFloat {
        max(0, container.size.width - 2 * container.lineFragmentPadding)
    }

    /// WHERE A DRAWING LINE'S CELL IS PAINTED, in the view's coordinates
    /// (`origin` is the text container's): the bottom of the used rect of
    /// the line's last fragment — the room the typesetter made — at the
    /// column's left. THE ONE GEOMETRY: the painter, the frames the drawing
    /// layer is handed and the cell boxes the seams and brackets are made
    /// from all read it, so none of them can drift from the others. Nil
    /// while it is folded away or not laid out with its room yet.
    func cellRect(_ line: CellLines.Line, in container: NSTextContainer, origin: CGPoint) -> CGRect? {
        guard line.range.length > 0, !folding.hides(line.range),
              let storage = textStorage, NSMaxRange(line.range) <= storage.length else { return nil }
        let glyph = glyphIndexForCharacter(at: NSMaxRange(line.range) - 1)
        guard glyph < numberOfGlyphs else { return nil }
        let used = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let size = drawings.shown.look(line.id).shown(column: Self.column(of: container)).size
        guard used.height >= size.height else { return nil }
        return CGRect(x: fragment.minX + container.lineFragmentPadding + origin.x,
                      y: used.maxY - size.height + origin.y, width: size.width, height: size.height)
    }

    /// The cells in this layout, painted — called while the text view draws
    /// its background, so the words are drawn over the paper and never
    /// under it.
    func paintDrawingCells(forGlyphRange glyphs: NSRange, at origin: CGPoint) {
        guard !drawings.lines.isEmpty, let container = textContainers.first,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let paper = DrawingCellPainter.Paper.screen(hex: InkPaths.notePaperHex(dark: dark))
        let column = Self.column(of: container)
        for line in drawings.lines where NSIntersectionRange(line.range, characters).length > 0 {
            guard let rect = cellRect(line, in: container, origin: origin) else { continue }
            DrawingCellPainter.paint(drawings.shown.look(line.id), in: context, at: rect.origin, column: column,
                                     paper: paper, media: drawings.shown.media)
            DrawingCellPainter.outline(rect, lit: drawings.lit == line.id, in: context)
        }
        // What is painted is where the cell is. The frames the layer over
        // the pane was told are re-read now, so a layout that settled after
        // the last time they were measured — a heading restyled, a marker
        // hidden — is never left a few points off what is on screen.
        onPainted?()
    }
}
