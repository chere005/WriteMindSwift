import Combine
import XCTest
@testable import WriteMind

// A TEST WRITES THE GESTURE, NOT THE PACKETS (Sean, 2026-10-03: "make sure i
// can develop wacom features without a device plugged in").
//
//     let rig = TabletRig()
//     rig.pen.hover(0.5, 0.5).down(0.4).move(0.6, 0.5).up()
//     rig.pen.hold(.lower) { rig.pen.down().move(0.5, 0.7).up() }
//     rig.pen.doublePress(.lower)
//     rig.pen.tap(.upper)
//
// The script drives the virtual tablet's own pen (`VirtualPen`) on a clock
// that never sleeps (`VirtualClock`): every call stamps a report a hundredth
// of a second after the last, `wait` and the taps move the clock, and what
// comes out goes through THE ONE DOOR (`TabletInput.receive`), the real
// packet parser, the real pen state machine, the real scribes — into the
// page and into the notebook. Coordinates are PAGE FRACTIONS (u, v), where
// the stroke is on the page as seen, whichever way the tablet is held; the
// `…Counts` forms say raw counts on the tablet.

/// A clock for the pen that never sleeps: time moves when a test says, and
/// whatever was waiting for it runs, in order, as it passes.
@MainActor
final class VirtualClock: PenClock {
    private final class Entry {
        let due: TimeInterval
        let order: Int
        let work: @MainActor () -> Void
        var cancelled = false
        init(due: TimeInterval, order: Int, work: @escaping @MainActor () -> Void) {
            self.due = due
            self.order = order
            self.work = work
        }
    }

    private(set) var now: TimeInterval
    private var queue: [Entry] = []
    private var issued = 0

    /// Far from zero, as the system's uptime is: a stamp of 0 is no stamp.
    init(start: TimeInterval = 1000) { now = start }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> AnyCancellable {
        issued += 1
        let entry = Entry(due: now + max(delay, 0), order: issued, work: work)
        queue.append(entry)
        return AnyCancellable { entry.cancelled = true }
    }

    /// Let `seconds` pass: everything that falls due in them runs, earliest
    /// first, and what it asks for in turn runs too if it falls due.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = queue.filter({ !$0.cancelled && $0.due <= target })
            .min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            now = max(now, next.due)
            queue.removeAll { $0 === next }
            next.work()
        }
        now = target
        queue.removeAll { $0.cancelled }
    }

    /// Whatever has been asked for and not yet run.
    var pending: Int { queue.filter { !$0.cancelled }.count }
}

/// The gesture, as a chain.
@MainActor
final class TabletScript {
    let pen: VirtualPen
    let clock: VirtualClock
    /// How long each step takes: the tablet reports about 120 times a second.
    var rate: TimeInterval = 0.008
    /// The tablet's field and how it is held — what a page fraction means.
    var geometry: () -> (extent: TabletExtent, quarterTurns: Int)

    init(pen: VirtualPen, clock: VirtualClock,
         geometry: @escaping () -> (extent: TabletExtent, quarterTurns: Int)) {
        self.pen = pen
        self.clock = clock
        self.geometry = geometry
    }

    // MARK: Where

    /// A page fraction as counts on the tablet.
    func counts(_ u: Double, _ v: Double) -> CGPoint {
        let (extent, turns) = geometry()
        return TabletMapping.counts(forPage: CGPoint(x: u, y: v), extent: extent, quarterTurns: turns)
    }

    /// Where the pen is on the page, as fractions — nil while it is away.
    var position: CGPoint? {
        guard pen.isNear else { return nil }
        let (extent, turns) = geometry()
        return TabletMapping.page(pen.frame.counts, extent: extent, quarterTurns: turns)
    }

    // MARK: The nib

    /// The pen is at (u, v), the nib up: it comes near if it was away.
    @discardableResult func hover(_ u: Double, _ v: Double) -> TabletScript {
        step()
        pen.move(to: counts(u, v))
        return self
    }

    /// The same, in raw counts on the tablet.
    @discardableResult func hoverCounts(_ x: Double, _ y: Double) -> TabletScript {
        step()
        pen.move(to: CGPoint(x: x, y: y))
        return self
    }

    /// The nib touches where the pen is, as hard as `pressure` — or as the
    /// last pressure set.
    @discardableResult func down(_ pressure: Double? = nil) -> TabletScript {
        step()
        pen.touch(pressure: pressure)
        return self
    }

    /// The pen moves to (u, v): a hover with the nib up, a drag with it down
    /// — pressing `pressure` there, when it is given, in the same report.
    @discardableResult func move(_ u: Double, _ v: Double, pressure: Double? = nil) -> TabletScript {
        step()
        pen.move(to: counts(u, v), pressure: pressure)
        return self
    }

    @discardableResult func moveCounts(_ x: Double, _ y: Double) -> TabletScript {
        step()
        pen.move(to: CGPoint(x: x, y: y))
        return self
    }

    /// The nib comes up.
    @discardableResult func up() -> TabletScript {
        step()
        pen.lift()
        return self
    }

