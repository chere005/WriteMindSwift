import SwiftUI
import XCTest
@testable import WriteMind

/// WHAT THE TYPESETTER DECIDES. Sean, 2026-10-03: "maths input should also
/// just allow for an expression so i could insert a function or something
/// and it would appear like the derivatives or integrals". One builder turns
/// an expression into a tree of typeset parts and two painters read it — so
/// these say what was decided (a TeX-like outline of the tree, with the
/// gaps left out) and how it comes out in a sentence, and say nothing about
/// pixels: `MathLayoutTests` is where it is measured.
final class MathBuilderTests: XCTestCase {
    private func outline(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard case .success(let expression) = WLParser.read(source) else {
            XCTFail("did not parse: \(source)", file: file, line: line)
            return ""
        }
        return MathBuilder.box(expression).outline
    }

    /// What each formula is set as. The first ten are the ones Sean named.
    static let decided: [(String, String)] = [
        ("Sin[x]^2/(1+x)", "\\frac{sin^{2}(x)}{1+x}"),
        ("Sqrt[a^2+b^2]", "\\sqrt{a^{2}+b^{2}}"),
        ("Integrate[Exp[-x^2], {x, -Infinity, Infinity}]", "∫_{−∞}^{∞}e^{−x^{2}}dx"),
        ("D[f[x], x]", "\\frac{∂f(x)}{∂x}"),
        ("Sum[1/n^2, {n, 1, Infinity}]", "∑_{n=1}^{∞}\\frac{1}{n^{2}}"),
        ("f[x_] := x^2", "f(x_):=x^{2}"),
        ("Limit[Sin[x]/x, x -> 0]", "lim_{x→0}\\frac{sin(x)}{x}"),
        ("{{1,2},{3,4}}", "([1,2;3,4])"),
        ("Alpha + Pi*Theta", "α+πθ"),
        ("-x^2", "−x^{2}"),
        ("a - (b - c)", "a−(b−c)"),
        ("2*3", "2×3"),
        ("x*2", "x·2"),
        ("2 x", "2x"),
        ("(a+b)(c+d)", "(a+b)(c+d)"),
        ("a/b + c/d", "\\frac{a}{b}+\\frac{c}{d}"),
        ("Integrate[f[x,y], {x,0,1}, {y,0,1}]", "∫_{0}^{1}∫_{0}^{1}f(x,y)dydx"),
        ("Integrate[x^2, x]", "∫x^{2}dx"),
        ("D[f[x,y], x, y]", "\\frac{∂^{2}f(x,y)}{∂x∂y}"),
        ("D[f, {x, 3}]", "\\frac{∂^{3}f}{∂x^{3}}"),
        ("D[f[x,y], {x,2}, {y,1}]", "\\frac{∂^{3}f(x,y)}{∂x^{2}∂y}"),
        ("Dt[f[x,t], t]", "\\frac{df(x,t)}{dt}"),
        ("Limit[1/x, x -> 0, Direction -> \"FromAbove\"]", "lim_{x→0⁺}\\frac{1}{x}"),
        ("Limit[1/x, x -> 0, Direction -> \"FromBelow\"]", "lim_{x→0⁻}\\frac{1}{x}"),
        ("Log[2, x]", "log_{2}(x)"),
        ("Binomial[n, k]", "(\\binom{n}{k})"),
        ("Plus[a, b, c]", "a+b+c"),
        ("Times[-1, x]", "−x"),
        ("Power[x, 2]", "x^{2}"),
        ("Divide[a, b]", "\\frac{a}{b}"),
        ("Subtract[a, b]", "a−b"),
        ("Element[x, Reals]", "x∈ℝ"),
        ("Sin[x]^-1", "sin(x)^{−1}"),
        ("n!", "n!"),
        ("f'[x]", "f′(x)"),
        ("m[[1,2]]", "m⟦1,2⟧"),
        ("{a, b, c}", "{a,b,c}"),
        ("Exp[x]^2", "(e^{x})^{2}"),
        ("Abs[x]", "|x|"),
        ("Floor[x]", "⌊x⌋"),
        ("Norm[v, 2]", "‖v‖_{2}"),
        ("Subscript[x, i]", "x_{i}"),
        ("Product[i, {i, 1, n}]", "∏_{i=1}^{n}i"),
        ("Sum[i, {i, n}]", "∑_{i=1}^{n}i"),
        ("Sum[i j, {i, 1, n}, {j, 1, m}]", "∑_{i=1}^{n}∑_{j=1}^{m}ij"),
        ("Sum[f[i], {i, {1, 2, 3}}]", "∑_{i∈{1,2,3}}f(i)"),
        ("x -> y -> z", "x→y→z"),
        ("a && b || !c", "a∧b∨¬c"),
        ("ContourIntegrate[f[z], z]", "∮f(z)dz"),
        ("Gamma[x]", "Γ(x)"),
        ("Foo[a, b]", "Foo(a,b)"),
        ("1.5 x", "1.5x"),
        ("(a+b)^2", "(a+b)^{2}"),
        ("x^y^z", "x^{y^{z}}"),
        ("-(a+b)", "−(a+b)"),
        ("30°", "30°"),
        ("Laplacian[f, {x, y}]", "∇^{2}f"),
        ("Curl[F, {x,y,z}]", "∇×F"),
        ("x == y", "x=y"),
        ("x != y", "x≠y"),
        ("a <= b", "a≤b"),
        ("#^2 &", "#^{2}&"),
        ("f[x_] := x^2 /; x > 0", "f(x_):=x^{2}/;x>0"),
        ("a = 1; b = 2", "a=1;b=2"),
        ("Cos[x]^n", "cos^{n}(x)"),
        ("Log[x]", "ln(x)"),
        ("1/(1+1/x)", "\\frac{1}{1+\\frac{1}{x}}"),
        ("a^-1", "a^{−1}"),
        ("x_Integer", "x_Integer"),
        ("MatrixForm[{{a,b},{c,d}}]", "([a,b;c,d])"),
    ]

