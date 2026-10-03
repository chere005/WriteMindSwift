import AppKit
import Combine

// THE PEN, FROM EVERY ROUTE IT MIGHT TAKE, THROUGH ONE FUNNEL.
//
// TWO ROUTES. The one that keeps the pen off the pointer is RAW CAPTURE:
// WriteMind holds the tablet's HID device and its reports come here as
// readings (`raw`, from `TabletCapture` by way of the controller). The
// other is what the Wacom driver posts when WriteMind does not hold the
// tablet — THE FALLBACK, which writes just as well and moves the pointer
// while it does.
//
// The fallback, measured with Sean's One by Wacom (2026-10-02): the nib's
// strokes arrive as leftMouseDown/Dragged/Up whose SUBTYPE is
// `.tabletPoint`, a hover as a mouseMoved with that subtype, the lower side
// switch as rightMouseDown/Dragged/Up with buttonMask 0x2, the upper one as
// 0x4 in the mask of the nib's own events (`PenSwitch`), and the pen
// coming near or going away as a native `.tabletProximity` event and as a
// mouseMoved with that subtype. `absoluteX/Y` are the tablet's own counts,
// origin top left, y down — the RAW LANDSCAPE frame, whichever way the
// driver's orientation setting is turned, and the same frame the raw
// reports are in. Everything that could be the pen is taken: native tablet
// events AND mouse events with a tablet subtype, from a LOCAL monitor
// (events sent to WriteMind) and a GLOBAL one (events sent elsewhere —
// watched, never touched), de-duplicated by timestamp so a sample that came
// by two routes counts once.
//
// ONE ROUTE AT A TIME: from the first raw report of a capture until the
// tablet is let go, the driver's events are ignored — the same stroke by
// both routes would be two strokes. A seized tablet ought to send the
// driver nothing, so events that KEEP coming say the driver still hears it;
// that is written down once and said in the pane.
//
// A session is diagnosed from /tmp/writemind-debug.log: the first event of
// each kind is written there, with which monitor saw it.
//
// THE PEN'S TWO BUTTONS ARE COMMANDS WHEN CLICKED IN THE AIR (Sean,
// 2026-10-02: "make the wacom buttons undo and redo last drawing"): the
// pen's state (`TabletPen.clicked`) tells a click — pressed and let go with
// the nib up throughout — from a switch held as the nib goes down, which is
// the box, and the click comes down the one stream as a sample of its own
// kind (`TabletSample.Phase.click`), by either route. What it does is the
// scribe's to say (`TabletScribe.command`).
//
// THE RAW ROUTE HAS ONE DOOR, AND MORE THAN THE TABLET USES IT (Sean,
// 2026-10-03: "make sure i can develop wacom features without a device
// plugged in"): `receive` takes a raw pen report from a `TabletSource` —
// the real HID reader, the virtual tablet, a replayed recording — tagged
// with what it is, lets in the real tablet always and the stand-ins only
// when a developer switched them on and no real tablet is plugged in
// (`TabletSourcePolicy`), and reads it with the same `WacomPenPacket` the
// tablet's own reports are read with (TabletSource.swift).
//
// Everything that decides anything — the reading of one event, the mapping
// onto the page, the rotation, the pen's state from one event to the next —
// is pure and tested with synthetic samples. Only the monitors are not.

/// The tablet's active area in its own counts — and, when it is known, how
/// many counts make a millimetre, which is what the paper's ruling is
/// measured by (`PageTheme`).
struct TabletExtent: Equatable {
    var width: Double
    var height: Double
    /// Counts in a millimetre; nil for a tablet nobody has measured.
    var countsPerMillimetre: Double?

