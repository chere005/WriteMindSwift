import SwiftUI

@main
struct WriteMindApp: App {
    @StateObject private var store = NoteStore()
    @StateObject private var appState = AppState()
    @StateObject private var camera = CameraController.shared
    @StateObject private var tablet = TabletController.shared
    @StateObject private var projects = ProjectStore()
    @State private var didRestoreSession = false

    init() {
        // EVERY PEN SAMPLE, NOT ONE A FRAME. AppKit coalesces mouse drags
        // by default, folding the samples that arrive between two
        // dispatches into one; a Wacom pen reports about 120 a second
        // only with this off (measured 2026-10-02), and the ink's shape
        // and pressure are drawn from exactly those samples. Once, at
        // launch, for the whole app — the mouse and the trackpad too, so
        // their legacy strokes now keep every drag sample as well (same
        // code, denser points; AGENTS.md, the legacy guarantee) — and AT
        // launch, not here: creating
        // `NSApplication.shared` puts coalescing back ON (measured: set
        // false, make the application, read true), and this init runs
        // before the application exists. The pen's pressure reader starts
        // at the same moment, for the same reason — a local monitor wants
        // an application to be running.
        guard Self.launchObserver == nil else { return }
        Self.launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            NSEvent.isMouseCoalescingEnabled = false
            PenSampleReader.shared.start()
        }
    }

    private static var launchObserver: NSObjectProtocol?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(appState)
                .environmentObject(camera)
                .environmentObject(tablet)
                .environmentObject(projects)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    guard !didRestoreSession else { return }
                    didRestoreSession = true
                    restoreSession()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification)) { _ in
                    cacheSession()
                }
                // The pane is the camera's or the tablet's by what was
                // picked, and by nothing else. And the samples' one consumer
                // is made the moment a tablet IS the input, whichever pane
                // is up — in Notebook mode the page's pane may never have
                // been shown, and samples nobody takes write nothing.
                .onReceive(tablet.$selectedTabletID) { picked in
                    appState.follow(tabletPicked: picked != nil)
                    if picked != nil { _ = TabletScribe.shared }
                }
                // Where the pen writes, and how the tablet is held, handed
                // to the funnel here and nowhere else: the page's pane and
                // the notes both read them, and either may be put away.
                .onReceive(appState.$tabletTarget) { tablet.input.aim(at: $0) }
                .onReceive(appState.$tabletQuarterTurns) { tablet.input.quarterTurns = $0 }
                // Typing in the note, or anything done on its layer, makes
                // the note the last thing written on again — ⌘Z goes back
                // to it from the tablet's page; typing makes ⌘Z the text's
                // again after the tablet wrote in the note, and the
                // drawing's steps say how far down its claim still reaches.
                .onReceive(store.$text) { _ in appState.noteTyped() }
                .onReceive(store.$drawing) { _ in appState.drawingChanged(steps: store.drawingSteps) }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.createNote() }
                    .shortcut(.newNote)
                Divider()
                Button("Close Tab") {
                    if let selection = store.selection { store.closeTab(selection) }
                }
                .shortcut(.closeTab)
                .disabled(store.selection == nil)
                Divider()
                Button("Open Notes Folder") { store.revealFolderInFinder() }
                    .shortcut(.openNotesFolder)
            }

            // ⌘S, THE KEY EVERY MAC APP HAS (Sean, 2026-09-21: "cmd s
            // for save"). The note is saved half a second after the last
            // keystroke and there was nothing to press; a person who has
            // typed something important presses ⌘S anyway, and an app
            // that answers nothing at all has not earned their trust.
            // It flushes what is pending — the note AND the drawing —
            // and `NoteStore.saveNow` still asks `NoteWriting.mayWrite`
            // first, so this cannot clobber another writer either.
            // AFTER that group, not replacing it: SwiftUI's `.saveItem`
            // group is where Close and Close All live, and replacing it
            // took both off the File menu (2026-09-21, spotted by
            // listing the menu after the fact — ⌘W still closed a tab,
            // so nothing looked wrong).
            CommandGroup(after: .saveItem) {
                Button("Save") { store.flushPendingSave() }
                    .shortcut(.save)
                    .disabled(store.selection == nil)
            }

            ExportMenu(store: store, projects: projects, appState: appState)

            ProjectMenu(store: store, projects: projects, cacheSession: cacheSession)

            CommandGroup(after: .sidebar) {
                Button(appState.showSidebar ? "Hide Notes Sidebar" : "Show Notes Sidebar") {
                    appState.toggleSidebar()
                }
                .shortcut(.toggleSidebar)

                // ⌘T, ⌘Y and ⌘P — the three the eye goes to (Sean,
                // 2026-09-21: "cmd t should be toggling markdown mode,
                // and cmd y should toggle video", after a first pass at
                // ⌘R and ⌘T). MOVED rather than added: ⇧⌘P and ⌃⌘C did
                // these two, and two keys for one action is two things to
                // remember and one of them always the wrong one.
                //
                // ⌘T is New Tab in most Mac apps, and this one has tabs —
                // but a new tab here IS a new note and ⌘N already makes
                // one (the + on the tab bar says so: "New note (⌘N)"), so
                // there is no second command for the key to shadow.
                Button(appState.mode == .editor ? "Show Markdown Preview" : "Show Markdown Editor") {
                    appState.toggleMode()
                }
                .shortcut(.toggleMode)

                // The video pane could once only be brought back from the
                // sidebar, which can itself be put away (Sean, 2026-09-19:
                // "what happened to the right pane with the camera view?").
                // ⌃⌘C did it from 2026-09-19; ⌘Y does it now.
                Button(appState.showCamera ? appState.inputSource.words.hide : appState.inputSource.words.show) {
                    appState.toggleCameraPane()
                }
                .shortcut(.toggleVideo)

                // The pen, which had no shortcut at all: the button on the
                // bar was the only way in and out of drawing.
                Button(appState.penActive ? "Stop Drawing" : "Draw") { appState.togglePen() }
                    .shortcut(.togglePen)

                // Where the TABLET's pen writes — the switch on the page's
                // bar, mirrored here as the pen above is, and with no key:
                // Esc in the notes is the notes' own (a seam, a block, a
                // link, held cells), and the mode is a long-lived one.
                Button(appState.tabletTarget == .page ? "Write on the Notebook with the Tablet"
                                                      : "Write on the Page with the Tablet") {
                    appState.writeOn(appState.tabletTarget == .page ? .notebook : .page)
                }
                .disabled(appState.inputSource != .tablet)

                // NO KEY on these two (Sean, 2026-09-21: "get rid of
                // ^cmd+e and opt+cmd+m"). The commands stay — the notes
                // pane comes back from the corner of the video, and the
                // markers are a setting somebody may want — but neither
                // is worth a chord.
                Button(appState.showEditor ? "Hide Notes Pane" : "Show Notes Pane") {
                    appState.toggleEditorPane()
                }

                Button(appState.showMarkers ? "Hide Markdown Markers" : "Show Markdown Markers") {
                    appState.showMarkers.toggle()
                }

                Divider()

                // FOLDING WHAT IS UNDER THE CELL YOU ARE IN, and not the
                // cell you are in (Sean, 2026-09-21: "collapse current
                // cell's subsections (or highlighted cells) is cmd+;").
                // ⌥⌘← and ⌥⌘→ folded the caret's OWN section, which takes
                // the line you are standing on off the screen; they are
                // gone, and this one key goes both ways because there is
                // no second key left to open them with.
                Button("Collapse Subsections") { collapseSubsections() }
                    .shortcut(.collapseSubsections)
                Button("Fold All Sections") { store.foldAllSections() }
                    .shortcut(.foldAllSections)
                Button("Unfold All Sections") { store.unfoldAllSections() }
                    .shortcut(.unfoldAllSections)
            }

            // ⌘Z ITSELF, not a monitor underneath it. The Edit menu's own
            // Undo went to the TEXT whatever had been done last (Sean,
            // 2026-09-19: "fix undo in drawing mode"). This item decides
            // where it goes and hands it to the responder chain when it is
            // not the drawing's. A LOCAL KEY MONITOR SEES THE KEY FIRST,
            // though — one that returns nil stops this item (measured
            // 2026-10-02) — so the drawing layer's, which takes ⌘Z for
            // itself while it owns undo, asks the page's claim the way
            // this item does (`DrawingCanvas.takesUndo`).
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    // The tablet's page first, while it was written on
                    // last (`AppState.pageOwnsUndo`).
                    if appState.pageOwnsUndo, TabletPage.shared.undo() { return }
                    if appState.drawingOwnsUndo, store.undoDrawing() { return }
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .shortcut(.undo)

                Button("Redo") {
                    if appState.pageOwnsUndo, TabletPage.shared.redo() { return }
                    if appState.drawingOwnsRedo, store.redoDrawing() { return }
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .shortcut(.redo)

                Divider()

                // And the drawing's own pair, whatever has the keyboard.
                // In the SAME group as the other two, not a group of its
                // own after them: `.commands` is a builder and takes ten
                // children, and ⌘S made an eleventh (2026-09-21).
                Button("Undo Drawing") { store.undoDrawing() }
                    .shortcut(.undoDrawing)
                    .disabled(!store.canUndoDrawing)
                Button("Redo Drawing") { store.redoDrawing() }
                    .shortcut(.redoDrawing)
                    .disabled(!store.canRedoDrawing)
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                // ⌘. as in a notebook: the selection grows a step at a time.
                Button("Expand Selection") { appState.editor.expandSelection() }
                    .shortcut(.expandSelection)
                Button("Select Next Occurrence") { appState.editor.selectNextOccurrence() }
                    .shortcut(.selectNextOccurrence)
                Button("Select All Occurrences") { appState.editor.selectAllOccurrences() }
                    .shortcut(.selectAllOccurrences)
            }

            // Every formatting shortcut lives HERE, not on a toolbar button
            // — a button inside a collapsed group is not in the view tree,
            // and a shortcut attached to it would stop working the moment
            // that section of the bar was put away (Sean, 2026-09-19: "each
            // section of the toolbar should be collapsable"). The menu bar
            // is also where a shortcut is discoverable.
            FormatMenu(appState: appState, store: store)
            InsertMenu(appState: appState, store: store)

            InputDevicesMenu(camera: camera, tablet: tablet, appState: appState)
        }
    }
}

