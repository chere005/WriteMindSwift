import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WriteMind

// THE DRAWING LAYER'S PART IN THE TABLET'S ERASER, through the layer itself:
// `DrawingCanvas.erase(byTablet:)` is what takes the strokes the nib's path
// touched off the note's floating layer and says the erasure is ONE step back
// — one `onBeginChange` at the first deletion, however many segments follow,
// and ⌘Z claimed for it (`onCursorInk`). The test rig's `RigNotes` plays that
// part for the script's tests, so a step count asserted through the rig would
// be the stand-in's; here the real layer is hosted, headless, and sent the
// same `NotebookErase` values `NotebookScribe.erases` publishes.

@MainActor
private final class HeldLayer: ObservableObject {
    @Published var drawing: Drawing
    var begun = 0
    var inked = 0
    let erases = PassthroughSubject<NotebookErase, Never>()

    init(_ drawing: Drawing) { self.drawing = drawing }
}

private struct HostedLayer: View {
    @ObservedObject var held: HeldLayer

    var body: some View {
        DrawingCanvas(layer: $held.drawing, mode: .cursor, color: .black, width: 2,
                      onBeginChange: { held.begun += 1 },
                      tabletErases: held.erases.eraseToAnyPublisher(),
                      onCursorInk: { held.inked += 1 })
            .frame(width: 400, height: 300)
    }
}

@MainActor
final class TabletEraseLayerTests: XCTestCase {
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
        host.rootView = AnyView(EmptyView())
        settle()
        window.contentView = nil
        window.close()
    }

    private func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
    }

    /// A line across the pane at fraction `y`, from a fifth to four fifths.
    private func line(at y: Double) -> Stroke {
        Stroke(colorHex: "#000000", width: 3, points: [CGPoint(x: 0.2, y: y), CGPoint(x: 0.8, y: y)])
    }

    private func show(_ drawing: Drawing) -> HeldLayer {
        let held = HeldLayer(drawing)
        host.rootView = AnyView(HostedLayer(held: held))
        settle()
        return held
    }

    /// The nib's path, in the layer's document points: straight down at `x`.
    private func path(x: Double, from y0: Double, to y1: Double) -> NotebookErase {
        .path(from: CGPoint(x: x, y: y0), to: CGPoint(x: x, y: y1))
    }

    /// A STROKE THE PATH CROSSES GOES, WHOLE; ONE ERASURE IS ONE STEP, TAKEN
    /// AT THE FIRST DELETION; THE NEXT ERASURE IS ANOTHER; AND A PATH THAT
    /// TOUCHES NOTHING TAKES NO STEP.
    func testTheLayerTakesTheStrokesTheNibCrossedAsOneStepAnErasure() throws {
        let near = line(at: 0.5), far = line(at: 0.9), last = line(at: 0.1)
        let held = show(Drawing(items: [.stroke(near), .stroke(far), .stroke(last)]))
        func ids() -> Set<UUID> { Set(held.drawing.items.map(\.id)) }
        XCTAssertEqual(ids(), [near.id, far.id, last.id])

        // Touching nothing: no step, no claim on ⌘Z.
        held.erases.send(path(x: 200, from: 70, to: 100))
        XCTAssertEqual(held.begun, 0, "a path that touches nothing is no step")
        XCTAssertEqual(held.inked, 0)

        // Across the middle line (y = 150 of 300): it goes, whole.
        held.erases.send(path(x: 200, from: 120, to: 180))
        XCTAssertEqual(ids(), [far.id, last.id], "the stroke the path crossed is gone and nothing else")
        XCTAssertEqual(held.begun, 1, "the step is taken at the first deletion")
        XCTAssertEqual(held.inked, 1, "and ⌘Z is the erasure's")

        // The same erasure goes on across the lower line (y = 270): still one step.
        held.erases.send(path(x: 200, from: 180, to: 290))
        XCTAssertEqual(ids(), [last.id])
        XCTAssertEqual(held.begun, 1, "one erasure is one step however many strokes it takes")
        XCTAssertEqual(held.inked, 1)

        // The nib lifts, and the next erasure is a step of its own.
        held.erases.send(.end)
        held.erases.send(path(x: 200, from: 5, to: 60))
        XCTAssertEqual(ids(), [], "the stroke at y = 30")
        XCTAssertEqual(held.begun, 2, "after the nib lifts, a new erasure is a new step")
        XCTAssertEqual(held.inked, 2)
    }

    /// Only STROKES are erased: a picture, a shape, an arrow stay where they
    /// are, however the nib crosses them.
    func testOnlyStrokesAreErased() throws {
        let ink = line(at: 0.5)
        let box = ShapeItem(kind: .rectangle, center: CGPoint(x: 0.5, y: 0.5), width: 0.4, aspect: 0.5,
                            colorHex: "#000000")
        let held = show(Drawing(items: [.stroke(ink), .shape(box)]))
        held.erases.send(path(x: 200, from: 100, to: 200))
        XCTAssertEqual(held.drawing.items.map(\.id), [box.id], "the line went and the rectangle stayed")
        XCTAssertEqual(held.begun, 1)
    }
}
