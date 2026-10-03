import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// A note written with where the caret is in it: `‸` for a caret, `«…»`
/// round a selection. Neither turns up in a real note, which `|` and `[…]`
/// do — a to-do box, `Sqrt[2]`.
enum Marked {
    static func parse(_ marked: String) -> (text: String, selection: NSRange) {
        let ns = marked as NSString
        let caret = ns.range(of: "‸")
        if caret.location != NSNotFound {
            return (ns.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
        }
        let open = ns.range(of: "«"), close = ns.range(of: "»")
        precondition(open.location != NSNotFound && close.location != NSNotFound, marked)
        let inner = NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
        let text = ns.substring(to: open.location) + ns.substring(with: inner) + ns.substring(from: NSMaxRange(close))
        return (text, NSRange(location: open.location, length: inner.length))
    }

    static func show(_ text: String, _ selection: NSRange) -> String {
        let ns = text as NSString
        let selection = MarkdownFormatting.clamp(selection, to: ns.length)
        guard selection.length > 0 else {
            return ns.replacingCharacters(in: selection, with: "‸")
        }
        return ns.substring(to: selection.location) + "«" + ns.substring(with: selection) + "»"
            + ns.substring(from: NSMaxRange(selection))
    }
}

/// WHERE A BLOCK GOES, AND WHAT IT HOLDS — the one rule both panes ask.
///
/// Sean, 2026-10-02: "make math and code block insertion sensible..". Before
/// this, ⌘8 and the maths palette wrote their fences wherever the caret
/// was, one newline either side: the paragraph they landed in was glued to
/// them with no seam between, a list item came out as `- ban` and a stray
/// `ana`, a fence went inside a fence, and ⌘9 ignored the caret altogether.
final class InsertionPlacementTests: XCTestCase {
    /// A note with a cell of most kinds in it.
    static let note = "# Title\n\nOne two three four.\n\n- apple\n- banana\n\n> quoted line\n\nLast line."

    /// The note after, written the way the context was: `‸` where the caret
    /// landed. "refused" when nothing was done.
    static func after(_ thing: Insertion.Thing, _ marked: String, atBar: Bool = false) -> String {
        let (text, selection) = Marked.parse(marked)
        switch Insertion.insert(thing, in: text, at: selection, atBar: atBar) {
        case .refused: return "refused"
        case .edit(let edit):
            let applied = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
            return Marked.show(applied, edit.selection)
        }
    }

    private let python = Insertion.Thing.code(.python)

    // MARK: - A block lands as a cell of its own

    func testInAParagraphTheWholeParagraphBecomesTheBlock() {
        // Sean, 2026-10-03: "pressing cmd1-0 should change type of cell
        // cursor is currently in" — it was cut at the caret, the block
        // between the halves. Now the cell the caret is in IS the block,
        // holding its words, wherever in it the caret was.
        XCTAssertEqual(Self.after(python, "# Title\n\nOne two‸ three four.\n\nLast line."),
                       "# Title\n\n```python\nOne two three four.‸\n```\n\nLast line.")
        XCTAssertEqual(Self.after(python, "# Title\n\n‸One two.\n\nLast line."),
                       "# Title\n\n```python\nOne two.‸\n```\n\nLast line.")
        XCTAssertEqual(Self.after(python, "# Title\n\nOne two.‸\n\nLast line."),
                       "# Title\n\n```python\nOne two.‸\n```\n\nLast line.")
    }

    func testAParagraphOfSeveralLinesIsOneCell() {
        XCTAssertEqual(Self.after(python, "First line\n‸second line"),
                       "```python\nFirst line\nsecond line‸\n```")
        XCTAssertEqual(Self.after(python, "First line‸\nsecond line"),
                       "```python\nFirst line\nsecond line‸\n```")
    }

