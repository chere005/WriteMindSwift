import Combine
import SwiftUI
import XCTest
@testable import WriteMind

// HOW THE TABLET SITS (Sean, 2026-10-02: "make sure i can orient the page
// with the device by rotating or flipping to make it match portrait or
// landscape"): the four ways round by name, the one control that writes
// the turn, and the writing turning with the sheet — strokes, history, the
// box, and whatever is half-drawn — so it stays where it is on the tablet.
// And the picture of it: the tablet drawn with its LIGHT where the light
// really is (Sean, 2026-10-02: "make the tablet orientation icon show the
// led on the tablet for the icon to give orientation").

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
    /// and a line on what was done to it — and where that leaves its
    /// light, the thing to look for on the desk, its words held together
    /// (no-break spaces) so a wrapped row never breaks inside them.
    func testEachHasANameThatSaysHowTheTabletSits() {
        XCTAssertEqual(TabletOrientation.allCases.map(\.title),
                       ["Landscape", "Portrait — turned right", "Landscape — upside down", "Portrait — turned left"])
        func held(_ words: String) -> String { words.replacingOccurrences(of: " ", with: "\u{A0}") }
        XCTAssertEqual(TabletOrientation.allCases.map(\.detail),
                       ["As it ships" + held(" · light on the left"),
                        "A quarter turn clockwise" + held(" · light at the top"),
                        "Turned half way round, for the other hand" + held(" · light on the right"),
                        "A quarter turn anticlockwise, for the other hand" + held(" · light at the bottom")])
    }

    /// THE LIGHT GOES ROUND WITH THE TABLET (Sean, 2026-10-02: "make the
    /// tablet orientation icon show the led on the tablet for the icon to
    /// give orientation"). As it ships the LED is just inside the left
    /// edge, half way down — Wacom's own photo of the small One by Wacom —
    /// so turned right it is at the top, half way round on the right, and
    /// turned left at the bottom.
    func testTheLightIsOnTheEdgeTheTurnLeavesItOn() {
        XCTAssertEqual(TabletOrientation.led, CGPoint(x: 0, y: 0.5), "the left edge, half way down, as it ships")
        XCTAssertEqual(TabletOrientation.allCases.map(\.ledEdge), [.leading, .top, .trailing, .bottom])
        XCTAssertEqual(TabletOrientation.allCases.map(\.lightPlace),
                       ["on the left", "at the top", "on the right", "at the bottom"])
        let places = [CGPoint(x: 0, y: 0.5), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 1)]
        for (orientation, place) in zip(TabletOrientation.allCases, places) {
            assertPoint(orientation.ledPoint, place, orientation.title)
        }
    }

    /// ...BY THE PEN'S OWN TURN, not a second table of four: the place on
    /// the tablet where the light is, in counts, through the funnel's
    /// mapping, is where the picture has it — on its edge, half way along
    /// — whichever tablet it is. So a stroke written beside the light is
    /// beside the dot.
    func testTheLightGoesThroughTheTurnThePensCountsGoThrough() {
        let tablets = [small, TabletExtent(width: 21600, height: 13500), TabletExtent(width: 1, height: 1)]
        for orientation in TabletOrientation.allCases {
            for tablet in tablets {
                let counts = CGPoint(x: TabletOrientation.led.x * tablet.width,
                                     y: TabletOrientation.led.y * tablet.height)
                let page = TabletMapping.page(counts, extent: tablet, quarterTurns: orientation.quarterTurns)
                assertPoint(orientation.ledPoint, page, "\(orientation.title) on \(tablet)")
                let onEdge: CGFloat, along: CGFloat
                switch orientation.ledEdge {
                case .top: (onEdge, along) = (page.y, page.x)
                case .bottom: (onEdge, along) = (1 - page.y, page.x)
                case .leading: (onEdge, along) = (page.x, page.y)
                case .trailing: (onEdge, along) = (1 - page.x, page.y)
                }
                XCTAssertEqual(onEdge, 0, accuracy: 1e-12,
                               "\(orientation.title): the light is at \(page), not on \(orientation.ledEdge)")
                XCTAssertEqual(along, 0.5, accuracy: 1e-12, "\(orientation.title): half way along, not \(page)")
            }
        }
    }

    /// THE DOT IS ON THE TABLET: inside the outline and clear of its line,
    /// against the edge the light is on and half way along it — at the
    /// corner's size, the popover's, and bigger. And the outline is the
    /// tablet's shape turned, in the middle of its square.
    func testTheDotSitsJustInsideTheOutlineHalfWayAlongItsEdge() throws {
        for size: CGFloat in [14, 16, 26, 32, 64] {
            for orientation in TabletOrientation.allCases {
                let said = "\(orientation.title) at \(size)"
                let outline = TabletGlyph.outline(orientation, size: size)
                let light = TabletGlyph.light(orientation, size: size)
                let line = TabletGlyph.line(size: size)
                XCTAssertTrue(CGRect(x: 0, y: 0, width: size, height: size).contains(outline), said)
                XCTAssertEqual(outline.height > outline.width, orientation.isPortrait, said)
                XCTAssertEqual(max(outline.width, outline.height), size, said)
                assertPoint(CGPoint(x: outline.midX, y: outline.midY), CGPoint(x: size / 2, y: size / 2), said)

                XCTAssertTrue(outline.insetBy(dx: line, dy: line).contains(light),
                              "\(said): the dot \(light) is not inside the outline \(outline), clear of its line")
                XCTAssertEqual(light.width, light.height, accuracy: 1e-12, said)
                XCTAssertGreaterThanOrEqual(light.width, 3, "\(said): too small to see")

                let away: [Edge: CGFloat] = [.leading: light.midX - outline.minX, .trailing: outline.maxX - light.midX,
                                             .top: light.midY - outline.minY, .bottom: outline.maxY - light.midY]
                let own = try XCTUnwrap(away[orientation.ledEdge])
                for (edge, distance) in away where edge != orientation.ledEdge {
                    XCTAssertLessThan(own, distance - 1, "\(said): the dot is no nearer \(orientation.ledEdge) than \(edge)")
                }
                let gap = own - light.width / 2 - line
                XCTAssertGreaterThan(gap, 0, "\(said): the dot runs into the outline")
                XCTAssertLessThan(gap, light.width / 2, "\(said): adrift of its edge")
                switch orientation.ledEdge {
                case .leading, .trailing: XCTAssertEqual(light.midY, outline.midY, accuracy: 1e-9, "\(said): half way along")
                case .top, .bottom: XCTAssertEqual(light.midX, outline.midX, accuracy: 1e-9, "\(said): half way along")
                }
            }
            let dots = TabletOrientation.allCases.map { TabletGlyph.light($0, size: size) }
            for (index, dot) in dots.enumerated() {
                for other in dots[(index + 1)...] {
                    XCTAssertFalse(dot.intersects(other), "four different pictures at \(size): \(dot) and \(other)")
                }
            }
        }
    }

    /// LIT, SO IT IS A LIGHT AND NOT A HOLE: a colour of its own — never
    /// the outline's — that reads on what the glyph is drawn on. A popover
    /// is dark or light with the appearance. THE CORNER IS NOT: its glass
    /// lies over the pane's black, a dark ground in both — #202423 in dark
    /// and #6E706F in light, read off the window server (a probe window,
    /// 2026-10-02; `ImageRenderer` draws no material) — and the full blue
    /// a light popover takes was 1.25 to 1 on it, told by its hue alone.
    func testTheLightIsLitInBothAppearances() throws {
        let dark = TabletGlyph.lightHex(onPane: false, dark: true)
        let light = TabletGlyph.lightHex(onPane: false, dark: false)
        for ground in ["#000000", "#1E1E1E", "#3A3A3C"] {
            XCTAssertGreaterThan(try XCTUnwrap(PageTheme.contrast(dark, ground)), 4.5, "\(dark) on \(ground)")
        }
        for ground in ["#FFFFFF", "#ECECEC"] {
            XCTAssertGreaterThan(try XCTUnwrap(PageTheme.contrast(light, ground)), 3, "\(light) on \(ground)")
        }
        let corners = [(dark: true, glass: "#202423"), (dark: false, glass: "#6E706F")]
        for corner in corners {
            let lit = TabletGlyph.lightHex(onPane: true, dark: corner.dark)
            XCTAssertGreaterThan(try XCTUnwrap(PageTheme.contrast(lit, corner.glass)), 3,
                                 "\(lit) on the corner's glass, \(corner.glass)")
        }
        // Not the outline's white or black: blue, in all of them.
        for hex in [dark, light] + corners.map({ TabletGlyph.lightHex(onPane: true, dark: $0.dark) }) {
            let colour = try XCTUnwrap(NSColor(hex: hex))
            XCTAssertGreaterThan(colour.blueComponent, colour.redComponent + 0.3, "\(hex) is not a blue light")
        }
    }

    /// The picture's pixels, four bytes each, the first row its top.
    private func pixels(of image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: image.width, height: image.height,
                                              bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// AND THE CORNER'S BUTTON IS BUILT THAT WAY: rendered as the pane
    /// has it, the pixel at the dot's middle is the pale light in light
    /// appearance as in dark — the button saying which ground it is on,
    /// not only the glyph being able to be told.
    @MainActor
    func testTheCornersButtonLightsThePaleDotInBothAppearances() throws {
        let scale: CGFloat = 4, padding: CGFloat = 6
        let side = TabletOrientationButton.glyph + 2 * padding
        for dark in [true, false] {
            let pale = try XCTUnwrap(NSColor(hex: TabletGlyph.lightHex(onPane: true, dark: dark)))
            for orientation in TabletOrientation.allCases {
                let said = "\(orientation.title), \(dark ? "dark" : "light")"
                let button = TabletOrientationButton(orientation: orientation, target: .page, onPick: { _ in })
                    .background(Color.black)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: button)
                renderer.scale = scale
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(CGFloat(image.width), side * scale, "\(said): the glyph in the corner's padding")
                XCTAssertEqual(CGFloat(image.height), side * scale, said)
                let data = try pixels(of: image)
                let dot = TabletGlyph.light(orientation, size: TabletOrientationButton.glyph)
                let x = Int((padding + dot.midX) * scale), y = Int((padding + dot.midY) * scale)
                let at = (y * image.width + x) * 4
                for (channel, want) in zip(0..<3, [pale.redComponent, pale.greenComponent, pale.blueComponent]) {
                    XCTAssertEqual(CGFloat(data[at + channel]), want * 255, accuracy: 6,
                                   "\(said): the dot is \(Array(data[at..<at + 3])), not the corner's light")
                }
            }
        }
    }

    /// AND THE VIEW DRAWS WHAT THE GEOMETRY SAYS: rendered, the lit pixels
    /// — the ones that are blue, which the outline never is — are centred
    /// where `TabletGlyph.light` puts the dot, in both appearances, and the
    /// outline's ink fills the square along its long side.
    @MainActor
    func testTheRenderedGlyphLightsTheDotWhereTheLightIs() throws {
        let scale: CGFloat = 4
        for dark in [true, false] {
            for size: CGFloat in [14, 16, 32] {
                for orientation in TabletOrientation.allCases {
                    let said = "\(orientation.title) at \(size), \(dark ? "dark" : "light")"
                    let view = TabletGlyph(orientation: orientation, size: size)
                        .foregroundStyle(dark ? Color.white : Color.black)
                        .background(dark ? Color.black : Color.white)
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = scale
                    let image = try XCTUnwrap(renderer.cgImage)
                    XCTAssertEqual(CGFloat(image.width), size * scale, said)
                    let data = try pixels(of: image)
                    // The blue of each pixel, as a weight: the dot and its glow.
                    var weight = 0.0, sumX = 0.0, sumY = 0.0, inked = 0
                    for y in 0..<image.height {
                        for x in 0..<image.width {
                            let at = (y * image.width + x) * 4
                            let red = Int(data[at]), blue = Int(data[at + 2])
                            // The bitmap's first row is the picture's top.
                            let down = Double(y) + 0.5
                            if blue - red > 40 {
                                let blueness = Double(blue - red)
                                weight += blueness
                                sumX += blueness * (Double(x) + 0.5)
                                sumY += blueness * down
                            }
                            if dark ? red > 128 : blue < 128 { inked += 1 }
                        }
                    }
                    XCTAssertGreaterThan(weight, 0, "\(said): nothing is lit")
                    XCTAssertGreaterThan(inked, 0, "\(said): no outline")
                    let dot = TabletGlyph.light(orientation, size: size)
                    XCTAssertEqual(CGFloat(sumX / weight) / scale, dot.midX, accuracy: 0.75, "\(said): the light's x")
                    XCTAssertEqual(CGFloat(sumY / weight) / scale, dot.midY, accuracy: 0.75, "\(said): the light's y")
                }
            }
        }
    }

    /// THE WAY IT SITS BY DEFAULT IS ONE LINE UNDER ITS NAME: the popover
    /// is as wide as "A quarter turn clockwise · light at the top" needs.
    /// At the paper's 310 it wrapped, and the row in use was the ragged
    /// one. Measured by the row's height against a row that cannot wrap —
    /// and against the same row with its line said twice over, which
    /// must, so the measure is known to tell. (Never against another of
    /// the four: whether the long ones wrap is nothing this asks for, and
    /// a popover widened until none did would have failed here.)
    @MainActor
    func testTheWayItSitsByDefaultIsOneLineInThePopover() throws {
        func height(_ orientation: TabletOrientation, detail: String? = nil) throws -> Int {
            let row = PickList(title: "How the Tablet Sits", width: TabletOrientationMenu.width) {
                PickRow(title: orientation.title, detail: detail ?? orientation.detail, isCurrent: true, action: {}) {
                    TabletGlyph(orientation: orientation, size: 26)
                }
            }
            return try XCTUnwrap(ImageRenderer(content: row).cgImage).height
        }
        let sits = TabletOrientation.portraitRight
        XCTAssertEqual(try height(sits), try height(.landscape),
                       "\"\(sits.detail)\" wrapped at \(TabletOrientationMenu.width)")
        XCTAssertGreaterThan(try height(sits, detail: sits.detail + " " + sits.detail), try height(sits),
                             "a line that wraps is a taller row")
        let menu = TabletOrientationMenu(current: .portraitRight, target: .page, onPick: { _ in })
        XCTAssertEqual(CGFloat(try XCTUnwrap(ImageRenderer(content: menu).cgImage).width), TabletOrientationMenu.width,
                       "the popover is the width its rows were measured at")
    }

    /// THE POPOVER SAYS WHAT A TURN DOES TO WHAT THE PEN WRITES ON. The
    /// control is live in Notebook mode too, and there the note's strokes
    /// are the note's and never turn — "its writing turns with it" said
    /// over a note was a promise the turn does not keep. And it says what
    /// the drawing's dot is — the tablet's light, and where it is as the
    /// tablet ships — or the four pictures are four shapes with a spot on.
    func testThePopoverSaysWhatATurnDoesToWhatThePenWritesOn() {
        let page = TabletOrientationMenu.footer(for: .page)
        let notebook = TabletOrientationMenu.footer(for: .notebook)
        XCTAssertTrue(page.contains("its writing with it"), page)
        XCTAssertTrue(page.contains("laid out again for the new shape"), "the paper is not turned: \(page)")
        XCTAssertFalse(notebook.contains("writing with it"), "the note's strokes never turn: \(notebook)")
        XCTAssertTrue(notebook.contains("stays where it was written"), notebook)
        for footer in [page, notebook] {
            XCTAssertTrue(footer.contains("The dot is the tablet's light — on the left as it ships."), footer)
            XCTAssertFalse(footer.localizedCaseInsensitiveContains("heavy"), "no tablet has a heavy edge: \(footer)")
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

    private func point(_ x: CGFloat, _ y: CGFloat, tip: Bool, side: Bool = false, upper: Bool = false,
                       pressure: Double = 0.5, at time: TimeInterval) -> TabletReading {
        var switches: Set<PenSwitch> = []
        if side { switches.insert(.lower) }
        if upper { switches.insert(.upper) }
        return TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: tip, switches: switches,
                                          pressure: pressure,
                                          buttons: (tip ? 1 : 0) | (side ? 2 : 0) | (upper ? 4 : 0)),
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

    /// And a box being drawn with the side switch held and the nib down.
    func testABoxUnderWayTurnsAndTheRestJoinsOn() {
        let (input, _, scribe) = rig()
        input.feed(point(1000, 1000, tip: true, upper: true, at: 1))
        input.feed(point(4000, 3000, tip: true, upper: true, at: 2))
        turn(input, scribe, to: 2)
        input.feed(point(6000, 5000, tip: true, upper: true, at: 3))
        input.feed(point(6000, 5000, tip: false, upper: false, at: 4))
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
        TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: tip, switches: [], pressure: 0.5,
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
