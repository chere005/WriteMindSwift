import AppKit
import SwiftUI

/// The right pane when a Wacom tablet is the input: THE PAGE the pen writes
/// on, where the video would be (Sean, 2026-10-02: "in normal mode its as if
/// we were looking at the picture of a page").
///
/// A sheet of paper at the tablet's own shape, turned the way the tablet is
/// held — one quarter turn clockwise unless he turns it back — with what has
/// been written on it (`TabletPage`, kept across launches), the stroke being
/// written, a marker where the nib is hovering, and the box that takes a
/// piece of the page into the note as a picture, as ink or as words.
///
/// While the pen writes in the NOTEBOOK ("Write on: Page | Notebook", on the
/// bar) the sheet is set aside — dimmed, with one line saying where the pen
/// is writing — and the switch on the bar is the way back; the page itself
/// is left exactly as it was.
struct TabletPane: View {
    @EnvironmentObject private var tablet: TabletController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NoteStore
    @ObservedObject private var sheet = TabletPage.shared
    /// The page's shape follows the tablet's size, which is read off the
    /// funnel only when it CHANGES — never at the pen's rate.
    @State private var extent = TabletExtent.fallback
    /// Esc, while a box is up.
    @State private var keyMonitor: Any?
    /// A note is on screen for the pen to write in, in Notebook mode — read
    /// off the funnel only when it CHANGES.
    @State private var notesShowing = false

    private var input: TabletInput { tablet.input }
    private var scribe: TabletScribe { .shared }

    /// Between the sheet and the sides of the pane.
    nonisolated static let margin: CGFloat = 18
    /// Above and below it: room for the corner's buttons and the status
    /// line, so that neither sits on the writing (a first render had the
    /// turn buttons over the page's top corner).
    nonisolated static let band: CGFloat = 44

