import AppKit
import SwiftUI

/// UI-only state: which pane is showing, whether the sidebar is out, and the pen.
final class AppState: ObservableObject {
    enum Mode: String { case editor, preview }

    /// Who the pane belongs to, one answer at a time (Sean, 2026-09-20:
    /// "the pen button section should allow choosing between pen mode,
    /// cursor mode, and pointer select mode which draws rectangles that
    /// can select drawn (or captured) stuff… pen and pointer select mode
    /// operate in the same space (along with placed squares and such.. the
    /// cursor interacts with the notebook (which is markdown)").
    ///
    /// TWO modes, and one button says which (Sean, 2026-09-21: "drop the
    /// cursor and select buttons.. clicking the pen outside of the dropdown
    /// is the toggle between pen and cursor"). In `cursor` the clicks go
    /// through to the words, the seams and the brackets; under the pen they
    /// do not go through at all. Select was a third, and is now what it
    /// always was underneath — a ⌘-drag, in either mode.
    enum CanvasMode: String, CaseIterable, Identifiable {
        case cursor, pen

        var id: String { rawValue }

        /// The app's own words for them, on the picker and in the footer.
        var title: String {
            switch self {
            case .cursor: return "Cursor"
            case .pen: return "Pen"
            }
        }

        var icon: String {
            switch self {
            case .cursor: return "cursorarrow"
            case .pen: return "pencil.tip"
            }
        }

        var help: String {
            switch self {
            case .cursor: return "The notebook takes the clicks — the words, the bars between the cells, the brackets. Objects on the page can still be dragged by hand."
            case .pen: return "Draw over the note. Hold ⌘ to pull a rectangle over what is on the page instead."
            }
        }

        /// What a press on the pane does, once the two tools that take the
        /// pane — the arrow tool, an armed shape — have had their say.
        enum Press: Equatable {
            /// Pull a rectangle over the page and pick up what it touches.
            case marquee
            /// Draw.
            case draw
            /// The objects on the layer: pick one up, or let the click
            /// through to the notebook.
            case objects
            /// A drawing cell's PAPER, in cursor mode: a stroke into the
            /// cell once the press has travelled (`paperStrokes`), or the
            /// caret into the cell if it never does.
            case paper
        }

        /// ⌘ IS THE SELECTOR, IN BOTH MODES (Sean, 2026-09-21: "in both
        /// modes holding cmd is how to get the selector") — which is why
        /// there is no third mode any more. It is asked before the mode,
        /// because a modifier held down is asked for by hand and that is
        /// what overrides a mode; under the pen a ⌘-drag used to draw a
        /// stroke over whatever it was meant to be picking up.
        ///
        /// ON A DRAWING CELL'S PAPER the cursor draws (Sean, 2026-10-02:
        /// "drawing cell which is cmd + 0"): the cell is for drawing in,
        /// and making him pick the pen up for each one is the step that
        /// the cell was made to save. An object under the point — on the
        /// layer or in a cell — is asked before the paper, by the canvas,
        /// and is picked up as it always was.
        func press(with modifiers: NSEvent.ModifierFlags, onCellPaper: Bool = false) -> Press {
            if modifiers.contains(.command) { return .marquee }
            if self == .pen { return .draw }
            return onCellPaper ? .paper : .objects
        }

        /// WHETHER A CURSOR-MODE PRESS ON A CELL'S PAPER HAS BECOME A
        /// STROKE: at once for a nib, whose touch IS the start of ink, and
        /// for a mouse or a trackpad once it has travelled `paperTravel`.
        /// A click that never moves leaves no dot and no empty step behind
        /// it — it puts the caret in the cell instead.
        static func paperStrokes(travelled: CGFloat, nib: Bool) -> Bool {
            nib || travelled >= paperTravel
        }

        /// How far a mouse press on a cell's paper goes before it draws.
        static let paperTravel: CGFloat = 3
    }

    /// What the right-hand pane shows: the camera's picture, or the page
    /// the tablet writes on. Not a switch of its own — it is whichever was
    /// picked last in Input Devices (Sean, 2026-10-02: "wacom should
    /// basically just be chosen as if it were an input display").
    enum InputSource: String {
        case camera, tablet

        /// The one rule: a tablet picked is the tablet's pane, and nothing
        /// picked — or a camera — is the camera's.
        static func of(tabletPicked: Bool) -> InputSource { tabletPicked ? .tablet : .camera }

