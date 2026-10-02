import AppKit
import SwiftUI

/// The right pane: whatever camera the Input Devices menu picked.
struct CameraPane: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NoteStore

    /// A box drawn on the picture: the capture button then brings in just
    /// that part of the page. Nothing arms it and nothing confirms it — a
    /// drag on the picture IS the box, a click clears it, a double-click
    /// takes the whole picture (Sean, 2026-09-19: "instead select a box for
    /// selecting by clicking and dragging .. click to get rid of a
    /// selection.. double click to select the whole image").
    @State private var section: CGRect?
    /// Armed to drag the box the pane zooms into (Sean, 2026-09-19: "drag a
    /// square to resize camera").

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            // The pen's pencil belongs to the note and nowhere else. A
            // cursor set anywhere is set EVERYWHERE until something else
            // sets one, and this pane set none — so the pencil followed
            // the pointer over here (Sean, 2026-09-20: "cursor only
            // becomes a pen in the notes pane in drawing mode!!!!!").
            // Claiming the arrow is what takes it back.
            CursorLayer(cursor: .arrow)
                .allowsHitTesting(false)
            switch camera.status {
            case .running:
                GeometryReader { outer in
                    // THE VIEWFINDER IS THE SHAPE THAT WAS ASKED FOR, and
                    // the pane is whatever the divider makes it (Sean,
                    // 2026-09-21: "add aspect ratio control"). Everything
                    // below is measured against `size` and not against the
                    // pane, so the box you drag, the zoom and what the
                    // capture brings in all go on meaning what they meant
                    // — inside the rectangle instead of inside the pane.
                    // `free` hands the pane straight back, which is what
                    // this was before there was a choice.
                    let size = appState.cameraAspect.fit(in: outer.size)
                    ZStack(alignment: .topLeading) {
                        // Turned inside the pane, not with it: at a quarter
                        // turn the preview is given the pane's height as its
                        // width, so the picture still fits after it comes round.
                        CameraPreview(session: camera.session)
                            .frame(width: appState.cameraIsTurned ? size.height : size.width,
                                   height: appState.cameraIsTurned ? size.width : size.height)
                            .rotationEffect(.degrees(Double(appState.cameraRotation)))
                            .position(x: size.width / 2, y: size.height / 2)
                            // Zoomed by moving the whole picture, not by
                            // touching the camera: the box the pane is
                            // showing is blown up to fill it.
                            .scaleEffect(zoomScale(in: size))
                            .offset(zoomOffset(in: size))
                            .clipped()
                        SectionBox(section: $section, size: size,
                                   busy: store.isCapturing,
                                   onWholePicture: { section = wholePictureBox(pane: size) },
                                   onFullWindow: { appState.toggleCameraFullWindow() },
                                   onInsert: { mode in insertSection(mode, pane: size) },
                                   onRead: { readSection(pane: size) })
                            .disabled(store.selectedNote == nil)
                        if appState.cameraZooming {
                            BoxDragger(hint: "Drag a box — the pane shows that much") { box in
                                appState.cameraZoom = CameraZoom.compose(box, over: appState.cameraZoom,
                                                                         in: size)
                                appState.cameraZooming = false
                            }
                        }
                    }
                    // Centred in the pane, with the pane's own black
                    // round it — the same black the letterbox bars of a
                    // wide picture in a tall pane have always been, so a
                    // chosen shape looks like the picture and not like a
                    // window with a hole in it.
                    .frame(width: size.width, height: size.height)
                    .position(x: outer.size.width / 2, y: outer.size.height / 2)
                }
            case .starting:
                ProgressView().controlSize(.large).tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .idle:
                placeholder(icon: "video", title: "No camera selected",
                            detail: "Pick one from the Input Devices menu.") {
                    devicePicker
                }
            case .denied:
                placeholder(icon: "video.slash", title: "Camera access is off",
                            detail: "Allow WriteMind in System Settings › Privacy & Security › Camera.") {
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            case .failed(let message):
                placeholder(icon: "exclamationmark.triangle", title: "Camera unavailable", detail: message) {
                    devicePicker
                }
            }

            if camera.status == .running, let name = camera.selectedDeviceName {
                VStack {
                    Spacer()
                    HStack {
                        Label(name, systemImage: "video.fill")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                    .padding(12)
                }
            }

            // Turning the picture, its size and the box to zoom into are
            // all on the editor's bar now, under the button that shows and
            // hides the video. The ONE thing left here is the way back from
            // whole screen — and only then, because with the notes pane
            // away there is no bar to put it on.
            HStack(spacing: 6) {
                if !appState.showEditor {
                    corner(icon: "rectangle.lefthalf.inset.filled", label: "Back to Side by Side",
                           help: "The notes and the video side by side again",
                           keys: ["⌃", "⌘", "E"]) {
                        appState.toggleEditorPane()
                    }
                }
            }
            .padding(10)
        }
        .clipped()
        // The pane draws its own tooltip bubbles: the same ones the editor's
        // bar has, which its buttons never got (Sean, 2026-09-19: "the
        // camera pane's own buttons never had the tooltip treatment the
        // editor's bar got"). Applied after `.clipped()` so a bubble is not
        // cut off by the picture's own clip.
        .paneTipHost()
        .onChange(of: camera.status) { _, status in
            if status != .running { section = nil; appState.cameraZooming = false }
        }
        .onChange(of: appState.cameraRotation) { _, _ in section = nil }
    }

    // MARK: - The zoom

    private func zoomScale(in pane: CGSize) -> CGFloat {
        guard let box = appState.cameraZoom else { return 1 }
        return CameraZoom.scale(of: box, in: pane)
    }

    private func zoomOffset(in pane: CGSize) -> CGSize {
        guard let box = appState.cameraZoom else { return .zero }
        return CameraZoom.offset(of: box, in: pane)
    }

    /// The box a double-click draws: the picture as it is actually on
    /// screen. Not the whole pane — the video is letterboxed inside it, and
    /// a box over the bars would be a lie (the capture clips it anyway).
    /// Zoomed in, it is the part of the picture that can be seen, which is
    /// what is being captured.
    private func wholePictureBox(pane: CGSize) -> CGRect? {
        guard let frame = camera.currentFrame() else { return nil }
        let raw = frame.extent.size
        let upright = appState.cameraIsTurned ? CGSize(width: raw.height, height: raw.width) : raw
        let shown = NotebookCapture.displayedFrame(of: upright, in: pane)
        guard shown.width > 2, shown.height > 2 else { return nil }
        let drawn = appState.cameraZoom.map { CameraZoom.zoomed(shown, box: $0, in: pane) } ?? shown
        let visible = drawn.intersection(CGRect(origin: .zero, size: pane))
        guard !visible.isNull, visible.width >= 2, visible.height >= 2 else { return nil }
        return visible
    }

    /// The box as an object on the page: the picture as it is, or the
    /// writing inside it lifted as ink.
    private func insertSection(_ mode: NotebookCapture.Mode, pane: CGSize) {
        guard let region = boxRegion(pane: pane) else { return }
        // Every tool put away, so what arrives can be picked up and
        // dragged where it goes — an armed shape would take that click.
        appState.putToolsAway()
        store.captureNotebook(frame: camera.currentFrame(), quarterTurns: appState.cameraRotation / 90,
                              colour: NSColor(appState.penColor), mode: mode, region: region)
        section = nil
    }

    /// The box read into the note as words.
    private func readSection(pane: CGSize) {
        guard let region = boxRegion(pane: pane) else { return }
        store.readCamera(frame: camera.currentFrame(), quarterTurns: appState.cameraRotation / 90,
                         region: region)
        section = nil
    }

    /// The box that was drawn, in the frame's own fractions.
    private func boxRegion(pane: CGSize) -> CGRect? {
        guard let section, let frame = camera.currentFrame() else { return nil }
        let raw = frame.extent.size
        let upright = appState.cameraIsTurned ? CGSize(width: raw.height, height: raw.width) : raw
        // A box drawn on a zoomed picture is somewhere else on the real one.
        let drawn = appState.cameraZoom.map { CameraZoom.unzoomed(section, box: $0, in: pane) } ?? section
        return NotebookCapture.region(from: drawn, frame: upright, in: pane)
    }

    /// The shortcut goes in as KEYCAPS, not in brackets at the end of the
    /// sentence, because the bubble draws them the way the bar's does.
    private func corner(icon: String, label: String, help: String, keys: [String] = [],
                        isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .paneTip(BarTip(title: label, keys: keys, detail: help))
        .accessibilityLabel(label)
    }

    /// The cameras and, under them, any tablet — the menu bar's list.
    private var devicePicker: some View { InputDevicePicker() }

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
        // The pane's stack is aligned top-trailing for its corner buttons;
        // the placeholder takes the whole pane so it sits in the middle
        // (Sean, 2026-09-18).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A box dragged over the camera picture, and the two ways to bring what is
