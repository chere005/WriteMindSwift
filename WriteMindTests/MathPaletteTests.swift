import XCTest
@testable import WriteMind

/// WHAT THE MATHS PALETTE HOLDS. Sean, 2026-10-03: "maths input should also
/// just allow for an expression so i could insert a function or something
/// and it would appear like the derivatives or integrals". The free field is
/// the palette; a shape is a way of writing into it; and what is in it is
/// either maths that reads, or a reason it does not — never something
/// broken that Insert would write all the same.
final class MathPaletteTests: XCTestCase {
    private func template(_ id: String) -> MathTemplate { MathTemplate.all.first { $0.id == id }! }

    func testItOpensEmptyWithNothingToInsertAndNothingWrong() {
        let palette = MathPalette()
        XCTAssertEqual(palette.reading, .empty)
        XCTAssertFalse(palette.canInsert)
        XCTAssertNil(palette.insertion)
        XCTAssertNil(palette.problem, "an empty field is not an error")
        XCTAssertNil(palette.template)
        XCTAssertTrue(palette.onItsOwnLine)
    }

    func testAnExpressionTypedThatReadsCanBeInsertedInItsOneSpelling() {
        var palette = MathPalette()
        palette.type("Sin[x]^2/(1+x)")
        XCTAssertEqual(palette.reading, .maths(canonical: "Sin[x]^2/(1 + x)"))
        XCTAssertTrue(palette.canInsert)
        XCTAssertEqual(palette.insertion, .maths("Sin[x]^2/(1 + x)", onItsOwnLine: true))
        XCTAssertEqual(palette.storedAs, "Sin[x]^2/(1 + x)", "the note holds the canonical form, and the field says so")
        palette.type("Sin[x]^2/(1 + x)")
        XCTAssertNil(palette.storedAs, "nothing to say when it was typed that way")
        palette.onItsOwnLine = false
        XCTAssertEqual(palette.insertion, .maths("Sin[x]^2/(1 + x)", onItsOwnLine: false))
    }

    func testEveryExpressionNamedInTheRequestCanBeInserted() {
        for source in ["Sin[x]^2/(1+x)", "Sqrt[a^2+b^2]", "Integrate[Exp[-x^2], {x, -Infinity, Infinity}]",
                       "D[f[x], x]", "Sum[1/n^2, {n, 1, Infinity}]", "f[x_] := x^2", "Limit[Sin[x]/x, x -> 0]",
                       "{{1,2},{3,4}}", "Alpha + Pi*Theta", "a^2*b + c - d/e"] {
            var palette = MathPalette()
            palette.type(source)
            XCTAssertTrue(palette.canInsert, source)
            XCTAssertNil(palette.problem, source)
        }
    }

    func testAnExpressionThatDoesNotReadSaysWhyAndCannotBeInserted() {
        var palette = MathPalette()
        palette.type("Integrate[x^2, {x, 0, 1}")
        XCTAssertFalse(palette.canInsert)
        XCTAssertNil(palette.insertion, "never broken source, silently")
        XCTAssertEqual(palette.problem, "Missing \"]\" — the \"[\" at position 10 is never closed.")
        XCTAssertNil(palette.storedAs)
        guard case .broken(let error) = palette.reading else { return XCTFail("\(palette.reading)") }
        XCTAssertEqual(error.offset, 9)
        // Mended, it can.
        palette.type("Integrate[x^2, {x, 0, 1}]")
        XCTAssertTrue(palette.canInsert)
        XCTAssertNil(palette.problem)
    }

    func testWhatANoteCannotCarryIsSaidInTheFieldAndCannotBeInserted() {
        var palette = MathPalette()
        palette.type("Text[\"a`b\"]")
        XCTAssertFalse(palette.canInsert)
        XCTAssertNil(palette.insertion)
        XCTAssertEqual(palette.problem, "The string at position 6 has a backtick or a line break in it, "
                       + "and a note cannot keep that — write it another way (a line break is \\n).")
        palette.type("Text[\"a\\nb\"]")
        XCTAssertTrue(palette.canInsert, "a backslash and an n are fine")
    }

    func testTwoLinesAreOneExpressionTooManyAndTheFieldSaysSo() {
        var palette = MathPalette()
        palette.type("a = 1\nb = 2")
        XCTAssertFalse(palette.canInsert)
        XCTAssertNil(palette.insertion, "never silently the product `a = 1b = 2`")
        XCTAssertEqual(palette.problem, "Maths holds one expression, and a new line starts a second one (position 7): "
                       + "join them with \";\" or insert them one at a time.")
        palette.type("a = 1;\nb = 2")
        XCTAssertEqual(palette.reading, .maths(canonical: "a = 1; b = 2"))
    }