    /// THE RAW SENSOR'S OWN EXTENT, landscape as it shipped: One by Wacom,
    /// small and medium — the Linux driver's table (wacom_wac.c), 100
    /// counts a millimetre; the small one is 152 × 95 mm.
    ///
    /// THE WACOM DRIVER'S DIMENSIONS ARE NEVER USED. It reports them
    /// ORIENTED — with its orientation set to portrait on Sean's Mac it
    /// said Xdim 9499 × Ydim 15199 — while the counts the pen sends, by
    /// NSEvent and by raw report alike, stay in the raw landscape frame (x
    /// was seen up to 13217, past that "width"). Taken as the extent and
    /// then turned again by the page's own quarter turn, they put every
    /// stroke in the wrong place (2026-10-02). The table, and what the pen
    /// is seen to reach, are the only two things that say how big the
    /// tablet is.
    static func known(productID: Int) -> TabletExtent? {
        switch productID {
        case 0x037A: return TabletExtent(width: 15200, height: 9500, countsPerMillimetre: 100)   // CTL-472
        case 0x037B: return TabletExtent(width: 21600, height: 13500, countsPerMillimetre: 100)  // CTL-672
        default: return nil
        }
    }

    /// For a tablet nobody has measured: the small One by Wacom's shape,
    /// which the widening below then grows to whatever the pen reaches.
    static let fallback = TabletExtent(width: 15200, height: 9500)

    /// The long side assumed for a tablet nobody has measured — the small
    /// One by Wacom's, in millimetres.
    static let assumedLongSide = 152.0

    /// WIDENED TO THE LARGEST VALUE EVER SEEN, so a wrong table entry can
    /// never clip the page: a count past the edge moves the edge — and not
    /// the scale, so the tablet is that much bigger in millimetres too.
    func widened(toInclude counts: CGPoint) -> TabletExtent {
        var wider = self
        wider.width = max(width, Double(counts.x))
        wider.height = max(height, Double(counts.y))
        return wider
    }

    /// The active area in millimetres, the way it shipped (landscape) —
    /// nil while nobody knows the counts' size.
    var millimetres: CGSize? {
        guard let perMillimetre = countsPerMillimetre, perMillimetre > 0 else { return nil }
        return CGSize(width: width / perMillimetre, height: height / perMillimetre)
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

    /// The page in millimetres — the tablet's active area, turned as the
    /// page is. A tablet nobody has measured is taken to be the small One
    /// by Wacom's length along its long side, at its own shape, so a paper
    /// is still ruled about as a hand writes.
    static func millimetres(of extent: TabletExtent, quarterTurns: Int) -> CGSize {
        let landscape = extent.millimetres
            ?? assumedMillimetres(for: CGSize(width: extent.width, height: extent.height))
        return turns(quarterTurns) % 2 == 0 ? landscape : CGSize(width: landscape.height, height: landscape.width)
    }

    /// Points to a millimetre: a point is 1/72 inch and an inch 25.4 mm. The
    /// screen's real pixel pitch is not asked — a point is how every other
    /// size in the window is measured.
    static let pointsPerMillimetre: CGFloat = 72 / 25.4

    /// A sheet the shape of `size` whose long side is the assumed one.
    static func assumedMillimetres(for size: CGSize) -> CGSize {
        let long = max(size.width, size.height)
        guard long > 0, size.width > 0, size.height > 0 else {
            return CGSize(width: TabletExtent.assumedLongSide, height: TabletExtent.assumedLongSide)
        }
        let scale = TabletExtent.assumedLongSide / Double(long)
        return CGSize(width: Double(size.width) * scale, height: Double(size.height) * scale)
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

/// The two switches on the pen's barrel (Sean's pen, the One by Wacom's
/// LP-190K, has both). Held as the nib goes down, either one makes the
/// stroke a selection; CLICKED IN THE AIR, each is a command
/// (`TabletPen.clicked`, `TabletScribe.command`).
enum PenSwitch: Hashable {
    /// The one nearer the nib: bit 0x02 of the raw report (`WacomPenPacket`;
    /// the Linux driver's BTN_STYLUS), and by the driver's events the right
    /// button (mask 0x2, `penLowerSide`).
    case lower
    /// The one further up the barrel: bit 0x04 (BTN_STYLUS2), and by the
    /// driver's events 0x4 in the mask (`penUpperSide`) — seen there on
    /// the nib's own events; whether a hover carries it has not been seen,
    /// so its click (redo) is sure only with the tablet captured.
    case upper
}

/// What one event says about the pen, or nothing for an event that is not
/// the pen's.
struct TabletReading: Equatable {
    enum Kind: Equatable {
        /// Where the nib is, in counts, and what is pressed. `switches` is
        /// nil when the reading CANNOT SAY what the switches are doing — a
        /// raw report that is not ready — which is neither a switch pressed
        /// nor one let go: read as "let go", one at the edge of the
        /// tablet's reach could make a click of a switch still held. A
        /// precaution; how the LP-190K's reports end there is unmeasured.
        case point(counts: CGPoint, tip: Bool, switches: Set<PenSwitch>?, pressure: Double, buttons: UInt)
        /// The pen came within reach of the tablet, or left it.
        case proximity(entering: Bool)
    }

    let kind: Kind
    let timestamp: TimeInterval
    /// True for the tablet's own word — an event of a tablet type, or a
    /// raw report (`WacomPenPacket.reading`) — and false for a mouse event
    /// carrying a tablet subtype. For the log, which is how a session says
    /// which route the pen took.
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
                         lower: buttons.contains(.penLowerSide), pressure: pressure, native: true)
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp,
             .rightMouseDown, .rightMouseDragged, .rightMouseUp, .mouseMoved:
            switch event.subtype {
            case .tabletProximity:
                return TabletReading(kind: .proximity(entering: event.isEnteringProximity),
                                     timestamp: event.timestamp, native: false)
            case .tabletPoint:
                let buttons = event.buttonMask
                var tip = buttons.contains(.penTip)
                var lower = buttons.contains(.penLowerSide)
                // The event's own type is the surest word on the button it
                // is about — the right button's up still carries 0x2
                // (measured) — and the mask speaks for the others.
                switch event.type {
                case .leftMouseDown, .leftMouseDragged: tip = true
                case .leftMouseUp: tip = false
                case .rightMouseDown, .rightMouseDragged: lower = true
                case .rightMouseUp: lower = false
                default: break
                }
                // A hover's pressure is not read at all (see PenSample);
                // the side switch's is made up (1.0, measured) and means
                // nothing. Only a nib on the tablet has one.
                let pressure = tip && event.type != .mouseMoved ? clamped(event.pressure) : 0
                return point(event, buttons: buttons, tip: tip, lower: lower, pressure: pressure, native: false)
            default:
                // A mouse, a trackpad: not the pen, and never touched.
                return nil
            }
        default:
            return nil
        }
    }

