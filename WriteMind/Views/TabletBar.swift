import SwiftUI

/// THE PAGE'S PEN AND PAPER, on one small bar in the tablet pane's top-left
/// corner (Sean, 2026-10-02: "it can have themed backgrounds and different
/// pen colors and strokes to write with"): the pen — its tool, its colour,
/// its size — and the paper under it. And WHERE THE PEN WRITES — "Write on:
/// Page | Notebook" (Sean, same day: "do the same for drawing mode in the
/// notebook itself and let the wacom control that as well.. as a separate
/// mode") — which is on this bar and nowhere else on screen; the View menu
/// carries it too, as it carries the notebook's own pen.
///
/// It sits in the band `TabletPane.band` keeps clear above the sheet, so it
/// is never over the writing, and what it opens is a popover, gone again at
/// the next click. Corner buttons in the camera pane's own style, all of it
/// SwiftUI: the colour well and the slider live in the popover, which is a
/// window of its own, so no hosted view sits over the pane to be handed its
/// cursorUpdates (AGENTS.md, the eighth cause) — which is also why the
/// switch is two buttons and not a segmented `Picker`, an NSSegmentedControl
/// underneath.
///
/// THE BAR HAS TO FIT THE PANE IT LIVES IN: offered only the width the
/// corner's buttons leave it (`TabletPane.topRow`), it takes the first of
/// its shapes that fits — the switch with "Write on" and an icon a name,
/// the two names alone, the two icons alone, and on a pane too narrow for
/// the row the switch on a row of its own over the pen and the paper. The
/// two names are what the split's default 420 gets: two bare icons there
/// read as one more paper control beside the swatch.
/// THE SWITCH NEVER MOVES UNDER THE POINTER THAT PRESSED IT: it comes
/// first, and while the pen writes in the notebook the page's pen and paper
/// are out of play but KEEP THEIR PLACE (`setAside`) — the corner's undo,
/// redo and clear the same — so the row measures the same in both modes
/// and the switch keeps one shape and one place. With them taken out, the
/// room they left made the switch grow its words and lead in Notebook mode
/// and lose them again in Page mode, and the button just pressed jumped.
struct TabletBar: View {
    @EnvironmentObject private var appState: AppState
    let theme: PageTheme
    /// A paper was picked from the menu.
    let onTheme: (PageTheme) -> Void
    /// Where the pen writes, and the switch's way of changing it.
    let target: TabletTarget
    let onTarget: (TabletTarget) -> Void

    @State private var showPen = false
    @State private var showPaper = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                TabletTargetSwitch(target: target, shape: .full, onPick: onTarget)
                controls
            }
            HStack(spacing: 6) {
                TabletTargetSwitch(target: target, shape: .names, onPick: onTarget)
                controls
            }
            HStack(spacing: 6) {
                TabletTargetSwitch(target: target, shape: .icons, onPick: onTarget)
                controls
            }
            VStack(alignment: .leading, spacing: 6) {
                TabletTargetSwitch(target: target, shape: .names, onPick: onTarget)
                HStack(spacing: 6) { controls }
            }
            VStack(alignment: .leading, spacing: 6) {
                TabletTargetSwitch(target: target, shape: .icons, onPick: onTarget)
                HStack(spacing: 6) { controls }
            }
        }
        // A popover left open on a control set aside would hang off nothing.
        .onChange(of: target) { _, _ in
            showPen = false
            showPaper = false
        }
    }

    /// THE ONE PLACE FOR WHAT FOLLOWS THE SWITCH: the page's pen and paper
    /// while the pen writes on the page, how the tablet lands on the notes
    /// while it writes in the notebook ("Fit | Real size", Sean, 2026-10-02).
    /// Stacked, both always measured, so the row is the same size in both
    /// modes and the switch does not move under the pointer that pressed it.
    private var controls: some View {
        ZStack(alignment: .leading) {
            pageControls
            scaleControls
        }
    }

    /// FIT OR REAL SIZE — icons alone, the tips say which (`NotebookScale`).
    private var scaleControls: some View {
        TabletScaleSwitch(scale: appState.notebookScale, onPick: { appState.notebookScale = $0 })
            .setAside(target != .notebook)
    }

    /// The page's own pen and paper — in play only while the pen writes on
    /// it, and in their place either way.
    @ViewBuilder private var pageControls: some View {
        Group {
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
        .setAside(target != .page)
    }
}

