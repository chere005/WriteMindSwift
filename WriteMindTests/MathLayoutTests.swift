import AppKit
import PDFKit
import SwiftUI
import XCTest
@testable import WriteMind

/// MATHS IN TWO DIMENSIONS, MEASURED. Sean, 2026-10-03: "maths input should
/// also just allow for an expression ... and it would appear like the
/// derivatives or integrals". A formula puts a fraction in a sum and a root in
/// that, and stacked views each with a baseline of their own could not line
/// those up. These say where things are, in points: a row has one baseline,
/// a fraction's bar hangs where the signs of `+` and `=` are drawn, a
/// script is raised by how tall its base is, a bracket is as tall as what
/// it holds.
final class MathLayoutTests: XCTestCase {
    private let size: CGFloat = 20

    private func drawing(_ source: String, size: CGFloat = 20,
                         file: StaticString = #filePath, line: UInt = #line) -> MathDrawing {
        guard case .success(let expression) = WLParser.read(source) else {
            XCTFail("did not parse: \(source)", file: file, line: line)
            return MathDrawing()
        }
        return MathLayout.drawing(for: MathBuilder.box(expression), size: size)
    }

    private func run(_ text: String, in drawing: MathDrawing, file: StaticString = #filePath,
                     line: UInt = #line) -> MathDrawing.Run {
        guard let found = drawing.runs.first(where: { $0.text == text }) else {
            XCTFail("no run \"\(text)\" in \(drawing.runs.map(\.text))", file: file, line: line)
            return MathDrawing.Run(text: "", face: .roman, size: 0, origin: .zero)
        }
        return found
    }

    // MARK: - A row, a fraction, a script

