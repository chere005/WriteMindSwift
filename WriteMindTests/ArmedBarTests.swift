import AppKit
import XCTest
@testable import WriteMind

/// The bar between two cells while it IS the cursor, and the commands
/// that arrive at it from somewhere other than the keyboard in a cell.
///
/// The bar is in no cell. Everything that reads "where the caret is" has
/// to be told that separately, because arming parks the caret at the next
/// cell's first character — the brackets were told (ee1cb44) and three
/// other readers were not.
final class ArmedBarFormatTests: XCTestCase {
    private let note = "First cell\n\nSecond cell"

    private func view(_ text: String) -> PasteAwareTextView {
        let view = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        view.string = text
        return view
    }

    private func armed(at offset: Int) -> (PasteAwareTextView, EditorBridge) {
        let view = view(note)
        // Exactly what `CellInsertions.onArm` does: the caret goes to the
        // seam's offset, which is the first character of the cell BELOW.
        view.setSelectedRange(NSRange(location: offset, length: 0))
        view.armedSeam = offset
        let bridge = EditorBridge()
        bridge.textView = view
        return (view, bridge)
    }

    // MARK: - The source pane

    func testAHeadingShortcutAtABarMakesTheCellThereAndDoesNotRetitleTheOneBelow() {
        let (view, bridge) = armed(at: 12)
        bridge.heading(.title)
        // The cell is MADE, now, with the marker in it and the caret where
        // the words go (Sean, 2026-09-21: "it should create a cell at the
        // position of the bar ready for that type of input").
        XCTAssertEqual(view.string, "First cell\n\n# \n\nSecond cell")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 14, length: 0))
        XCTAssertNil(view.armedSeam, "the bar was the cursor and the caret has taken over")
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(view.string, "First cell\n\n# x\n\nSecond cell")
    }

    func testEveryCommandThatNamesAKindMakesThatCellAtTheBar() {
        let wanted: [(String, (EditorBridge) -> Void, String)] = [
            ("Title", { $0.heading(.title) }, "First cell\n\n# \n\nSecond cell"),
            ("Body Text", { $0.heading(.body) }, "First cell\n\n\n\nSecond cell"),
            ("Dashes List", { $0.list(.dashes) }, "First cell\n\n* \n\nSecond cell"),
            ("Dots List", { $0.bullets() }, "First cell\n\n- \n\nSecond cell"),
            ("Quote", { $0.quote() }, "First cell\n\n> \n\nSecond cell"),
        ]
        for (name, command, expected) in wanted {
            let (view, bridge) = armed(at: 12)
            command(bridge)
            XCTAssertEqual(view.string, expected, name)
            XCTAssertNil(view.armedSeam, "\(name) left the bar up")
        }
        // A fenced block is a pair of lines rather than a prefix, so it is
        // named apart rather than spelled out beside the others.
        let (view, bridge) = armed(at: 12)
        bridge.codeBlock(.python)
        XCTAssertTrue(view.string.contains("```"), view.string)
        XCTAssertTrue(view.string.hasPrefix("First cell\n\n"), view.string)
        XCTAssertTrue(view.string.hasSuffix("\n\nSecond cell"), view.string)
    }

    func testACommandWithNoKindOpensAPlainCellAtTheBarAndRunsInIt() {
        // Bold and the rest name no kind, so the cell is a plain one and
        // the command does its ordinary work inside it — which is what
        // "ready for that type of input" means for something that is not
        // a kind of cell.
        let (bold, boldBridge) = armed(at: 12)
        boldBridge.bold()
        XCTAssertEqual(bold.string, "First cell\n\n****\n\nSecond cell")
        XCTAssertNil(bold.armedSeam)

        let (maths, mathsBridge) = armed(at: 12)
        mathsBridge.insertMath("Pi", display: false)
        XCTAssertTrue(maths.string.contains("Pi"), maths.string)
        XCTAssertTrue(maths.string.hasPrefix("First cell\n\n"), maths.string)
    }

    func testACommandThatActsOnACellStillDoesNothingAtABar() {
        // Delete, duplicate, move, split, merge: there is no cell at a
        // bar, and making an empty one to delete is churn in the note and
        // a step on the undo stack for a gesture that did nothing.
        for command in [{ (b: EditorBridge) in b.deleteCell() }, { $0.duplicateCell() },
                        { $0.moveCell(up: true) }, { $0.splitCell() }, { $0.mergeCells() },
                        { $0.expandSelection() }] {
            let (view, bridge) = armed(at: 12)
            command(bridge)
            XCTAssertEqual(view.string, note)
            XCTAssertEqual(view.armedSeam, 12, "and the bar is still up")
        }
    }

    func testTheSameShortcutWithNoBarUpStillStylesTheCellTheCaretIsIn() {
        // The rule is about the bar and nothing else: an ordinary caret in
        // "Second cell" still titles "Second cell".
        let view = view(note)
        view.setSelectedRange(NSRange(location: 12, length: 0))
        let bridge = EditorBridge()
        bridge.textView = view
        bridge.heading(.title)
        XCTAssertEqual(view.string, "First cell\n\n# Second cell")
    }

    // MARK: - The rendered page, where there is no text view at the bar

    func testAFormatCommandAtABarOnTheRenderedPageGoesToTheBarAndNotToTheFirstCell() {
        // `perform` used to fall through to `ensureEditing` — `openSomething`,
        // which knows nothing about the bar and opens the note's FIRST
        // cell. ⌘1 at a bar under the last cell titled the top of the note.
        let bridge = EditorBridge()
        var opened = 0
        var asked: [CellTypes.Kind?] = []
        bridge.ensureEditing = { opened += 1; return true }
        bridge.barIsUp = { true }
        // What the page really does: it opens the cell and says whether
        // that was the whole command.
        bridge.armedBar = { kind in asked.append(kind); return kind != nil }

        bridge.heading(.title)
        bridge.list(.dots)
        bridge.quote()
        XCTAssertEqual(asked, [.heading(.title), .list(.dots), .quote])
        XCTAssertEqual(opened, 0, "a kind is the whole of the command")

        // Bold names no kind: the page opens a plain cell, and the bridge
        // then waits for the text view that cell is about to build.
        bridge.bold()
        XCTAssertEqual(asked.last, CellTypes.Kind?.none)
        XCTAssertEqual(opened, 1, "and it runs in the cell that just opened")
    }

    func testACellCommandAtABarOnTheRenderedPageMakesNothing() {
        let bridge = EditorBridge()
        var asked = 0
        bridge.ensureEditing = { XCTFail("nothing to open"); return false }
        bridge.barIsUp = { true }
        bridge.armedBar = { _ in asked += 1; return true }
        bridge.expandSelection()
        XCTAssertEqual(asked, 0, "acting on a cell is not making one")
    }

    func testWithNoBarUpTheRenderedPageStillOpensSomethingToTypeIn() {
        let bridge = EditorBridge()
        var opened = 0
        bridge.ensureEditing = { opened += 1; return true }
        bridge.armedBar = { _ in false }
        bridge.barIsUp = { false }
        bridge.heading(.title)
        XCTAssertEqual(opened, 1)
    }
}

