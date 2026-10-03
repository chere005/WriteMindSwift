import Foundation

/// What WriteMind may do with a drawing cell's file.
enum DrawingCellState: Equatable {
    /// Its own file, every object read — or no file yet, which the first
    /// change creates. Drawn in, and written.
    case writable
    /// Shown, never drawn in and never written: a picture that is not
    /// WriteMind's, WriteMind's but unreadable, or one changed by another
    /// writer since it was read. Why, in one line.
    case readOnly(String)
    /// iCloud has not downloaded it yet. Nothing is shown and nothing is
    /// ever created over it.
    case placeholder
}

/// The drawing cells' files: `_drawings/cells/<ID>.png` in the note's own
/// folder — VISIBLE, on Sean's word (2026-10-02: "visible data generally
/// speaking"), and the same relative path at every depth.
///
/// Three rules, and every one is about somebody else's work:
///
/// - **A write goes over only the bytes this app last read or wrote**
///   (`NoteWriting.mayWrite(dataOnDisk:known:)`, the note's own rule).
///   Anything else is another writer's — a second instance, iCloud, an
///   editor — and the write is refused, never forced.
/// - **An iCloud placeholder is never created over**: a file that has not
///   downloaded is still a file, and writing one beside it is a conflict
///   copy at best.
/// - **NOTHING HERE DELETES ANYTHING.** A cell taken out of a note leaves
///   its file; a cell emptied is written empty; a note moved leaves the
///   originals behind it. A file nobody points at costs a few kilobytes,
///   and a file deleted that somebody did point at is a drawing gone.
enum DrawingCellStore {
    /// `<the note's folder>/_drawings/cells`.
    static func folder(besides note: URL) -> URL {
        note.deletingLastPathComponent()
            .appending(path: DrawingCells.dataFolder, directoryHint: .isDirectory)
            .appending(path: DrawingCells.cellsFolder, directoryHint: .isDirectory)
    }

    static func url(_ id: UUID, besides note: URL) -> URL {
        folder(besides: note).appending(path: id.uuidString + ".png")
    }

    /// What iCloud leaves in place of a file it has not downloaded.
    static func placeholder(_ id: UUID, besides note: URL) -> URL {
        folder(besides: note).appending(path: "." + id.uuidString + ".png.icloud")
    }

    /// A cell's file as it was found.
    struct Loaded: Equatable {
        /// The drawing — nil for no file yet, and for any file that is not
        /// one this build can draw in.
        var cell: DrawingCell?
        var state: DrawingCellState
        /// The bytes read: the only bytes a write may go over, and the
        /// pixels a read-only cell shows.
        var known: Data?
    }

    static func load(_ id: UUID, besides note: URL) -> Loaded {
        let file = url(id, besides: note)
        guard FileManager.default.fileExists(atPath: file.path) else {
            let waiting = FileManager.default.fileExists(atPath: placeholder(id, besides: note).path)
            return Loaded(cell: nil, state: waiting ? .placeholder : .writable, known: nil)
        }
        guard let data = try? Data(contentsOf: file) else {
            return Loaded(cell: nil, state: .readOnly(unreadable), known: nil)
        }
        switch DrawingCellFile.read(data) {
        case .cell(let cell): return Loaded(cell: cell, state: .writable, known: data)
        case .picture: return Loaded(cell: nil, state: .readOnly(notOurs), known: data)
        case .unreadable(let why): return Loaded(cell: nil, state: .readOnly(why), known: data)
        }
    }

    /// What a write came to.
    enum Write: Equatable {
        /// The bytes now on disk — what the next write may go over.
        case written(Data)
        /// Nothing was written, and the cell is read-only from here on.
        case refused(String)

        /// The cell's state after it.
        var state: DrawingCellState {
            switch self {
            case .written: return .writable
            case .refused(let why): return .readOnly(why)
            }
        }
    }

    /// The cell into its file: `rendition` — the PNG of it — with the cell's
    /// payload in it. `known` is the bytes last read or written, nil for a
    /// cell that has never had a file.
    static func write(_ cell: DrawingCell, rendition: Data, id: UUID, besides note: URL,
                      known: Data?) -> Write {
        let file = url(id, besides: note)
        guard !FileManager.default.fileExists(atPath: placeholder(id, besides: note).path) else {
            return .refused(notDownloaded)
        }
        let there = FileManager.default.fileExists(atPath: file.path)
        let onDisk = there ? try? Data(contentsOf: file) : nil
        guard !there || onDisk != nil else { return .refused(unreadable) }
        guard NoteWriting.mayWrite(dataOnDisk: onDisk, known: known) else { return .refused(changedElsewhere) }
        // Read-only is the file's, not only the caller's: a picture that is
        // not a cell this build can read is never written over, whoever asks.
        if let onDisk {
            switch DrawingCellFile.read(onDisk) {
            case .cell: break
            case .picture: return .refused(notOurs)
            case .unreadable(let why): return .refused(why)
            }
        }
        guard let bytes = DrawingCellFile.embed(DrawingCellFile.payload(cell), in: rendition) else {
            return .refused(notWritten)
        }
        do {
            try FileManager.default.createDirectory(at: folder(besides: note), withIntermediateDirectories: true)
            try bytes.write(to: file, options: .atomic)
        } catch {
            NSLog("WriteMind: could not write the drawing cell \(id.uuidString): \(error)")
            return .refused(notWritten)
        }
        return .written(bytes)
    }

    /// A cell's file beside another note, under `newID` — the same id for a
    /// note moved to another section, a new one for a note duplicated. A
    /// COPY: the original stays where it was, so a move that is undone in
    /// Finder, or a note put back from the Trash, still has its drawing.
    /// Never over a file, or a placeholder, already there.
    static func copy(_ id: UUID, to newID: UUID, from note: URL, to other: URL) {
        let source = url(id, besides: note)
        let destination = url(newID, besides: other)
        guard source.standardizedFileURL != destination.standardizedFileURL,
              FileManager.default.fileExists(atPath: source.path),
              !FileManager.default.fileExists(atPath: destination.path),
              !FileManager.default.fileExists(atPath: placeholder(newID, besides: other).path)
        else { return }
        do {
            try FileManager.default.createDirectory(at: folder(besides: other), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            NSLog("WriteMind: could not copy the drawing cell \(id.uuidString): \(error)")
        }
    }

    // MARK: - What the footer says

    static let notOurs = "This picture was not drawn in WriteMind, so it can only be shown."
    static let unreadable = "This drawing's file could not be read, so it can only be shown."
    static let notDownloaded = "This drawing has not downloaded yet."
    static let changedElsewhere = "This drawing changed on disk, so it was not written over."
    static let notWritten = "This drawing could not be saved, so it was left as it is on disk."
}
