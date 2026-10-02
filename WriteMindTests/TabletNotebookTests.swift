import AppKit
import Combine
import XCTest
@testable import WriteMind

// THE TABLET WRITING STRAIGHT INTO THE NOTE — the separate mode (Sean,
// 2026-10-02: "do the same for drawing mode in the notebook itself and let
// the wacom control that as well.. as a separate mode"). The tablet held
// turned is fitted onto the notes, the nib writes the note's own strokes,
// the side switch is the layer's marquee, and the driver's context and the
// funnel follow the notebook being on screen.

private func assertPoint(_ got: CGPoint, _ want: CGPoint, _ message: String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(got.x, want.x, accuracy: 1e-9, "\(got) is not \(want) \(message)", file: file, line: line)
    XCTAssertEqual(got.y, want.y, accuracy: 1e-9, "\(got) is not \(want) \(message)", file: file, line: line)
}

/// The tablet's turned shape on the notes: fitted, centred, turned.
final class NotebookMappingTests: XCTestCase {
    /// The small One by Wacom held a quarter turn clockwise: H/W.
    private let portrait: CGFloat = 9500.0 / 15200.0
    private let panes = [CGSize(width: 1000, height: 600), CGSize(width: 400, height: 900),
                         CGSize(width: 700, height: 700)]

    /// FITTED, NOT STRETCHED: handwriting keeps its proportions whatever
    /// shape the notes pane is — the tablet's own shape, as big as fits.
    func testTheTabletIsFittedOntoTheNotesNeverStretched() {
        for pane in panes {
            let area = NotebookPlace(pane: pane, scroll: 0, aspect: portrait).area
            XCTAssertEqual(area.width / area.height, portrait, accuracy: 1e-9, "stretched to fit \(pane)")
            let room = CGRect(origin: .zero, size: pane)
                .insetBy(dx: NotebookPlace.margin - 0.001, dy: NotebookPlace.margin - 0.001)
            XCTAssertTrue(room.contains(area), "\(area) is off the notes in \(pane)")
            let fillsWidth = abs(area.width - (pane.width - 2 * NotebookPlace.margin)) < 1e-9
            let fillsHeight = abs(area.height - (pane.height - 2 * NotebookPlace.margin)) < 1e-9
            XCTAssertTrue(fillsWidth || fillsHeight, "\(area) is smaller than \(pane) allows")
        }
    }

    func testTheAreaIsCentredOnTheNotes() {
        for pane in panes {
            let area = NotebookPlace(pane: pane, scroll: 250, aspect: portrait).area
            XCTAssertEqual(area.midX, pane.width / 2, accuracy: 1e-9, "\(pane)")
            XCTAssertEqual(area.midY, pane.height / 2, accuracy: 1e-9,
                           "on the PANE, whatever the scroll: the visible notes are what it maps onto")
        }
    }

    /// Each quarter turn through the funnel's own mapping: the tablet's four
    /// corners land on the area's four corners, turned clockwise a corner a
    /// turn — and an odd turn makes the tablet tall on the notes.
    func testEveryQuarterTurnPutsTheTabletsCornersOnTheAreasCorners() {
        let extent = TabletExtent(width: 15200, height: 9500)
        let pane = CGSize(width: 900, height: 700)
        // Clockwise from the top left, on the tablet and on the area.
        let tablet = [CGPoint(x: 0, y: 0), CGPoint(x: 15200, y: 0), CGPoint(x: 15200, y: 9500), CGPoint(x: 0, y: 9500)]
        for turns in 0..<4 {
            let place = NotebookPlace(pane: pane, scroll: 0,
                                      aspect: TabletMapping.aspect(of: extent, quarterTurns: turns))
            let a = place.area
            let corners = [CGPoint(x: a.minX, y: a.minY), CGPoint(x: a.maxX, y: a.minY),
                           CGPoint(x: a.maxX, y: a.maxY), CGPoint(x: a.minX, y: a.maxY)]
            for (index, counts) in tablet.enumerated() {
                let page = TabletMapping.page(counts, extent: extent, quarterTurns: turns)
                assertPoint(place.onPane(page), corners[(index + turns) % 4], "turn \(turns), corner \(index)")
            }
            XCTAssertEqual(a.width > a.height, turns % 2 == 0, "turn \(turns): \(a)")
        }
    }

