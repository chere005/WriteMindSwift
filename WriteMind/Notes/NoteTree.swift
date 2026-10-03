import Foundation

/// A section in the sidebar IS a folder on disk — `~/Documents/WriteMind/Ideas`
/// is a section, `Ideas/2026` is a subsection. Nothing is invented: the tree
/// the app shows is the tree Finder shows, so a note moved in one is moved in
/// the other.
struct NoteSection: Identifiable, Equatable {
    let url: URL
    let name: String
    /// 0 for the root, 1 for a section, 2 for a subsection, and so on.
    let depth: Int
    var notes: [Note]
    var sections: [NoteSection]

    var id: String { url.path }
    var isRoot: Bool { depth == 0 }
    var isEmpty: Bool { notes.isEmpty && sections.isEmpty }

    /// Every note in this section and below it.
    var allNotes: [Note] { notes + sections.flatMap(\.allNotes) }
    var allSections: [NoteSection] { sections + sections.flatMap(\.allSections) }

    /// Whether this section is a real folder on disk RIGHT NOW — asked at
    /// the moment, not remembered from the read, because a folder can go
    /// between the two (Finder, the Trash, a drive unplugged) and the
    /// watcher only sees the primary folder's top level. Everything that
    /// takes a folder out of the project asks this first (Sean, 2026-09-19:
    /// "remove folder on project only if it's a real folder that exists").
    var isRealFolder: Bool { NoteTree.isRealFolder(at: url) }
}

/// The hand-kept order of the rows in one folder. Markdown files have no
/// intrinsic order and a folder listing is alphabetical, so dragging a note
/// into place has to be remembered somewhere: one JSON file, hidden, holding
/// a list of names per folder. Anything not named in it sorts after what is,
/// newest first, so a note made outside WriteMind still shows up.
struct NoteOrder: Codable, Equatable {
    /// Folder path relative to the notes root ("" for the root) → row names,
    /// a note's file name or a section's folder name.
    var folders: [String: [String]] = [:]

    static let fileName = "order.json"

    static func url(in directory: URL) -> URL {
        directory
            .appending(path: ".writemind", directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    static func load(in directory: URL) -> NoteOrder {
        guard let data = try? Data(contentsOf: url(in: directory)),
              let order = try? JSONDecoder().decode(NoteOrder.self, from: data) else { return NoteOrder() }
        return order
    }

    func save(in directory: URL) {
        let file = Self.url(in: directory)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(self).write(to: file, options: .atomic)
        } catch {
            NSLog("WriteMind: could not save the sidebar order: \(error)")
        }
    }

    /// The key a folder is stored under: its path relative to the root.
    static func key(for folder: URL, in root: URL) -> String {
        let folderPath = folder.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard folderPath != rootPath else { return "" }
        guard folderPath.hasPrefix(rootPath + "/") else { return folderPath }
        return String(folderPath.dropFirst(rootPath.count + 1))
    }

    /// Sort `names` by the remembered order; unknown names keep the order they
    /// arrived in (the caller sorts those by date) and go last.
    func arrange(_ names: [String], folder: URL, root: URL) -> [String] {
        let wanted = folders[Self.key(for: folder, in: root)] ?? []
        var remaining = names
        var out: [String] = []
        for name in wanted {
            if let index = remaining.firstIndex(of: name) {
                out.append(remaining.remove(at: index))
            }
        }
        return out + remaining
    }

    mutating func set(_ names: [String], folder: URL, root: URL) {
        folders[Self.key(for: folder, in: root)] = names
    }

    /// Forget a folder that has gone, and any name inside the ones that stay.
    mutating func forget(name: String, folder: URL, root: URL) {
        let key = Self.key(for: folder, in: root)
        folders[key]?.removeAll { $0 == name }
        if folders[key]?.isEmpty == true { folders.removeValue(forKey: key) }
    }
}

enum NoteTree {
    static let noteExtensions = ["md", "markdown", "txt"]

    /// A directory that exists at this moment: `fileExists(atPath:isDirectory:)`
    /// with the directory flag set. A plain file, a path never made or since
    /// gone, and a folder on a volume that is not mounted all say no. A
    /// symlink to a folder says yes — `fileExists` follows it, as Finder does.
    static func isRealFolder(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Whether a folder is a section. Every folder is, but one: `_drawings`
    /// beside a note holds that note's drawing cells (`DrawingCells`) — the
    /// note's data, visible on Sean's word (2026-10-02: "visible data
    /// generally speaking"), and not a folder of notes. So the sidebar never
    /// lists it, nothing counts it, no section is made or renamed to its
    /// name, and no note is moved into it. Any case: the disk is not
    /// case-sensitive.
    static func isSection(_ folder: URL) -> Bool {
        folder.lastPathComponent.caseInsensitiveCompare(DrawingCells.dataFolder) != .orderedSame
    }

    /// Read a folder and everything under it. Hidden folders — `.drawings`,
    /// `.writemind` — are skipped: they are the app's own bookkeeping. So is
    /// a note's `_drawings` (`isSection`).
    static func read(directory: URL, root: URL, order: NoteOrder, depth: Int = 0,
                     excluding: Set<String> = []) -> NoteSection {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []

        var notes: [Note] = []
        var sections: [NoteSection] = []

        for url in entries {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                // A folder taken out of the project stays on disk and out of the tree.
                guard !excluding.contains(url.standardizedFileURL.path), isSection(url) else { continue }
                sections.append(read(directory: url, root: root, order: order, depth: depth + 1,
                                     excluding: excluding))
            } else if noteExtensions.contains(url.pathExtension.lowercased()) {
                let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                notes.append(Note.make(url: url,
                                       modified: values?.contentModificationDate ?? .distantPast,
                                       contents: contents))
            }
        }

        // Newest first is the default; the remembered order wins where it has
        // an opinion, so a dragged row stays where it was dropped.
        notes.sort { $0.modified > $1.modified }
        sections.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let arranged = order.arrange(notes.map(\.url.lastPathComponent) + sections.map(\.name),
                                     folder: directory, root: root)
        notes = arranged.compactMap { name in notes.first { $0.url.lastPathComponent == name } }
        sections = arranged.compactMap { name in sections.first { $0.name == name } }

        return NoteSection(url: directory,
                           name: depth == 0 ? "Notes" : directory.lastPathComponent,
                           depth: depth, notes: notes, sections: sections)
    }

    /// A name nothing else in `folder` is using — and, for a folder, never
    /// the name of a note's data (`isSection`), which a section by that name
    /// would vanish into.
    static func uniqueURL(in folder: URL, base: String, extension ext: String?) -> URL {
        let stem = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        func candidate(_ name: String) -> URL {
            ext.map { folder.appending(path: "\(name).\($0)") } ?? folder.appending(path: name, directoryHint: .isDirectory)
        }
        var url = candidate(stem)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) || (ext == nil && !isSection(url)) {
            url = candidate("\(stem) \(counter)")
            counter += 1
        }
        return url
    }
}
