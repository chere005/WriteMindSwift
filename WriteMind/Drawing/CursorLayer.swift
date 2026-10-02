import AppKit
import SwiftUI

/// Puts a cursor over the editor without taking any of its clicks.
///
/// The obvious SwiftUI way — push the cursor `onHover` — loses: the text view
/// underneath sets the I-beam from its own tracking area on every mouse move,
/// and whichever ran last wins, so the pen's cursor flickered back to a text
/// cursor (Sean, 2026-09-18: "in drawing mode, the cursor should become a
/// pencil"). A view with a real cursor rect, above the text view, wins the
/// same argument every time; the tracking area is the belt to that braces.
///
/// AND IT IS THERE ONLY WHILE IT HAS A CURSOR TO SHOW (`DrawingCanvas.body`).
/// Being a hosted NSView over the pane is exactly what makes it win: AppKit
/// routes every cursorUpdate in the pane to it, whatever its `hitTest` says.
/// It used to stay mounted with no cursor in cursor mode, and so answered
/// all of the notebook's cursorUpdates with the window's arrow (AGENTS.md:
/// the eighth cause).
struct CursorLayer: NSViewRepresentable {
    /// What the pointer is over the pane while the layer is up. Never nil:
    /// a layer with nothing of its own to show is not mounted at all.
    var cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectView {
        let view = CursorRectView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ view: CursorRectView, context: Context) {
        view.cursor = cursor
    }

    final class CursorRectView: NSView {
        /// Changed in place while the layer stays up — the pencil to the
        /// crosshair, the open hand to the closed one. Going away
        /// altogether is not a change of cursor but the layer coming down,
        /// and AppKit hands the pointer back then by itself: taking a view
        /// with a cursor rect out from under a still pointer rebuilds the
        /// window's rects, and the owner of the rect under the pointer now
        /// is sent a cursorUpdate (measured 2026-10-02, a scratch copy of
        /// the app and a probe with nothing else changing). An arrow put
        /// up here, as it used to be, is an arrow over the notebook, which
        /// is the bug that took this layer out of cursor mode.
        var cursor: NSCursor? {
            didSet {
                guard cursor !== oldValue else { return }
                window?.invalidateCursorRects(for: self)
                if let cursor, isMouseInside { cursor.set() }
            }
        }
        private var isMouseInside = false
        private var monitor: Any?
        /// Sees the pointer once it is over another application.
        private var outside: Any?
        private var observers: [NSObjectProtocol] = []

        /// What this layer has installed: its local monitor, its global
        /// one and its notification observers. All three while it is in a
        /// window and none once it is out of one — a monitor that outlives
        /// its layer keeps setting a cursor for a pane that has gone.
        var watchers: (local: Bool, global: Bool, observers: Int) {
            (monitor != nil, outside != nil, observers.count)
        }

        /// What a pointer at `point` should be shown, given the cursor this
        /// layer wants and whether the pointer was over it a moment ago.
        /// Nil means "leave it alone": either the layer has no cursor of its
        /// own, or the pointer is somewhere else and was already somewhere
        /// else, so that view's cursor is not ours to overwrite.
        ///
        /// The arrow on the way out is the whole point. `NSCursor.set()` is
        /// global and sticks until something else sets one, and the camera
        /// pane, the toolbar and the sidebar set none — so the pencil used to
        /// follow the pointer right out of the note (Sean, 2026-09-19: "the
        /// pen cursor should only appear in the note pane").
        static func cursor(_ cursor: NSCursor?, at point: CGPoint, in rect: CGRect,
                           wasInside: Bool) -> NSCursor? {
            guard let cursor else { return nil }
            if rect.contains(point) { return cursor }
            return wasInside ? .arrow : nil
        }

        /// Whether the pencil has to be handed back, given that the pointer
        /// is no longer ours. Nil means there is nothing to hand back.
        ///
        /// `cursor(_:at:in:wasInside:)` above deals with the pointer moving
        /// from this layer to somewhere else IN THE WINDOW — the camera
        /// pane, the toolbar, the sidebar. This one is the other way out:
        /// the pointer leaves the WINDOW, or the app stops being the active
        /// one, and no mouse-moved event is ever delivered to say so, so the
        /// pencil was left lying over Finder and everything else (Sean,
        /// 2026-09-21: "make sure the draw pen only shows while its in the
        /// notes pane, not outside the app").
        static func reclaimed(cursor: NSCursor?, wasInside: Bool) -> NSCursor? {
            guard cursor != nil, wasInside else { return nil }
            return .arrow
        }

