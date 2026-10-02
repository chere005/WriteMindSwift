import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// The papers (Sean, 2026-10-02: "it can have themed backgrounds and
/// different pen colors and strokes to write with"): what each one is,
/// what it prints and how far apart — measured in the tablet's own
/// millimetres — and an ink that reads on it.
final class PageThemeTests: XCTestCase {
    /// The small One by Wacom, held turned as Sean holds it.
    private let small = CGSize(width: 95, height: 152)

    private func rows(_ print: PagePrint) -> [PagePrint.Rule] {
        print.rules.filter { $0.from.y == $0.to.y }.sorted { $0.from.y < $1.from.y }
    }

    private func columns(_ print: PagePrint) -> [PagePrint.Rule] {
        print.rules.filter { $0.from.x == $0.to.x }.sorted { $0.from.x < $1.from.x }
    }

    private func assertEvenlySpaced(_ values: [CGFloat], by step: Double, _ what: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(values.count, 1, what, file: file, line: line)
        for (a, b) in zip(values, values.dropFirst()) {
            XCTAssertEqual(Double(b - a), step, accuracy: 1e-9, "\(what): \(a) to \(b)", file: file, line: line)
        }
    }

    private func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let colour = NSColor(hex: hex)!.usingColorSpace(.sRGB)!
        return (Double(colour.redComponent) * 255, Double(colour.greenComponent) * 255, Double(colour.blueComponent) * 255)
    }

    func testEveryPaperHasANameAndALineAboutIt() {
        for theme in PageTheme.allCases {
            XCTAssertFalse(theme.title.isEmpty, "\(theme)")
            XCTAssertFalse(theme.detail.isEmpty, "\(theme)")
        }
        XCTAssertEqual(Set(PageTheme.allCases.map(\.title)).count, PageTheme.allCases.count)
    }

    /// Plain is white, the legal pad yellow, the blackboard a deep
    /// green-black — and every paper's own ink reads on it comfortably.
    func testEveryPaperHasAnInkThatReadsOnIt() throws {
        XCTAssertEqual(PageTheme.plain.paperHex, "#FFFFFF")
        let legal = rgb(PageTheme.legal.paperHex)
        XCTAssertTrue(legal.r > 230 && legal.g > 220 && legal.b < 190, "a legal pad is yellow, \(legal)")
        let board = rgb(PageTheme.blackboard.paperHex)
        XCTAssertTrue(board.r < 50 && board.g < 60 && board.b < 50 && board.g >= board.r && board.g >= board.b,
                      "the board is deep green-black, \(board)")
        XCTAssertTrue(PageTheme.blackboard.isDark)
        XCTAssertFalse(PageTheme.legal.isDark)
        for theme in PageTheme.allCases {
            let contrast = try XCTUnwrap(PageTheme.contrast(theme.defaultInk, theme.paperHex))
            XCTAssertGreaterThan(contrast, 7, "\(theme)'s own ink on its own paper")
        }
        XCTAssertGreaterThan(try XCTUnwrap(PageTheme.luminance(PageTheme.blackboard.defaultInk)), 0.7,
                             "the board's ink is chalk")
        XCTAssertEqual(PageTheme.ruled.defaultInk, "#1C1C1E")
    }

    /// RULED PAPER IS RULED 8 MM APART, from two rulings down, edge to edge
    /// in light blue — and a red margin two rulings in, top to bottom.
    func testRuledLinesAreEightMillimetresApartWithARedMargin() {
        let print = PageTheme.ruled.layout(millimetres: small)
        let lines = rows(print)
        assertEvenlySpaced(lines.map(\.from.y), by: 8.0 / 152, "the ruling")
        XCTAssertEqual(Double(lines.first?.from.y ?? 0), 16.0 / 152, accuracy: 1e-9, "two rulings of header")
        XCTAssertEqual(lines.count, 17, "16 mm to 144 mm, half a ruling clear of the foot")
        for rule in lines {
            XCTAssertEqual(rule.from.x, 0)
            XCTAssertEqual(rule.to.x, 1)
            let colour = rgb(rule.colorHex)
            XCTAssertGreaterThan(colour.b, colour.r + 40, "blue, \(rule.colorHex)")
        }
        let margin = columns(print)
        XCTAssertEqual(margin.count, 1)
        XCTAssertEqual(Double(margin.first?.from.x ?? 0), 16.0 / 95, accuracy: 1e-9)
        XCTAssertEqual(margin.first?.from.y, 0)
        XCTAssertEqual(margin.first?.to.y, 1)
        let red = rgb(margin.first?.colorHex ?? "#000000")
        XCTAssertGreaterThan(red.r, red.g + 60, "red")
    }

    /// A legal pad: the ruling, and a DOUBLE red margin.
    func testALegalPadIsRuledWithADoubleRedMargin() {
        let print = PageTheme.legal.layout(millimetres: small)
        assertEvenlySpaced(rows(print).map(\.from.y), by: 8.0 / 152, "the ruling")
        let margin = columns(print)
        XCTAssertEqual(margin.count, 2)
        guard margin.count == 2 else { return }
        XCTAssertEqual(Double(margin[0].from.x), 16.0 / 95, accuracy: 1e-9)
        XCTAssertEqual(Double(margin[1].from.x - margin[0].from.x) * 95, 1.2, accuracy: 1e-9, "1.2 mm apart")
        for rule in margin {
            let red = rgb(rule.colorHex)
            XCTAssertGreaterThan(red.r, red.g + 60, "red")
        }
    }

    /// DOTS AND SQUARES ARE 5 MM, as many as fit, centred — the paper left
    /// at both edges the same.
    func testDotsAndGraphSquaresAreFiveMillimetres() {
        let dots = PageTheme.dotGrid.layout(millimetres: small).dots
        let xs = Array(Set(dots.map(\.x))).sorted(), ys = Array(Set(dots.map(\.y))).sorted()
        XCTAssertEqual(xs.count, 19)
        XCTAssertEqual(ys.count, 30)
        XCTAssertEqual(dots.count, 19 * 30)
        assertEvenlySpaced(xs, by: 5.0 / 95, "dots across")
        assertEvenlySpaced(ys, by: 5.0 / 152, "dots down")
        XCTAssertEqual(Double(xs.first ?? 0), Double(1 - (xs.last ?? 1)), accuracy: 1e-9, "centred across")
        XCTAssertEqual(Double(ys.first ?? 0), Double(1 - (ys.last ?? 1)), accuracy: 1e-9, "centred down")

        let graph = PageTheme.graph.layout(millimetres: small)
        assertEvenlySpaced(columns(graph).map(\.from.x), by: 5.0 / 95, "squares across")
        assertEvenlySpaced(rows(graph).map(\.from.y), by: 5.0 / 152, "squares down")
        XCTAssertTrue(graph.rules.allSatisfy { ($0.from.x == 0 && $0.to.x == 1) || ($0.from.y == 0 && $0.to.y == 1) },
                      "every line runs edge to edge")
    }

    func testPlainAndTheBlackboardPrintNothing() {
        XCTAssertEqual(PageTheme.plain.layout(millimetres: small), PagePrint())
        XCTAssertEqual(PageTheme.blackboard.layout(millimetres: small), PagePrint())
    }

    /// THE RULING IS THE TABLET'S, NOT THE SHEET'S: a bigger tablet gets
    /// more lines 8 mm apart, not the same lines further apart — whatever
    /// size the pane shows the sheet at.
    func testABiggerTabletGetsMoreLinesNotFatterOnes() throws {
        let medium = try XCTUnwrap(TabletExtent.known(productID: 0x037B))
        let millimetres = TabletMapping.millimetres(of: medium, quarterTurns: 1)
        XCTAssertEqual(millimetres, CGSize(width: 135, height: 216))
        let lines = rows(PageTheme.ruled.layout(millimetres: millimetres))
        assertEvenlySpaced(lines.map(\.from.y), by: 8.0 / 216, "the ruling on the medium tablet")
        XCTAssertGreaterThan(lines.count, rows(PageTheme.ruled.layout(millimetres: small)).count)
    }

    /// WHEN THE PAPER CHANGES, INK THAT WOULD NOT READ ON IT BECOMES THE
    /// PAPER'S OWN; ink that reads stays as it was picked.
    func testInkThatWouldNotReadOnTheNewPaperBecomesThePapersOwn() {
        let chalk = PageTheme.blackboard.defaultInk
        XCTAssertEqual(PageTheme.blackboard.readable("#1C1C1E"), chalk, "black on the board")
        XCTAssertEqual(PageTheme.plain.readable(chalk), PageTheme.plain.defaultInk, "chalk on white paper")
        XCTAssertEqual(PageTheme.legal.readable("#F5B700"), PageTheme.legal.defaultInk, "amber on a yellow pad")
        XCTAssertEqual(PageTheme.graph.readable("#2D7DD2"), "#2D7DD2", "blue reads on graph paper")
        XCTAssertEqual(PageTheme.blackboard.readable("#F2542D"), "#F2542D", "red reads on the board")
        XCTAssertEqual(PageTheme.ruled.readable("#2FBF71"), "#2FBF71", "green reads on white")
        XCTAssertEqual(PageTheme.ruled.readable("not a colour"), PageTheme.ruled.defaultInk)
    }

    /// ONLY THE CHANGE OF PAPER IS ANSWERED FOR: ink the new paper reads
    /// WORSE on, and not at all, becomes its own; a colour that read no
    /// worse on the paper before was picked on that paper, and stays.
    func testOnlyAPaperThatMakesTheInkReadWorseChangesIt() {
        let amber = "#F5B700", black = "#1C1C1E", chalk = PageTheme.blackboard.defaultInk
        XCTAssertEqual(PageTheme.ruled.ink(amber, after: .plain), amber, "white to white changes nothing under it")
        XCTAssertEqual(PageTheme.plain.ink(amber, after: .plain), amber, "the same paper picked again")
        XCTAssertEqual(PageTheme.blackboard.ink(black, after: .blackboard), black, "black picked on the board")
        XCTAssertEqual(PageTheme.ruled.ink(chalk, after: .graph), chalk, "chalk picked on white")
        XCTAssertEqual(PageTheme.blackboard.ink(black, after: .plain), chalk, "black onto the board")
        XCTAssertEqual(PageTheme.ruled.ink(chalk, after: .blackboard), black, "chalk off the board")
        XCTAssertEqual(PageTheme.legal.ink(amber, after: .plain), black, "amber onto the yellow pad reads worse")
        XCTAssertEqual(PageTheme.legal.ink("#2FBF71", after: .plain), "#2FBF71", "green still reads on the pad")
        XCTAssertEqual(PageTheme.blackboard.ink("#F2542D", after: .ruled), "#F2542D", "red reads on the board")
        XCTAssertEqual(PageTheme.ruled.ink("not a colour", after: .plain), PageTheme.ruled.defaultInk)
    }

    /// The board's own chalk is offered beside the app's six; on paper the
    /// six already have an ink that reads.
    func testTheBoardOffersItsChalk() {
        XCTAssertEqual(PageTheme.plain.swatches, AppState.presetColors)
        XCTAssertEqual(PageTheme.blackboard.swatches, AppState.presetColors + [PageTheme.blackboard.defaultInk])
    }
}

