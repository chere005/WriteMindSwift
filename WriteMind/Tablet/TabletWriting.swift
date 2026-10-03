import AppKit
import Combine

// FROM THE PEN'S SAMPLES TO THE PAGE: the nib down is ink, the nib down
// with the UPPER side switch held is a box, with the LOWER an eraser that
// deletes whole strokes, and a side switch pressed twice in the air is undo
// (lower) or redo (upper) (`TabletScribe.command`). The rule is `TabletWriting`, a
// value tested sample by sample; `TabletScribe` is its shell — it takes the
// funnel's stream (`TabletInput.samples`, page fractions after the turn),
// keeps the stroke being written where its own layer can redraw it at the
// pen's rate, and hands a finished stroke to the page.
//
// It is the ONE consumer of the samples, and the target is chosen HERE:
// "Write on: Page | Notebook" — the page's own writing below, or straight
// into the note through `NotebookScribe` (TabletNotebook.swift). The funnel
// and the page stay as they are either way.

/// What the pen writes with on the page — the page's own pen, off the bar
/// in its corner (`AppState.pageInkTool`, `pageInkHex`, `pageInkWidth`).
/// A stroke takes it as it stands when the nib goes down and keeps it.
struct TabletInk: Equatable {
    var colorHex: String
    /// In the page's own points (`TabletPage.longSide`).
    var width: Double
    var tool: InkTool = .pen

    /// The pen menu's width on a page drawn `viewScale` view points to a
    /// page point. A 3-point pen WRITES 3 POINTS WHERE IT IS SEEN WRITING —
    /// on the page as big as the pane shows it — and from then on the ink
    /// is part of the picture of the page, and grows and shrinks with it.
    static func width(penWidth: Double, viewScale: CGFloat) -> Double {
        guard viewScale.isFinite, viewScale > 0 else { return penWidth }
        return penWidth / Double(viewScale)
    }
}

/// The rule, sample by sample.
struct TabletWriting {
    enum Outcome: Equatable {
        case none
        /// The nib went down: a stroke has begun.
        case began
        /// The stroke being written has another point.
        case grew
        /// The nib came up: this stroke is finished.
        case finished(Stroke)
        /// The box — begun by the nib with a side switch held — being
        /// dragged: so far, page fractions.
        case boxing(CGRect)
        /// It came up: the box it drew.
        case boxed(CGRect)
        /// It came up where it went down: a tap with the switch held, the
        /// box's own click, which puts a box away. (A switch clicked IN THE
        /// AIR is another thing, a command, and never comes here —
        /// `TabletScribe.command`.)
        case clicked
        /// The ERASER — begun by the nib with the lower switch held — went
        /// from `from` to `to` on the page (one point at the start): what it
        /// touched goes, whole strokes.
        case erasing(from: CGPoint, to: CGPoint)
        /// It came up: the erasure is one step.
        case erased
    }

    /// How far the nib must move with the switch held, in page fractions,
    /// before it is a box and not a click — a hair more than a millimetre
    /// on the small One by Wacom, about the four points a mouse is allowed.
    static let clickSlop: CGFloat = 0.01

    private(set) var stroke: Stroke?
    private var boxStart: CGPoint?
    private var boxMoved = false
    private var eraseLast: CGPoint?

    mutating func consume(_ sample: TabletSample, ink: TabletInk) -> Outcome {
        switch sample.phase {
        case .hover, .click:
            return .none
        case .down:
            if sample.eraser {
                stroke = nil
                boxStart = nil
                eraseLast = sample.page
                return .erasing(from: sample.page, to: sample.page)
            }
            if sample.sideSwitch {
                stroke = nil
                boxStart = sample.page
                boxMoved = false
                return .none
            }
            boxStart = nil
            // THE PEN'S OWN SAMPLE: ink from the first point, a pressure
            // per point, exactly as the notebook's pen makes it
            // (`PenSampleReader`, `Stroke.starting`).
            stroke = Stroke.starting(at: sample.page, colorHex: ink.colorHex, width: ink.width,
                                     pen: .pen(pressure: sample.pressure), tool: ink.tool)
            return .began
        case .drag:
            if let last = eraseLast {
                eraseLast = sample.page
                return .erasing(from: last, to: sample.page)
            }
            if let start = boxStart {
                if !boxMoved {
                    boxMoved = max(abs(sample.page.x - start.x), abs(sample.page.y - start.y)) >= Self.clickSlop
                }
                return boxMoved ? .boxing(Self.box(from: start, to: sample.page)) : .none
            }
            guard stroke != nil else { return .none }
            stroke?.append(sample.page, pen: .pen(pressure: sample.pressure))
            return .grew
        case .up:
            if eraseLast != nil {
                eraseLast = nil
                return .erased
            }
            if let start = boxStart {
                boxStart = nil
                let moved = boxMoved
                    || max(abs(sample.page.x - start.x), abs(sample.page.y - start.y)) >= Self.clickSlop
                return moved ? .boxed(Self.box(from: start, to: sample.page)) : .clicked
            }
            // The lift itself is not a point: it reports no pressure, and a
            // last point at none would pinch every stroke's end — the
            // notebook's pen does not take its mouse-up either. A tap is
            // therefore one point, which the ink draws as a dot.
            guard let finished = stroke else { return .none }
            stroke = nil
            return .finished(finished)
        }
    }

