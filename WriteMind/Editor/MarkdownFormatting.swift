import Foundation

/// Pure text transforms behind the toolbar buttons and the editor's Tab /
/// Shift-Tab / Backspace keys. They work in UTF-16 (`NSRange`) because that is
/// what the NSTextView hands back.
enum MarkdownFormatting {
    struct Edit: Equatable {
        /// The slice of the document to replace…
        let range: NSRange
        /// …with this…
        let replacement: String
        /// …leaving this selected afterwards.
        let selection: NSRange
    }

    static let bold = "**"
    static let italic = "_"
    static let underlineOpen = "<u>"
    static let underlineClose = "</u>"
    /// GFM strikethrough (Sean, 2026-09-19: "add strikethrough").
    static let strike = "~~"
    static let bullet = "- "
    static let quote = "> "
    /// One step of indentation, and the width a tab is shown at: four
    /// spaces (Sean, 2026-09-19: "indentation and tab width is 4 spaces").
    /// It was two, because four spaces on a line that belongs to no list
    /// is a markdown code block and that is what one indented paragraph
    /// now renders as. Four is what was asked for; see docs/TODO.md.
    static let indentUnit = "    "
    static let tabWidth = 4

    // MARK: - Code blocks

    /// A fenced code block round the selection, on lines of its own — or an
    /// empty one to type into, with the caret inside it (Sean, 2026-09-18).
    static func codeBlock(text: String, selection: NSRange, language: String = "") -> Edit {
        let ns = text as NSString
        let range = clamp(selection, to: ns.length)
        let before = range.location > 0 ? ns.substring(to: range.location) : ""
        let after = ns.substring(from: NSMaxRange(range))
        let lead = (before.isEmpty || before.hasSuffix("\n")) ? "" : "\n"
        let tail = (after.isEmpty || after.hasPrefix("\n")) ? "" : "\n"
        let inner = ns.substring(with: range)
        // An empty block keeps an empty line between its fences: the caret
        // goes on THAT line. With the caret on the closing fence's line
        // instead, typing produced "FSADF```" — a block that never closed
        // (Sean, 2026-09-19: "code block button is buggy").
        let body = inner.isEmpty ? "\n" : (inner.hasSuffix("\n") ? inner : inner + "\n")
        let replacement = lead + "```" + language + "\n" + body + "```" + tail
        let caret = inner.isEmpty
            ? range.location + (lead as NSString).length + 3 + (language as NSString).length + 1
            : range.location + (replacement as NSString).length
        return Edit(range: range, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    // MARK: - Wrapping

    /// Wrap the selection in `open`…`close`, or strip them if already there —
    /// whether the markers sit inside the selection or just outside it.
    static func toggleWrap(text: String, selection: NSRange, open: String, close: String? = nil) -> Edit {
        let ns = text as NSString
        let close = close ?? open
        let selection = clamp(selection, to: ns.length)
        let selected = ns.substring(with: selection)
        let openLen = (open as NSString).length
        let closeLen = (close as NSString).length

        // "**word**" selected → "word"
        if selected.hasPrefix(open), selected.hasSuffix(close),
           (selected as NSString).length >= openLen + closeLen {
            let inner = (selected as NSString).substring(
                with: NSRange(location: openLen, length: (selected as NSString).length - openLen - closeLen))
            return Edit(range: selection, replacement: inner,
                        selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }

        // **|word|** selected → "word"
        let before = NSRange(location: selection.location - openLen, length: openLen)
        let after = NSRange(location: NSMaxRange(selection), length: closeLen)
        if before.location >= 0, NSMaxRange(after) <= ns.length,
           ns.substring(with: before) == open, ns.substring(with: after) == close {
            let whole = NSRange(location: before.location, length: openLen + selection.length + closeLen)
            return Edit(range: whole, replacement: selected,
                        selection: NSRange(location: before.location, length: selection.length))
        }

        // Anything else gets wrapped; an empty selection leaves the caret between the markers.
        return Edit(range: selection, replacement: open + selected + close,
                    selection: NSRange(location: selection.location + openLen, length: selection.length))
    }

    /// The heading ladder, in Sean's words (2026-09-18). Level 0 is body
    /// text; level 6 is the author subheader, which the preview renders as
    /// italic, slightly bigger than body, rather than as a sixth-rank heading.
    enum Heading: Int, CaseIterable, Identifiable {
        case body = 0, title, header, section, subsection, subsubsection, authorSubheader

        var id: Int { rawValue }

        /// The ladder as the menu shows it and as the keys run: ⌘1 title,
        /// ⌘2 chapter, ⌘3 author, ⌘4–⌘6 section to subsubsection, ⌘7 body
        /// text (Sean, 2026-09-19). The markers underneath do not change —
        /// the author line is still the sixth-rank heading it always was,
        /// it just sits third on the ladder, under the title it belongs to.
        static let ladder: [Heading] = [.title, .header, .authorSubheader, .section, .subsection, .subsubsection, .body]

        /// The digit after ⌘ that sets this level.
        var key: Character {
            Character(String((Heading.ladder.firstIndex(of: self) ?? 6) + 1))
        }

        var name: String {
            switch self {
            case .body: return "Body Text"
            case .title: return "Title"
            case .header: return "Chapter"
            case .section: return "Section"
            case .subsection: return "Subsection"
            case .subsubsection: return "Subsubsection"
            case .authorSubheader: return "Author"
            }
        }

        /// What the line is written as — `#` per level, and nothing for body.
        var marker: String { rawValue == 0 ? "" : String(repeating: "#", count: rawValue) + " " }
    }

    /// Make every line the selection touches that heading level. Applying the
    /// level a line already has takes it back to body text, so the toolbar
    /// entry toggles.
    ///
    /// `evenIfEmpty` is for a cell that has only just been opened. A blank
    /// line normally keeps its shape — ⌘1 over three paragraphs must not
    /// write a marker on the empty lines holding them apart — but the cell
    /// a seam opens IS blank, and the kind the + chose for it still has to
    /// be written somewhere (Sean, 2026-09-20: "the next input will create
    /// a cell the type of"). Only `CellTypes.opening` asks for it.
    static func setHeading(text: String, selection: NSRange, level: Heading,
                           evenIfEmpty: Bool = false) -> Edit {
        let ns = text as NSString
        let block = ns.lineRange(for: clamp(selection, to: ns.length))
        let first = ns.substring(with: block).components(separatedBy: "\n").first ?? ""
        let target: Heading = (headingLevel(of: first) == level && level != .body) ? .body : level

        return rewriteLines(text: text, selection: selection) { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                return evenIfEmpty ? line + target.marker : line
            }
            let indent = leadingWhitespace(line)
            let rest = String(line.dropFirst(indent.count))
            return indent + target.marker + stripHeading(rest)
        }
    }

    /// The level a line is written at — `.body` when it opens with no hashes,
    /// with more than six, or with hashes that are not followed by a space.
    static func headingLevel(of line: String) -> Heading {
        let rest = line.drop { $0 == " " || $0 == "\t" }
        let hashes = rest.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return .body }
        let after = rest.dropFirst(hashes.count)
        guard after.isEmpty || after.hasPrefix(" ") else { return .body }
        return Heading(rawValue: hashes.count) ?? .body
    }

    private static func stripHeading(_ rest: String) -> String {
        let hashes = rest.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return rest }
        var body = rest.dropFirst(hashes.count)
        guard body.isEmpty || body.hasPrefix(" ") else { return rest }
        while body.hasPrefix(" ") { body = body.dropFirst() }
        return String(body)
    }