/// The page in the tablet's millimetres — what the paper is ruled by.
final class TabletMillimetreTests: XCTestCase {
    /// The small One by Wacom: 15200 × 9500 counts, a hundred to the
    /// millimetre — 152 × 95 mm, turned as the page is turned.
    func testTheSmallOneIsAHundredCountsAMillimetre() throws {
        let one = try XCTUnwrap(TabletExtent.known(productID: 0x037A))
        XCTAssertEqual(one.countsPerMillimetre, 100)
        XCTAssertEqual(one.millimetres, CGSize(width: 152, height: 95))
        XCTAssertEqual(TabletMapping.millimetres(of: one, quarterTurns: 1), CGSize(width: 95, height: 152))
        XCTAssertEqual(TabletMapping.millimetres(of: one, quarterTurns: 2), CGSize(width: 152, height: 95))
        XCTAssertEqual(TabletMapping.millimetres(of: one, quarterTurns: 3), CGSize(width: 95, height: 152))
    }

    /// A count past the edge moves the edge and not the scale.
    func testWideningKeepsTheScale() throws {
        let one = try XCTUnwrap(TabletExtent.known(productID: 0x037A))
        let wider = one.widened(toInclude: CGPoint(x: 15300, y: 100))
        XCTAssertEqual(wider.countsPerMillimetre, 100)
        XCTAssertEqual(Double(wider.millimetres?.width ?? 0), 153, accuracy: 1e-9)
    }

