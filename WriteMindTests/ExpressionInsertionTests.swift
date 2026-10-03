import AppKit
import XCTest
@testable import WriteMind

/// AN EXPRESSION GOES IN THROUGH THE SAME PATH AS A SHAPE. Sean, 2026-10-03:
/// "maths input should also just allow for an expression so i could insert a
/// function or something and it would appear like the derivatives or
/// integrals". The palette hands `Insertion` the WL and where it goes;
/// nothing else is different — the placement rules, the one step of undo and
/// the caret afterwards are the ones every shape has had since 2026-10-02 —
/// except that maths that does not read is refused, and says why, instead of
/// being written into a note as it was typed.
final class ExpressionInsertionTests: XCTestCase {
    private func after(_ wl: String, display: Bool, _ marked: String, atBar: Bool = false) -> String {
        InsertionPlacementTests.after(.maths(wl, onItsOwnLine: display), marked, atBar: atBar)
    }

    // MARK: - Where it goes

    func testADisplayExpressionLandsAsACellOfItsOwnWithTheCaretAtTheEndOfItsWL() {
        XCTAssertEqual(after("f[x_] := x^2", display: true, "One two‸ three four."),
                       "One two\n\n```wl\nf[x_] := x^2‸\n```\n\nthree four.")
        XCTAssertEqual(after("Sin[x]^2/(1+x)", display: true, "One.\n\n‸Two.", atBar: true),
                       "One.\n\n```wl\nSin[x]^2/(1 + x)‸\n```\n\nTwo.", "written as WL's one spelling")
        XCTAssertEqual(after("{{1,2},{3,4}}", display: true, "‸"), "```wl\n{{1, 2}, {3, 4}}‸\n```")
    }

    func testAnInlineExpressionStaysInTheSentenceWithTheCaretAfterIt() {
        XCTAssertEqual(after("Sqrt[a^2+b^2]", display: false, "One two ‸three."),
                       "One two `wl:Sqrt[a^2 + b^2]`‸three.")
        XCTAssertEqual(after("Integrate[Exp[-x^2], {x, -Infinity, Infinity}]", display: false, "The area ‸is it."),
                       "The area `wl:Integrate[Exp[-x^2], {x, -Infinity, Infinity}]`‸is it.")
        XCTAssertEqual(after("Pi", display: false, "#‸ Title"), "# `wl:Pi`‸Title", "never in front of a marker")
        XCTAssertEqual(after("Alpha + Beta", display: false, "‸"), "`wl:Alpha + Beta`‸", "no words: a cell of its own")
    }

    func testASelectionThatIsTheExpressionIsReplacedByItAndWordsAreNeverThrownAway() {
        XCTAssertEqual(after("f[x_] := x^2", display: false, "So «f[x_] := x^2» holds."),
                       "So `wl:f[x_] := x^2`‸ holds.")
        XCTAssertEqual(after("Sqrt[x^2 + 1]", display: false, "Area «x^2 + 1» here."), "Area `wl:Sqrt[x^2 + 1]`‸ here.")
        XCTAssertEqual(after("Sin[x]", display: true, "One «two three» four."),
                       "One two three\n\n```wl\nSin[x]‸\n```\n\nfour.")
    }

    func testInsideAMathsBlockOrSpanItIsTheBareWLAtTheCaret() {
        XCTAssertEqual(after("Sin[x]^2", display: true, "```wl\nx + ‸\n```"), "```wl\nx + Sin[x]^2‸\n```")
        XCTAssertEqual(after("Sin[x]^2", display: false, "Area `wl:x + ‸` here."), "Area `wl:x + Sin[x]^2‸` here.")
    }

    func testInsideCodeInlineMathsIsStillRefusedAndDisplayGoesAfter() {
        XCTAssertEqual(after("Sin[x]", display: false, "```python\nprint(‸1)\n```"), "refused")
        XCTAssertEqual(after("Sin[x]", display: true, "```python\nprint(‸1)\n```"),
                       "```python\nprint(1)\n```\n\n```wl\nSin[x]‸\n```")
    }

    // MARK: - Broken maths is refused, and says why

