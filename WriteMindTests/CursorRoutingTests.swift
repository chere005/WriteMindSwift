import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

// WHICH VIEW A CURSORUPDATE REACHES, AND WHAT IT SAYS WHEN IT GETS THERE.
//
// AppKit does not hand a cursorUpdate to the view whose tracking area made
// it. `_routeCursorUpdateEvent` hit-tests the window at the pointer and
// sends `cursorUpdate:` to whatever answers — and while a cursorUpdate is
// the current event, SwiftUI's hosting view answers that hit test with the
// topmost NSView it hosts, whatever that view's own `hitTest` says. The
// drawing layer's `CursorLayer` was always mounted, with no cursor of its
// own in cursor mode, so it answered for the whole pane and the window
// behind it put the arrow up: the horizontal I-beam between two cells went
// back to an arrow every time a cursorUpdate came through (Sean,
// 2026-10-02: "the horizontal cursor stuff should work in markdown view
// mode"). Measured on macOS 26.6.2 — the diagnosis's probes are the
// template for `HostedPane`.

/// Whatever is under the drawing layer — the notebook, in the app: a leaf
/// AppKit view that answers every hit test, as the text view does.
private final class StandIn: NSView {
    override var isFlipped: Bool { true }
}

private struct StandInLayer: NSViewRepresentable {
    let view: StandIn
    func makeNSView(context: Context) -> StandIn { view }
    func updateNSView(_ view: StandIn, context: Context) {}
}

/// A flipped host, so a point in a test reads the same way up as a point
/// in the views it holds.
private final class FlippedPane: NSView {
    override var isFlipped: Bool { true }
}

/// The editor pane cut down to what decides where a cursorUpdate goes: an
/// AppKit view where the notebook is and the drawing layer over it, in one
/// hosting view, in a window that is never shown.
@MainActor
private final class HostedPane {
    let standIn = StandIn()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    /// A bar above the note and a footer below it, the way `EditorPane`
    /// stacks them, or the note alone.
    private let bars: Bool

    /// In window coordinates, with `bars`: the window's content is 300
    /// high, the top bar the 40 points at its top and the footer the 20
    /// at its bottom.
    static let onTheTopBar = NSPoint(x: 200, y: 280)
    static let onTheFooter = NSPoint(x: 200, y: 10)
    static let onTheNote = NSPoint(x: 200, y: 150)

    init(_ mode: AppState.CanvasMode, bars: Bool = false) {
        self.bars = bars
        window.isReleasedWhenClosed = false
        window.contentView = host
        show(mode)
    }

    func show(_ mode: AppState.CanvasMode) {
        let note = ZStack {
            StandInLayer(view: standIn)
            DrawingCanvas(layer: .constant(Drawing()), mode: mode, color: .black, width: 2)
        }
        host.rootView = bars
            ? AnyView(VStack(spacing: 0) {
                Color.gray.frame(height: 40)
                note
                Color.gray.frame(height: 20)
            }.frame(width: 400, height: 300))
            : AnyView(note.frame(width: 400, height: 300))
        settle()
    }

    /// An event of `type` at `point` (window coordinates) in this window.
    func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent? {
        switch type {
        case .cursorUpdate:
            return NSEvent.enterExitEvent(with: .cursorUpdate, location: point, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, trackingNumber: 0, userData: nil)
        default:
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: 0, pressure: 0)
        }
    }

    /// Takes the canvas down, so its own key monitors go with it.
    func close() {
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

    /// Every cursor layer in the pane.
    var layers: [CursorLayer.CursorRectView] { Self.layers(in: host) }

    static func layers(in view: NSView) -> [CursorLayer.CursorRectView] {
        let own = (view as? CursorLayer.CursorRectView).map { [$0] } ?? []
        return own + view.subviews.flatMap { layers(in: $0) }
    }

    /// What the window's hit test answers at `point` (window coordinates)
    /// while an event of `type` is the current one — the very call
    /// `_routeCursorUpdateEvent` makes, at the pointer, on the window's
    /// frame view. The event is posted and dequeued so that it IS
    /// `NSApp.currentEvent`, and never dispatched.
    func hit(at point: NSPoint, during type: NSEvent.EventType) -> NSView? {
        guard let event = event(type, at: point) else { XCTFail("no \(type) event could be made"); return nil }
        return whileCurrent(event) {
            XCTAssertEqual(NSApp.currentEvent?.type, type, "the premise: the event is the current one")
            let frame = window.contentView!.superview!
            return frame.hitTest(frame.convert(point, from: nil))
        }
    }
}

