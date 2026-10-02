import AppKit
import IOKit.hid
import XCTest
@testable import WriteMind

// WRITEMIND TAKES THE TABLET ITSELF (Sean, 2026-10-02: "fix the wacom not
// being captured by writemind properly issues"). The three parts of
// `TabletCapture.swift`, each on its own: one raw report read into what the
// pen is doing, the rules for when the tablet is asked for, held and let go,
// and the real doors to macOS refusing to open from a test.

/// One raw pen report, read. The layout is the Bamboo-pen class's.
final class WacomPenPacketTests: XCTestCase {
    /// Hovering at (0x1234, 0x0BCD), 20 off the surface.
    private let hovering: [UInt8] = [2, 0xE0, 0x34, 0x12, 0xCD, 0x0B, 0, 0, 20, 0]

    func testTheFieldsAreLittleEndianAtTheirPlaces() throws {
        let packet = try XCTUnwrap(WacomPenPacket(hovering))
        XCTAssertEqual(packet.x, 0x1234)
        XCTAssertEqual(packet.y, 0x0BCD)
        XCTAssertEqual(packet.distance, 20)
        XCTAssertEqual(packet.pressure, 0)
        XCTAssertTrue(packet.inRange)
        XCTAssertTrue(packet.hasPosition)
        XCTAssertTrue(packet.isReady)
        XCTAssertFalse(packet.tip)
    }

    /// The far corner of the small One by Wacom fits: 15200 is 0x3B60.
    func testTheWholeTabletFitsTheField() throws {
        let corner = try XCTUnwrap(WacomPenPacket([2, 0xE0, 0x60, 0x3B, 0x1C, 0x25, 0, 0, 0, 0]))
        XCTAssertEqual(corner.x, 15200)
        XCTAssertEqual(corner.y, 9500)
    }

    func testEachBitIsItsOwnThing() throws {
        let bits: [(UInt8, KeyPath<WacomPenPacket, Bool>)] = [
            (0x80, \.inRange), (0x40, \.hasPosition), (0x20, \.isReady), (0x08, \.eraser),
            (0x04, \.upperSwitch), (0x02, \.lowerSwitch), (0x01, \.tip),
        ]
        for (bit, field) in bits {
            let packet = try XCTUnwrap(WacomPenPacket([2, bit, 0, 0, 0, 0, 0, 0, 0, 0]))
            for (other, otherField) in bits {
                XCTAssertEqual(packet[keyPath: otherField], other == bit, "bit \(String(bit, radix: 16))")
            }
            XCTAssertEqual(packet[keyPath: field], true)
        }
    }

    /// 0…2047 is 0…1, and nothing the tablet could send is past 1.
    func testPressureIsScaledToOne() throws {
        let pressed = { (low: UInt8, high: UInt8) in
            try XCTUnwrap(WacomPenPacket([2, 0xE1, 0, 0, 0, 0, low, high, 0, 0])).pressure
        }
        XCTAssertEqual(try pressed(0, 0), 0)
        XCTAssertEqual(try pressed(0xFF, 0x07), 1, "2047 is full pressure")
        XCTAssertEqual(try pressed(0x00, 0x04), 1024.0 / 2047.0, accuracy: 1e-12)
        XCTAssertEqual(try pressed(0xFF, 0xFF), 1, "past the top is the top")
    }

    /// NOTHING IS GUESSED: a short report, a long one — the tablet's second
    /// interface sends 64 bytes under the same id — another id, and none at
    /// all are not pen reports.
    func testWhatIsNotExactlyAPenReportIsRejected() {
        XCTAssertNil(WacomPenPacket([]))
        XCTAssertNil(WacomPenPacket(Array(hovering.prefix(9))), "short")
        XCTAssertNil(WacomPenPacket(hovering + [0]), "long")
        XCTAssertNil(WacomPenPacket([2] + [UInt8](repeating: 0, count: 63)), "the vendor interface's")
        XCTAssertNil(WacomPenPacket([1] + hovering.dropFirst()), "the mouse's report, before the mode is set")
        XCTAssertNil(WacomPenPacket([0xC0] + hovering.dropFirst()))
    }

    // MARK: - Into the funnel's words

    private func point(_ reading: TabletReading)
        -> (counts: CGPoint, tip: Bool, switches: Set<PenSwitch>?, pressure: Double, buttons: UInt)? {
        guard case .point(let counts, let tip, let switches, let pressure, let buttons) = reading.kind else { return nil }
        return (counts, tip, switches, pressure, buttons)
    }

