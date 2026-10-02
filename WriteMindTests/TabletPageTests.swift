import AppKit
import Combine
import XCTest
@testable import WriteMind

func assertRect(_ rect: CGRect?, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
    guard let rect else { return XCTFail("no rect", file: file, line: line) }
    for (got, want) in [(rect.minX, expected.minX), (rect.minY, expected.minY),
                        (rect.width, expected.width), (rect.height, expected.height)] {
        XCTAssertEqual(got, want, accuracy: 1e-9, "\(rect) is not \(expected)", file: file, line: line)
    }
}

/// A stroke on the page: page fractions, a width in page points, ink.
func pageStroke(_ points: [CGPoint], width: Double = 4, colorHex: String = "#2D7DD2",
                pressures: [Double]? = nil, tool: InkTool = .pen) -> Stroke {
    Stroke(colorHex: colorHex, width: width, points: points,
           pressures: pressures ?? Array(repeating: 0.5, count: points.count), tool: tool)
}

/// The page the tablet writes on, as a model: one step back a stroke,
/// clear as one step, kept in Application Support and never wiped, and
/// turned with the tablet rather than stretched.
@MainActor
final class TabletPageTests: XCTestCase {
    private var dir: URL!
    private var file: URL { dir.appending(path: "TabletPage.json") }

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-page-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private let a = pageStroke([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.15)])
    private let b = pageStroke([CGPoint(x: 0.5, y: 0.5)], pressures: [0.9])

    func testEachStrokeIsOneStepBackAndForth() {
        let page = TabletPage(url: nil)
        page.commit(a)
        page.commit(b)
        XCTAssertEqual(page.strokes, [a, b])
        XCTAssertTrue(page.undo())
        XCTAssertEqual(page.strokes, [a], "one stroke, one step")
        XCTAssertTrue(page.undo())
        XCTAssertEqual(page.strokes, [])
        XCTAssertFalse(page.undo(), "nothing left to take back")
        XCTAssertTrue(page.redo())
        XCTAssertTrue(page.redo())
        XCTAssertEqual(page.strokes, [a, b])
        XCTAssertFalse(page.redo())
    }

    func testWritingAfterAnUndoDropsWhatWasUndone() {
        let page = TabletPage(url: nil)
        page.commit(a)
        page.commit(b)
        page.undo()
        page.commit(b)
        XCTAssertFalse(page.canRedo)
        XCTAssertEqual(page.strokes, [a, b])
    }

    func testClearingIsOneStepAndABlankPageIsNone() {
        let page = TabletPage(url: nil)
        page.clear()
        XCTAssertFalse(page.canUndo, "clearing a blank page did nothing and is no step")
        page.commit(a)
        page.commit(b)
        page.clear()
        XCTAssertEqual(page.strokes, [])
        XCTAssertTrue(page.undo())
        XCTAssertEqual(page.strokes, [a, b], "Undo brings the whole page back at once")
    }

    func testThePageIsThereWhenTheAppComesBackPressureToolAndAll() throws {
        let page = TabletPage(url: file)
        let fountain = pageStroke([CGPoint(x: 0.3, y: 0.4), CGPoint(x: 0.31, y: 0.42)],
                                  pressures: [0.2, 0.8], tool: .fountain)
        page.commit(a)
        page.commit(fountain)
        page.flush()
        let back = TabletPage(url: file)
        XCTAssertEqual(back.strokes, [a, fountain])
        XCTAssertEqual(back.strokes.last?.pressures, [0.2, 0.8])
        XCTAssertEqual(back.strokes.last?.tool, .fountain)
        XCTAssertNil(back.setAside)
        XCTAssertFalse(back.canUndo, "the history is the session's, not the file's")
    }

    /// Saved once the pen rests, not on every stroke — and not lost.
    func testTheSaveWaitsForThePenToRest() async throws {
        let page = TabletPage(url: file)
        page.commit(a)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "not written under the pen")
        for _ in 0..<60 where !FileManager.default.fileExists(atPath: file.path) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "written once it rested")
        XCTAssertEqual(TabletPage.load(from: file).sheet.strokes, [a])
    }

    /// A BAD FILE IS SET ASIDE, NEVER WIPED: moved to .corrupt-<date>,
    /// bytes and all, and the page starts blank — and the next save does
    /// not touch it.
    func testAFileThatIsNotAPageIsSetAsideNotWrittenOver() throws {
        let garbage = Data("{ this is not a page".utf8)
        try garbage.write(to: file)
        let page = TabletPage(url: file)
        XCTAssertEqual(page.strokes, [])
        let aside = try XCTUnwrap(page.setAside)
        XCTAssertTrue(aside.lastPathComponent.hasPrefix("TabletPage.corrupt-"), aside.lastPathComponent)
        XCTAssertEqual(aside.pathExtension, "json")
        XCTAssertEqual(try Data(contentsOf: aside), garbage, "set aside as it was")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        page.commit(a)
        page.flush()
        XCTAssertEqual(TabletPage.load(from: file).sheet.strokes, [a])
        XCTAssertEqual(try Data(contentsOf: aside), garbage, "and left alone after")
    }

    /// One stroke that will not read costs that stroke and nothing else —
    /// and the file as it was is kept beside the page.
    func testAStrokeThatWillNotReadIsLeftOutAndTheFileKeptBeside() throws {
        let encoder = JSONEncoder()
        let good = try XCTUnwrap(String(data: encoder.encode(a), encoding: .utf8))
        let other = try XCTUnwrap(String(data: encoder.encode(b), encoding: .utf8))
        let json = "{\"version\":1,\"quarterTurns\":1,\"strokes\":[\(good),{\"colorHex\":7},\(other)]}"
        try Data(json.utf8).write(to: file)
        let page = TabletPage(url: file)
        XCTAssertEqual(page.strokes, [a, b])
        let aside = try XCTUnwrap(page.setAside)
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), json)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "copied, not moved: the page is still there")
    }

    /// Once the file as it was is beside the page, the strokes that read
    /// are written back over it — so a page nobody writes on is not copied
    /// aside again on every launch.
    func testAPartReadPageIsSetAsideOnceAndThenWrittenClean() throws {
        let encoder = JSONEncoder()
        let good = try XCTUnwrap(String(data: encoder.encode(a), encoding: .utf8))
        let other = try XCTUnwrap(String(data: encoder.encode(b), encoding: .utf8))
        try Data("{\"version\":1,\"quarterTurns\":1,\"strokes\":[\(good),{\"colorHex\":7},\(other)]}".utf8).write(to: file)
        let first = TabletPage(url: file)
        XCTAssertNotNil(first.setAside)
        first.flush()
        let second = TabletPage(url: file)
        XCTAssertNil(second.setAside, "copied aside a second time")
        XCTAssertEqual(second.strokes, [a, b])
        let asides = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".corrupt-") }
        XCTAssertEqual(asides.count, 1, "\(asides)")
    }

    /// QUITTING WAITS FOR THE SAVE ALREADY ON ITS WAY. The pen rested, the
    /// save went to the disk's queue, and ⌘Q came before it landed: the
    /// flush on the way out waits for it, or the app exits under it and
    /// every stroke since the save before is gone.
    func testTheFlushOnQuittingWaitsForASaveAlreadyOnItsWay() async throws {
        let page = TabletPage(url: file)
        let disk = DispatchSemaphore(value: 0)
        page.queue.async { disk.wait() }
        page.commit(a)
        // The pen rests; the save is handed over, and waits behind the
        // busy disk.
        try await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { disk.signal() }
        page.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the flush returned before the save it had sent")
        XCTAssertEqual(TabletPage.load(from: file).sheet.strokes, [a])
    }

    /// A SAVE NEVER CLOBBERS (AGENTS.md): the page writes its file only
    /// while the bytes there are the ones it last read or wrote. Something
    /// else wrote it since — a second copy of the app — and that is left as
    /// it is; this page goes beside it, and keeps going there.
    func testAPageWrittenBySomethingElseIsNotWrittenOver() throws {
        let page = TabletPage(url: file)
        page.commit(a)
        page.flush()
        let theirs = try JSONEncoder().encode(TabletSheet(strokes: [b], quarterTurns: 1))
        try theirs.write(to: file)
        let c = pageStroke([CGPoint(x: 0.7, y: 0.7)])
        page.commit(c)
        page.flush()
        XCTAssertEqual(try Data(contentsOf: file), theirs, "the other writer's page was written over")
        let beside = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".conflict-") }
        XCTAssertEqual(beside.count, 1, "\(beside)")
        guard let name = beside.first else { return }
        XCTAssertEqual(TabletPage.load(from: dir.appending(path: name)).sheet.strokes, [a, c])
        page.clear()
        page.flush()
        XCTAssertEqual(try Data(contentsOf: file), theirs, "a later save went back to the file")
        XCTAssertEqual(TabletPage.load(from: dir.appending(path: name)).sheet.strokes, [])
    }

    /// A COPY OF THE APP THAT IS NOT THIS ONE KEEPS A PAGE OF ITS OWN. A
    /// scratch build driven to check something is given a bundle id of its
    /// own, and Application Support is found by the app's NAME — so it
    /// opened Sean's page, and a stroke or a clear there wrote over it.
    func testAnotherBuildOfTheAppKeepsAPageOfItsOwn() {
        XCTAssertEqual(TabletPage.fileName(bundleID: "com.seancheren.WriteMind"), "TabletPage.json")
        let scratch = TabletPage.fileName(bundleID: "com.seancheren.WriteMindScratch")
        XCTAssertNotEqual(scratch, "TabletPage.json")
        XCTAssertTrue(scratch.hasPrefix("TabletPage-") && scratch.hasSuffix(".json"), scratch)
        XCTAssertNotEqual(TabletPage.fileName(bundleID: nil), "TabletPage.json")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.seancheren.WriteMind", "the test host is the app")
    }

    func testAnOlderOrEmptyFileOpensAsItIs() throws {
        try Data("{}".utf8).write(to: file)
        let blank = TabletPage(url: file)
        XCTAssertEqual(blank.strokes, [])
        XCTAssertNil(blank.setAside)
        let stroke = try XCTUnwrap(String(data: JSONEncoder().encode(a), encoding: .utf8))
        try Data("{\"strokes\":[\(stroke)]}".utf8).write(to: file)
        let old = TabletPage.load(from: file)
        XCTAssertEqual(old.sheet.strokes, [a])
        XCTAssertEqual(old.sheet.quarterTurns, 1)
        XCTAssertEqual(old.sheet.theme, .plain, "a page from before there were papers is plain")
        XCTAssertNil(old.setAside)
    }

    /// THE PAPER IS THE PAGE'S, saved with it — and a change of paper is
    /// not a step back: nothing was written.
    func testThePaperIsKeptWithThePage() throws {
        let page = TabletPage(url: file)
        XCTAssertEqual(page.theme, .plain)
        page.commit(a)
        page.setTheme(.legal)
        XCTAssertEqual(page.theme, .legal)
        XCTAssertEqual(page.history.count, 1, "the stroke is a step; the paper is not")
        page.flush()
        let back = TabletPage(url: file)
        XCTAssertEqual(back.theme, .legal)
        XCTAssertEqual(back.strokes, [a])
        let json = try XCTUnwrap(String(data: Data(contentsOf: file), encoding: .utf8))
        XCTAssertTrue(json.contains("\"theme\":\"legal\""), json)
    }

    /// A paper this build does not know opens as plain and costs the page
    /// nothing else — no stroke lost, nothing set aside.
    func testAPaperThisBuildDoesNotKnowOpensPlain() throws {
        let stroke = try XCTUnwrap(String(data: JSONEncoder().encode(a), encoding: .utf8))
        try Data("{\"version\":1,\"quarterTurns\":1,\"theme\":\"isometric\",\"strokes\":[\(stroke)]}".utf8)
            .write(to: file)
        let page = TabletPage(url: file)
        XCTAssertEqual(page.theme, .plain)
        XCTAssertEqual(page.strokes, [a])
        XCTAssertNil(page.setAside)
    }

    /// Never in ~/Documents/WriteMind, which is Sean's notes; in the test
    /// host, in the test host's own support folder.
    func testThePageIsKeptInApplicationSupportNeverWithTheNotes() throws {
        let url = try XCTUnwrap(TabletPage.defaultURL)
        XCTAssertEqual(url.lastPathComponent, "TabletPage.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "WriteMind")
        XCTAssertTrue(url.path.hasPrefix(TestHost.supportDirectory.path), url.path)
        XCTAssertFalse(url.path.hasPrefix(NoteStore.defaultDirectory().path))
    }

    /// TURNING THE TABLET TURNS THE INK, and each stroke stays where it is
    /// ON THE TABLET: a point written with the tablet one way round is the
    /// page point the same counts give the next way round.
    func testTurningTheSheetKeepsTheInkWhereItIsOnTheTablet() {
        let extent = TabletExtent(width: 15200, height: 9500)
        let counts = [CGPoint(x: 0, y: 0), CGPoint(x: 15200, y: 0), CGPoint(x: 3800, y: 2375),
                      CGPoint(x: 12000, y: 9000), CGPoint(x: 7600, y: 4750)]
        for turns in 0..<4 {
            for count in counts {
                let before = TabletMapping.page(count, extent: extent, quarterTurns: turns)
                for by in 1..<4 {
                    let after = TabletMapping.page(count, extent: extent, quarterTurns: turns + by)
                    let turned = TabletPage.turned(before, by: by)
                    XCTAssertEqual(turned.x, after.x, accuracy: 1e-9, "turn \(turns) by \(by) at \(count)")
                    XCTAssertEqual(turned.y, after.y, accuracy: 1e-9, "turn \(turns) by \(by) at \(count)")
                }
            }
        }
    }

    func testTurningKeepsPressuresGivesNewIdsAndTurnsTheHistoryToo() {
        let page = TabletPage(url: nil)
        page.commit(a)
        page.commit(b)
        let historyBefore = page.history.count
        page.align(to: 2)
        XCTAssertEqual(page.history.count, historyBefore, "a turn is not a step back")
        XCTAssertEqual(page.strokes.map(\.points), [a, b].map { $0.points.map { TabletPage.turned($0, by: 1) } })
        XCTAssertEqual(page.strokes.map(\.pressures), [a.pressures, b.pressures])
        XCTAssertFalse(page.strokes.contains { $0.id == a.id || $0.id == b.id },
                       "rewritten points under the old id would be served from the ink cache stale")
        page.undo()
        XCTAssertEqual(page.strokes.map(\.points), [a.points.map { TabletPage.turned($0, by: 1) }],
                       "Undo brings back the page as it was — turned the way it is now")
        page.align(to: 1)
        let back = page.strokes.first?.points ?? []
        XCTAssertEqual(back.count, a.points.count)
        for (turned, original) in zip(back, a.points) {
            XCTAssertEqual(turned.x, original.x, accuracy: 1e-12, "and turned back is where it started")
            XCTAssertEqual(turned.y, original.y, accuracy: 1e-12)
        }
    }

    func testAPageSavedOneWayRoundOpensTurnedToMatch() {
        let page = TabletPage(url: file)
        page.commit(a)
        page.flush()
        let back = TabletPage(url: file)
        back.align(to: 0)
        XCTAssertEqual(back.strokes.first?.points, a.points.map { TabletPage.turned($0, by: 3) })
        back.flush()
        XCTAssertEqual(TabletPage.load(from: file).sheet.quarterTurns, 0, "and is saved the new way round")
    }

    /// The page's own points: the long side is always the same, so a stroke
    /// keeps its size when the sheet turns from tall to wide.
    func testThePageIsTheSameSizeWhicheverWayItIsTurned() {
        XCTAssertEqual(TabletPage.size(aspect: 0.625), CGSize(width: 500, height: 800))
        XCTAssertEqual(TabletPage.size(aspect: 1.6), CGSize(width: 800, height: 500))
        XCTAssertEqual(TabletPage.size(aspect: .nan), CGSize(width: 800, height: 800))
    }
}

