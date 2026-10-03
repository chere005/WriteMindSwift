import SwiftUI

/// The left pane: the markdown editor or its preview, with the drawing layer
/// on top of whichever is showing.
struct EditorPane: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var appState: AppState
    /// Bumped by a click in the text, which is what tells the objects on the
    /// drawing layer to let go.
    @State private var textClicks = 0

    /// How far the source editor has scrolled: the drawing layer follows.
    @State private var scrollOffset: CGFloat = 0
    /// The two panes' frames for the drawing layer, and the way between.
    @StateObject private var frames = PaneFrames()
    /// Where the drawing cells are on the pane that is up, as it last told
    /// (`CellFrame`), and the one the caret is in — whose grip the layer
    /// shows.
    @State var drawingFrames: [CellFrame] = []
    @State private var caretDrawing: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Always there, even with nothing open (Sean, 2026-09-18): the +
            // tab is the way to a new note from here.
            TabBar()
            Divider()
            // Above the editor, so a tooltip hanging off the bar is drawn
            // over the text rather than under it.
            TopBar()
                .zIndex(2)
            Divider()
            if let pending = appState.pendingLink {
                LinkBanner(pending: pending)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let note = store.selectedNote {
                ZStack {
                    if appState.mode == .editor {
                        MarkdownTextView(text: $store.text, documentID: note.id,
                                         bridge: appState.editor,
                                         onLinkTrigger: { caret in beginLink(from: note, caret: caret) },
                                         onPasteImage: { store.pasteImage(from: $0) },
                                         onClick: { textClicks += 1 },
                                         cursor: appState.paneCursor,
                                         onScroll: { offset in
                                             scrollOffset = offset
                                             store.canvasScroll = offset
                                         },
                                         onTopCell: { store.topCell = $0 },
                                         topCell: store.topCell,
                                         collapsed: store.collapsedHere,
                                         onToggleSection: { store.toggleSection($0) },
                                         showMarkers: appState.showMarkers,
                                         // The seams are the notebook's, so
                                         // they are there only in cursor
                                         // mode (Sean, 2026-09-20: "cursor
                                         // only becomes a pen in the notes
                                         // pane in drawing mode!!!!!"); the
                                         // pen, the select marquee, the
                                         // arrow tool and a placement
                                         // waiting to land each have the
                                         // whole pane.
                                         seamsEnabled: !appState.canvasOwnsPane,
                                         drawingCells: drawingCells(of: note),
                                         onDrawingFrames: { told(drawingFrames: $0) },
                                         onDrawingCaret: { caretDrawing = $0 })
                    } else {
                        MarkdownPreview(markdown: $store.text,
                                        onFollow: { store.follow(destination: $0) },
                                        bridge: appState.editor,
                                        onEditingChanged: { appState.blockEditing = $0 },
                                        onScroll: { offset in
                                            scrollOffset = offset
                                            store.canvasScroll = offset
                                        },
                                        onClick: { textClicks += 1 },
                                        onTopCell: { store.topCell = $0 },
                                        topCell: store.topCell,
                                        onLayout: { frames.rendered = $0 },
                                        collapsed: store.collapsedHere,
                                        onToggleSection: { store.toggleSection($0) },
                                        // The same switch, off the same
                                        // expression: the two panes are
                                        // the same notebook.
                                        seamsEnabled: !appState.canvasOwnsPane,
                                        onPickEvaluator: { store.setEnvironment($0, of: $1) },
                                        runningCell: store.runningCell,
                                        drawingCells: drawingCells(of: note),
                                        onDrawingFrames: { told(drawingFrames: $0) },
                                        onDrawingCaret: { caretDrawing = $0 })
                            .id(note.id)
                    }
                    // The drawing belongs to the note, so it shows in both
                    // modes. In pen and select mode it takes the whole pane;
                    // in cursor mode it takes only the objects on it, and the
                    // text underneath gets everything else.
                    DrawingCanvas(layer: layerDrawing,
                                  mode: appState.canvasMode,
                                  color: appState.penColor,
                                  width: appState.penWidth,
                                  tool: appState.penTool,
                                  mediaDirectory: store.owningFolder(for: note.url),
                                  documentID: note.id,
                                  deselectToken: textClicks,
                                  onBeginChange: { store.beginDrawingChange() },
                                  onSize: { store.canvasSize = $0 },
                                  onCrop: { store.cropImage(id: $0, to: $1) },
                                  onReadText: { store.readText(in: $0) },
                                  onPasteImage: { store.pasteImage(from: $0) },
                                  connectActive: appState.connectActive,
                                  pendingLabelEdit: store.pendingLabelEdit,
                                  onLabelEditStarted: { store.pendingLabelEdit = nil },
                                  onSelectionChanged: { appState.canvasSelection = $0 },
                                  onUndo: { store.undoDrawing() },
                                  onRedo: { store.redoDrawing() },
                                  pageOwnsUndo: { appState.pageOwnsUndo },
                                  placing: appState.placing,
                                  onDisarm: { appState.placing = nil },
                                  onEscapePen: { appState.escapePen() },
                                  onEscapeBox: { TabletScribe.shared.box.key($0) == nil },
                                  tabletPicks: NotebookScribe.shared.picks.eraseToAnyPublisher(),
                                  // Both panes scroll their objects with
                                  // the text now, so a picture stays beside
                                  // what it was put beside.
                                  scrollOffset: scrollOffset,
                                  cells: $store.cells,
                                  cellFrames: CellFrame.forLayer(drawingFrames, rendered: appState.mode == .preview),
                                  litCell: caretDrawing,
                                  onCellTap: { appState.editor.focusDrawingCell($0) },
                                  onDock: { dock($0) },
                                  onMakeCell: { makeCell($0) },
                                  onCellChanged: { store.fitCell($0) },
                                  // Drawn with the keyboard still in the
                                  // text, so ⌘Z is the ink's until the next
                                  // keystroke — down to where the drawing
                                  // stood under it.
                                  onCursorInk: { appState.inkedNote(above: store.drawingSteps) })
                    // The tablet writing straight into the note: its live
                    // stroke, its marquee, and where it lands on the notes
                    // while the pen is near. Over the layer, taking no
                    // clicks, and nothing in it an NSView. Only over the
                    // rendered page: the notes are drawn on there and
                    // nowhere else (Sean, 2026-10-02: "only allow drawing in
                    // wysiwyg mode, both from wacom and from the pen cursor
                    // tool"), and with the layer away the funnel has no
                    // note on screen — the pen is a pointer, and the page
                    // says to bring the rendered one up (`TabletPane`).
                    if appState.mode == .preview {
                        NotebookTabletLayer(scrollOffset: scrollOffset)
                    }
                }
                .onAppear {
                    appState.editor.pasteImage = { store.pasteImage(from: $0) }
                    // Why a command did nothing — a code block asked for
                    // inside one — goes where the camera's notices go.
                    appState.editor.say = { store.notice($0) }
                    // A drawing cell duplicated gets a file of its own.
                    appState.editor.onFork = { store.copyCells($0) }
                    // How an evaluation's answer reaches the note: the
                    // bridge's own write, which takes no keyboard and
                    // moves no caret.
                    store.writeCell = { appState.editor.write($0) }
                    store.writeBar = { appState.editor.armBar(after: $0, in: store.text) }
                    // ⇧↩ runs the cell the caret is in, and only when
                    // that cell is an evaluation cell.
                    appState.editor.evaluatesHere = {
                        store.isEvaluationCell(appState.editor.caretCell())
                    }
                    appState.editor.runCell = {
                        store.runCell(appState.editor.caretCell())
                    }
                    // Pictures land under the caret while the source editor
                    // is up; the preview's blocks have their own text views.
                    store.caretAnchor = { appState.mode == .editor ? appState.editor.caretLineFrame() : nil }
                    // And whatever lands by its place on the pane — the
                    // middle of the window, the tablet's nib — lands in the
                    // frame the sidecar keeps, worked out from the note as
                    // it is now: it is about to be saved.
                    store.paneMapping = { [frames] in paneMapping(frames, exact: true) }
                    store.insertBelow = { text, y in
                        guard appState.mode == .editor else { return false }
                        appState.editor.insert(text, belowDocumentY: y)
                        return true
                    }
                }
                // The rendered page's cells belong to the page that
                // measured them: another note's, or a page about to be
                // built again, would map the layer through cells it does
                // not have. Until the page measures its own the layer is
                // shown in the stored frame. And the markdown pane's,
                // laid out on the last visit to the page, are of the note
                // as it was then.
                .onChange(of: appState.mode) { _, _ in forgetFrames() }
                .onChange(of: note.id) { _, _ in forgetFrames() }
                .onChange(of: store.pendingLinkInsertion) { _, range in
                    guard let range else { return }
                    appState.editor.select(range)
                    store.pendingLinkInsertion = nil
                }
                Divider()
                HStack {
                    Text(note.url.lastPathComponent)
                    if store.isCapturing {
                        ProgressView().controlSize(.mini)
                        Text("Reading the page…")
                    } else if let notice = store.captureNotice {
                        Text(notice).foregroundStyle(Color.accentColor).lineLimit(1)
                    }
                    Spacer()
                    // WHICH MODE, in the footer. A pane that swallows
                    // every click needs somewhere on screen that says why
                    // it does — and the mode is remembered across a launch,
                    // so the answer cannot be "you only just pressed it".
                    if appState.canvasMode != .cursor {
                        Label(appState.canvasMode.title, systemImage: appState.canvasMode.icon)
                            .foregroundStyle(Color.accentColor)
                    }
                    // And WHAT IS ARMED, for the same reason: a node or a
                    // line stays armed after it is drawn (Sean,
                    // 2026-10-02: "after drawing a rectangle dont exit
                    // rectangle mode.."), and every drag on the pane is
                    // then the shape's until it is put away.
                    if let placing = appState.placing {
                        Label(placing.footer, systemImage: placing.symbol)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                    if !store.drawing.isEmpty {
                        Text(store.drawing.items.count == 1 ? "1 object" : "\(store.drawing.items.count) objects")
                    }
                    Text(wordCount == 1 ? "1 word" : "\(wordCount) words")
                    if let saved = store.lastSaved {
                        Text("Saved \(saved, format: .dateTime.hour().minute())")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(.bar)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.pencil").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("No note open").font(.title3).foregroundStyle(.secondary)
                    Button("New Note  ⌘N") { store.createNote() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    /// The drawing as the layer works on it: the stored one in the
    /// markdown pane, and on the rendered page that one shown through the
    /// page's own cells, every change the layer makes going back the same
    /// way (`Drawing.shown`, `Drawing.stored`).
    var layerDrawing: Binding<Drawing> {
        guard appState.mode == .preview else { return $store.drawing }
        let frames = frames, store = store
        return Binding(
            get: {
                let size = store.canvasSize
                // Nothing to show is nothing to lay out for.
                guard !store.drawing.isEmpty else { return store.drawing }
                return frames.shown(store.drawing, through: paneMapping(frames), in: size)
            },
            set: { shown in
                let stored = frames.stored(shown, over: store.drawing, through: paneMapping(frames, exact: true),
                                           in: store.canvasSize)
                // Every write is a save: one that changes nothing is none.
                if stored != store.drawing { store.drawing = stored }
            })
    }

    /// From the stored frame to the pane on screen: the identity in the
    /// markdown pane, and through the two panes' cells on the rendered
    /// page — `exact` for a write (`PaneFrames.mapping`).
    private func paneMapping(_ frames: PaneFrames, exact: Bool = false) -> PaneMapping {
        guard appState.mode == .preview else { return .identity }
        return frames.mapping(text: store.text, size: store.canvasSize, showMarkers: appState.showMarkers,
                              collapsed: store.collapsedHere, cells: drawingCells(of: store.selectedNote),
                              exact: exact)
    }

    /// The note's drawing cells as the panes paint them.
    private func drawingCells(of note: Note?) -> DrawingCellsShown {
        DrawingCellsShown(looks: store.cellLooks, media: note.map { store.owningFolder(for: $0.url) })
    }

    /// The pane that is up told where its drawing cells are: the layer
    /// draws into them by it, and the tablet routes by it.
    private func told(drawingFrames: [CellFrame]) {
        self.drawingFrames = drawingFrames
        store.cellFrames = drawingFrames
    }

    /// Another note, or the other mode: nothing measured for the last one
    /// is this one's. NOT the cells' frames: this runs after the pane that
    /// has come up has told its own, and clearing them here left the layer
    /// with none — a stroke on a cell then floated over it instead of going
    /// in. A new pane tells its frames the first time it measures, even
    /// when it has no cell, so they are always the pane's that is up.
    private func forgetFrames() {
        frames.forget()
        caretDrawing = nil
    }

    /// The words in the note — and a drawing cell's line is not words.
    private var wordCount: Int {
        DrawingCells.prose(store.text).split { $0.isWhitespace || $0.isNewline }.count
    }

    private func beginLink(from note: Note, caret: Int) {
        withAnimation(.easeInOut(duration: 0.15)) {
            appState.pendingLink = AppState.PendingLink(
                sourceNoteID: note.id, sourceTitle: note.title, caret: caret)
        }
    }
}

/// THE TWO FRAMES THE DRAWING LAYER LIVES IN, and the way between them.
///
/// The sidecar keeps objects in the markdown pane's frame and the rendered
/// page shows them through a `PaneMapping` from that pane's cells to its
/// own. This holds what that needs, and pays for each piece once: the
/// rendered page's cells as it last measured them; the markdown pane's
/// cells for the same note, laid out offscreen
/// (`MarkdownTextView.cellBoxes(of:pane:showMarkers:collapsed:)`, a whole
/// TextKit layout, so kept until the note, the pane's width, the markers or
/// the folds change — a pane only made taller or shorter wraps no line
/// differently — and NEVER ON A KEYSTROKE OR A FRAME OF A RESIZE: styling a
/// long note is tens of milliseconds, so while the note is typed into or
/// the window dragged the cells laid out last are carried along
/// (`PaneMapping.shifted`) and laid out again once that stops; a position
/// about to be SAVED never waits for that, `exact`); and the last drawing
/// shown, so a drag's every frame is not the whole drawing mapped there
/// and back again.
@MainActor
final class PaneFrames: ObservableObject {
    /// How the markdown pane's cells are laid out for a note, in a pane,
    /// with its markers and folds.
    typealias Layout = @MainActor (_ text: String, _ pane: CGSize, _ showMarkers: Bool, _ collapsed: Set<String>,
                                   _ drawings: DrawingCellsShown)
        -> (cells: [CellSeams.Box], width: CGFloat, height: CGFloat)

    /// The rendered page's cells, or nil until it has measured them.
    @Published var rendered: [CellSeams.Box]?
    private let layout: Layout
    private var laidOut: LaidOut?
    private var relayout: DispatchWorkItem?
    private var last: (stored: Drawing, mapping: PaneMapping, size: CGSize, shown: Drawing)?

    /// The markdown pane's cells as last laid out.
    private struct LaidOut {
        /// For this text, in a pane this wide, with these markers and folds
        /// — and drawing cells this big, which take the room they take.
        var text: String
        var pane: CGFloat
        var markers: Bool
        var folds: Set<String>
        var footprints: [UUID: CGSize]
        var cells: [CellSeams.Box]
        /// The width the text was laid out at, and how tall the note is at
        /// the pane's full width — which together say whether a pane of
        /// another height wraps it the same (`MarkdownTextView.textWidth`).
        var width: CGFloat
        var height: CGFloat
        /// False while the cells are the last layout carried along by an
        /// edit or a resize, until it is laid out again.
        var measured = true
    }

    init(layout: @escaping Layout = MarkdownTextView.cellBoxes(of:pane:showMarkers:collapsed:drawings:)) {
        self.layout = layout
    }

    /// Another note, or the other mode: nothing measured for the last one
    /// is this one's, and the markdown pane's cells laid out on the last
    /// visit to the page are of the note as it was then — carrying them
    /// along "by the edit" over everything typed since would be nonsense.
    func forget() {
        relayout?.cancel()
        relayout = nil
        laidOut = nil
        last = nil
        rendered = nil
    }

    /// From the markdown pane's frame to the rendered page's, for this
    /// note at this size — the identity until the page has measured.
    /// `exact` for a position about to be saved: worked out from the note
    /// as it is now, never from cells carried along.
    func mapping(text: String, size: CGSize, showMarkers: Bool, collapsed: Set<String>,
                 cells: DrawingCellsShown = DrawingCellsShown(), exact: Bool = false) -> PaneMapping {
        guard let rendered, size.width > 1 else { return .identity }
        let source = sourceCells(text: text, size: size, showMarkers: showMarkers, collapsed: collapsed,
                                 drawings: cells, exact: exact)
        // The page has a scroller beside it whenever the markdown pane
        // would — the same note, near enough the same height.
        return PaneMapping(from: source.cells, to: rendered,
                           fromColumn: MarkdownTextView.column(width: source.width),
                           toColumn: MarkdownPreview.column(width: source.width))
    }

    /// The markdown pane's cells for this note, laid out offscreen — or,
    /// while it is being typed into or the pane resized, the last layout
    /// carried along by the edit, with a fresh one coming once that stops.
    private func sourceCells(text: String, size: CGSize, showMarkers: Bool, collapsed: Set<String>,
                             drawings: DrawingCellsShown, exact: Bool) -> (cells: [CellSeams.Box], width: CGFloat) {
        if let laidOut, laidOut.markers == showMarkers, laidOut.folds == collapsed,
           laidOut.footprints == drawings.footprints {
            let wraps = laidOut.pane == size.width
                && MarkdownTextView.textWidth(pane: size, noteHeight: laidOut.height) == laidOut.width
            if wraps, laidOut.text == text, laidOut.measured || !exact { return (laidOut.cells, laidOut.width) }
            if !exact {
                let carried = laidOut.text == text
                    ? laidOut.cells : PaneMapping.shifted(laidOut.cells, from: laidOut.text, to: text)
                self.laidOut?.text = text
                self.laidOut?.cells = carried
                self.laidOut?.measured = false
                relayout?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.laidOut?.text == text else { return }
                    self.laidOut = self.layOut(text, size: size, showMarkers: showMarkers, collapsed: collapsed,
                                               drawings: drawings)
                    self.relayout = nil
                    self.objectWillChange.send()
                }
                relayout = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
                return (carried, laidOut.width)
            }
        }
        relayout?.cancel()
        relayout = nil
        let fresh = layOut(text, size: size, showMarkers: showMarkers, collapsed: collapsed, drawings: drawings)
        laidOut = fresh
        return (fresh.cells, fresh.width)
    }

    private func layOut(_ text: String, size: CGSize, showMarkers: Bool, collapsed: Set<String>,
                        drawings: DrawingCellsShown) -> LaidOut {
        let fresh = layout(text, size, showMarkers, collapsed, drawings)
        return LaidOut(text: text, pane: size.width, markers: showMarkers, folds: collapsed,
                       footprints: drawings.footprints, cells: fresh.cells, width: fresh.width, height: fresh.height)
    }

    /// The stored drawing as the pane on screen shows it.
    func shown(_ stored: Drawing, through mapping: PaneMapping, in size: CGSize) -> Drawing {
        guard !mapping.isIdentity else { return stored }
        if let last, last.stored == stored, last.mapping == mapping, last.size == size { return last.shown }
        let shown = stored.shown(through: mapping, in: size)
        last = (stored, mapping, size, shown)
        return shown
    }

    /// What the layer did on the pane on screen, as the sidecar keeps it.
    /// What it changed is told from what it was HANDED — the last drawing
    /// shown, through whichever cells — and goes back through `mapping`,
    /// the cells as they are now. What the layer wrote is what it is shown
    /// next, so a drag never sees its own move come back a rounding error
    /// away — unless it was handed the drawing through other cells, or a
    /// group was made, undone or lost a member, which moves where the
    /// rest are shown (`Drawing.stored`): then it is shown afresh.
    func stored(_ shown: Drawing, over stored: Drawing, through mapping: PaneMapping, in size: CGSize) -> Drawing {
        guard !mapping.isIdentity else { return shown }
        let before: Drawing, handedThrough: PaneMapping
        if let last, last.stored == stored, last.size == size {
            before = last.shown
            handedThrough = last.mapping
        } else {
            before = stored.shown(through: mapping, in: size)
            handedThrough = mapping
        }
        let result = stored.stored(shown, wasShown: before, through: mapping, in: size)
        let settled = handedThrough == mapping && !Self.regrouped(shown, from: before)
        last = settled ? (result, mapping, size, shown) : nil
        return result
    }

    /// Whether a write made a group, undid one or took a member out of one.
    private static func regrouped(_ shown: Drawing, from before: Drawing) -> Bool {
        let groups = Dictionary(shown.items.map { ($0.id, $0.group) }, uniquingKeysWith: { first, _ in first })
        return before.items.contains { old in
            guard let group = groups[old.id] else { return old.group != nil }
            return group != old.group
        }
    }
}
