import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// Holding several cells at once (Sean, 2026-09-20: "fix selecting multiple
/// cells by clicking and dragging, shift clicking, or cmd clicking").
///
/// The gestures themselves are checked on screen; what is pinned here is the
/// arithmetic under them, which is the part that can be wrong silently.
final class CellSelectionTests: XCTestCase {
    private let note = "First cell\n\nSecond cell\n\nThird cell"
    private var cells: [NSRange] { MarkdownParser.positioned(from: note).map(\.range) }

    /// Three cells, each 20 points tall with an 8-point seam between them,
    /// the way the page stacks them.
    private var stack: [CellSelection.Span] {
        [(top: 20, bottom: 40, range: cells[0]),
         (top: 48, bottom: 68, range: cells[1]),
         (top: 76, bottom: 96, range: cells[2])]
    }

    // MARK: - An outer bracket holds the cells inside it

    /// A note with a heading and two cells under it.
    private var sectioned: String { "# Head\n\nOne\n\nTwo\n\n# Next\n\nThree" }
    private var sectionedCells: [NSRange] { MarkdownParser.positioned(from: sectioned).map(\.range) }
    private var firstSection: NSRange {
        let sections = NotebookOutline.sections(in: sectioned)
        return sections[0].range
    }

    func testASectionsBracketStandsForEveryCellUnderIt() {
        // Sean, 2026-09-21: "an outer selection isn't always grabbing
        // inner elements". The heading and the two cells below it.
        let held = CellSelection.cells(of: firstSection, in: sectionedCells)
        XCTAssertEqual(held.count, 3, "got \(held)")
        XCTAssertEqual(held.first, sectionedCells.first)
    }

    func testACellsOwnBracketStandsForItselfAndNothingElse() {
        let one = sectionedCells[1]
        XCTAssertEqual(CellSelection.cells(of: one, in: sectionedCells), [one])
    }

    func testABracketThatHoldsNoWholeCellAnswersWithItself() {
        // Half a cell is not a cell, and answering with nothing would make
        // a click do nothing at all.
        let half = NSRange(location: 1, length: 2)
        XCTAssertEqual(CellSelection.cells(of: half, in: sectionedCells), [half])
    }

    func testHoldingASectionLightsEveryBracketInsideIt() {
        let held = CellSelection.cells(of: firstSection, in: sectionedCells)
        for cell in held {
            XCTAssertTrue(CellSelection.covers(cell, held), "\(cell) should be lit")
        }
        // …and nothing in the section after it.
        XCTAssertFalse(CellSelection.covers(sectionedCells.last!, held))
    }

    func testANestedSectionComesWithItsParent() {
        let note = "# Outer\n\nOne\n\n## Inner\n\nTwo"
        let cells = MarkdownParser.positioned(from: note).map(\.range)
        let outer = NotebookOutline.sections(in: note).first { $0.depth == 0 }!
        let held = CellSelection.cells(of: outer.range, in: cells)
        XCTAssertEqual(held.count, cells.count, "the outer bracket holds the lot")
    }

    // MARK: - Dragging a bar up or down

    func testADragDownABarStartsOnTheCellBelowIt() {
        // The bar between the first two cells, at y = 44.
        XCTAssertEqual(CellSelection.cell(fromSeamAt: 44, goingDown: true, in: stack), cells[1])
    }

    func testADragUpABarStartsOnTheCellAboveIt() {
        XCTAssertEqual(CellSelection.cell(fromSeamAt: 44, goingDown: false, in: stack), cells[0])
    }

    func testTheBarAboveTheFirstCellHasNothingAboveItSoItTakesTheFirst() {
        // A drag has to select something; the nearest cell the other way
        // is the honest answer at either end of the note.
        XCTAssertEqual(CellSelection.cell(fromSeamAt: 10, goingDown: false, in: stack), cells[0])
    }