    func testNothingIsCutSoNoHalfCanReadAsSomethingElse() {
        // The review of 2026-10-02 had cuts leave a half that read as
        // something else ("- it was late." a list, "# 42" a heading, three
        // backticks a fence) and one marker in each half of a span. The
        // cell is no longer cut at all: every word goes into the block as
        // it was, spans whole.
        XCTAssertEqual(Self.after(python, "Use `npm‸ install` to set up."),
                       "```python\nUse `npm install` to set up.‸\n```")
        XCTAssertEqual(Self.after(python, "Some **bold‸ words** here."),
                       "```python\nSome **bold words** here.‸\n```")
        XCTAssertEqual(Self.after(python, "See [the ma‸nual](https://x.y) first."),
                       "```python\nSee [the manual](https://x.y) first.‸\n```")
        XCTAssertEqual(Self.after(python, "I went home‸ - it was late."),
                       "```python\nI went home - it was late.‸\n```")
        XCTAssertEqual(Self.after(python, "Ticket‸ # 42 is fixed."),
                       "```python\nTicket # 42 is fixed.‸\n```")
        XCTAssertEqual(Self.after(python, "Use‸ ```this``` here."),
                       "```python\nUse ```this``` here.‸\n```")
        XCTAssertEqual(Self.after(python, "Intro\n---‸ and more"),
                       "```python\nIntro\n--- and more‸\n```")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "**All bold‸ words**"), "**All bold`wl:Pi`‸ words**",
                       "inline maths is at home in bold")
        XCTAssertEqual(Self.after(.evaluation(.python), "**All bold‸ words**"),
                       "```eval python\n**All bold words**‸\n```")
    }

    func testAHeadingBecomesTheBlockHoldingItsWordsWithoutTheMarker() {
        XCTAssertEqual(Self.after(python, "# Ti‸tle\n\nWords."),
                       "```python\nTitle‸\n```\n\nWords.")
        XCTAssertEqual(Self.after(python, "‸# Title\n\nWords."),
                       "```python\nTitle‸\n```\n\nWords.")
    }

    func testAListOrAQuoteBecomesTheBlockHoldingItsLinesWithoutTheirMarkers() {
        // The list is one cell: every item's words, a line each.
        XCTAssertEqual(Self.after(python, "- app‸le\n- banana"), "```python\napple\nbanana‸\n```")
        XCTAssertEqual(Self.after(python, "- apple\n‸- banana"), "```python\napple\nbanana‸\n```")
        XCTAssertEqual(Self.after(python, "- [ ] milk‸\n- [ ] eggs"), "```python\nmilk\neggs‸\n```")
        XCTAssertEqual(Self.after(python, "> quo‸ted line\n\nAfter."), "```python\nquoted line‸\n```\n\nAfter.")
    }

    func testAnEmptyNoteAnEmptyLastLineAndTheEndsOfTheNote() {
        XCTAssertEqual(Self.after(python, "‸"), "```python\n‸\n```")
        XCTAssertEqual(Self.after(python, "Words.\n‸"), "Words.\n\n```python\n‸\n```")
        XCTAssertEqual(Self.after(python, Self.note + "\n‸"),
                       Self.note + "\n\n```python\n‸\n```",
                       "an empty last line is a place for a new cell")
        XCTAssertEqual(Self.after(python, Self.note + "‸"),
                       String(Self.note.dropLast("Last line.".count)) + "```python\nLast line.‸\n```",
                       "the end of the last paragraph is still in that paragraph")
    }

    func testOnAnEmptyLineOfABlankCellTheBlockTakesThatLineAndNoOther() {
        // A run of empty lines is the note's own content (Sean,
        // 2026-09-20: "one with 8 empty lines"): the block takes the line
        // the caret was on, and the lines either side stay — three empty
        // lines in the cell became one above it and one below. Spaced the
        // way a seam spaces a cell, it ate two more.
        XCTAssertEqual(Self.after(python, "Above.\n\n\n‸\n\n\nBelow."),
                       "Above.\n\n\n\n```python\n‸\n```\n\n\n\nBelow.")
        let after = "Above.\n\n\n\n```python\n\n```\n\n\n\nBelow."
        XCTAssertEqual(MarkdownParser.blocks(from: after),
                       [.paragraph("Above."), .blank(lines: 1), .code(language: "python", body: ""),
                        .blank(lines: 1), .paragraph("Below.")])
    }

    func testAtTheBarItIsMadeThereAndKeepsItsLanguage() {
        // ⌘8 at a bar used to drop the language picked under the button:
        // the + offers one plain Code Block and the bar went the +'s way.
        XCTAssertEqual(Self.after(python, "One.\n\n‸Two.", atBar: true),
                       "One.\n\n```python\n‸\n```\n\nTwo.")
        XCTAssertEqual(Self.after(.code(.plain), "One.\n\n‸Two.", atBar: true),
                       "One.\n\n```\n‸\n```\n\nTwo.")
        XCTAssertEqual(Self.after(python, "One.‸", atBar: true),
                       "One.\n\n```python\n‸\n```")
    }

    // MARK: - A selection becomes what the block holds

    func testCodeTakesTheSelectionVerbatimAndWhatIsEitherSideStaysACell() {
        XCTAssertEqual(Self.after(python, "One «two three» four."),
                       "One\n\n```python\ntwo three‸\n```\n\nfour.")
        XCTAssertEqual(Self.after(python, "# Title\n\n«One two three four.»\n\nLast."),
                       "# Title\n\n```python\nOne two three four.‸\n```\n\nLast.")
        XCTAssertEqual(Self.after(python, "Above.\n\n«- apple\n- banana»\n\nBelow."),
                       "Above.\n\n```python\n- apple\n- banana‸\n```\n\nBelow.")
    }

    func testAnItemsWordsSelectedTakeTheItemAndLeaveNoEmptyMarkerBehind() {
        XCTAssertEqual(Self.after(python, "- apple\n- «banana»\n\nAfter."),
                       "- apple\n\n```python\nbanana‸\n```\n\nAfter.")
    }

    func testPartOfAnItemsWordsSelectedLeavesTheItemItsMarkerAndTheRest() {
        // The review of 2026-10-02: selecting the FRONT of an item's words
        // took its marker with them, and the words left behind came out a
        // plain paragraph — "# Big Title" with "Big" made code left
        // "Title" a paragraph, "milk" lost its box. The item is cut only
        // between its lines, as it is for a caret: what is left keeps its
        // marker, and the block goes above the line — or, from the middle
        // of the words, below it.
        XCTAssertEqual(Self.after(python, "# «Big» Title\n\nWords."),
                       "```python\nBig‸\n```\n\n# Title\n\nWords.")
        XCTAssertEqual(Self.after(python, "- «big» red apple\n- banana"),
                       "```python\nbig‸\n```\n\n- red apple\n- banana")
        XCTAssertEqual(Self.after(python, "- [ ] «buy» milk"), "```python\nbuy‸\n```\n\n- [ ] milk")
        XCTAssertEqual(Self.after(python, "> «quoted» line"), "```python\nquoted‸\n```\n\n> line")
        XCTAssertEqual(Self.after(python, "- apple\n- big «red» apple\n- banana"),
                       "- apple\n- big apple\n\n```python\nred‸\n```\n\n- banana")
        XCTAssertEqual(Self.after(.maths("Sqrt[x]", onItsOwnLine: true), "- «x» is the side"),
                       "```wl\nSqrt[x]‸\n```\n\n- is the side")
    }

    func testASelectionOfASpansWordsTakesItsMarkersWithIt() {
        // Left behind, `**` and `**` were two paragraphs of nothing but
        // markers either side of the block.
        XCTAssertEqual(Self.after(python, "Some **«bold words»** here."),
                       "Some\n\n```python\nbold words‸\n```\n\nhere.")
        XCTAssertEqual(Self.after(.maths("Sqrt[x^2]", onItsOwnLine: true), "Area `«x^2»` here."),
                       "Area\n\n```wl\nSqrt[x^2]‸\n```\n\nhere.")
    }

    func testASelectionWithAFenceInItIsRefusedRatherThanNested() {
        XCTAssertEqual(Self.after(python, "One «two\n\n```wl\nSqrt»[2]\n```"), "refused")
    }

    // MARK: - Inside a fenced block

    func testCodeInsideCodeDoesNothingAndSaysWhy() {
        let (text, caret) = Marked.parse("```python\nprint(‸1)\n```")
        XCTAssertEqual(Insertion.insert(python, in: text, at: caret, atBar: false), .refused(.codeInCode))
        XCTAssertFalse(Insertion.Refusal.codeInCode.message.isEmpty)
    }

    func testCodeInsideAnotherKindOfBlockGoesAfterIt() {
        XCTAssertEqual(Self.after(python, "```wl\nSqrt[‸2]\n```\n\nAfter."),
                       "```wl\nSqrt[2]\n```\n\n```python\n‸\n```\n\nAfter.")
        // AFTER ITS ANSWER, never between a cell and what it said.
        XCTAssertEqual(Self.after(python, "```eval python\nx‸ = 1\n```\n\n```out\n1\n```\n\nAfter."),
                       "```eval python\nx = 1\n```\n\n```out\n1\n```\n\n```python\n‸\n```\n\nAfter.")
    }

    func testAtTheEndOfAnUnclosedFenceTheCaretIsInItAndABlockAfterItClosesItFirst() {
        // The review of 2026-10-02: the caret at the end of a fence still
        // being typed — where it sits while typing one — was not "in" it,
        // and anything written after a fence with no closing line BECAME
        // its closing line: ```eval python shut the python block and its
        // own closing fence opened one that ran to the end of the note.
        XCTAssertEqual(Self.after(.evaluation(.python), "```python\nprint(1)‸"), "```eval python\nprint(1)‸")
        let (text, caret) = Marked.parse("```python\nprint(1)‸")
        XCTAssertEqual(Insertion.insert(python, in: text, at: caret, atBar: false), .refused(.codeInCode))
        XCTAssertEqual(Self.after(.maths("Sqrt[x]", onItsOwnLine: true), "```python\nprint(‸1)"),
                       "```python\nprint(1)\n```\n\n```wl\nSqrt[x]‸\n```")
        XCTAssertEqual(Self.after(python, "```eval wl\nN[Pi]\n‸"),
                       "```eval wl\nN[Pi]\n```\n\n```python\n‸\n```")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: true), "```wl\nx + ‸"), "```wl\nx + Pi‸")
    }

    func testMathsIntoAMathsBlockWithNoLineBetweenItsFencesGetsOne() {
        // Written at the caret it went ON a fence line — "```wlPi", or
        // "Pi```", which is no closing fence at all.
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: true), "```wl‸"), "```wl\nPi‸")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "```wl\n‸```"), "```wl\nPi‸\n```")
    }

    func testBelowACellThatHasAnAnswerMeansBelowTheAnswer() {
        XCTAssertEqual(Self.after(.code(.plain), "```eval python\nx = 1\n```‸\n\n```out\n1\n```"),
                       "```eval python\nx = 1\n```\n\n```out\n1\n```\n\n```\n‸\n```")
    }

    // MARK: - ⌘9

    func testAnEvaluationCellFollowsTheSamePlacement() {
        XCTAssertEqual(Self.after(.evaluation(.python), "One two‸ three four."),
                       "```eval python\nOne two three four.‸\n```")
        XCTAssertEqual(Self.after(.evaluation(.python), "One two three four.‸\n\nNext."),
                       "```eval python\nOne two three four.‸\n```\n\nNext.")
        XCTAssertEqual(Self.after(.evaluation(.wolfram), "One.\n\n‸Two.", atBar: true),
                       "One.\n\n```eval wl\n‸\n```\n\nTwo.")
        XCTAssertEqual(Self.after(.evaluation(.python), "One «two three» four."),
                       "One\n\n```eval python\ntwo three‸\n```\n\nfour.")
        XCTAssertEqual(Self.after(.evaluation(.cpp), "‸"), "```eval c++\n‸\n```")
    }

    func testInACodeCellItTurnsThatCellIntoOneAndTheCaretStaysPut() {
        // Sean, 2026-09-21: "cmd+9 should start a new cell or turn the
        // existing cell to an evaluation cell" — unchanged, except that
        // the caret is no longer thrown onto the fence line.
        XCTAssertEqual(Self.after(.evaluation(.python), "Notes.\n\n```python\nprint(‸1)\n```"),
                       "Notes.\n\n```eval python\nprint(‸1)\n```")
        XCTAssertEqual(Self.after(.evaluation(.python), "```eval wl\nx‸\n```"),
                       "```eval python\nx‸\n```")
    }

    func testInACellThatAlreadyRunsThereItDoesNothingAndSaysSo() {
        let (text, caret) = Marked.parse("```eval python\nx‸ = 1\n```")
        XCTAssertEqual(Insertion.insert(.evaluation(.python), in: text, at: caret, atBar: false),
                       .refused(.alreadyEvaluates(.python)))
        XCTAssertTrue(Insertion.Refusal.alreadyEvaluates(.python).message.contains("Python"))
    }

    func testInAnAnswerANewCellGoesUnderTheAnswerAndTheAnswerIsLeftAlone() {
        // It used to turn the ANSWER into an evaluation cell.
        XCTAssertEqual(Self.after(.evaluation(.python), "```eval python\nx = 1\n```\n\n```out\n‸1\n```\n\nAfter."),
                       "```eval python\nx = 1\n```\n\n```out\n1\n```\n\n```eval python\n‸\n```\n\nAfter.")
    }

    // MARK: - Maths on its own line

    func testDisplayMathsIsPlacedLikeAnyOtherBlockWithTheCaretAtTheEndOfItsWL() {
        XCTAssertEqual(Self.after(.maths("Sqrt[x]", onItsOwnLine: true), "One two‸ three four."),
                       "One two\n\n```wl\nSqrt[x]‸\n```\n\nthree four.")
        XCTAssertEqual(Self.after(.maths("Sqrt[x]", onItsOwnLine: true), "One.\n\n‸Two.", atBar: true),
                       "One.\n\n```wl\nSqrt[x]‸\n```\n\nTwo.")
    }

    func testASelectionThatReadsAsMathsIsTheMathsAndIsReplacedByIt() {
        XCTAssertEqual(Self.after(.maths("Sqrt[x^2 + 1]", onItsOwnLine: true), "Area «x^2 + 1» here."),
                       "Area\n\n```wl\nSqrt[x^2 + 1]‸\n```\n\nhere.")
    }

    func testSelectedWordsAreNeverThrownAwayTheMathsGoesAfterThem() {
        // It used to REPLACE them: select "two three", pick π, and the
        // words were gone with nothing on screen to say where.
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: true), "One «two three» four."),
                       "One two three\n\n```wl\nPi‸\n```\n\nfour.")
    }

    func testMathsInsideABlockOfWolframLanguageGoesInAsTheBareWL() {
        // A maths block IS WL: a fence or a code span inside it is
        // garbage, and the palette's ∑ and α are what composing one needs.
        XCTAssertEqual(Self.after(.maths("\\[Alpha]", onItsOwnLine: true), "```wl\nSqrt[«2»]\n```"),
                       "```wl\nSqrt[\\[Alpha]‸]\n```")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "```wl\nx + ‸\n```"),
                       "```wl\nx + Pi‸\n```")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: true), "```eval wl\nN[‸]\n```"),
                       "```eval wl\nN[Pi‸]\n```")
    }

    func testDisplayMathsInsideCodeGoesAfterIt() {
        XCTAssertEqual(Self.after(.maths("Sqrt[x]", onItsOwnLine: true), "```python\nprint(‸1)\n```\n\nAfter."),
                       "```python\nprint(1)\n```\n\n```wl\nSqrt[x]‸\n```\n\nAfter.")
    }

    // MARK: - Maths inline

    func testInlineMathsStaysInTheSentence() {
        XCTAssertEqual(Self.after(.maths("Sqrt[x]", onItsOwnLine: false), "One two ‸three."),
                       "One two `wl:Sqrt[x]`‸three.")
        XCTAssertEqual(Self.after(.maths("Sqrt[x^2 + 1]", onItsOwnLine: false), "Area «x^2 + 1» here."),
                       "Area `wl:Sqrt[x^2 + 1]`‸ here.")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "One «two three» four."),
                       "One two three`wl:Pi`‸ four.")
    }

    func testInlineMathsNeverGoesInFrontOfAMarker() {
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "#‸ Title"), "# `wl:Pi`‸Title")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "‸- apple"), "- `wl:Pi`‸apple")
    }

    func testInlineMathsWhereThereAreNoWordsIsACellOfItsOwn() {
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "One.\n\n‸Two.", atBar: true),
                       "One.\n\n`wl:Pi`‸\n\nTwo.")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "‸"), "`wl:Pi`‸")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "```python\nx\n```‸\n\nAfter."),
                       "```python\nx\n```\n\n`wl:Pi`‸\n\nAfter.")
    }

    func testMathsInAMathsSpanIsThatSpansAndInACodeSpanIsRefused() {
        // The review of 2026-10-02: inline maths at a caret in a `wl:` span
        // wrote a code span inside the code span. A `wl:` span is maths the
        // way a ```wl block is, and gets the bare WL; any other code span
        // is code, and refuses it.
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: false), "Area `wl:x^2 + ‸` here."),
                       "Area `wl:x^2 + Pi‸` here.")
        XCTAssertEqual(Self.after(.maths("Pi", onItsOwnLine: true), "Area `wl:x^2 + ‸` here."),
                       "Area `wl:x^2 + Pi‸` here.")
        XCTAssertEqual(Self.after(.maths("Sqrt[x^2]", onItsOwnLine: false), "Area `wl:«x^2»` here."),
                       "Area `wl:Sqrt[x^2]‸` here.")
        for marked in ["Run `npm‸ install` first.", "Run `«npm»` first."] {
            let (text, selection) = Marked.parse(marked)
            XCTAssertEqual(Insertion.insert(.maths("Pi", onItsOwnLine: false), in: text, at: selection, atBar: false),
                           .refused(.mathsInCode), marked)
        }
    }

    func testInlineMathsInsideCodeIsRefused() {
        let (text, caret) = Marked.parse("```python\nprint(‸1)\n```")
        XCTAssertEqual(Insertion.insert(.maths("Pi", onItsOwnLine: false), in: text, at: caret, atBar: false),
                       .refused(.mathsInCode))
    }

    // MARK: - Every context, every command

    /// Whatever the context, a block that went in is a cell of its own:
    /// the note parses to the cells it had, cut where the caret was, plus
    /// exactly the one that was made — and none of the old cells' words
    /// went missing.
    func testEveryBlockLandsAsExactlyOneNewCellAndNoWordIsLost() {
        let contexts = [
            "# Title\n\nOne two‸ three four.\n\n- apple\n- banana\n\n> quoted line\n\nLast line.",
            "# Title\n\n‸One two three four.\n\n- apple",
            "# Ti‸tle\n\nOne.",
            "One.\n\n- apple\n- ban‸ana\n- cherry",
            "One.\n\n> quo‸ted\n> line two",
            "‸",
            "Words.\n‸",
            "Above.\n\n\n‸\n\n\nBelow.",
            "‸# Title",
            "# Title\n\nLast line.‸",
            "One «two three» four.\n\nNext.",
            "Above.\n\n«- apple\n- banana»\n\nBelow.",
        ]
        let things: [Insertion.Thing] = [.code(.python), .code(.plain), .evaluation(.wolfram),
                                         .maths("Sqrt[x]", onItsOwnLine: true)]
        for context in contexts {
            let (text, selection) = Marked.parse(context)
            let before = MarkdownParser.positioned(from: text)
            for thing in things {
                guard case .edit(let edit) = Insertion.insert(thing, in: text, at: selection, atBar: false) else {
                    XCTFail("\(thing) refused in \(context)"); continue
                }
                let applied = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
                let cells = MarkdownParser.positioned(from: applied)
                let fences = cells.filter { if case .code = $0.block { return true } else { return false } }
                XCTAssertEqual(fences.count, 1, "\(thing) in \(context): \(applied.debugDescription)")
                // The caret is inside the new cell, where typing goes.
                if let made = fences.first {
                    XCTAssertTrue(made.range.location < edit.selection.location
                                  && edit.selection.location < NSMaxRange(made.range),
                                  "\(thing) in \(context): the caret is not in the block")
                }
                // At a caret, the cell it is in becomes the block (the same
                // number of cells), or one more is made; a cell is cut at
                // most once. (A selection takes whole cells into the block,
                // so it can be fewer.)
                if selection.length == 0 {
                    XCTAssertTrue((before.count...before.count + 2).contains(cells.count),
                                  "\(thing) in \(context): \(applied.debugDescription)")
                }
                // Not one word lost.
                func words(_ s: String) -> [String] {
                    s.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                }
                let kept = words(applied)
                for word in words(text) {
                    XCTAssertTrue(kept.contains(word), "\(thing) in \(context) lost \(word)")
                }
            }
        }
    }
}

