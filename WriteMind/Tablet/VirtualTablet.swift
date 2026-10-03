import Combine
import Foundation

// THE VIRTUAL TABLET (Sean, 2026-10-03: "make sure i can develop wacom
// features without a device plugged in"). A pad on screen stands for the
// tablet's field and the mouse or trackpad stands for the pen: moving over
// it is the pen hovering, pressing is the nib going down, a slider is how
// hard, and each side switch is a button that can be held, tapped or
// double-pressed. What it says is what the real tablet says — raw pen
// reports, ten bytes each (`PenFrame.report`) — through the one door
// (`TabletInput.receive`), so every pen mode can be tried by hand: ink, the
// eraser on the lower switch held, the box on the upper held, undo on a
// double press of the lower, redo on a double press of the upper, the
// notebook as the target, Fit and Real size.
//
// It is OFF unless a developer switched it on, and the real tablet always
// wins (`TabletSourcePolicy`); nothing here is in a release user's flow.
//
// `VirtualPen` is the pen — a state, a clock and the reports it makes, with
// no view in it — and the test script (`TabletScript`) drives the very same
// one, so a test of a gesture and a hand on the pad are one code path.
// `VirtualTablet` is the pad's model: the pad's points turned into counts,
// the slider, the latched switches, and the keys.

/// The pen: where it is, what is pressed, and the reports that say so.
@MainActor
final class VirtualPen: TabletSource {
    let kind = TabletSourceKind.virtual
    var door: ((PenStreamEvent, TimeInterval) -> Void)?
    /// Every moment as the exact frame, beside the report that says it — for
    /// a test that walks `TabletPen` alone and wants a pressure of 0.3 to be
    /// 0.3 and not 614/2047.
    var onFrame: ((PenFrame, TimeInterval) -> Void)?

    let clock: PenClock

    /// How long a TAP holds a switch down, and how long between the two
    /// taps of a double press: both inside the pen's own limits
    /// (`TabletPen.tapLimit`, `doubleWindow`), as a finger's would be.
    static let tapLength: TimeInterval = 0.08
    static let doubleGap: TimeInterval = 0.12

    /// What the nib presses with when it goes down.
    private(set) var pressure = 0.5
    /// The pen as the tablet would report it now.
    private(set) var frame = PenFrame.away(at: CGPoint(x: 7600, y: 4750))
    /// Where it was last, in counts: where a switch pressed with the pen
    /// away brings it back.
    private(set) var lastCounts: CGPoint?

    private var latched: Set<PenSwitch> = []
    private var keyed: Set<PenSwitch> = []
    private var tapping: Set<PenSwitch> = []
    private var timers: [AnyCancellable] = []
    private var lastStamp = -TimeInterval.infinity

    init(clock: PenClock? = nil) {
        self.clock = clock ?? LivePenClock.shared
    }

    var isNear: Bool { frame.inRange }
    var isDown: Bool { frame.inRange && frame.tip }
    /// Every switch that counts as held: latched, held by a key, or in the
    /// middle of a tap.
    var switches: Set<PenSwitch> { latched.union(keyed).union(tapping) }
    var latchedSwitches: Set<PenSwitch> { latched }

    // MARK: - Moving

    /// The pen is at `counts`: coming near if it was away, hovering, or — with
    /// the nib down — dragging. `pressure` presses differently from this
    /// report on, with no report of its own for it.
    func move(to counts: CGPoint, pressure: Double? = nil) {
        if let pressure { self.pressure = Self.clamped(pressure) }
        if !frame.inRange { send(.arriving(at: counts)) }
        lastCounts = counts
        frame.inRange = true
        frame.hasPosition = true
        frame.ready = true
        frame.counts = counts
        frame.switches = switches
        frame.pressure = frame.tip ? self.pressure : 0
        frame.distance = frame.tip ? 0 : PenFrame().distance
        send(frame)
    }

    /// The nib goes down where the pen is, as hard as `pressure` (or the
    /// slider's, when none is given).
    func touch(pressure: Double? = nil) {
        if let pressure { self.pressure = Self.clamped(pressure) }
        if !frame.inRange { move(to: lastCounts ?? PenFrame().counts) }
        frame.tip = true
        frame.pressure = self.pressure
        frame.distance = 0
        frame.switches = switches
        send(frame)
    }

