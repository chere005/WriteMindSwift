import Combine
import XCTest
@testable import WriteMind

/// THE RECORDING'S FILE: NDJSON, a header and an event a line (Sean,
/// 2026-10-03: "make sure i can develop wacom features without a device
/// plugged in").
final class PenRecordingFileTests: XCTestCase {
    private func sample() -> PenRecording {
        var header = PenRecording.Header()
        header.source = "virtual"
        header.productID = 0x037A
        header.width = 15200
        header.height = 9500
        header.quarterTurns = 1
        header.note = "a hover, a touch, a driver reading and a proximity"
        let point = TabletReading(kind: .point(counts: CGPoint(x: 7600, y: 4750), tip: true, switches: [.lower, .upper],
                                               pressure: 0.25, buttons: 7), timestamp: 0.016, native: false)
        let cannotSay = TabletReading(kind: .point(counts: CGPoint(x: 1, y: 2), tip: false, switches: nil,
                                                   pressure: 0, buttons: 0), timestamp: 0.02, native: true)
        let leaving = TabletReading(kind: .proximity(entering: false), timestamp: 0.024, native: true)
        return PenRecording(header: header, entries: [
            PenStreamEntry(time: 0, event: .report(penReport(flags: 0xE0))),
            PenStreamEntry(time: 0.008, event: .report(penReport(flags: 0xE1, pressure: 1024))),
            PenStreamEntry(time: 0.016, event: .reading(point)),
            PenStreamEntry(time: 0.02, event: .reading(cannotSay)),
            PenStreamEntry(time: 0.024, event: .reading(leaving)),
        ])
    }

