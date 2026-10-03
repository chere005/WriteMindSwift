import AppKit

/// What a block's markdown looks like while it is being edited.
///
/// The text stays exactly what is in the file — nothing is hidden, so nothing
/// can be lost on the way back — but the markers step back and what they mean
/// shows through: bold is bold, a heading is heading-sized, a link is
/// coloured, maths is set apart. It is the same document either way, which is
/// what keeps the preview safe to type into.
enum MarkdownSourceStyle {
    enum Kind: Equatable {
        case marker
        case heading(Int)
        /// A word inside a fenced code block, coloured for its language.
        case codeToken(CodeToken.Kind)
        case bold
        case italic
        case strikethrough
        case code
        case math
        case linkText
        case linkURL
        case listMarker
        case quoteMarker
    }

    struct Run: Equatable {
        var range: NSRange
        var kind: Kind
    }

    // MARK: - Reading it

    static func runs(in source: String) -> [Run] {
        let ns = source as NSString
        var runs: [Run] = []
        var covered = [Bool](repeating: false, count: ns.length)

        func cover(_ range: NSRange) {
            for index in range.location..<min(NSMaxRange(range), covered.count) { covered[index] = true }
        }
        func isFree(_ range: NSRange) -> Bool {
            !(range.location..<min(NSMaxRange(range), covered.count)).contains { covered[$0] }
        }

        // What a line is, before what is inside it. A fence line is a marker
        // and the lines inside the fence are code (or maths, for a `wl`
        // fence) — decided here, ahead of the inline patterns, because the
        // inline-code pattern read the first two backticks of a ``` as an
        // empty code span and left the third looking like text (Sean,
        // 2026-09-19: "showing the 3rd tick as the wrong color").
        var offset = 0
        var fence: Kind?
        var fenceLanguage: CodeLanguage?
        var fenceBodyStart = 0

        /// The code between the fences, coloured for whichever language the
        /// opening fence named (Sean, 2026-09-19: "make sure to support c,
        /// cpp, wolfram, python, typescript code blocks"). Done at the
        /// CLOSING fence, over the whole body at once, so a string or a
        /// comment that runs over several lines is read as one thing.
        func closeFence(bodyEnd: Int) {
            defer { fence = nil; fenceLanguage = nil }
            guard let language = fenceLanguage, language != .plain, bodyEnd > fenceBodyStart else { return }
            let body = ns.substring(with: NSRange(location: fenceBodyStart, length: bodyEnd - fenceBodyStart))
            for token in CodeHighlighter.tokens(in: body, language: language) {
                runs.append(Run(range: NSRange(location: fenceBodyStart + token.range.location,
                                               length: token.range.length),
                                kind: .codeToken(token.kind)))
            }
        }

        for line in source.components(separatedBy: "\n") {
            let length = (line as NSString).length
            let start = offset
            offset += length + 1
            guard length > 0 else { continue }

            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("```") {
                runs.append(Run(range: NSRange(location: start, length: length), kind: .marker))
                cover(NSRange(location: start, length: length))
                if fence == nil {
                    let language = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    fence = MathMarkup.isMathFence(language) ? .math : .code
                    fenceLanguage = MathMarkup.isMathFence(language) ? nil : CodeLanguage.colouring(fence: language)
                    fenceBodyStart = offset
                } else {
                    closeFence(bodyEnd: max(fenceBodyStart, start - 1))
                }
                continue
            }
            if let fence {
                runs.append(Run(range: NSRange(location: start, length: length), kind: fence))
                cover(NSRange(location: start, length: length))
                continue
            }

            let hashes = line.prefix { $0 == "#" }
            if (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " {
                let marker = hashes.count + 1
                runs.append(Run(range: NSRange(location: start, length: marker), kind: .marker))
                if length > marker {
                    runs.append(Run(range: NSRange(location: start + marker, length: length - marker),
                                    kind: .heading(hashes.count)))
                }
                cover(NSRange(location: start, length: marker))
                continue
            }

            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let rest = line.dropFirst(indent.count)
            if let marker = ["- ", "* ", "+ "].first(where: { rest.hasPrefix($0) }) {
                let range = NSRange(location: start + indent.count, length: (marker as NSString).length)
                runs.append(Run(range: range, kind: .listMarker))
                cover(range)
            } else if rest.hasPrefix(">") {
                let quotes = rest.prefix { $0 == ">" || $0 == " " }
                let range = NSRange(location: start + indent.count, length: (String(quotes) as NSString).length)
                runs.append(Run(range: range, kind: .quoteMarker))
                cover(range)
            } else {
                let digits = rest.prefix { $0.isNumber }
                let after = rest.dropFirst(digits.count)
                if !digits.isEmpty, digits.count <= 4, after.hasPrefix(". ") || after.hasPrefix(") ") {
                    let range = NSRange(location: start + indent.count, length: digits.count + 2)
                    runs.append(Run(range: range, kind: .listMarker))
                    cover(range)
                }
            }
        }

        // A fence left open by a half-typed block still colours its body.
        if fence != nil { closeFence(bodyEnd: ns.length) }

        // ``a ` b`` — two backticks either side, which is how a code span
        // holds a backtick of its own (Sean, 2026-09-20: "code blocks are
        // only ``` and ` and `` blocks"). Before the single-backtick
        // pattern, which would otherwise read the first two as an empty
        // span.
        for match in Patterns.codePair.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            guard isFree(match.range), match.range.length > 4 else { continue }
            runs.append(Run(range: NSRange(location: match.range.location, length: 2), kind: .marker))
            runs.append(Run(range: NSRange(location: match.range.location + 2,
                                           length: match.range.length - 4), kind: .code))
            runs.append(Run(range: NSRange(location: NSMaxRange(match.range) - 2, length: 2), kind: .marker))
            cover(match.range)
        }