    /// BOTH SWITCHES BY THIS ROUTE, EACH BY ITS OWN WORD: the lower is the
    /// right button (mask 0x2, measured), the upper the mask's 0x4,
    /// `penUpperSide` — on Sean's tablet the nib's own events carried it, a
    /// down with mask 0x5 and an up with 0x4 (2026-10-02), so either switch
    /// held as the nib goes down is the box by this route as by the raw
    /// reports. No hover has been seen with it, so the upper's click —
    /// redo — is promised only with the tablet captured (`TabletPane.redoTip`).
    private static func point<Event: TabletEventFields>(_ event: Event, buttons: NSEvent.ButtonMask, tip: Bool,
                                                        lower: Bool, pressure: Double,
                                                        native: Bool) -> TabletReading {
        var switches: Set<PenSwitch> = []
        if lower { switches.insert(.lower) }
        if buttons.contains(.penUpperSide) { switches.insert(.upper) }
        return TabletReading(kind: .point(counts: CGPoint(x: event.absoluteX, y: event.absoluteY), tip: tip,
                                          switches: switches, pressure: pressure, buttons: UInt(buttons.rawValue)),
                             timestamp: event.timestamp, native: native)
    }

    private static func clamped(_ pressure: Float) -> Double {
        let value = Double(pressure)
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// One moment of the pen on the turned tablet — what `TabletScribe` makes
/// ink and boxes of on the page, or ink and a marquee in the note, and the
/// click of a side switch, which is neither.
struct TabletSample: Equatable {
    enum Phase: Equatable {
        /// Near the tablet, the nib up: the marker follows it.
        case hover
        /// The nib went down here.
        case down
        /// Still under way, here now: the nib down — or, for a box, a
        /// switch still held after the nib came up.
        case drag
        /// It ended here: the nib came up, and for a box the switch too.
        case up
        /// A SIDE SWITCH WAS CLICKED IN THE AIR, here — pressed and let go
        /// with the nib up the whole time. A command, not ink and not a
        /// box: once, as it is let go (`TabletPen.clicked`).
        case click(PenSwitch)
    }

    /// Where on the page, (u, v) in 0…1 from the top left, after the turn.
    let page: CGPoint
    /// 0…1 while the nib is on the tablet; 0 on a hover and at the up.
    let pressure: Double
    let phase: Phase
    /// The stroke is a SELECTION, not ink: the UPPER side switch was held as
    /// the nib went down (Sean, 2026-10-03: "the other button is hold to drag
    /// a selector box (as if clicking and dragging)"). The same on every
    /// sample of one down…up, so a stroke is one thing from start to finish.
    let sideSwitch: Bool
    /// False on the one sample that says the pen went out of reach — the
    /// marker goes, at the last place it was.
    let inProximity: Bool
    let timestamp: TimeInterval
    /// The stroke is an ERASER: the LOWER side switch was held as the nib
    /// went down (Sean, 2026-10-03: "press and hold to make it an eraser that
    /// deletes entire strokes"). Latched like `sideSwitch`, and never both.
    var eraser = false
    /// The switch pressed in the air and not yet let go, on a hover: what
    /// the pen WILL be if the nib goes down now — the lower an eraser, the
    /// upper a box — so the marker can say so before it does
    /// (`TabletHoverMarker.mode`).
    var holding: PenSwitch?
}

/// The pen's state from one reading to the next. A value, so a test can
/// walk it through any sequence.
struct TabletPen {
    private(set) var inProximity = false
    /// A stroke — ink, or a box — is under way: begun by the nib, and a box
    /// kept going by a switch still held after the nib came up.
    private(set) var engaged = false
    /// What the stroke under way is: latched at its down.
    private(set) var selecting = false
    /// What the stroke under way is, the other way: an ERASER, begun by the
    /// nib with the LOWER switch held. Latched at its down.
    private(set) var erasing = false
    /// A side switch was pressed under a stroke of INK and is still held
    /// after the nib came up: it makes no box of the next stroke until it
    /// has been let go.
    private(set) var switchHeldOver = false
    /// A side switch pressed IN THE AIR and not yet let go: the tap it
    /// will be if it is let go before anything else happens (`clicked`) —
    /// and when it was pressed, and the tap before it, for the double press
    /// that is the command.
    private(set) var armed: PenSwitch?
    private var armedAt: TimeInterval = 0
    private var lastTap: (pen: PenSwitch, at: TimeInterval)?
    /// A press let go within this is a TAP; held longer it is a hold, which
    /// is the eraser or the box and never half of a double press.
    static let tapLimit: TimeInterval = 0.4
    /// Two taps of the same switch, let go within this of each other, are
    /// ONE COMMAND — undo for the lower, redo for the upper (Sean, 2026-10-03:
    /// "a double press of that same button is undo", "double tap to redo").
    static let doubleWindow: TimeInterval = 0.6
    /// The switches as the last point had them, and nil while nothing has
    /// said — the pen out of reach, or the tablet not ready: a switch first
    /// seen already held was not pressed here.
    private var held: Set<PenSwitch>?
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
            // Coming or going, nothing here says what the switches are
            // doing: one held across it was neither pressed nor let go.
            armed = nil
            held = nil
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
            erasing = false
            switchHeldOver = false
            lastTap = nil
            inProximity = false
            if let last {
                out.append(sample(last, 0, .hover, false, reading.timestamp))
            }
            return out

        case .point(let counts, let tip, let switches, let pressure, _):
            guard fresh(reading.timestamp, in: &recentPoints) else { return [] }
            extent = extent.widened(toInclude: counts)
            let page = TabletMapping.page(counts, extent: extent, quarterTurns: quarterTurns)
            last = page
            inProximity = true
            let switchDown = switches?.isEmpty == false
            let upperDown = switches?.contains(.upper) == true
            let lowerDown = switches?.contains(.lower) == true
            if !switchDown { switchHeldOver = false }
            let click = clicked(switches, tip: tip, at: reading.timestamp)
            // A STROKE BEGINS WITH THE NIB, and what KIND of stroke is
            // latched at that down: A SWITCH HELD AS THE NIB GOES DOWN
            // MAKES IT THE BOX, either switch. The switch alone, in the air,
            // begins nothing — it used to begin the box there, and a click
            // of it could then be no command (Sean, 2026-10-02: "make the
            // wacom buttons undo and redo last drawing"). Once under way the
            // stroke's own kind says what keeps it going, as it always has:
            // INK ENDS WHERE THE NIB LIFTS — asked as "nib or switch", a
            // switch pressed under ink and held past the lift went on
            // drawing in the air at no pressure — and THE BOX GOES ON WHILE
            // THE NIB OR THE SWITCH IS DOWN, so a switch let go mid-drag is
            // still the box and so is the nib lifted with one held.
            let pressing = engaged && selecting ? tip || upperDown : tip
            let phase: TabletSample.Phase
            switch (engaged, pressing) {
            case (false, true):
                engaged = true
                // THE UPPER SWITCH IS THE BOX, THE LOWER THE ERASER
                // (Sean, 2026-10-03). Both at once is the box: the one
                // that is not an erasure.
                selecting = upperDown && !switchHeldOver
                erasing = !selecting && lowerDown && !switchHeldOver
                phase = .down
            case (true, true):
                phase = .drag
            case (true, false):
                engaged = false
                phase = .up
                // Still held as the ink ended: no box and no eraser until
                // pressed again. An eraser's own switch, held on after the
                // nib lifts, is the eraser still: the next touch erases.
                if !selecting, !erasing, switchDown { switchHeldOver = true }
            case (false, false):
                phase = click.map { .click($0) } ?? .hover
            }
            let out = sample(page, tip && phase != .up ? pressure : 0, phase, true, reading.timestamp)
            if phase == .up {
                selecting = false
                erasing = false
            }
            return [out]
        }
    }

