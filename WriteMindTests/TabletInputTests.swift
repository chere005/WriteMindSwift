import AppKit
import Combine
import XCTest
@testable import WriteMind

/// The tablet onto the page: counts to page fractions through the quarter
/// turn, the extent that can only grow, and the pen's state from one event
/// to the next. Sean holds the One by Wacom turned a quarter turn clockwise
/// (2026-10-02: "i want to rotate the wacom 90 degrees clockwise for when
/// its in use in WriteMind").
@MainActor
final class TabletMappingTests: XCTestCase {
    private let small = TabletExtent(width: 15200, height: 9500)

    private func assertPoint(_ point: CGPoint, _ x: CGFloat, _ y: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: 1e-9, "u", file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: 1e-9, "v", file: file, line: line)
    }

    /// u = 1 − y/H, v = x/W: the tablet's top-left corner is the page's
    /// top-RIGHT, and the page is H/W wide.
    func testOneQuarterTurnClockwiseIsTheDefaultShape() {
        let page = { (x: CGFloat, y: CGFloat) in
            TabletMapping.page(CGPoint(x: x, y: y), extent: self.small, quarterTurns: 1)
        }
        assertPoint(page(0, 0), 1, 0)
        assertPoint(page(15200, 0), 1, 1)
        assertPoint(page(15200, 9500), 0, 1)
        assertPoint(page(0, 9500), 0, 0)
        assertPoint(page(7600, 4750), 0.5, 0.5)
        assertPoint(page(3800, 2375), 0.75, 0.25)
        XCTAssertEqual(TabletMapping.aspect(of: small, quarterTurns: 1), 0.625, accuracy: 1e-9, "9500 / 15200")
    }

    /// Where the tablet's top-left corner lands, and the page's shape, for
    /// each way the tablet can lie.
    func testEveryQuarterTurnIsARotationOfThePage() {
        let corners: [(turns: Int, topLeft: CGPoint, topRight: CGPoint, aspect: CGFloat)] = [
            (0, CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), 1.6),
            (1, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), 0.625),
            (2, CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), 1.6),
            (3, CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), 0.625),
        ]
        for corner in corners {
            let topLeft = TabletMapping.page(.zero, extent: small, quarterTurns: corner.turns)
            let topRight = TabletMapping.page(CGPoint(x: 15200, y: 0), extent: small, quarterTurns: corner.turns)
            assertPoint(topLeft, corner.topLeft.x, corner.topLeft.y)
            assertPoint(topRight, corner.topRight.x, corner.topRight.y)
            XCTAssertEqual(TabletMapping.aspect(of: small, quarterTurns: corner.turns), corner.aspect,
                           accuracy: 1e-9, "turn \(corner.turns)")
            // Every turn keeps the middle in the middle and the page whole.
            assertPoint(TabletMapping.page(CGPoint(x: 7600, y: 4750), extent: small, quarterTurns: corner.turns),
                        0.5, 0.5)
        }
    }

    func testTurnsWrapBothWays() {
        XCTAssertEqual(TabletMapping.turns(-1), 3)
        XCTAssertEqual(TabletMapping.turns(4), 0)
        XCTAssertEqual(TabletMapping.turns(5), 1)
        XCTAssertEqual(TabletMapping.page(.zero, extent: small, quarterTurns: 5),
                       TabletMapping.page(.zero, extent: small, quarterTurns: 1))
    }

    func testTheTableKnowsTheOneByWacom() {
        XCTAssertEqual(TabletExtent.known(productID: 0x037A),
                       TabletExtent(width: 15200, height: 9500, countsPerMillimetre: 100))
        XCTAssertEqual(TabletExtent.known(productID: 0x037B),
                       TabletExtent(width: 21600, height: 13500, countsPerMillimetre: 100))
        XCTAssertNil(TabletExtent.known(productID: 0x0001))
    }

    /// A WRONG TABLE ENTRY CAN NEVER CLIP THE PAGE: the edge moves out to
    /// the farthest the pen has reached, and never back in.
    func testTheExtentOnlyGrows() {
        let extent = TabletExtent(width: 100, height: 50)
        XCTAssertEqual(extent.widened(toInclude: CGPoint(x: 150, y: 20)), TabletExtent(width: 150, height: 50))
        XCTAssertEqual(extent.widened(toInclude: CGPoint(x: 10, y: 80)), TabletExtent(width: 100, height: 80))
        XCTAssertEqual(extent.widened(toInclude: CGPoint(x: 10, y: 10)), extent)
    }

    /// THE COUNTS ARE THE RAW LANDSCAPE SENSOR'S, whichever way the Wacom
    /// driver's own orientation is set. On Sean's Mac it is set to portrait
    /// and the driver says the tablet is 9499 × 15199 — while the pen was
    /// seen at x = 13217. On the table's extent that is on the sheet where
    /// the nib is, and nothing widens; on the driver's it was past the
    /// "edge", stretched the page, and was then turned a second time.
    func testACountPastTheDriversOrientedWidthIsOnTheTablesSheet() throws {
        var pen = TabletPen()
        var extent = try XCTUnwrap(TabletExtent.known(productID: 0x037A))
        XCTAssertGreaterThan(extent.width, extent.height, "the raw sensor is landscape")
        let seen = TabletReading(kind: .point(counts: CGPoint(x: 13217, y: 4750), tip: false, switches: [],
                                              pressure: 0, buttons: 0), timestamp: 1, native: true)
        let out = pen.consume(seen, extent: &extent, quarterTurns: 1)
        XCTAssertEqual(extent, TabletExtent(width: 15200, height: 9500, countsPerMillimetre: 100),
                       "inside the table: nothing widens")
        assertPoint(out[0].page, 0.5, 13217.0 / 15200.0)
        XCTAssertEqual(TabletMapping.aspect(of: extent, quarterTurns: 1), 0.625, accuracy: 1e-9,
                       "turned once, the sheet is tall")
    }

    func testAPointPastTheEdgeIsOnThePageAndMovesTheEdge() {
        var pen = TabletPen()
        var extent = small
        let past = TabletReading(kind: .point(counts: CGPoint(x: 16000, y: 9800), tip: false, switches: [],
                                              pressure: 0, buttons: 0), timestamp: 1, native: false)
        let out = pen.consume(past, extent: &extent, quarterTurns: 1)
        XCTAssertEqual(extent, TabletExtent(width: 16000, height: 9800))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].page, CGPoint(x: 0, y: 1), "the far corner, not off the sheet")
    }

    func testThePageFitsThePaneAtTheTabletsShape() {
        let frame = TabletMapping.fit(aspect: 0.625, in: CGSize(width: 400, height: 1000), margin: 18)
        XCTAssertEqual(frame.width, 364, accuracy: 1e-9)
        XCTAssertEqual(frame.height, 364 / 0.625, accuracy: 1e-9)
        XCTAssertEqual(frame.midX, 200, accuracy: 1e-9)
        XCTAssertEqual(frame.midY, 500, accuracy: 1e-9)
        let wide = TabletMapping.fit(aspect: 0.625, in: CGSize(width: 1000, height: 400), margin: 18)
        XCTAssertEqual(wide.height, 364, accuracy: 1e-9)
        XCTAssertEqual(wide.width, 364 * 0.625, accuracy: 1e-9)
        XCTAssertEqual(TabletPane.pageFrame(in: CGSize(width: 400, height: 1000), extent: small, quarterTurns: 1),
                       frame, "the pane's sheet is the tablet's shape, turned")
        // Short of height, the sheet keeps clear of the corner's buttons
        // above it (10 points in, about 24 tall) and the status line below.
        let short = TabletPane.pageFrame(in: CGSize(width: 1000, height: 400), extent: small, quarterTurns: 1)
        XCTAssertEqual(short.minY, 44, accuracy: 1e-9)
        XCTAssertEqual(short.maxY, 356, accuracy: 1e-9)
        XCTAssertEqual(short.width / short.height, 0.625, accuracy: 1e-9)
    }
}

