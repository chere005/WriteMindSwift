import Foundation

/// Splitting one notebook cell in two, and joining two into one (Sean,
/// 2026-09-19: "cmd+d and cmd+m to split and merge cells").
///
/// A cell here is a block of the markdown — a paragraph, a list, a quote, a
/// table, a fenced block — the same thing the brackets down the right-hand
/// side draw and the same thing a picture may not be dropped into the middle
/// of. So a split is a blank line put in at the caret, and a merge is the
/// blank line between two cells taken out: the notebook's structure lives in
/// the markdown, and these two commands edit exactly that.
enum NotebookCells {
    /// The cell holding the caret, cut in two there. The caret lands
    /// BETWEEN the two cells — on the blank line the break puts in, which
    /// is the seam the pane arms as the bar (Sean, 2026-09-20: "when
    /// dividing a cell, the cursor should go inbetween the new cells").
    ///
    /// Nothing happens at either end of a cell (there is no cut to make that
    /// would not leave an empty one), and nothing happens inside a fenced
    /// block: a blank line in the middle of one does not make two blocks, it
    /// makes one block with a hole in it. Nor in a drawing cell, whose one
    /// line is a file's name: cut, it would be two broken lines.
    static func split(text: String, selection: NSRange) -> MarkdownFormatting.Edit? {
        let string = text as NSString
        let caret = min(max(selection.location, 0), string.length)
        guard let cell = block(containing: caret, in: text) else { return nil }
        if case .code = cell.block { return nil }
        if case .drawing = cell.block { return nil }

        // The whitespace the caret sits in goes with the break: splitting
        // "one | two" must not leave a space hanging off either cell, and
        // a cut at a LINE boundary must not leave the newline that is
        // already there under the two the break writes (Sean, 2026-09-20:
        // "there shouldn't be a spuriously added newline").
        var start = caret, end = caret
        while start > cell.range.location, isBlank(string.character(at: start - 1)) { start -= 1 }
        let cellEnd = cell.range.location + cell.range.length
        while end < cellEnd, isBlank(string.character(at: end)) { end += 1 }

        let head = string.substring(with: NSRange(location: cell.range.location, length: start - cell.range.location))
        let tail = string.substring(with: NSRange(location: end, length: cellEnd - end))
        guard !head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        return MarkdownFormatting.Edit(range: NSRange(location: start, length: end - start),
                                       replacement: "\n\n",
                                       selection: NSRange(location: start + 1, length: 0))
    }

    /// The cell holding the caret and the one after it, joined — or, in the
    /// last cell, that one and the one before it. The caret lands on the
    /// seam, so the next ⌘D undoes it.
    ///
    /// A heading will not take another cell's words: it is one line by
    /// definition, and a "merge" that left the words in a separate block
    /// would only have deleted a blank line. Nor will a drawing cell, on
    /// either side: its line has to stand alone to be one.
    static func merge(text: String, selection: NSRange) -> MarkdownFormatting.Edit? {
        let string = text as NSString
        let caret = min(max(selection.location, 0), string.length)
        let cells = MarkdownParser.positioned(from: text)
        guard let index = cells.firstIndex(where: { NSLocationInRange(caret, $0.range) || caret == $0.range.location })
                ?? cells.indices.last
        else { return nil }
        let pair = index + 1 < cells.count ? (index, index + 1) : (index - 1, index)
        guard pair.0 >= 0, pair.1 < cells.count else { return nil }
        let first = cells[pair.0], second = cells[pair.1]
        if case .heading = first.block { return nil }
        if case .code = first.block { return nil }
        if case .code = second.block { return nil }
        if case .drawing = first.block { return nil }
        if case .drawing = second.block { return nil }

        let seam = first.range.location + first.range.length
        let gap = NSRange(location: seam, length: max(0, second.range.location - seam))
        guard gap.length > 0 else { return nil }
        return MarkdownFormatting.Edit(range: gap, replacement: "\n",
                                       selection: NSRange(location: seam + 1, length: 0))
    }

    /// Mathematica's ⌘. — the selection grown one step: the word the caret
    /// is in, then the whole cell, then the section that holds it, then
    /// the note (Sean, 2026-09-20: "make cells behave like mathematica
    /// cells"). Nil when there is nothing bigger to take.
    static func expand(_ selection: NSRange, in text: String) -> NSRange? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let caret = min(max(selection.location, 0), ns.length - 1)

