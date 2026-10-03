import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// THE CARET IN A DRAWING CELL (docs/CROSS-PLATFORM.md: the caret key
/// table). A drawing cell takes no characters — its one line is the name of
/// its file — so for anything that WRITES, the caret in one stands in for
/// the bar under it, and nothing a key does can land on the line. One table
/// for both panes, held here; the markdown pane's way in, its text view's
/// own commands, is hosted for real below.
final class DrawingCellKeyTableTests: XCTestCase {
    private let id = UUID(uuidString: "6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6")!
    private var line: String { DrawingCells.line(id) }

    func testTheTableReadOffAKeysCharacters() {
        // A printable character: a text cell after the drawing with it in.
        XCTAssertEqual(DrawingCells.key(characters: "a", chord: false), .write("a"))
        XCTAssertEqual(DrawingCells.key(characters: "É", chord: false), .write("É"))
        XCTAssertEqual(DrawingCells.key(characters: " ", chord: false), .write(" "))
        // Return: an empty cell after it.
        XCTAssertEqual(DrawingCells.key(characters: "\r", chord: false), .empty)
        XCTAssertEqual(DrawingCells.key(characters: "\n", chord: false), .empty)
        // ⌫ and ⌦ HOLD the cell; one stray key never deletes a drawing.
        XCTAssertEqual(DrawingCells.key(characters: "\u{8}", chord: false), .hold)
        XCTAssertEqual(DrawingCells.key(characters: "\u{7F}", chord: false), .hold)
        XCTAssertEqual(DrawingCells.key(characters: "\u{F728}", chord: false), .hold, "the forward delete's own key")
        // ↑ and ↓: the bar above, the bar below.
        XCTAssertEqual(DrawingCells.key(characters: "\u{F700}", chord: false), .step(up: true))
        XCTAssertEqual(DrawingCells.key(characters: "\u{F701}", chord: false), .step(up: false))
        XCTAssertEqual(DrawingCells.key(characters: "\u{1B}", chord: false), .leave)
        // A ⌘ or ⌃ chord is a command's, whatever its character.
        XCTAssertEqual(DrawingCells.key(characters: "0", chord: true), .pass)
        XCTAssertEqual(DrawingCells.key(characters: "\r", chord: true), .pass)
        XCTAssertEqual(DrawingCells.key(characters: "\u{8}", chord: true), .pass)
        // ← and →, the function keys, a tab: nothing of the cell's.
        XCTAssertEqual(DrawingCells.key(characters: "\u{F702}", chord: false), .pass)
        XCTAssertEqual(DrawingCells.key(characters: "\u{F703}", chord: false), .pass)
        XCTAssertEqual(DrawingCells.key(characters: "\u{F704}", chord: false), .pass)
        XCTAssertEqual(DrawingCells.key(characters: "\t", chord: false), .pass)
        XCTAssertEqual(DrawingCells.key(characters: "", chord: false), .pass)
    }

