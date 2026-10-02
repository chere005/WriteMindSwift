import AppKit
import XCTest
@testable import WriteMind

/// Sean, 2026-10-02: "do a thorough test of cell selection and input
/// insertion ux behavior". Every gesture and key the two panes answer at a
/// cell, a bar and a bracket, stated as AGENTS.md's rules state it. Nearly
/// every test here failed against the code before this pass; the few that
/// held already say "A GUARD" — they pin the edge of what changed.

/// The markdown pane as `MarkdownTextView.makeNSView` puts it together: the
/// text view with its folding layout, its gutter, its seam layer, the
/// coordinator as its delegate and the bridge on it — so a key goes through
/// `doCommand(by:)`, the delegate and the arming exactly as it does on
/// screen.
private final class SourcePane {
    let tv = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
    let gutter = NotebookGutter(frame: .zero)
    let insertions: CellInsertions
    let bridge = EditorBridge()
    let coordinator: MarkdownTextView.Coordinator
    private let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))

    init(_ note: String, width: CGFloat = 400) {
        let folding = FoldingLayoutManager()
        tv.textContainer?.replaceLayoutManager(folding)
        folding.typesetter = FoldingTypesetter(folding.folding)
        tv.font = MarkdownTextView.font
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 24, height: 20)
        tv.frame.size.width = width
        tv.string = note
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        tv.addSubview(gutter)
        insertions = CellInsertions(frame: tv.bounds)
        tv.addSubview(insertions)
        bridge.textView = tv
        coordinator = MarkdownTextView(text: .constant(note), documentID: nil, bridge: bridge).makeCoordinator()
        coordinator.gutter = gutter
        coordinator.insertions = insertions
        tv.delegate = coordinator
        tv.onArmChanged = { [weak insertions] in insertions?.armedOffset = $0 }
        // What `makeNSView` hands the layer: a click in a seam arms it and
        // parks the caret at the seam's offset.
        insertions.onArm = { [weak tv] offset in
            guard let tv else { return }
            tv.armedSeam = offset
            tv.setSelectedRange(NSRange(location: min(offset, (tv.string as NSString).length), length: 0))
        }
        let coordinator = coordinator
        gutter.onSelect = { [weak tv] range in if let tv { coordinator.select([range], in: tv) } }
        gutter.onSelectCells = { [weak tv] ranges in if let tv { coordinator.select(ranges, in: tv) } }
        scroll.documentView = tv
        coordinator.watchScrolling(of: scroll)
        coordinator.refreshBrackets(in: tv)
    }

    func click(seam offset: Int) { insertions.onArm?(offset) }
    func caret(at offset: Int) { tv.setSelectedRange(NSRange(location: offset, length: 0)) }
    func key(_ selector: Selector) { tv.doCommand(by: selector) }
    /// The way a keystroke arrives: {NSNotFound, 0}, "wherever the caret is".
    func type(_ characters: String) {
        tv.insertText(characters, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    func hold(_ ranges: [NSRange]) { coordinator.select(ranges, in: tv) }
    var cells: [NSRange] { MarkdownParser.positioned(from: tv.string).map(\.range) }
    var blocks: [MarkdownBlock] { MarkdownParser.blocks(from: tv.string) }
    var held: [NSRange] { tv.selectedRanges.map(\.rangeValue).filter { $0.length > 0 } }
}

private let note = "First cell\n\nSecond cell\n\nThird cell"
private let first = NSRange(location: 0, length: 10)
private let second = NSRange(location: 12, length: 11)
private let third = NSRange(location: 25, length: 10)

// MARK: - A key at the bar

/// docs/FEATURES.md: "Escape or a click anywhere else takes the line back
/// without leaving an empty cell behind". The bar is in no cell, so a key
/// pressed at it may not edit the cell beside it either — and the rendered
/// page's seam, which has no text to run a key in, never has.
final class KeyAtTheBarTests: XCTestCase {
    private let editing: [(String, Selector)] = [
        ("⌫", #selector(NSResponder.deleteBackward(_:))),
        ("⌦", #selector(NSResponder.deleteForward(_:))),
        ("⌥⌫", #selector(NSResponder.deleteWordBackward(_:))),
        ("⇥", #selector(NSResponder.insertTab(_:))),
        ("⇧⇥", #selector(NSResponder.insertBacktab(_:))),
        ("esc", #selector(NSResponder.cancelOperation(_:))),
    ]

    func testNoKeyAtAClickedBarEditsTheCellBelowIt() {
        // A click parks the caret at the first character of the cell
        // BELOW. Before, the bar went out and the key then ran there: ⌫
        // joined "Second cell" to the cell above, ⌦ took its "S", ⇥
        // indented it.
        for (name, selector) in editing {
            let pane = SourcePane(note)
            pane.click(seam: 12)
            pane.key(selector)
            XCTAssertEqual(pane.tv.string, note, name)
            XCTAssertNil(pane.tv.armedSeam, "\(name) takes the bar back")
        }
        let indented = "First cell\n\n    Second cell"
        let pane = SourcePane(indented)
        pane.click(seam: 12)
        pane.key(#selector(NSResponder.insertBacktab(_:)))
        XCTAssertEqual(pane.tv.string, indented, "⇧⇥ does not outdent the cell below either")
    }

    func testNoKeyAtAnArrowedBarEditsTheCellsEitherSide() {
        // ↓ off "First cell" leaves the caret on the blank line between the
        // two cells: ⌫ there took the newline that ends "First cell".
        for (name, selector) in editing {
            let pane = SourcePane(note)
            pane.caret(at: 11)
            XCTAssertEqual(pane.tv.armedSeam, 12, "the premise: the caret on the separator arms its bar")
            pane.key(selector)
            XCTAssertEqual(pane.tv.string, note, name)
        }
    }

    func testTypingAfterEscapeAtAnArrowedBarWeldsNothing() {
        // The caret used to stay on the separator once the bar was out,
        // and the next character went in on that line: "First cell\nx\n
        // Second cell", three cells read as one paragraph — the very merge
        // arming was built to stop. It goes where a click leaves it.
        let pane = SourcePane(note)
        pane.caret(at: 11)
        pane.key(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(pane.tv.selectedRange(), NSRange(location: 12, length: 0), "the start of the cell below")
        pane.type("x")
        XCTAssertEqual(pane.blocks, [.paragraph("First cell"), .paragraph("xSecond cell"), .paragraph("Third cell")])
    }

    func testEscapeAtTheBarUnderTheLastCellLeavesTheCaretInIt() {
        // Under the last cell there is no cell below, and the empty line a
        // final newline leaves is the tail seam itself.
        let pane = SourcePane("Only cell\n")
        pane.click(seam: 10)
        pane.key(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(pane.tv.selectedRange(), NSRange(location: 9, length: 0))
        pane.type("x")
        XCTAssertEqual(pane.blocks, [.paragraph("Only cellx")])
    }

    func testReturnBesideTheBarStillOpensAnEmptyCell() {
        // ⌃↩ and ⌥↩ are Return too, as they are on the rendered page,
        // where all three arrive as "\r". (Return itself, A GUARD: it
        // always opened one.)
        for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
                         #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))] {
            let pane = SourcePane(note)
            pane.click(seam: 12)
            pane.key(selector)
            XCTAssertEqual(pane.blocks, [.paragraph("First cell"), .blank(lines: 1), .paragraph("Second cell"),
                                         .paragraph("Third cell")], "\(selector)")
        }
    }

    func testTheTwoPanesReadEveryKeyAtABarTheSameWay() {
        // The source pane reads selectors, the rendered page characters;
        // the same key has to mean the same thing in both.
        let keys: [(Selector, String)] = [
            (#selector(NSResponder.insertNewline(_:)), "\r"),
            (#selector(NSResponder.cancelOperation(_:)), "\u{1B}"),
            (#selector(NSResponder.moveUp(_:)), "\u{F700}"),
            (#selector(NSResponder.moveDown(_:)), "\u{F701}"),
            (#selector(NSResponder.deleteForward(_:)), "\u{7F}"),
            (#selector(NSResponder.insertTab(_:)), "\t"),
        ]
        for (selector, characters) in keys {
            XCTAssertEqual(CellSeams.command(NSStringFromSelector(selector)),
                           MarkdownPreview.seamKey(characters: characters, modifiers: []),
                           NSStringFromSelector(selector))
        }
    }
}

// MARK: - The arrows: cell, bar, cell

/// docs/FEATURES.md: "↓ off the bottom of a cell lands ON it, ↓ again goes
/// into the next cell, and ↑ comes back the same way."
final class ArrowAtTheBarTests: XCTestCase {
    func testDownFromAClickedBarGoesIntoTheCellBelowIt() {
        // It went to the second line of "Second cell" — which, for a cell
        // of one line, is the bar under it: the cell was skipped.
        let pane = SourcePane(note)
        pane.click(seam: 12)
        pane.key(#selector(NSResponder.moveDown(_:)))
        XCTAssertNil(pane.tv.armedSeam)
        XCTAssertEqual(pane.tv.selectedRange(), NSRange(location: 12, length: 0))
    }

    func testUpFromAClickedBarGoesIntoTheCellAboveIt() {
        // It went to the blank line the bar stands for and armed the same
        // bar again: the key did nothing anybody could see.
        let pane = SourcePane(note)
        pane.click(seam: 12)
        pane.key(#selector(NSResponder.moveUp(_:)))
        XCTAssertNil(pane.tv.armedSeam)
        XCTAssertEqual(pane.tv.selectedRange(), NSRange(location: 10, length: 0), "the end of the cell above")
    }

    func testArrowedOntoTheBarTheArrowsGoTheSamePlaces() {
        // Getting there by arrow and by click leave the page the same.
        for (selector, wanted) in [(#selector(NSResponder.moveUp(_:)), 10),
                                   (#selector(NSResponder.moveDown(_:)), 12)] {
            let pane = SourcePane(note)
            pane.caret(at: 11)
            pane.key(selector)
            XCTAssertNil(pane.tv.armedSeam)
            XCTAssertEqual(pane.tv.selectedRange().location, wanted)
        }
    }

    func testAtTheTwoEndsOfTheNoteTheBarStays() {
        // There is no cell that way, as on the rendered page (`walk`).
        let top = SourcePane(note)
        top.click(seam: 0)
        top.key(#selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(top.tv.armedSeam, 0)
        let bottom = SourcePane(note)
        bottom.click(seam: 35)
        bottom.key(#selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(bottom.tv.armedSeam, 35)
    }

    func testStepIsReadOffTheBarAndNotOffTheCaret() {
        XCTAssertEqual(CellSeams.step(from: 12, up: false, in: note), 12)
        XCTAssertEqual(CellSeams.step(from: 12, up: true, in: note), 10)
        XCTAssertEqual(CellSeams.step(from: 35, up: true, in: note), 35, "the tail's cell above is the last")
        XCTAssertNil(CellSeams.step(from: 0, up: true, in: note))
        XCTAssertNil(CellSeams.step(from: 35, up: false, in: note))
    }

    func testUpOnTheFirstLineLandsOnTheBarAboveTheFirstCell() {
        // There is no line above the first cell for the caret to land on,
        // so NSTextView put it at the start of the note, an ordinary caret,
        // and the bar there could only be clicked.
        let pane = SourcePane(note)
        pane.caret(at: 3)
        pane.key(#selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(pane.tv.armedSeam, 0)
        pane.type("x")
        XCTAssertEqual(pane.blocks.first, .paragraph("x"), "a cell above the first one")
        XCTAssertEqual(pane.blocks.count, 4)
    }

    func testDownOnTheLastLineLandsOnTheBarUnderTheLastCell() {
        let pane = SourcePane(note)
        pane.caret(at: 27)
        pane.key(#selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(pane.tv.armedSeam, 35)
        pane.type("x")
        XCTAssertEqual(pane.blocks.last, .paragraph("x"))
        XCTAssertEqual(pane.blocks.count, 4)
    }

    func testANoteThatEndsInANewlineToo() {
        // The empty line under the last cell IS the tail seam: typing there
        // went into the last cell as a second line ("Only cell x").
        let pane = SourcePane("Only cell\n")
        pane.caret(at: 3)
        pane.key(#selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(pane.tv.armedSeam, 10)
        pane.type("x")
        XCTAssertEqual(pane.blocks, [.paragraph("Only cell"), .paragraph("x")])
    }

    func testAWrappedFirstParagraphWalksItsOwnLinesFirst() {
        // A GUARD on the arming above: the first LINE AS LAID OUT, not the
        // first line of the file — ↑ on the second line of a long
        // paragraph is still a move inside it.
        let long = String(repeating: "word ", count: 40) + "\n\nNext"
        let pane = SourcePane(long)
        pane.caret(at: 150)
        XCTAssertFalse(MarkdownTextView.isOnEndLine(of: pane.tv, top: true), "the premise: it wraps")
        pane.key(#selector(NSResponder.moveUp(_:)))
        XCTAssertNil(pane.tv.armedSeam)
        XCTAssertEqual(pane.tv.string, long)
    }
}

// MARK: - Return at the end of a cell

/// The rendered page's Return at the end of a cell makes the next cell.
/// The source pane's leaves the caret on a blank line under it — which is a
/// separator, so the bar is the cursor there and what is typed is a cell.
final class ReturnAtTheEndOfACellTests: XCTestCase {
    func testReturnThenTypingAtTheEndOfACellMakesTheNextCell() {
        // NSTextView moves the caret inside its own edit, and the seams it
        // was checked against were the ones from before the Return — so
        // the bar never came up and "x" became a second line of the cell
        // above ("First cell x" on the page).
        let pane = SourcePane(note)
        pane.caret(at: 10)
        pane.key(#selector(NSResponder.insertNewline(_:)))
        XCTAssertNotNil(pane.tv.armedSeam)
        pane.type("x")
        XCTAssertEqual(pane.blocks, [.paragraph("First cell"), .paragraph("x"), .paragraph("Second cell"),
                                     .paragraph("Third cell")])
    }

    func testAndAtTheEndOfTheLastCell() {
        let pane = SourcePane("Only cell")
        pane.caret(at: 9)
        pane.key(#selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(pane.tv.armedSeam, 10)
        pane.type("x")
        XCTAssertEqual(pane.tv.string, "Only cell\n\nx")
    }

    func testTheLineUnderTheLastCellIsTheTailSeam() {
        XCTAssertEqual(CellSeams.arm(caret: NSRange(location: 10, length: 0), in: "Only cell\n", current: nil), 10)
        // A GUARD, the rest: with no newline the end of the note is the end
        // of the last cell.
        XCTAssertNil(CellSeams.arm(caret: NSRange(location: 9, length: 0), in: "Only cell", current: nil))
        // A fence with no closing line runs to the end of the note.
        XCTAssertNil(CellSeams.arm(caret: NSRange(location: 15, length: 0), in: "```python\ncode\n", current: nil))
    }
}

// MARK: - Cells held by their brackets

/// docs/FEATURES.md: "Everything a single cell answers to, a handful
/// answers to together: type and all of them are replaced by one cell
/// holding what you typed, ⌫ or ⌦ takes exactly them and closes the
/// stack, Escape lets go of them".
final class HeldCellsTests: XCTestCase {
    func testBackspaceOverCellsHeldWithAHoleTakesThemAndOneUndoBringsThemBack() {
        // It THREW: the cells' deletions are made back to front, NSTextView
        // was handed the ranges in that order, and building the combined
        // change it gives the editor's delegate it ran off the end of its
        // own string (NSInvalidArgumentException). ⌫ did nothing but raise.
        let pane = SourcePane(note)
        pane.hold([first, third])
        pane.key(#selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(pane.tv.string, "Second cell")
        pane.tv.undoManager?.undo()
        XCTAssertEqual(pane.tv.string, note)
    }

    func testMovingCellsHeldWithAHoleMovesEachOfThem() {
        // Two moves in one edit, back to front — the same throw.
        let pane = SourcePane("A\n\nB\n\nC\n\nD")
        pane.hold([NSRange(location: 0, length: 1), NSRange(location: 6, length: 1)])
        pane.bridge.moveCell(up: false)
        XCTAssertEqual(pane.tv.string, "B\n\nA\n\nD\n\nC")
    }

    func testTypingOverHalfAHiddenPairStillTakesTheOtherHalf() {
        // The same throw from the other edit made in several parts:
        // `MarkerDeletion` hands its ranges back to front too, so typing
        // over "**bo" in "**bold** here" raised where it should leave
        // "xld here" (AGENTS.md: "an edit over hidden markers takes them
        // whole, and takes a pair together").
        let pane = SourcePane("**bold** here")
        pane.tv.setSelectedRange(NSRange(location: 0, length: 4))
        pane.type("x")
        XCTAssertEqual(pane.tv.string, "xld here")
    }

    func testTypingReplacesEveryHeldCellWithOneCell() throws {
        let edit = try XCTUnwrap(CellCommands.typing("x", over: [first, third], in: note))
        let after = (note as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(after, "x\n\nSecond cell")
        XCTAssertEqual(edit.selection, NSRange(location: 1, length: 0), "the caret after what was typed")
    }

    func testADeleteTakesThemAndPutsNothingInTheirPlace() throws {
        let edit = try XCTUnwrap(CellCommands.typing("", over: [first, third], in: note))
        XCTAssertEqual((note as NSString).replacingCharacters(in: edit.range, with: edit.replacement), "Second cell")
    }

    func testItIsOneEditOverTheSpanThatChanged() throws {
        // One change, so it is one step of undo, and nothing outside it is
        // touched.
        let edit = try XCTUnwrap(CellCommands.typing("x", over: [second], in: note))
        XCTAssertEqual(edit.range.location, 12)
        XCTAssertEqual((note as NSString).replacingCharacters(in: edit.range, with: edit.replacement),
                       "First cell\n\nx\n\nThird cell")
    }

    func testInTheMarkdownPaneEveryHeldCellIsReplacedAndNotOnlyTheFirst() {
        // NSTextView types over the FIRST range of a discontiguous
        // selection and keeps the others: "x\n\nSecond cell\n\nThird cell".
        let pane = SourcePane(note)
        pane.hold([first, third])
        pane.type("x")
        XCTAssertEqual(pane.tv.string, "x\n\nSecond cell")
        XCTAssertEqual(pane.tv.selectedRange(), NSRange(location: 1, length: 0))
        pane.tv.undoManager?.undo()
        XCTAssertEqual(pane.tv.string, note, "one ⌘Z puts all of them back")
    }

    func testASectionsBracketThenTypingReplacesTheWholeSection() {
        // A section's bracket holds every cell under it, one range each:
        // typing replaced the heading and kept the rest of the section.
        let notebook = "# Head\n\none\n\ntwo\n\n# Next\n\nBody"
        let pane = SourcePane(notebook)
        let section = NotebookOutline.sections(in: notebook)[0]
        pane.hold(CellSelection.cells(of: section.range, in: pane.cells))
        pane.type("x")
        XCTAssertEqual(pane.tv.string, "x\n\n# Next\n\nBody")
    }

    func testForwardDeleteTakesThemAllAsBackspaceDoes() {
        // NSTextView took their words and left the blank lines between
        // them standing: "\n\nSecond cell\n\n". The rendered page's ⌦ is
        // its ⌫, and closes the stack.
        let pane = SourcePane(note)
        pane.hold([first, third])
        pane.key(#selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(pane.tv.string, "Second cell")
    }

    func testMovingOrCopyingThemIsStillAMoveAndACopy() {
        // A GUARD: those commands edit the same held cells through the same
        // text view; only the user's own keystroke over them is typing.
        let moved = SourcePane(note)
        moved.hold([first, second])
        moved.bridge.moveCell(up: false)
        XCTAssertEqual(moved.tv.string, "Third cell\n\nFirst cell\n\nSecond cell")
        let copied = SourcePane(note)
        copied.hold([first, third])
        copied.bridge.duplicateCell()
        XCTAssertEqual(copied.blocks.count, 5)
    }

    func testEscapeLetsHeldCellsGo() {
        // The rendered page's column: "Escape: the brackets go out and the
        // note is untouched" (`MarkdownPreview.cellKey`). Here they stayed
        // held, and Escape ran NSTextView's word completion over them.
        let pane = SourcePane(note)
        pane.hold([first, third])
        pane.key(#selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(pane.held, [])
        XCTAssertEqual(pane.tv.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(pane.tv.string, note)
    }
}

// MARK: - The gutter

final class HeldBracketClickTests: XCTestCase {
    func testAStillClickOnOneOfSeveralHeldBracketsTakesItAlone() throws {
        // A press on a held bracket begins a MOVE; one that never moved did
        // nothing at all, and every cell stayed held. The rendered page's
        // column has always called the same press a click.
        let pane = SourcePane(note)
        pane.hold([first, third])
        let bracket = try XCTUnwrap(pane.gutter.brackets.first { $0.isCell && NSEqualRanges($0.range, third) })
        XCTAssertTrue(bracket.held, "the premise")
        let point = NSPoint(x: NotebookGutter.width - 6, y: (bracket.top + bracket.bottom) / 2)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: pane.gutter.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { pane.gutter.mouseDown(with: event) } else { pane.gutter.mouseUp(with: event) }
        }
        XCTAssertEqual(pane.held, [third])
        XCTAssertEqual(pane.tv.string, note, "and nothing moved")
    }
}

// MARK: - A command that acts on a cell, at a bar

/// AGENTS.md, "A COMMAND AT A BAR MAKES THE CELL THERE": the commands that
/// act ON a cell — delete, duplicate, move, split, merge — "still do
/// nothing at a bar".
final class CellCommandAtABarTests: XCTestCase {
    func testOnTheRenderedPageNoneOfThemReachesTheNote() {
        // Its hooks fall back to the note's FIRST cell when nothing is held
        // or open, and at a bar nothing is: Delete Cell took the top of the
        // note, ⌃M joined its first two cells.
        let commands: [(String, (EditorBridge) -> Void)] = [
            ("Delete Cell", { $0.deleteCell() }), ("Duplicate Cell", { $0.duplicateCell() }),
            ("Move Cell Up", { $0.moveCell(up: true) }), ("Move Cell Down", { $0.moveCell(up: false) }),
            ("Merge Cells", { $0.mergeCells() }), ("Split Cell", { $0.splitCell() }),
            ("Move Section Up", { $0.moveSection(up: true) }),
        ]
        for (name, command) in commands {
            let bridge = EditorBridge()
            var reached: [String] = []
            bridge.barIsUp = { true }
            bridge.armedBar = { _ in reached.append("a cell made"); return true }
            bridge.cellEditInDocument = { _ in reached.append("cells") }
            bridge.mergeCellsInDocument = { reached.append("merge") }
            bridge.splitCellInDocument = { reached.append("split") }
            bridge.moveSectionInDocument = { _ in reached.append("section") }
            command(bridge)
            XCTAssertEqual(reached, [], name)
        }
    }

    func testInTheMarkdownPaneMoveSectionDoesNothingEither() {
        // The caret a bar parks at the start of the cell below moved THAT
        // cell's section.
        let notebook = "# A\n\none\n\n# B\n\ntwo"
        let pane = SourcePane(notebook)
        pane.click(seam: 10)
        pane.bridge.moveSection(up: true)
        XCTAssertEqual(pane.tv.string, notebook)
        XCTAssertEqual(pane.tv.armedSeam, 10, "and the bar is still up")
    }
}

// MARK: - A drag from a bar on the rendered page

/// AGENTS.md: "A BRACKET IS ONE OF THREE THINGS, and `!foldable` is not how
/// to ask which." A drag from a bar asked it that way, so the In/Out pair's
/// own bracket was one of the cells it walked.
final class SeamDragTests: XCTestCase {
    // A, then an evaluation cell and its answer, then D — as `cellBrackets`
    // lays them out: the pair's bracket first, then the cells, then the
    // sections.
    private let a = NSRange(location: 0, length: 1)
    private let input = NSRange(location: 3, length: 20)
    private let output = NSRange(location: 25, length: 12)
    private let d = NSRange(location: 39, length: 1)
    private var brackets: [CellBrackets.Bracket] {
        [CellBrackets.Bracket(key: "pair", depth: 0, top: 60, bottom: 140, group: true,
                              range: NSRange(location: 3, length: 34)),
         CellBrackets.Bracket(key: "cell:0", depth: 1, top: 30, bottom: 50, range: a),
         CellBrackets.Bracket(key: "cell:3", depth: 1, top: 60, bottom: 90, range: input),
         CellBrackets.Bracket(key: "cell:25", depth: 1, top: 110, bottom: 140, range: output),
         CellBrackets.Bracket(key: "cell:39", depth: 1, top: 160, bottom: 180, range: d)]
    }

    func testADragDownFromTheBarUnderACellNeverTakesThatCell() throws {
        let seam = CellSeams.Seam(top: 50, bottom: 60, offset: 3, line: 55)
        let drag = try XCTUnwrap(MarkdownPreview.seamDrag(from: seam, by: 115, to: 170, anchor: nil,
                                                          brackets: brackets))
        XCTAssertEqual(drag.cells, [input, output, d])
    }

    func testADragUpOverThePairTakesItsTwoCellsAndNothingAboveThem() throws {
        let seam = CellSeams.Seam(top: 180, bottom: 400, offset: 40, line: 184)
        let drag = try XCTUnwrap(MarkdownPreview.seamDrag(from: seam, by: -100, to: 75, anchor: nil,
                                                          brackets: brackets))
        XCTAssertEqual(drag.cells, [input, output, d])
    }
}
