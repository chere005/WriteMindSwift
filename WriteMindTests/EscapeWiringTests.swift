import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

// ESC, THROUGH THE REAL WIRING. `CanvasKeyTests` holds the layer's Esc chain
// to stub closures, which proves the chain and nothing of what the editor pane
// hands it. These host the real `EditorPane` — the real `DrawingCanvas` in it,
// its real key monitor, the closures `EditorPane` wires to the real `AppState`
// — and send a real Esc through the application (a local monitor is asked
// there). A review (2026-10-03) found the earlier tests pinned an
// `AppState.escapeTool()` that nothing in the app called: the function is
// gone, and what Esc does is what the pane's own closures do.

@MainActor
final class EscapeWiringTests: XCTestCase {
    private var suite: String!
    private var dir: URL!
    private var window: NSWindow!
    private var host: NSHostingView<AnyView>!
    private var store: NoteStore!
    private var appState: AppState!
    private var cell: UUID!

    override func setUp() async throws {
        suite = "WriteMindTests-\(UUID().uuidString)"
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-esc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cell = UUID()
        try Data("# One\n\nfirst\n\n\(DrawingCells.line(cell))\n\nlast\n".utf8).write(to: dir.appending(path: "One.md"))
        store = NoteStore(directory: dir)
        appState = AppState(defaults: UserDefaults(suiteName: suite)!)
        appState.mode = .preview
        let tablet = TabletController(defaults: UserDefaults(suiteName: suite)!, hid: StandInHID(),
                                      input: TabletInput(), live: false)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host = NSHostingView(rootView: AnyView(
            EditorPane()
                .environmentObject(store)
                .environmentObject(appState)
                .environmentObject(CameraController.shared)
                .environmentObject(tablet)
                .frame(width: 900, height: 700)))
        window.contentView = host
        settle()
    }

    override func tearDown() async throws {
        // Takes the layer down, so its key monitor goes with it.
        host.rootView = AnyView(EmptyView())
        settle()
        window.contentView = nil
        window.close()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }

    private func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
    }

    /// A plain Esc for this window, through the application — where the local
    /// key monitors are asked.
    private func pressEscape() throws {
        let esc = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                 isARepeat: false, keyCode: 53))
        NSApp.sendEvent(esc)
        settle()
    }

    private func nothingInHand(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(appState.canvasMode, .cursor, message, file: file, line: line)
        XCTAssertFalse(appState.connectActive, message, file: file, line: line)
        XCTAssertNil(appState.placing, message, file: file, line: line)
        XCTAssertNil(appState.cellDrawing, message, file: file, line: line)
        XCTAssertFalse(appState.canvasOwnsPane, message, file: file, line: line)
        XCTAssertEqual(appState.toolLines, [], message, file: file, line: line)
    }

    /// EVERY TOOL IN HAND IS PUT AWAY BY ESC — the pen, the arrow tool, an
    /// armed shape or mark, and an entered cell — through the layer's chain
    /// and the pane's own closures.
    func testEscPutsAwayWhateverIsInHandThroughTheRealPane() throws {
        let tools: [(String, () -> Void)] = [
            ("the pen", { self.appState.canvasMode = .pen }),
            ("the arrow tool", { self.appState.connectActive = true }),
            ("an armed box", { self.appState.arm(.shape(.rectangle)) }),
            ("an armed tick", { self.appState.arm(.shape(.check)) }),
            ("an armed arrow line", { self.appState.arm(.line(start: .none, end: .arrow)) }),
            ("an entered cell", { self.appState.enterCell(self.cell) }),
        ]
        for (name, pick) in tools {
            pick()
            settle()
            XCTAssertTrue(appState.canvasOwnsPane || appState.cellDrawing != nil, "\(name) was not picked")
            if name == "an entered cell" {
                XCTAssertEqual(appState.cellDrawing, cell, "the pane ended the mode by itself before any key")
            }
            try pressEscape()
            nothingInHand("Esc left \(name) in hand")
            // And the one after it has nothing to put away.
            try pressEscape()
            nothingInHand("a second Esc picked \(name) back up")
        }
    }

    /// No KEY CHANGES THE TABLET'S TARGET (`TabletTarget`): an Esc that sent
    /// the pen back to the page was taken from every Esc meant for the notes,
    /// so the footer names the switch instead. The pane's Esc leaves the nib
    /// where it was put.
    func testEscDoesNotTakeTheTabletsNotebookTarget() throws {
        appState.follow(tabletPicked: true)
        appState.writeOn(.notebook)
        settle()
        try pressEscape()
        XCTAssertEqual(appState.tabletTarget, .notebook)
        XCTAssertEqual(appState.toolLines.map(\.words),
                       ["Tablet pen: writing on the notebook, pick Page on the tablet's bar to stop"])
    }
}