    func testTheSameTableReadOffTheTextViewsCommands() {
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.insertNewline(_:))), .empty)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.insertLineBreak(_:))), .empty)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))), .empty)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.deleteBackward(_:))), .hold)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.deleteForward(_:))), .hold)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.deleteWordBackward(_:))), .hold)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.deleteToEndOfLine(_:))), .hold)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.moveUp(_:))), .step(up: true))
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.moveDown(_:))), .step(up: false))
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.cancelOperation(_:))), .leave)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.moveLeft(_:))), .pass)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.moveRight(_:))), .pass)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.insertTab(_:))), .pass)
        XCTAssertEqual(DrawingCells.key(command: #selector(NSResponder.selectAll(_:))), .pass)
    }

    /// The caret is in the cell anywhere on its line, both ends included —
    /// the end is where ⌘0 leaves it and where a click on the paper puts
    /// it. A selection is not a caret.
    func testTheCaretIsInTheCellAtEitherEndOfItsLineAndASelectionIsNot() {
        let note = "Above\n\n\(line)\n\nBelow"
        let lines = DrawingCells.lines(in: note).map(\.range)
        let range = NSRange(location: 7, length: (line as NSString).length)
        XCTAssertEqual(lines, [range])
        XCTAssertEqual(DrawingCells.cell(atCaret: NSRange(location: range.location, length: 0), lines: lines), range)
        XCTAssertEqual(DrawingCells.cell(atCaret: NSRange(location: NSMaxRange(range), length: 0), lines: lines), range)
        XCTAssertEqual(DrawingCells.cell(atCaret: NSRange(location: 10, length: 0), lines: lines), range)
        XCTAssertNil(DrawingCells.cell(atCaret: NSRange(location: 6, length: 0), lines: lines), "the blank line above")
        XCTAssertNil(DrawingCells.cell(atCaret: NSRange(location: NSMaxRange(range) + 1, length: 0), lines: lines),
                     "the blank line below")
        XCTAssertNil(DrawingCells.cell(atCaret: NSRange(location: 7, length: 3), lines: lines), "a selection is not a caret")
    }

    /// The bar under a drawing cell, as the offset a cell opens at: the
    /// next cell's start, or the note's end under the last cell.
    func testTheSeamAfterACellIsTheNextCellsStartOrTheNotesEnd() {
        let note = "Above\n\n\(line)\n\nBelow"
        let range = DrawingCells.lines(in: note)[0].range
        XCTAssertEqual(DrawingCells.seamAfter(range, in: note), (note as NSString).range(of: "Below").location)
        let last = "Above\n\n\(line)"
        XCTAssertEqual(DrawingCells.seamAfter(DrawingCells.lines(in: last)[0].range, in: last), (last as NSString).length)
        // Two drawings in a row: the second's start.
        let two = "\(line)\n\n\(DrawingCells.line(UUID()))"
        XCTAssertEqual(DrawingCells.seamAfter(DrawingCells.lines(in: two)[0].range, in: two),
                       (line as NSString).length + 2)
    }

    /// The caret never rests INSIDE the hidden line: strictly inside it goes
    /// to an end — forward to the end, back to the start — and a selection
    /// that takes part of the line takes all of it. Either end is a place
    /// to be, so ← from the start and → from the end leave the cell.
    func testTheCaretNeverRestsInsideTheLine() {
        let lines = [NSRange(location: 10, length: 20)]
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 15, length: 0), lines: lines, backwards: false),
                       NSRange(location: 30, length: 0))
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 15, length: 0), lines: lines, backwards: true),
                       NSRange(location: 10, length: 0))
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 10, length: 0), lines: lines, backwards: true),
                       NSRange(location: 10, length: 0), "the start is a place")
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 30, length: 0), lines: lines, backwards: false),
                       NSRange(location: 30, length: 0), "and so is the end")
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 5, length: 0), lines: lines, backwards: false),
                       NSRange(location: 5, length: 0), "outside, nothing moves")
        // A selection: part of the line is all of it.
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 5, length: 10), lines: lines, backwards: false),
                       NSRange(location: 5, length: 25))
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 12, length: 30), lines: lines, backwards: true),
                       NSRange(location: 10, length: 32))
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 12, length: 5), lines: lines, backwards: false),
                       NSRange(location: 10, length: 20), "a piece inside takes the whole line")
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 10, length: 20), lines: lines, backwards: false),
                       NSRange(location: 10, length: 20))
        XCTAssertEqual(DrawingCells.snap(NSRange(location: 0, length: 5), lines: lines, backwards: false),
                       NSRange(location: 0, length: 5))
    }
}

