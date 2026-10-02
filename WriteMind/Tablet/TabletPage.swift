import AppKit
import Combine
import SwiftUI

// THE PAGE THE TABLET WRITES ON (Sean, 2026-10-02: "in normal mode its as
// if we were looking at the picture of a page, and anything drawn can be
// selected and inserted").
//
// A page is a list of the drawing layer's own `Stroke`s — ink, with a
// pressure per point and a tool — whose points are FRACTIONS OF THE PAGE
// (0…1 across, 0…1 down, from the top left) and whose widths are in the
// page's own points: the page is `TabletPage.longSide` points along its
// long side, whichever way it is turned, so a stroke keeps its size when
// the sheet goes from portrait to landscape and back. Everything that is
// not a fraction — the ink's outline, the box a selection touches, a
// picture cut from the page — is worked in those points, and the pane only
// scales them to fit.
//
// It is kept in Application Support, never beside the notes: the notes
// folder is Sean's and holds markdown and the sidecars of markdown, and
// this page belongs to no note. A run of the test host keeps its page in
// `TestHost.supportDirectory` like its session.

/// The paper. ONE KIND FOR NOW — themes are the next step (Sean,
/// 2026-10-02: "it can have themed backgrounds and different pen colors
/// and strokes to write with"): dot grid, ruled, graph, legal, blackboard.
/// Whatever a theme puts on the sheet it puts there in TWO places, the
/// pane and a picture taken off the page (`TabletRender`), and both ask
/// this enum — so a ruling added here appears in both or in neither.
enum PageTheme: String, CaseIterable, Codable {
    case plain

