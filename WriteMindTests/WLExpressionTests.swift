import XCTest
@testable import WriteMind

/// WHAT A FORMULA IS WRITTEN WITH, read back. Sean, 2026-10-03: "maths input
/// should also just allow for an expression so i could insert a function or
/// something and it would appear like the derivatives or integrals". The
/// parser used to read the handful of shapes the palette writes; these are
/// the expressions that were typed by hand, and what happens when one is
/// wrong.
final class WLExpressionTests: XCTestCase {
    private func parse(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> WLExpr {
        guard case .success(let expression) = WLParser.read(source) else {
            XCTFail("did not parse: \(source)", file: file, line: line)
            return .symbol("?")
        }
        return expression
    }

    private func canonical(_ source: String) -> String { WLPrinter.source(parse(source)) }

    private func failure(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> WLSyntaxError {
        guard case .failure(let error) = WLParser.read(source) else {
            XCTFail("parsed, and should not have: \(source)", file: file, line: line)
            return WLSyntaxError(message: "", offset: 0, length: 0)
        }
        return error
    }

    // MARK: - The expressions Sean named

    func testEveryExpressionNamedInTheRequestReads() {
        let named = [
            "Sin[x]^2/(1+x)", "Sqrt[a^2+b^2]", "Integrate[Exp[-x^2], {x, -Infinity, Infinity}]",
            "D[f[x], x]", "Sum[1/n^2, {n, 1, Infinity}]", "f[x_] := x^2", "Limit[Sin[x]/x, x -> 0]",
            "{{1,2},{3,4}}", "Alpha + Pi*Theta", "a^2 * b + c - d / e"
        ]
        for source in named { _ = parse(source) }
        XCTAssertEqual(canonical("Sin[x]^2/(1+x)"), "Sin[x]^2/(1 + x)")
        XCTAssertEqual(canonical("Integrate[Exp[-x^2], {x, -Infinity, Infinity}]"),
                       "Integrate[Exp[-x^2], {x, -Infinity, Infinity}]", "-x^2 is -(x^2), as WL has it")
        XCTAssertEqual(canonical("f[x_] := x^2"), "f[x_] := x^2")
        XCTAssertEqual(canonical("{{1,2},{3,4}}"), "{{1, 2}, {3, 4}}")
    }

    func testAMinusSignBindsLooserThanAPowerAndTighterThanASum() {
        // `Exp[-x^2]` was read as Exp[(-x)^2] — the palette's own improper
        // integral wrote the wrong maths into the note.
        XCTAssertEqual(parse("-x^2"), .negate(.binary("^", .symbol("x"), .number("2"))))
        XCTAssertEqual(parse("(-x)^2"), .binary("^", .negate(.symbol("x")), .number("2")))
        XCTAssertEqual(parse("-a*b + c"),
                       .binary("+", .negate(.binary("*", .symbol("a"), .symbol("b"))), .symbol("c")))
        XCTAssertEqual(parse("2^-x*3"),
                       .binary("*", .binary("^", .number("2"), .negate(.symbol("x"))), .number("3")),
                       "in an exponent the minus is the exponent's alone")
        XCTAssertEqual(canonical("a*-b"), "a*(-b)")
        XCTAssertEqual(canonical("(-a)*b"), "(-a)*b", "a negation as a factor keeps its brackets")
    }

    func testPowersAssociateToTheRightAndTwoThingsSideBySideAreAProduct() {
        XCTAssertEqual(parse("2^3^4"), .binary("^", .number("2"), .binary("^", .number("3"), .number("4"))))
        XCTAssertEqual(parse("2 x"), .binary("*", .number("2"), .symbol("x")))
        XCTAssertEqual(parse("2 x^2"), .binary("*", .number("2"), .binary("^", .symbol("x"), .number("2"))))
        XCTAssertEqual(parse("a/b/c"), .binary("/", .binary("/", .symbol("a"), .symbol("b")), .symbol("c")))
        XCTAssertEqual(canonical("a - (b - c)"), "a - (b - c)")
    }

    // MARK: - The rest of what a formula is written with

    func testRelationsLogicAssignmentsAndRules() {
        XCTAssertEqual(canonical("x!=y&&!z||w"), "x != y && !z || w")
        XCTAssertEqual(canonical("f[x_]:=x^2/;x>0"), "f[x_] := x^2 /; x > 0")
        XCTAssertEqual(canonical("a=1;b=2"), "a = 1; b = 2")
        XCTAssertEqual(canonical("x->y->z"), "x -> y -> z")
        XCTAssertEqual(canonical("(x->y)->z"), "(x -> y) -> z")
        XCTAssertEqual(canonical("a . b"), "a . b")
        // WL gives a comparison less than a sum, a rule less than both.
        XCTAssertEqual(parse("a + b == c -> d"),
                       .binary("->", .binary("==", .binary("+", .symbol("a"), .symbol("b")), .symbol("c")), .symbol("d")))
    }

    func testPatternsPartsPrimesFactorialsAndPureFunctions() {
        XCTAssertEqual(parse("x_"), .blank(name: "x", count: 1, head: nil))
        XCTAssertEqual(parse("x__"), .blank(name: "x", count: 2, head: nil))
        XCTAssertEqual(parse("_Integer"), .blank(name: nil, count: 1, head: "Integer"))
        XCTAssertEqual(parse("x_Real"), .blank(name: "x", count: 1, head: "Real"))
        XCTAssertEqual(canonical("m[[1,2]]"), "m[[1, 2]]")
        XCTAssertEqual(parse("m[[1]]"), .part(.symbol("m"), [.number("1")]))
        XCTAssertEqual(parse("f'[x]"), .call(.postfix("'", .symbol("f")), [.symbol("x")]))
        XCTAssertEqual(canonical("f''[x]"), "f''[x]")
        XCTAssertEqual(parse("n!"), .postfix("!", .symbol("n")))
        XCTAssertEqual(canonical("(n+1)!"), "(n + 1)!")
        XCTAssertEqual(parse("2^3!"), .binary("^", .number("2"), .postfix("!", .number("3"))),
                       "a factorial binds tighter than a power")
        XCTAssertEqual(canonical("#^2+1&"), "#^2 + 1 &")
        XCTAssertEqual(canonical("Map[#^2&, {1, 2}]"), "Map[#^2 &, {1, 2}]")
    }

    func testAPartIsTwoBracketsSideBySideAndACallOfAListIsNot() {
        XCTAssertEqual(parse("f[{1, 2}]"), .call(.symbol("f"), [.list([.number("1"), .number("2")])]))
        XCTAssertEqual(parse("f[g[x]]"), .call(.symbol("f"), [.call(.symbol("g"), [.symbol("x")])]))
        XCTAssertNotNil(WLParser.parse("a[[1]][[2]]"))
    }

    func testTypographyIsPutBackAndWhatIsStoredIsPlainWL() {
        // A keyboard's autocorrect and a paste from a page.
        XCTAssertEqual(canonical("x² + y³"), "x^2 + y^3")
        XCTAssertEqual(canonical("a − b"), "a - b")
        XCTAssertEqual(canonical("2 × 3"), "2*3")
        XCTAssertEqual(canonical("a ≤ b"), "a <= b")
        XCTAssertEqual(canonical("x → 0"), "x -> 0")
        XCTAssertEqual(canonical("Direction → “FromAbove”"), "Direction -> \"FromAbove\"")
        XCTAssertEqual(canonical("30°"), "30*Degree")
        XCTAssertEqual(canonical("x → ∞"), "x -> Infinity")
        XCTAssertEqual(canonical("(* a comment *) x"), "x", "WL's comments are skipped")
        XCTAssertEqual(canonical("\\[Alpha] + \\[Beta]"), "\\[Alpha] + \\[Beta]")
    }

    func testNumbersAreAsTyped() {
        XCTAssertEqual(parse("1.5"), .number("1.5"))
        XCTAssertEqual(parse(".5"), .number(".5"))
        XCTAssertEqual(parse("1.5 x"), .binary("*", .number("1.5"), .symbol("x")))
    }

    // MARK: - What is wrong, and where

    func testUnbalancedBracketsAreSaidInPlainWords() {
        let open = failure("Integrate[x^2, {x, 0, 1}")
        XCTAssertEqual(open.message, "Missing \"]\" — the \"[\" at position 10 is never closed.")
        XCTAssertEqual(open.offset, 9)
        XCTAssertEqual(failure("(1 + 2").message, "Missing \")\" — the \"(\" at position 1 is never closed.")
        XCTAssertEqual(failure("{1, 2").message, "Missing \"}\" — the \"{\" at position 1 is never closed.")
        XCTAssertEqual(failure("Sin[x))").message, "The \"[\" at position 4 is closed by \")\" at position 6 — it needs \"]\".")
        XCTAssertEqual(failure("x + 1)").message, "Unexpected \")\" at position 6 — nothing is open to close.")
        // The innermost one still open is the one named.
        XCTAssertEqual(failure("f[g[x").offset, 3)
        // A bracket inside a string is a character.
        XCTAssertNotNil(WLParser.parse("\"a(b\" + 1"))
    }

    func testOtherMistakesSaySoToo() {
        XCTAssertEqual(failure("1 +").message, "Expected an expression after \"+\".")
        XCTAssertEqual(failure("1 +").offset, 3, "at the end, where something is missing")
        XCTAssertEqual(failure("* 2").message, "Expected an expression before \"*\".")
        XCTAssertEqual(failure("x ,").message, "Unexpected \",\" at position 3.")
        XCTAssertEqual(failure("f[x,]").message, "Expected an expression after \",\".")
        XCTAssertEqual(failure("x = ").message, "Expected an expression after \"=\".")
        XCTAssertTrue(failure("|x|").message.contains("Abs[x]"), "the way WL writes an absolute value")
        XCTAssertEqual(failure("\"abc").message, "A string is missing its closing quote.")
        XCTAssertEqual(failure("(* never closed").message, "A comment (* … is never closed with *).")
        XCTAssertEqual(failure("\\[Alpha").message, "A \\[Name] is missing its closing ].")
        XCTAssertEqual(failure("   ").message, "There is nothing to typeset yet.")
        XCTAssertEqual(failure("x ? y").message, "Unexpected \"?\" at position 3.")
        XCTAssertEqual(failure("()").message, "Expected an expression after \"(\".")
        XCTAssertEqual(failure("()").offset, 1, "at the bracket that closes it")
    }

    // MARK: - A new line is a new statement, never a product

    // Review, 2026-10-03: a newline was whitespace, so `a = 1⏎b = 2` read as
    // `a = ((1*b) = 2)`, was typeset as "a = 1b = 2" and — through Insertion's
    // canonical step — written into the note as that one wrong formula.

    func testTwoCompleteExpressionsOnTwoLinesAreRefusedNotMultiplied() {
        for source in ["a = 1\nb = 2", "x\ny", "f[x] := x^2\ng[x] := x^3", "a\n+ b", "1\n2", "x^2\n(y + 1)",
                       "a = 1\r\nb = 2", "x\n\ny", "  x  \n  y  \n"] {
            guard case .failure(let error) = WLParser.read(source) else {
                return XCTFail("read as one expression, and it is two: \(source.debugDescription) → \(WLParser.parse(source).map(WLPrinter.source) ?? "?")")
            }
            XCTAssertTrue(error.message.contains("new line"), "\(source.debugDescription): \(error.message)")
            XCTAssertNil(WLParser.parse(source), source.debugDescription)
        }
        let error = failure("a = 1\nb = 2")
        XCTAssertEqual(error.message, "Maths holds one expression, and a new line starts a second one (position 7): "
                       + "join them with \";\" or insert them one at a time.")
        XCTAssertEqual(error.offset, 6, "at the first thing of the second line")
    }

    func testALineIsOnlyEndedWhereTheExpressionIsComplete() {
        // An operator left hanging goes on to the next line; so does anything inside a bracket.
        XCTAssertEqual(canonical("a +\nb"), "a + b")
        XCTAssertEqual(canonical("a *\n  b"), "a*b")
        XCTAssertEqual(canonical("a = 1;\nb = 2"), "a = 1; b = 2", "a `;` between them makes them one expression")
        XCTAssertEqual(canonical("Integrate[\n  Sin[x],\n  {x, 0, 1}\n]"), "Integrate[Sin[x], {x, 0, 1}]")
        XCTAssertEqual(canonical("{1,\n 2,\n 3}"), "{1, 2, 3}")
        XCTAssertEqual(canonical("m[[1,\n2]]"), "m[[1, 2]]")
        XCTAssertEqual(canonical("(a\n b)"), "a*b", "inside brackets a new line is a space, as in WL")
        // At the ends, and inside a comment or a string, a line break separates nothing.
        XCTAssertEqual(canonical("x^2\n"), "x^2")
        XCTAssertEqual(canonical("\n\n  x^2"), "x^2")
        XCTAssertEqual(canonical("a (* one\n line *) + b"), "a + b")
        XCTAssertEqual(canonical("a (* c *)\n"), "a")
        XCTAssertEqual(parse("\"two\nlines\""), .text("two\nlines"))
        // The first line unfinished is its own mistake, said first.
        XCTAssertEqual(failure("x +\n").message, "Expected an expression after \"+\".")
        XCTAssertTrue(failure("Sin[x\ny").message.hasPrefix("Missing \"]\""))
        // On one line, two things side by side are still a product.
        XCTAssertEqual(canonical("2 x"), "2*x")
    }

    func testSomethingElseOnTheNextLineIsNotCalledANewExpression() {
        XCTAssertEqual(failure("x\n, y").message, "Unexpected \",\" at position 3.")
    }

    func testTheOldWayOfAskingStillAnswersNilForBrokenMaths() {
        XCTAssertNil(WLParser.parse("Integrate["))
        XCTAssertNil(WLParser.parse("x +"))
        XCTAssertNil(WLParser.parse("{1, 2"))
    }

    // MARK: - It all comes back

    /// Every spelling that has a canonical form comes back as itself.
    static let corpus = [
        "Sin[x]^2/(1 + x)", "Sqrt[a^2 + b^2]", "-x^2", "(-a)*b", "a*(-b)", "a - (b - c)", "a - b - c",
        "f[x_] := x^2 /; x > 0", "2^(-x)*3", "!(a && b)", "!a == b", "-(-x)", "(a + b)^2", "a^(b + c)",
        "(a^b)^c", "a^b^c", "x -> y -> z", "(x -> y) -> z", "(n + 1)!", "n!!", "#^2 + 1 &", "{a, {b, c}}",
        "a = b = c", "f'[x]", "m[[1, 2]]", "x_Integer", "Integrate[f[x, y], {x, 0, 1}, {y, 0, 1}]",
        "Limit[1/x, x -> 0, Direction -> \"FromAbove\"]", "a . b . c", "a/b/c", "a/(b/c)", "(a + b)/(c + d)"
    ]

    func testCanonicalFormIsAFixedPoint() {
        for source in Self.corpus {
            XCTAssertEqual(canonical(source), source, "\(source) is canonical")
            XCTAssertEqual(parse(canonical(source)), parse(source))
        }
    }

    func testEverySpellingOfTheSameThingLandsOnOneForm() {
        XCTAssertEqual(WLPrinter.canonical("x^2+1"), WLPrinter.canonical("x ^ 2 + 1"))
        XCTAssertEqual(WLPrinter.canonical("x²+1"), WLPrinter.canonical("x^2 + 1"))
    }

    /// A tree is printed and read back as itself: whatever the printer
    /// writes, the parser meant. Random trees, a fixed seed.
    func testAnyTreePrintsAsWLThatReadsBackAsTheSameTree() {
        var random = SeededRandom(seed: 20261003)
        for _ in 0..<3000 {
            let tree = Self.tree(depth: 4, &random)
            let printed = WLPrinter.source(tree)
            guard case .success(let read) = WLParser.read(printed) else {
                XCTFail("\(printed) did not read back (\(tree))")
                continue
            }
            XCTAssertEqual(read, tree, "printed as \(printed)")
        }
    }

    private static let binaryOperators = ["+", "-", "*", "/", "^", "==", "!=", "<", ">=", "->", ":>", "&&", "||", "=",
                                          ":=", "/;", "/.", ".", ";", "==="]

    static func tree(depth: Int, _ random: inout SeededRandom) -> WLExpr {
        let leaves: [WLExpr] = [.number("2"), .number("1.5"), .symbol("x"), .symbol("y"), .symbol("Pi"),
                                .symbol("\\[Alpha]"), .symbol("#"), .text("ab"),
                                .blank(name: "x", count: 1, head: nil), .blank(name: nil, count: 2, head: "Integer")]
        if depth == 0 || random.next(below: 4) == 0 { return leaves[random.next(below: leaves.count)] }
        switch random.next(below: 9) {
        case 0: return .negate(tree(depth: depth - 1, &random))
        case 1: return .prefix("!", tree(depth: depth - 1, &random))
        case 2: return .postfix(["!", "'", "&"][random.next(below: 3)], tree(depth: depth - 1, &random))
        case 3:
            return .list((0..<random.next(below: 3)).map { _ in tree(depth: depth - 1, &random) })
        case 4:
            return .call(random.next(below: 4) == 0 ? tree(depth: depth - 1, &random) : .symbol("f"),
                         (0..<random.next(below: 3)).map { _ in tree(depth: depth - 1, &random) })
        case 5:
            return .part(.symbol("m"), (1...(1 + random.next(below: 2))).map { _ in tree(depth: depth - 1, &random) })
        default:
            let op = binaryOperators[random.next(below: binaryOperators.count)]
            return .binary(op, tree(depth: depth - 1, &random), tree(depth: depth - 1, &random))
        }
    }

    // MARK: - Odd input

    func testOddInputNeitherThrowsNorLoopsAndWhatReadsPrintsAndReadsAgain() {
        var random = SeededRandom(seed: 7)
        let pieces = ["x", "y", "Sin", "[", "]", "(", ")", "{", "}", ",", "+", "-", "*", "/", "^", "=", ":=", "->", "==",
                      "!", "'", "&", "&&", "||", "#", "_", "__", "\"", "“", "\\[", "\\[Alpha]", "(*", "*)", ".", ";",
                      "1", "2.5", ".5", " ", "\n", "²", "−", "×", "∞", "°", "|", "?", "@", "%", "~", "`", "é", "😀", "\u{0}"]
        for _ in 0..<4000 {
            let source = (0..<random.next(below: 40)).map { _ in pieces[random.next(below: pieces.count)] }.joined()
            switch WLParser.read(source) {
            case .failure(let error):
                XCTAssertFalse(error.message.isEmpty, source)
                XCTAssertTrue((0...source.count).contains(error.offset), "\(source) → \(error)")
            case .success(let expression):
                let printed = WLPrinter.source(expression)
                guard case .success(let again) = WLParser.read(printed) else {
                    XCTFail("\(source) printed as \(printed), which does not read")
                    continue
                }
                XCTAssertEqual(again, expression, "\(source) printed as \(printed)")
            }
        }
    }

    func testWhatIsTooLongOrTooDeepIsRefusedNotAttempted() {
        XCTAssertEqual(failure(String(repeating: "(", count: 1500)).offset, 1499, "brackets, said before the grammar")
        XCTAssertTrue(failure(String(repeating: "(", count: 100_000)).message.contains("too long"))
        XCTAssertTrue(failure(String(repeating: "(", count: 400) + "x" + String(repeating: ")", count: 400))
            .message.contains("nested too deeply"))
        XCTAssertTrue(failure(String(repeating: "-", count: 400) + "x").message.contains("nested too deeply"))
        XCTAssertTrue(failure(String(repeating: "a+", count: 50_000) + "a").message.contains("too long"))
        XCTAssertNotNil(WLParser.parse(String(repeating: "a+", count: 900) + "a"), "a long sum is still a sum")
        XCTAssertNotNil(WLParser.parse(String(repeating: "(", count: 250) + "x" + String(repeating: ")", count: 250)))
        XCTAssertNotNil(WLParser.parse("f" + String(repeating: "'", count: 1500) + "[x]"))
    }
}

/// A fixed sequence of numbers, so a failure is the same failure next time.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11
    }

    mutating func next(below limit: Int) -> Int { Int(next() % UInt64(max(limit, 1))) }
}
