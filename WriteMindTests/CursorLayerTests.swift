import AppKit
import XCTest
@testable import WriteMind

/// The pen's pencil belongs to the note pane and nowhere else.
final class CursorLayerTests: XCTestCase {
    private let pane = CGRect(x: 0, y: 0, width: 400, height: 600)

    private func cursor(at point: CGPoint, wasInside: Bool,
                        _ cursor: NSCursor? = DrawingCursors.pencil) -> NSCursor? {
        CursorLayer.CursorRectView.cursor(cursor, at: point, in: pane, wasInside: wasInside)
    }

    func testThePencilIsShownOverTheNote() {
        XCTAssertTrue(cursor(at: CGPoint(x: 200, y: 300), wasInside: false) === DrawingCursors.pencil)
        XCTAssertTrue(cursor(at: CGPoint(x: 200, y: 300), wasInside: true) === DrawingCursors.pencil)
    }

    func testLeavingTheNoteTakesThePencilBack() {
        // The camera pane sets no cursor of its own, so the pencil would
        // stick there unless the arrow is put back on the way out.
        XCTAssertTrue(cursor(at: CGPoint(x: 900, y: 300), wasInside: true) === NSCursor.arrow)
    }

    // MARK: - The other way out: off the window altogether

    func testThePencilIsHandedBackWhenThePointerLeavesTheApp() {
        // A global mouse-moved, the window losing key, the app going
        // inactive: each says the pointer is somewhere this app cannot
        // draw on, and nothing else will ever put the arrow back.
        XCTAssertEqual(CursorLayer.CursorRectView.reclaimed(cursor: DrawingCursors.pencil,
                                                            wasInside: true),
                       NSCursor.arrow)
    }

    func testNothingIsHandedBackIfThePointerWasNotOursToBeginWith() {
        XCTAssertNil(CursorLayer.CursorRectView.reclaimed(cursor: DrawingCursors.pencil,
                                                          wasInside: false))
    }

    func testWithThePenDownThereIsNothingToHandBack() {
        XCTAssertNil(CursorLayer.CursorRectView.reclaimed(cursor: nil, wasInside: true))
    }

    func testNothingIsForcedOnAPointerThatWasNeverOverTheNote() {
        // Otherwise every mouse move anywhere in the window would fight the
        // split divider's resize cursor and the gutter's pointing hand.
        XCTAssertNil(cursor(at: CGPoint(x: 900, y: 300), wasInside: false))
    }

    func testWithThePenDownTheLayerAsksForNothing() {
        XCTAssertNil(cursor(at: CGPoint(x: 200, y: 300), wasInside: true, nil))
        XCTAssertNil(cursor(at: CGPoint(x: 900, y: 300), wasInside: true, nil))
    }
}

/// The camera pane claims the arrow, so the pen's pencil cannot follow the
/// pointer out of the note (Sean, 2026-09-20: "cursor only becomes a pen in
/// the notes pane in drawing mode!!!!!").
final class CursorOutsideTheNoteTests: XCTestCase {
    func testTheLayerAnswersWithWhateverCursorItIsGiven() {
        let pane = CGRect(x: 0, y: 0, width: 300, height: 300)
        XCTAssertTrue(CursorLayer.CursorRectView.cursor(.arrow, at: CGPoint(x: 10, y: 10),
                                                        in: pane, wasInside: false) === NSCursor.arrow)
    }

    func testAClaimedArrowBeatsWhateverWasSetBefore() {
        // What the camera pane does: it claims the arrow for its own area,
        // so the pencil set over the note does not carry into it.
        let pane = CGRect(x: 0, y: 0, width: 300, height: 300)
        let inside = CursorLayer.CursorRectView.cursor(.arrow, at: CGPoint(x: 150, y: 150),
                                                       in: pane, wasInside: true)
        XCTAssertTrue(inside === NSCursor.arrow)
    }

    func testTheNoteStillGetsThePencilBack() {
        let pane = CGRect(x: 0, y: 0, width: 300, height: 300)
        XCTAssertTrue(CursorLayer.CursorRectView.cursor(DrawingCursors.pencil,
                                                        at: CGPoint(x: 150, y: 150),
                                                        in: pane, wasInside: false)
                      === DrawingCursors.pencil)
    }
}