extension WriteMindApp {
    /// ⌘; — fold away what is under the cells in play, and open them
    /// again when they are all already folded.
    ///
    /// The cells are whichever are held, or the one the caret is in; on
    /// the rendered page that comes through `EditorBridge`'s document
    /// hooks, so it is the same command in both panes.
    private func collapseSubsections() {
        var cells = appState.editor.selectedCells()
        if cells.isEmpty, let caret = appState.editor.caretCell() { cells = [caret] }
        let keys = NotebookOutline.subsections(of: cells, in: store.text)
        guard !keys.isEmpty else { return }
        let folding = NotebookOutline.folding(keys, collapsed: store.collapsedHere)
        for key in keys { store.setSection(key, collapsed: folding) }
    }

    /// Come back to the project that was open, the notes that were open in
    /// it, and the one that was in front — plus any text that had not reached
    /// disk. Sublime Text's hot exit, and the reason closing an unsaved
    /// project is safe.
    private func restoreSession() {
        if let path = ProjectStore.lastProjectPath() {
            projects.open(URL(fileURLWithPath: path))
        }
        let session = ProjectSession.load(forProjectAt: projects.fileURL?.path)

        var folders = projects.folders
        if folders.isEmpty, let cached = session?.folders, !cached.isEmpty {
            folders = cached.map { URL(fileURLWithPath: $0, isDirectory: true) }
            projects.adopt(folders: folders,
                           excluded: (session?.excluded ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) })
        }
        if folders.isEmpty {
            folders = [store.directory]
            projects.adopt(folders: folders)
        }
        store.setFolders(folders, excluding: projects.excluded)

