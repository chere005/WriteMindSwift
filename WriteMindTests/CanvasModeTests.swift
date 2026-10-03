import AppKit
import XCTest
@testable import WriteMind

/// Two modes over one pane, and only one of them is the notebook's (Sean,
/// 2026-09-21: "clicking the pen outside of the dropdown is the toggle
/// between pen and cursor.. in both modes holding cmd is how to get the
/// selector").
@MainActor
final class CanvasModeTests: XCTestCase {
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

    func testCursorModeIsTheOnlyOneThatLetsTheNotebookHaveThePane() {
        let app = state()
        XCTAssertEqual(app.canvasMode, .cursor, "a pane with no tool picked is the notebook's")
        XCTAssertFalse(app.canvasOwnsPane)
        XCTAssertFalse(app.penActive)

        app.canvasMode = .pen
        XCTAssertTrue(app.canvasOwnsPane)
        XCTAssertTrue(app.penActive, "the pen is the mode now, not a flag beside it")

        app.canvasMode = .cursor
        XCTAssertFalse(app.canvasOwnsPane)
    }

    /// Sean, 2026-10-02: "esc should exit pen mode". Taken only when there
    /// was a pen to put down, so Esc in cursor mode is still everyone
    /// else's.
    func testEscapePutsThePenDownAndOnlyTakesTheKeyWhenItDid() {
        let app = state()
        XCTAssertFalse(app.escapePen(), "no pen up: the key is not ours")
        XCTAssertEqual(app.canvasMode, .cursor)

        app.canvasMode = .pen
        XCTAssertTrue(app.escapePen())
        XCTAssertEqual(app.canvasMode, .cursor)
        XCTAssertFalse(app.canvasOwnsPane, "the notebook has the pane back")
        XCTAssertFalse(app.escapePen(), "a second Esc has nothing to put down")
    }

    func testTheTwoToolsTakeThePaneWithoutBeingModes() {
        let app = state()
        app.connectActive = true
        XCTAssertTrue(app.canvasOwnsPane, "the arrow tool has the pane while it is on")
        XCTAssertEqual(app.canvasMode, .cursor, "and it is not a mode: the mode is still the cursor")

        app.connectActive = false
        app.placing = .shape(.oval)
        XCTAssertTrue(app.canvasOwnsPane)
        XCTAssertEqual(app.canvasMode, .cursor)
    }

    func testPickingAModePutsDownWhateverToolWasHeld() {
        let app = state()
        app.connectActive = true
        app.canvasMode = .pen
        XCTAssertFalse(app.connectActive, "one answer to what a drag does, not two")

        app.placing = .shape(.oval)
        XCTAssertEqual(app.canvasMode, .cursor, "arming a shape puts the pen down, as it always did")
        app.canvasMode = .pen
        XCTAssertNil(app.placing, "and picking a mode puts the armed shape away")
    }

    /// A shape stays armed after it is drawn (Sean, 2026-10-02: "after
    /// drawing a rectangle dont exit rectangle mode.."), so the palette is
    /// one of the ways to put it away: the same tile again.
    func testPickingTheArmedShapeAgainPutsItAway() {
        let app = state()
        app.arm(.shape(.rectangle))
        XCTAssertEqual(app.placing, .shape(.rectangle))
        app.arm(.shape(.rectangle))
        XCTAssertNil(app.placing, "the same tile twice is the way out")
        XCTAssertFalse(app.canvasOwnsPane, "and the notebook has the pane back")

        app.arm(.shape(.rectangle))
        app.arm(.shape(.oval))
        XCTAssertEqual(app.placing, .shape(.oval), "another tile is another tool, not the way out")
        app.arm(.line(start: .none, end: .arrow))
        app.arm(.line(start: .arrow, end: .arrow))
        XCTAssertEqual(app.placing, .line(start: .arrow, end: .arrow), "two heads is a different tool")
    }

