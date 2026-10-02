import AppKit
import SwiftUI

/// The sections the bar is made of. Each one can be put away and comes back
/// as a single icon (Sean, 2026-09-19: "each section of the toolbar should be
/// collapsable to make things sane"). Every shortcut lives in the Format
/// menu, so putting a section away never takes a key combination with it.
enum ToolGroup: String, CaseIterable, Identifiable {
    // Maths and flow charts stand on their own: they have nothing to do
    // with each other or with dropping a picture on the page (Sean,
    // 2026-09-19: "flowcharts and maths deserve their own sections for now,
    // they're basically completely separate things at this point").
    // `capture` is the pen's section — the name is what the collapsed
    // state was saved under, so it stays.
    case style, structure, insert, maths, flowchart, capture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .style: return "Style"
        case .structure: return "Structure"
        case .insert: return "Insert"
        case .maths: return "Maths"
        case .flowchart: return "Flow Chart"
        case .capture: return "Pen"
        }
    }

    var icon: String {
        switch self {
        case .style: return "textformat"
        case .structure: return "list.bullet.indent"
        case .insert: return "plus.square.on.square"
        case .maths: return "function"
        case .flowchart: return "flowchart"
        case .capture: return "pencil"
        }
    }
}

/// The bar over the editor pane — always there, and only there (Sean,
/// 2026-09-18: "menubar should only be on the edit text pane"): formatting on
/// the left, editor/preview on the right. Small icons, evenly spaced, each
/// section separated by a grip that puts it away; a control that opens a
/// menu carries its chevron as part of itself.
struct TopBar: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var camera: CameraController
    @State private var showPenMenu = false
    @State private var showTextStyle = false
    @State private var showMath = false
    @State private var showShapes = false
    @State private var showMarks = false

    /// The text buttons work wherever there is text to work on: the source,
    /// a block being edited in the preview, and — since 2026-09-19 — the
    /// preview with nothing clicked yet, where pressing one opens a block
    /// and then does it.
    private var canFormat: Bool { store.selectedNote != nil }
    /// The pen works over the rendered page too, not just the source.
    private var canDraw: Bool { store.selectedNote != nil }

    var body: some View {
        HStack(spacing: 2) {
            // ONE spot for the sidebar's switch, the one it had when the
            // sidebar was away (Sean, 2026-09-19: "keep the hide side bar in
            // the same spot (where it is when it's closed)"). It used to
            // move: on the sidebar's own header while it was open, over here
            // once it was gone, so hiding it and bringing it back was two
            // buttons in two places.
            BarButton(systemImage: "sidebar.left",
                      label: appState.showSidebar ? "Hide Notes Sidebar" : "Show Notes Sidebar",
                      help: appState.showSidebar ? "Put the notes list away"
                                                 : "Bring the notes list back",
                      keys: ["⌃", "⌘", "S"],
                      isOn: appState.showSidebar) {
                appState.toggleSidebar()
            }
            BarDivider()

            BarGroup(.style) { styleTools }
            BarGroup(.structure) { structureTools }
            BarGroup(.insert) { insertTools }
            BarGroup(.maths) { mathsTools }
            BarGroup(.flowchart) { flowChartTools }
            BarGroup(.capture) { captureTools }

            Spacer(minLength: 6)
            // The markdown toggle and the video's switch used to end this
            // bar. They are on the SIDEBAR's bar now (Sean, 2026-09-21:
            // "move the markdown toggle and video button to the menubar
            // above the sidebar"), which leaves this one to the tools and
            // nothing else — and keeps the rule that a pane's switch is on
            // a different pane, once.
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        // The bar's own contents stay inside it; the tooltips, which are an
        // overlay applied after this, deliberately hang below it.
        .clipped()
        .background(.bar)
        .environment(\.barTipsEnabled, true)
        .overlayPreferenceValue(BarTipKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    BarTipBubble(tip: anchor.tip, over: proxy[anchor.bounds], within: proxy.size)
                }
            }
            .allowsHitTesting(false)
        }
        .contextMenu {
            Text("Toolbar Sections")
            ForEach(ToolGroup.allCases) { group in
                Toggle(group.title, isOn: Binding(
                    get: { !appState.isCollapsed(group) },
                    set: { appState.setCollapsed(group, !$0) }))
            }
        }
    }

    // MARK: - The sections

    @ViewBuilder
    private var styleTools: some View {
        Group {
            // The heading ladder: the icon and its chevron are one menu.
            BarMenu(glyph: "textformat.size", label: "Text Style",
                    tip: BarTip(title: "Text Style",
                                detail: "Title, chapter, author, section, subsection, subsubsection (⌘1–⌘6) or body text (⌘7)")) {
                ForEach(MarkdownFormatting.Heading.ladder) { level in
                    Button(level.name) { appState.editor.heading(level) }
                }
            }
            BarButton(systemImage: "bold", label: "Bold", help: "Heavier type for the selection",
                      keys: ["⌘", "B"]) { appState.editor.bold() }
            BarButton(systemImage: "italic", label: "Italic", help: "Sloped type for the selection",
                      keys: ["⌘", "I"]) { appState.editor.italic() }
            BarButton(systemImage: "underline", label: "Underline", help: "A line under the selection",
                      keys: ["⌘", "U"]) { appState.editor.underline() }
            BarButton(systemImage: "strikethrough", label: "Strikethrough",
                      help: "A line through the selection — struck out, still readable",
                      keys: ["⇧", "⌘", "X"]) { appState.editor.strikethrough() }
            BarButton(systemImage: "textformat", label: "Font and Colour",
                      help: "Font, size and colour for the selected text") {
                showTextStyle.toggle()
            }
            .popover(isPresented: $showTextStyle, arrowEdge: .bottom) { TextStyleMenu() }
        }
        .disabled(!canFormat)
    }

    @ViewBuilder
    private var structureTools: some View {
        Group {
            // The list button writes whichever marker the chevron picked;
            // dots to begin with (Sean, 2026-09-19).
            BarSplit(isOn: false) {
                BarButton(systemImage: appState.bulletStyle.systemImage, label: "List",
                          help: "Make these lines a \(appState.bulletStyle.title.lowercased()) list",
                          keys: ["⇧", "⌘", "L"], bare: true) {
                    appState.editor.list(appState.bulletStyle)
                }
            } menu: {
                Picker("List", selection: $appState.bulletStyle) {
                    ForEach(MarkdownFormatting.ListStyle.allCases) { style in
                        Label(style.title, systemImage: style.systemImage).tag(style)
                    }
                }
                .pickerStyle(.inline)
            } menuTip: {
                BarTip(title: "List Style", detail: "Dots, dashes or numbers")
            }

            BarButton(systemImage: "text.quote", label: "Quote", help: "Set these lines in as a quotation",
                      keys: ["⌃", "⌘", "Q"]) { appState.editor.quote() }

            // The fence carries a language, and the chevron picks it —
            // C, C++, Wolfram, Python, TypeScript (Sean, 2026-09-19).
            BarSplit(isOn: false) {
                BarButton(systemImage: "chevron.left.forwardslash.chevron.right", label: "Code Block",
                          help: appState.codeLanguage == .plain
                              ? "A fenced block, set in monospace"
                              : "A fenced \(appState.codeLanguage.title) block, coloured",
                          keys: ["⌘", "8"], bare: true) {
                    appState.editor.codeBlock(language: appState.codeLanguage.fence)
                }
            } menu: {
                Picker("Language", selection: $appState.codeLanguage) {
                    ForEach(CodeLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.inline)
            } menuTip: {
                BarTip(title: "Code Language", detail: "What the block is written in")
            }

            BarButton(systemImage: "decrease.indent", label: "Decrease Indentation",
                      help: "Out one step — quotes and bullets too", keys: ["⌘", "["]) {
                appState.editor.outdent()
            }
            BarButton(systemImage: "increase.indent", label: "Increase Indentation",
                      help: "In one step — quotes and bullets too", keys: ["⌘", "]"]) {
                appState.editor.indent()
            }

            // A section — its heading and everything under it — swaps places
            // with its neighbour (Sean, 2026-09-19).
            BarButton(systemImage: "arrow.up.to.line.compact", label: "Move Section Up",
                      help: "This heading and everything under it, above the section before it",
                      keys: ["⌃", "⌘", "↑"]) { appState.editor.moveSection(up: true) }
            BarButton(systemImage: "arrow.down.to.line.compact", label: "Move Section Down",
                      help: "This heading and everything under it, below the section after it",
                      keys: ["⌃", "⌘", "↓"]) { appState.editor.moveSection(up: false) }
        }
        .disabled(!canFormat)
    }

    @ViewBuilder
    private var mathsTools: some View {
        BarButton(systemImage: "function", label: "Maths",
                  help: "Integrals, sums, derivatives — written as Wolfram Language") {
            showMath.toggle()
        }
        .popover(isPresented: $showMath, arrowEdge: .bottom) { MathMenu(isPresented: $showMath) }
        .disabled(!canFormat)
    }

    /// Nodes, the arrows between them, and the marks drawn beside them.
    @ViewBuilder
    private var flowChartTools: some View {
        Group {
            BarButton(systemImage: "square.on.circle", label: "Shapes",
                      help: "Flow-chart shapes, and arrows between them — hold ⌥ and drag from a node",
                      isOn: appState.shapesLit) {
                showShapes.toggle()
            }
            .popover(isPresented: $showShapes, arrowEdge: .bottom) { ShapeMenu(isPresented: $showShapes) }
            BarButton(systemImage: "checkmark.circle", label: "Marks",
                      help: "Check marks, crosses, stars, arrows — the things drawn all the time",
                      isOn: appState.marksLit) {
                showMarks.toggle()
            }
            .popover(isPresented: $showMarks, arrowEdge: .bottom) { MarkMenu(isPresented: $showMarks) }
        }
        .disabled(store.selectedNote == nil)
    }

    @ViewBuilder
    private var insertTools: some View {
        Group {
            // Things dropped on the page: a picture, a floating box of
            // words. They work in the preview too.
            Group {
                // Adding a picture is an Insert ▸ Image away (⇧⌘I), not a
                // button on the bar (Sean, 2026-09-19: "the insert image
                // button should be in a menu bar entry under insert").
                BarButton(systemImage: "character.textbox", label: "Text Box",
                          help: "A box of words that floats over the page; the note's text keeps clear of it") {
                    appState.putToolsAway()
                    store.addTextBox(colorHex: appState.penColorHex)
                }
            }
            .disabled(store.selectedNote == nil)
        }
    }

    @ViewBuilder
    private var captureTools: some View {
        // ONE BUTTON FOR THE PANE: the pen, lit while it is down (Sean,
        // 2026-09-21: "drop the cursor and select buttons.. clicking the
        // pen outside of the dropdown is the toggle between pen and
        // cursor"). The cursor and the marquee each had one beside it —
        // three buttons for two answers and a mode that ⌘ already gives
        // in both. The chevron is the pen's own options, and pressing it
        // does not put the pen down.
        //
        // The capture button that used to sit here is gone: the camera
        // pane's own three buttons say what to do with a box (Sean,
        // 2026-09-19: "get rid of the capture button in the toolbar").
        Group {
            BarSplit(isOn: appState.canvasMode == .pen) {
                BarButton(systemImage: "pencil", label: "Pen",
                          help: appState.penActive
                              ? "Put the pen down and give the clicks back to the notebook"
                              : "Draw over the note (hold ⌘ in either mode to pull a rectangle over what is on the page)",
                          isOn: appState.canvasMode == .pen, bare: true) {
                    // A second press puts it down rather than doing
                    // nothing, which is what a pen button has always done
                    // here (Sean, 2026-09-18). The same one writer ⌘P uses.
                    appState.togglePen()
                }
            } chevron: {
                Button { showPenMenu.toggle() } label: { BarChevron() }
                    .buttonStyle(.plain)
                    .barTip(BarTip(title: "Pen", detail: "Size, colour, and what is on the layer"))
                    .accessibilityLabel("Pen Options")
                    .popover(isPresented: $showPenMenu, arrowEdge: .bottom) { PenMenu() }
            }
        }
        .disabled(!canDraw)
    }
}

