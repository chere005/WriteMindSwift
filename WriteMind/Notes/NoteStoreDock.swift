import Foundation

/// A DOCK THAT MADE A CELL: the line it wrote and where, tied to the drawing
/// step that moved the objects (Sean, 2026-10-02: "a dock button which
/// inserts it into the cell of the existing cursor, and a create cell from
/// drawing"). One step on the drawing's own stack takes the objects back to
/// the layer, and this is what takes the line they were docked under out of
/// the note with them — and puts it back with the redo.
struct DockRecord: Equatable {
    /// The `drawingSteps` the dock is.
    var step: Int
    var cell: UUID
    /// Where the opening was written.
    var offset: Int
    /// What was written there: the blank lines a cell needs round it and
    /// the line itself.
    var opening: String
}

extension NoteStore {
    /// A dock made a cell: remember it for its step.
    func recordDock(cell: UUID, offset: Int, opening: String) {
        docks.removeAll { $0.step == drawingSteps }
        docks.append(DockRecord(step: drawingSteps, cell: cell, offset: offset, opening: opening))
    }

    /// The step was taken back: the opening goes out of the note — what was
    /// written, if it is still where it was, and failing that the cell's
    /// line alone. Through the pane's own write, so it is an edit like any
    /// other and ⌘Z in the text can bring it back.
    func takeOutLine(of record: DockRecord) {
        let ns = text as NSString
        let opening = ns.range(of: record.opening)
        let line = DrawingCells.lines(in: text).first { $0.id == record.cell }?.range
        let range: NSRange
        if opening.location != NSNotFound, let line, NSLocationInRange(line.location, opening) {
            range = opening
        } else if let line {
            range = line
        } else {
            return
        }
        writeCell?(MarkdownFormatting.Edit(range: range, replacement: "",
                                           selection: NSRange(location: range.location, length: 0)))
    }

    /// The step was put back: the opening goes back where it was, unless
    /// the cell is there already.
    func putBackLine(of record: DockRecord) {
        guard !DrawingCells.lines(in: text).contains(where: { $0.id == record.cell }) else { return }
        let at = min(record.offset, (text as NSString).length)
        let length = (record.opening as NSString).length
        writeCell?(MarkdownFormatting.Edit(range: NSRange(location: at, length: 0), replacement: record.opening,
                                           selection: NSRange(location: at + length, length: 0)))
    }
}

extension NoteStore {
    /// EVERY PICTURE THE OPEN NOTE STILL NEEDS: on its layer, in its undo
    /// history and its redo future, and in its cells — what the media sweep
    /// is told to keep (`DrawingStore.pruneMedia(in:keeping:)`). A dock
    /// puts a picture in a cell and ⌘Z puts it back on the layer, and it
    /// has to have a file to come back to.
    var mediaInUse: Set<String> {
        var names = Set(drawing.images.map(\.file))
        for state in drawingHistory + drawingFuture {
            names.formUnion(state.layer.images.map(\.file))
            for cell in state.cells.values { names.formUnion(cell.drawing.images.map(\.file)) }
        }
        for cell in cells.values { names.formUnion(cell.drawing.images.map(\.file)) }
        return names
    }
}
