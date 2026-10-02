import Combine
import SwiftUI
import XCTest
@testable import WriteMind

// HOW THE TABLET SITS (Sean, 2026-10-02: "make sure i can orient the page
// with the device by rotating or flipping to make it match portrait or
// landscape"): the four ways round by name, the one control that writes
// the turn, and the writing turning with the sheet — strokes, history, the
// box, and whatever is half-drawn — so it stays where it is on the tablet.

private func assertPoint(_ got: CGPoint, _ want: CGPoint, accuracy: CGFloat = 1e-12, _ message: String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(got.x, want.x, accuracy: accuracy, "\(got) is not \(want) \(message)", file: file, line: line)
    XCTAssertEqual(got.y, want.y, accuracy: accuracy, "\(got) is not \(want) \(message)", file: file, line: line)
}

/// Points all over the page, edges and corners included.
private let pagePoints: [CGPoint] = stride(from: 0.0, through: 1.0, by: 0.1).flatMap { x in
    stride(from: 0.0, through: 1.0, by: 0.125).map { y in CGPoint(x: x, y: y) }
} + [CGPoint(x: 0.3, y: 0.7), CGPoint(x: 1.0 / 3, y: 2.0 / 3), CGPoint(x: 0.123456789, y: 0.987654321)]

/// The four, by name, and what each one is.
final class TabletOrientationTests: XCTestCase {
    private let small = TabletExtent(width: 15200, height: 9500, countsPerMillimetre: 100)

    /// WACOM'S FOUR, in quarter turns clockwise from the way it ships:
    /// landscape, portrait, landscape flipped, portrait flipped.
    func testTheFourAreQuarterTurnsClockwiseFromTheWayItShips() {
        XCTAssertEqual(TabletOrientation.allCases.map(\.quarterTurns), [0, 1, 2, 3])
        XCTAssertEqual(TabletOrientation.allCases.map(\.isPortrait), [false, true, false, true])
        XCTAssertEqual(TabletOrientation(quarterTurns: 1), .portraitRight)
        XCTAssertEqual(TabletOrientation(quarterTurns: -1), .portraitLeft, "a quarter turn anticlockwise")
        XCTAssertEqual(TabletOrientation(quarterTurns: 6), .landscapeUpsideDown)
        XCTAssertEqual(TabletOrientation(quarterTurns: 4), .landscape)
        for orientation in TabletOrientation.allCases {
            XCTAssertEqual(TabletOrientation(quarterTurns: orientation.quarterTurns), orientation)
            XCTAssertEqual(TabletMapping.aspect(of: small, quarterTurns: orientation.quarterTurns) < 1,
                           orientation.isPortrait, "\(orientation.title) is the shape it says")
        }
    }

    /// It says plainly how the tablet sits: a name each, none the same,
    /// and a line on what was done to it.
    func testEachHasANameThatSaysHowTheTabletSits() {
        XCTAssertEqual(TabletOrientation.allCases.map(\.title),
                       ["Landscape", "Portrait — turned right", "Landscape — upside down", "Portrait — turned left"])
        for orientation in TabletOrientation.allCases {
            XCTAssertFalse(orientation.detail.isEmpty, orientation.title)
        }
        XCTAssertEqual(Set(TabletOrientation.allCases.map(\.detail)).count, 4)
    }