        /// What the pane's one switch, its panel and its way out call it.
        var words: PaneWords { self == .tablet ? .page : .camera }
    }

    /// THE PANE IS CALLED WHAT IT SHOWS. The switch, the View menu, the
    /// panel under the chevron and the whole-window × were worded for video
    /// alone, so with the tablet picked the only control for the page named
    /// a camera that was off.
    struct PaneWords: Equatable {
        let show: String
        let hide: String
        let showHelp: String
        let hideHelp: String
        let shownIcon: String
        let hiddenIcon: String
        let wholeWindowHelp: String
        let sideBySideHelp: String
        let leaveWholeWindow: String
        let options: String

        static let camera = PaneWords(show: "Show Video", hide: "Hide Video",
                                      showHelp: "Bring the camera pane back", hideHelp: "Put the camera pane away",
                                      shownIcon: "video.fill", hiddenIcon: "video.slash",
                                      wholeWindowHelp: "Put the notes away and give the window to the video",
                                      sideBySideHelp: "The notes and the video side by side again",
                                      leaveWholeWindow: "Leave Full-Window Video", options: "Video Options")

        static let page = PaneWords(show: "Show Page", hide: "Hide Page",
                                    showHelp: "Bring the tablet's page back", hideHelp: "Put the tablet's page away",
                                    shownIcon: "pencil.tip.crop.circle", hiddenIcon: "pencil.slash",
                                    wholeWindowHelp: "Put the notes away and give the window to the page",
                                    sideBySideHelp: "The notes and the page side by side again",
                                    leaveWholeWindow: "Leave Full-Window Page", options: "Page Options")
    }

    /// A `/link` waiting for its target: which note it was typed in, roughly
    /// where, and what the note was called so the banner can say so.
    struct PendingLink: Equatable {
        let sourceNoteID: Note.ID
        let sourceTitle: String
        let caret: Int
    }

