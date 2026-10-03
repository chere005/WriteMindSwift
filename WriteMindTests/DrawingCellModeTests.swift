import AppKit
import CoreGraphics
import XCTest
@testable import WriteMind

// A DRAWING CELL IS STATIC, AND CLICKING INTO IT IS THE ONE WAY TO DRAW IN IT
// (Sean, 2026-10-03: "drawing cells are static unless you enter click into
// it, which forces you into a drawing mode where you can only draw in that
// cell (mouse or wacom into cell (if wacom is in write on notebook mode))
// otherwise you can select and insert like normal or page capture by
// selection from a document camera").
//
// This file holds the rules as the pure functions and the state machines the
// canvas, the store and the tablet ask — a SwiftUI drag cannot be driven from
// a test (the window is never key, and the gesture does not fire for a
// synthesized event), so what a press DOES is decided in one place that can
// be walked.

/// A cell drawn 400 wide, shown at three quarters (300 wide) at (28, 300),
/// and the pane it is on.
private let pane = CGSize(width: 800, height: 600)
private let frame = CellFrame(id: UUID(), line: NSRange(location: 20, length: 59),
                              rect: CGRect(x: 28, y: 300, width: 300, height: 90), scale: 0.75, width: 400,
                              writable: true)

final class StaticDrawingCellTests: XCTestCase {
    /// WHICH SPACE A PRESS IS IN. A cell nobody has entered is not a space at
    /// all: whatever is under the point, the press is the floating layer's.
    /// In cursor mode a drag on a cell's paper used to draw in it, and the
    /// pencil was the pointer over every cell on the page (Sean, 2026-10-03:
    /// "drawing mode seems to keep turning itself on as i'm trying to
    /// navigate").
    func testACellNobodyEnteredIsNoSpaceAtAll() {
        let floating = Stroke(colorHex: "#000000", width: 4,
                              points: [CGPoint(x: 0.05, y: 0.55), CGPoint(x: 0.5, y: 0.55)])
        let layer = Drawing(strokes: [floating])
        let inked = Stroke(colorHex: "#000000", width: 4,
                           points: [CGPoint(x: 0.25, y: 0.15), CGPoint(x: 0.3, y: 0.15)])
        let cells = [frame.id: DrawingCell(width: 400, aspect: 0.3, drawing: Drawing(strokes: [inked]))]
        func at(_ x: CGFloat, _ y: CGFloat, entered: UUID? = nil) -> (space: CanvasSpaceID, item: UUID?) {
            CanvasSpace.at(CGPoint(x: x, y: y), layer: layer, pane: pane, frames: [frame], cells: cells,
                           entered: entered)
        }
        XCTAssertEqual(at(250, 380).space, .floating, "the paper of a cell nobody entered took a press")
        XCTAssertNil(at(250, 380).item)
        XCTAssertEqual(at(103, 345).space, .floating, "nor did its ink, which is the picture's")
        XCTAssertNil(at(103, 345).item, "a cell's own stroke was picked up from outside the cell")
        XCTAssertEqual(at(200, 330).space, .floating)
        XCTAssertEqual(at(200, 330).item, floating.id, "a floating object over a static cell is still the layer's")
    }

    /// The tablet's nib in the notebook: a stroke begun over a static cell is
    /// floating ink over it, exactly as over any other part of the page. It
    /// used to go into the cell — "whatever the pen mode or tablet is doing,
    /// nothing draws into it".
    @MainActor
    func testATabletStrokeBegunOverAStaticCellFloatsOverIt() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-static-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("# Sketch\n".utf8).write(to: dir.appending(path: "Sketch.md"))
        let store = NoteStore(directory: dir)
        store.canvasSize = pane
        store.cellFrames = [frame]
        // Inside the cell: (150, 330) on the pane.
        let stroke = Stroke.starting(at: CGPoint(x: 150.0 / 800.0, y: 330.0 / 600.0), colorHex: "#1C1C1E", width: 3,
                                     pen: .pen(pressure: 0.5), tool: .pen)
        XCTAssertTrue(store.inkFromTablet(stroke))
        XCTAssertEqual(store.drawing.strokes.count, 1, "the stroke over a static cell did not float")
        XCTAssertTrue(store.cells.isEmpty, "and the cell was drawn in")
        XCTAssertEqual(store.drawingSteps, 1)
    }
}