    /// Nobody has measured it: the small One's long side, at its own shape.
    func testAnUnmeasuredTabletIsTakenToBeTheSmallOnesLength() {
        let unknown = TabletExtent(width: 20000, height: 10000)
        XCTAssertNil(unknown.millimetres)
        XCTAssertEqual(TabletMapping.millimetres(of: unknown, quarterTurns: 1), CGSize(width: 76, height: 152))
        XCTAssertEqual(TabletMapping.assumedMillimetres(for: CGSize(width: 500, height: 800)),
                       CGSize(width: 95, height: 152))
    }
}

/// THE PANE AND THE PICTURE PRINT THE SAME PAPER: the pane's paper layer
/// and Image's picture of the page, for every paper, pixel for pixel —
/// and the paper is really printed, not two blanks agreeing.
@MainActor
final class PagePaperPrintTests: XCTestCase {
    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    func testThePaneAndThePicturePrintTheSamePaper() throws {
        let pageSize = CGSize(width: 250, height: 400)
        let millimetres = CGSize(width: 95, height: 152)
        for theme in PageTheme.allCases {
            let renderer = ImageRenderer(content: TabletPaperLayer(theme: theme, pageSize: pageSize,
                                                                   millimetres: millimetres)
                .frame(width: pageSize.width * 2, height: pageSize.height * 2))
            renderer.scale = 1
            let pane = try XCTUnwrap(renderer.cgImage, "\(theme)")
            let picture = try XCTUnwrap(TabletRender.image(of: [], region: CGRect(origin: .zero, size: pageSize),
                                                           pageSize: pageSize, theme: theme,
                                                           millimetres: millimetres, scale: 2), "\(theme)")
            XCTAssertEqual(pane.width, picture.width)
            XCTAssertEqual(pane.height, picture.height)
            let a = pixels(pane), b = pixels(picture)
            let paper = NSColor(hex: theme.paperHex)!.usingColorSpace(.sRGB)!
            let sheet = [paper.redComponent, paper.greenComponent, paper.blueComponent].map { Int($0 * 255) }
            var differing = 0, printed = 0
            let count = picture.width * picture.height
            for pixel in 0..<count {
                let at = pixel * 4
                if (0..<3).contains(where: { abs(Int(a[at + $0]) - Int(b[at + $0])) > 40 }) { differing += 1 }
                if (0..<3).contains(where: { abs(Int(b[at + $0]) - sheet[$0]) > 24 }) { printed += 1 }
            }
            XCTAssertLessThan(Double(differing) / Double(count), 0.01, "\(theme): the pane and the picture disagree")
            let prints = theme != .plain && theme != .blackboard
            if prints {
                XCTAssertGreaterThan(printed, count / 400, "\(theme) printed nothing")
            } else {
                XCTAssertEqual(printed, 0, "\(theme) prints nothing")
            }
        }
    }
}

