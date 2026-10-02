import SwiftUI

/// THE PAGE'S PEN AND PAPER, on one small bar in the tablet pane's top-left
/// corner (Sean, 2026-10-02: "it can have themed backgrounds and different
/// pen colors and strokes to write with"): the pen — its tool, its colour,
/// its size — and the paper under it.
///
/// It sits in the band `TabletPane.band` keeps clear above the sheet, so it
/// is never over the writing, and what it opens is a popover, gone again at
/// the next click. Corner buttons in the camera pane's own style, all of it
/// SwiftUI: the colour well and the slider live in the popover, which is a
/// window of its own, so no hosted view sits over the pane to be handed its
/// cursorUpdates (AGENTS.md, the eighth cause).
struct TabletBar: View {
    @EnvironmentObject private var appState: AppState
    let theme: PageTheme
    /// A paper was picked from the menu.
    let onTheme: (PageTheme) -> Void

    @State private var showPen = false
    @State private var showPaper = false

    var body: some View {
        HStack(spacing: 6) {
            Button { showPen.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.pageInkTool.icon)
                        .font(.system(size: 12, weight: .semibold))
                    InkChip(inkHex: appState.pageInkHex, theme: theme)
                }
                .frame(height: 14)
                .foregroundStyle(Color.primary)
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .paneTip(BarTip(title: "Pen on the Page",
                            detail: "\(appState.pageInkTool.title), \(Int(appState.pageInkWidth)) pt — what new strokes on the page are written with"))
            .accessibilityLabel("Pen on the Page")
            .popover(isPresented: $showPen, arrowEdge: .bottom) { TabletPenMenu(theme: theme) }

            Button { showPaper.toggle() } label: {
                PaperSwatch(theme: theme)
                    .frame(width: 20, height: 14)
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .paneTip(BarTip(title: "Paper", detail: "\(theme.title) — \(theme.detail.lowercasedFirst)"))
            .accessibilityLabel("Paper: \(theme.title)")
            .popover(isPresented: $showPaper, arrowEdge: .bottom) {
                PaperMenu(current: theme) { picked in
                    showPaper = false
                    onTheme(picked)
                }
            }
        }
    }
}

/// A dot of the page's ink ON A PIECE OF THE PAPER it writes on. On the
/// corner's dark glass alone the first ink of all, near-black, was an empty
/// ring; on its paper it reads exactly as well as it does on the page —
/// which is the other thing the button is there to say.
struct InkChip: View {
    let inkHex: String
    let theme: PageTheme

    var body: some View {
        Circle()
            .fill(Color(hex: inkHex) ?? .black)
            .frame(width: 8, height: 8)
            .frame(width: 14, height: 14)
            .background(Color(nsColor: theme.paper), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5))
    }
}

/// The page's pen: the tool, the size, the colour — the notebook pen's own
/// controls (`PenControls.swift`), bound to the page's pen.
struct TabletPenMenu: View {
    @EnvironmentObject private var appState: AppState
    /// The paper, for its own ink among the swatches.
    let theme: PageTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pen on the Page").font(.headline)
            InkToolPicker(tool: $appState.pageInkTool)
            PenSizeRow(width: $appState.pageInkWidth, colour: Color(hex: appState.pageInkHex) ?? .black)
            PenColourRow(hex: $appState.pageInkHex, swatches: theme.swatches)
            Text("New strokes take these; what is on the page keeps what it was written with.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        // Ten wider than the notebook's: the board's chalk is a seventh
        // swatch.
        .frame(width: 340)
        .foregroundStyle(.primary)
        .tint(.accentColor)
    }
}

/// The papers, a row each: a swatch of it, its name, what is printed on
/// it, and a tick on the one under the writing. A menu in a popover, so
/// each swatch is the paper's own print and not an icon of it.
struct PaperMenu: View {
    let current: PageTheme
    let onPick: (PageTheme) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Paper").font(.headline).padding(.horizontal, 6).padding(.bottom, 6)
            ForEach(PageTheme.allCases) { theme in
                PaperRow(theme: theme, isCurrent: theme == current) { onPick(theme) }
            }
        }
        .padding(10)
        .frame(width: 310)
    }
}

private struct PaperRow: View {
    let theme: PageTheme
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PaperSwatch(theme: theme).frame(width: 44, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.title)
                    Text(theme.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(isCurrent ? 1 : 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(hovering ? 0.15 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// A piece of a paper for a menu: its colour and its print, by the page's
/// own printer (`PageTheme.print`), looking at the left-hand side of a
/// page of the small tablet held turned — where a ruled page has its
/// margin — and printed heavier, so a hairline shows at the size of an
/// icon.
struct PaperSwatch: View {
    let theme: PageTheme

    /// The page the swatch is a piece of, and the piece, in millimetres.
    static let page = CGSize(width: 95, height: 152)
    static let window = CGRect(x: 6, y: 34, width: 30, height: 21)
    static let weight: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                cg.setFillColor(theme.paper.cgColor)
                cg.fill(CGRect(origin: .zero, size: size))
                let scale = size.width / Self.window.width
                cg.scaleBy(x: scale, y: scale)
                cg.translateBy(x: -Self.window.minX, y: -Self.window.minY)
                // In millimetres from here: the page's points ARE its
                // millimetres.
                theme.print(in: cg, pageSize: Self.page, millimetres: Self.page, weight: Self.weight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5))
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