/// THE MARKDOWN PANE, HOSTED FOR REAL, with the caret in a drawing cell and
/// its line hidden: what each key and each command does there.
@MainActor
final class DrawingCellKeyHostedTests: XCTestCase {
    private var windows: [NSWindow] = []
    private let id = UUID(uuidString: "6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6")!
    private var line: String { DrawingCells.line(id) }
    private var note: String { "Above\n\n\(line)\n\nBelow" }
    private var lineRange: NSRange { NSRange(location: 7, length: (line as NSString).length) }
    /// The bar under the drawing cell: where "Below" starts.
    private var after: Int { (note as NSString).range(of: "Below").location }

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows = []
        super.tearDown()
    }

    private final class Text { var value: String; init(_ value: String) { self.value = value } }

    /// The source pane, markers hidden, the caret at `caret`.
    private func hosted(_ text: Text, bridge: EditorBridge = EditorBridge(), caret: Int) throws -> PasteAwareTextView {
        let size = CGSize(width: 600, height: 400)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let binding = Binding(get: { text.value }, set: { text.value = $0 })
        let host = NSHostingView(rootView: MarkdownTextView(text: binding, documentID: nil, bridge: bridge,
                                                            showMarkers: false)
            .frame(width: size.width, height: size.height))
        window.contentView = host
        windows.append(window)
        settle(host)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let tv = try XCTUnwrap(all(host).compactMap { $0 as? PasteAwareTextView }.first { !($0 is BlockTextView) })
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        settle(tv)
        XCTAssertTrue(tv.drawingStandIns, "the premise: the line is hidden, so the keys stand in for the bar")
        XCTAssertEqual(tv.drawingCellAtCaret, lineRange, "the premise: the caret is in the drawing cell")
        return tv
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    func testACharacterOpensATextCellAfterTheDrawingWithItIn() throws {
        let text = Text(note)
        let tv = try hosted(text, caret: NSMaxRange(lineRange))
        tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(tv.string, CellTypes.open(.text, writing: "x", in: note, at: after).markdown)
        XCTAssertEqual(tv.string, "Above\n\n\(line)\n\nx\n\nBelow", "the image line untouched, the x in a cell under it")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: (tv.string as NSString).range(of: "x\n\nBelow").location + 1,
                                                   length: 0), "the caret after what was typed")
        XCTAssertNil(tv.armedSeam, "the bar did its job and went")
    }

    func testReturnOpensAnEmptyCellAfterIt() throws {
        let text = Text(note)
        // The START of the line is in the cell too.
        let tv = try hosted(text, caret: lineRange.location)
        tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        let opened = CellTypes.open(.text, in: note, at: after)
        XCTAssertEqual(tv.string, opened.markdown)
        XCTAssertEqual(tv.selectedRange(), NSRange(location: opened.caret, length: 0))
        XCTAssertNil(tv.armedSeam)
    }

    /// ⌫ HOLDS THE CELL, whole; a second ⌫ takes it, as it takes any held
    /// cell (the pane's own rule, `EditorBridge.deleteHeldCells`).
    func testDeleteHoldsTheCellAndASecondDeleteTakesIt() throws {
        let text = Text(note)
        let tv = try hosted(text, caret: NSMaxRange(lineRange))
        tv.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(tv.string, note, "one stray key never deletes a drawing")
        XCTAssertEqual(tv.selectedRange(), lineRange, "held whole")
        tv.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertFalse(tv.string.contains(line), "the second ⌫ takes the held cell")
        XCTAssertEqual(MarkdownParser.blocks(from: tv.string), [.paragraph("Above"), .paragraph("Below")])
    }

    func testTheArrowsArmTheBarAboveAndBelowTheCell() throws {
        let text = Text(note)
        let tv = try hosted(text, caret: NSMaxRange(lineRange))
        tv.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(tv.armedSeam, after, "↓ is the bar under the cell")
        XCTAssertEqual(tv.string, note)
        tv.armedSeam = nil
        tv.setSelectedRange(NSRange(location: NSMaxRange(lineRange), length: 0))
        tv.doCommand(by: #selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(tv.armedSeam, lineRange.location, "↑ is the bar above it")
        XCTAssertEqual(tv.string, note)
    }

    /// Every command that NAMES A KIND makes its cell after the drawing —
    /// the ladder, the fence, the evaluation cell, the lists, the quote,
    /// ⌘0 — and the image line is byte for byte what it was: a `# ` or a
    /// fence written onto it would have broken it.
    func testACommandThatNamesAKindMakesItsCellAfterTheDrawing() throws {
        let commands: [(String, CellTypes.Kind, (EditorBridge) -> Void)] = [
            ("⌘1", .heading(.title), { $0.heading(.title) }),
            ("⌘4", .heading(.section), { $0.heading(.section) }),
            ("⌘8", .code, { $0.codeBlock() }),
            ("⌘9", .evaluation(.wolfram), { _ = $0.evaluationCellAtBar(.wolfram) }),
            ("dots", .list(.dots), { $0.bullets() }),
            ("numbered", .list(.numbered), { $0.list(.numbered) }),
            ("quote", .quote, { $0.quote() }),
        ]
        for (name, kind, command) in commands {
            let text = Text(note)
            let bridge = EditorBridge()
            let tv = try hosted(text, bridge: bridge, caret: NSMaxRange(lineRange))
            command(bridge)
            XCTAssertEqual(tv.string, CellTypes.open(kind, in: note, at: after).markdown, name)
            XCTAssertTrue(tv.string.hasPrefix("Above\n\n\(line)\n\n"), "\(name): the drawing's line is untouched")
            XCTAssertEqual(DrawingCells.lines(in: tv.string).map(\.id), [id], name)
        }
        // And ⌘0 itself: the next drawing, after this one.
        let text = Text(note)
        let bridge = EditorBridge()
        let tv = try hosted(text, bridge: bridge, caret: 10)
        bridge.drawingCell()
        let ids = DrawingCells.ids(in: tv.string)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids.first, id)
        XCTAssertEqual(tv.string, "Above\n\n\(line)\n\n\(DrawingCells.line(ids[1]))\n\nBelow")
    }

    /// A drawing cell has no lines of words: nothing to cut, nothing to
    /// join to, nothing to move in or out.
    func testSplitMergeIndentAndOutdentDoNothingInADrawingCell() throws {
        let text = Text(note)
        let bridge = EditorBridge()
        let tv = try hosted(text, bridge: bridge, caret: 10)
        bridge.splitCell()
        XCTAssertEqual(tv.string, note, "⌃D")
        bridge.mergeCells()
        XCTAssertEqual(tv.string, note, "⌃M")
        bridge.indent()
        XCTAssertEqual(tv.string, note, "⌘]")
        bridge.outdent()
        XCTAssertEqual(tv.string, note, "⌘[")
        XCTAssertNil(tv.armedSeam, "and none of them left a bar armed")
        // The cuts themselves refuse, on either side of the drawing.
        XCTAssertNil(NotebookCells.split(text: note, selection: NSRange(location: 10, length: 0)))
        XCTAssertNil(NotebookCells.merge(text: note, selection: NSRange(location: 10, length: 0)))
        XCTAssertNil(NotebookCells.merge(text: note, selection: NSRange(location: after, length: 0)),
                     "the cell under a drawing will not take it")
    }

    /// Duplicate Cell on a drawing cell: a drawing of its own — a new id,
    /// and the store told which file to copy (`EditorBridge.onFork`).
    func testDuplicateCellGivesTheCopyItsOwnDrawing() throws {
        let text = Text(note)
        let bridge = EditorBridge()
        var forked: [(old: UUID, new: UUID)] = []
        bridge.onFork = { forked.append(contentsOf: $0) }
        let tv = try hosted(text, bridge: bridge, caret: NSMaxRange(lineRange))
        bridge.duplicateCell()
        let ids = DrawingCells.ids(in: tv.string)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids.first, id, "the original keeps its drawing")
        XCTAssertNotEqual(ids.last, id, "the copy gets its own")
        XCTAssertEqual(forked.map(\.old), [id])
        XCTAssertEqual(forked.map(\.new), [ids[1]])
        XCTAssertEqual(tv.string, "Above\n\n\(line)\n\n\(DrawingCells.line(ids[1]))\n\nBelow")
    }

    /// With the markers SHOWN the line is text like any other, typed in as
    /// text: the stand-ins are for the hidden line only.
    func testWithTheMarkersShownTheLineIsOrdinaryText() throws {
        let text = Text(note)
        let size = CGSize(width: 600, height: 400)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let binding = Binding(get: { text.value }, set: { text.value = $0 })
        let host = NSHostingView(rootView: MarkdownTextView(text: binding, documentID: nil, bridge: EditorBridge(),
                                                            showMarkers: true)
            .frame(width: size.width, height: size.height))
        window.contentView = host
        windows.append(window)
        settle(host)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let tv = try XCTUnwrap(all(host).compactMap { $0 as? PasteAwareTextView }.first { !($0 is BlockTextView) })
        tv.setSelectedRange(NSRange(location: NSMaxRange(lineRange), length: 0))
        XCTAssertFalse(tv.drawingStandIns)
        XCTAssertEqual(tv.drawingCellAtCaret, lineRange, "it is still known to be the drawing's line")
        tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(tv.string, "Above\n\n\(line)x\n\nBelow", "typed onto the line, as any text is")
    }
}
