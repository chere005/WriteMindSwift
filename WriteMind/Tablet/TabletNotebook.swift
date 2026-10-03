import AppKit
import Combine

// THE PEN WRITES STRAIGHT INTO THE NOTE — the separate mode (Sean,
// 2026-10-02: "make the text strokes well implemented to feel natural for
// writing letters.. do the same for drawing mode in the notebook itself and
// let the wacom control that as well.. as a separate mode").
//
// "Write on: Page | Notebook", on the page's bar. On the notebook, the
// tablet held turned is FITTED onto the notes that are on screen — its own
// shape, as big as fits, centred, never stretched, because handwriting has
// to keep its proportions — and the nib writes the note's own strokes, in
// the note's own coordinates, with the NOTEBOOK pen's tool, colour and
// width: the stroke the layer's own pen would have made at that spot, with
// a pressure a point. A side switch held as the nib goes down is the
// layer's marquee; clicked in the air, the lower one is the note's drawing
// undo and the upper its redo (`TabletScribe.command`). The page is left as
// it is.
//
// The same shape as the page's (`TabletWriting`, `TabletScribe`): the rule
// is a value walked sample by sample in the tests (`NotebookWriting`), the
// mapping is pure (`NotebookPlace`), and `NotebookScribe` is the shell —
// fed by `TabletScribe`, still the funnel's ONE consumer, which chooses the
// target. What it writes with and where the notes are come from the notes
// pane (`NotebookTabletLayer`); where a stroke goes is `NoteStore`'s.

/// Where the tablet's pen writes (`AppState.tabletTarget`).
enum TabletTarget: String, CaseIterable, Identifiable {
    /// Its own page, in the pane where the video would be — the default.
    case page
    /// The open note's drawing layer, over the notes.
    case notebook

    var id: String { rawValue }

    /// The switch's words: "Write on: Page | Notebook".
    var title: String {
        switch self {
        case .page: return "Page"
        case .notebook: return "Notebook"
        }
    }

    var icon: String {
        switch self {
        case .page: return "doc"
        case .notebook: return "book.closed"
        }
    }

    var help: String {
        switch self {
        case .page:
            return "The pen writes on this page, which keeps what is written on it"
        case .notebook:
            return "The pen writes straight into the open note, with the notebook's pen"
        }
    }
}

/// Where the notes are on screen, for the pen: the pane the drawing layer
/// covers — below the tab bar and the formatting bar, above the footer, in
/// the source pane and on the rendered page alike — how far the text under
/// it has scrolled, and the tablet's turned shape.
struct NotebookPlace: Equatable {
    /// The drawing layer's size: the visible notes.
    var pane: CGSize
    /// How far the text has scrolled (`DrawingCanvas.scrollOffset`).
    var scroll: CGFloat
    /// The tablet's width over its height, turned the way it is held
    /// (`TabletMapping.aspect`).
    var aspect: CGFloat
    /// Which note is open under the layer (`Note.ID`). Not part of the
    /// mapping: a stroke under way is let go when it changes
    /// (`NotebookScribe.place`).
    var note: String? = nil
    /// How the tablet is held (`AppState.tabletQuarterTurns`) — the turn
    /// `aspect` was worked from. Not part of the mapping either, and for
    /// the same reason: a stroke under way is let go when it changes.
    var quarterTurns = 1

    /// Between the tablet's area and the edges of the notes, so its outline
    /// is never drawn on the edge of the pane.
    static let margin: CGFloat = 12

    /// THE TABLET ON THE NOTES: its turned shape, as big as fits the pane
    /// less the margin, centred — FITTED, never stretched, so a letter
    /// written on the tablet keeps its proportions in the note whatever
    /// shape the window is. On the PANE, not the document: the pen writes
    /// on the notes that can be seen, wherever the note is scrolled to.
    var area: CGRect { TabletMapping.fit(aspect: aspect, in: pane, margin: Self.margin) }

    /// No notes on screen to write on — none open, or a pane too small to
    /// hold the area.
    var isEmpty: Bool {
        !(pane.width > 2 * Self.margin && pane.height > 2 * Self.margin) || !(aspect > 0)
    }

    /// A point on the turned tablet — page fractions, as the funnel gives
    /// it (`TabletSample.page`) — on the pane, in view points.
    func onPane(_ page: CGPoint) -> CGPoint {
        let area = self.area
        return CGPoint(x: area.minX + page.x * area.width, y: area.minY + page.y * area.height)
    }