/// The rule from samples to ink and boxes, sample by sample.
final class TabletWritingTests: XCTestCase {
    private let ink = TabletInk(colorHex: "#F2542D", width: 5)

    private func sample(_ x: CGFloat, _ y: CGFloat, _ phase: TabletSample.Phase, pressure: Double = 0.5,
                        side: Bool = false) -> TabletSample {
        TabletSample(page: CGPoint(x: x, y: y), pressure: pressure, phase: phase, sideSwitch: side,
                     inProximity: true, timestamp: 0)
    }

    func testNibDownToNibUpIsOneStrokeWithAPressureAPoint() throws {
        var writing = TabletWriting()
        XCTAssertEqual(writing.consume(sample(0.1, 0.1, .hover, pressure: 0), ink: ink), .none)
        XCTAssertEqual(writing.consume(sample(0.1, 0.1, .down, pressure: 0.3), ink: ink), .began)
        XCTAssertEqual(writing.consume(sample(0.12, 0.1, .drag, pressure: 0.6), ink: ink), .grew)
        XCTAssertEqual(writing.consume(sample(0.14, 0.11, .drag, pressure: 0.7), ink: ink), .grew)
        guard case .finished(let stroke) = writing.consume(sample(0.14, 0.11, .up, pressure: 0), ink: ink) else {
            return XCTFail("the up finishes the stroke")
        }
        XCTAssertEqual(stroke.points, [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.12, y: 0.1), CGPoint(x: 0.14, y: 0.11)],
                       "the lift is not a point")
        XCTAssertEqual(stroke.pressures, [0.3, 0.6, 0.7])
        XCTAssertEqual(stroke.tool, .pen)
        XCTAssertEqual(stroke.colorHex, "#F2542D")
        XCTAssertEqual(stroke.width, 5)
        XCTAssertNil(writing.stroke)
    }

    /// A TAP IS A DOT (Sean's i's and full stops): one point, which the ink
    /// draws round.
    func testATapIsADot() throws {
        var writing = TabletWriting()
        _ = writing.consume(sample(0.5, 0.5, .down, pressure: 0.8), ink: ink)
        guard case .finished(let dot) = writing.consume(sample(0.5, 0.5, .up, pressure: 0), ink: ink) else {
            return XCTFail("a tap is a stroke")
        }
        XCTAssertEqual(dot.points.count, 1)
        let size = TabletPage.size(aspect: 0.625)
        let path = InkPaths.path(for: dot, points: CanvasItem.stroke(dot).basePoints(in: size)).path
        let box = path.boundingRect
        XCTAssertGreaterThan(box.width, 2, "a dot you can see")
        XCTAssertEqual(box.width, box.height, accuracy: box.width * 0.2, "round, not a dash")
        XCTAssertEqual(box.midX, 0.5 * size.width, accuracy: 1)
    }

    private func assertBox(_ outcome: TabletWriting.Outcome, done: Bool, _ expected: CGRect,
                           file: StaticString = #filePath, line: UInt = #line) {
        let rect: CGRect
        switch outcome {
        case .boxing(let box) where !done: rect = box
        case .boxed(let box) where done: rect = box
        default: return XCTFail("\(outcome)", file: file, line: line)
        }
        assertRect(rect, expected, file: file, line: line)
    }

    func testTheSideSwitchDrawsABoxAndNoInk() {
        var writing = TabletWriting()
        XCTAssertEqual(writing.consume(sample(0.2, 0.3, .down, side: true), ink: ink), .none)
        XCTAssertNil(writing.stroke)
        assertBox(writing.consume(sample(0.6, 0.5, .drag, side: true), ink: ink), done: false,
                  CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2))
        // Dragged back up and left past where it began: the box flips.
        assertBox(writing.consume(sample(0.1, 0.1, .drag, side: true), ink: ink), done: false,
                  CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.2))
        assertBox(writing.consume(sample(0.7, 0.9, .up, side: true), ink: ink), done: true,
                  CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.6))
        XCTAssertNil(writing.stroke, "no ink came of it")
    }

    func testASideSwitchThatDoesNotMoveIsAClick() {
        var writing = TabletWriting()
        _ = writing.consume(sample(0.2, 0.3, .down, side: true), ink: ink)
        XCTAssertEqual(writing.consume(sample(0.203, 0.302, .drag, side: true), ink: ink), .none,
                       "a wobble under the slop is not a box yet")
        XCTAssertEqual(writing.consume(sample(0.204, 0.302, .up, side: true), ink: ink), .clicked)
    }

    func testABoxStaysOnThePage() {
        assertRect(TabletWriting.box(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 1.3, y: -0.2)),
                   CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    /// A 3-POINT PEN WRITES 3 POINTS WHERE IT IS SEEN WRITING: on a page
    /// shown at half its own size, its width in page points is double.
    func testThePenWritesTheMenusWidthAsItIsSeen() {
        XCTAssertEqual(TabletInk.width(penWidth: 3, viewScale: 0.5), 6)
        XCTAssertEqual(TabletInk.width(penWidth: 3, viewScale: 1.5), 2)
        XCTAssertEqual(TabletInk.width(penWidth: 3, viewScale: 0), 3, "no page on screen yet: as it is")
        let ink = TabletPane.ink(colorHex: "#1C1C1E", penWidth: 3, viewScale: 0.84)
        XCTAssertEqual(ink.width * 0.84, 3, accuracy: 1e-9)
        XCTAssertEqual(ink.tool, .pen)
        XCTAssertEqual(TabletPane.ink(colorHex: "#1C1C1E", penWidth: 3, tool: .fountain, viewScale: 1).tool, .fountain,
                       "the page's pen writes with the tool on its bar")
    }

    /// A stroke takes the page's pen as it stands when the nib goes down —
    /// tool, colour, width — and keeps it: a change on the bar mid-stroke,
    /// or after, is the NEXT stroke's.
    func testAStrokeKeepsThePenItWasBegunWith() throws {
        var writing = TabletWriting()
        let marker = TabletInk(colorHex: "#2FBF71", width: 6, tool: .marker)
        let pencil = TabletInk(colorHex: "#1C1C1E", width: 1, tool: .pencil)
        _ = writing.consume(sample(0.1, 0.1, .down), ink: marker)
        _ = writing.consume(sample(0.2, 0.1, .drag), ink: pencil)
        guard case .finished(let stroke) = writing.consume(sample(0.2, 0.1, .up), ink: pencil) else {
            return XCTFail("the up finishes the stroke")
        }
        XCTAssertEqual(stroke.tool, .marker)
        XCTAssertEqual(stroke.colorHex, "#2FBF71")
        XCTAssertEqual(stroke.width, 6)
        XCTAssertEqual(stroke.pressures?.count, stroke.points.count)
    }

    /// The pen lifted off the tablet with the nib still down finishes the
    /// stroke — through the funnel's own state machine.
    func testThePenLeavingMidStrokeFinishesIt() {
        var pen = TabletPen()
        var extent = TabletExtent(width: 100, height: 100)
        var writing = TabletWriting()
        var outcomes: [TabletWriting.Outcome] = []
        let readings = [
            TabletReading(kind: .point(counts: CGPoint(x: 10, y: 10), tip: true, sideSwitch: false,
                                       pressure: 0.4, buttons: 1), timestamp: 1, native: false),
            TabletReading(kind: .point(counts: CGPoint(x: 20, y: 10), tip: true, sideSwitch: false,
                                       pressure: 0.5, buttons: 1), timestamp: 2, native: false),
            TabletReading(kind: .proximity(entering: false), timestamp: 3, native: false),
        ]
        for reading in readings {
            for sample in pen.consume(reading, extent: &extent, quarterTurns: 0) {
                outcomes.append(writing.consume(sample, ink: ink))
            }
        }
        XCTAssertEqual(outcomes.count, 4)
        guard case .finished(let stroke) = outcomes[2] else { return XCTFail("\(outcomes)") }
        XCTAssertEqual(stroke.points.count, 2)
        XCTAssertEqual(outcomes[3], .none, "the leaving itself writes nothing")
    }
}

