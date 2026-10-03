import SwiftUI

/// THE TABLET OVER THE NOTES, in Notebook mode: the stroke the pen is
/// writing and the marquee it drags with a side switch held, and — while
/// the pen is near — a faint outline of where the tablet lands on the notes
/// and the marker where the nib is. Over the drawing layer, in the same
/// frame.
///
/// It is also the notes pane's word to the tablet: a note is on screen
/// (`TabletInput.notebookAppeared`, which is what holding the tablet and
/// the funnel's swallowing follow in Notebook mode), where it is and how far
/// it has scrolled (`NotebookScribe.place`), what the notebook's pen writes
/// with, and the way into the note (`NotebookScribe.writes(into:telling:)`:
/// where a finished stroke goes, and what a click of the pen's switches
/// takes back and puts back).
///
/// NOTHING HERE IS AN NSVIEW and none of it takes a click: SwiftUI shapes
/// and a `Canvas`, with hit testing off — a hosted view over the notes is
/// handed every cursorUpdate there and answers with the arrow (AGENTS.md,
/// the eighth cause).
struct NotebookTabletLayer: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var tablet: TabletController
    /// How far the text under the layer has scrolled (`EditorPane`).
    let scrollOffset: CGFloat
    /// The tablet's size, read off the funnel only when it CHANGES.
    @State private var extent = TabletExtent.fallback
    /// Where the notes were last measured here, to hand back to the scribe
    /// when this layer comes up after another has let go of it.
    @State private var measured: NotebookPlace?

    private var input: TabletInput { tablet.input }
    private var scribe: NotebookScribe { .shared }

    var body: some View {
        GeometryReader { geo in
            let turns = appState.tabletQuarterTurns
            let place = NotebookPlace(pane: geo.size, scroll: scrollOffset,
                                      aspect: TabletMapping.aspect(of: extent, quarterTurns: turns),
                                      note: store.selectedNote?.id, quarterTurns: turns,
                                      scale: appState.notebookScale,
                                      millimetres: TabletMapping.millimetres(of: extent, quarterTurns: turns))
            ZStack(alignment: .topLeading) {
                if appState.tabletWritesInNotebook {
                    NotebookLiveInk(scribe: scribe, scrollOffset: scrollOffset)
                    NotebookPenGuide(input: input, area: place.area)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // The outline of a tablet at real size can be bigger than the
            // notes, and is cut off at their edge.
            .clipped()
            .onChange(of: place, initial: true) { _, place in
                measured = place
                scribe.place = place
            }
        }
        .allowsHitTesting(false)
        .onReceive(input.$extent.removeDuplicates()) { extent = $0 }
        // The NOTEBOOK's pen — the pen menu's tool, colour and width — never
        // the page's.
        .onChange(of: TabletInk(colorHex: appState.penColorHex, width: appState.penWidth, tool: appState.penTool),
                  initial: true) { _, ink in scribe.ink = ink }
        // TWO OF THESE CAN BE UP AT ONCE for a moment — the notes pane is
        // built again when a pane beside it comes or goes, and SwiftUI may
        // bring the new one up before the old one goes — so this one's
        // coming takes the scribe whatever the old one's going did, and the
        // going lets go only with the last (`NotebookScribe.layerWent`).
        .onAppear {
            scribe.writes(into: store, telling: appState)
            if let measured { scribe.place = measured }
            input.notebookAppeared()
        }
        .onDisappear {
            input.notebookDisappeared()
            scribe.layerWent(othersShowing: input.notebookIsShowing)
        }
    }
}

/// The stroke the nib is writing and the marquee it drags with a side
/// switch held, at the pen's rate — drawn by the layer's own painters
/// (`DrawingCanvas.paintLive`, `paintMarquee`) in the document's
/// coordinates, a scroll's worth up, exactly as the layer draws its own
/// pen's stroke.
private struct NotebookLiveInk: View {
    @ObservedObject var scribe: NotebookScribe
    let scrollOffset: CGFloat
    /// The note's paper, so the stroke under the nib is shown as it will
    /// be once it lands (`InkPaths.shownHex`).
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let stroke = scribe.stroke
        let marquee = scribe.marquee
        let paper = InkPaths.notePaperHex(dark: colorScheme == .dark)
        Canvas { context, size in
            context.translateBy(x: 0, y: -scrollOffset)
            if let stroke { DrawingCanvas.paintLive(stroke, in: &context, size: size, paper: paper) }
            if let marquee { DrawingCanvas.paintMarquee(marquee, in: &context) }
        }
    }
}

/// WHERE THE TABLET IS ON THE NOTES, while the pen is near: a faint outline
/// of the area it maps onto, and the page's own hover marker inside it. Its
/// own view watching the funnel, so the pen's hundred-odd samples a second
/// redraw a ring and a rectangle and not the notes.
private struct NotebookPenGuide: View {
    @ObservedObject var input: TabletInput
    let area: CGRect

    var body: some View {
        if input.pen != nil {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .frame(width: area.width, height: area.height)
                .position(x: area.midX, y: area.midY)
            TabletHoverMarker(input: input, page: area)
        }
    }
}
