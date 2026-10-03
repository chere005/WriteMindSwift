import Combine
import Foundation

// THE DEVELOPER'S TOOLS FOR THE PEN (Sean, 2026-10-03: "make sure i can
// develop wacom features without a device plugged in"): the virtual tablet,
// recording a session and replaying one. All of it is OFF unless switched on
// — Input Devices ▸ Tablet Developer — and the real tablet wins whenever it
// is plugged in (`TabletSourcePolicy`), so none of it can be in a release
// user's flow. The switch is remembered (it is a developer's setting), but
// the virtual tablet is never PICKED on its own: a launch comes up with the
// pick it had, and the stand-in is chosen from the Tablets list like any
// tablet.

@MainActor
final class TabletDeveloper: ObservableObject {
    /// The defaults key of the developer switch; absent is off.
    static let virtualKey = "tabletVirtualEnabled"

    /// THE SWITCH: the virtual tablet is listed with the tablets, and its
    /// pad and a replay are heard, only while it is on and no real tablet
    /// is plugged in. Off by default.
    @Published var virtualEnabled: Bool {
        didSet {
            guard virtualEnabled != oldValue else { return }
            defaults.set(virtualEnabled, forKey: Self.virtualKey)
            onVirtualChange?(virtualEnabled)
        }
    }
    /// The controller's cue to list the stand-in or take it away.
    var onVirtualChange: ((Bool) -> Void)?

    /// The pad's model, and the pen behind it.
    let virtual: VirtualTablet

    /// Why the stand-ins are silent, in words — nil while they are heard
    /// (`TabletSourcePolicy.silence`). Said in the virtual tablet's panel and
    /// in the Tablet Developer menu.
    @Published var silence: String?

    @Published private(set) var isRecording = false
    /// A line about the last thing that was done or went wrong: where a
    /// recording was saved, why one could not be played. It stays until the
    /// next, in the virtual tablet's panel and at the head of the Tablet
    /// Developer menu — and every one is ALSO said in the app's footer
    /// (`onSay`), because the panel is only up while the virtual tablet is
    /// the pick, which is never the case in the flow the tools are for: a
    /// session recorded on the real tablet saves with the pane on the page
    /// and no panel in sight.
    @Published private(set) var status: String?
    /// Where a message goes besides `status` — the footer, once the app has
    /// wired it (`say(in:)`).
    var onSay: ((String) -> Void)?
    /// The last recording saved.
    @Published private(set) var lastRecording: URL?
    /// The replay in hand, running or held.
    @Published private(set) var replay: PenReplay?

    /// Which tablet is the input, for a recording's header — the controller
    /// says (`TabletController`).
    var productID: () -> Int? = { nil }

    private let defaults: UserDefaults
    private let input: TabletInput
    private let clock: PenClock

    init(defaults: UserDefaults, input: TabletInput, clock: PenClock? = nil) {
        let clock = clock ?? LivePenClock.shared
        self.defaults = defaults
        self.input = input
        self.clock = clock
        virtualEnabled = defaults.bool(forKey: Self.virtualKey)
        virtual = VirtualTablet(clock: clock)
    }

    /// Say it: `status`, and the footer.
    func say(_ text: String) {
        status = text
        onSay?(text)
    }

    /// The footer is the note store's notice line — the one the camera's
    /// notices and a refused command go to — shown whatever the pick is.
    func say(in store: NoteStore) {
        onSay = { [weak store] text in store?.notice(text) }
    }

    // MARK: - Recording

    /// Where recordings are kept: Application Support/WriteMind/PenRecordings
    /// — a visible folder, and the test host's own under test (never beside
    /// the notes).
    nonisolated static var recordingsDirectory: URL {
        let base = TestHost.isActive
            ? TestHost.supportDirectory
            : (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
        return base.appending(path: "WriteMind", directoryHint: .isDirectory)
            .appending(path: "PenRecordings", directoryHint: .isDirectory)
    }

    /// Start writing the session down: every event the funnel lets in from
    /// here on, the real tablet's or the virtual one's.
    func startRecording() {
        guard !isRecording else { return }
        input.recorder = PenRecorder()
        isRecording = true
        say("Recording the pen — every report the page hears is written down.")
    }

    /// Stop, and save what was heard as `pen-<date>.ndjson` in the
    /// recordings folder. Nothing heard is nothing saved, and says so.
    @discardableResult
    func stopRecording(into folder: URL = TabletDeveloper.recordingsDirectory, now: Date = Date()) -> URL? {
        guard isRecording, let recorder = input.recorder else { return nil }
        input.recorder = nil
        isRecording = false
        guard !recorder.isEmpty else {
            say("Nothing was recorded — the pen said nothing while it ran. A tablet has to be picked and the page (or a note) on screen.")
            return nil
        }
        let recording = recorder.recording(extent: input.extent, productID: productID(),
                                           quarterTurns: input.quarterTurns, created: now)
        let url = folder.appending(path: Self.fileName(at: now))
        do {
            try recording.write(to: url)
            lastRecording = url
            say("Saved \(url.lastPathComponent) — \(recording.entries.count) events, "
                + String(format: "%.1f s.", recording.duration))
            return url
        } catch {
            say("Could not save the recording: \(error.localizedDescription)")
            return nil
        }
    }

    /// `pen-2026-10-03-143005.ndjson`.
    static func fileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "pen-\(formatter.string(from: date)).ndjson"
    }

    // MARK: - Replay

    /// A replay can be heard: the stand-ins are switched on, no real tablet
    /// is plugged in, and the pen has somewhere to write — a tablet picked
    /// and its page (or a note) on screen.
    var canReplay: Bool { input.policy.admits(.replay) && input.isRunning && input.targetIsShowing }

    /// Why a replay would not be heard, in words; nil when it would.
    var replayBlocker: String? {
        if let silence = input.policy.silence { return silence }
        if !input.isRunning { return "Pick a tablet first — the Virtual Tablet, in Input Devices." }
        if !input.targetIsShowing { return "The page (or a note, in Notebook mode) has to be on screen for the pen to write on." }
        return nil
    }

    /// Play a recording through the one door: on the field it was recorded
    /// on, at `speed` times the pace it happened at — or, with `stepping`,
    /// held at its start for `replay.step()` to deliver an event at a time.
    @discardableResult
    func play(_ recording: PenRecording, speed: Double = 1, stepping: Bool = false) -> PenReplay? {
        if let blocker = replayBlocker {
            say(blocker)
            return nil
        }
        stopReplay()
        if let extent = recording.header.extent { input.extent = extent }
        let replay = PenReplay(recording, clock: clock)
        input.attach(replay)
        self.replay = replay
        if stepping {
            replay.hold()
        } else {
            replay.play(speed: speed)
        }
        say(stepping ? "Stepping through \(recording.entries.count) events."
                     : "Playing \(recording.entries.count) events.")
        return replay
    }

    /// Read a recording from `url` and play it. A file that is not a whole
    /// recording is not played, and the status says why.
    @discardableResult
    func play(contentsOf url: URL, speed: Double = 1, stepping: Bool = false) -> PenReplay? {
        do {
            return play(try PenRecording(contentsOf: url), speed: speed, stepping: stepping)
        } catch {
            let why = (error as? PenRecording.Failure)?.description ?? error.localizedDescription
            say("\(url.lastPathComponent) cannot be played: \(why)")
            return nil
        }
    }

    /// Stop the replay in hand: the pen is lifted where it was.
    func stopReplay() {
        replay?.stop()
        replay = nil
    }
}