// MARK: - A section of the bar

/// One section, with the grip that puts it away at its end. Collapsed, the
/// whole section is a single icon that brings it back.
struct BarGroup<Content: View>: View {
    @EnvironmentObject private var appState: AppState
    let group: ToolGroup
    @ViewBuilder let content: () -> Content

    init(_ group: ToolGroup, @ViewBuilder content: @escaping () -> Content) {
        self.group = group
        self.content = content
    }

    var body: some View {
        HStack(spacing: 2) {
            if appState.isCollapsed(group) {
                BarButton(systemImage: group.icon, label: "Show \(group.title) Tools",
                          help: "This section is put away — click to bring it back") {
                    appState.setCollapsed(group, false)
                }
                .opacity(0.55)
            } else {
                content()
            }
            BarGrip(title: group.title, collapsed: appState.isCollapsed(group)) {
                appState.setCollapsed(group, !appState.isCollapsed(group))
            }
        }
    }
}

/// The separator between two sections, and the handle that puts the section
/// on its left away. It looks like a divider until the pointer is on it.
struct BarGrip: View {
    let title: String
    var collapsed: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(hovering ? 0.45 : 0.18))
                .frame(width: hovering ? 3 : 1, height: 16)
                .frame(width: 11, height: BarButton.width)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .barTip(BarTip(title: collapsed ? "Show \(title)" : "Hide \(title)",
                       detail: collapsed ? nil : "Put this section of the bar away"))
        .accessibilityLabel(collapsed ? "Show \(title) Tools" : "Hide \(title) Tools")
    }
}

