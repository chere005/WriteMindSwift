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

    /// The line on the page while it is set aside: where the pen is
    /// writing — and with no note on screen it is writing nowhere and is a
    /// pointer again (`TabletInput.targetIsShowing`), so the page says THAT,
    /// not that it is writing on the notebook. A note that shows as
    /// markdown is no place to write either (Sean, 2026-10-02: "only allow
    /// drawing in wysiwyg mode, both from wacom and from the pen cursor
    /// tool"), and the line says to bring the rendered page up, and how.
    nonisolated static func setAsideLine(notesShowing: Bool, rendered: Bool = true) -> String {
        if notesShowing { return "The pen is writing on the notebook" }
        return rendered ? "No note on screen to write in — the pen is a pointer until there is"
                        : "Show the rendered page (⌘T) to write on the notes — the pen is a pointer until then"
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
        case .standby, .captured, .fallback:
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
                    PageSetAside(frame: frame, notesShowing: notesShowing,
                                 rendered: appState.mode == .preview || store.selectedNote == nil)
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
            scribe.align(to: appState.tabletQuarterTurns)
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
            // The ink turns with the sheet, and the box with the ink — it
            // stays over the writing it was drawn round. (The funnel is
            // told the turn by the app, whichever pane is up.)
            scribe.align(to: turns)
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
        // As the camera's capture does: every tool is put away so what has
        // just arrived can be picked up and dragged where it goes.
        if choice != .text {
            appState.putToolsAway()
            // What is written or picked is drawing, and drawing is on the rendered page.
            appState.showRenderedPage()
        }
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

    /// ONE LINE, bottom left where the camera pane names its camera: that
    /// WriteMind has the pen, or why the pen is moving the pointer as well
    /// and the one thing to do about it (`line(for:name:)`).
    @ViewBuilder private var statusLine: some View {
        if let line = Self.line(for: tablet.status, name: name) {
            HStack(spacing: 8) {
                Label(line.text, systemImage: line.icon)
                    .font(.caption)
                    .lineLimit(2)
                if line.opensSettings {
                    Button("Open Input Monitoring Settings") {
                        if let url = URL(string: Self.inputMonitoringSettings) { NSWorkspace.shared.open(url) }
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

    // MARK: - The corner

    /// The page's undo, redo and clear; how the tablet sits; and — with
    /// the notes put away — the way back to side by side, as on the camera
    /// pane. Undo is here and not only on ⌘Z because the page never has
    /// the keyboard: ⌘Z reaches it only straight after writing
    /// (`AppState.pageOwnsUndo`). The turn is here rather than on the
    /// bar's video panel because it turns THE TABLET, which only this pane
    /// shows; the panel's own turn is the camera's and is greyed out while
    /// no camera is running. It is ONE control, the four ways round by
    /// name (`TabletOrientationButton`), in the place of the two
    /// quarter-turn buttons that were here: a second control for the turn
    /// anywhere else on screen breaks EVERY BUTTON HAS EXACTLY ONE PLACE.
    private var corners: some View {
        HStack(spacing: 6) {
            // The page's own undo, redo and clear — ⌘Z and ⇧⌘Z reach the
            // same two while the page was written on last, and so does a
            // click of the pen's own buttons (`undoTip`). Out of play while
            // the pen writes in the notebook — the page is set aside, and
            // the notes' own undo is the one in play — but IN THEIR PLACE,
            // so the bar beside them is offered the same room in both modes
            // and its switch keeps its shape (`TabletBar`).
            if showsPageControls {
                Group {
                    corner(icon: "arrow.uturn.backward", label: "Undo on the Page",
                           help: Self.undoTip, enabled: sheet.canUndo) {
                        if sheet.undo() { appState.pageWritten() }
                    }
                    corner(icon: "arrow.uturn.forward", label: "Redo on the Page",
                           help: Self.redoTip, enabled: sheet.canRedo) {
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
                TabletOrientationButton(orientation: appState.tabletOrientation, target: appState.tabletTarget,
                                        onPick: orient)
            }
            if !appState.showEditor {
                corner(icon: "rectangle.lefthalf.inset.filled", label: "Back to Side by Side",
                       help: "The notes and the page side by side again") {
                    appState.toggleEditorPane()
                }
            }
        }
    }

    /// The tablet sits another way: the sheet comes round, and the ink on
    /// it in the SAME breath — left to the `onChange` behind it, one frame
    /// showed the old ink on the new shape. The `onChange` stays, for a
    /// turn that comes from anywhere else.
    private func orient(_ orientation: TabletOrientation) {
        appState.orientTablet(orientation)
        scribe.align(to: appState.tabletQuarterTurns)
    }

    /// WHAT THE PAGE'S UNDO AND REDO SAY UNDER THE POINTER — every way to
    /// each, the pen's own buttons among them (Sean, 2026-10-02: "make the
    /// wacom buttons undo and redo last drawing", then 2026-10-03: "a double
    /// press of that same button is undo", "double tap to redo"): a double
    /// press of the lower one in the air is this Undo, of the upper one this
    /// Redo. Redo's says what it needs: by the driver's events the upper
    /// button has been seen only with the nib down, so its double tap is
    /// promised only captured.
    nonisolated static let undoTip = "Take back the last stroke on the page — ⌘Z does it too, straight after "
        + "writing, and so does a double press of the pen's lower button with the nib off the tablet"
    nonisolated static let redoTip = "Put back what Undo took off the page — and so does a double tap of the pen's "
        + "upper button with the nib off the tablet, while the pen is captured"

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

/// HOW THE TABLET SITS — the one control for the turn, in the page's corner
/// (Sean, 2026-10-02: "make sure i can orient the page with the device by
/// rotating or flipping to make it match portrait or landscape"): the tablet
/// drawn the way it lies, its light where the light is (`TabletGlyph`),
/// opening the four ways round by name. A button opening a popover, as the
/// paper's does — a SwiftUI `Menu` is an AppKit control hosted over the
/// pane (the eighth cause). It is the TABLET'S, so it holds for the
/// notebook as for the page, and the popover says what a turn does to
/// whichever the pen is writing on.
struct TabletOrientationButton: View {
    let orientation: TabletOrientation
    /// Where the pen writes — what the popover's last line is about.
    let target: TabletTarget
    let onPick: (TabletOrientation) -> Void
    @State private var showing = false

    /// The tablet's long side on the button, in points — with the corner's
    /// padding, one of the corner's buttons.
    static let glyph: CGFloat = 14

    var body: some View {
        Button { showing.toggle() } label: {
            TabletGlyph(orientation: orientation, size: Self.glyph, onPane: true)
                .foregroundStyle(Color.primary)
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .paneTip(BarTip(title: "How the Tablet Sits",
                        detail: "\(orientation.title), \(orientation.detail.lowercasedFirst)"))
        .accessibilityLabel("How the Tablet Sits: \(orientation.title)")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            TabletOrientationMenu(current: orientation, target: target) { picked in
                showing = false
                onPick(picked)
            }
        }
    }
}

/// The four ways round, a row each — the tablet drawn that way, its name,
/// what was done to it and where that leaves its light, the one in use
/// ticked — and under them what a turn does to what the pen writes on, and
/// what the drawing's dot is.
struct TabletOrientationMenu: View {
    let current: TabletOrientation
    let target: TabletTarget
    let onPick: (TabletOrientation) -> Void

    /// Wide enough that the way it sits by default — "A quarter turn
    /// clockwise · light at the top" — is one line under its name.
    static let width: CGFloat = 350

    var body: some View {
        PickList(title: "How the Tablet Sits", footer: Self.footer(for: target), width: Self.width) {
            ForEach(TabletOrientation.allCases) { orientation in
                PickRow(title: orientation.title, detail: orientation.detail,
                        isCurrent: orientation == current, action: { onPick(orientation) }) {
                    TabletGlyph(orientation: orientation, size: 26).foregroundStyle(Color.primary)
                }
            }
        }
    }

    /// The popover's last line: what a turn does to what the pen writes
    /// on. The page's writing turns with it, each stroke staying where it
    /// is on the tablet, and its paper is laid for the new shape; a NOTE'S
    /// strokes are the note's and never turn — only the tablet's area on
    /// the notes does. And what the drawing's dot is (Sean, 2026-10-02:
    /// "show the led on the tablet for the icon to give orientation") — a
    /// dot nobody has named is one more shape.
    nonisolated static func footer(for target: TabletTarget) -> String {
        let light = "The dot is the tablet's light — \(TabletOrientation.landscape.lightPlace) as it ships."
        switch target {
        case .page:
            return "The page turns to match, and its writing with it — each stroke stays where it is on the "
                + "tablet. The paper's lines are laid out again for the new shape. " + light
        case .notebook:
            return "The tablet's area on the notes turns to match. What is already in the note stays where "
                + "it was written. " + light
        }
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

    /// WHAT THE PEN IS, as the marker shows it: ink, the lower switch's
    /// eraser or the upper's box — held in the air (what the nib will be
    /// when it goes down) or latched for the stroke under way (Sean,
    /// 2026-10-03).
    enum Mode: Equatable {
        case ink, eraser, box
    }

    static func mode(of pen: TabletSample) -> Mode {
        if pen.eraser || pen.holding == .lower { return .eraser }
        if pen.sideSwitch || pen.holding == .upper { return .box }
        return .ink
    }

    var body: some View {
        if let pen = input.pen {
            let down = pen.phase == .down || pen.phase == .drag
            let mode = Self.mode(of: pen)
            let at = CGPoint(x: page.minX + pen.page.x * page.width, y: page.minY + pen.page.y * page.height)
            Group {
                switch mode {
                case .ink:
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .background(Circle().fill(Color.accentColor.opacity(down ? 0.45 : 0)))
                        .frame(width: 12, height: 12)
                case .eraser:
                    // A bigger, dashed ring in red: what it touches goes.
                    Circle()
                        .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .background(Circle().fill(Color.red.opacity(down ? 0.3 : 0)))
                        .frame(width: 20, height: 20)
                case .box:
                    Rectangle()
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .background(Rectangle().fill(Color.accentColor.opacity(down ? 0.3 : 0)))
                        .frame(width: 14, height: 14)
                }
            }
            .position(at)
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
    /// The view is not what stops the pen (`setAsideLine`).
    let rendered: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.62))
            Label(TabletPane.setAsideLine(notesShowing: notesShowing, rendered: rendered),
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