/// Whether a selection reads as maths — and so whether the palette starts
/// from it, and whether the maths may stand in its place.
final class MathSelectionTests: XCTestCase {
    func testWLReadsAsMathsAndWordsDoNot() {
        XCTAssertEqual(MathSelection.reading("x^2 + 1"), "x^2 + 1")
        XCTAssertEqual(MathSelection.reading(" x^2+1 "), "x^2 + 1", "in the one spelling the palette writes")
        XCTAssertEqual(MathSelection.reading("Sin[x]"), "Sin[x]")
        XCTAssertEqual(MathSelection.reading("x"), "x")
        XCTAssertEqual(MathSelection.reading("\\[Alpha] + b"), "\\[Alpha] + b")
        XCTAssertNotNil(MathSelection.reading("Pi r^2"))
        // WL reads "the area" as the product of two symbols. It is words.
        XCTAssertNil(MathSelection.reading("the area"))
        XCTAssertNil(MathSelection.reading("area"))
        XCTAssertNil(MathSelection.reading("f(x) = 2x"), "not WL, so not something the palette can set")
        XCTAssertNil(MathSelection.reading(""))
        XCTAssertNil(MathSelection.reading("x\ny"))
    }

    func testALineTakenWithItsNewlineReadsAsMathsAndIsReplaced() {
        // The review of 2026-10-02: a triple-click takes the line's own
        // newline with it, and the newline made the selection read as
        // words — so the palette did not start from it, and the maths
        // went in under a line it should have replaced.
        XCTAssertEqual(MathSelection.reading("x^2 + 1\n"), "x^2 + 1")
        XCTAssertNil(MathSelection.reading("x\ny\n"), "a newline in the middle is still two lines")
        let note = "Before.\n\nx^2 + 1\n\nAfter."
        XCTAssertEqual(MathSelection.seed(in: note, selection: NSRange(location: 9, length: 8)),
                       MathSelection.Seed(wl: "x^2 + 1", inline: false))
        XCTAssertEqual(InsertionPlacementTests.after(.maths("Sqrt[x^2 + 1]", onItsOwnLine: true),
                                                     "Before.\n\n«x^2 + 1\n»\nAfter."),
                       "Before.\n\n```wl\nSqrt[x^2 + 1]‸\n```\n\nAfter.")
        XCTAssertEqual(InsertionPlacementTests.after(.maths("Sqrt[x^2 + 1]", onItsOwnLine: false),
                                                     "Before.\n\n«x^2 + 1\n»\nAfter."),
                       "Before.\n\n`wl:Sqrt[x^2 + 1]`‸\n\nAfter.")
    }

