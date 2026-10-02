import AppKit
import Combine
import XCTest
@testable import WriteMind

/// macOS as the controller sees it: Input Monitoring as it stands, and the
/// tablet's HID device — every call written down, answers that can be held
/// back to arrive later, and reports a test sends as the tablet would.
/// Opens nothing.
final class StandInHID: TabletHID {
    var granted = TabletCapture.Access.granted
    /// What the prompt comes back with.
    var answer = TabletCapture.Access.granted
    /// What an open comes back with: nil is the tablet taken.
    var refusal: TabletCapture.Refusal?
    private(set) var accessReads = 0
    private(set) var asks = 0
    private(set) var seizes: [Int] = []
    private(set) var releases = 0
    private(set) var releasesWaitedFor = 0
    /// Open at the moment, as the device would be.
    private(set) var isOpen = false
    var hold = false
    var held: [() -> Void] = []
    /// Every capture's own way in for reports, oldest first.
    private(set) var reports: [([UInt8], TimeInterval) -> Void] = []

    func access() -> TabletCapture.Access {
        accessReads += 1
        return granted
    }

    func requestAccess(done: @escaping (TabletCapture.Access) -> Void) {
        asks += 1
        let answer = self.answer
        let land = { [self] in
            // The prompt's answer is what Input Monitoring reads from then on.
            granted = answer
            done(answer)
        }
        if hold { held.append(land) } else { land() }
    }

    func seize(vendorID: Int, productID: Int,
               report: @escaping ([UInt8], TimeInterval) -> Void,
               done: @escaping (TabletCapture.Refusal?) -> Void) {
        XCTAssertEqual(vendorID, 0x056A)
        seizes.append(productID)
        reports.append(report)
        let refusal = self.refusal
        let land = { [self] in
            isOpen = refusal == nil
            done(refusal)
        }
        if hold { held.append(land) } else { land() }
    }

    func release(waiting: Bool) {
        releases += 1
        if waiting { releasesWaitedFor += 1 }
        isOpen = false
    }
}

/// A pen report as the One by Wacom sends it.
func penReport(x: Int = 7600, y: Int = 4750, flags: UInt8 = 0xE0, pressure: Int = 0) -> [UInt8] {
    [2, flags, UInt8(x & 0xFF), UInt8(x >> 8), UInt8(y & 0xFF), UInt8(y >> 8),
     UInt8(pressure & 0xFF), UInt8(pressure >> 8), 20, 0]
}

/// The tablet chosen "as if it were an input display" (Sean, 2026-10-02):
/// found, picked, remembered — and TAKEN: its HID device held while there is
/// something to write on and WriteMind is in front, let go otherwise
/// ("fix the wacom not being captured by writemind properly issues").
/// Against a stand-in for macOS, because the test host never opens a
/// device.
@MainActor
final class TabletControllerTests: XCTestCase {
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
        // The page is on screen, as it is whenever a tablet is the input
        // and its pane is up. The tests that put it away say so.
        input.pageAppeared()
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// In front, unless the test says otherwise — as WriteMind is whenever
    /// Sean is picking from its menu.
    private func controller(active: Bool = true) -> TabletController {
        let tablets = TabletController(defaults: defaults, hid: hid, input: input, live: false)
        if active { tablets.appBecameActive() }
        return tablets
    }

    private func picked() -> TabletController {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        return tablets
    }

    /// The tablet as the stand-in would send it: one report into the
    /// capture numbered `capture` (the first is 0). A capture that was
    /// never made is a failure, not a trap.
    private func send(_ report: [UInt8], at time: TimeInterval, capture: Int = 0,
                      file: StaticString = #filePath, line: UInt = #line) {
        guard hid.reports.indices.contains(capture) else {
            return XCTFail("the tablet was never taken (capture \(capture))", file: file, line: line)
        }
        hid.reports[capture](report, time)
    }

    // MARK: - Names

    func testATabletIsNamedForTheBoxNotTheDescriptor() {
        XCTAssertEqual(oneByWacom.name, "One by Wacom (CTL-472)")
        XCTAssertEqual(TabletDevice(model: nil, productID: 0x037A, serial: nil).name, "One by Wacom (CTL-472)",
                       "no product string: the product id still knows it")
        XCTAssertEqual(TabletDevice(model: "CTL-672", productID: 0x037B, serial: nil).name, "One by Wacom (CTL-672)")
        XCTAssertEqual(TabletDevice(model: "CTL-6100", productID: 0x0376, serial: nil).name, "Wacom CTL-6100")
        XCTAssertEqual(TabletDevice(model: "Wacom Intuos Pro M", productID: 0x0357, serial: nil).name,
                       "Wacom Intuos Pro M")
        XCTAssertEqual(TabletDevice(model: "", productID: 0x0001, serial: nil).name, "Wacom Tablet")
    }