    func testSpacesAroundItAreNotPartOfIt() {
        var palette = MathPalette()
        palette.type("   x^2  \n")
        XCTAssertEqual(palette.reading, .maths(canonical: "x^2"))
        palette.type("    ")
        XCTAssertEqual(palette.reading, .empty)
    }

    // MARK: - Opened over a selection

    func testItIsSeededFromASelectionThatReadsAsMathsAndSaysWhereItGoes() {
        var palette = MathPalette()
        palette.start(seed: MathSelection.Seed(wl: "x^2 + 1", inline: true))
        XCTAssertEqual(palette.expression, "x^2 + 1")
        XCTAssertFalse(palette.onItsOwnLine, "it sits in a sentence")
        XCTAssertEqual(palette.insertion, .maths("x^2 + 1", onItsOwnLine: false))

        var alone = MathPalette()
        alone.start(seed: MathSelection.Seed(wl: "f[x_] := x^2", inline: false))
        XCTAssertEqual(alone.expression, "f[x_] := x^2")
        XCTAssertTrue(alone.onItsOwnLine)

        var none = MathPalette()
        none.start(seed: nil)
        XCTAssertEqual(none.reading, .empty, "no selection, an empty field with the keyboard in it")
    }

    func testAShapePickedOverASelectionWrapsItAndTheNextShapeDoesNotNestTheLast() {
        var palette = MathPalette()
        palette.start(seed: MathSelection.Seed(wl: "x^2 + 1", inline: false))
        palette.choose(template("sqrt"))
        XCTAssertEqual(palette.expression, "Sqrt[x^2 + 1]")
        palette.choose(template("abs"))
        XCTAssertEqual(palette.expression, "Abs[x^2 + 1]", "the selection again, not √ of it")
        palette.choose(template("sum"))
        XCTAssertEqual(palette.values, ["x^2 + 1", "i", "1", "n"])
        XCTAssertEqual(palette.expression, "Sum[x^2 + 1, {i, 1, n}]")
    }

    // MARK: - Shapes and their parts

    func testAShapeWritesIntoTheFieldAndItsPartsDriveIt() {
        var palette = MathPalette()
        palette.choose(template("integrate.definite"))
        XCTAssertEqual(palette.expression, "Integrate[x^2, {x, 0, 1}]")
        XCTAssertEqual(palette.template?.id, "integrate.definite")
        palette.setValue("Sin[x]", at: 0)
        palette.setValue("Pi", at: 3)
        XCTAssertEqual(palette.expression, "Integrate[Sin[x], {x, 0, Pi}]")
        XCTAssertEqual(palette.insertion, .maths("Integrate[Sin[x], {x, 0, Pi}]", onItsOwnLine: true))
        palette.setValue("", at: 0)
        XCTAssertEqual(palette.expression, "Integrate[x^2, {x, 0, Pi}]", "an empty part falls back to its suggestion")
    }

    func testTypingInTheFieldLetsGoOfTheShapeBecauseItNoLongerDescribesIt() {
        var palette = MathPalette()
        palette.choose(template("sum"))
        XCTAssertNotNil(palette.template)
        palette.type("Sum[k^2, {k, 1, 10}]")
        XCTAssertNil(palette.template)
        XCTAssertEqual(palette.values, [])
        palette.setValue("zzz", at: 0)
        XCTAssertEqual(palette.expression, "Sum[k^2, {k, 1, 10}]", "nothing to fill in any more")
    }

    func testWhatWasTypedIsWhatTheNextShapeWraps() {
        var palette = MathPalette()
        palette.type("x^2 + 1")
        palette.choose(template("sqrt"))
        XCTAssertEqual(palette.expression, "Sqrt[x^2 + 1]")
    }

    // MARK: - The field and the shapes compose

    // Review, 2026-10-03: a shape overwrote the field. Type `2`, click π and
    // the field was `Pi`; type `x^2+1`, click √ and then |x|, and the
    // formula was gone; a formula with a bracket missing was thrown away on
    // any click. Sean's decision: they compose.

    func testAShapeWithNoPartsIsWrittenIntoWhatWasTypedAndTypingGoesOn() {
        var palette = MathPalette()
        palette.type("2")
        palette.choose(template("pi"))
        XCTAssertEqual(palette.expression, "2 Pi ", "π goes in after the 2, and room is left for the next thing typed")
        palette.type(palette.expression + "r")
        XCTAssertEqual(palette.expression, "2 Pi r")
        XCTAssertEqual(palette.reading, .maths(canonical: "2*Pi*r"))
        palette.choose(template("greek.Alpha"))
        XCTAssertEqual(palette.expression, "2 Pi r \\[Alpha] ")
        XCTAssertEqual(palette.reading, .maths(canonical: "2*Pi*r*\\[Alpha]"))
        XCTAssertNil(palette.template, "what is in the field is what was typed, with a symbol in it")
    }

