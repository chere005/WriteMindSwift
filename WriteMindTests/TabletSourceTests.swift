import Combine
import XCTest
@testable import WriteMind

/// A MOMENT OF THE PEN IS THE REPORT THE TABLET WOULD SEND (Sean,
/// 2026-10-03: "make sure i can develop wacom features without a device
/// plugged in"): the virtual tablet, the test script and the recorded
/// fixtures all say it as a `PenFrame`, and what the funnel reads out of its
/// bytes is what the real tablet's bytes would have been read as.
final class PenFrameTests: XCTestCase {
    /// The bytes the One by Wacom sends for a pen hovering at the middle:
    /// the helper in `TabletControllerTests` was written from real reports.
    func testAHoverIsTheReportTheTabletSends() {
        let hover = PenFrame(counts: CGPoint(x: 7600, y: 4750))
        XCTAssertEqual(hover.report, penReport(x: 7600, y: 4750, flags: 0xE0))
    }

    func testANibDownCarriesTheTipAndThePressure() {
        let down = PenFrame(counts: CGPoint(x: 7600, y: 4750), tip: true, pressure: 0.5, distance: 0)
        XCTAssertEqual(Array(down.report.prefix(8)), Array(penReport(x: 7600, y: 4750, flags: 0xE1, pressure: 1024).prefix(8)))
        XCTAssertEqual(WacomPenPacket.rawPressure(1), 2047)
        XCTAssertEqual(WacomPenPacket.rawPressure(0), 0)
        XCTAssertEqual(WacomPenPacket.rawPressure(7), 2047, "past full is full")
        XCTAssertEqual(WacomPenPacket.rawPressure(-1), 0)
    }

    func testEachSwitchIsItsOwnBit() {
        XCTAssertEqual(PenFrame(switches: [.lower]).report[1], 0xE2)
        XCTAssertEqual(PenFrame(switches: [.upper]).report[1], 0xE4)
        XCTAssertEqual(PenFrame(switches: [.lower, .upper]).report[1], 0xE6)
        XCTAssertEqual(PenFrame(tip: true, switches: [.lower]).report[1], 0xE3)
    }

    func testTheArrivingAndTheAwayReports() {
        let arriving = PenFrame.arriving(at: CGPoint(x: 100, y: 200))
        XCTAssertEqual(arriving.report[1], 0x80, "in range, no position")
        XCTAssertEqual(WacomPenPacket(arriving.report)?.reading(at: 1).kind, .proximity(entering: true))
        let away = PenFrame.away(at: CGPoint(x: 100, y: 200))
        XCTAssertEqual(away.report[1], 0x00)
        XCTAssertEqual(WacomPenPacket(away.report)?.reading(at: 1).kind, .proximity(entering: false))
    }