    /// The pick is remembered by the tablet, not by the port it is in.
    func testATabletKeepsItsIdAcrossPlugs() {
        XCTAssertEqual(oneByWacom.id, "wacom-037a-2DA00L1059230")
        XCTAssertEqual(oneByWacom, TabletDevice(model: "CTL-472 ", productID: 0x037A, serial: "2DA00L1059230"))
        XCTAssertEqual(TabletDevice(model: "CTL-472", productID: 0x037A, serial: "  ").id, "wacom-037a-")
    }

    // MARK: - A first launch never asks

    func testTheTestHostsOwnControllerHasNoTabletAndAsksNothing() {
        XCTAssertTrue(TestHost.isActive)
        XCTAssertTrue(TabletController.shared.tablets.isEmpty, "the test host found a tablet over IOKit")
        XCTAssertFalse(TabletController.shared.isSelected, "the test host restored a remembered pick")
        XCTAssertEqual(TabletController.shared.status, .off)
        XCTAssertFalse(TabletController.shared.capture.isCaptured)
    }

    /// Nothing picked: Input Monitoring is not so much as read.
    func testAFirstLaunchNeverAsks() {
        hid.granted = .undecided
        let tablets = controller()
        tablets.restoreRemembered()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        XCTAssertEqual(tablets.tablets, [oneByWacom], "listed")
        XCTAssertFalse(tablets.isSelected, "listed is not picked")
        XCTAssertEqual(hid.accessReads, 0, "Input Monitoring was looked up with nothing picked")
        XCTAssertEqual(hid.asks, 0)
        XCTAssertEqual(hid.seizes, [])
        XCTAssertEqual(tablets.status, .off)
    }

    /// PICKING IS THE ONE THING THAT MAY ASK — and, allowed, it takes the
    /// tablet.
    func testPickingTheTabletAsksTakesThePenAndIsRemembered() {
        hid.granted = .undecided
        let tablets = picked()
        XCTAssertEqual(hid.asks, 1, "the pick put macOS's question")
        XCTAssertEqual(hid.seizes, [0x037A], "allowed: the tablet's HID device is opened, seized")
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
        XCTAssertEqual(tablets.selectedTabletID, oneByWacom.id)
        XCTAssertEqual(defaults.string(forKey: "lastTabletID"), oneByWacom.id)
        XCTAssertTrue(input.isRunning, "the funnel is open")
    }

    func testAlreadyAllowedAPickAsksNothingAndTakesThePen() {
        let tablets = picked()
        XCTAssertEqual(hid.asks, 0)
        XCTAssertEqual(hid.seizes, [0x037A])
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
    }

    /// THE EXTENT IS THE RAW SENSOR'S, from the table: 15200 × 9500 for the
    /// small One by Wacom, landscape as it shipped. The driver on Sean's Mac
    /// is set to portrait and says 9499 × 15199 — and nothing here asks it.
    func testTheExtentIsTheRawSensorsFromTheTable() {
        _ = picked()
        XCTAssertEqual(input.extent, TabletExtent(width: 15200, height: 9500, countsPerMillimetre: 100))
    }

    func testARememberedTabletComesBackWithoutAsking() {
        hid.granted = .undecided
        defaults.set(oneByWacom.id, forKey: "lastTabletID")
        defaults.set(oneByWacom.name, forKey: "lastTabletName")
        let tablets = controller()
        tablets.restoreRemembered()
        XCTAssertTrue(tablets.isSelected, "the pane is the tablet's from the start")
        XCTAssertEqual(tablets.status, .unplugged, "until it is found")
        XCTAssertEqual(tablets.selectedName, "One by Wacom (CTL-472)")
        XCTAssertEqual(hid.accessReads, 0, "not plugged in: nothing to look up")
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        XCTAssertEqual(hid.asks, 0, "a launch never asks")
        XCTAssertEqual(hid.seizes, [], "and never opens what it has not been allowed")
        XCTAssertEqual(tablets.status, .fallback(.undecided))
        XCTAssertTrue(input.isRunning, "the page still takes the pen from what the driver posts")
    }