    func testEveryFormulaIsSetAsItsMeaningSays() {
        for (source, expected) in Self.decided {
            XCTAssertEqual(outline(source), expected, source)
        }
    }

    func testTheSamePartsAreTheSameWhateverWroteThem() {
        // FullForm and the operators it stands for are one thing set once.
        XCTAssertEqual(outline("Plus[a, Times[b, c]]"), outline("a + b*c"))
        XCTAssertEqual(outline("Power[Divide[a, b], 2]"), outline("(a/b)^2"))
        XCTAssertEqual(outline("Rational[1, 2]"), outline("1/2"))
        XCTAssertEqual(outline("Equal[x, 1]"), outline("x == 1"))
        XCTAssertEqual(outline("Not[a]"), outline("!a"))
        XCTAssertEqual(outline("Factorial[n]"), outline("n!"))
        XCTAssertEqual(outline("Rule[x, 0]"), outline("x -> 0"))
    }

    func testAShapeFromThePaletteIsJustAnExpression() {
        // The derivative the palette writes and the one typed are one tree.
        let derivative = MathTemplate.all.first { $0.id == "derivative" }!
        let wl = derivative.wl(["Sin[x]", "x"])
        XCTAssertEqual(wl, "D[Sin[x], x]")
        XCTAssertEqual(outline(wl), outline("D[ Sin[ x ] , x ]"))
        XCTAssertEqual(outline(wl), "\\frac{∂sin(x)}{∂x}")
        // And every shape goes through the one builder and comes out as something.
        for template in MathTemplate.all {
            let wl = template.wl(template.initialValues)
            XCTAssertFalse(outline(wl).isEmpty, "\(template.id): \(wl)")
        }
    }

    func testBracketsAppearWhereTheReadingNeedsThemAndNowhereElse() {
        XCTAssertEqual(outline("(a+b)*c"), "(a+b)c")
        XCTAssertEqual(outline("a+b*c"), "a+bc")
        XCTAssertEqual(outline("a*(b/c)"), "a(\\frac{b}{c})")
        XCTAssertEqual(outline("(a^b)^c"), "(a^{b})^{c}")
        XCTAssertEqual(outline("a^(b^c)"), "a^{b^{c}}")
        XCTAssertEqual(outline("Sin[x+1]"), "sin(x+1)")
        XCTAssertEqual(outline("-(a+b)"), "−(a+b)")
        XCTAssertEqual(outline("a + (-b)"), "a+(−b)")
        XCTAssertEqual(outline("Integrate[x + 1, x]"), "∫(x+1)dx")
        XCTAssertEqual(outline("Sum[a + b, {i, 1, n}]"), "∑_{i=1}^{n}(a+b)")
    }

    func testTwoNumbersAreNeverSetSideBySide() {
        XCTAssertEqual(outline("2*3"), "2×3")
        XCTAssertEqual(outline("2*3*4"), "2×3×4")
        XCTAssertEqual(outline("x*2"), "x·2")
        XCTAssertEqual(outline("2*x"), "2x")
        XCTAssertEqual(outline("Pi*2"), "π·2")
    }