// MARK: - Cell drawing mode: the pure rules

/// WHAT A PRESS ABOUT A DRAWING CELL IS (`CellDrawing.contact`). Nothing is
/// drawn into a cell nobody entered; a CLICK on one — a press that never
/// travelled — enters it; inside the entered cell every press is the cell's,
/// and outside it every press is the way out.
final class CellDrawingContactTests: XCTestCase {
    private let inside = CGPoint(x: 150, y: 330)
    private let outside = CGPoint(x: 600, y: 100)
    private func contact(_ point: CGPoint, entered: UUID? = nil, frames: [CellFrame] = [frame],
                         covered: Bool = false, tool: Bool = false,
                         command: Bool = false) -> CellDrawing.Contact {
        CellDrawing.contact(at: point, entered: entered, frames: frames, coveredByObject: covered, tool: tool,
                            command: command)
    }

    func testAPressOnAStaticCellIsAClickThatMayEnterIt() {
        XCTAssertEqual(contact(inside), .click(frame.id))
        XCTAssertEqual(contact(outside), .none, "off every cell it is the page's press")
    }

    /// An object over the cell is what is clicked; an armed shape, mark or
    /// arrow tool does its own thing where it is pressed (a tick goes down
    /// ON the cell, floating); ⌘ is the marquee.
    func testSomethingElseOnTheCellIsNotAClickIntoIt() {
        XCTAssertEqual(contact(inside, covered: true), .none, "a floating object over the cell takes the click")
        XCTAssertEqual(contact(inside, tool: true), .none, "an armed tool puts its thing down")
        XCTAssertEqual(contact(inside, command: true), .none, "⌘ is the selector")
        var readOnly = frame
        readOnly.writable = false
        XCTAssertEqual(contact(inside, frames: [readOnly]), .none, "a read-only cell is nothing to enter")
    }

    func testInTheEnteredCellEveryPressIsTheCellsWhateverIsOverIt() {
        XCTAssertEqual(contact(inside, entered: frame.id), .drawing(frame.id))
        XCTAssertEqual(contact(inside, entered: frame.id, covered: true), .drawing(frame.id),
                       "nothing else on the page reacts: a floating object over the cell is not reached")
        XCTAssertEqual(contact(inside, entered: frame.id, command: true), .drawing(frame.id),
                       "⌘ is still the marquee, in the cell")
    }

    /// A press outside the entered cell — on the page, on another cell, on
    /// nothing — is the way out; the canvas leaves the mode and asks again,
    /// so another cell clicked is entered in its turn.
    func testAPressOutsideTheEnteredCellIsTheWayOut() {
        XCTAssertEqual(contact(outside, entered: frame.id), .leaving)
        let other = CellFrame(id: UUID(), line: NSRange(location: 90, length: 59),
                              rect: CGRect(x: 28, y: 420, width: 300, height: 90), scale: 0.75, width: 400,
                              writable: true)
        XCTAssertEqual(contact(CGPoint(x: 100, y: 450), entered: frame.id, frames: [frame, other]), .leaving)
        XCTAssertEqual(contact(CGPoint(x: 100, y: 450), frames: [frame, other]), .click(other.id),
                       "and asked again with nothing entered, it is a click into the other")
        XCTAssertEqual(contact(inside, entered: UUID()), .leaving, "a cell that is gone holds nothing")
    }

    /// The layer takes a press on every writable cell's paper to see whether
    /// it is a click — it never draws there — and none on a read-only one.
    func testTheLayerTakesAPressOnEveryWritableCellsPaperToSeeIfItIsAClick() {
        var readOnly = frame
        readOnly.id = UUID()
        readOnly.writable = false
        XCTAssertEqual(CellDrawing.paperTaken(frames: [frame, readOnly]), [frame.rect])
        XCTAssertEqual(CellDrawing.paperTaken(frames: []), [])
    }