// MARK: - The controls

/// One icon button: 11pt in a 22pt square, so the bar fits a half-width
/// window with every control still legible.
struct BarButton: View {
    static let width: CGFloat = 22

    let systemImage: String
    let label: String
    let help: String
    /// The shortcut, a key to a cap: ["⇧", "⌘", "P"].
    var keys: [String] = []
    var isOn: Bool = false
    /// Inside a BarSplit, which draws the lit background for both halves, so
    /// this one draws none of its own.
    var bare: Bool = false
    /// The sidebar header fits five of these beside its buttons, so it asks
    /// for the narrow one.
    var width: CGFloat = BarButton.width
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BarGlyph(systemImage: systemImage)
                .frame(width: width, height: BarButton.width)
                .contentShape(Rectangle())
        }
        .buttonStyle(BarButtonStyle(isOn: isOn, bare: bare))
        .barTip(BarTip(title: label, keys: keys, detail: help))
        .accessibilityLabel(label)
    }
}

/// How every button on the bar answers the pointer: a soft fill under it, a
/// firmer one while it is held, the accent colour while it is on, and a
/// plain fade when there is nothing it can do.
struct BarButtonStyle: ButtonStyle {
    var isOn = false
    var bare = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .background {
                if !bare {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(fill(pressed: pressed))
                }
            }
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.10), value: pressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }

    private func fill(pressed: Bool) -> Color {
        if isOn { return Color.accentColor.opacity(pressed ? 0.34 : 0.22) }
        if pressed { return Color.primary.opacity(0.18) }
        return Color.primary.opacity(hovering && isEnabled ? 0.10 : 0)
    }
}

