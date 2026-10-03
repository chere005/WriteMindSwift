import AppKit
import SwiftUI
import UniformTypeIdentifiers

// THE VIRTUAL TABLET'S PANEL (Sean, 2026-10-03: "make sure i can develop
// wacom features without a device plugged in"): a small floating window with
// a pad drawn at the tablet's turned shape — the mouse or trackpad over it
// is the pen: moving is hovering, pressing is the nib down — a pressure
// slider, the two side switches as buttons (hold, tap, double press), the
// eraser toggle, and the developer's record and replay.
//
// IT IS A WINDOW OF ITS OWN, not a view over the pane: the pad is an AppKit
// view and over the notes or the page that would be handed every cursorUpdate
// (AGENTS.md, the eighth cause); in a window of its own it is nobody's but its
// own. The pad's model is `VirtualTablet`, which has no view in it, and the
// test script drives the same one.

// MARK: - The pad

/// The tablet's field as it lies, turned the way the page is: the pen is
/// wherever the pointer is on it. All the arithmetic is the model's
/// (`VirtualTablet.padMove`); this view only turns events into fractions of
/// itself.
final class VirtualPadView: NSView {
    weak var tablet: VirtualTablet?
    /// How the tablet is held, for the light's place.
    var quarterTurns = 1 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A crosshair: the pointer is a pen here.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // Always: the panel is a floating one, and the main window is the
        // key one while the pen hovers over the pad.
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways,
                                                           .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    // MARK: Events

    /// The pointer's place on the pad, fractions of it from the top left.
    func fraction(of event: NSEvent) -> CGPoint {
        fraction(ofWindowPoint: event.locationInWindow)
    }