    func testMathsHoldsASelectionOnlyWhenItIsInsideIt() {
        XCTAssertTrue(MathSelection.holds("Sqrt[x^2 + 1]", selected: "x^2+1"))
        XCTAssertTrue(MathSelection.holds("x^2 + 1", selected: "x^2 + 1"))
        XCTAssertFalse(MathSelection.holds("Max[a]", selected: "x"), "a letter of a name is not the selection")
        XCTAssertFalse(MathSelection.holds("Pi", selected: "x"))
        XCTAssertFalse(MathSelection.holds("Pi", selected: "two three"))
    }

    func testTheSeedIsTheSelectionAndSaysWhetherItSitsInALine() {
        let line = "Area x^2 + 1 here."
        let inside = MathSelection.seed(in: line, selection: NSRange(location: 5, length: 7))
        XCTAssertEqual(inside, MathSelection.Seed(wl: "x^2 + 1", inline: true))
        let whole = MathSelection.seed(in: "Before.\n\nx^2 + 1\n\nAfter.", selection: NSRange(location: 9, length: 7))
        XCTAssertEqual(whole, MathSelection.Seed(wl: "x^2 + 1", inline: false))
        XCTAssertNil(MathSelection.seed(in: line, selection: NSRange(location: 5, length: 0)))
        XCTAssertNil(MathSelection.seed(in: line, selection: NSRange(location: 0, length: 4)), "words")
    }