    /// The pen goes out of reach of the tablet.
    @discardableResult func leave() -> TabletScript {
        step()
        pen.leave()
        return self
    }

    /// The nib presses differently from now on — and, with it down, now.
    @discardableResult func pressure(_ value: Double) -> TabletScript {
        step()
        pen.setPressure(value)
        return self
    }

    // MARK: The switches

    @discardableResult func press(_ which: PenSwitch) -> TabletScript {
        step()
        pen.set(which, held: true)
        return self
    }

    @discardableResult func release(_ which: PenSwitch) -> TabletScript {
        step()
        pen.set(which, held: false)
        return self
    }

    /// A switch held for the length of `body` — pressed in the air first, as
    /// a hand does it, and let go after.
    @discardableResult func hold(_ which: PenSwitch, _ body: () -> Void) -> TabletScript {
        press(which)
        body()
        return release(which)
    }

    /// A TAP: pressed and let go within the pen's tap limit, the nib staying
    /// up.
    @discardableResult func tap(_ which: PenSwitch) -> TabletScript {
        step()
        pen.tap(which)
        clock.advance(by: VirtualPen.tapLength + rate)
        return self
    }

    /// A DOUBLE PRESS: two taps of the same switch, close together — undo
    /// for the lower, redo for the upper.
    @discardableResult func doublePress(_ which: PenSwitch) -> TabletScript {
        step()
        pen.doublePress(which)
        clock.advance(by: VirtualPen.doublePressLength + rate)
        return self
    }

    // MARK: Time

    /// Let `seconds` of the clock pass with the pen as it is.
    @discardableResult func wait(_ seconds: TimeInterval) -> TabletScript {
        clock.advance(by: seconds)
        return self
    }

    // MARK: Whole gestures

    /// A stroke: hover at the first point, nib down, a move to each of the
    /// others, nib up. `pressure` is one pressure, or the ramp from the
    /// first to the last when `to` is given.
    @discardableResult func stroke(_ points: [(Double, Double)], pressure: Double = 0.5,
                                   to last: Double? = nil) -> TabletScript {
        guard let first = points.first else { return self }
        hover(first.0, first.1)
        down(pressure)
        for (index, point) in points.dropFirst().enumerated() {
            var press: Double?
            if let last {
                let along = Double(index + 1) / Double(max(points.count - 1, 1))
                press = pressure + (last - pressure) * along
            }
            move(point.0, point.1, pressure: press)
        }
        return up()
    }

    /// A straight line from where the pen is to (u, v) in `steps` moves,
    /// nib as it is.
    @discardableResult func line(to u: Double, _ v: Double, steps: Int = 8) -> TabletScript {
        let from = position ?? CGPoint(x: u, y: v)
        for index in 1...max(steps, 1) {
            let along = Double(index) / Double(max(steps, 1))
            move(from.x + (u - from.x) * along, from.y + (v - from.y) * along)
        }
        return self
    }

    /// Time moves on a step before anything is said, so no two reports ever
    /// share a stamp.
    private func step() { clock.advance(by: rate) }
}

/// The pen's state machine ALONE, fed by a script with exact frames — for a
/// test of `TabletPen` itself, where a pressure of 0.3 should come out 0.3.
/// (Through the funnel it is the report's own quantised 614/2047.)
@MainActor
final class PenBench {
    let clock = VirtualClock()
    let pen: VirtualPen
    let script: TabletScript
    private(set) var state = TabletPen()
    var extent = TabletExtent(width: 15200, height: 9500)
    var quarterTurns = 1
    /// Every sample, in order.
    private(set) var samples: [TabletSample] = []

    init(quarterTurns: Int = 1) {
        self.quarterTurns = quarterTurns
        pen = VirtualPen(clock: clock)
        script = TabletScript(pen: pen, clock: clock, geometry: { (TabletExtent(width: 15200, height: 9500), quarterTurns) })
        pen.onFrame = { [unowned self] frame, time in
            var extent = self.extent
            self.samples += self.state.consume(frame.reading(at: time), extent: &extent, quarterTurns: self.quarterTurns)
            self.extent = extent
        }
    }

    var phases: [TabletSample.Phase] { samples.map(\.phase) }

    /// The samples made since `mark`, and the mark to ask from next time.
    func since(_ mark: Int) -> ArraySlice<TabletSample> { samples.dropFirst(mark) }
    var mark: Int { samples.count }
}

/// THE WHOLE PATH, WITH NO TABLET: the virtual pen through the one door
/// (`TabletInput.receive`) into the page, and — when `notes` is asked for —
/// into a real note store with a stand-in for the drawing layer's part (the
/// eraser's deletions and the marquee's pick, by the layer's own rules).
@MainActor
final class TabletRig {
    let clock = VirtualClock()
    let input = TabletInput()
    let page = TabletPage(url: nil)
    let notebook = NotebookScribe()
    let scribe: TabletScribe
    let virtual: VirtualPen
    let pen: TabletScript
    /// Every sample the funnel published, in order.
    private(set) var samples: [TabletSample] = []
    /// The notes, when the rig has them.
    let notes: RigNotes?