        guard let session else { return }
        // Unsaved text first: restoring a tab loads the note from disk, and
        // the cached buffer is what should win over it.
        for (path, text) in session.unsavedBuffers where text != (try? String(contentsOfFile: path, encoding: .utf8)) {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        store.reload()
        store.restoreTabs(session.openNotePaths, active: session.activeNotePath)
        store.setCollapsedSections(session.collapsedSections)
    }

    /// Write the session down. Called on quit, and whenever a project closes.
    func cacheSession() {
        store.flushPendingSave()
        var session = ProjectSession()
        session.projectPath = projects.fileURL?.path
        session.folders = store.folders.map(\.path)
        session.excluded = projects.excluded.map(\.path)
        session.openNotePaths = store.openNoteIDs
        session.activeNotePath = store.selection
        session.collapsedSections = store.collapsedSectionsForSession
        session.save()
    }
}

/// The Format menu: the heading ladder, the marks a span can carry, lists,
/// code, indentation and moving a whole section.
struct FormatMenu: Commands {
    @ObservedObject var appState: AppState
    @ObservedObject var store: NoteStore

    private var editor: EditorBridge { appState.editor }

    var body: some Commands {
        CommandMenu("Format") {
            // ⌘1 title, ⌘2 chapter, ⌘3 author, ⌘4–⌘6 sections, ⌘7 body.
            ForEach(MarkdownFormatting.Heading.ladder) { level in
                Button(level.name) { editor.heading(level) }
                    .shortcut(.heading(level))
            }
            Divider()
            Button("Bold") { editor.bold() }.shortcut(.bold)
            Button("Italic") { editor.italic() }.shortcut(.italic)
            Button("Underline") { editor.underline() }.shortcut(.underline)
            Button("Strikethrough") { editor.strikethrough() }
                .shortcut(.strikethrough)
            Divider()
            Button("\(appState.bulletStyle.title) List") { editor.list(appState.bulletStyle) }
                .shortcut(.list)
            Button("Quote") { editor.quote() }.shortcut(.quote)
            Divider()
            Button("Decrease Indentation") { editor.outdent() }.shortcut(.outdent)
            Button("Increase Indentation") { editor.indent() }.shortcut(.indent)
            Divider()
            // The notebook's own two commands. ⌃D and ⌃M, not ⌘D and ⌘M:
            // ⌘D was already Select Next Occurrence (Sean, 2026-09-19:
            // "cmd d was already multi text selection... change make ctrl d
            // and ctrl m divide and merge"), and ⌘M is Minimise.
            Button("Split Cell") { editor.splitCell() }
                .shortcut(.splitCell)
                .disabled(store.selectedNote == nil)
            Button("Merge Cells") { editor.mergeCells() }
                .shortcut(.mergeCells)
                .disabled(store.selectedNote == nil)
            Divider()
            // A cell is a thing you can hold, the way a notebook's is
            // (Sean, 2026-09-20). ⌘D is Sublime's multi-cursor and stays
            // that way, so the cell commands take ⌃ keys.
            Button("Duplicate Cell") { editor.duplicateCell() }
                .shortcut(.duplicateCell)
                .disabled(store.selectedNote == nil)
            // NO KEY (Sean, 2026-09-21: "backspace is enough to delete
            // the selected cell so no need for ^+backspace"). ⌫ over a
            // held cell already takes it — `MarkdownPreview.cellKey` on
            // the rendered page, the text view's own delete in the
            // source — so ⌃⌫ was a second way to do what the obvious key
            // already did.
            Divider()

            // ⌘9 — AN EVALUATION CELL HERE: the cell the caret is in
            // becomes one, or a new one goes in after it (Sean,
            // 2026-09-21: "cmd+9 should start a new cell or turn the
            // existing cell to an evaluation cell"). Running one is ⇧↩,
            // which belongs to the cell and not to this menu — a menu
            // key equivalent would swallow shift-return everywhere.
            Button("Evaluation Cell") {
                // At a bar the cell is MADE THERE and that is the whole
                // of it; anywhere else the caret's own cell becomes one.
                guard !editor.evaluationCellAtBar(appState.evaluator) else { return }
                store.makeEvaluationCell(appState.evaluator, at: editor.caretCell())
            }
            .shortcut(.evaluationCell)
            .disabled(store.selectedNote == nil)

            Button("Delete Cell") { editor.deleteCell() }
                .disabled(store.selectedNote == nil)
            Button("Move Cell Up") { editor.moveCell(up: true) }
                .shortcut(.moveCellUp)
                .disabled(store.selectedNote == nil)
            Button("Move Cell Down") { editor.moveCell(up: false) }
                .shortcut(.moveCellDown)
                .disabled(store.selectedNote == nil)
            Divider()
            Button("Move Section Up") { editor.moveSection(up: true) }
                .shortcut(.moveSectionUp)
            Button("Move Section Down") { editor.moveSection(up: false) }
                .shortcut(.moveSectionDown)
        }
    }
}