    /// THE GLYPH IS THE TABLET AS IT LIES: the bar it draws is on the edge
    /// the tablet's own top edge lands on — asked of the funnel's mapping,
    /// not written down a second time.
    func testTheGlyphMarksTheEdgeTheTabletsTopLandsOn() {
        for orientation in TabletOrientation.allCases {
            for x in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let top = TabletMapping.page(CGPoint(x: x * small.width, y: 0), extent: small,
                                             quarterTurns: orientation.quarterTurns)
                let onEdge: CGFloat
                switch orientation.topEdge {
                case .top: onEdge = top.y
                case .bottom: onEdge = 1 - top.y
                case .leading: onEdge = top.x
                case .trailing: onEdge = 1 - top.x
                }
                XCTAssertEqual(onEdge, 0, accuracy: 1e-12,
                               "\(orientation.title): the tablet's top edge is at \(top), not \(orientation.topEdge)")
            }
        }
        XCTAssertEqual(Set(TabletOrientation.allCases.map(\.topEdge)).count, 4, "four different pictures")
    }

    /// THE POPOVER SAYS WHAT A TURN DOES TO WHAT THE PEN WRITES ON. The
    /// control is live in Notebook mode too, and there the note's strokes
    /// are the note's and never turn — "its writing turns with it" said
    /// over a note was a promise the turn does not keep. And it says what
    /// the drawing's heavy edge is, or the four pictures are four shapes.
    func testThePopoverSaysWhatATurnDoesToWhatThePenWritesOn() {
        let page = TabletOrientationMenu.footer(for: .page)
        let notebook = TabletOrientationMenu.footer(for: .notebook)
        XCTAssertTrue(page.contains("its writing with it"), page)
        XCTAssertTrue(page.contains("laid out again for the new shape"), "the paper is not turned: \(page)")
        XCTAssertFalse(notebook.contains("writing with it"), "the note's strokes never turn: \(notebook)")
        XCTAssertTrue(notebook.contains("stays where it was written"), notebook)
        for footer in [page, notebook] {
            XCTAssertTrue(footer.contains("The heavy edge is the tablet's top"), footer)
        }
    }
}

/// The one turn, and the one control that writes it.
@MainActor
final class TabletOrientationStateTests: XCTestCase {
    private var suite: String!

    override func setUp() async throws {
        suite = "WriteMindTests-orientation-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    private func state() -> AppState { AppState(defaults: UserDefaults(suiteName: suite)!) }

    /// Portrait, turned right — one quarter turn clockwise — until it is
    /// turned (Sean, 2026-10-02).
    func testTheDefaultIsPortraitTurnedRight() {
        XCTAssertEqual(state().tabletOrientation, .portraitRight)
    }

    /// ONE WRITER: the way round picked by name is the turn stored, read
    /// back as the same name, and remembered.
    func testPickingAWayRoundIsTheOneTurn() {
        let app = state()
        app.orientTablet(.landscapeUpsideDown)
        XCTAssertEqual(app.tabletQuarterTurns, 2)
        XCTAssertEqual(state().tabletOrientation, .landscapeUpsideDown, "remembered")
        app.orientTablet(.landscape)
        XCTAssertEqual(app.tabletQuarterTurns, 0)
        for orientation in TabletOrientation.allCases {
            app.orientTablet(orientation)
            XCTAssertEqual(app.tabletOrientation, orientation)
            XCTAssertEqual(state().tabletOrientation, orientation)
        }
    }

    /// The way it already sits, picked again, is no turn at all — nothing
    /// is published, so nothing downstream turns.
    func testPickingTheWayItAlreadySitsIsNoTurn() {
        let app = state()
        var heard = 0
        let watching = app.$tabletQuarterTurns.dropFirst().sink { _ in heard += 1 }
        defer { watching.cancel() }
        app.orientTablet(.portraitRight)
        XCTAssertEqual(heard, 0)
        app.orientTablet(.landscape)
        XCTAssertEqual(heard, 1)
    }
}

/// THE WRITING TURNS WITH THE PAGE: the pure turn, and every place that
/// holds page fractions turned by it together.
@MainActor
final class PageTurnTests: XCTestCase {
    private let a = pageStroke([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.15), CGPoint(x: 0.3, y: 0.7)],
                               pressures: [0.2, 0.5, 0.9])
    private let b = pageStroke([CGPoint(x: 0.5, y: 0.5)], pressures: [0.9])

    /// FOUR QUARTER TURNS ARE NO TURN: by any number of turns and back is
    /// where it started, a turn is the same turn four on or four back, and
    /// two turns are their sum — within floating error, which `1 − (1 − x)`
    /// is allowed.
    func testAnyTurnAndBackIsWhereItStarted() {
        for point in pagePoints {
            XCTAssertEqual(TabletPage.turned(point, by: 0), point, "no turn moves nothing")
            var round = point
            for _ in 0..<4 { round = TabletPage.turned(round, by: 1) }
            assertPoint(round, point, "four quarter turns")
            for by in 0..<4 {
                assertPoint(TabletPage.turned(TabletPage.turned(point, by: by), by: 4 - by), point,
                            "by \(by) and back")
                assertPoint(TabletPage.turned(TabletPage.turned(point, by: by), by: -by), point,
                            "by \(by) and back the other way")
                assertPoint(TabletPage.turned(point, by: by + 4), TabletPage.turned(point, by: by))
                assertPoint(TabletPage.turned(point, by: by - 4), TabletPage.turned(point, by: by))
                for then in 0..<4 {
                    assertPoint(TabletPage.turned(TabletPage.turned(point, by: by), by: then),
                                TabletPage.turned(point, by: by + then), "by \(by) then \(then)")
                }
            }
        }
    }