    func testMathsThatDoesNotReadIsRefusedEverywhereWithTheReason() {
        for (marked, display, atBar) in [("One‸ two.", true, false), ("One ‸two.", false, false),
                                         ("One.\n\n‸Two.", true, true), ("```wl\nx + ‸\n```", true, false),
                                         ("Area `wl:x + ‸` here.", false, false), ("```python\nx‸\n```", true, false),
                                         ("‸", true, false)] {
            let (text, selection) = Marked.parse(marked)
            let outcome = Insertion.insert(.maths("Integrate[x^2, {x, 0, 1}", onItsOwnLine: display), in: text,
                                           at: selection, atBar: atBar)
            XCTAssertEqual(outcome,
                           .refused(.mathsDoesNotParse("Missing \"]\" — the \"[\" at position 10 is never closed.")), marked)
        }
        XCTAssertEqual(Insertion.Refusal.mathsDoesNotParse("Missing \"]\".").message,
                       "That maths does not read, so nothing was inserted: Missing \"]\".")
        for broken in ["x +", "(1 + 2", "Sin[x))", "\"abc", "|x|", "", "   "] {
            XCTAssertEqual(after(broken, display: true, "One‸ two."), "refused", broken)
            XCTAssertEqual(after(broken, display: false, "One‸ two."), "refused", broken)
        }
    }

    // MARK: - The source pane: one step of undo, the caret where typing goes

    private final class Undoer: NSObject, NSTextViewDelegate {
        let manager: UndoManager = {
            let manager = UndoManager()
            manager.groupsByEvent = false
            return manager
        }()
        func undoManager(for view: NSTextView) -> UndoManager? { manager }
    }

