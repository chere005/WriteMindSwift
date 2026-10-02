import Foundation

/// The document surgery the preview's editor does: make a block, split one,
/// take an empty one away, carry a list on to the next line. Pure, so the
/// awkward cases — the first block, the last one, a note that is empty — are
/// tested rather than discovered.
enum PreviewEditing {
    /// A new, empty block at `offset`, with the blank lines it needs on both
    /// sides. Returns the note and where the block starts.
    static func insertBlock(in markdown: String, at offset: Int) -> (markdown: String, caret: Int) {
        insertBlock(in: markdown, replacing: NSRange(location: offset, length: 0))
    }

    /// The same, in the place of `range` — what comes out of the note to
    /// make way for the block: a selection that is becoming its content,
    /// the spaces at a cut (`Insertion`). The spacing either side is read
    /// off what is left either side, and the blank cell below off the note
    /// AS IT IS: cutting a paragraph out first and then asking left the
    /// blank lines either side of the hole looking like a cell of their
    /// own, and the block came out with a spare empty line under it.
    static func insertBlock(in markdown: String, replacing range: NSRange) -> (markdown: String, caret: Int) {
        let ns = markdown as NSString
        let range = MarkdownFormatting.clamp(range, to: ns.length)
        let clamped = range.location
        let before = ns.substring(to: clamped)
        let after = ns.substring(from: NSMaxRange(range))

        let lead = before.isEmpty ? "" : (before.hasSuffix("\n\n") ? "" : (before.hasSuffix("\n") ? "\n" : "\n\n"))
        // The blank lines a new block needs under it, EXCEPT where the
        // newlines already there are a cell of their own: a run of empty
        // lines is the note's content, not spacing (Sean, 2026-09-20: "one
        // with 8 empty lines"), so reading the first two of them as this
        // block's separator ate two of his — an eight-line cell came back
        // a six-line one.
        let trail: String
        if after.isEmpty {
            trail = ""
        } else if opensABlankCell(in: markdown, at: NSMaxRange(range)) {
            trail = "\n\n"
        } else {
            trail = after.hasPrefix("\n\n") ? "" : (after.hasPrefix("\n") ? "\n" : "\n\n")
        }
        let caret = (before as NSString).length + (lead as NSString).length
        return (before + lead + trail + after, caret)
    }

    /// Whether the cell that starts exactly here is a run of blank lines.
    private static func opensABlankCell(in markdown: String, at offset: Int) -> Bool {
        MarkdownParser.positioned(from: markdown).contains { block in
            guard block.range.location == offset else { return false }
            if case .blank = block.block { return true }
            return false
        }
    }

    /// Return in the middle of a block: what is behind the caret stays, what
    /// is in front of it becomes the next block.
    static func split(_ markdown: String, at range: NSRange,
                      head: String, tail: String) -> (markdown: String, editing: NSRange) {
        let ns = markdown as NSString
        guard NSMaxRange(range) <= ns.length else { return (markdown, range) }
        let replacement = head + "\n\n" + tail
        let updated = ns.replacingCharacters(in: range, with: replacement)
        let location = range.location + (head as NSString).length + 2
        return (updated, NSRange(location: location, length: (tail as NSString).length))
    }

    /// Backspace in a block with nothing in it: the block goes, and so do the
    /// blank lines that were holding it apart from its neighbours.
    static func removeBlock(_ markdown: String, at range: NSRange) -> (markdown: String, previous: NSRange?) {
        let ns = markdown as NSString
        guard NSMaxRange(range) <= ns.length else { return (markdown, nil) }

        var start = range.location
        while start > 0, ns.character(at: start - 1) == 10 { start -= 1 }
        var end = NSMaxRange(range)
        while end < ns.length, ns.character(at: end) == 10 { end += 1 }

        // Whatever is left on either side still has to be two separate blocks.
        let joiner = (start > 0 && end < ns.length) ? "\n\n" : ""
        let updated = ns.replacingCharacters(in: NSRange(location: start, length: end - start), with: joiner)

        let previous = MarkdownParser.positioned(from: updated)
            .last { NSMaxRange($0.range) <= start }
        return (updated, previous?.range)
    }

    /// What the next line of a list, or a quote, starts with. Nil when the
    /// line is not one of those; empty when the item is empty and Return
    /// should end the list instead of adding to it.
    static func listContinuation(for line: String) -> String? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indent.count)

        // A task list carries on as a task, unticked: the next thing is
        // something still to do (Sean, 2026-09-21).
        if let task = MarkdownParser.todoItem(String(rest)) {
            let marker = String(rest.prefix(2))
            return task.text.isEmpty ? "" : String(indent) + marker + "[ ] "
        }
        for marker in ["- ", "* ", "+ ", "> "] where rest.hasPrefix(marker) {
            let content = rest.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? "" : String(indent) + marker
        }

        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 4 {
            let afterDigits = rest.dropFirst(digits.count)
            for marker in [". ", ") "] where afterDigits.hasPrefix(marker) {
                let content = afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if content.isEmpty { return "" }
                let next = (Int(digits) ?? 1) + 1
                return String(indent) + "\(next)" + marker
            }
        }
        return nil
    }

    /// The line the caret is in, as a range — what the continuation is read
    /// from, and what an ended list item is deleted back to.
    static func lineRange(in text: String, at location: Int) -> NSRange {
        let ns = text as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        return ns.lineRange(for: NSRange(location: min(max(location, 0), ns.length), length: 0))
    }
}
