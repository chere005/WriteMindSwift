import SwiftUI

/// The small menu under the pen button: the pen's OWN settings — the tool
/// a tablet's nib writes with, its size and its colour, in the order the
/// page's pen has them (`TabletPenMenu`) — and a way to start over.
///
/// The mode is not in here. It is ONE button on the bar, the pen, and
/// pressing it toggles (Sean, 2026-09-21: "clicking the pen outside of the
/// dropdown is the toggle between pen and cursor"), and every button has
/// exactly one place.
struct PenMenu: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NoteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pen").font(.headline)

            // The page's bar has the same picker, in the same place. Here
            // it is a TABLET'S: the mouse and the trackpad draw the line
            // they always drew.
            VStack(alignment: .leading, spacing: 6) {
                InkToolPicker(tool: $appState.penTool)
                Text("What a tablet's pen writes with — a mouse or the trackpad draws the plain line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PenSizeRow(width: $appState.penWidth, colour: appState.penColor)

            PenColourRow(hex: $appState.penColorHex)

            Divider()

            HStack(spacing: 8) {
                Button { store.undoDrawing() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndoDrawing)
                .help("Undo the last thing that happened on the drawing layer — a stroke, a move, a delete (⇧⌘Z is the text's undo)")

                Button { store.redoDrawing() } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!store.canRedoDrawing)

                Spacer()
                Text(objectCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Clear Drawing", role: .destructive) { store.clearDrawing() }
                    .disabled(store.drawing.isEmpty)
                Spacer()
                Button {
                    appState.canvasMode = .cursor
                    store.chooseImage()
                } label: {
                    Label("Add Image", systemImage: "photo.badge.plus")
                }
                .disabled(store.selectedNote == nil)
            }

            Divider()

            // The pen's button says which mode the pane is in; what is
            // worth saying here is what holds in both.
            Text("An object can be dragged by hand or worked with its handles in any mode. ⌘ and drag pulls a selection rectangle without leaving cursor mode, ⌃G holds what is picked together or takes it apart, and a picture can be pasted straight in.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 330)
        .foregroundStyle(.primary)
        .tint(.accentColor)
    }

    private var objectCount: String {
        let strokes = store.drawing.strokes.count
        let images = store.drawing.images.count
        let parts = [strokes == 1 ? "1 stroke" : "\(strokes) strokes",
                     images == 0 ? nil : (images == 1 ? "1 picture" : "\(images) pictures")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

}
