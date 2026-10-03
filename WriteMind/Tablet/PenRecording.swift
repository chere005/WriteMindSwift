import Combine
import Foundation

// RECORD AND REPLAY (Sean, 2026-10-03: "make sure i can develop wacom
// features without a device plugged in"). A session of the pen — the real
// tablet's, the virtual one's — is written down as it reached the funnel,
// with the moment of each event, and played back later: at the speed it
// happened, faster or slower, or one event at a time. A bug seen once on the
// real tablet is a file that can be replayed as often as it takes, and a
// fixture in the tests is a session somebody recorded.
//
// THE FILE is NDJSON, one JSON object a line, keys sorted so two recordings
// of the same session are the same bytes:
//
//     {"format":"writemind-pen-stream","version":1,"source":"virtual","productID":890,
//      "width":15200,"height":9500,"quarterTurns":1,"note":"a stroke"}
//     {"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":0}
//     {"report":"02 e1 b0 1d 8e 12 00 04 00 00","t":0.008}
//     {"reading":{...},"t":0.016}
//
// `t` is seconds from the FIRST event. An event is the tablet's own report —
// the ten bytes, in hex — or, for a session made while WriteMind did not
// hold the tablet and the Wacom driver's events were all there was, the
// reading those events were made into: the fallback route has no bytes. The
// header says what the recording is of; replay plays on that tablet's field.

/// One event of a recording, and when, in seconds from the first.
struct PenStreamEntry: Equatable {
    var time: TimeInterval
    var event: PenStreamEvent
}

/// A session of the pen, in memory: the header and the events.
struct PenRecording: Equatable {
    struct Header: Codable, Equatable {
        var format = PenRecording.format
        var version = PenRecording.version
        /// When it was recorded, ISO 8601 — absent in a fixture, which is
        /// the same bytes however often it is made.
        var created: String?
        /// "hid", "driver", "virtual" or "replay" — and "mixed" when more
        /// than one spoke.
        var source: String?
        /// The tablet it was recorded on: its USB product and the field in
        /// counts. Replay plays on that field.
        var productID: Int?
        var width: Double?
        var height: Double?
        /// How the tablet was held. Information only: the page's turn is
        /// the user's, and replay does not change it.
        var quarterTurns: Int?
        /// What it is of, in a person's words.
        var note: String?

        /// The field the recording was made on, when it says.
        var extent: TabletExtent? {
            guard let width, let height, width > 0, height > 0 else { return nil }
            var extent = productID.flatMap(TabletExtent.known(productID:)) ?? TabletExtent(width: width, height: height)
            extent.width = width
            extent.height = height
            return extent
        }
    }

    static let format = "writemind-pen-stream"
    static let version = 1

    var header: Header
    var entries: [PenStreamEntry]

    init(header: Header = Header(), entries: [PenStreamEntry] = []) {
        self.header = header
        self.entries = entries
    }

    /// From the first event to the last, in seconds.
    var duration: TimeInterval {
        guard let first = entries.first, let last = entries.last else { return 0 }
        return last.time - first.time
    }

    // MARK: - The file

    /// Why a recording could not be read — never "the rest of it": a file
    /// that is not whole is not played.
    enum Failure: Error, Equatable, CustomStringConvertible {
        case empty
        case notAPenStream
        case newer(Int)
        case line(Int, String)

        var description: String {
            switch self {
            case .empty: return "the file is empty"
            case .notAPenStream: return "the first line is not a WriteMind pen recording's header"
            case .newer(let version): return "it is version \(version) of the format, and this build reads \(PenRecording.version)"
            case .line(let number, let why): return "line \(number): \(why)"
            }
        }
    }