    /// A CLICK IS A PRESS THAT NEVER TRAVELLED: under three points. A click
    /// leaves no dot and no empty step; one that moves is whatever the
    /// pen or the cursor makes of a drag.
    func testAClickIsAPressUnderThreePoints() {
        XCTAssertEqual(CellDrawing.clickTravel, 3)
        XCTAssertTrue(CellDrawing.isClick(travelled: 0))
        XCTAssertTrue(CellDrawing.isClick(travelled: 2.9))
        XCTAssertFalse(CellDrawing.isClick(travelled: 3))
    }

    /// CLIPPED TO THE CELL: a point goes into the cell's own fractions held
    /// inside it on every side — x in 0…1, y in 0…the cell's height over its
    /// width (120 high at 400 wide: 0.3) — so a stroke dragged out of a cell
    /// runs along its edge and nothing is left outside it.
    func testAPointIsHeldInsideTheCellOnEverySide() {
        func held(_ x: Double, _ y: Double) -> CGPoint { CellDrawing.hold(CGPoint(x: x, y: y), in: frame) }
        XCTAssertEqual(held(0.5, 0.1), CGPoint(x: 0.5, y: 0.1), "inside is untouched")
        XCTAssertEqual(held(-0.2, 0.1), CGPoint(x: 0, y: 0.1))
        XCTAssertEqual(held(1.4, 0.1), CGPoint(x: 1, y: 0.1))
        XCTAssertEqual(held(0.5, -0.3), CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(held(0.5, 0.9).x, 0.5)
        XCTAssertEqual(held(0.5, 0.9).y, 0.3, accuracy: 1e-12, "the bottom edge: 90 ÷ 0.75 ÷ 400")
        XCTAssertEqual(CellDrawing.hold(document: CGPoint(x: 5, y: 700), in: frame.rect),
                       CGPoint(x: 28, y: 390), "and the same in the page's points")
        XCTAssertEqual(CellDrawing.hold(document: CGPoint(x: 100, y: 350), in: frame.rect), CGPoint(x: 100, y: 350))
    }

    /// The mode ends when its cell goes: folded away, read-only, out of the
    /// note.
    func testACellCanBeEnteredOnlyWhileItHasAWritableFrame() {
        XCTAssertTrue(CellDrawing.enterable(frame.id, in: [frame]))
        XCTAssertFalse(CellDrawing.enterable(frame.id, in: []), "folded away: no frame")
        var readOnly = frame
        readOnly.writable = false
        XCTAssertFalse(CellDrawing.enterable(frame.id, in: [readOnly]))
        XCTAssertFalse(CellDrawing.enterable(UUID(), in: [frame]))
    }

    /// THE MODE CAN END UNDER A PRESS (Esc, ⌘P, the cell folding away: the
    /// button is down while a key is pressed). A press under way in a cell
    /// that is still there stays the cell's until it ends — its points are in
    /// the cell's own fractions, and carried on to the page they were a
    /// mis-scaled stroke on the floating layer — and in a cell that is gone it
    /// is dropped; with none under way the layer's space is back at once.
    func testAPressUnderWayStaysTheCellsUntilItEnds() {
        typealias Leaving = CellDrawing.Departure
        XCTAssertEqual(CellDrawing.departure(pressUnderWay: false, cellThere: true), Leaving.now)
        XCTAssertEqual(CellDrawing.departure(pressUnderWay: false, cellThere: false), Leaving.now)
        XCTAssertEqual(CellDrawing.departure(pressUnderWay: true, cellThere: true), Leaving.whenPressEnds,
                       "a stroke began in the cell: it is finished in it, never on the page")
        XCTAssertEqual(CellDrawing.departure(pressUnderWay: true, cellThere: false), Leaving.dropPress,
                       "and with the cell gone nothing of it can land")
    }

    /// In a cell the press draws wherever it lands in it — the cursor never
    /// did and still does not outside — and ⌘ is the marquee.
    func testInAnEnteredCellAPressDrawsAndCommandIsStillTheMarquee() {
        typealias Mode = AppState.CanvasMode
        XCTAssertEqual(Mode.cursor.press(with: [], inEnteredCell: true), .draw)
        XCTAssertEqual(Mode.cursor.press(with: [.command], inEnteredCell: true), .marquee)
        XCTAssertEqual(Mode.cursor.press(with: [], inEnteredCell: false), .objects, "outside it is the cursor's")
    }
}

// MARK: - Cell drawing mode: the state machine

/// ENTERING IS EXPLICIT AND LEAVING IS GUARANTEED. A click into a cell
/// enters it (`AppState.enterCell`); Esc, a click outside, another note, a
/// pane or a mode switch, the Done control and another tool each leave it;
/// nothing between strokes does.
@MainActor
final class CellDrawingStateTests: XCTestCase {
    private var suite: String!
    private var dir: URL!
    private let cell = UUID()
    private let other = UUID()

