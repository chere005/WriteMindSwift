import AppKit
import CoreGraphics
import XCTest
@testable import WriteMind

// THE WACOM PEN AND A DRAWING CELL (Sean, 2026-10-03: "mouse or wacom into
// cell (if wacom is in write on notebook mode)"; "With the tablet on 'Write
// on: Page' the pen does not draw into cells at all"). With the tablet's
// target the NOTEBOOK, a drawing cell is static until the nib TAPS it, and
// then the nib writes into that cell and nowhere else, clipped to it, onto
// its own undo — and a touch outside it is the way out. With the target the
// page nothing of this happens: the pen writes on the tablet's own page,
// which has no cells (`TabletScribe` hands the notebook nothing then).

/// A cell on the page at (100, 300) in document points, 300 × 120, and a
/// second one under it; the pane is 800 × 600 and has scrolled 100.
private let cellA = CellFrame(id: UUID(), line: NSRange(location: 20, length: 59),
                              rect: CGRect(x: 100, y: 300, width: 300, height: 120), scale: 1, width: 300,
                              writable: true)
private let cellB = CellFrame(id: UUID(), line: NSRange(location: 90, length: 59),
                              rect: CGRect(x: 100, y: 460, width: 300, height: 120), scale: 1, width: 300,
                              writable: true)
private var cellReadOnly: CellFrame {
    var frame = cellB
    frame.id = UUID()
    frame.rect = CGRect(x: 450, y: 300, width: 200, height: 120)
    frame.writable = false
    return frame
}

private func makePlace(entered: UUID? = nil, cells: [CellFrame] = [cellA, cellB]) -> NotebookPlace {
    NotebookPlace(pane: CGSize(width: 800, height: 600), scroll: 100, aspect: 1.6, cells: cells, entered: entered)
}

/// A sample of the nib at a point of the DOCUMENT (the layer's own points).
private func sample(_ point: CGPoint, in place: NotebookPlace, _ phase: TabletSample.Phase, pressure: Double = 0.5,
                    side: Bool = false, eraser: Bool = false) -> TabletSample {
    let area = place.area
    let page = CGPoint(x: (point.x - area.minX) / area.width, y: (point.y - place.scroll - area.minY) / area.height)
    var made = TabletSample(page: page, pressure: pressure, phase: phase, sideSwitch: side, inProximity: true,
                            timestamp: 0)
    made.eraser = eraser
    return made
}

private let inA = CGPoint(x: 200, y: 350)
private let inB = CGPoint(x: 200, y: 500)
private let onPage = CGPoint(x: 600, y: 520)

/// The rule, sample by sample.
@MainActor
final class NotebookCellWritingTests: XCTestCase {
    private let ink = TabletInk(colorHex: "#2D7DD2", width: 3, tool: .pen)

    private func tap(_ at: CGPoint, in place: NotebookPlace, jitter: CGFloat = 0) -> [NotebookWriting.Outcome] {
        var writing = NotebookWriting()
        var outcomes = [writing.consume(sample(at, in: place, .down), at: place, ink: ink)]
        if jitter > 0 {
            outcomes.append(writing.consume(sample(CGPoint(x: at.x + jitter, y: at.y), in: place, .drag), at: place,
                                            ink: ink))
        }
        outcomes.append(writing.consume(sample(CGPoint(x: at.x + jitter, y: at.y), in: place, .up, pressure: 0),
                                        at: place, ink: ink))
        return outcomes
    }

    /// THE NIB TAPPING A STATIC CELL ENTERS IT — and the tap leaves no dot,
    /// shows no ink while it is down, and is a click's own: under three
    /// points of travel.
    func testATapOnAStaticCellEntersItAndLeavesNoInk() {
        XCTAssertEqual(tap(inA, in: makePlace()), [.none, .entered(cellA.id)])
        XCTAssertEqual(tap(inB, in: makePlace()), [.none, .entered(cellB.id)])
        XCTAssertEqual(tap(inA, in: makePlace(), jitter: 2), [.none, .none, .entered(cellA.id)],
                       "a wobbly tap is still a tap")
    }

    /// A tap off every cell is a dot, as ever; on a read-only cell it is a
    /// dot too (nothing is drawn in it, nothing is entered).
    func testATapAnywhereElseIsADot() {
        let place = makePlace(cells: [cellA, cellB, cellReadOnly])
        for at in [onPage, CGPoint(x: 500, y: 350)] {
            let outcomes = tap(at, in: place)
            XCTAssertEqual(outcomes.first, .began, "ink shows from the touch")
            guard case .finished(let dot)? = outcomes.last else { return XCTFail("\(at) was not a dot: \(outcomes)") }
            XCTAssertEqual(dot.points.count, 1)
        }
    }