    func testAShapePickedAfterwardsTakesTheSelectionIntoItsFirstSlot() {
        let sqrt = MathTemplate.all.first { $0.id == "sqrt" }!
        XCTAssertEqual(sqrt.values(seed: "x^2 + 1"), ["x^2 + 1"])
        XCTAssertEqual(sqrt.wl(sqrt.values(seed: "x^2 + 1")), "Sqrt[x^2 + 1]")
        let sum = MathTemplate.all.first { $0.id == "sum" }!
        XCTAssertEqual(sum.values(seed: "1/k"), ["1/k", "i", "1", "n"])
        XCTAssertEqual(sum.values(seed: nil), sum.initialValues)
        let pi = MathTemplate.all.first { $0.id == "pi" }!
        XCTAssertEqual(pi.values(seed: "x"), [], "a symbol has nowhere to put it")
    }
}

/// The source pane: the bridge applies what `Insertion` says through the
/// text view, so the note, the caret and ONE undo step all come out right.
final class SourceInsertionTests: XCTestCase {
    /// The text view's own undo stack, grouped BY HAND: in the app the end
    /// of every event closes a group, and a test has no events. Left to
    /// group by event, a whole test is one group and one undo takes
    /// everything in it, which proves nothing about a step.
    final class Undoer: NSObject, NSTextViewDelegate {
        let manager: UndoManager = {
            let manager = UndoManager()
            manager.groupsByEvent = false
            return manager
        }()
        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    private var undoer = Undoer()