    /// AS THE LAYER'S OWN PEN PUTS A POINT: on the pane, a scroll's worth
    /// further down the document, as fractions of the pane on BOTH axes —
    /// and past the first screen of a long note, not pinned to it.
    func testAPointGoesIntoTheDocumentAsFractionsOfThePane() {
        let pane = CGSize(width: 800, height: 600)
        let place = NotebookPlace(pane: pane, scroll: 900, aspect: portrait)
        let centre = CGPoint(x: 0.5, y: 0.5)
        assertPoint(place.onPane(centre), CGPoint(x: 400, y: 300))
        assertPoint(place.inDocument(centre), CGPoint(x: 400, y: 1200))
        assertPoint(place.strokePoint(centre), CGPoint(x: 0.5, y: 2))
        let corner = place.strokePoint(CGPoint(x: 1, y: 1))
        XCTAssertEqual(corner.x, place.area.maxX / 800, accuracy: 1e-12)
        XCTAssertEqual(corner.y, (place.area.maxY + 900) / 600, accuracy: 1e-12)
    }

    func testNoNotesOnScreenIsNoPlaceToWrite() {
        XCTAssertTrue(NotebookPlace(pane: .zero, scroll: 0, aspect: portrait).isEmpty)
        XCTAssertTrue(NotebookPlace(pane: CGSize(width: 20, height: 600), scroll: 0, aspect: portrait).isEmpty)
        XCTAssertFalse(NotebookPlace(pane: CGSize(width: 800, height: 600), scroll: 0, aspect: portrait).isEmpty)
    }
}

/// Samples to the note's strokes and the marquee, sample by sample.
@MainActor
final class NotebookWritingTests: XCTestCase {
    private let ink = TabletInk(colorHex: "#2D7DD2", width: 3, tool: .fountain)
    private let place = NotebookPlace(pane: CGSize(width: 800, height: 600), scroll: 120, aspect: 0.625)

    private func sample(_ x: CGFloat, _ y: CGFloat, _ phase: TabletSample.Phase, pressure: Double = 0.5,
                        side: Bool = false) -> TabletSample {
        TabletSample(page: CGPoint(x: x, y: y), pressure: pressure, phase: phase, sideSwitch: side,
                     inProximity: true, timestamp: 0)
    }

    func testNibDownToNibUpIsOneStrokeInTheNotesOwnCoordinates() throws {
        var writing = NotebookWriting()
        XCTAssertEqual(writing.consume(sample(0.2, 0.2, .hover, pressure: 0), at: place, ink: ink), .none)
        XCTAssertEqual(writing.consume(sample(0.2, 0.2, .down, pressure: 0.3), at: place, ink: ink), .began)
        XCTAssertEqual(writing.consume(sample(0.3, 0.25, .drag, pressure: 0.6), at: place, ink: ink), .grew)
        guard case .finished(let stroke) = writing.consume(sample(0.3, 0.25, .up, pressure: 0), at: place, ink: ink)
        else { return XCTFail("the up finishes the stroke") }
        XCTAssertEqual(stroke.points, [place.strokePoint(CGPoint(x: 0.2, y: 0.2)),
                                       place.strokePoint(CGPoint(x: 0.3, y: 0.25))], "the lift is not a point")
        XCTAssertEqual(stroke.pressures, [0.3, 0.6])
        XCTAssertEqual(stroke.tool, .fountain, "the notebook pen's tool, not the page's")
        XCTAssertEqual(stroke.colorHex, "#2D7DD2")
        XCTAssertEqual(stroke.width, 3, "the notebook pen's width, in the pane's points as its own pen draws")
        XCTAssertNil(writing.stroke)
        // Where the layer's own pen would have put the same spot: the pane
        // point, the scroll added, over the pane's size.
        let onPane = place.onPane(CGPoint(x: 0.2, y: 0.2))
        XCTAssertEqual(stroke.points[0].x, onPane.x / 800, accuracy: 1e-12)
        XCTAssertEqual(stroke.points[0].y, (onPane.y + 120) / 600, accuracy: 1e-12)
    }