    func testAHoverIsAPointWithNothingPressed() throws {
        let reading = try XCTUnwrap(WacomPenPacket(hovering)).reading(at: 3.5)
        let hover = try XCTUnwrap(point(reading))
        XCTAssertEqual(hover.counts, CGPoint(x: 0x1234, y: 0x0BCD), "raw landscape counts, as an event's are")
        XCTAssertFalse(hover.tip)
        XCTAssertEqual(hover.switches, [], "ready, and neither switch pressed")
        XCTAssertEqual(hover.pressure, 0)
        XCTAssertEqual(reading.timestamp, 3.5)
        XCTAssertTrue(reading.native)
    }

    func testTheTipDownCarriesItsPressure() throws {
        let nib = try XCTUnwrap(point(try XCTUnwrap(WacomPenPacket([2, 0xE1, 0, 1, 0, 1, 0x00, 0x04, 0, 0])).reading(at: 1)))
        XCTAssertTrue(nib.tip)
        XCTAssertEqual(nib.pressure, 1024.0 / 2047.0, accuracy: 1e-12)
        XCTAssertEqual(nib.buttons, 0x1)
    }

    /// EACH SWITCH IS ITS OWN BIT, and the reading says which (Sean,
    /// 2026-10-02: "make the wacom buttons undo and redo last drawing" — a
    /// click of the lower one undoes, of the upper one redoes): 0x02 the
    /// lower, nearer the nib, 0x04 the upper. The upper one used to be read
    /// as nothing at all.
    func testEachSwitchIsItsOwnBit() throws {
        let lower = try XCTUnwrap(point(try XCTUnwrap(WacomPenPacket([2, 0xE2, 0, 1, 0, 1, 0, 0, 0, 0])).reading(at: 1)))
        XCTAssertEqual(lower.switches, [.lower])
        XCTAssertFalse(lower.tip)
        XCTAssertEqual(lower.pressure, 0)
        let upper = try XCTUnwrap(point(try XCTUnwrap(WacomPenPacket([2, 0xE4, 0, 1, 0, 1, 0, 0, 0, 0])).reading(at: 1)))
        XCTAssertEqual(upper.switches, [.upper], "the upper switch was read as nothing")
        XCTAssertEqual(upper.buttons, 0x4, "in the log, all the same")
        let both = try XCTUnwrap(point(try XCTUnwrap(WacomPenPacket([2, 0xE6, 0, 1, 0, 1, 0, 0, 0, 0])).reading(at: 1)))
        XCTAssertEqual(both.switches, [.lower, .upper])
    }

    /// The tip, the switches and the pressure count only once the tablet
    /// says they are ready — and until it does, the reading CANNOT SAY what
    /// the switches are doing: not "let go", which at the edge of the
    /// tablet's reach would make a click of a switch that is still held.
    func testNothingIsPressedUntilTheTabletIsReady() throws {
        let early = try XCTUnwrap(point(try XCTUnwrap(WacomPenPacket([2, 0xC3, 0, 1, 0, 1, 0xFF, 0x07, 0, 0])).reading(at: 1)))
        XCTAssertFalse(early.tip)
        XCTAssertNil(early.switches, "a report that is not ready said the switches were let go")
        XCTAssertEqual(early.pressure, 0)
        XCTAssertEqual(early.buttons, 0)
    }

    /// In range with no position yet is the pen coming near — never a point
    /// at (0, 0). Out of range is the pen gone.
    func testRangeWithoutAPositionIsThePenComingNear() throws {
        XCTAssertEqual(try XCTUnwrap(WacomPenPacket([2, 0x80, 0, 0, 0, 0, 0, 0, 0, 0])).reading(at: 1).kind,
                       .proximity(entering: true))
        XCTAssertEqual(try XCTUnwrap(WacomPenPacket([2, 0x00, 0, 0, 0, 0, 0, 0, 0, 0])).reading(at: 1).kind,
                       .proximity(entering: false))
        XCTAssertEqual(try XCTUnwrap(WacomPenPacket([2, 0x61, 9, 9, 9, 9, 9, 9, 0, 0])).reading(at: 1).kind,
                       .proximity(entering: false), "whatever else an out-of-range report carries")
    }