    /// A STROKE OVER A STATIC CELL FLOATS: it begins once it has travelled,
    /// from where the nib went down (nothing of the start is lost), and goes
    /// on the page like any stroke — never into the cell.
    func testAStrokeOverAStaticCellFloatsOverItFromWhereItBegan() throws {
        let place = makePlace()
        var writing = NotebookWriting()
        XCTAssertEqual(writing.consume(sample(inA, in: place, .down), at: place, ink: ink), .none)
        XCTAssertEqual(writing.consume(sample(CGPoint(x: 201, y: 350), in: place, .drag), at: place, ink: ink), .none,
                       "still a tap: no ink yet")
        XCTAssertEqual(writing.consume(sample(CGPoint(x: 215, y: 355), in: place, .drag), at: place, ink: ink), .began)
        XCTAssertEqual(writing.consume(sample(CGPoint(x: 240, y: 360), in: place, .drag), at: place, ink: ink), .grew)
        guard case .finished(let stroke) = writing.consume(sample(CGPoint(x: 240, y: 360), in: place, .up, pressure: 0),
                                                           at: place, ink: ink)
        else { return XCTFail("the lift of a stroke over a static cell is a stroke on the page") }
        XCTAssertEqual(stroke.points.count, 4, "the start, the wobble, and the two after it")
        XCTAssertEqual(stroke.points[0], place.strokePoint(sample(inA, in: place, .down).page))
    }

    func testTheEraserAndTheSwitchOverAStaticCellAreNeverATap() {
        let place = makePlace()
        var writing = NotebookWriting()
        XCTAssertEqual(writing.consume(sample(inA, in: place, .down, eraser: true), at: place, ink: ink),
                       .erasing(from: inA, to: inA))
        XCTAssertEqual(writing.consume(sample(inA, in: place, .up, pressure: 0, eraser: true), at: place, ink: ink),
                       .erased)
        guard case .selecting = writing.consume(sample(inA, in: place, .down, side: true), at: place, ink: ink)
        else { return XCTFail("the switch held is the marquee, not a tap into the cell") }
    }

    // MARK: In a cell

    /// IN CELL DRAWING MODE the nib writes into the entered cell: the stroke
    /// that lands is the cell's, and no tap enters anything.
    func testInACellTheNibWritesIntoItAndNowhereElse() throws {
        let place = makePlace(entered: cellA.id)
        var writing = NotebookWriting()
        XCTAssertEqual(writing.consume(sample(inA, in: place, .down), at: place, ink: ink), .began,
                       "ink shows at once: a touch in the entered cell is not a tap into anything")
        XCTAssertEqual(writing.consume(sample(CGPoint(x: 260, y: 380), in: place, .drag), at: place, ink: ink), .grew)
        guard case .finishedInCell(let stroke, let id) = writing.consume(
            sample(CGPoint(x: 260, y: 380), in: place, .up, pressure: 0), at: place, ink: ink)
        else { return XCTFail("a stroke in the entered cell is the cell's") }
        XCTAssertEqual(id, cellA.id)
        XCTAssertEqual(stroke.points.count, 2)
        // A tap there is a dot, in the cell.
        guard case .finishedInCell(let dot, _)? = tap(inA, in: place).last else { return XCTFail("a tap is a dot") }
        XCTAssertEqual(dot.points.count, 1)
    }

    /// CLIPPED TO THE CELL: a stroke dragged out of it, on every side, runs
    /// along its edge — no point of it is outside the cell's rect.
    func testAStrokeDraggedOutOfTheCellIsHeldInsideIt() throws {
        let place = makePlace(entered: cellA.id)
        var writing = NotebookWriting()
        _ = writing.consume(sample(inA, in: place, .down), at: place, ink: ink)
        for out in [CGPoint(x: 50, y: 350), CGPoint(x: 600, y: 310), CGPoint(x: 300, y: 700), CGPoint(x: 300, y: 150)] {
            _ = writing.consume(sample(out, in: place, .drag), at: place, ink: ink)
        }
        guard case .finishedInCell(let stroke, _) = writing.consume(sample(inA, in: place, .up, pressure: 0),
                                                                    at: place, ink: ink)
        else { return XCTFail("a stroke in the entered cell is the cell's") }
        XCTAssertEqual(stroke.points.count, 5)
        for point in stroke.points {
            let document = CGPoint(x: point.x * place.pane.width, y: point.y * place.pane.height)
            XCTAssertTrue(cellA.rect.insetBy(dx: -1e-6, dy: -1e-6).contains(document),
                          "\(document) is outside the cell \(cellA.rect)")
        }
    }