    func testARememberedTabletAlreadyAllowedIsTakenAtLaunch() {
        defaults.set(oneByWacom.id, forKey: "lastTabletID")
        let tablets = controller(active: false)
        tablets.restoreRemembered()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        XCTAssertEqual(hid.seizes, [], "not yet in front")
        XCTAssertEqual(tablets.status, .standby)
        tablets.appBecameActive()
        XCTAssertEqual(hid.seizes, [0x037A])
        XCTAssertEqual(hid.asks, 0)
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
    }

    /// Nobody answered yet: the launch stops at the question, coming to the
    /// front does not put it, the next PICK does.
    func testAnUnansweredQuestionWaitsForThePick() {
        hid.granted = .undecided
        defaults.set(oneByWacom.id, forKey: "lastTabletID")
        let tablets = controller()
        tablets.restoreRemembered()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        XCTAssertEqual(tablets.status, .fallback(.undecided))
        tablets.appResignedActive()
        tablets.appBecameActive()
        XCTAssertEqual(hid.asks, 0, "coming to the front does not ask")
        tablets.pick(oneByWacom)
        XCTAssertEqual(hid.asks, 1)
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
    }

    func testARefusalIsSaidAndNothingIsOpened() {
        hid.granted = .denied
        let tablets = picked()
        XCTAssertEqual(tablets.status, .fallback(.denied))
        XCTAssertEqual(hid.asks, 0, "macOS has its answer; asking again is no prompt")
        XCTAssertEqual(hid.seizes, [], "IOKit's own open would ask — nothing is opened unallowed")
        XCTAssertTrue(tablets.isSelected, "the page still works from what reaches WriteMind")
        XCTAssertTrue(input.isRunning)
    }

    func testAPickRefusedAtThePromptIsSaid() {
        hid.granted = .undecided
        hid.answer = .denied
        let tablets = picked()
        XCTAssertEqual(hid.asks, 1)
        XCTAssertEqual(hid.seizes, [])
        XCTAssertEqual(tablets.status, .fallback(.denied))
    }

    /// Allowed in System Settings while WriteMind was behind it: seen the
    /// moment WriteMind comes back to the front.
    func testAPermissionGivenInSettingsIsSeenOnComingBack() {
        hid.granted = .denied
        let tablets = picked()
        tablets.appResignedActive()
        hid.granted = .granted
        tablets.appBecameActive()
        XCTAssertEqual(hid.seizes, [0x037A])
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
    }

    /// The log says what Input Monitoring reads when that CHANGES — it is
    /// looked at on every coming-to-the-front, and written once.
    func testTheLogSaysWhatInputMonitoringReadsWhenItChanges() {
        hid.granted = .denied
        let tablets = controller()
        var lines: [String] = []
        tablets.log = { lines.append($0) }
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.appResignedActive()
        tablets.appBecameActive()
        XCTAssertEqual(lines.filter { $0.contains("Input Monitoring reads") },
                       ["tablet: Input Monitoring reads denied"])
        hid.granted = .granted
        tablets.appResignedActive()
        tablets.appBecameActive()
        XCTAssertEqual(lines.filter { $0.contains("Input Monitoring reads") },
                       ["tablet: Input Monitoring reads denied", "tablet: Input Monitoring reads granted"])
    }

    /// macOS gives a running app its new permission only after a relaunch.
    func testAllowedButStillRefusedSaysToRelaunch() {
        hid.refusal = .relaunch
        let tablets = picked()
        XCTAssertEqual(tablets.status, .fallback(.relaunch))
        XCTAssertFalse(tablets.capture.isCaptured)
    }

    /// THE FALLBACK: the driver holds the tablet — the page still writes
    /// from the driver's events, and the next coming-to-the-front tries
    /// again.
    func testARefusedSeizeFallsBackToTheDriversEvents() {
        hid.refusal = .driverHolds(TabletCapture.exclusiveAccess)
        let tablets = picked()
        XCTAssertEqual(tablets.status, .fallback(.driverHolds(TabletCapture.exclusiveAccess)))
        XCTAssertTrue(input.isCapturing, "the pen's events are still the page's")
        XCTAssertNil(input.rawSince)
        tablets.appResignedActive()
        hid.refusal = nil
        tablets.appBecameActive()
        XCTAssertEqual(hid.seizes.count, 2, "tried again on coming back")
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
    }

