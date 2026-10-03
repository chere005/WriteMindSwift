import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

// THE LAYER'S KEYS ANSWER FOR THE LAYER AS IT IS NOW, not as it was when it
// came on screen. Its key monitor is installed once, in `onAppear`, and a
// closure there holds a COPY of the view: every plain input it reads — the
// mode, an armed shape, the arrow tool — is frozen at the moment the layer
// appeared, and the layer does not appear again when they change. A note
// opened with the pen down, the pen then picked up: Esc read "no pen" and
// fell through, and the pen stayed up (Sean, 2026-10-02: "esc should exit
// pen mode").

/// What the test turns, as the app's state does: the layer is handed it
/// afresh on every change, the way `EditorPane` hands it `appState`'s.
@MainActor
private final class Knobs: ObservableObject {
    @Published var mode: AppState.CanvasMode = .cursor
    @Published var placing: CanvasPlacement?
    var pensPutDown = 0
    var placingsCalledOff = 0
}

private struct KnobbedCanvas: View {
    @ObservedObject var knobs: Knobs

    var body: some View {
        DrawingCanvas(layer: .constant(Drawing()), mode: knobs.mode, color: .black, width: 2,
                      placing: knobs.placing,
                      onDisarm: { knobs.placingsCalledOff += 1; knobs.placing = nil },
                      onEscapePen: {
                          guard knobs.mode == .pen else { return false }
                          knobs.pensPutDown += 1
                          knobs.mode = .cursor
                          return true
                      })
        .frame(width: 400, height: 300)
    }
}

@MainActor
final class CanvasKeyTests: XCTestCase {
    private var window: NSWindow!
    private var host: NSHostingView<AnyView>!

    override func setUp() async throws {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host = NSHostingView(rootView: AnyView(EmptyView()))
        window.contentView = host
    }

    override func tearDown() async throws {
        // Takes the layer down, so its key monitor goes with it.
        host.rootView = AnyView(EmptyView())
        settle()
        window.contentView = nil
        window.close()
    }

    private func show(_ knobs: Knobs) {
        host.rootView = AnyView(KnobbedCanvas(knobs: knobs))
        settle()
    }

    private func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
    }

    /// A plain Esc for this window, through the application — where the
    /// local key monitors are asked.
    private func pressEscape() throws {
        let esc = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                 isARepeat: false, keyCode: 53))
        NSApp.sendEvent(esc)
        settle()
    }

    /// The premise: a layer that came up with the pen already down hears
    /// Esc, so a key sent through the application reaches its monitor.
    func testEscPutsDownAPenThatWasUpWhenTheLayerCameUp() throws {
        let knobs = Knobs()
        knobs.mode = .pen
        show(knobs)
        try pressEscape()
        XCTAssertEqual(knobs.pensPutDown, 1)
        XCTAssertEqual(knobs.mode, .cursor)
    }

    func testEscPutsDownAPenPickedUpAfterTheLayerCameUp() throws {
        let knobs = Knobs()
        show(knobs)
        knobs.mode = .pen
        settle()
        try pressEscape()
        XCTAssertEqual(knobs.pensPutDown, 1, "the layer's keys still thought the pen was down")
        XCTAssertEqual(knobs.mode, .cursor)
        try pressEscape()
        XCTAssertEqual(knobs.pensPutDown, 1, "a second Esc has no pen to put down")
    }

    func testEscPutsAwayAShapeArmedAfterTheLayerCameUp() throws {
        let knobs = Knobs()
        show(knobs)
        knobs.placing = .shape(.rectangle)
        settle()
        try pressEscape()
        XCTAssertEqual(knobs.placingsCalledOff, 1, "the layer's keys still thought nothing was armed")
        XCTAssertNil(knobs.placing)
    }
}