    /// A TOUCH OUTSIDE THE ENTERED CELL IS THE WAY OUT and nothing else: no
    /// ink, no box, no erasure, whatever the nib does until it lifts — and
    /// the next touch is a touch like any other.
    func testATouchOutsideTheEnteredCellLeavesAndDrawsNothing() {
        let place = makePlace(entered: cellA.id)
        var writing = NotebookWriting()
        XCTAssertEqual(writing.consume(sample(onPage, in: place, .down), at: place, ink: ink), .left)
        XCTAssertEqual(writing.consume(sample(CGPoint(x: 620, y: 530), in: place, .drag), at: place, ink: ink), .none)
        XCTAssertEqual(writing.consume(sample(CGPoint(x: 640, y: 540), in: place, .drag), at: place, ink: ink), .none,
                       "nothing of a touch that left the cell is ink")
        XCTAssertEqual(writing.consume(sample(CGPoint(x: 640, y: 540), in: place, .up, pressure: 0), at: place,
                                       ink: ink), .none)
        XCTAssertNil(writing.stroke)
        XCTAssertEqual(writing.consume(sample(onPage, in: place, .down), at: place, ink: ink), .left,
                       "still entered as far as this value knows: the app has not yet been told")
        _ = writing.consume(sample(onPage, in: place, .up, pressure: 0), at: place, ink: ink)
        // And once the app has left the mode the next touch is ink.
        let left = makePlace()
        XCTAssertEqual(writing.consume(sample(onPage, in: left, .down), at: left, ink: ink), .began)
    }

    /// The eraser and the side switch go down outside the cell: the way out
    /// too — "nothing else on the page reacts to the pen". Inside, the eraser
    /// is erasing (the layer scopes it to the cell) and the switch the
    /// marquee.
    func testTheEraserAndTheSwitchOutsideTheEnteredCellLeaveToo() {
        let place = makePlace(entered: cellA.id)
        var writing = NotebookWriting()
        XCTAssertEqual(writing.consume(sample(onPage, in: place, .down, eraser: true), at: place, ink: ink), .left)
        _ = writing.consume(sample(onPage, in: place, .up, pressure: 0, eraser: true), at: place, ink: ink)
        XCTAssertEqual(writing.consume(sample(onPage, in: place, .down, side: true), at: place, ink: ink), .left)
        _ = writing.consume(sample(onPage, in: place, .up, pressure: 0, side: true), at: place, ink: ink)
        XCTAssertEqual(writing.consume(sample(inA, in: place, .down, eraser: true), at: place, ink: ink),
                       .erasing(from: inA, to: inA))
        _ = writing.consume(sample(inA, in: place, .up, pressure: 0, eraser: true), at: place, ink: ink)
        guard case .selecting = writing.consume(sample(inA, in: place, .down, side: true), at: place, ink: ink)
        else { return XCTFail("the switch inside the cell is its marquee") }
    }

    /// A tap on ANOTHER cell while one is entered leaves the first and enters
    /// the second, as a click does — one touch down is the way out, and its
    /// lift is the way in.
    func testATapOnAnotherCellLeavesOneAndEntersTheOther() {
        let place = makePlace(entered: cellA.id)
        var writing = NotebookWriting()
        XCTAssertEqual(writing.consume(sample(inB, in: place, .down), at: place, ink: ink), .left)
        XCTAssertEqual(writing.consume(sample(inB, in: place, .up, pressure: 0), at: place, ink: ink),
                       .entered(cellB.id))
        // Dragged across it, it is only the way out.
        XCTAssertEqual(writing.consume(sample(inB, in: place, .down), at: place, ink: ink), .left)
        _ = writing.consume(sample(CGPoint(x: 300, y: 520), in: place, .drag), at: place, ink: ink)
        XCTAssertEqual(writing.consume(sample(CGPoint(x: 300, y: 520), in: place, .up, pressure: 0), at: place,
                                       ink: ink), .none)
    }
}

// MARK: - Through the scribe, the store and the app

@MainActor
final class NotebookCellScribeTests: XCTestCase {
    private var dir: URL!
    private var store: NoteStore!
    private var state: AppState!
    private var suite: String!
    private var notebook: NotebookScribe!

