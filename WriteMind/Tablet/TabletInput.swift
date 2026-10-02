import AppKit
import Combine

// THE PEN, FROM EVERY ROUTE IT MIGHT TAKE, THROUGH ONE FUNNEL.
//
// Measured with Sean's One by Wacom (2026-10-02), with the driver moving
// the pointer as it does by default: the nib's strokes arrive as
// leftMouseDown/Dragged/Up whose SUBTYPE is `.tabletPoint`, a hover as a
// mouseMoved with that subtype, the side switch as rightMouseDown/Dragged/Up
// with buttonMask 0x2, and the pen coming near or going away as a
// mouseMoved with the `.tabletProximity` subtype. `absoluteX/Y` are the
// tablet's own counts, origin top left, y down.
//
// What the driver sends once WriteMind's context has taken the pen off the
// pointer (Mvsc false) nobody has yet seen — "pure tablet events", Wacom's
// docs say, which ought to be `.tabletPoint` / `.tabletProximity` events
// of their own, and which might be routed to another application if the
// pointer stopped over its window. So everything that could be the pen is
// taken: native tablet events AND mouse events with a tablet subtype, from
// a LOCAL monitor (events sent to WriteMind) and a GLOBAL one (events sent
// elsewhere — watched, never touched), de-duplicated by timestamp so a
// sample that came by two routes counts once. The first real session is
// diagnosed from /tmp/writemind-debug.log: the first event of each kind is
// written there, with which monitor saw it.
//
// Everything that decides anything — the reading of one event, the mapping
// onto the page, the rotation, the pen's state from one event to the next —
// is pure and tested with synthetic samples. Only the monitors are not.

/// The tablet's active area in its own counts.
struct TabletExtent: Equatable {
    var width: Double
    var height: Double

    /// One by Wacom, small and medium — the Linux driver's table
    /// (wacom_wac.c), 100 counts a millimetre. The driver's own answer wins
    /// when it gives one; this is for when it does not.
    static func known(productID: Int) -> TabletExtent? {
        switch productID {
        case 0x037A: return TabletExtent(width: 15200, height: 9500)   // CTL-472
        case 0x037B: return TabletExtent(width: 21600, height: 13500)  // CTL-672
        default: return nil
        }
    }

    /// For a tablet nobody has measured: the small One by Wacom's shape,
    /// which the widening below then grows to whatever the pen reaches.
    static let fallback = TabletExtent(width: 15200, height: 9500)

    /// WIDENED TO THE LARGEST VALUE EVER SEEN, so a wrong table entry or a
    /// driver that answered for some other tablet can never clip the page:
    /// a count past the edge moves the edge.
    func widened(toInclude counts: CGPoint) -> TabletExtent {
        TabletExtent(width: max(width, Double(counts.x)), height: max(height, Double(counts.y)))
    }
}

/// Counts on the tablet to a place on the page.
enum TabletMapping {
    /// Quarter turns clockwise, always 0…3 whatever was asked.
    static func turns(_ quarterTurns: Int) -> Int { ((quarterTurns % 4) + 4) % 4 }

    /// The page fraction (u, v) — origin top left, 0…1 both ways — of a
    /// point at `counts` on a tablet of `extent`, held turned `quarterTurns`
    /// clockwise from the landscape it shipped in.
    ///
    /// ONE QUARTER TURN IS THE DEFAULT (Sean, 2026-10-02: "i want to
    /// rotate the wacom 90 degrees clockwise for when its in use in
    /// WriteMind"): u = 1 − y/H, v = x/W, and the page is H/W wide.
    static func page(_ counts: CGPoint, extent: TabletExtent, quarterTurns: Int) -> CGPoint {
        let x = clamp(Double(counts.x) / max(extent.width, 1))
        let y = clamp(Double(counts.y) / max(extent.height, 1))
        switch turns(quarterTurns) {
        case 1: return CGPoint(x: 1 - y, y: x)
        case 2: return CGPoint(x: 1 - x, y: 1 - y)
        case 3: return CGPoint(x: y, y: 1 - x)
        default: return CGPoint(x: x, y: y)
        }
    }