    /// The sheet itself.
    var paper: NSColor {
        switch self {
        case .plain: return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    /// What is printed on the sheet before anything is written on it, in
    /// a y-down context in page points. Plain paper has nothing; the
    /// ruled and gridded papers will draw here.
    func print(in context: CGContext, pageSize: CGSize) {
        switch self {
        case .plain: break
        }
    }
}

/// What is written to disk: the strokes, and which way the tablet was held
/// when they were last turned to match it — so a page saved under one turn
/// and opened under another comes up turned to fit, never stretched.
struct TabletSheet: Equatable {
    static let version = 1

    var strokes: [Stroke] = []
    /// `AppState.tabletQuarterTurns` the strokes are aligned to.
    var quarterTurns = 1
    /// How many strokes in the file could not be read — 0 for a clean file.
    /// Not written: it is a fact about one reading of one file.
    var unreadable = 0
}

extension TabletSheet: Codable {
    private enum CodingKeys: String, CodingKey { case version, strokes, quarterTurns }

    /// One stroke that may not read. A bad element in a plain `[Stroke]`
    /// fails the whole array, and with it every good stroke on the page.
    private struct Readable: Decodable {
        let stroke: Stroke?
        init(from decoder: Decoder) throws { stroke = try? Stroke(from: decoder) }
    }

    /// FORGIVING, the way every sidecar here is: each key is read if it is
    /// there, a stroke that cannot be read is counted and left out, and
    /// only a file that is not a page at all throws — which `TabletPage`
    /// answers by setting the file aside, never by wiping it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quarterTurns = TabletMapping.turns((try? container.decodeIfPresent(Int.self, forKey: .quarterTurns)) ?? nil ?? 1)
        guard container.contains(.strokes) else { return }
        if let read = try? container.decode([Readable].self, forKey: .strokes) {
            strokes = read.compactMap(\.stroke)
            unreadable = read.count - strokes.count
        } else {
            // `strokes` is there and is not a list of anything: none of it
            // can be read, and how much there was is not known.
            unreadable = 1
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(strokes, forKey: .strokes)
        try container.encode(quarterTurns, forKey: .quarterTurns)
    }
}

/// The page: its strokes, the undo history, and the file.
@MainActor
final class TabletPage: ObservableObject {
    static let shared = TabletPage(url: TabletPage.defaultURL, flushOnQuit: true)

    /// THE PAGE'S OWN POINTS: its long side is this many, whichever way it
    /// is turned. Near what the pane shows a page at (about 670 points tall
    /// in a 1280 × 800 window), so a page point is close to a screen point
    /// and the ink's outline comes out the shape the notebook's pen gives
    /// at the same size.
    nonisolated static let longSide: CGFloat = 800

    /// The page in its own points, at `aspect` (width ÷ height).
    nonisolated static func size(aspect: CGFloat) -> CGSize {
        guard aspect.isFinite, aspect > 0 else { return CGSize(width: longSide, height: longSide) }
        return aspect <= 1 ? CGSize(width: longSide * aspect, height: longSide)
                           : CGSize(width: longSide, height: longSide / aspect)
    }

    /// What is on the page, back to front.
    @Published private(set) var strokes: [Stroke]
    /// Whole pages, as they were before each change — a stroke is one
    /// step, a clear is one — and the ones Undo has stepped back out of.
    @Published private(set) var history: [[Stroke]] = []
    @Published private(set) var future: [[Stroke]] = []
    /// Which way the tablet was held for the strokes as they are.
    private(set) var quarterTurns: Int
    /// Where a file that could not be read was put, when one was.
    let setAside: URL?

    static let historyLimit = 60
    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// Where the page is written, and the bytes it last read from there or
    /// wrote there — the second of the two locks (AGENTS.md, "a save never
    /// clobbers"). After `init`, touched only on `queue`.
    private final class PageFile: @unchecked Sendable {
        var url: URL
        var known: Data?
        init(url: URL, known: Data?) {
            self.url = url
            self.known = known
        }
    }

    private let file: PageFile?
    private var saveTask: Task<Void, Never>?
    private var dirty = false
    /// Encoding a page of handwriting is tens of milliseconds in a Debug
    /// build; it is done off the main thread so the next stroke never waits
    /// for the last one's save. One queue, so saves land in order — and a
    /// test can hold it, to be the disk being slow.
    let queue = DispatchQueue(label: "com.seancheren.WriteMind.tablet-page", qos: .utility)
    private var quitObserver: NSObjectProtocol?
    var log: (String) -> Void = { line in if !TestHost.isActive { DebugLog.write(line) } }

    /// The page in `url`, or a blank one. `url` nil keeps nothing.
    init(url: URL?, flushOnQuit: Bool = false) {
        var rewrite = false
        if let url {
            let loaded = Self.load(from: url)
            file = PageFile(url: url, known: loaded.known)
            strokes = loaded.sheet.strokes
            quarterTurns = loaded.sheet.quarterTurns
            setAside = loaded.setAside
            if let aside = loaded.setAside {
                let line = "tablet page: \(url.lastPathComponent) could not be read whole — kept as "
                    + "\(aside.lastPathComponent), \(loaded.sheet.strokes.count) strokes read"
                if !TestHost.isActive { DebugLog.write(line) }
            }
            // Copied aside, what could be read goes back over the file —
            // now, not at the next stroke: a page nobody wrote on was read
            // again at every launch, and copied aside again with it.
            rewrite = loaded.setAside != nil && loaded.sheet.unreadable > 0
        } else {
            file = nil
            strokes = []
            quarterTurns = 1
            setAside = nil
        }
        if flushOnQuit {
            // Synchronously, on the way out: a Task would run after the
            // app had gone, and the last stroke with it.
            quitObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
        }
        if rewrite { scheduleSave() }
    }

    // MARK: - Changes

    /// A stroke written: one step back.
    func commit(_ stroke: Stroke) {
        remember()
        strokes.append(stroke)
        scheduleSave()
    }

    /// The page blank again — and one step back, so ⌘Z brings it all back.
    func clear() {
        guard !strokes.isEmpty else { return }
        remember()
        strokes = []
        scheduleSave()
    }

    @discardableResult
    func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        future.append(strokes)
        strokes = previous
        scheduleSave()
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let next = future.popLast() else { return false }
        history.append(strokes)
        strokes = next
        scheduleSave()
        return true
    }

    private func remember() {
        history.append(strokes)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        future.removeAll()
    }

    // MARK: - Turning

    /// The tablet is held another way: THE INK TURNS WITH THE SHEET. The
    /// page's shape is the tablet's turned, so a quarter turn makes a tall
    /// page wide; leaving the fractions where they were would stretch every
    /// letter on it. Turned, each stroke stays where it is ON THE TABLET —
    /// `TabletMapping.page` for one more turn is this turn of the last
    /// one. Not an undo step (nothing was written), but the history turns
    /// too, or Undo would bring back a page turned the old way.
    func align(to turns: Int) {
        let target = TabletMapping.turns(turns)
        let by = TabletMapping.turns(target - quarterTurns)
        guard by != 0 else { return }
        // A stroke is in most of the history's pages at once; it is turned
        // once and shared, as it was before.
        var turned: [UUID: Stroke] = [:]
        func turn(_ page: [Stroke]) -> [Stroke] {
            page.map { stroke in
                if let done = turned[stroke.id] { return done }
                let done = Self.turned(stroke, by: by)
                turned[stroke.id] = done
                return done
            }
        }
        strokes = turn(strokes)
        history = history.map(turn)
        future = future.map(turn)
        quarterTurns = target
        scheduleSave()
    }

    /// A point on the page after the sheet turns `quarterTurns` clockwise.
    nonisolated static func turned(_ point: CGPoint, by quarterTurns: Int) -> CGPoint {
        switch TabletMapping.turns(quarterTurns) {
        case 1: return CGPoint(x: 1 - point.y, y: point.x)
        case 2: return CGPoint(x: 1 - point.x, y: 1 - point.y)
        case 3: return CGPoint(x: point.y, y: 1 - point.x)
        default: return point
        }
    }

    /// A stroke after the sheet turns. A NEW ID: its points are rewritten,
    /// and `InkCache` remembers an outline by id and a fingerprint that a
    /// turn can leave the same. Point for point, so `pressures` stays
    /// parallel (AGENTS.md, the lockstep rule).
    nonisolated static func turned(_ stroke: Stroke, by quarterTurns: Int) -> Stroke {
        var turned = stroke
        turned.id = UUID()
        turned.points = stroke.points.map { Self.turned($0, by: quarterTurns) }
        return turned
    }

    // MARK: - The file

    /// Application Support/WriteMind/TabletPage.json — or the test host's
    /// own support folder — named for this build of the app.
    nonisolated static var defaultURL: URL? {
        let base = TestHost.isActive
            ? TestHost.supportDirectory
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?.appending(path: "WriteMind", directoryHint: .isDirectory)
            .appending(path: fileName(bundleID: Bundle.main.bundleIdentifier))
    }

    /// The app's own bundle id — the one Sean runs.
    nonisolated static let appBundleID = "com.seancheren.WriteMind"

    /// A COPY OF THE APP THAT IS NOT THIS ONE KEEPS A PAGE OF ITS OWN — the
    /// first of the two locks. Application Support is found by the app's
    /// NAME and not its bundle id, and a scratch build is given an id of
    /// its own to be driven at all (computer use finds an app by its id);
    /// with one fixed name it opened Sean's page, and a stroke, a turn or
    /// "Clear the Page" there wrote over his.
    nonisolated static func fileName(bundleID: String?) -> String {
        guard bundleID != appBundleID else { return "TabletPage.json" }
        return "TabletPage-\(bundleID ?? "unbundled").json"
    }

    /// Half a second after the last change, off the main thread.
    private func scheduleSave() {
        guard file != nil else { return }
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.save(wait: false)
        }
    }