    /// The same point in the DOCUMENT: a scroll's worth further down, where
    /// the drawing layer keeps everything (`DrawingCanvas.doc`).
    func inDocument(_ page: CGPoint) -> CGPoint {
        let point = onPane(page)
        return CGPoint(x: point.x, y: point.y + scroll)
    }

    /// As a stroke keeps it: the document point as fractions of the pane on
    /// BOTH axes — the layer's own pen's normalising, without its clamp to
    /// one pane's height (`DrawingCanvas.normalise` pins a point a screen
    /// or more down a long note to the bottom of the first screen; the area
    /// is always on the pane, so there is nothing here to clamp).
    func strokePoint(_ page: CGPoint) -> CGPoint {
        let point = inDocument(page)
        return CGPoint(x: point.x / pane.width, y: point.y / pane.height)
    }
}

/// The rule, sample by sample: the nib down is ink in the note, the nib
/// down with a side switch held is the layer's marquee.
struct NotebookWriting {
    enum Outcome: Equatable {
        case none
        /// The nib went down: a stroke has begun.
        case began
        /// The stroke being written has another point.
        case grew
        /// The nib came up: this stroke goes into the note.
        case finished(Stroke)
        /// The marquee — begun by the nib with a side switch held — being
        /// dragged: so far, in the document's points, as a ⌘-drag's is.
        case selecting(CGRect)
        /// It came up: the layer picks what this touches.
        case selected(CGRect)
    }

    private(set) var stroke: Stroke?
    private var marqueeStart: CGPoint?

    mutating func consume(_ sample: TabletSample, at place: NotebookPlace, ink: TabletInk) -> Outcome {
        switch sample.phase {
        case .hover, .click:
            return .none
        case .down:
            if sample.sideSwitch {
                // A tap with the side switch held is a ⌘-click: the marquee
                // of nothing picks what is under it, or lets go of what was
                // picked.
                stroke = nil
                let start = place.inDocument(sample.page)
                marqueeStart = start
                return .selecting(CGRect(origin: start, size: .zero))
            }
            marqueeStart = nil
            // EXACTLY AS THE LAYER'S OWN PEN BEGINS ONE (`DrawingCanvas`,
            // `.drawing`): `Stroke.starting` with the nib's own sample, so
            // the pen picked on the pen menu makes ink with a pressure a
            // point.
            stroke = Stroke.starting(at: place.strokePoint(sample.page), colorHex: ink.colorHex, width: ink.width,
                                     pen: .pen(pressure: sample.pressure), tool: ink.tool)
            return .began
        case .drag:
            if let start = marqueeStart {
                return .selecting(CanvasGeometry.rect(from: start, to: place.inDocument(sample.page)))
            }
            guard stroke != nil else { return .none }
            stroke?.append(place.strokePoint(sample.page), pen: .pen(pressure: sample.pressure))
            return .grew
        case .up:
            if let start = marqueeStart {
                marqueeStart = nil
                return .selected(CanvasGeometry.rect(from: start, to: place.inDocument(sample.page)))
            }
            // The lift is not a point (it reports no pressure), as on the
            // page and as for the layer's own pen: a tap is one point, which
            // the ink draws as a dot.
            guard let finished = stroke else { return .none }
            stroke = nil
            return .finished(finished)
        }
    }

    /// Whatever was under way is forgotten, and nothing of it lands.
    mutating func reset() {
        stroke = nil
        marqueeStart = nil
    }
}

/// The shell round `NotebookWriting`: the stroke being written where one
/// layer over the notes can redraw it at the pen's rate, the marquee the
/// same, and what lands handed on — a stroke to the note, a marquee to the
/// drawing layer, which picks with its own rule.
@MainActor
final class NotebookScribe: ObservableObject {
    /// The one the notes pane draws and `TabletScribe.shared` feeds.
    static let shared = NotebookScribe()

    /// THE STROKE BEING WRITTEN, in the note's own coordinates — watched by
    /// one layer that draws it and nothing else (`NotebookLiveInk`), so a
    /// note full of drawing is not redrawn under every sample.
    @Published private(set) var stroke: Stroke?
    /// The marquee while it is dragged — begun by the nib with a side
    /// switch held — in document points.
    @Published private(set) var marquee: CGRect?
    /// A marquee let go, in document points: the drawing layer picks what
    /// it touches, as at the end of a ⌘-drag (`DrawingCanvas.marqueePicked`).
    let picks = PassthroughSubject<CGRect, Never>()