    override func setUp() async throws {
        suite = "WriteMindTests-\(UUID().uuidString)"
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-cellpen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# Sketch\n".utf8).write(to: dir.appending(path: "Sketch.md"))
        store = NoteStore(directory: dir)
        store.canvasSize = CGSize(width: 800, height: 600)
        store.cellFrames = [cellA, cellB]
        state = AppState(defaults: UserDefaults(suiteName: suite)!)
        state.mode = .preview
        state.follow(tabletPicked: true)
        notebook = NotebookScribe()
        notebook.place = makePlace()
        notebook.writes(into: store, telling: state)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        notebook = nil
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// The app hands the place on as the cell mode changes
    /// (`NotebookTabletLayer`).
    private func syncPlace() { notebook.place = makePlace(entered: state.cellDrawing) }

    private func touch(_ points: [CGPoint], pressure: Double = 0.5) {
        for (index, point) in points.enumerated() {
            let phase: TabletSample.Phase = index == 0 ? .down : (index == points.count - 1 ? .up : .drag)
            notebook.consume(sample(point, in: notebook.place!, phase, pressure: phase == .up ? 0 : pressure))
        }
    }

    /// TAP ENTERS, STROKE DRAWS IN, TOUCH OUTSIDE LEAVES — the whole round
    /// trip through the real wiring, one step each.
    func testTapStrokeAndLeaveThroughTheRealWiring() throws {
        // A stroke over a static cell floats.
        touch([inA, CGPoint(x: 230, y: 360), CGPoint(x: 260, y: 370)])
        XCTAssertEqual(store.drawing.strokes.count, 1, "a stroke over a static cell is floating ink")
        XCTAssertTrue(store.cells.isEmpty)
        XCTAssertNil(state.cellDrawing)

        // A tap enters it, and draws nothing.
        let before = store.drawingSteps
        touch([inA, inA])
        XCTAssertEqual(state.cellDrawing, cellA.id, "a tap on a static cell did not enter it")
        XCTAssertEqual(store.drawingSteps, before, "a tap that enters leaves no step behind it")
        XCTAssertEqual(store.drawing.strokes.count, 1, "and no dot")
        syncPlace()

        // In it the nib writes into the cell: held inside, one step.
        touch([CGPoint(x: 150, y: 340), CGPoint(x: 700, y: 380), CGPoint(x: 700, y: 390)])
        let cell = try XCTUnwrap(store.cells[cellA.id], "the stroke did not go into the entered cell")
        XCTAssertEqual(cell.drawing.strokes.count, 1)
        XCTAssertEqual(store.drawing.strokes.count, 1, "nothing else on the page was drawn")
        XCTAssertEqual(store.drawingSteps, before + 1)
        for point in cell.drawing.strokes[0].points {
            XCTAssertTrue((0...1).contains(point.x), "\(point) is outside the cell")
        }
        XCTAssertEqual(state.cellDrawing, cellA.id, "it does not end by itself between strokes")
        XCTAssertTrue(state.drawingOwnsUndo, "⌘Z is claimed for the cell")

        // A touch outside it leaves.
        touch([onPage, onPage])
        XCTAssertNil(state.cellDrawing, "a touch outside the cell did not leave it")
        XCTAssertEqual(store.drawing.strokes.count, 1, "and drew nothing")
        syncPlace()
        // Back to ordinary: the next touch there is a dot.
        touch([onPage, onPage])
        XCTAssertEqual(store.drawing.strokes.count, 2)
    }

    /// A tap in the markdown view enters nothing: the rendered page owns it
    /// (the layer that carries the nib is not up there either).
    func testATapEntersNothingWhileTheMarkdownViewIsUp() {
        state.mode = .editor
        touch([inA, inA])
        XCTAssertNil(state.cellDrawing)
    }

    /// The pen's two buttons in a cell are the CELL's undo and redo: they
    /// take back the strokes written in it and never reach the page.
    func testInACellThePensButtonsAreTheCellsOwnUndoAndRedo() {
        touch([onPage, CGPoint(x: 650, y: 540), CGPoint(x: 700, y: 550)])
        XCTAssertEqual(store.drawing.strokes.count, 1)
        touch([inA, inA])
        syncPlace()
        touch([inA, CGPoint(x: 250, y: 360), CGPoint(x: 300, y: 370)])
        XCTAssertEqual(store.cells[cellA.id]?.drawing.strokes.count, 1)

        notebook.takeBack()
        XCTAssertEqual(store.cells[cellA.id]?.drawing.strokes.count, 0, "the lower switch took back the cell's stroke")
        notebook.takeBack()
        XCTAssertEqual(store.drawing.strokes.count, 1, "and a second reached the page")
        notebook.putBack()
        XCTAssertEqual(store.cells[cellA.id]?.drawing.strokes.count, 1)
        notebook.putBack()
        XCTAssertEqual(store.cells[cellA.id]?.drawing.strokes.count, 1)
        XCTAssertEqual(store.drawing.strokes.count, 1)
    }

    /// WITH THE TABLET ON THE PAGE THE PEN DOES NOT DRAW INTO CELLS AT ALL
    /// (Sean, 2026-10-03: "if wacom is in write on notebook mode"): through
    /// the funnel's one consumer, a tap on a cell's place writes a dot on the
    /// tablet's own page and the note never hears of it — and picked, the
    /// notebook enters the cell.
    func testWithTheTabletOnThePageTheNibNeverTouchesACell() {
        let input = TabletInput()
        input.extent = TabletExtent(width: 15200, height: 9500)
        let page = TabletPage(url: nil)
        let scribe = TabletScribe(page: page, input: input, notebook: notebook)
        withExtendedLifetime(scribe) {
            input.aim(at: .page)
            scribe.consume(sample(inA, in: notebook.place!, .down))
            scribe.consume(sample(inA, in: notebook.place!, .up, pressure: 0))
            XCTAssertNil(state.cellDrawing, "a tap on the page's own sheet entered a cell of the notebook")
            XCTAssertTrue(store.cells.isEmpty)
            XCTAssertTrue(store.drawing.isEmpty)
            XCTAssertEqual(page.strokes.count, 1, "the pen wrote on the page, as before")

            input.aim(at: .notebook)
            scribe.consume(sample(inA, in: notebook.place!, .down))
            scribe.consume(sample(inA, in: notebook.place!, .up, pressure: 0))
            XCTAssertEqual(state.cellDrawing, cellA.id, "and on the notebook the same tap enters the cell")
            XCTAssertEqual(page.strokes.count, 1)
        }
    }

    /// Entering from a tap puts the caret into the cell, as a click's does.
    func testATapPutsTheCaretIntoTheCellLikeAClickDoes() {
        var focused: [UUID] = []
        state.editor.focusDrawingCellInDocument = { focused.append($0) }
        touch([inA, inA])
        XCTAssertEqual(focused, [cellA.id])
    }
}

// MARK: - The mode ends under the nib

/// THE CELL MODE CAN END WITH THE NIB DOWN — Esc, ⌘P, another note, the cell
/// folding away — and what the touch was doing in the cell must never go on
/// onto the page (review, 2026-10-03; Sean's rule: a stroke is cancelled or
/// finished into the cell cleanly). The stroke lands in the cell it began in,
/// held inside it, or nowhere when the cell is gone; the eraser and the
/// marquee, which would reach the page's own strokes and objects once the
/// cell is no longer the one entered, stop.
@MainActor
final class CellModeEndsUnderTheNibTests: XCTestCase {
    private var dir: URL!
    private var store: NoteStore!
    private var state: AppState!
    private var suite: String!
    private var notebook: NotebookScribe!