    @Published var showSidebar: Bool { didSet { defaults.set(showSidebar, forKey: Keys.showSidebar) } }
    @Published var showEditor: Bool { didSet { defaults.set(showEditor, forKey: Keys.showEditor) } }
    @Published var showCamera: Bool { didSet { defaults.set(showCamera, forKey: Keys.showCamera) } }
    @Published var penWidth: Double { didSet { defaults.set(penWidth, forKey: Keys.penWidth) } }
    /// Quarter turns of the video pane, kept because a camera that is mounted
    /// sideways stays mounted sideways.
    @Published var cameraRotation: Int { didSet { defaults.set(cameraRotation, forKey: Keys.cameraRotation) } }
    /// How the tablet is held: quarter turns clockwise from the landscape it
    /// shipped in, 0…3. ONE by default (Sean, 2026-10-02: "i want to rotate
    /// the wacom 90 degrees clockwise for when its in use in WriteMind"),
    /// and remembered, because a tablet kept turned on the desk stays
    /// turned.
    @Published var tabletQuarterTurns: Int {
        didSet { defaults.set(tabletQuarterTurns, forKey: Keys.tabletQuarterTurns) }
    }
    /// WHERE THE TABLET'S PEN WRITES: its own page, or straight into the
    /// note (Sean, 2026-10-02: "do the same for drawing mode in the notebook
    /// itself and let the wacom control that as well.. as a separate
    /// mode"). The page unless the notebook is picked, and remembered — a
    /// way of working, like the turn. Changed through `writeOn` (the
    /// switch on the page's bar, and the View menu) and nothing else — no
    /// key; the funnel is handed it from the app (`TabletInput.aim`).
    @Published var tabletTarget: TabletTarget {
        didSet { defaults.set(tabletTarget.rawValue, forKey: Keys.tabletTarget) }
    }
    /// How the tablet lands on the notes in Notebook mode: the whole of it
    /// on the visible notes, or a millimetre for a millimetre (Sean,
    /// 2026-10-02). Remembered, like the turn.
    @Published var notebookScale: NotebookScale {
        didSet { defaults.set(notebookScale.rawValue, forKey: Keys.notebookScale) }
    }
    /// Which pane the input is — derived from the pick, so it has ONE
    /// writer (`follow(tabletPicked:)`, fed by the tablet controller) and
    /// is never stored: the pick is what is remembered.
    @Published private(set) var inputSource: InputSource = .camera
    /// What shape the viewfinder is (Sean, 2026-09-21: "add aspect ratio
    /// control"). Remembered, like the turn and the zoom beside it: the
    /// shape you photograph pages in is a property of your notebook, not
    /// of this launch.
    /// What ⌘9 makes: the environment the last evaluation cell was, so a
    /// notebook of Python cells takes one press each (Sean, 2026-09-22:
    /// "remember last used cell type when inserting") — Wolfram until one
    /// has been picked ("default to wolfram"). Written by the badge on a
    /// cell when an environment is chosen there (`EditorPane`), and by
    /// nothing else.
    @Published var evaluator: Evaluator {
        didSet { defaults.set(evaluator.rawValue, forKey: Keys.evaluator) }
    }
    @Published var cameraAspect: CameraAspect {
        didSet { defaults.set(cameraAspect.rawValue, forKey: Keys.cameraAspect) }
    }
    @Published var penColorHex: String { didSet { defaults.set(penColorHex, forKey: Keys.penColorHex) } }
    /// What a TABLET'S pen writes with in the notebook (Sean, 2026-10-02:
    /// "different pen colors and strokes to write with"). Only a nib takes
    /// it: a mouse or a trackpad stroke is the legacy line, tool nil,
    /// exactly as it always was.
    @Published var penTool: InkTool { didSet { defaults.set(penTool.rawValue, forKey: Keys.penTool) } }
    /// THE PAGE'S OWN PEN: its tool, its colour and its size, on the bar
    /// in the page's corner and remembered here like the notebook pen's.
    /// Its own and not the notebook pen's, because the paper under it is
    /// its own — chalk on a blackboard would otherwise leave the notebook
    /// writing white on white. New strokes take them; strokes already on
    /// the page keep what they were written with.
    @Published var pageInkTool: InkTool { didSet { defaults.set(pageInkTool.rawValue, forKey: Keys.pageInkTool) } }
    @Published var pageInkHex: String { didSet { defaults.set(pageInkHex, forKey: Keys.pageInkHex) } }
    /// As it is SEEN on the page (`TabletInk.width`).
    @Published var pageInkWidth: Double { didSet { defaults.set(pageInkWidth, forKey: Keys.pageInkWidth) } }
    /// The part of the video the pane is zoomed into, in pane fractions of
    /// the unzoomed picture (Sean, 2026-09-19: "drag a square to resize
    /// camera"). Nil is the whole picture.
    @Published var cameraZoom: CGRect? {
        didSet {
            defaults.set(cameraZoom.map { [$0.minX, $0.minY, $0.width, $0.height] }, forKey: Keys.cameraZoom)
        }
    }
    /// Armed to drag the box the video zooms into. Lives here because the
    /// button that arms it is on the editor's bar and the drag happens on
    /// the video (Sean, 2026-09-19: "picture and whole screen should be
    /// dropdowns from the show video button").
    @Published var cameraZooming = false
    /// What the list button writes: dots, dashes or numbers — dots by
    /// default (Sean, 2026-09-19).
    @Published var bulletStyle: MarkdownFormatting.ListStyle {
        didSet { defaults.set(bulletStyle.rawValue, forKey: Keys.bulletStyle) }
    }
    /// The language a new code block is tagged with.
    @Published var codeLanguage: CodeLanguage {
        didSet { defaults.set(codeLanguage.rawValue, forKey: Keys.codeLanguage) }
    }
    @Published var textFamily: String { didSet { defaults.set(textFamily, forKey: Keys.textFamily) } }
    @Published var textSize: Double { didSet { defaults.set(textSize, forKey: Keys.textSize) } }
    @Published var textColorHex: String { didSet { defaults.set(textColorHex, forKey: Keys.textColorHex) } }
    @Published var textApplyFamily: Bool { didSet { defaults.set(textApplyFamily, forKey: Keys.textApplyFamily) } }
    @Published var textApplySize: Bool { didSet { defaults.set(textApplySize, forKey: Keys.textApplySize) } }
    @Published var textApplyColor: Bool { didSet { defaults.set(textApplyColor, forKey: Keys.textApplyColor) } }
    /// True shows the raw markdown in the editor — `**`, `#`, the link's
    /// URL. Off (the default) hides them, leaving the styled text, with the
    /// caret's own paragraph always showing its own (Sean, 2026-09-19:
    /// "allow wysiwyg editing including all the buttons on the bar").
    @Published var showMarkers: Bool { didSet { defaults.set(showMarkers, forKey: Keys.showMarkers) } }
    /// Which sections of the toolbar are put away (Sean, 2026-09-19: "each
    /// section of the toolbar should be collapsable to make things sane").
    /// The shortcuts keep working: they live in the Format menu, not on the
    /// buttons.
    @Published var collapsedToolGroups: Set<String> {
        didSet { defaults.set(Array(collapsedToolGroups).sorted(), forKey: Keys.collapsedToolGroups) }
    }
    /// Set while the user is picking what a `/link` should point at.
    @Published var pendingLink: PendingLink?
    @Published var mode: Mode = .editor
    /// What the pane is for right now. Remembered like the pen's size and
    /// colour: it is a tool that was picked, not a thing that happened.
    @Published var canvasMode: CanvasMode = .cursor {
        didSet {
            defaults.set(canvasMode.rawValue, forKey: Keys.canvasMode)
            // The two tools that take the pane are not modes, and holding
            // one while a mode is on would be two answers to "what does
            // this drag do".
            guard canvasMode != .cursor else { return }
            if connectActive { connectActive = false }
            if placing != nil { placing = nil }
            showRenderedPage()
        }
    }
    /// The pen, which is a question about the mode and not a flag of its
    /// own any more — everything that used to ask still asks.
    var penActive: Bool { canvasMode == .pen }