    // MARK: - Held, and let go

    /// THE TABLET FOLLOWS THE PAGE. Put the pane away (⌘Y) and the pen is
    /// a pointer again — in WriteMind too, where the notebook's own pen
    /// needs it, and where a pen held for a page nobody can see would write
    /// nowhere at all. Bring the page back and it is taken again, asking
    /// nothing.
    func testPuttingThePageAwayGivesThePenBack() {
        let tablets = picked()
        XCTAssertTrue(hid.isOpen)
        input.pageDisappeared()
        XCTAssertEqual(hid.releases, 1, "the page went and the tablet stayed held")
        XCTAssertFalse(hid.isOpen)
        XCTAssertEqual(tablets.status, .standby)
        tablets.appResignedActive()
        tablets.appBecameActive()
        XCTAssertEqual(hid.seizes.count, 1, "the tablet was taken for a page nobody can see")
        input.pageAppeared()
        XCTAssertEqual(hid.seizes.count, 2, "back on screen: taken again")
        XCTAssertEqual(hid.asks, 0, "asking nothing")
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
    }

    /// AND IT FOLLOWS THE APP: in another app the pen is that app's.
    func testLeavingTheFrontGivesThePenBackAndComingBackTakesIt() {
        let tablets = picked()
        tablets.appResignedActive()
        XCTAssertEqual(hid.releases, 1)
        XCTAssertFalse(hid.isOpen, "WriteMind behind another app still held the tablet")
        XCTAssertEqual(tablets.status, .standby)
        tablets.appBecameActive()
        XCTAssertEqual(hid.seizes.count, 2)
        XCTAssertTrue(hid.isOpen)
    }

    /// A pick with the pane put away asks — the question is the pick's to
    /// put — and opens nothing until there is a page to write on.
    func testAPickWithThePageAwayAsksAndWaitsForThePage() {
        hid.granted = .undecided
        input.pageDisappeared()
        let tablets = picked()
        XCTAssertEqual(hid.asks, 1, "the pick asks, page or no page")
        XCTAssertEqual(hid.seizes, [], "and holds nothing until the page is up")
        XCTAssertEqual(tablets.status, .standby)
        input.pageAppeared()
        XCTAssertEqual(hid.seizes, [0x037A])
    }

    func testUnpluggingLetsGoAndPluggingBackTakesThePen() {
        let tablets = picked()
        tablets.unplugged(registryID: 1)
        XCTAssertEqual(hid.releases, 1)
        XCTAssertEqual(tablets.status, .unplugged)
        XCTAssertTrue(tablets.isSelected, "still the pick — the pane says it is unplugged")
        XCTAssertTrue(tablets.tablets.isEmpty)
        tablets.plugged(oneByWacom, registryID: 2, settle: 0)
        XCTAssertEqual(hid.seizes.count, 2)
        XCTAssertEqual(hid.asks, 0)
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
    }

    func testTurningTheTabletOffLetsGoAndForgets() {
        let tablets = picked()
        tablets.turnOff()
        XCTAssertEqual(hid.releases, 1)
        XCTAssertEqual(tablets.status, .off)
        XCTAssertFalse(tablets.isSelected)
        XCTAssertNil(defaults.string(forKey: "lastTabletID"), "the next launch is the camera's")
        XCTAssertFalse(input.isRunning, "the pen is a pointer again")
    }

    /// On the way out the tablet is closed before the process goes, so
    /// whatever was changed on it is put back.
    func testQuittingClosesTheTabletAndWaitsForIt() {
        let tablets = picked()
        tablets.appWillQuit()
        XCTAssertEqual(hid.releasesWaitedFor, 1)
        XCTAssertFalse(tablets.capture.isCaptured)
    }

    func testAnOpenThatLandsAfterTheTabletWasTurnedOffIsNobodys() {
        hid.hold = true
        let tablets = picked()
        XCTAssertEqual(tablets.status, .standby, "the open is on its way")
        tablets.turnOff()
        XCTAssertEqual(hid.releases, 1, "the close follows the open down the same queue")
        guard !hid.held.isEmpty else { return XCTFail("nothing was being opened") }
        hid.held.removeFirst()()
        XCTAssertEqual(tablets.status, .off)
        XCTAssertFalse(tablets.capture.isCaptured)
    }