    override func setUp() {
        super.setUp()
        suite = "WriteMindTests-\(UUID().uuidString)"
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-cellmode-\(UUID().uuidString)")
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// An app on the rendered page: cells are entered there and nowhere else.
    private func state() -> AppState {
        let app = AppState(defaults: UserDefaults(suiteName: suite)!)
        app.mode = .preview
        return app
    }

    func testClickingIntoACellEntersItAndTheNotebookKeepsEverythingElse() {
        let app = state()
        XCTAssertNil(app.cellDrawing, "nothing is entered by being there")
        app.enterCell(cell)
        XCTAssertEqual(app.cellDrawing, cell)
        XCTAssertFalse(app.canvasOwnsPane, "the notebook still has the page round the cell: clicks, bars, brackets")
        XCTAssertEqual(app.canvasMode, .cursor)
        app.enterCell(other)
        XCTAssertEqual(app.cellDrawing, other, "a click into another cell is that cell's mode")
    }

    /// The markdown view shows a cell as a picture and nothing is drawn
    /// there: the rendered page owns the mode.
    func testACellInTheMarkdownViewCannotBeEntered() {
        let app = AppState(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(app.mode, .editor)
        app.enterCell(cell)
        XCTAssertNil(app.cellDrawing)
    }

    /// ONE TOOL AT A TIME, both ways round: entering puts the pen, the arrow
    /// tool and an armed shape away, and picking any of them leaves the cell.
    func testOneToolAtATimeTheCellIncluded() {
        let tools: [(String, (AppState) -> Void)] = [
            ("the pen", { $0.canvasMode = .pen }),
            ("⌘P", { $0.togglePen() }),
            ("the arrow tool", { $0.connectActive = true }),
            ("an armed box", { $0.arm(.shape(.rectangle)) }),
            ("an armed tick", { $0.arm(.shape(.check)) }),
        ]
        for (name, pick) in tools {
            let app = state()
            pick(app)
            app.enterCell(cell)
            XCTAssertEqual(app.cellDrawing, cell, "entering with \(name) in hand")
            XCTAssertFalse(app.canvasOwnsPane, "\(name) was left in hand in the cell")
            pick(app)
            XCTAssertNil(app.cellDrawing, "\(name) was picked and the cell stayed entered")
            XCTAssertTrue(app.canvasOwnsPane)
        }
    }

    /// EVERY WAY OUT, but Esc — which is a key, and is sent through the real
    /// editor pane in `EscapeWiringTests`.
    func testEveryWayOutLeavesTheCell() throws {
        let doneControl: (String, (AppState) -> Void) = ("the Done control", { $0.endCellDrawing() })
        let ways: [(String, (AppState) -> Void)] = [
            doneControl,
            ("markdown", { $0.toggleMode() }),
            ("the notes pane going", { $0.showEditor = false }),
            ("the video pane going", { $0.showCamera = false }),
            ("the window given to the picture", { $0.cameraFullWindow = true }),
            ("a tablet picked", { $0.follow(tabletPicked: true) }),
            ("a way onto the page", { $0.putToolsAway() }),
        ]
        for (name, leave) in ways {
            let app = state()
            app.enterCell(cell)
            XCTAssertEqual(app.cellDrawing, cell)
            leave(app)
            XCTAssertNil(app.cellDrawing, "\(name) left the cell entered")
        }
        // Another note.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# One\n".utf8).write(to: dir.appending(path: "One.md"))
        try Data("# Two\n".utf8).write(to: dir.appending(path: "Two.md"))
        let store = NoteStore(directory: dir)
        let app = state()
        app.watchNotes(of: store)
        app.enterCell(cell)
        let next = try XCTUnwrap(store.notes.map(\.id).first { $0 != store.selection })
        store.openTab(next)
        XCTAssertNil(app.cellDrawing, "another note kept the cell entered")
    }

    /// IT DOES NOT END BY ITSELF BETWEEN STROKES: a stroke landing, the note
    /// typed in, the drawing changing — the mode is Sean's until he leaves.
    func testItDoesNotEndByItselfBetweenStrokes() {
        let app = state()
        app.enterCell(cell)
        app.drawingChanged(steps: 1)
        app.inkedNote(above: 0)
        app.drawingChanged(steps: 2)
        app.noteTyped()
        app.pageWritten()
        app.notebookChanged()
        app.showSidebar.toggle()
        app.follow(tabletPicked: false)
        app.showCamera = true
        XCTAssertEqual(app.cellDrawing, cell)
    }

    /// Undo and redo are the cell's own while it is entered, and are claimed
    /// even with the keyboard in the note's text.
    func testUndoIsTheCellsWhileItIsEntered() {
        let app = state()
        XCTAssertFalse(app.drawingOwnsUndo)
        app.enterCell(cell)
        XCTAssertTrue(app.drawingOwnsUndo)
        XCTAssertTrue(app.drawingOwnsRedo)
        app.endCellDrawing()
        XCTAssertFalse(app.drawingOwnsUndo)
    }

    /// IT SHOWS: the footer says where the drawing goes and how to stop it.
    func testTheFooterNamesTheCell() {
        let app = state()
        app.enterCell(cell)
        XCTAssertEqual(app.toolLines.map(\.words), ["Drawing in a cell: Esc or Done to finish"])
        for line in app.toolLines {
            XCTAssertNotNil(NSImage(systemSymbolName: line.symbol, accessibilityDescription: nil), line.symbol)
        }
        app.endCellDrawing()
        XCTAssertEqual(app.toolLines, [])
    }

    /// EXPLICIT: a cell is entered from a click on it — the layer's, or the
    /// nib's tap through the tablet's notebook mode — and from nothing else,
    /// read off the sources so a new way in fails here.
    func testACellIsEnteredOnlyByAClickIntoIt() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "WriteMind", directoryHint: .isDirectory)
        let sources = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
        var callers: [String] = []
        for file in sources {
            for (index, raw) in (try String(contentsOf: file, encoding: .utf8)).components(separatedBy: "\n").enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("//"), line.contains("enterCell(") || line.contains(".cellDrawing =") else { continue }
                callers.append("\(file.lastPathComponent):\(line)")
            }
        }
        let allowed = ["AppState.swift", "EditorPane.swift", "TabletNotebook.swift"]
        for caller in callers {
            XCTAssertTrue(allowed.contains { caller.hasPrefix($0) }, "a cell is entered from \(caller)")
        }
        XCTAssertTrue(callers.contains { $0.hasPrefix("EditorPane.swift") }, "the layer's click enters one")
        XCTAssertTrue(callers.contains { $0.hasPrefix("TabletNotebook.swift") }, "and so does the nib's tap")
    }
}