    /// One tool at a time, both ways round: the arrow tool and an armed
    /// shape each put the other away. Left armed, the shape took the drag
    /// meant for the arrow, every time, now that it no longer goes back
    /// on its own.
    func testTheArrowToolAndAnArmedShapePutEachOtherAway() {
        let app = state()
        app.arm(.shape(.diamond))
        app.connectActive = true
        XCTAssertNil(app.placing, "the arrow tool picked: the diamond is put away")
        XCTAssertTrue(app.connectActive)

        app.arm(.shape(.diamond))
        XCTAssertFalse(app.connectActive, "and the other way round, as it always was")
        XCTAssertEqual(app.placing, .shape(.diamond))
    }

    /// A text box or a picture from the bar is dropped to be picked up and
    /// typed in or dragged — a shape left armed took the click that should
    /// have finished the text box and put a rectangle down instead.
    func testATextBoxOrAPictureFromTheBarPutsEveryToolAway() {
        let app = state()
        app.arm(.shape(.rectangle))
        app.putToolsAway()
        XCTAssertNil(app.placing)
        XCTAssertFalse(app.canvasOwnsPane)

        app.connectActive = true
        app.putToolsAway()
        XCTAssertFalse(app.connectActive)

        app.canvasMode = .pen
        app.putToolsAway()
        XCTAssertEqual(app.canvasMode, .cursor, "the pen is put down for it, as it always was")
        XCTAssertFalse(app.canvasOwnsPane)
    }