    func testAnOpenThatLandsAfterThePageWentIsNobodys() {
        hid.hold = true
        let tablets = picked()
        input.pageDisappeared()
        XCTAssertEqual(hid.releases, 1)
        guard !hid.held.isEmpty else { return XCTFail("nothing was being opened") }
        hid.held.removeFirst()()
        XCTAssertFalse(tablets.capture.isCaptured)
        XCTAssertEqual(tablets.status, .standby)
    }

    /// Picked again while macOS's question is still up: one question, not
    /// two, and the pane is the page all along.
    func testPickingAgainWhileTheQuestionIsUpAsksOnce() {
        hid.granted = .undecided
        hid.hold = true
        let tablets = picked()
        tablets.pick(oneByWacom)
        XCTAssertEqual(hid.asks, 1)
        XCTAssertEqual(tablets.status, .standby)
        hid.hold = false
        guard !hid.held.isEmpty else { return XCTFail("nothing was asked") }
        hid.held.removeFirst()()
        XCTAssertEqual(hid.seizes, [0x037A])
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
    }

    /// THE HOLD FOLLOWS THE PICK: with two tablets plugged in, picking the
    /// other one lets go of the first and takes it — and what the first
    /// still sends is nobody's.
    func testPickingAnotherTabletLetsGoOfTheFirstAndTakesIt() {
        let tablets = picked()
        let medium = TabletDevice(model: "CTL-672", productID: 0x037B, serial: "3EB00M2000001")
        tablets.plugged(medium, registryID: 2, settle: 0)
        tablets.pick(medium)
        XCTAssertEqual(hid.releases, 1, "the first tablet stayed held")
        XCTAssertEqual(hid.seizes, [0x037A, 0x037B], "the one picked was never taken")
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: false))
        var got = 0
        let watching = input.samples.sink { _ in got += 1 }
        defer { watching.cancel() }
        send(penReport(), at: 10.0)
        XCTAssertEqual(got, 0, "the tablet let go of went on writing")
        send(penReport(), at: 10.1, capture: 1)
        XCTAssertEqual(got, 1)
    }

    // MARK: - The reports

    /// ONE FUNNEL: a raw report becomes the same samples an event would —
    /// through the turn, onto the page.
    func testTheTabletsOwnReportsBecomeThePensSamples() {
        let tablets = picked()
        XCTAssertTrue(tablets.capture.isCaptured)
        var got: [TabletSample] = []
        let watching = input.samples.sink { got.append($0) }
        defer { watching.cancel() }
        send(penReport(x: 3800, y: 2375), at: 10.0)
        send(penReport(x: 3800, y: 2375, flags: 0xE1, pressure: 1024), at: 10.008)
        send(penReport(x: 3800, y: 2375, flags: 0xE0), at: 10.016)
        XCTAssertEqual(got.map(\.phase), [.hover, .down, .up])
        guard got.count == 3 else { return }
        XCTAssertEqual(got[1].page, CGPoint(x: 0.75, y: 0.25), "turned a quarter clockwise, as an event's is")
        XCTAssertEqual(got[1].pressure, 1024.0 / 2047.0, accuracy: 1e-9)
        XCTAssertEqual(input.rawSince, 10.0)
    }

    /// WHETHER THE PEN WAS DOWN AS THE TABLET WAS TAKEN is in the log, by
    /// the tablet's own first word of each capture. A pen tap on
    /// WriteMind's window is what brings it to the front, so the tablet can
    /// be taken with the nib still on it — the driver posted the button
    /// going down and, cut off, never posts it coming up. Nobody has seen
    /// what macOS makes of that; this line is how a session says it
    /// happened.
    func testTheLogSaysWhetherThePenWasDownAsTheTabletWasTaken() {
        let tablets = picked()
        var lines: [String] = []
        input.log = { lines.append($0) }
        let delivering = "tablet: raw capture is delivering — the driver's events are ignored from here; "
        let down = delivering + "its first report has the pen DOWN, so the driver saw it go down and will not see it lift"
        let up = delivering + "its first report has nothing pressed"

        send(penReport(flags: 0xE1, pressure: 900), at: 10.0)
        send(penReport(flags: 0xE0), at: 10.008)
        XCTAssertEqual(lines.filter { $0.contains("is delivering") }, [down], "the nib, and said once a capture")

        tablets.appResignedActive()
        tablets.appBecameActive()
        send(penReport(), at: 11.0, capture: 1)
        XCTAssertEqual(lines.filter { $0.contains("is delivering") }, [down, up], "hovering")

        tablets.appResignedActive()
        tablets.appBecameActive()
        send(penReport(flags: 0xE2), at: 12.0, capture: 2)
        XCTAssertEqual(lines.filter { $0.contains("is delivering") }, [down, up, down],
                       "the side switch is the driver's right button")

        tablets.appResignedActive()
        tablets.appBecameActive()
        send(penReport(flags: 0x80), at: 13.0, capture: 3)
        XCTAssertEqual(lines.filter { $0.contains("is delivering") }, [down, up, down, up], "only coming near")
    }

    /// What is not a pen report is written down and left alone.
    func testAReportThatIsNotThePensDrawsNothing() {
        let tablets = picked()
        var lines: [String] = []
        tablets.log = { lines.append($0) }
        var got = 0
        let watching = input.samples.sink { _ in got += 1 }
        defer { watching.cancel() }
        send([1, 0, 3, 0xFD], at: 10.0)
        send([2] + [UInt8](repeating: 0, count: 63), at: 10.1)
        XCTAssertEqual(got, 0)
        XCTAssertNil(input.rawSince)
        XCTAssertEqual(lines.filter { $0.contains("not a pen report") }.count, 2, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("01 00 03 fd") }, "in hex, whole")
    }

    /// A tablet that is held and cannot be read is a dead pen: it is given
    /// back, the pane says so, and the driver's events write again.
    func testATabletWhoseReportsCannotBeReadIsGivenBack() {
        let tablets = picked()
        for index in 0..<TabletCapture.unreadableBurst {
            send([1, 0, 3, 0xFD], at: 10 + Double(index) * 0.008)
        }
        XCTAssertEqual(hid.releases, 1, "held on to a tablet it cannot read")
        XCTAssertEqual(tablets.status, .fallback(.unreadable))
        tablets.appResignedActive()
        tablets.appBecameActive()
        XCTAssertEqual(hid.seizes.count, 1, "and not taken again until it is picked again")
    }

    /// The first few reports of a pick go to the log; the pen's hundred a
    /// second after that do not.
    func testTheLogHoldsTheFirstReportsAndNotEverySample() {
        let tablets = picked()
        var lines: [String] = []
        tablets.log = { lines.append($0) }
        for index in 0..<40 {
            send(penReport(x: 100 + index), at: 10 + Double(index) * 0.008)
        }
        XCTAssertEqual(lines.filter { $0.contains("raw report") }.count, TabletController.reportsToLog)
        XCTAssertEqual(lines.filter { $0.contains("first raw reading") }.count, 1)
        XCTAssertTrue(lines.contains { $0.contains("first raw reading") && $0.contains("distance: 20") },
                      "the first report is in the log as it was READ, every field, beside what was made of it")
        send([0xC0, 1, 2, 3, 4, 5, 6, 7, 8, 9], at: 11)
        send([0xC0, 9, 8, 7, 6, 5, 4, 3, 2, 1], at: 11.1)
        XCTAssertEqual(lines.filter { $0.contains("unknown kind") }.count, 1, "the first of a kind, once")
    }

    /// A report on its way when the tablet was let go is nobody's — and one
    /// from the capture before is not this capture's.
    func testAReportFromACaptureLetGoIsDropped() {
        let tablets = picked()
        var got = 0
        let watching = input.samples.sink { _ in got += 1 }
        defer { watching.cancel() }
        tablets.appResignedActive()
        send(penReport(), at: 10.0)
        XCTAssertEqual(got, 0, "let go, and still drawing")
        tablets.appBecameActive()
        send(penReport(), at: 10.1)
        XCTAssertEqual(got, 0, "the old capture's report drew on the new one")
        send(penReport(), at: 10.2, capture: 1)
        XCTAssertEqual(got, 1)
    }

    /// Letting go mid-stroke lifts the pen: the stroke ends where it was,
    /// and the driver's next event starts afresh.
    func testLettingGoMidStrokeEndsTheStroke() {
        let tablets = picked()
        var got: [TabletSample] = []
        let watching = input.samples.sink { got.append($0) }
        defer { watching.cancel() }
        send(penReport(flags: 0xE1, pressure: 900), at: 10.0)
        tablets.appResignedActive()
        XCTAssertEqual(got.map(\.phase), [.down, .up, .hover])
        XCTAssertEqual(got.last?.inProximity, false)
        XCTAssertNil(input.rawSince)
        XCTAssertNil(input.pen)
    }

    /// The driver went on posting while WriteMind held the tablet: the
    /// pane says the pointer may still move.
    func testADriverThatStillPostsIsSaid() throws {
        let tablets = picked()
        send(penReport(), at: 10.0)
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                       mouseCursorPosition: .zero, mouseButton: .left))
        cg.setIntegerValueField(.mouseEventSubtype, value: 1)
        cg.timestamp = 12_000_000_000
        XCTAssertNil(input.handle(try XCTUnwrap(NSEvent(cgEvent: cg)), from: .local))
        XCTAssertEqual(tablets.status, .captured(driverStillPosts: true))
    }
}