    /// Each delta the way the sheet turns: clockwise, the top left corner
    /// goes to the top right, and a turned point stays on the page.
    func testEachDeltaTurnsTheSheetClockwise() {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        for by in 0..<4 {
            for (index, corner) in corners.enumerated() {
                assertPoint(TabletPage.turned(corner, by: by), corners[(index + by) % 4], "corner \(index) by \(by)")
            }
            for point in pagePoints {
                let turned = TabletPage.turned(point, by: by)
                XCTAssertTrue((0...1).contains(turned.x) && (0...1).contains(turned.y), "\(point) by \(by) left the page")
            }
        }
    }

    /// A BOX TURNS WITH THE SHEET, onto exactly the turned corners — so it
    /// is over the same writing — and four turns bring it back.
    func testABoxTurnsOverTheSameWriting() {
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.15)
        assertRect(TabletPage.turned(box, by: 1), CGRect(x: 0.65, y: 0.1, width: 0.15, height: 0.3))
        assertRect(TabletPage.turned(box, by: 2), CGRect(x: 0.6, y: 0.65, width: 0.3, height: 0.15))
        assertRect(TabletPage.turned(box, by: 3), CGRect(x: 0.2, y: 0.6, width: 0.15, height: 0.3))
        var round = box
        for _ in 0..<4 { round = TabletPage.turned(round, by: 1) }
        assertRect(round, box)
        // What it touches, the same strokes either way round — on the page
        // in its own points, which go from tall to wide.
        let strokes = [a, b, pageStroke([CGPoint(x: 0.9, y: 0.9)])]
        let tall = TabletPage.size(aspect: 0.625), wide = TabletPage.size(aspect: 1.6)
        let before = TabletSelection.touched(strokes, by: box, pageSize: tall)
        XCTAssertEqual(before.map(\.id), [a.id], "the box is round the first stroke alone")
        for by in 1..<4 {
            let turned = strokes.map { TabletPage.turned($0, by: by) }
            let after = TabletSelection.touched(turned, by: TabletPage.turned(box, by: by),
                                                pageSize: by % 2 == 0 ? tall : wide)
            XCTAssertEqual(after.map(\.id), [turned[0].id], "turned by \(by), the box is round another stroke")
        }
    }

    /// FROM EVERY WAY ROUND TO EVERY OTHER: every stroke and every page in
    /// the history turned by the same quarter turns, pressures kept — and
    /// not a step back.
    func testAligningTurnsEveryStrokeAndTheHistoryByTheSameTurns() {
        for from in 0..<4 {
            for to in 0..<4 {
                let page = TabletPage(url: nil)
                page.align(to: from)
                page.commit(a)
                page.commit(b)
                let by = page.align(to: to)
                XCTAssertEqual(by, TabletMapping.turns(to - from), "from \(from) to \(to)")
                XCTAssertEqual(page.history.count, 2, "a turn is not a step back")
                XCTAssertEqual(page.strokes.map(\.points),
                               [a, b].map { $0.points.map { TabletPage.turned($0, by: by) } }, "from \(from) to \(to)")
                XCTAssertEqual(page.strokes.map(\.pressures), [a.pressures, b.pressures])
                XCTAssertEqual(page.strokes.map(\.width), [a.width, b.width], "a width is in the page's own points")
                XCTAssertEqual(page.history.last?.map(\.points), [a.points.map { TabletPage.turned($0, by: by) }],
                               "the history turns with the page")
                page.undo()
                XCTAssertEqual(page.strokes.map(\.points), [a.points.map { TabletPage.turned($0, by: by) }],
                               "Undo brings the page back the way round it is now")
            }
        }
    }

    /// Four quarter turns, one at a time, and the page is as it was.
    func testTurningRoundOnceAQuarterAtATimeIsThePageAsItWas() {
        let page = TabletPage(url: nil)
        page.commit(a)
        for turns in [2, 3, 0, 1] { XCTAssertEqual(page.align(to: turns), 1) }
        XCTAssertEqual(page.align(to: 1), 0, "already that way round")
        let back = page.strokes.first?.points ?? []
        XCTAssertEqual(back.count, a.points.count)
        for (turned, original) in zip(back, a.points) { assertPoint(turned, original) }
    }
}