    private func pane(_ marked: String, bar: Bool = false) -> (PasteAwareTextView, EditorBridge) {
        let (text, selection) = Marked.parse(marked)
        let view = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        view.allowsUndo = true
        view.delegate = undoer
        view.string = text
        view.setSelectedRange(selection)
        if bar { view.armedSeam = selection.location }
        let bridge = EditorBridge()
        bridge.textView = view
        return (view, bridge)
    }

    /// One event's worth: a keystroke, a menu command.
    private func event(_ body: () -> Void) {
        undoer.manager.beginUndoGrouping()
        body()
        undoer.manager.endUndoGrouping()
    }

    private func type(_ text: String, in view: NSTextView) {
        event { view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    }

    func testThePaneEndsWhereTheRuleSaysWithTheCaretInTheBlock() {
        let (view, bridge) = pane("# Title\n\nOne two‸ three four.")
        event { bridge.codeBlock(.python) }
        XCTAssertEqual(Marked.show(view.string, view.selectedRange()),
                       "# Title\n\n```python\nOne two three four.‸\n```")
    }

    func testOneUndoTakesTheWholeInsertionBackAndNothingElse() {
        let (view, bridge) = pane("Words‸\n\nNext.")
        type(" here", in: view)
        event { bridge.codeBlock(.python) }
        type("x", in: view)
        XCTAssertEqual(view.string, "```python\nWords herex\n```\n\nNext.")
        undoer.manager.undo()
        XCTAssertEqual(view.string, "```python\nWords here\n```\n\nNext.", "what was typed in it goes first")
        undoer.manager.undo()
        XCTAssertEqual(view.string, "Words here\n\nNext.", "then the block, whole, and nothing typed before it")
    }

    func testAtABarOneUndoPutsTheNoteBackExactly() {
        // The bar's own builder registered its change twice: one ⌘Z left
        // the note half undone mid-note and threw at the end of it.
        for (marked, thing) in [("One.\n\n‸Two.", 0), ("One.\n\nTwo.‸", 0), ("One.\n\n‸Two.", 1), ("One.\n\nTwo.‸", 2)] {
            let (view, bridge) = pane(marked, bar: true)
            let original = view.string
            event {
                switch thing {
                case 0: bridge.codeBlock(.python)
                case 1: bridge.insertMath("Pi", display: true)
                default: bridge.evaluationCell(.python)
                }
            }
            XCTAssertNotEqual(view.string, original, marked)
            XCTAssertNil(view.armedSeam, "the caret has taken over from the bar")
            undoer.manager.undo()
            XCTAssertEqual(view.string, original, "\(marked) #\(thing)")
        }
    }

    func testWhatTheBarOpensComesOutWithOneUndoAndNothingThrows() {
        // Typing at the bar under the last cell: the opening and the
        // character, and ⌘Z back to the note as it was.
        let (view, _) = pane("One.\n\nTwo.‸", bar: true)
        type("x", in: view)
        XCTAssertEqual(view.string, "One.\n\nTwo.\n\nx")
        undoer.manager.undo()
        XCTAssertEqual(view.string, "One.\n\nTwo.")
        // And a kind named at a bar mid-note.
        let (titled, bridge) = pane("One.\n\n‸Two.", bar: true)
        event { bridge.heading(.title) }
        XCTAssertEqual(titled.string, "One.\n\n# \n\nTwo.")
        undoer.manager.undo()
        XCTAssertEqual(titled.string, "One.\n\nTwo.")
    }

    func testARefusalWritesNothingAndSaysWhyInTheFooter() {
        let (view, bridge) = pane("```python\nprint(‸1)\n```")
        var said: [String] = []
        bridge.say = { said.append($0) }
        bridge.codeBlock(.python)
        XCTAssertEqual(view.string, "```python\nprint(1)\n```")
        XCTAssertEqual(said, [Insertion.Refusal.codeInCode.message])
    }

    func testTheSelectionReadsAsTheSeedForThePalette() {
        let (_, bridge) = pane("Area «x^2 + 1» here.")
        XCTAssertEqual(bridge.mathsSeed(), MathSelection.Seed(wl: "x^2 + 1", inline: true))
    }
}

/// The rendered page asks the same rule with the same note and the same
/// caret — read out of whichever cell is open — and opens the cell the
/// caret landed in.
final class RenderedInsertionSpotTests: XCTestCase {
    private let note = "# Title\n\nOne two.\n\n```python\nprint(1)\n```\n\n- [ ] milk"

    func testAnOpenCellsCaretIsItsPlaceInTheNote() {
        let words = MarkdownPreview.insertionSpot(in: note, cursor: .cell(NSRange(location: 9, length: 8)),
                                                  fence: nil, inEditor: NSRange(location: 3, length: 0),
                                                  bar: nil, held: [])
        XCTAssertEqual(words.selection, NSRange(location: 12, length: 0))
        XCTAssertFalse(words.atBar)
        // A code cell's editor holds the code alone: its fence line is
        // ahead of everything the editor counts.
        let code = MarkdownPreview.insertionSpot(in: note, cursor: .cell(NSRange(location: 19, length: 22)),
                                                 fence: MarkdownPreview.Fence(open: "```python", close: "```"),
                                                 inEditor: NSRange(location: 6, length: 1), bar: nil, held: [])
        XCTAssertEqual(code.selection, NSRange(location: 19 + 10 + 6, length: 1))
        XCTAssertEqual((note as NSString).substring(with: code.selection), "1")
        // One reminder of a checklist holds its words alone.
        let item = MarkdownPreview.insertionSpot(in: note, cursor: .item(NSRange(location: 49, length: 4)),
                                                 fence: nil, inEditor: NSRange(location: 4, length: 0),
                                                 bar: nil, held: [])
        XCTAssertEqual(item.selection, NSRange(location: 53, length: 0))
    }

