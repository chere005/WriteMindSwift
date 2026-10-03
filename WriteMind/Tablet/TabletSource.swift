import Combine
import Foundation

// THE PEN WITH NO TABLET PLUGGED IN (Sean, 2026-10-03: "make sure i can
// develop wacom features without a device plugged in").
//
// Every feature on the pen's path — the page, the notebook, the eraser, the
// box, undo and redo by double press, Fit and Real size — used to be
// reachable only with the real CTL-472 in hand. The path now has ONE DOOR,
// `TabletInput.receive`, and anything that can speak for a tablet comes in
// by it: the real HID reader (`TabletController`, which seizes the device),
// the VIRTUAL TABLET (`VirtualTablet`: a pad on screen, the mouse for a pen),
// and a REPLAY of a recorded session (`PenReplay`). What goes through the
// door is the tablet's own word — a raw 10-byte pen report, exactly the
// bytes `WacomPenPacket` reads — so the virtual tablet and a replay exercise
// the real parser, the real `TabletPen` state machine, the real turn and the
// real scribes, and a bug found with no device in the house is a bug the
// device would have shown.
//
// WHO MAY SPEAK is decided in one place and written down here
// (`TabletSourcePolicy`): THE REAL DEVICE ALWAYS WINS — a tablet plugged
// in silences the stand-ins — and the stand-ins are OFF unless a developer
// switched them on (Input Devices ▸ Tablet Developer). A release user's
// flow never has a virtual pen in it.

/// Where a report came from.
enum TabletSourceKind: String, Codable, CaseIterable {
    /// The tablet's own HID reports, seized by WriteMind.
    case hid
    /// What the Wacom driver posts as events when WriteMind does not hold
    /// the tablet (the fallback route).
    case driver
    /// The virtual tablet's pad.
    case virtual
    /// A recorded session played back.
    case replay

    /// The real device, by either of its two routes.
    var isReal: Bool { self == .hid || self == .driver }
}

/// WHICH SOURCE IS HEARD — a value, so a test can walk it through every
/// combination. The real device is always heard; the virtual tablet and a
/// replay only when the developer switch is on AND no real tablet is
/// plugged in: a real tablet WINS the moment it is connected, and the
/// stand-ins are idle until it is gone.
struct TabletSourcePolicy: Equatable {
    /// The developer's switch (`TabletDeveloper.virtualEnabled`): off unless
    /// somebody turned it on.
    var developerOn = false
    /// A real Wacom is plugged in (`TabletController.tablets`).
    var realConnected = false

    func admits(_ kind: TabletSourceKind) -> Bool {
        switch kind {
        case .hid, .driver: return true
        case .virtual, .replay: return developerOn && !realConnected
        }
    }

    /// Why the stand-ins say nothing, in words — nil when they are heard.
    var silence: String? {
        if !developerOn {
            return "The virtual tablet is off — Input Devices ▸ Tablet Developer ▸ Virtual Tablet turns it on."
        }
        if realConnected {
            return "A real tablet is plugged in, so it wins — the virtual tablet is idle until it is unplugged."
        }
        return nil
    }
}

/// One thing a source says: a raw report off a tablet (or the virtual one),
/// or what the driver's events were read as when the tablet was not held.
enum PenStreamEvent: Equatable {
    /// One pen report, the tablet's bytes (`WacomPenPacket`).
    case report([UInt8])
    /// A reading made from the driver's events — the fallback route has no
    /// bytes to give.
    case reading(TabletReading)
}

/// Anything that speaks for a tablet. A host connects it to the funnel
/// (`TabletInput.attach`), after which what it says reaches
/// `TabletInput.receive` tagged with its kind — so the real HID reader and
/// a virtual one are interchangeable at the one place samples enter.
@MainActor
protocol TabletSource: AnyObject {
    var kind: TabletSourceKind { get }
    /// Where this source's events go, with the moment they were made on the
    /// system clock (`ProcessInfo.systemUptime`'s). Nil: it says nothing.
    var door: ((PenStreamEvent, TimeInterval) -> Void)? { get set }
}

extension TabletSource {
    /// Say something through the door, if there is one.
    func emit(_ event: PenStreamEvent, at time: TimeInterval) { door?(event, time) }
}

extension TabletInput {
    /// Connect a source to THE ONE DOOR: from now on what it says is heard
    /// by `receive`, as its own kind.
    @MainActor func attach(_ source: TabletSource) {
        let kind = source.kind
        source.door = { [weak self] event, time in self?.receive(event, at: time, from: kind) }
    }
}

// MARK: - A clock a pen can be run on

/// What time it is and how to ask for something later — the live one, or a
/// test's, which never sleeps (`VirtualClock` in the tests): the taps and
/// the replay's gaps are made of waiting, and a test must not.
@MainActor
protocol PenClock: AnyObject {
    /// Seconds, on the same scale as the pen reports' stamps.
    var now: TimeInterval { get }
    /// Run `work` after `delay` seconds; cancelled by cancelling the result.
    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> AnyCancellable
}