        /// The argument with the text view is settled here, not in the view
        /// hierarchy: a cursorUpdate event is how AppKit hands a view its turn
        /// to set the cursor (the text view's I-beam, the window's arrow), so
        /// while there is a cursor to show and the pointer is over this
        /// layer, those events are swallowed before anyone gets them, and
        /// every move sets the cursor again (Sean, 2026-09-18: "the highlight
        /// cursor keeps coming up").
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                Self.live.remove(self)
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                stopWatchingForLeaving()
                return
            }
            Self.live.add(self)
            // Without this the window is only told about mouse moves while
            // the pointer is inside a tracking area — so the move that
            // LEAVES this layer for the camera pane never arrived, and the
            // pencil stayed on over there (Sean, 2026-09-20: "cursor only
            // becomes a pen in the notes pane in drawing mode!!!!!").
            // Left on when the layer goes: the camera pane's own layer is
            // up beside this one for most of a session and asks the same,
            // and two layers putting back what each found would leave the
            // window with whatever the last one to go happened to find.
            window.acceptsMouseMovedEvents = true
            watchForLeaving()
            // PUT UP UNDER A POINTER THAT HAS NOT MOVED — the pen picked
            // up from the keyboard, ⌘ pressed, the pointer arriving on an
            // object — the pane is this layer's from now, and nothing of
            // ours says so until the pointer moves. AppKit does send a
            // cursorUpdate as the rects are rebuilt, but it is routed to
            // this layer's HOST, not through the monitor, and the window
            // answers it with the ARROW: measured 2026-10-02, a layer put
            // up under a still pointer with this set taken out showed the
            // arrow; with it, its own cursor (in the scratch app, the
            // pencil from the View menu with the pointer held still). On
            // the next turn, once SwiftUI has given it a frame.
            DispatchQueue.main.async { [weak self] in
                guard let self, let cursor = self.cursor, let window = self.window,
                      Self.appHasPointer(in: window),
                      self.region.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil))
                else { return }
                self.isMouseInside = true
                cursor.set()
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.cursorUpdate, .mouseMoved, .leftMouseDragged, .mouseEntered, .mouseExited]) { [weak self] event in
                self?.filter(event) ?? event
            }
        }

        /// What the monitor does with one event, before it is dispatched:
        /// the event to dispatch, or nil to swallow it. Named so a test can
        /// hand it an event without a window that is shown and key.
        func filter(_ event: NSEvent) -> NSEvent? {
            guard let cursor, let window, event.window === window, !isHiddenOrHasHiddenAncestor
            else { return event }
            let point = convert(event.locationInWindow, from: nil)
            let region = self.region
            let inside = region.contains(point)
            guard let wanted = Self.cursor(cursor, at: point, in: region, wasInside: isMouseInside)
            else { isMouseInside = inside; return event }
            isMouseInside = inside
            guard inside else { wanted.set(); return event }
            cursor.set()
            // A monitor runs BEFORE the event is dispatched, so anything
            // the dispatch sets wins over this. Setting it again on the
            // next turn of the run loop runs after all of that.
            DispatchQueue.main.async { [weak self] in
                guard let self, let cursor = self.cursor, let window = self.window else { return }
                let now = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if self.region.contains(now) { cursor.set() }
            }
            return event.type == .cursorUpdate ? nil : event
        }

        /// The part of the window this layer covers, in its own
        /// coordinates: its bounds, cut by whatever clips them.
        ///
        /// NOT `visibleRect` ALONE. For a view SwiftUI hosts it is not cut
        /// to the view's own bounds: measured on macOS 26.6.2, the note's
        /// layer had a visible rect from the bottom of the window to the
        /// top — over the top bar, the tab bar and the footer — and an
        /// infinite one while it was being taken out of its window. Read
        /// as "the pointer is over the note" it put the pencil up over the
        /// formatting bar (`CursorLayerRegionTests`). The split pane does
        /// clip it from the side, which is the half that is worth keeping.
        var region: NSRect { bounds.intersection(visibleRect) }

        /// Every layer that is in a window now, for `claim(at:in:)`.
        private static let live = NSHashTable<CursorRectView>.weakObjects()

        /// The cursor a layer is showing over `point` (window coordinates)
        /// of `window`, and nil where no layer with a cursor is over it.
        ///
        /// WHILE ONE IS, THE POINTER IS THE LAYER'S. Its monitor sets its
        /// cursor before each move is dispatched and again on the next
        /// turn — but the notebook under it is handed the same moves by
        /// its own tracking areas, and the gutter's hand, the seam's bar
        /// and the words' I-beam set in between were two answers to one
        /// event, the flicker of the seventh cause, under the ⌘
        /// crosshair, a hand on an object, and the pencil over the gutter.
        /// So the notebook's move handlers ask this first and give the
        /// same answer, and light nothing for a press the canvas takes
        /// (`LayerClaimTests`).
        static func claim(at point: NSPoint, in window: NSWindow?) -> NSCursor? {
            guard let window else { return nil }
            for layer in live.allObjects where layer.window === window && !layer.isHiddenOrHasHiddenAncestor {
                if let cursor = layer.cursor, layer.region.contains(layer.convert(point, from: nil)) {
                    return cursor
                }
            }
            return nil
        }

        /// Whether this app has the pointer: the app active, `window` key
        /// and the frontmost window under the pointer. `NSCursor.set()` is
        /// global, and the window answers `mouseLocationOutsideOfEventStream`
        /// wherever the pointer is — over another app's window in front of
        /// this one too — so a cursor set on that alone is put up over
        /// somebody else's (AGENTS: "THE PENCIL HAS TO BE HANDED BACK WHEN
        /// THE POINTER LEAVES THE APP").
        private static func appHasPointer(in window: NSWindow) -> Bool {
            NSApp.isActive && window.isKeyWindow
                && NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
                    == window.windowNumber
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let outside { NSEvent.removeMonitor(outside) }
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        /// The three ways the pointer stops being ours without a mouse-moved
        /// event ever saying so: it crosses into another application (a
        /// GLOBAL monitor is the only thing that sees that, and it can only
        /// watch, which is all this needs), the window stops being key, or
        /// the app stops being active. Each hands the pencil back.
        private func watchForLeaving() {
            guard outside == nil else { return }
            outside = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
                [weak self] _ in
                // A global monitor only fires for events going to ANOTHER
                // app, so its arrival is itself the news: the pointer is not
                // here any more.
                self?.handBack()
            }
            for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main) { [weak self] _ in self?.handBack() })
            }
        }

        private func stopWatchingForLeaving() {
            if let outside { NSEvent.removeMonitor(outside) }
            outside = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        /// Put the arrow back, once, if the pencil is ours and still up.
        private func handBack() {
            guard let wanted = Self.reclaimed(cursor: cursor, wasInside: isMouseInside) else { return }
            isMouseInside = false
            wanted.set()
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            if let cursor { addCursorRect(bounds, cursor: cursor) }
        }

        /// Never in the way of a click — the drawing canvas and the text view
        /// below it get every event.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var acceptsFirstResponder: Bool { false }

        /// Over `region`, and not `.inVisibleRect`: the visible rect of a
        /// hosted view runs over the bars above and below the note, so the
        /// pointer coming in over the tab bar was "entered" and got the
        /// pencil there.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: region,
                options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
                owner: self))
        }

        override func mouseEntered(with event: NSEvent) { isMouseInside = true; cursor?.set() }

        override func mouseExited(with event: NSEvent) {
            let had = isMouseInside
            isMouseInside = false
            if had, cursor != nil { NSCursor.arrow.set() }
        }
        override func mouseMoved(with event: NSEvent) { cursor?.set() }

        override func cursorUpdate(with event: NSEvent) {
            if let cursor { cursor.set() } else { super.cursorUpdate(with: event) }
        }
    }
}