    /// The sheet turned under a stroke or a box being drawn: what is
    /// already down turns with it, as the page's strokes do
    /// (`TabletPage.turned`), so the rest of it — read the new way round
    /// by the funnel — carries on from where the nib is ON THE TABLET.
    mutating func turn(by quarterTurns: Int) {
        guard TabletMapping.turns(quarterTurns) != 0 else { return }
        if let under = stroke { stroke = TabletPage.turned(under, by: quarterTurns) }
        if let start = boxStart { boxStart = TabletPage.turned(start, by: quarterTurns) }
        if let last = eraseLast { eraseLast = TabletPage.turned(last, by: quarterTurns) }
    }

    /// A box between two page points, on the page.
    static func box(from a: CGPoint, to b: CGPoint) -> CGRect {
        CanvasGeometry.rect(from: a, to: b).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

/// The selection box on the page, in page fractions — its own object so
/// that only the box's layer redraws while it is dragged.
@MainActor
final class TabletBox: ObservableObject {
    @Published var rect: CGRect?

    /// A box drawn on the page view (view points, `size` the page's frame)
    /// as page fractions, cut to the page; nil when it misses it.
    nonisolated static func fraction(_ rect: CGRect, in size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let box = CGRect(x: rect.minX / size.width, y: rect.minY / size.height,
                         width: rect.width / size.width, height: rect.height / size.height)
            .standardized
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return box.isNull ? nil : box
    }

    /// And back, for drawing.
    nonisolated static func points(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
               width: rect.width * size.width, height: rect.height * size.height)
    }

    /// ESC PUTS THE BOX AWAY, as a click off it does — and is taken only
    /// when there was a box, so at every other time Esc is still the
    /// notebook's (it puts the pen down). And only an Esc meant for the
    /// page: one for ANOTHER window — a popover, a sheet — or for a field
    /// being typed in is theirs to call off (`elsewhere`), box or no box.
    nonisolated static func putsAway(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, hasBox: Bool,
                                     elsewhere: Bool) -> Bool {
        hasBox && !elsewhere && keyCode == 53
            && modifiers.intersection([.command, .control, .option, .shift]).isEmpty
    }

    /// Who asks the box about an Esc. While a drawing layer watches keys,
    /// the box is a step in ITS chain, at the place that chain chose for it
    /// (`DrawingCanvas.handleKey`); the page's own monitor answers only when
    /// no layer is up — no note open, or the notes put away.
    nonisolated static func paneAnswersEscape(layersWatching: Int) -> Bool { layersWatching == 0 }

    /// The key is for a window that is not the page's, or for a field
    /// editor in it.
    static func isElsewhere(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        if window !== NSApp?.mainWindow { return true }
        return (window.firstResponder as? NSTextView)?.isFieldEditor == true
    }

    /// A key monitor's answer: nil for the Esc it took, the event itself —
    /// unchanged — for everything else.
    func key(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown,
              Self.putsAway(keyCode: event.keyCode, modifiers: event.modifierFlags, hasBox: rect != nil,
                            elsewhere: Self.isElsewhere(event))
        else { return event }
        rect = nil
        return nil
    }
}

/// The shell round `TabletWriting` — and where the pen's target is chosen.
@MainActor
final class TabletScribe: ObservableObject {
    static let shared = TabletScribe(page: .shared, input: .shared, notebook: .shared)

    let page: TabletPage
    let box = TabletBox()
    /// THE STROKE BEING WRITTEN, published at the pen's rate (~120 a
    /// second) and watched by one layer that draws it and nothing else.
    /// The page's finished strokes change once a stroke, so a full page of
    /// handwriting is not redrawn under every sample.
    @Published private(set) var stroke: Stroke?
    /// The colour, width and tool — set by the pane from the page's own
    /// pen and the page's size on screen.
    var ink = TabletInk(colorHex: PageTheme.plain.defaultInk, width: 3)
    /// A stroke went onto the page, or a click of the pen's switches took
    /// one off it or put one back: ⌘Z is the page's now.
    var onWrite: (() -> Void)?