    private var watching: AnyCancellable?

    init(target: TabletTarget = .page, quarterTurns: Int = 1,
         extent: TabletExtent = TabletExtent(width: 15200, height: 9500, countsPerMillimetre: 100),
         notes withNotes: Bool = false, developerOn: Bool = true) {
        input.extent = extent
        input.quarterTurns = quarterTurns
        input.policy = TabletSourcePolicy(developerOn: developerOn, realConnected: false)
        input.start()
        input.aim(at: target)
        virtual = VirtualPen(clock: clock)
        input.attach(virtual)
        scribe = TabletScribe(page: page, input: input, notebook: notebook)
        pen = TabletScript(pen: virtual, clock: clock, geometry: { [unowned input] in (input.extent, input.quarterTurns) })
        notes = withNotes ? RigNotes(notebook: notebook, input: input, turns: quarterTurns, extent: extent) : nil
        watching = input.samples.sink { [unowned self] in samples.append($0) }
        // The page, and the note, are on screen: the pen has somewhere to
        // write whichever way it is aimed.
        input.pageAppeared()
        if withNotes || target == .notebook { input.notebookAppeared() }
    }

    deinit {
        watching?.cancel()
    }

    var phases: [TabletSample.Phase] { samples.map(\.phase) }

    /// Play a recording through the one door on this rig's clock, to the end,
    /// at `speed` times the pace it happened at (`PenReplay.asFastAsPossible`
    /// for no waiting), and hand the replay back. The recording's own field
    /// is the tablet's, as it is when the app replays one.
    @discardableResult
    func play(_ recording: PenRecording, speed: Double = 1) -> PenReplay {
        if let extent = recording.header.extent { input.extent = extent }
        let replay = PenReplay(recording, clock: clock, base: clock.now + 1)
        input.attach(replay)
        replay.play(speed: speed)
        clock.advance(by: speed.isInfinite ? 0.001 : recording.duration / speed + 1)
        return replay
    }
}

/// A note store with the notebook's layer's part played by the test: the
/// pen's strokes land through `NotebookScribe.writes` as the notes pane
/// wires it, and what the eraser touches and the marquee picks is decided by
/// the layer's own rules (`DrawingCanvas.strokesTouched`, `marqueePicked`).
@MainActor
final class RigNotes {
    let dir: URL
    let store: NoteStore
    let state: AppState
    /// What the layer holds picked — the marquee's last pick.
    private(set) var selection: Set<UUID> = []
    private var erasing = false
    private var subscriptions: [AnyCancellable] = []
    let pane: CGSize
    private let notebook: NotebookScribe
    private let turns: Int
    private let extent: TabletExtent

    init(notebook: NotebookScribe, input: TabletInput, turns: Int, extent: TabletExtent,
         pane: CGSize = CGSize(width: 800, height: 600), scale: NotebookScale = .fit) {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-rig-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data("# Letters\n\nDear Sean,\n".utf8).write(to: dir.appending(path: "Letters.md"))
        store = NoteStore(directory: dir)
        state = AppState(defaults: UserDefaults(suiteName: "WriteMindTests-\(UUID().uuidString)")!)
        self.pane = pane
        self.notebook = notebook
        self.turns = turns
        self.extent = extent
        place(scale: scale)
        notebook.writes(into: store, telling: state)
        subscriptions.append(notebook.erases.sink { [unowned self] in erase($0) })
        subscriptions.append(notebook.picks.sink { [unowned self] rect in
            selection = DrawingCanvas.marqueePicked(rect, in: store.drawing, size: self.pane, adding: nil)
        })
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Where the notes are, as the notes pane tells the scribe: the pane, the
    /// tablet's shape as it is held, Fit or Real size.
    func place(scale: NotebookScale) {
        notebook.place = NotebookPlace(pane: pane, scroll: 0,
                                       aspect: TabletMapping.aspect(of: extent, quarterTurns: turns),
                                       note: store.selectedNote?.id, quarterTurns: turns, scale: scale,
                                       millimetres: TabletMapping.millimetres(of: extent, quarterTurns: turns))
    }

    /// The layer's part in the eraser: a stroke the path touches goes whole,
    /// and the whole erasure is one step back, taken at the first deletion.
    private func erase(_ erase: NotebookErase) {
        switch erase {
        case .end:
            erasing = false
        case .path(let a, let b):
            let gone = DrawingCanvas.strokesTouched(by: a, to: b, in: store.drawing, size: pane)
            guard !gone.isEmpty else { return }
            if !erasing {
                store.beginDrawingChange()
                erasing = true
            }
            store.drawing = store.drawing.removing(gone)
            selection.subtract(gone)
        }
    }

    /// The strokes on the note's floating layer.
    var strokes: [Stroke] {
        store.drawing.items.compactMap { item in
            if case .stroke(let stroke) = item { return stroke }
            return nil
        }
    }
}
