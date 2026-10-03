import XCTest
@testable import WriteMind

final class WLParserTests: XCTestCase {
    func testAnIntegralParsesIntoItsHeadAndItsBounds() {
        let parsed = WLParser.parse("Integrate[x^2, {x, 0, 1}]")
        XCTAssertEqual(parsed, .call(.symbol("Integrate"), [
            .binary("^", .symbol("x"), .number("2")),
            .list([.symbol("x"), .number("0"), .number("1")])
        ]))
    }

    func testTimesBindsTighterThanPlusAndPowerTighterThanBoth() {
        XCTAssertEqual(WLParser.parse("a + b*c^2"),
                       .binary("+", .symbol("a"),
                               .binary("*", .symbol("b"),
                                       .binary("^", .symbol("c"), .number("2")))))
    }

    func testPowersAssociateToTheRight() {
        XCTAssertEqual(WLParser.parse("2^3^4"),
                       .binary("^", .number("2"), .binary("^", .number("3"), .number("4"))))
    }

    func testTwoThingsSideBySideAreAProduct() {
        XCTAssertEqual(WLParser.parse("2 x"), .binary("*", .number("2"), .symbol("x")))
    }

    func testGreekArrivesAsOneName() {
        XCTAssertEqual(WLParser.parse("\\[Alpha] + 1"),
                       .binary("+", .symbol("\\[Alpha]"), .number("1")))
        XCTAssertEqual(MathSymbols.glyph(for: "\\[Alpha]"), "α")
        XCTAssertEqual(MathSymbols.glyph(for: "Pi"), "π")
    }

    func testHalfTypedMathsIsNotAnExpression() {
        XCTAssertNil(WLParser.parse("Integrate["))
        XCTAssertNil(WLParser.parse("x +"))
        XCTAssertNil(WLParser.parse("{1, 2"))
    }
}

final class WLPrinterTests: XCTestCase {
    func testCanonicalFormDropsBracketsItDoesNotNeedAndKeepsTheOnesItDoes() {
        XCTAssertEqual(WLPrinter.canonical("(x+1)/(2)"), "(x + 1)/2")
        XCTAssertEqual(WLPrinter.canonical("Sum[i^2,{i,1,n}]"), "Sum[i^2, {i, 1, n}]")
        XCTAssertEqual(WLPrinter.canonical("a*(b + c)"), "a*(b + c)")
    }

    func testAnythingThatDoesNotParseIsLeftExactlyAsItWasTyped() {
        XCTAssertEqual(WLPrinter.canonical("Integrate[x"), "Integrate[x")
    }

    func testEverySpellingOfTheSameThingLandsOnOneForm() {
        XCTAssertEqual(WLPrinter.canonical("x^2+1"), WLPrinter.canonical("x ^ 2 + 1"))
    }
}

final class MathTemplateTests: XCTestCase {
    func testTheFieldsFillInTheSlots() {
        let integral = MathTemplate.all.first { $0.id == "integrate.definite" }!
        XCTAssertEqual(integral.wl(["Sin[x]", "x", "0", "Pi"]), "Integrate[Sin[x], {x, 0, Pi}]")
    }

    func testAnEmptyFieldFallsBackToWhatTheSlotSuggested() {
        let sum = MathTemplate.all.first { $0.id == "sum" }!
        XCTAssertEqual(sum.wl(["", "k", " ", "10"]), "Sum[i^2, {k, 1, 10}]")
    }

    func testEveryTemplateInThePaletteWritesWLThatParses() {
        for template in MathTemplate.all {
            let wl = template.wl(template.initialValues)
            XCTAssertNotNil(WLParser.parse(wl), "\(template.id) wrote unparseable WL: \(wl)")
            XCTAssertFalse(wl.contains("#"), "\(template.id) left a slot unfilled: \(wl)")
        }
    }

    func testEveryGroupHasSomethingInIt() {
        for group in MathTemplate.Group.allCases {
            XCTAssertFalse(MathTemplate.group(group).isEmpty, "\(group.rawValue) is empty")
        }
    }
}

final class MathMarkupTests: XCTestCase {
    func testMathsIsSpelledAsOrdinaryMarkdown() {
        XCTAssertEqual(MathMarkup.inline("Pi"), "`wl:Pi`")
        XCTAssertEqual(MathMarkup.block("Pi"), "```wl\nPi\n```")
        XCTAssertTrue(MathMarkup.isMathFence("wl"))
        XCTAssertFalse(MathMarkup.isMathFence("swift"))
        XCTAssertFalse(MathMarkup.isMathFence("wolfram"), "a wolfram fence is code, set and coloured as code")
        XCTAssertFalse(MathMarkup.isMathFence(nil))
    }

    func testOnlyACodeSpanThatSaysWLIsMaths() {
        XCTAssertEqual(MathMarkup.expression(inCode: "wl:Sqrt[2]"), "Sqrt[2]")
        XCTAssertNil(MathMarkup.expression(inCode: "let x = 1"))
        XCTAssertNil(MathMarkup.expression(inCode: "wl:"))
    }