    /// Where the sheet sits in a pane this size: the tablet's shape turned,
    /// as big as fits. The page's layers draw into exactly this.
    nonisolated static func pageFrame(in pane: CGSize, extent: TabletExtent, quarterTurns: Int) -> CGRect {
        let room = CGSize(width: pane.width, height: max(pane.height - 2 * (band - margin), 1))
        return TabletMapping.fit(aspect: TabletMapping.aspect(of: extent, quarterTurns: quarterTurns),
                                 in: room, margin: margin)
            .offsetBy(dx: 0, dy: band - margin)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            // The arrow, claimed for this pane as the camera's claims it —
            // otherwise the notebook's pencil follows the pointer over here.
            CursorLayer(cursor: .arrow)
                .allowsHitTesting(false)
            content
            topRow
        }
        .clipped()
        .paneTipHost()
        .onReceive(input.$extent.removeDuplicates()) { extent = $0 }
        .onReceive(input.$notebookIsShowing.removeDuplicates()) { notesShowing = $0 }
    }

    /// The pen writes on this page, not in the notebook.
    private var writesOnPage: Bool { appState.tabletTarget == .page }

    /// The line on the page while it is set aside.
    /// The line on the page while it is set aside: where the pen is
    /// writing — and with no note on screen it is writing nowhere and is a
    /// pointer again (`TabletInput.targetIsShowing`), so the page says THAT,
    /// not that it is writing on the notebook.
    nonisolated static func setAsideLine(notesShowing: Bool) -> String {
        notesShowing ? "The pen is writing on the notebook"
                     : "No note on screen to write in — the pen is a pointer until there is"
    }

    /// The bar on the left and the corner's buttons on the right, IN ONE
    /// ROW, so the bar is offered only the width the corner leaves it and
    /// picks the shape of itself that fits (`TabletBar`) — laid over each
    /// other, a bar that grew a switch would run under the corner's buttons
    /// on a pane of the width the split gives it.
    private var topRow: some View {
        HStack(alignment: .top, spacing: 8) {
            bar
            Spacer(minLength: 0)
            corners
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - What the pane shows

    @ViewBuilder private var content: some View {
        switch tablet.status {
        case .off:
            placeholder(icon: "pencil.tip", title: "No tablet selected",
                        detail: "Pick one from the Input Devices menu.") { InputDevicePicker() }
        case .unplugged:
            placeholder(icon: "cable.connector.slash", title: "\(name) is unplugged",
                        detail: "Plug it back in and the page comes back — or pick a camera.") { InputDevicePicker() }
        case .connecting, .ready, .unavailable:
            page
        }
    }

    private var name: String { tablet.selectedTablet?.name ?? tablet.selectedName ?? "The tablet" }

    private var page: some View {
        GeometryReader { geo in
            let turns = appState.tabletQuarterTurns
            let frame = Self.pageFrame(in: geo.size, extent: extent, quarterTurns: turns)
            let pageSize = TabletPage.size(aspect: TabletMapping.aspect(of: extent, quarterTurns: turns))
            let millimetres = TabletMapping.millimetres(of: extent, quarterTurns: turns)
            ZStack(alignment: .topLeading) {
                // A click on the pane round the sheet puts a box away.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { scribe.box.rect = nil }
                TabletSheetView(page: sheet, scribe: scribe, pageSize: pageSize, size: frame.size,
                                theme: sheet.theme, millimetres: millimetres,
                                canTake: store.selectedNote != nil && writesOnPage, busy: store.isCapturing,
                                onFullWindow: { appState.toggleCameraFullWindow() },
                                onTake: { choice, box in
                                    take(choice, box: box, pageSize: pageSize, millimetres: millimetres)
                                })
                    .position(x: frame.midX, y: frame.midY)
                if writesOnPage {
                    TabletHoverMarker(input: input, page: frame)
                } else {
                    PageSetAside(frame: frame, notesShowing: notesShowing)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: turns)
            // The page's own pen, off the bar in the corner — its width as
            // it is SEEN on this page at this size (`TabletInk.width`).
            .onChange(of: Self.ink(colorHex: appState.pageInkHex, penWidth: appState.pageInkWidth,
                                   tool: appState.pageInkTool, viewScale: frame.width / max(pageSize.width, 1)),
                      initial: true) { _, ink in scribe.ink = ink }
        }
        .overlay(alignment: .bottomLeading) { statusLine }
        // The pen is the page's only while the page is on screen.
        .onAppear {
            sheet.align(to: appState.tabletQuarterTurns)
            let state = appState
            scribe.onWrite = { [weak state] in state?.pageWritten() }
            input.pageAppeared()
            // Esc for the box when no drawing layer is up to ask it in its
            // own chain (`TabletBox.paneAnswersEscape`).
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                MainActor.assumeIsolated {
                    guard TabletBox.paneAnswersEscape(layersWatching: DrawingCanvas.keyWatchers) else { return event }
                    return TabletScribe.shared.box.key(event)
                }
            }
        }
        .onDisappear {
            input.pageDisappeared()
            scribe.box.rect = nil
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onChange(of: appState.tabletQuarterTurns) { _, turns in
            // The ink turns with the sheet; a box drawn the old way round
            // would be over some other part of it now. (The funnel is told
            // the turn by the app, whichever pane is up.)
            sheet.align(to: turns)
            scribe.box.rect = nil
        }
    }

    /// What the scribe writes with — the page pen's colour, its width as
    /// seen on the page, and its tool.
    nonisolated static func ink(colorHex: String, penWidth: Double, tool: InkTool = .pen,
                                viewScale: CGFloat) -> TabletInk {
        TabletInk(colorHex: colorHex, width: TabletInk.width(penWidth: penWidth, viewScale: viewScale), tool: tool)
    }

    /// One of the box's three into the note, and the box put away. Image
    /// takes the paper with it, printed as the pane prints it.
    private func take(_ choice: TabletChoice, box: CGRect, pageSize: CGSize, millimetres: CGSize) {
        // As the camera's capture does: the pen is put down so what has
        // just arrived can be picked up and dragged where it goes.
        if choice != .text { appState.canvasMode = .cursor }
        if store.takeFromTablet(choice, strokes: sheet.strokes, box: box, pageSize: pageSize,
                                theme: sheet.theme, millimetres: millimetres) {
            scribe.box.rect = nil
        }
    }

    /// Another paper under the writing — saved with the page — and, if the
    /// change leaves the pen's ink unreadable, the paper's own ink instead
    /// (`AppState.pagePaperChanged`). The paper in use, picked again, is
    /// no change at all.
    private func choose(_ theme: PageTheme) {
        let old = sheet.theme
        guard theme != old else { return }
        sheet.setTheme(theme)
        appState.pagePaperChanged(from: old, to: theme)
    }

    // MARK: - The bar

    /// The page's pen and paper and where the pen writes, top left, in the
    /// band above the sheet — shown whenever the corner's own buttons are.
    @ViewBuilder private var bar: some View {
        if showsPageControls {
            TabletBar(theme: sheet.theme, onTheme: choose, target: appState.tabletTarget,
                      onTarget: { appState.writeOn($0) })
        }
    }

    /// The page is up, so its controls are.
    private var showsPageControls: Bool {
        tablet.isSelected && tablet.status != .unplugged && tablet.status != .off
    }

    /// ONE LINE, bottom left where the camera pane names its camera: the
    /// tablet's name while the driver has the pen, and otherwise why the
    /// pen is moving the pointer as well.
    @ViewBuilder private var statusLine: some View {
        if let line = Self.line(for: tablet.status, name: name) {
            HStack(spacing: 8) {
                Label(line.text, systemImage: line.icon)
                    .font(.caption)
                    .lineLimit(2)
                if line.opensAutomation {
                    Button("Open Automation Settings") {
                        if let url = URL(string: Self.automationSettings) { NSWorkspace.shared.open(url) }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(12)
        }
    }

    nonisolated static let automationSettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    /// What the line says. Pure, so every status is known to have its words.
    struct StatusLine: Equatable {
        let icon: String
        let text: String
        /// Offer the way to System Settings › Privacy & Security › Automation.
        var opensAutomation = false
    }

    nonisolated static func line(for status: TabletController.Status, name: String) -> StatusLine? {
        let alsoPointer = "so the pen moves the pointer too"
        switch status {
        case .off, .unplugged:
            return nil
        case .ready:
            return StatusLine(icon: "pencil.tip", text: name)
        case .connecting:
            return StatusLine(icon: "ellipsis.circle", text: "Asking the Wacom driver to keep the pen on the page…")
        case .unavailable(let failure):
            switch failure {
            case .noDriver:
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "The Wacom driver isn't running, \(alsoPointer).")
            case .automationDenied:
                return StatusLine(icon: "hand.raised",
                                  text: "WriteMind isn't allowed to ask the Wacom driver, \(alsoPointer).",
                                  opensAutomation: true)
            case .needsConsent:
                return StatusLine(icon: "hand.raised",
                                  text: "Pick \(name) in Input Devices again to let WriteMind ask the Wacom driver — until then the pen moves the pointer too.")
            case .timedOut:
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "The Wacom driver didn't answer, \(alsoPointer).")
            case .noTablet:
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "The Wacom driver doesn't see the tablet yet, \(alsoPointer).")
            case .noReply:
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "The Wacom driver gave no answer, \(alsoPointer).")
            case .other(let status):
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "The Wacom driver said no (\(status)), \(alsoPointer).")
            case .refusedUnderTest:
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "A test run does not talk to the Wacom driver.")
            }
        }
    }

    // MARK: - The corner

    /// The page's undo, redo and clear; turning the page; and — with the
    /// notes put away — the way back to side by side, as on the camera
    /// pane. Undo is here and not only on ⌘Z because the page never has
    /// the keyboard: ⌘Z reaches it only straight after writing
    /// (`AppState.pageOwnsUndo`). The turn is here rather than on
    /// the bar's video panel because it turns THE TABLET, which only this
    /// pane shows; the panel's own turn is the camera's and is greyed out
    /// while no camera is running.
    private var corners: some View {
        HStack(spacing: 6) {
            // The page's own undo, redo and clear — ⌘Z and ⇧⌘Z reach the
            // same two while the page was written on last. Out of play while
            // the pen writes in the notebook — the page is set aside, and
            // the notes' own undo is the one in play — but IN THEIR PLACE,
            // so the bar beside them is offered the same room in both modes
            // and its switch keeps its shape (`TabletBar`).
            if showsPageControls {
                Group {
                    corner(icon: "arrow.uturn.backward", label: "Undo on the Page",
                           help: "Take back the last stroke on the page — ⌘Z does it too, straight after writing",
                           enabled: sheet.canUndo) {
                        if sheet.undo() { appState.pageWritten() }
                    }
                    corner(icon: "arrow.uturn.forward", label: "Redo on the Page",
                           help: "Put back what Undo took off the page", enabled: sheet.canRedo) {
                        if sheet.redo() { appState.pageWritten() }
                    }
                    corner(icon: "trash", label: "Clear the Page",
                           help: "Wipe the page clean — Undo brings it all back", enabled: !sheet.strokes.isEmpty) {
                        sheet.clear()
                        appState.pageWritten()
                    }
                    Divider().frame(height: 18)
                }
                .setAside(!writesOnPage)
            }
            // The turn is the TABLET'S, so it holds for the notebook too.
            if showsPageControls {
                corner(icon: "rotate.left", label: "Turn Left",
                       help: "Turn the page a quarter turn anticlockwise — the way the tablet sits on the desk") {
                    turn(by: -1)
                }
                corner(icon: "rotate.right", label: "Turn Right",
                       help: "Turn the page a quarter turn clockwise — the way the tablet sits on the desk") {
                    turn(by: 1)
                }
            }
            if !appState.showEditor {
                corner(icon: "rectangle.lefthalf.inset.filled", label: "Back to Side by Side",
                       help: "The notes and the page side by side again") {
                    appState.toggleEditorPane()
                }
            }
        }
    }

    /// The sheet comes round, and the ink on it in the SAME breath — left
    /// to the `onChange` behind it, one frame showed the old ink on the
    /// new shape. The `onChange` stays, for a turn that comes from
    /// anywhere else.
    private func turn(by quarterTurns: Int) {
        appState.rotateTablet(by: quarterTurns)
        sheet.align(to: appState.tabletQuarterTurns)
        scribe.box.rect = nil
    }

    private func corner(icon: String, label: String, help: String, enabled: Bool = true,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(enabled ? 1 : 0.35))
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .paneTip(BarTip(title: label, detail: help))
        .accessibilityLabel(label)
    }

    private func placeholder<Extra: View>(icon: String, title: String, detail: String,
                                          @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.white.opacity(0.5))
            Text(title).font(.title3).foregroundStyle(.white)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            extra().padding(.top, 6)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Where the nib is, over the page — or, in Notebook mode, over the area of
