import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// THINGS MULTIPLIED ARE ON ONE LINE, SIDE BY SIDE. Sean, 2026-10-03, with
/// two screenshots of a Wolfram result `(-2*x) * (E^-(x^2))`: "how is the
/// math being formatted? this is terrible, things multiplied should be on
/// the same line horizontally". It was set as "(-2) x" with the e and its
/// exponent lower and smaller than the rest — the old typesetter, a pile of
/// attributed runs with baseline offsets, which is gone. What there is now is
/// one builder (`MathBuilder`) and two painters, and these hold the three
/// things that were said about it:
///
/// 1. every factor of a product shares ONE baseline, in two dimensions and in
///    a sentence, whatever the factor is (a number, a letter, a function, a
///    power with a negative or bracketed exponent, a fraction, a root, a sum
///    in brackets) — scripts are raised relative to it, never moved off it;
/// 2. the brackets Mathematica's traditional form does not draw are not
///    drawn — a factor that is only a product, or a negated product in front,
///    is part of the product: `-2 x e^{-x²}`, not `(-2x) e^{-x²}` — while the
///    brackets round a sum, or round anything whose meaning they carry, stay;
/// 3. every place that typesets WL goes through that one builder.
final class MathProductTests: XCTestCase {
    private let size: CGFloat = 20