    /// ONE WRITER for "the pen goes up or comes down", so the button on
    /// the bar and ⌘P cannot drift apart (Sean, 2026-09-21: "cmd p for
    /// toggling draw mode"). A second press puts it down rather than
    /// doing nothing, which is what the pen button has always done here.
    func togglePen() { canvasMode = penActive ? .cursor : .pen }

    /// Esc puts the pen down (Sean, 2026-10-02: "esc should exit pen
    /// mode"). True when there was a pen to put down, so the key is taken
    /// only then — in cursor mode Esc belongs to whatever else wants it.
    func escapePen() -> Bool {
        guard penActive else { return false }
        canvasMode = .cursor
        return true
    }
    /// The arrow tool (Sean, 2026-09-18): drag from node to node. One tool
    /// at a time — picking it up puts the pen down and an armed shape
    /// away, and the other way round. An armed shape is asked for the
    /// press first (`DrawingCanvas.begin`), so one left beside the arrow
    /// tool — and a shape no longer goes back on its own — would take
    /// every drag meant for the arrow.
    @Published var connectActive: Bool = false {
        didSet {
            guard connectActive else { return }
            if canvasMode != .cursor { canvasMode = .cursor }
            if placing != nil { placing = nil }
            showRenderedPage()
        }
    }
    /// The shape or mark armed by the palette, waiting for the drag that
    /// says where it goes (Sean, 2026-09-19). One tool at a time. A node
    /// a line or a mark stays here after it is put down, for the next one,
    /// until it is put away (`CanvasPlacement`).
    @Published var placing: CanvasPlacement? {
        didSet {
            guard placing != nil else { return }
            canvasMode = .cursor
            connectActive = false
            showRenderedPage()
        }
    }
    /// THE PALETTE'S ONE WRITER. A shape stays armed after it is drawn
    /// (Sean, 2026-10-02: "after drawing a rectangle dont exit rectangle
    /// mode.."), so the tile that armed it is one of the ways to put it
    /// away: the same tile again — lit while it is armed. Another tile is
    /// another tool.
    func arm(_ placement: CanvasPlacement) {
        placing = placing == placement ? nil : placement
    }

    /// DRAWING IS ON THE RENDERED PAGE ONLY. Sean, 2026-10-02: "only allow
    /// drawing in wysiwyg mode, both from wacom and from the pen cursor
    /// tool" — the pen, the arrow tool, an armed shape or mark, and the
    /// tablet writing in the notebook. What is drawn still SHOWS in both
    /// views (`PaneMapping`); picking any tool of drawing in the markdown
    /// view brings the rendered page up under it, through the same switch
    /// ⌘T is (`toggleMode`: the place and the cursor go with it), and
    /// going back to markdown puts the tools down. Called by every tool's
    /// own setter, so no button or key has to remember it.
    func showRenderedPage() {
        guard mode == .editor else { return }
        toggleMode()
    }

    /// EVERY TOOL PUT AWAY — the pen, the arrow tool, an armed shape — for
    /// something dropped on the page to be typed in or picked up: a text
    /// box or a picture from the bar or the Insert menu, a capture from
    /// the camera or the tablet. Each of those put the pen down already;
    /// a shape left armed would take the click that finishes the text box,
    /// or picks up the picture, and put a rectangle down instead. Every
    /// one of them comes through here (`CanvasModeTests` reads the
    /// sources for it).
    func putToolsAway() {
        canvasMode = .cursor
        connectActive = false
        placing = nil
    }