/// The pane follows the pick, and the tablet's turn is remembered.
@MainActor
final class TabletInputSourceTests: XCTestCase {
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "WriteMindTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func state() -> AppState { AppState(defaults: UserDefaults(suiteName: suite)!) }

    func testThePaneIsWhicheverWasPickedLast() {
        let app = state()
        XCTAssertEqual(app.inputSource, .camera)
        app.follow(tabletPicked: true)
        XCTAssertEqual(app.inputSource, .tablet)
        app.follow(tabletPicked: false)
        XCTAssertEqual(app.inputSource, .camera)
        XCTAssertEqual(AppState.InputSource.of(tabletPicked: true), .tablet)
    }

    /// One quarter turn clockwise unless he turns it back — and kept.
    func testTheTabletIsHeldTurnedOnceClockwiseUntilItIsTurned() {
        let app = state()
        XCTAssertEqual(app.tabletQuarterTurns, 1)
        app.rotateTablet(by: 1)
        XCTAssertEqual(app.tabletQuarterTurns, 2)
        XCTAssertEqual(state().tabletQuarterTurns, 2, "remembered")
        app.rotateTablet(by: -3)
        XCTAssertEqual(app.tabletQuarterTurns, 3)
        app.rotateTablet(by: 1)
        XCTAssertEqual(app.tabletQuarterTurns, 0)
        UserDefaults(suiteName: suite)!.set(7, forKey: "tabletQuarterTurns")
        XCTAssertEqual(state().tabletQuarterTurns, 3, "whatever is stored comes back as a quarter turn")
    }
}

