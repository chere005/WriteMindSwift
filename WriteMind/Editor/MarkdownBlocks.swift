import AppKit
import SwiftUI
import Foundation

/// The block structure of a markdown document — enough for notes, not a spec.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    /// A list written with `* `, shown with a dash (Sean, 2026-09-19: "picks
    /// dots or dashes or numbered"). Ordinary markdown either way.
    case dashes([String])
    /// A GFM task list: the words, and whether the box is ticked.
    case todos([TodoItem])
    case numbered([String])
    case quote(String)
    case code(language: String?, body: String)
    case rule
    /// Empty lines a note holds on purpose. A run of blank lines between
    /// two cells is one line to end the cell above, one to announce the
    /// cell below, and whatever is left over in the middle is a cell of
    /// its own (Sean, 2026-09-20: "the line after baz would be a part of
    /// baz, the next line starts new data… so there's 3 cells there.. one
    /// with 8 empty lines"). The spacing BETWEEN cells is the editor's;
    /// these are the note's.
    case blank(lines: Int)
    /// A drawing cell: `![](_drawings/cells/<ID>.png)` on a line of its own
    /// (`DrawingCells`). The id is the cell; the alt text is whatever the
    /// line says.
    case drawing(id: UUID, alt: String)

    var isDrawing: Bool {
        if case .drawing = self { return true }
        return false
    }
}

/// A block and the slice of source it was parsed from — the range is what
/// makes editing the rendered preview possible: a block is written back over
/// its own source and nothing else is touched.
/// One line of a task list: what it says, and whether it is done.
struct TodoItem: Equatable {
    var text: String
    var done: Bool
}

struct PositionedBlock: Equatable, Identifiable {
    let block: MarkdownBlock
    let range: NSRange
    var id: Int { range.location }
}

enum MarkdownParser {
    static func blocks(from markdown: String) -> [MarkdownBlock] {
        positioned(from: markdown).map(\.block)
    }