    // MARK: - Line prefixes

    /// Add `- ` to every line the selection touches, or remove it when they all have one.
    static func toggleBullets(text: String, selection: NSRange) -> Edit {
        toggleLinePrefix(text: text, selection: selection, prefix: bullet,
                         isPrefixed: isBulleted, strip: stripBullet)
    }

    /// What a list is marked with (Sean, 2026-09-19: "picks dots or dashes
    /// or numbered.. default to dots"): `- ` shows as a round bullet, `* `
    /// as a dash, and a numbered list counts from 1. All three are ordinary
    /// markdown lists to anything else that opens the note.
    enum ListStyle: String, CaseIterable, Identifiable {
        /// `todo` is GFM's task list — `- [ ] ` and `- [x] ` — a dots list
        /// with a box in front of the words (Sean, 2026-09-21: "add a
        /// bullet type which are todo bullets that can be checked or
        /// unchecked"). It is a list style and not a cell of its own,
        /// because that is what it is in the file.
        case dots, dashes, numbered, todo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dots: return "Dots"
            case .dashes: return "Dashes"
            case .numbered: return "Numbered"
            case .todo: return "To-do"
            }
        }

        var systemImage: String {
            switch self {
            case .dots: return "list.bullet"
            case .dashes: return "list.dash"
            case .numbered: return "list.number"
            case .todo: return "checklist"
            }
        }

        /// The marker for the `index`th item (from 1).
        func marker(_ index: Int) -> String {
            switch self {
            case .dots: return "- "
            case .dashes: return "* "
            case .numbered: return "\(index). "
            // Unticked: a new item is something still to do.
            case .todo: return "- [ ] "
            }
        }

        /// Whether `rest` (a line past its indentation) carries this marker.
        func matches(_ rest: String) -> Bool {
            switch self {
            // A task is NOT a dots list that happens to start with a
            // dash: asking dots of a task list read it as already styled
            // and took the markers off instead of swapping them, so
            // "- [x] milk" became "milk".
            case .dots:
                return (rest.hasPrefix("- ") || rest.hasPrefix("+ ")) && MarkdownParser.todoItem(rest) == nil
            case .dashes: return rest.hasPrefix("* ") && MarkdownParser.todoItem(rest) == nil
            case .numbered: return MarkdownParser.numberedItem(rest) != nil
            case .todo: return MarkdownParser.todoItem(rest) != nil
            }
        }
    }

    /// Make every line the selection touches an item in `style`, whatever
    /// list it was in before; when they all already are, take the markers
    /// away — so the button toggles, like the others.
    static func toggleList(text: String, selection: NSRange, style: ListStyle) -> Edit {
        let ns = text as NSString
        var block = ns.lineRange(for: clamp(selection, to: ns.length))
        var body = ns.substring(with: block)
        if body.hasSuffix("\n") { body.removeLast(); block.length -= 1 }
        let nonEmpty = body.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allStyled = !nonEmpty.isEmpty && nonEmpty.allSatisfy { style.matches(String($0.drop { $0 == " " || $0 == "\t" })) }

        var number = 0
        return rewriteLines(text: text, selection: selection) { line in
            let indent = leadingWhitespace(line)
            let rest = String(line.dropFirst(indent.count))
            if allStyled { return indent + stripListMarker(rest) }
            if rest.isEmpty && !nonEmpty.isEmpty { return line }
            number += 1
            return indent + style.marker(number) + stripListMarker(rest)
        }
    }

    /// The `index`th task line inside `block` ticked, or unticked if it
    /// already was (Sean, 2026-09-21: "todo bullets that can be checked or
    /// unchecked"). Nil when that line is not a task after all — the note
    /// may have been edited since the box was drawn.
    ///
    /// Only the box is rewritten: the words, the indentation and whichever
    /// of `-`, `*` and `+` the line was written with are left exactly as
    /// they are, because this is a tick and not a reformat.
    static func toggleTodo(text: String, block: NSRange, item index: Int) -> Edit? {
        let ns = text as NSString
        guard block.location >= 0, NSMaxRange(block) <= ns.length else { return nil }
        var line = block.location
        var seen = 0
        while line < NSMaxRange(block) {
            let range = ns.lineRange(for: NSRange(location: line, length: 0))
            let body = ns.substring(with: range)
            let bare = body.hasSuffix("\n") ? String(body.dropLast()) : body
            let indent = leadingWhitespace(bare)
            if MarkdownParser.todoItem(String(bare.dropFirst(indent.count))) != nil {
                if seen == index {
                    // The box is the character after "- [", whatever the
                    // marker and the indentation were.
                    let box = range.location + indent.count + 3
                    guard box < ns.length else { return nil }
                    let now = ns.substring(with: NSRange(location: box, length: 1))
                    let next = now.lowercased() == "x" ? " " : "x"
                    return Edit(range: NSRange(location: box, length: 1), replacement: next,
                                selection: NSRange(location: box + 1, length: 0))
                }
                seen += 1
            }
            line = NSMaxRange(range)
            if range.length == 0 { break }
        }
        return nil
    }

    /// `rest` without whichever list marker heads it.
    static func stripListMarker(_ rest: String) -> String {
        // The box first: a to-do is `- ` and then `[ ] `, and taking only
        // the dash would leave the box standing in the words.
        if let item = MarkdownParser.todoItem(rest) { return item.text }
        for marker in ["- ", "* ", "+ "] where rest.hasPrefix(marker) { return String(rest.dropFirst(2)) }
        if let item = MarkdownParser.numberedItem(rest) { return item }
        return rest
    }

    /// A fenced block taken apart, so the preview can let the CODE be
    /// typed while the fences stay where they are (Sean, 2026-09-19: "i
    /// want to be able to type code in the code block"). Nil when this is
    /// not a fenced block.
    static func fenced(_ source: String) -> (open: String, body: String, close: String)? {
        var lines = source.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("```")
        else { return nil }
        let open = lines.removeFirst()
        var close = ""
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces) == "```" {
            close = lines.removeLast()
        }
        return (open, lines.joined(separator: "\n"), close)
    }

    /// And put back together again.
    static func refenced(open: String, body: String, close: String) -> String {
        var out = open + "\n" + body
        if !close.isEmpty { out += "\n" + close }
        return out
    }

    /// The language a fence names, for colouring what is typed into it.
    static func fenceLanguage(_ open: String) -> String {
        String(open.trimmingCharacters(in: .whitespaces).dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    /// The same, for `> `.
    static func toggleQuote(text: String, selection: NSRange) -> Edit {
        toggleLinePrefix(text: text, selection: selection, prefix: quote,
                         isPrefixed: isQuoted, strip: stripQuote)
    }

    /// One level in: a quoted line gains another `> `, anything else gains two spaces.
    /// Works on a bullet, a quote, or a plain paragraph.
    static func indent(text: String, selection: NSRange) -> Edit {
        rewriteLines(text: text, selection: blockOrSelection(text: text, selection: selection)) { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let indent = leadingWhitespace(line)
            let rest = String(line.dropFirst(indent.count))
            return rest.hasPrefix(">") ? indent + quote + rest : indentUnit + line
        }
    }

    /// One level out: a step of indentation if there is one, otherwise one
    /// `> ` marker — so Shift-Tab on a top-level quote unquotes the line.
    static func outdent(text: String, selection: NSRange) -> Edit {
        rewriteLines(text: text, selection: blockOrSelection(text: text, selection: selection)) { line in
            let indent = leadingWhitespace(line)
            if indent.hasPrefix(indentUnit) { return String(line.dropFirst(indentUnit.count)) }
            if indent.hasPrefix("\t") { return String(line.dropFirst()) }
            let rest = String(line.dropFirst(indent.count))
            guard rest.hasPrefix(">") else { return line }
            return indent + stripQuote(rest)
        }
    }

    /// Backspace inside a line's prefix takes a level off instead of deleting a
    /// character; anywhere else it is an ordinary backspace, and this is nil.
    static func outdentForBackspace(text: String, selection: NSRange) -> Edit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let selection = clamp(selection, to: ns.length)
        let line = ns.lineRange(for: selection)
        let column = selection.location - line.location
        // At column 0 there is no prefix to be inside. Whether the key then
        // joins the line above is the caller's: inside a cell it does, at
        // the start of one it does nothing (`NotebookCells.atTheStartOfACell`).
        guard column > 0 else { return nil }
        let body = ns.substring(with: line)
        guard column <= prefixLength(of: body), prefixLength(of: body) > 0 else { return nil }
        let edit = outdent(text: text, selection: selection)
        return edit.replacement == body ? nil : edit
    }

    /// Indenting with a caret moves the WHOLE BLOCK it sits in, not just the
    /// line under the cursor (Sean, 2026-09-18) — a paragraph typed across
    /// several lines is one piece of text and moves as one.
    ///
    /// A list item, a quote line and a heading each stand alone: Tab on the
    /// second bullet of a list has to nest THAT bullet, not the list.
    /// A real selection is always taken as given.
    static func blockOrSelection(text: String, selection: NSRange) -> NSRange {
        guard selection.length == 0 else { return selection }
        let ns = text as NSString
        let caret = clamp(selection, to: ns.length)
        let line = ns.lineRange(for: caret)
        guard groupsWithNeighbours(lineAt: line, in: ns) else { return caret }

        var start = line.location
        while start > 0 {
            let previous = ns.lineRange(for: NSRange(location: start - 1, length: 0))
            guard groupsWithNeighbours(lineAt: previous, in: ns) else { break }
            start = previous.location
        }
        var end = NSMaxRange(line)
        while end < ns.length {
            let next = ns.lineRange(for: NSRange(location: end, length: 0))
            guard groupsWithNeighbours(lineAt: next, in: ns) else { break }
            end = NSMaxRange(next)
        }
        // The whole span of lines. rewriteLines takes its own line range from
        // this and strips one trailing newline, so shortening it here dropped
        // the last line of every paragraph that ended the document.
        return NSRange(location: start, length: max(0, end - start))
    }

    /// A plain paragraph line — the only kind that moves with its neighbours.
    private static func groupsWithNeighbours(lineAt range: NSRange, in ns: NSString) -> Bool {
        var line = ns.substring(with: range)
        if line.hasSuffix("\n") { line.removeLast() }
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !isBulleted(line), !isQuoted(line) else { return false }
        guard headingLevel(of: line) == .body else { return false }
        guard numberedItem(for: line) == nil else { return false }
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("```") else { return false }
        return true
    }

    private static func numberedItem(for line: String) -> String? {
        MarkdownParser.numberedItem(line.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Classifiers

    static func isBulleted(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
    }

    static func isQuoted(_ line: String) -> Bool {
        line.drop { $0 == " " || $0 == "\t" }.hasPrefix(">")
    }

    /// The whitespace, quote markers and list marker a line opens with — what
    /// Tab and Backspace treat as structure rather than text.
    static func prefixLength(of line: String) -> Int {
        var rest = Substring(line)
        var length = 0
        let indent = rest.prefix { $0 == " " || $0 == "\t" }
        length += indent.count
        rest = rest.dropFirst(indent.count)
        while rest.hasPrefix(">") {
            rest = rest.dropFirst()
            length += 1
            if rest.hasPrefix(" ") { rest = rest.dropFirst(); length += 1 }
            let more = rest.prefix { $0 == " " || $0 == "\t" }
            rest = rest.dropFirst(more.count)
            length += more.count
        }
        if isBulleted(String(rest)) { length += 2 }
        return length
    }

    // MARK: - Machinery

    private static func toggleLinePrefix(text: String, selection: NSRange, prefix: String,
                                         isPrefixed: (String) -> Bool,
                                         strip: @escaping (String) -> String) -> Edit {
        let ns = text as NSString
        var block = ns.lineRange(for: clamp(selection, to: ns.length))
        var body = ns.substring(with: block)
        if body.hasSuffix("\n") { body.removeLast(); block.length -= 1 }

        let nonEmpty = body.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allPrefixed = !nonEmpty.isEmpty && nonEmpty.allSatisfy { isPrefixed($0) }

        return rewriteLines(text: text, selection: selection) { line in
            let indent = leadingWhitespace(line)
            let rest = String(line.dropFirst(indent.count))
            if allPrefixed {
                guard isPrefixed(line) else { return line }
                return indent + strip(rest)
            }
            // An empty line in the middle of a block keeps its shape.
            if rest.isEmpty && !nonEmpty.isEmpty { return line }
            if isPrefixed(line) { return line }
            return indent + prefix + rest
        }
    }

    /// Rewrite every line the selection touches. A selection keeps the whole
    /// block selected; a caret moves by however much its own line shifted.
    private static func rewriteLines(text: String, selection: NSRange,
                                     transform: (String) -> String) -> Edit {
        let ns = text as NSString
        let selection = clamp(selection, to: ns.length)
        var block = ns.lineRange(for: selection)
        var body = ns.substring(with: block)
        var trailingNewline = ""
        if body.hasSuffix("\n") {
            trailingNewline = "\n"
            body.removeLast()
            block.length -= 1
        }

        let lines = body.components(separatedBy: "\n")
        var caretDelta = 0
        var offset = 0
        var rewritten: [String] = []
        rewritten.reserveCapacity(lines.count)
        for line in lines {
            let lineLength = (line as NSString).length
            let caretOnThisLine = selection.length == 0
                && selection.location - block.location >= offset
                && selection.location - block.location <= offset + lineLength
            let new = transform(line)
            if caretOnThisLine { caretDelta = (new as NSString).length - lineLength }
            rewritten.append(new)
            offset += lineLength + 1
        }

        let replacement = rewritten.joined(separator: "\n") + trailingNewline
        let newSelection: NSRange
        if selection.length == 0 {
            newSelection = NSRange(location: max(block.location, selection.location + caretDelta), length: 0)
        } else {
            newSelection = NSRange(location: block.location,
                                   length: (replacement as NSString).length - (trailingNewline as NSString).length)
        }
        return Edit(range: NSRange(location: block.location, length: block.length + (trailingNewline as NSString).length),
                    replacement: replacement, selection: newSelection)
    }

    private static func leadingWhitespace(_ line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private static func stripBullet(_ rest: String) -> String { String(rest.dropFirst(2)) }

    private static func stripQuote(_ rest: String) -> String {
        var out = Substring(rest)
        guard out.hasPrefix(">") else { return rest }
        out = out.dropFirst()
        if out.hasPrefix(" ") { out = out.dropFirst() }
        return String(out)
    }

    static func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let len = min(max(0, range.length), length - location)
        return NSRange(location: location, length: len)
    }
}