/// the notes the tablet lands on (`NotebookTabletLayer`). Its own view,
/// watching the funnel on its own, so that the pen's hundred-odd samples a
/// second redraw a dot and not the pane. A SwiftUI shape and not an NSView:
/// a hosted view over a pane takes every cursorUpdate there (AGENTS.md, the
/// eighth cause).
struct TabletHoverMarker: View {
    @ObservedObject var input: TabletInput
    let page: CGRect

    var body: some View {
        if let pen = input.pen {
            let down = pen.phase == .down || pen.phase == .drag
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .background(Circle().fill(Color.accentColor.opacity(down ? 0.45 : 0)))
                .frame(width: 12, height: 12)
                .position(x: page.minX + pen.page.x * page.width, y: page.minY + pen.page.y * page.height)
                .allowsHitTesting(false)
        }
    }
}

/// THE PAGE SET ASIDE while the pen writes in the notebook: the sheet
/// dimmed, and one line saying where the pen is writing — or that with no
/// note on screen it is not writing at all — and the switch on the bar
/// above is the way back. It takes the clicks on the sheet, so nothing is
/// boxed off a page the pen is not writing on; and it is a SwiftUI shape,
/// never an NSView (the eighth cause).
private struct PageSetAside: View {
    let frame: CGRect
    let notesShowing: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.62))
            Label(TabletPane.setAsideLine(notesShowing: notesShowing),
                  systemImage: notesShowing ? TabletTarget.notebook.icon : "cursorarrow")
                .font(.callout)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture {}
        .position(x: frame.midX, y: frame.midY)
        .accessibilityElement(children: .combine)
    }
}