    func testAStringThatNoMarkdownFormCanCarryIsRefusedWithAMessage() {
        for source in ["Text[\"a`b\"]", "Text[\"line\none\"]", "\"```\"", "{\"ok\", \"a`b\"}", "Text[“a`b”]"] {
            guard case .failure(let error) = MathMarkup.read(source) else { return XCTFail("read: \(source.debugDescription)") }
            XCTAssertTrue(error.message.contains("backtick"), error.message)
            XCTAssertTrue((0..<source.count).contains(error.offset), "at the string: \(error)")
        }
        // The note's own text is another matter: a block a person wrote with a backtick in a string still
        // typesets — only what the palette would WRITE is held to what a note can keep.
        XCTAssertNotNil(WLParser.parse("Text[\"a`b\"]"))
        XCTAssertNotNil(MathTypesetter.inline("Text[\"a`b\"]"))
        // Fine: no backtick, no line break, a backslash-n typed as two characters, an apostrophe.
        for source in ["Text[\"a b\"]", "Text[\"a\\nb\"]", "Text[\"it's\"]", "x + 1"] {
            guard case .success = MathMarkup.read(source) else { return XCTFail("refused: \(source)") }
        }
    }

    func testTypesettingGivesUpOnWhatIsNotAnExpression() {
        XCTAssertNil(MathTypesetter.inline("Integrate["))
        XCTAssertNotNil(MathTypesetter.inline("Integrate[x^2, {x, 0, 1}]"))
    }
}

/// The calculus the menu grew on 2026-09-19.
final class CalculusTypesettingTests: XCTestCase {
    private func set(_ wl: String) -> String {
        String(MathTypesetter.inline(wl)?.characters ?? AttributedString("").characters)
    }

    func testPartialsReadAsPartials() {
        XCTAssertTrue(set("D[f[x, y], x]").contains("∂"), set("D[f[x, y], x]"))
        XCTAssertTrue(set("D[f[x, y], x, y]").contains("∂"), set("D[f[x, y], x, y]"))
        XCTAssertTrue(set("Dt[f[x, t], t]").hasPrefix("d"), set("Dt[f[x, t], t]"))
    }

    func testTheVectorOperatorsUseNabla() {
        XCTAssertTrue(set("Grad[f, {x, y, z}]").contains("∇"))
        XCTAssertTrue(set("Div[v, {x, y, z}]").contains("∇·"), set("Div[v, {x, y, z}]"))
        XCTAssertTrue(set("Curl[v, {x, y, z}]").contains("∇×"), set("Curl[v, {x, y, z}]"))
        XCTAssertTrue(set("Laplacian[f, {x, y}]").contains("∇"))
    }

    func testADoubleIntegralGetsTwoSigns() {
        XCTAssertTrue(set("Integrate[f, {x, 0, 1}, {y, 0, 1}]").contains("∫∫"),
                      set("Integrate[f, {x, 0, 1}, {y, 0, 1}]"))
        XCTAssertTrue(set("ContourIntegrate[f[z], z]").contains("∮"))
    }

    func testAOneSidedLimitShowsWhichSide() {
        XCTAssertTrue(set("Limit[1/x, x -> 0, Direction -> \"FromAbove\"]").contains("\u{207A}"),
                      set("Limit[1/x, x -> 0, Direction -> \"FromAbove\"]"))
        XCTAssertTrue(set("Limit[1/x, x -> 0, Direction -> \"FromBelow\"]").contains("\u{207B}"))
    }

    func testTheNewSymbolsHaveGlyphs() {
        XCTAssertEqual(MathSymbols.glyph(for: "\\[PlusMinus]"), "±")
        XCTAssertEqual(MathSymbols.glyph(for: "\\[Implies]"), "⇒")
        XCTAssertEqual(MathSymbols.glyph(for: "\\[ContourIntegral]"), "∮")
        XCTAssertEqual(MathSymbols.glyph(for: "Reals"), "ℝ")
        XCTAssertEqual(MathSymbols.glyph(for: "\\[Alpha]"), "α", "the greek table still wins")
    }

    func testEveryTemplateWritesSomethingTheParserUnderstands() {
        for template in MathTemplate.all {
            let wl = template.wl(template.initialValues)
            XCTAssertFalse(wl.isEmpty, template.id)
            XCTAssertNotNil(WLParser.parse(wl), "\(template.id) wrote \(wl)")
        }
    }

    func testTheCalculusGroupGrew() {
        XCTAssertGreaterThan(MathTemplate.group(.calculus).count, 15)
        XCTAssertGreaterThan(MathTemplate.group(.symbols).count, 30)
        XCTAssertEqual(Set(MathTemplate.all.map(\.id)).count, MathTemplate.all.count, "ids are unique")
    }
}