    func testAReportIsLoggedInHex() {
        XCTAssertEqual(WacomPenPacket.hex([2, 0xE1, 0x60, 0x3B]), "02 e1 60 3b")
    }
}

/// WHEN THE TABLET IS ASKED FOR, HELD AND LET GO — the rules, walked.
final class TabletCaptureTests: XCTestCase {
    private typealias Conditions = TabletCapture.Conditions
    private let ready = TabletCapture.Conditions(productID: 0x037A, targetShowing: true, active: true)

    func testAllThreeAndAllowedTakesTheTablet() {
        var capture = TabletCapture()
        XCTAssertEqual(capture.changed(ready, access: .granted), [.seize(productID: 0x037A, attempt: 1)])
        XCTAssertEqual(capture.holding, .seizing)
        capture.landed(attempt: 1, refusal: nil)
        XCTAssertTrue(capture.isCaptured)
        XCTAssertNil(capture.refusal)
        XCTAssertEqual(capture.changed(ready, access: .granted), [], "held: nothing more to do")
    }

    /// No tablet, nothing to write on, or not in front: any one of them
    /// missing and nothing is opened.
    func testAnyOneConditionMissingOpensNothing() {
        let short = [
            Conditions(productID: nil, targetShowing: true, active: true),
            Conditions(productID: 0x037A, targetShowing: false, active: true),
            Conditions(productID: 0x037A, targetShowing: true, active: false),
        ]
        for conditions in short {
            var capture = TabletCapture()
            XCTAssertEqual(capture.changed(conditions, access: .granted), [], "\(conditions)")
            XCTAssertEqual(capture.holding, .nothing)
            XCTAssertNil(capture.refusal, "nothing is wrong: there is nothing to hold it for")
        }
    }

    /// And any one of them GOING lets go of what is held.
    func testAnyOneConditionGoingLetsGo() {
        let gone = [
            Conditions(productID: nil, targetShowing: true, active: true),
            Conditions(productID: 0x037A, targetShowing: false, active: true),
            Conditions(productID: 0x037A, targetShowing: true, active: false),
        ]
        for conditions in gone {
            var capture = TabletCapture()
            _ = capture.changed(ready, access: .granted)
            capture.landed(attempt: 1, refusal: nil)
            XCTAssertEqual(capture.changed(conditions, access: .granted), [.release], "\(conditions)")
            XCTAssertFalse(capture.isCaptured)
            XCTAssertEqual(capture.changed(conditions, access: .granted), [], "let go once")
        }
    }

    /// A FIRST LAUNCH NEVER ASKS, AND ONLY A PICK ASKS.
    func testOnlyAPickAsks() {
        var capture = TabletCapture()
        XCTAssertEqual(capture.changed(ready, access: .undecided), [], "nobody picked: nobody is asked")
        XCTAssertEqual(capture.refusal, .undecided)
        XCTAssertEqual(capture.changed(ready, access: .undecided, picked: true), [.ask])
        XCTAssertEqual(capture.holding, .asking)
        XCTAssertEqual(capture.changed(ready, access: .undecided, picked: true), [], "one question at a time")
        XCTAssertEqual(capture.changed(ready, access: .undecided), [], "and it is still up")
        XCTAssertEqual(capture.answered(.granted), [.seize(productID: 0x037A, attempt: 1)])
        XCTAssertNil(capture.refusal)
    }

    /// The question is the pick's whether or not the page is up; what it
    /// allows waits for the page.
    func testAPickAsksWithNothingToWriteOnAndOpensNothing() {
        var capture = TabletCapture()
        let away = Conditions(productID: 0x037A, targetShowing: false, active: true)
        XCTAssertEqual(capture.changed(away, access: .undecided, picked: true), [.ask])
        XCTAssertEqual(capture.answered(.granted), [])
        XCTAssertEqual(capture.holding, .nothing)
        XCTAssertEqual(capture.changed(ready, access: .granted), [.seize(productID: 0x037A, attempt: 1)])
    }

    /// With no tablet plugged in there is nothing to ask for.
    func testAPickOfATabletThatIsNotThereAsksNothing() {
        var capture = TabletCapture()
        XCTAssertEqual(capture.changed(Conditions(productID: nil, targetShowing: true, active: true),
                                       access: .undecided, picked: true), [])
    }