    /// A DOUBLE PRESS OF A SIDE SWITCH IN THE AIR (Sean, 2026-10-02: "make
    /// the wacom buttons undo and redo last drawing", then 2026-10-03: "a
    /// double press of that same button is undo", "double tap to redo" —
    /// the single press having become the hold that makes the eraser and
    /// the box). A TAP is a press let go in the air within `tapLimit`, the
    /// nib up from the press to the letting go and the press itself seen;
    /// the SECOND tap of the same switch within `doubleWindow` of the first
    /// is the command, returned on the one reading that lets it go. One
    /// tap alone, a press held longer, a tap with the nib touching, and the
    /// other switch joining in are none of them anything, and leave none
    /// owed — and a hold is never half of a double press.
    ///
    /// Everything else is no click either: a switch pressed under a stroke,
    /// one already held as the pen comes into reach, and a reading that
    /// cannot say what the switches are doing.
    private mutating func clicked(_ switches: Set<PenSwitch>?, tip: Bool, at time: TimeInterval) -> PenSwitch? {
        let before = held
        held = switches
        guard let now = switches, !tip, !engaged else {
            armed = nil
            if tip { lastTap = nil }
            return nil
        }
        if let pressed = armed {
            if now == [pressed] { return nil }
            armed = nil
            guard now.isEmpty, time - armedAt <= Self.tapLimit else {
                lastTap = nil
                return nil
            }
            if let last = lastTap, last.pen == pressed, time - last.at <= Self.doubleWindow {
                lastTap = nil
                return pressed
            }
            lastTap = (pressed, time)
            return nil
        }
        if before?.isEmpty == true, now.count == 1 {
            armed = now.first
            armedAt = time
        }
        return nil
    }