/// The pane's one switch, its panel and its way out call it what it is.
final class InputPaneWordsTests: XCTestCase {
    func testThePageIsNeverCalledTheVideo() {
        let camera = AppState.InputSource.camera.words
        XCTAssertEqual(camera.hide, "Hide Video", "the camera's words are as they were")
        XCTAssertEqual(camera.wholeWindowHelp, "Put the notes away and give the window to the video")
        let page = AppState.InputSource.tablet.words
        let texts = [page.show, page.hide, page.showHelp, page.hideHelp, page.wholeWindowHelp,
                     page.sideBySideHelp, page.leaveWholeWindow, page.options]
        for text in texts {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("video")
                           || text.localizedCaseInsensitiveContains("camera"), "the page called \(text)")
        }
        for words in [camera, page] {
            for icon in [words.shownIcon, words.hiddenIcon] {
                XCTAssertNotNil(NSImage(systemSymbolName: icon, accessibilityDescription: nil),
                                "the pane's switch asks for the missing symbol \(icon)")
            }
        }
    }
}

/// The pane's one line about the pen: the one useful thing for each state.
@MainActor
final class TabletPaneLineTests: XCTestCase {
    private let tablet = "One by Wacom (CTL-472)"
    private let refusals: [TabletCapture.Refusal] = [
        .undecided, .denied, .relaunch, .driverHolds(TabletCapture.exclusiveAccess),
        .failed(TabletCapture.notPermitted), .noDevice, .unreadable, .underTest,
    ]

    func testEveryReasonThePenIsNotHeldHasItsLine() {
        for refusal in refusals {
            let line = TabletPane.line(for: .fallback(refusal), name: tablet)
            XCTAssertNotNil(line, "\(refusal)")
            XCTAssertFalse(line?.text.isEmpty ?? true)
        }
    }