    func testTheTailBarHasNothingBelowItSoItTakesTheLast() {
        XCTAssertEqual(CellSelection.cell(fromSeamAt: 400, goingDown: true, in: stack), cells[2])
    }

    func testANoteWithNoCellsHasNothingToDragTo() {
        XCTAssertNil(CellSelection.cell(fromSeamAt: 44, goingDown: true, in: []))
    }

    func testADragFromABarDownTwoCellsTakesBoth() {
        let anchor = try! XCTUnwrap(CellSelection.cell(fromSeamAt: 44, goingDown: true, in: stack))
        let over = try! XCTUnwrap(CellSelection.cell(at: 90, in: stack))
        XCTAssertEqual(CellSelection.between(anchor, over, in: cells), [cells[1], cells[2]])
    }

    func testSpansOutOfOrderAreStillReadTopToBottom() {
        XCTAssertEqual(CellSelection.cell(fromSeamAt: 44, goingDown: true, in: stack.reversed()),
                       cells[1])
    }

    // MARK: - What lights a bracket

    func testOneRangeOverTheWholeCellPicksIt() {
        XCTAssertTrue(CellSelection.covers(cells[1], [cells[1]]))
        XCTAssertTrue(CellSelection.covers(cells[1], [NSRange(location: 0, length: 40)]))
        XCTAssertFalse(CellSelection.covers(cells[1], [NSRange(location: 12, length: 4)]))
    }

    func testTwoCellsPickedSeparatelyDoNotPickTheSectionRoundThem() {
        // The reason it is any ONE range and never their union: two
        // adjacent cells held separately are two cells, not the group that
        // holds them, or every bracket out to the margin would light up.
        let selection = [cells[0], cells[1]]
        let section = NSRange(location: cells[0].location,
                              length: NSMaxRange(cells[1]) - cells[0].location)
        XCTAssertTrue(CellSelection.covers(cells[0], selection))
        XCTAssertTrue(CellSelection.covers(cells[1], selection))
        XCTAssertFalse(CellSelection.covers(section, selection),
                       "the blank line between them is in neither range")
    }

    func testPickedIsEveryCellABracketWouldLight() {
        XCTAssertEqual(CellSelection.picked(cells: cells, selection: [cells[2], cells[0]]),
                       [cells[0], cells[2]], "in the note's order, whatever order they were taken in")
        XCTAssertEqual(CellSelection.picked(cells: cells, selection: [NSRange(location: 2, length: 0)]), [])
    }

    // MARK: - Shift, and the drag

    func testExtendingReachesEveryCellBetweenTheTwo() {
        XCTAssertEqual(CellSelection.between(cells[0], cells[2], in: cells), cells)
        XCTAssertEqual(CellSelection.between(cells[2], cells[0], in: cells), cells,
                       "a drag upwards reaches the same cells")
        XCTAssertEqual(CellSelection.between(cells[1], cells[1], in: cells), [cells[1]])
    }

    func testExtendingFromARangeThatIsNotACellStillReachesTheOneClicked() {
        let nowhere = NSRange(location: 900, length: 4)
        XCTAssertEqual(CellSelection.between(nowhere, cells[1], in: cells), [cells[1]])
    }

    func testAnAnchorThatNoLongerNamesABracketIsDropped() {
        // Both panes keep the last bracket clicked so shift-click can
        // reach from it, and neither is rebuilt when the note changes or
        // is swapped for another. `between` will not fail on a stale one
        // — `index(of:)` falls back to raw offset overlap — so the run
        // would light from whatever cell now sits at those offsets.
        XCTAssertEqual(CellSelection.anchor(cells[1], in: cells), cells[1])
        XCTAssertNil(CellSelection.anchor(NSRange(location: 13, length: 12), in: cells),
                     "the second cell as it was before a word was typed above it")
        XCTAssertNil(CellSelection.anchor(nil, in: cells))
    }