    static func positioned(from markdown: String) -> [PositionedBlock] {
        var blocks: [PositionedBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var todos: [TodoItem] = []
        var dashes: [String] = []
        var numbered: [String] = []
        var quote: [String] = []
        var code: [String]?
        var codeLanguage: String?

        // Where the open block started, and where the last line of it ended.
        var blockStart = 0
        var blockEnd = 0
        var lineStart = 0
        /// A run of blank lines being counted: which line it started on
        /// and where in the text that line began.
        var blankRunStart: Int?
        var blankRunFirst = 0
        var lineLengths: [Int] = []

        func emit(_ block: MarkdownBlock) {
            blocks.append(PositionedBlock(block: block, range: NSRange(location: blockStart, length: blockEnd - blockStart)))
        }

        func flush() {
            if !paragraph.isEmpty { emit(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !bullets.isEmpty { emit(.bullets(bullets)); bullets = [] }
            if !todos.isEmpty { emit(.todos(todos)); todos = [] }
            if !dashes.isEmpty { emit(.dashes(dashes)); dashes = [] }
            if !numbered.isEmpty { emit(.numbered(numbered)); numbered = [] }
            if !quote.isEmpty { emit(.quote(quote.joined(separator: " "))); quote = [] }
        }

        /// The first line of a block sets its start; every line extends its end.
        func openIfNeeded() {
            if paragraph.isEmpty && bullets.isEmpty && todos.isEmpty && dashes.isEmpty
                && numbered.isEmpty && quote.isEmpty && code == nil {
                blockStart = lineStart
            }
        }

        let allLines = markdown.components(separatedBy: .newlines)
        lineLengths = allLines.map { ($0 as NSString).length + 1 }

        /// The middle of a run of blank lines, as a cell. The first line
        /// of the run and the last one are the separators either side of
        /// it, so a run of one or two leaves nothing behind.
        func emitBlankRun(upTo lineIndex: Int, from start: Int) {
            let count = lineIndex - start
            guard count >= 3 else { return }
            // emit reads blockStart and blockEnd, so this cell has to put
            // them back: the line that ENDED the run has already moved
            // blockEnd on to itself (it is read at the top of the loop),
            // and a cell that kept the blank run's end left the next one
            // with a range of negative length.
            let openStart = blockStart
            let openEnd = blockEnd
            defer { blockStart = openStart; blockEnd = openEnd }
            let from = blankRunFirst + lineLengths[start]
            var to = from
            for index in (start + 1)..<(lineIndex - 1) { to += lineLengths[index] }
            blockStart = from
            blockEnd = max(from, to - 1)
            emit(.blank(lines: count - 2))
        }

        for (lineIndex, rawLine) in allLines.enumerated() {
            defer { lineStart += (rawLine as NSString).length + 1 }
            let lineEnd = lineStart + (rawLine as NSString).length
            // Where the open block ended before this line is read.
            let openEnd = blockEnd
            // A blank line ends a block without being part of it, so only the
            // lines that go INTO a block move its end (a paragraph's range
            // stops at its last character, not at the newline after it).
            if !rawLine.trimmingCharacters(in: .whitespaces).isEmpty || code != nil {
                blockEnd = lineEnd
            }
            // A run of blank lines: the first ends the cell above it and
            // the last announces the one below; whatever is between them
            // is a cell of empty lines (Sean, 2026-09-20). Counted HERE,
            // at the top, because every branch below this one continues.
            if code == nil {
                if rawLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    if blankRunStart == nil { blankRunStart = lineIndex; blankRunFirst = lineStart }
                } else if let start = blankRunStart {
                    emitBlankRun(upTo: lineIndex, from: start)
                    blankRunStart = nil
                }
            }

            if var open = code {
                if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    emit(.code(language: codeLanguage, body: open.joined(separator: "\n")))
                    code = nil
                    codeLanguage = nil
                } else {
                    open.append(rawLine)
                    code = open
                }
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // A line of pipes is an ordinary paragraph. Tables came out of
            // the app whole on 2026-09-20 (Sean: "just completely remove
            // tables as a feature and we'll rebuild that from scratch"),
            // and with them the one place this parser looked ahead — at the
            // `---|---` rule that turned the line above it into a header.

            if line.hasPrefix("```") {
                flush()
                blockStart = lineStart
                let lang = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                codeLanguage = lang.isEmpty ? nil : lang
                code = []
                continue
            }
            if line.isEmpty { flush(); continue }
            if isRule(line) { flush(); blockStart = lineStart; emit(.rule); continue }
            if let (level, text) = heading(line) {
                flush(); blockStart = lineStart; emit(.heading(level: level, text: text)); continue
            }
            // A drawing ends whatever it follows, the way a heading does —
            // and that block keeps the range it had: `blockEnd` has already
            // moved on to this line, and a paragraph whose range ran over
            // the image line would write over it when edited.
            if let cell = DrawingCells.parse(line) {
                blockEnd = openEnd
                flush()
                blockStart = lineStart
                blockEnd = lineEnd
                emit(.drawing(id: cell.id, alt: cell.alt))
                continue
            }
            if line.hasPrefix(">") {
                if !paragraph.isEmpty || !bullets.isEmpty || !todos.isEmpty
                    || !dashes.isEmpty || !numbered.isEmpty { flush() }
                openIfNeeded()
                quote.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            }
            // Before the plain bullet, because `- [ ] milk` starts with
            // `- ` and would otherwise be a bullet whose words are a box.
            if let item = todoItem(line) {
                if !paragraph.isEmpty || !bullets.isEmpty || !dashes.isEmpty
                    || !numbered.isEmpty || !quote.isEmpty { flush() }
                openIfNeeded()
                todos.append(item)
                continue
            }
            if let item = bulletItem(line) {
                if !paragraph.isEmpty || !todos.isEmpty || !dashes.isEmpty
                    || !numbered.isEmpty || !quote.isEmpty { flush() }
                openIfNeeded()
                bullets.append(item)
                continue
            }
            if let item = dashItem(line) {
                if !paragraph.isEmpty || !bullets.isEmpty || !todos.isEmpty
                    || !numbered.isEmpty || !quote.isEmpty { flush() }
                openIfNeeded()
                dashes.append(item)
                continue
            }
            if let item = numberedItem(line) {
                if !paragraph.isEmpty || !bullets.isEmpty || !todos.isEmpty
                    || !dashes.isEmpty || !quote.isEmpty { flush() }
                openIfNeeded()
                numbered.append(item)
                continue
            }
            if !bullets.isEmpty || !todos.isEmpty || !dashes.isEmpty
                || !numbered.isEmpty || !quote.isEmpty { flush() }
            openIfNeeded()
            // The first line keeps the spaces it was written with, so an
            // indented paragraph is drawn indented. Four spaces is NOT a
            // code block in WriteMind — code is what is inside ```, ` or
            // `` and nothing else (Sean, 2026-09-20).
            paragraph.append(paragraph.isEmpty ? String(rawLine.prefix { $0 == " " }) + line : line)
        }

        if let open = code {
            // An unclosed fence still renders as code — better than swallowing the rest of the note.
            emit(.code(language: codeLanguage, body: open.joined(separator: "\n")))
        }
        flush()
        if let start = blankRunStart { emitBlankRun(upTo: allLines.count, from: start) }
        return blocks
    }

    // MARK: - Line classifiers

    static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " || rest.isEmpty else { return nil }
        return (hashes.count, rest.trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" } || compact.allSatisfy { $0 == "_" }
    }

    /// A dot bullet: `- ` or `+ `.
    /// A task-list line: `- [ ] words` or `- [x] words`, the box either
    /// way round in case and either a dash or a star in front of it, which
    /// is what other markdown editors write.
    static func todoItem(_ line: String) -> TodoItem? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let rest = line.dropFirst(marker.count)
            guard rest.hasPrefix("["), rest.count >= 3 else { return nil }
            let box = rest.dropFirst().prefix(1)
            guard rest.dropFirst(2).hasPrefix("]") else { return nil }
            let after = rest.dropFirst(3)
            // `- []x` is not a task; the box is followed by a space or
            // it is the whole of the line.
            guard after.isEmpty || after.hasPrefix(" ") else { return nil }
            switch box.lowercased() {
            case " ": return TodoItem(text: String(after.dropFirst(0)).trimmedLeadingSpace, done: false)
            case "x": return TodoItem(text: String(after).trimmedLeadingSpace, done: true)
            default: return nil
            }
        }
        return nil
    }

