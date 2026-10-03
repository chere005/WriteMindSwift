import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// THE TWO DOORS TO APPKIT THAT LET THE SHAPES COMPOSE AT THE CARET.
/// `MathPalette.choose` is told where the caret is, and the palette's field
/// is a SwiftUI `TextField` with no selection to bind on macOS 14, so the
/// view reads it off the field's editor and puts it back. A field editor
/// that holds some other text — a part field, the note's own text view, a
/// field that has not caught up with a write — must never be taken for it.
@MainActor
final class MathFieldCaretTests: XCTestCase {
    private var window: NSWindow!

    override func setUp() async throws {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() async throws {
        window.contentView = nil
        window.close()
    }

    private func field(_ text: String) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 10, y: 150, width: 300, height: 24))
        field.isEditable = true
        field.stringValue = text
        window.contentView?.addSubview(field)
        return field
    }

    func testItReadsAndPlacesTheCaretOfTheFieldThatHoldsTheText() throws {
        let expression = field("2 Pi r")
        XCTAssertTrue(window.makeFirstResponder(expression))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertTrue(editor.isFieldEditor)
        editor.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertEqual(MathFieldCaret.selection(holding: "2 Pi r", in: window), NSRange(location: 2, length: 0))
        XCTAssertNil(MathFieldCaret.selection(holding: "not what the field holds", in: window))
        XCTAssertNil(MathFieldCaret.selection(holding: "2 Pi r", in: nil))

        XCTAssertTrue(MathFieldCaret.place(5, holding: "2 Pi r", in: window))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertFalse(MathFieldCaret.place(9, holding: "2 Pi r", in: window), "past the end of it")
        XCTAssertFalse(MathFieldCaret.place(1, holding: "not what the field holds", in: window), "it has not caught up yet")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 5, length: 0), "and nothing moved")
    }

    func testAFieldThatIsNotTheExpressionIsNeverTakenForIt() throws {
        let part = field("x^2")
        XCTAssertTrue(window.makeFirstResponder(part))
        XCTAssertNil(MathFieldCaret.selection(holding: "2 Pi r", in: window), "a part field")

        // The note's own text view holds the same words and is not a field editor.
        let notes = NSTextView(frame: NSRect(x: 10, y: 10, width: 300, height: 100))
        notes.string = "2 Pi r"
        window.contentView?.addSubview(notes)
        XCTAssertTrue(window.makeFirstResponder(notes))
        XCTAssertFalse(notes.isFieldEditor)
        XCTAssertNil(MathFieldCaret.selection(holding: "2 Pi r", in: window))
        XCTAssertFalse(MathFieldCaret.place(1, holding: "2 Pi r", in: window))

        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertNil(MathFieldCaret.selection(holding: "2 Pi r", in: window), "nothing has the keyboard")
    }

    private func run(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testSettlingPutsTheCaretBackOnceTheFieldHasCaughtUpWithTheWrite() throws {
        let expression = field("2r")
        XCTAssertTrue(window.makeFirstResponder(expression))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        // The palette wrote "2 Pi r" and wants the caret after the "Pi ": the field shows it a moment later.
        MathFieldCaret.settle(5, holding: "2 Pi r", window: { self.window })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { expression.stringValue = "2 Pi r" }
        run(for: 0.5)
        XCTAssertEqual(editor.string, "2 Pi r")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testSettlingGivesUpWhenTheFieldNeverShowsTheWriteAndTouchesNothingElse() throws {
        let expression = field("something else")
        XCTAssertTrue(window.makeFirstResponder(expression))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        MathFieldCaret.settle(5, holding: "2 Pi r", window: { self.window })
        run(for: 0.4)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 0))
    }
}
