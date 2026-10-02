import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.cameraFullWindow {
            // THE WHOLE WINDOW IS THE PICTURE (Sean, 2026-09-21). Not a
            // pane at its widest — the sidebar, the notes and the divider
            // are all out, so a page held up to the camera is as big as
            // the screen can make it.
            inputPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) { wayOut }
                .transition(.opacity)
        } else {
            panes
        }
    }

    /// The right-hand pane: the camera's picture, or — when a tablet is the
    /// input — the page it writes on. ONE PANE, two faces, so the switch
    /// that shows and hides it, ⌘Y, the whole-window view and the divider
    /// all go on working whichever it is ("every button has exactly one
    /// place").
    @ViewBuilder private var inputPane: some View {
        switch appState.inputSource {
        case .camera: CameraPane()
        case .tablet: TabletPane()
        }
    }

    /// The transparent × he asked for, over the top-left corner of the
    /// picture. It is drawn ON the video rather than on a bar above it,
    /// because there is no bar: the window is the picture. Below the
    /// title bar's own buttons, which are the window's and not this
    /// view's to crowd.
    private var wayOut: some View {
        Button { appState.toggleCameraFullWindow() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.35), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .padding(14)
        .help("Back to the notes — double-clicking the picture does it too")
        .accessibilityLabel(appState.inputSource.words.leaveWholeWindow)
    }

    private var panes: some View {
        HStack(spacing: 0) {
            if appState.showSidebar {
                SidebarView()
                    .frame(width: 250)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }

            // Either pane can be put away — the video from the sidebar
            // header's own toggle, left of New Note (Sean, 2026-09-18); the
            // notes pane from the View menu. AppState keeps at least one up.
            // HSplitView is rebuilt (the .id) when the set of panes changes,
            // because it remembers divider positions for the panes it had and
            // will otherwise hand the survivor the width of the pair.
            HSplitView {
                if appState.showEditor {
                    // The editor carries the formatting bar — which is inside
                    // that pane, over the text only (Sean, 2026-09-18), never
                    // across the sidebar or the video — so it gets the larger
                    // share by default. The video is a viewfinder.
                    EditorPane()
                        .frame(minWidth: 460, idealWidth: 720, maxWidth: .infinity, maxHeight: .infinity)
                }
                if appState.showCamera {
                    inputPane
                        .frame(minWidth: 280,
                               idealWidth: appState.showEditor ? 420 : 900,
                               maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .id("\(appState.showEditor)-\(appState.showCamera)")

        }
    }
}