    /// A TAP IS A DOT, in the note as on the page: one point, drawn round,
    /// where the nib touched.
    func testATapIsADotWhereTheNibTouched() {
        var writing = NotebookWriting()
        _ = writing.consume(sample(0.5, 0.5, .down, pressure: 0.8), at: place, ink: ink)
        guard case .finished(let dot) = writing.consume(sample(0.5, 0.5, .up, pressure: 0), at: place, ink: ink)
        else { return XCTFail("a tap is a stroke") }
        XCTAssertEqual(dot.points.count, 1)
        let box = InkPaths.path(for: dot, points: CanvasItem.stroke(dot).basePoints(in: place.pane)).path.boundingRect
        XCTAssertGreaterThan(box.width, 1, "a dot you can see")
        XCTAssertEqual(box.width, box.height, accuracy: box.width * 0.2, "round, not a dash")
        let at = place.inDocument(CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(box.midX, at.x, accuracy: 1)
        XCTAssertEqual(box.midY, at.y, accuracy: 1)
    }

    /// The side switch is the drawing layer's marquee, in the document's
    /// points as a ⌘-drag's is — and never ink.
    func testTheSideSwitchIsTheMarqueeInDocumentPointsAndNoInk() {
        var writing = NotebookWriting()
        let start = place.inDocument(CGPoint(x: 0.2, y: 0.3))
        let end = place.inDocument(CGPoint(x: 0.6, y: 0.5))
        guard case .selecting(let first) = writing.consume(sample(0.2, 0.3, .down, side: true), at: place, ink: ink)
        else { return XCTFail("the switch down starts a marquee") }
        XCTAssertEqual(first, CGRect(origin: start, size: .zero))
        guard case .selecting(let dragged) = writing.consume(sample(0.6, 0.5, .drag, side: true), at: place, ink: ink)
        else { return XCTFail("the drag grows it") }
        assertRect(dragged, CanvasGeometry.rect(from: start, to: end))
        guard case .selected(let done) = writing.consume(sample(0.6, 0.5, .up, side: true), at: place, ink: ink)
        else { return XCTFail("the up picks") }
        assertRect(done, CanvasGeometry.rect(from: start, to: end))
        XCTAssertGreaterThan(done.minY, 120, "in the document: a scroll's worth down")
        XCTAssertNil(writing.stroke, "no ink came of it")
    }

    func testDroppingForgetsWhatWasUnderWay() {
        var writing = NotebookWriting()
        _ = writing.consume(sample(0.2, 0.2, .down), at: place, ink: ink)
        XCTAssertNotNil(writing.stroke)
        writing.reset()
        XCTAssertNil(writing.stroke)
        XCTAssertEqual(writing.consume(sample(0.3, 0.3, .up), at: place, ink: ink), .none, "nothing lands of it")
    }
}

/// The shell: the funnel's stream into the note — through `TabletScribe`,
/// the samples' one consumer, which chooses the target.
@MainActor
final class NotebookScribeTests: XCTestCase {
    private func point(_ x: CGFloat, _ y: CGFloat, tip: Bool, side: Bool = false, pressure: Double = 0.5,
                       at time: TimeInterval) -> TabletReading {
        TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: tip, sideSwitch: side, pressure: pressure,
                                   buttons: (tip ? 1 : 0) | (side ? 2 : 0)),
                      timestamp: time, native: false)
    }

    private func rig(_ target: TabletTarget = .notebook) -> (TabletInput, TabletPage, TabletScribe, NotebookScribe) {
        let input = TabletInput()
        input.extent = TabletExtent(width: 15200, height: 9500)
        input.quarterTurns = 1
        input.aim(at: target)
        let page = TabletPage(url: nil)
        let notebook = NotebookScribe()
        notebook.place = NotebookPlace(pane: CGSize(width: 800, height: 600), scroll: 40, aspect: 0.625)
        notebook.ink = TabletInk(colorHex: "#8E44AD", width: 2, tool: .pencil)
        return (input, page, TabletScribe(page: page, input: input, notebook: notebook), notebook)
    }

    func testInNotebookModeTheStrokeGoesIntoTheNoteAndNotOntoThePage() throws {
        let (input, page, scribe, notebook) = rig()
        var landed: [Stroke] = []
        notebook.onStroke = { landed.append($0) }
        input.feed(point(3800, 2375, tip: false, at: 1))
        input.feed(point(3800, 2375, tip: true, pressure: 0.25, at: 2))
        input.feed(point(7600, 4750, tip: true, pressure: 0.75, at: 3))
        XCTAssertEqual(notebook.stroke?.points.count, 2, "the stroke is live while it is written")
        XCTAssertTrue(landed.isEmpty, "nothing in the note while the nib is down")
        input.feed(point(7600, 4750, tip: false, at: 4))
        XCTAssertNil(notebook.stroke)
        XCTAssertEqual(landed.count, 1)
        XCTAssertEqual(page.strokes, [], "the page is untouched while this is on")
        XCTAssertNil(scribe.stroke)
        let stroke = try XCTUnwrap(landed.first)
        let place = try XCTUnwrap(notebook.place)
        // Through the quarter turn — (1 − y/H, x/W) — and onto the notes.
        XCTAssertEqual(stroke.points, [place.strokePoint(CGPoint(x: 0.75, y: 0.25)),
                                       place.strokePoint(CGPoint(x: 0.5, y: 0.5))])
        XCTAssertEqual(stroke.pressures, [0.25, 0.75])
        XCTAssertEqual(stroke.tool, .pencil)
        XCTAssertEqual(stroke.colorHex, "#8E44AD")
        XCTAssertEqual(stroke.width, 2)
    }

    func testInPageModeTheNoteIsLeftAlone() {
        let (input, page, scribe, notebook) = rig(.page)
        withExtendedLifetime(scribe) {
            var landed = 0
            notebook.onStroke = { _ in landed += 1 }
            input.feed(point(3800, 2375, tip: true, at: 1))
            input.feed(point(7600, 4750, tip: true, at: 2))
            XCTAssertNil(notebook.stroke)
            input.feed(point(7600, 4750, tip: false, at: 3))
            XCTAssertEqual(landed, 0)
            XCTAssertEqual(page.strokes.count, 1)
        }
    }

    /// The side switch over the notes is the layer's marquee: shown while it
    /// is dragged, handed to the layer to pick with when it is let go, and
    /// no ink and no box on the page.
    func testTheSideSwitchPicksInTheNoteAndWritesNothing() throws {
        let (input, page, scribe, notebook) = rig()
        var picks: [CGRect] = []
        let watching = notebook.picks.sink { picks.append($0) }
        defer { watching.cancel() }
        var landed = 0
        notebook.onStroke = { _ in landed += 1 }
        input.feed(point(0, 0, tip: false, side: true, at: 1))
        input.feed(point(7600, 4750, tip: false, side: true, at: 2))
        XCTAssertNotNil(notebook.marquee, "the marquee shows while it is dragged")
        input.feed(point(7600, 4750, tip: false, side: false, at: 3))
        XCTAssertNil(notebook.marquee)
        XCTAssertEqual(picks.count, 1)
        let place = try XCTUnwrap(notebook.place)
        assertRect(picks.first, CanvasGeometry.rect(from: place.inDocument(CGPoint(x: 1, y: 0)),
                                                    to: place.inDocument(CGPoint(x: 0.5, y: 0.5))))
        XCTAssertEqual(landed, 0)
        XCTAssertEqual(page.strokes, [])
        XCTAssertNil(scribe.box.rect, "no box on the page")
    }

    func testChangingWhereThePenWritesDropsWhatWasHalfWritten() {
        let (input, page, scribe, notebook) = rig()
        withExtendedLifetime(scribe) {
            var landed = 0
            notebook.onStroke = { _ in landed += 1 }
            input.feed(point(3800, 2375, tip: true, at: 1))
            input.feed(point(4000, 2375, tip: true, at: 2))
            XCTAssertNotNil(notebook.stroke)
            input.aim(at: .page)
            XCTAssertNil(notebook.stroke, "a half-written stroke left standing in the note")
            input.feed(point(4000, 2375, tip: false, at: 3))
            XCTAssertEqual(landed, 0)
            XCTAssertEqual(page.strokes, [], "nor on the page: the lift of a stroke it never saw begin")
        }
    }

    func testGoingToTheNotebookPutsThePagesBoxAway() {
        let (input, _, scribe, _) = rig(.page)
        scribe.box.rect = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        input.aim(at: .notebook)
        XCTAssertNil(scribe.box.rect)
    }

    /// A NOTES PANE BUILT AGAIN — ⌘Y in Notebook mode makes a new one —
    /// can come up before the old one has gone, and the old one going must
    /// not take the pen's place and its way into the note with it: the
    /// next stroke went live and landed nowhere.
    func testALayerGoingLeavesThePenToTheOneStillUp() {
        let (input, _, scribe, notebook) = rig()
        withExtendedLifetime(scribe) {
            var landed = 0
            notebook.onStroke = { _ in landed += 1 }
            notebook.layerWent(othersShowing: true)
            XCTAssertNotNil(notebook.place, "the layer still up lost where the notes are")
            input.feed(point(3800, 2375, tip: true, at: 1))
            input.feed(point(4000, 2375, tip: false, at: 2))
            XCTAssertEqual(landed, 1, "the stroke was drawn and never landed")
            notebook.layerWent(othersShowing: false)
            XCTAssertNil(notebook.place, "the last one gone: no notes to write on")
            input.feed(point(3800, 2375, tip: true, at: 3))
            input.feed(point(4000, 2375, tip: false, at: 4))
            XCTAssertEqual(landed, 1)
        }
    }

    /// ANOTHER NOTE OPENED UNDER THE NIB takes nothing of what was under
    /// way: a stroke begun in one note does not land in the next, a scroll
    /// below it, and a marquee begun in one picks nothing in the other. A
    /// scroll or a resize in the same note is no such thing.
    func testANoteChangedUnderTheNibTakesNothingWithIt() {
        let (input, _, scribe, notebook) = rig()
        withExtendedLifetime(scribe) {
            let pane = CGSize(width: 800, height: 600)
            notebook.place = NotebookPlace(pane: pane, scroll: 40, aspect: 0.625, note: "Letters.md")
            var landed = 0
            notebook.onStroke = { _ in landed += 1 }
            var picks = 0
            let watching = notebook.picks.sink { _ in picks += 1 }
            defer { watching.cancel() }

            input.feed(point(3800, 2375, tip: true, at: 1))
            notebook.place = NotebookPlace(pane: pane, scroll: 90, aspect: 0.625, note: "Letters.md")
            input.feed(point(4000, 2375, tip: true, at: 2))
            XCTAssertNotNil(notebook.stroke, "a scroll in the same note is not a new note")
            input.feed(point(4000, 2375, tip: false, at: 3))
            XCTAssertEqual(landed, 1)

            input.feed(point(3800, 2375, tip: true, at: 4))
            notebook.place = NotebookPlace(pane: pane, scroll: 0, aspect: 0.625, note: "Shopping.md")
            XCTAssertNil(notebook.stroke, "the stroke from the last note is still being drawn over this one")
            input.feed(point(4000, 2375, tip: true, at: 5))
            input.feed(point(4000, 2375, tip: false, at: 6))
            XCTAssertEqual(landed, 1, "a stroke begun in one note landed in the next")

            input.feed(point(0, 0, tip: false, side: true, at: 7))
            notebook.place = NotebookPlace(pane: pane, scroll: 0, aspect: 0.625, note: "Letters.md")
            XCTAssertNil(notebook.marquee)
            input.feed(point(7600, 4750, tip: false, side: true, at: 8))
            input.feed(point(7600, 4750, tip: false, side: false, at: 9))
            XCTAssertEqual(picks, 0, "a marquee begun in one note picked in the next")
        }
    }

    func testWithNoNotesOnScreenTheNibWritesNothing() {
        let (input, _, scribe, notebook) = rig()
        withExtendedLifetime(scribe) {
            notebook.place = nil
            var landed = 0
            notebook.onStroke = { _ in landed += 1 }
            input.feed(point(3800, 2375, tip: true, at: 1))
            input.feed(point(4000, 2375, tip: true, at: 2))
            input.feed(point(4000, 2375, tip: false, at: 3))
            XCTAssertNil(notebook.stroke)
            XCTAssertEqual(landed, 0)
        }
    }
}