    /// The nib comes up.
    func lift() {
        guard frame.inRange, frame.tip else { frame.tip = false; return }
        frame.tip = false
        frame.pressure = 0
        frame.distance = PenFrame().distance
        frame.switches = switches
        send(frame)
    }

    /// The pen goes out of reach, where it was. A tap not yet finished is
    /// given up.
    func leave() {
        timers.forEach { $0.cancel() }
        timers = []
        tapping = []
        guard frame.inRange else { return }
        let at = frame.counts
        frame = .away(at: at)
        send(frame)
    }

    /// How hard the nib presses from now on — and, with it down, now.
    func setPressure(_ value: Double) {
        pressure = Self.clamped(value)
        guard frame.inRange, frame.tip else { return }
        frame.pressure = pressure
        send(frame)
    }

    // MARK: - The side switches

    /// How a switch came to be held: latched on a button, or held by a key
    /// (and let go with it).
    enum Hold { case latch, key }

    /// A switch pressed or let go. With the pen away the state is kept and
    /// nothing is sent — a real pen out of reach reports nothing — and the
    /// first report when it comes near says so.
    func set(_ which: PenSwitch, held: Bool, by hold: Hold = .latch) {
        let before = switches
        switch hold {
        case .latch: if held { latched.insert(which) } else { latched.remove(which) }
        case .key: if held { keyed.insert(which) } else { keyed.remove(which) }
        }
        // Only a CHANGE is a report: the pad hears the modifier keys at
        // every pointer move, and a held key is not a new press.
        if switches != before { resend() } else { frame.switches = switches }
    }

    /// A TAP: pressed, and let go `tapLength` later — on the clock, so a
    /// test waits for it without sleeping. A pen that is away is brought
    /// near first: a switch cannot be pressed in the air if there is no air.
    func tap(_ which: PenSwitch) {
        bringNear()
        tapping.insert(which)
        resend()
        timers.append(clock.after(Self.tapLength) { [weak self] in
            guard let self else { return }
            self.tapping.remove(which)
            self.resend()
        })
    }

    /// TWO TAPS of the same switch, `doubleGap` apart: undo for the lower,
    /// redo for the upper.
    func doublePress(_ which: PenSwitch) {
        tap(which)
        timers.append(clock.after(Self.tapLength + Self.doubleGap) { [weak self] in self?.tap(which) })
    }

    /// How long a double press takes, from the first press to the second's
    /// letting go.
    static var doublePressLength: TimeInterval { tapLength + doubleGap + tapLength }

    // MARK: - Sending

    private func bringNear() {
        guard !frame.inRange else { return }
        move(to: lastCounts ?? PenFrame().counts)
    }

    /// The switches changed: say so, if the pen is within reach.
    private func resend() {
        frame.switches = switches
        guard frame.inRange else { return }
        send(frame)
    }