    func testASymbolIsNotRunIntoTheLetterBesideIt() {
        var palette = MathPalette()
        palette.type("x")
        palette.choose(template("pi"))
        XCTAssertEqual(palette.reading, .maths(canonical: "x*Pi"), "not a symbol called xPi")
        var empty = MathPalette()
        empty.choose(template("pi"))
        XCTAssertEqual(empty.reading, .maths(canonical: "Pi"))
        XCTAssertEqual(empty.insertion, .maths("Pi", onItsOwnLine: true))
    }

    func testAFormulaThatDoesNotReadYetKeepsWhatWasTypedWhenAShapeIsPicked() {
        var palette = MathPalette()
        palette.type("x^2 +")
        palette.choose(template("pi"))
        XCTAssertEqual(palette.expression, "x^2 + Pi ")
        XCTAssertEqual(palette.reading, .maths(canonical: "x^2 + Pi"), "and it reads now")

        var broken = MathPalette()
        broken.type("Integrate[x^2, {x, 0, 1}")
        broken.choose(template("sqrt"))
        XCTAssertTrue(broken.expression.hasPrefix("Integrate[x^2, {x, 0, 1}"), "what was typed is not thrown away: \(broken.expression)")
        XCTAssertTrue(broken.expression.contains("Sqrt[x]"), broken.expression)
        XCTAssertNotNil(broken.problem, "it still says what is wrong")
    }

    func testASecondShapeWrapsWhatWasTypedToo() {
        var palette = MathPalette()
        palette.type("x^2+1")
        palette.choose(template("sqrt"))
        XCTAssertEqual(palette.expression, "Sqrt[x^2 + 1]")
        palette.choose(template("abs"))
        XCTAssertEqual(palette.expression, "Abs[x^2 + 1]", "the typed formula again, not nothing")
        palette.choose(template("abs"))
        XCTAssertEqual(palette.expression, "Abs[x^2 + 1]", "the same shape twice")
        palette.choose(template("sum"))
        XCTAssertEqual(palette.expression, "Sum[x^2 + 1, {i, 1, n}]")
        // Typing something else is a new subject.
        palette.type("y")
        palette.choose(template("sqrt"))
        palette.choose(template("abs"))
        XCTAssertEqual(palette.expression, "Abs[y]")
    }

    func testASymbolGoesInAtTheCaretAndTypingGoesOnAfterIt() {
        var palette = MathPalette()
        palette.type("2r")
        palette.choose(template("pi"), selection: NSRange(location: 1, length: 0))
        XCTAssertEqual(palette.expression, "2 Pi r")
        XCTAssertEqual(palette.caret, 5, "between the space after the π and the r")
        XCTAssertEqual(palette.reading, .maths(canonical: "2*Pi*r"))

        palette.type("f[]")
        palette.choose(template("pi"), selection: NSRange(location: 2, length: 0))
        XCTAssertEqual(palette.expression, "f[Pi ]", "after an opening bracket there is nothing to keep apart")
        XCTAssertEqual(palette.caret, 5)

        // The end, when the field does not say where the caret is — and nowhere past it.
        for selection in [nil, NSRange(location: NSNotFound, length: 0), NSRange(location: 99, length: 0)] {
            var end = MathPalette()
            end.type("x +")
            end.choose(template("pi"), selection: selection)
            XCTAssertEqual(end.expression, "x + Pi ")
            XCTAssertEqual(end.caret, 7)
        }
        // Typing again forgets where the caret was to go.
        palette.type("Pi")
        XCTAssertNil(palette.caret)
    }

    func testASelectionInTheFieldIsNeverWrittenOver() {
        var palette = MathPalette()
        palette.type("x + y")
        palette.choose(template("pi"), selection: NSRange(location: 0, length: 5))
        XCTAssertEqual(palette.expression, "x + y Pi ", "the editor selects all of it when it takes the keyboard")
        var inside = MathPalette()
        inside.type("a b c")
        inside.choose(template("pi"), selection: NSRange(location: 2, length: 1))
        XCTAssertEqual(inside.expression, "a b Pi  c", "at the end of the selection, which stays")
    }

    func testWritingMeasuresTheCaretInUTF16UnitsAsTheFieldCountsThem() {
        let written = MathPalette.writing("Pi", into: "😀", at: NSRange(location: 2, length: 0))
        XCTAssertEqual(written.field, "😀 Pi ")
        XCTAssertEqual(written.caret, 6, "the emoji is two units")
        XCTAssertEqual(MathPalette.writing("Pi", into: "", at: nil).field, "Pi ", "nothing before it to keep it from")
        XCTAssertEqual(MathPalette.writing("Pi", into: "a, ", at: nil).field, "a, Pi ", "already apart")
        XCTAssertEqual(MathPalette.writing("Pi", into: "(", at: nil).field, "(Pi ")
    }