    func testAStaleAnchorWouldHaveReachedTheWrongRun() {
        // Why it is asked at all, in one line: left to itself, a range
        // from the note as it was extends from whatever it overlaps now.
        let stale = NSRange(location: 13, length: 12)
        XCTAssertEqual(CellSelection.between(stale, cells[2], in: cells).count, 2,
                       "it resolves by overlap, and reaches a cell the user never clicked")
        XCTAssertEqual(CellSelection.between(CellSelection.anchor(stale, in: cells) ?? cells[2],
                                             cells[2], in: cells),
                       [cells[2]], "one cell, and not the wrong two")
    }

    func testTogglingTakesACellOutAndPutsItBack() {
        let both = CellSelection.toggling(cells[2], in: [cells[0]])
        XCTAssertEqual(both, [cells[0], cells[2]])
        XCTAssertEqual(CellSelection.toggling(cells[0], in: both), [cells[2]],
                       "cmd-clicking one out of the middle leaves a hole")
    }

    // MARK: - Which bracket the pointer is on

    private let spans: [CellSelection.Span] = [
        (top: 0, bottom: 20, range: NSRange(location: 0, length: 10)),
        (top: 30, bottom: 50, range: NSRange(location: 12, length: 11))
    ]

    func testADragInsideACellsBracketIsOnThatCell() {
        XCTAssertEqual(CellSelection.cell(at: 10, in: spans), spans[0].range)
        XCTAssertEqual(CellSelection.cell(at: 40, in: spans), spans[1].range)
    }

    func testADragOverTheSpaceBetweenTwoCellsTakesTheNearer() {
        // The pointer spends half a drag in the seams; a drag that let go
        // while it crossed one would flicker the whole way down the page.
        XCTAssertEqual(CellSelection.cell(at: 24, in: spans), spans[0].range)
        XCTAssertEqual(CellSelection.cell(at: 27, in: spans), spans[1].range)
        XCTAssertEqual(CellSelection.cell(at: 900, in: spans), spans[1].range,
                       "dragged off the bottom of the page: the last cell")
    }

    func testAnEmptyPageHasNoCellToDragOver() {
        XCTAssertNil(CellSelection.cell(at: 10, in: []))
    }
}

/// The gutter is drawn FROM the pane's selection, and the two questions a
/// bracket answers — is it drawn heavy, is its cell being held — part
/// company over the cell the caret merely sits in.
final class GutterBracketTests: XCTestCase {
    private let note = "First cell\n\nSecond cell\n\nThird cell"
    private var cells: [NSRange] { MarkdownParser.positioned(from: note).map(\.range) }