    /// Whether anything on the drawing layer is picked. The canvas keeps
    /// its own selection; this is the part the menu bar needs to know, so
    /// ⌘Z can go to the drawing rather than the text.
    @Published var canvasSelection = false

    /// Whether the drawing layer has the pane, so that no click reaches the
    /// notebook underneath: either of the layer's own two modes, or one of
    /// the two tools that take the pane until they are put away.
    ///
    /// ONE answer. The seams, the pointer and the hit testing all used to
    /// spell out the same three booleans separately, and a fourth thing to
    /// hold the pane meant finding all three lists again.
    var canvasOwnsPane: Bool {
        canvasMode != .cursor || connectActive || placing != nil
    }

    /// What the pointer is over the note pane, or nil to leave it to the
    /// notebook — which in cursor mode has four answers of its own (the
    /// bar between two cells, the hand over the + and over the brackets,
    /// the I-beam over the words) and is not ours to overwrite.
    var paneCursor: NSCursor? {
        if placing != nil || connectActive { return .crosshair }
        switch canvasMode {
        case .pen: return DrawingCursors.pencil
        case .cursor: return nil
        }
    }

    /// WHICH OF THE BAR'S TWO PALETTE BUTTONS IS LIT — the bar lights a
    /// tool that holds the pane, as it lights the pen, and a shape now
    /// holds it until it is put away (Sean, 2026-10-02: "after drawing a
    /// rectangle dont exit rectangle mode.."). The Shapes button for the
    /// arrow tool and the flow chart's nodes, the Marks button for its
    /// own tiles; both for the box, the circle and the triangle the two
    /// palettes share, since either tile puts it away. The lit tile is
    /// inside a popover that closes when it is picked, so the bar is
    /// where it shows.
    var shapesLit: Bool { connectActive || placing?.isOnFlowChart == true }
    var marksLit: Bool { placing?.isOnMarks == true }

    /// Whose ⌘Z it is. The drawing's while the pen is up, while something
    /// on the layer is picked, while a shape is waiting to be put down,
    /// while the arrow tool is on, or straight after ink went into the note
    /// with the keyboard still in its text — the five times the last thing
    /// done was done on the layer (Sean, 2026-09-19: "fix undo in drawing
    /// mode").
    var drawingOwnsUndo: Bool { layerInHand || inkOwnsUndo }

    /// And ⇧⌘Z: the same, but the ink's claim on it outlasts the strokes
    /// it took back (`inkOwnsRedo`).
    var drawingOwnsRedo: Bool { layerInHand || inkOwnsRedo }

    /// The four that are the layer's own: something on it in hand.
    private var layerInHand: Bool { penActive || connectActive || placing != nil || canvasSelection }

    /// Where the drawing's undo stood under the FIRST stroke since the text
    /// was last typed in that went into the note with the keyboard still in
    /// its text — the tablet's in Notebook mode, and a cursor-mode stroke
    /// on a drawing cell's paper — as `NoteStore.drawingSteps`, which counts
    /// every step taken and taken back; nil while no ink has a claim on
    /// ⌘Z. Not published: only the Undo and Redo items read it, when
    /// pressed.
    private(set) var inkFloor: Int?
    /// Where the drawing's undo stands now, told on every change to the
    /// drawing (`drawingChanged`).
    private(set) var drawingSteps = 0
    /// Ink went into the note over a drawing that stood at `floor` steps —
    /// a tablet stroke landing (`NoteStore.inkFromTablet`), or the layer
    /// starting a cursor-mode stroke in a cell. The first since the typing
    /// sets the claim's floor; the rest are above it.
    func inkedNote(above floor: Int) {
        if inkFloor == nil { inkFloor = floor }
    }
    /// The note's drawing changed, and its undo stands at `steps`: the last
    /// thing done is the note's again (`notebookChanged`), and the
    /// tablet's claim is measured from here.
    func drawingChanged(steps: Int) {
        notebookChanged()
        drawingSteps = steps
    }
    /// The note's TEXT changed: the last thing done is the text's — the
    /// page's claim goes (`notebookChanged`) and so does the ink's.
    func noteTyped() {
        notebookChanged()
        inkFloor = nil
    }