/// The tablet's stroke in the note through the real store, and whose ⌘Z
/// it is afterwards.
@MainActor
final class NotebookInkUndoTests: XCTestCase {
    private var dir: URL!
    private var store: NoteStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-notebook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# Letters\n\nDear Sean,\n".utf8).write(to: dir.appending(path: "Letters.md"))
        store = NoteStore(directory: dir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private let stroke = Stroke.starting(at: CGPoint(x: 0.3, y: 1.4), colorHex: "#1C1C1E", width: 3,
                                         pen: .pen(pressure: 0.5), tool: .pen)

    /// ⌘Z TAKES ONE STROKE: one step on the drawing's undo, taken as it lands.
    func testAStrokeFromTheTabletIsOneStepBack() {
        let before = store.drawing
        XCTAssertTrue(store.inkFromTablet(stroke))
        XCTAssertEqual(store.drawing.strokes, [stroke])
        XCTAssertTrue(store.undoDrawing())
        XCTAssertEqual(store.drawing, before)
        XCTAssertFalse(store.canUndoDrawing, "one stroke, one step")
        XCTAssertTrue(store.redoDrawing())
        XCTAssertEqual(store.drawing.strokes, [stroke])
    }

    func testWithNoNoteOpenThereIsNowhereToWrite() throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let nothing = NoteStore(directory: empty)
        XCTAssertNil(nothing.selectedNote)
        XCTAssertFalse(nothing.inkFromTablet(stroke))
        XCTAssertTrue(nothing.drawing.isEmpty)
        XCTAssertFalse(nothing.canUndoDrawing)
    }

