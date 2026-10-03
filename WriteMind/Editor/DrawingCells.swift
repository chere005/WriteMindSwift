import AppKit

/// A DRAWING CELL, as the note holds it: one line, an image every markdown
/// reader shows, naming a file beside the note.
///
/// Sean, 2026-10-02: "on drawing segments, add a dock button which inserts
/// it into the cell of the existing cursor, and a create cell from drawing
/// which has a new type of cell.. and drawing cell which is cmd + 0". Asked
/// the same day whether the files go in a hidden folder or a visible one:
/// "visible data generally speaking". So the line is
///
///     ![](_drawings/cells/6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6.png)
///
/// with a blank line either side, exactly what `CellTypes.open` writes for
/// any cell, and the file is `_drawings/cells/<ID>.png` in the NOTE'S OWN
/// folder — the same bytes at every depth, so a note moved to another
/// section never needs its line rewritten. The cell is known by its UUID
/// and nothing else: the alt text is free, and WriteMind writes none.
///
/// Pure, and the one reader of the line for everyone — the parser, the
/// store, the commands — so none of them can disagree about what is one.
enum DrawingCells {
    /// The folder beside a note that holds its data rather than notes. It is
    /// never a section (`NoteTree.isSection`).
    static let dataFolder = "_drawings"
    static let cellsFolder = "cells"
    /// What the line names the file by, relative to the note.
    static var relativeFolder: String { dataFolder + "/" + cellsFolder }

    /// The line for a cell.
    static func line(_ id: UUID) -> String {
        "![](\(relativeFolder)/\(id.uuidString).png)"
    }

    /// The whole line, trimmed: an image of a file in the cells folder named
    /// by a UUID, and nothing else on the line but the `<a id>` that `/link`
    /// writes in front of any block that is not a heading
    /// (`MarkdownLinking.anchor`) — without it, linking to a drawing would
    /// turn it back into a paragraph. Words beside the image, another
    /// folder, `../`, a name that is not a UUID, another extension: a
    /// paragraph, as it always was.
    private static let pattern: NSRegularExpression = {
        let uuid = "[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}"
        let folder = NSRegularExpression.escapedPattern(for: relativeFolder)
        // A pattern written here and nowhere else; a typo is a crash on
        // the first note opened, which the parser tests are the first to see.
        return try! NSRegularExpression(
            pattern: "^(?:<a id=\"[^\"]*\"></a>)?!\\[([^\\]\\n]*)\\]\\(\(folder)/(\(uuid))\\.png\\)$")
    }()

    /// The cell a line is, if it is one: its id, its alt text, and where the
    /// id sits in the line (what a fork rewrites).
    private static func match(_ line: String) -> (id: UUID, alt: String, idRange: NSRange)? {
        let ns = line as NSString
        guard let found = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let id = UUID(uuidString: ns.substring(with: found.range(at: 2))) else { return nil }
        return (id, ns.substring(with: found.range(at: 1)), found.range(at: 2))
    }

    /// A trimmed line of the note, read as a drawing cell.
    static func parse(_ line: String) -> (id: UUID, alt: String)? {
        match(line).map { ($0.id, $0.alt) }
    }

    /// Every drawing cell in the note, in order, with the range of its line.
    /// Through the parser, so a drawing line inside a fence is code and not
    /// a cell.
    static func lines(in markdown: String) -> [(id: UUID, range: NSRange)] {
        MarkdownParser.positioned(from: markdown).compactMap { block in
            guard case .drawing(let id, _) = block.block else { return nil }
            return (id, block.range)
        }
    }

    /// The ids the note names, each once, in the order they first appear.
    static func ids(in markdown: String) -> [UUID] {
        var seen: Set<UUID> = []
        return lines(in: markdown).map(\.id).filter { seen.insert($0).inserted }
    }