    /// The page's width over its height: the tablet's own shape, turned.
    static func aspect(of extent: TabletExtent, quarterTurns: Int) -> CGFloat {
        guard extent.width > 0, extent.height > 0 else { return 1 }
        let landscape = extent.width / extent.height
        return CGFloat(turns(quarterTurns) % 2 == 0 ? landscape : 1 / landscape)
    }

    /// The biggest rectangle of `aspect` that fits `pane` less `margin` all
    /// round, centred in it.
    static func fit(aspect: CGFloat, in pane: CGSize, margin: CGFloat) -> CGRect {
        let room = CGSize(width: max(pane.width - 2 * margin, 1), height: max(pane.height - 2 * margin, 1))
        guard aspect > 0 else { return CGRect(origin: CGPoint(x: margin, y: margin), size: room) }
        let byWidth = CGSize(width: room.width, height: room.width / aspect)
        let size = byWidth.height <= room.height ? byWidth : CGSize(width: room.height * aspect, height: room.height)
        return CGRect(x: (pane.width - size.width) / 2, y: (pane.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

/// The fields `TabletReading` may ask of an event. NSEvent has them all —
/// but asking one that the event's type does not define is an Objective-C
/// exception that takes the app down, so the reading only asks what the
/// type and subtype have already said is there, and a spy in the tests
/// proves it.
protocol TabletEventFields {
    var type: NSEvent.EventType { get }
    var subtype: NSEvent.EventSubtype { get }
    var timestamp: TimeInterval { get }
    var pressure: Float { get }
    var absoluteX: Int { get }
    var absoluteY: Int { get }
    var buttonMask: NSEvent.ButtonMask { get }
    var isEnteringProximity: Bool { get }
}

extension NSEvent: TabletEventFields {}

/// What one event says about the pen, or nothing for an event that is not
/// the pen's.
struct TabletReading: Equatable {
    enum Kind: Equatable {
        /// Where the nib is, in counts, and what is pressed.
        case point(counts: CGPoint, tip: Bool, sideSwitch: Bool, pressure: Double, buttons: UInt)
        /// The pen came within reach of the tablet, or left it.
        case proximity(entering: Bool)
    }

    let kind: Kind
    let timestamp: TimeInterval
    /// True for an event of the tablet's own type, false for a mouse event
    /// carrying a tablet subtype — for the log, which is how the first
    /// session says which route the driver took.
    let native: Bool

    /// Every event type the funnel watches.
    static let watched: NSEvent.EventTypeMask = [
        .leftMouseDown, .leftMouseDragged, .leftMouseUp,
        .rightMouseDown, .rightMouseDragged, .rightMouseUp,
        .mouseMoved, .tabletPoint, .tabletProximity,
    ]

    /// Pure, and generic so a spy can show what is never asked.
    static func reading<Event: TabletEventFields>(_ event: Event) -> TabletReading? {
        switch event.type {
        case .tabletProximity:
            return TabletReading(kind: .proximity(entering: event.isEnteringProximity),
                                 timestamp: event.timestamp, native: true)
        case .tabletPoint:
            // A pure tablet event says whether the nib is down by its
            // buttons or by its pressure; either will do.
            let pressure = clamped(event.pressure)
            let buttons = event.buttonMask
            return point(event, buttons: buttons, tip: buttons.contains(.penTip) || pressure > 0,
                         sideSwitch: buttons.contains(.penLowerSide), pressure: pressure, native: true)
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp,
             .rightMouseDown, .rightMouseDragged, .rightMouseUp, .mouseMoved:
            switch event.subtype {
            case .tabletProximity:
                return TabletReading(kind: .proximity(entering: event.isEnteringProximity),
                                     timestamp: event.timestamp, native: false)
            case .tabletPoint:
                let buttons = event.buttonMask
                var tip = buttons.contains(.penTip)
                var side = buttons.contains(.penLowerSide)
                // The event's own type is the surest word on the button it
                // is about; the mask speaks for the other one.
                switch event.type {
                case .leftMouseDown, .leftMouseDragged: tip = true
                case .leftMouseUp: tip = false
                case .rightMouseDown, .rightMouseDragged: side = true
                case .rightMouseUp: side = false
                default: break
                }
                // A hover's pressure is not read at all (see PenSample);
                // the side switch's is made up (1.0, measured) and means
                // nothing. Only a nib on the tablet has one.
                let pressure = tip && event.type != .mouseMoved ? clamped(event.pressure) : 0
                return point(event, buttons: buttons, tip: tip, sideSwitch: side, pressure: pressure, native: false)
            default:
                // A mouse, a trackpad: not the pen, and never touched.
                return nil
            }
        default:
            return nil
        }
    }

    private static func point<Event: TabletEventFields>(_ event: Event, buttons: NSEvent.ButtonMask, tip: Bool,
                                                        sideSwitch: Bool, pressure: Double,
                                                        native: Bool) -> TabletReading {
        TabletReading(kind: .point(counts: CGPoint(x: event.absoluteX, y: event.absoluteY), tip: tip,
                                   sideSwitch: sideSwitch, pressure: pressure, buttons: UInt(buttons.rawValue)),
                      timestamp: event.timestamp, native: native)
    }

    private static func clamped(_ pressure: Float) -> Double {
        let value = Double(pressure)
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// One moment of the pen on the page — what `TabletScribe` makes ink and
/// boxes of (and, later, the notebook).
struct TabletSample: Equatable {
    enum Phase: Equatable {
        /// Near the tablet, nothing pressed: the marker follows it.
        case hover
        /// The nib (or the side switch) went down here.
        case down
        /// Still down, here now.
        case drag
        /// Let go, here.
        case up
    }

    /// Where on the page, (u, v) in 0…1 from the top left, after the turn.
    let page: CGPoint
    /// 0…1 while the nib is on the tablet; 0 on a hover and at the up.
    let pressure: Double
    let phase: Phase
    /// The stroke is a SELECTION, not ink: the side switch was held when it
    /// went down. The same on every sample of one down…up, so a stroke is
    /// one thing from start to finish.
    let sideSwitch: Bool
    /// False on the one sample that says the pen went out of reach — the
    /// marker goes, at the last place it was.
    let inProximity: Bool
    let timestamp: TimeInterval
}

/// The pen's state from one reading to the next. A value, so a test can
/// walk it through any sequence.
struct TabletPen {
    private(set) var inProximity = false
    /// The nib or the switch is down.
    private(set) var engaged = false
    /// What the stroke under way is: latched at its down.
    private(set) var selecting = false
    /// The side switch was pressed under a stroke of INK and is still held
    /// after the nib came up: it starts nothing until it has been let go.
    private(set) var switchHeldOver = false
    private(set) var last: CGPoint?
    /// Timestamps lately consumed, points and proximity apart: the same
    /// sample arriving by a second route is a duplicate, not a second
    /// sample.
    private var recentPoints: [TimeInterval] = []
    private var recentProximity: [TimeInterval] = []
    private static let memory = 16

    /// The samples `reading` makes — none for a duplicate, two when the pen
    /// leaves with the nib still down (the up, then the leaving).
    /// `extent` is widened in place by whatever the pen reaches.
    mutating func consume(_ reading: TabletReading, extent: inout TabletExtent,
                          quarterTurns: Int) -> [TabletSample] {
        switch reading.kind {
        case .proximity(let entering):
            guard fresh(reading.timestamp, in: &recentProximity) else { return [] }
            if entering {
                // No position comes with it; the marker appears with the
                // first point rather than flashing up where it last was.
                inProximity = true
                return []
            }
            var out: [TabletSample] = []
            if engaged, let last {
                out.append(sample(last, 0, .up, true, reading.timestamp))
            }
            engaged = false
            selecting = false
            switchHeldOver = false
            inProximity = false
            if let last {
                out.append(sample(last, 0, .hover, false, reading.timestamp))
            }
            return out

        case .point(let counts, let tip, let sideSwitch, let pressure, _):
            guard fresh(reading.timestamp, in: &recentPoints) else { return [] }
            extent = extent.widened(toInclude: counts)
            let page = TabletMapping.page(counts, extent: extent, quarterTurns: quarterTurns)
            last = page
            inProximity = true
            if !sideSwitch { switchHeldOver = false }
            let side = sideSwitch && !switchHeldOver
            // INK ENDS WHERE THE NIB LIFTS. Once a stroke is under way its
            // own kind says what keeps it going: the nib, for ink; the nib
            // or the switch, for a box (the switch let go mid-drag is still
            // the box). Asked as "either", a switch pressed under ink and
            // held past the lift went on drawing in the air at no pressure.
            let pressing = engaged ? (selecting ? tip || side : tip) : tip || side
            let phase: TabletSample.Phase
            switch (engaged, pressing) {
            case (false, true):
                engaged = true
                selecting = side
                phase = .down
            case (true, true):
                phase = .drag
            case (true, false):
                engaged = false
                phase = .up
                // Still held as the ink ended: not a box until pressed again.
                if !selecting, sideSwitch { switchHeldOver = true }
            case (false, false):
                phase = .hover
            }
            let out = sample(page, tip && phase != .up ? pressure : 0, phase, true, reading.timestamp)
            if phase == .up { selecting = false }
            return [out]
        }
    }

    private func sample(_ page: CGPoint, _ pressure: Double, _ phase: TabletSample.Phase,
                        _ inProximity: Bool, _ timestamp: TimeInterval) -> TabletSample {
        TabletSample(page: page, pressure: pressure, phase: phase,
                     sideSwitch: phase == .hover ? false : selecting,
                     inProximity: inProximity, timestamp: timestamp)
    }

    private func fresh(_ timestamp: TimeInterval, in recent: inout [TimeInterval]) -> Bool {
        guard !recent.contains(timestamp) else { return false }
        recent.append(timestamp)
        if recent.count > Self.memory { recent.removeFirst(recent.count - Self.memory) }
        return true
    }
}

/// The funnel itself: the monitors, the pen's state, and the stream of
/// samples. One per app (`shared`); a test makes its own and feeds it.
final class TabletInput: ObservableObject {
    static let shared = TabletInput()

    enum Route: String { case local, global }

    /// Every sample, in order — what `TabletScribe` draws ink and boxes
    /// from. Only while `isCapturing`.
    let samples = PassthroughSubject<TabletSample, Never>()

    /// The pen as last seen, for the hover marker; nil once it is out of
    /// reach. Published at the pen's own rate, so only the marker should
    /// watch it.
    @Published private(set) var pen: TabletSample?

    /// The tablet's area in counts — the driver's answer, else the table,
    /// widened by the pen. The page's shape follows it.
    @Published var extent = TabletExtent.fallback
    /// How the tablet is held (`AppState.tabletQuarterTurns`).
    var quarterTurns = 1

    /// A tablet is the chosen input (`start`/`stop`).
    private(set) var isRunning = false
    /// How many pages are on screen. A count, not a flag: two windows can
    /// each have one, and the first to go must not switch the pen off for
    /// the other.
    private var pagesShowing = 0

    /// THE PEN BELONGS TO THE PAGE only while a tablet is the input and its
    /// page is on screen. Then the local monitor SWALLOWS every pen event —
    /// a tap on the tablet must never click a button or move the caret
    /// under a pointer it happens to have left somewhere — and at every
    /// other time it hands every event back as it came, to a pen that is an
    /// ordinary pen again: the driver's context goes with the last page
    /// (`pageShowingChanged`).
    var isCapturing: Bool { isRunning && pagesShowing > 0 }

    private var state = TabletPen()
    private var local: Any?
    private var global: Any?
    private var seen: Set<String> = []
    private var widened = false
    /// Asked by the global route: events going to other applications count
    /// only while WriteMind is in front, or a pen used in another app would
    /// write on this page.
    var appIsActive: () -> Bool = { NSApp?.isActive ?? false }
    var log: (String) -> Void = { line in if !TestHost.isActive { DebugLog.write(line) } }

    /// The tablet was chosen: watch for the pen. Never in the test host,
    /// which has no tablet.
    func start() {
        isRunning = true
        seen = []
        widened = false
        guard !TestHost.isActive, local == nil else { return }
        local = NSEvent.addLocalMonitorForEvents(matching: TabletReading.watched) { [weak self] event in
            guard let self else { return event }
            return self.handle(event, from: .local)
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: TabletReading.watched) { [weak self] event in
            _ = self?.handle(event, from: .global)
        }
    }

    /// The tablet was let go of: the pen is a pointer again.
    func stop() {
        isRunning = false
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        local = nil
        global = nil
        state = TabletPen()
        if pen != nil { pen = nil }
    }

    /// A page is on screen.
    var pageIsShowing: Bool { pagesShowing > 0 }
    /// Told when the first page comes on screen (true) and when the last
    /// one goes (false): the controller's cue to take the pen off the
    /// pointer, or to give it back (`TabletController.pageShowing`).
    var pageShowingChanged: ((Bool) -> Void)?

    /// A page came on screen, or went.
    func pageAppeared() {
        pagesShowing += 1
        if pagesShowing == 1 { pageShowingChanged?(true) }
    }
    func pageDisappeared() {
        let was = pagesShowing
        pagesShowing = max(pagesShowing - 1, 0)
        if pagesShowing == 0, pen != nil { pen = nil }
        if was == 1 { pageShowingChanged?(false) }
    }

    /// One event from either monitor. Returns what the local monitor hands
    /// on: nil for a pen event taken for the page, the event itself —
    /// unchanged, the same object — for everything else. The global
    /// route's answer is ignored; it can only watch.
    func handle(_ event: NSEvent, from route: Route) -> NSEvent? {
        guard let reading = TabletReading.reading(event) else { return event }
        noteFirst(event, reading, route)
        guard isCapturing else { return event }
        if route == .global, !appIsActive() { return event }
        feed(reading)
        return nil
    }

    /// The pure part's shell: run a reading through the pen's state and
    /// publish what comes out.
    func feed(_ reading: TabletReading) {
        var extent = self.extent
        let out = state.consume(reading, extent: &extent, quarterTurns: quarterTurns)
        if extent != self.extent {
            if !widened {
                widened = true
                log("tablet: the pen reached past the table — extent widened to "
                    + "\(Int(extent.width)) x \(Int(extent.height)) (and further widening is not logged)")
            }
            self.extent = extent
        }
        for sample in out {
            if sample.inProximity != (pen != nil) {
                log("tablet: proximity \(sample.inProximity ? "in" : "out")")
            }
            pen = sample.inProximity ? sample : nil
            samples.send(sample)
        }
    }

    /// ONE LINE PER KIND, NOT PER SAMPLE: the first event of each type and
    /// subtype from each route. A pure tablet event is never asked its
    /// subtype — it has none, and asking is an exception that takes the
    /// app down (measured 2026-10-02).
    private func noteFirst(_ event: NSEvent, _ reading: TabletReading, _ route: Route) {
        let subtype = reading.native ? "none" : String(event.subtype.rawValue)
        let key = "\(route.rawValue)-\(event.type.rawValue)-\(subtype)"
        guard !seen.contains(key) else { return }
        seen.insert(key)
        var line = "tablet: first \(route.rawValue) event type=\(event.type.rawValue) "
            + "subtype=\(subtype) native=\(reading.native)"
        switch reading.kind {
        case .point(_, let tip, let side, _, let buttons):
            line += " buttons=0x\(String(buttons, radix: 16)) tip=\(tip) side=\(side)"
        case .proximity(let entering):
            line += " proximity=\(entering ? "in" : "out")"
        }
        log(line + " capturing=\(isCapturing)")
    }
}