    private func brackets(selecting selection: [NSRange],
                          armed: Int? = nil) -> [NotebookGutter.Bracket] {
        let tv = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        tv.font = MarkdownTextView.font
        tv.string = note
        tv.textContainer?.containerSize = NSSize(width: 352, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        tv.selectedRanges = selection.map { NSValue(range: $0) }
        // What a click in a seam leaves behind: the bar armed, and the
        // caret parked at the separator between the two cells.
        tv.armedSeam = armed
        // Held weakly by the coordinator, so the test keeps it alive.
        let gutter = NotebookGutter(frame: NSRect(x: 0, y: 0, width: NotebookGutter.width, height: 800))
        let coordinator = MarkdownTextView(text: .constant(note), documentID: nil,
                                           bridge: EditorBridge()).makeCoordinator()
        coordinator.gutter = gutter
        coordinator.refreshBrackets(in: tv)
        return gutter.brackets.filter { !$0.foldable }
    }

    func testTheCaretsOwnCellIsDrawnHeavyAndIsNotHeld() {
        // Which is the whole distinction: the caret lights the cell being
        // typed in, on both sides, and that must not read as a cell the
        // user picked up — there is always a caret somewhere.
        let out = brackets(selecting: [NSRange(location: 2, length: 0)])
        let first = out.first { NSEqualRanges($0.range, cells[0]) }
        XCTAssertEqual(first?.selected, true)
        XCTAssertEqual(first?.held, false)
        XCTAssertEqual(out.filter(\.held).count, 0, "nothing is held by a caret")
    }

    func testTheBarBetweenTwoCellsLightsNeitherOfThem() {
        // Arming puts the caret at the separator's own offset, which
        // `NotebookCells.block(containing:)` reads as the start of the
        // cell BELOW — so the next cell was drawn heavy while the bar
        // above it was the cursor (Sean, 2026-09-20: "the next section
        // shouldn't be highlighted when the input cursor is currently
        // that horizontal bar"). While a seam is armed the caret is in
        // no cell at all.
        let out = brackets(selecting: [NSRange(location: 12, length: 0)], armed: 12)
        XCTAssertEqual(out.filter(\.selected).count, 0, "the bar is the cursor, and it lights nothing")
        XCTAssertEqual(out.filter(\.held).count, 0)
    }

    func testCellsReallyHeldStayLitWhateverTheBarIsDoing() {
        // A real selection is a different thing from a caret: the bar
        // puts out what the CARET lights, and nothing else.
        let out = brackets(selecting: [cells[0], cells[2]], armed: 12)
        XCTAssertEqual(out.filter(\.held).map(\.range), [cells[0], cells[2]])
        XCTAssertEqual(out.filter(\.selected).map(\.range), [cells[0], cells[2]])
    }

    func testACellTheSelectionCoversIsHeld() {
        let out = brackets(selecting: [cells[0]])
        XCTAssertEqual(out.first { NSEqualRanges($0.range, cells[0]) }?.held, true)
        XCTAssertEqual(out.first { NSEqualRanges($0.range, cells[1]) }?.held, false)
    }

    func testTwoCellsWithAHoleBetweenThemAreBothHeld() {
        let out = brackets(selecting: [cells[0], cells[2]])
        XCTAssertEqual(out.filter(\.held).map(\.range), [cells[0], cells[2]])
    }
}

/// A flipped host, so a point in the test reads the same way up as a point
/// in the gutter and the conversions either side of an event are exact.
private final class Pane: NSView {
    override var isFlipped: Bool { true }
}

/// What a press on a bracket does — which of the two gestures it begins,
/// and what a modifier makes of it.
final class GutterClickTests: XCTestCase {
    private let first = NSRange(location: 0, length: 10)
    private let second = NSRange(location: 12, length: 11)

    /// Two cells, one above the other. `lit` is a bracket drawn heavy,
    /// `held` one a real selection covers — the distinction the gestures
    /// turn on.
    private func gutter(lit: Bool = false, held: Bool = false) -> NotebookGutter {
        let pane = Pane(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let view = NotebookGutter(frame: NSRect(x: 0, y: 0, width: NotebookGutter.width, height: 200))
        view.brackets = [
            .init(key: "cell:0", depth: 0, top: 0, bottom: 20, collapsed: false,
                  selected: lit || held, held: held, range: first),
            .init(key: "cell:12", depth: 0, top: 30, bottom: 50, collapsed: false,
                  range: second)
        ]
        pane.addSubview(view)
        return view
    }

    /// A bracket at depth 0 is drawn six points in from the column's right
    /// edge; these are points on its line.
    private func onFirst(_ y: CGFloat = 10) -> CGPoint { CGPoint(x: NotebookGutter.width - 6, y: y) }
    private func onSecond() -> CGPoint { CGPoint(x: NotebookGutter.width - 6, y: 40) }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, in view: NSView,
                       modifiers: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                           modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                           context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    // MARK: - Lit is not held

    func testADragFromTheCaretsOwnBracketSelectsInsteadOfMovingTheCell() {
        // There is always a caret somewhere, so there is always one
        // bracket drawn heavy with nothing selected — and a press on it
        // took the move branch, so a drag meant as a selection reordered
        // the note (2026-09-20).
        let view = gutter(lit: true)
        var picked: [NSRange] = []
        var moved: [NSRange] = []
        view.onSelect = { picked.append($0) }
        view.onMoveCell = { range, _ in moved.append(range) }
        view.mouseDown(with: mouse(.leftMouseDown, at: onFirst(), in: view))
        view.mouseUp(with: mouse(.leftMouseUp, at: onFirst(45), in: view))
        XCTAssertEqual(picked, [first], "a plain click on it picks the cell up")
        XCTAssertEqual(moved, [], "and dragging it takes cells, it does not reorder the note")
    }

    func testADragFromACellThatIsReallyHeldStillMovesIt() {
        let view = gutter(held: true)
        var moved: [(NSRange, Bool)] = []
        view.onMoveCell = { moved.append(($0, $1)) }
        view.mouseDown(with: mouse(.leftMouseDown, at: onFirst(), in: view))
        view.mouseUp(with: mouse(.leftMouseUp, at: onFirst(45), in: view))
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.0, first)
        XCTAssertEqual(moved.first?.1, false, "dragged downwards")
    }