extension View {
    /// OUT OF PLAY, IN ITS PLACE: not drawn, not pressed, not hovered, not
    /// read out — and still measured, so what is beside it does not move
    /// (`TabletBar`, the tablet pane's corner).
    func setAside(_ aside: Bool) -> some View {
        opacity(aside ? 0 : 1)
            .allowsHitTesting(!aside)
            .accessibilityHidden(aside)
    }
}

/// "WRITE ON: PAGE | NOTEBOOK" — two buttons in one capsule, the one in use
/// lit. Lit with the primary colour, never the accent: the accent can be
/// yellow, and words on yellow are not words (AGENTS.md, colours).
struct TabletTargetSwitch: View {
    /// How much of it there is room for.
    enum Shape {
        /// "Write on", and an icon and a name a button.
        case full
        /// The two names alone.
        case names
        /// The two icons alone, for a narrow pane — the tip still says it
        /// all.
        case icons
    }

    let target: TabletTarget
    let shape: Shape
    let onPick: (TabletTarget) -> Void

    var body: some View {
        HStack(spacing: 2) {
            if shape == .full {
                Text("Write on")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 5)
                    .padding(.trailing, 1)
                    .fixedSize()
            }
            ForEach(TabletTarget.allCases) { option in
                let lit = option == target
                Button { onPick(option) } label: {
                    HStack(spacing: 4) {
                        if shape != .names {
                            Image(systemName: option.icon)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        if shape != .icons {
                            Text(option.title).font(.system(size: 11, weight: .semibold)).fixedSize()
                        }
                    }
                    .foregroundStyle(lit ? Color.primary : Color.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(lit ? 0.18 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .paneTip(BarTip(title: "Write on the \(option.title)", detail: option.help))
                .accessibilityLabel("Write on the \(option.title)")
                .accessibilityAddTraits(lit ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// "FIT | REAL SIZE" — two buttons in one capsule, the one in use lit, as
/// the target switch is built (and for the same reason not a segmented
/// `Picker`: an NSSegmentedControl underneath). Icons alone: the row has to
/// measure what the page's pen and paper do (`TabletBar.controls`).
struct TabletScaleSwitch: View {
    let scale: NotebookScale
    let onPick: (NotebookScale) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotebookScale.allCases) { option in
                let lit = option == scale
                Button { onPick(option) } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(lit ? Color.primary : Color.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(lit ? 0.18 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .paneTip(BarTip(title: option.title, detail: option.help))
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(lit ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
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
        PickList(title: "Paper") {
            ForEach(PageTheme.allCases) { theme in
                PickRow(title: theme.title, detail: theme.detail, isCurrent: theme == current,
                        action: { onPick(theme) }) {
                    PaperSwatch(theme: theme)
                }
            }
        }
    }
}

/// A PICKER IN A POPOVER — the paper's, and how the tablet sits: its
/// heading, a row a choice, and a line under them if it has one. One view
/// for both, so the two cannot drift apart. As wide as its rows' words
/// need: the paper's are short, the tablet's say where its light is.
struct PickList<Rows: View>: View {
    let title: String
    var footer: String? = nil
    var width: CGFloat = 310
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).padding(.horizontal, 6).padding(.bottom, 6)
            rows()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
            }
        }
        .padding(10)
        .frame(width: width)
    }
}

/// One choice in a `PickList`: a picture of it, its name over one line
/// on it, and a tick on the one in use, the row washed with the accent
/// under the pointer.
struct PickRow<Picture: View>: View {
    let title: String
    let detail: String
    let isCurrent: Bool
    let action: () -> Void
    @ViewBuilder let picture: () -> Picture
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                picture().frame(width: 44, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
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
        .accessibilityLabel(title)
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

extension String {
    /// "Ruled" → "ruled": a title worn as the second half of a tip.
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