    /// The other target: the note, in Notebook mode.
    let notebook: NotebookScribe

    private var writing = TabletWriting()
    private weak var input: TabletInput?
    private var subscription: AnyCancellable?
    private var retargeting: AnyCancellable?

    /// `input` nil for a test that hands samples over itself; `notebook`
    /// nil for one of its own.
    init(page: TabletPage, input: TabletInput?, notebook: NotebookScribe? = nil) {
        self.page = page
        self.notebook = notebook ?? NotebookScribe()
        self.input = input
        // The funnel publishes from its monitors, which run on the main
        // thread.
        subscription = input?.samples.sink { [weak self] sample in
            MainActor.assumeIsolated { self?.consume(sample) }
        }
        // NOTHING HALF-DONE CROSSES OVER: the target changing drops the
        // stroke, the box and the marquee under way for either, so the lift
        // of a stroke begun on the page lands nowhere and the page's box is
        // not left up under the notebook's veil. The switch is flipped on
        // the main thread, from the bar or the menu or Esc.
        retargeting = input?.$target.removeDuplicates().dropFirst().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.dropUnderWay() }
        }
    }

    /// Where the samples go: the funnel's own word on it (`TabletInput.target`),
    /// so the switch has one writer.
    private var target: TabletTarget { input?.target ?? .page }

    /// THE TABLET IS HELD ANOTHER WAY, and everything in page fractions
    /// turns together, in one breath: the page's strokes and its history
    /// (`TabletPage.align`), the box left up over them — still over the
    /// same writing, where it used to be put away — and a stroke or a box
    /// half-drawn, so the rest of it joins on. The pane calls this for
    /// every turn — its corner's control, and any other — and on coming up.
    func align(to quarterTurns: Int) {
        let by = page.align(to: quarterTurns)
        guard by != 0 else { return }
        writing.turn(by: by)
        if stroke != nil { stroke = writing.stroke }
        if let rect = box.rect { box.rect = TabletPage.turned(rect, by: by) }
    }

    /// THE PEN'S BUTTONS UNDO AND REDO THE LAST DRAWING (Sean, 2026-10-02:
    /// "make the wacom buttons undo and redo last drawing"): a click of the
    /// LOWER switch takes it back, of the UPPER puts it back — and THIS IS
    /// THE ONE PLACE THAT SAYS WHOSE, by where the pen writes. On the page
    /// it is the page's own undo and redo, what the corner's two buttons
    /// do, ⌘Z the page's afterwards as after them; in the notebook it is
    /// the note's drawing undo and redo, the two ⌥⌘Z and ⇧⌥⌘Z call
    /// (`NotebookScribe.takeBack`). Never a second undo beside either, and
    /// with nothing to take back or put back, nothing at all: no step, no
    /// claim on ⌘Z. A click cannot come while a stroke or a box is under
    /// way — the pen's own state sees to that (`TabletPen.clicked`).
    private func command(_ clicked: PenSwitch) {
        switch (target, clicked) {
        case (.page, .lower): if page.undo() { onWrite?() }
        case (.page, .upper): if page.redo() { onWrite?() }
        case (.notebook, .lower): notebook.takeBack()
        case (.notebook, .upper): notebook.putBack()
        }
    }

    private func dropUnderWay() {
        writing = TabletWriting()
        if stroke != nil { stroke = nil }
        if box.rect != nil { box.rect = nil }
        notebook.drop()
    }

    func consume(_ sample: TabletSample) {
        if case .click(let clicked) = sample.phase {
            command(clicked)
            return
        }
        if target == .notebook {
            notebook.consume(sample)
            return
        }
        switch writing.consume(sample, ink: ink) {
        case .none:
            break
        case .began:
            // Writing on the page puts a box away, as a click would.
            if box.rect != nil { box.rect = nil }
            stroke = writing.stroke
        case .grew:
            stroke = writing.stroke
        case .finished(let finished):
            // In one breath, so the live layer lets go of the stroke in the
            // same frame the page's layer takes it.
            stroke = nil
            page.commit(finished)
            onWrite?()
        case .boxing(let rect), .boxed(let rect):
            box.rect = rect
        case .clicked:
            if box.rect != nil { box.rect = nil }
        case .erasing(let from, let to):
            // Erasing on the page puts a box away, as writing does.
            if box.rect != nil { box.rect = nil }
            if page.erase(from: from, to: to, radius: StrokeEraser.pageRadius) { onWrite?() }
        case .erased:
            page.endErasing()
        }
    }
}