/// A DARK PAPER IS STILL A SHEET ON THE BLACK PANE: the board has a faint
/// light edge, and it is drawn OVER the paper layer — under it, the paper's
/// own fill covered it and the board ran straight into the black. A white
/// paper has none.
@MainActor
final class TabletSheetEdgeTests: XCTestCase {
    private struct Picture {
        var data: [UInt8]
        var width: Int
        func green(x: Int, y: Int) -> Int { Int(data[(y * width + x) * 4 + 1]) }
        func red(x: Int, y: Int) -> Int { Int(data[(y * width + x) * 4]) }
    }

    private func render(_ theme: PageTheme) throws -> Picture {
        let page = TabletPage(url: nil)
        let view = TabletSheetView(page: page, scribe: TabletScribe(page: page, input: nil),
                                   pageSize: CGSize(width: 500, height: 800), size: CGSize(width: 200, height: 320),
                                   theme: theme, millimetres: CGSize(width: 95, height: 152),
                                   canTake: false, busy: false, onFullWindow: {}, onTake: { _, _ in })
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: image.width, height: image.height,
                                              bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Picture(data: data, width: image.width)
    }

    func testTheBoardHasAnEdgeOverItsPaper() throws {
        let board = try render(.blackboard)
        let middle = 320
        let inside = board.green(x: 40, y: middle)
        XCTAssertEqual(inside, 0x2A, accuracy: 2, "the board itself")
        XCTAssertGreaterThan(board.green(x: 1, y: middle), inside + 15, "the board's left edge shows")
        XCTAssertGreaterThan(board.green(x: 398, y: middle), inside + 15, "and its right")
        XCTAssertGreaterThan(board.green(x: 200, y: 1), inside + 15, "and its top")
    }