    func testAnAnswerOfNoIsARefusal() {
        var capture = TabletCapture()
        _ = capture.changed(ready, access: .undecided, picked: true)
        XCTAssertEqual(capture.answered(.denied), [])
        XCTAssertEqual(capture.refusal, .denied)
        var unanswered = TabletCapture()
        _ = unanswered.changed(ready, access: .undecided, picked: true)
        XCTAssertEqual(unanswered.answered(.undecided), [])
        XCTAssertEqual(unanswered.refusal, .undecided, "put away unanswered: the next pick asks again")
        XCTAssertEqual(unanswered.changed(ready, access: .undecided, picked: true), [.ask])
    }

    /// NOTHING IS OPENED UNALLOWED — IOKit's own open would put the
    /// question up by itself.
    func testDeniedOpensNothingEvenOnAPick() {
        var capture = TabletCapture()
        XCTAssertEqual(capture.changed(ready, access: .denied, picked: true), [])
        XCTAssertEqual(capture.refusal, .denied)
        XCTAssertEqual(capture.holding, .nothing)
    }

    /// Switched off in System Settings while the tablet is held: let go.
    func testPermissionTakenAwayLetsGo() {
        var capture = TabletCapture()
        _ = capture.changed(ready, access: .granted)
        capture.landed(attempt: 1, refusal: nil)
        XCTAssertEqual(capture.changed(ready, access: .denied), [.release])
        XCTAssertEqual(capture.refusal, .denied)
    }

    /// And given, it is taken at the next change — coming back from System
    /// Settings is one.
    func testPermissionGivenIsTakenUpAtTheNextChange() {
        var capture = TabletCapture()
        _ = capture.changed(ready, access: .denied)
        XCTAssertEqual(capture.changed(ready, access: .granted), [.seize(productID: 0x037A, attempt: 1)])
        XCTAssertNil(capture.refusal, "the old no is not left standing while the open is on its way")
    }

    /// A refused open is said, falls back, and is tried again only when
    /// something changes — never in a loop of its own.
    func testARefusedOpenIsARefusalAndIsRetriedAtTheNextChange() {
        var capture = TabletCapture()
        _ = capture.changed(ready, access: .granted)
        capture.landed(attempt: 1, refusal: .driverHolds(TabletCapture.exclusiveAccess))
        XCTAssertFalse(capture.isCaptured)
        XCTAssertEqual(capture.holding, .nothing)
        XCTAssertEqual(capture.refusal, .driverHolds(TabletCapture.exclusiveAccess))
        XCTAssertEqual(capture.changed(ready, access: .granted), [.seize(productID: 0x037A, attempt: 2)])
        XCTAssertEqual(capture.refusal, .driverHolds(TabletCapture.exclusiveAccess),
                       "the pane keeps its reason until the tablet is taken")
        capture.landed(attempt: 2, refusal: nil)
        XCTAssertNil(capture.refusal)
        XCTAssertTrue(capture.isCaptured)
    }

    /// An open that lands after the tablet was let go, or after a newer
    /// one was started, is nobody's.
    func testAnOpenThatLandsLateIsNobodys() {
        var capture = TabletCapture()
        _ = capture.changed(ready, access: .granted)
        let away = Conditions(productID: 0x037A, targetShowing: true, active: false)
        XCTAssertEqual(capture.changed(away, access: .granted), [.release], "the close follows the open")
        capture.landed(attempt: 1, refusal: nil)
        XCTAssertFalse(capture.isCaptured, "held behind another app")

        XCTAssertEqual(capture.changed(ready, access: .granted), [.seize(productID: 0x037A, attempt: 2)])
        capture.landed(attempt: 1, refusal: .failed(-1))
        XCTAssertEqual(capture.holding, .seizing, "the old open's answer was taken for the new one's")
        XCTAssertNil(capture.refusal)
        capture.landed(attempt: 2, refusal: nil)
        XCTAssertTrue(capture.isCaptured)
    }

