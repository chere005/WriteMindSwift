import Foundation

/// The two line breaks that MAKE a fenced block, which a key may not take.
///
/// Sean, 2026-10-03: "cursor behavior around backticks is very weird".
/// ⌫ at the start of the first line of code (or ⌦ at the end of the fence
/// line) took the line break after "```python" — and the first line of the
/// program was then the fence's language, "```pythonx = 1", coloured as
/// nothing and never run. ⌫ at the start of the closing fence (or ⌦ at the end
/// of the last line of code) joined the closing ``` onto the code, which is no
/// fence at all, so the block ran on and took the rest of the note.
///
/// Only for a KEY: a selection that takes one is the user's own choice, and
/// undo puts one back. The rendered page's code editor holds the code alone,
/// with no fence line in it, where ⌫ at the start already does nothing.
enum FenceLines {
    /// The offsets of those line breaks, in a note: the one that ends an
    /// opening fence line and the one in front of a closing fence line. A
    /// fence that never closes has only the first. Read the way
    /// `MarkdownSourceStyle` reads a fence — a line that starts with three
    /// backticks, blanks aside, opens one and the next such line closes it.
    static func breaks(in text: String) -> [Int] {
        let ns = text as NSString
        var found: [Int] = []
        var open = false
        var start = 0
        while start < ns.length {
            let line = ns.lineRange(for: NSRange(location: start, length: 0))
            let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
            let length = (content as NSString).length
            if content.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if open {
                    // The closing fence: the break in front of it.
                    if line.location > 0 { found.append(line.location - 1) }
                } else if line.location + length < ns.length {
                    // The opening fence: the break at the end of it.
                    found.append(line.location + length)
                }
                open.toggle()
            }
            start = max(NSMaxRange(line), start + 1)
        }
        return found
    }

    /// Whether a delete of `range` would take one of them.
    static func takes(_ range: NSRange, in text: String) -> Bool {
        let breaks = breaks(in: text)
        guard !breaks.isEmpty else { return false }
        return breaks.contains { NSLocationInRange($0, range) }
    }
}
