import SwiftUI

/// The shapes popover: flow-chart nodes to put down, and the arrow tool.
struct ShapeMenu: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NoteStore

    private let nodes: [ShapeItem.Kind] = [.rectangle, .roundedRectangle, .oval, .diamond, .triangle, .parallelogram]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flow Chart").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 6), count: 3), spacing: 6) {
                ForEach(nodes) { kind in
                    PaletteButton(title: kind.title, symbol: kind.symbol,
                                  isOn: appState.placing == .shape(kind)) {
                        appState.arm(.shape(kind))
                        isPresented = false
                    }
                }
            }

            Divider()

            Toggle(isOn: $appState.connectActive) {
                Label("Draw arrows between nodes", systemImage: "arrow.right")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Text("Pick a shape, then drag on the page from one corner to the other. It stays picked, so the next drag draws the next one, until Esc, the pen, or the shape picked again. Hold \u{2325} and drag from a node to draw an arrow without the tool; with the tool on, any drag draws one. A bar then picks the heads and the line, and a double-click gives a node its label.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 264)
    }
}

/// The marks popover: the things drawn all the time, as objects.
struct MarkMenu: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState

    private let marks: [ShapeItem.Kind] = [.check, .cross, .question, .star, .rectangle, .oval, .triangle]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Marks").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 6), count: 3), spacing: 6) {
                ForEach(marks) { kind in
                    PaletteButton(title: kind.title, symbol: kind.symbol,
                                  isOn: appState.placing == .shape(kind)) {
                        // PICKING A MARK ARMS IT; THE CLICK IS WHERE IT
                        // GOES (Sean, 2026-09-21: "the checkmark
                        // shouldn't be placed until i click where it
                        // goes, like an arrow"). It lands at one line of
                        // text's size, which is what a tick beside a
                        // word is, and a drag still sizes it by hand.
                        appState.arm(.shape(kind))
                        isPresented = false
                    }
                }
                line("Arrow", start: .none, end: .arrow)
                line("Both Ways", start: .arrow, end: .arrow)
                line("Line", start: .none, end: .none)
            }
            Text("Pick a mark and then click where it goes: it lands the size of a line of writing, and the handles move, size and turn it. Drag instead of clicking to size it as it goes down, and hold \u{2318} to keep it for the next one. A line or an arrow runs from the press to the release. A box, a circle, a triangle, a line or an arrow stays picked for the next drag until Esc.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 264)
    }

    private func line(_ title: String, start: ConnectorItem.Head, end: ConnectorItem.Head) -> some View {
        let placement = CanvasPlacement.line(start: start, end: end)
        return PaletteButton(title: title, symbol: placement.symbol, isOn: appState.placing == placement) {
            appState.arm(placement)
            isPresented = false
        }
    }
}

private struct PaletteButton: View {
    let title: String
    let symbol: String
    /// The tool armed now, lit the way the bar lights a tool that is on:
    /// a shape stays armed after it is drawn, and picking the lit tile
    /// again is one of the ways to put it away (`AppState.arm`).
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isOn ? Color.accentColor : .primary)
            .frame(width: 64, height: 50)
            .background(isOn ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(isOn ? "\(title) is picked — click to put it away" : title)
    }
}
