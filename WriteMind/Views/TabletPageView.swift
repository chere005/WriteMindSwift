import SwiftUI

/// The sheet and everything on it, in the frame `TabletPane.pageFrame`
/// gives it: the paper, what the paper has printed on it, the finished ink,
/// the stroke being written, and the box — back to front. The hover marker goes over all of it, in the pane.
///
/// THREE LAYERS, THREE RATES, so that 120 samples a second redraw one
/// stroke and not a page of handwriting: the finished ink changes once a
/// stroke and is `Equatable`, so SwiftUI skips it while it has not; the
/// live stroke is its own layer watching `TabletScribe.stroke`; the box is
/// its own layer watching `TabletBox`. Every one of them is SwiftUI — a
/// hosted NSView over the pane would be handed every cursorUpdate there
/// (AGENTS.md, the eighth cause).
struct TabletSheetView: View {
    @ObservedObject var page: TabletPage
    let scribe: TabletScribe
    /// The page in its own points (`TabletPage.size`).
    let pageSize: CGSize
    /// The frame's size on screen.
    let size: CGSize
    var theme: PageTheme = .plain
    /// A box's three choices can go somewhere: a note is open.
    let canTake: Bool
    /// One of them is still being read.
    let busy: Bool
    let onFullWindow: () -> Void
    let onTake: (TabletChoice, CGRect) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: theme.paper))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
                .allowsHitTesting(false)
            Group {
                TabletPaperLayer(theme: theme, pageSize: pageSize)
                    .equatable()
                TabletInkLayer(strokes: page.strokes, pageSize: pageSize)
                    .equatable()
                TabletLiveLayer(scribe: scribe, pageSize: pageSize)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .allowsHitTesting(false)
            TabletBoxLayer(box: scribe.box, size: size, busy: busy,
                           onFullWindow: onFullWindow, onTake: onTake)
                .disabled(!canTake)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// What the theme prints on the sheet — the SAME call `TabletRender` makes
/// for a picture taken off the page (`PageTheme.print`), in page points
/// scaled to the frame — so a ruling is on the pane and in the picture, or
/// in neither. Plain paper prints nothing.
struct TabletPaperLayer: View, Equatable {
    let theme: PageTheme
    let pageSize: CGSize

    var body: some View {
        Canvas { context, size in
            guard pageSize.width > 0 else { return }
            let scale = size.width / pageSize.width
            context.withCGContext { cg in
                cg.scaleBy(x: scale, y: scale)
                theme.print(in: cg, pageSize: pageSize)
            }
        }
    }
}

/// The page's finished strokes, in the page's own points scaled to the
/// frame — so an outline is made once (`InkCache`) and a resized pane only
/// scales it.
struct TabletInkLayer: View, Equatable {
    let strokes: [Stroke]
    let pageSize: CGSize

    var body: some View {
        Canvas { context, size in
            Self.paint(strokes, pageSize: pageSize, in: &context, size: size)
        }
    }

    /// The pane's painter for the page: `DrawingCanvas.draw`, the
    /// notebook's own, under one scale from page points to the frame.
    static func paint(_ strokes: [Stroke], pageSize: CGSize, in context: inout GraphicsContext, size: CGSize) {
        guard pageSize.width > 0 else { return }
        let scale = size.width / pageSize.width
        context.scaleBy(x: scale, y: scale)
        for stroke in strokes {
            DrawingCanvas.draw(stroke, points: CanvasItem.stroke(stroke).basePoints(in: pageSize), in: &context)
        }
    }
}

/// The one stroke the nib is writing, at the pen's rate.
private struct TabletLiveLayer: View {
    @ObservedObject var scribe: TabletScribe
    let pageSize: CGSize

    var body: some View {
        let stroke = scribe.stroke
        Canvas { context, size in
            guard let stroke else { return }
            TabletInkLayer.paint([stroke], pageSize: pageSize, in: &context, size: size)
        }
    }
}

/// The selection box: the camera's own `SectionBox` — its look, its three
/// buttons, its gestures — over the page, in the page's fractions. A drag
/// with the mouse or the trackpad draws it here; the pen's side switch
/// draws it through `TabletScribe`; either way it is the same box.
private struct TabletBoxLayer: View {
    @ObservedObject var box: TabletBox
    let size: CGSize
    let busy: Bool
    let onFullWindow: () -> Void
    let onTake: (TabletChoice, CGRect) -> Void

    var body: some View {
        SectionBox(section: Binding(get: { box.rect.map { TabletBox.points($0, in: size) } },
                                    set: { box.rect = $0.flatMap { TabletBox.fraction($0, in: size) } }),
                   size: size,
                   busy: busy,
                   // A click with no box takes the whole page, as it takes
                   // the whole picture on the camera.
                   onWholePicture: { box.rect = CGRect(x: 0, y: 0, width: 1, height: 1) },
                   onFullWindow: onFullWindow,
                   onInsert: { mode in take(mode == .ink ? .writing : .image) },
                   onRead: { take(.text) },
                   help: .tabletPage)
    }

    private func take(_ choice: TabletChoice) {
        guard let rect = box.rect else { return }
        onTake(choice, rect)
    }
}