    /// Input Monitoring is what System Settings can change: undecided and
    /// denied offer the way there, and nothing else does.
    func testOnlyInputMonitoringOffersTheSettings() {
        for refusal in refusals {
            let offers = refusal == .undecided || refusal == .denied
            XCTAssertEqual(TabletPane.line(for: .fallback(refusal), name: tablet)?.opensSettings, offers, "\(refusal)")
        }
        XCTAssertEqual(TabletPane.line(for: .captured(driverStillPosts: false), name: tablet)?.opensSettings, false)
        XCTAssertEqual(TabletPane.inputMonitoringSettings,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    /// Nobody was asked yet — a pick remembered from before WriteMind took
    /// the tablet itself: the line says how to be asked.
    func testUndecidedSaysToPickAgain() throws {
        let text = try XCTUnwrap(TabletPane.line(for: .fallback(.undecided), name: tablet)).text
        XCTAssertTrue(text.contains("Pick \(tablet) in Input Devices again"), text)
        XCTAssertTrue(text.contains("Input Monitoring"), text)
    }

    func testDeniedNamesThePermission() throws {
        let text = try XCTUnwrap(TabletPane.line(for: .fallback(.denied), name: tablet)).text
        XCTAssertTrue(text.contains("Input Monitoring"), text)
        XCTAssertTrue(text.contains("moves the pointer too"), text)
    }

    func testAllowedButRefusedSaysToQuitAndReopen() throws {
        let text = try XCTUnwrap(TabletPane.line(for: .fallback(.relaunch), name: tablet)).text
        XCTAssertTrue(text.contains("quit and reopen WriteMind"), text)
    }

    /// The fallback gives its reason — with what IOKit said, in hex, the
    /// same number the log has.
    func testTheFallbackSaysWhyWithTheCode() throws {
        let held = try XCTUnwrap(TabletPane.line(for: .fallback(.driverHolds(TabletCapture.exclusiveAccess)),
                                                 name: tablet)).text
        XCTAssertTrue(held.contains("0xe00002c5"), held)
        XCTAssertTrue(held.contains("moves the pointer too"), held)
        let failed = try XCTUnwrap(TabletPane.line(for: .fallback(.failed(TabletCapture.notPermitted)),
                                                   name: tablet)).text
        XCTAssertTrue(failed.contains("0xe00002e2"), failed)
    }

    /// Held: quiet. Held with the driver still posting: said.
    func testCapturedIsQuietUnlessTheDriverStillPosts() {
        XCTAssertEqual(TabletPane.line(for: .captured(driverStillPosts: false), name: tablet)?.text,
                       "\(tablet) — pen captured")
        let still = TabletPane.line(for: .captured(driverStillPosts: true), name: tablet)
        XCTAssertTrue(still?.text.contains("pointer may still move") ?? false, "\(String(describing: still))")
    }

    func testStandbyNamesTheTabletAndThePlaceholdersHaveNoLine() {
        XCTAssertEqual(TabletPane.line(for: .standby, name: tablet)?.text, tablet)
        XCTAssertNil(TabletPane.line(for: .off, name: tablet))
        XCTAssertNil(TabletPane.line(for: .unplugged, name: tablet))
    }

    /// Nothing here talks of the driver being ASKED any more: there is no
    /// Automation in it.
    func testNoLineSpeaksOfAutomation() {
        let statuses: [TabletController.Status] = [.standby, .captured(driverStillPosts: false),
                                                    .captured(driverStillPosts: true)]
            + refusals.map { .fallback($0) }
        for status in statuses {
            let text = TabletPane.line(for: status, name: tablet)?.text ?? ""
            XCTAssertFalse(text.localizedCaseInsensitiveContains("automation"), text)
        }
    }

    func testNothingInTheAppAsksForAutomation() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription"),
                     "the Apple Event path is gone, and its usage string with it")
    }

    func testEveryIconTheTabletPaneUsesExists() {
        var icons: Set<String> = ["pencil.tip", "cable.connector.slash", "rotate.left", "rotate.right",
                                  "rectangle.lefthalf.inset.filled", "video.badge.ellipsis"]
        let statuses: [TabletController.Status] = [.standby, .captured(driverStillPosts: false),
                                                    .captured(driverStillPosts: true)]
            + refusals.map { .fallback($0) }
        for status in statuses { if let icon = TabletPane.line(for: status, name: tablet)?.icon { icons.insert(icon) } }
        for icon in icons {
            XCTAssertNotNil(NSImage(systemSymbolName: icon, accessibilityDescription: nil),
                            "the tablet pane asks for the missing symbol \(icon)")
        }
    }
}