    override func setUp() async throws {
        suite = "WriteMindTests-\(UUID().uuidString)"
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-cellends-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# Sketch\n".utf8).write(to: dir.appending(path: "Sketch.md"))
        store = NoteStore(directory: dir)
        store.canvasSize = CGSize(width: 800, height: 600)
        store.cellFrames = [cellA, cellB]
        state = AppState(defaults: UserDefaults(suiteName: suite)!)
        state.mode = .preview
        state.follow(tabletPicked: true)
        notebook = NotebookScribe()
        notebook.place = makePlace()
        notebook.writes(into: store, telling: state)
        // A tap enters cell A, as the nib does.
        down(inA)
        up(inA)
        XCTAssertEqual(state.cellDrawing, cellA.id)
        syncPlace()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        notebook = nil
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// What the notes pane hands the scribe as the mode changes.
    private func syncPlace(cells: [CellFrame] = [cellA, cellB]) {
        notebook.place = makePlace(entered: state.cellDrawing, cells: cells)
    }
    private func down(_ at: CGPoint, side: Bool = false, eraser: Bool = false) {
        notebook.consume(sample(at, in: notebook.place!, .down, side: side, eraser: eraser))
    }
    private func drag(_ at: CGPoint, side: Bool = false, eraser: Bool = false) {
        notebook.consume(sample(at, in: notebook.place!, .drag, side: side, eraser: eraser))
    }
    private func up(_ at: CGPoint, side: Bool = false, eraser: Bool = false) {
        notebook.consume(sample(at, in: notebook.place!, .up, pressure: 0, side: side, eraser: eraser))
    }

    /// A STROKE BEGUN IN THE CELL LANDS IN THAT CELL, whatever the mode does
    /// under it: held inside the cell to the end, and never on the page.
    func testAStrokeBegunInTheCellLandsInItWhenTheModeEndsUnderTheNib() throws {
        down(inA)
        drag(CGPoint(x: 230, y: 360))
        state.endCellDrawing()
        syncPlace()
        drag(CGPoint(x: 600, y: 520))
        drag(CGPoint(x: 700, y: 560))
        up(CGPoint(x: 700, y: 560))
        XCTAssertTrue(store.drawing.strokes.isEmpty, "the rest of the stroke went onto the page")
        let cell = try XCTUnwrap(store.cells[cellA.id], "the stroke did not land in the cell it began in")
        XCTAssertEqual(cell.drawing.strokes.count, 1)
        for point in cell.drawing.strokes[0].points {
            XCTAssertTrue((0...1).contains(point.x), "\(point) is outside the cell")
        }
        XCTAssertNil(state.cellDrawing, "and the mode did not come back for it")
    }

    /// A STROKE WHOSE CELL IS GONE LANDS NOWHERE — not floating over the page
    /// where the cell was, which is where `inkFromTablet` put it for want of a
    /// cell to put it in. No step is left behind either.
    func testAStrokeWhoseCellWentLandsNowhere() {
        let steps = store.drawingSteps
        down(inA)
        drag(CGPoint(x: 230, y: 360))
        // The cell folds away: the pane tells the store and the scribe, and
        // the mode ends with it.
        store.cellFrames = [cellB]
        state.endCellDrawing()
        syncPlace(cells: [cellB])
        drag(CGPoint(x: 260, y: 370))
        up(CGPoint(x: 260, y: 370))
        XCTAssertTrue(store.drawing.strokes.isEmpty, "a stroke begun in a cell floated onto the page when the cell went")
        XCTAssertNil(store.cells[cellA.id])
        XCTAssertEqual(store.drawingSteps, steps, "and left an empty step behind it")
        XCTAssertNil(notebook.stroke)
    }

    /// THE STORE'S HALF: told a cell that has no frame, `inkFromTablet` takes
    /// nothing, begins nothing and says so.
    func testAStrokeForACellThatIsNotThereIsRefused() {
        let steps = store.drawingSteps
        let stroke = Stroke.starting(at: CGPoint(x: 0.3, y: 0.6), colorHex: "#1C1C1E", width: 3,
                                     pen: .pen(pressure: 0.5), tool: .pen)
        XCTAssertFalse(store.inkFromTablet(stroke, intoCell: UUID()))
        XCTAssertTrue(store.drawing.strokes.isEmpty)
        XCTAssertEqual(store.drawingSteps, steps)
        // A read-only cell is no cell to write in either.
        var locked = cellA
        locked.id = UUID()
        locked.writable = false
        store.cellFrames = [cellA, cellB, locked]
        XCTAssertFalse(store.inkFromTablet(stroke, intoCell: locked.id))
        XCTAssertEqual(store.drawingSteps, steps)
        // And with no cell named it is the page's, as ever.
        XCTAssertTrue(store.inkFromTablet(stroke))
        XCTAssertEqual(store.drawing.strokes.count, 1)
    }

    /// THE ERASER begun in the cell reaches only that cell's strokes. The
    /// canvas scopes it by the cell ENTERED, so once the mode is over the rest
    /// of the erasure would be the page's: it stops, and the erasure ends (one
    /// step) where the mode did.
    func testTheEraserBegunInTheCellStopsWhenTheModeEnds() {
        var heard: [NotebookErase] = []
        let watching = notebook.erases.sink { heard.append($0) }
        defer { watching.cancel() }
        down(inA, eraser: true)
        drag(CGPoint(x: 220, y: 350), eraser: true)
        XCTAssertEqual(heard.count, 2)
        state.endCellDrawing()
        syncPlace()
        drag(CGPoint(x: 600, y: 520), eraser: true)
        drag(CGPoint(x: 640, y: 540), eraser: true)
        up(CGPoint(x: 640, y: 540), eraser: true)
        XCTAssertEqual(heard.last, .end, "the erasure was not ended where the mode ended")
        XCTAssertEqual(heard.filter { if case .path = $0 { return true } else { return false } }.count, 2,
                       "the nib went on erasing after the mode ended, over the page's own strokes")
        XCTAssertEqual(heard.filter { $0 == .end }.count, 1)
    }

    /// THE MARQUEE begun in the cell is dropped with it: lifted over the page
    /// it would pick the page's objects.
    func testTheMarqueeBegunInTheCellIsDroppedWhenTheModeEnds() {
        var picked: [CGRect] = []
        let watching = notebook.picks.sink { picked.append($0) }
        defer { watching.cancel() }
        down(inA, side: true)
        drag(CGPoint(x: 230, y: 360), side: true)
        XCTAssertNotNil(notebook.marquee)
        state.endCellDrawing()
        syncPlace()
        drag(CGPoint(x: 600, y: 520), side: true)
        up(CGPoint(x: 600, y: 520), side: true)
        XCTAssertTrue(picked.isEmpty, "a marquee begun in a cell picked the page's objects")
        XCTAssertNil(notebook.marquee)
    }

    /// WHAT THE CHECK MUST NOT TOUCH: a touch that began OUTSIDE the entered
    /// cell is the way out, and its lift on another cell is the way into that
    /// one — the app leaves the mode as the nib goes down, tells the scribe,
    /// and the touch goes on.
    func testATouchThatLeftTheCellStillEntersTheCellItIsLiftedOn() {
        down(inB)
        XCTAssertNil(state.cellDrawing, "a touch outside the entered cell is the way out")
        syncPlace()
        drag(CGPoint(x: 201, y: 501))
        up(CGPoint(x: 201, y: 501))
        XCTAssertEqual(state.cellDrawing, cellB.id)
    }

    /// Nor a stroke that is only a tap into a cell: entering one changes the
    /// entered cell under the nib that tapped it.
    func testATapEntersTheCellEvenThoughTheEnteredCellChangesUnderIt() {
        state.endCellDrawing()
        syncPlace()
        down(inB)
        up(inB)
        XCTAssertEqual(state.cellDrawing, cellB.id)
        syncPlace()
        XCTAssertNil(notebook.stroke)
        XCTAssertTrue(store.drawing.strokes.isEmpty)
    }
}

// MARK: - ⌘Z straight after drawing in a cell

/// A STROKE IN A CELL GIVES ⌘Z TO THE INK, whoever drew it, so that ⌘Z right
/// after Esc or Done never undoes the typing before it (review, 2026-10-03:
/// the mouse's stroke did not claim it, the nib's did, and a cursor-mode
/// stroke into a cell used to).
///
/// What this holds: the nib's half through the real scribe and its wiring, the
/// mouse's through the closures the editor pane hands the canvas
/// (`onCursorInk` is `AppState.inkedNote(above:)`, `onBeginChange` is
/// `NoteStore.beginDrawingChange`, the cell binding is `NoteStore.cells`) in
/// the order `DrawingCanvas.beginInk` calls them — the gesture that calls them
/// cannot be driven from a test, so that call is read, not run.
@MainActor
final class CellInkClaimsUndoTests: XCTestCase {
    private var dir: URL!
    private var store: NoteStore!
    private var state: AppState!
    private var suite: String!
    private var notebook: NotebookScribe!
    private var wiring: Any?