    /// THE HOLD FOLLOWS THE PICK. Two tablets plugged in and the other one
    /// picked while the first is held: the first is let go and the other
    /// taken. Left held, the first went on writing as "pen captured" and
    /// the one ticked in the menu was a dead pen on the page.
    func testAnotherTabletPickedMovesTheHold() {
        let other = Conditions(productID: 0x037B, targetShowing: true, active: true)
        var capture = captured()
        XCTAssertEqual(capture.changed(other, access: .granted, picked: true),
                       [.release, .seize(productID: 0x037B, attempt: 2)])
        XCTAssertEqual(capture.holding, .seizing)
        capture.landed(attempt: 2, refusal: nil)
        XCTAssertTrue(capture.isCaptured)
        XCTAssertEqual(capture.changed(other, access: .granted), [], "held: nothing more to do")

        // And with the first one's open still on its way: its answer is
        // not the second one's.
        var opening = TabletCapture()
        _ = opening.changed(ready, access: .granted)
        XCTAssertEqual(opening.changed(other, access: .granted, picked: true),
                       [.release, .seize(productID: 0x037B, attempt: 2)])
        opening.landed(attempt: 1, refusal: nil)
        XCTAssertEqual(opening.holding, .seizing, "the first tablet's open was taken for the second's")
    }

    // MARK: - Reports nobody can read

    private func captured() -> TabletCapture {
        var capture = TabletCapture()
        _ = capture.changed(ready, access: .granted)
        capture.landed(attempt: 1, refusal: nil)
        return capture
    }

    /// A SEIZED TABLET WHOSE REPORTS CANNOT BE READ IS A DEAD PEN: the
    /// driver hears nothing and neither does the page. A burst of reports
    /// at the pen's rate with not one of them the pen's, and the tablet is
    /// given back — the page writes again from the driver's events.
    func testABurstOfReportsNobodyCanReadGivesTheTabletBack() {
        var capture = captured()
        for index in 0..<(TabletCapture.unreadableBurst - 1) {
            XCTAssertEqual(capture.reported(known: false, at: 5 + Double(index) * 0.008), [], "report \(index)")
        }
        XCTAssertTrue(capture.isCaptured)
        XCTAssertEqual(capture.reported(known: false, at: 5.3), [.release])
        XCTAssertFalse(capture.isCaptured)
        XCTAssertEqual(capture.refusal, .unreadable)
        XCTAssertEqual(capture.reported(known: false, at: 5.31), [], "given back once")
    }

    /// Not taken again for the same dead pen at every coming-to-the-front —
    /// only by a pick, or the tablet plugged in afresh.
    func testAnUnreadableTabletIsTriedAgainOnlyByAPick() {
        var capture = captured()
        for index in 0..<TabletCapture.unreadableBurst { _ = capture.reported(known: false, at: 5 + Double(index) * 0.008) }
        XCTAssertEqual(capture.changed(ready, access: .granted), [], "taken again with nothing changed")
        XCTAssertEqual(capture.refusal, .unreadable)
        XCTAssertEqual(capture.changed(ready, access: .granted, picked: true),
                       [.seize(productID: 0x037A, attempt: 2)])
        var replugged = captured()
        for index in 0..<TabletCapture.unreadableBurst { _ = replugged.reported(known: false, at: 5 + Double(index) * 0.008) }
        _ = replugged.changed(Conditions(), access: .undecided)
        XCTAssertEqual(replugged.changed(ready, access: .granted), [.seize(productID: 0x037A, attempt: 2)])
    }

    /// A report now and then that is not the pen's — a status report, the
    /// other interface — is not a pen that cannot be read: only a burst
    /// inside a second is.
    func testTheOddUnknownReportIsNotADeadPen() {
        var capture = captured()
        for index in 0..<(TabletCapture.unreadableBurst * 3) {
            XCTAssertEqual(capture.reported(known: false, at: 5 + Double(index) * 0.5), [])
        }
        XCTAssertTrue(capture.isCaptured)
    }

    /// Once the pen has been read in this capture, nothing unknown gives
    /// the tablet back.
    func testOnceThePenHasBeenReadUnknownReportsNeverLetGo() {
        var capture = captured()
        XCTAssertEqual(capture.reported(known: true, at: 5), [])
        for index in 0..<(TabletCapture.unreadableBurst * 2) {
            XCTAssertEqual(capture.reported(known: false, at: 5.1 + Double(index) * 0.008), [])
        }
        XCTAssertTrue(capture.isCaptured)
    }

    /// Unplugged, or turned off: nothing held, nothing wrong.
    func testNoTabletForgetsTheRefusal() {
        var capture = TabletCapture()
        _ = capture.changed(ready, access: .denied)
        _ = capture.changed(Conditions(), access: .undecided)
        XCTAssertNil(capture.refusal)
    }

    // MARK: - What an open came back with