/// The Insert menu: the things that go ON a note rather than change how it
/// reads — a picture, a box of words, a table, a block of code (Sean,
/// 2026-09-19: "the insert image should be in a menu bar entry under
/// insert").
struct InsertMenu: Commands {
    @ObservedObject var appState: AppState
    @ObservedObject var store: NoteStore

    var body: some Commands {
        CommandMenu("Insert") {
            // The same as the bar's: every tool put away, so the picture
            // or the box that arrives takes the next click.
            Button("Image…") {
                appState.putToolsAway()
                store.chooseImage()
            }
            .shortcut(.insertImage)
            .disabled(store.selectedNote == nil)

            Button("Text Box") {
                appState.putToolsAway()
                store.addTextBox(colorHex: appState.penColorHex)
            }
            .disabled(store.selectedNote == nil)

            Divider()

            Button("\(appState.codeLanguage == .plain ? "Code Block" : appState.codeLanguage.title + " Block")") {
                appState.editor.codeBlock(language: appState.codeLanguage.fence)
            }
            .shortcut(.codeBlock)
            .disabled(store.selectedNote == nil)
        }
    }
}

/// The Project menu: the folders a project is made of, and the file it can
/// be saved as.
struct ProjectMenu: Commands {
    @ObservedObject var store: NoteStore
    @ObservedObject var projects: ProjectStore
    let cacheSession: () -> Void