/// The icon itself, at the bar's one size.
struct BarGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .imageScale(.medium)
            .frame(width: BarButton.width, height: BarButton.width)
    }
}

/// A menu that looks like one of the bar's buttons: the glyph and its
/// chevron drawn as ONE image, because a borderless Menu keeps a single
/// image label and drops anything else.
struct BarMenu<Content: View>: View {
    let glyph: String
    let label: String
    let tip: BarTip
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            BarChevron.glyphWithChevron(glyph, label: label)
                .frame(width: BarButton.width + BarChevron.width, height: BarButton.width)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: BarButton.width + BarChevron.width + 4)
        .barTip(tip)
        .accessibilityLabel(label)
    }
}

/// The small arrow a control shows for the menu it opens — tucked against
/// the icon, the same height, so the two read as one thing. A drawn IMAGE,
/// not a symbol and not a path: a Menu's borderless-button style turns its
/// label into an NSButton, which sets its own font on a symbol (the arrow
/// came out icon-sized beside the camera) and drops a path altogether. A
/// template image keeps its size and takes the tint.
struct BarChevron: View {
    static let width: CGFloat = 11

    static let image: Image = Image(size: CGSize(width: BarChevron.width, height: BarButton.width),
                                    label: Text("Options")) { context in
        var path = Path()
        path.move(to: CGPoint(x: 2, y: 9.5))
        path.addLine(to: CGPoint(x: 5.5, y: 13))
        path.addLine(to: CGPoint(x: 9, y: 9.5))
        context.stroke(path, with: .color(.black),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }
    .renderingMode(.template)

    /// A glyph and the chevron in ONE image, for a menu whose label has to
    /// be a single picture.
    static func glyphWithChevron(_ systemImage: String, label: String) -> Image {
        Image(size: CGSize(width: BarButton.width + BarChevron.width, height: BarButton.width),
              label: Text(label)) { context in
            let symbol = context.resolve(Image(systemName: systemImage).renderingMode(.template))
            let height: CGFloat = 12
            let width = symbol.size.height > 0 ? symbol.size.width * height / symbol.size.height : height
            var glyph = CGRect(x: (BarButton.width - width) / 2, y: (BarButton.width - height) / 2,
                               width: width, height: height)
            glyph = glyph.integral
            context.draw(symbol, in: glyph)
            var path = Path()
            path.move(to: CGPoint(x: BarButton.width + 2, y: 9.5))
            path.addLine(to: CGPoint(x: BarButton.width + 5.5, y: 13))
            path.addLine(to: CGPoint(x: BarButton.width + 9, y: 9.5))
            context.stroke(path, with: .color(.black),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .renderingMode(.template)
    }

    var body: some View {
        BarChevron.image
            .frame(width: BarChevron.width, height: BarButton.width)
            .contentShape(Rectangle())
    }
}

/// An icon and its chevron as ONE button: one background, one hover, a
/// hairline between the two halves (Sean, 2026-09-18: "their dropdowns as
/// part of the singular button, with a small divider between the button and
/// the dropdown arrow").
struct BarSplit<Icon: View, Chevron: View>: View {
    var isOn: Bool = false
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let chevron: () -> Chevron
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 0) {
            icon()
            Rectangle()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 1, height: 12)
            chevron()
        }
        .foregroundStyle(isOn ? Color.accentColor : .primary)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isOn ? Color.accentColor.opacity(0.22)
                           : Color.primary.opacity(hovering && isEnabled ? 0.10 : 0.05)))
        .opacity(isEnabled ? 1 : 0.35)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}