    static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(2))
        }
        return nil
    }

    /// A dash bullet: `* `.
    static func dashItem(_ line: String) -> String? {
        line.hasPrefix("* ") ? String(line.dropFirst(2)) : nil
    }

    static func numberedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 4 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}

/// Inline markdown (`**bold**`, `_italic_`, `` `code` ``, links) plus the two
/// HTML tags the toolbar writes: `<u>` from the underline button and
/// `<span style="…">` from the text-style menu.
enum MarkdownInline {
    /// `paper` is what this is being drawn ON, as `#RRGGBB`, when that is
    /// something other than the window the colours were chosen in — the PDF
    /// export passes white. A span's colour is then checked against it and
    /// swapped for black or white if it would not be readable, because a
    /// note that is legible on screen has to be legible on paper too (Sean,
    /// 2026-09-19: "be mindful of text color"). Nil leaves every colour
    /// exactly as it was written.
    ///
    /// REMEMBERED by what it was made from (Sean, 2026-10-03: "resizing the
    /// screen by dragging the middle vertical line is groggy"): the rendered
    /// page builds every row again at every width the divider goes through,
    /// and tokenising and styling every paragraph of a long note each time
    /// was a fifth of what a drag cost. The same words at the same size on the
    /// same paper are the same string.
    static func attributed(_ source: String, baseSize: CGFloat = 15,
                           paper: String? = nil) -> AttributedString {
        let key = "\(baseSize)|\(paper ?? "")|\(source)" as NSString
        if let kept = attributedCache.object(forKey: key) { return kept.value }
        let made = buildAttributed(source, baseSize: baseSize, paper: paper)
        attributedCache.setObject(AttributedBox(made), forKey: key)
        return made
    }

    private final class AttributedBox {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    private static let attributedCache: NSCache<NSString, AttributedBox> = {
        let cache = NSCache<NSString, AttributedBox>()
        cache.countLimit = 6000
        return cache
    }()

    private static func buildAttributed(_ source: String, baseSize: CGFloat, paper: String?) -> AttributedString {
        var result = AttributedString()
        var stack: [Style] = []

        for token in tokenize(source) {
            switch token {
            case .open(let style): stack.append(style)
            case .close: if !stack.isEmpty { stack.removeLast() }
            case .text(let text):
                result.append(styled(text, with: Style.merged(stack), baseSize: baseSize, paper: paper))
            }
        }
        return result
    }

    struct Style: Equatable {
        var underline = false
        var family: String?
        var size: Double?
        var colorHex: String?

        static func merged(_ stack: [Style]) -> Style {
            stack.reduce(into: Style()) { out, next in
                out.underline = out.underline || next.underline
                if let family = next.family { out.family = family }
                if let size = next.size { out.size = size }
                if let hex = next.colorHex { out.colorHex = hex }
            }
        }
    }

    enum Token: Equatable { case open(Style), close, text(String) }