    func testTheFileIsAHeaderAndAnEventALineWithSortedKeys() throws {
        let text = String(decoding: sample().ndjson(), as: UTF8.self)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 6)
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(lines[0], #"{"format":"writemind-pen-stream","height":9500,"note":"a hover, a touch, a driver reading and a proximity","productID":890,"quarterTurns":1,"source":"virtual","version":1,"width":15200}"#)
        XCTAssertEqual(lines[1], #"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":0}"#)
        XCTAssertEqual(lines[2], #"{"report":"02 e1 b0 1d 8e 12 00 04 14 00","t":0.008}"#)
        XCTAssertTrue(lines[3].hasPrefix(#"{"reading":{"#), lines[3])
    }

    func testARecordingReadsBackAsItWasWritten() throws {
        let recording = sample()
        let back = try PenRecording(ndjson: recording.ndjson())
        XCTAssertEqual(back.header, recording.header)
        XCTAssertEqual(back.entries, recording.entries)
        XCTAssertEqual(back.duration, 0.024, accuracy: 1e-9)
        XCTAssertEqual(back.ndjson(), recording.ndjson(), "the same bytes again")
    }

    func testAReadingThatCouldNotSayWhatTheSwitchesDidIsKeptThatWay() throws {
        guard case .reading(let reading) = try PenRecording(ndjson: sample().ndjson()).entries[3].event,
              case .point(_, _, let switches, _, _) = reading.kind else { return XCTFail() }
        XCTAssertNil(switches, "unknown is not 'let go'")
    }

    func testTheHeaderSaysWhatFieldItWasRecordedOn() {
        let extent = sample().header.extent
        XCTAssertEqual(extent?.width, 15200)
        XCTAssertEqual(extent?.height, 9500)
        XCTAssertEqual(extent?.countsPerMillimetre, 100, "the table knows the small One by Wacom's scale")
        XCTAssertNil(PenRecording.Header().extent, "a header that says nothing of it")
    }

    func testBlankLinesAreSkippedAndTheFileNeedsNoTrailingNewline() throws {
        let text = String(decoding: sample().ndjson(), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: "\n\n")
        let back = try PenRecording(ndjson: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        XCTAssertEqual(back.entries.count, 5)
    }

    /// A file that is not whole is not played — never "the rest of it".
    func testAFileThatIsNotAWholeRecordingIsRefusedWithWhy() throws {
        XCTAssertThrowsError(try PenRecording(ndjson: Data())) { XCTAssertEqual($0 as? PenRecording.Failure, .empty) }
        XCTAssertThrowsError(try PenRecording(ndjson: Data("hello\n".utf8))) {
            XCTAssertEqual($0 as? PenRecording.Failure, .notAPenStream)
        }
        XCTAssertThrowsError(try PenRecording(ndjson: Data(#"{"format":"something-else","version":1}"#.utf8))) {
            XCTAssertEqual($0 as? PenRecording.Failure, .notAPenStream)
        }
        XCTAssertThrowsError(try PenRecording(ndjson: Data(#"{"format":"writemind-pen-stream","version":9}"#.utf8))) {
            XCTAssertEqual($0 as? PenRecording.Failure, .newer(9))
        }
        let good = String(decoding: sample().ndjson(), as: UTF8.self)
        var broken = good.split(separator: "\n").map(String.init)
        broken[2] = #"{"report":"02 zz","t":0.01}"#
        XCTAssertThrowsError(try PenRecording(ndjson: Data(broken.joined(separator: "\n").utf8))) {
            guard case PenRecording.Failure.line(let number, _) = $0 else { return XCTFail("\($0)") }
            XCTAssertEqual(number, 3, "the line it is on")
        }
        broken[2] = #"{"t":0.01}"#
        XCTAssertThrowsError(try PenRecording(ndjson: Data(broken.joined(separator: "\n").utf8)))
        broken[2] = #"{"reading":{"kind":"wobble","native":true},"t":0.01}"#
        XCTAssertThrowsError(try PenRecording(ndjson: Data(broken.joined(separator: "\n").utf8)))
    }

    func testAFileIsWrittenAndReadFromDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-pen-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "nested/session.ndjson")
        try sample().write(to: url)
        XCTAssertEqual(try PenRecording(contentsOf: url), sample())
    }
}

/// The recorder: what the funnel heard, from the first event.
final class PenRecorderTests: XCTestCase {
    func testTimesAreFromTheFirstEventAndRoundedToTheMicrosecond() {
        let recorder = PenRecorder()
        recorder.record(.report(penReport()), at: 5000.5, from: .virtual)
        recorder.record(.report(penReport()), at: 5000.5 + 0.1 + 0.2, from: .virtual)
        XCTAssertEqual(recorder.entries.map(\.time), [0, 0.3], "not 0.30000000000000004")
    }

    func testAReadingCarriesItsTimeInTheEntryAlone() {
        let recorder = PenRecorder()
        let reading = TabletReading(kind: .proximity(entering: true), timestamp: 777, native: true)
        recorder.record(.reading(reading), at: 777, from: .driver)
        recorder.record(.reading(reading), at: 777.5, from: .driver)
        XCTAssertEqual(recorder.entries[1].event,
                       .reading(TabletReading(kind: .proximity(entering: true), timestamp: 0.5, native: true)))
    }

    func testTheHeaderIsMadeFromWhatWasHeard() {
        let recorder = PenRecorder()
        recorder.record(.report(penReport()), at: 1, from: .hid)
        let recording = recorder.recording(extent: TabletExtent(width: 15200, height: 9500), productID: 0x037A,
                                           quarterTurns: 1, created: Date(timeIntervalSince1970: 0), note: "x")
        XCTAssertEqual(recording.header.source, "hid")
        XCTAssertEqual(recording.header.productID, 0x037A)
        XCTAssertEqual(recording.header.created, "1970-01-01T00:00:00Z")
        XCTAssertEqual(recording.header.note, "x")
    }
}

/// THE REPLAY: at the speed it happened, at a multiple of it, or one event
/// at a time, on a clock that never sleeps.
@MainActor
final class PenReplayTests: XCTestCase {
    /// A hover at t = 0, the nib down at 0.1, the nib up at 0.3.
    private var recording: PenRecording {
        PenRecording(entries: [
            PenStreamEntry(time: 0, event: .report(penReport(flags: 0xE0))),
            PenStreamEntry(time: 0.1, event: .report(penReport(flags: 0xE1, pressure: 1024))),
            PenStreamEntry(time: 0.3, event: .report(penReport(flags: 0xE0))),
        ])
    }

    private func replay(_ recording: PenRecording? = nil, base: TimeInterval = 500) -> (TabletRig, PenReplay) {
        let rig = TabletRig()
        let replay = PenReplay(recording ?? self.recording, clock: rig.clock, base: base)
        rig.input.attach(replay)
        return (rig, replay)
    }

    func testAtTheSpeedItHappened() {
        let (rig, replay) = replay()
        replay.play()
        XCTAssertEqual(replay.state, .playing)
        XCTAssertEqual(replay.delivered, 0, "nothing until the clock runs")
        rig.clock.advance(by: 0)
        XCTAssertEqual(replay.delivered, 1, "the first is due at once")
        rig.clock.advance(by: 0.09)
        XCTAssertEqual(replay.delivered, 1)
        rig.clock.advance(by: 0.02)
        XCTAssertEqual(replay.delivered, 2, "0.1 s after the first")
        rig.clock.advance(by: 0.18)
        XCTAssertEqual(replay.delivered, 2)
        rig.clock.advance(by: 0.02)
        XCTAssertEqual(replay.delivered, 3, "0.2 s after the second")
        XCTAssertEqual(replay.state, .finished)
        XCTAssertEqual(rig.phases, [.hover, .down, .up])
    }

    /// THE PEN READS THE RECORDED TIMES, whatever the pace of the waiting: a
    /// double press is a double press at any speed.
    func testTheStampsAreTheRecordedOnesAtAnySpeed() {
        for speed in [1.0, 2.0, 8.0, PenReplay.asFastAsPossible] {
            let (rig, replay) = replay(base: 500)
            replay.play(speed: speed)
            rig.clock.advance(by: 10)
            let stamps = rig.samples.map(\.timestamp)
            XCTAssertEqual(stamps.count, 3)
            for (stamp, want) in zip(stamps, [500, 500.1, 500.3]) {
                XCTAssertEqual(stamp, want, accuracy: 1e-9, "at \(speed)×")
            }
            XCTAssertEqual(replay.state, .finished)
        }
    }

    func testAtADoubleSpeedTheWaitingIsHalved() {
        let (rig, replay) = replay()
        replay.play(speed: 2)
        rig.clock.advance(by: 0)
        rig.clock.advance(by: 0.051)
        XCTAssertEqual(replay.delivered, 2)
        rig.clock.advance(by: 0.1)
        XCTAssertEqual(replay.delivered, 3)
    }

    func testAtHalfSpeedItTakesTwiceAsLong() {
        let (rig, replay) = replay()
        replay.play(speed: 0.5)
        rig.clock.advance(by: 0.19)
        XCTAssertEqual(replay.delivered, 1)
        rig.clock.advance(by: 0.02)
        XCTAssertEqual(replay.delivered, 2)
    }

    func testAsFastAsPossibleIsNoWaitingAtAll() {
        let (rig, replay) = replay()
        replay.play(speed: PenReplay.asFastAsPossible)
        rig.clock.advance(by: 0)
        XCTAssertEqual(replay.state, .finished)
        XCTAssertEqual(replay.delivered, 3)
    }

    /// ONE EVENT AT A TIME.
    func testSteppingDeliversOneEventAtATime() {
        let (rig, replay) = replay()
        replay.hold()
        XCTAssertEqual(replay.state, .paused)
        rig.clock.advance(by: 10)
        XCTAssertEqual(replay.delivered, 0, "held at the start, whatever the clock says")
        replay.step()
        XCTAssertEqual(rig.phases, [.hover])
        XCTAssertEqual(replay.state, .paused)
        replay.step()
        XCTAssertEqual(rig.phases, [.hover, .down])
        XCTAssertEqual(replay.delivered, 2)
        replay.step()
        XCTAssertEqual(rig.phases, [.hover, .down, .up])
        XCTAssertEqual(replay.state, .finished)
        replay.step()
        XCTAssertEqual(rig.samples.count, 3, "nothing past the end")
    }

    func testPausingHoldsBetweenEventsAndPlayingGoesOn() {
        let (rig, replay) = replay()
        replay.play()
        rig.clock.advance(by: 0)
        replay.pause()
        XCTAssertEqual(replay.state, .paused)
        rig.clock.advance(by: 5)
        XCTAssertEqual(replay.delivered, 1)
        replay.play()
        rig.clock.advance(by: 0.5)
        XCTAssertEqual(replay.state, .finished)
    }

    func testASteppedReplayCanBePlayedOnFromWhereItIs() {
        let (rig, replay) = replay()
        replay.hold()
        replay.step()
        replay.play(speed: 1)
        rig.clock.advance(by: 1)
        XCTAssertEqual(replay.state, .finished)
        XCTAssertEqual(rig.phases, [.hover, .down, .up])
    }

    /// STOPPED WITH THE NIB DOWN, the pen is lifted where it was: a stroke
    /// half-played must not stay down for the next one to carry on.
    func testStoppingMidStrokeLiftsThePenWhereItWas() {
        let (rig, replay) = replay()
        replay.hold()
        replay.step()
        replay.step()
        XCTAssertEqual(rig.phases, [.hover, .down])
        replay.stop()
        XCTAssertEqual(rig.phases, [.hover, .down, .up, .hover], "the stroke ends, and the pen goes out of reach")
        XCTAssertEqual(replay.state, .ready)
        XCTAssertEqual(replay.delivered, 0, "wound back to its start")
        XCTAssertEqual(rig.page.strokes.count, 1, "the half-played stroke is one stroke, finished")
        XCTAssertNil(rig.input.pen)
    }

    func testFinishedTellsWhoWasWaiting() {
        let (rig, replay) = replay()
        var finished = 0
        replay.onFinish = { finished += 1 }
        replay.play()
        rig.clock.advance(by: 1)
        XCTAssertEqual(finished, 1)
    }

    func testAnEmptyRecordingFinishesAtOnce() {
        let (_, replay) = replay(PenRecording())
        replay.play()
        XCTAssertEqual(replay.state, .finished)
    }

    /// Replayed twice, a recording is two strokes: the second never repeats
    /// the stamps the pen has just seen (a repeated stamp is a duplicate to
    /// it) because the clock moved on.
    func testReplayedTwiceItIsTwoStrokes() throws {
        let rig = TabletRig()
        let recording = try PenFixtures.load("stroke")
        rig.play(recording, speed: PenReplay.asFastAsPossible)
        rig.play(recording, speed: PenReplay.asFastAsPossible)
        XCTAssertEqual(rig.page.strokes.count, 2)
    }

    /// With the switch off, or a real tablet plugged in, a replay is not
    /// heard: it is a source like the virtual tablet.
    func testAReplayIsNotHeardWithTheSwitchOffOrARealTabletPluggedIn() {
        // The control: with the switch on and no real tablet, the same replay is heard.
        let (heardRig, heard) = replay()
        heard.play(speed: PenReplay.asFastAsPossible)
        heardRig.clock.advance(by: 1)
        XCTAssertEqual(heardRig.phases, [.hover, .down, .up])

        for policy in [TabletSourcePolicy(developerOn: false, realConnected: false),
                       TabletSourcePolicy(developerOn: true, realConnected: true)] {
            let (rig, replay) = replay()
            rig.input.policy = policy
            replay.play(speed: PenReplay.asFastAsPossible)
            rig.clock.advance(by: 1)
            XCTAssertEqual(replay.state, .finished, "it ran to the end all the same: \(policy)")
            XCTAssertEqual(rig.samples, [], "\(policy)")
        }
    }
}

/// The developer's tools: recording to a file, playing one back.
@MainActor
final class TabletDeveloperTests: XCTestCase {
    private var folder: URL!
    private var suite: String!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-dev-\(UUID().uuidString)")
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

    func testRecordingTheVirtualPadWritesAFileThatPlaysBack() throws {
        let (developer, input, clock) = make()
        developer.startRecording()
        XCTAssertTrue(developer.isRecording)
        developer.virtual.padMove(to: CGPoint(x: 0.3, y: 0.3))
        clock.advance(by: 0.02)
        developer.virtual.padDown(at: CGPoint(x: 0.3, y: 0.3))
        clock.advance(by: 0.02)
        developer.virtual.padMove(to: CGPoint(x: 0.4, y: 0.35))
        clock.advance(by: 0.02)
        developer.virtual.padUp(at: CGPoint(x: 0.4, y: 0.35))
        let url = try XCTUnwrap(developer.stopRecording(into: folder, now: Date(timeIntervalSince1970: 86_400)))
        XCTAssertFalse(developer.isRecording)
        XCTAssertNil(input.recorder)
        XCTAssertEqual(url.pathExtension, "ndjson")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("pen-1970-01-0"), url.lastPathComponent)
        XCTAssertEqual(developer.lastRecording, url)
        XCTAssertTrue(developer.status?.contains("Saved") == true, developer.status ?? "")

        let recording = try PenRecording(contentsOf: url)
        XCTAssertEqual(recording.header.source, "virtual")
        XCTAssertEqual(recording.header.productID, 0x037A)
        XCTAssertEqual(recording.header.width, 15200)
        XCTAssertEqual(recording.header.quarterTurns, 1)
        XCTAssertEqual(recording.header.created, "1970-01-02T00:00:00Z")
        XCTAssertGreaterThanOrEqual(recording.entries.count, 5)
        XCTAssertEqual(recording.entries.first?.time, 0)
    }

    func testNothingHeardIsNothingSavedAndSaysWhy() {
        let (developer, _, _) = make(developerOn: false)
        developer.startRecording()
        developer.virtual.padMove(to: CGPoint(x: 0.3, y: 0.3))
        XCTAssertNil(developer.stopRecording(into: folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(developer.status?.contains("Nothing was recorded") == true, developer.status ?? "")
        XCTAssertNil(developer.stopRecording(into: folder), "not recording")
    }

    func testAReplayHasToBeHeardAndSaysWhyItWouldNotBe() throws {
        let recording = try PenFixtures.load("stroke")
        let (off, _, _) = make(developerOn: false)
        XCTAssertNil(off.play(recording))
        XCTAssertTrue(off.status?.contains("virtual tablet is off") == true, off.status ?? "")
        XCTAssertFalse(off.canReplay)

        let (on, input, _) = make()
        XCTAssertTrue(on.canReplay)
        XCTAssertNil(on.replayBlocker)
        input.stop()
        XCTAssertFalse(on.canReplay)
        XCTAssertTrue(on.replayBlocker?.contains("Pick a tablet") == true)
        input.start()
        input.pageDisappeared()
        XCTAssertTrue(on.replayBlocker?.contains("on screen") == true, on.replayBlocker ?? "")
        input.policy.realConnected = true
        XCTAssertTrue(on.replayBlocker?.contains("real tablet") == true)
    }

    /// Played from the developer's own entry: on the field it was recorded
    /// on, through the one door, at the speed asked.
    func testPlayingARecordingWritesItsStrokeOnThePage() throws {
        let (developer, input, clock) = make()
        let page = TabletPage(url: nil)
        let scribe = TabletScribe(page: page, input: input)
        input.extent = TabletExtent(width: 20000, height: 12000)
        let replay = try XCTUnwrap(developer.play(try PenFixtures.load("stroke"), speed: 4))
        XCTAssertEqual(input.extent.width, 15200, "the recording's own field is the tablet's")
        clock.advance(by: 5)
        XCTAssertEqual(replay.state, .finished)
        XCTAssertEqual(page.strokes.count, 1)
        withExtendedLifetime(scribe) {}
    }

    func testSteppingFromTheDeveloperHoldsAtTheStart() throws {
        let (developer, input, clock) = make()
        let scribe = TabletScribe(page: TabletPage(url: nil), input: input)
        let replay = try XCTUnwrap(developer.play(try PenFixtures.load("stroke"), stepping: true))
        clock.advance(by: 10)
        XCTAssertEqual(replay.delivered, 0)
        replay.step()
        XCTAssertEqual(replay.delivered, 1)
        developer.stopReplay()
        XCTAssertNil(developer.replay)
        withExtendedLifetime(scribe) {}
    }

    func testAFileThatCannotBePlayedSaysSo() throws {
        let (developer, _, _) = make()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bad = folder.appending(path: "bad.ndjson")
        try Data("not a recording\n".utf8).write(to: bad)
        XCTAssertNil(developer.play(contentsOf: bad))
        XCTAssertTrue(developer.status?.contains("bad.ndjson cannot be played") == true, developer.status ?? "")
        XCTAssertNil(developer.play(contentsOf: folder.appending(path: "missing.ndjson")))
    }

    func testTheRecordingsFolderIsAVisibleOneUnderApplicationSupport() {
        let path = TabletDeveloper.recordingsDirectory.path
        XCTAssertTrue(path.hasSuffix("/WriteMind/PenRecordings"), path)
        XCTAssertFalse(path.contains("/."), "visible data, not a dot-folder")
        XCTAssertTrue(path.contains("WriteMind-test-support"), "the test host keeps its own, never Sean's")
    }

    func testTheFileNameIsTheDate() {
        let name = TabletDeveloper.fileName(at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(name.hasPrefix("pen-19"), name)
        XCTAssertTrue(name.hasSuffix(".ndjson"))
    }
}

/// THE FIXTURES: each a recorded session, replayed through the one door
/// into the page — and the notebook — with the document outcome asserted.
@MainActor
final class PenFixtureReplayTests: XCTestCase {
    private func replayed(_ name: String, target: TabletTarget = .page, notes: Bool = false,
                          speed: Double = PenReplay.asFastAsPossible) throws -> TabletRig {
        let rig = TabletRig(target: target, notes: notes)
        rig.play(try PenFixtures.load(name), speed: speed)
        return rig
    }

    private func assertPoint(_ got: CGPoint, _ x: Double, _ y: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(got.x), x, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(Double(got.y), y, accuracy: 1e-3, file: file, line: line)
    }

    func testTheStrokeIsOneStrokeOfInkOnThePage() throws {
        let rig = try replayed("stroke")
        XCTAssertEqual(rig.page.strokes.count, 1)
        let stroke = try XCTUnwrap(rig.page.strokes.first)
        XCTAssertEqual(stroke.points.count, PenFixtures.line.count)
        for (point, want) in zip(stroke.points, PenFixtures.line) { assertPoint(point, want.0, want.1) }
        XCTAssertNil(rig.input.pen, "the recording ends with the pen leaving")
    }

    /// The pace of the waiting changes nothing about what is written.
    func testTheSameStrokeAtEverySpeed() throws {
        let reference = try XCTUnwrap(try replayed("stroke").page.strokes.first?.points,
                                      "the reference replay writes a stroke — or nothing is compared with nothing")
        XCTAssertEqual(reference.count, PenFixtures.line.count)
        for speed in [0.5, 1, 4, 16] {
            let rig = try replayed("stroke", speed: speed)
            XCTAssertEqual(rig.page.strokes.first?.points, reference, "at \(speed)×")
        }
    }

    func testTheStrokeGoesIntoTheNoteInNotebookMode() throws {
        let rig = try replayed("stroke", target: .notebook, notes: true)
        XCTAssertEqual(rig.notes?.strokes.count, 1)
        XCTAssertEqual(rig.page.strokes, [])
    }

    func testTheBoxSelectIsABoxOnThePage() throws {
        let rig = try replayed("box-select")
        let box = try XCTUnwrap(rig.scribe.box.rect)
        assertPoint(box.origin, 0.2, 0.2)
        XCTAssertEqual(Double(box.width), 0.5, accuracy: 1e-3)
        XCTAssertEqual(Double(box.height), 0.4, accuracy: 1e-3)
        XCTAssertEqual(rig.page.strokes, [])
    }

    func testTheLowerHoldEraseTakesTheLineItCrossed() throws {
        let rig = try replayed("lower-hold-erase")
        XCTAssertEqual(rig.page.strokes, [], "the stroke written first is gone, whole")
        XCTAssertEqual(rig.page.history.count, 2, "the stroke is a step and the erasure is one")
        XCTAssertTrue(rig.page.undo())
        XCTAssertEqual(rig.page.strokes.count, 1, "one ⌘Z brings it back")
    }

    /// What is asserted is what the replay decides — the stroke is in the note
    /// and the eraser's path takes it, by the layer's own touching rule
    /// (`DrawingCanvas.strokesTouched`). How the LAYER makes an erasure one
    /// step back is `TabletEraseLayerTests`' (the rig's `RigNotes` only
    /// stands in for it, so a step count asserted here would test the stand-in).
    func testTheLowerHoldEraseTakesTheNotesStrokeToo() throws {
        let rig = try replayed("lower-hold-erase", target: .notebook, notes: true)
        XCTAssertEqual(rig.notes?.strokes, [])
        let drawn = try replayed("stroke", target: .notebook, notes: true)
        XCTAssertEqual(drawn.notes?.strokes.count, 1, "the same replay minus the eraser leaves its stroke")
    }

    func testTheDoublePressUndoesTheStroke() throws {
        let rig = try replayed("double-press-undo")
        XCTAssertEqual(rig.page.strokes, [])
        XCTAssertTrue(rig.page.canRedo)
        XCTAssertEqual(rig.samples.filter { $0.phase == .click(.lower) }.count, 1)
    }

    func testTheDoublePressUndoesTheNotesStroke() throws {
        let rig = try replayed("double-press-undo", target: .notebook, notes: true)
        XCTAssertEqual(rig.notes?.strokes, [])
        XCTAssertEqual(rig.notes?.store.canRedoDrawing, true)
    }

    func testTheDoubleTapRedoesIt() throws {
        let rig = try replayed("double-tap-redo")
        XCTAssertEqual(rig.page.strokes.count, 1, "undone, then put back")
        XCTAssertFalse(rig.page.canRedo)
        XCTAssertEqual(rig.samples.filter { $0.phase == .click(.lower) }.count, 1)
        XCTAssertEqual(rig.samples.filter { $0.phase == .click(.upper) }.count, 1)
    }

    func testThePressureRampIsARampOfPressures() throws {
        let rig = try replayed("pressure-ramp")
        let pressures = try XCTUnwrap(rig.page.strokes.first?.pressures)
        XCTAssertEqual(pressures.count, 10)
        XCTAssertEqual(pressures.first ?? 0, 0.1, accuracy: 1 / 2047)
        XCTAssertEqual(pressures.last ?? 0, 1, accuracy: 1 / 2047)
        XCTAssertEqual(pressures, pressures.sorted())
        XCTAssertEqual(Set(pressures).count, 10)
    }

    /// A replay is real timing on the virtual clock: the double press of the
    /// lower switch is a command at speed 1 and still at 16×, and it is the
    /// recorded gaps that make it one, not the waiting.
    func testTheDoublePressIsStillACommandAtAnySpeed() throws {
        for speed in [1.0, 16.0, PenReplay.asFastAsPossible] {
            let rig = try replayed("double-press-undo", speed: speed)
            XCTAssertEqual(rig.page.strokes, [], "\(speed)×")
            // Undone, not never written: the stroke was drawn and the command took it back.
            XCTAssertTrue(rig.page.canRedo, "\(speed)×: the stroke is a step to redo")
            XCTAssertEqual(rig.samples.filter { $0.phase == .click(.lower) }.count, 1, "\(speed)×")
        }
    }
}

/// THE FILES ARE WHAT THEIR RECIPES RECORD, so a fixture cannot drift from
/// what it says it is of — and `WRITEMIND_REGENERATE_FIXTURES=1` writes them
/// again (see `PenFixtures`).
@MainActor
final class PenFixtureFilesTests: XCTestCase {
    func testEveryFixtureIsTheBytesItsRecipeRecords() throws {
        for recipe in PenFixtures.recipes {
            let recorded = PenFixtures.record(recipe)
            if PenFixtures.regenerating {
                try recorded.write(to: PenFixtures.url(recipe.name))
                continue
            }
            let onDisk = try Data(contentsOf: PenFixtures.url(recipe.name))
            XCTAssertEqual(String(decoding: onDisk, as: UTF8.self), String(decoding: recorded.ndjson(), as: UTF8.self),
                           "\(recipe.name).ndjson is not what its recipe records — regenerate the fixtures (PenFixtures)")
        }
    }

    /// THE FOLDER, AS DOCUMENTED: every file in it is a whole recording that
    /// replays to its end, the ones with a recipe are their recipe's bytes,
    /// and a recipe with no file is missing one.
    func testTheFolderIsAsItShouldBe() {
        XCTAssertEqual(PenFixtures.problems(), [])
    }

    /// A SESSION RECORDED ON THE REAL TABLET IS JUST ANOTHER FILE IN THE
    /// FOLDER (docs/WACOM-DEV.md): one with no recipe is allowed, and is held
    /// only to being a whole recording that replays.
    func testARecordingWithNoRecipeIsAllowedInTheFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-fixtures-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for recipe in PenFixtures.recipes {
            try FileManager.default.copyItem(at: PenFixtures.url(recipe.name), to: folder.appending(path: "\(recipe.name).ndjson"))
        }
        XCTAssertEqual(PenFixtures.problems(in: folder), [])

        // What the app's Record button writes on the real tablet: the HID
        // source, a date, no note, no recipe.
        var recording = PenFixtures.record(PenFixtures.recipes[0])
        recording.header.source = "hid"
        recording.header.created = "2026-10-03T14:30:05Z"
        recording.header.note = nil
        try recording.write(to: folder.appending(path: "real-tablet-scribble.ndjson"))
        XCTAssertEqual(PenFixtures.problems(in: folder), [], "the suite is not red because somebody added a recording")
    }

    func testAFileInTheFolderThatIsNotAWholeRecordingIsReportedWithItsLine() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-fixtures-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for recipe in PenFixtures.recipes {
            try FileManager.default.copyItem(at: PenFixtures.url(recipe.name), to: folder.appending(path: "\(recipe.name).ndjson"))
        }
        try Data((#"{"format":"writemind-pen-stream","version":1}"# + "\n" + #"{"report":"02 zz","t":0}"# + "\n").utf8)
            .write(to: folder.appending(path: "half-written.ndjson"))
        try Data(#"{"format":"writemind-pen-stream","version":1}"#.utf8).write(to: folder.appending(path: "empty.ndjson"))
        let problems = PenFixtures.problems(in: folder)
        XCTAssertEqual(problems.count, 2, "\(problems)")
        XCTAssertTrue(problems.contains { $0.hasPrefix("half-written.ndjson: line 2") }, "\(problems)")
        XCTAssertTrue(problems.contains { $0.hasPrefix("empty.ndjson: no events") }, "\(problems)")
    }

    func testAFileWithARecipeThatHasDriftedFromItIsReported() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-fixtures-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for recipe in PenFixtures.recipes {
            try FileManager.default.copyItem(at: PenFixtures.url(recipe.name), to: folder.appending(path: "\(recipe.name).ndjson"))
        }
        let drifted = folder.appending(path: "stroke.ndjson")
        let text = try String(contentsOf: drifted, encoding: .utf8)
        try text.replacingOccurrences(of: #""t":0.008"#, with: #""t":0.009"#).write(to: drifted, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: folder.appending(path: "pressure-ramp.ndjson"))
        let problems = PenFixtures.problems(in: folder)
        XCTAssertTrue(problems.contains { $0.hasPrefix("stroke.ndjson: not what its recipe records") }, "\(problems)")
        XCTAssertTrue(problems.contains { $0.hasPrefix("pressure-ramp.ndjson: a recipe with no file") }, "\(problems)")
    }

    func testEveryFixtureIsSmall() throws {
        for recipe in PenFixtures.recipes {
            let size = try Data(contentsOf: PenFixtures.url(recipe.name)).count
            XCTAssertLessThan(size, 16_000, "\(recipe.name).ndjson is \(size) bytes")
        }
    }

    func testEveryFixtureIsRawReportsOfTheSmallOneByWacom() throws {
        for recipe in PenFixtures.recipes {
            let recording = try PenFixtures.load(recipe.name)
            XCTAssertEqual(recording.header.productID, 0x037A)
            XCTAssertEqual(recording.header.source, "virtual")
            XCTAssertEqual(recording.header.note, recipe.note)
            XCTAssertNil(recording.header.created, "a fixture is the same bytes however often it is made")
            XCTAssertFalse(recording.entries.isEmpty)
            for entry in recording.entries {
                guard case .report(let bytes) = entry.event else { return XCTFail("\(recipe.name): a reading") }
                XCTAssertNotNil(WacomPenPacket(bytes), "\(recipe.name): \(WacomPenPacket.hex(bytes))")
            }
        }
    }
}