    override func setUp() async throws {
        suite = "WriteMindTests-\(UUID().uuidString)"
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-cellclaim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# Sketch\n\nsome words\n".utf8).write(to: dir.appending(path: "Sketch.md"))
        store = NoteStore(directory: dir)
        store.canvasSize = CGSize(width: 800, height: 600)
        store.cellFrames = [cellA, cellB]
        state = AppState(defaults: UserDefaults(suiteName: suite)!)
        state.mode = .preview
        state.follow(tabletPicked: true)
        notebook = NotebookScribe()
        notebook.place = makePlace()
        notebook.writes(into: store, telling: state)
        // As the app tells the state of the drawing (`WriteMindApp`).
        let drawing = store.$drawing.sink { [unowned self] _ in state.drawingChanged(steps: store.drawingSteps) }
        let cells = store.$cells.sink { [unowned self] _ in state.drawingChanged(steps: store.drawingSteps) }
        wiring = [drawing, cells]
        state.enterCell(cellA.id)
        notebook.place = makePlace(entered: cellA.id)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        wiring = nil
        notebook = nil
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func afterLeavingTheCell() {
        state.endCellDrawing()
        XCTAssertTrue(state.drawingOwnsUndo, "⌘Z after leaving the cell went to the text")
        XCTAssertTrue(state.drawingOwnsRedo)
        // Only down to where the drawing stood: with the stroke taken back
        // the typing before it is next.
        XCTAssertTrue(store.undoDrawing())
        XCTAssertFalse(state.drawingOwnsUndo, "the stroke is back: ⌘Z is the typing's")
    }

    func testTheNibsStrokeInACellClaimsCmdZAfterTheModeEnds() {
        notebook.consume(sample(inA, in: notebook.place!, .down))
        notebook.consume(sample(CGPoint(x: 260, y: 380), in: notebook.place!, .drag))
        notebook.consume(sample(CGPoint(x: 260, y: 380), in: notebook.place!, .up, pressure: 0))
        XCTAssertEqual(store.cells[cellA.id]?.drawing.strokes.count, 1)
        afterLeavingTheCell()
    }

    func testTheMousesStrokeInACellClaimsCmdZAfterTheModeEnds() {
        // The canvas's `beginInk`: the claim, then the step; and at the end
        // of the drag the stroke goes into the cell.
        state.inkedNote(above: store.drawingSteps)
        store.beginDrawingChange()
        var cell = store.cells[cellA.id] ?? .empty(width: Double(cellA.width))
        cell.drawing.items.append(.stroke(Stroke.starting(at: CGPoint(x: 0.2, y: 0.1), colorHex: "#1C1C1E", width: 3,
                                                         pen: .pen(pressure: 0.5), tool: .pen)))
        store.cells[cellA.id] = cell
        XCTAssertEqual(store.cells[cellA.id]?.drawing.strokes.count, 1)
        afterLeavingTheCell()
    }

    /// And typing clears the claim for both: ⌘Z is the text's again.
    func testTypingTakesTheClaimBack() {
        state.inkedNote(above: store.drawingSteps)
        store.beginDrawingChange()
        store.cells[cellA.id] = .empty(width: Double(cellA.width))
        state.endCellDrawing()
        XCTAssertTrue(state.drawingOwnsUndo)
        state.noteTyped()
        XCTAssertFalse(state.drawingOwnsUndo)
    }
}

// MARK: - A cell's own undo and redo

/// UNDO AND REDO INSIDE A CELL step through the strokes of THAT CELL and
/// never reach the page or another cell (Sean, 2026-10-03: "onto its own
/// drawing history so undo/redo works inside it").
@MainActor
final class CellUndoTests: XCTestCase {
    private var dir: URL!
    private var store: NoteStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-cellundo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# Sketch\n".utf8).write(to: dir.appending(path: "Sketch.md"))
        store = NoteStore(directory: dir)
        store.canvasSize = CGSize(width: 800, height: 600)
        store.cellFrames = [cellA, cellB]
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func stroke(at point: CGPoint) -> Stroke {
        Stroke.starting(at: CGPoint(x: point.x / 800, y: point.y / 600), colorHex: "#1C1C1E", width: 3,
                        pen: .pen(pressure: 0.5), tool: .pen)
    }