    func testCmdClickTakesTheCaretsCellWithItNoMore() {
        // `picked` reads the brackets, and it used to read the flag that
        // the caret's own cell sets: cmd-clicking one bracket selected
        // two, and ⌃⌫ then took a cell nobody had clicked.
        let view = gutter(lit: true)
        var handed: [NSRange] = []
        view.onSelectCells = { handed = $0 }
        view.mouseDown(with: mouse(.leftMouseDown, at: onSecond(), in: view, modifiers: .command))
        XCTAssertEqual(handed, [second])
    }

    func testCmdClickTakesAHeldCellBackOut() {
        let view = gutter(held: true)
        var handed: [NSRange] = []
        view.onSelectCells = { handed = $0 }
        view.mouseDown(with: mouse(.leftMouseDown, at: onFirst(), in: view, modifiers: .command))
        XCTAssertEqual(handed, [], "the one cell that was held, taken out")
    }

    // MARK: - What the column swallows

    func testAClickWhereThereIsNoBracketGoesToTheTextBehind() {
        // The column is 22 of the text container's own 24 points of right
        // margin. Taking every click in it meant the margin no longer put
        // a caret at the end of the line — and, worse, the click never
        // reached `PasteAwareTextView.mouseDown`, which is the one path
        // that puts an armed seam out. The bar stayed drawn with no caret
        // anywhere (AGENTS.md: "every path that disarms … must go through
        // that property").
        let view = gutter()
        XCTAssertNil(view.hitTest(NSPoint(x: 11, y: 150)), "far below every bracket")
        XCTAssertNil(view.hitTest(NSPoint(x: 2, y: 10)), "the far side of the column")
    }

    func testAClickOnABracketIsTheGuttersOwn() {
        let view = gutter()
        XCTAssertTrue(view.hitTest(onFirst()) === view)
    }