/// DRAWING IS ON THE RENDERED PAGE ONLY (Sean, 2026-10-02: "only allow
/// drawing in wysiwyg mode, both from wacom and from the pen cursor
/// tool"). It was the other way for a day — "drawing should be allowed in
/// either wysiwyg and markdown mode", 2026-09-19 — and what was drawn
/// still shows in both; it is DRAWING that has one place. Picking a tool
/// in the markdown view brings the rendered page up under it, and coming
/// back to markdown puts the tools down.
@MainActor
final class PenAcrossModesTests: XCTestCase {
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

    private let mark = ShapeItem.Kind.check
    private let box = ShapeItem.Kind.rectangle

    func testEveryDrawingToolPickedInMarkdownBringsTheRenderedPageUp() {
        let picks: [(String, (AppState) -> Void)] = [
            ("the pen", { $0.canvasMode = .pen }),
            ("⌘P", { $0.togglePen() }),
            ("a box", { $0.arm(.shape(self.box)) }),
            ("a mark", { $0.arm(.shape(self.mark)) }),
            ("a line", { $0.arm(.line(start: .none, end: .arrow)) }),
            ("the arrow tool", { $0.connectActive = true }),
        ]
        for (name, pick) in picks {
            // The pen is remembered between launches: a fresh start each.
            UserDefaults.standard.removePersistentDomain(forName: suite)
            let app = state()
            XCTAssertEqual(app.mode, .editor)
            pick(app)
            XCTAssertEqual(app.mode, .preview, "\(name) was picked and the markdown view stayed up")
            XCTAssertTrue(app.canvasOwnsPane, "\(name) lost its tool to the switch")
        }
    }

    func testThePenStaysUpWhileTheRenderedPageIsUpAndGoesDownWhenMarkdownReturns() {
        let app = state()
        app.canvasMode = .pen
        app.toggleMode()
        XCTAssertEqual(app.mode, .editor)
        XCTAssertFalse(app.penActive, "the pen was left up over a view it cannot draw on")
        XCTAssertFalse(app.canvasOwnsPane, "the notes have the pane back")
        app.toggleMode()
        XCTAssertEqual(app.mode, .preview)
        XCTAssertFalse(app.penActive, "the pen does not come back by itself")
    }

    func testEveryToolIsPutAwayOnTheWayBackToMarkdown() {
        let app = state()
        app.arm(.shape(mark))
        app.toggleMode()
        XCTAssertNil(app.placing)
        app.connectActive = true
        app.toggleMode()
        app.toggleMode()
        XCTAssertFalse(app.connectActive)
        XCTAssertFalse(app.canvasOwnsPane)
    }

    func testPuttingTheToolDownLeavesTheRenderedPageUp() {
        let app = state()
        app.canvasMode = .pen
        app.canvasMode = .cursor
        XCTAssertEqual(app.mode, .preview, "putting a tool away is not a reason to switch views")
    }

    /// The pen's mode is remembered across a launch, and a launch always
    /// starts on the markdown view: the two are not allowed to disagree.
    func testAPenRememberedFromLastTimeComesUpOnTheRenderedPage() {
        let last = state()
        last.canvasMode = .pen
        let app = state()
        XCTAssertTrue(app.penActive)
        XCTAssertEqual(app.mode, .preview, "a launch came up with the pen over the markdown view")
    }

    /// The tablet writing in the notebook is drawing too.
    func testWritingOnTheNotebookFromTheTabletBringsTheRenderedPageUp() {
        let app = state()
        app.writeOn(.page)
        XCTAssertEqual(app.mode, .editor, "the tablet's own page is not the notes")
        app.writeOn(.notebook)
        XCTAssertEqual(app.mode, .preview)
    }

    /// The pen's line on the tablet's page says why it is not writing.
    func testTheTabletSaysWhyItIsNotWritingWhileTheNotesShowMarkdown() {
        XCTAssertEqual(TabletPane.setAsideLine(notesShowing: false, rendered: false),
                       "Show the rendered page (⌘T) to write on the notes — the pen is a pointer until then")
        XCTAssertEqual(TabletPane.setAsideLine(notesShowing: false, rendered: true),
                       "No note on screen to write in — the pen is a pointer until there is")
        XCTAssertEqual(TabletPane.setAsideLine(notesShowing: true, rendered: true),
                       "The pen is writing on the notebook")
    }
}
