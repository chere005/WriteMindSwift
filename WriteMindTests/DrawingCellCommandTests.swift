import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// ⌘0 — a drawing cell here (Sean, 2026-10-02: "drawing cell which is cmd +
/// 0"). At a bar it is made there; in a cell it goes UNDER THE CARET'S OWN
/// LINE, never splitting a fence and never between an In and its Out; on the
/// rendered page with nothing open, in the middle of what is on screen —
/// never after the note's first cell for want of a caret. Bytes exact: the
/// only thing a test cannot know in advance is the id, so it is read back
/// out of the note and the rest is held to the byte.
final class DrawingCellCommandTests: XCTestCase {
    private func view(_ text: String, caret: Int, armed: Bool = false) -> (PasteAwareTextView, EditorBridge) {
        let view = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        view.string = text
        view.setSelectedRange(NSRange(location: caret, length: 0))
        if armed { view.armedSeam = caret }
        let bridge = EditorBridge()
        bridge.textView = view
        return (view, bridge)
    }

    /// ⌘0 with the caret at `caret`: the note after it, the cell's line as
    /// it was made, and where the caret ended up.
    private func zero(_ text: String, at caret: Int, armed: Bool = false)
        -> (note: String, line: String, caret: Int)? {
        let (view, bridge) = view(text, caret: caret, armed: armed)
        bridge.drawingCell()
        let before = Set(DrawingCells.ids(in: text))
        guard let made = DrawingCells.ids(in: view.string).first(where: { !before.contains($0) }) else {
            XCTFail("⌘0 at \(caret) in \(text.debugDescription) made no cell: \(view.string.debugDescription)")
            return nil
        }
        return (view.string, DrawingCells.line(made), view.selectedRange().location)
    }

    // MARK: - The table, row by row

    func testAtAnArmedBarTheCellIsMadeThere() throws {
        let made = try XCTUnwrap(zero("One\n\nTwo", at: 5, armed: true))
        XCTAssertEqual(made.note, "One\n\n\(made.line)\n\nTwo")
        XCTAssertEqual(made.caret, 5 + (made.line as NSString).length, "at the end of its line")
    }

    func testInADrawingCellTheNextOneGoesAfterIt() throws {
        let first = DrawingCells.line(UUID())
        for caret in [0, 10, (first as NSString).length] {
            let made = try XCTUnwrap(zero(first, at: caret))
            XCTAssertEqual(made.note, "\(first)\n\n\(made.line)", "caret at \(caret)")
        }
    }

    func testAnywhereInAOneLineParagraphItGoesAfterIt() throws {
        for caret in [0, 3, 11] {
            let made = try XCTUnwrap(zero("Hello world\n\nNext", at: caret))
            XCTAssertEqual(made.note, "Hello world\n\n\(made.line)\n\nNext", "caret at \(caret)")
            XCTAssertEqual(made.caret, 13 + (made.line as NSString).length)
        }
    }

    func testInAListItGoesUnderTheItemAndTheListIsTwoLists() throws {
        let made = try XCTUnwrap(zero("- a\n- b\n- c", at: 6))
        XCTAssertEqual(made.note, "- a\n- b\n\n\(made.line)\n\n- c")
        XCTAssertEqual(MarkdownParser.blocks(from: made.note).count, 3)
    }

    func testInAParagraphOfSeveralLinesItGoesUnderTheCaretsLine() throws {
        let made = try XCTUnwrap(zero("Line one\nLine two\n\nNext", at: 2))
        XCTAssertEqual(made.note, "Line one\n\n\(made.line)\n\nLine two\n\nNext")
    }

    func testAFenceIsNeverSplit() throws {
        let code = "```swift\nlet a = 1\nlet b = 2\n```\n\nNext"
        let made = try XCTUnwrap(zero(code, at: 12))
        XCTAssertEqual(made.note, "```swift\nlet a = 1\nlet b = 2\n```\n\n\(made.line)\n\nNext")
        let maths = "```wl\nSum[i, {i, 1, n}]\n```"
        let after = try XCTUnwrap(zero(maths, at: 8))
        XCTAssertEqual(after.note, "\(maths)\n\n\(after.line)")
    }

    func testAnEvaluationCellGetsItAfterItsAnswer() throws {
        let note = "```eval python\nprint(1)\n```\n\n```out\n1\n```\n\nNext"
        for caret in [17, 34] {
            let made = try XCTUnwrap(zero(note, at: caret))
            XCTAssertEqual(made.note, "```eval python\nprint(1)\n```\n\n```out\n1\n```\n\n\(made.line)\n\nNext",
                           "caret at \(caret): nothing may come between an In and its Out")
        }
    }

    func testANoteWithNothingInItIsTheCell() throws {
        let made = try XCTUnwrap(zero("", at: 0))
        XCTAssertEqual(made.note, made.line)
    }

    // MARK: - The rendered page