    private func page() { XCTAssertTrue(store.inkFromTablet(stroke(at: CGPoint(x: 600, y: 520)))) }
    private func ink(_ cell: CellFrame, at point: CGPoint) {
        XCTAssertTrue(store.inkFromTablet(stroke(at: point), intoCell: cell.id))
    }
    private func strokes(in cell: CellFrame) -> Int { store.cells[cell.id]?.drawing.strokes.count ?? 0 }

    /// The strokes made in the cell, newest first; at the page's step it
    /// stops, and redo puts back only what was taken back there.
    func testUndoInACellStepsThroughItsOwnStrokesAndStopsAtThePage() {
        page()
        ink(cellA, at: CGPoint(x: 150, y: 330))
        ink(cellA, at: CGPoint(x: 250, y: 360))
        XCTAssertEqual(strokes(in: cellA), 2)
        XCTAssertTrue(store.canUndoDrawing(inCell: cellA.id))

        XCTAssertTrue(store.undoDrawing(inCell: cellA.id))
        XCTAssertEqual(strokes(in: cellA), 1)
        XCTAssertTrue(store.undoDrawing(inCell: cellA.id))
        XCTAssertEqual(strokes(in: cellA), 0)
        XCTAssertEqual(store.drawing.strokes.count, 1)

        XCTAssertFalse(store.canUndoDrawing(inCell: cellA.id), "the next step back is the page's")
        XCTAssertFalse(store.undoDrawing(inCell: cellA.id), "and the cell's undo does not reach it")
        XCTAssertEqual(store.drawing.strokes.count, 1, "the page's stroke is where it was")

        XCTAssertTrue(store.redoDrawing(inCell: cellA.id))
        XCTAssertEqual(strokes(in: cellA), 1)
        XCTAssertTrue(store.redoDrawing(inCell: cellA.id))
        XCTAssertEqual(strokes(in: cellA), 2)
        XCTAssertFalse(store.canRedoDrawing(inCell: cellA.id))
        XCTAssertFalse(store.redoDrawing(inCell: cellA.id), "nothing more was taken back")
    }