/// The shell: the funnel's stream onto the page, the live stroke apart
/// from the page, and the box.
@MainActor
final class TabletScribeTests: XCTestCase {
    private func point(_ x: CGFloat, _ y: CGFloat, tip: Bool, side: Bool = false, pressure: Double = 0.5,
                       at time: TimeInterval) -> TabletReading {
        TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: tip, sideSwitch: side, pressure: pressure,
                                   buttons: (tip ? 1 : 0) | (side ? 2 : 0)),
                      timestamp: time, native: false)
    }

    private func rig() -> (TabletInput, TabletPage, TabletScribe) {
        let input = TabletInput()
        input.extent = TabletExtent(width: 15200, height: 9500)
        input.quarterTurns = 1
        let page = TabletPage(url: nil)
        return (input, page, TabletScribe(page: page, input: input))
    }

    func testThePensSamplesBecomeAStrokeOnThePage() throws {
        let (input, page, scribe) = rig()
        var written = 0
        scribe.onWrite = { written += 1 }
        input.feed(point(3800, 2375, tip: false, at: 1))
        input.feed(point(3800, 2375, tip: true, pressure: 0.25, at: 2))
        input.feed(point(7600, 4750, tip: true, pressure: 0.75, at: 3))
        XCTAssertEqual(page.strokes, [], "nothing on the page while the nib is down")
        XCTAssertEqual(scribe.stroke?.points.count, 2, "the stroke is live on its own")
        input.feed(point(7600, 4750, tip: false, at: 4))
        let stroke = try XCTUnwrap(page.strokes.first)
        XCTAssertNil(scribe.stroke)
        XCTAssertEqual(written, 1)
        // Through the quarter turn: (1 − y/H, x/W).
        XCTAssertEqual(stroke.points, [CGPoint(x: 0.75, y: 0.25), CGPoint(x: 0.5, y: 0.5)])
        XCTAssertEqual(stroke.pressures, [0.25, 0.75])
        XCTAssertEqual(stroke.tool, .pen)
    }

    func testTheSideSwitchDrawsTheBoxAndTheNibPutsItAway() {
        let (input, page, scribe) = rig()
        input.feed(point(0, 0, tip: false, side: true, at: 1))
        input.feed(point(7600, 4750, tip: false, side: true, at: 2))
        input.feed(point(7600, 4750, tip: false, side: false, at: 3))
        assertRect(scribe.box.rect, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(page.strokes, [], "a box is not ink")
        input.feed(point(1000, 1000, tip: true, at: 4))
        XCTAssertNil(scribe.box.rect, "writing puts the box away")
        input.feed(point(1000, 1000, tip: false, at: 5))
        input.feed(point(5000, 5000, tip: false, side: true, at: 6))
        input.feed(point(5000, 5000, tip: false, side: false, at: 7))
        XCTAssertNil(scribe.box.rect)
        scribe.box.rect = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        input.feed(point(5000, 5000, tip: false, side: true, at: 8))
        input.feed(point(5000, 5000, tip: false, side: false, at: 9))
        XCTAssertNil(scribe.box.rect, "a side-switch click puts it away")
    }

    func testEscPutsTheBoxAwayAndIsTakenOnlyThen() throws {
        let box = TabletBox()
        func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           characters: code == 53 ? "\u{1b}" : "a",
                                           charactersIgnoringModifiers: code == 53 ? "\u{1b}" : "a",
                                           isARepeat: false, keyCode: code))
        }
        let esc = try key(53)
        XCTAssertTrue(box.key(esc) === esc, "no box: Esc is somebody else's")
        box.rect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let other = try key(0)
        XCTAssertTrue(box.key(other) === other, "any other key goes on, unchanged")
        let commandEsc = try key(53, .command)
        XCTAssertTrue(box.key(commandEsc) === commandEsc)
        XCTAssertNotNil(box.rect)
        XCTAssertNil(box.key(esc), "Esc with a box is taken")
        XCTAssertNil(box.rect)
    }

    /// Esc for another window — a popover, a sheet — or for a field being
    /// typed in is that window's or that field's, box or no box. And while
    /// the drawing layer watches keys the box is a step in ITS Esc chain,
    /// in the order that chain chose; the pane's own monitor answers only
    /// when no layer is there to ask it.
    func testEscForSomewhereElseIsNotTheBoxs() {
        XCTAssertTrue(TabletBox.putsAway(keyCode: 53, modifiers: [], hasBox: true, elsewhere: false))
        XCTAssertFalse(TabletBox.putsAway(keyCode: 53, modifiers: [], hasBox: true, elsewhere: true),
                       "Esc meant for a popover or a field put the box away")
        XCTAssertTrue(TabletBox.paneAnswersEscape(layersWatching: 0))
        XCTAssertFalse(TabletBox.paneAnswersEscape(layersWatching: 1),
                       "two monitors racing for one Esc, in whichever order they were added")
    }

    func testABoxDrawnWithTheMouseIsKeptInPageFractions() {
        let size = CGSize(width: 400, height: 640)
        assertRect(TabletBox.fraction(CGRect(x: 100, y: 160, width: 200, height: 320), in: size),
                   CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        // Cut to the page.
        assertRect(TabletBox.fraction(CGRect(x: 300, y: -64, width: 200, height: 128), in: size),
                   CGRect(x: 0.75, y: 0, width: 0.25, height: 0.1))
        XCTAssertNil(TabletBox.fraction(CGRect(x: 500, y: 0, width: 10, height: 10), in: size))
        XCTAssertEqual(TabletBox.points(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), in: size),
                       CGRect(x: 100, y: 160, width: 200, height: 320))
    }

    /// 120 SAMPLES A SECOND REDRAW ONE STROKE, NOT THE PAGE. The page —
    /// which its layer watches — says nothing while a stroke is written,
    /// and once when it is finished; the finished ink's layer is equal to
    /// itself, so SwiftUI skips it in between.
    func testWritingDoesNotStirThePageUntilTheStrokeIsDone() {
        let (input, page, scribe) = rig()
        defer { withExtendedLifetime(scribe) {} }
        var changes = 0
        let watching = page.objectWillChange.sink { changes += 1 }
        defer { watching.cancel() }
        input.feed(point(1000, 1000, tip: true, at: 1))
        for step in 1...120 {
            input.feed(point(1000 + CGFloat(step) * 20, 1000, tip: true, at: 1 + Double(step) / 120))
        }
        XCTAssertEqual(changes, 0, "a page of handwriting redrawn under every sample")
        input.feed(point(3400, 1000, tip: false, at: 3))
        XCTAssertGreaterThan(changes, 0)
        let layer = TabletInkLayer(strokes: page.strokes, pageSize: CGSize(width: 500, height: 800))
        XCTAssertEqual(layer, TabletInkLayer(strokes: page.strokes, pageSize: CGSize(width: 500, height: 800)))
    }

    /// A full page of handwriting under the pen: what a sample costs — its
    /// way through the funnel and the scribe, and the live stroke's outline
    /// redrawn — stays far inside the 8 ms a sample has at 120 a second,
    /// even in a Debug build. (What it does not measure is SwiftUI's own
    /// drawing; the test above is what keeps the page out of that.)
    func testAFullPageDoesNotSlowTheNextStroke() {
        let (input, page, scribe) = rig()
        for line in 0..<20 {
            for word in 0..<20 {
                let x = 0.05 + Double(word) * 0.045, y = 0.05 + Double(line) * 0.045
                page.commit(pageStroke((0..<120).map { CGPoint(x: x + Double($0) * 0.0003,
                                                               y: y + sin(Double($0) / 6) * 0.01) }))
            }
        }
        XCTAssertEqual(page.strokes.count, 400)
        let size = TabletPage.size(aspect: 0.625)
        let start = Date()
        for step in 0..<240 {
            input.feed(point(1000 + CGFloat(step) * 10, 2000 + CGFloat(step % 7) * 10,
                             tip: step < 239, at: 10 + Double(step) / 120))
            if let live = scribe.stroke {
                _ = InkPaths.path(for: live, points: CanvasItem.stroke(live).basePoints(in: size))
            }
        }
        let perSample = Date().timeIntervalSince(start) / 240
        XCTAssertEqual(page.strokes.count, 401)
        XCTAssertLessThan(perSample, 0.004, "\(perSample * 1000) ms a sample")
    }
}
