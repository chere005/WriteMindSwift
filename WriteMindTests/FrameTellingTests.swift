import SwiftUI
import XCTest
@testable import WriteMind

/// A pane TELLS THE LAYER ITS DRAWING CELLS' FRAMES the first time it
/// measures, even when it has none (found driving the app, 2026-10-02: a
/// cell made in the markdown pane, then the rendered page, then a stroke on
/// the cell — the stroke floated over it). `EditorPane` used to clear the
/// frames when the mode changed, after the new pane had told its own, and a
/// pane only told what had moved.
@MainActor
final class FrameTellingTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows = []
        super.tearDown()
    }

    private func host<Content: View>(_ view: Content) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view.frame(width: 600, height: 500))
        window.contentView = host
        windows.append(window)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
    }

    func testTheRenderedPageTellsItsFramesOnceEvenWithNoCell() {
        var told: [[CellFrame]] = []
        host(MarkdownPreview(markdown: .constant("Only words here.\n\nAnd more."),
                             onDrawingFrames: { told.append($0) }))
        XCTAssertEqual(told.count, 1, "told once, and told empty")
        XCTAssertEqual(told.first?.count, 0)
    }

    func testTheMarkdownPaneTellsItsFramesOnceEvenWithNoCell() {
        var told: [[CellFrame]] = []
        host(MarkdownTextView(text: .constant("Only words here.\n\nAnd more."), documentID: nil,
                              bridge: EditorBridge(), showMarkers: true,
                              onDrawingFrames: { told.append($0) }))
        XCTAssertGreaterThanOrEqual(told.count, 1, "told, and told empty")
        XCTAssertEqual(told.last?.count, 0)
    }
}