/// Runs `body` with `event` as `NSApp.currentEvent` — posted and dequeued,
/// never dispatched — then leaves the app's current event as it was found,
/// or, if there was none, a harmless application-defined one: a cursorUpdate
/// left current has no click count, so a later reader that asks for one
/// dies, and `NotebookGutter.hitTest` reads it.
@MainActor
func whileCurrent<T>(_ event: NSEvent, _ body: () throws -> T) rethrows -> T {
    let before = NSApp.currentEvent
    defer {
        if let back = before ?? NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                                     timestamp: 0, windowNumber: 0, context: nil,
                                                     subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(back, atStart: true)
            _ = NSApp.nextEvent(matching: NSEvent.EventTypeMask(type: back.type),
                                until: Date(), inMode: .default, dequeue: true)
        }
    }
    NSApp.postEvent(event, atStart: true)
    _ = NSApp.nextEvent(matching: NSEvent.EventTypeMask(type: event.type),
                        until: Date(), inMode: .default, dequeue: true)
    return try body()
}

/// A press or a cursorUpdate at `point` in no window in particular, for
/// making one of them the current event.
@MainActor
func current(_ type: NSEvent.EventType, at point: NSPoint = .zero) -> NSEvent {
    type == .cursorUpdate
        ? NSEvent.enterExitEvent(with: .cursorUpdate, location: point, modifierFlags: [], timestamp: 0,
                                 windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        : NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0,
                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}

private func describe(_ view: NSView?) -> String {
    view.map { String(describing: type(of: $0)) } ?? "nothing"
}

@MainActor
final class CursorUpdateRoutingTests: XCTestCase {
    private let overTheNote = [NSPoint(x: 100, y: 150), NSPoint(x: 300, y: 40), NSPoint(x: 20, y: 280)]

    func testWithNoToolUpACursorUpdateOverTheNoteReachesTheNotebook() {
        let pane = HostedPane(.cursor)
        defer { pane.close() }
        for point in overTheNote {
            // The premise: a mouse event at the same point reaches the
            // notebook, so the layer's `allowsHitTesting(false)` and its
            // `hitTest → nil` both hold for everything else.
            let moved = pane.hit(at: point, during: .mouseMoved)
            XCTAssertTrue(moved === pane.standIn, "a mouse move at \(point) went to \(describe(moved))")
            // The bug: a cursorUpdate at that same point went to the
            // layer's host, and on up to the window's arrow.
            let routed = pane.hit(at: point, during: .cursorUpdate)
            XCTAssertTrue(routed === pane.standIn,
                          "a cursorUpdate at \(point) went to \(describe(routed)), not the notebook")
        }
    }

    func testUnderThePenTheLayerIsWhatACursorUpdateReaches() {
        // Why the pencil's monitor has to SWALLOW cursorUpdates rather than
        // answer them: routed, they reach the layer's host and not
        // `CursorRectView.cursorUpdate`, and the window behind the host
        // puts the arrow up.
        let pane = HostedPane(.pen)
        defer { pane.close() }
        guard let layer = pane.layers.first else { return XCTFail("the premise: the pen's layer") }
        for point in overTheNote {
            let routed = pane.hit(at: point, during: .cursorUpdate)
            XCTAssertFalse(routed === pane.standIn)
            // Its HOST, and not the layer: `CursorRectView.cursorUpdate`
            // is never what answers, which is why the monitor swallows.
            XCTAssertFalse(routed is CursorLayer.CursorRectView,
                           "a cursorUpdate at \(point) reached the layer itself, not its host")
            XCTAssertTrue(routed === layer.superview,
                          "a cursorUpdate at \(point) went to \(describe(routed)), not the layer's host")
        }
    }

    func testTheLayerIsThereOnlyWhileItHasACursorAndTakesItsWatchersWithIt() {
        let pane = HostedPane(.pen)
        defer { pane.close() }
        XCTAssertEqual(pane.layers.count, 1, "the pen's pencil is the layer's")
        guard let pen = pane.layers.first else { return }
        XCTAssertTrue(pen.watchers.local, "the monitor that swallows cursorUpdates")
        XCTAssertTrue(pen.watchers.global, "the one that sees the pointer leave the app")
        XCTAssertEqual(pen.watchers.observers, 2, "resign key, resign active")

        pane.show(.cursor)
        XCTAssertEqual(pane.layers.count, 0, "no tool, no cursor of its own, nothing over the notebook")
        XCTAssertNil(pen.window)
        XCTAssertFalse(pen.watchers.local, "a monitor outlived its layer")
        XCTAssertFalse(pen.watchers.global, "a global monitor outlived its layer")
        XCTAssertEqual(pen.watchers.observers, 0)

        pane.show(.pen)
        XCTAssertEqual(pane.layers.count, 1, "and it comes back with the pen")
        guard let again = pane.layers.first else { return }
        XCTAssertTrue(again.watchers.local)
        XCTAssertTrue(again.watchers.global)
        XCTAssertEqual(again.watchers.observers, 2)
    }
}

// MARK: - Every view a cursorUpdate can reach has an answer of its own

/// The views a cursorUpdate is routed to in the markdown pane — the seam
/// layer, the text view, the gutter — each answer it. None of them may fall
/// through to a default: NSView's goes up the responder chain to the window
/// and its arrow, which over the notebook is exactly the bug.
final class SeamCursorCoverageTests: XCTestCase {
    /// Every kind of seam a page can have: ordinary gaps, a widened pair
    /// that overlap, edges in the middle of a pixel, and an empty note.
    private let pages: [[CellSeams.Seam]] = [
        CellSeams.seams(cells: [(top: 20, bottom: 60, offset: 0), (top: 86, bottom: 120, offset: 12),
                                (top: 146.3, bottom: 180.7, offset: 30)],
                        pageTop: 0, pageBottom: 400, noteLength: 44),
        CellSeams.seams(cells: [(top: 10, bottom: 30, offset: 0), (top: 31, bottom: 33, offset: 5),
                                (top: 34.5, bottom: 60.25, offset: 9)],
                        pageTop: 0, pageBottom: 100, noteLength: 20),
        [CellSeams.Seam(top: 20.3, bottom: 39.6, offset: 0, line: 30),
         CellSeams.Seam(top: 80.5, bottom: 81.2, offset: 7, line: 80.8)],
        CellSeams.seams(cells: [], pageTop: 0, pageBottom: 300, noteLength: 0)
    ]

    func testWhereverAClickIsInASeamThePointerIsInOneToo() {
        // The seam layer takes a point by `seam(at:)` and answers it by
        // `pointerSeam`. A point the first takes and the second does not
        // is a cursorUpdate routed to the layer that the layer cannot
        // answer.
        for (page, seams) in pages.enumerated() {
            let showings: [Int?] = [nil, 999] + seams.map { Optional($0.offset) }
            for showing in showings {
                var missed: [CGFloat] = []
                for step in 0...3440 {
                    let y = CGFloat(step) / 8 - 5
                    if CellSeams.seam(at: y, in: seams) != nil,
                       CellSeams.pointerSeam(at: y, in: seams, showing: showing) == nil {
                        missed.append(y)
                    }
                }
                XCTAssertEqual(missed, [], "page \(page), showing \(String(describing: showing))")
            }
        }
    }

    func testTheSeamLayerAnswersEveryPointItTakes() {
        for (page, seams) in pages.enumerated() {
            let pane = FlippedPane(frame: NSRect(x: 0, y: 0, width: 400, height: 420))
            let layer = CellInsertions(frame: pane.bounds)
            pane.addSubview(layer)
            layer.measure(seams)
            var missed: [NSPoint] = []
            for step in 0...1700 {
                for x in [2, 9, 14, 100, 377.5, 378, 390] as [CGFloat] {
                    let point = NSPoint(x: x, y: CGFloat(step) / 4 - 5)
                    guard layer.hitTest(point) != nil else { continue }
                    if layer.cursor(at: layer.convert(point, from: pane)) == nil { missed.append(point) }
                }
            }
            XCTAssertEqual(missed, [], "page \(page)")
        }
    }
}

/// The bracket column has ONE reader, and the text view asks it rather than
/// answering for the column itself — or saying nothing, which beside a
/// bracket meant nobody answered at all.
final class GutterCursorTests: XCTestCase {
    private let note = "# Title\n\nFirst cell\n\nSecond cell"

    private func gutter() -> (FlippedPane, NotebookGutter) {
        let pane = FlippedPane(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let view = NotebookGutter(frame: NSRect(x: 0, y: 0, width: NotebookGutter.width, height: 200))
        view.brackets = [
            .init(key: "cell:0", depth: 0, top: 20, bottom: 60, collapsed: false,
                  range: NSRange(location: 0, length: 10)),
            .init(key: "section", depth: 1, top: 20, bottom: 140, collapsed: false,
                  range: NSRange(location: 0, length: 30), foldable: true)
        ]
        pane.addSubview(view)
        return (pane, view)
    }

    func testTheHandIsOnABracketAndTheArrowBesideOne() {
        let (_, view) = gutter()
        let cell = view.bounds.maxX - 6
        XCTAssertEqual(view.cursor(at: CGPoint(x: cell, y: 40)), .pointingHand, "on the cell's bracket")
        XCTAssertEqual(view.cursor(at: CGPoint(x: cell - 5, y: 100)), .pointingHand, "on the section's")
        XCTAssertEqual(view.cursor(at: CGPoint(x: 0.5, y: 40)), .arrow, "beside them, at the column's edge")
        XCTAssertEqual(view.cursor(at: CGPoint(x: cell, y: 100)), .arrow, "under the cell's, beside the section's")
        XCTAssertEqual(view.cursor(at: CGPoint(x: cell, y: 180)), .arrow, "below both")
    }

    @MainActor
    func testTheHandIsExactlyWhereTheGutterTakesAClick() {
        // A hand promises a press; the gutter takes the press only on a
        // bracket and leaves every other point to the text view.
        let (pane, view) = gutter()
        var wrong: [NSPoint] = []
        whileCurrent(current(.leftMouseDown)) {
            for step in 0...800 {
                for x in stride(from: 0, through: NotebookGutter.width, by: 0.5) {
                    let point = NSPoint(x: x, y: CGFloat(step) / 4)
                    let takes = view.hitTest(point) != nil
                    let hand = view.cursor(at: view.convert(point, from: pane)) == .pointingHand
                    if takes != hand { wrong.append(point) }
                }
            }
        }
        XCTAssertEqual(wrong, [])
    }

    @MainActor
    func testWhileACursorUpdateIsRoutedTheWholeColumnIsTheGutters() {
        // The pointer, unlike the press, is the column's everywhere — and
        // only the column's: a cursorUpdate beside the column is the words'.
        let (pane, view) = gutter()
        whileCurrent(current(.cursorUpdate)) {
            XCTAssertEqual(NSApp.currentEvent?.type, .cursorUpdate, "the premise")
            for point in [NSPoint(x: 0.5, y: 40), NSPoint(x: 8, y: 100), NSPoint(x: 21.5, y: 190),
                          NSPoint(x: view.bounds.maxX - 6, y: 40)] {
                XCTAssertTrue(view.hitTest(point) === view, "\(point)")
            }
            XCTAssertNil(view.hitTest(NSPoint(x: NotebookGutter.width + 1, y: 40)), "outside the column")
        }
        _ = pane
    }

    /// The text view, its gutter and its seam layer, put together the way
    /// the pane builds them and placed by the pane's own code.
    private func source() -> (PasteAwareTextView, NotebookGutter, CellInsertions) {
        let tv = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        tv.font = MarkdownTextView.font
        tv.textContainerInset = NSSize(width: 24, height: 20)
        tv.string = note
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let gutter = NotebookGutter(frame: .zero)
        tv.addSubview(gutter)
        let insertions = CellInsertions(frame: tv.bounds)
        tv.addSubview(insertions)
        let coordinator = MarkdownTextView(text: .constant(note), documentID: nil,
                                           bridge: EditorBridge()).makeCoordinator()
        coordinator.gutter = gutter
        coordinator.insertions = insertions
        coordinator.refreshBrackets(in: tv)
        return (tv, gutter, insertions)
    }

    func testTheTextViewHandsTheBracketColumnToTheGutter() {
        let (tv, gutter, _) = source()
        XCTAssertGreaterThan(gutter.frame.minX, 300, "the premise: the gutter is on the right")
        let cell = gutter.brackets.first { $0.isCell }
        XCTAssertNotNil(cell, "the premise: the note has a cell with a bracket")
        let y = cell.map { ($0.top + $0.bottom) / 2 } ?? 40
        // The text view's edge is the gutter's: left of it the words have
        // the pointer (nil — NSTextView's own I-beam), right of it the
        // gutter does, through its own reader.
        var wrong: [CGFloat] = []
        for x in stride(from: gutter.frame.minX - 3, to: gutter.frame.maxX, by: 0.5) {
            let point = NSPoint(x: x, y: y)
            let wanted = x < gutter.frame.minX ? nil : gutter.cursor(at: tv.convert(point, to: gutter))
            if tv.cursorForUpdate(at: point) != wanted { wrong.append(x) }
        }
        XCTAssertEqual(wrong, [], "the gutter starts at \(gutter.frame.minX)")
        // And both of the gutter's answers come through it.
        let line = gutter.frame.maxX - 6
        XCTAssertEqual(tv.cursorForUpdate(at: NSPoint(x: line, y: y)), .pointingHand, "on the bracket")
        XCTAssertEqual(tv.cursorForUpdate(at: NSPoint(x: gutter.frame.minX + 0.5, y: y)), .arrow,
                       "beside it, where the gutter's hitTest is nil")
    }
}

/// An open block on the rendered page is a `BlockTextView` — a
/// PasteAwareTextView with no gutter, whose words run to its right edge.
/// The bracket column is the gutter's, so where there is no gutter there
/// is no column: a cursorUpdate there is the words', NSTextView's I-beam.
final class NoGutterCursorTests: XCTestCase {
    func testATextViewWithNoGutterKeepsItsWordsToItsRightEdge() {
        let views: [PasteAwareTextView] = [PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60)),
                                           BlockTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60)),
                                           BlockTextView(frame: NSRect(x: 0, y: 0, width: 18, height: 30))]
        for tv in views {
            tv.string = "A line long enough to run right across the view"
            XCTAssertTrue(tv.subviews.allSatisfy { !($0 is NotebookGutter) }, "the premise: no gutter")
            var wrong: [CGFloat] = []
            for x in stride(from: 0.5, to: tv.bounds.maxX, by: 0.5) where tv.cursorForUpdate(at: NSPoint(x: x, y: 10)) != nil {
                wrong.append(x)
            }
            XCTAssertEqual(wrong, [], "\(type(of: tv)), \(tv.bounds.width) wide")
        }
    }
}

