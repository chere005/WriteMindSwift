import AppKit

/// What was under the pointer at the last mouse event: a pen pressed this
/// hard, or not a pen at all.
///
/// A Wacom pen's strokes arrive as ordinary left-mouse events whose
/// SUBTYPE is `.tabletPoint` and whose `pressure` runs 0…1 with the nib
/// (measured on Sean's One by Wacom, 2026-10-02: ~120 events a second
/// once coalescing is off, a couple of hundred distinct levels in one
/// session). A mouse or a trackpad sends the same event types with
/// another subtype — a Force Touch trackpad even reports a pressure of
/// its own, which is a click, not a nib — so the SUBTYPE is the only
/// question, and pressure is read only once it has said "pen".
enum PenSample: Equatable {
    case mouse
    case pen(pressure: Double)

    /// What the reader watches. Hover is not in it: a `.mouseMoved`
    /// carries no nib, and reading `.pressure` off one is not safe (the
    /// event does not define it).
    static let watched: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .tabletPoint]

    /// The sample an event carries, or nil for an event that says nothing
    /// about the nib — which leaves whatever was known before it alone.
    /// Pure, and generic over `PenEvent` so a test can prove what it
    /// never asks.
    static func reading<Event: PenEvent>(_ event: Event) -> PenSample? {
        switch event.type {
        case .tabletPoint:
            return .pen(pressure: clamped(event.pressure))
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            guard event.subtype == .tabletPoint else { return .mouse }
            return .pen(pressure: clamped(event.pressure))
        default:
            return nil
        }
    }

    private static func clamped(_ pressure: Float) -> Double {
        let value = Double(pressure)
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// The three things `PenSample.reading` may ask of an event. NSEvent has
/// them already.
protocol PenEvent {
    var type: NSEvent.EventType { get }
    var subtype: NSEvent.EventSubtype { get }
    var pressure: Float { get }
}

extension NSEvent: PenEvent {}

/// The pressure the pen is pressing with NOW, for the drawing layer to
/// read while it handles the same event.
///
/// The layer's pen is a SwiftUI `DragGesture`, which hands over a location
/// and nothing else. A LOCAL monitor sees each event before the window
/// dispatches it, so by the time the gesture's `onChanged` runs for a
/// drag, `sample` already describes that very drag. It watches and never
/// takes: every event goes back out exactly as it came in (`pass`), or
/// every click in the app dies.
final class PenSampleReader {
    static let shared = PenSampleReader()

    /// The last nib pressure seen, and whether the last event that said
    /// anything about the pointer was a pen at all.
    private(set) var pressure: Double = InkOutline.defaultPressure
    private(set) var lastWasTablet = false
    private var monitor: Any?

    /// What the layer reads: the pen and its pressure, or the mouse.
    var sample: PenSample { lastWasTablet ? .pen(pressure: pressure) : .mouse }

    /// Once, when the application has finished launching
    /// (`WriteMindApp.init`); a second call is nothing.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: PenSample.watched) { [weak self] event in
            self?.pass(event) ?? event
        }
    }

    /// Note what `event` says about the nib, and hand it straight back.
    @discardableResult
    func pass(_ event: NSEvent) -> NSEvent {
        note(PenSample.reading(event))
        return event
    }

    func note(_ sample: PenSample?) {
        switch sample {
        case .pen(let pressure)?:
            self.pressure = pressure
            lastWasTablet = true
        case .mouse?:
            lastWasTablet = false
        case nil:
            break
        }
    }
}