    func testAClickOutsideTheGutterIsNoneOfItsBusiness() {
        XCTAssertNil(gutter().hitTest(NSPoint(x: 100, y: 100)))
    }
}

/// And the same two questions on the rendered page, where the gesture is a
/// SwiftUI drag rather than a mouse down.
final class RenderedBracketGestureTests: XCTestCase {
    func testAPressThatDriftsThreePointsIsStillAClick() {
        // Three points between press and release is ordinary with a
        // mouse. A separate three-point slop settled the gesture as a
        // drag that early, and the mouse up then never reached the click
        // — so the cell never opened and a double-click never folded the
        // section (2026-09-20).
        XCTAssertFalse(CellBrackets.isDrag(travelled: 3))
        XCTAssertFalse(CellBrackets.isDrag(travelled: -3))
        XCTAssertTrue(CellBrackets.isDrag(travelled: CellBrackets.dragThreshold))
        XCTAssertTrue(CellBrackets.isDrag(travelled: -20))
    }
}

/// And what a key means while the rendered page is holding cells. It has
/// no text view to type over a selection with, the way the markdown pane
/// has, so the meanings are spelled out and tested here.
final class HeldCellKeyTests: XCTestCase {
    func testAPrintableCharacterReplacesWhatIsHeld() {
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "x", modifiers: []), .replace("x"))
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "X", modifiers: .shift), .replace("X"))
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "#", modifiers: .shift), .replace("#"))
    }

    func testADeleteTakesThemAndEscapeLetsThemGo() {
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "\u{8}", modifiers: []), .remove, "backspace")
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "\u{7F}", modifiers: []), .remove, "forward delete")
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "\u{1B}", modifiers: []), .clear)
    }

    /// Sean, 2026-10-02, asked whether a click on a cell's bracket OPENS it
    /// or SELECTS it (the markdown pane selects): "select". A held cell is
    /// then opened by Return, so a checklist — whose items own their own
    /// clicks and which only its bracket used to open as a whole — can still
    /// be got into.
    func testReturnOpensAHeldCell() {
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "\r", modifiers: []), .open)
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "\r", modifiers: .shift), .pass,
                       "⇧↩ runs an evaluation cell and is not this")
    }

    func testAShortcutIsNotTyping() {
        // ⌃⌫ is the Delete Cell menu item and ⌘S is not an S; both are
        // somebody else's before they are ever this.
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "\u{8}", modifiers: .control), .pass)
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "s", modifiers: .command), .pass)
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "\u{F701}", modifiers: []), .pass, "an arrow")
        XCTAssertEqual(MarkdownPreview.cellKey(characters: "", modifiers: []), .pass)
    }
}
/// An OUTER bracket is held when the cells under it are (Sean, 2026-09-21:
/// "highlighting all of this should have highlighted all the outermost
/// cells").
final class OuterBracketTests: XCTestCase {
    private let cells = [NSRange(location: 0, length: 5),
                         NSRange(location: 7, length: 3),
                         NSRange(location: 12, length: 4)]
    private var section: NSRange { NSRange(location: 0, length: 16) }

    func testASectionIsHeldWhenEveryCellUnderItIs() {
        // Cells picked up one at a time are SEVERAL ranges, and no one
        // of them covers the section round them — which is the question
        // `covers` asks, and why the outer bracket stayed grey with the
        // whole note picked up.
        XCTAssertTrue(CellSelection.holds(section, cells: cells, selection: cells))
        XCTAssertFalse(CellSelection.covers(section, cells),
                       "which is why holding a section is a rule of its own")
    }

    func testOneCellShortIsNotTheSection() {
        XCTAssertFalse(CellSelection.holds(section, cells: cells,
                                           selection: [cells[0], cells[1]]))
        XCTAssertFalse(CellSelection.holds(section, cells: cells, selection: []))
    }

    func testOneSweepOverTheWholeNoteHoldsItToo() {
        // A drag through the text is one range, and it covered the
        // section already. It still does.
        XCTAssertTrue(CellSelection.holds(section, cells: cells,
                                          selection: [NSRange(location: 0, length: 16)]))
    }

    func testACellsOwnBracketAsksTheSameQuestionOfItself() {
        XCTAssertTrue(CellSelection.holds(cells[1], cells: cells, selection: [cells[1]]))
        XCTAssertFalse(CellSelection.holds(cells[1], cells: cells, selection: [cells[0]]))
    }

    func testABracketWithNoCellsInItFallsBackToItsOwnCharacters() {
        // Before the page has measured anything there are no cells to
        // ask about, and a bracket that answered "held" for an empty
        // list would light the whole margin.
        XCTAssertFalse(CellSelection.holds(section, cells: [], selection: []))
        XCTAssertTrue(CellSelection.holds(section, cells: [], selection: [section]))
    }
}