    private func send(_ frame: PenFrame) {
        // STRICTLY INCREASING STAMPS: two reports with one stamp are, to the
        // pen's state machine, one report seen by two routes.
        let stamp = max(clock.now, lastStamp + 0.0005)
        lastStamp = stamp
        onFrame?(frame, stamp)
        emit(.report(frame.report), at: stamp)
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

/// THE PAD'S MODEL: a pad drawn at the tablet's turned shape, whose points
/// are turned back into the counts the real tablet would have reported at
/// the same place on the desk, and the controls beside it — the slider, the
/// switches' buttons, the keys.
@MainActor
final class VirtualTablet: ObservableObject, TabletSource {
    let kind = TabletSourceKind.virtual
    var door: ((PenStreamEvent, TimeInterval) -> Void)? {
        get { pen.door }
        set { pen.door = newValue }
    }

    let pen: VirtualPen

    /// The tablet's field and how it is held, asked at every point: they
    /// change under the pad (a turn, the extent widening) and the pad has to
    /// follow (`TabletController` hands in the funnel's own).
    var geometry: () -> (extent: TabletExtent, quarterTurns: Int) = { (TabletExtent.fallback, 1) }

    /// How hard the nib presses: the slider's.
    @Published var pressure = 0.5 {
        didSet { pen.setPressure(pressure) }
    }
    /// The switches held on by their buttons.
    @Published private(set) var lowerHeld = false
    @Published private(set) var upperHeld = false
    /// The pen is near the pad, and its nib is down.
    @Published private(set) var isNear = false
    @Published private(set) var isDown = false

    /// Nudging the pressure by a key or the scroll wheel.
    static let pressureStep = 0.05

    init(clock: PenClock? = nil) {
        pen = VirtualPen(clock: clock)
    }

    // MARK: - The pad

    /// The pad's point (u, v), fractions of the pad from its top left — the
    /// pad is drawn at the turned page's shape — as the counts on the
    /// tablet.
    func counts(atPad point: CGPoint) -> CGPoint {
        let (extent, turns) = geometry()
        return TabletMapping.counts(forPage: point, extent: extent, quarterTurns: turns)
    }

    /// Where the pen is on the pad now, as fractions of it; nil while it is
    /// away.
    var padPoint: CGPoint? {
        guard pen.isNear else { return nil }
        let (extent, turns) = geometry()
        return TabletMapping.page(pen.frame.counts, extent: extent, quarterTurns: turns)
    }

    /// The pointer moved over the pad: the pen hovers there, or with the nib
    /// down drags.
    func padMove(to point: CGPoint) {
        place(at: counts(atPad: point))
        refresh()
    }

    /// The pointer went down on the pad: the nib touches.
    func padDown(at point: CGPoint) {
        place(at: counts(atPad: point))
        pen.touch()
        refresh()
    }

    /// The pointer came up: the nib lifts, and the pen stays where it was,
    /// hovering — the pointer going to a switch's button is not the pen
    /// leaving.
    func padUp(at point: CGPoint? = nil) {
        if let point { place(at: counts(atPad: point)) }
        pen.lift()
        refresh()
    }

    /// The pen to `counts` — unless it is there already and near: the
    /// pointer pressed or let go where it stopped is no new place, and a
    /// duplicate point in the ink would be the pad's doing, not the pen's.
    private func place(at counts: CGPoint) {
        guard !pen.isNear || pen.frame.counts != counts else { return }
        pen.move(to: counts)
    }

    /// Take the pen away: out of reach of the tablet.
    func penAway() {
        pen.leave()
        refresh()
    }

    // MARK: - The switches

    /// The ERASER TOGGLE: the lower switch held on — which is what the
    /// eraser is on the real pen (the CTL-472's pen has no eraser end; its
    /// lower side switch held as the nib goes down erases whole strokes).
    var eraser: Bool {
        get { lowerHeld }
        set { hold(.lower, newValue) }
    }

    /// A switch latched on or off by its button.
    func hold(_ which: PenSwitch, _ held: Bool) {
        switch which {
        case .lower: lowerHeld = held
        case .upper: upperHeld = held
        }
        pen.set(which, held: held)
        refresh()
    }

    func tap(_ which: PenSwitch) {
        pen.tap(which)
        refresh()
    }

    func doublePress(_ which: PenSwitch) {
        pen.doublePress(which)
        refresh()
    }

    /// The modifier keys as the pad hears them: ⇧ holds the lower switch and
    /// ⌥ the upper, for as long as they are down — a way to hold a switch
    /// WHILE DRAWING, when the pointer's one button is the nib.
    func keysHeld(lower: Bool, upper: Bool) {
        pen.set(.lower, held: lower, by: .key)
        pen.set(.upper, held: upper, by: .key)
        refresh()
    }

    // MARK: - Pressure

    func nudgePressure(by delta: Double) {
        pressure = min(max(pressure + delta, 0), 1)
    }

    /// The number keys: 1 is a tenth of the way up … 9 nine tenths, 0 full.
    func setPressure(digit: Int) {
        guard (0...9).contains(digit) else { return }
        pressure = digit == 0 ? 1 : Double(digit) / 10
    }

    private func refresh() {
        if isNear != pen.isNear { isNear = pen.isNear }
        if isDown != pen.isDown { isDown = pen.isDown }
        objectWillChange.send()
    }
}