    /// ⌘Z TAKES BACK INK PUT IN THE NOTE, straight after it: the tablet's
    /// strokes — the pen is in one hand and ⌘Z under the other — and a
    /// cursor-mode stroke on a drawing cell's paper, after which nothing is
    /// picked and the pen is down. Either way the keyboard is still in the
    /// note's text, and left to it ⌘Z after a stroke undid the TYPING. From
    /// the stroke until the text is typed in, and only while the notes can
    /// be seen — AND ONLY DOWN TO THE FLOOR: once the strokes are taken
    /// back, and anything done on the layer after them, what is next to
    /// undo is the typing before them, and an undo that went on into the
    /// drawing undid an older step there and left the newer words standing.
    var inkOwnsUndo: Bool {
        guard let floor = inkFloor else { return false }
        return drawingSteps > floor && notesInView
    }

    /// ⇧⌘Z puts back what ⌘Z took off the drawing — the ink's strokes —
    /// until the text is typed in. When the drawing has nothing to put
    /// back it goes on to the text (the Redo item).
    var inkOwnsRedo: Bool { inkFloor != nil && notesInView }

    /// The notes pane is on screen.
    private var notesInView: Bool { showEditor && !cameraFullWindow }

    /// The tablet's page was the last thing written on — by the pen, or by
    /// its own undo, redo and clear — and nothing in the note has changed
    /// since. Not published: only the Undo item reads it, when pressed.
    private(set) var pageWrittenLast = false
    func pageWritten() { pageWrittenLast = true }
    /// The note's text or its drawing changed: the last thing done is the
    /// note's again.
    func notebookChanged() { if pageWrittenLast { pageWrittenLast = false } }

    /// The page's paper changed from `old`: INK THE CHANGE LEAVES
    /// UNREADABLE BECOMES THE PAPER'S OWN (`PageTheme.ink(_:after:)`) —
    /// chalk on the board, black back on white — and a colour picked on
    /// purpose stays as it was picked, through the same paper picked again
    /// or another white one.
    func pagePaperChanged(from old: PageTheme, to theme: PageTheme) {
        let ink = theme.ink(pageInkHex, after: old)
        if ink != pageInkHex { pageInkHex = ink }
    }

    /// ⌘Z TAKES BACK THE LAST STROKE ON THE PAGE while the page is what
    /// was written on last. The page has no keyboard focus of its own —
    /// the pen is in one hand and ⌘Z under the other — and left to the
    /// focus, ⌘Z after a stroke on the tablet undid the TYPING in the note
    /// instead. Asked before `drawingOwnsUndo`: the page is the newer.
    /// Only while the page can be SEEN — an undo nobody can watch happen
    /// is a stroke lost.
    var pageOwnsUndo: Bool {
        pageWrittenLast && inputSource == .tablet && (showCamera || cameraFullWindow)
    }

    /// True while a block in the preview is open for editing. The bar's
    /// buttons work on that block, so they are live on that side too.
    @Published var blockEditing = false

    /// The toolbar's handle on the live NSTextView.
    let editor = EditorBridge()

    static let presetColors = ["#F2542D", "#F5B700", "#2FBF71", "#2D7DD2", "#8E44AD", "#1C1C1E"]