// MARK: - The pointer the event was routed by

/// AppKit picks the view for a cursorUpdate by where the pointer is NOW
/// (`mouseLocationOutsideOfEventStream`), and the event's own location can
/// be a move behind it. A view that reads the event answers for a place
/// the pointer has left: an upright I-beam on a seam, an arrow on a
/// bracket. These put a real point under the real pointer — by moving the
/// window, which is never shown, and never the pointer — and send the
/// event from somewhere else.
@MainActor
final class CursorUpdatePointerTests: XCTestCase {
    private var window: NSWindow!
    private var saved: NSCursor!

    override func setUp() {
        super.setUp()
        saved = NSCursor.current
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 800),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() {
        saved.set()
        window.contentView = nil
        window.close()
        super.tearDown()
    }

    /// Moves the window so that `target`, a point of `view`, is under the
    /// pointer. False if the pointer would not hold still long enough.
    private func underThePointer(_ view: NSView, at target: NSPoint) -> Bool {
        for _ in 0..<5 {
            let inWindow = view.convert(target, to: nil)
            let mouse = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: mouse.x - inWindow.x, y: mouse.y - inWindow.y))
            let now = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if abs(now.x - target.x) <= 1, abs(now.y - target.y) <= 1 { return true }
        }
        return false
    }

    /// A cursorUpdate whose own location is `point`, a point of `view`.
    private func cursorUpdate(at point: NSPoint, of view: NSView) -> NSEvent {
        NSEvent.enterExitEvent(with: .cursorUpdate, location: view.convert(point, to: nil), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    private func source(_ note: String) -> (PasteAwareTextView, NotebookGutter, CellInsertions) {
        let pane = FlippedPane(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        window.contentView = pane
        let tv = PasteAwareTextView(frame: pane.bounds)
        pane.addSubview(tv)
        tv.font = MarkdownTextView.font
        tv.textContainerInset = NSSize(width: 24, height: 20)
        tv.string = note
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let gutter = NotebookGutter(frame: .zero)
        tv.addSubview(gutter)
        let insertions = CellInsertions(frame: tv.bounds)
        tv.addSubview(insertions)
        let coordinator = MarkdownTextView(text: .constant(note), documentID: nil,
                                           bridge: EditorBridge()).makeCoordinator()
        coordinator.gutter = gutter
        coordinator.insertions = insertions
        coordinator.refreshBrackets(in: tv)
        return (tv, gutter, insertions)
    }

    func testTheTextViewAnswersForTheSeamThePointerIsInNotTheCellTheEventSaysItWasIn() throws {
        let (tv, _, insertions) = source("First cell\n\nSecond cell\n\nThird cell")
        guard insertions.seams.count >= 3 else { return XCTFail("the premise: seams between the cells") }
        let seam = insertions.seams[1]
        let inTheSeam = NSPoint(x: 100, y: (seam.top + seam.bottom) / 2)
        let onTheCell = NSPoint(x: 100, y: seam.top - 8)
        XCTAssertNil(insertions.seam(at: onTheCell), "the premise: a cell, the words' I-beam")
        guard underThePointer(tv, at: inTheSeam) else { throw XCTSkip("the pointer would not hold still") }
        NSCursor.crosshair.set()
        tv.cursorUpdate(with: cursorUpdate(at: onTheCell, of: tv))
        XCTAssertEqual(NSCursor.current, .iBeamCursorForVerticalLayout,
                       "the event said a cell; the pointer, which is what AppKit routed by, is in a seam")
    }

    func testTheSeamLayerAnswersForTheCrossThePointerIsOn() throws {
        let (_, _, insertions) = source("First cell\n\nSecond cell\n\nThird cell")
        guard insertions.seams.count >= 3 else { return XCTFail("the premise: seams between the cells") }
        let seam = insertions.seams[1]
        let onThePlus = NSPoint(x: CellInsertions.plus(onTheLineAt: seam.line).midX, y: seam.line)
        let alongTheBar = NSPoint(x: 200, y: seam.line)
        XCTAssertEqual(insertions.cursor(at: onThePlus), .pointingHand, "the premise")
        XCTAssertEqual(insertions.cursor(at: alongTheBar), .iBeamCursorForVerticalLayout, "the premise")
        guard underThePointer(insertions, at: onThePlus) else { throw XCTSkip("the pointer would not hold still") }
        NSCursor.crosshair.set()
        insertions.cursorUpdate(with: cursorUpdate(at: alongTheBar, of: insertions))
        XCTAssertEqual(NSCursor.current, .pointingHand)
    }

    func testTheTextViewHandsTheBracketColumnToTheGutterAtThePointer() throws {
        // Whenever the text view IS handed a cursorUpdate in its bracket
        // column, this handler — not the helper under it — has to ask the
        // gutter. (In the pane as hosted, the clip view is what is routed
        // there beside a bracket: `BracketColumnRoutingTests`.) The event
        // says the words; the pointer is in the column.
        let (tv, gutter, _) = source("First cell\n\nSecond cell")
        guard let cell = gutter.brackets.first(where: \.isCell) else { return XCTFail("the premise: a bracket") }
        let y = (cell.top + cell.bottom) / 2
        let inTheWords = NSPoint(x: 100, y: y)
        let besideIt = NSPoint(x: gutter.frame.minX + 0.5, y: y)
        let onIt = NSPoint(x: gutter.frame.maxX - 6, y: y)
        XCTAssertNil(gutter.hitTest(tv.convert(besideIt, to: gutter.superview)), "the premise: not the gutter's")
        XCTAssertNil(tv.cursorForUpdate(at: inTheWords), "the premise: the words' own I-beam")

        guard underThePointer(tv, at: besideIt) else { throw XCTSkip("the pointer would not hold still") }
        NSCursor.crosshair.set()
        tv.cursorUpdate(with: cursorUpdate(at: inTheWords, of: tv))
        XCTAssertEqual(NSCursor.current, .arrow, "beside the bracket")

        guard underThePointer(tv, at: onIt) else { throw XCTSkip("the pointer would not hold still") }
        NSCursor.crosshair.set()
        tv.cursorUpdate(with: cursorUpdate(at: inTheWords, of: tv))
        XCTAssertEqual(NSCursor.current, .pointingHand, "on the bracket")
    }

    func testTheGutterAnswersForTheBracketThePointerIsOn() throws {
        let (_, gutter, _) = source("First cell\n\nSecond cell")
        guard let cell = gutter.brackets.first(where: \.isCell) else { return XCTFail("the premise: a bracket") }
        let onTheBracket = NSPoint(x: gutter.bounds.maxX - 6, y: (cell.top + cell.bottom) / 2)
        let beside = NSPoint(x: 0.5, y: onTheBracket.y)
        XCTAssertEqual(gutter.cursor(at: onTheBracket), .pointingHand, "the premise")
        XCTAssertEqual(gutter.cursor(at: beside), .arrow, "the premise")
        guard underThePointer(gutter, at: onTheBracket) else { throw XCTSkip("the pointer would not hold still") }
        NSCursor.crosshair.set()
        gutter.cursorUpdate(with: cursorUpdate(at: beside, of: gutter))
        XCTAssertEqual(NSCursor.current, .pointingHand)
    }
}

// MARK: - The layer's own region, and its claim on the notebook under it

/// Where the drawing layer covers. Not its `visibleRect`: for a view SwiftUI
/// hosts, that is not cut to the view's bounds — measured on macOS 26.6.2 it
/// ran from the bottom of the window to the top, over the top bar, the tab
/// bar and the footer, and it is infinite while the view is being taken out
/// of its window. Read as "the pointer is over the note", it put the pencil
/// over the formatting bar.
@MainActor
final class CursorLayerRegionTests: XCTestCase {
    func testTheLayerCoversTheNoteAndNotTheBarsAboveAndBelowIt() {
        let pane = HostedPane(.pen, bars: true)
        defer { pane.close() }
        guard let layer = pane.layers.first else { return XCTFail("the premise: the pen's layer") }
        let at = { (point: NSPoint) in layer.convert(point, from: nil) }
        XCTAssertTrue(layer.region.contains(at(HostedPane.onTheNote)))
        XCTAssertFalse(layer.region.contains(at(HostedPane.onTheTopBar)), "the top bar")
        XCTAssertFalse(layer.region.contains(at(HostedPane.onTheFooter)), "the footer")
    }

    func testThePencilIsTheNotesAndNotTheBars() {
        let saved = NSCursor.current
        defer { saved.set() }
        let pane = HostedPane(.pen, bars: true)
        defer { pane.close() }
        guard let layer = pane.layers.first,
              let overTheBar = pane.event(.mouseMoved, at: HostedPane.onTheTopBar),
              let overTheNote = pane.event(.mouseMoved, at: HostedPane.onTheNote),
              let overTheFooter = pane.event(.mouseMoved, at: HostedPane.onTheFooter),
              let updateOnTheNote = pane.event(.cursorUpdate, at: HostedPane.onTheNote),
              let updateOnTheFooter = pane.event(.cursorUpdate, at: HostedPane.onTheFooter)
        else { return XCTFail("the premise: the pen's layer and the events") }
        XCTAssertTrue(overTheNote.window === pane.window, "the premise: the events are the window's")

        NSCursor.arrow.set()
        _ = layer.filter(overTheBar)
        XCTAssertFalse(NSCursor.current === DrawingCursors.pencil, "the pencil over the top bar")
        _ = layer.filter(overTheNote)
        XCTAssertTrue(NSCursor.current === DrawingCursors.pencil, "the premise: the pencil over the note")
        _ = layer.filter(overTheFooter)
        XCTAssertEqual(NSCursor.current, .arrow, "leaving the note for the footer hands the pencil back")
        XCTAssertNotNil(layer.filter(updateOnTheFooter), "a cursorUpdate over the footer is the footer's")
        XCTAssertNil(layer.filter(updateOnTheNote), "one over the note is swallowed")
    }

    func testTheLayersTrackingAreaIsItsRegion() {
        let pane = HostedPane(.pen, bars: true)
        defer { pane.close() }
        guard let layer = pane.layers.first else { return XCTFail("the premise: the pen's layer") }
        layer.updateTrackingAreas()
        XCTAssertEqual(layer.trackingAreas.count, 1)
        guard let area = layer.trackingAreas.first else { return }
        XCTAssertFalse(area.options.contains(.inVisibleRect), "the visible rect runs over the bars")
        XCTAssertEqual(area.rect, layer.region)
    }
}

/// While a drawing layer shows a cursor of its own — the pen's pencil, the
/// ⌘ crosshair, a hand on an object — its monitor sets that cursor on every
/// move, before the move is dispatched and again on the next turn. The
/// notebook's views are handed the same moves by their own tracking areas,
/// and each answering with its own cursor in between was two answers to
/// one event: a flicker. And a bracket or a seam lit under it promised a
/// press the canvas takes.
@MainActor
final class LayerClaimTests: XCTestCase {
    private var window: NSWindow!
    private var saved: NSCursor!

    override func setUp() {
        super.setUp()
        saved = NSCursor.current
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 800),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() {
        saved.set()
        window.contentView = nil
        window.close()
        super.tearDown()
    }

    private func moved(at point: NSPoint, of view: NSView) -> NSEvent {
        NSEvent.mouseEvent(with: .mouseMoved, location: view.convert(point, to: nil), modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 0, pressure: 0)!
    }

    private func entered(at point: NSPoint, of view: NSView) -> NSEvent {
        NSEvent.enterExitEvent(with: .mouseEntered, location: view.convert(point, to: nil), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    func testWhileALayerShowsItsOwnCursorTheNotebookGivesItsAnswerAndLightsNothing() {
        let note = "First cell\n\nSecond cell\n\nThird cell"
        let pane = FlippedPane(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        window.contentView = pane
        let tv = PasteAwareTextView(frame: pane.bounds)
        pane.addSubview(tv)
        tv.font = MarkdownTextView.font
        tv.textContainerInset = NSSize(width: 24, height: 20)
        tv.string = note
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let gutter = NotebookGutter(frame: .zero)
        tv.addSubview(gutter)
        let insertions = CellInsertions(frame: tv.bounds)
        tv.addSubview(insertions)
        let coordinator = MarkdownTextView(text: .constant(note), documentID: nil,
                                           bridge: EditorBridge()).makeCoordinator()
        coordinator.gutter = gutter
        coordinator.insertions = insertions
        coordinator.refreshBrackets(in: tv)
        var lit: [NSRange] = []
        gutter.onHoverCells = { lit = $0 }

        guard insertions.seams.count >= 3, let cell = gutter.brackets.first(where: \.isCell) else {
            return XCTFail("the premise: cells, seams between them, a bracket")
        }
        let seam = insertions.seams[1]
        let onTheBracket = NSPoint(x: gutter.bounds.maxX - 6, y: (cell.top + cell.bottom) / 2)
        let alongTheBar = NSPoint(x: 200, y: seam.line)
        let onTheWords = NSPoint(x: 60, y: (cell.top + cell.bottom) / 2)
        XCTAssertNil(insertions.seam(at: onTheWords), "the premise: the words, not a seam")

        // With no layer up, each answers for itself — the premise.
        NSCursor.arrow.set()
        gutter.mouseMoved(with: moved(at: onTheBracket, of: gutter))
        XCTAssertEqual(NSCursor.current, .pointingHand)
        XCTAssertFalse(lit.isEmpty, "the bracket's cells lit")
        insertions.mouseMoved(with: moved(at: alongTheBar, of: insertions))
        XCTAssertEqual(NSCursor.current, .iBeamCursorForVerticalLayout)
        XCTAssertNotNil(insertions.pointerPlus, "the seam lit, with its +")

        // The ⌘ crosshair: cursor mode, so the text view has no override
        // and every one of its tracking areas is live.
        let layer = CursorLayer.CursorRectView(frame: pane.bounds)
        layer.cursor = .crosshair
        pane.addSubview(layer)
        defer { layer.removeFromSuperview() }
        XCTAssertNil(tv.cursorOverride, "the premise: cursor mode")

        NSCursor.arrow.set()
        gutter.mouseMoved(with: moved(at: onTheBracket, of: gutter))
        XCTAssertEqual(NSCursor.current, .crosshair, "the gutter on a bracket")
        XCTAssertEqual(lit, [], "a bracket lit under the crosshair")
        NSCursor.arrow.set()
        gutter.mouseEntered(with: entered(at: onTheBracket, of: gutter))
        XCTAssertEqual(NSCursor.current, .crosshair, "the gutter, entered")
        NSCursor.arrow.set()
        insertions.mouseMoved(with: moved(at: alongTheBar, of: insertions))
        XCTAssertEqual(NSCursor.current, .crosshair, "the seam layer along a bar")
        XCTAssertNil(insertions.pointerPlus, "a seam lit under the crosshair")
        NSCursor.arrow.set()
        tv.mouseMoved(with: moved(at: onTheWords, of: tv))
        XCTAssertEqual(NSCursor.current, .crosshair, "the text view over the words")
        NSCursor.arrow.set()
        tv.mouseEntered(with: entered(at: onTheWords, of: tv))
        XCTAssertEqual(NSCursor.current, .crosshair, "the text view, entered")

        // Only where the layer is: one over the foot of the pane claims
        // nothing at the top of it.
        layer.frame = NSRect(x: 0, y: 700, width: 400, height: 100)
        NSCursor.arrow.set()
        gutter.mouseMoved(with: moved(at: onTheBracket, of: gutter))
        XCTAssertEqual(NSCursor.current, .pointingHand, "a layer that is not over the bracket")

        // And the claim goes with the layer.
        layer.frame = pane.bounds
        layer.removeFromSuperview()
        NSCursor.arrow.set()
        gutter.mouseMoved(with: moved(at: onTheBracket, of: gutter))
        XCTAssertEqual(NSCursor.current, .pointingHand, "the layer is gone")
    }
}

// MARK: - The bracket column, in the editor as the pane hosts it

/// Beside a bracket a TextKit 1 text view's `hitTest` is nil — it answers
/// nil for its own inset margins, and the column is 22 of its right 24 — so
/// the hosted editor's hit test used to find the scroll view's CLIP VIEW,
/// which answered with the document cursor, the upright I-beam, while the
/// gutter's moves said the arrow (measured 2026-10-02 on screen under
/// `-NSDebugCursorRects`: I-beam, then arrow). The gutter takes the whole
/// column while a cursorUpdate is current; this asks the hosted editor
/// itself what a cursorUpdate there reaches and what that says.
@MainActor
final class BracketColumnRoutingTests: XCTestCase {
    func testWhateverACursorUpdateReachesInTheColumnGivesTheGuttersAnswer() throws {
        let saved = NSCursor.current
        defer { saved.set() }
        let note = (1...6).map { "Paragraph \($0) with some words in it." }.joined(separator: "\n\n")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MarkdownTextView(text: .constant(note), documentID: nil,
                                                            bridge: EditorBridge()).frame(width: 500, height: 600))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        guard let tv = all(host).compactMap({ $0 as? PasteAwareTextView }).first,
              let gutter = tv.subviews.compactMap({ $0 as? NotebookGutter }).first,
              let cell = gutter.brackets.first(where: \.isCell)
        else { return XCTFail("the premise: the editor, its gutter, a cell's bracket") }

        let y = (cell.top + cell.bottom) / 2
        for (x, wanted) in [(CGFloat(1), NSCursor.arrow), (8, .arrow), (gutter.bounds.maxX - 6, .pointingHand)] {
            let inGutter = NSPoint(x: x, y: y)
            XCTAssertEqual(gutter.cursor(at: inGutter), wanted, "the premise: the gutter's answer at x=\(x)")
            // The real pointer over that point, as AppKit routes by it.
            var held = false
            for _ in 0..<5 where !held {
                let inWindow = gutter.convert(inGutter, to: nil)
                let mouse = NSEvent.mouseLocation
                window.setFrameOrigin(NSPoint(x: mouse.x - inWindow.x, y: mouse.y - inWindow.y))
                let now = gutter.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                held = abs(now.x - inGutter.x) <= 1 && abs(now.y - inGutter.y) <= 1
            }
            guard held else { throw XCTSkip("the pointer would not hold still") }
            let location = gutter.convert(inGutter, to: nil)
            guard let event = NSEvent.enterExitEvent(with: .cursorUpdate, location: location, modifierFlags: [],
                                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window.windowNumber, context: nil,
                                                     eventNumber: 0, trackingNumber: 0, userData: nil)
            else { return XCTFail("no cursorUpdate") }
            let frameView = window.contentView!.superview!
            let routed = whileCurrent(event) { () -> NSView? in
                XCTAssertEqual(NSApp.currentEvent?.type, .cursorUpdate, "the premise: a cursorUpdate is current")
                return frameView.hitTest(frameView.convert(location, from: nil))
            }
            XCTAssertNotNil(routed)
            NSCursor.crosshair.set()
            routed?.cursorUpdate(with: event)
            let names: [(NSCursor, String)] = [(.arrow, "arrow"), (.crosshair, "crosshair (untouched)"),
                                               (.iBeam, "I-beam"), (.pointingHand, "hand")]
            let shown = names.first { $0.0 == NSCursor.current }?.1 ?? "\(NSCursor.current)"
            var chain: [String] = []
            var responder: NSResponder? = routed
            while let next = responder, chain.count < 12 { chain.append(String(describing: type(of: next))); responder = next.nextResponder }
            XCTAssertEqual(NSCursor.current, wanted,
                           "x=\(x): routed to \(routed.map { String(describing: type(of: $0)) } ?? "nothing"), showing \(shown); chain \(chain)")
        }
    }
}
