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
        palette.choose(template("pi"))
        XCTAssertEqual(palette.expression, "Pi", "a shape with nowhere to put it")
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
        // Not when it does not read: there is nothing to wrap.
        var broken = MathPalette()
        broken.type("x^2 +")
        broken.choose(template("sqrt"))
        XCTAssertEqual(broken.expression, "Sqrt[x]")
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