    func testAWhitePaperHasNoEdge() throws {
        let plain = try render(.plain)
        XCTAssertEqual(plain.red(x: 1, y: 320), 255, accuracy: 2)
        XCTAssertEqual(plain.red(x: 40, y: 320), 255, accuracy: 2)
    }
}

/// The page's own pen, remembered apart from the notebook's — and the
/// notebook pen's tool beside it.
final class PagePenTests: XCTestCase {
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "WriteMindTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testThePagesPenIsRememberedApartFromTheNotebooks() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.pageInkTool, .pen)
        XCTAssertEqual(state.pageInkHex, PageTheme.plain.defaultInk, "a first page is written in black")
        XCTAssertEqual(state.pageInkWidth, 3)
        XCTAssertEqual(state.penTool, .pen)
        state.pageInkTool = .brush
        state.pageInkHex = "#2D7DD2"
        state.pageInkWidth = 7
        state.penTool = .fountain
        let back = AppState(defaults: defaults)
        XCTAssertEqual(back.pageInkTool, .brush)
        XCTAssertEqual(back.pageInkHex, "#2D7DD2")
        XCTAssertEqual(back.pageInkWidth, 7)
        XCTAssertEqual(back.penTool, .fountain)
        XCTAssertEqual(back.penColorHex, AppState.presetColors[0], "the notebook's pen is its own")
        defaults.set("quill", forKey: "pageInkTool")
        XCTAssertEqual(AppState(defaults: defaults).pageInkTool, .pen, "a tool this build does not know is the pen")
    }

    /// Black ink, then the blackboard: chalk. Red ink, then white paper:
    /// still red. And remembered as it changed.
    func testAChangeOfPaperSwitchesInkThatWouldNotRead() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let state = AppState(defaults: defaults)
        state.pageInkHex = "#1C1C1E"
        state.pagePaperChanged(from: .plain, to: .blackboard)
        XCTAssertEqual(state.pageInkHex, PageTheme.blackboard.defaultInk)
        XCTAssertEqual(AppState(defaults: defaults).pageInkHex, PageTheme.blackboard.defaultInk)
        state.pagePaperChanged(from: .blackboard, to: .ruled)
        XCTAssertEqual(state.pageInkHex, PageTheme.ruled.defaultInk, "chalk on ruled paper")
        state.pageInkHex = "#F2542D"
        state.pagePaperChanged(from: .ruled, to: .blackboard)
        XCTAssertEqual(state.pageInkHex, "#F2542D", "red reads on the board and was picked")
        XCTAssertEqual(state.penColorHex, AppState.presetColors[0], "the notebook's pen is not the page's")
    }

    /// A COLOUR PICKED ON PURPOSE OUTLIVES A PAPER THAT CHANGES NOTHING
    /// UNDER IT: the paper in use picked again, or another white one. Black
    /// picked on the board stays black; amber on white stays amber.
    func testPickingThePaperAgainOrAnotherWhiteOneKeepsAPickedColour() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let state = AppState(defaults: defaults)
        state.pageInkHex = "#1C1C1E"
        state.pagePaperChanged(from: .blackboard, to: .blackboard)
        XCTAssertEqual(state.pageInkHex, "#1C1C1E", "black picked on the board, the board picked again")
        state.pageInkHex = "#F5B700"
        state.pagePaperChanged(from: .plain, to: .ruled)
        XCTAssertEqual(state.pageInkHex, "#F5B700", "amber from plain to ruled")
        state.pagePaperChanged(from: .ruled, to: .graph)
        XCTAssertEqual(state.pageInkHex, "#F5B700", "amber from ruled to graph")
        state.pagePaperChanged(from: .graph, to: .legal)
        XCTAssertEqual(state.pageInkHex, "#1C1C1E", "the yellow pad is where amber stops reading")
    }
}