    private func sample(_ page: CGPoint, _ pressure: Double, _ phase: TabletSample.Phase,
                        _ inProximity: Bool, _ timestamp: TimeInterval) -> TabletSample {
        TabletSample(page: page, pressure: pressure, phase: phase,
                     sideSwitch: phase == .hover ? false : selecting,
                     inProximity: inProximity, timestamp: timestamp,
                     eraser: phase == .hover ? false : erasing,
                     holding: phase == .hover ? armed : nil)
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
    /// from, and takes the switches' clicks from. Only while `isCapturing`.
    let samples = PassthroughSubject<TabletSample, Never>()

    /// The pen as last seen, for the hover marker; nil once it is out of
    /// reach. Published at the pen's own rate, so only the marker should
    /// watch it.
    @Published private(set) var pen: TabletSample?

    /// The tablet's area in counts — the raw sensor's, from the table,
    /// widened by the pen; never the driver's oriented measure
    /// (`TabletExtent.known`). The page's shape follows it.
    @Published var extent = TabletExtent.fallback
    /// How the tablet is held (`AppState.tabletQuarterTurns`).
    var quarterTurns = 1

    /// A tablet is the chosen input (`start`/`stop`).
    private(set) var isRunning = false
    /// How many pages are on screen, and how many notebooks — a note open
    /// under its drawing layer. Counts, not flags: two windows can each
    /// have one, and the first to go must not switch the pen off for the
    /// other.
    private var pagesShowing = 0
    private var notebooksShowing = 0 {
        didSet { if notebookIsShowing != (notebooksShowing > 0) { notebookIsShowing = notebooksShowing > 0 } }
    }
    /// A note is on screen under its layer — published, for the page set
    /// aside to say whether the pen is writing in one (`TabletPane`).
    @Published private(set) var notebookIsShowing = false

    /// Where the pen writes: its page, or the note (`AppState.tabletTarget`,
    /// handed in by `aim(at:)`). Published so the scribe can drop whatever
    /// was half-written for the target it leaves.
    @Published private(set) var target: TabletTarget = .page

    /// THE PEN BELONGS TO ITS TARGET only while a tablet is the input and
    /// that target is on screen — the page in Page mode, a note in Notebook
    /// mode, whichever else is or is not up. Then the local monitor
    /// SWALLOWS every pen event — a tap on the tablet must never click a
    /// button or move the caret under a pointer it happens to have left
    /// somewhere — and at every other time it hands every event back as it
    /// came, to a pen that is an ordinary pen again: the tablet itself is
    /// let go with the last of them (`targetShowingChanged`).
    var isCapturing: Bool { isRunning && targetIsShowing }

    /// RAW CAPTURE IS DELIVERING: when the first raw report of this capture
    /// came, nil while WriteMind does not hold the tablet or has heard
    /// nothing from it yet. While it is set the driver's events are ignored.
    private(set) var rawSince: TimeInterval?
    /// The driver went on posting pen events while WriteMind held the
    /// tablet: it still hears it, and the pointer may still move. Said once
    /// in the log, and in the pane (`driverStillPostsChanged`) until the
    /// tablet is picked again.
    private(set) var driverStillPosts = false {
        didSet { if driverStillPosts != oldValue { driverStillPostsChanged?(driverStillPosts) } }
    }
    var driverStillPostsChanged: ((Bool) -> Void)?
    private var seizedEventNoted = false

    private var state = TabletPen()
    private var local: Any?
    private var global: Any?
    private var seen: Set<String> = []
    private var widened = false

    /// WHO MAY SPEAK through `receive`: the real tablet always, the virtual
    /// one and a replay only while a developer has them switched on and no
    /// real tablet is plugged in (`TabletSourcePolicy`). Off, and the real
    /// device not connected, is a release user's flow: nothing but the real
    /// tablet is ever heard.
    var policy = TabletSourcePolicy()
    /// Writing the session down, while a developer records one
    /// (`PenRecorder`): everything `receive` lets in and the driver's
    /// events the funnel takes.
    var recorder: PenRecorder?
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
        seizedEventNoted = false
        driverStillPosts = false
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
        rawSince = nil
        driverStillPosts = false
        if pen != nil { pen = nil }
    }

