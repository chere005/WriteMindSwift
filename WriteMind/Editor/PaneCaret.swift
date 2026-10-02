import Foundation

/// WHERE THE TYPING WAS, carried across ⌘T.
///
/// Sean, 2026-10-03: "preserve the position of things as much as possible
/// between markdown and wysiwyg mode". The two panes are two views that
/// are torn down and built again on every switch, and neither carried a
/// cursor: the markdown pane came up with its caret at the END of the note
/// and nothing holding the keyboard — so ⌘1 straight after the switch
/// titled the last cell, and a pasted picture landed under the last line —
/// and the rendered page came up with nothing open, so the first command
/// opened and restyled the note's FIRST cell. An armed bar, its + choice
/// and the cells held by their brackets went with them.
///
/// Three things a cursor can be on either side, in the NOTE's offsets so
/// either pane can read them: a caret or a selection in one cell's words,
/// cells held by their brackets, or the bar between two cells and what
/// its + chose. Pure: each pane reads its own state into one of these on
/// the way out and opens it on the way in.
enum PaneCaret: Equatable {
    /// A caret, or a selection, in the note.
    case text(NSRange)
    /// Cells held by their brackets, by their ranges.
    case cells([NSRange])
    /// The bar between two cells: the offset a cell would open at there,
    /// and the kind the + on it chose.
    case bar(offset: Int, kind: CellTypes.Kind)

    /// The markdown pane's cursor: its armed bar if there is one, else
    /// what its selection holds — whole cells, picked up by their
    /// brackets (one or several), or a caret or a selection in the words.
    static func source(selection: [NSRange], armed: Int?, kind: CellTypes.Kind, in text: String) -> PaneCaret? {
        if let armed { return .bar(offset: armed, kind: kind) }
        let ranges = selection.filter { $0.location != NSNotFound }
        guard let first = ranges.first else { return nil }
        let cells = MarkdownParser.positioned(from: text).map(\.range)
        let whole = ranges.allSatisfy { range in cells.contains { NSEqualRanges($0, range) } }
        if whole, ranges.count > 1 || first.length > 0 { return .cells(ranges) }
        return .text(first)
    }

    /// The rendered page's caret, in the note: `open` is the range its
    /// open editor stands for — a cell, or one reminder's words — and
    /// `inside` the selection in that editor's own text. A code cell's
    /// editor holds the code alone, so its fence line (`fence`) and the
    /// newline after it come first in the note.
    static func rendered(open: NSRange, inside: NSRange, fence: String?) -> PaneCaret {
        let skipped = fence.map { ($0 as NSString).length + 1 } ?? 0
        return .text(NSRange(location: open.location + skipped + inside.location, length: inside.length))
    }

    /// What the rendered page opens for a cursor.
    enum Opening: Equatable {
        /// A cell open for typing, with the selection in its editor's own
        /// text — after the fence, for a code cell.
        case cell(NSRange, selection: NSRange)
        /// One reminder's words, with the selection in them — a checklist
        /// is typed in a reminder at a time.
        case item(NSRange, selection: NSRange)
        case cells([NSRange])
        case bar(offset: Int, kind: CellTypes.Kind)
    }

    /// The cell a caret is in, opened round it. Nil for a caret in no cell
    /// at all — on the blank line between two, which the markdown pane
    /// would have armed as a bar if it were one.
    func opening(in text: String) -> Opening? {
        switch self {
        case .cells(let ranges): return .cells(ranges)
        case .bar(let offset, let kind): return .bar(offset: offset, kind: kind)
        case .text(let range):
            let ns = text as NSString
            guard let block = MarkdownParser.positioned(from: text)
                .first(where: { NSLocationInRange(range.location, $0.range) || NSMaxRange($0.range) == range.location })
            else { return nil }
            let cell = block.range
            // As much of the selection as is in the cell: a selection
            // running on into the next cell has no one editor to be in.
            let end = min(NSMaxRange(range), NSMaxRange(cell))
            if case .todos = block.block {
                let reminders = ListEditing.reminders(in: cell, of: ns)
                guard let reminder = reminders.last(where: { $0.line.location <= range.location })
                        ?? reminders.first
                else { return nil }
                let words = reminder.text
                let start = min(max(range.location, words.location), NSMaxRange(words))
                let stop = min(max(end, start), NSMaxRange(words))
                return .item(words, selection: NSRange(location: start - words.location, length: stop - start))
            }
            var bodyStart = cell.location
            var bodyEnd = NSMaxRange(cell)
            if let parts = MarkdownFormatting.fenced(ns.substring(with: cell)) {
                bodyStart += (parts.open as NSString).length + 1
                bodyEnd = min(bodyEnd, bodyStart + (parts.body as NSString).length)
            }
            let start = min(max(range.location, bodyStart), max(bodyEnd, bodyStart))
            let stop = min(max(end, start), max(bodyEnd, bodyStart))
            return .cell(cell, selection: NSRange(location: start - bodyStart, length: stop - start))
        }
    }
}
