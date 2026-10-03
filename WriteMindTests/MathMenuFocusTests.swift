import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// THE PALETTE OPENS WITH THE KEYBOARD IN ITS EXPRESSION FIELD — the headline
/// of the 2026-10-03 maths change ("type an expression"), which was covered
/// only by the pure model. The real view is hosted in a window of its own and
/// the window's first responder is asked, so a popover that opens with the
/// field not focused (a click needed before typing) fails here.
/// A window that can be key and stays where it is put — far off every screen, so a test run
/// never shows one.
private final class OffscreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class MathMenuFocusTests: XCTestCase {
    private var window: NSWindow!
    private var defaults: UserDefaults!
    private var suite = "MathMenuFocusTests-\(UUID().uuidString)"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)!
        window = OffscreenWindow(contentRect: NSRect(x: -9000, y: -9000, width: 460, height: 640),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() async throws {
        window.contentView = nil
        window.close()
        defaults.removePersistentDomain(forName: suite)
    }

    private func run(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func host() {
        let state = AppState(defaults: defaults)
        window.contentView = NSHostingView(rootView: MathMenu(isPresented: .constant(true)).environmentObject(state))
    }

    private func assertTheKeyboardIsInTheExpressionField(_ message: String = "", file: StaticString = #filePath,
                                                         line: UInt = #line) throws {
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView,
                                   "nothing in the palette has the keyboard: \(String(describing: window.firstResponder)) \(message)",
                                   file: file, line: line)
        XCTAssertTrue(editor.isFieldEditor, file: file, line: line)
        let field = try XCTUnwrap(editor.delegate as? NSTextField, file: file, line: line)
        XCTAssertTrue((field.placeholderString ?? "").hasPrefix("Expression"),
                      "the keyboard is in some other field: \(field.placeholderString ?? "-") \(message)", file: file, line: line)
    }

    func testTheKeyboardIsInTheExpressionFieldWhenThePaletteOpens() throws {
        host()
        window.orderFrontRegardless()
        window.makeKey()
        run(for: 0.8)
        try assertTheKeyboardIsInTheExpressionField()
    }
}