    /// WHERE ⌘0 PUTS ITS CELL when the caret is in a cell: UNDER THE CARET'S
    /// OWN SOURCE LINE (Sean, 2026-09-22: "in an existing cell .. the input
    /// cursor and text can only go above and below a docked image"). For a
    /// one-line paragraph that is after the cell; in a list, a quote or a
    /// paragraph of several lines the drawing lands under the line he is
    /// on, and the cell becomes two.
    ///
    /// Except where that would cut something that cannot be cut: a fence
    /// is never split, so a fenced or maths cell gives its end — and an
    /// evaluation cell the end of its answer, since nothing may come
    /// between an In and its Out (`EvalCells.groups`). A drawing cell gives
    /// its own end, so ⌘0 in one makes the next one after it. A cell of
    /// blank lines gives the caret itself, because `insertBlock` keeps the
    /// run's lines round whatever opens in it. A caret in no cell at all is
    /// where the cell goes.
    ///
    /// Never "the first cell" for want of one: that fallback is how ⌘1 once
    /// titled the top of the note from a bar at its bottom.
    static func landing(caret: Int, in markdown: String) -> Int {
        let ns = markdown as NSString
        let caret = min(max(caret, 0), ns.length)
        let blocks = MarkdownParser.positioned(from: markdown)
        guard let cell = blocks.first(where: { $0.range.location <= caret && caret <= NSMaxRange($0.range) })
        else { return caret }
        switch cell.block {
        case .code:
            let group = EvalCells.groups(in: markdown).first {
                NSEqualRanges($0.input, cell.range) || NSEqualRanges($0.output, cell.range)
            }
            return NSMaxRange(group?.range ?? cell.range)
        case .drawing:
            return NSMaxRange(cell.range)
        case .blank:
            return caret
        default:
            var end = 0
            ns.getLineStart(nil, end: nil, contentsEnd: &end, for: NSRange(location: caret, length: 0))
            return min(max(end, cell.range.location), NSMaxRange(cell.range))
        }
    }

    /// The note with every drawing cell given a NEW id — what a duplicated
    /// note is written as, so two notes never share a drawing (copying the
    /// files is the store's half). A line pasted twice by hand names one
    /// drawing in both places, and so does its copy: one old id, one new.
    /// Nothing but the ids changes, byte for byte.
    static func forked(_ markdown: String, minting mint: () -> UUID = UUID.init)
        -> (markdown: String, ids: [(old: UUID, new: UUID)]) {
        let ns = markdown as NSString
        var renamed: [(old: UUID, new: UUID)] = []
        var edits: [(range: NSRange, id: UUID)] = []
        for cell in lines(in: markdown) {
            let text = ns.substring(with: cell.range)
            // The block's range starts at its line's start and the parser
            // reads the line trimmed, so the match is measured from where
            // the trimmed line begins.
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let lead = (text as NSString).range(of: trimmed).location
            guard lead != NSNotFound, let found = match(trimmed) else { continue }
            let new: UUID
            if let known = renamed.first(where: { $0.old == found.id }) {
                new = known.new
            } else {
                new = mint()
                renamed.append((found.id, new))
            }
            edits.append((NSRange(location: cell.range.location + lead + found.idRange.location,
                                  length: found.idRange.length), new))
        }
        let out = NSMutableString(string: markdown)
        for edit in edits.reversed() { out.replaceCharacters(in: edit.range, with: edit.id.uuidString) }
        return (out as String, renamed)
    }

    /// The note without its drawing cells' lines — what the footer counts
    /// words in. A drawing is not words, and its line is a file's name.
    static func prose(_ markdown: String) -> String {
        guard markdown.contains(relativeFolder) else { return markdown }
        let out = NSMutableString(string: markdown)
        for line in lines(in: markdown).reversed() { out.replaceCharacters(in: line.range, with: "") }
        return out as String
    }

    // MARK: - The caret in a drawing cell

    /// The drawing cell a caret is in, by its line: a caret anywhere on the
    /// line, both of its ends included. A selection is not a caret.
    static func cell(atCaret selection: NSRange, lines: [NSRange]) -> NSRange? {
        guard selection.length == 0 else { return nil }
        return lines.first { selection.location >= $0.location && selection.location <= NSMaxRange($0) }
    }

    /// THE SEAM UNDER A DRAWING CELL, as the offset a cell would open at
    /// there: the next cell's start, or the note's end. A drawing cell takes
    /// no characters, so anything that WRITES with the caret in one goes to
    /// the bar under it — it stands in for that bar.
    static func seamAfter(_ line: NSRange, in markdown: String) -> Int {
        let end = NSMaxRange(line)
        return MarkdownParser.positioned(from: markdown).first { $0.range.location >= end }?.range.location
            ?? (markdown as NSString).length
    }