    func testTheBarHeldCellsAndNothingOpen() {
        let bar = MarkdownPreview.insertionSpot(in: note, cursor: .none, fence: nil, inEditor: nil,
                                                bar: 19, held: [])
        XCTAssertEqual(bar.selection, NSRange(location: 19, length: 0))
        XCTAssertTrue(bar.atBar)
        let held = MarkdownPreview.insertionSpot(in: note, cursor: .none, fence: nil, inEditor: nil, bar: nil,
                                                 held: [NSRange(location: 19, length: 22), NSRange(location: 9, length: 8)])
        XCTAssertEqual(held.selection, NSRange(location: 9, length: 8), "the first held cell, whole")
        // Nothing open: where `openSomething` would open — the end of the
        // first cell, where its caret goes.
        let none = MarkdownPreview.insertionSpot(in: note, cursor: .none, fence: nil, inEditor: nil, bar: nil, held: [])
        XCTAssertEqual(none.selection, NSRange(location: 7, length: 0))
        XCTAssertEqual(MarkdownPreview.insertionSpot(in: "", cursor: .none, fence: nil, inEditor: nil,
                                                     bar: nil, held: []).selection,
                       NSRange(location: 0, length: 0))
    }

    func testTheLandingIsTheNewCellOpenedAsItsCodeWithTheCaretInside() {
        let made = "One\n\n```python\n\n```\n\ntwo."
        let landing = MarkdownPreview.landing(at: 15, in: made)
        XCTAssertEqual(landing.cell, NSRange(location: 5, length: 14))
        XCTAssertEqual(landing.caret, 0, "on the empty line between the fences, the code's first character")
        let maths = "```wl\nSqrt[x]\n```"
        XCTAssertEqual(MarkdownPreview.landing(at: 13, in: maths).caret, 7, "at the end of the WL")
        let words = "One `wl:Pi` two."
        XCTAssertEqual(MarkdownPreview.landing(at: 11, in: words).cell, NSRange(location: 0, length: 16))
        XCTAssertEqual(MarkdownPreview.landing(at: 11, in: words).caret, 11)
    }

    func testAnEditInsideTheOpenCellsWordsGoesThroughItsEditor() {
        // Inline maths and the bare WL keep the cell one cell, so they go
        // through the open editor and its own undo; anything that makes a
        // cell is the note's.
        let inline = MarkdownFormatting.Edit(range: NSRange(location: 12, length: 0), replacement: "`wl:Pi`",
                                             selection: NSRange(location: 19, length: 0))
        XCTAssertEqual(MarkdownPreview.editorEdit(inline, cursor: .cell(NSRange(location: 9, length: 8)),
                                                  fence: nil, draftLength: 8),
                       MarkdownFormatting.Edit(range: NSRange(location: 3, length: 0), replacement: "`wl:Pi`",
                                               selection: NSRange(location: 10, length: 0)))
        let block = MarkdownFormatting.Edit(range: NSRange(location: 12, length: 0), replacement: "\n\n```\n\n```\n\n",
                                            selection: NSRange(location: 18, length: 0))
        XCTAssertNil(MarkdownPreview.editorEdit(block, cursor: .cell(NSRange(location: 9, length: 8)),
                                                fence: nil, draftLength: 8))
        XCTAssertNil(MarkdownPreview.editorEdit(inline, cursor: .none, fence: nil, draftLength: 0))
    }

    /// The same contexts through both panes: the source pane's caret IS the
    /// note's, the rendered page reads its own out of the open cell.
    func testBothPanesComeOutTheSame() {
        let contexts = ["# Title\n\nOne two‸ three.", "# Title\n\nOne «two» three.",
                        "- apple\n- ban‸ana", "```python\nx‸\n```\n\nAfter.", "```wl\nSqrt[‸2]\n```"]
        let things: [Insertion.Thing] = [.code(.python), .evaluation(.python),
                                         .maths("Pi", onItsOwnLine: true), .maths("Pi", onItsOwnLine: false)]
        for context in contexts {
            let (text, selection) = Marked.parse(context)
            guard let cell = NotebookCells.block(containing: selection.location, in: text)?.range else {
                XCTFail(context); continue
            }
            let source = (text as NSString).substring(with: cell)
            let parts = MarkdownFormatting.fenced(source)
            let fence = parts.map { MarkdownPreview.Fence(open: $0.open, close: $0.close) }
            let lead = parts.map { ($0.open as NSString).length + 1 } ?? 0
            let inEditor = NSRange(location: selection.location - cell.location - lead, length: selection.length)
            let spot = MarkdownPreview.insertionSpot(in: text, cursor: .cell(cell), fence: fence,
                                                     inEditor: inEditor, bar: nil, held: [])
            XCTAssertEqual(spot.selection, selection, context)
            for thing in things {
                let view = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
                view.string = text
                view.setSelectedRange(selection)
                let bridge = EditorBridge()
                bridge.textView = view
                switch thing {
                case .code(let language): bridge.codeBlock(language)
                case .evaluation(let evaluator): bridge.evaluationCell(evaluator)
                case .maths(let wl, let own): bridge.insertMath(wl, display: own)
                }
                let page = Insertion.insert(thing, in: text, at: spot.selection, atBar: spot.atBar)
                guard case .edit(let edit) = page else {
                    XCTAssertEqual(view.string, text, "refused in one pane, written in the other: \(context)")
                    continue
                }
                let rendered = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
                XCTAssertEqual(view.string, rendered, "\(thing) in \(context)")
                XCTAssertEqual(view.selectedRange(), edit.selection, "\(thing) in \(context)")
            }
        }
    }
}

/// The rendered page itself, hosted: the cell is made where the caret was,
/// it opens as code with the caret in it, and one ⌘Z takes it back.
final class RenderedInsertionTests: XCTestCase {
    /// The note as `NoteStore` holds it: published, so the page redraws
    /// when it changes, the way it does in the app.
    final class Note: ObservableObject {
        @Published var text: String
        init(_ text: String) { self.text = text }
    }