extension BarSplit {
    /// The common shape: an icon, and a chevron that opens a picker.
    init<MenuContent: View>(isOn: Bool = false,
                            @ViewBuilder icon: @escaping () -> Icon,
                            @ViewBuilder menu: @escaping () -> MenuContent,
                            menuTip: @escaping () -> BarTip) where Chevron == BarSplitMenu<MenuContent> {
        self.init(isOn: isOn, icon: icon) {
            BarSplitMenu(tip: menuTip(), content: menu)
        }
    }
}

/// The chevron half of a split control, opening a menu.
struct BarSplitMenu<Content: View>: View {
    let tip: BarTip
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) { BarChevron().fixedSize() }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: BarChevron.width + 4)
            .barTip(tip)
            .accessibilityLabel(tip.title)
    }
}

struct BarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 5)
    }
}

// MARK: - Tooltips

/// What a tooltip says: the control's name, its shortcut as keycaps, and a
/// line about what it does (Sean, 2026-09-19: "nice responsive tooltips").
struct BarTip: Equatable {
    var title: String
    var keys: [String] = []
    var detail: String?
}

private struct BarTipAnchor: Equatable {
    var tip: BarTip
    var bounds: Anchor<CGRect>
}

private struct BarTipKey: PreferenceKey {
    static let defaultValue: BarTipAnchor? = nil
    static func reduce(value: inout BarTipAnchor?, nextValue: () -> BarTipAnchor?) {
        value = nextValue() ?? value
    }
}