    /// A step on the page, or in another cell, on top of the cell's own is
    /// not the cell's to take back.
    func testAStepOnThePageOrInAnotherCellIsNotTheCellsToUndo() {
        ink(cellA, at: CGPoint(x: 150, y: 330))
        ink(cellB, at: CGPoint(x: 150, y: 490))
        XCTAssertFalse(store.canUndoDrawing(inCell: cellA.id), "the newest step is cell B's")
        XCTAssertTrue(store.canUndoDrawing(inCell: cellB.id))
        XCTAssertFalse(store.undoDrawing(inCell: cellA.id))
        XCTAssertEqual(strokes(in: cellB), 1)
        XCTAssertEqual(strokes(in: cellA), 1)

        page()
        XCTAssertFalse(store.canUndoDrawing(inCell: cellB.id))
        XCTAssertTrue(store.undoDrawing(), "the whole drawing's undo is as it always was: the page's stroke")
        XCTAssertTrue(store.canUndoDrawing(inCell: cellB.id), "and then cell B's is the newest again")
        XCTAssertTrue(store.undoDrawing(inCell: cellB.id))
        XCTAssertEqual(strokes(in: cellB), 0)
        XCTAssertEqual(strokes(in: cellA), 1, "never the other cell's")
    }

    /// Redo is the cell's too: what is next to put back must be the cell's.
    func testRedoInACellPutsBackOnlyTheCellsOwnStep() {
        ink(cellA, at: CGPoint(x: 150, y: 330))
        page()
        XCTAssertTrue(store.undoDrawing(), "the page's stroke goes")
        XCTAssertFalse(store.canRedoDrawing(inCell: cellA.id), "the next step to put back is the page's")
        XCTAssertFalse(store.redoDrawing(inCell: cellA.id))
        XCTAssertEqual(store.drawing.strokes.count, 0, "the page's stroke was not put back from inside the cell")
        XCTAssertTrue(store.redoDrawing())
        XCTAssertEqual(store.drawing.strokes.count, 1)
    }

    /// No cell at all is the whole drawing's undo, exactly as before.
    func testNoCellIsTheWholeDrawingsUndo() {
        page()
        ink(cellA, at: CGPoint(x: 150, y: 330))
        XCTAssertTrue(store.canUndoDrawing(inCell: nil))
        XCTAssertTrue(store.undoDrawing(inCell: nil))
        XCTAssertEqual(strokes(in: cellA), 0)
        XCTAssertTrue(store.undoDrawing(inCell: nil))
        XCTAssertEqual(store.drawing.strokes.count, 0)
        XCTAssertFalse(store.undoDrawing(inCell: nil))
        XCTAssertTrue(store.redoDrawing(inCell: nil))
    }
}
