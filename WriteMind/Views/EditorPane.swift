import SwiftUI

/// The left pane: the markdown editor or its preview, with the drawing layer
/// on top of whichever is showing.
struct EditorPane: View {
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var appState: AppState
    /// Bumped by a click in the text, which is what tells the objects on the
    /// drawing layer to let go.
    @State private var textClicks = 0

    /// How far the source editor has scrolled: the drawing layer follows.
    @State private var scrollOffset: CGFloat = 0
    /// The two panes' frames for the drawing layer, and the way between.
    @StateObject private var frames = PaneFrames()

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
                                         seamsEnabled: !appState.canvasOwnsPane)
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
                                        runningCell: store.runningCell)
                            .id(note.id)
                    }
                    // The drawing belongs to the note, so it shows in both
                    // modes. In pen and select mode it takes the whole pane;
                    // in cursor mode it takes only the objects on it, and the
                    // text underneath gets everything else.
                    DrawingCanvas(drawing: layerDrawing,
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
                                  scrollOffset: scrollOffset)
                    // The tablet writing straight into the note: its live
                    // stroke, its marquee, and where it lands on the notes
                    // while the pen is near. Over the layer, taking no
                    // clicks, and nothing in it an NSView.
                    NotebookTabletLayer(scrollOffset: scrollOffset)
                }
                .onAppear {
                    appState.editor.pasteImage = { store.pasteImage(from: $0) }
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
                    // frame the sidecar keeps.
                    store.paneMapping = { [frames] in paneMapping(frames) }
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
                // shown in the stored frame.
                .onChange(of: appState.mode) { _, _ in frames.rendered = nil }
                .onChange(of: note.id) { _, _ in frames.forget() }
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
    private var layerDrawing: Binding<Drawing> {
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
                let stored = frames.stored(shown, over: store.drawing, through: paneMapping(frames),
                                           in: store.canvasSize)
                // Every write is a save: one that changes nothing is none.
                if stored != store.drawing { store.drawing = stored }
            })
    }

    /// From the stored frame to the pane on screen: the identity in the
    /// markdown pane, and through the two panes' cells on the rendered
    /// page.
    private func paneMapping(_ frames: PaneFrames) -> PaneMapping {
        guard appState.mode == .preview else { return .identity }
        return frames.mapping(text: store.text, size: store.canvasSize, showMarkers: appState.showMarkers,
                              collapsed: store.collapsedHere)
    }

    private var wordCount: Int {
        store.text.split { $0.isWhitespace || $0.isNewline }.count
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
/// TextKit layout, so kept until the note, the size, the markers or the
/// folds change — and NEVER ON A KEYSTROKE: styling a long note is tens of
/// milliseconds, so while the note is typed into the cells laid out last
/// are carried along by the edit (`PaneMapping.shifted`) and laid out
/// again once the typing stops); and the last drawing shown, so a drag's
/// every frame is not the whole drawing mapped there and back again.
@MainActor
final class PaneFrames: ObservableObject {
    /// The rendered page's cells, or nil until it has measured them.
    @Published var rendered: [CellSeams.Box]?
    private var laidOut: (text: String, pane: CGSize, markers: Bool, folds: Set<String>,
                          cells: [CellSeams.Box], width: CGFloat)?
    private var relayout: DispatchWorkItem?
    private var last: (stored: Drawing, mapping: PaneMapping, size: CGSize, shown: Drawing)?

    /// Another note: nothing measured for the last one is this one's, and
    /// carrying its cells along "by the edit" would be nonsense.
    func forget() {
        relayout?.cancel()
        relayout = nil
        laidOut = nil
        last = nil
        rendered = nil
    }

    /// From the markdown pane's frame to the rendered page's, for this
    /// note at this size — the identity until the page has measured.
    func mapping(text: String, size: CGSize, showMarkers: Bool, collapsed: Set<String>) -> PaneMapping {
        guard let rendered, size.width > 1 else { return .identity }
        let source = sourceCells(text: text, size: size, showMarkers: showMarkers, collapsed: collapsed)
        // The page has a scroller beside it whenever the markdown pane
        // would — the same note, near enough the same height.
        return PaneMapping(from: source.cells, to: rendered,
                           fromColumn: MarkdownTextView.column(width: source.width),
                           toColumn: MarkdownPreview.column(width: source.width))
    }

    /// The markdown pane's cells for this note, laid out offscreen — or,
    /// while it is being typed into, the last layout carried along by the
    /// edit, with a fresh one coming once the typing stops.
    private func sourceCells(text: String, size: CGSize, showMarkers: Bool,
                             collapsed: Set<String>) -> (cells: [CellSeams.Box], width: CGFloat) {
        if let laidOut, laidOut.pane == size, laidOut.markers == showMarkers, laidOut.folds == collapsed {
            if laidOut.text == text { return (laidOut.cells, laidOut.width) }
            let carried = PaneMapping.shifted(laidOut.cells, from: laidOut.text, to: text)
            self.laidOut = (text, size, showMarkers, collapsed, carried, laidOut.width)
            relayout?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let now = self.laidOut, now.text == text, now.pane == size else { return }
                let fresh = MarkdownTextView.cellBoxes(of: text, pane: size, showMarkers: showMarkers,
                                                       collapsed: collapsed)
                self.laidOut = (text, size, showMarkers, collapsed, fresh.cells, fresh.width)
                self.objectWillChange.send()
            }
            relayout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            return (carried, laidOut.width)
        }
        let fresh = MarkdownTextView.cellBoxes(of: text, pane: size, showMarkers: showMarkers, collapsed: collapsed)
        laidOut = (text, size, showMarkers, collapsed, fresh.cells, fresh.width)
        return fresh
    }

    /// The stored drawing as the pane on screen shows it.
    func shown(_ stored: Drawing, through mapping: PaneMapping, in size: CGSize) -> Drawing {
        guard !mapping.isIdentity else { return stored }
        if let last, last.stored == stored, last.mapping == mapping, last.size == size { return last.shown }
        let shown = stored.shown(through: mapping, in: size)
        last = (stored, mapping, size, shown)
        return shown
    }

    /// What the layer did on the pane on screen, as the sidecar keeps it —
    /// and what the layer wrote is what it is shown next, so a drag never
    /// sees its own move come back a rounding error away.
    func stored(_ shown: Drawing, over stored: Drawing, through mapping: PaneMapping, in size: CGSize) -> Drawing {
        guard !mapping.isIdentity else { return shown }
        let before = self.shown(stored, through: mapping, in: size)
        let result = stored.stored(shown, wasShown: before, through: mapping, in: size)
        last = (result, mapping, size, shown)
        return result
    }
}