/// Only the bar itself draws the bubbles; the same buttons used elsewhere
/// (the sidebar's header) keep the system's own help tag.
private struct BarTipsEnabledKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var barTipsEnabled: Bool {
        get { self[BarTipsEnabledKey.self] }
        set { self[BarTipsEnabledKey.self] = newValue }
    }
}

extension View {
    func barTip(_ tip: BarTip) -> some View { modifier(BarTipModifier(tip: tip)) }
}

/// A beat before the first tooltip, then none at all while the pointer runs
/// along the bar — which is what "responsive" means here: it keeps up, and
/// it does not flash at a pointer passing through.
@MainActor
enum BarTipTiming {
    static var lastShown = Date.distantPast

    static var delay: UInt64 {
        Date().timeIntervalSince(lastShown) < 0.8 ? 70_000_000 : 420_000_000
    }
}

struct BarTipModifier: ViewModifier {
    let tip: BarTip
    @Environment(\.barTipsEnabled) private var enabled
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    @State private var showing = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .onHover { inside in
                    hovering = inside
                    if !inside {
                        if showing { BarTipTiming.lastShown = Date() }
                        showing = false
                    }
                }
                .task(id: hovering) {
                    guard hovering else { return }
                    try? await Task.sleep(nanoseconds: BarTipTiming.delay)
                    guard !Task.isCancelled, hovering else { return }
                    showing = true
                    BarTipTiming.lastShown = Date()
                }
                .anchorPreference(key: BarTipKey.self, value: .bounds) { bounds in
                    showing ? BarTipAnchor(tip: tip, bounds: bounds) : nil
                }
        } else {
            // Outside the bar — the sidebar's header — the system's help tag.
            content.help(tip.detail ?? tip.title)
        }
    }
}

/// The bubble: the name, the keycaps, and the line underneath. It hangs
/// below the bar and is nudged sideways to stay inside the pane.
///
/// Not private: `detailWidth` is the rule that keeps the pane big enough for
/// what is written on it, and WriteMindTests holds it.
struct BarTipBubble: View {
    let tip: BarTip
    let over: CGRect
    let within: CGSize
    @State private var size: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(tip.title).font(.system(size: 12, weight: .semibold))
                if !tip.keys.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(Array(tip.keys.enumerated()), id: \.offset) { _, key in
                            Text(key)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .frame(minWidth: 15)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Color.primary.opacity(0.14)))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if let detail = tip.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: BarTipBubble.detailWidth(detail), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.10)))
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
        .fixedSize()
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { size = proxy.size }
                    .onChange(of: proxy.size) { _, new in size = new }
            }
        }
        .position(x: clampedX, y: over.maxY + 8 + size.height / 2)
        .transition(.opacity)
    }

    /// How wide the line under the title is allowed to be: its own width,
    /// measured, up to a cap.
    ///
    /// Sean, 2026-09-19: "the pane behind the tooltip for the buttons like
    /// shapes etc isn't big enough". It was `maxWidth: 240`, and under this
    /// bubble's own `.fixedSize()` NOTHING proposes a width — so the cap
    /// clamped the BOX while the text went on laying itself out as one long
    /// line and drew straight out of the material behind it. The Shapes tip
    /// ("Flow-chart shapes, and arrows between them — hold ⌥ and drag from a
    /// node") is nearly twice the cap, which is why that one showed it worst.
    ///
    /// A concrete width is a real proposal, so a long detail WRAPS and the
    /// pane grows down with it, while a short one still gets a bubble no
    /// wider than its own words. The measurement is AppKit's because the
    /// font is the same one SwiftUI resolves `.system(size: 11)` to, and the
    /// extra point covers the rounding between the two.
    static func detailWidth(_ detail: String, cap: CGFloat = 240) -> CGFloat {
        let measured = (detail as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)])
            .width
        return min(measured.rounded(.up) + 1, cap)
    }

    private var clampedX: CGFloat {
        guard size.width > 0 else { return over.midX }
        let half = size.width / 2
        return min(max(over.midX, half + 6), max(half + 6, within.width - half - 6))
    }
}