    private let defaults: UserDefaults
    private enum Keys {
        static let showSidebar = "showSidebar"
        static let showEditor = "showEditor"
        static let showCamera = "showCamera"
        static let penWidth = "penWidth"
        static let cameraRotation = "cameraRotation"
        static let tabletQuarterTurns = "tabletQuarterTurns"
        static let tabletTarget = "tabletTarget"
        static let notebookScale = "notebookScale"
        static let penColorHex = "penColorHex"
        static let penTool = "penTool"
        static let pageInkTool = "pageInkTool"
        static let pageInkHex = "pageInkHex"
        static let pageInkWidth = "pageInkWidth"
        static let canvasMode = "canvasMode"
        static let cameraZoom = "cameraZoom"
        static let cameraAspect = "cameraAspect"
        static let evaluator = "evaluator"
        static let bulletStyle = "bulletStyle"
        static let codeLanguage = "codeLanguage"
        static let collapsedToolGroups = "collapsedToolGroups"
        static let showMarkers = "showMarkers"
        static let textFamily = "textFamily"
        static let textSize = "textSize"
        static let textColorHex = "textColorHex"
        static let textApplyFamily = "textApplyFamily"
        static let textApplySize = "textApplySize"
        static let textApplyColor = "textApplyColor"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showSidebar = defaults.object(forKey: Keys.showSidebar) as? Bool ?? true
        // BOTH PANES, EVERY LAUNCH (Sean, 2026-09-19: "default video always
        // to side by side"). Putting a pane away is a thing you do for a
        // minute, not a setting — and a launch that came up with the video
        // hidden left him hunting for the way back. Still written down, so
        // nothing else has to change; simply not read at startup.
        showEditor = true
        showCamera = true
        penWidth = defaults.object(forKey: Keys.penWidth) as? Double ?? 3
        cameraRotation = defaults.object(forKey: Keys.cameraRotation) as? Int ?? 0
        tabletQuarterTurns = TabletMapping.turns(defaults.object(forKey: Keys.tabletQuarterTurns) as? Int ?? 1)
        // A target this build does not know is the page.
        tabletTarget = TabletTarget(rawValue: defaults.string(forKey: Keys.tabletTarget) ?? "") ?? .page
        notebookScale = NotebookScale(rawValue: defaults.string(forKey: Keys.notebookScale) ?? "") ?? .fit
        cameraAspect = CameraAspect(rawValue: defaults.string(forKey: Keys.cameraAspect) ?? "") ?? .free
        evaluator = Evaluator(rawValue: defaults.string(forKey: Keys.evaluator) ?? "") ?? .wolfram
        penColorHex = defaults.string(forKey: Keys.penColorHex) ?? Self.presetColors[0]
        // A tool this build does not know is the pen, as it is on a stroke.
        penTool = InkTool(rawValue: defaults.string(forKey: Keys.penTool) ?? "") ?? .pen
        pageInkTool = InkTool(rawValue: defaults.string(forKey: Keys.pageInkTool) ?? "") ?? .pen
        pageInkHex = defaults.string(forKey: Keys.pageInkHex) ?? PageTheme.plain.defaultInk
        pageInkWidth = defaults.object(forKey: Keys.pageInkWidth) as? Double ?? 3
        // A launch comes up in whichever mode it was left in, and the
        // footer says which one that is — a pane that swallows clicks
        // with nothing on screen to say why is the trap the hidden video
        // pane was (Sean, 2026-09-19).
        let remembered = CanvasMode(rawValue: defaults.string(forKey: Keys.canvasMode) ?? "") ?? .cursor
        canvasMode = remembered
        // A launch starts on the markdown view and the pen is drawn on the
        // rendered page only (`showRenderedPage`): the two may not disagree.
        if remembered != .cursor { mode = .preview }
        if let box = defaults.array(forKey: Keys.cameraZoom) as? [Double], box.count == 4 {
            cameraZoom = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
        } else {
            cameraZoom = nil
        }
        bulletStyle = MarkdownFormatting.ListStyle(rawValue: defaults.string(forKey: Keys.bulletStyle) ?? "") ?? .dots
        codeLanguage = CodeLanguage(rawValue: defaults.string(forKey: Keys.codeLanguage) ?? "") ?? .plain
        collapsedToolGroups = Set(defaults.stringArray(forKey: Keys.collapsedToolGroups) ?? [])
        // The markdown pane shows the markdown: that is what it is FOR,
        // and the rendered-and-editable side is the other button (Sean,
        // 2026-09-19). ⌥⌘M still hides them for anyone who wants the
        // source rendered in place.
        showMarkers = defaults.object(forKey: Keys.showMarkers) as? Bool ?? true
        textFamily = defaults.string(forKey: Keys.textFamily) ?? "System"
        textSize = defaults.object(forKey: Keys.textSize) as? Double ?? 15
        textColorHex = defaults.string(forKey: Keys.textColorHex) ?? Self.presetColors[3]
        textApplyFamily = defaults.object(forKey: Keys.textApplyFamily) as? Bool ?? false
        textApplySize = defaults.object(forKey: Keys.textApplySize) as? Bool ?? false
        textApplyColor = defaults.object(forKey: Keys.textApplyColor) as? Bool ?? true
    }

    /// What the T menu would write: only the parts that are ticked, and
    /// "System" means "no font-family at all", not a family called System.
    var spanStyle: MarkdownFormatting.SpanStyle {
        MarkdownFormatting.SpanStyle(
            family: (textApplyFamily && textFamily != "System") ? textFamily : nil,
            size: textApplySize ? textSize : nil,
            colorHex: textApplyColor ? textColorHex : nil)
    }

    var penColor: Color {
        get { Color(hex: penColorHex) ?? .orange }
        set { penColorHex = newValue.hexString }
    }