    /// The target is on screen: a page in Page mode, a note in Notebook
    /// mode.
    var targetIsShowing: Bool {
        switch target {
        case .page: return pagesShowing > 0
        case .notebook: return notebooksShowing > 0
        }
    }
    /// Told when the target comes on screen (true) and when it goes
    /// (false) — the last page or note going, the pen sent to a target that
    /// is not up: the controller's cue to take the pen off the pointer, or
    /// to give it back (`TabletController.targetChanged`). Only when that
    /// CHANGES: from the page to the notebook with both up the tablet
    /// stays held, and serves either.
    var targetShowingChanged: ((Bool) -> Void)?

    /// Where the pen writes from now on.
    func aim(at target: TabletTarget) {
        guard target != self.target else { return }
        changingWhatShows { self.target = target }
    }

    /// A page came on screen, or went.
    func pageAppeared() { changingWhatShows { pagesShowing += 1 } }
    func pageDisappeared() { changingWhatShows { pagesShowing = max(pagesShowing - 1, 0) } }

    /// A note came on screen under its drawing layer, or went.
    func notebookAppeared() { changingWhatShows { notebooksShowing += 1 } }
    func notebookDisappeared() { changingWhatShows { notebooksShowing = max(notebooksShowing - 1, 0) } }

    /// The one way the counts and the target change: the marker goes with
    /// a target that is no longer up, and the controller hears only of a
    /// change.
    private func changingWhatShows(_ change: () -> Void) {
        let was = targetIsShowing
        change()
        let now = targetIsShowing
        if !now, pen != nil { pen = nil }
        if was != now { targetShowingChanged?(now) }
    }