        // Code first, because what is inside it is not markdown at all.
        for match in Patterns.code.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            // Two backticks with nothing between them are two backticks, as
            // the rendered page draws them — not an empty span whose ticks
            // vanish when the caret leaves the line (Sean, 2026-10-03:
            // "cursor behavior around backticks is very weird"): type "``",
            // move on, and both were gone. The same for the first two of a
            // "```" inside a sentence, and for a tick typed in front of a
            // span's own ("``foo`").
            guard isFree(match.range), match.range.length > 2 else { continue }
            let inner = match.range(at: 1)
            let text = inner.length > 0 ? ns.substring(with: inner) : ""
            runs.append(Run(range: NSRange(location: match.range.location, length: 1), kind: .marker))
            runs.append(Run(range: NSRange(location: NSMaxRange(match.range) - 1, length: 1), kind: .marker))
            if text.hasPrefix(MathMarkup.inlinePrefix) {
                let prefix = (MathMarkup.inlinePrefix as NSString).length
                runs.append(Run(range: NSRange(location: inner.location, length: prefix), kind: .marker))
                runs.append(Run(range: NSRange(location: inner.location + prefix, length: inner.length - prefix),
                                kind: .math))
            } else if inner.length > 0 {
                runs.append(Run(range: inner, kind: .code))
            }
            cover(match.range)
        }

        for match in Patterns.link.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            guard isFree(match.range) else { continue }
            let text = match.range(at: 1)
            let url = match.range(at: 2)
            runs.append(Run(range: NSRange(location: match.range.location, length: 1), kind: .marker))
            if text.length > 0 { runs.append(Run(range: text, kind: .linkText)) }
            runs.append(Run(range: NSRange(location: NSMaxRange(text), length: 2), kind: .marker))
            if url.length > 0 { runs.append(Run(range: url, kind: .linkURL)) }
            runs.append(Run(range: NSRange(location: NSMaxRange(match.range) - 1, length: 1), kind: .marker))
            cover(match.range)
        }

        // <u>, <span style=…>, <mark id=…> — the toolbar's own HTML.
        for match in Patterns.tag.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            guard isFree(match.range) else { continue }
            runs.append(Run(range: match.range, kind: .marker))
            cover(match.range)
        }

        for (pattern, kind) in [(Patterns.bold, Kind.bold), (Patterns.italic, Kind.italic)] {
            for match in pattern.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                guard isFree(match.range) else { continue }
                let marker = match.range(at: 1).length
                // `**` on its own is two markers round nothing — not a style.
                guard match.range.length > marker * 2 else { continue }
                runs.append(Run(range: NSRange(location: match.range.location, length: marker), kind: .marker))
                runs.append(Run(range: NSRange(location: match.range.location + marker,
                                               length: match.range.length - marker * 2), kind: kind))
                runs.append(Run(range: NSRange(location: NSMaxRange(match.range) - marker, length: marker),
                                kind: .marker))
                cover(match.range)
            }
        }

        // ~~struck~~ (Sean, 2026-09-19: "add strikethrough").
        for match in Patterns.strike.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            guard isFree(match.range), match.range.length > 4 else { continue }
            runs.append(Run(range: NSRange(location: match.range.location, length: 2), kind: .marker))
            runs.append(Run(range: NSRange(location: match.range.location + 2, length: match.range.length - 4),
                            kind: .strikethrough))
            runs.append(Run(range: NSRange(location: NSMaxRange(match.range) - 2, length: 2), kind: .marker))
            cover(match.range)
        }

        // Longest first where two runs start together, so a code token lands
        // ON TOP of the line-wide code run rather than under it.
        return runs.sorted {
            $0.range.location != $1.range.location
                ? $0.range.location < $1.range.location
                : $0.range.length > $1.range.length
        }
    }

    // MARK: - Its spans

    /// AN INLINE SPAN, ITS MARKERS AND ALL — a code span, maths, bold,
    /// italic, struck, a link, a tag — read with the patterns `runs`
    /// styles them with. What a cut through a paragraph has to go round
    /// (`Insertion`, the review of 2026-10-02): cut one in two and each
    /// half keeps a marker that pairs with nothing.
    struct Span: Equatable {
        enum Kind: Equatable {
            case code
            /// A `wl:` code span: maths, the way a ```wl block is.
            case maths
            /// Bold, italic, struck, a link, a tag.
            case styled
        }
        var range: NSRange
        /// What is between its markers — after the `wl:` too, for maths.
        /// A link's is the whole link and a tag's the whole tag: an
        /// address is not a marker to be thrown away.
        var content: NSRange
        var kind: Kind
    }

    /// Every span in `source`, a cell of words — nested ones too: bold
    /// round a code span is bold for a cut, though `runs` colours only the
    /// code. No fence is looked for; a cell of words has none.
    static func spans(in source: String) -> [Span] {
        let ns = source as NSString
        let all = NSRange(location: 0, length: ns.length)
        var spans: [Span] = []
        // Code first, as in `runs` — what is inside it is not markdown —
        // and `` before `, which would read the first two backticks of a
        // `` span as an empty one.
        for match in Patterns.codePair.matches(in: source, range: all) where match.range.length > 4 {
            spans.append(Span(range: match.range,
                              content: NSRange(location: match.range.location + 2, length: match.range.length - 4),
                              kind: .code))
        }
        for match in Patterns.code.matches(in: source, range: all)
        where match.range.length > 2
            && !spans.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
            let inner = match.range(at: 1)
            let maths = ns.substring(with: inner).hasPrefix(MathMarkup.inlinePrefix)
            let prefix = maths ? (MathMarkup.inlinePrefix as NSString).length : 0
            spans.append(Span(range: match.range,
                              content: NSRange(location: inner.location + prefix, length: inner.length - prefix),
                              kind: maths ? .maths : .code))
        }
        let code = spans.map(\.range)
        func inCode(_ range: NSRange) -> Bool {
            code.contains { NSIntersectionRange($0, range).length == range.length }
        }
        for pattern in [Patterns.link, Patterns.tag] {
            for match in pattern.matches(in: source, range: all) where !inCode(match.range) {
                spans.append(Span(range: match.range, content: match.range, kind: .styled))
            }
        }
        // The emphasis patterns capture their marker; the strike's is `~~`.
        let emphasis: [(NSRegularExpression, Int?)] = [(Patterns.bold, nil), (Patterns.italic, nil), (Patterns.strike, 2)]
        for (pattern, fixed) in emphasis {
            for match in pattern.matches(in: source, range: all) where !inCode(match.range) {
                let marker = fixed ?? match.range(at: 1).length
                guard match.range.length > marker * 2 else { continue }
                spans.append(Span(range: match.range,
                                  content: NSRange(location: match.range.location + marker,
                                                   length: match.range.length - marker * 2),
                                  kind: .styled))
            }
        }
        return spans
    }

    private enum Patterns {
        static let code = regex("`([^`\n]*)`")
        /// Two backticks either side, holding anything but a newline — a
        /// span that can contain a single backtick.
        static let codePair = regex("``[^\n]*?``")
        static let link = regex("\\[([^\\]\n]*)\\]\\(([^)\n]*)\\)")
        static let tag = regex("</?[A-Za-z][^>\n]*>")
        static let bold = regex("(\\*\\*|__)(?=\\S)(?:.*?\\S)\\1")
        static let italic = regex("(\\*|_)(?=\\S)(?:[^*_\n]*?[^\\s*_])\\1")
        static let strike = regex("~~(?=\\S)(?:[^~\n]*?\\S)~~")

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // The patterns are literals here; one that does not compile is a
            // typo in this file, not something a note can cause.
            try! NSRegularExpression(pattern: pattern)
        }
    }

    // MARK: - Showing it

    static func apply(to storage: NSTextStorage, base: NSFont, paragraph: NSParagraphStyle) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: base,
                               .foregroundColor: NSColor.textColor,
                               .paragraphStyle: paragraph], range: full)

        for run in runs(in: storage.string) {
            let range = NSIntersectionRange(run.range, full)
            guard range.length > 0 else { continue }
            switch run.kind {
            case .marker:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .heading(let level):
                storage.addAttribute(.font, value: headingFont(level, base: base), range: range)
            case .bold:
                add(.bold, in: range, of: storage)
            case .italic:
                add(.italic, in: range, of: storage)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .code:
                monospace(range, of: storage)
            case .codeToken(let kind):
                monospace(range, of: storage)
                storage.addAttribute(.foregroundColor, value: CodeColours.colour(for: kind), range: range)
                if kind == .comment { add(.italic, in: range, of: storage) }
            case .math:
                monospace(range, of: storage)
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
            case .linkText:
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
            case .linkURL:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .listMarker, .quoteMarker:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }
        }
        storage.endEditing()
    }

    /// The blank lines between cells: structure rather than writing, so
    /// they are drawn at the gap the rendered page leaves rather than at a
    /// full line's height. The same note is then nearly the same height on
    /// both sides (Sean, 2026-09-19: "positions stay the same in markdown
    /// and wysiwyg mode", "there shouldn't be gaps between cells").
    ///
    /// A fence's ``` line is NOT one of these, however little it means on
    /// the rendered page: it has characters on it, and squashing a line
    /// with writing on it to a few points clips the writing (Sean,
    /// 2026-09-20, with a picture of a code cell cut in half).
    ///
    /// Only while the markers are hidden. With the raw markdown showing,
    /// the file is shown as it is written, full-height blank lines and all.
    static func structuralLines(in source: String) -> [NSRange] {
        let ns = source as NSString
        var runs: [[NSRange]] = []
        var current: [NSRange] = []
        var index = 0
        while index < ns.length {
            let line = ns.lineRange(for: NSRange(location: index, length: 0))
            if ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                current.append(line)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
            index = max(NSMaxRange(line), index + 1)
        }
        if !current.isEmpty { runs.append(current) }

        // The FIRST and LAST blank line of a run are the separators either
        // side of what is between them; the rest are a cell of empty lines
        // the note is holding on purpose, and they keep their height
        // (Sean, 2026-09-20: "one with 8 empty lines.. and autospacing
        // between the cells").
        return runs.flatMap { run -> [NSRange] in
            run.count <= 2 ? run : [run[0], run[run.count - 1]]
        }
    }

    /// How tall a blank line is drawn. Nearly nothing: the gap between two
    /// cells is made by the SPACE AFTER the cell above it, not by however
    /// many blank lines the file happens to have between them, so that
    /// every gap is the same one (Sean, 2026-09-20: "cells still aren't
    /// stacked with an even small spacing between them").
    static let structuralSize: CGFloat = 2

    /// The last line of every cell — the line that carries the gap.
    static func cellEndLines(in source: String) -> [NSRange] {
        let ns = source as NSString
        return MarkdownParser.positioned(from: source).compactMap { block in
            let end = min(max(NSMaxRange(block.range) - 1, 0), max(ns.length - 1, 0))
            guard ns.length > 0 else { return nil }
            return ns.lineRange(for: NSRange(location: end, length: 0))
        }
    }

    /// The same ladder the rendered block uses, so a heading being edited is
    /// the size it will be.
    static func headingFont(_ level: Int, base: NSFont) -> NSFont {
        let size = MarkdownPreview.BlockView.headingSize(level)
        switch level {
        case 1: return NSFont.systemFont(ofSize: size, weight: .bold)
        case 2, 3, 4, 5: return NSFont.systemFont(ofSize: size, weight: .semibold)
        default:
            let italic = NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
            return italic
        }
    }

    private static func add(_ traits: NSFontDescriptor.SymbolicTraits, in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            if let updated = NSFont(descriptor: descriptor, size: font.pointSize) {
                storage.addAttribute(.font, value: updated, range: subrange)
            }
        }
    }

    private static func monospace(_ range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let size = ((value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)).pointSize
            // The 0.95 is `MarkdownTextView.codeSize`'s, for the body font;
            // a heading with code in it keeps its own size.
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size * 0.95, weight: .regular),
                                 range: subrange)
        }
    }
}

private extension NSRegularExpression {
    func matches(in string: String, range: NSRange) -> [NSTextCheckingResult] {
        matches(in: string, options: [], range: range)
    }
}
