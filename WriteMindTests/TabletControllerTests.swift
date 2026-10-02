import AppKit
import XCTest
@testable import WriteMind

/// The tablet chosen "as if it were an input display" (Sean, 2026-10-02):
/// found, picked, remembered, and the driver's context made, kept and let
/// go — against a stand-in for the driver, because the test host never
/// talks to the real one.
@MainActor
final class TabletControllerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var link: StandInLink!
    private var input: TabletInput!

    private let oneByWacom = TabletDevice(model: "CTL-472", productID: 0x037A, serial: "2DA00L1059230")

    override func setUp() {
        super.setUp()
        suite = "WriteMindTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        link = StandInLink()
        input = TabletInput()
        // The page is on screen, as it is whenever a tablet is the input
        // and its pane is up. The tests that put it away say so.
        input.pageAppeared()
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func controller() -> TabletController {
        TabletController(defaults: defaults, link: link, input: input, live: false)
    }

    /// The driver as the controller sees it: every call written down, and
    /// an answer that can be held back to arrive later.
    final class StandInLink: TabletDriverLink {
        struct Call: Equatable {
            let existing: UInt32?
            let ask: Bool
        }
        var driverIsRunning = true
        var calls: [Call] = []
        var letGone: [UInt32] = []
        var letGoWithoutWaiting: [UInt32] = []
        var nextContext: UInt32 = 7
        var failure: WacomDriver.Failure?
        var failureUnlessAsked: WacomDriver.Failure?
        var extent: TabletExtent?
        var hold = false
        var held: [() -> Void] = []

        func takeThePen(existing: UInt32?, ask: Bool, done: @escaping @MainActor (WacomDriver.Outcome) -> Void) {
            calls.append(Call(existing: existing, ask: ask))
            var outcome = WacomDriver.Outcome()
            if let failureUnlessAsked, !ask {
                outcome.failure = failureUnlessAsked
            } else if let failure {
                outcome.failure = failure
            } else if let existing {
                outcome.context = existing
            } else {
                outcome.context = nextContext
                outcome.created = true
                outcome.extent = extent
            }
            let answer = { MainActor.assumeIsolated { done(outcome) } }
            if hold { held.append(answer) } else { answer() }
        }

        func letGo(_ context: UInt32, wait: Bool) {
            if wait { letGone.append(context) } else { letGoWithoutWaiting.append(context) }
        }
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
    }

    func testAFirstLaunchNeverAsks() {
        let tablets = controller()
        tablets.restoreRemembered()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        XCTAssertEqual(tablets.tablets, [oneByWacom], "listed")
        XCTAssertFalse(tablets.isSelected, "listed is not picked")
        XCTAssertEqual(link.calls, [], "the driver was spoken to with nothing picked")
        XCTAssertEqual(tablets.status, .off)
    }

    /// PICKING IS THE ONE THING THAT MAY ASK.
    func testPickingTheTabletAsksTakesThePenAndIsRemembered() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        XCTAssertEqual(link.calls, [.init(existing: nil, ask: true)])
        XCTAssertEqual(tablets.status, .ready)
        XCTAssertEqual(tablets.currentContext, 7)
        XCTAssertEqual(tablets.selectedTabletID, oneByWacom.id)
        XCTAssertEqual(defaults.string(forKey: "lastTabletID"), oneByWacom.id)
        XCTAssertTrue(input.isRunning, "the funnel is open")
        XCTAssertEqual(input.extent, TabletExtent(width: 15200, height: 9500, countsPerMillimetre: 100),
                       "the table's size until the driver says")
    }

    /// The driver's counts win; the table still says how big the tablet
    /// is in millimetres, which is what the paper is ruled by.
    func testTheDriversOwnMeasureWins() {
        link.extent = TabletExtent(width: 15000, height: 9300)
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        XCTAssertEqual(input.extent.width, 15000)
        XCTAssertEqual(input.extent.height, 9300)
        XCTAssertEqual(Double(input.extent.millimetres?.width ?? 0), 152, accuracy: 1e-9)
    }

    func testARememberedTabletComesBackWithoutAsking() {
        defaults.set(oneByWacom.id, forKey: "lastTabletID")
        defaults.set(oneByWacom.name, forKey: "lastTabletName")
        let tablets = controller()
        tablets.restoreRemembered()
        XCTAssertTrue(tablets.isSelected, "the pane is the tablet's from the start")
        XCTAssertEqual(tablets.status, .unplugged, "until it is found")
        XCTAssertEqual(tablets.selectedName, "One by Wacom (CTL-472)")
        XCTAssertEqual(link.calls, [])
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        XCTAssertEqual(link.calls, [.init(existing: nil, ask: false)], "a launch reconnects, and never asks")
        XCTAssertEqual(tablets.status, .ready)
    }

    /// Nobody answered the prompt yet: the launch stops at the question;
    /// the next PICK asks it.
    func testAnUnansweredQuestionWaitsForThePick() {
        link.failureUnlessAsked = .needsConsent
        defaults.set(oneByWacom.id, forKey: "lastTabletID")
        let tablets = controller()
        tablets.restoreRemembered()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        XCTAssertEqual(tablets.status, .unavailable(.needsConsent))
        tablets.appBecameActive()
        XCTAssertEqual(link.calls.map(\.ask), [false, false], "coming to the front does not ask")
        tablets.pick(oneByWacom)
        XCTAssertEqual(link.calls.last, .init(existing: nil, ask: true))
        XCTAssertEqual(tablets.status, .ready)
    }

    func testARefusalIsSaid() {
        link.failure = .automationDenied
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        XCTAssertEqual(tablets.status, .unavailable(.automationDenied))
        XCTAssertTrue(tablets.isSelected, "the page still works from what reaches WriteMind")
        XCTAssertTrue(input.isRunning)
    }

    func testNoDriverIsSaidWithoutAnAppleEvent() {
        link.driverIsRunning = false
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        XCTAssertEqual(tablets.status, .unavailable(.noDriver))
        XCTAssertEqual(link.calls, [])
    }

    // MARK: - Kept, made again, let go

    /// Contexts act only while WriteMind is in front: coming back checks the
    /// one that stands, and makes no second.
    func testComingBackToTheFrontKeepsTheContext() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.appBecameActive()
        XCTAssertEqual(link.calls.last, .init(existing: 7, ask: false))
        XCTAssertEqual(tablets.currentContext, 7)
        XCTAssertEqual(link.letGone, [])
    }

    func testTheDriverRestartingMakesANewContext() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.driverQuit()
        XCTAssertEqual(tablets.status, .unavailable(.noDriver))
        XCTAssertNil(tablets.currentContext, "the context went with the driver")
        link.nextContext = 8
        tablets.driverLaunched(settle: 0)
        XCTAssertEqual(link.calls.last, .init(existing: nil, ask: false))
        XCTAssertEqual(tablets.currentContext, 8)
        XCTAssertEqual(tablets.status, .ready)
    }

    func testUnpluggingLetsTheContextGoAndPluggingBackTakesThePen() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.unplugged(registryID: 1)
        XCTAssertEqual(link.letGone, [7])
        XCTAssertEqual(tablets.status, .unplugged)
        XCTAssertTrue(tablets.isSelected, "still the pick — the pane says it is unplugged")
        XCTAssertTrue(tablets.tablets.isEmpty)
        tablets.plugged(oneByWacom, registryID: 2, settle: 0)
        XCTAssertEqual(link.calls.last, .init(existing: nil, ask: false))
        XCTAssertEqual(tablets.status, .ready)
    }

    func testTurningTheTabletOffLetsGoAndForgets() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.turnOff()
        XCTAssertEqual(link.letGone, [7])
        XCTAssertEqual(tablets.status, .off)
        XCTAssertFalse(tablets.isSelected)
        XCTAssertNil(defaults.string(forKey: "lastTabletID"), "the next launch is the camera's")
        XCTAssertFalse(input.isRunning, "the pen is a pointer again")
    }

    /// Wacom's rule: a context is destroyed before the app quits — posted,
    /// because there is no time left to wait.
    func testQuittingLetsTheContextGoWithoutWaiting() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.appWillQuit()
        XCTAssertEqual(link.letGoWithoutWaiting, [7])
        XCTAssertNil(tablets.currentContext)
    }

    func testAContextMadeForATabletTurnedOffMeanwhileIsLetGo() {
        link.hold = true
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        XCTAssertEqual(tablets.status, .connecting)
        tablets.turnOff()
        link.held.removeFirst()()
        XCTAssertEqual(link.letGone, [7])
        XCTAssertEqual(tablets.status, .off)
        XCTAssertNil(tablets.currentContext)
    }

    /// THE CONTEXT FOLLOWS THE PAGE. Put the pane away (⌘Y) and the pen is
    /// a pointer again — in WriteMind too, where the notebook's own pen
    /// needs it, and where a pen kept off the pointer for a page nobody can
    /// see would write nowhere at all. Bring the page back and the pen is
    /// the page's again, asking nothing.
    func testPuttingThePageAwayGivesThePenBack() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        XCTAssertEqual(tablets.currentContext, 7)
        input.pageDisappeared()
        XCTAssertEqual(link.letGone, [7], "the page went and the context stayed")
        XCTAssertNil(tablets.currentContext)
        tablets.appBecameActive()
        tablets.driverLaunched(settle: 0)
        XCTAssertEqual(link.calls.count, 1, "a context was made for a page nobody can see")
        link.nextContext = 8
        input.pageAppeared()
        XCTAssertEqual(link.calls.last, .init(existing: nil, ask: false), "back on screen: taken again, asking nothing")
        XCTAssertEqual(tablets.currentContext, 8)
        XCTAssertEqual(tablets.status, .ready)
    }

    /// A pick with the pane put away still asks — the question is the
    /// pick's to put — but holds no context until there is a page to
    /// write on.
    func testAPickWithThePageAwayAsksAndWaitsForThePage() {
        input.pageDisappeared()
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        XCTAssertEqual(link.calls, [.init(existing: nil, ask: true)], "the pick asks, page or no page")
        XCTAssertEqual(link.letGone, [7], "and lets go of what it made until the page is up")
        XCTAssertNil(tablets.currentContext)
        link.nextContext = 8
        input.pageAppeared()
        XCTAssertEqual(link.calls.last, .init(existing: nil, ask: false))
        XCTAssertEqual(tablets.currentContext, 8)
    }

    func testAContextThatLandsAfterThePageWentIsLetGo() {
        link.hold = true
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        input.pageDisappeared()
        link.held.removeFirst()()
        XCTAssertEqual(link.letGone, [7])
        XCTAssertNil(tablets.currentContext)
    }

    /// Picked again while the driver is still answering — the Automation
    /// prompt still up, say — the pane is the page saying it is asking, not
    /// "No tablet selected" under a menu that ticks the tablet.
    func testPickingAgainDuringAConversationIsConnectingNotOff() {
        link.hold = true
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.turnOff()
        XCTAssertEqual(tablets.status, .off)
        tablets.pick(oneByWacom)
        XCTAssertEqual(tablets.status, .connecting)
        link.held.removeFirst()()
        XCTAssertEqual(link.calls.last, .init(existing: 7, ask: true), "the second pick's question is still put")
        link.held.removeFirst()()
        XCTAssertEqual(tablets.status, .ready)
        XCTAssertEqual(tablets.currentContext, 7)
    }

    /// The same for a replug during a conversation: not left "unplugged".
    func testPluggingBackInDuringAConversationIsConnectingNotUnplugged() {
        link.hold = true
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.unplugged(registryID: 1)
        XCTAssertEqual(tablets.status, .unplugged)
        tablets.plugged(oneByWacom, registryID: 2, settle: 0)
        XCTAssertEqual(tablets.status, .connecting)
    }

    /// THE DRIVER IS A BACKGROUND APP (LSBackgroundOnly, LSUIElement), and
    /// macOS posts no launch or quit notice for one — the running list is
    /// the only thing that says it came or went.
    func testTheDriverComingAndGoingIsReadOffTheRunningList() {
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        tablets.runningApplicationsChanged(kind: .insertion, old: [], new: ["com.apple.Safari", nil], settle: 0)
        tablets.runningApplicationsChanged(kind: .removal, old: ["com.apple.Safari"], new: [], settle: 0)
        XCTAssertEqual(tablets.status, .ready, "somebody else's app")
        XCTAssertEqual(link.calls.count, 1)
        tablets.runningApplicationsChanged(kind: .removal, old: [WacomDriver.bundleIdentifier], new: [], settle: 0)
        XCTAssertEqual(tablets.status, .unavailable(.noDriver))
        XCTAssertNil(tablets.currentContext, "the context went with the driver")
        link.nextContext = 8
        tablets.runningApplicationsChanged(kind: .insertion, old: [], new: [nil, WacomDriver.bundleIdentifier], settle: 0)
        XCTAssertEqual(link.calls.last, .init(existing: nil, ask: false))
        XCTAssertEqual(tablets.currentContext, 8)
        XCTAssertEqual(tablets.status, .ready)
        // A whole new list at once (KVO's `.setting`) is read the same way.
        tablets.runningApplicationsChanged(kind: .setting, old: [WacomDriver.bundleIdentifier, "x"], new: ["x"],
                                           settle: 0)
        XCTAssertEqual(tablets.status, .unavailable(.noDriver))
    }

    /// One conversation at a time; whatever arrived meanwhile runs once
    /// afterwards — and asks if any of it asked.
    func testCallsDuringAConversationRunOnceAfterIt() {
        link.hold = true
        link.failureUnlessAsked = .needsConsent
        let tablets = controller()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        defaults.set(oneByWacom.id, forKey: "lastTabletID")
        tablets.restoreRemembered()
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        XCTAssertEqual(link.calls, [.init(existing: nil, ask: false)])
        tablets.appBecameActive()
        tablets.pick(oneByWacom)
        tablets.appBecameActive()
        XCTAssertEqual(link.calls.count, 1, "nothing overlaps")
        link.held.removeFirst()()
        XCTAssertEqual(link.calls.last, .init(existing: nil, ask: true), "the pick's question was kept")
        XCTAssertEqual(link.calls.count, 2)
        link.held.removeFirst()()
        XCTAssertEqual(tablets.status, .ready)
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
        app.orientTablet(.landscapeUpsideDown)
        XCTAssertEqual(app.tabletQuarterTurns, 2)
        XCTAssertEqual(state().tabletQuarterTurns, 2, "remembered")
        app.orientTablet(.landscape)
        XCTAssertEqual(state().tabletQuarterTurns, 0, "remembered")
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

/// The pane's one line about the pen.
@MainActor
final class TabletPaneLineTests: XCTestCase {
    func testEveryWayTheDriverCanSayNoHasItsLine() {
        let failures: [WacomDriver.Failure] = [.noDriver, .automationDenied, .needsConsent, .timedOut,
                                               .noReply, .noTablet, .refusedUnderTest, .other(-50)]
        for failure in failures {
            let line = TabletPane.line(for: .unavailable(failure), name: "One by Wacom (CTL-472)")
            XCTAssertNotNil(line, "\(failure)")
            XCTAssertFalse(line?.text.isEmpty ?? true)
        }
    }

    /// Only a refusal offers System Settings — it is the one thing settled
    /// there.
    func testOnlyARefusalOffersTheSettings() {
        XCTAssertEqual(TabletPane.line(for: .unavailable(.automationDenied), name: "x")?.opensAutomation, true)
        XCTAssertEqual(TabletPane.line(for: .unavailable(.noDriver), name: "x")?.opensAutomation, false)
        XCTAssertEqual(TabletPane.line(for: .unavailable(.needsConsent), name: "x")?.opensAutomation, false)
        XCTAssertEqual(TabletPane.automationSettings,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    func testReadyNamesTheTabletAndThePlaceholdersHaveNoLine() {
        XCTAssertEqual(TabletPane.line(for: .ready, name: "One by Wacom (CTL-472)")?.text, "One by Wacom (CTL-472)")
        XCTAssertNotNil(TabletPane.line(for: .connecting, name: "x"))
        XCTAssertNil(TabletPane.line(for: .off, name: "x"))
        XCTAssertNil(TabletPane.line(for: .unplugged, name: "x"))
    }

    func testEveryIconTheTabletPaneUsesExists() {
        // The turn's control is drawn (`TabletGlyph`), not a symbol.
        var icons: Set<String> = ["pencil.tip", "cable.connector.slash",
                                  "rectangle.lefthalf.inset.filled", "video.badge.ellipsis"]
        let statuses: [TabletController.Status] = [.ready, .connecting, .unavailable(.noDriver),
                                                    .unavailable(.automationDenied), .unavailable(.needsConsent)]
        for status in statuses { if let icon = TabletPane.line(for: status, name: "x")?.icon { icons.insert(icon) } }
        for icon in icons {
            XCTAssertNotNil(NSImage(systemSymbolName: icon, accessibilityDescription: nil),
                            "the tablet pane asks for the missing symbol \(icon)")
        }
    }
}