    var body: some Commands {
        CommandMenu("Project") {
            Text(projects.name + (projects.hasUnsavedProjectChanges ? " — edited" : ""))

            Divider()

            Button("Add Folder to Project…") {
                guard let folder = projects.chooseFolder(
                    message: "Add a folder of notes to “\(projects.name)”.") else { return }
                projects.addFolder(folder)
                store.setFolders(projects.folders, excluding: projects.excluded)
            }
            .shortcut(.addFolderToProject)

            Menu("Remove Folder") {
                ForEach(store.folders, id: \.path) { folder in
                    Button(folder.lastPathComponent) {
                        projects.removeFolder(folder)
                        store.setFolders(projects.folders, excluding: projects.excluded)
                    }
                    .disabled(store.folders.count <= 1)
                }
            }

            Divider()

            // ⇧⌘S, not ⌃⌘S: that one was registered TWICE — here and on
            // "Hide Notes Sidebar" in the View menu — and a key equivalent
            // claimed twice goes to whichever menu comes first in the bar,
            // so View won and this item could not be pressed from the
            // keyboard at all (found 2026-09-21 while checking what ⌘S
            // would collide with).
            Button("Save Project") { projects.save() }
                .shortcut(.saveProject)
            Button("Save Project As…") { projects.saveAs() }

            Divider()

            Button("Open Project…") {
                cacheSession()
                if projects.openWithPanel() { store.setFolders(projects.folders, excluding: projects.excluded) }
            }
            Button("New Project") {
                cacheSession()
                projects.newProject(startingAt: NoteStore.defaultDirectory())
                store.setFolders(projects.folders, excluding: projects.excluded)
            }
        }
    }
}

/// The "Input Devices" menu bar item: every camera the Mac can see, an off
/// switch, any Wacom tablet plugged in, and what SHAPE the picture is shown
/// at.
///
/// A TABLET IS PICKED HERE THE WAY A CAMERA IS (Sean, 2026-10-02: "wacom
/// should basically just be chosen as if it were an input display"): ticked
/// like one, and picking it turns the camera off and makes the pane the
/// page; picking a camera gives the pane back to the video. Both go through
/// `InputDevices`, which the picker in the pane uses too.
///
/// The shape lives here rather than in the Picture panel on the bar (Sean,
/// 2026-09-21: "aspect ratio control should be in the video input
/// dropdown"). It is a property of what you are pointing the camera at —
/// a page, a whiteboard, a screen — which is the same question this menu
/// already asks.
struct InputDevicesMenu: Commands {
    @ObservedObject var camera: CameraController
    @ObservedObject var tablet: TabletController
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("Input Devices") {
            if camera.devices.isEmpty {
                Text("No cameras found")
            } else {
                ForEach(camera.devices) { device in
                    Button {
                        InputDevices.pick(cameraID: device.id, cameras: camera, tablets: tablet)
                    } label: {
                        HStack {
                            Text(device.name)
                            if camera.selectedDeviceID == device.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Divider()

            Button("Turn Camera Off") { camera.turnOff() }
                .disabled(camera.selectedDeviceID == nil)

            // Under the cameras, and only when there is a tablet to say
            // anything about: a Mac with no Wacom on it has no tablets
            // section at all.
            if !tablet.tablets.isEmpty || tablet.isSelected {
                Divider()
                Text("Tablets")
                ForEach(tablet.tablets) { device in
                    Button {
                        InputDevices.pick(device, cameras: camera, tablets: tablet)
                    } label: {
                        HStack {
                            Text(device.name)
                            if tablet.selectedTabletID == device.id { Image(systemName: "checkmark") }
                        }
                    }
                }
                if tablet.isSelected, tablet.selectedTablet == nil {
                    Text("\(tablet.selectedName ?? "The tablet") — unplugged")
                }
                Button("Turn Tablet Off") { tablet.turnOff() }
                    .disabled(!tablet.isSelected)
            }

            Divider()

            // The viewfinder's shape. Ticked the way the cameras above
            // are, because it is the same kind of choice: one of a list,
            // and the one it is now.
            Menu("Aspect Ratio") {
                ForEach(CameraAspect.allCases) { choice in
                    Button {
                        appState.cameraAspect = choice
                    } label: {
                        HStack {
                            Text(choice == .free ? "Free — as the camera sends it" : choice.title)
                            if appState.cameraAspect == choice { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Button("Refresh Device List") { camera.refreshDevices() }
                .shortcut(.refreshDevices)
        }
    }
}