    /// EVERY WAY ONTO THE PAGE PUTS THE TOOLS AWAY, not only the bar's:
    /// Insert ▸ Image… (⇧⌘I) and Insert ▸ Text Box, the camera's capture
    /// and the tablet's. Each put the pen down so what arrived could be
    /// typed in or picked up, and each left a shape armed — which, now
    /// that a shape stays armed, took that click and put a box down on
    /// what had just arrived.
    func testEveryWayOntoThePagePutsTheToolsAway() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "WriteMind", directoryHint: .isDirectory)
        let sources = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
        var drops = 0
        for file in sources {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                guard ["store.addTextBox(", "store.chooseImage(", "store.captureNotebook(",
                       "store.takeFromTablet("].contains(where: line.contains) else { continue }
                drops += 1
                let before = lines[max(0, index - 6)..<index].joined(separator: "\n")
                XCTAssertTrue(before.contains("appState.putToolsAway()"),
                              "\(file.lastPathComponent):\(index + 1) drops something on the page "
                              + "with a tool still in hand")
                // And the page it lands on is the rendered one: there is no
                // drawing in markdown (Sean, 2026-10-02).
                XCTAssertTrue(before.contains("appState.showRenderedPage()"),
                              "\(file.lastPathComponent):\(index + 1) drops something on a page "
                              + "that may be the markdown view, where nothing is drawn")
            }
        }
        XCTAssertEqual(drops, 6, "the bar's Text Box, the pen menu's Add Image, the Insert menu's "
                       + "two, the camera's capture, the tablet's")
    }

    /// THE BAR LIGHTS A TOOL THAT HOLDS THE PANE: the arrow tool always
    /// did, and a shape now holds it too until it is put away. The button
    /// lit is the one whose palette has the tile — both of them for the
    /// box, the circle and the triangle the two palettes share, since
    /// either tile puts it away.
    func testTheBarLightsThePaletteThatHoldsWhatIsArmed() {
        let app = state()
        XCTAssertFalse(app.shapesLit)
        XCTAssertFalse(app.marksLit)

        app.arm(.shape(.diamond))
        XCTAssertTrue(app.shapesLit, "a diamond is on the flow chart's palette")
        XCTAssertFalse(app.marksLit)

        app.arm(.shape(.check))
        XCTAssertFalse(app.shapesLit)
        XCTAssertTrue(app.marksLit, "a tick is on the Marks palette")

        app.arm(.line(start: .arrow, end: .arrow))
        XCTAssertFalse(app.shapesLit)
        XCTAssertTrue(app.marksLit, "so are the lines")

        app.arm(.shape(.rectangle))
        XCTAssertTrue(app.shapesLit, "a box is on both")
        XCTAssertTrue(app.marksLit)

        app.connectActive = true
        XCTAssertTrue(app.shapesLit, "the arrow tool is the flow chart's")
        XCTAssertFalse(app.marksLit, "and it put the box away")

        app.putToolsAway()
        XCTAssertFalse(app.shapesLit)
        XCTAssertFalse(app.marksLit)
    }

    func testTheModeIsRememberedTheWayThePensSizeIs() {
        let first = state()
        first.canvasMode = .pen
        XCTAssertEqual(state().canvasMode, .pen, "a launch comes up where it was left")

        first.canvasMode = .cursor
        XCTAssertEqual(state().canvasMode, .cursor)
    }

    /// The part that has cost four rounds of Sean's time: whose cursor it is.
    /// Nil is not "no cursor" — it is "the notebook's", which has four of its
    /// own (the bar between two cells, the hand over the + and over the
    /// brackets, the I-beam over the words) and is not ours to overwrite.
    func testTheCursorFollowsTheModeAndIsHandedBack() {
        let app = state()
        XCTAssertNil(app.paneCursor)

        app.canvasMode = .pen
        XCTAssertTrue(app.paneCursor === DrawingCursors.pencil)

        app.canvasMode = .cursor
        XCTAssertNil(app.paneCursor, "a mode switch leaves no cursor behind it")

        app.connectActive = true
        XCTAssertTrue(app.paneCursor === NSCursor.crosshair)
        app.connectActive = false
        app.placing = .shape(.oval)
        XCTAssertTrue(app.paneCursor === NSCursor.crosshair)
        app.placing = nil
        XCTAssertNil(app.paneCursor)
    }

    func testTheModesAreThePenAndTheCursorAndNothingElse() {
        // Sean, 2026-09-21: "drop the cursor and select buttons..
        // clicking the pen outside of the dropdown is the toggle between
        // pen and cursor". Two modes and one button: the pen is down or
        // it is not, and the button says which.
        XCTAssertEqual(AppState.CanvasMode.allCases, [.cursor, .pen])
    }

    func testAPaneLeftInAModeThatIsGoneComesUpAsTheNotebooks() {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("select", forKey: "canvasMode")
        XCTAssertEqual(AppState(defaults: defaults).canvasMode, .cursor,
                       "a remembered mode that no longer exists is the notebook's")
    }

    func testCommandIsTheSelectorInBothModes() {
        // Sean, 2026-09-21: "in both modes holding cmd is how to get the
        // selector". Under the pen a ⌘-drag used to draw a stroke.
        XCTAssertEqual(AppState.CanvasMode.pen.press(with: [.command]), .marquee)
        XCTAssertEqual(AppState.CanvasMode.cursor.press(with: [.command]), .marquee)
        XCTAssertEqual(AppState.CanvasMode.pen.press(with: [.command, .shift]), .marquee,
                       "⇧ says whether it adds to what is picked, not what the drag is")
        XCTAssertEqual(AppState.CanvasMode.pen.press(with: []), .draw)
        XCTAssertEqual(AppState.CanvasMode.cursor.press(with: []), .objects)
    }

    /// WHAT A PRESS DOES IN EACH SPACE (docs/CROSS-PLATFORM.md: the press
    /// table). On a drawing cell's paper the cursor draws (Sean, 2026-10-02:
    /// "drawing cell which is cmd + 0"): the cell is for drawing in, and
    /// making him pick the pen up for each one is the step the cell was
    /// made to save. An object under the point — on the layer or in a
    /// cell — is asked before the paper, and is picked up as it always was.
    func testOnACellsPaperTheCursorDrawsOnceItHasTravelled() {
        typealias Mode = AppState.CanvasMode
        // ⌘ held: the marquee, in that space, whatever is under it.
        XCTAssertEqual(Mode.pen.press(with: [.command], onCellPaper: true), .marquee)
        XCTAssertEqual(Mode.cursor.press(with: [.command], onCellPaper: true), .marquee)
        // The pen draws anywhere — into the space under its first point.
        XCTAssertEqual(Mode.pen.press(with: [], onCellPaper: true), .draw)
        XCTAssertEqual(Mode.pen.press(with: [], onCellPaper: false), .draw)
        // The cursor: an object is picked up; the paper is drawn on.
        XCTAssertEqual(Mode.cursor.press(with: [], onCellPaper: false), .objects)
        XCTAssertEqual(Mode.cursor.press(with: [], onCellPaper: true), .paper)
        // A press on the paper becomes a stroke once a mouse has travelled
        // three points, and at once under a nib — whose touch IS ink. A
        // click that never moves leaves no dot and no empty step: it puts
        // the caret in the cell instead.
        XCTAssertEqual(Mode.paperTravel, 3)
        XCTAssertFalse(Mode.paperStrokes(travelled: 0, nib: false))
        XCTAssertFalse(Mode.paperStrokes(travelled: 2.9, nib: false))
        XCTAssertTrue(Mode.paperStrokes(travelled: 3, nib: false))
        XCTAssertTrue(Mode.paperStrokes(travelled: 0, nib: true))
    }

    /// A symbol that does not exist draws as nothing at all, and the button
    /// or the footer label is then a blank space that means something.
    func testEveryModeHasAWordAndASymbolThatExists() {
        for mode in AppState.CanvasMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.help.isEmpty)
            XCTAssertNotNil(NSImage(systemSymbolName: mode.icon, accessibilityDescription: nil),
                            "\(mode.rawValue) is drawn with \(mode.icon)")
        }
    }
}