    /// With nothing open the rendered page has no caret, and `caretCell()`
    /// there falls back to the note's FIRST cell — a drawing asked for at
    /// the bottom of the screen would appear at the top of the note.
    func testTheRenderedPageWithNothingOpenUsesTheMiddleOfTheScreenAndNeverTheFirstCell() throws {
        let note = (1...8).map { "Paragraph \($0)" }.joined(separator: "\n\n")
        let rows = MarkdownParser.positioned(from: note).map { (id: $0.range.location, height: CGFloat(40)) }
        let seams = MarkdownPreview.seams(rows: rows, noteLength: (note as NSString).length, pageHeight: 300)
        let wanted = seams[5]
        let at = MarkdownPreview.drawingCellLanding(open: nil, caret: 0, seams: seams, middle: wanted.line + 3,
                                                    in: note)
        XCTAssertEqual(at, wanted.offset)
        let first = try XCTUnwrap(MarkdownParser.positioned(from: note).first?.range)
        XCTAssertNotEqual(at, NSMaxRange(first))
        XCTAssertNotEqual(at, seams[1].offset, "the seam under the first cell")
    }

    func testTheRenderedPageWithACellOpenUsesTheMarkdownPanesRule() {
        let note = "- a\n- b\n- c\n\nNext"
        XCTAssertEqual(MarkdownPreview.drawingCellLanding(open: NSRange(location: 0, length: 11), caret: 6,
                                                          seams: [], middle: 0, in: note),
                       DrawingCells.landing(caret: 6, in: note))
        XCTAssertEqual(DrawingCells.landing(caret: 6, in: note), 7)
    }

    func testOnTheRenderedPageThePageDecidesAndTheFirstCellIsNeverAsked() {
        let bridge = EditorBridge()
        var asked = 0, placed = 0
        bridge.cellRangeInDocument = { asked += 1; return NSRange(location: 0, length: 3) }
        bridge.drawingCellInDocument = { placed += 1 }
        bridge.drawingCell()
        XCTAssertEqual(placed, 1)
        XCTAssertEqual(asked, 0)

        // And a bar armed there makes the cell at the bar, as every kind is.
        var kinds: [CellTypes.Kind?] = []
        bridge.armedBar = { kinds.append($0); return true }
        bridge.drawingCell()
        XCTAssertEqual(kinds, [.drawing])
        XCTAssertEqual(placed, 1, "the bar took it")
    }

    func testABlockOpenOnTheRenderedPageIsNotTheMarkdownPane() {
        // An open cell there is a text view too; without the page's own
        // closure ⌘0 must not write into one rendered block.
        let block = BlockTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        block.string = "Words"
        let bridge = EditorBridge()
        bridge.textView = block
        bridge.drawingCell()
        XCTAssertEqual(block.string, "Words")
    }
}

/// The source pane, hosted for real: ⌘0 is ONE text edit, so ⌘Z takes it
/// out; and Drawing chosen on the + opens at once.
@MainActor
final class DrawingCellHostedTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows = []
        super.tearDown()
    }

    private final class Note { var text: String; init(_ text: String) { self.text = text } }

    private func hosted(_ note: Note, bridge: EditorBridge) throws -> PasteAwareTextView {
        let size = CGSize(width: 600, height: 400)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let binding = Binding(get: { note.text }, set: { note.text = $0 })
        let host = NSHostingView(rootView: MarkdownTextView(text: binding, documentID: nil, bridge: bridge,
                                                            showMarkers: true)
            .frame(width: size.width, height: size.height))
        window.contentView = host
        windows.append(window)
        settle(host)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        return try XCTUnwrap(all(host).compactMap { $0 as? PasteAwareTextView }.first { !($0 is BlockTextView) })
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    func testCommandZeroIsOneTextEditThatUndoTakesOut() throws {
        let note = Note("Hello world\n\nNext")
        let bridge = EditorBridge()
        let tv = try hosted(note, bridge: bridge)
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        bridge.drawingCell()
        let id = try XCTUnwrap(DrawingCells.ids(in: tv.string).first)
        XCTAssertEqual(tv.string, "Hello world\n\n\(DrawingCells.line(id))\n\nNext")
        settle(tv)
        XCTAssertEqual(note.text, tv.string, "the note has it")
        let undo = try XCTUnwrap(tv.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(tv.string, "Hello world\n\nNext")
        settle(tv)
        XCTAssertEqual(note.text, "Hello world\n\nNext")
    }

    func testChoosingDrawingOnThePlusOpensItThereAndThen() throws {
        let note = Note("First cell\n\nSecond cell")
        let tv = try hosted(note, bridge: EditorBridge())
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: 12, length: 0))
        tv.armedSeam = 12
        let plus = try XCTUnwrap(tv.subviews.compactMap { $0 as? CellInsertions }.first)
        plus.onChoose?(.drawing)
        let id = try XCTUnwrap(DrawingCells.ids(in: tv.string).first, tv.string)
        XCTAssertEqual(tv.string, "First cell\n\n\(DrawingCells.line(id))\n\nSecond cell")
        XCTAssertNil(tv.armedSeam, "the bar has done its job")
        XCTAssertEqual(tv.selectedRange().location, 12 + (DrawingCells.line(id) as NSString).length)

        // Any other kind still waits on the bar for what is typed next.
        let other = try hosted(Note("First cell\n\nSecond cell"), bridge: EditorBridge())
        other.setSelectedRange(NSRange(location: 12, length: 0))
        other.armedSeam = 12
        try XCTUnwrap(other.subviews.compactMap { $0 as? CellInsertions }.first).onChoose?(.quote)
        XCTAssertEqual(other.string, "First cell\n\nSecond cell")
        XCTAssertEqual(other.armedType, .quote)
    }
}