    /// The pen is in one hand and ⌘Z under the other, and the keyboard is
    /// still in the note's text: left to it, ⌘Z after a stroke in the note
    /// undid the TYPING. The drawing owns it from the stroke until the text
    /// is typed in — and only while the notes can be seen.
    func testZTakesTheStrokeBackStraightAfterTheTabletWroteInTheNote() {
        let state = AppState(defaults: UserDefaults(suiteName: "WriteMindTests-\(UUID().uuidString)")!)
        state.follow(tabletPicked: true)
        XCTAssertFalse(state.drawingOwnsUndo)
        land(stroke, telling: state)
        XCTAssertTrue(state.drawingOwnsUndo, "⌘Z after a stroke in the note went to the text")
        state.noteTyped()
        XCTAssertFalse(state.drawingOwnsUndo, "typed in since: ⌘Z is the text's again")
        land(stroke, telling: state)
        state.showEditor = false
        XCTAssertFalse(state.drawingOwnsUndo, "the notes put away: an undo there would not be seen")
    }

    /// What the app does round a tablet stroke: the store takes it, the
    /// drawing's change is told as every change is (`WriteMindApp`), and
    /// the claim is made from where the drawing's undo stood under it
    /// (`NotebookTabletLayer`).
    private func land(_ stroke: Stroke, telling state: AppState) {
        let floor = store.drawingSteps
        XCTAssertTrue(store.inkFromTablet(stroke))
        state.drawingChanged(steps: store.drawingSteps)
        state.tabletInkedNote(above: floor)
    }