    func testARowSitsOnOneBaselineWhateverIsStackedInIt() {
        let d = drawing("x + a/b")
        XCTAssertEqual(run("x", in: d).origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(run("+", in: d).origin.y, 0, accuracy: 0.001, "the sign is on the line of the x, not the top of the fraction")
        XCTAssertGreaterThan(run("a", in: d).origin.y, 0, "the numerator is above the line")
        XCTAssertLessThan(run("b", in: d).origin.y, 0, "the denominator is below it")
        // Left to right, in order, without overlap.
        let plus = run("+", in: d), numerator = run("a", in: d)
        XCTAssertGreaterThan(plus.origin.x, run("x", in: d).origin.x)
        XCTAssertGreaterThan(numerator.origin.x, plus.origin.x)
    }

    func testAFractionsBarHangsOnTheAxisBetweenItsParts() {
        let d = drawing("x + a/b")
        let bar = d.shapes.boundingBoxOfPath
        XCTAssertEqual(bar.midY, MathLayout.axis * size, accuracy: 0.5, "where the crossbar of a + is")
        XCTAssertLessThan(bar.height, 2, "a rule")
        XCTAssertGreaterThan(run("a", in: d).origin.y, bar.maxY, "the numerator's baseline is above the bar")
        XCTAssertLessThan(run("b", in: d).origin.y, bar.minY, "and the denominator's is below it")
        XCTAssertGreaterThan(bar.width, MathFonts.measure("a", face: .italic, size: size).advance)
    }

    func testAFractionAddsHeightAboveAndBelowTheLineAndNothingToTheWidthOfItsSurroundings() {
        let plain = drawing("x + a"), stacked = drawing("x + a/b")
        XCTAssertGreaterThan(stacked.ascent, plain.ascent)
        XCTAssertGreaterThan(stacked.descent, plain.descent + 0.3 * size)
        XCTAssertGreaterThan(stacked.height, plain.height + 0.5 * size)
    }

    func testTheDenominatorsBaselineHoldsStillForDenominatorsOfOrdinaryHeight() {
        // An x and a d are different heights; the baselines should not be.
        XCTAssertEqual(run("x", in: drawing("1/x")).origin.y, run("d", in: drawing("1/d")).origin.y, accuracy: 0.001)
    }

    func testAFractionInsideAFractionIsSmaller() {
        let d = drawing("1/(1 + 1/x)")
        XCTAssertGreaterThan(run("1", in: d).size, run("x", in: d).size)
        XCTAssertEqual(run("x", in: d).size, size * 0.96 * 0.82, accuracy: 0.001)
    }

    func testAScriptIsSmallerAndRaisedAndASubscriptLowered() {
        let power = drawing("x^2")
        XCTAssertEqual(run("2", in: power).size, size * MathLayout.scriptScale, accuracy: 0.001)
        XCTAssertGreaterThan(run("2", in: power).origin.y, 0.3 * size)
        XCTAssertEqual(run("x", in: power).origin.y, 0, accuracy: 0.001)
        XCTAssertLessThan(run("i", in: drawing("Subscript[x, i]")).origin.y, -0.1 * size)
        let tower = drawing("x^2^3")
        XCTAssertEqual(run("3", in: tower).size, size * pow(MathLayout.scriptScale, 2), accuracy: 0.001)
        XCTAssertGreaterThan(run("3", in: tower).origin.y, run("2", in: tower).origin.y)
    }

    func testAPowerOfSomethingTallIsRaisedByHowTallItIs() {
        XCTAssertGreaterThan(run("2", in: drawing("(a/b)^2")).origin.y, run("2", in: drawing("x^2")).origin.y)
        // sin²(x): the power on the name, at the height of any other power.
        XCTAssertEqual(run("2", in: drawing("Sin[x]^2")).size, size * MathLayout.scriptScale, accuracy: 0.001)
    }

    func testASubscriptAndASuperscriptTogetherDoNotTouch() {
        let both = MathLayout.drawing(for: .script(.glyphs("x", .italic), sup: .glyphs("2", .roman),
                                                   sub: .glyphs("i", .italic)), size: size)
        let up = run("2", in: both), down = run("i", in: both)
        XCTAssertGreaterThan(up.origin.y - down.origin.y, 0.3 * size)
    }

    // MARK: - Brackets, roots, big operators, matrices

    func testABracketIsAsTallAsWhatItHolds() {
        let small = drawing("Abs[x]"), tall = drawing("Abs[a/b]")
        XCTAssertGreaterThan(tall.shapes.boundingBoxOfPath.height, small.shapes.boundingBoxOfPath.height + 0.5 * size)
        let content = drawing("a/b")
        XCTAssertGreaterThanOrEqual(tall.shapes.boundingBoxOfPath.height, content.height - 0.1 * size)
        // Round ones too: a parenthesis round a fraction reaches past it.
        let round = drawing("(a/b)^2")
        XCTAssertGreaterThan(round.ascent, content.ascent - 0.01)
        // The fence is centred on the axis: as much above it as below.
        let bars = small.shapes.boundingBoxOfPath
        XCTAssertEqual(bars.midY, MathLayout.axis * size, accuracy: 0.05 * size)
    }

    func testARootHasItsRoofOverWhatItHolds() {
        let d = drawing("Sqrt[x]")
        let content = run("x", in: d)
        let shape = d.shapes.boundingBoxOfPath
        XCTAssertGreaterThan(shape.maxY, MathFonts.measure("x", face: .italic, size: size).ascent, "the roof is above the x")
        XCTAssertGreaterThanOrEqual(shape.maxX, content.origin.x + MathFonts.measure("x", face: .italic, size: size).advance,
                                    "and runs to its far edge")
        XCTAssertLessThan(shape.minX, content.origin.x, "the sign is in front of it")
        // A root of a fraction is as tall as the fraction.
        XCTAssertGreaterThan(drawing("Sqrt[a/b]").ascent, drawing("Sqrt[x]").ascent + 0.3 * size)
    }

    func testBigOperatorsCarryTheirLimitsOverAndUnderThemCentred() {
        let d = drawing("Sum[i, {i, 1, n}]")
        let sign = run("∑", in: d), upper = run("n", in: d)
        let lower = d.runs.first { $0.text == "1" }!
        XCTAssertGreaterThan(upper.origin.y, sign.origin.y + MathFonts.measure("∑", face: .roman, size: sign.size).ascent * 0.5,
                             "the end of the range is above the sign")
        XCTAssertLessThan(lower.origin.y, 0, "the start is below it")
        let signCentre = sign.origin.x + MathFonts.measure("∑", face: .roman, size: sign.size).advance / 2
        let upperCentre = upper.origin.x + MathFonts.measure("n", face: .italic, size: upper.size).advance / 2
        XCTAssertEqual(upperCentre, signCentre, accuracy: 0.25 * size, "centred over it")
        XCTAssertGreaterThan(sign.size, size, "bigger than the line it stands in")
        // The term follows on the line.
        XCTAssertEqual(d.runs.last?.origin.y ?? 1, 0, accuracy: 0.001)
    }

    func testAnIntegralsLimitsAreBesideTheSignAndTheSignIsCentredOnTheAxis() {
        let d = drawing("Integrate[f[x], {x, 0, 1}]")
        let sign = run("∫", in: d), top = run("1", in: d), foot = run("0", in: d)
        let signWidth = MathFonts.measure("∫", face: .roman, size: sign.size).advance
        XCTAssertGreaterThanOrEqual(top.origin.x, sign.origin.x + signWidth - 0.01, "to the right of it")
        XCTAssertGreaterThan(top.origin.y, 0.4 * size, "at its top")
        XCTAssertLessThan(foot.origin.y, -0.2 * size, "and its foot")
        XCTAssertGreaterThan(sign.size, 1.5 * size)
        // The sign is as far above the axis as below it, within its slant.
        let metrics = MathFonts.measure("∫", face: .roman, size: sign.size)
        let centre = sign.origin.y + (metrics.ascent - metrics.descent) / 2
        XCTAssertEqual(centre, MathLayout.axis * size, accuracy: 0.02 * size)
    }

    func testAMatrixIsAGridOfCellsCentredInTheirColumns() {
        let d = drawing("{{a, bb}, {ccc, d}}")
        XCTAssertEqual(run("a", in: d).origin.y, run("bb", in: d).origin.y, accuracy: 0.001)
        XCTAssertEqual(run("ccc", in: d).origin.y, run("d", in: d).origin.y, accuracy: 0.001)
        XCTAssertGreaterThan(run("a", in: d).origin.y, run("ccc", in: d).origin.y + 0.5 * size)
        // The first column is as wide as ccc and a is centred in it.
        let a = run("a", in: d), c = run("ccc", in: d)
        let aCentre = a.origin.x + MathFonts.measure("a", face: .italic, size: size).advance / 2
        let cCentre = c.origin.x + MathFonts.measure("ccc", face: .italic, size: size).advance / 2
        XCTAssertEqual(aCentre, cCentre, accuracy: 0.1 * size, "within the lean of an italic")
        XCTAssertGreaterThan(run("bb", in: d).origin.x, c.origin.x + MathFonts.measure("ccc", face: .italic, size: size).advance)
        // With brackets at both ends as tall as the grid.
        XCTAssertGreaterThan(d.shapes.boundingBoxOfPath.height, 2 * size)
    }

    func testARaggedMatrixStillLaysOut() {
        let d = drawing("{{a}, {b, c}}")
        XCTAssertEqual(d.runs.map(\.text).sorted(), ["a", "b", "c"])
        XCTAssertGreaterThan(d.width, 0)
    }

    // MARK: - Measurements that hold everywhere

    func testNothingIsLeftOutsideItsOwnBox() {
        for (source, _) in MathBuilderTests.decided {
            let d = drawing(source)
            XCTAssertTrue(d.width.isFinite && d.ascent.isFinite && d.descent.isFinite, source)
            XCTAssertGreaterThan(d.width, 0, source)
            XCTAssertGreaterThan(d.height, 0, source)
            for run in d.runs {
                XCTAssertGreaterThanOrEqual(run.origin.x, -0.001, "\(source): \(run.text)")
                XCTAssertLessThanOrEqual(run.origin.x, d.width + 0.001, "\(source): \(run.text)")
                XCTAssertLessThanOrEqual(run.origin.y, d.ascent + 0.001, "\(source): \(run.text)")
                XCTAssertGreaterThanOrEqual(run.origin.y, -d.descent - 0.001, "\(source): \(run.text)")
            }
            if !d.shapes.isEmpty {
                let box = d.shapes.boundingBoxOfPath
                XCTAssertGreaterThanOrEqual(box.minX, -0.5, source)
                XCTAssertLessThanOrEqual(box.maxX, d.width + 0.5, source)
                XCTAssertLessThanOrEqual(box.maxY, d.ascent + 0.5, source)
                XCTAssertGreaterThanOrEqual(box.minY, -d.descent - 0.5, source)
            }
        }
    }

    func testEveryShapeInThePaletteIsSetAtASaneSize() {
        for template in MathTemplate.all {
            let wl = template.wl(template.initialValues)
            let d = drawing(wl)
            XCTAssertTrue(d.width > 0 && d.width < 40 * size, "\(template.id): \(d.width)")
            XCTAssertTrue(d.height > 0 && d.height < 12 * size, "\(template.id): \(d.height)")
        }
    }

    func testItScalesWithTheSizeItIsSetAt() {
        for source in ["x + a/b", "Sum[1/n^2, {n, 1, Infinity}]", "Sqrt[a^2 + b^2]", "{{1, 2}, {3, 4}}"] {
            let small = drawing(source, size: 20), big = drawing(source, size: 40)
            XCTAssertEqual(big.width / small.width, 2, accuracy: 0.12, source)
            XCTAssertEqual(big.height / small.height, 2, accuracy: 0.12, source)
        }
    }

    func testNothingThrowsOrDivergesOnATreeOfAnyShape() {
        var random = SeededRandom(seed: 5)
        for _ in 0..<800 {
            let tree = WLExpressionTests.tree(depth: 5, &random)
            let d = MathLayout.drawing(for: MathBuilder.box(tree), size: 18)
            XCTAssertTrue(d.width.isFinite && d.ascent.isFinite && d.descent.isFinite, WLPrinter.source(tree))
            XCTAssertLessThan(d.width, 200_000, WLPrinter.source(tree))
        }
    }

    func testTheDeepestThingTheParserAllowsIsStillSet() {
        let nested = String(repeating: "(", count: 250) + "x" + String(repeating: ")", count: 250)
        let d = drawing(nested)
        XCTAssertTrue(d.width.isFinite && d.width > 0)
        let powers = drawing("x" + String(repeating: "^x", count: 60))
        XCTAssertTrue(powers.width.isFinite && powers.width > 0)
        let fractions = drawing(String(repeating: "1/(1 + ", count: 40) + "x" + String(repeating: ")", count: 40))
        XCTAssertTrue(fractions.height.isFinite && fractions.height > 0)
        // Long chains are shallow to the parser and deep in the tree: a
        // thousand divisions, nearly two thousand primes, a quarter
        // thousand roots in roots, and the typesetter is still on its feet.
        for source in [String(repeating: "a/", count: 990) + "a", "f" + String(repeating: "'", count: 1900) + "[x]",
                       String(repeating: "Sqrt[", count: 250) + "1" + String(repeating: "]", count: 250),
                       String(repeating: "f[", count: 250) + "a" + String(repeating: "]", count: 250)] {
            let deep = drawing(source)
            XCTAssertTrue(deep.width.isFinite && deep.width > 0, String(source.prefix(20)))
            XCTAssertNotNil(MathTypesetter.inline(source), String(source.prefix(20)))
        }
    }

    // MARK: - Painted

    /// A drawing as the pixels `MathView` puts on a page, through the
    /// renderer the PDF export uses.
    @MainActor
    private func image(_ source: String, size: CGFloat = 22, dark: Bool = false) -> NSBitmapImageRep? {
        let view = MathView(source: source, size: size)
            .environment(\.colorScheme, dark ? .dark : .light)
            .padding(4)
            .background(dark ? Color.black : Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg)
    }

    /// The bounding rows of ink: the pixels that are not the paper's.
    private func ink(_ bitmap: NSBitmapImageRep, dark: Bool = false) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>,
                                                                         countByRow: [Int])? {
        var rows: [Int] = [], columns: [Int] = []
        var counts = [Int](repeating: 0, count: bitmap.pixelsHigh)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let brightness = (colour.redComponent + colour.greenComponent + colour.blueComponent) / 3
                if dark ? brightness > 0.3 : brightness < 0.8 {
                    counts[y] += 1
                    rows.append(y)
                    columns.append(x)
                }
            }
        }
        guard let top = rows.min(), let bottom = rows.max(), let left = columns.min(), let right = columns.max() else { return nil }
        return (top...bottom, left...right, counts)
    }

    @MainActor
    func testItIsPaintedAndTheRightWayUp() throws {
        // T has its bar at the top: more ink in its top row than its bottom.
        let bitmap = try XCTUnwrap(image("T", size: 40))
        let found = try XCTUnwrap(ink(bitmap), "nothing was painted")
        let top = found.countByRow[found.rows.lowerBound + 1], bottom = found.countByRow[found.rows.upperBound - 1]
        XCTAssertGreaterThan(top, bottom * 2, "upright: the crossbar is over the stem")
    }

    @MainActor
    func testAFractionIsPaintedAsTallerThanTheLineItIsIn() throws {
        let line = try XCTUnwrap(ink(try XCTUnwrap(image("x + a"))))
        let stacked = try XCTUnwrap(ink(try XCTUnwrap(image("x + a/b"))))
        XCTAssertGreaterThan(stacked.rows.count, line.rows.count + 12, "in device pixels at 2×")
        XCTAssertGreaterThan(stacked.columns.count, line.columns.count - 2)
    }

    @MainActor
    func testItDrawsInTheColourTheAppearanceAsksFor() throws {
        XCTAssertNotNil(ink(try XCTUnwrap(image("Sum[1/n^2, {n, 1, Infinity}]")), dark: false))
        XCTAssertNotNil(ink(try XCTUnwrap(image("Sum[1/n^2, {n, 1, Infinity}]", dark: true)), dark: true),
                        "on a dark page it is light, not black on black")
    }

    /// The page as the PDF export draws it: `ImageRenderer` into a PDF
    /// context, which is where a Canvas that guessed which way is up would
    /// show it.
    @MainActor
    private func pdf(_ source: String, size: CGFloat) -> PDFDocument? {
        let renderer = ImageRenderer(content: MathView(source: source, size: size).padding(4))
        let data = NSMutableData()
        renderer.render { size, render in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { return }
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
            context.closePDF()
        }
        return PDFDocument(data: data as Data)
    }

    @MainActor
    func testInAPDFItIsRealTextTheRightWayUp() throws {
        let document = try XCTUnwrap(pdf("Sin[x]^2/(1+x)", size: 22))
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertTrue((page.string ?? "").contains("sin"), "text, not a picture of text: \(page.string ?? "nil")")
        let tee = try XCTUnwrap(pdf("T", size: 40)?.page(at: 0))
        let thumbnail = tee.thumbnail(of: CGSize(width: 200, height: 200), for: .mediaBox)
        let bitmap = try XCTUnwrap(thumbnail.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let found = try XCTUnwrap(ink(bitmap))
        let top = found.countByRow[found.rows.lowerBound + 2], bottom = found.countByRow[found.rows.upperBound - 2]
        XCTAssertGreaterThan(top, bottom * 2, "the crossbar of the T is at the top")
    }

    @MainActor
    func testCanvasIsAsBigAsItsDrawingAndBrokenMathsIsShownAsTyped() throws {
        let d = drawing("Sqrt[a^2 + b^2]", size: 22)
        let bitmap = try XCTUnwrap(image("Sqrt[a^2 + b^2]", size: 22))
        // 4 points of padding each side, drawn at 2×.
        XCTAssertEqual(CGFloat(bitmap.pixelsWide), (MathCanvas.size(of: d).width + 8) * 2, accuracy: 3)
        XCTAssertEqual(CGFloat(bitmap.pixelsHigh), (MathCanvas.size(of: d).height + 8) * 2, accuracy: 3)
        // A formula that does not read is still the user's text.
        let broken = try XCTUnwrap(image("Sqrt[a^2"))
        XCTAssertNotNil(ink(broken), "the source, as it was typed")
    }
}
