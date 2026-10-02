import Foundation

/// WHERE A BLOCK GOES WHEN ONE IS ASKED FOR, AND WHAT IT HOLDS — ⌘8 and the
/// code button, ⌘9, and the maths palette, in both panes.
///
/// Sean, 2026-10-02: "make math and code block insertion sensible..". Each
/// of the three used to write its fence wherever the caret happened to be,
/// with one newline either side: the paragraph it landed in was glued to it
/// with no seam between them, a list item came out as `- ban`, a stray
/// `ana` and a code block, a fence went inside a fence, a maths palette
/// threw selected words away, and ⌘9 ignored the caret altogether and put
/// its cell under whatever cell the caret was in. The rules, in the order
/// they are asked:
///
/// - AT THE BAR THE CELL IS MADE THERE, the rule every command already
///   follows — and ⌘8 keeps the language picked under the button there
///   too, which it used to drop.
/// - INSIDE A FENCED BLOCK nothing is ever nested. A block of the same kind
///   does nothing and the footer says why (⌘8 in code, ⌘9 in a cell that
///   already runs that way). ⌘9 in any other fenced cell turns it into one
///   (Sean, 2026-09-21: "cmd+9 should start a new cell or turn the existing
///   cell to an evaluation cell") — except an answer, which is never code.
///   Maths in a block that is already Wolfram Language goes in as the bare
///   WL at the caret. Anything else goes in after the block, as its own
///   cell — after its answer, when it has one.
/// - A BLOCK IS A CELL OF ITS OWN: a blank line above it and below, never
///   glued into a paragraph or a list item. A paragraph is cut at the caret
///   and the block goes between the halves (at the front of its words,
///   above it; at the end, below). Cells made of lines — a heading, a list,
///   a quote — are cut only between lines: above the caret's line when the
///   caret is at the front of its words or in its marker, below it
///   otherwise. On an empty line of a blank cell the block takes that line
///   and no other.
/// - A SELECTION BECOMES WHAT THE BLOCK HOLDS: code verbatim, the text
///   either side staying as cells of its own. Maths takes a selection's
///   place only when the maths still holds it (`MathSelection.holds`), so
///   selected words are never thrown away — the maths goes after them.
///   A selection with a fence in it is refused: that would be a nest.
/// - THE CARET ENDS WHERE TYPING GOES: between an empty block's fences, at
///   the end of what a block was given, at the end of display maths' WL,
///   after inline maths.
/// - INLINE MATHS STAYS IN THE SENTENCE, never in front of a marker; where
///   there are no words — a bar, an empty line, the edge of a fenced cell —
///   it is a plain cell of its own.
///
/// It answers with ONE edit over the note, so the source pane applies it
/// as one step of undo, and the rendered page asks the same question with
/// the same note and the same caret and gets the same answer. The cell's
/// own text is `CellTypes.open`'s — the one block builder — and its spacing
/// is `PreviewEditing.insertBlock`'s.
enum Insertion {
    /// What is being put in.
    enum Thing: Equatable {
        /// ⌘8, the code button and Insert ▸ Code Block, in the language
        /// picked under the button.
        case code(CodeLanguage)
        /// ⌘9, in the environment the badge last picked.
        case evaluation(Evaluator)
        /// The palette's WL: on a line of its own, a ```wl cell; in the
        /// sentence, a `wl:` code span.
        case maths(String, onItsOwnLine: Bool)
    }

    /// Why nothing was written — said in the footer, because a key that
    /// does nothing and says nothing reads as a key that is broken.
    enum Refusal: Equatable {
        case codeInCode
        case alreadyEvaluates(Evaluator)
        case mathsInCode
        case fenceInSelection

        var message: String {
            switch self {
            case .codeInCode:
                return "The caret is in a code block already, and a code block cannot go inside one."
            case .alreadyEvaluates(let evaluator):
                return "This is a \(evaluator.title) evaluation cell already."
            case .mathsInCode:
                return "Maths goes in words or in a maths block — inside code it would only be typed as code."
            case .fenceInSelection:
                return "That selection has a fenced block in it, and one block cannot go inside another."
            }
        }
    }

