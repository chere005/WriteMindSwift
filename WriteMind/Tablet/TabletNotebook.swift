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

/// HOW THE TABLET LANDS ON THE NOTES (Sean, 2026-10-02: "a toggle from
/// scaling to real drawing size or the mapping to the entire visible
/// screen"). Fit maps the whole tablet onto the visible notes; Real size
/// makes a millimetre on the tablet a millimetre of the screen — the
/// tablet's area centred on the notes, clipped by the pane when it is
/// bigger, never shrunk. Remembered (`AppState.notebookScale`), and on the
/// tablet bar while the pen writes in the notebook.
enum NotebookScale: String, CaseIterable, Identifiable {
    case fit
    case real

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: return "Fit"
        case .real: return "Real size"
        }
    }

    var icon: String {
        switch self {
        case .fit: return "arrow.up.left.and.arrow.down.right"
        case .real: return "ruler"
        }
    }

    var help: String {
        switch self {
        case .fit: return "The whole tablet covers the notes you can see"
        case .real: return "A millimetre on the tablet is a millimetre on the screen — the tablet sits in the middle of the notes"
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
    /// Fit, or the tablet at its real size (`NotebookScale`).
    var scale: NotebookScale = .fit
    /// The tablet's active area in millimetres, turned as it is held
    /// (`TabletMapping.millimetres`). Zero is unmeasured, and Real size
    /// then has nothing to be real to: it falls back to Fit.
    var millimetres: CGSize = .zero
    /// The drawing cells that can be drawn in, in document points.
    var cells: [CellFrame] = []
    /// The cell in cell drawing mode.
    var entered: UUID? = nil

    /// Between the tablet's area and the edges of the notes, so its outline
    /// is never drawn on the edge of the pane.
    static let margin: CGFloat = 12

    /// THE TABLET ON THE NOTES: its turned shape, as big as fits the pane
    /// less the margin, centred — FITTED, never stretched, so a letter
    /// written on the tablet keeps its proportions in the note whatever
    /// shape the window is. On the PANE, not the document: the pen writes
    /// on the notes that can be seen, wherever the note is scrolled to.
    ///
    /// AT REAL SIZE the area is the tablet's millimetres at the screen's
    /// points per millimetre, centred on the same pane — and left as big as
    /// it is when the pane is smaller: what is off the notes is off.
    var area: CGRect {
        guard scale == .real, millimetres.width > 0, millimetres.height > 0 else {
            return TabletMapping.fit(aspect: aspect, in: pane, margin: Self.margin)
        }
        let size = CGSize(width: millimetres.width * TabletMapping.pointsPerMillimetre,
                          height: millimetres.height * TabletMapping.pointsPerMillimetre)
        return CGRect(x: (pane.width - size.width) / 2, y: (pane.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// No notes on screen to write on — none open, or a pane too small to
    /// hold the area.
    var isEmpty: Bool {
        !(pane.width > 2 * Self.margin && pane.height > 2 * Self.margin) || !(aspect > 0)
    }

    /// A point on the turned tablet — page fractions, as the funnel gives
    /// it (`TabletSample.page`) — on the pane, in view points.
    ///
    /// AT REAL SIZE a tablet bigger than the pane has parts that land off
    /// the notes, and the pen there writes along the edge rather than in
    /// the air beyond it — the area is clipped, never shrunk.
    func onPane(_ page: CGPoint) -> CGPoint {
        let area = self.area
        let point = CGPoint(x: area.minX + page.x * area.width, y: area.minY + page.y * area.height)
        guard scale == .real else { return point }
        return CGPoint(x: min(max(point.x, 0), pane.width), y: min(max(point.y, 0), pane.height))
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
    ///
    /// `rect`, when it is given, is the entered cell's frame in document
    /// points: the point is HELD INSIDE it first, so a stroke written in a cell
    /// runs along its edge and leaves nothing outside (`CellDrawing.hold`).
    func strokePoint(_ page: CGPoint, heldIn rect: CGRect? = nil) -> CGPoint {
        var point = inDocument(page)
        if let rect { point = CellDrawing.hold(document: point, in: rect) }
        return CGPoint(x: point.x / pane.width, y: point.y / pane.height)
    }
}

/// The rule, sample by sample: the nib down is ink in the note, the nib
/// down with a side switch held is the layer's marquee — and a DRAWING CELL
/// is static: the nib TAPPING one enters it, and in cell drawing mode the
/// nib writes into that cell and nowhere else.
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
        /// The ERASER — begun by the nib with the lower switch held — went
        /// from `from` to `to`, in the document's points (one point at the
        /// start): the layer deletes the strokes it touched, whole.
        case erasing(from: CGPoint, to: CGPoint)
        /// It came up: the erasure is one step.
        case erased
        /// THE NIB TAPPED A STATIC DRAWING CELL — down and up under
        /// `CellDrawing.clickTravel` over a writable cell nobody had
        /// entered: the cell is entered, and the tap leaves no dot (the
        /// click is the way in, as for the mouse).
        case entered(UUID)
        /// In cell drawing mode the nib went down OUTSIDE the entered cell:
        /// the way out. Nothing of that touch is ink, a box or an erasure
        /// (a tap of it on another cell enters that one, as a click does).
        case left
        /// The nib came up having written inside the entered cell: this stroke
        /// goes into THAT CELL, held inside it, and nowhere else.
        case finishedInCell(Stroke, UUID)
    }

    private(set) var stroke: Stroke?
    private var marqueeStart: CGPoint?
    private var eraseLast: CGPoint?
    /// The entered cell this touch is writing into, with where it is on the
    /// page (document points).
    private var cell: (id: UUID, rect: CGRect)?
    /// A touch that began over a static, writable cell: a tap if it never
    /// travels (`CellDrawing.clickTravel`), else a stroke over it.
    private var tapCell: UUID?
    /// The touch is not ink: it began outside the entered cell.
    private var inkless = false
    private var downAt: CGPoint = .zero
    private var travelled: CGFloat = 0

    mutating func consume(_ sample: TabletSample, at place: NotebookPlace, ink: TabletInk) -> Outcome {
        switch sample.phase {
        case .hover, .click:
            return .none
        case .down:
            let at = place.inDocument(sample.page)
            reset()
            downAt = at
            // IN A CELL a touch inside the entered cell is the cell's, and a
            // touch anywhere else is the way out — the touch itself is
            // nothing, and a tap of it on another cell enters that cell.
            if let entered = place.entered {
                guard let frame = place.cells.first(where: { $0.id == entered && $0.writable }),
                      frame.rect.contains(at) else {
                    inkless = true
                    if !sample.eraser, !sample.sideSwitch {
                        tapCell = place.cells.first { $0.writable && $0.rect.contains(at) }?.id
                    }
                    return .left
                }
                cell = (frame.id, frame.rect)
            }
            if sample.eraser {
                eraseLast = at
                return .erasing(from: at, to: at)
            }
            if sample.sideSwitch {
                // A tap with the side switch held is a ⌘-click: the marquee
                // of nothing picks what is under it, or lets go of what was
                // picked.
                marqueeStart = at
                return .selecting(CGRect(origin: at, size: .zero))
            }
            // EXACTLY AS THE LAYER'S OWN PEN BEGINS ONE (`DrawingCanvas`,
            // `.drawing`): `Stroke.starting` with the nib's own sample, so
            // the pen picked on the pen menu makes ink with a pressure a
            // point.
            stroke = Stroke.starting(at: place.strokePoint(sample.page, heldIn: cell?.rect), colorHex: ink.colorHex,
                                     width: ink.width, pen: .pen(pressure: sample.pressure), tool: ink.tool)
            // A touch on a static cell may be a tap into it: it shows no ink
            // until it has travelled.
            if cell == nil, let over = place.cells.first(where: { $0.writable && $0.rect.contains(at) }) {
                tapCell = over.id
                return .none
            }
            return .began
        case .drag:
            let at = place.inDocument(sample.page)
            travelled = max(travelled, hypot(at.x - downAt.x, at.y - downAt.y))
            if inkless { return .none }
            if let last = eraseLast {
                eraseLast = at
                return .erasing(from: last, to: at)
            }
            if let start = marqueeStart {
                return .selecting(CanvasGeometry.rect(from: start, to: at))
            }
            guard stroke != nil else { return .none }
            stroke?.append(place.strokePoint(sample.page, heldIn: cell?.rect), pen: .pen(pressure: sample.pressure))
            if tapCell != nil {
                // Still a tap: no ink yet. Once it has travelled it is a
                // stroke over the cell, from where the nib went down.
                guard !CellDrawing.isClick(travelled: travelled) else { return .none }
                tapCell = nil
                return .began
            }
            return .grew
        case .up:
            let at = place.inDocument(sample.page)
            travelled = max(travelled, hypot(at.x - downAt.x, at.y - downAt.y))
            defer { reset() }
            if inkless {
                // A tap on another cell, outside the one that was entered,
                // enters that one: a click does.
                if let tap = tapCell, CellDrawing.isClick(travelled: travelled) { return .entered(tap) }
                return .none
            }
            if eraseLast != nil { return .erased }
            if let start = marqueeStart { return .selected(CanvasGeometry.rect(from: start, to: at)) }
            // The lift is not a point (it reports no pressure), as on the
            // page and as for the layer's own pen: a tap is one point, which
            // the ink draws as a dot.
            guard let finished = stroke else { return .none }
            if let tap = tapCell, CellDrawing.isClick(travelled: travelled) { return .entered(tap) }
            if let cell { return .finishedInCell(finished, cell.id) }
            return .finished(finished)
        }
    }

    /// The entered cell the touch under way began in (every touch inside it,
    /// a stroke, the eraser's or the marquee's), nil for any other touch.
    var cellTouch: UUID? { cell?.id }
    /// Where the cell is that the touch under way began in (document points).
    var cellRect: CGRect? { cell?.rect }
    /// The touch under way is the eraser's, or the marquee's.
    var isErasing: Bool { eraseLast != nil }
    var isSelecting: Bool { marqueeStart != nil }

    /// Whatever was under way is forgotten, and nothing of it lands.
    mutating func reset() {
        stroke = nil
        marqueeStart = nil
        eraseLast = nil
        cell = nil
        tapCell = nil
        inkless = false
        travelled = 0
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
    /// The marquee while it is dragged — begun by the nib with the UPPER side
    /// switch held — in document points.
    @Published private(set) var marquee: CGRect?
    /// A marquee let go, in document points: the drawing layer picks what
    /// it touches, as at the end of a ⌘-drag (`DrawingCanvas.marqueePicked`).
    let picks = PassthroughSubject<CGRect, Never>()
    /// What the ERASER did over the notes, in document points: the drawing
    /// layer deletes the strokes it touched, whole (`DrawingCanvas.erase`).
    let erases = PassthroughSubject<NotebookErase, Never>()

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
    ///
    /// AND SO IS THE CELL MODE ENDING UNDER A TOUCH THAT BEGAN IN IT (Esc, ⌘P,
    /// the cell folding away — the nib is down and the mode is not): the
    /// canvas scopes the eraser and the marquee by the cell ENTERED, so their
    /// rest would be the PAGE'S — the eraser deleting its strokes, the marquee
    /// picking its objects — and they stop with the mode. A stroke carries on
    /// held inside its cell and lands in it, or nowhere if the cell is gone
    /// (`NoteStore.inkFromTablet`): ink is never lost to a key, and never goes
    /// onto the page. A touch that began OUTSIDE the entered cell — the way
    /// out — is not one of these: it has no cell, and its lift on another
    /// cell still enters that one.
    var place: NotebookPlace? {
        didSet {
            if oldValue?.note != place?.note || oldValue?.quarterTurns != place?.quarterTurns { drop(); return }
            if let home = writing.cellTouch, home != place?.entered, writing.isErasing || writing.isSelecting {
                drop()
            }
        }
    }
    /// Where the stroke under the nib is held, as it is drawn live: the cell it
    /// began in, which is held to its end even when the mode ends under the
    /// nib (it lands there, `finishedInCell`).
    var touchClip: CGRect? { writing.cellRect }
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
    /// A stroke written in the ENTERED cell (cell drawing mode), the cell it
    /// goes into: held inside it, one step on that cell's undo.
    var onCellStroke: ((Stroke, UUID) -> Void)?
    /// The nib TAPPED a static cell: it is entered (`AppState.enterCell`),
    /// and the caret goes into it as a click's does.
    var onEnterCell: ((UUID) -> Void)?
    /// The nib went down outside the entered cell: the way out.
    var onLeaveCell: (() -> Void)?

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
        onCellStroke = { [weak store, weak state] stroke, cell in
            guard let store else { return }
            let floor = store.drawingSteps
            guard store.inkFromTablet(stroke, intoCell: cell) else { return }
            state?.inkedNote(above: floor)
        }
        // A TAP ON A STATIC CELL IS A CLICK INTO IT: the caret goes in, as a
        // click's does, and the cell mode is entered — the one way in for the
        // nib, as the layer's click is for the mouse.
        onEnterCell = { [weak state] id in
            state?.editor.focusDrawingCell(id)
            state?.enterCell(id)
        }
        onLeaveCell = { [weak state] in state?.endCellDrawing() }
        // IN A CELL the pen's buttons are the cell's own undo and redo
        // (`NoteStore.undoDrawing(inCell:)`), as ⌘Z is.
        onUndo = { [weak store, weak state] in store?.undoDrawing(inCell: state?.cellDrawing) }
        onRedo = { [weak store, weak state] in store?.redoDrawing(inCell: state?.cellDrawing) }
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
        case .erasing(let from, let to):
            erases.send(.path(from: from, to: to))
        case .erased:
            erases.send(.end)
        case .entered(let id):
            // The tap shows no ink and leaves none: the cell is entered.
            stroke = nil
            onEnterCell?(id)
        case .left:
            stroke = nil
            marquee = nil
            onLeaveCell?()
        case .finishedInCell(let finished, let id):
            stroke = nil
            onCellStroke?(finished, id)
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
    /// went — and nothing of it lands. An erasure under way is ENDED first,
    /// so the layer's one step for it is closed (`DrawingCanvas.erase`), and
    /// the next erasure begins its own.
    func drop() {
        if writing.isErasing { erases.send(.end) }
        writing.reset()
        if stroke != nil { stroke = nil }
        if marquee != nil { marquee = nil }
    }
}
