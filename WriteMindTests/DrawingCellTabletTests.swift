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