    /// The file's bytes: the header, then an event a line, a newline after
    /// each.
    func ndjson() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var out = Data()
        func line<T: Encodable>(_ value: T) {
            if let data = try? encoder.encode(value) {
                out.append(data)
                out.append(0x0A)
            }
        }
        line(header)
        for entry in entries { line(Line(entry)) }
        return out
    }

    /// Read a file's bytes. The header must be this format; an event that
    /// will not read is the whole file refused, with its line number.
    init(ndjson data: Data) throws {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { (number: $0.offset + 1, text: $0.element.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.text.isEmpty }
        guard let first = lines.first else { throw Failure.empty }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: Data(first.text.utf8)),
              header.format == Self.format else { throw Failure.notAPenStream }
        guard header.version <= Self.version else { throw Failure.newer(header.version) }
        var entries: [PenStreamEntry] = []
        for line in lines.dropFirst() {
            do {
                entries.append(try decoder.decode(Line.self, from: Data(line.text.utf8)).entry)
            } catch Failure.line(_, let why) {
                throw Failure.line(line.number, why)
            } catch {
                throw Failure.line(line.number, "not an event of a pen recording")
            }
        }
        self.init(header: header, entries: entries)
    }

    init(contentsOf url: URL) throws {
        try self.init(ndjson: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ndjson().write(to: url, options: .atomic)
    }

    // MARK: - One line

    /// An event as a line: `{"report":"…","t":…}` or `{"reading":{…},"t":…}`.
    private struct Line: Codable {
        var t: Double
        var report: String?
        var reading: ReadingRecord?

        init(_ entry: PenStreamEntry) {
            t = entry.time
            switch entry.event {
            case .report(let bytes): report = WacomPenPacket.hex(bytes)
            case .reading(let reading): self.reading = ReadingRecord(reading)
            }
        }

        var entry: PenStreamEntry {
            get throws {
                if let report {
                    let bytes = try Self.bytes(of: report)
                    return PenStreamEntry(time: t, event: .report(bytes))
                }
                if let reading { return PenStreamEntry(time: t, event: .reading(try reading.value(at: t))) }
                throw Failure.line(0, "neither a report nor a reading")
            }
        }

        private static func bytes(of hex: String) throws -> [UInt8] {
            let parts = hex.split(separator: " ")
            let bytes = parts.compactMap { UInt8($0, radix: 16) }
            guard !parts.isEmpty, bytes.count == parts.count else { throw Failure.line(0, "a report that is not hex bytes") }
            return bytes
        }
    }

    /// A reading, as JSON: what the driver's events were read as.
    fileprivate struct ReadingRecord: Codable, Equatable {
        /// "point" or "proximity".
        var kind: String
        var x: Double?
        var y: Double?
        var tip: Bool?
        /// "lower" / "upper"; absent when the reading could not say.
        var switches: [String]?
        var pressure: Double?
        var buttons: UInt?
        var entering: Bool?
        var native: Bool

        init(_ reading: TabletReading) {
            native = reading.native
            switch reading.kind {
            case .point(let counts, let tip, let switches, let pressure, let buttons):
                kind = "point"
                x = Double(counts.x)
                y = Double(counts.y)
                self.tip = tip
                self.switches = switches.map { $0.map { $0 == .lower ? "lower" : "upper" }.sorted() }
                self.pressure = pressure
                self.buttons = buttons
            case .proximity(let entering):
                kind = "proximity"
                self.entering = entering
            }
        }

        func value(at time: TimeInterval) throws -> TabletReading {
            switch kind {
            case "point":
                guard let x, let y, let tip, let pressure else { throw Failure.line(0, "a point with no place") }
                let switches: Set<PenSwitch>? = try self.switches.map { names in
                    Set(try names.map { name in
                        switch name {
                        case "lower": return PenSwitch.lower
                        case "upper": return PenSwitch.upper
                        default: throw Failure.line(0, "a switch called \(name)")
                        }
                    })
                }
                return TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: tip, switches: switches,
                                                  pressure: pressure, buttons: buttons ?? 0),
                                     timestamp: time, native: native)
            case "proximity":
                guard let entering else { throw Failure.line(0, "a proximity that does not say which way") }
                return TabletReading(kind: .proximity(entering: entering), timestamp: time, native: native)
            default:
                throw Failure.line(0, "a reading of kind \(kind)")
            }
        }
    }
}

// MARK: - Recording

/// WRITES A SESSION DOWN as the funnel hears it (`TabletInput.recorder`):
/// every event that was let in and had somewhere to go, with its time from
/// the first. Not a stream of what the hardware sent — what the pen's path
/// consumed, which is what a replay has to put back.
final class PenRecorder {
    private(set) var entries: [PenStreamEntry] = []
    private(set) var sources: Set<TabletSourceKind> = []
    private var origin: TimeInterval?

    var isEmpty: Bool { entries.isEmpty }

    /// Microseconds are all a stamp means, and a file of 0.30000000000000004s
    /// is a file nobody can read.
    static func rounded(_ time: TimeInterval) -> TimeInterval { (time * 1_000_000).rounded() / 1_000_000 }

    func record(_ event: PenStreamEvent, at time: TimeInterval, from source: TabletSourceKind) {
        let origin = self.origin ?? time
        self.origin = origin
        let t = Self.rounded(time - origin)
        var event = event
        // A reading carries a time of its own; in a recording the entry's
        // is the only one, so two recordings of one session are equal.
        if case .reading(let reading) = event {
            event = .reading(TabletReading(kind: reading.kind, timestamp: t, native: reading.native))
        }
        entries.append(PenStreamEntry(time: t, event: event))
        sources.insert(source)
    }

    /// What has been heard so far, as a recording.
    func recording(extent: TabletExtent?, productID: Int?, quarterTurns: Int?, created: Date? = nil,
                   note: String? = nil) -> PenRecording {
        var header = PenRecording.Header()
        if let created {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            header.created = formatter.string(from: created)
        }
        header.source = sources.count > 1 ? "mixed" : sources.first?.rawValue
        header.productID = productID
        header.width = extent?.width
        header.height = extent?.height
        header.quarterTurns = quarterTurns
        header.note = note
        return PenRecording(header: header, entries: entries)
    }
}

// MARK: - Replay