/// What one event says about the pen — off events built the way the system
/// builds them (a CGEvent, its tablet fields set, then `NSEvent(cgEvent:)`),
/// so what is tested is AppKit's own reading of them.
final class TabletReadingTests: XCTestCase {
    private let point: Int64 = 1, proximity: Int64 = 2, mouse: Int64 = 0, touch: Int64 = 3

    private func mouseEvent(_ type: CGEventType, subtype: Int64, x: Int64 = 0, y: Int64 = 0, buttons: Int64 = 0,
                            pressure: Double = 0, entering: Bool = false, at nanos: UInt64 = 1_000) throws -> NSEvent {
        let button: CGMouseButton = [.rightMouseDown, .rightMouseDragged, .rightMouseUp].contains(type) ? .right : .left
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type,
                                       mouseCursorPosition: CGPoint(x: 50, y: 50), mouseButton: button))
        cg.setIntegerValueField(.mouseEventSubtype, value: subtype)
        // The point's fields and the proximity's share their storage in a
        // CGEvent, so only the ones the subtype means are set.
        if subtype == proximity {
            cg.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        } else {
            cg.setIntegerValueField(.tabletEventPointX, value: x)
            cg.setIntegerValueField(.tabletEventPointY, value: y)
            cg.setIntegerValueField(.tabletEventPointButtons, value: buttons)
        }
        cg.setDoubleValueField(.mouseEventPressure, value: pressure)
        cg.timestamp = nanos
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    private func tabletEvent(x: Int64, y: Int64, buttons: Int64, pressure: Double, at nanos: UInt64 = 1_000) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(source: nil))
        cg.type = .tabletPointer
        cg.setIntegerValueField(.tabletEventPointX, value: x)
        cg.setIntegerValueField(.tabletEventPointY, value: y)
        cg.setIntegerValueField(.tabletEventPointButtons, value: buttons)
        cg.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        cg.timestamp = nanos
        let event = try XCTUnwrap(NSEvent(cgEvent: cg))
        XCTAssertEqual(event.type, .tabletPoint)
        return event
    }

    private func proximityEvent(entering: Bool) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(source: nil))
        cg.type = .tabletProximity
        cg.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    private func pointOf(_ event: NSEvent, file: StaticString = #filePath, line: UInt = #line)
        -> (counts: CGPoint, tip: Bool, side: Bool, switches: Set<PenSwitch>?, pressure: Double, native: Bool)? {
        guard let reading = TabletReading.reading(event),
              case .point(let counts, let tip, let switches, let pressure, _) = reading.kind else {
            XCTFail("not a point", file: file, line: line)
            return nil
        }
        return (counts, tip, switches?.isEmpty == false, switches, pressure, reading.native)
    }

    /// As measured: a stroke is left-mouse events with the tablet subtype.
    func testAStrokeIsTheLeftButtonWithTheTabletSubtype() throws {
        let drag = try XCTUnwrap(pointOf(try mouseEvent(.leftMouseDragged, subtype: point, x: 9123, y: 4567,
                                                        buttons: 1, pressure: 0.5, at: 2_500_000_000)))
        XCTAssertEqual(drag.counts, CGPoint(x: 9123, y: 4567), "absoluteX/Y are the tablet's counts")
        XCTAssertTrue(drag.tip)
        XCTAssertFalse(drag.side)
        XCTAssertEqual(drag.pressure, 0.5, accuracy: 1.0 / 255)
        XCTAssertFalse(drag.native)
        XCTAssertEqual(TabletReading.reading(try mouseEvent(.leftMouseDragged, subtype: point,
                                                            at: 2_500_000_000))?.timestamp, 2.5)

        let down = try XCTUnwrap(pointOf(try mouseEvent(.leftMouseDown, subtype: point, buttons: 1, pressure: 0.2)))
        XCTAssertTrue(down.tip)
        let up = try XCTUnwrap(pointOf(try mouseEvent(.leftMouseUp, subtype: point, buttons: 0)))
        XCTAssertFalse(up.tip, "the up is the nib leaving")
        XCTAssertEqual(up.pressure, 0)
    }

    func testAHoverIsAPointWithNothingPressed() throws {
        let hover = try XCTUnwrap(pointOf(try mouseEvent(.mouseMoved, subtype: point, x: 100, y: 200, pressure: 0.9)))
        XCTAssertEqual(hover.counts, CGPoint(x: 100, y: 200))
        XCTAssertFalse(hover.tip)
        XCTAssertFalse(hover.side)
        XCTAssertEqual(hover.pressure, 0, "a hover's pressure is never read")
    }

    /// As measured: the side switch is the RIGHT button, mask 0x2, with a
    /// made-up pressure of 1.
    func testTheSideSwitchIsTheRightButton() throws {
        let side = try XCTUnwrap(pointOf(try mouseEvent(.rightMouseDown, subtype: point, buttons: 2, pressure: 1)))
        XCTAssertTrue(side.side)
        XCTAssertFalse(side.tip)
        XCTAssertEqual(side.pressure, 0, "the switch's pressure means nothing")
        XCTAssertTrue(try XCTUnwrap(pointOf(try mouseEvent(.rightMouseDragged, subtype: point, buttons: 2))).side)
        XCTAssertFalse(try XCTUnwrap(pointOf(try mouseEvent(.rightMouseUp, subtype: point, buttons: 0))).side)
    }

    /// BY THE DRIVER'S EVENTS THE LOWER SWITCH IS THE RIGHT BUTTON AND THE
    /// UPPER IS THE MASK'S 0x4 (`penUpperSide`). Both measured on Sean's
    /// tablet, 2026-10-02: the right button came with mask 0x2 (and its up
    /// still with 0x2 — the event's type is the word on its own button),
    /// and the nib's own down and up with 0x5 and 0x4. An event always says
    /// what the switches are doing — never "cannot say".
    func testTheDriversRightButtonIsTheLowerSwitchAndItsMaskSaysTheUpper() throws {
        XCTAssertEqual(try XCTUnwrap(pointOf(try mouseEvent(.rightMouseDown, subtype: point, buttons: 2))).switches,
                       [.lower])
        XCTAssertEqual(try XCTUnwrap(pointOf(try mouseEvent(.rightMouseDragged, subtype: point, buttons: 0))).switches,
                       [.lower], "the right button is the lower switch, whatever the mask says of it")
        XCTAssertEqual(try XCTUnwrap(pointOf(try mouseEvent(.rightMouseUp, subtype: point, buttons: 2))).switches, [],
                       "the right button's up, as measured: let go, though its mask still has it")
        XCTAssertEqual(try XCTUnwrap(pointOf(try mouseEvent(.mouseMoved, subtype: point, buttons: 0))).switches, [])
        XCTAssertEqual(try XCTUnwrap(pointOf(try mouseEvent(.mouseMoved, subtype: point, buttons: 4))).switches,
                       [.upper], "the mask's upper switch was thrown away")
        let down = try XCTUnwrap(pointOf(try mouseEvent(.leftMouseDown, subtype: point, buttons: 5, pressure: 0.5)))
        XCTAssertTrue(down.tip)
        XCTAssertEqual(down.switches, [.upper], "the nib down with the upper switch held, as measured (0x5)")
        let up = try XCTUnwrap(pointOf(try mouseEvent(.leftMouseUp, subtype: point, buttons: 4)))
        XCTAssertFalse(up.tip)
        XCTAssertEqual(up.switches, [.upper], "and up with it still held (0x4)")
        XCTAssertEqual(try XCTUnwrap(pointOf(try mouseEvent(.rightMouseDragged, subtype: point, buttons: 6))).switches,
                       [.lower, .upper])
        XCTAssertEqual(try XCTUnwrap(pointOf(try tabletEvent(x: 1, y: 1, buttons: 2, pressure: 0))).switches, [.lower])
        XCTAssertEqual(try XCTUnwrap(pointOf(try tabletEvent(x: 1, y: 1, buttons: 4, pressure: 0))).switches, [.upper])
    }

    /// Events of the tablet's own type, should the driver ever send the pen
    /// that way: the nib is down by its button or its pressure.
    func testAPureTabletEventIsThePen() throws {
        let nib = try XCTUnwrap(pointOf(try tabletEvent(x: 7000, y: 3000, buttons: 1, pressure: 0.25)))
        XCTAssertEqual(nib.counts, CGPoint(x: 7000, y: 3000))
        XCTAssertTrue(nib.tip)
        XCTAssertEqual(nib.pressure, 0.25, accuracy: 1e-3)
        XCTAssertTrue(nib.native)
        XCTAssertTrue(try XCTUnwrap(pointOf(try tabletEvent(x: 1, y: 1, buttons: 0, pressure: 0.3))).tip,
                      "pressure alone says the nib is down")
        let hovering = try XCTUnwrap(pointOf(try tabletEvent(x: 1, y: 1, buttons: 0, pressure: 0)))
        XCTAssertFalse(hovering.tip)
        let switched = try XCTUnwrap(pointOf(try tabletEvent(x: 1, y: 1, buttons: 2, pressure: 0)))
        XCTAssertTrue(switched.side)
        XCTAssertFalse(switched.tip)
    }

    func testProximityComesBothWays() throws {
        XCTAssertEqual(TabletReading.reading(try mouseEvent(.mouseMoved, subtype: proximity, entering: true))?.kind,
                       .proximity(entering: true))
        XCTAssertEqual(TabletReading.reading(try mouseEvent(.mouseMoved, subtype: proximity, entering: false))?.kind,
                       .proximity(entering: false))
        let native = try XCTUnwrap(TabletReading.reading(try proximityEvent(entering: false)))
        XCTAssertEqual(native.kind, .proximity(entering: false))
        XCTAssertTrue(native.native)
        XCTAssertEqual(TabletReading.reading(try proximityEvent(entering: true))?.kind, .proximity(entering: true))
    }

    func testAMouseATrackpadAndAKeyAreNotThePen() throws {
        XCTAssertNil(TabletReading.reading(try mouseEvent(.leftMouseDragged, subtype: mouse, pressure: 1)))
        XCTAssertNil(TabletReading.reading(try mouseEvent(.leftMouseDown, subtype: touch, pressure: 0.7)))
        XCTAssertNil(TabletReading.reading(try mouseEvent(.mouseMoved, subtype: mouse)))
        XCTAssertNil(TabletReading.reading(try mouseEvent(.rightMouseDown, subtype: mouse)))
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                 windowNumber: 0, context: nil, characters: "a",
                                                 charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        XCTAssertNil(TabletReading.reading(key), "and asking did not raise")
    }

    func testTheFunnelWatchesEveryRouteThePenWasSeenToTake() {
        for type: NSEvent.EventTypeMask in [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown,
                                            .rightMouseDragged, .rightMouseUp, .mouseMoved, .tabletPoint,
                                            .tabletProximity] {
            XCTAssertTrue(TabletReading.watched.contains(type), "\(type)")
        }
        XCTAssertFalse(TabletReading.watched.contains(.keyDown))
        XCTAssertFalse(TabletReading.watched.contains(.scrollWheel))
    }

    /// Asking an event a field its type does not define is an exception
    /// that takes the app down — so the reading must never ASK. The spy
    /// records every question.
    private final class Spy: TabletEventFields {
        let type: NSEvent.EventType
        private let kind: NSEvent.EventSubtype
        var asked: Set<String> = []
        init(_ type: NSEvent.EventType, _ subtype: NSEvent.EventSubtype) {
            self.type = type
            self.kind = subtype
        }
        var subtype: NSEvent.EventSubtype { asked.insert("subtype"); return kind }
        var timestamp: TimeInterval { 1 }
        var pressure: Float { asked.insert("pressure"); return 0.5 }
        var absoluteX: Int { asked.insert("absoluteX"); return 1 }
        var absoluteY: Int { asked.insert("absoluteY"); return 1 }
        var buttonMask: NSEvent.ButtonMask { asked.insert("buttonMask"); return [] }
        var isEnteringProximity: Bool { asked.insert("isEnteringProximity"); return true }
    }

    func testOnlyWhatTheEventDefinesIsEverAsked() {
        let trackpad = Spy(.leftMouseDragged, .touch)
        XCTAssertNil(TabletReading.reading(trackpad))
        XCTAssertEqual(trackpad.asked, ["subtype"], "a trackpad was asked a tablet's questions")

        // A pure tablet event has no subtype, and asking for one raises.
        let pure = Spy(.tabletPoint, .tabletPoint)
        _ = TabletReading.reading(pure)
        XCTAssertFalse(pure.asked.contains("subtype"), "a pure tablet event was asked its subtype")
        XCTAssertTrue(pure.asked.contains("pressure"), "its pressure is its own")
        let pureNear = Spy(.tabletProximity, .tabletProximity)
        _ = TabletReading.reading(pureNear)
        XCTAssertEqual(pureNear.asked, ["isEnteringProximity"])

        let hover = Spy(.mouseMoved, .tabletPoint)
        _ = TabletReading.reading(hover)
        XCTAssertFalse(hover.asked.contains("pressure"), "pressure was read off a hover")
        XCTAssertTrue(hover.asked.contains("absoluteX"), "the spy has to be able to see a question")

        let coming = Spy(.mouseMoved, .tabletProximity)
        _ = TabletReading.reading(coming)
        XCTAssertEqual(coming.asked, ["subtype", "isEnteringProximity"], "a proximity event has no position to ask")

        let side = Spy(.rightMouseDown, .tabletPoint)
        _ = TabletReading.reading(side)
        XCTAssertFalse(side.asked.contains("pressure"), "the side switch's pressure is made up")
    }
}