    /// Every combination of what a report says reads back as what was said,
    /// and a frame's own `reading` is the same rule applied to the exact
    /// pressure: the two differ only by the report's quantisation.
    func testEveryFrameReadsBackAsWhatWasSaid() throws {
        for inRange in [true, false] {
            for hasPosition in [true, false] {
                for ready in [true, false] {
                    for tip in [true, false] {
                        for lower in [true, false] {
                            for upper in [true, false] {
                                var switches: Set<PenSwitch> = []
                                if lower { switches.insert(.lower) }
                                if upper { switches.insert(.upper) }
                                let frame = PenFrame(inRange: inRange, hasPosition: hasPosition, ready: ready,
                                                     counts: CGPoint(x: 3801, y: 2377), tip: tip, pressure: 0.3,
                                                     switches: switches)
                                let packet = try XCTUnwrap(WacomPenPacket(frame.report))
                                XCTAssertEqual(packet.inRange, inRange)
                                XCTAssertEqual(packet.hasPosition, hasPosition)
                                XCTAssertEqual(packet.isReady, ready)
                                XCTAssertEqual(packet.tip, tip)
                                XCTAssertEqual(packet.lowerSwitch, lower)
                                XCTAssertEqual(packet.upperSwitch, upper)
                                XCTAssertEqual(packet.x, 3801)
                                XCTAssertEqual(packet.y, 2377)
                                let exact = frame.reading(at: 5)
                                let bytes = packet.reading(at: 5)
                                switch (exact.kind, bytes.kind) {
                                case (.point(let a, let tipA, let sa, let pa, let ba),
                                      .point(let b, let tipB, let sb, let pb, let bb)):
                                    XCTAssertEqual(a, b)
                                    XCTAssertEqual(tipA, tipB)
                                    XCTAssertEqual(sa, sb)
                                    XCTAssertEqual(pa, pb, accuracy: 1 / 2047)
                                    XCTAssertEqual(ba, bb)
                                default:
                                    XCTAssertEqual(exact.kind, bytes.kind)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testTheExactReadingKeepsAPressureTheReportCannot() {
        let frame = PenFrame(counts: CGPoint(x: 10, y: 10), tip: true, pressure: 0.3)
        guard case .point(_, _, _, let pressure, _) = frame.reading(at: 1).kind else { return XCTFail() }
        XCTAssertEqual(pressure, 0.3)
    }

    func testACountOffTheFieldIsKeptOnIt() {
        XCTAssertEqual(PenFrame(counts: CGPoint(x: -5, y: 99999)).report[2...5], [0, 0, 0xFF, 0xFF])
        XCTAssertEqual(PenFrame(counts: CGPoint(x: CGFloat.nan, y: 0)).report[2...3], [0, 0])
    }
}

/// THE INVERSE OF THE TURN: the pad is drawn as the page is, and its
/// pointer has to be turned back into the counts the real tablet would
/// have reported at the same place.
final class TabletMappingInverseTests: XCTestCase {
    func testPageAndCountsAreInversesForEveryTurn() {
        let extent = TabletExtent(width: 15200, height: 9500)
        for turns in -1...5 {
            for u in stride(from: 0.0, through: 1.0, by: 0.125) {
                for v in stride(from: 0.0, through: 1.0, by: 0.125) {
                    let counts = TabletMapping.counts(forPage: CGPoint(x: u, y: v), extent: extent, quarterTurns: turns)
                    let page = TabletMapping.page(counts, extent: extent, quarterTurns: turns)
                    XCTAssertEqual(page.x, u, accuracy: 1e-9, "turn \(turns) at (\(u), \(v))")
                    XCTAssertEqual(page.y, v, accuracy: 1e-9, "turn \(turns) at (\(u), \(v))")
                }
            }
        }
    }

    /// The tablet's top left, one quarter turn clockwise, is the page's
    /// top right.
    func testTheDefaultTurnPutsTheTabletsTopLeftAtThePagesTopRight() {
        let extent = TabletExtent(width: 15200, height: 9500)
        XCTAssertEqual(TabletMapping.counts(forPage: CGPoint(x: 1, y: 0), extent: extent, quarterTurns: 1), .zero)
        XCTAssertEqual(TabletMapping.counts(forPage: CGPoint(x: 0.5, y: 0.5), extent: extent, quarterTurns: 1),
                       CGPoint(x: 7600, y: 4750))
    }

    func testAPointOffThePageIsOnIt() {
        let extent = TabletExtent(width: 15200, height: 9500)
        XCTAssertEqual(TabletMapping.counts(forPage: CGPoint(x: 2, y: -1), extent: extent, quarterTurns: 0),
                       CGPoint(x: 15200, y: 0))
    }
}

/// WHO MAY SPEAK, in one place.
final class TabletSourcePolicyTests: XCTestCase {
    func testTheRealDeviceIsAlwaysHeard() {
        for developer in [true, false] {
            for real in [true, false] {
                let policy = TabletSourcePolicy(developerOn: developer, realConnected: real)
                XCTAssertTrue(policy.admits(.hid))
                XCTAssertTrue(policy.admits(.driver))
            }
        }
    }

    /// OFF BY DEFAULT: a policy nobody touched hears nothing virtual.
    func testTheStandInsAreOffUntilSwitchedOn() {
        let policy = TabletSourcePolicy()
        XCTAssertFalse(policy.admits(.virtual))
        XCTAssertFalse(policy.admits(.replay))
        XCTAssertNotNil(policy.silence)
    }

    func testSwitchedOnWithNoRealTabletTheyAreHeard() {
        let policy = TabletSourcePolicy(developerOn: true, realConnected: false)
        XCTAssertTrue(policy.admits(.virtual))
        XCTAssertTrue(policy.admits(.replay))
        XCTAssertNil(policy.silence)
    }

    /// THE REAL DEVICE WINS WHENEVER IT IS CONNECTED.
    func testARealTabletPluggedInSilencesTheStandIns() {
        let policy = TabletSourcePolicy(developerOn: true, realConnected: true)
        XCTAssertFalse(policy.admits(.virtual))
        XCTAssertFalse(policy.admits(.replay))
        XCTAssertTrue(policy.silence?.contains("real tablet") == true)
    }
}

/// The one door: who gets through it, and into what.
@MainActor
final class TabletDoorTests: XCTestCase {
    private func rig() -> (TabletInput, VirtualPen, VirtualClock, () -> [TabletSample], AnyCancellable) {
        let input = TabletInput()
        input.start()
        input.pageAppeared()
        let clock = VirtualClock()
        let pen = VirtualPen(clock: clock)
        input.attach(pen)
        var heard: [TabletSample] = []
        let watching = input.samples.sink { heard.append($0) }
        return (input, pen, clock, { heard }, watching)
    }

    /// A RELEASE USER'S FLOW: nothing switched on, and a virtual pen — which
    /// is always there, built with the controller — says nothing the page
    /// hears.
    func testTheVirtualPenIsNotHeardUnlessADeveloperSwitchedItOn() {
        let (input, pen, clock, heard, watching) = rig()
        defer { watching.cancel() }
        clock.advance(by: 1)
        pen.move(to: CGPoint(x: 7600, y: 4750))
        pen.touch()
        pen.lift()
        XCTAssertEqual(heard(), [], "the virtual tablet spoke with the switch off")
        XCTAssertNil(input.pen)

        input.policy.developerOn = true
        clock.advance(by: 1)
        pen.move(to: CGPoint(x: 7600, y: 4750))
        pen.touch()
        XCTAssertEqual(heard().map(\.phase), [.hover, .down])
    }

    func testARealTabletPluggedInSilencesTheVirtualPenWhateverIsSwitchedOn() {
        let (input, pen, clock, heard, watching) = rig()
        defer { watching.cancel() }
        input.policy = TabletSourcePolicy(developerOn: true, realConnected: true)
        clock.advance(by: 1)
        pen.move(to: CGPoint(x: 7600, y: 4750))
        XCTAssertEqual(heard(), [])

        // And the real HID reader is heard all the same, by the same door.
        let hid = HIDTabletSource()
        input.attach(hid)
        hid.emit(.report(penReport(flags: 0xE0)), at: 50)
        XCTAssertEqual(heard().map(\.phase), [.hover])
    }

    /// What goes through the door is the tablet's word, and a report that
    /// is not a pen report is not the pen's.
    func testAReportThatIsNotThePensIsNobodysBusiness() {
        let (input, _, _, heard, watching) = rig()
        defer { watching.cancel() }
        input.policy.developerOn = true
        let hid = HIDTabletSource()
        input.attach(hid)
        hid.emit(.report([2, 0xE0, 0, 0]), at: 1)
        hid.emit(.report([UInt8](repeating: 2, count: 64)), at: 2)
        XCTAssertEqual(heard(), [])
        hid.emit(.report(penReport()), at: 3)
        XCTAssertEqual(heard().count, 1)
    }

    /// Nothing is heard with nowhere to write: the same rule as for the
    /// real tablet's reports.
    func testNothingIsHeardWithNoPageOnScreen() {
        let input = TabletInput()
        input.start()
        input.policy.developerOn = true
        let pen = VirtualPen(clock: VirtualClock())
        input.attach(pen)
        let recorder = PenRecorder()
        input.recorder = recorder
        var got = 0
        let watching = input.samples.sink { _ in got += 1 }
        defer { watching.cancel() }
        pen.move(to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(got, 0)
        XCTAssertTrue(recorder.isEmpty, "what had nowhere to go is not part of a session")
    }

    /// What is heard is what is recorded, from every source that was heard
    /// — and nothing that was turned away.
    func testWhatIsHeardIsRecordedAndNothingElse() {
        let (input, pen, clock, _, watching) = rig()
        defer { watching.cancel() }
        let recorder = PenRecorder()
        input.recorder = recorder
        // Turned away: the virtual pen with the switch off.
        clock.advance(by: 1)
        pen.move(to: CGPoint(x: 1, y: 1))
        XCTAssertTrue(recorder.isEmpty, "a source nobody heard was written down")

        let hid = HIDTabletSource()
        input.attach(hid)
        hid.emit(.report(penReport()), at: 100)
        hid.emit(.report([2, 1, 2]), at: 100.1)
        XCTAssertEqual(recorder.entries.map(\.event), [.report(penReport())], "a report that is not the pen's is no part of it")
        XCTAssertEqual(recorder.sources, [.hid])

        input.policy.developerOn = true
        clock.advance(by: 1)
        pen.move(to: CGPoint(x: 1, y: 1))
        XCTAssertEqual(recorder.sources, [.hid, .virtual])
        XCTAssertEqual(recorder.recording(extent: nil, productID: nil, quarterTurns: nil).header.source, "mixed")
    }

    private func driverEvent(_ type: CGEventType, buttons: Int64, at nanos: UInt64) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 10, y: 10),
                                       mouseButton: .left))
        cg.setIntegerValueField(.mouseEventSubtype, value: 1)
        cg.setIntegerValueField(.tabletEventPointX, value: 7600)
        cg.setIntegerValueField(.tabletEventPointY, value: 4750)
        cg.setIntegerValueField(.tabletEventPointButtons, value: buttons)
        cg.setDoubleValueField(.mouseEventPressure, value: buttons & 1 != 0 ? 0.5 : 0)
        cg.timestamp = nanos
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    /// The fallback route has no bytes to give: a session made from the
    /// driver's events is recorded as the readings they were made into, by
    /// the funnel's own `handle`.
    func testTheDriversEventsAreRecordedAsReadings() throws {
        let (input, _, _, heard, watching) = rig()
        defer { watching.cancel() }
        let recorder = PenRecorder()
        input.recorder = recorder
        XCTAssertNil(input.handle(try driverEvent(.mouseMoved, buttons: 0, at: 1_000_000_000), from: .local))
        XCTAssertNil(input.handle(try driverEvent(.leftMouseDown, buttons: 1, at: 1_008_000_000), from: .local))
        XCTAssertEqual(heard().map(\.phase), [.hover, .down])
        XCTAssertEqual(recorder.entries.count, 2)
        XCTAssertEqual(recorder.sources, [.driver])
        XCTAssertEqual(recorder.entries[0].time, 0)
        XCTAssertEqual(recorder.entries[1].time, 0.008, accuracy: 1e-9)
        guard case .reading(let reading) = recorder.entries[1].event, case .point(_, let tip, _, _, _) = reading.kind else {
            return XCTFail("not a point reading")
        }
        XCTAssertTrue(tip)
        XCTAssertFalse(reading.native)
    }
}

/// The virtual pen: stamps, taps, double presses — on a clock that never
/// sleeps.
@MainActor
final class VirtualPenTests: XCTestCase {
    private func make() -> (VirtualPen, VirtualClock, () -> [(frame: PenFrame, time: TimeInterval)]) {
        let clock = VirtualClock()
        let pen = VirtualPen(clock: clock)
        var frames: [(frame: PenFrame, time: TimeInterval)] = []
        pen.onFrame = { frames.append(($0, $1)) }
        return (pen, clock, { frames })
    }

    func testComingNearSaysSoBeforeItSaysWhere() {
        let (pen, _, frames) = make()
        pen.move(to: CGPoint(x: 1000, y: 2000))
        XCTAssertEqual(frames().count, 2)
        XCTAssertFalse(frames()[0].frame.hasPosition, "in range, no position yet")
        XCTAssertTrue(frames()[0].frame.inRange)
        XCTAssertTrue(frames()[1].frame.hasPosition)
        XCTAssertEqual(frames()[1].frame.counts, CGPoint(x: 1000, y: 2000))
        pen.move(to: CGPoint(x: 1100, y: 2000))
        XCTAssertEqual(frames().count, 3, "near already: no second arrival")
    }

    /// Two reports never share a stamp, even with the clock standing still:
    /// to the pen's state machine that is one report seen twice.
    func testStampsOnlyIncrease() {
        let (pen, _, frames) = make()
        pen.move(to: .zero)
        pen.touch()
        pen.lift()
        pen.leave()
        let stamps = frames().map(\.time)
        XCTAssertEqual(stamps, stamps.sorted())
        XCTAssertEqual(Set(stamps).count, stamps.count)
    }

    func testTheNibCarriesThePressureItWentDownWithAndTheSliderChangesIt() {
        let (pen, _, frames) = make()
        pen.move(to: CGPoint(x: 1000, y: 1000))
        pen.touch(pressure: 0.25)
        XCTAssertEqual(frames().last?.frame.pressure, 0.25)
        pen.setPressure(0.75)
        XCTAssertEqual(frames().last?.frame.pressure, 0.75, "the slider moved with the nib down: a report says so")
        pen.lift()
        XCTAssertEqual(frames().last?.frame.pressure, 0)
        XCTAssertFalse(frames().last?.frame.tip ?? true)
        XCTAssertEqual(pen.pressure, 0.75, "and the next touch presses as hard")
    }

    func testATapHoldsTheSwitchForTheTapLengthOnTheClock() {
        let (pen, clock, frames) = make()
        pen.move(to: CGPoint(x: 1000, y: 1000))
        let before = frames().count
        pen.tap(.lower)
        XCTAssertEqual(frames().count, before + 1)
        XCTAssertEqual(frames().last?.frame.switches, [.lower])
        clock.advance(by: VirtualPen.tapLength / 2)
        XCTAssertEqual(frames().count, before + 1, "still held")
        clock.advance(by: VirtualPen.tapLength)
        XCTAssertEqual(frames().count, before + 2)
        XCTAssertEqual(frames().last?.frame.switches, [])
        let pressed = frames()[before].time, released = frames()[before + 1].time
        XCTAssertGreaterThanOrEqual(released - pressed, VirtualPen.tapLength - 0.002)
        XCTAssertLessThan(released - pressed, TabletPen.tapLimit, "a tap, never a hold")
    }

    func testADoublePressIsTwoTapsInsideTheDoubleWindow() {
        let (pen, clock, frames) = make()
        pen.move(to: CGPoint(x: 1000, y: 1000))
        let before = frames().count
        pen.doublePress(.upper)
        clock.advance(by: 1)
        let held = frames().dropFirst(before).map(\.frame.switches)
        XCTAssertEqual(held, [[.upper], [], [.upper], []])
        let times = frames().dropFirst(before).map(\.time)
        XCTAssertLessThan(times[3] - times[0], TabletPen.doubleWindow + TabletPen.tapLimit)
        XCTAssertLessThanOrEqual(times[1] - times[0], TabletPen.tapLimit)
        XCTAssertLessThanOrEqual(times[3] - times[2], TabletPen.tapLimit)
        XCTAssertLessThanOrEqual(times[3] - times[1], TabletPen.doubleWindow)
    }

    /// A pen that is away is brought near by a tap: a switch cannot be
    /// pressed in the air if there is no air.
    func testATapBringsTheAwayPenNear() {
        let (pen, clock, frames) = make()
        pen.tap(.lower)
        XCTAssertTrue(pen.isNear)
        XCTAssertEqual(frames().first?.frame.hasPosition, false, "arriving first")
        clock.advance(by: 1)
        XCTAssertEqual(pen.switches, [])
    }

    /// A switch held while the pen is away is not reported — a real pen out
    /// of reach reports nothing — and the first report after says so.
    func testASwitchHeldWithThePenAwayIsHeldWhenItComesNear() {
        let (pen, _, frames) = make()
        pen.set(.lower, held: true)
        XCTAssertEqual(frames().count, 0)
        pen.move(to: CGPoint(x: 5, y: 5))
        XCTAssertEqual(frames().last?.frame.switches, [.lower])
    }

    /// A latch, a key and a tap are three ways to hold one switch, and it is
    /// held while any of them is.
    func testASwitchIsHeldWhileAnyOfThreeThingsHoldsIt() {
        let (pen, clock, _) = make()
        pen.move(to: .zero)
        pen.set(.upper, held: true, by: .latch)
        pen.set(.upper, held: true, by: .key)
        pen.set(.upper, held: false, by: .latch)
        XCTAssertEqual(pen.switches, [.upper], "the key still holds it")
        pen.set(.upper, held: false, by: .key)
        XCTAssertEqual(pen.switches, [])
        pen.tap(.upper)
        XCTAssertEqual(pen.switches, [.upper])
        clock.advance(by: 1)
        XCTAssertEqual(pen.switches, [])
    }

    func testLeavingGivesUpATapNotYetLetGo() {
        let (pen, clock, frames) = make()
        pen.move(to: .zero)
        pen.tap(.lower)
        pen.leave()
        let count = frames().count
        clock.advance(by: 1)
        XCTAssertEqual(frames().count, count, "the tap's letting go was sent after the pen had gone")
        XCTAssertFalse(pen.isNear)
        XCTAssertEqual(frames().last?.frame.report[1], 0, "out of range")
    }
}

/// The pad's model: points on the pad are counts on the tablet.
@MainActor
final class VirtualTabletTests: XCTestCase {
    private func make(turns: Int = 1) -> (VirtualTablet, VirtualClock, () -> [PenFrame]) {
        let clock = VirtualClock()
        let tablet = VirtualTablet(clock: clock)
        tablet.geometry = { (TabletExtent(width: 15200, height: 9500), turns) }
        var frames: [PenFrame] = []
        tablet.pen.onFrame = { frame, _ in frames.append(frame) }
        return (tablet, clock, { frames })
    }

    /// The pad is the page as it lies: its middle is the tablet's, and its
    /// top right — one quarter turn clockwise — is the tablet's top left.
    func testAPadPointIsTheCountsTheRealTabletWouldHaveReported() {
        let (tablet, _, frames) = make()
        tablet.padMove(to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(frames().last?.counts, CGPoint(x: 7600, y: 4750))
        tablet.padMove(to: CGPoint(x: 1, y: 0))
        XCTAssertEqual(frames().last?.counts, .zero)
        XCTAssertEqual(tablet.padPoint, CGPoint(x: 1, y: 0))
    }

    func testThePadFollowsHowTheTabletIsHeld() {
        let (tablet, _, frames) = make(turns: 0)
        tablet.padMove(to: CGPoint(x: 0.25, y: 0.5))
        XCTAssertEqual(frames().last?.counts, CGPoint(x: 3800, y: 4750))
    }

    func testPressingIsTheNibAndTheSliderIsHowHard() {
        let (tablet, _, frames) = make()
        tablet.pressure = 0.8
        tablet.padDown(at: CGPoint(x: 0.5, y: 0.5))
        XCTAssertTrue(tablet.isDown)
        XCTAssertEqual(frames().last?.pressure, 0.8)
        XCTAssertTrue(frames().last?.tip ?? false)
        tablet.padUp(at: CGPoint(x: 0.5, y: 0.6))
        XCTAssertFalse(tablet.isDown)
        XCTAssertTrue(tablet.isNear, "the pointer coming up is the nib lifting, not the pen leaving")
    }

    /// THE POINTER GOING TO A SWITCH'S BUTTON IS NOT THE PEN LEAVING: the pen
    /// stays near, where it was, until it is taken away.
    func testThePenStaysNearUntilItIsTakenAway() {
        let (tablet, _, frames) = make()
        tablet.padMove(to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertTrue(tablet.isNear)
        tablet.tap(.lower)
        XCTAssertEqual(frames().last?.switches, [.lower])
        tablet.penAway()
        XCTAssertFalse(tablet.isNear)
        XCTAssertNil(tablet.padPoint)
    }

    func testTheEraserToggleHoldsTheLowerSwitch() {
        let (tablet, _, frames) = make()
        tablet.padMove(to: CGPoint(x: 0.5, y: 0.5))
        tablet.eraser = true
        XCTAssertTrue(tablet.lowerHeld)
        XCTAssertEqual(frames().last?.switches, [.lower])
        tablet.padDown(at: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(frames().last?.switches, [.lower], "held as the nib goes down")
        tablet.eraser = false
        XCTAssertEqual(frames().last?.switches, [])
    }

    func testTheModifierKeysHoldTheSwitchesWhileTheyAreDown() {
        let (tablet, _, frames) = make()
        tablet.padMove(to: CGPoint(x: 0.5, y: 0.5))
        tablet.keysHeld(lower: true, upper: false)
        XCTAssertEqual(frames().last?.switches, [.lower])
        tablet.keysHeld(lower: true, upper: true)
        XCTAssertEqual(frames().last?.switches, [.lower, .upper])
        tablet.keysHeld(lower: false, upper: false)
        XCTAssertEqual(frames().last?.switches, [])
        XCTAssertFalse(tablet.lowerHeld, "a key is no latch")
    }

    func testPressureKeysAndTheWheel() {
        let (tablet, _, _) = make()
        tablet.setPressure(digit: 3)
        XCTAssertEqual(tablet.pressure, 0.3)
        tablet.setPressure(digit: 0)
        XCTAssertEqual(tablet.pressure, 1)
        tablet.nudgePressure(by: 0.5)
        XCTAssertEqual(tablet.pressure, 1)
        tablet.nudgePressure(by: -VirtualTablet.pressureStep)
        XCTAssertEqual(tablet.pressure, 0.95, accuracy: 1e-9)
        tablet.setPressure(digit: 11)
        XCTAssertEqual(tablet.pressure, 0.95, accuracy: 1e-9, "not a key")
    }
}

/// The controller: the virtual tablet as one of the tablets, the real one
/// winning, nothing remembered.
@MainActor
final class VirtualTabletControllerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var hid: StandInHID!
    private var input: TabletInput!
    private let oneByWacom = TabletDevice(model: "CTL-472", productID: 0x037A, serial: "2DA00L1059230")

    override func setUp() {
        super.setUp()
        suite = "WriteMindTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        hid = StandInHID()
        input = TabletInput()
        input.pageAppeared()
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func controller() -> TabletController {
        let tablets = TabletController(defaults: defaults, hid: hid, input: input, live: false)
        tablets.appBecameActive()
        return tablets
    }

    /// OFF BY DEFAULT: a controller nobody configured lists no virtual tablet,
    /// and its funnel hears nothing virtual.
    func testTheVirtualTabletIsOffByDefaultAndNotListed() {
        let tablets = controller()
        XCTAssertFalse(tablets.developer.virtualEnabled)
        XCTAssertEqual(tablets.tablets, [])
        XCTAssertFalse(input.policy.admits(.virtual))
        XCTAssertNotNil(tablets.developer.silence)
    }

    func testSwitchedOnItIsListedAsATabletAndTheSwitchIsRemembered() {
        let tablets = controller()
        tablets.developer.virtualEnabled = true
        XCTAssertEqual(tablets.tablets, [TabletDevice.virtual])
        XCTAssertTrue(input.policy.admits(.virtual))
        XCTAssertNil(tablets.developer.silence)
        XCTAssertTrue(defaults.bool(forKey: TabletDeveloper.virtualKey))
        XCTAssertTrue(controller().developer.virtualEnabled, "the developer's switch is remembered")
    }

    func testPickingItAsksNothingAndOpensNothing() {
        let tablets = controller()
        tablets.developer.virtualEnabled = true
        tablets.pick(TabletDevice.virtual)
        XCTAssertEqual(tablets.status, .virtual)
        XCTAssertEqual(tablets.selectedTablet, TabletDevice.virtual)
        XCTAssertEqual(hid.seizes, [], "nothing to seize")
        XCTAssertEqual(hid.accessReads, 0, "nothing to ask macOS")
        XCTAssertEqual(hid.asks, 0)
        XCTAssertEqual(input.extent, TabletExtent.known(productID: 0x037A), "the small One by Wacom's field")
        XCTAssertTrue(input.isRunning)
    }

    /// A LAUNCH NEVER COMES UP IN THE VIRTUAL TABLET: the pick is not
    /// remembered, and the real tablet picked before stays the pick.
    func testTheVirtualPickIsNeverRemembered() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.unplugged(registryID: 1)
        tablets.developer.virtualEnabled = true
        tablets.pick(TabletDevice.virtual)
        XCTAssertEqual(defaults.string(forKey: "lastTabletID"), oneByWacom.id)

        let next = controller()
        next.restoreRemembered()
        XCTAssertEqual(next.selectedTabletID, oneByWacom.id)
    }

    /// THE REAL DEVICE WINS: plugged in, it silences the stand-in, takes it
    /// off the list and — with the stand-in the input — takes the pen.
    func testARealTabletPluggedInTakesTheVirtualOnesPlace() {
        let tablets = controller()
        tablets.developer.virtualEnabled = true
        tablets.pick(TabletDevice.virtual)
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        XCTAssertEqual(tablets.tablets, [oneByWacom], "the stand-in is not offered beside a real tablet")
        XCTAssertFalse(input.policy.admits(.virtual))
        XCTAssertEqual(tablets.selectedTablet, oneByWacom)
        XCTAssertEqual(hid.seizes, [0x037A], "the real tablet is seized as it always is")
        XCTAssertNotNil(tablets.developer.silence)

        // And unplugged, the stand-in is there again, though not picked.
        tablets.unplugged(registryID: 1)
        XCTAssertEqual(tablets.tablets, [TabletDevice.virtual])
        XCTAssertTrue(input.policy.admits(.virtual))
    }

    /// THE REAL PICK BEHIND THE STAND-IN STAYS: the developer's switch going
    /// off with the virtual tablet the input turns the tablet off — and never
    /// touches the real tablet picked before it, which the next launch comes
    /// up on if it is plugged in.
    func testSwitchingTheStandInOffNeverForgetsTheRealPickBehindIt() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.unplugged(registryID: 1)
        tablets.developer.virtualEnabled = true
        tablets.pick(TabletDevice.virtual)
        XCTAssertEqual(tablets.selectedTabletID, TabletDevice.virtual.id)

        tablets.developer.virtualEnabled = false
        XCTAssertNil(tablets.selectedTabletID, "the stand-in was the input and is gone")
        XCTAssertEqual(defaults.string(forKey: "lastTabletID"), oneByWacom.id, "the real pick is not forgotten")
        XCTAssertEqual(defaults.string(forKey: "lastTabletName"), oneByWacom.name)

        let next = controller()
        next.restoreRemembered()
        XCTAssertEqual(next.selectedTabletID, oneByWacom.id, "a launch comes up on the real tablet")
    }

    /// "Turn Tablet Off" with the stand-in the input is the same: it was
    /// never remembered, so nothing is forgotten — but a REAL tablet turned
    /// off still is (nothing about that changes), and picking a camera says
    /// it for the real tablet remembered whatever is the input.
    func testTurningTheStandInOffForgetsNothingAndARealTabletStillIs() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.turnOff()
        XCTAssertNil(defaults.string(forKey: "lastTabletID"), "a real tablet turned off is forgotten")
        XCTAssertNil(defaults.string(forKey: "lastTabletName"))

        tablets.pick(oneByWacom)
        tablets.unplugged(registryID: 1)
        tablets.developer.virtualEnabled = true
        tablets.pick(TabletDevice.virtual)
        tablets.turnOff()
        XCTAssertFalse(tablets.isSelected)
        XCTAssertEqual(defaults.string(forKey: "lastTabletID"), oneByWacom.id, "the stand-in turned off forgets nothing")

        tablets.pick(TabletDevice.virtual)
        tablets.forgetRemembered()   // what picking a camera does first (`InputDevices.pick(cameraID:)`)
        tablets.turnOff()
        XCTAssertNil(defaults.string(forKey: "lastTabletID"), "a camera picked: no tablet comes back at launch")
        XCTAssertNil(defaults.string(forKey: "lastTabletName"))
    }

    func testSwitchingItOffWhileItIsTheInputTurnsTheTabletOff() {
        let tablets = controller()
        tablets.developer.virtualEnabled = true
        tablets.pick(TabletDevice.virtual)
        tablets.developer.virtualEnabled = false
        XCTAssertFalse(tablets.isSelected)
        XCTAssertEqual(tablets.status, .off)
        XCTAssertEqual(tablets.tablets, [])
    }

    /// Picking the real tablet after the virtual one lets go of the
    /// stand-in's pen: the funnel is not left believing a tablet is
    /// delivering, which would swallow the driver's events for ever.
    func testARealTabletTakingThePenLetsGoOfTheVirtualOne() {
        let tablets = controller()
        tablets.developer.virtualEnabled = true
        tablets.pick(TabletDevice.virtual)
        tablets.developer.virtual.padMove(to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertNotNil(input.rawSince, "the stand-in's reports are raw ones")
        XCTAssertNotNil(input.pen)

        tablets.plugged(oneByWacom, registryID: 2, settle: 0)
        XCTAssertEqual(tablets.selectedTablet, oneByWacom)
        XCTAssertNil(input.rawSince, "the driver's events are the pen's again until the tablet delivers")
        XCTAssertNil(input.pen, "the stand-in's pen is out of reach")
        XCTAssertFalse(tablets.developer.virtual.isNear)
    }

    func testTheStatusLineSaysItIsTheVirtualOneAndOffersItsWindow() throws {
        let line = try XCTUnwrap(TabletPane.line(for: .virtual, name: "Virtual Tablet (developer)"))
        XCTAssertTrue(line.opensVirtualPanel)
        XCTAssertFalse(line.opensSettings)
        XCTAssertTrue(line.text.contains("real tablet"), line.text)
        XCTAssertFalse(TabletPane.line(for: .standby, name: "x")?.opensVirtualPanel ?? true)
    }
}