    private func expression(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> WLExpr? {
        guard case .success(let parsed) = WLParser.read(source) else {
            XCTFail("did not parse: \(source)", file: file, line: line)
            return nil
        }
        return parsed
    }

    private func outline(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        expression(source, file: file, line: line).map { MathBuilder.box($0).outline } ?? ""
    }

    private func drawing(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> MathDrawing {
        guard let parsed = expression(source, file: file, line: line) else { return MathDrawing() }
        return MathLayout.drawing(for: MathBuilder.box(parsed), size: size)
    }

    // MARK: - The brackets a product does not need

    /// What each product is set as, with the gaps left out. The first is
    /// Sean's.
    static let flattened: [(String, String)] = [
        ("(-2*x) * (E^-(x^2))", "−2xe^{−x^{2}}"),
        ("(-2*x) * E^(-x^2)", "−2xe^{−x^{2}}"),
        ("-2*x*E^(-x^2)", "−2xe^{−x^{2}}"),
        ("(-2)*x", "−2x"),
        ("(-2)*x*E^(-x^2)", "−2xe^{−x^{2}}"),
        ("(-x)*y", "−xy"),
        ("(-x^2)*y", "−x^{2}y"),
        ("(-2*x)*(3*y)", "−2x·3y"),
        ("a*(b*c)", "abc"),
        ("a*(b*c)*d", "abcd"),
        ("x*(y*(z*w))", "xyzw"),
        ("2*(3*x)", "2×3x"),
        ("(a*b)*(c*d)", "abcd"),
        ("Times[a, Times[b, c]]", "abc"),
        ("Times[Times[a, b], c]", "abc"),
        ("a*Times[b, Sin[x]]", "absin(x)"),
        // A sum in the front of a negation keeps the brackets the sum needs.
        ("(-(a+b))*c", "−(a+b)c"),
        ("(-(-x))*y", "−(−x)y"),
    ]

    func testABracketedProductOrANegatedProductInFrontIsPartOfTheProduct() {
        for (source, expected) in Self.flattened {
            XCTAssertEqual(outline(source), expected, source)
        }
    }

    /// Brackets that carry a meaning stay.
    static let kept: [(String, String)] = [
        ("(a+b)*c", "(a+b)c"),
        ("(a+b)*(c+d)", "(a+b)(c+d)"),
        ("a*(b-c)*d", "a(b−c)d"),
        // A sign anywhere but in front reads as a subtraction without them.
        ("x*(-y)", "x(−y)"),
        ("2*(-x)", "2(−x)"),
        ("a*(-2*x)", "a(−2x)"),
        // A product that is a base or a term is still a product in brackets.
        ("(a*b)^2", "(ab)^{2}"),
        ("((-2)*x)^2", "(−2x)^{2}"),
        ("a + (-2)*x", "a+(−2x)"),
        ("a - b*c", "a−bc"),
        // A fraction beside a number is not a mixed number.
        ("2*(1/3)", "2(\\frac{1}{3})"),
        ("x*(a/b)*y", "x(\\frac{a}{b})y"),
        // Division is not a product: a/(b*c) is a fraction over a product.
        ("a/(b*c)", "\\frac{a}{bc}"),
        ("(a*b)/c", "\\frac{ab}{c}"),
        ("-(a*b)", "−ab"),
        ("-(a+b)", "−(a+b)"),
        ("-(-x)", "−(−x)")
    ]

    func testBracketsRoundASumOrWhatChangesTheMeaningStay() {
        for (source, expected) in Self.kept {
            XCTAssertEqual(outline(source), expected, source)
        }
    }

    func testAProductWithASignInFrontIsASignedTermWhereverItIsUsed() {
        // As a term of a sum it is bracketed, as -x is; as a base it is bracketed; as an exponent or the
        // numerator of a fraction it is not (the typesetting is bigger and higher there already).
        guard let signed = expression("(-2)*x"), let plain = expression("2*x") else { return }
        XCTAssertEqual(MathBuilder.box(signed).level, WLLevel.sum, "a sign in front: a term, like -x")
        XCTAssertEqual(MathBuilder.box(plain).level, WLLevel.product)
        XCTAssertEqual(outline("e^((-2)*x)"), "e^{−2x}")
        XCTAssertEqual(outline("((-2)*x)/y"), "\\frac{−2x}{y}")
    }

    /// The stored text is the user's formula, not the display's: the same
    /// expression, spelled the one canonical way, brackets and all. Setting
    /// is a display decision and never rewrites the note.
    func testWhatIsStoredKeepsTheBracketsTheDisplayDrops() {
        var palette = MathPalette()
        palette.type("(-2*x) * (E^-(x^2))")
        XCTAssertEqual(palette.reading, .maths(canonical: "(-2*x)*E^(-x^2)"))
        XCTAssertEqual(palette.insertion, .maths("(-2*x)*E^(-x^2)", onItsOwnLine: true))
        XCTAssertEqual(WLParser.parse("(-2*x)*E^(-x^2)"), WLParser.parse("(-2*x) * (E^-(x^2))"), "and it reads back as the same tree")
        for (source, _) in Self.flattened + Self.kept {
            guard let tree = expression(source) else { continue }
            XCTAssertEqual(WLParser.parse(WLPrinter.source(tree)), tree, "\(source): the printer keeps the tree it was given")
        }
    }

    func testAnythingASentenceOrAPageHoldsReadsTheSameWithTheBracketsGone() {
        XCTAssertEqual(MathTypesetter.reading("(-2*x) * (E^-(x^2))"), "−2\u{2009}x\u{2009}e−x2", "a thin space between factors")
        let sentence = String(MarkdownInline.render("So `wl:(-2*x) * (E^-(x^2))` it is.").characters)
        XCTAssertTrue(sentence.contains("−2\u{2009}x\u{2009}e−x2"), sentence)
        XCTAssertFalse(sentence.contains("(−2"), sentence)
    }

    // MARK: - One baseline, in two dimensions

    /// Products with one kind of thing in them, each. Every one of them,
    /// and Sean's own, must put all of its factors on the one line.
    static let lines: [String] = [
        // numbers
        "2*3*4", "2 x 3", "-2*3", "3.5 x 10",
        // letters
        "a b c d", "x*y*z", "alpha beta gamma",
        // function calls
        "Sin[x] Cos[x] f[y]", "f[x] g[y] h[z]", "2 Sin[x] x", "Sin[x]^2 Cos[x]^2 x",
        // powers with negative or bracketed exponents
        "x^-2 y", "x^(-2) y^(a+b) z", "2^-x 3^(x+1)", "E^(-x^2) x", "x^2 y^3 z^-1", "(a+b)^2 c", "x^(a^2) y",
        // roots
        "Sqrt[x] y Sqrt[x+1]", "2 Sqrt[a^2+b^2] c", "x Sqrt[y Sqrt[z]] w",
        // sums in brackets
        "(a+b)(c+d) e", "x (a+b)^2 y", "a (b+c) (d-e) f",
        // and the one that was reported, in the shapes it can be written
        "(-2*x) * (E^-(x^2))", "-2 x E^(-x^2)", "(-2)*x*E^(-x^2)", "E^(-x^2) * (-2*x)",
        "a*(b*c)*d", "2*(3*x)", "Times[a, Times[b, c]]"
    ]

    func testEveryFactorOfAProductSitsOnTheOneBaseline() {
        for source in Self.lines {
            let d = drawing(source)
            let body = d.runs.filter { $0.size == size }
            XCTAssertFalse(body.isEmpty, source)
            for run in body {
                XCTAssertEqual(run.origin.y, 0, accuracy: 0.0001,
                               "\"\(run.text)\" of \(source) is off the line of its neighbours: \(d.runs.map { "\($0.text)@\($0.origin.y)" })")
            }
            // Side by side, in the order written.
            let xs = body.map(\.origin.x)
            XCTAssertEqual(xs, xs.sorted(), "\(source): left to right")
            XCTAssertEqual(Set(xs).count, xs.count, "\(source): none on top of another")
        }
    }

    func testScriptsAreRaisedFromTheBaselineAndNeverMovedOffItOrDownIt() {
        for source in Self.lines {
            let d = drawing(source)
            for run in d.runs where run.size < size {
                XCTAssertGreaterThan(run.origin.y, 0.3 * size,
                                     "\"\(run.text)\" of \(source) is a script, and sits above the line: \(run.origin.y)")
                XCTAssertLessThan(run.size, size, source)
            }
        }
        // The exponent stays at its base, not at the end of the line.
        let d = drawing("E^(-x^2) x")
        let e = d.runs.first { $0.text == "e" }!, minus = d.runs.first { $0.text == "−" }!, x = d.runs.last { $0.text == "x" }!
        XCTAssertGreaterThan(minus.origin.x, e.origin.x)
        XCTAssertLessThan(minus.origin.x, x.origin.x, "the exponent is before the x that follows it")
        XCTAssertEqual(e.origin.y, x.origin.y, accuracy: 0.0001, "the e and the x are on one line")
    }

    func testTheReportedResultHasItsEAndItsExponentOnTheLineOfTheTwoAndTheX() {
        let d = drawing("(-2*x) * (E^-(x^2))")
        XCTAssertEqual(d.runs.map(\.text).joined(), "−2xe−x2", "no bracket round the −2x")
        for text in ["−", "2", "x", "e"] {
            XCTAssertEqual(d.runs.first { $0.text == text }!.origin.y, 0, accuracy: 0.0001, text)
        }
        let big = d.runs.filter { $0.size == size }
        XCTAssertEqual(big.map(\.text), ["−", "2", "x", "e"], "the −2, the x and the e are all set at the one size")
        XCTAssertEqual(d.runs.filter { $0.size < size }.map(\.text), ["−", "x", "2"], "the exponent is smaller and higher, and only it")
    }

    /// A fraction is a factor like any other: its bar is on the axis of the
    /// line and the factors either side are on the line.
    func testAFractionAsAFactorHangsItsBarOnTheAxisAndLeavesTheOthersOnTheLine() {
        for source in ["a (b/c) d", "x (1/y) z", "2 (a/b) c"] {
            let d = drawing(source)
            let bar = d.shapes.boundingBoxOfPath
            for run in d.runs where run.size == size {
                XCTAssertEqual(run.origin.y, 0, accuracy: 0.0001, "\"\(run.text)\" of \(source)")
            }
            let stacked = d.runs.filter { $0.size < size }
            XCTAssertTrue(stacked.contains { $0.origin.y > 0 }, "\(source): a numerator above the line")
            XCTAssertTrue(stacked.contains { $0.origin.y < 0 }, "\(source): a denominator below it")
            // The bar of the fraction, within the fences round it, is on the axis (the fences' own reach is
            // symmetric about it, so the box of all the shapes is centred there too).
            XCTAssertEqual(bar.midY, MathLayout.axis * size, accuracy: 0.05 * size, source)
        }
        let first = drawing("(a/b) c (d/e)")
        for run in first.runs where run.size == size {
            XCTAssertEqual(run.origin.y, 0, accuracy: 0.0001, "\"\(run.text)\"")
        }
        XCTAssertEqual(first.shapes.boundingBoxOfPath.midY, MathLayout.axis * size, accuracy: 0.05 * size)
    }

    func testAProductAfterAFractionOrInsideARootOrAFenceStaysOnItsOwnLine() {
        // Nothing a factor holds drags the line of the others.
        let tall = drawing("(a/b) Sqrt[x] (c+d)")
        for run in tall.runs where run.size == size {
            XCTAssertEqual(run.origin.y, 0, accuracy: 0.0001, "\"\(run.text)\"")
        }
        XCTAssertGreaterThan(tall.ascent, drawing("a Sqrt[x] c").ascent, "though it is taller for what the fraction holds")
    }

    // MARK: - One baseline, in a sentence

    private func offsets(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> [(text: String, offset: CGFloat)] {
        guard let typeset = MathTypesetter.inline(source) else {
            XCTFail("did not typeset: \(source)", file: file, line: line)
            return []
        }
        return typeset.runs.map { (String(typeset[$0.range].characters), $0.baselineOffset ?? 0) }
    }

    func testInASentenceTheFactorsAreOnTheLineAndTheScriptsAreRaisedFromIt() {
        for source in Self.lines {
            let runs = offsets(source)
            XCTAssertFalse(runs.isEmpty, source)
            for run in runs {
                XCTAssertGreaterThanOrEqual(run.offset, 0, "\"\(run.text)\" of \(source) is lower than the line")
            }
            let line = runs.filter { $0.offset == 0 }.map(\.text).joined()
            XCTAssertFalse(line.isEmpty, source)
            XCTAssertFalse(line.contains("(−2") && source.hasPrefix("(-2"), "\(source): \(line)")
        }
        let reported = offsets("(-2*x) * (E^-(x^2))")
        XCTAssertEqual(reported.filter { $0.offset == 0 }.map(\.text).joined(), "−2\u{2009}x\u{2009}e", "the factors, on the line")
        XCTAssertEqual(reported.filter { $0.offset > 0 }.map(\.text).joined(), "−x2", "the exponent, raised")
        XCTAssertGreaterThan(reported.last!.offset, reported.first { $0.offset > 0 }!.offset, "and the square in it raised again")
    }

    // MARK: - Painted: what the screen shows

    /// How far above the foot of the picture the ink reaches, and how far
    /// the foot of the ink is from the bottom of the picture, in device
    /// pixels at 2x, for `view` on white paper. The picture is only as big as
    /// the thing in it, so a raised exponent makes it taller; what stays put
    /// is the line the letters stand on, which is the same distance from the
    /// bottom whatever is above it. (No letter below has a tail.)
    @MainActor
    private func ink(of view: some View, file: StaticString = #filePath, line: UInt = #line) throws -> (reach: Int, foot: Int) {
        let renderer = ImageRenderer(content: view.foregroundColor(.black).padding(6).background(Color.white))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage, file: file, line: line))
        var rows: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                // Transparent is paper, not black.
                let darkness = colour.alphaComponent * (1 - (colour.redComponent + colour.greenComponent + colour.blueComponent) / 3)
                if darkness > 0.25 { rows.append(y); break }
            }
        }
        let top = try XCTUnwrap(rows.min(), "nothing painted", file: file, line: line)
        let bottom = try XCTUnwrap(rows.max(), file: file, line: line)
        return (bottom - top, bitmap.pixelsHigh - 1 - bottom)
    }

    /// The SwiftUI side of the sentence's line: that `Text` really puts a
    /// factor's glyphs on the line and raises a script from it, as the
    /// attributes say.
    @MainActor
    func testTheSentenceIsPaintedWithEveryFactorOnTheLineAndTheExponentRaisedFromIt() throws {
        func painted(_ source: String) throws -> (reach: Int, foot: Int) {
            try ink(of: Text(try XCTUnwrap(MathTypesetter.inline(source, size: 24), source)))
        }
        let flat = try painted("a e x"), power = try painted("a e^2 x")
        XCTAssertEqual(power.foot, flat.foot, accuracy: 1, "the line the letters stand on does not move for a power")
        XCTAssertGreaterThan(power.reach, flat.reach + 12, "the exponent is above the letters beside it")

        let reported = try painted("(-2*x) * (E^-(x^2))"), bare = try painted("-2*x*E")
        XCTAssertEqual(reported.foot, bare.foot, accuracy: 1, "the e, the x and the 2 are on the one line")
        XCTAssertGreaterThan(reported.reach, bare.reach + 8)
    }

    /// And the two-dimensional painter's: what the page shows for a ```wl block.
    @MainActor
    func testTheBlockIsPaintedWithEveryFactorOnTheLineAndTheExponentRaisedFromIt() throws {
        func painted(_ source: String) throws -> (reach: Int, foot: Int) { try ink(of: MathView(source: source, size: 24)) }
        let flat = try painted("a e x"), power = try painted("a e^2 x")
        XCTAssertEqual(power.foot, flat.foot, accuracy: 1, "the line the letters stand on does not move for a power")
        XCTAssertGreaterThan(power.reach, flat.reach + 12, "the exponent is above the letters beside it")

        let reported = try painted("(-2*x) * (E^-(x^2))"), bare = try painted("-2*x*E")
        XCTAssertEqual(reported.foot, bare.foot, accuracy: 1, "the e, the x and the 2 are on the one line")
        XCTAssertGreaterThan(reported.reach, bare.reach + 8)
        // With no bracket round the −2x there is nothing but the exponent above the letters: the reach is that
        // of the sum of its parts, not a bracket's.
        let sans = try painted("-2*x*E^(-x^2)")
        XCTAssertEqual(reported.reach, sans.reach, accuracy: 1, "(-2*x)*(E^-(x^2)) is -2 x e^(-x^2) as set")
        XCTAssertEqual(reported.foot, sans.foot, accuracy: 1)
    }

    // MARK: - One typesetter

    /// Every place that typesets WL asks the one builder, and the places are
    /// these. A new one fails here and has to say it uses it. (The Out cell
    /// of an evaluation is not one of them: it is the plain text the engine
    /// printed, in monospace, by `EvalOutput`'s own rule.)
    func testEveryPlaceThatTypesetsMathsUsesTheOneBuilder() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "WriteMind", directoryHint: .isDirectory)
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }) ?? []
        XCTAssertGreaterThan(files.count, 100)
        func path(_ file: URL) -> String { String(file.path.dropFirst(root.path.count + 1)) }

        var scriptedByHand: [String] = [], users: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains("baselineOffset") { scriptedByHand.append(path(file)) }
            if path(file).hasPrefix("Math/") { continue }
            if ["MathTypesetter.", "MathView(", "MathLayout.", "MathBuilder.", "MathDrawing"].contains(where: source.contains) {
                users.append(path(file))
            }
        }
        // Raised and lowered text is written in one place for maths (the other is the folding typesetter, which
        // is not maths at all).
        XCTAssertEqual(scriptedByHand.sorted(), ["Editor/NotebookFolding.swift", "Math/MathTypesetter.swift"])
        // The sentence's `wl:` span, the page's ```wl block, the palette's preview — and nothing else.
        XCTAssertEqual(users.sorted(), ["Editor/MarkdownBlocks.swift", "Editor/MarkdownPreview.swift", "Views/MathMenu.swift"])

        // And what those three call is the builder: both painters read `MathBuilder.box`.
        let typesetter = try String(contentsOf: root.appending(path: "Math/MathTypesetter.swift"), encoding: .utf8)
        let view = try String(contentsOf: root.appending(path: "Math/MathView.swift"), encoding: .utf8)
        XCTAssertTrue(typesetter.contains("MathBuilder.box(expr)"))
        XCTAssertTrue(view.contains("MathBuilder.box(expression)"))
        // The out cell: plain text, never set.
        let out = try String(contentsOf: root.appending(path: "Eval/EvalOutput.swift"), encoding: .utf8)
        XCTAssertFalse(out.contains("MathTypesetter"))
        XCTAssertFalse(out.contains("MathView"))
    }
}