/// The shell: the page, the box and what is half-drawn turned together.
@MainActor
final class TabletScribeTurnTests: XCTestCase {
    private let extent = TabletExtent(width: 15200, height: 9500)

    private func point(_ x: CGFloat, _ y: CGFloat, tip: Bool, side: Bool = false, pressure: Double = 0.5,
                       at time: TimeInterval) -> TabletReading {
        TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: tip, sideSwitch: side, pressure: pressure,
                                   buttons: (tip ? 1 : 0) | (side ? 2 : 0)),
                      timestamp: time, native: false)
    }

    private func rig() -> (TabletInput, TabletPage, TabletScribe) {
        let input = TabletInput()
        input.extent = extent
        input.quarterTurns = 1
        let page = TabletPage(url: nil)
        return (input, page, TabletScribe(page: page, input: input))
    }

    /// The tablet turned, as the pane turns it: the funnel reads the new
    /// way round, and the scribe turns what is on the page.
    private func turn(_ input: TabletInput, _ scribe: TabletScribe, to turns: Int) {
        input.quarterTurns = turns
        scribe.align(to: turns)
    }

    /// THE BOX STAYS OVER THE WRITING: turned with the sheet, where it
    /// used to be put away.
    func testTheBoxTurnsWithTheSheetAndIsNotPutAway() {
        let (input, page, scribe) = rig()
        page.commit(pageStroke([CGPoint(x: 0.2, y: 0.3)]))
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.15)
        scribe.box.rect = box
        turn(input, scribe, to: 2)
        assertRect(scribe.box.rect, TabletPage.turned(box, by: 1))
        XCTAssertEqual(page.strokes.first?.points, [TabletPage.turned(CGPoint(x: 0.2, y: 0.3), by: 1)])
        turn(input, scribe, to: 1)
        assertRect(scribe.box.rect, box)
    }

    /// A STROKE HALF-WRITTEN WHEN THE TABLET TURNS joins on where the nib
    /// is: every point of it is where the counts put it the new way round.
    func testAStrokeUnderWayTurnsAndTheRestJoinsOn() throws {
        let (input, page, scribe) = rig()
        let counts = [CGPoint(x: 3800, y: 2375), CGPoint(x: 5000, y: 3000), CGPoint(x: 7600, y: 4750)]
        input.feed(point(counts[0].x, counts[0].y, tip: true, at: 1))
        input.feed(point(counts[1].x, counts[1].y, tip: true, at: 2))
        turn(input, scribe, to: 3)
        XCTAssertEqual(scribe.stroke?.points.count, 2, "the live stroke is still there")
        input.feed(point(counts[2].x, counts[2].y, tip: true, at: 3))
        input.feed(point(counts[2].x, counts[2].y, tip: false, at: 4))
        let stroke = try XCTUnwrap(page.strokes.first)
        let expected = counts.map { TabletMapping.page($0, extent: extent, quarterTurns: 3) }
        XCTAssertEqual(stroke.points.count, expected.count)
        for (got, want) in zip(stroke.points, expected) { assertPoint(got, want, accuracy: 1e-9) }
        XCTAssertEqual(stroke.pressures?.count, stroke.points.count, "the lockstep rule")
    }

    /// And a box being drawn with the side switch.
    func testABoxUnderWayTurnsAndTheRestJoinsOn() {
        let (input, _, scribe) = rig()
        input.feed(point(1000, 1000, tip: false, side: true, at: 1))
        input.feed(point(4000, 3000, tip: false, side: true, at: 2))
        turn(input, scribe, to: 2)
        input.feed(point(6000, 5000, tip: false, side: true, at: 3))
        input.feed(point(6000, 5000, tip: false, side: false, at: 4))
        let start = TabletMapping.page(CGPoint(x: 1000, y: 1000), extent: extent, quarterTurns: 2)
        let end = TabletMapping.page(CGPoint(x: 6000, y: 5000), extent: extent, quarterTurns: 2)
        assertRect(scribe.box.rect, TabletWriting.box(from: start, to: end))
    }

    /// Already that way round: nothing moves, and the box stays as it is.
    func testNoTurnMovesNothing() {
        let (_, page, scribe) = rig()
        page.commit(pageStroke([CGPoint(x: 0.2, y: 0.3)]))
        let before = page.strokes
        scribe.box.rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.15)
        scribe.align(to: 1)
        XCTAssertEqual(page.strokes, before, "not even a new id")
        assertRect(scribe.box.rect, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.15))
    }
}

