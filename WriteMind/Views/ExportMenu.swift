import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File ▸ Export… (⌘E) — the note on paper, or the project.
///
/// ONE COMMAND, AND THE FORMAT IS CHOSEN IN THE SAVE PANEL (Sean,
/// 2026-09-21: "export is either as pdf or as project (which is just the
/// directory structure).. output format is chosen in the save menu"). It
/// was a submenu with one item in it, which is a menu that exists to hold
/// the next thing; the next thing is here, and it is a popup in the panel
/// rather than a second item, because "where does it go" and "what is it"
/// are one question, asked once.
///
/// The popup is an ACCESSORY VIEW rather than the panel's own file-type
/// list: that list only labels a type the system knows, and a project file
/// is this app's own extension with no declaration anywhere — the
/// Info.plist is generated from build settings, which cannot carry a type
/// declaration. Two dozen lines of AppKit buy the words "PDF" and
/// "Project" instead of "writemind-project".
///
/// The menu bar is the ONLY place it lives: no button on the bar, no item
/// in the sidebar's Folder menu (Sean, 2026-09-19: "there should only be
/// one … button").
struct ExportMenu: Commands {
    @ObservedObject var store: NoteStore
    @ObservedObject var projects: ProjectStore
    /// How the markdown pane lays the note out — its markers — which is
    /// the frame the drawing's objects are kept in.
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export…") { export() }
                .shortcut(.export)
                .disabled(store.selectedNote == nil && store.folders.isEmpty)
        }
    }

    /// What can come out. A PDF is the note as it reads; a project is the
    /// folders and nothing else — no notes are copied, because the notes
    /// are already files and the project is only the shape they sit in.
    enum Format: CaseIterable, Equatable {
        case pdf
        case project

        var title: String {
            switch self {
            case .pdf: return "PDF"
            case .project: return "Project"
            }
        }

        var extensionName: String {
            switch self {
            case .pdf: return "pdf"
            case .project: return Project.fileExtension
            }
        }

        var message: String {
            switch self {
            case .pdf: return "Where the PDF goes."
            case .project: return "Where the project file goes — the folders, not the notes."
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        let chooser = ExportFormatChooser()
        // Nothing is offered that cannot be made: with no note open there
        // is no page to print.
        chooser.setFormats(store.selectedNote == nil ? [.project] : Format.allCases)
        panel.accessoryView = chooser.view
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        chooser.onChange = { format in
            panel.nameFieldStringValue = name(for: format)
            panel.message = format.message
        }
        chooser.onChange?(chooser.format)

        guard panel.runModal() == .OK, var url = panel.url else { return }
        // A name typed without one still gets the extension it chose.
        if url.pathExtension.isEmpty { url.appendPathExtension(chooser.format.extensionName) }
        switch chooser.format {
        case .pdf: writePDF(to: url)
        case .project: writeProject(to: url)
        }
    }

    private func name(for format: Format) -> String {
        switch format {
        case .pdf:
            return store.selectedNote.map { NoteExport.suggestedName(for: $0.url) } ?? "Note.pdf"
        case .project:
            return "\(projects.name).\(Format.project.extensionName)"
        }
    }

    /// The note as it is read, on paper (Sean, 2026-09-19: "export as pdf").
    private func writePDF(to url: URL) {
        guard let note = store.selectedNote else { return }
        // The text is taken from the editor rather than the disk: what is
        // on screen is what Sean means by "this note", debounce or no.
        guard let data = NoteExport.pdf(markdown: store.text,
                                        drawing: store.drawing,
                                        cells: DrawingCellsShown(looks: store.cellLooks,
                                                                 media: store.owningFolder(for: note.url)),
                                        media: store.owningFolder(for: note.url),
                                        pane: store.canvasSize,
                                        markers: appState.showMarkers,
                                        folds: store.collapsedHere) else {
            report("WriteMind could not make a PDF of this note.", url: url)
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            report(error.localizedDescription, url: url)
        }
    }

    /// The project: the folders that are in it and the ones kept out of
    /// it, and nothing else.
    ///
    /// NOT "Save Project As…", which is in the Project menu and moves the
    /// open project to a new file. An export writes a copy and leaves the
    /// session exactly where it was — which is what makes it safe to hand
    /// somebody the shape of a notebook without adopting their file.
    private func writeProject(to url: URL) {
        let project = Project(folders: store.folders.map(\.standardizedFileURL.path),
                              excluded: projects.excluded.map(\.standardizedFileURL.path))
        do {
            try project.save(to: url)
        } catch {
            report(error.localizedDescription, url: url)
        }
    }

    /// A failed export is worth a word — a file that silently did not
    /// appear is the worst of the three outcomes.
    private func report(_ message: String, url: URL) {
        let alert = NSAlert()
        alert.messageText = "Could not write “\(url.lastPathComponent)”"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// The "Format:" row under the save panel. A class, because a popup button
/// needs a target that outlives the line that made it.
final class ExportFormatChooser: NSObject {
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 48))

    var onChange: ((ExportMenu.Format) -> Void)?
    private(set) var formats: [ExportMenu.Format] = ExportMenu.Format.allCases

    var format: ExportMenu.Format {
        let index = popup.indexOfSelectedItem
        return index >= 0 && index < formats.count ? formats[index] : (formats.first ?? .pdf)
    }

    override init() {
        super.init()
        let label = NSTextField(labelWithString: "Format:")
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItems(withTitles: formats.map(\.title))
        popup.target = self
        popup.action = #selector(changed)
        view.addSubview(label)
        view.addSubview(popup)
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: popup.leadingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: popup.centerYAnchor),
            popup.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 30),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            popup.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// Set before the panel is shown; the list is rebuilt around it.
    func setFormats(_ formats: [ExportMenu.Format]) {
        guard !formats.isEmpty else { return }
        self.formats = formats
        popup.removeAllItems()
        popup.addItems(withTitles: formats.map(\.title))
    }

    @objc private func changed() { onChange?(format) }
}