    /// The caret never sits INSIDE a drawing cell's line, whose characters
    /// are hidden while the markers are: strictly inside, it goes to the
    /// line's end moving forward and to its start moving back, and a
    /// selection that takes part of a line takes all of it. So ← from the
    /// start and → from the end leave the cell, and ← and → inside it go
    /// from one end to the other.
    static func snap(_ range: NSRange, lines: [NSRange], backwards: Bool) -> NSRange {
        if range.length == 0 {
            guard let line = lines.first(where: { range.location > $0.location && range.location < NSMaxRange($0) })
            else { return range }
            return NSRange(location: backwards ? line.location : NSMaxRange(line), length: 0)
        }
        var widened = range
        for line in lines {
            let overlap = NSIntersectionRange(widened, line)
            guard overlap.length > 0, overlap.length < line.length else { continue }
            widened = NSUnionRange(widened, line)
        }
        return widened
    }

    /// What a key does with the caret in a drawing cell — ONE TABLE FOR BOTH
    /// PANES (docs/CROSS-PLATFORM.md). For anything that writes, the cell
    /// stands in for the bar under it.
    enum Key: Equatable {
        /// A printable character: a text cell AFTER the drawing with it in
        /// — the bar under the drawing, typed into.
        case write(String)
        /// Return: an empty cell after it, open for typing.
        case empty
        /// ⌫ or ⌦: the cell is HELD, whole, its bracket with it — and ⌫ on
        /// a held cell takes it, as it takes any. One stray key never
        /// deletes a drawing.
        case hold
        /// ↑ or ↓: the bar above it, or the bar below it.
        case step(up: Bool)
        /// Escape: out of the cell, on the rendered page. The markdown pane
        /// does nothing new with it.
        case leave
        /// Not the cell's business: a ⌘ or ⌃ chord, and anything else.
        case pass
    }

    /// The table, read off a key the way the rendered page gets one: its
    /// characters, and whether ⌘ or ⌃ was held. The arrows and the
    /// deletes arrive as characters too, in Unicode's private use area.
    static func key(characters: String, chord: Bool) -> Key {
        guard !chord else { return .pass }
        switch characters {
        case "\u{1B}": return .leave
        case "\r", "\n", "\u{3}": return .empty
        case "\u{8}", "\u{7F}", "\u{F728}": return .hold
        case "\u{F700}": return .step(up: true)
        case "\u{F701}": return .step(up: false)
        default: break
        }
        guard !characters.isEmpty else { return .pass }
        let printable = characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
        return printable ? .write(characters) : .pass
    }

    /// The same table, read off the command a key became in a text view —
    /// the markdown pane's way in. Typing arrives as `insertText`, which is
    /// `.write`, and never here.
    static func key(command: Selector) -> Key {
        switch command {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return .empty
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)),
             #selector(NSResponder.deleteWordBackward(_:)), #selector(NSResponder.deleteWordForward(_:)),
             #selector(NSResponder.deleteToBeginningOfLine(_:)), #selector(NSResponder.deleteToEndOfLine(_:)),
             #selector(NSResponder.deleteBackwardByDecomposingPreviousCharacter(_:)):
            return .hold
        case #selector(NSResponder.moveUp(_:)): return .step(up: true)
        case #selector(NSResponder.moveDown(_:)): return .step(up: false)
        case #selector(NSResponder.cancelOperation(_:)): return .leave
        default: return .pass
        }
    }

    // MARK: - How big it is

    /// HOW BIG A CELL IS SHOWN in a column `column` points wide. Never
    /// bigger than it was drawn: s = min(1, column ÷ W), and in a narrower
    /// column the drawing shrinks WHOLE — ink widths too, like a picture —
    /// at the column's left. An empty cell is the column's width and
    /// `emptyHeight` tall. Never under two lines: a cell with no height is
    /// a cell nothing can hold, and nothing can be drawn in.
    static func shown(_ cell: DrawingCell?, column: CGFloat) -> (scale: CGFloat, size: CGSize) {
        let drawn = cell.map { CGFloat($0.width) } ?? 0
        let width = drawn > 0 ? drawn : max(column, 1)
        let scale = column > 0 ? min(1, column / width) : 1
        let height = cell.map { CGFloat($0.height) } ?? CGFloat(emptyHeight)
        return (scale, CGSize(width: width * scale, height: max(height * scale, 2 * MarkdownTextView.lineHeight)))
    }

    /// How tall a cell with nothing in it is: eight lines of the note's
    /// text, room to start writing in.
    static let emptyHeight = Double(8 * MarkdownTextView.lineHeight)

    /// The least air left under a drawing's content when its cell is made
    /// shorter: a bottom edge on the ink reads as ink cut off.
    static let pad: Double = 12
}