/// The cursors the drawing layer uses.
enum DrawingCursors {
    /// A pencil while the pen is up, pointed at the spot it will draw — the
    /// hotspot is the tip, bottom-left, not the image's centre. Black with a
    /// white halo, big enough to see: the first one was a thin white glyph
    /// that vanished on the page (Sean, 2026-09-18: "isn't very visible").
    static let pencil: NSCursor = {
        let size = NSSize(width: 28, height: 28)
        let base = NSImage.SymbolConfiguration(pointSize: 22, weight: .heavy)
        guard let symbol = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Pen"),
              let halo = symbol.withSymbolConfiguration(
                  base.applying(NSImage.SymbolConfiguration(paletteColors: [.white]))),
              let lead = symbol.withSymbolConfiguration(
                  base.applying(NSImage.SymbolConfiguration(paletteColors: [.black])))
        else { return .crosshair }

        let image = NSImage(size: size, flipped: false) { rect in
            let box = rect.insetBy(dx: 3, dy: 3)
            for dx in [-1.5, 0, 1.5] as [CGFloat] {
                for dy in [-1.5, 0, 1.5] as [CGFloat] where dx != 0 || dy != 0 {
                    halo.draw(in: box.offsetBy(dx: dx, dy: dy), from: .zero, operation: .sourceOver, fraction: 1)
                }
            }
            lead.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        // The hot spot is given top-left up; the tip is at the bottom left.
        return NSCursor(image: image, hotSpot: NSPoint(x: 4, y: size.height - 4))
    }()
}