    /// One event from either monitor. Returns what the local monitor hands
    /// on: nil for a pen event taken for the target, the event itself —
    /// unchanged, the same object — for everything else. The global
    /// route's answer is ignored; it can only watch.
    func handle(_ event: NSEvent, from route: Route) -> NSEvent? {
        guard let reading = TabletReading.reading(event) else { return event }
        noteFirst(event, reading, route)
        guard isCapturing else { return event }
        if route == .global, !appIsActive() { return event }
        if let rawSince {
            // The raw route has this stroke. The event is still the pen's,
            // and still swallowed — a tap must not click — but it draws
            // nothing.
            noteWhileSeized(event, at: reading.timestamp, from: route, rawSince: rawSince)
            return nil
        }
        recorder?.record(.reading(reading), at: reading.timestamp, from: .driver)
        feed(reading)
        return nil
    }

    /// THE ONE DOOR EVERY SOURCE ENTERS BY (Sean, 2026-10-03: "make sure i
    /// can develop wacom features without a device plugged in"): the real
    /// tablet's HID reports (`TabletController`), the virtual tablet's
    /// pad, a replayed recording — each says its events here, tagged with
    /// what it is, and what is said is the tablet's own word, a raw pen
    /// report, read by the same `WacomPenPacket`, fed to the same pen. A
    /// source the policy does not admit is not heard, and neither is
    /// anything while the target is not on screen; what is heard is
    /// recorded when a developer is recording, before it is read, so a
    /// recording is what a replay has to put back.
    ///
    /// A report that is not exactly a pen report is none of the pen's
    /// business here — the controller logs the first of them in hex.
    func receive(_ event: PenStreamEvent, at time: TimeInterval, from source: TabletSourceKind) {
        guard policy.admits(source), isCapturing else { return }
        switch event {
        case .report(let bytes):
            guard let packet = WacomPenPacket(bytes) else { return }
            recorder?.record(event, at: time, from: source)
            raw(packet.reading(at: time))
        case .reading(let reading):
            let stamped = TabletReading(kind: reading.kind, timestamp: time, native: reading.native)
            recorder?.record(.reading(stamped), at: time, from: source)
            raw(stamped)
        }
    }