    /// Where the notes are — kept up to date by the notes pane while a note
    /// is on screen, nil while none is (`NotebookTabletLayer`).
    ///
    /// ANOTHER NOTE UNDER THE NIB TAKES NOTHING WITH IT: the layer stays
    /// up when the tab changes, so a stroke begun in one note would land in
    /// the next — half its points a scroll below the rest, and a step on
    /// that note's undo — and a marquee would pick there. Whatever was
    /// under way is dropped when the note changes, or the notes go; a
    /// scroll or a resize in the same note keeps it.
    ///
    /// AND SO IS A TURN UNDER THE NIB: the note does not turn with the
    /// tablet the way the page does — its strokes are the note's, where
    /// they were written on it — but the area the tablet lands on does,
    /// and the rest of a stroke under way would carry on a quarter turn
    /// away from the start of it.
    var place: NotebookPlace? {
        didSet {
            if oldValue?.note != place?.note || oldValue?.quarterTurns != place?.quarterTurns { drop() }
        }
    }
    /// What the pen writes with: the NOTEBOOK's pen — `AppState.penTool`,
    /// `penColorHex`, `penWidth` — never the page's.
    var ink = TabletInk(colorHex: AppState.presetColors[0], width: 3)
    /// A finished stroke, into the open note (`NoteStore.inkFromTablet`,
    /// which turns it away with no note open).
    var onStroke: ((Stroke) -> Void)?
    /// The note's own drawing undo and redo, for a click of the pen's
    /// switches (`takeBack`, `putBack`).
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?

    private var writing = NotebookWriting()

    /// THE WAY INTO THE NOTE, handed over by a notes pane's layer as it
    /// comes up (`NotebookTabletLayer`): where a finished stroke lands, and
    /// what a click of the pen's switches takes back and puts back —
    /// `NoteStore.undoDrawing` and `redoDrawing` THEMSELVES, the two ⌥⌘Z and
    /// ⇧⌥⌘Z call, never a second undo beside them (Sean, 2026-10-02: "make
    /// the wacom buttons undo and redo last drawing"). Here and not in the
    /// view so the tests go through the same way in.
    func writes(into store: NoteStore, telling state: AppState) {
        onStroke = { [weak store, weak state] stroke in
            guard let store else { return }
            let floor = store.drawingSteps
            guard store.inkFromTablet(stroke) else { return }
            // ⌘Z is the stroke's now, not the typing's — down to where
            // the drawing stood under it.
            state?.inkedNote(above: floor)
        }
        onUndo = { [weak store] in store?.undoDrawing() }
        onRedo = { [weak store] in store?.redoDrawing() }
    }

    /// The pen's lower switch clicked in Notebook mode: the note's drawing,
    /// one step back — and its upper: one step forward again. ONLY WITH
    /// NOTES ON SCREEN, as for the nib: an undo nobody can watch happen is
    /// a stroke lost. With nothing to take back or put back the store does
    /// nothing at all — no beep, and no step of its own.
    func takeBack() { if hasNotes { onUndo?() } }
    func putBack() { if hasNotes { onRedo?() } }

    private var hasNotes: Bool { place.map { !$0.isEmpty } ?? false }

    func consume(_ sample: TabletSample) {
        // No notes on screen: nothing to write on, and nothing half-written
        // is kept for when there are.
        guard let place, !place.isEmpty else { drop(); return }
        switch writing.consume(sample, at: place, ink: ink) {
        case .none:
            break
        case .began, .grew:
            stroke = writing.stroke
        case .finished(let finished):
            // In one breath, so the live layer lets go of the stroke in the
            // same frame the drawing layer takes it.
            stroke = nil
            onStroke?(finished)
        case .selecting(let rect):
            marquee = rect
        case .selected(let rect):
            marquee = nil
            picks.send(rect)
        }
    }

    /// A notes pane's layer went (`NotebookTabletLayer`). What was under
    /// way goes with it, but WHERE THE NOTES ARE AND THE WAY INTO THEM GO
    /// ONLY WITH THE LAST: the pane is built again whenever a pane beside
    /// it comes or goes (⌘Y, in Notebook mode the natural thing to press),
    /// and SwiftUI can bring the new one up before the old one goes — the
    /// old one's going then left the new one with no place and no way in,
    /// and every stroke after it was drawn live and landed nowhere.
    func layerWent(othersShowing: Bool) {
        drop()
        guard !othersShowing else { return }
        place = nil
        onStroke = nil
        onUndo = nil
        onRedo = nil
    }

    /// Whatever was under way is dropped — the target changed, the notes
    /// went — and nothing of it lands.
    func drop() {
        writing.reset()
        if stroke != nil { stroke = nil }
        if marquee != nil { marquee = nil }
    }
}