/// Notebook mode: the area turns with the tablet, and the note does not.
@MainActor
final class NotebookTurnTests: XCTestCase {
    private func point(_ x: CGFloat, _ y: CGFloat, tip: Bool, at time: TimeInterval) -> TabletReading {
        TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: tip, sideSwitch: false, pressure: 0.5,
                                   buttons: tip ? 1 : 0),
                      timestamp: time, native: false)
    }

    private let extent = TabletExtent(width: 15200, height: 9500)
    private let pane = CGSize(width: 800, height: 600)

    private func place(_ turns: Int) -> NotebookPlace {
        NotebookPlace(pane: pane, scroll: 40, aspect: TabletMapping.aspect(of: extent, quarterTurns: turns),
                      note: "Letters.md", quarterTurns: turns)
    }

    /// A TURN UNDER THE NIB TAKES NOTHING WITH IT: the area turned under a
    /// stroke under way, the rest of it would land a quarter turn away
    /// from the start — so it is dropped, as for another note. The strokes
    /// already in the note are the note's, and nothing turns them.
    func testATurnUnderTheNibDropsTheStrokeUnderWay() {
        let input = TabletInput()
        input.extent = extent
        input.quarterTurns = 1
        input.aim(at: .notebook)
        let notebook = NotebookScribe()
        notebook.place = place(1)
        let scribe = TabletScribe(page: TabletPage(url: nil), input: input, notebook: notebook)
        withExtendedLifetime(scribe) {
            var landed: [Stroke] = []
            notebook.onStroke = { landed.append($0) }
            input.feed(point(3800, 2375, tip: true, at: 1))
            input.feed(point(4000, 2375, tip: false, at: 2))
            XCTAssertEqual(landed.count, 1)

            input.feed(point(3800, 2375, tip: true, at: 3))
            XCTAssertNotNil(notebook.stroke)
            input.quarterTurns = 0
            notebook.place = place(0)
            XCTAssertNil(notebook.stroke, "half a stroke left standing across the turn")
            input.feed(point(4000, 2375, tip: true, at: 4))
            input.feed(point(4000, 2375, tip: false, at: 5))
            XCTAssertEqual(landed.count, 1, "a stroke begun one way round landed the other")

            // The next one is written the new way round, on the new area.
            input.feed(point(0, 0, tip: true, at: 6))
            input.feed(point(0, 0, tip: false, at: 7))
            XCTAssertEqual(landed.count, 2)
            assertPoint(landed.last?.points.first ?? .zero, place(0).strokePoint(CGPoint(x: 0, y: 0)), accuracy: 1e-9)
        }
    }

    /// THE AREA FOLLOWS THE TURN: wide on the notes held landscape, tall
    /// held portrait, the tablet's top left corner where the turn puts it.
    func testTheAreaFollowsTheTurn() {
        for orientation in TabletOrientation.allCases {
            let area = place(orientation.quarterTurns).area
            XCTAssertEqual(area.height > area.width, orientation.isPortrait, orientation.title)
            let corner = place(orientation.quarterTurns)
                .onPane(TabletMapping.page(.zero, extent: extent, quarterTurns: orientation.quarterTurns))
            let expected = [CGPoint(x: area.minX, y: area.minY), CGPoint(x: area.maxX, y: area.minY),
                            CGPoint(x: area.maxX, y: area.maxY), CGPoint(x: area.minX, y: area.maxY)][orientation.quarterTurns]
            assertPoint(corner, expected, accuracy: 1e-9, orientation.title)
        }
    }
}