    /// Whatever has not reached the disk, now, and waited for — including
    /// a save already handed to the queue. Called on the way out, and AppKit
    /// exits as soon as it returns: a save still being written then died
    /// with the app, and the `.atomic` write left the file as it was before
    /// it, every stroke since gone.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        if dirty { save(wait: true) } else { queue.sync {} }
    }

    private func save(wait: Bool) {
        guard let file else { return }
        dirty = false
        let sheet = TabletSheet(strokes: strokes, quarterTurns: quarterTurns)
        let log = log
        let work = { Self.write(sheet, to: file, log: log) }
        if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    /// On `queue`. A SAVE NEVER CLOBBERS (AGENTS.md) — the second lock, the
    /// one `NoteStore.saveNow` keeps: the page writes its file only while
    /// the bytes there are the ones it last read or wrote. Anything else is
    /// another writer — a second copy of the app with the same id, a script
    /// — whose page is not this one's to throw away. It is left as it is,
    /// and this page is written BESIDE it, `TabletPage.conflict-<date>.json`,
    /// from then on: nothing either of them wrote is lost, and the next
    /// launch opens the file that was there.
    nonisolated private static func write(_ sheet: TabletSheet, to file: PageFile, log: (String) -> Void) {
        do {
            try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(sheet)
            let onDisk = try? Data(contentsOf: file.url)
            if !NoteWriting.mayWrite(dataOnDisk: onDisk, known: file.known) {
                let beside = asideURL(for: file.url, at: Date(), kind: "conflict")
                log("tablet page: \(file.url.lastPathComponent) was written by something else since this page "
                    + "read it — left as it is; the page is kept in \(beside.lastPathComponent) from now on")
                file.url = beside
            }
            try data.write(to: file.url, options: .atomic)
            file.known = data
        } catch {
            log("tablet page: could not save \(file.url.lastPathComponent): \(error)")
        }
    }

    /// The page in the file, where the file went if it could not be read
    /// whole, and the bytes left at `url` afterwards (`known`, for the lock).
    ///
    /// A BAD FILE IS SET ASIDE, NEVER WIPED. A file that is not a page at
    /// all is MOVED to `TabletPage.corrupt-<date>.json` and the page starts
    /// blank; a page with some strokes that will not read keeps the ones
    /// that will, and the file as it was is COPIED there first — and the
    /// page writes what could be read back over the original straight
    /// away. Either way what was on disk is still on disk. A file that
    /// could not be moved aside is not known, so the lock keeps every save
    /// off it.
    nonisolated static func load(from url: URL, now: Date = Date())
        -> (sheet: TabletSheet, setAside: URL?, known: Data?) {
        guard let data = try? Data(contentsOf: url) else { return (TabletSheet(), nil, nil) }
        let manager = FileManager.default
        if let sheet = try? JSONDecoder().decode(TabletSheet.self, from: data) {
            guard sheet.unreadable > 0 else { return (sheet, nil, data) }
            let aside = asideURL(for: url, at: now)
            return (sheet, (try? manager.copyItem(at: url, to: aside)) == nil ? nil : aside, data)
        }
        let aside = asideURL(for: url, at: now)
        guard (try? manager.moveItem(at: url, to: aside)) != nil else { return (TabletSheet(), nil, nil) }
        return (TabletSheet(), aside, nil)
    }

    /// `TabletPage.corrupt-2026-10-02T14-03-22.json` (or `.conflict-…`)
    /// beside the page, and never over one already there.
    nonisolated static func asideURL(for url: URL, at date: Date, kind: String = "corrupt") -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent + ".\(kind)-" + formatter.string(from: date)
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        var candidate = folder.appending(path: "\(stem).\(ext)")
        var count = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(stem)-\(count).\(ext)")
            count += 1
        }
        return candidate
    }
}