/// inside it onto the page: the writing alone, or the picture.
/// Drag a box on the picture, and that is it — no chooser afterwards. What
/// the box is FOR is the caller's business; the zoom uses it.
private struct BoxDragger: View {
    let hint: String
    let onBox: (CGRect) -> Void
    @State private var box: CGRect?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    guard let box else { return }
                    var outside = Path(CGRect(origin: .zero, size: geo.size))
                    outside.addRect(box)
                    context.fill(outside, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                    context.stroke(Path(box), with: .color(.white),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .local)
                        .onChanged { value in
                            box = CanvasGeometry.rect(from: value.startLocation, to: value.location)
                        }
                        .onEnded { value in
                            let drawn = CanvasGeometry.rect(from: value.startLocation, to: value.location)
                            box = nil
                            guard drawn.width > 8, drawn.height > 8 else { return }
                            onBox(drawn)
                        }
                )

                if box == nil {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                        .position(x: geo.size.width / 2, y: 30)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Not private: `action` is the rule that decides what a click means, and
/// it is tested.
struct SectionBox: View {

    /// What the end of a gesture means.
    enum Action: Equatable { case keep, clear, whole, fullWindow }

    /// Four points of slack, so a click stays a click.
    static func isDrag(_ translation: CGSize) -> Bool {
        max(abs(translation.width), abs(translation.height)) >= 4
    }

    /// A drag leaves its box alone. TWO CLICKS FILL THE WINDOW WITH THE
    /// PICTURE and two more put it back (Sean, 2026-09-21: "doubleclick
    /// the camera to make the whole window the camera.. double click again
    /// to exit"). One click clears a box, and — with no box to clear —
    /// takes the whole picture, which is the gesture the double-click used
    /// to be: the three capture buttons only appear once something is
    /// boxed, so without it the only way to photograph the whole frame
    /// was to drag a box round all of it by hand.
    ///
    /// The second click of a double arrives as its own event, so the first
    /// has already done its half by then — which is what makes the
    /// clearing instant and is why these are one gesture and not two
    /// `onTapGesture`s waiting on each other (Sean, 2026-09-19: "clicking
    /// to exit after selecting a section of the page is slow").
    static func action(translation: CGSize, clicks: Int, hasBox: Bool) -> Action {
        if isDrag(translation) { return .keep }
        if clicks >= 2 { return .fullWindow }
        return hasBox ? .clear : .whole
    }

    @Binding var section: CGRect?
    let size: CGSize
    /// True while a capture is already running.
    var busy = false
    /// Put the box round the whole picture, without dragging one.
    let onWholePicture: () -> Void
    /// The picture on its own, filling the window — and back again.
    var onFullWindow: (() -> Void)?
    /// The box as a picture, or as ink.
    var onInsert: ((NotebookCapture.Mode) -> Void)?
    /// The box read into the note as words.
    var onRead: (() -> Void)?
    /// What the three buttons say they do — the same three on the camera
    /// and on the tablet's page, from different sources.
    var help = Help.camera

    struct Help: Equatable {
        var image: String
        var writing: String
        var text: String

        static let camera = Help(image: "Put the picture inside the box on the page, squared up",
                                 writing: "Lift the writing inside the box onto the page as ink",
                                 text: "Read the writing inside the box into the note as words")
        /// The page's ink is already clean: nothing is squared up or
        /// traced, and Writing brings the strokes themselves.
        static let tabletPage = Help(image: "Put this part of the page into the note as a picture, paper and all",
                                     writing: "Bring the strokes the box touches into the note, pressure and colour kept",
                                     text: "Read the writing the box touches into the note as words")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                guard let section else { return }
                var outside = Path(CGRect(origin: .zero, size: size))
                outside.addRect(section)
                context.fill(outside, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                context.stroke(Path(section), with: .color(.white),
                               style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .contentShape(Rectangle())
            // ONE gesture for all three. A `.onTapGesture` pair would make
            // the single click WAIT to find out whether a second one is
            // coming — a visible pause before the box clears (Sean,
            // 2026-09-19: "clicking to exit after selecting a section of
            // the page is slow"). AppKit already knows how many clicks it
            // has seen, so the click is answered the moment it lands.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard SectionBox.isDrag(value.translation) else { return }
                        section = CanvasGeometry.rect(from: value.startLocation, to: value.location)
                    }
                    .onEnded { value in
                        switch SectionBox.action(translation: value.translation,
                                                 clicks: NSApp.currentEvent?.clickCount ?? 1,
                                                 hasBox: section != nil) {
                        case .keep: break
                        case .clear: section = nil
                        case .whole: onWholePicture()
                        case .fullWindow: onFullWindow?()
                        }
                    }
            )

            if let section {
                // Three things can be done with a box, so here are three
                // buttons — not a sentence about a button somewhere else
                // (Sean, 2026-09-19).
                HStack(spacing: 6) {
                    choice("Image", icon: "photo", help: help.image) {
                        // .page, not .raw: a page found in the frame is
                        // straightened and brought in at the notebook's
                        // remembered size, which is the whole point of
                        // photographing a page. Without a page it falls
                        // back to the frame itself.
                        onInsert?(.page)
                    }
                    choice("Writing", icon: "scribble.variable", help: help.writing) {
                        onInsert?(.ink)
                    }
                    choice("Text", icon: "text.viewfinder", help: help.text) {
                        onRead?()
                    }
                }
                .disabled(busy)
                .opacity(busy ? 0.6 : 1)
                .position(x: min(max(section.midX, 150), max(size.width - 150, 150)),
                          y: min(section.maxY + 22, max(size.height - 18, 18)))
            }
        }
    }
    private func choice(_ title: String, icon: String, help: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.62), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.28)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Hosted by the camera pane, which is the view these sit over.
        .paneTip(BarTip(title: title, detail: help))
        .accessibilityLabel(title)
    }

}