    func testGreekSpelledOutIsGreek() {
        XCTAssertEqual(outline("Alpha"), "α")
        XCTAssertEqual(outline("Theta"), "θ")
        XCTAssertEqual(outline("Pi"), "π")
        XCTAssertEqual(outline("\\[Beta]"), "β")
        XCTAssertEqual(outline("\\[CapitalOmega]"), "Ω")
        XCTAssertEqual(outline("Alpha*Beta + Gamma"), "αβ+γ")
        XCTAssertEqual(outline("Gamma[x]"), "Γ(x)", "called, it is the function")
        // Capital Greek is upright and a variable is italic.
        XCTAssertEqual(MathBuilder.box(.symbol("\\[CapitalSigma]")), .glyphs("Σ", .roman))
        XCTAssertEqual(MathBuilder.box(.symbol("Alpha")), .glyphs("α", .italic))
        XCTAssertEqual(MathBuilder.box(.symbol("x1")), .glyphs("x1", .italic))
        XCTAssertEqual(MathBuilder.box(.symbol("rate")), .glyphs("rate", .roman))
        XCTAssertEqual(MathBuilder.box(.symbol("Reals")), .glyphs("ℝ", .roman))
    }

    func testAMatrixIsRowsOfCellsAndARaggedOneIsStillOne() {
        XCTAssertEqual(MathBuilder.box(WLParser.parse("{{1,2},{3,4}}")!),
                       .fenced(.paren, .matrix([[.glyphs("1", .roman), .glyphs("2", .roman)],
                                                [.glyphs("3", .roman), .glyphs("4", .roman)]])))
        XCTAssertEqual(outline("{{a},{b, c}}"), "([a;b,c])")
        XCTAssertEqual(outline("{{1, 2, 3}}"), "([1,2,3])", "one row is a matrix too")
        XCTAssertEqual(outline("{1, {2, 3}}"), "{1,{2,3}}", "not every item a row: a list")
        XCTAssertEqual(outline("{}"), "{}")
        XCTAssertEqual(outline("{{}}"), "{{}}")
    }

    func testWhatItDoesNotKnowIsSetAsAFunctionApplied() {
        XCTAssertEqual(outline("Foo[a, b]"), "Foo(a,b)")
        XCTAssertEqual(outline("f[x][y]"), "f(x)(y)")
        XCTAssertEqual(outline("g[]"), "g()")
        XCTAssertEqual(outline("Integrate[x]"), "Integrate(x)", "an integral with no variable is not one")
        XCTAssertEqual(outline("Limit[x, 3]"), "Limit(x,3)")
        XCTAssertEqual(outline("Sum[i, {i, 1, 2, 3, 4}]"), "Sum(i,{i,1,2,3,4})")
        XCTAssertEqual(outline("D[f]"), "D(f)")
        XCTAssertEqual(outline("Sqrt[a, b]"), "Sqrt(a,b)")
    }

    func testTheLevelOfAPartSaysWhetherItNeedsBracketsAsAFactor() {
        XCTAssertEqual(MathBuilder.box(WLParser.parse("a + b")!).level, WLLevel.sum)
        XCTAssertEqual(MathBuilder.box(WLParser.parse("a b")!).level, WLLevel.product)
        XCTAssertEqual(MathBuilder.box(WLParser.parse("a^b")!).level, WLLevel.power)
        XCTAssertEqual(MathBuilder.box(WLParser.parse("a/b")!).level, WLLevel.product)
        XCTAssertEqual(MathBuilder.box(WLParser.parse("f[x]")!).level, WLLevel.atom)
        XCTAssertEqual(MathBuilder.box(WLParser.parse("Plus[a, b]")!).level, WLLevel.sum, "judged by what was built")
    }
}

