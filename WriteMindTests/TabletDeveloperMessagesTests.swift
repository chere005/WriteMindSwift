import Combine
import XCTest
@testable import WriteMind

/// WHAT THE PEN DEVELOPER'S TOOLS SAY, and where (Sean, 2026-10-03: "make sure
/// i can develop wacom features without a device plugged in"): a message is
/// the status the panel and the menu show AND a line in the app's footer,
/// whatever tablet is picked, and a replay that would not be heard is said
/// before a file is asked for.
@MainActor
final class TabletDeveloperMessagesTests: XCTestCase {
    private var folder: URL!
    private var suite: String!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-say-\(UUID().uuidString)")
        suite = "WriteMindTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func make(developerOn: Bool = true) -> (TabletDeveloper, TabletInput, VirtualClock) {
        let clock = VirtualClock()
        let input = TabletInput()
        input.start()
        input.pageAppeared()
        input.policy = TabletSourcePolicy(developerOn: developerOn, realConnected: false)
        let developer = TabletDeveloper(defaults: UserDefaults(suiteName: suite)!, input: input, clock: clock)
        input.attach(developer.virtual)
        developer.productID = { 0x037A }
        return (developer, input, clock)
    }

    /// EVERY MESSAGE IS SAID IN THE APP'S FOOTER, whatever is picked: the
    /// virtual tablet's panel is up only while the virtual tablet is the pick,
    /// which is not the flow recording is for (a bug seen on the real tablet),
    /// and a message said only there — a recording saved, nothing heard, a
    /// file that cannot be played — was said to nobody.
    func testEveryMessageIsAlsoSaidInTheFooterWhateverIsPicked() throws {
        let notes = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-footer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: notes) }
        let store = NoteStore(directory: notes)
        let (developer, _, clock) = make()
        developer.virtualEnabled = true
        developer.say(in: store)
        XCTAssertNil(store.captureNotice)

        developer.startRecording()
        XCTAssertTrue(store.captureNotice?.contains("Recording the pen") == true, store.captureNotice ?? "nil")

        XCTAssertNil(developer.stopRecording(into: folder), "nothing was heard")
        XCTAssertTrue(store.captureNotice?.contains("Nothing was recorded") == true, store.captureNotice ?? "nil")
        XCTAssertEqual(store.captureNotice, developer.status, "the panel and the footer say the same")

        developer.startRecording()
        developer.virtual.padMove(to: CGPoint(x: 0.3, y: 0.3))
        clock.advance(by: 0.02)
        developer.virtual.padDown(at: CGPoint(x: 0.3, y: 0.3))
        let saved = try XCTUnwrap(developer.stopRecording(into: folder))
        XCTAssertTrue(store.captureNotice?.contains("Saved \(saved.lastPathComponent)") == true, store.captureNotice ?? "nil")

        // A file that is not whole: its line is in the footer.
        let broken = folder.appending(path: "broken.ndjson")
        try Data((#"{"format":"writemind-pen-stream","version":1}"# + "\n"
                  + #"{"report":"02 zz","t":0}"# + "\n").utf8).write(to: broken)
        XCTAssertNil(developer.play(contentsOf: broken))
        XCTAssertTrue(store.captureNotice?.contains("broken.ndjson cannot be played: line 2") == true,
                      store.captureNotice ?? "nil")
        XCTAssertNil(developer.play(contentsOf: folder.appending(path: "missing.ndjson")))
        XCTAssertTrue(store.captureNotice?.contains("missing.ndjson cannot be played") == true, store.captureNotice ?? "nil")

        // A replay that would not be heard.
        let (off, _, _) = make(developerOn: false)
        off.say(in: store)
        XCTAssertNil(off.play(try PenFixtures.load("stroke")))
        XCTAssertTrue(store.captureNotice?.contains("virtual tablet is off") == true, store.captureNotice ?? "nil")
    }

    /// THE WIRING, which no running test can reach (the app's scene is not
    /// built under test): the app hands the footer to the developer, and the
    /// footer shows the notice the store keeps. Read from the sources, as the
    /// suite does where a call has to be there (`CanvasModeTests`).
    func testTheAppHandsTheFooterToTheDeveloperAndTheFooterShowsTheNotice() throws {
        func source(_ path: String) throws -> String {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            return try String(contentsOf: root.appending(path: path), encoding: .utf8)
        }
        let app = try source("WriteMind/WriteMindApp.swift")
        XCTAssertTrue(app.contains("tablet.developer.say(in: store)"), "WriteMindApp no longer wires the developer's messages to the footer")
        let pane = try source("WriteMind/Views/EditorPane.swift")
        XCTAssertTrue(pane.contains("store.captureNotice"), "the footer no longer shows the store's notice")
        XCTAssertTrue(try source("WriteMind/Tablet/TabletDeveloper.swift").contains("store?.notice(text)"),
                      "the developer's footer line is the store's notice")
    }

    /// A NOTICE IS NEVER SAID TO NOBODY: the footer is the notes pane's, so
    /// where it is not on screen — the notes put away, the page held up
    /// whole-window, no note open — `ContentView` says the store's notice in a
    /// line at the foot of the window; where it is, only the footer does.
    func testTheNoticeIsInTheFooterWhereThereIsOneAndAtTheFootOfTheWindowWhereThereIsNot() throws {
        let on = ContentView.editorFooterIsOnScreen
        XCTAssertTrue(on(false, true, true), "notes up, a note open: the footer says it")
        XCTAssertFalse(on(false, false, true), "the notes put away (the page alone)")
        XCTAssertFalse(on(true, true, true), "the page held up whole-window")
        XCTAssertFalse(on(false, true, false), "no note open: the pane says 'No note open', with no footer")
        XCTAssertFalse(on(true, false, false))

        // The view reads the store's notice for that line (the scene is not
        // built under test, so from the source, as the wiring test below does).
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: root.appending(path: "WriteMind/Views/ContentView.swift"), encoding: .utf8)
        XCTAssertTrue(content.contains("store.captureNotice"), "ContentView no longer says a notice with no footer")
        XCTAssertTrue(content.contains(".overlay(alignment: .bottom) { strayNotice }"), "and no longer puts it on screen")
    }

    /// The footer is not the only place: with nothing wired, the message is
    /// still the status the panel and the menu show.
    func testAMessageIsTheStatusWithNoFooterWired() {
        let (developer, _, _) = make()
        developer.startRecording()
        XCTAssertEqual(developer.status, "Recording the pen — every report the page hears is written down.")
    }

    /// A REPLAY THAT WOULD NOT BE HEARD IS SAID BEFORE A FILE IS ASKED FOR:
    /// the menu's "Replay…" used to open the chooser first and only then say
    /// why nothing happened.
    func testAReplayThatWouldNotBeHeardIsSaidBeforeAFileIsAskedFor() throws {
        var asked = 0
        let chooser: () -> URL? = { asked += 1; return nil }

        let (off, _, _) = make(developerOn: false)
        var said: [String] = []
        off.onSay = { said.append($0) }
        off.chooseAndPlay(choosing: chooser)
        XCTAssertEqual(asked, 0, "the switch is off: no chooser")
        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said.first?.contains("virtual tablet is off") == true, said.first ?? "")

        let (real, realInput, _) = make()
        real.onSay = { said.append($0) }
        realInput.policy.realConnected = true
        real.chooseAndPlay(choosing: chooser)
        XCTAssertEqual(asked, 0, "a real tablet is plugged in: no chooser")
        XCTAssertTrue(said.last?.contains("real tablet") == true, said.last ?? "")

        let (nobody, nobodyInput, _) = make()
        nobody.onSay = { said.append($0) }
        nobodyInput.stop()
        nobody.chooseAndPlay(choosing: chooser)
        XCTAssertEqual(asked, 0, "no tablet picked: no chooser")
        XCTAssertTrue(said.last?.contains("Pick a tablet") == true, said.last ?? "")

        let (hidden, hiddenInput, _) = make()
        hidden.onSay = { said.append($0) }
        hiddenInput.pageDisappeared()
        hidden.chooseAndPlay(choosing: chooser)
        XCTAssertEqual(asked, 0, "nothing on screen to write on: no chooser")
        XCTAssertTrue(said.last?.contains("on screen") == true, said.last ?? "")

        // Heard: the chooser is asked, and what it gives is played.
        let (ready, _, _) = make()
        ready.onSay = { said.append($0) }
        ready.chooseAndPlay(stepping: true, choosing: { asked += 1; return PenFixtures.url("stroke") })
        XCTAssertEqual(asked, 1)
        XCTAssertNotNil(ready.replay)
        XCTAssertTrue(said.last?.contains("Stepping through") == true, said.last ?? "")
        ready.stopReplay()
    }

    // MARK: - The menu

    /// WHAT THE MENU OFFERS follows where the tools stand: the record item
    /// says which it is, the window and the replays wait for the switch, Next
    /// Event and Stop Replay for a replay in hand, and the last message is
    /// kept at its foot.
    func testTheMenuOffersWhatTheToolsCanDoAndSaysWhatHappened() throws {
        let (developer, _, clock) = make()

        var menu = TabletDeveloperMenuModel(developer)
        XCTAssertEqual(menu.recordTitle, "Record Pen Session")
        XCTAssertFalse(menu.showWindowEnabled, "the switch is off")
        XCTAssertFalse(menu.replayEnabled)
        XCTAssertFalse(menu.nextEventEnabled)
        XCTAssertFalse(menu.stopReplayEnabled)
        XCTAssertNil(menu.status)
        XCTAssertNil(menu.silence)

        developer.silence = "A real tablet is plugged in, so it wins"
        XCTAssertEqual(TabletDeveloperMenuModel(developer).silence, "A real tablet is plugged in, so it wins")
        developer.silence = nil

        developer.virtualEnabled = true
        menu = TabletDeveloperMenuModel(developer)
        XCTAssertTrue(menu.showWindowEnabled)
        XCTAssertTrue(menu.replayEnabled)

        developer.startRecording()
        menu = TabletDeveloperMenuModel(developer)
        XCTAssertEqual(menu.recordTitle, "Stop Recording Pen Session")
        XCTAssertTrue(menu.status?.contains("Recording") == true, menu.status ?? "nil")
        _ = developer.stopRecording(into: folder)
        menu = TabletDeveloperMenuModel(developer)
        XCTAssertEqual(menu.recordTitle, "Record Pen Session")
        XCTAssertTrue(menu.status?.contains("Nothing was recorded") == true, menu.status ?? "nil")

        let replay = try XCTUnwrap(developer.play(try PenFixtures.load("stroke"), stepping: true))
        menu = TabletDeveloperMenuModel(developer)
        XCTAssertTrue(menu.nextEventEnabled)
        XCTAssertTrue(menu.stopReplayEnabled)
        while replay.state != .finished { replay.step() }
        clock.advance(by: 1)
        menu = TabletDeveloperMenuModel(developer)
        XCTAssertFalse(menu.nextEventEnabled, "nothing left to step")
        XCTAssertTrue(menu.stopReplayEnabled, "the replay is still in hand")
        developer.stopReplay()
        menu = TabletDeveloperMenuModel(developer)
        XCTAssertFalse(menu.stopReplayEnabled)

        developer.virtualEnabled = false
        XCTAssertFalse(TabletDeveloperMenuModel(developer).replayEnabled)
    }
}