/// PLAYS A RECORDING BACK through the one door (`TabletInput.receive`), as a
/// source of its own kind: at the speed it happened, at a multiple of it, or
/// ONE EVENT AT A TIME. What the pen's state machine sees is stamped as
/// recorded, so a replay at any speed — or by hand, a click a step — does
/// exactly what the session did: the double press is still a double press
/// at 8×, because the timing the pen reads is in the stamps and only the
/// waiting between events is sped up.
@MainActor
final class PenReplay: ObservableObject, TabletSource {
    enum State: Equatable {
        /// Not started, or stopped and wound back.
        case ready
        case playing
        /// Between events, waiting to be stepped or played on.
        case paused
        /// Every event delivered.
        case finished
    }

    let kind = TabletSourceKind.replay
    var door: ((PenStreamEvent, TimeInterval) -> Void)?

    let recording: PenRecording
    @Published private(set) var state = State.ready
    /// How many events have been delivered.
    @Published private(set) var delivered = 0
    /// The multiple of real time the waiting is run at; `.infinity` is no
    /// waiting at all.
    private(set) var speed = 1.0

    /// "As fast as it will go": every event at once, in order.
    nonisolated static let asFastAsPossible = Double.infinity

    private let clock: PenClock
    /// Where the recorded `t` of 0 lands on the stamps the pen reads.
    private let base: TimeInterval
    private var timer: AnyCancellable?
    private var lastWasNear = false
    private var lastStamp: TimeInterval?
    private var lastCounts: CGPoint?
    /// Told when the last event has been delivered.
    var onFinish: (() -> Void)?

    /// `base` is where recorded time zero lands: the clock's now, by
    /// default, so a second replay of the same file never repeats the
    /// stamps the pen has just seen (a repeated stamp is a duplicate to it).
    init(_ recording: PenRecording, clock: PenClock? = nil, base: TimeInterval? = nil) {
        let clock = clock ?? LivePenClock.shared
        self.recording = recording
        self.clock = clock
        self.base = base ?? clock.now
    }

    var count: Int { recording.entries.count }
    var isPlaying: Bool { state == .playing }

    // MARK: Controls

    /// Play from where it is, at `speed` times the pace it happened at.
    func play(speed: Double = 1) {
        guard state != .finished else { return }
        self.speed = speed > 0 ? speed : 1
        guard delivered < count else { finish(); return }
        state = .playing
        schedule()
    }

    /// Held at the start, to be stepped through by hand.
    func hold() {
        guard state == .ready, delivered < count else { return }
        state = .paused
    }

    /// Hold between events.
    func pause() {
        guard state == .playing else { return }
        timer?.cancel()
        timer = nil
        state = .paused
    }

    /// ONE EVENT, now — whatever the clock says is due.
    func step() {
        guard state != .finished, delivered < count else { return }
        timer?.cancel()
        timer = nil
        state = .paused
        deliverNext()
        if delivered >= count { finish() }
    }

    /// Let go: the pen is lifted wherever it was (a stroke half-played must
    /// not stay down), and the replay is wound back to its start.
    func stop() {
        timer?.cancel()
        timer = nil
        liftPen()
        delivered = 0
        state = .ready
    }

    // MARK: Delivery

    private func schedule() {
        timer?.cancel()
        guard state == .playing else { return }
        guard delivered < count else { finish(); return }
        let gap = delivered == 0 ? 0 : recording.entries[delivered].time - recording.entries[delivered - 1].time
        let wait = speed.isInfinite ? 0 : max(gap, 0) / speed
        timer = clock.after(wait) { [weak self] in
            guard let self, self.state == .playing else { return }
            self.deliverNext()
            if self.delivered >= self.count { self.finish() } else { self.schedule() }
        }
    }

    private func deliverNext() {
        let entry = recording.entries[delivered]
        delivered += 1
        let stamp = base + entry.time
        lastStamp = stamp
        switch entry.event {
        case .report(let bytes):
            if let packet = WacomPenPacket(bytes) {
                lastWasNear = packet.inRange
                lastCounts = CGPoint(x: packet.x, y: packet.y)
            }
            emit(.report(bytes), at: stamp)
        case .reading(let reading):
            switch reading.kind {
            case .point(let counts, _, _, _, _):
                lastWasNear = true
                lastCounts = counts
            case .proximity(let entering):
                lastWasNear = entering
            }
            emit(.reading(TabletReading(kind: reading.kind, timestamp: stamp, native: reading.native)), at: stamp)
        }
    }

    private func finish() {
        timer?.cancel()
        timer = nil
        state = .finished
        onFinish?()
    }

    /// The pen goes out of reach where it last was, if it was near: the
    /// pen's state machine ends any stroke under way as it leaves.
    private func liftPen() {
        guard lastWasNear, let lastStamp else { return }
        lastWasNear = false
        let stamp = lastStamp + 0.001
        self.lastStamp = stamp
        emit(.report(PenFrame.away(at: lastCounts ?? .zero).report), at: stamp)
    }
}