/// The real thing: the system's uptime, the main queue.
@MainActor
final class LivePenClock: PenClock {
    static let shared = LivePenClock()

    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> AnyCancellable {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0), execute: item)
        return AnyCancellable { item.cancel() }
    }
}

// MARK: - A moment of the pen, and the report it is

/// ONE MOMENT OF THE PEN as a tablet would report it: where (raw landscape
/// counts, origin top left, y down), whether the nib is down and how hard,
/// which side switches are held, and whether the pen is near. The virtual
/// tablet, the test script and the recorder's fixtures all say it in this
/// one shape, and `report` is the bytes the real tablet would send for it.
struct PenFrame: Equatable {
    /// Within reach of the tablet at all (0x80 of the report's flags).
    var inRange = true
    /// Near enough that x and y mean something (0x40).
    var hasPosition = true
    /// The tip, the switches and the pressure mean something (0x20).
    var ready = true
    var counts = CGPoint(x: 7600, y: 4750)
    var tip = false
    /// 0…1.
    var pressure = 0.0
    var switches: Set<PenSwitch> = []
    /// The pen's eraser end (0x08). The One by Wacom's pen has none and
    /// nothing reads it: it is here so a report can say it.
    var eraserEnd = false
    /// Height above the surface, in the report's own units: a hover's.
    var distance = 20

    /// The pen out of reach, last seen at `counts` — what the tablet sends
    /// as the pen goes away.
    static func away(at counts: CGPoint) -> PenFrame {
        PenFrame(inRange: false, hasPosition: false, ready: false, counts: counts, tip: false, pressure: 0,
                 switches: [], eraserEnd: false, distance: 0)
    }

    /// The pen coming near, before it has a place: in range, no position.
    static func arriving(at counts: CGPoint) -> PenFrame {
        PenFrame(inRange: true, hasPosition: false, ready: false, counts: counts, tip: false, pressure: 0,
                 switches: [], eraserEnd: false, distance: 20)
    }

    /// The ten bytes the tablet would send (`WacomPenPacket`).
    var report: [UInt8] {
        var flags: UInt8 = 0
        if inRange { flags |= 0x80 }
        if hasPosition { flags |= 0x40 }
        if ready { flags |= 0x20 }
        if eraserEnd { flags |= 0x08 }
        if switches.contains(.upper) { flags |= 0x04 }
        if switches.contains(.lower) { flags |= 0x02 }
        if tip { flags |= 0x01 }
        let x = Self.count(counts.x), y = Self.count(counts.y), p = WacomPenPacket.rawPressure(pressure)
        return [WacomPenPacket.reportID, flags, UInt8(x & 0xFF), UInt8(x >> 8), UInt8(y & 0xFF), UInt8(y >> 8),
                UInt8(p & 0xFF), UInt8(p >> 8), UInt8(clamping: distance), 0]
    }

    /// What the funnel reads out of it, with the pressure EXACT instead of
    /// quantised to the report's 2047 steps — for a test that walks
    /// `TabletPen` alone and wants 0.3 to be 0.3.
    func reading(at timestamp: TimeInterval) -> TabletReading {
        WacomPenPacket(self).reading(at: timestamp)
    }

    static func count(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 0 }
        return min(max(Int(value.rounded()), 0), 0xFFFF)
    }
}

extension WacomPenPacket {
    /// A pressure as the report's 0…2047.
    static func rawPressure(_ pressure: Double) -> Int {
        guard pressure.isFinite else { return 0 }
        return min(max(Int((pressure * fullPressure).rounded()), 0), Int(fullPressure))
    }

    /// The packet a frame is, with the pressure left exact. The same fields
    /// the byte parser fills in, so a frame's `reading` and the reading of
    /// its `report` are one rule applied to two spellings of one moment.
    init(_ frame: PenFrame) {
        inRange = frame.inRange
        hasPosition = frame.hasPosition
        isReady = frame.ready
        tip = frame.tip
        lowerSwitch = frame.switches.contains(.lower)
        upperSwitch = frame.switches.contains(.upper)
        eraser = frame.eraserEnd
        x = PenFrame.count(frame.counts.x)
        y = PenFrame.count(frame.counts.y)
        pressure = min(max(frame.pressure, 0), 1)
        distance = frame.distance
    }
}

extension TabletMapping {
    /// THE INVERSE OF `page`: the counts on the tablet that land at page
    /// fraction (u, v) when it is held turned `quarterTurns`. The virtual
    /// pad is drawn as the page is — the tablet as it lies, turned — and
    /// its pointer has to be turned back into the counts the real tablet
    /// would have reported at the same place on the desk.
    static func counts(forPage page: CGPoint, extent: TabletExtent, quarterTurns: Int) -> CGPoint {
        let u = min(max(Double(page.x), 0), 1), v = min(max(Double(page.y), 0), 1)
        let w = extent.width, h = extent.height
        switch turns(quarterTurns) {
        case 1: return CGPoint(x: v * w, y: (1 - u) * h)
        case 2: return CGPoint(x: (1 - u) * w, y: (1 - v) * h)
        case 3: return CGPoint(x: (1 - v) * w, y: u * h)
        default: return CGPoint(x: u * w, y: v * h)
        }
    }
}