    private let pointer = { (status: IOReturn) in TabletCapture.Opened(usagePage: 1, usage: 2, status: status) }
    private let vendor = { (status: IOReturn) in TabletCapture.Opened(usagePage: 0xFF00, usage: 0x80, status: status) }

    func testThePointersDeviceOpenedIsTheTabletTaken() {
        XCTAssertNil(TabletCapture.verdict(of: [pointer(kIOReturnSuccess), vendor(kIOReturnSuccess)]))
        XCTAssertNil(TabletCapture.verdict(of: [pointer(kIOReturnSuccess), vendor(TabletCapture.exclusiveAccess)]),
                     "the interface nobody reads is the log's business")
    }

    /// THE DEVICE THAT MOVES THE POINTER is the one that has to be held.
    func testThePointersDeviceRefusedIsARefusalWhateverElseOpened() {
        XCTAssertEqual(TabletCapture.verdict(of: [pointer(TabletCapture.exclusiveAccess), vendor(kIOReturnSuccess)]),
                       .driverHolds(TabletCapture.exclusiveAccess))
        XCTAssertEqual(TabletCapture.verdict(of: [pointer(TabletCapture.notPermitted), vendor(kIOReturnSuccess)]),
                       .relaunch, "allowed, and macOS still said no: quit and reopen")
        XCTAssertEqual(TabletCapture.verdict(of: [pointer(-7)]), .failed(-7))
    }

    func testNothingToOpenIsNoDevice() {
        XCTAssertEqual(TabletCapture.verdict(of: []), .noDevice)
    }

    /// A tablet with no pointer device at all is held only if all it has
    /// opened.
    func testWithNoPointerDeviceEverythingMustOpen() {
        XCTAssertNil(TabletCapture.verdict(of: [vendor(kIOReturnSuccess)]))
        XCTAssertEqual(TabletCapture.verdict(of: [vendor(kIOReturnSuccess), vendor(-7)]), .failed(-7))
    }

    /// The numbers the log and the pane say are IOKit's own.
    func testTheCodesAreIOKits() {
        XCTAssertEqual(TabletCapture.notPermitted, kIOReturnNotPermitted)
        XCTAssertEqual(TabletCapture.exclusiveAccess, kIOReturnExclusiveAccess)
        XCTAssertEqual(TabletCapture.hex(TabletCapture.exclusiveAccess), "0xe00002c5")
        XCTAssertEqual(TabletCapture.Refusal.relaunch.code, kIOReturnNotPermitted)
        XCTAssertNil(TabletCapture.Refusal.denied.code)
    }
}

/// THE REAL DOORS REFUSE FROM A TEST. The spies stand where IOKit is first
/// touched — the permission read, the permission ask, the search for the
/// tablet's devices — so if a guard ever went, this fails on a spy and not
/// with a prompt on Sean's screen or his tablet taken from under his hand.
final class LiveTabletHIDTests: XCTestCase {
    func testTheTestHostAsksNothingAndOpensNothing() {
        XCTAssertTrue(TestHost.isActive)
        let hid = LiveTabletHID()
        var checked = 0, asked = 0, searched = 0
        hid.check = { checked += 1; return kIOHIDAccessTypeGranted }
        hid.ask = { asked += 1; return true }
        hid.find = { _, _ in searched += 1; return [] }
        hid.log = { _ in }

        XCTAssertEqual(hid.access(), .undecided)
        let answered = expectation(description: "the ask comes back")
        hid.requestAccess { access in
            XCTAssertEqual(access, .undecided)
            answered.fulfill()
        }
        let landed = expectation(description: "the open comes back")
        hid.seize(vendorID: 0x056A, productID: 0x037A, report: { _, _ in XCTFail("a report in the test host") },
                  done: { refusal in
                      XCTAssertEqual(refusal, .underTest)
                      landed.fulfill()
                  })
        hid.release(waiting: false)
        hid.release(waiting: true)
        wait(for: [answered, landed], timeout: 5)
        // Whatever a door without its guard would have queued has run.
        let settled = expectation(description: "the queues have drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { DispatchQueue.main.async { settled.fulfill() } }
        wait(for: [settled], timeout: 5)
        XCTAssertEqual(checked, 0, "the test host read Input Monitoring")
        XCTAssertEqual(asked, 0, "the test host asked macOS for Input Monitoring")
        XCTAssertEqual(searched, 0, "the test host went looking for the tablet's HID devices")
    }
}