    /// ⌘Z IS THE STROKES' ONLY UNTIL THEY ARE TAKEN BACK. Typed in after an
    /// older change on the layer, then written on with the tablet: ⌘Z
    /// takes the strokes, and the next one is the TEXT's — the typing is
    /// newer than anything on the drawing under the strokes, and an undo
    /// that went on into the drawing undid an older step and left the
    /// newer typing standing.
    func testOnceTheTabletsStrokesAreTakenBackZIsTheTextsAgain() {
        let state = AppState(defaults: UserDefaults(suiteName: "WriteMindTests-\(UUID().uuidString)")!)
        state.follow(tabletPicked: true)
        // An older step on the layer.
        store.beginDrawingChange()
        store.drawing.items.append(.stroke(Stroke(colorHex: "#2D7DD2", width: 3,
                                                  points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.1)])))
        state.drawingChanged(steps: store.drawingSteps)
        // Then the typing, then two strokes from the tablet.
        state.noteTyped()
        land(stroke, telling: state)
        land(Stroke.starting(at: CGPoint(x: 0.5, y: 0.5), colorHex: "#1C1C1E", width: 3,
                             pen: .pen(pressure: 0.5), tool: .pen), telling: state)

        XCTAssertTrue(state.drawingOwnsUndo)
        XCTAssertTrue(store.undoDrawing())
        state.drawingChanged(steps: store.drawingSteps)
        XCTAssertTrue(state.drawingOwnsUndo, "one stroke still to take back")
        XCTAssertTrue(store.undoDrawing())
        state.drawingChanged(steps: store.drawingSteps)
        XCTAssertFalse(state.drawingOwnsUndo,
                       "both strokes taken back: the next ⌘Z undid the older step on the layer, over the typing")
        XCTAssertTrue(state.drawingOwnsRedo, "⇧⌘Z puts the stroke back")
        XCTAssertTrue(store.redoDrawing())
        state.drawingChanged(steps: store.drawingSteps)
        XCTAssertTrue(state.drawingOwnsUndo, "put back, it is the stroke's again")
        state.noteTyped()
        XCTAssertFalse(state.drawingOwnsUndo)
        XCTAssertFalse(state.drawingOwnsRedo, "typed in since: ⇧⌘Z is the text's")
    }

    /// The drawing's steps count every step taken and taken back, and do
    /// not stop at the sixty the undo keeps — the claim compares them, and
    /// at the cap the history's own count stands still under a new step.
    func testTheDrawingsStepsCountPastWhatUndoKeeps() {
        XCTAssertEqual(store.drawingSteps, 0)
        for _ in 0..<70 { store.beginDrawingChange() }
        XCTAssertEqual(store.drawingSteps, 70)
        XCTAssertTrue(store.undoDrawing())
        XCTAssertEqual(store.drawingSteps, 69)
        XCTAssertTrue(store.redoDrawing())
        XCTAssertEqual(store.drawingSteps, 70)
        XCTAssertTrue(store.inkFromTablet(stroke))
        XCTAssertEqual(store.drawingSteps, 71)
    }
}

