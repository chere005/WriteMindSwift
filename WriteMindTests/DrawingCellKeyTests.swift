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