/// The + on the bar is a button, and a button is only pressable where it
/// is drawn.
final class ArmedBarPlusTests: XCTestCase {
    private let seam = CellSeams.Seam(top: 60, bottom: 68, offset: 12, line: 64)
    private let elsewhere = CellSeams.Seam(top: 120, bottom: 128, offset: 30, line: 124)

    func testThePlusIsPressedOnlyOnTheSeamThePlusIsDrawnOn() {
        let onIt = CGPoint(x: 9, y: 64)
        XCTAssertTrue(CellInsertions.pressesPlus(at: onIt, in: seam, drawnOn: seam))
        XCTAssertFalse(CellInsertions.pressesPlus(at: onIt, in: seam, drawnOn: elsewhere),
                       "the bar is on another seam, so nothing is drawn on this one")
        XCTAssertFalse(CellInsertions.pressesPlus(at: onIt, in: seam, drawnOn: nil))
    }

    func testTheTargetIsTheWholeLeftEdgeOfTheSeamWhichIsWhyItHasToBeDrawnThere() {
        // Nine points either side of the line, which on an ordinary eight
        // point seam is all of it: without the "is it drawn" question the
        // plain click that moves the bar to another seam popped the menu.
        for y in stride(from: CGFloat(60), through: 68, by: 0.5) {
            let point = CGPoint(x: 9, y: y)
            XCTAssertTrue(CellInsertions.pressesPlus(at: point, in: seam, drawnOn: seam), "\(y)")
            XCTAssertFalse(CellInsertions.pressesPlus(at: point, in: seam, drawnOn: nil), "\(y)")
        }
        XCTAssertFalse(CellInsertions.pressesPlus(at: CGPoint(x: 40, y: 64), in: seam, drawnOn: seam),
                       "the bar itself is not a button")
    }
}