    func testTheSelectionAThePaletteOpenedOverIsNotWrappedAfterSomethingElseWasTyped() {
        var palette = MathPalette()
        palette.start(seed: MathSelection.Seed(wl: "x^2 + 1", inline: false))
        palette.type("y")
        palette.choose(template("sqrt"))
        palette.choose(template("abs"))
        XCTAssertEqual(palette.expression, "Abs[y]", "y was typed over the selection; the selection is not wrapped")
    }

    func testACompoundFormulaIsBracketedWhereAnOperatorReachesIt() {
        for (typed, power, root) in [("a + b", "(a + b)^2", "(a + b)^(1/3)"),
                                     ("x^2 + 1", "(x^2 + 1)^2", "(x^2 + 1)^(1/3)"),
                                     ("a*b", "(a*b)^2", "(a*b)^(1/3)"),
                                     ("-x", "(-x)^2", "(-x)^(1/3)"),
                                     ("x", "x^2", "x^(1/3)"),
                                     ("f[x]", "f[x]^2", "f[x]^(1/3)"),
                                     ("Sin[x]^2", "(Sin[x]^2)^2", "(Sin[x]^2)^(1/3)"),
                                     ("2", "2^2", "2^(1/3)")] {
            var palette = MathPalette()
            palette.type(typed)
            palette.choose(template("power"))
            XCTAssertEqual(palette.expression, power, typed)
            palette.choose(template("root"))
            XCTAssertEqual(palette.expression, root, typed)
        }
    }

    func testTheSelectionASeedingWrapsIsBracketedToo() {
        var palette = MathPalette()
        palette.start(seed: MathSelection.Seed(wl: "a + b", inline: false))
        palette.choose(template("power"))
        XCTAssertEqual(palette.expression, "(a + b)^2", "it was a + b^2, which is another formula")
        palette.choose(template("root"))
        XCTAssertEqual(palette.expression, "(a + b)^(1/3)")
        palette.choose(template("equal"))
        XCTAssertEqual(palette.expression, "a + b == y")
        palette.choose(template("fraction"))
        XCTAssertEqual(palette.expression, "(a + b)/(b)")
    }

    func testAPartTypedIntoAShapeIsBracketedLikeASelection() {
        var palette = MathPalette()
        palette.choose(template("power"))
        palette.setValue("a + b", at: 0)
        XCTAssertEqual(palette.expression, "(a + b)^2")
        palette.setValue("n + 1", at: 1)
        XCTAssertEqual(palette.expression, "(a + b)^(n + 1)")
        palette.choose(template("equal"))
        palette.setValue("a -> b", at: 0)
        XCTAssertEqual(palette.expression, "(a -> b) == y", "a rule is not the left of an equation")
        // A part is only ever put in as itself: `#2` in a slot is the user's pure function, not a slot.
        var sum = MathPalette()
        sum.choose(template("sum"))
        sum.setValue("#1 + #2 &", at: 0)
        XCTAssertEqual(sum.expression, "Sum[#1 + #2 &, {i, 1, n}]")
    }

    func testEveryShapeThePaletteOffersCanBeInserted() {
        for shape in MathTemplate.all {
            var palette = MathPalette()
            palette.choose(shape)
            XCTAssertTrue(palette.canInsert, "\(shape.id): \(palette.expression)")
            XCTAssertNil(palette.problem, shape.id)
        }
    }

    func testAShapeAndTheSameTypedByHandAreOneThing() {
        var shaped = MathPalette()
        shaped.choose(template("derivative"))
        shaped.setValue("f[x]", at: 0)
        var typed = MathPalette()
        typed.type("D[f[x],   x]")
        XCTAssertEqual(shaped.insertion, typed.insertion)
        XCTAssertEqual(MathBuilder.box(WLParser.parse(shaped.expression)!), MathBuilder.box(WLParser.parse(typed.expression)!))
    }

    // MARK: - Through to the note

    func testWhatItInsertsGoesThroughTheSamePathTheShapesDo() throws {
        var palette = MathPalette()
        palette.type("f[x_] := x^2")
        let thing = try XCTUnwrap(palette.insertion)
        let (text, selection) = Marked.parse("One two‸ three.")
        guard case .edit(let edit) = Insertion.insert(thing, in: text, at: selection, atBar: false) else {
            return XCTFail("refused")
        }
        let applied = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(Marked.show(applied, edit.selection), "One two\n\n```wl\nf[x_] := x^2‸\n```\n\nthree.")
    }
}