/// The pen's state from one reading to the next.
final class TabletPenTests: XCTestCase {
    private var pen = TabletPen()
    private var extent = TabletExtent(width: 15200, height: 9500)
    private var clock: TimeInterval = 0

    override func setUp() {
        super.setUp()
        pen = TabletPen()
        extent = TabletExtent(width: 15200, height: 9500)
        clock = 0
    }

    /// `side` is the lower switch, `upper` the other; `ready` false is a
    /// reading that cannot say what the switches are doing.
    private func at(_ x: Double = 7600, _ y: Double = 4750, tip: Bool = false, side: Bool = false,
                    upper: Bool = false, ready: Bool = true, pressure: Double = 0,
                    time: TimeInterval? = nil) -> [TabletSample] {
        clock += 0.008
        var switches: Set<PenSwitch> = []
        if side { switches.insert(.lower) }
        if upper { switches.insert(.upper) }
        let reading = TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: tip,
                                                 switches: ready ? switches : nil,
                                                 pressure: pressure, buttons: 0),
                                    timestamp: time ?? clock, native: false)
        return pen.consume(reading, extent: &extent, quarterTurns: 1)
    }

    private func near(_ entering: Bool) -> [TabletSample] {
        clock += 0.008
        return pen.consume(TabletReading(kind: .proximity(entering: entering), timestamp: clock, native: true),
                           extent: &extent, quarterTurns: 1)
    }

    private func phases(_ samples: [TabletSample]) -> [TabletSample.Phase] { samples.map(\.phase) }

    func testAStrokeIsHoverDownDragUpHover() {
        XCTAssertEqual(phases(at()), [.hover])
        let down = at(tip: true, pressure: 0.3)
        XCTAssertEqual(phases(down), [.down])
        XCTAssertEqual(down[0].pressure, 0.3)
        let drag = at(7700, 4750, tip: true, pressure: 0.6)
        XCTAssertEqual(phases(drag), [.drag])
        XCTAssertEqual(drag[0].pressure, 0.6)
        let up = at(7800, 4750)
        XCTAssertEqual(phases(up), [.up])
        XCTAssertEqual(up[0].pressure, 0, "the nib has left")
        XCTAssertEqual(phases(at()), [.hover])
        XCTAssertTrue(([down, drag, up].flatMap { $0 }).allSatisfy { !$0.sideSwitch && $0.inProximity })
    }

    func testATapIsADownAndAnUp() {
        XCTAssertEqual(phases(at(tip: true, pressure: 0.5)), [.down])
        XCTAssertEqual(phases(at()), [.up])
    }

    /// A down that was never seen — the page came up mid-stroke, or the
    /// down went by another route — is still a down; an up never seen is
    /// still an up.
    func testWhatWasMissedIsMadeUp() {
        XCTAssertEqual(phases(at(tip: true, pressure: 0.4)), [.down], "no hover first")
        XCTAssertEqual(phases(at(tip: true, pressure: 0.4)), [.drag])
        XCTAssertEqual(phases(at()), [.up], "a hover arriving while down is the up")
    }

    /// A SWITCH HELD AS THE NIB GOES DOWN IS A SELECTION, FROM THE NIB'S
    /// DOWN UNTIL NIB AND SWITCH ARE BOTH UP — either switch, and let go
    /// mid-drag it is still the box. The switch alone, in the air, starts nothing: pressed and
    /// let go there it is a click (below), which it could not be while it
    /// also began a box.
    func testASwitchHeldAsTheNibGoesDownMakesASelection() {
        XCTAssertEqual(phases(at()), [.hover])
        XCTAssertEqual(phases(at(side: true)), [.hover], "the switch alone, in the air, began a box")
        XCTAssertFalse(pen.engaged)
        let down = at(tip: true, side: true, pressure: 0.5)
        XCTAssertEqual(phases(down), [.down])
        XCTAssertTrue(down[0].sideSwitch)
        XCTAssertTrue(at(7700, 4750, tip: true, side: true, pressure: 0.5)[0].sideSwitch)
        XCTAssertTrue(at(7800, 4750, tip: true, pressure: 0.5)[0].sideSwitch,
                      "the switch let go mid-drag is still the box")
        let up = at(7800, 4750)
        XCTAssertEqual(phases(up), [.up])
        XCTAssertTrue(up[0].sideSwitch)
        XCTAssertEqual(phases(at()), [.hover], "and letting go after a box is no click")
        XCTAssertFalse(at()[0].sideSwitch, "a hover is no selection")

        // The upper switch held makes the same box.
        XCTAssertEqual(phases(at(upper: true)), [.hover])
        let upper = at(tip: true, upper: true, pressure: 0.5)
        XCTAssertEqual(phases(upper), [.down])
        XCTAssertTrue(upper[0].sideSwitch, "the upper switch held as the nib went down wrote ink")
        XCTAssertEqual(phases(at()), [.up])

        // Ink that has begun stays ink if the switch is pressed under it.
        XCTAssertFalse(at(tip: true, pressure: 0.5)[0].sideSwitch)
        XCTAssertFalse(at(tip: true, side: true, pressure: 0.5)[0].sideSwitch)
    }

    /// THE BOX GOES ON WHILE THE NIB OR THE SWITCH IS DOWN, as it always
    /// has — only its beginning is the nib's now. The nib lifted with the
    /// switch still held carries it on in the air; it ends when both are
    /// up; and letting the switch go then is the box's end, not a click,
    /// because the nib touched while it was held.
    func testTheBoxGoesOnWhileTheSwitchIsHeldAndLettingGoIsNoClick() {
        _ = at()
        _ = at(side: true)
        XCTAssertEqual(phases(at(tip: true, side: true, pressure: 0.5)), [.down])
        XCTAssertEqual(phases(at(7700, 4750, tip: true, side: true, pressure: 0.5)), [.drag])
        let lift = at(7700, 4750, side: true)
        XCTAssertEqual(phases(lift), [.drag], "the nib came up with the switch held, and the box ended")
        XCTAssertTrue(lift[0].sideSwitch)
        XCTAssertEqual(lift[0].pressure, 0, "in the air")
        XCTAssertEqual(phases(at(9000, 8000, side: true)), [.drag], "still held: the box follows the pen")
        let end = at(9000, 8000)
        XCTAssertEqual(phases(end), [.up], "letting go after a box was a click")
        XCTAssertTrue(end[0].sideSwitch)
        XCTAssertEqual(phases(at(9000, 8000)), [.hover])
        XCTAssertNil(pen.armed)
    }

    /// INK ENDS WHERE THE NIB LIFTS. The switch pressed under a stroke of
    /// ink and still held as the nib comes up is no reason to go on drawing
    /// in the air — and it makes no box of the next stroke either until it
    /// has been let go and pressed again, and no click when it is let go.
    func testInkEndsAtTheLiftWhateverTheSwitchIsDoing() {
        XCTAssertEqual(phases(at(tip: true, pressure: 0.5)), [.down])
        XCTAssertEqual(phases(at(7700, 4750, tip: true, side: true, pressure: 0.5)), [.drag])
        let lift = at(7800, 4750, side: true)
        XCTAssertEqual(phases(lift), [.up], "the nib came up and the ink went on")
        XCTAssertFalse(lift[0].sideSwitch)
        XCTAssertEqual(phases(at(9000, 8000, side: true)), [.hover])
        XCTAssertFalse(pen.engaged)
        let more = at(9000, 8000, tip: true, side: true, pressure: 0.5)
        XCTAssertEqual(phases(more), [.down])
        XCTAssertFalse(more[0].sideSwitch, "the switch held over from the ink made a box of the next stroke")
        XCTAssertEqual(phases(at(9000, 8000, side: true)), [.up])
        XCTAssertEqual(phases(at(9000, 8000)), [.hover], "let go — and no click: the nib touched while it was held")
        XCTAssertEqual(phases(at(9000, 8000, side: true)), [.hover])
        let box = at(9000, 8000, tip: true, side: true, pressure: 0.5)
        XCTAssertEqual(phases(box), [.down], "pressed again: a box")
        XCTAssertTrue(box[0].sideSwitch)
    }

    // MARK: - A click of a side switch

    /// A SIDE SWITCH CLICKED IN THE AIR IS A COMMAND (Sean, 2026-10-02:
    /// "make the wacom buttons undo and redo last drawing"): pressed and
    /// let go with the nib up the whole time. It says which switch, it
    /// fires as the switch is LET GO — so that holding it and putting the
    /// nib down can still be the box — and once, however long it was held
    /// and however far the pen moved meanwhile.
    func testASwitchClickedInTheAirIsACommandOncePerClick() {
        XCTAssertEqual(phases(at()), [.hover])
        XCTAssertEqual(phases(at(side: true)), [.hover], "pressed: nothing yet")
        XCTAssertEqual(pen.armed, .lower)
        XCTAssertEqual(phases(at(7700, 4750, side: true)), [.hover], "held: it does not repeat")
        XCTAssertEqual(phases(at(9000, 8000, side: true)), [.hover])
        let click = at(9000, 8000)
        XCTAssertEqual(phases(click), [.click(.lower)], "the lower switch, let go in the air")
        XCTAssertFalse(click[0].sideSwitch, "a command, not a selection")
        XCTAssertEqual(click[0].pressure, 0)
        XCTAssertTrue(click[0].inProximity, "the marker stays where the pen is")
        XCTAssertFalse(pen.engaged)
        XCTAssertNil(pen.armed)
        XCTAssertEqual(phases(at(9000, 8000)), [.hover], "once a click")

        XCTAssertEqual(phases(at(upper: true)), [.hover])
        XCTAssertEqual(phases(at()), [.click(.upper)], "the upper switch")
        XCTAssertEqual(phases(at(side: true)), [.hover])
        XCTAssertEqual(phases(at()), [.click(.lower)], "and each click is one more")
    }

    /// The same sample by two routes counts once, so a click does too.
    func testAReleaseSeenTwiceIsOneClick() {
        _ = at(time: 10)
        _ = at(side: true, time: 10.008)
        XCTAssertEqual(phases(at(time: 10.016)), [.click(.lower)])
        XCTAssertEqual(at(time: 10.016), [], "the copy clicked again")
    }

    /// NOT WHILE THE NIB IS DOWN: a switch pressed and let go under a
    /// stroke of ink, or under a box, is no command — the stroke goes on as
    /// it was — and one pressed under ink and let go after the lift is
    /// none either.
    func testASwitchPressedWhileTheNibIsDownIsNoClick() {
        var seen: [TabletSample.Phase] = []
        seen += phases(at(tip: true, pressure: 0.5))
        seen += phases(at(7700, 4750, tip: true, side: true, pressure: 0.5))
        seen += phases(at(7800, 4750, tip: true, pressure: 0.5))
        seen += phases(at(7900, 4750, tip: true, upper: true, pressure: 0.5))
        seen += phases(at(8000, 4750, tip: true, pressure: 0.5))
        seen += phases(at(8000, 4750))
        XCTAssertEqual(seen, [.down, .drag, .drag, .drag, .drag, .up], "a switch under the ink did something")

        // Under a box: the upper one clicked while the lower holds the box.
        _ = at(side: true)
        seen = phases(at(tip: true, side: true, pressure: 0.5))
        seen += phases(at(7700, 4750, tip: true, side: true, upper: true, pressure: 0.5))
        seen += phases(at(7800, 4750, tip: true, side: true, pressure: 0.5))
        seen += phases(at(7800, 4750, side: true))
        seen += phases(at(7800, 4750))
        XCTAssertEqual(seen, [.down, .drag, .drag, .drag, .up], "a switch under the box did something")

        // Pressed under ink, let go after the lift.
        _ = at(tip: true, pressure: 0.5)
        _ = at(tip: true, upper: true, pressure: 0.5)
        XCTAssertEqual(phases(at(upper: true)), [.up])
        XCTAssertEqual(phases(at()), [.hover], "the nib touched while it was held")
    }

    /// THE PRESS HAS TO BE SEEN, IN REACH. A switch already held as the pen
    /// comes near was not pressed here; one held as the pen goes away was
    /// not let go here; and a reading that cannot say what the switches are
    /// doing — a report of the tablet's own that is not ready — is neither
    /// a press nor a letting go. None of them is a click.
    func testAClickIsPressedAndLetGoInReach() {
        XCTAssertEqual(near(true), [])
        XCTAssertEqual(phases(at(side: true)), [.hover], "came near already held")
        XCTAssertEqual(phases(at()), [.hover], "a switch that was never seen pressed clicked")

        XCTAssertEqual(phases(at(side: true)), [.hover])
        XCTAssertEqual(phases(near(false)), [.hover], "the pen left with the switch held")
        XCTAssertNil(pen.armed)
        XCTAssertEqual(near(true), [])
        XCTAssertEqual(phases(at()), [.hover], "and came back with it let go: no click")

        XCTAssertEqual(phases(at(side: true)), [.hover])
        XCTAssertEqual(phases(at(ready: false)), [.hover], "a reading that cannot say was taken for a letting go")
        XCTAssertEqual(phases(at(side: true)), [.hover], "still held when the tablet could say again")
        XCTAssertEqual(phases(at()), [.hover], "its press was not seen through")

        XCTAssertEqual(phases(at(side: true)), [.hover])
        XCTAssertEqual(phases(at()), [.click(.lower)], "and a click seen whole still is one")
    }

    /// TWO SWITCHES AT ONCE ARE NO COMMAND: there is no saying which was
    /// meant, so nothing fires until both are let go and one is pressed
    /// again.
    func testTwoSwitchesTogetherAreNoCommand() {
        _ = at()
        XCTAssertEqual(phases(at(side: true)), [.hover])
        XCTAssertEqual(phases(at(side: true, upper: true)), [.hover])
        XCTAssertEqual(phases(at(upper: true)), [.hover], "one of a pair let go was a click")
        XCTAssertEqual(phases(at()), [.hover], "and so was the other")
        XCTAssertEqual(phases(at(side: true, upper: true)), [.hover])
        XCTAssertEqual(phases(at()), [.hover], "both pressed at once, both let go at once")
        XCTAssertEqual(phases(at(upper: true)), [.hover])
        XCTAssertEqual(phases(at()), [.click(.upper)])
    }

    func testThePenLeavingHidesTheMarker() {
        _ = at(3800, 2375)
        XCTAssertEqual(near(false), [TabletSample(page: CGPoint(x: 0.75, y: 0.25), pressure: 0, phase: .hover,
                                                  sideSwitch: false, inProximity: false, timestamp: clock)])
        XCTAssertFalse(pen.inProximity)
    }

    func testLeavingWithTheNibDownLiftsItFirst() {
        _ = at(tip: true, pressure: 0.5)
        let out = near(false)
        XCTAssertEqual(phases(out), [.up, .hover])
        XCTAssertTrue(out[0].inProximity)
        XCTAssertFalse(out[1].inProximity)
        XCTAssertFalse(pen.engaged)
    }

    /// Coming near carries no position, so nothing is drawn until the pen
    /// is seen — the marker must not flash up where it was last time.
    func testComingNearSaysNothingUntilThePenIsSeen() {
        XCTAssertEqual(near(true), [])
        XCTAssertTrue(pen.inProximity)
        XCTAssertEqual(near(false), [], "out of reach having never been seen: nothing to hide")
    }

    /// THE SAME SAMPLE BY TWO ROUTES COUNTS ONCE: the timestamp is the
    /// sample's own, whichever monitor and whichever event type it came as.
    func testTheSameSampleTwiceCountsOnce() {
        XCTAssertEqual(phases(at(tip: true, pressure: 0.5, time: 10)), [.down])
        XCTAssertEqual(at(tip: true, pressure: 0.5, time: 10), [], "the copy")
        XCTAssertEqual(phases(at(tip: true, pressure: 0.5, time: 10.008)), [.drag])
        // A proximity event and a point are different things even at the
        // same moment: the leaving is not taken for a copy of the drag.
        let leaving = pen.consume(TabletReading(kind: .proximity(entering: false), timestamp: 10.008, native: true),
                                  extent: &extent, quarterTurns: 1)
        XCTAssertEqual(phases(leaving), [.up, .hover])
    }

    func testTheMarkerIsWhereThePenIsOnTheTurnedPage() {
        let hover = at(0, 0)
        XCTAssertEqual(hover[0].page, CGPoint(x: 1, y: 0), "the tablet's top left is the page's top right")
        XCTAssertTrue(hover[0].inProximity)
    }
}