/// Where the pen writes, the switch, and what the page says.
@MainActor
final class TabletTargetTests: XCTestCase {
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

    func testThePageUntilTheNotebookIsPickedAndThePickIsRemembered() {
        let app = state()
        XCTAssertEqual(app.tabletTarget, .page)
        app.writeOn(.notebook)
        XCTAssertEqual(app.tabletTarget, .notebook)
        XCTAssertEqual(state().tabletTarget, .notebook, "remembered")
        UserDefaults(suiteName: suite)!.set("whiteboard", forKey: "tabletTarget")
        XCTAssertEqual(state().tabletTarget, .page, "a target this build does not know is the page")
    }

    /// A pen writing in a notebook nobody can see writes nowhere: picking
    /// the notebook brings the notes into view.
    func testPickingTheNotebookBringsTheNotesIntoView() {
        let app = state()
        app.showEditor = false
        app.cameraFullWindow = true
        app.writeOn(.notebook)
        XCTAssertTrue(app.showEditor)
        XCTAssertFalse(app.cameraFullWindow)
        app.writeOn(.page)
        XCTAssertTrue(app.showEditor, "going back to the page puts nothing away")
    }

    /// THE PAGE SET ASIDE SAYS WHERE THE PEN IS — and with no note on
    /// screen it is writing nowhere, and a pointer: the line must not say
    /// it is writing on the notebook then.
    func testThePageSetAsideSaysThePenWritesOnTheNotebookOnlyWhileANoteIsUp() {
        XCTAssertEqual(TabletPane.setAsideLine(notesShowing: true), "The pen is writing on the notebook")
        let none = TabletPane.setAsideLine(notesShowing: false)
        XCTAssertFalse(none.localizedCaseInsensitiveContains("writing on the notebook"), none)
        XCTAssertTrue(none.localizedCaseInsensitiveContains("pointer"), "say what the pen is meanwhile: \(none)")
    }

    func testEveryTargetHasItsWordsAndAnIconThatExists() {
        XCTAssertEqual(TabletTarget.allCases.map(\.title), ["Page", "Notebook"])
        for target in TabletTarget.allCases {
            XCTAssertFalse(target.help.isEmpty, "\(target)")
            XCTAssertNotNil(NSImage(systemSymbolName: target.icon, accessibilityDescription: nil),
                            "\(target) asks for the missing symbol \(target.icon)")
        }
    }
}

/// The funnel takes the pen for whichever target is on screen.
final class TabletInputTargetTests: XCTestCase {
    private func penDrag(at nanos: UInt64 = 1_000) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                       mouseCursorPosition: CGPoint(x: 10, y: 10), mouseButton: .left))
        cg.setIntegerValueField(.mouseEventSubtype, value: 1)
        cg.setIntegerValueField(.tabletEventPointX, value: 7600)
        cg.setIntegerValueField(.tabletEventPointY, value: 4750)
        cg.setIntegerValueField(.tabletEventPointButtons, value: 1)
        cg.setDoubleValueField(.mouseEventPressure, value: 0.5)
        cg.timestamp = nanos
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    func testInNotebookModeItIsTheNotebookOnScreenThatTakesThePen() throws {
        let input = TabletInput()
        input.start()
        input.aim(at: .notebook)
        input.pageAppeared()
        XCTAssertFalse(input.isCapturing, "the page is up, but the pen writes in the notebook")
        let pen = try penDrag()
        XCTAssertTrue(input.handle(pen, from: .local) === pen)
        input.notebookAppeared()
        XCTAssertTrue(input.isCapturing)
        XCTAssertNil(input.handle(try penDrag(at: 2_000), from: .local),
                     "the pen's tap reached whatever the pointer was over")
        input.pageDisappeared()
        XCTAssertTrue(input.isCapturing, "the page may be put away: the notebook is what is written on")
        input.aim(at: .page)
        XCTAssertFalse(input.isCapturing, "back to the page, and the page is away")
    }

    func testWhatIsOnScreenIsSaidOnlyWhenItChanges() {
        let input = TabletInput()
        var said: [Bool] = []
        input.targetShowingChanged = { said.append($0) }
        input.pageAppeared()
        input.notebookAppeared()
        input.aim(at: .notebook)
        input.notebookDisappeared()
        input.aim(at: .page)
        input.notebookAppeared()
        input.notebookDisappeared()
        input.notebookDisappeared()
        XCTAssertEqual(said, [true, false, true])
        input.aim(at: .notebook)
        input.notebookAppeared()
        XCTAssertEqual(said, [true, false, true, false, true],
                       "one too many goings did not leave the count below nothing")
    }

    /// Whether a note is on screen, for the page to say so: published, and
    /// a count underneath — one of two going leaves one.
    func testANoteOnScreenIsPublished() {
        let input = TabletInput()
        XCTAssertFalse(input.notebookIsShowing)
        input.notebookAppeared()
        XCTAssertTrue(input.notebookIsShowing)
        input.notebookAppeared()
        input.notebookDisappeared()
        XCTAssertTrue(input.notebookIsShowing, "one of two notes panes went")
        input.notebookDisappeared()
        XCTAssertFalse(input.notebookIsShowing)
    }

    func testTheMarkerGoesWithTheTarget() throws {
        let input = TabletInput()
        input.start()
        input.pageAppeared()
        _ = input.handle(try penDrag(), from: .local)
        XCTAssertNotNil(input.pen)
        input.aim(at: .notebook)
        XCTAssertNil(input.pen, "a marker for a pen that writes nowhere on screen")
    }
}

