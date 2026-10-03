import XCTest
@testable import WriteMind

/// A FILE IS NOT TRUSTED: hand-edited, cut short or somebody else's, it may say
/// anything, and what it says goes into the pen's arithmetic. None of it can
/// trap — a number that cannot be a tablet's is the file refused whole, with
/// its line — and a number that got in some other way is clamped before it
/// becomes an Int.
@MainActor
final class PenRecordingHostileFileTests: XCTestCase {
    private let header = #"{"format":"writemind-pen-stream","version":1,"width":15200,"height":9500}"#
    private let hover = #"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":0}"#

    private func ndjson(_ lines: String...) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

    private func assertRefused(_ data: Data, atLine line: Int, containing word: String,
                               file: StaticString = #filePath, lineNumber: UInt = #line) {
        XCTAssertThrowsError(try PenRecording(ndjson: data), file: file, line: lineNumber) {
            guard case PenRecording.Failure.line(let number, let why) = $0 else {
                return XCTFail("\($0)", file: file, line: lineNumber)
            }
            XCTAssertEqual(number, line, "the line it is on", file: file, line: lineNumber)
            XCTAssertTrue(why.contains(word), why, file: file, line: lineNumber)
        }
    }

    /// A field no tablet has is refused at the header's line: an enormous one
    /// went straight into the pad's arithmetic and the first move trapped.
    func testAHeaderWhoseFieldIsNotATabletsIsRefusedAtItsLine() {
        for field in [#""width":1e30,"height":9500"#, #""width":15200,"height":1e30"#, #""width":70000,"height":9500"#,
                      #""width":0,"height":9500"#, #""width":-15200,"height":9500"#, #""width":15200"#,
                      #""height":9500"#] {
            let header = #"{"format":"writemind-pen-stream","version":1,"# + field + "}"
            assertRefused(ndjson(header, hover), atLine: 1, containing: "field")
        }
        XCTAssertNoThrow(try PenRecording(ndjson: ndjson(header, hover)), "a real tablet's is fine")
        XCTAssertNoThrow(try PenRecording(ndjson: ndjson(
            #"{"format":"writemind-pen-stream","version":1,"width":65535,"height":1}"#, hover)), "the largest a report can count")
    }

    func testAHeaderMadeInMemoryGivesNoFieldWhenItIsNotATabletsEither() {
        for (width, height) in [(1e30, 9500.0), (15200, Double.infinity), (Double.nan, 9500), (-1, 9500), (0, 0), (65536, 100)] {
            var header = PenRecording.Header()
            header.width = width
            header.height = height
            XCTAssertNil(header.extent, "\(width) x \(height)")
        }
        var fine = PenRecording.Header()
        fine.width = 65535
        fine.height = 65535
        XCTAssertNotNil(fine.extent)
    }

    func testAnEventThatCannotBeATabletsIsRefusedAtItsLine() {
        let cases: [(String, String)] = [
            (#"{"reading":{"kind":"point","x":1e30,"y":5,"tip":false,"pressure":0,"native":true},"t":0.1}"#, "place"),
            (#"{"reading":{"kind":"point","x":5,"y":-1,"tip":false,"pressure":0,"native":true},"t":0.1}"#, "place"),
            (#"{"reading":{"kind":"point","x":5,"y":70000,"tip":false,"pressure":0,"native":true},"t":0.1}"#, "place"),
            (#"{"reading":{"kind":"point","x":5,"y":5,"tip":true,"pressure":5,"native":true},"t":0.1}"#, "pressure"),
            (#"{"reading":{"kind":"point","x":5,"y":5,"tip":true,"pressure":-0.5,"native":true},"t":0.1}"#, "pressure"),
            (#"{"report":"02 e0","t":0.1}"#, "pen report"),
            (#"{"report":"03 e0 b0 1d 8e 12 00 00 14 00","t":0.1}"#, "pen report"),
            (#"{"report":"02 e0 b0 1d 8e 12 00 00 14 00 00","t":0.1}"#, "pen report"),
            (#"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":-1}"#, "time"),
            (#"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":1e12}"#, "time"),
            (#"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":86401}"#, "time"),
        ]
        for (event, word) in cases {
            assertRefused(ndjson(header, hover, event), atLine: 3, containing: word)
        }
        XCTAssertNoThrow(try PenRecording(ndjson: ndjson(
            header, hover, #"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":86400}"#)), "a day is the longest")
    }

    func testTimeNeverGoesBackwards() {
        assertRefused(ndjson(header, #"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":0.5}"#,
                           #"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":0.25}"#), atLine: 3, containing: "before")
        XCTAssertNoThrow(try PenRecording(ndjson: ndjson(
            header, #"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":0.5}"#,
            #"{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":0.5}"#)), "two events at one moment are fine")
    }

    /// Whatever number reaches the report, it is a report: a count past the
    /// two bytes is the edge, a pressure past full is full.
    func testAFrameOfAnyMagnitudeIsAReport() {
        for huge in [1e30, 9.3e18, Double(Int.max), -1e30, -9.3e18, Double.infinity, -Double.infinity, Double.nan, 70000, -3] {
            let frame = PenFrame(counts: CGPoint(x: huge, y: huge), tip: true, pressure: huge)
            let report = frame.report
            XCTAssertEqual(report.count, 10, "\(huge)")
            XCTAssertNotNil(WacomPenPacket(report), "\(huge)")
            _ = WacomPenPacket(frame)
            _ = frame.reading(at: 1)
        }
        let past = PenFrame(counts: CGPoint(x: 1e30, y: 9.3e18), pressure: 1e30).report
        XCTAssertEqual(Array(past[2...5]), [0xFF, 0xFF, 0xFF, 0xFF], "the edge of the field")
        XCTAssertEqual(Int(past[6]) | Int(past[7]) << 8, 2047, "full pressure")
        let before = PenFrame(counts: CGPoint(x: -1e30, y: -9.3e18), pressure: -1e30).report
        XCTAssertEqual(Array(before[2...7]), [0, 0, 0, 0, 0, 0])
    }

    func testAFieldThatIsNotANumberWidensNothing() {
        let field = TabletExtent(width: 15200, height: 9500)
        XCTAssertEqual(field.widened(toInclude: CGPoint(x: Double.infinity, y: Double.nan)), field)
        XCTAssertEqual(field.widened(toInclude: CGPoint(x: 16000, y: Double.infinity)).width, 16000)
        XCTAssertEqual(field.widened(toInclude: CGPoint(x: 16000, y: Double.infinity)).height, 9500)
    }

    /// A recording that never went through a file — made in memory, its
    /// header and its places as hostile as can be — is played and the pad is
    /// moved on it: nothing traps, and the pen's field is not the header's.
    func testAHostileRecordingMadeInMemoryPlaysAndTheNextMoveOnThePadDoesNotTrap() throws {
        let rig = TabletRig()
        var header = PenRecording.Header()
        header.width = 1e30
        header.height = 1e30
        let far = TabletReading(kind: .point(counts: CGPoint(x: 1e30, y: 1e30), tip: false, switches: [],
                                             pressure: 1e30, buttons: 0), timestamp: 0, native: true)
        let recording = PenRecording(header: header, entries: [PenStreamEntry(time: 0, event: .reading(far)),
                                                              PenStreamEntry(time: 0.01, event: .reading(far))])
        let before = rig.input.extent
        let replay = rig.play(recording, speed: PenReplay.asFastAsPossible)
        XCTAssertEqual(replay.state, .finished)
        XCTAssertNil(header.extent)
        // The funnel's field widened to what the driver's reading said (finite),
        // and the pad moved on it makes a report all the same.
        XCTAssertGreaterThanOrEqual(rig.input.extent.width, before.width)
        let tablet = VirtualTablet(clock: rig.clock)
        tablet.geometry = { [unowned rig] in (rig.input.extent, rig.input.quarterTurns) }
        var reports: [PenFrame] = []
        tablet.pen.onFrame = { frame, _ in reports.append(frame) }
        tablet.padMove(to: CGPoint(x: 1, y: 1))
        tablet.padDown(at: CGPoint(x: 0.5, y: 0.5))
        let report = try XCTUnwrap(reports.last).report
        XCTAssertEqual(report.count, 10)
        XCTAssertNotNil(WacomPenPacket(report))
    }

    func testTheClockIsNeverAskedToWaitLongerThanADay() {
        XCTAssertEqual(LivePenClock.bounded(0.25), 0.25)
        XCTAssertEqual(LivePenClock.bounded(1e30), PenRecording.longestTime)
        XCTAssertEqual(LivePenClock.bounded(Double.greatestFiniteMagnitude), PenRecording.longestTime)
        XCTAssertEqual(LivePenClock.bounded(-5), 0)
        XCTAssertEqual(LivePenClock.bounded(Double.infinity), 0, "not a wait")
        XCTAssertEqual(LivePenClock.bounded(Double.nan), 0, "not a wait")
    }
}