    func fraction(ofWindowPoint point: CGPoint) -> CGPoint {
        let local = convert(point, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        return CGPoint(x: min(max(local.x / bounds.width, 0), 1), y: min(max(local.y / bounds.height, 0), 1))
    }

    override func mouseEntered(with event: NSEvent) { move(event) }
    override func mouseMoved(with event: NSEvent) { move(event) }
    override func mouseDragged(with event: NSEvent) { move(event) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        heldKeys(event.modifierFlags)
        tablet?.padDown(at: fraction(of: event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        heldKeys(event.modifierFlags)
        tablet?.padUp(at: fraction(of: event))
        needsDisplay = true
    }

    private func move(_ event: NSEvent) {
        heldKeys(event.modifierFlags)
        tablet?.padMove(to: fraction(of: event))
        needsDisplay = true
    }

    /// ⇧ holds the lower switch and ⌥ the upper, while they are down: a way
    /// to hold a switch while drawing.
    private func heldKeys(_ flags: NSEvent.ModifierFlags) {
        tablet?.keysHeld(lower: flags.contains(.shift), upper: flags.contains(.option))
    }

    override func flagsChanged(with event: NSEvent) {
        heldKeys(event.modifierFlags)
        needsDisplay = true
    }

    /// The wheel is the pressure: scrolling up presses harder.
    override func scrollWheel(with event: NSEvent) {
        let step = event.hasPreciseScrollingDeltas ? 0.004 : 0.03
        tablet?.nudgePressure(by: Double(event.scrollingDeltaY) * step)
        needsDisplay = true
    }

    /// 1…9 and 0 are a tenth of the way up to full, [ and ] a step down and
    /// up. Anything else is not the pad's.
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty,
              let characters = event.charactersIgnoringModifiers, let tablet else {
            super.keyDown(with: event)
            return
        }
        switch characters {
        case "[": tablet.nudgePressure(by: -VirtualTablet.pressureStep)
        case "]": tablet.nudgePressure(by: VirtualTablet.pressureStep)
        default:
            guard let digit = Int(characters), characters.count == 1 else { super.keyDown(with: event); return }
            tablet.setPressure(digit: digit)
        }
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        outline.fill()
        NSColor(calibratedWhite: 0.45, alpha: 1).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        // The tablet's light, where the light is.
        let led = TabletOrientation(quarterTurns: quarterTurns).ledPoint
        let inset: CGFloat = 8
        let dot = CGPoint(x: min(max(led.x * bounds.width, inset), bounds.width - inset),
                          y: min(max(led.y * bounds.height, inset), bounds.height - inset))
        NSColor(calibratedRed: 0.55, green: 0.8, blue: 1, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)).fill()

        guard let tablet, let page = tablet.padPoint else {
            drawCaption("Move the pointer here — it is the pen")
            return
        }
        let at = CGPoint(x: page.x * bounds.width, y: page.y * bounds.height)
        let down = tablet.isDown
        let radius = 5 + CGFloat(tablet.pressure) * 9
        let ring = NSBezierPath(ovalIn: CGRect(x: at.x - radius, y: at.y - radius, width: 2 * radius, height: 2 * radius))
        let colour: NSColor = tablet.lowerHeld || tablet.pen.switches.contains(.lower) ? .systemRed
            : (tablet.pen.switches.contains(.upper) ? .systemOrange : .controlAccentColor)
        if down {
            colour.withAlphaComponent(0.55).setFill()
            ring.fill()
        }
        colour.setStroke()
        ring.lineWidth = 1.5
        ring.stroke()
    }

    private func drawCaption(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(calibratedWhite: 0.6, alpha: 1),
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}

/// The pad in the panel's SwiftUI.
private struct VirtualPad: NSViewRepresentable {
    @ObservedObject var tablet: VirtualTablet
    let quarterTurns: Int

    func makeNSView(context: Context) -> VirtualPadView {
        let view = VirtualPadView()
        view.tablet = tablet
        view.quarterTurns = quarterTurns
        return view
    }

    func updateNSView(_ view: VirtualPadView, context: Context) {
        view.tablet = tablet
        view.quarterTurns = quarterTurns
        view.needsDisplay = true
    }
}

// MARK: - The panel's contents

struct VirtualTabletView: View {
    @ObservedObject var tablet: VirtualTablet
    @ObservedObject var developer: TabletDeveloper
    @ObservedObject var appState: AppState
    let input: TabletInput

    /// The tablet's field, read off the funnel only when it changes.
    @State private var extent = TabletExtent.fallback
    @State private var speed = 1.0

    /// The pad's box: the tablet's turned shape as big as fits it — tall
    /// held one quarter turn, wide held as it ships — so the window is the
    /// same size whichever way the tablet is turned.
    static let padBox: CGFloat = 300

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                VirtualPad(tablet: tablet, quarterTurns: appState.tabletQuarterTurns)
                    .aspectRatio(TabletMapping.aspect(of: extent, quarterTurns: appState.tabletQuarterTurns),
                                 contentMode: .fit)
                    .frame(width: Self.padBox, height: Self.padBox)
                penRow
            }
            .frame(width: Self.padBox)
            VStack(alignment: .leading, spacing: 12) {
                if let silence = developer.silence {
                    Label(silence, systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                pressureRow
                Divider()
                HStack(alignment: .top, spacing: 14) {
                    switchColumn(.lower, title: "Lower switch", detail: "hold: eraser\ndouble press: undo")
                    switchColumn(.upper, title: "Upper switch", detail: "hold: box\ndouble press: redo")
                }
                Toggle("Eraser — holds the lower switch", isOn: Binding(get: { tablet.eraser },
                                                                        set: { tablet.eraser = $0 }))
                    .help("The pen's eraser is its lower switch held as the nib goes down")
                Text("⇧ held over the pad is the lower switch, ⌥ the upper. 1–9 and 0, [ ] or the wheel set the pressure.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                developerRow
            }
            .frame(width: 290)
        }
        .padding(14)
        .onReceive(input.$extent.removeDuplicates()) { extent = $0 }
    }

    private var penRow: some View {
        HStack {
            Label(tablet.isDown ? "Nib down" : (tablet.isNear ? "Hovering" : "Pen away"),
                  systemImage: tablet.isDown ? "pencil.tip" : (tablet.isNear ? "hand.point.up.left" : "moon.zzz"))
                .font(.caption)
            Spacer()
            Button("Take the pen away") { tablet.penAway() }
                .controlSize(.small)
                .disabled(!tablet.isNear)
        }
    }

    private var pressureRow: some View {
        HStack(spacing: 8) {
            Text("Pressure").font(.caption)
            Slider(value: $tablet.pressure, in: 0...1)
            Text("\(Int((tablet.pressure * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func switchColumn(_ which: PenSwitch, title: String, detail: String) -> some View {
        let held = which == .lower ? tablet.lowerHeld : tablet.upperHeld
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            Toggle("Hold", isOn: Binding(get: { held }, set: { tablet.hold(which, $0) }))
                .toggleStyle(.button)
            HStack(spacing: 6) {
                Button("Tap") { tablet.tap(which) }
                Button("Double") { tablet.doublePress(which) }
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var developerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if developer.isRecording { developer.stopRecording() } else { developer.startRecording() }
                } label: {
                    Label(developer.isRecording ? "Stop Recording" : "Record", systemImage: "record.circle")
                        .foregroundStyle(developer.isRecording ? Color.red : Color.primary)
                }
                Button("Replay…") { developer.chooseAndPlay(speed: speed) }
                if let replay = developer.replay {
                    ReplayControls(replay: replay, developer: developer)
                }
            }
            Picker("Speed", selection: $speed) {
                Text("½×").tag(0.5)
                Text("1×").tag(1.0)
                Text("2×").tag(2.0)
                Text("4×").tag(4.0)
                Text("Max").tag(PenReplay.asFastAsPossible)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let status = developer.status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let last = developer.lastRecording {
                Button("Show \(last.lastPathComponent) in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([last])
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
    }
}

/// Play on, hold, step and stop, for the replay in hand.
private struct ReplayControls: View {
    @ObservedObject var replay: PenReplay
    @ObservedObject var developer: TabletDeveloper

    var body: some View {
        HStack(spacing: 6) {
            if replay.isPlaying {
                Button { replay.pause() } label: { Image(systemName: "pause.fill") }
            } else {
                Button { replay.play(speed: replay.speed) } label: { Image(systemName: "play.fill") }
                    .disabled(replay.state == .finished)
            }
            Button { replay.step() } label: { Image(systemName: "forward.frame.fill") }
                .disabled(replay.state == .finished)
                .help("Deliver the next event")
            Button { developer.stopReplay() } label: { Image(systemName: "stop.fill") }
            Text("\(replay.delivered)/\(replay.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

extension TabletDeveloper {
    /// Ask for a recording and play it — the menu's and the panel's
    /// "Replay…". The panel starts in the recordings folder. `choosing` is
    /// how a file is asked for (a test hands in its own).
    func chooseAndPlay(speed: Double = 1, stepping: Bool = false, choosing: (() -> URL?)? = nil) {
        // A replay that would not be heard is said BEFORE a file is asked
        // for: picking one and then finding nothing happened is the worst
        // way to be told (`replayBlocker`, which `play` would say as well).
        if let blocker = replayBlocker {
            say(blocker)
            return
        }
        // A chooser that gives nothing was cancelled; no chooser is the panel.
        let chosen: URL? = choosing.map { $0() } ?? Self.askForRecording()
        guard let url = chosen else { return }
        play(contentsOf: url, speed: speed, stepping: stepping)
    }

    static func askForRecording() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Replay a Pen Session"
        panel.message = "Pick a pen recording (.ndjson)."
        panel.allowedContentTypes = [UTType(filenameExtension: "ndjson") ?? .json, .json, .plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = recordingsDirectory
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The recordings folder, shown in Finder (made first, so there is one).
    func revealRecordings() {
        try? FileManager.default.createDirectory(at: Self.recordingsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.recordingsDirectory)
    }
}

// MARK: - The window

/// The panel: floating, only as key as it needs to be, forgotten when
/// closed. One per app (`shared`); a test makes its own with `makePanel`.
@MainActor
final class VirtualTabletPanel: NSObject, NSWindowDelegate {
    static let shared = VirtualTabletPanel()

    private var panel: NSPanel?
    private weak var tablet: VirtualTablet?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// The window and what is in it, not yet shown.
    static func makePanel(tablet: VirtualTablet, developer: TabletDeveloper, appState: AppState,
                          input: TabletInput) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Virtual Tablet"
        panel.isFloatingPanel = true
        // A click on the pad makes it key (the pad asks), a click on a
        // button does not: the main window stays the one typed in.
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        let view = FirstMouseHostingView(rootView: VirtualTabletView(tablet: tablet, developer: developer,
                                                                    appState: appState, input: input))
        panel.contentView = view
        panel.setContentSize(view.fittingSize)
        return panel
    }

    /// Show the panel, making it the first time.
    func show(tablets: TabletController, appState: AppState) {
        attach(tablets.developer.virtual)
        if panel == nil {
            let panel = Self.makePanel(tablet: tablets.developer.virtual, developer: tablets.developer,
                                       appState: appState, input: tablets.input)
            panel.delegate = self
            panel.setFrameAutosaveName("WriteMindVirtualTablet")
            self.panel = panel
        }
        panel?.orderFront(nil)
    }

    /// Whose pen goes out of reach with the window — `hide` and closing.
    /// Apart from `show` so a test can have a panel with a pen and no window.
    func attach(_ tablet: VirtualTablet) {
        self.tablet = tablet
    }

    func hide() {
        panel?.orderOut(nil)
        tablet?.penAway()
    }

    /// Closed with the red button: the pen goes out of reach with it.
    func windowWillClose(_ notification: Notification) {
        tablet?.penAway()
    }
}

/// A hosting view that takes the click that brings its window forward as a
/// click on the control under it.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