    /// TWO LINES AT MOST: the first event of the driver's to arrive while
    /// the tablet is held, whatever it turns out to be, and the first that
    /// was made late enough to mean the driver is still posting.
    private func noteWhileSeized(_ event: NSEvent, at timestamp: TimeInterval, from route: Route,
                                 rawSince: TimeInterval) {
        let what = "type=\(event.type.rawValue) from the \(route.rawValue) monitor, made "
            + "\(String(format: "%+.2f", timestamp - rawSince)) s from the first raw report"
        if !seizedEventNoted {
            seizedEventNoted = true
            log("tablet: a pen event from the driver while seized — \(what); ignored")
        }
        if !driverStillPosts, Self.stillPosting(eventAt: timestamp, rawSince: rawSince) {
            log("tablet: driver still posts events while seized — \(what)")
            driverStillPosts = true
        }
    }

    /// How long after the first raw report an event of the driver's has to
    /// be MADE to count as the driver still posting: events it made before
    /// the tablet was taken are still on their way up the queue for a
    /// moment after.
    static let stragglers: TimeInterval = 0.5

    static func stillPosting(eventAt timestamp: TimeInterval, rawSince: TimeInterval) -> Bool {
        timestamp > rawSince + stragglers
    }

    /// One reading off the tablet itself, while WriteMind holds it
    /// (`TabletController`, from `WacomPenPacket.reading`) — through the
    /// same pen state, the same turn and the same stream as an event's.
    func raw(_ reading: TabletReading) {
        guard isCapturing else { return }
        if rawSince == nil {
            rawSince = reading.timestamp
            log("tablet: raw capture is delivering — the driver's events are ignored from here; "
                + Self.penAsTaken(reading))
        }
        feed(reading)
    }

    /// WHETHER THE PEN WAS DOWN AS THE TABLET WAS TAKEN, for the log, by
    /// the tablet's own first word of a capture — it comes within a
    /// hundredth of a second of the last one the driver heard. A pen tap on
    /// WriteMind's window is an ordinary click that brings it to the front,
    /// so the tablet can be taken with the nib (or the switch, the driver's
    /// right button) still down: the driver posted the button going down
    /// and, hearing nothing more, never posts it coming up. The ink is
    /// whole either way — the down came by the driver's event, the rest of
    /// the stroke and its lift by the raw reports — but what macOS makes of
    /// a button the driver left down has not been seen, and this is how a
    /// session says it happened.
    static func penAsTaken(_ first: TabletReading) -> String {
        guard case .point(_, let tip, let switches, _, _) = first.kind, tip || switches?.isEmpty == false else {
            return "its first report has nothing pressed"
        }
        return "its first report has the pen DOWN, so the driver saw it go down and will not see it lift"
    }

    /// WriteMind let go of the tablet: the driver has the pen again. A
    /// stroke under way ends here, as it does when the pen leaves — the
    /// driver's next event would otherwise carry on a line from wherever
    /// the nib had been.
    func rawEnded(at timestamp: TimeInterval) {
        guard rawSince != nil else { return }
        rawSince = nil
        feed(TabletReading(kind: .proximity(entering: false), timestamp: timestamp, native: true))
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
            if case .click(let clicked) = sample.phase { noteFirstClick(clicked) }
            pen = sample.inProximity ? sample : nil
            samples.send(sample)
        }
    }

    /// WHICH SWITCH A CLICK WAS, once each a pick. That 0x02 is the button
    /// nearer the nib is the Linux driver's word (BTN_STYLUS), never checked
    /// against Sean's own pen: if undo and redo come out on the wrong
    /// buttons, this line says which bit his finger pressed.
    private func noteFirstClick(_ clicked: PenSwitch) {
        let key = "click-\(clicked)"
        guard !seen.contains(key) else { return }
        seen.insert(key)
        log("tablet: first click of the pen's \(clicked) switch"
            + (rawSince == nil ? " (by the driver's events)" : " (off the tablet itself)"))
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
        case .point(_, let tip, let switches, _, let buttons):
            line += " buttons=0x\(String(buttons, radix: 16)) tip=\(tip) side=\(switches?.isEmpty == false)"
        case .proximity(let entering):
            line += " proximity=\(entering ? "in" : "out")"
        }
        log(line + " capturing=\(isCapturing)")
    }
}