// MARK: - The canvas's press glue, read

/// THE GESTURE GLUE CANNOT BE RUN HERE (a SwiftUI drag does not fire for a
/// synthesized event in a window that is never key), so the two rules of the
/// review of 2026-10-03 that live in it — a press the cell mode ends under is
/// finished in the cell or dropped and never goes on onto the page, and a
/// stroke in a cell claims ⌘Z — are held at the call sites by reading
/// `DrawingCanvas.swift`. The decisions they ask for are walked
/// (`CellDrawing.departure`, `CellInkClaimsUndoTests`); what this holds is that
/// the glue still asks them.
final class CellPressGlueTests: XCTestCase {
    private func canvasSource() throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "WriteMind/Drawing/DrawingCanvas.swift")
        return try String(contentsOf: file, encoding: .utf8)
    }

    /// The text from the first `start` after `from` to the next `end` after
    /// it (or the end of the file).
    private func text(_ source: String, from start: String, to end: String?) throws -> String {
        let begin = try XCTUnwrap(source.range(of: start), "\(start) is gone from DrawingCanvas.swift")
        let rest = source[begin.lowerBound...]
        guard let end, let stop = rest.dropFirst(start.count).range(of: end) else { return String(rest) }
        return String(rest[..<stop.lowerBound])
    }

    /// EVERY PLACE THAT LEAVES THE ACTIVE CELL asks `leave(cell:cellThere:)`,
    /// which asks `CellDrawing.departure`: a bare `enter(.floating)` in these
    /// handlers took the layer's space from a stroke under way, and the rest
    /// of it was appended in pane fractions to a stroke begun in cell
    /// fractions.
    func testTheHandlersThatEndTheCellAsTheSpaceAskTheDepartureRule() throws {
        let source = try canvasSource()
        for (name, start, end) in [
            ("the mode ending", ".onChange(of: enteredCell)", ".onChange(of: selection)"),
            ("the cell folding away", ".onChange(of: cellFrames)", ".onChange(of: deselectToken)"),
            ("another note", ".onChange(of: documentID)", ".onChange(of: cellFrames)"),
        ] {
            let body = try text(source, from: start, to: end)
            XCTAssertTrue(body.contains("leave(cell:"), "\(name) does not ask what becomes of a press under way")
            XCTAssertFalse(body.contains("enter(.floating)"), "\(name) takes the layer's space from a press under way")
        }
        let leave = try text(source, from: "private func leave(cell:", to: "/// A press at `panePoint`")
        XCTAssertTrue(leave.contains("CellDrawing.departure(pressUnderWay: interaction != nil"),
                      "leaving no longer asks the one rule")
    }

    /// A PRESS ENDS IN ONE PLACE, `pressEnded()`, which gives the layer its
    /// space back once the press the mode ended under is over: a gesture that
    /// reset `interaction` itself left `leaveWhenPressEnds` set for the next
    /// press and the layer's space never came back.
    func testEveryPressEndsThroughThePlaceThatGivesTheLayerItsSpaceBack() throws {
        let source = try canvasSource()
        XCTAssertEqual(source.components(separatedBy: "interaction = nil").count - 1, 1,
                       "something other than pressEnded() puts a press down")
        let ended = try text(source, from: "private func pressEnded()", to: "private enum Interaction")
        XCTAssertTrue(ended.contains("leaveWhenPressEnds"), "pressEnded() no longer gives the layer its space back")
        XCTAssertTrue(ended.contains("enter(.floating)"))
        // The three drags that carry a press end through it.
        XCTAssertEqual(source.components(separatedBy: "pressEnded()").count - 1, 4,
                       "the main drag, the handles' and the connector's end through pressEnded(), and its own definition")
    }

    /// A STROKE'S FIRST POINT CLAIMS ⌘Z through `beginInk()`: the call that
    /// takes the step back for a stroke is never made bare, so a stroke in a
    /// cell tells `onCursorInk` first, as the nib's does.
    func testAStrokeBeginsThroughTheCallThatClaimsCmdZ() throws {
        let source = try canvasSource()
        let start = try text(source, from: "if current == nil {", to: "current = Stroke.starting(")
        XCTAssertTrue(start.contains("beginInk()"), "a stroke began without claiming ⌘Z for a cell")
        XCTAssertFalse(start.contains("onBeginChange?()"), "a stroke takes its step without asking beginInk()")
        let ink = try text(source, from: "private func beginInk()", to: "/// THE ACTIVE CELL CAN BE")
        let claim = try XCTUnwrap(ink.range(of: "onCursorInk?()"), "beginInk() no longer claims ⌘Z")
        let step = try XCTUnwrap(ink.range(of: "onBeginChange?()"), "beginInk() no longer takes the step")
        XCTAssertLessThan(claim.lowerBound, step.lowerBound, "the claim is told before the step is taken")
        XCTAssertTrue(ink.contains("if case .cell = active"), "and only for a stroke in a cell")
    }
}