    /// Quarter turns, and only quarter turns — a video pane seven degrees off
    /// is a mistake, not a choice.
    func rotateCamera(by degrees: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            cameraRotation = ((cameraRotation + degrees) % 360 + 360) % 360
        }
    }

    /// On its side, so the preview's width and height swap.
    var cameraIsTurned: Bool { cameraRotation == 90 || cameraRotation == 270 }

    /// How the tablet sits, by name — THE ONE WRITER of the turn, from the
    /// one control for it in the page's corner (`TabletOrientationButton`).
    /// The way it already sits, picked again, publishes nothing, so nothing
    /// downstream turns.
    func orientTablet(_ orientation: TabletOrientation) {
        guard orientation.quarterTurns != tabletQuarterTurns else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            tabletQuarterTurns = orientation.quarterTurns
        }
    }

    /// How the tablet sits, as one of Wacom's four.
    var tabletOrientation: TabletOrientation { TabletOrientation(quarterTurns: tabletQuarterTurns) }

    /// The switch: write on the page, or on the notebook. PICKING THE
    /// NOTEBOOK BRINGS THE NOTES INTO VIEW — a pen writing in a note nobody
    /// can see writes nowhere, and the page's veil would be saying it was
    /// writing there. Going back to the page puts nothing away.
    func writeOn(_ target: TabletTarget) {
        if tabletTarget != target { tabletTarget = target }
        // The notebook is drawn on the rendered page only (`showRenderedPage`).
        if target == .notebook { showRenderedPage() }
        guard target == .notebook, !showEditor || cameraFullWindow else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            showEditor = true
            cameraFullWindow = false
        }
    }

    /// The tablet is the input and writes in the note.
    var tabletWritesInNotebook: Bool { inputSource == .tablet && tabletTarget == .notebook }

    /// What was picked in Input Devices decides the pane.
    func follow(tabletPicked: Bool) {
        let source = InputSource.of(tabletPicked: tabletPicked)
        if inputSource != source { inputSource = source }
    }

    func isCollapsed(_ group: ToolGroup) -> Bool { collapsedToolGroups.contains(group.rawValue) }

    func setCollapsed(_ group: ToolGroup, _ collapsed: Bool) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if collapsed { collapsedToolGroups.insert(group.rawValue) }
            else { collapsedToolGroups.remove(group.rawValue) }
        }
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() }
    }

    /// Either pane can be put away, but not both — an empty window has no way
    /// back, since the buttons that bring a pane back live on the panes.
    func toggleCameraPane() {
        withAnimation(.easeInOut(duration: 0.18)) {
            if showCamera { showCamera = false; showEditor = true; cameraFullWindow = false }
            else { showCamera = true }
        }
    }

    func toggleEditorPane() {
        withAnimation(.easeInOut(duration: 0.18)) {
            if showEditor { showEditor = false; showCamera = true } else { showEditor = true }
        }
    }

    /// THE PICTURE ON ITS OWN, filling the window (Sean, 2026-09-21:
    /// "doubleclick the camera to make the whole window the camera..
    /// double click again to exit and have a transparent x in the top
    /// left"). Two ways back, because a window that is nothing but a
    /// picture has to say how to leave it: the same double-click, and the
    /// × drawn over the top-left corner.
    ///
    /// NOT REMEMBERED ACROSS A LAUNCH, and that is the same rule the two
    /// panes follow ("BOTH PANES, EVERY LAUNCH"): coming up as nothing
    /// but a viewfinder is a window whose notes have vanished, and the
    /// answer being drawn on the picture is not good enough for the first
    /// second of a launch.
    @Published var cameraFullWindow = false

    func toggleCameraFullWindow() {
        withAnimation(.easeInOut(duration: 0.18)) {
            cameraFullWindow.toggle()
            // Filling the window with a pane that has been put away is a
            // black rectangle and no way out.
            if cameraFullWindow { showCamera = true }
        }
    }

    func toggleMode() {
        // The cursor goes with the note: read now, while the pane it is
        // in is still up (`PaneCaret`).
        editor.carryCaret()
        withAnimation(.easeInOut(duration: 0.15)) {
            mode = (mode == .editor) ? .preview : .editor
        }
        // The drawing belongs to the note and shows in both views, but it
        // is drawn on the rendered page only (`showRenderedPage`): coming
        // back to markdown puts every tool down, and going forward again
        // does not pick one up.
        if mode == .editor {
            blockEditing = false
            putToolsAway()
        }
    }
}