/// The kind a bar is carrying survives the bar being armed again where it
/// already is — the same rule in both panes.
final class ArmedBarChoiceTests: XCTestCase {
    func testPressingThePlusAgainOnTheSameBarKeepsWhatWasChosen() {
        // The rendered page threw it away and then popped the menu with
        // the OLD kind ticked, so the tick showed state that no longer
        // existed and dismissing the menu left plain text behind.
        let bar = MarkdownPreview.SeamID(index: 1, offset: 12)
        XCTAssertEqual(MarkdownPreview.arming(bar, over: bar, keeping: .quote), .quote)
        XCTAssertEqual(MarkdownPreview.arming(bar, over: nil, keeping: .quote), .text)
        XCTAssertEqual(MarkdownPreview.arming(bar, over: MarkdownPreview.SeamID(index: 2, offset: 30),
                                              keeping: .quote), .text,
                       "a bar somewhere else is a bar of its own")
    }

    func testTheMarkdownPaneAnswersTheSameThreeGesturesTheSameWay() {
        let view = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        view.string = "First cell\n\nSecond cell"
        view.armedSeam = 12
        view.armedType = .quote
        view.armedSeam = 12
        XCTAssertEqual(view.armedType, .quote, "the same bar again keeps the choice")
        view.armedSeam = 30
        XCTAssertEqual(view.armedType, .text)
    }
}

/// With the markers hidden, a bar is not a caret in the cell below it.
final class ArmedBarMarkerTests: XCTestCase {
    /// "Body text", a separator, then a heading whose `## ` can vanish.
    private let note = "Body text\n\n## Notes"

    private func textView() -> PasteAwareTextView {
        // TextKit 1, the way the source editor builds it: `MarkerHiding`
        // is a layout-manager delegate and there is no layout manager to
        // be a delegate of otherwise.
        let view = PasteAwareTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
        view.string = note
        return view
    }

    private func hiding() -> MarkerHiding {
        let hiding = MarkerHiding()
        hiding.setMarkers(MarkerHiding.hideable(MarkdownSourceStyle.runs(in: note), in: note as NSString))
        return hiding
    }

    func testArmingTheSeamAboveAHeadingLeavesItsHashesHidden() {
        let view = textView()
        XCTAssertNotNil(view.layoutManager, "TextKit 1, or nothing below is exercised")
        let hiding = self.hiding()
        XCTAssertTrue(hiding.isHidden(11), "the ## starts out hidden")

        // The caret really in the heading shows the heading's markers.
        view.setSelectedRange(NSRange(location: 14, length: 0))
        view.updateHiddenMarkers(hiding)
        XCTAssertFalse(hiding.isHidden(11), "the caret's own paragraph shows its own")

        // The bar armed in the seam above it is in no cell at all. Arming
        // parks the caret at the heading's first character, and that made
        // the `## ` pop into view and the words shift right with nothing
        // typed (Sean, 2026-09-20: "the next section shouldn't be
        // highlighted when the input cursor is currently that horizontal
        // bar").
        view.armedSeam = 11
        view.setSelectedRange(NSRange(location: 11, length: 0))
        view.updateHiddenMarkers(hiding)
        XCTAssertNil(hiding.revealed, "a bar reveals no paragraph")
        XCTAssertTrue(hiding.isHidden(11))
    }

    func testTheBarUnderTheLastCellDoesNotOpenTheLastCellEither() {
        // The tail seam's offset is the note's length, which clamps onto
        // the last character — so it was the LAST cell that popped its
        // markers there.
        let view = textView()
        let hiding = self.hiding()
        view.armedSeam = (note as NSString).length
        view.setSelectedRange(NSRange(location: (note as NSString).length, length: 0))
        view.updateHiddenMarkers(hiding)
        XCTAssertNil(hiding.revealed)
        XCTAssertTrue(hiding.isHidden(11))
    }

    func testTheMarkersComeBackAsSoonAsTheCaretIsInACellAgain() {
        let view = textView()
        let hiding = self.hiding()
        view.armedSeam = 11
        view.setSelectedRange(NSRange(location: 11, length: 0))
        view.updateHiddenMarkers(hiding)
        view.armedSeam = nil
        view.setSelectedRange(NSRange(location: 14, length: 0))
        view.updateHiddenMarkers(hiding)
        XCTAssertFalse(hiding.isHidden(11))
    }
}