/// The second painter: a line of type with raised and lowered scripts.
final class InlineMathTests: XCTestCase {
    private func line(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> AttributedString {
        guard let typeset = MathTypesetter.inline(source) else {
            XCTFail("did not typeset: \(source)", file: file, line: line)
            return AttributedString()
        }
        return typeset
    }

    private func text(_ source: String) -> String { String(line(source).characters) }

    /// The text of each run with how far it is raised.
    private func offsets(_ source: String) -> [(String, CGFloat)] {
        let typeset = line(source)
        return typeset.runs.map { (String(typeset[$0.range].characters), $0.baselineOffset ?? 0) }
    }

    func testAFormulaReadsOnOneLine() {
        XCTAssertEqual(text("Sin[x]^2/(1+x)"), "sin2(x)/(1 + x)")
        XCTAssertEqual(text("Sqrt[a^2+b^2]"), "√(a2 + b2)")
        XCTAssertEqual(text("f[x_] := x^2"), "f(x_) := x2")
        XCTAssertEqual(text("Alpha + Pi*Theta"), "α + π\u{2009}θ")
        XCTAssertEqual(text("{1, 2}"), "{1, 2}")
        XCTAssertEqual(text("2*3"), "2 × 3")
        XCTAssertEqual(text("a/b"), "a/b")
        XCTAssertEqual(text("(a+b)/(c+d)"), "(a + b)/(c + d)")
        XCTAssertEqual(text("x -> 0"), "x → 0")
        XCTAssertEqual(text("a && b"), "a ∧ b")
        XCTAssertEqual(text("Binomial[n, k]"), "Cnk", "in a sentence, the way it always was")
        XCTAssertEqual(text("{{1,2},{3,4}}"), "(1, 2; 3, 4)")
    }

    func testPowersAreRaisedAndSubscriptsLowered() {
        XCTAssertTrue(offsets("x^2").contains { $0.0 == "2" && $0.1 > 0 })
        XCTAssertTrue(offsets("Subscript[x, i]").contains { $0.0 == "i" && $0.1 < 0 })
        XCTAssertTrue(offsets("Sin[x]^2").contains { $0.0 == "2" && $0.1 > 0 }, "the power on the name")
        // A power of a power is higher again: the offsets add.
        let nested = offsets("x^2^3")
        let two = nested.first { $0.0.contains("2") }!.1
        let three = nested.first { $0.0.contains("3") }!.1
        XCTAssertGreaterThan(three, two)
    }

    func testBigOperatorsCarryTheirLimitsAndShapesStillReadAsTheyDid() {
        let sum = text("Sum[1/n^2, {n, 1, Infinity}]")
        XCTAssertTrue(sum.hasPrefix("∑"), sum)
        XCTAssertTrue(sum.contains("n = 1") && sum.contains("∞"), sum)
        XCTAssertTrue(text("Integrate[x^2, {x, 0, 1}]").hasPrefix("∫"))
        XCTAssertTrue(text("Integrate[x^2, {x, 0, 1}]").hasSuffix(" dx"), text("Integrate[x^2, {x, 0, 1}]"))
        XCTAssertTrue(text("Integrate[Exp[-x^2], {x, -Infinity, Infinity}]").contains("e−x2"),
                      text("Integrate[Exp[-x^2], {x, -Infinity, Infinity}]"))
        XCTAssertTrue(text("Limit[Sin[x]/x, x -> 0]").hasPrefix("lim"))
        XCTAssertTrue(text("D[f[x], x]").contains("∂f(x)/∂x"), text("D[f[x], x]"))
        XCTAssertTrue(text("Product[i, {i, 1, n}]").hasPrefix("∏"))
    }

    func testGreekSpelledOutIsGreekInASentenceToo() {
        XCTAssertEqual(text("Alpha"), "α")
        XCTAssertEqual(text("Theta"), "θ")
        XCTAssertEqual(text("Pi"), "π")
        XCTAssertEqual(text("\\[Beta]"), "β")
    }

    func testWhatDoesNotParseIsNotTypeset() {
        XCTAssertNil(MathTypesetter.inline("Integrate["))
        XCTAssertNil(MathTypesetter.inline("x +"))
        XCTAssertNotNil(MathTypesetter.inline("Integrate[x^2, {x, 0, 1}]"))
        XCTAssertEqual(MathTypesetter.reading("Sin[x]"), "sin(x)")
        XCTAssertNil(MathTypesetter.reading("Sin[x"))
    }

    func testASentenceWithMathsInItTypesetsTheSpanAndLeavesTheCodeAlone() {
        let rendered = String(MarkdownInline.render("Area `wl:Sqrt[x^2 + 1]` and `let x = 1`.").characters)
        XCTAssertTrue(rendered.contains("√(x2 + 1)"), rendered)
        XCTAssertTrue(rendered.contains("let x = 1"), "a code span that is not WL is still code")
        let formula = String(MarkdownInline.render("So `wl:f[x_] := Sin[x]^2/(1+x)` holds.").characters)
        XCTAssertTrue(formula.contains("f(x_) := sin2(x)/(1 + x)"), formula)
        let broken = String(MarkdownInline.render("Half `wl:Sin[x` here.").characters)
        XCTAssertTrue(broken.contains("wl:Sin[x"), "broken maths is shown as it was typed: \(broken)")
    }

    func testNothingThrowsOnATreeOfAnyShape() {
        var random = SeededRandom(seed: 99)
        for _ in 0..<1500 {
            let tree = WLExpressionTests.tree(depth: 5, &random)
            let typeset = MathTypesetter.render(tree, size: 15)
            XCTAssertFalse(String(typeset.characters).isEmpty, WLPrinter.source(tree))
        }
    }
}