    /// Render one run of markdown and lay the enclosing style over it. The
    /// bold/italic the markdown itself carries survives: it comes back as an
    /// `inlinePresentationIntent`, which is read here and folded into the
    /// span's own font rather than being overwritten by it.
    static func styled(_ text: String, with style: Style, baseSize: CGFloat,
                       paper: String? = nil) -> AttributedString {
        var piece = render(text, baseSize: baseSize)
        if style.underline { piece.underlineStyle = .single }
        if let hex = style.colorHex {
            // One rule for "can this be read on that", shared with the text
            // boxes on the drawing layer.
            let readable = paper.map { TextBoxStyle.readableInk(hex, on: $0) } ?? hex
            if let colour = Color(hex: readable) { piece.foregroundColor = colour }
        }

        if style.family != nil || style.size != nil {
            let size = style.size.map { CGFloat($0) } ?? baseSize
            for run in piece.runs {
                let intent = run.inlinePresentationIntent ?? []
                var traits: NSFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                piece[run.range].font = font(family: style.family, size: size, traits: traits)
            }
        }
        return piece
    }

    static func font(family: String?, size: CGFloat, traits: NSFontDescriptor.SymbolicTraits) -> Font {
        let base: NSFont
        if let family, let named = NSFont(name: family, size: size) ?? NSFontManager.shared
            .font(withFamily: family, traits: [], weight: 5, size: size) {
            base = named
        } else {
            base = NSFont.systemFont(ofSize: size)
        }
        guard !traits.isEmpty else { return Font(base) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return Font(NSFont(descriptor: descriptor, size: size) ?? base)
    }

    static func render(_ text: String, baseSize: CGFloat = 15) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        let parsed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        return typesetMaths(in: parsed, baseSize: baseSize)
    }

    /// `` `wl:Sum[i, {i, 1, n}]` `` in a sentence comes out as maths. The runs
    /// are replaced back to front, so the ranges ahead of each one are still
    /// the ranges it was found at.
    static func typesetMaths(in string: AttributedString, baseSize: CGFloat) -> AttributedString {
        var result = string
        var replacements: [(Range<AttributedString.Index>, AttributedString)] = []
        for run in result.runs {
            guard (run.inlinePresentationIntent ?? []).contains(.code) else { continue }
            let text = String(result[run.range].characters)
            guard let source = MathMarkup.expression(inCode: text),
                  let maths = MathTypesetter.inline(source, size: baseSize) else { continue }
            replacements.append((run.range, maths))
        }
        for (range, maths) in replacements.reversed() {
            result.replaceSubrange(range, with: maths)
        }
        return result
    }

    /// Split on `<u>`, `</u>`, `<span style="…">` and `</span>`; everything
    /// else is text, including any other HTML, which stays literal.
    static func tokenize(_ source: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        let ns = source as NSString
        var index = 0

        func flush() {
            if !buffer.isEmpty { tokens.append(.text(buffer)); buffer = "" }
        }

        while index < ns.length {
            let rest = ns.substring(from: index)
            if rest.hasPrefix("<u>") {
                flush(); tokens.append(.open(Style(underline: true))); index += 3
            } else if rest.hasPrefix("</u>") {
                flush(); tokens.append(.close); index += 4
            } else if rest.hasPrefix("</span>") {
                flush(); tokens.append(.close); index += 7
            } else if rest.hasPrefix("<span"), let close = rest.range(of: ">") {
                let tag = String(rest[rest.startIndex..<close.upperBound])
                flush()
                tokens.append(.open(style(fromTag: tag)))
                index += (tag as NSString).length
            } else {
                buffer.append(Character(UnicodeScalar(ns.character(at: index)) ?? " "))
                index += 1
            }
        }
        flush()
        return tokens
    }

    /// `<span style="font-family: Georgia; font-size: 18px; color: #2D7DD2">`
    static func style(fromTag tag: String) -> Style {
        var style = Style()
        guard let open = tag.range(of: "style=\""), let close = tag.range(of: "\"", range: open.upperBound..<tag.endIndex)
        else { return style }
        for declaration in tag[open.upperBound..<close.lowerBound].components(separatedBy: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            switch pair[0].lowercased() {
            case "font-family": style.family = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\'\""))
            case "font-size": style.size = Double(pair[1].replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces))
            case "color": style.colorHex = pair[1]
            default: break
            }
        }
        return style
    }
}

extension String {
    /// The one space after a task list's box, dropped — the words start
    /// after it, and a line with nothing after the box is empty.
    var trimmedLeadingSpace: String { hasPrefix(" ") ? String(dropFirst()) : self }
}