/// The funnel's shell: what it takes, what it gives back, and when.
final class TabletInputTests: XCTestCase {
    private func penDrag(at nanos: UInt64 = 1_000, x: Int64 = 7600, y: Int64 = 4750) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                       mouseCursorPosition: CGPoint(x: 10, y: 10), mouseButton: .left))
        cg.setIntegerValueField(.mouseEventSubtype, value: 1)
        cg.setIntegerValueField(.tabletEventPointX, value: x)
        cg.setIntegerValueField(.tabletEventPointY, value: y)
        cg.setIntegerValueField(.tabletEventPointButtons, value: 1)
        cg.setDoubleValueField(.mouseEventPressure, value: 0.5)
        cg.timestamp = nanos
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    private func trackpadDrag() throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                       mouseCursorPosition: CGPoint(x: 10, y: 10), mouseButton: .left))
        cg.setIntegerValueField(.mouseEventSubtype, value: 3)
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    private func pureTabletPoint(at nanos: UInt64 = 5_000) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(source: nil))
        cg.type = .tabletPointer
        cg.setIntegerValueField(.tabletEventPointX, value: 3800)
        cg.setIntegerValueField(.tabletEventPointY, value: 2375)
        cg.setIntegerValueField(.tabletEventPointButtons, value: 1)
        cg.setDoubleValueField(.tabletEventPointPressure, value: 0.4)
        cg.timestamp = nanos
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    private func pureProximity(at nanos: UInt64 = 4_000) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(source: nil))
        cg.type = .tabletProximity
        cg.setIntegerValueField(.tabletProximityEventEnterProximity, value: 1)
        cg.timestamp = nanos
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    /// A PURE TABLET EVENT HAS NO SUBTYPE TO ASK: `subtype` on one is an
    /// exception that takes the app down (measured 2026-10-02) — and the
    /// driver does send them: the pen coming near arrives as one. Through
    /// the whole funnel, both routes, taken or not, the first-event log
    /// line included.
    func testPureTabletEventsGoThroughWithoutAQuestionTheyCannotAnswer() throws {
        let input = TabletInput()
        var lines: [String] = []
        input.log = { lines.append($0) }
        let point = try pureTabletPoint()
        let near = try pureProximity()
        XCTAssertTrue(input.handle(point, from: .local) === point)
        XCTAssertTrue(input.handle(near, from: .global) === near)
        XCTAssertEqual(lines.count, 2, "the first of each kind is written down")
        XCTAssertTrue(lines.allSatisfy { $0.contains("native=true") }, "\(lines)")

        input.start()
        input.pageAppeared()
        XCTAssertNil(input.handle(try pureProximity(at: 6_000), from: .local))
        XCTAssertNil(input.handle(try pureTabletPoint(at: 7_000), from: .local))
        XCTAssertEqual(input.pen?.phase, .down)
        XCTAssertEqual(input.pen?.page, CGPoint(x: 0.75, y: 0.25))
    }

    /// Not the input, or no page on screen: every event goes back exactly
    /// as it came, the pen's included — the pen is a pointer then.
    func testNothingIsTakenUnlessThePageIsShowing() throws {
        let input = TabletInput()
        let pen = try penDrag()
        XCTAssertTrue(input.handle(pen, from: .local) === pen)
        input.start()
        XCTAssertTrue(input.handle(pen, from: .local) === pen, "the tablet is the input, but no page is up")
        input.stop()
        input.pageAppeared()
        XCTAssertTrue(input.handle(pen, from: .local) === pen, "a page, but no tablet")
    }

    /// While the page is up the pen's events are SWALLOWED — a tap must not
    /// click whatever is under the pointer — and the trackpad's never are.
    func testWhileThePageIsUpThePenIsTheirsAndTheTrackpadIsNot() throws {
        let input = TabletInput()
        input.start()
        input.pageAppeared()
        XCTAssertTrue(input.isCapturing)
        var got: [TabletSample] = []
        let watching = input.samples.sink { got.append($0) }
        defer { watching.cancel() }

        XCTAssertNil(input.handle(try penDrag(at: 1_000), from: .local), "the pen's event reached the window")
        let trackpad = try trackpadDrag()
        XCTAssertTrue(input.handle(trackpad, from: .local) === trackpad)
        XCTAssertEqual(got.map(\.phase), [.down])
        XCTAssertEqual(input.pen?.page, CGPoint(x: 0.5, y: 0.5))

        // The same sample again — swallowed, and not drawn twice.
        XCTAssertNil(input.handle(try penDrag(at: 1_000), from: .local))
        XCTAssertEqual(got.count, 1)
    }

    /// The global route sees events going to OTHER apps. They count only
    /// while WriteMind is in front — a pen used in another app must not
    /// write on this page.
    func testTheGlobalRouteCountsOnlyWhileWriteMindIsInFront() throws {
        let input = TabletInput()
        input.start()
        input.pageAppeared()
        var active = false
        input.appIsActive = { active }
        var got = 0
        let watching = input.samples.sink { _ in got += 1 }
        defer { watching.cancel() }

        _ = input.handle(try penDrag(at: 1_000), from: .global)
        XCTAssertEqual(got, 0)
        active = true
        _ = input.handle(try penDrag(at: 2_000), from: .global)
        XCTAssertEqual(got, 1)
    }

    /// Two windows can each have a page; the first to go must not take the
    /// pen from the other.
    func testThePenIsThePagesWhileAnyPageIsUp() {
        let input = TabletInput()
        input.start()
        input.pageAppeared()
        input.pageAppeared()
        input.pageDisappeared()
        XCTAssertTrue(input.isCapturing)
        input.pageDisappeared()
        XCTAssertFalse(input.isCapturing)
        input.pageDisappeared()
        input.pageAppeared()
        XCTAssertTrue(input.isCapturing, "one too many goings did not leave the count below nothing")
    }

    func testStoppingForgetsThePen() throws {
        let input = TabletInput()
        input.start()
        input.pageAppeared()
        _ = input.handle(try penDrag(), from: .local)
        XCTAssertNotNil(input.pen)
        input.stop()
        XCTAssertNil(input.pen)
        XCTAssertFalse(input.isCapturing)
    }

    func testThePenReachingPastTheTableWidensTheExtent() throws {
        let input = TabletInput()
        input.extent = TabletExtent(width: 15200, height: 9500)
        input.start()
        input.pageAppeared()
        _ = input.handle(try penDrag(x: 15600, y: 100), from: .local)
        XCTAssertEqual(input.extent, TabletExtent(width: 15600, height: 9500))
    }

    // MARK: - The raw route

    private func rawPoint(x: Double = 3800, y: Double = 2375, tip: Bool = false, pressure: Double = 0,
                          at time: TimeInterval) -> TabletReading {
        TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: tip, switches: [], pressure: pressure,
                                   buttons: tip ? 1 : 0), timestamp: time, native: true)
    }

    private func capturing() -> (TabletInput, () -> [TabletSample], AnyCancellable) {
        let input = TabletInput()
        input.start()
        input.pageAppeared()
        var got: [TabletSample] = []
        let watching = input.samples.sink { got.append($0) }
        return (input, { got }, watching)
    }

    // MARK: - A click of a side switch, by both routes

    /// One of the tablet's own reports at the middle of the small One by
    /// Wacom (7600, 4750), `flags` its second byte; the tip down presses.
    private func report(_ flags: UInt8, at time: TimeInterval) throws -> TabletReading {
        let pressure: [UInt8] = flags & 0x01 != 0 ? [0x00, 0x04] : [0, 0]
        return try XCTUnwrap(WacomPenPacket([2, flags, 0xB0, 0x1D, 0x8E, 0x12] + pressure + [0, 0])).reading(at: time)
    }

    /// One of the driver's events at the same place: a mouse event with the
    /// tablet subtype, `buttons` its mask.
    private func driverEvent(_ type: CGEventType, buttons: Int64, at nanos: UInt64) throws -> NSEvent {
        let right: Set<CGEventType> = [.rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type,
                                       mouseCursorPosition: CGPoint(x: 10, y: 10),
                                       mouseButton: right.contains(type) ? .right : .left))
        cg.setIntegerValueField(.mouseEventSubtype, value: 1)
        cg.setIntegerValueField(.tabletEventPointX, value: 7600)
        cg.setIntegerValueField(.tabletEventPointY, value: 4750)
        cg.setIntegerValueField(.tabletEventPointButtons, value: buttons)
        cg.setDoubleValueField(.mouseEventPressure, value: buttons & 1 != 0 ? 0.5 : 0)
        cg.timestamp = nanos
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    /// OFF THE TABLET'S OWN REPORTS — the pen captured — each switch
    /// clicked in the air comes down the one stream as its own click, an
    /// event of its own kind: the lower (0x02) and the upper (0x04) (Sean,
    /// 2026-10-02: "make the wacom buttons undo and redo last drawing").
    func testEachSwitchClickedInTheAirIsItsOwnClickOffTheRawReports() throws {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        for (step, flags) in ([0xE0, 0xE2, 0xE2, 0xE0, 0xE4, 0xE0, 0xE0] as [UInt8]).enumerated() {
            input.raw(try report(flags, at: 20 + Double(step) * 0.008))
        }
        XCTAssertEqual(got().map(\.phase), [.hover, .hover, .hover, .click(.lower), .hover, .click(.upper), .hover])
        XCTAssertEqual(got().filter { $0.phase != .hover }.map(\.page), [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.5)],
                       "where the pen was")
        XCTAssertEqual(input.pen?.phase, .hover, "and the marker is still the pen's")
    }

    /// THE LOG SAYS WHICH SWITCH A CLICK WAS, once each: that 0x02 is the
    /// button nearer the nib is the Linux driver's word, never checked
    /// against Sean's own pen — a session's log is how it gets checked.
    func testTheFirstClickOfEachSwitchIsWrittenDown() throws {
        let (input, _, watching) = capturing()
        defer { watching.cancel() }
        var lines: [String] = []
        input.log = { lines.append($0) }
        for (step, flags) in ([0xE0, 0xE2, 0xE0, 0xE2, 0xE0, 0xE4, 0xE0, 0xE4, 0xE0] as [UInt8]).enumerated() {
            input.raw(try report(flags, at: 20 + Double(step) * 0.008))
        }
        let clicks = lines.filter { $0.contains("click") }
        XCTAssertEqual(clicks.count, 2, "one line a switch, not one a click: \(lines)")
        XCTAssertTrue(clicks.first?.contains("lower") == true, "\(clicks)")
        XCTAssertTrue(clicks.last?.contains("upper") == true, "\(clicks)")
    }

    /// Off the same reports, a switch HELD AS THE NIB GOES DOWN is still
    /// the box — either switch — going on while the nib or the switch is
    /// down, and letting it go afterwards is no click.
    func testASwitchHeldAsTheNibGoesDownIsStillTheBoxOffTheRawReports() throws {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        for (step, flags) in ([0xE0, 0xE4, 0xE5, 0xE5, 0xE4, 0xE0, 0xE2, 0xE3, 0xE1, 0xE0] as [UInt8]).enumerated() {
            input.raw(try report(flags, at: 20 + Double(step) * 0.008))
        }
        XCTAssertEqual(got().map(\.phase), [.hover, .hover, .down, .drag, .drag, .up, .hover, .down, .drag, .up])
        XCTAssertEqual(got().map(\.sideSwitch), [false, false, true, true, true, true, false, true, true, true])
    }

    /// A REPORT THAT IS NOT READY SAYS NOTHING OF THE SWITCHES — as the
    /// pen is taken away, say (unmeasured on the LP-190K; a precaution): a
    /// switch held as the pen goes has not been let go, and is no click —
    /// nor is one held when the tablet itself is let go.
    func testASwitchHeldAsThePenLeavesIsNoClick() throws {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        for (step, flags) in ([0xE0, 0xE2, 0xC0, 0x80, 0x00] as [UInt8]).enumerated() {
            input.raw(try report(flags, at: 20 + Double(step) * 0.008))
        }
        XCTAssertEqual(got().map(\.phase), [.hover, .hover, .hover, .hover], "taking the pen away clicked")
        XCTAssertEqual(got().last?.inProximity, false)

        input.raw(try report(0xE0, at: 21))
        input.raw(try report(0xE4, at: 21.008))
        input.rawEnded(at: 21.016)
        XCTAssertEqual(got().dropFirst(4).map(\.phase), [.hover, .hover, .hover], "the tablet let go clicked")
    }

    /// BY THE DRIVER'S EVENTS — the fallback, the pen not captured — the
    /// lower switch is the right button: clicked in the air it is the lower
    /// switch's click, and every event of it is still swallowed, so nothing
    /// under the pointer gets a right click.
    func testTheDriversRightButtonClickedInTheAirIsTheLowerSwitchsClick() throws {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        XCTAssertNil(input.handle(try driverEvent(.mouseMoved, buttons: 0, at: 1_000_000), from: .local))
        XCTAssertNil(input.handle(try driverEvent(.rightMouseDown, buttons: 2, at: 2_000_000), from: .local))
        XCTAssertNil(input.handle(try driverEvent(.rightMouseDragged, buttons: 2, at: 3_000_000), from: .local))
        XCTAssertNil(input.handle(try driverEvent(.rightMouseUp, buttons: 0, at: 4_000_000), from: .local))
        XCTAssertNil(input.handle(try driverEvent(.mouseMoved, buttons: 0, at: 5_000_000), from: .local))
        XCTAssertEqual(got().map(\.phase), [.hover, .hover, .hover, .click(.lower), .hover])
    }

    /// And by the driver's events the right button held as the nib goes
    /// down is still the box: the nib's own events say the switch is held
    /// by their mask, and the box goes on until the button is let go.
    func testTheDriversRightButtonHeldAsTheNibGoesDownIsStillTheBox() throws {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        let events: [(CGEventType, Int64)] = [(.mouseMoved, 0), (.rightMouseDown, 2), (.leftMouseDown, 3),
                                              (.leftMouseDragged, 3), (.leftMouseUp, 2), (.rightMouseUp, 0)]
        for (step, event) in events.enumerated() {
            XCTAssertNil(input.handle(try driverEvent(event.0, buttons: event.1, at: UInt64(step + 1) * 1_000_000),
                                      from: .local))
        }
        XCTAssertEqual(got().map(\.phase), [.hover, .hover, .down, .drag, .drag, .up])
        XCTAssertEqual(got().map(\.sideSwitch), [false, false, true, true, true, true])
    }

    /// THE UPPER SWITCH BY THE DRIVER'S EVENTS is the mask's 0x4, and held
    /// as the nib goes down it is the box by this route as by the raw
    /// reports — the masks as measured, a down with 0x5 and an up with 0x4.
    /// Should a hover's mask carry it too (not yet seen), its click is the
    /// upper's.
    func testTheDriversUpperSwitchIsTheMasksAndHeldAsTheNibGoesDownIsTheBox() throws {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        let events: [(CGEventType, Int64)] = [(.mouseMoved, 0), (.leftMouseDown, 5), (.leftMouseDragged, 5),
                                              (.leftMouseUp, 4), (.mouseMoved, 0),
                                              (.mouseMoved, 4), (.mouseMoved, 4), (.mouseMoved, 0)]
        for (step, event) in events.enumerated() {
            XCTAssertNil(input.handle(try driverEvent(event.0, buttons: event.1, at: UInt64(step + 1) * 1_000_000),
                                      from: .local))
        }
        XCTAssertEqual(got().map(\.phase), [.hover, .down, .drag, .drag, .up, .hover, .hover, .click(.upper)])
        XCTAssertEqual(got().map(\.sideSwitch), [false, true, true, true, true, false, false, false],
                       "the upper switch held as the nib went down wrote ink")
    }

    /// ONE FUNNEL: a reading off the tablet itself goes through the same
    /// pen state, the same turn and the same stream as an event's.
    func testARawReadingIsThePenLikeAnyOther() {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        input.raw(rawPoint(at: 20))
        input.raw(rawPoint(tip: true, pressure: 0.5, at: 20.008))
        XCTAssertEqual(got().map(\.phase), [.hover, .down])
        guard got().count == 2 else { return }
        XCTAssertEqual(got()[1].page, CGPoint(x: 0.75, y: 0.25))
        XCTAssertEqual(got()[1].pressure, 0.5)
        XCTAssertEqual(input.pen?.phase, .down, "the marker follows it")
        XCTAssertEqual(input.rawSince, 20)
    }

    /// A reading that arrives with nothing to write on — the tablet being
    /// let go as the page went — writes nothing.
    func testARawReadingWithNoTargetUpIsDropped() {
        let input = TabletInput()
        input.start()
        var got = 0
        let watching = input.samples.sink { _ in got += 1 }
        defer { watching.cancel() }
        input.raw(rawPoint(at: 20))
        XCTAssertEqual(got, 0)
        XCTAssertNil(input.rawSince)
    }

    /// ONE ROUTE AT A TIME: once the tablet itself is delivering, what the
    /// driver posts is still the pen's — swallowed, so a tap clicks nothing
    /// — and draws nothing: the same stroke by both routes would be two.
    func testWhileTheTabletDeliversTheDriversEventsDrawNothing() throws {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        input.raw(rawPoint(at: 20))
        XCTAssertNil(input.handle(try penDrag(at: 20_100_000_000), from: .local), "the pen's event reached the window")
        _ = input.handle(try penDrag(at: 20_200_000_000), from: .global)
        XCTAssertEqual(got().map(\.phase), [.hover], "the driver's event drew beside the tablet's own")
        let trackpad = try trackpadDrag()
        XCTAssertTrue(input.handle(trackpad, from: .local) === trackpad, "the trackpad is never the pen's")
    }

    /// Held but silent — WriteMind has the device and no pen report has
    /// come — is not delivering: until one does, the driver's events still
    /// write. A capture that brings nothing must not cost the page its pen.
    func testUntilTheFirstRawReportTheDriversEventsStillWrite() throws {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        XCTAssertNil(input.handle(try penDrag(at: 1_000), from: .local))
        XCTAssertEqual(got().map(\.phase), [.down])
    }

    /// The tablet let go — the app left the front, the page went: a stroke
    /// under way ends where it was, the marker goes, and the driver's
    /// events are the pen again.
    func testTheTabletLetGoLiftsThePenAndGivesTheRouteBack() throws {
        let (input, got, watching) = capturing()
        defer { watching.cancel() }
        input.raw(rawPoint(tip: true, pressure: 0.4, at: 20))
        input.rawEnded(at: 21)
        XCTAssertEqual(got().map(\.phase), [.down, .up, .hover])
        guard got().count == 3 else { return }
        XCTAssertEqual(got()[1].page, CGPoint(x: 0.75, y: 0.25), "lifted where it was")
        XCTAssertNil(input.pen)
        XCTAssertNil(input.rawSince)
        input.rawEnded(at: 22)
        XCTAssertEqual(got().count, 3, "let go once")
        XCTAssertNil(input.handle(try penDrag(at: 23_000_000_000), from: .local))
        XCTAssertEqual(got().last?.phase, .down, "the driver's events write again")
    }

    /// A SEIZED TABLET OUGHT TO SEND THE DRIVER NOTHING. Events it made
    /// before the tablet was taken are still on their way up for a moment;
    /// events made well after say the driver still hears it — written down
    /// once, and told to whoever is listening.
    func testEventsThatKeepComingSayTheDriverStillPosts() throws {
        let (input, _, watching) = capturing()
        defer { watching.cancel() }
        var lines: [String] = []
        input.log = { lines.append($0) }
        var told: [Bool] = []
        input.driverStillPostsChanged = { told.append($0) }
        input.raw(rawPoint(at: 20))
        _ = input.handle(try penDrag(at: 19_990_000_000), from: .local)
        _ = input.handle(try penDrag(at: 20_300_000_000), from: .local)
        XCTAssertFalse(input.driverStillPosts, "a straggler from before the tablet was taken")
        XCTAssertEqual(lines.filter { $0.contains("a pen event from the driver while seized") }.count, 1,
                       "the first is written down whatever it turns out to be: \(lines)")
        _ = input.handle(try penDrag(at: 21_000_000_000), from: .local)
        _ = input.handle(try penDrag(at: 21_008_000_000), from: .local)
        XCTAssertTrue(input.driverStillPosts)
        XCTAssertEqual(told, [true])
        XCTAssertEqual(lines.filter { $0.contains("driver still posts events while seized") }.count, 1, "once")
        // Picked again, it is a fresh question.
        input.start()
        XCTAssertFalse(input.driverStillPosts)
        XCTAssertEqual(told, [true, false])
    }

    func testOnlyAnEventMadeWellAfterTheFirstReportCounts() {
        XCTAssertFalse(TabletInput.stillPosting(eventAt: 19.9, rawSince: 20))
        XCTAssertFalse(TabletInput.stillPosting(eventAt: 20 + TabletInput.stragglers, rawSince: 20))
        XCTAssertTrue(TabletInput.stillPosting(eventAt: 20.6, rawSince: 20))
    }
}