    private func pane(_ marked: String, undoer: Undoer, bar: Bool = false) -> (PasteAwareTextView, EditorBridge) {
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

    private func event(_ undoer: Undoer, _ body: () -> Void) {
        undoer.manager.beginUndoGrouping()
        body()
        undoer.manager.endUndoGrouping()
    }

    func testOneUndoTakesAnExpressionBackWhereverItWentAndTheCaretEndsAfterIt() {
        for (marked, display) in [("One two‸ three.", true), ("One two ‸three.", false), ("One.\n\n‸Two.", true),
                                  ("Area «x^2 + 1» here.", false), ("```wl\nx + ‸\n```", true)] {
            let undoer = Undoer()
            let (view, bridge) = pane(marked, undoer: undoer, bar: marked.contains("\n\n‸"))
            let original = view.string
            event(undoer) { bridge.insertMath("f[x_] := Sin[x]^2/(1+x)", display: display) }
            XCTAssertNotEqual(view.string, original, marked)
            XCTAssertTrue(view.string.contains("f[x_] := Sin[x]^2/(1 + x)"), view.string)
            let caret = view.selectedRange()
            XCTAssertEqual(caret.length, 0)
            let before = (view.string as NSString).substring(to: caret.location)
            XCTAssertTrue(before.hasSuffix(display ? "(1 + x)" : "(1 + x)`") || before.hasSuffix("(1 + x)"),
                          "the caret is after the maths: \(Marked.show(view.string, caret))")
            undoer.manager.undo()
            XCTAssertEqual(view.string, original, "one ⌘Z: \(marked)")
        }
    }

    func testBrokenMathsFromThePaletteWritesNothingAndSaysWhyInTheFooter() {
        let undoer = Undoer()
        let (view, bridge) = pane("One two‸ three.", undoer: undoer)
        var said: [String] = []
        bridge.say = { said.append($0) }
        bridge.insertMath("Sin[x", display: true)
        XCTAssertEqual(view.string, "One two three.")
        XCTAssertEqual(said, ["That maths does not read, so nothing was inserted: Missing \"]\" — the \"[\" at position 4 is never closed."])
        XCTAssertFalse(undoer.manager.canUndo, "no step was taken")
    }

    // MARK: - The selection the palette is seeded from

    func testAFormulaSelectedInANoteSeedsThePaletteAndProseDoesNot() {
        XCTAssertEqual(MathSelection.reading("f[x_] := x^2"), "f[x_] := x^2")
        XCTAssertEqual(MathSelection.reading("x = 2y + 1"), "x = 2*y + 1")
        XCTAssertEqual(MathSelection.reading("n!"), "n!")
        XCTAssertEqual(MathSelection.reading("x² + y²"), "x^2 + y^2")
        XCTAssertEqual(MathSelection.reading("Integrate[x^2, {x, 0, 1}]"), "Integrate[x^2, {x, 0, 1}]")
        // Function notation as a page writes it is not WL's, and WL would set it as a product.
        XCTAssertNil(MathSelection.reading("f(x) = 2x"))
        XCTAssertNil(MathSelection.reading("g(x)"))
        // Prose that happens to parse.
        XCTAssertNil(MathSelection.reading("I'm"))
        XCTAssertNil(MathSelection.reading("#hashtag"))
        XCTAssertNil(MathSelection.reading("snake_case"))
        XCTAssertNil(MathSelection.reading("my_var + 1"))
        XCTAssertEqual(MathSelection.reading("f[x_Integer] := x"), "f[x_Integer] := x")
        XCTAssertNil(MathSelection.reading("Hello!"))
        XCTAssertNil(MathSelection.reading("the area"))
        XCTAssertNil(MathSelection.reading("e.g."))
        XCTAssertNil(MathSelection.reading("C++"))
        XCTAssertEqual(MathSelection.reading("f'[x]"), "f'[x]")
        XCTAssertEqual(MathSelection.reading("#^2 &"), "#^2 &")
    }

    func testMathsHoldsAnExpressionOnlyWhenAWholeTermOfItIsTheSelection() {
        XCTAssertTrue(MathSelection.holds("f[x_] := x^2", selected: "x^2"))
        XCTAssertTrue(MathSelection.holds("m[[i, j]]", selected: "i"))
        XCTAssertTrue(MathSelection.holds("!a && b", selected: "a"))
        XCTAssertTrue(MathSelection.holds("n!", selected: "n"))
        XCTAssertFalse(MathSelection.holds("Sin[x]", selected: "y"))
    }

    // MARK: - What is stored is plain WL, and clicking back in edits it

    func testWhatIsStoredIsPlainMarkdownThatReadsBackAsTheSameExpression() throws {
        let formula = "Integrate[Exp[-x^2], {x, -Infinity, Infinity}]"
        // Inline: a code span.
        let span = MathMarkup.inline(formula)
        XCTAssertEqual(span, "`wl:Integrate[Exp[-x^2], {x, -Infinity, Infinity}]`")
        XCTAssertEqual(MathMarkup.expression(inCode: String(span.dropFirst().dropLast())), formula)
        // Display: a fence, which is a cell of its own to the parser.
        let note = "Before.\n\n" + MathMarkup.block(formula) + "\n\nAfter."
        let blocks = MarkdownParser.blocks(from: note)
        guard case .code(let language, let body) = blocks[1] else { return XCTFail("\(blocks)") }
        XCTAssertTrue(MathMarkup.isMathFence(language))
        XCTAssertEqual(body, formula)
        XCTAssertEqual(WLParser.parse(body), WLParser.parse(formula))
    }

    func testClickingBackIntoARenderedMathsCellOpensItsSourceAndEditingItRetypesIt() throws {
        let note = "Before.\n\n```wl\nSin[x]^2/(1 + x)\n```\n\nAfter."
        let cell = try XCTUnwrap(MarkdownParser.positioned(from: note).first {
            if case .code = $0.block { return true } else { return false }
        })
        let source = (note as NSString).substring(with: cell.range)
        // The cell opens as its WL alone, the fences staying put round it.
        let parts = try XCTUnwrap(MarkdownFormatting.fenced(source))
        XCTAssertEqual(parts.body, "Sin[x]^2/(1 + x)")
        XCTAssertEqual(parts.open, "```wl")
        // Typing in it is typing the WL; put back together it is still the note.
        let edited = MarkdownFormatting.refenced(open: parts.open, body: "Sin[x]^3/(1 + x)", close: parts.close)
        let after = (note as NSString).replacingCharacters(in: cell.range, with: edited)
        guard case .code(_, let body) = MarkdownParser.blocks(from: after)[1] else { return XCTFail("\(after)") }
        XCTAssertEqual(body, "Sin[x]^3/(1 + x)")
        XCTAssertNotNil(WLParser.parse(body), "and it typesets again")
        // A click lands the caret at the end of the WL, after the fence line.
        let landing = MarkdownPreview.landing(at: cell.range.location + 6 + (parts.body as NSString).length, in: note)
        XCTAssertEqual(landing.cell, cell.range)
        XCTAssertEqual(landing.caret, (parts.body as NSString).length)
    }

    func testAnInlineSpanIsEditedAsTheTextOfItsSentence() throws {
        let note = "The area `wl:Sqrt[a^2 + b^2]` is it."
        let cell = try XCTUnwrap(MarkdownParser.positioned(from: note).first)
        XCTAssertEqual((note as NSString).substring(with: cell.range), note, "the whole sentence opens, WL span and all")
        let edited = note.replacingOccurrences(of: "a^2 + b^2", with: "a^2 + b^2 + c^2")
        let typeset = String(MarkdownInline.render(edited).characters)
        XCTAssertTrue(typeset.contains("√(a2 + b2 + c2)"), typeset)
    }
}