        // The word first, unless a word is already what is held.
        let word = ns.rangeOfWord(at: caret)
        if selection.length == 0 || (word.length > 0 && !NSEqualRanges(selection, word)),
           word.length > selection.length {
            return word
        }
        // Then the cell.
        if let cell = block(containing: caret, in: text)?.range,
           cell.length > selection.length, !NSEqualRanges(selection, cell) {
            return cell
        }
        // Then the section it belongs to, heading and all.
        let sections = NotebookOutline.sections(in: text)
        if let section = NotebookOutline.section(containing: caret, in: sections) {
            let end = min(max(section.contentEnd, NSMaxRange(section.headingRange)), ns.length)
            let range = NSRange(location: section.range.location,
                                length: max(0, end - section.range.location))
            if range.length > selection.length { return range }
        }
        // And finally the whole note.
        let whole = NSRange(location: 0, length: ns.length)
        return whole.length > selection.length ? whole : nil
    }

    /// One blank line between two cells, never a stack of them.
    ///
    /// A note is a stack of cells: they come one after another, and the
    /// empty space between them is the editor's, not the file's (Sean,
    /// 2026-09-20: "this space shouldn't be possible. cells come
    /// immediately after each other"). A run of blank lines — left by a
    /// deleted cell, or by leaning on Return — is squeezed back to the one
    /// blank line that separates two cells.
    ///
    /// Two exceptions, both necessary: blank lines INSIDE a fence are
    /// code, and the line the caret is on is the empty cell being typed
    /// into, which cannot be taken away while it is being used.
    ///
    /// Nil when there is nothing to tidy, which is almost every keystroke.
    static func tidied(_ text: String, caret: Int) -> (text: String, caret: Int)? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        var lines: [(range: NSRange, blank: Bool, fenced: Bool)] = []
        var index = 0
        var inFence = false
        while index < ns.length {
            let line = ns.lineRange(for: NSRange(location: index, length: 0))
            let body = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasPrefix("```") { inFence.toggle() }
            lines.append((line, body.isEmpty && !inFence, inFence))
            index = max(NSMaxRange(line), index + 1)
        }

        var keep = [Bool](repeating: true, count: lines.count)
        var runStart: Int?
        func settle(_ end: Int) {
            guard let start = runStart else { return }
            for i in start..<end where i != start {
                // The caret's own blank line stays: it is the cell being
                // typed into.
                let line = lines[i].range
                let holdsCaret = caret >= line.location && caret <= NSMaxRange(line)
                keep[i] = holdsCaret
            }
            // A note does not begin with blank lines at all — not even
            // the one a run keeps between two cells, because there is no
            // cell above the first one.
            if start == 0 { keep[0] = false }
            runStart = nil
        }
        for (i, line) in lines.enumerated() {
            if line.blank {
                if runStart == nil { runStart = i }
            } else {
                settle(i)
            }
        }
        settle(lines.count)

        guard keep.contains(false) else { return nil }
        var out = ""
        var moved = caret
        for (i, line) in lines.enumerated() {
            let body = ns.substring(with: line.range)
            if keep[i] {
                out += body
            } else if line.range.location < caret {
                moved -= (body as NSString).length
            }
        }
        return (out, min(max(moved, 0), (out as NSString).length))
    }

    /// The block a character index falls in — the one it starts, when it
    /// sits exactly on a boundary.
    static func block(containing character: Int, in text: String) -> PositionedBlock? {
        let cells = MarkdownParser.positioned(from: text)
        return cells.first { NSLocationInRange(character, $0.range) }
            ?? cells.last { $0.range.location + $0.range.length == character }
    }

    /// What a break absorbs: a space, a tab, and the newline at a line
    /// boundary.
    ///
    /// The newline is the one that was missing. The break writes its own
    /// "\n\n", so a newline left standing beside them is a third — and
    /// "One\ntwo" cut at the boundary came out "One\n\n\ntwo": two cells
    /// with an empty line between them that nobody typed. It only looked
    /// right in the tests because every one of them cut a single-line
    /// paragraph, where the caret sits on a space.
    private static func isBlank(_ character: unichar) -> Bool {
        character == 32 || character == 9 || character == 10
    }
}