    enum Outcome: Equatable {
        case edit(MarkdownFormatting.Edit)
        case refused(Refusal)
    }

    /// What `thing` does to `text` with `selection` where the caret is — or,
    /// `atBar`, with the insertion bar at `selection.location`.
    static func insert(_ thing: Thing, in text: String, at selection: NSRange, atBar: Bool) -> Outcome {
        let ns = text as NSString
        let selection = MarkdownFormatting.clamp(selection, to: ns.length)
        let thing = canonical(thing)
        if atBar { return made(thing, at: Spot(removing: NSRange(location: selection.location, length: 0)), in: text) }

        let blocks = MarkdownParser.positioned(from: text)
        if let cell = blocks.first(where: { fenced($0.block) != nil && encloses($0.range, selection) }),
           let kind = fenced(cell.block) {
            return inside(cell, kind, thing, selection, in: text)
        }
        if selection.length > 0,
           blocks.contains(where: { fenced($0.block) != nil && NSIntersectionRange($0.range, selection).length > 0 }) {
            return .refused(.fenceInSelection)
        }

        switch thing {
        case .maths(let wl, let onItsOwnLine):
            if selection.length > 0, MathSelection.holds(wl, selected: ns.substring(with: selection)) {
                guard onItsOwnLine else { return .edit(written(wl: MathMarkup.inline(wl), over: selection)) }
                return made(thing, at: selectionSpot(selection, ns), in: text)
            }
            // Words are kept: the maths goes in where the selection ends.
            let caret = NSMaxRange(selection)
            return onItsOwnLine
                ? made(thing, at: spot(for: caret, in: text, blocks), in: text)
                : inline(wl, at: caret, in: text, blocks)
        case .code, .evaluation:
            let selected = ns.substring(with: selection)
            guard selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return made(thing, at: selectionSpot(selection, ns),
                            holding: selected.trimmingCharacters(in: .newlines), in: text)
            }
            return made(thing, at: spot(for: selection.location, in: text, blocks), in: text)
        }
    }

    // MARK: - Inside a fenced block

    /// A fenced cell, as far as putting something into it goes.
    private enum Fenced: Equatable {
        case code(CodeLanguage?)
        case maths
        case evaluation(Evaluator?)
        /// An Out cell: what a run said, never code to be written in.
        case answer
    }

    private static func fenced(_ block: MarkdownBlock) -> Fenced? {
        guard case .code(let language, _) = block else { return nil }
        if EvalOutput.isOut(block) { return .answer }
        if MathMarkup.isMathFence(language) { return .maths }
        if Evaluator.isEvaluation(fence: language) { return .evaluation(Evaluator.from(fence: language)) }
        return .code(CodeLanguage.from(fence: language))
    }

    /// Whether what a fenced cell holds is Wolfram Language — maths, a
    /// Wolfram cell that runs, Wolfram code — so the palette's WL can go
    /// into it as it is.
    private static func holdsWL(_ kind: Fenced) -> Bool {
        switch kind {
        case .maths: return true
        case .evaluation(let evaluator): return evaluator == .wolfram
        case .code(let language): return language == .wolfram
        case .answer: return false
        }
    }

    /// Inside a cell, not at its edges: a caret before the opening fence or
    /// after the closing one is above or below the cell, and a selection of
    /// the whole cell — its bracket held — is in it.
    private static func encloses(_ cell: NSRange, _ selection: NSRange) -> Bool {
        guard cell.location <= selection.location, NSMaxRange(selection) <= NSMaxRange(cell) else { return false }
        guard selection.length == 0 else { return true }
        return cell.location < selection.location && selection.location < NSMaxRange(cell)
    }

    private static func inside(_ cell: PositionedBlock, _ kind: Fenced, _ thing: Thing,
                               _ selection: NSRange, in text: String) -> Outcome {
        let after = Spot(removing: NSRange(location: below(cell.range, in: text), length: 0))
        switch thing {
        case .code:
            if case .code = kind { return .refused(.codeInCode) }
            return made(thing, at: after, in: text)
        case .evaluation(let evaluator):
            if case .answer = kind { return made(thing, at: after, in: text) }
            if case .evaluation(let already) = kind, already == evaluator {
                return .refused(.alreadyEvaluates(evaluator))
            }
            guard let turned = EvalCells.setEnvironment(evaluator, of: cell.range, in: text) else {
                return .refused(.alreadyEvaluates(evaluator))
            }
            // The fence line is rewritten and the caret stays in the code
            // it was in, moved by however much longer that line got.
            return .edit(MarkdownFormatting.Edit(range: turned.range, replacement: turned.replacement,
                                                 selection: moved(selection, by: turned)))
        case .maths(let wl, let onItsOwnLine):
            if holdsWL(kind), let body = body(of: cell.range, in: text),
               body.location <= selection.location, NSMaxRange(selection) <= NSMaxRange(body) {
                return .edit(written(wl: wl, over: selection))
            }
            if !onItsOwnLine, !holdsWL(kind) { return .refused(.mathsInCode) }
            return made(thing, at: after, in: text)
        }
    }

    /// Where "below this cell" is: under its answer, when it has one — a
    /// cell is never put between code and what it said.
    private static func below(_ cell: NSRange, in text: String) -> Int {
        NSMaxRange(EvalCells.out(after: cell, in: text)?.range ?? cell)
    }

    /// The lines between a fenced cell's two fences.
    private static func body(of cell: NSRange, in text: String) -> NSRange? {
        let ns = text as NSString
        guard NSMaxRange(cell) <= ns.length else { return nil }
        let open = ns.lineRange(for: NSRange(location: cell.location, length: 0))
        let start = min(NSMaxRange(open), NSMaxRange(cell))
        var end = NSMaxRange(cell)
        let last = ns.lineRange(for: NSRange(location: max(cell.location, NSMaxRange(cell) - 1), length: 0))
        if last.location > cell.location,
           ns.substring(with: last).trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            end = max(start, last.location - 1)
        }
        return NSRange(location: start, length: end - start)
    }

    private static func moved(_ selection: NSRange, by edit: MarkdownFormatting.Edit) -> NSRange {
        let change = (edit.replacement as NSString).length - edit.range.length
        if selection.location >= NSMaxRange(edit.range) {
            return NSRange(location: selection.location + change, length: selection.length)
        }
        return NSRange(location: min(selection.location, edit.range.location + (edit.replacement as NSString).length),
                       length: 0)
    }

    // MARK: - Where a cell goes

    /// The place a new cell is made: what comes out of the note first — the
    /// spaces at a cut, or a selection that is becoming the cell's content —
    /// with the cell going in where that was.
    private struct Spot {
        var removing: NSRange
        /// On an empty line of a run of them that is a cell of its own: the
        /// new cell takes that one line, and the lines either side stay the
        /// note's.
        var inBlankCell = false
    }

    /// Where a cell goes for a caret outside every fenced block.
    private static func spot(for caret: Int, in text: String, _ blocks: [PositionedBlock]) -> Spot {
        let ns = text as NSString
        let here = NSRange(location: caret, length: 0)
        guard let cell = blocks.first(where: { $0.range.location <= caret && caret <= NSMaxRange($0.range) }) else {
            return Spot(removing: here)
        }
        switch cell.block {
        case .blank:
            return Spot(removing: here, inBlankCell: true)
        case .paragraph:
            return paragraphSpot(caret, cell.range, ns)
        case .code:
            // Only its edges reach here: before the opening fence is above
            // it, after the closing one is below it.
            let at = caret <= cell.range.location ? cell.range.location : below(cell.range, in: text)
            return Spot(removing: NSRange(location: at, length: 0))
        default:
            return lineSpot(caret, ns)
        }
    }

    /// A paragraph is prose, and is cut where the caret is — but not into a
    /// half with nothing in it: at the front of its words the cell goes
    /// above, at the end of them below.
    private static func paragraphSpot(_ caret: Int, _ cell: NSRange, _ ns: NSString) -> Spot {
        let first = line(at: cell.location, ns)
        if caret <= first.location + wordsStart(ns.substring(with: first)) {
            return Spot(removing: NSRange(location: cell.location, length: 0))
        }
        let rest = ns.substring(with: NSRange(location: caret, length: NSMaxRange(cell) - caret))
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            return Spot(removing: NSRange(location: NSMaxRange(cell), length: 0))
        }
        // The spaces at the cut would only hang at the end of one half and
        // the front of the other; the front of a line is where a paragraph
        // keeps its indentation.
        var start = caret, end = caret
        while start > 0, isSpace(ns.character(at: start - 1)) { start -= 1 }
        while end < ns.length, isSpace(ns.character(at: end)) { end += 1 }
        return Spot(removing: NSRange(location: start, length: end - start))
    }

    /// A heading, a list, a quote, a rule: cut only between its lines, so
    /// no item's words are ever split and no marker is left behind.
    private static func lineSpot(_ caret: Int, _ ns: NSString) -> Spot {
        let here = line(at: caret, ns)
        let front = here.location + wordsStart(ns.substring(with: here))
        return Spot(removing: NSRange(location: caret <= front ? here.location : NSMaxRange(here), length: 0))
    }

    /// A selection taken out to be a block's content. The spaces at either
    /// cut go with it, and so does a marker or an indent left with no words
    /// after it: `- ` with its words gone is an empty bullet nobody asked
    /// for, so selecting an item's words takes the item.
    private static func selectionSpot(_ selection: NSRange, _ ns: NSString) -> Spot {
        var start = selection.location
        let first = line(at: start, ns)
        if start <= first.location + wordsStart(ns.substring(with: first)) {
            start = first.location
        } else {
            while start > first.location, isSpace(ns.character(at: start - 1)) { start -= 1 }
        }
        var end = NSMaxRange(selection)
        // Ending just past a newline is ending at the front of the next
        // line, whose indentation is its own.
        if end > 0, end > selection.location, ns.character(at: end - 1) != 10 {
            let last = line(at: end, ns)
            let rest = ns.substring(with: NSRange(location: end, length: NSMaxRange(last) - end))
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                end = NSMaxRange(last)
            } else {
                while end < NSMaxRange(last), isSpace(ns.character(at: end)) { end += 1 }
            }
        }
        return Spot(removing: NSRange(location: start, length: end - start))
    }

    /// The line `offset` is on, without its newline.
    private static func line(at offset: Int, _ ns: NSString) -> NSRange {
        var range = ns.lineRange(for: NSRange(location: min(max(offset, 0), ns.length), length: 0))
        if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
        return range
    }

    /// How far into a line its words start: past the indentation, the
    /// quote markers, and a heading's hashes or a list's marker — the box
    /// of a to-do with it. Every one of them is ASCII, so this counts in
    /// UTF-16 as the note does.
    static func wordsStart(_ line: String) -> Int {
        var rest = Substring(line)
        var count = 0
        func drop(_ n: Int) { rest = rest.dropFirst(n); count += n }
        drop(rest.prefix { $0 == " " || $0 == "\t" }.count)
        while rest.hasPrefix(">") {
            drop(1)
            drop(rest.prefix { $0 == " " }.count)
        }
        let hashes = rest.prefix { $0 == "#" }.count
        if (1...6).contains(hashes), rest.count == hashes || rest.dropFirst(hashes).hasPrefix(" ") {
            drop(hashes)
            if rest.hasPrefix(" ") { drop(1) }
            return count
        }
        if MarkdownParser.todoItem(String(rest)) != nil {
            drop(5)
            if rest.hasPrefix(" ") { drop(1) }
            return count
        }
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            drop(2)
            return count
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }.count
        if digits > 0, rest.dropFirst(digits).hasPrefix(". ") || rest.dropFirst(digits).hasPrefix(") ") {
            drop(digits + 2)
        }
        return count
    }

    private static func isSpace(_ character: unichar) -> Bool { character == 32 || character == 9 }

    // MARK: - Making it

    /// The new cell at `spot`, holding `content`: its text from
    /// `CellTypes.open` — the same builder the + on the bar uses — and its
    /// blank lines from `PreviewEditing.insertBlock`, handed back as one
    /// edit over the note.
    private static func made(_ thing: Thing, at spot: Spot, holding content: String = "",
                             in text: String) -> Outcome {
        let kind: CellTypes.Kind
        let written: String
        // Display maths is typed whole into a plain cell, and its caret
        // goes back over the closing fence onto the end of the WL.
        var back = 0
        switch thing {
        case .code(let language): kind = .code(language); written = content
        case .evaluation(let evaluator): kind = .evaluation(evaluator); written = content
        case .maths(let wl, onItsOwnLine: true):
            kind = .text
            written = MathMarkup.block(wl)
            back = ("\n```" as NSString).length
        case .maths(let wl, onItsOwnLine: false): kind = .text; written = MathMarkup.inline(wl)
        }
        let cell = CellTypes.open(kind, writing: written, in: "", at: 0)

        let result: String
        let start: Int
        if spot.inBlankCell {
            let ns = text as NSString
            let offset = spot.removing.location
            result = ns.substring(to: offset) + "\n" + cell.markdown + "\n" + ns.substring(from: offset)
            start = offset + 1
        } else {
            let (opened, at) = PreviewEditing.insertBlock(in: text, replacing: spot.removing)
            let ns = opened as NSString
            result = ns.substring(to: at) + cell.markdown + ns.substring(from: at)
            start = at
        }
        return .edit(edit(from: text, to: result, caret: start + cell.caret - back))
    }

    /// Inline maths at a caret: in the words, at the front of them when the
    /// caret is in a marker — and where there are no words, a plain cell of
    /// its own holding it.
    private static func inline(_ wl: String, at caret: Int, in text: String, _ blocks: [PositionedBlock]) -> Outcome {
        let ns = text as NSString
        let cell = blocks.first { $0.range.location <= caret && caret <= NSMaxRange($0.range) }
        switch cell?.block {
        case .paragraph?, .heading?, .bullets?, .dashes?, .todos?, .numbered?, .quote?:
            let here = line(at: caret, ns)
            let at = max(caret, here.location + wordsStart(ns.substring(with: here)))
            return .edit(written(wl: MathMarkup.inline(wl), over: NSRange(location: at, length: 0)))
        default:
            return made(.maths(wl, onItsOwnLine: false), at: spot(for: caret, in: text, blocks), in: text)
        }
    }

    /// Something written over a range in place, the caret after it.
    private static func written(wl: String, over range: NSRange) -> MarkdownFormatting.Edit {
        MarkdownFormatting.Edit(range: range, replacement: wl,
                                selection: NSRange(location: range.location + (wl as NSString).length, length: 0))
    }

    /// The palette's WL in its one spelling.
    private static func canonical(_ thing: Thing) -> Thing {
        guard case .maths(let wl, let onItsOwnLine) = thing else { return thing }
        return .maths(WLPrinter.canonical(wl.trimmingCharacters(in: .whitespacesAndNewlines)), onItsOwnLine: onItsOwnLine)
    }

    /// The one edit that turns `old` into `new`: what they share at both
    /// ends is left alone, so undo and the rendered page's cell ranges see
    /// only what changed. Never through the middle of a character that
    /// takes two UTF-16 units.
    private static func edit(from old: String, to new: String, caret: Int) -> MarkdownFormatting.Edit {
        let a = old as NSString, b = new as NSString
        let shortest = min(a.length, b.length)
        var prefix = 0
        while prefix < shortest, a.character(at: prefix) == b.character(at: prefix) { prefix += 1 }
        if prefix > 0, prefix < a.length, UTF16.isTrailSurrogate(a.character(at: prefix)) { prefix -= 1 }
        var suffix = 0
        while suffix < shortest - prefix,
              a.character(at: a.length - 1 - suffix) == b.character(at: b.length - 1 - suffix) { suffix += 1 }
        if suffix > 0, a.length - suffix > prefix, UTF16.isTrailSurrogate(a.character(at: a.length - suffix)) {
            suffix -= 1
        }
        return MarkdownFormatting.Edit(
            range: NSRange(location: prefix, length: a.length - prefix - suffix),
            replacement: b.substring(with: NSRange(location: prefix, length: b.length - prefix - suffix)),
            selection: NSRange(location: caret, length: 0))
    }
}