    struct Page: View {
        @ObservedObject var note: Note
        let bridge: EditorBridge
        var body: some View { MarkdownPreview(markdown: $note.text, bridge: bridge).frame(width: 500, height: 600) }
    }

    private var window: NSWindow!
    private var note: Note!
    private var bridge: EditorBridge!

    private func host(_ text: String) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        note = Note(text)
        bridge = EditorBridge()
        window.contentView = NSHostingView(rootView: Page(note: note, bridge: bridge))
        settle()
    }

    override func tearDown() {
        window?.contentView = nil
        window?.close()
    }

    private func settle(_ seconds: TimeInterval = 0.3) {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// One keystroke's worth of undo, as a group of its own. In the app the
    /// end of its event closes the group the keystroke opened; a test has
    /// no events, so that group stayed open and the next thing registered
    /// joined it — one ⌘Z took both (see `SourceInsertionTests.Undoer`).
    /// So it is grouped by hand, with the grouping by event OFF while it
    /// is: on, beginning a group opens the event's own first and nests in
    /// it, and ending that one by hand leaves the undo manager sure it is
    /// still in it — it throws at the next registration.
    private func keystroke(in view: NSTextView, _ body: () -> Void) {
        guard let undo = view.undoManager else { return body() }
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
        undo.groupsByEvent = true
    }

    /// The first cell open, the caret `at` into it.
    private func openTheFirstCell(caret at: Int) -> BlockTextView? {
        XCTAssertEqual(bridge.ensureEditing?(), true)
        settle()
        guard let open = bridge.textView as? BlockTextView else { return nil }
        open.setSelectedRange(NSRange(location: at, length: 0))
        return open
    }

    func testACodeBlockIsMadeAtTheCaretOpenedAsCodeAndOneUndoTakesItBack() {
        host("Words here.\n\nMore.")
        guard openTheFirstCell(caret: 5) != nil else { return XCTFail("the premise: a cell open for typing") }
        bridge.codeBlock(.python)
        settle()
        XCTAssertEqual(note.text, "```python\nWords here.\n```\n\nMore.")
        guard let code = bridge.textView as? BlockTextView else { return XCTFail("nothing open after it") }
        XCTAssertEqual(code.string, "Words here.", "the cell is open as its code, holding its words")
        XCTAssertTrue(code.isCode)
        XCTAssertEqual(code.selectedRange(), NSRange(location: 11, length: 0))
        code.undoManager?.undo()
        settle()
        XCTAssertEqual(note.text, "Words here.\n\nMore.")
    }

    func testTheBlockMadeFromTheOpenCellTakesTheNextKeystrokeNotTheOldParagraph() {
        // The new cell starts where the open one did, so SwiftUI keeps the
        // same editor for it — and an editor that has the keyboard does not
        // take new text from outside. The next keystroke wrote the old
        // paragraph back over the code.
        host("Words here.\n\nMore.")
        guard openTheFirstCell(caret: 0) != nil else { return XCTFail("the premise: a cell open for typing") }
        bridge.codeBlock(.python)
        settle()
        XCTAssertEqual(note.text, "```python\nWords here.\n```\n\nMore.")
        guard let code = bridge.textView as? BlockTextView else { return XCTFail("nothing open after it") }
        XCTAssertEqual(code.string, "Words here.")
        code.setSelectedRange(NSRange(location: 11, length: 0))
        code.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        settle()
        XCTAssertEqual(note.text, "```python\nWords here.x\n```\n\nMore.")
    }

    func testTurningAnOpenCodeCellIntoAnEvaluationCellKeepsWhatWasTypedUndoable() {
        // The review of 2026-10-02: ⌘9 on an open code cell rewrites its
        // fence line only, so the same cell reopens in the same editor —
        // and the way back was put on that editor's stack after EMPTYING
        // it: what had been typed in the cell could not be undone any
        // more. The source pane's ⌘9 is one step on top of the rest.
        host("```python\nprint(1)\n```")
        guard let open = openTheFirstCell(caret: 8) else { return XCTFail("the premise: a cell open for typing") }
        keystroke(in: open) { open.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        settle()
        XCTAssertEqual(note.text, "```python\nprint(1)x\n```")
        bridge.evaluationCell(.python)
        settle()
        XCTAssertEqual(note.text, "```eval python\nprint(1)x\n```")
        (bridge.textView as? BlockTextView)?.undoManager?.undo()
        settle()
        XCTAssertEqual(note.text, "```python\nprint(1)x\n```", "the turn first")
        (bridge.textView as? BlockTextView)?.undoManager?.undo()
        settle()
        XCTAssertEqual(note.text, "```python\nprint(1)\n```", "then what was typed before it")
    }

    func testInlineMathsGoesThroughTheOpenCellsOwnEditor() {
        host("Words here.\n\nMore.")
        guard let open = openTheFirstCell(caret: 5) else { return XCTFail("the premise: a cell open for typing") }
        bridge.insertMath("Pi", display: false)
        settle()
        XCTAssertEqual(note.text, "Words`wl:Pi` here.\n\nMore.")
        XCTAssertTrue(bridge.textView === open, "the same cell, still open")
        open.undoManager?.undo()
        settle()
        XCTAssertEqual(note.text, "Words here.\n\nMore.")
    }

    func testARefusalOnThePageSaysWhyAndWritesNothing() {
        host("```python\nprint(1)\n```")
        var said: [String] = []
        bridge.say = { said.append($0) }
        guard openTheFirstCell(caret: 2) != nil else { return XCTFail("the premise: a cell open for typing") }
        bridge.codeBlock(.python)
        settle()
        XCTAssertEqual(note.text, "```python\nprint(1)\n```")
        XCTAssertEqual(said, [Insertion.Refusal.codeInCode.message])
    }
}
