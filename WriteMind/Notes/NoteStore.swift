import AppKit
import Combine
import CoreImage
import Foundation
import UniformTypeIdentifiers

/// Owns `~/Documents/WriteMind`: the note list, the text of the open note, and autosave.
@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    /// The sidebar's tree: one root per project folder, and inside each,
    /// sections are folders and so are subsections.
    @Published private(set) var roots: [NoteSection] = []
    /// The notes tabs that are open, in the order they were opened.
    @Published private(set) var openNoteIDs: [Note.ID] = []
    /// Where a new note goes — the section selected in the sidebar.
    @Published var selectedSectionID: NoteSection.ID?
    private var order = NoteOrder()
    @Published var selection: Note.ID?
    @Published var text: String = ""
    @Published var drawing = Drawing()
    /// THE OPEN NOTE'S DRAWING CELLS, by id (`DrawingCells`): each one's
    /// objects, in fractions of its own width. Loaded for every id in the
    /// text when the note opens, and for a new one the moment the text
    /// names it. Kept OUT of `drawing`, so Clear Drawing, `Drawing.isEmpty`
    /// and the sidecar's save and delete never see them; a cell nothing has
    /// been drawn in yet is not here at all.
    @Published var cells: [UUID: DrawingCell] = [:]
    /// What may be done with each cell's file (`DrawingCellState`).
    @Published private(set) var cellStates: [UUID: DrawingCellState] = [:]
    /// The pixels of each read-only cell: what it shows.
    private var cellPictures: [UUID: NSImage] = [:]
    /// The bytes last read from or written to each cell's file — the only
    /// bytes a write may go over (`DrawingCellStore.write`).
    private var cellKnown: [UUID: Data] = [:]
    /// What each cell's file holds, as last read or written: a cell equal
    /// to it has nothing to save.
    private var cellSaved: [UUID: DrawingCell] = [:]
    /// What each cell's file held when it was first read — what a step of
    /// the drawing taken before it was read restores it to (`restore`).
    private var cellLoaded: [UUID: DrawingCell] = [:]
    /// Where the cells are on the pane on screen, as it last laid them out:
    /// a tablet stroke begun in one lands there (`inkFromTablet`).
    var cellFrames: [CellFrame] = []
    /// What the drawing looked like before each change, newest last, and the
    /// states Undo has stepped back out of — the floating layer AND the
    /// cells (`DrawingState`). Whole snapshots, not strokes: an object that
    /// was moved, scaled or deleted has to come back too. Both are cleared
    /// when the note changes, so Undo never reaches into another note's
    /// work.
    @Published private(set) var drawingHistory: [DrawingState] = []
    @Published private(set) var drawingFuture: [DrawingState] = []
    /// A word about the last page capture, shown for a moment in the footer.
    @Published private(set) var captureNotice: String?
    /// A shape the canvas should open for typing as soon as it sees it —
    /// a text box just added. The canvas clears it once it has.
    @Published var pendingLabelEdit: UUID?
    @Published private(set) var isCapturing = false
    /// The size of the pane the drawing is on. Not published — it changes
    /// with every drag of the window divider, and nothing redraws for it; it
    /// is only there so a new picture can be sized to fit.
    var canvasSize: CGSize = .zero
    /// How far the editor has scrolled, so a new object lands in view.
    var canvasScroll: CGFloat = 0
    /// The place at the top of the window: the cell, by the character
    /// offset it starts at, and how far into it (`CellPlace`). The two
    /// sides lay the same note out at different heights, so a scroll
    /// POSITION does not carry across a switch between them; the place
    /// does (Sean, 2026-09-19: "positions stay the same in markdown and
    /// wysiwyg mode"; 2026-10-02: "preserve the position of things as much
    /// as possible"). Whichever pane comes up puts it back at the top. It
    /// is the open note's: another note opens at its own top, and an edit
    /// above the place moves it with the cell it names.
    var topCell: CellPlace = .top
    /// From the frame the sidecar keeps to the pane on screen
    /// (`PaneMapping`) — the identity in the markdown pane. Set by the
    /// editor pane; everything put on the layer by a place on the pane —
    /// the middle of the window, a capture's landing, the tablet's nib —
    /// goes through it on the way in (`landed`), and so does a crop. It is
    /// the note as it is now, never cells carried along by an edit: what
    /// goes through it is saved.
    var paneMapping: () -> PaneMapping = { .identity }
    /// Where the caret's line is, in the pane's document coordinates — set
    /// by the editor pane, nil while the source editor is not up.
    var caretAnchor: (() -> CGRect?)?
    /// Puts text into the note under a picture (its bottom edge, in document
    /// points). Returns false when there is no editor to do it, and the
    /// text is appended instead.
    var insertBelow: ((String, CGFloat) -> Bool)?

    /// The words in a picture, read and put into the note under it (Sean,
    /// 2026-09-18). Vision runs off the main thread; the insertion is back
    /// on it.
    func readText(in id: UUID) {
        guard let note = selectedNote, let item = drawing[id: id], case .image(let picture) = item,
              !isCapturing,
              let loaded = DrawingStore.loadImage(picture.file, in: owningFolder(for: note.url)),
              let cgImage = loaded.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        let box = item.bounds(in: paneSize)
        let bottom = box.maxY
        isCapturing = true
        Task {
            let reading = await Task.detached(priority: .userInitiated) {
                TextRecognition.read(cgImage)
            }.value
            isCapturing = false
            // A sketched flow chart comes in as real nodes and arrows,
            // under the picture it was read from (Sean, 2026-09-19).
            let chart = flowChart(from: reading, under: box)
            let lines = reading.lines
            guard !lines.isEmpty else {
                notice(chart.isEmpty ? "No text could be read in that picture."
                                     : "Brought the flow chart in under the picture.")
                return
            }
            let read = lines.joined(separator: "\n")
            if insertBelow?(read, bottom) != true {
                text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + read + "\n"
            }
            // The picture STAYS — reading it is not a conversion (Sean,
            // 2026-09-19: "converting an image or drawing or drawing pulled
            // from an image to text should not replace the object itself,
            // but insert the text underneath it"). ⌘Z takes the words back
            // out; the drawing was never touched.
            _ = note
            let words = lines.count == 1 ? "Read 1 line into the note." : "Read \(lines.count) lines into the note."
            notice(chart.isEmpty ? words : words + " The flow chart came with it.")
        }
    }

    /// The chart a reading found, put on the layer under `box` — or
    /// nothing, which is what a page of prose gives.
    @discardableResult
    private func flowChart(from reading: TextRecognition.Reading, under box: CGRect) -> [CanvasItem] {
        guard let page = reading.page, paneSize.width > 1, paneSize.height > 1 else { return [] }
        let items = FlowChartReading.items(ink: page.marks.writingMask(),
                                           width: page.width, height: page.height,
                                           words: reading.words, in: paneSize,
                                           colorHex: "#1C1C1E", lineWidth: 2)
        guard !items.isEmpty else { return [] }
        // Under the picture, in a band of its own size — the same rule the
        // words follow.
        let landing = CGRect(x: box.minX, y: min(box.maxY + 12, paneSize.height - 40),
                             width: box.width, height: box.height)
        let placed = FlowChartReading.placed(items, into: landing, pane: paneSize)
        beginDrawingChange()
        drawing.items.append(contentsOf: placed)
        drawing.reconnect(in: paneSize)
        return placed
    }
    @Published private(set) var lastSaved: Date?

    /// Every folder in the project. The first is the primary — where a note
    /// goes when nothing else says otherwise, and what the hidden `.drawings`
    /// and `.writemind` folders sit beside for notes that live in it.
    @Published private(set) var folders: [URL]
    /// The primary folder. Kept as `directory` because it is what the folder
    /// menu, the watcher and the default target all mean.
    var directory: URL { folders.first ?? Self.defaultDirectory() }
    /// Set when the folder cannot be read or created — almost always macOS's
    /// Documents-folder permission, which the sidebar then offers a way out of.
    @Published private(set) var accessDenied = false

    private static let directoryKey = "notesDirectoryPath"
    private var isLoadingText = false
    private var saveTask: Task<Void, Never>?
    private var drawingSaveTask: Task<Void, Never>?
    private var folderWatcher: DispatchSourceFileSystemObject?
    private var cancellables: Set<AnyCancellable> = []

    /// `~/Documents/WriteMind`, unless the user picked somewhere else after a
    /// permission refusal — that choice is remembered.
    static func defaultDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: "WriteMind", directoryHint: .isDirectory)
    }

    init(directory: URL? = nil, folders: [URL]? = nil) {
        if let folders, !folders.isEmpty {
            self.folders = folders
        } else if let directory {
            self.folders = [directory]
        } else if TestHost.isActive {
            // The app hosting the unit suite: a scratch folder, so a test run
            // never opens ~/Documents — and never asks whether it may.
            self.folders = [TestHost.notesDirectory]
        } else if let saved = UserDefaults.standard.string(forKey: Self.directoryKey) {
            self.folders = [URL(fileURLWithPath: saved, isDirectory: true)]
        } else {
            self.folders = [Self.defaultDirectory()]
        }

        createDirectoryIfNeeded()
        reload()
        selection = notes.first?.id
        loadTextForSelection()
        startWatchingFolder()

        // @Published fires in willSet, so inside this sink `self.selection`
        // is still the OLD note. The flush saves that one; the load uses the
        // value the publisher handed us.
        $selection
            .removeDuplicates()
            .sink { [weak self] newSelection in
                guard let self else { return }
                self.flushPendingSave()
                self.topCell = .top
                self.loadText(for: newSelection)
                // Selecting a note opens its tab — there is no other way in.
                if let newSelection, !self.openNoteIDs.contains(newSelection) {
                    self.openNoteIDs.append(newSelection)
                }
            }
            .store(in: &cancellables)

        $text
            .dropFirst()
            .sink { [weak self] new in
                guard let self else { return }
                // In `willSet`: `self.text` is still the text before.
                self.topCell = self.topCell.shifted(from: self.text, to: new)
                self.scheduleSave()
                // A line that names a cell not read yet — ⌘0, a paste, a
                // duplicated cell — is read now.
                if !self.isLoadingText, let note = self.selectedNote { self.loadCells(named: new, besides: note.url) }
            }
            .store(in: &cancellables)

        $drawing
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, !self.isLoadingText else { return }
                self.layerChanged = true
                self.scheduleDrawingSave()
            }
            .store(in: &cancellables)

        $cells
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleDrawingSave() }
            .store(in: &cancellables)
    }

    var selectedNote: Note? { notes.first { $0.id == selection } }

    // MARK: - Folder

    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            accessDenied = false
        } catch {
            // A refused Documents grant lands here as EPERM, not as "missing".
            accessDenied = !FileManager.default.isWritableFile(atPath: directory.path)
            if accessDenied { NSLog("WriteMind: no access to \(directory.path): \(error)") }
        }
    }

    /// Swap the project's folders wholesale. Keeps the open note if its file
    /// is still inside one of them.
    /// Folders inside the project's folders that are kept out of the tree
    /// (standardised paths).
    @Published private(set) var excludedFolders: Set<String> = []

    /// Swap the project's folders wholesale — and, when given, which folders
    /// inside them stay hidden. Keeps the open note if its file is still
    /// inside one of them.
    func setFolders(_ newFolders: [URL], excluding: [URL]? = nil) {
        if let excluding { excludedFolders = Set(excluding.map(\.standardizedFileURL.path)) }
        flushPendingSave()
        folderWatcher?.cancel()
        folderWatcher = nil
        folders = newFolders.isEmpty ? [Self.defaultDirectory()] : newFolders
        let keep = selection
        reload()
        if let keep, notes.contains(where: { $0.id == keep }) {
            selection = keep
        } else {
            selection = openNoteIDs.first(where: { id in notes.contains { $0.id == id } }) ?? notes.first?.id
        }
        loadTextForSelection()
        startWatchingFolder()
    }

    func reload() {
        createDirectoryIfNeeded()
        var readable: [NoteSection] = []
        var anyDenied = false
        for folder in folders {
            guard FileManager.default.isReadableFile(atPath: folder.path) else { anyDenied = true; continue }
            let folderOrder = NoteOrder.load(in: folder)
            if folder == directory { order = folderOrder }
            readable.append(NoteTree.read(directory: folder, root: folder, order: folderOrder,
                                          excluding: excludedFolders))
        }
        accessDenied = anyDenied && readable.isEmpty
        roots = readable
        notes = readable.flatMap(\.allNotes)

        if let selection, !notes.contains(where: { $0.id == selection }) {
            self.selection = notes.first?.id
        }
        if let selectedSectionID, section(withID: selectedSectionID) == nil {
            self.selectedSectionID = nil
        }
        openNoteIDs.removeAll { id in !notes.contains { $0.id == id } }
    }

    /// The root the whole sidebar used to be. Kept for everything that means
    /// "the primary folder's tree".
    var root: NoteSection {
        roots.first ?? NoteSection(url: directory, name: "Notes", depth: 0, notes: [], sections: [])
    }

    var allSections: [NoteSection] { roots + roots.flatMap(\.allSections) }

    /// The section a new note belongs in: the one selected, else the one
    /// holding the open note, else the primary folder.
    var targetSection: NoteSection {
        if let selectedSectionID, let found = section(withID: selectedSectionID) { return found }
        if let note = selectedNote,
           let found = section(withURL: note.url.deletingLastPathComponent()) { return found }
        return root
    }

    func section(withID id: NoteSection.ID) -> NoteSection? {
        allSections.first { $0.id == id }
    }

    func section(withURL url: URL) -> NoteSection? {
        allSections.first { $0.url.standardizedFileURL == url.standardizedFileURL }
    }

    /// Which project folder a note lives under — where its drawing sidecar and
    /// its row order belong. The primary folder when nothing matches.
    func owningFolder(for url: URL) -> URL {
        let path = url.standardizedFileURL.path
        return folders.first { path.hasPrefix($0.standardizedFileURL.path + "/") } ?? directory
    }

    // MARK: - Tabs

    func openTab(_ id: Note.ID) {
        if !openNoteIDs.contains(id) { openNoteIDs.append(id) }
        selection = id
    }

    func closeTab(_ id: Note.ID) {
        guard let index = openNoteIDs.firstIndex(of: id) else { return }
        if selection == id { flushPendingSave() }
        openNoteIDs.remove(at: index)
        guard selection == id else { return }
        let next = openNoteIDs.indices.contains(index) ? openNoteIDs[index] : openNoteIDs.last
        selection = next
    }

    func closeOtherTabs(keeping id: Note.ID) {
        flushPendingSave()
        openNoteIDs = openNoteIDs.filter { $0 == id }
        selection = id
    }

    func restoreTabs(_ ids: [Note.ID], active: Note.ID?) {
        openNoteIDs = ids.filter { id in notes.contains { $0.id == id } }
        if let active, notes.contains(where: { $0.id == active }) {
            selection = active
            if !openNoteIDs.contains(active) { openNoteIDs.append(active) }
        }
        loadTextForSelection()
    }

    /// The way past a refused folder permission: a folder the user PICKS is
    /// granted to this app by macOS there and then, whatever TCC said before.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory.deletingLastPathComponent()
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder WriteMind keeps your notes in."
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        setDirectory(picked)
    }

    func useDefaultFolder() { setDirectory(Self.defaultDirectory()) }

    /// Replace the PRIMARY folder, keeping any others the project added.
    private func setDirectory(_ url: URL) {
        if url == Self.defaultDirectory() {
            UserDefaults.standard.removeObject(forKey: Self.directoryKey)
        } else {
            UserDefaults.standard.set(url.path, forKey: Self.directoryKey)
        }
        setFolders([url] + folders.dropFirst())
    }

    func revealFolderInFinder() {
        createDirectoryIfNeeded()
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    /// Reload the list when something else (Finder, another editor) touches the folder.
    private func startWatchingFolder() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let keepSelection = self.selection
            self.reload()
            if let keepSelection, self.notes.contains(where: { $0.id == keepSelection }) {
                self.selection = keepSelection
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        folderWatcher = source
    }

    // MARK: - Editing

    private func loadTextForSelection() { loadText(for: selection) }

    private func loadText(for id: Note.ID?) {
        isLoadingText = true
        defer { isLoadingText = false }
        drawingHistory.removeAll()
        drawingFuture.removeAll()
        drawingSteps = 0
        cells = [:]
        cellStates = [:]
        cellPictures = [:]
        cellKnown = [:]
        cellSaved = [:]
        cellLoaded = [:]
        cellFrames = []
        layerChanged = false
        guard let note = notes.first(where: { $0.id == id }) else {
            text = ""
            drawing = Drawing()
            onDisk = nil
            return
        }
        let read = try? String(contentsOf: note.url, encoding: .utf8)
        text = read ?? ""
        // What the file held when we took it. `saveNow` will not write
        // over anything else — see NoteWriting.
        onDisk = read
        drawing = DrawingStore.load(for: note.url, in: owningFolder(for: note.url))
        loadCells(named: text, besides: note.url)
    }

    /// Every cell `text` names that has not been read yet, read from its
    /// file beside the note (`DrawingCellStore.load`): drawn in when it is
    /// WriteMind's and readable whole, shown as its pixels when it is not,
    /// one line when iCloud has not downloaded it, and empty — the first
    /// change makes the file — when there is none.
    private func loadCells(named text: String, besides note: URL) {
        guard text.contains(DrawingCells.relativeFolder) else { return }
        let unread = DrawingCells.ids(in: text).filter { cellStates[$0] == nil }
        guard !unread.isEmpty else { return }
        var states = cellStates, read = cells
        for id in unread {
            let loaded = DrawingCellStore.load(id, besides: note)
            states[id] = loaded.state
            cellKnown[id] = loaded.known
            if let cell = loaded.cell {
                read[id] = cell
                cellSaved[id] = cell
                cellLoaded[id] = cell
            }
            if case .readOnly = loaded.state { cellPictures[id] = loaded.known.flatMap(NSImage.init(data:)) }
        }
        cellStates = states
        if read != cells { cells = read }
    }

    /// What each cell shows, for the panes and the PDF.
    var cellLooks: [UUID: DrawingCellLook] {
        var looks: [UUID: DrawingCellLook] = [:]
        for (id, state) in cellStates {
            looks[id] = DrawingCellLook(cell: cells[id], state: state, picture: cellPictures[id])
        }
        for (id, cell) in cells where looks[id] == nil { looks[id] = DrawingCellLook(cell: cell) }
        return looks
    }

    /// A cell drawn in, grown to keep its ink: content within a line of its
    /// bottom gets room under it, and what was moved past its sides or top
    /// is shifted back in (`DrawingCell.fitted`, `keptIn`). Part of the
    /// step that changed it, never a step of its own.
    func fitCell(_ id: UUID) {
        guard let cell = cells[id] else { return }
        let fitted = cell.keptIn().fitted(lineHeight: Double(MarkdownTextView.lineHeight))
        if fitted != cell { cells[id] = fitted }
    }

    /// Drawing cells DUPLICATED with the cell their lines are in: each copy
    /// gets a copy of its original's file — after anything not yet saved in
    /// the original is written, so the copy is the drawing as it is now.
    func copyCells(_ pairs: [(old: UUID, new: UUID)]) {
        guard let note = selectedNote, !pairs.isEmpty else { return }
        saveCellsNow()
        for pair in pairs { DrawingCellStore.copy(pair.old, to: pair.new, from: note.url, to: note.url) }
    }

    /// The bytes this app last read from the open note's file, or last
    /// wrote to it. Nil while no note is open.
    private var onDisk: String?

    // MARK: - Notebook sections

    /// Which sections are closed, per note (the note's path → the section
    /// keys). Kept here rather than in the text, because a fold is a view of
    /// the note, not a change to it (Sean, 2026-09-19: "make the sections
    /// grouped like wolfram/jupyter notebooks.. show the notebook grouping
    /// and collapsing on the side").
    @Published var collapsedSections: [String: Set<String>] = [:]

    /// The closed sections of the note that is open.
    var collapsedHere: Set<String> {
        guard let selection else { return [] }
        return collapsedSections[selection] ?? []
    }

    func toggleSection(_ key: String) {
        guard let selection else { return }
        var keys = collapsedSections[selection] ?? []
        if keys.contains(key) { keys.remove(key) } else { keys.insert(key) }
        collapsedSections[selection] = keys
    }

    func setSection(_ key: String, collapsed: Bool) {
        guard let selection else { return }
        var keys = collapsedSections[selection] ?? []
        if collapsed { keys.insert(key) } else { keys.remove(key) }
        collapsedSections[selection] = keys
    }

    /// Every section of the note that has a body, closed at once.
    func foldAllSections() {
        guard let selection else { return }
        collapsedSections[selection] = Set(NotebookOutline.sections(in: text)
            .filter(\.hasBody)
            .map(\.key))
    }

    func unfoldAllSections() {
        guard let selection else { return }
        collapsedSections[selection] = []
    }

    func setCollapsedSections(_ keys: [String: [String]]) {
        collapsedSections = keys.mapValues(Set.init)
    }

    var collapsedSectionsForSession: [String: [String]] {
        collapsedSections.compactMapValues { $0.isEmpty ? nil : Array($0).sorted() }
    }

    /// How many steps the drawing has been taken since the note was
    /// opened, less the ones taken back — a step begun, an undo, a redo —
    /// and NOT held to the sixty `drawingHistory` keeps, whose count stands
    /// still under a new step once it is full. What the tablet's claim on
    /// ⌘Z is measured against (`AppState.inkFloor`).
    private(set) var drawingSteps = 0

    var canUndoDrawing: Bool { !drawingHistory.isEmpty }
    var canRedoDrawing: Bool { !drawingFuture.isEmpty }

    /// Called BEFORE a change, not after it — the canvas calls this as a
    /// gesture begins, so what gets kept is the state the gesture is about to
    /// leave. A drag is one entry, however many frames it took.
    func beginDrawingChange() {
        drawingSteps += 1
        drawingHistory.append(DrawingState(layer: drawing, cells: cells))
        if drawingHistory.count > 60 { drawingHistory.removeFirst() }
        drawingFuture.removeAll()
    }

    /// True when there was something to step back to — the canvas asks so
    /// it can hand ⌘Z on to the text when the drawing has nothing to undo
    /// (Sean, 2026-09-19: "add undo when drawing").
    @discardableResult
    func undoDrawing() -> Bool {
        guard let previous = drawingHistory.popLast() else { return false }
        // Counted before the drawing changes: its change is told with the
        // count (`AppState.drawingChanged`).
        drawingSteps -= 1
        drawingFuture.append(DrawingState(layer: drawing, cells: cells))
        restore(previous)
        return true
    }

    @discardableResult
    func redoDrawing() -> Bool {
        guard let next = drawingFuture.popLast() else { return false }
        drawingSteps += 1
        drawingHistory.append(DrawingState(layer: drawing, cells: cells))
        restore(next)
        return true
    }

    /// A step of the drawing put back: the layer, and the cells. A cell the
    /// step has nothing of was not part of it — read after it was taken, or
    /// first drawn in after it — and goes back to what its file held when
    /// it was read, or EMPTY AT THE SIZE IT HAS: never out of the dictionary
    /// with its drawing still in the file, and never a file deleted
    /// (nothing under `_drawings/cells` ever is).
    private func restore(_ state: DrawingState) {
        var restored = state.cells
        for (id, cell) in cells where restored[id] == nil {
            restored[id] = cellLoaded[id] ?? DrawingCell(width: cell.width, aspect: cell.aspect, drawing: Drawing())
        }
        drawing = state.layer
        if restored != cells { cells = restored }
    }

    /// A stroke the tablet's pen wrote straight into the note (Notebook
    /// mode, `NotebookScribe`). ONE STEP BACK, taken as it LANDS — so ⌘Z
    /// takes the stroke, and one given up half-way (the target changed, the
    /// notes went) leaves no empty step behind it. False with no note open.
    ///
    /// BEGUN IN A DRAWING CELL, IT IS THE CELL'S: routed by its first point
    /// against the cells' frames on the pane, moved into the cell's own
    /// fractions point for point with every pressure kept
    /// (`CanvasSpace.rehome`), and the cell grows to keep it — the same
    /// step. Anywhere else it floats, as it always did.
    @discardableResult
    func inkFromTablet(_ stroke: Stroke) -> Bool {
        guard selectedNote != nil else { return false }
        beginDrawingChange()
        let pane = paneSize
        if let first = stroke.points.first,
           let frame = cellFrames.first(where: {
               $0.writable && $0.rect.contains(CGPoint(x: first.x * pane.width, y: first.y * pane.height))
           }) {
            var cell = cells[frame.id] ?? .empty(width: Double(frame.width))
            cell.drawing.items.append(CanvasSpace.rehome(.stroke(stroke), from: .floating(pane: pane),
                                                         to: .cell(frame)))
            cells[frame.id] = cell
            fitCell(frame.id)
            return true
        }
        drawing.items.append(contentsOf: landed([.stroke(stroke)]))
        return true
    }

    func clearDrawing() {
        guard !drawing.isEmpty else { return }
        beginDrawingChange()
        drawing = Drawing()
    }

    // MARK: - Pictures

    /// A picture from the Add Image button or the Open panel.
    @discardableResult
    func addImage(from url: URL) -> Bool {
        guard let note = selectedNote,
              let imported = DrawingStore.importImage(from: url, in: owningFolder(for: note.url))
        else { return false }
        place(imported)
        return true
    }

    /// A picture off the pasteboard — ⌘V in the editor lands here.
    @discardableResult
    func addImage(_ image: NSImage) -> Bool {
        guard let note = selectedNote,
              let imported = DrawingStore.importImage(image, in: owningFolder(for: note.url))
        else { return false }
        place(imported)
        return true
    }

    /// ⌘V in the editor with a picture on the pasteboard. A file URL is
    /// copied as it stands, so a JPEG stays a JPEG; raw pasteboard image data
    /// is written as a PNG. Anything else is left for the text view to paste.
    @discardableResult
    func pasteImage(from pasteboard: NSPasteboard = .general) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            let pictures = urls.filter {
                UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true
            }
            if !pictures.isEmpty {
                var added = false
                for url in pictures where addImage(from: url) { added = true }
                if added { return true }
            }
        }
        // Only when there is real image data — a copied PDF or file icon can
        // also become an NSImage, and swallowing that paste would be wrong.
        guard pasteboard.availableType(from: [.tiff, .png, .fileContents]) != nil,
              let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
        else {
            DebugLog.write("pasteImage: nothing pasteable as a picture, types=\((pasteboard.types ?? []).map(\.rawValue).joined(separator: ","))")
            return false
        }
        let added = addImage(image)
        DebugLog.write("pasteImage: picture \(NSStringFromSize(image.size)) added=\(added) noteOpen=\(selectedNote != nil)")
        return added
    }

    /// The page of the notebook on the camera, as ink on the drawing layer
    /// (Sean, 2026-09-18). The work runs off the main thread; the object is
    /// added, and the sidecar written, back on it.
    /// The words inside the box on the camera, straight into the note —
    /// no picture at all (Sean, 2026-09-19: "the ocr of the selection").
    func readCamera(frame: CIImage?, quarterTurns: Int, region: CGRect?) {
        guard selectedNote != nil, !isCapturing else { return }
        guard let frame else { notice("There is no camera picture to read."); return }
        guard let result = NotebookCapture.capture(.raw, from: frame, quarterTurns: quarterTurns,
                                                   colour: .black, rememberedRatio: nil, region: region),
              let cgImage = result.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { notice("There is nothing to read in that box."); return }
        readIntoNote(cgImage, anchor: caretAnchor?()?.maxY)
    }

    /// The words in a picture that is NOT on the layer — a box on the
    /// camera, a box on the tablet's page — read off the main thread and
    /// put into the note under the caret's line (`anchor`, document
    /// points), with a sketched chart beside them. One path for both, so
    /// the tablet's Text arrives exactly where the camera's does.
    private func readIntoNote(_ cgImage: CGImage, anchor: CGFloat?) {
        isCapturing = true
        Task {
            let reading = await Task.detached(priority: .userInitiated) {
                TextRecognition.read(cgImage)
            }.value
            isCapturing = false
            // The same for a box on the camera or the tablet's page: a
            // sketch in it arrives as a chart, placed where a capture
            // would have landed.
            let landing = CGRect(x: paneSize.width * 0.1, y: (anchor ?? 0) + 12,
                                 width: paneSize.width * 0.8, height: paneSize.height * 0.5)
            // The caret's line is a place on the pane; the chart is put
            // down in the frame the sidecar keeps.
            let under = paneMapping().inverse.point(CGPoint(x: landing.minX, y: landing.minY - 12))
            let chart = flowChart(from: reading, under: CGRect(x: under.x, y: under.y,
                                                               width: landing.width, height: 0))
            let lines = reading.lines
            guard !lines.isEmpty else {
                notice(chart.isEmpty ? "No text could be read in that box."
                                     : "Brought the flow chart in.")
                return
            }
            let read = lines.joined(separator: "\n")
            if insertBelow?(read, anchor ?? 0) != true {
                text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + read + "\n"
            }
            let words = lines.count == 1 ? "Read 1 line into the note." : "Read \(lines.count) lines into the note."
            notice(chart.isEmpty ? words : words + " The flow chart came with it.")
        }
    }

    func captureNotebook(frame: CIImage?, quarterTurns: Int, colour: NSColor,
                         mode: NotebookCapture.Mode = .ink, region: CGRect? = nil) {
        guard selectedNote != nil, !isCapturing else { return }
        guard let frame else { notice("There is no camera picture to take the page from."); return }
        isCapturing = true
        let remembered = UserDefaults.standard.object(forKey: Self.pageShapeKey) as? Double
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                NotebookCapture.capture(mode, from: frame, quarterTurns: quarterTurns, colour: colour,
                                        rememberedRatio: remembered, region: region)
            }.value
            isCapturing = false
            guard let result else {
                switch (mode, region == nil) {
                case (.ink, true):
                    notice("No writing found on the page. Move the notebook into the frame and try again.")
                case (.ink, false):
                    notice("No writing found in that section.")
                case (.page, true):
                    notice("No page found. Move the notebook into the frame and try again.")
                case (.page, false):
                    notice("That section is not on the page.")
                case (.raw, _):
                    notice("There is no camera picture to take.")
                }
                return
            }
            if result.pageFound { UserDefaults.standard.set(result.shape.ratio, forKey: Self.pageShapeKey) }
            if placeCapture(result, mode: mode) {
                notice(mode == .ink ? "The writing is in — drag it where it goes."
                                    : "The page is in — drag it where it goes.")
            }
        }
    }

    /// The shape of the notebook's pages, long side over short, learned from
    /// the first page captured so every page after it comes out the same size.
    private static let pageShapeKey = "notebookPageShape"

    /// Keep only the part of a picture inside `rect` (fractions of it,
    /// top-left origin). The kept part stays exactly where it was on the
    /// pane on screen: cropped as that pane shows the picture, and put back
    /// like anything the layer moves (`Drawing.stored`) — kept in place in
    /// the sidecar instead, on the rendered page it landed wherever the
    /// page's cells put its new corner. The rest of the picture is gone,
    /// and ⌘Z on the drawing layer brings it back.
    func cropImage(id: UUID, to rect: CGRect) {
        let mapping = paneMapping()
        let shown = drawing.shown(through: mapping, in: paneSize)
        guard let note = selectedNote,
              let index = shown.items.firstIndex(where: { $0.id == id }),
              case .image(let item) = shown.items[index],
              rect.width > 0.001, rect.height > 0.001,
              let cropped = DrawingStore.cropImage(item.file, to: rect, in: owningFolder(for: note.url))
        else { return }
        beginDrawingChange()
        var after = shown
        after.items[index] = .image(CanvasEdit.crop(item, to: rect, file: cropped.file,
                                                    aspect: cropped.aspect, in: paneSize))
        drawing = drawing.stored(after, wasShown: shown, through: mapping, in: paneSize)
        notice("Cropped — ⌘Z on the drawing layer brings the rest back.")
    }

    /// A capture is placed where it was on the page, at the page's scale —
    /// not at the size the picture happens to be.
    private func placeCapture(_ result: NotebookCapture.Result, mode: NotebookCapture.Mode) -> Bool {
        guard let note = selectedNote else { return false }
        let folder = owningFolder(for: note.url)
        // Traced writing goes in as a vector; a photograph, and writing too
        // faint to trace, fall back to the picture.
        let vector = result.vector.flatMap {
            DrawingStore.importVector($0, size: result.frame.size, in: folder)
        }
        guard let imported = vector ?? DrawingStore.importImage(result.image, in: folder,
                                                                jpegQuality: mode == .ink ? nil : 0.85)
        else { return false }
        let landing = pageScaleLanding(frame: result.frame, pageSize: result.pageSize, aspect: imported.aspect)
        beginDrawingChange()
        drawing.items.append(contentsOf: landed([.image(ImageItem(file: imported.file, center: landing.center,
                                                                  width: landing.width, aspect: imported.aspect))]))
        return true
    }

    /// WHERE SOMETHING CUT FROM A PAGE LANDS: at the page's scale
    /// (`NotebookCapture.placement` — a whole page would fill 0.9 of the
    /// pane, a part of it is that part of such a page) and under the
    /// caret's line when there is one, else where it sat on the page. The
    /// camera's captures and the tablet's page both come in through here,
    /// so a box of writing is the same size whichever of the two it came
    /// off. `frame` is the piece's box on its page and `pageSize` the page,
    /// in the same units; `aspect` is height over width. The centre is in
    /// fractions of the pane (document coordinates), the width a fraction
    /// of the pane's width.
    private func pageScaleLanding(frame: CGRect, pageSize: CGSize, aspect: Double) -> (center: CGPoint, width: Double) {
        let placement = NotebookCapture.placement(frame: frame, pageSize: pageSize, pane: paneSize, nudge: nudge)
        let widthPoints = placement.width * paneSize.width
        let (underCaret, atCaret) = placedCenter(width: widthPoints, height: widthPoints * aspect)
        let center = atCaret
            ? underCaret
            : CGPoint(x: placement.center.x, y: placement.center.y + canvasScroll / paneSize.height)
        return (center, placement.width)
    }

    // MARK: - The tablet's page

    /// What the box on the tablet's page brings into the note — the
    /// camera's three choices, made from ink that is already clean (Sean,
    /// 2026-10-02: "anything drawn can be selected and inserted"). `strokes`
    /// is the whole page and `box` the box on it, in page fractions;
    /// `pageSize` is the page in its own points (`TabletPage.size`), and
    /// `theme` and `millimetres` its paper, which only Image carries.
    /// False when nothing went in, with a word in the footer about why.
    @discardableResult
    func takeFromTablet(_ choice: TabletChoice, strokes: [Stroke], box: CGRect, pageSize: CGSize,
                        theme: PageTheme = .plain, millimetres: CGSize? = nil) -> Bool {
        guard let note = selectedNote, pageSize.width > 0, pageSize.height > 0 else { return false }
        switch choice {
        case .image:
            // The box as it is on the page, paper and all, as a PNG — the
            // picture path every other picture takes, at the capture's
            // scale.
            let region = TabletSelection.pagePoints(box, pageSize: pageSize)
            guard let picture = TabletRender.image(of: strokes, region: region, pageSize: pageSize, theme: theme,
                                                   millimetres: millimetres),
                  let imported = DrawingStore.importImage(DrawingStore.image(from: picture),
                                                          in: owningFolder(for: note.url))
            else { notice("That box is not on the page."); return false }
            let landing = pageScaleLanding(frame: region, pageSize: pageSize, aspect: imported.aspect)
            beginDrawingChange()
            drawing.items.append(contentsOf: landed([.image(ImageItem(file: imported.file, center: landing.center,
                                                                      width: landing.width,
                                                                      aspect: imported.aspect))]))
            notice("The page is in — drag it where it goes.")
            return true
        case .writing:
            // The strokes themselves, crisp at any size, pressure, tool and
            // colour kept: ONE group, ONE step back.
            let touched = TabletSelection.touched(strokes, by: box, pageSize: pageSize)
            guard let frame = TabletSelection.inkBounds(touched, pageSize: pageSize),
                  frame.width > 0, frame.height > 0
            else { notice("There is no writing in that box."); return false }
            let landing = pageScaleLanding(frame: frame, pageSize: pageSize, aspect: frame.height / frame.width)
            // A group of one is no group: ⌃G would read it as one to take
            // apart.
            let placed = TabletSelection.noteStrokes(touched, pageSize: pageSize, frame: frame,
                                                     center: landing.center, width: landing.width,
                                                     pane: paneSize, group: touched.count > 1 ? UUID() : nil)
            beginDrawingChange()
            drawing.items.append(contentsOf: landed(placed.map(CanvasItem.stroke)))
            notice("The writing is in — drag it where it goes.")
            return true
        case .text:
            // Rendered black on white and read — never through the camera's
            // capture, which would threshold clean ink a second time.
            guard !isCapturing else { return false }
            let touched = TabletSelection.touched(strokes, by: box, pageSize: pageSize)
            guard !touched.isEmpty, let ink = TabletRender.ink(of: touched, pageSize: pageSize)
            else { notice("There is no writing in that box."); return false }
            readIntoNote(ink, anchor: caretAnchor?()?.maxY)
            return true
        }
    }

    /// A line in the footer. Not private since 2026-09-21: an
    /// evaluation's refusals go here too, and they are raised by the
    /// menu command rather than by the store.
    /// THE CELL THAT IS RUNNING, by the offset it starts at — one child
    /// at a time, which is a limit and is written down as one. Never
    /// `isCapturing`: that one guards the camera's OCR and a page
    /// capture, and sharing it would cross-block them and print "Reading
    /// the page…" over an evaluation.
    @Published var runningCell: Int?
    /// How an answer reaches the note: `EditorPane` hands over the
    /// editor bridge's own write, which does not take the keyboard and
    /// does not move the caret.
    var writeCell: ((MarkdownFormatting.Edit) -> Void)?
    /// And where the bar goes once the answer is in.
    var writeBar: ((NSRange) -> Void)?

    func notice(_ text: String) {
        captureNotice = text
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if captureNotice == text { captureNotice = nil }
        }
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Pictures sit on the drawing layer — drag, scale and rotate them there."
        // A sheet on the window, so it can never open BEHIND the window — a
        // modal panel back there is a click that did nothing and an app that
        // stopped answering (Sean, 2026-09-18: "bringing in images is broken").
        let take: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls { self.addImage(from: url) }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: take)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            take(panel.runModal())
        }
    }

    /// Dropped in the middle of the pane, at a size that fits it, and nudged
    /// along a little each time so a second picture is not hidden by the first.
    private func place(_ imported: ImportedImage) {
        let pane = paneSize
        var width = min(imported.pixelWidth, pane.width * 0.6)
        var height = width * imported.aspect
        if height > pane.height * 0.6 {
            height = pane.height * 0.6
            width = imported.aspect > 0 ? height / imported.aspect : width
        }
        let (center, _) = placedCenter(width: width, height: height)
        beginDrawingChange()
        drawing.items.append(contentsOf: landed([.image(ImageItem(file: imported.file,
                                                                  center: center,
                                                                  width: width / pane.width,
                                                                  aspect: imported.aspect))]))
    }

    // MARK: - Shapes

    /// A text box, empty, handed straight to the canvas to be typed in.
    func addTextBox(colorHex: String) {
        guard selectedNote != nil else { return }
        beginDrawingChange()
        // A line tall, the same way it will be a line tall after the first
        // word is typed — so the card does not jump the moment it is used.
        let width = 0.25
        let box = ShapeItem(kind: .text, center: visibleCenter, width: width,
                            aspect: TextBoxStyle.aspect(for: "", boxWidth: width * paneSize.width),
                            colorHex: colorHex, lineWidth: 1)
        drawing.items.append(contentsOf: landed([.shape(box)]))
        pendingLabelEdit = box.id
    }

    /// A free arrow or line, lying across the middle of the pane.
    func addConnector(startHead: ConnectorItem.Head, endHead: ConnectorItem.Head,
                      line: ConnectorItem.LineStyle = .solid, colorHex: String, lineWidth: Double) {
        guard selectedNote != nil else { return }
        beginDrawingChange()
        let y = visibleCenter.y
        drawing.items.append(contentsOf: landed([.connector(ConnectorItem(
            start: CGPoint(x: 0.42 + nudge, y: y), end: CGPoint(x: 0.58 + nudge, y: y),
            startHead: startHead, endHead: endHead, line: line,
            colorHex: colorHex, lineWidth: min(max(lineWidth, 1.5), 6)))]))
    }

    /// The pane pictures are sized against — a plausible one before the
    /// canvas has reported its size.
    private var paneSize: CGSize {
        canvasSize.width > 40 && canvasSize.height > 40 ? canvasSize : CGSize(width: 900, height: 600)
    }

    /// A little along each time, so a second picture is not hidden by the first.
    private var nudge: Double { Double(drawing.images.count % 6) * 0.03 }

    /// Items placed by where they are on the pane on screen — the middle
    /// of the window, a capture's landing, the tablet's nib — into the
    /// frame the sidecar keeps: the rendered page's own cells back to the
    /// markdown pane's, so the picture dropped beside a paragraph there is
    /// beside it here.
    private func landed(_ items: [CanvasItem]) -> [CanvasItem] {
        let mapping = paneMapping()
        guard !mapping.isIdentity else { return items }
        return Drawing.carried(items, through: mapping.inverse, in: paneSize)
    }

    /// The middle of what is on screen, as fractions of the pane — the
    /// layer scrolls with the text, so "the middle" moves with the scroll.
    private var visibleCenter: CGPoint {
        let pane = paneSize
        return CGPoint(x: 0.5 + nudge, y: (pane.height * 0.5 + canvasScroll) / pane.height + nudge)
    }


    /// Where a new picture or capture goes: just under the caret's line,
    /// flush with the text (Sean, 2026-09-18: "placed where the cursor is
    /// and aligned with the text") — or the middle of what is on screen
    /// when there is no caret to go by. `width` and `height` in points;
    /// the flag says which of the two it was.
    ///
    /// One `gapHeight` under the line, the same seam that sits between two
    /// cells, so the landing and the seam can never drift apart. Nothing
    /// moves to make room: the object floats over the note and the note
    /// does not know it is there (Sean, 2026-09-20: "floating objects like
    /// images, drawing, text fields, etc completely separate from the
    /// cells").
    private func placedCenter(width: CGFloat, height: CGFloat) -> (center: CGPoint, atCaret: Bool) {
        let pane = paneSize
        guard let line = caretAnchor?() else { return (visibleCenter, false) }
        let x = min(line.minX + width / 2, max(width / 2, pane.width - width / 2))
        let y = line.maxY + MarkdownPreview.gapHeight + height / 2
        return (CGPoint(x: x / pane.width, y: y / pane.height), true)
    }

    private func scheduleDrawingSave() {
        guard !isLoadingText, selectedNote != nil else { return }
        drawingSaveTask?.cancel()
        drawingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.saveDrawingNow()
        }
    }

    /// Whether the floating layer has changed since its sidecar was
    /// written. The cells have files of their own, and a stroke in one is
    /// no reason to write the sidecar again.
    private var layerChanged = false

    private func saveDrawingNow() {
        guard let note = selectedNote else { return }
        if layerChanged {
            layerChanged = false
            DrawingStore.save(drawing, for: note.url, in: owningFolder(for: note.url))
        }
        saveCellsNow()
    }

    /// EVERY CELL THAT HAS CHANGED since its file was read or written, into
    /// its file — and only those, and only the writable ones. A cell put
    /// back by undo to nothing is written EMPTY at the size it last had: a
    /// file is never removed. A write the store refuses — another writer's
    /// bytes on disk, a placeholder — makes the cell read-only, shown as
    /// what was read, and the footer says why.
    private func saveCellsNow() {
        guard let note = selectedNote else { return }
        let media = owningFolder(for: note.url)
        for id in Set(cells.keys).union(cellSaved.keys) where cellStates[id] ?? .writable == .writable {
            let emptied = cellSaved[id].map { DrawingCell(width: $0.width, aspect: $0.aspect, drawing: Drawing()) }
            guard let wanted = cells[id] ?? emptied, wanted != cellSaved[id],
                  let rendition = DrawingCellPainter.rendition(wanted, media: media) else { continue }
            switch DrawingCellStore.write(wanted, rendition: rendition, id: id, besides: note.url, known: cellKnown[id]) {
            case .written(let bytes):
                cellKnown[id] = bytes
                cellSaved[id] = wanted
                if cellStates[id] != .writable { cellStates[id] = .writable }
            case .refused(let why):
                cellStates[id] = .readOnly(why)
                cellPictures[id] = cellKnown[id].flatMap(NSImage.init(data:))
                notice(why)
            }
        }
    }

    private func scheduleSave() {
        guard !isLoadingText, selectedNote != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func flushPendingSave() {
        if saveTask != nil {
            saveTask?.cancel()
            saveTask = nil
            saveNow()
        }
        if drawingSaveTask != nil {
            drawingSaveTask?.cancel()
            drawingSaveTask = nil
            saveDrawingNow()
        }
        // Deleting a picture cannot delete its file then and there — Undo has
        // to be able to bring it back. Leaving the note is when that stops
        // being true, so that is when the unreferenced ones go.
        for folder in folders { DrawingStore.pruneMedia(in: folder) }
    }

    private func saveNow() {
        guard let note = selectedNote else { return }
        let body = text
        // Somebody else may have written to this file since we read it —
        // a second instance of the app (the deploy smoke-launches one), a
        // script, another editor. Overwriting it takes their work away
        // without a word, which is how a note lost two cells on
        // 2026-09-20. The buffer is kept and the watcher brings the newer
        // file in; nothing is lost by not writing.
        let now = try? String(contentsOf: note.url, encoding: .utf8)
        guard NoteWriting.mayWrite(onDisk: now, known: onDisk) else {
            NSLog("WriteMind: \(note.url.lastPathComponent) changed underneath us — not overwriting it")
            notice("\(note.url.lastPathComponent) changed on disk, so it was not overwritten.")
            // Take the newer file as what is there, so the watcher's
            // reload is the thing that decides what happens next rather
            // than this refusing on every keystroke from here on.
            onDisk = now
            return
        }
        do {
            try body.write(to: note.url, atomically: true, encoding: .utf8)
            onDisk = body
            lastSaved = Date()
            refreshRow(for: note.url, contents: body)
        } catch {
            NSLog("WriteMind: failed to save \(note.url.lastPathComponent): \(error)")
        }
    }

    /// Update one row in place so saving does not reshuffle the list under the cursor.
    private func refreshRow(for url: URL, contents: String) {
        guard let index = notes.firstIndex(where: { $0.url == url }) else { return }
        notes[index] = Note.make(url: url, modified: Date(), contents: contents)
    }

    // MARK: - Links between notes

    /// Finish a `/link`: write an anchor into the note showing NOW (unless it
    /// is a heading, which is its own anchor), then go back to the note the
    /// `/link` was typed in and put the markdown link where the trigger was.
    ///
    /// Returns false when the target cannot be used — linking a note to
    /// itself, or a source note that has gone away.
    @discardableResult
    func completeLink(_ pending: AppState.PendingLink, targetSelection: NSRange) -> Bool {
        guard let target = selectedNote,
              let source = notes.first(where: { $0.id == pending.sourceNoteID }),
              target.id != source.id
        else { return false }

        flushPendingSave()

        let anchor = MarkdownLinking.anchor(in: text, at: targetSelection)
        if let rewritten = anchor.rewrittenText {
            text = rewritten
            flushPendingSave()
        }

        let markdown = MarkdownLinking.link(title: anchor.title,
                                            fileName: target.url.lastPathComponent,
                                            anchor: anchor.id)

        // The source is not the open note any more, so it is edited on disk
        // and then re-opened — the editor never shows a stale copy.
        guard var sourceText = try? String(contentsOf: source.url, encoding: .utf8) else { return false }
        guard let triggerRange = MarkdownLinking.triggerRange(in: sourceText, near: pending.caret) else { return false }
        sourceText = (sourceText as NSString).replacingCharacters(in: triggerRange, with: markdown)
        do {
            try sourceText.write(to: source.url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("WriteMind: could not write the link into \(source.url.lastPathComponent): \(error)")
            return false
        }

        reload()
        selection = source.id
        loadTextForSelection()
        pendingLinkInsertion = NSRange(location: triggerRange.location,
                                       length: (markdown as NSString).length)
        return true
    }

    /// Where the link just landed, so the editor can select it once.
    @Published var pendingLinkInsertion: NSRange?

    /// Open the note a link points at, and say where in it to land.
    /// `destination` is the `Note.md#anchor` from the markdown.
    @discardableResult
    func follow(destination: String) -> Bool {
        let parts = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let file = String(parts[0]).removingPercentEncoding ?? String(parts[0])
        guard !file.isEmpty else { return false }
        guard let note = notes.first(where: { $0.url.lastPathComponent == file })
                ?? notes.first(where: { $0.filename == file }) else { return false }

        flushPendingSave()
        selection = note.id
        loadTextForSelection()

        guard parts.count == 2, !parts[1].isEmpty else { return true }
        let anchor = String(parts[1])
        let ns = text as NSString
        for needle in ["id=\"\(anchor)\""] {
            let found = ns.range(of: needle)
            if found.location != NSNotFound {
                pendingLinkInsertion = ns.lineRange(for: found)
                return true
            }
        }
        // A heading slug has nothing written into the file; find the heading.
        for line in text.components(separatedBy: "\n") where MarkdownFormatting.headingLevel(of: line) != .body {
            if MarkdownLinking.slug(for: MarkdownLinking.title(forBlock: line)) == anchor {
                let found = ns.range(of: line)
                if found.location != NSNotFound { pendingLinkInsertion = found }
                return true
            }
        }
        return true
    }

    // MARK: - Note lifecycle

    // MARK: - Sections

    @discardableResult
    func createSection(named base: String = "New Section", in parent: NoteSection? = nil) -> NoteSection? {
        let folder = (parent ?? targetSection).url
        let url = NoteTree.uniqueURL(in: folder, base: base, extension: nil)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            NSLog("WriteMind: could not make a section: \(error)")
            return nil
        }
        appendToOrder(name: url.lastPathComponent, folder: folder)
        reload()
        // A new section is NOT selected. Selecting it silently moves where
        // the next new note lands, which is not what making a folder means
        // (Sean, 2026-09-19: "after adding a section it shouldn't be
        // selected").
        return section(withURL: url)
    }

    func rename(_ section: NoteSection, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != section.name, !section.isRoot else { return }
        flushPendingSave()
        let parent = section.url.deletingLastPathComponent()
        let destination = NoteTree.uniqueURL(in: parent, base: trimmed, extension: nil)
        do {
            try FileManager.default.moveItem(at: section.url, to: destination)
            renameInOrder(from: section.url.lastPathComponent, to: destination.lastPathComponent, folder: parent)
            reload()
            selectedSectionID = destination.path
        } catch {
            NSLog("WriteMind: could not rename that section: \(error)")
        }
    }

    /// Trashing a section trashes the notes in it — the same as in Finder,
    /// and recoverable there for the same reason.
    func delete(_ section: NoteSection) {
        guard !section.isRoot else { return }
        flushPendingSave()
        do {
            try FileManager.default.trashItem(at: section.url, resultingItemURL: nil)
            forgetInOrder(name: section.url.lastPathComponent,
                          folder: section.url.deletingLastPathComponent())
        } catch {
            NSLog("WriteMind: could not trash that section: \(error)")
        }
        if selectedSectionID == section.id { selectedSectionID = nil }
        reload()
    }

    // MARK: - Moving and duplicating

    /// Move a note into a section. A no-op when it is already there, and
    /// when the "section" is a note's `_drawings` (`NoteTree.isSection`).
    ///
    /// Its drawing cells' files are COPIED to `_drawings/cells` beside it
    /// in the new folder, where its lines already point; the originals stay
    /// where they were, so nothing is lost if the move is undone in Finder.
    @discardableResult
    func move(_ note: Note, to section: NoteSection) -> Bool {
        let from = note.url.deletingLastPathComponent()
        guard from.standardizedFileURL != section.url.standardizedFileURL,
              NoteTree.isSection(section.url) else { return false }
        flushPendingSave()
        let destination = NoteTree.uniqueURL(in: section.url,
                                             base: note.filename, extension: note.url.pathExtension)
        do {
            try FileManager.default.moveItem(at: note.url, to: destination)
            DrawingStore.move(from: note.url, in: owningFolder(for: note.url),
                              to: destination, in: owningFolder(for: destination))
            let moved = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
            for id in DrawingCells.ids(in: moved) {
                DrawingCellStore.copy(id, to: id, from: note.url, to: destination)
            }
            forgetInOrder(name: note.url.lastPathComponent, folder: from)
            appendToOrder(name: destination.lastPathComponent, folder: section.url)
            let wasOpen = selection == note.id
            reload()
            if wasOpen { selection = destination.path; loadTextForSelection() }
            return true
        } catch {
            NSLog("WriteMind: could not move that note: \(error)")
            return false
        }
    }

    /// Move a section inside another one, refusing to put it inside itself.
    @discardableResult
    func move(_ section: NoteSection, to target: NoteSection) -> Bool {
        guard !section.isRoot, NoteTree.isSection(target.url) else { return false }
        let from = section.url.deletingLastPathComponent()
        guard from.standardizedFileURL != target.url.standardizedFileURL else { return false }
        guard !target.url.standardizedFileURL.path.hasPrefix(section.url.standardizedFileURL.path + "/"),
              target.id != section.id else { return false }
        flushPendingSave()
        let destination = NoteTree.uniqueURL(in: target.url, base: section.name, extension: nil)
        do {
            try FileManager.default.moveItem(at: section.url, to: destination)
            forgetInOrder(name: section.url.lastPathComponent, folder: from)
            appendToOrder(name: destination.lastPathComponent, folder: target.url)
            reload()
            return true
        } catch {
            NSLog("WriteMind: could not move that section: \(error)")
            return false
        }
    }

    /// Drop a note onto a row: into that row's section if it is somewhere
    /// else, and then into that row's PLACE in the order. This is the whole
    /// of "drag to rearrange" — the move is a file move, the place is the
    /// order file, and a drag within one folder is only the second.
    @discardableResult
    func place(_ note: Note, before target: Note) -> Bool {
        guard note.id != target.id else { return false }
        let targetFolder = target.url.deletingLastPathComponent()
        var moving = note

        if note.url.deletingLastPathComponent().standardizedFileURL != targetFolder.standardizedFileURL {
            guard let section = section(withURL: targetFolder), move(note, to: section),
                  let moved = notes.first(where: {
                      $0.url.deletingLastPathComponent().standardizedFileURL == targetFolder.standardizedFileURL
                          && $0.filename.hasPrefix(note.filename)
                  })
            else { return false }
            moving = moved
        }

        let siblings = section(withURL: targetFolder)?.notes.map(\.url.lastPathComponent) ?? []
        var names = siblings
        names.removeAll { $0 == moving.url.lastPathComponent }
        let index = names.firstIndex(of: target.url.lastPathComponent) ?? names.count
        names.insert(moving.url.lastPathComponent, at: index)
        // Sections keep their own places in the same list.
        let sectionNames = section(withURL: targetFolder)?.sections.map(\.name) ?? []
        withOrder(for: targetFolder) { file, root in
            file.set(names + sectionNames, folder: targetFolder, root: root)
        }
        reload()
        return true
    }

    /// A copy of the note beside it. TWO NOTES NEVER SHARE A DRAWING CELL:
    /// the copy's cells get new ids and copies of their files, so drawing in
    /// one never draws in the other — a note with no cells is copied byte
    /// for byte, as it always was.
    @discardableResult
    func duplicate(_ note: Note) -> Note? {
        flushPendingSave()
        let folder = note.url.deletingLastPathComponent()
        let destination = NoteTree.uniqueURL(in: folder, base: note.filename + " copy",
                                             extension: note.url.pathExtension)
        do {
            let forked = (try? String(contentsOf: note.url, encoding: .utf8)).map { DrawingCells.forked($0) }
            if let forked, !forked.ids.isEmpty {
                for (old, new) in forked.ids {
                    DrawingCellStore.copy(old, to: new, from: note.url, to: destination)
                }
                try forked.markdown.write(to: destination, atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.copyItem(at: note.url, to: destination)
            }
            let folderRoot = owningFolder(for: note.url)
            let drawing = DrawingStore.load(for: note.url, in: folderRoot)
            if !drawing.isEmpty {
                DrawingStore.save(DrawingStore.copyingMedia(drawing, in: folderRoot),
                                  for: destination, in: folderRoot)
            }
            insertInOrder(name: destination.lastPathComponent,
                          after: note.url.lastPathComponent, folder: folder)
            reload()
            return notes.first { $0.url == destination }
        } catch {
            NSLog("WriteMind: could not duplicate that note: \(error)")
            return nil
        }
    }

    /// Put `names` in this order inside `folder` — what a drag within a
    /// section commits.
    func reorder(_ names: [String], in section: NoteSection) {
        withOrder(for: section.url) { file, root in
            file.set(names, folder: section.url, root: root)
        }
        reload()
    }

    /// Each project folder keeps its own order file, so a folder carries its
    /// arrangement with it into another project.
    private func withOrder(for folder: URL, _ change: (inout NoteOrder, URL) -> Void) {
        let root = owningFolder(for: folder)
        var file = NoteOrder.load(in: root)
        change(&file, root)
        file.save(in: root)
        if root == directory { order = file }
    }

    private func appendToOrder(name: String, folder: URL) {
        withOrder(for: folder) { file, root in
            var names = file.folders[NoteOrder.key(for: folder, in: root)] ?? []
            if !names.contains(name) { names.append(name) }
            file.set(names, folder: folder, root: root)
        }
    }

    private func insertInOrder(name: String, after other: String, folder: URL) {
        withOrder(for: folder) { file, root in
            var names = file.folders[NoteOrder.key(for: folder, in: root)] ?? []
            names.removeAll { $0 == name }
            if let index = names.firstIndex(of: other) {
                names.insert(name, at: names.index(after: index))
            } else {
                names.append(name)
            }
            file.set(names, folder: folder, root: root)
        }
    }

    private func renameInOrder(from old: String, to new: String, folder: URL) {
        withOrder(for: folder) { file, root in
            var names = file.folders[NoteOrder.key(for: folder, in: root)] ?? []
            if let index = names.firstIndex(of: old) { names[index] = new } else { names.append(new) }
            file.set(names, folder: folder, root: root)
        }
    }

    private func forgetInOrder(name: String, folder: URL) {
        withOrder(for: folder) { file, root in
            file.forget(name: name, folder: folder, root: root)
        }
    }

    // MARK: - Note lifecycle

    @discardableResult
    func createNote(named base: String = "Untitled") -> Note? {
        flushPendingSave()
        createDirectoryIfNeeded()
        let folder = targetSection.url
        let url = NoteTree.uniqueURL(in: folder, base: base, extension: "md")
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("WriteMind: failed to create note: \(error)")
            return nil
        }
        appendToOrder(name: url.lastPathComponent, folder: folder)
        reload()
        openTab(url.path)
        return notes.first { $0.url == url }
    }

    func rename(_ note: Note, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != note.filename else { return }
        flushPendingSave()
        let folder = note.url.deletingLastPathComponent()
        let destination = NoteTree.uniqueURL(in: folder, base: trimmed, extension: note.url.pathExtension)
        do {
            try FileManager.default.moveItem(at: note.url, to: destination)
            DrawingStore.rename(from: note.url, to: destination, in: owningFolder(for: note.url))
            renameInOrder(from: note.url.lastPathComponent, to: destination.lastPathComponent, folder: folder)
            reload()
            selection = destination.path
        } catch {
            NSLog("WriteMind: failed to rename note: \(error)")
        }
    }

    func delete(_ note: Note) {
        saveTask?.cancel()
        saveTask = nil
        drawingSaveTask?.cancel()
        drawingSaveTask = nil
        do {
            try FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
            DrawingStore.delete(for: note.url, in: owningFolder(for: note.url))
            forgetInOrder(name: note.url.lastPathComponent, folder: note.url.deletingLastPathComponent())
        } catch {
            NSLog("WriteMind: failed to trash note: \(error)")
        }
        let wasSelected = selection == note.id
        reload()
        if wasSelected { selection = notes.first?.id }
    }

}