/// THE CONTEXT FOLLOWS THE TARGET: in Notebook mode the notebook on screen
/// is what keeps the pen off the pointer, whether or not the page is up.
@MainActor
final class TabletNotebookContextTests: XCTestCase {
    private var suite: String!
    private var link: TabletControllerTests.StandInLink!
    private var input: TabletInput!
    private let oneByWacom = TabletDevice(model: "CTL-472", productID: 0x037A, serial: "2DA00L1059230")

    override func setUp() {
        super.setUp()
        suite = "WriteMindTests-\(UUID().uuidString)"
        link = TabletControllerTests.StandInLink()
        input = TabletInput()
        input.pageAppeared()
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testInNotebookModeTheContextFollowsTheNotebook() {
        let tablets = TabletController(defaults: UserDefaults(suiteName: suite)!, link: link, input: input,
                                       live: false)
        tablets.plugged(oneByWacom, registryID: 1, settle: 0)
        tablets.pick(oneByWacom)
        XCTAssertEqual(tablets.currentContext, 7)
        input.notebookAppeared()
        input.aim(at: .notebook)
        XCTAssertEqual(tablets.currentContext, 7, "both up: the one context serves either")
        XCTAssertEqual(link.calls.count, 1)
        XCTAssertEqual(link.letGone, [])
        input.pageDisappeared()
        XCTAssertEqual(tablets.currentContext, 7, "the page put away while the pen writes in the notebook")
        input.notebookDisappeared()
        XCTAssertEqual(link.letGone, [7], "no notebook on screen: the pen is a pointer again")
        link.nextContext = 8
        input.notebookAppeared()
        XCTAssertEqual(link.calls.last, .init(existing: nil, ask: false), "back on screen: taken, asking nothing")
        XCTAssertEqual(tablets.currentContext, 8)
        input.aim(at: .page)
        XCTAssertEqual(link.letGone, [7, 8], "back to a page that is put away")
        XCTAssertNil(tablets.currentContext)
    }
}

/// The side switch picks by the marquee's own rule — the ⌘-drag's.
final class TabletMarqueeTests: XCTestCase {
    func testTheSideSwitchPicksByTheMarqueesOwnRule() {
        let pane = CGSize(width: 1000, height: 200)
        let group = UUID()
        let left = Stroke(colorHex: "#2D7DD2", width: 3, points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.2, y: 0.5)],
                          group: group)
        let right = Stroke(colorHex: "#2D7DD2", width: 3, points: [CGPoint(x: 0.8, y: 0.5), CGPoint(x: 0.9, y: 0.5)],
                           group: group)
        let loose = Stroke(colorHex: "#2D7DD2", width: 3, points: [CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.55, y: 0.1)])
        let drawing = Drawing(items: [.stroke(left), .stroke(right), .stroke(loose)])
        XCTAssertEqual(DrawingCanvas.marqueePicked(CGRect(x: 120, y: 80, width: 40, height: 40), in: drawing,
                                                   size: pane, adding: nil),
                       [left.id, right.id], "touching one of a group takes the group")
        XCTAssertEqual(DrawingCanvas.marqueePicked(CGRect(x: 510, y: 10, width: 20, height: 20), in: drawing,
                                                   size: pane, adding: [left.id, right.id]),
                       [left.id, right.id, loose.id], "⇧ adds to what is picked")
        XCTAssertEqual(DrawingCanvas.marqueePicked(CGRect(x: 300, y: 150, width: 10, height: 10), in: drawing,
                                                   size: pane, adding: nil), [], "over nothing, nothing")
    }
}