/// What the rectangle takes. It is one rule wherever the drag came from —
/// ⌘ under the pen, ⌘ over the words, and the mode that used to be beside
/// them.
final class CanvasMarqueeTests: XCTestCase {
    private let pane = CGSize(width: 1000, height: 200)

    private func line(from: CGPoint, to: CGPoint) -> CanvasItem {
        .stroke(Stroke(colorHex: "#2D7DD2", width: 3, points: [from, to]))
    }

    func testTheMarqueeTakesEverythingItTouchesAndNothingElse() {
        let crossed = line(from: CGPoint(x: 0.1, y: 0.5), to: CGPoint(x: 0.9, y: 0.5))
        let inside = line(from: CGPoint(x: 0.47, y: 0.45), to: CGPoint(x: 0.49, y: 0.55))
        let elsewhere = line(from: CGPoint(x: 0.1, y: 0.1), to: CGPoint(x: 0.2, y: 0.1))
        let drawing = Drawing(items: [crossed, inside, elsewhere])

        // A small box in the middle of the pane: it cuts the long stroke
        // rather than holding it, which is enough (Sean, 2026-09-18: "if
        // it's in the selection rectangle, it's included, the whole drawing
        // doesn't need to be highlighted").
        let taken = drawing.ids(touching: CGRect(x: 460, y: 80, width: 40, height: 40), in: pane)
        XCTAssertEqual(taken, [crossed.id, inside.id])
    }

    func testAHiddenPictureIsNotSweptUpByTheRectangle() {
        // A picture read into words is put away, not thrown away — it cannot
        // be clicked and is not drawn, so a rectangle dragged over the empty
        // space where it used to be must not hand it to ⌫ either.
        let put = CanvasItem.image(ImageItem(file: "a.png", center: CGPoint(x: 0.5, y: 0.5),
                                             width: 0.4, hidden: true))
        let drawing = Drawing(items: [put])
        XCTAssertTrue(drawing.ids(touching: CGRect(x: 0, y: 0, width: 1000, height: 200), in: pane).isEmpty)
    }
}
