import AppKit
import Combine
import SwiftUI

/// The drawing layer over the editor.
///
/// In pen mode it takes every click and draws; in select mode it takes every
/// click and pulls a rectangle round whatever it touches. In cursor mode it
/// takes only the clicks that land on an object — everything else falls
/// through to the text underneath — so a drawing can be dragged, scaled and
/// rotated without the editor losing a single keystroke (Sean, 2026-09-18).
/// Holding ⌘ there is the marquee as well, which is where select mode came
/// from and is why the modifier still works.
struct DrawingCanvas: View {
    @Binding var drawing: Drawing
    /// Whose pane it is (`AppState.CanvasMode`). The pen was a boolean
    /// until 2026-09-20 and everything here that asks whether it is up
    /// still asks, through `penActive`.
    let mode: AppState.CanvasMode
    private var penActive: Bool { mode == .pen }
    let color: Color
    let width: Double
    /// What a tablet's nib writes with (`AppState.penTool`). A mouse or a
    /// trackpad stroke never takes it — it is the legacy line.
    var tool: InkTool = .pen
    /// Where the pictures are, so they can be drawn.
    var mediaDirectory: URL?
    /// Changing it drops the selection — another note's objects are not this
    /// note's selection.
    var documentID: String?
    /// Bumped when the text view takes a click, so the objects let go.
    var deselectToken: Int = 0
    /// Called before the first change of a gesture, so undo gets a snapshot
    /// of what things looked like before it.
    var onBeginChange: (() -> Void)?
    /// The pane's size, so a pasted picture can be sized to fit it.
    var onSize: ((CGSize) -> Void)?
    /// The crop was confirmed: keep only this part (fractions of the
    /// picture, top-left origin) of this picture.
    var onCrop: ((UUID, CGRect) -> Void)?
    /// Read the words in this picture into the note.
    var onReadText: ((UUID) -> Void)?
    /// ⌘V with a picture on the pasteboard and no text view to take it.
    var onPasteImage: ((NSPasteboard) -> Bool)?
    /// The arrow tool: a drag from one thing to another draws a connector
    /// (Sean, 2026-09-18: "arrows can be drawn from node to node").
    var connectActive: Bool = false
    /// A shape to open for typing straight away (a text box just added),
    /// and the word that it has been.
    var pendingLabelEdit: UUID?
    var onLabelEditStarted: (() -> Void)?
    /// Something on the layer is picked, or nothing is — the menu bar needs
    /// to know, so ⌘Z can be the drawing's.
    var onSelectionChanged: ((Bool) -> Void)?
    /// ⌘Z and ⇧⌘Z while the layer owns them. Each returns true when it had
    /// something to do; false hands the key on to the text underneath.
    var onUndo: (() -> Bool)?
    var onRedo: (() -> Bool)?
    /// The tablet's page was written on last (`AppState.pageOwnsUndo`):
    /// ⌘Z is the page's, and goes on to the Edit menu that gives it there.
    var pageOwnsUndo: () -> Bool = { false }
    /// A shape or a mark armed by the palette: the next drag puts it down,
    /// from where the drag starts to where it ends (Sean, 2026-09-19) — and
    /// a node or a line stays armed for the drag after
    /// (`CanvasPlacement.staysArmed`).
    var placing: CanvasPlacement?
    /// The tool is handed back: a mark put down with no ⌘ held, or Esc.
    var onDisarm: (() -> Void)?
    /// Esc with the pen up: the pen goes down. True when it was taken.
    var onEscapePen: (() -> Bool)?
    /// Esc while the tablet's page has a box up: it is put away. True when
    /// it was taken (`TabletBox.key`).
    var onEscapeBox: ((NSEvent) -> Bool)?
    /// The tablet's marquee — the nib dragged with a side switch held — let
    /// go over the notes, in document points (`NotebookScribe.picks`):
    /// picked by the marquee's own rule.
    var tabletPicks: AnyPublisher<CGRect, Never> = Empty().eraseToAnyPublisher()
    /// How far the text under the layer has scrolled. Objects live in the
    /// DOCUMENT — a picture sits beside the paragraph it was put next to and
    /// goes up with it — so everything is drawn and hit this far up.
    var scrollOffset: CGFloat = 0

    /// A point on the pane, in the document's coordinates.
    private func doc(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: point.y + scrollOffset) }
    /// A point in the document, where it is on the pane.
    private func screen(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: point.y - scrollOffset) }

    private enum Interaction: Equatable {
        case drawing
        case moving
        case handle
        case marquee(start: CGPoint, additive: Bool)
        case connecting(from: CGPoint, node: UUID?)
        case placing(from: CGPoint)
        case idle
    }

    private enum HandleKind { case rotate, scale, move }

    private static let space = "WriteMindCanvas"

    @State private var current: Stroke?
    /// The note's paper in this appearance, for showing ink that would
    /// otherwise be the paper's own colour.
    @Environment(\.colorScheme) private var colorScheme
    private var notePaper: String { InkPaths.notePaperHex(dark: colorScheme == .dark) }
    @State private var selection: Set<UUID> = []
    @State private var hovered: UUID?
    @State private var hoveredHandles: Set<String> = []
    @State private var marquee: CGRect?
    @State private var interaction: Interaction?
    @State private var snapshot: [UUID: ItemTransform] = [:]
    @State private var pivot: CGPoint = .zero
    @State private var startAngle: Double = 0
    @State private var commandDown = false
    @State private var images: [String: Image] = [:]
    @State private var flagsMonitor: Any?
    @State private var keyMonitor: Any?
    /// The picture being cropped, and the crop box as fractions of it.
    @State private var cropping: UUID?
    @State private var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// An arrow being drawn, from where to where, in view points.
    @State private var connectPreview: (from: CGPoint, to: CGPoint)?
    /// The shape being dragged out, before it is real.
    @State private var placePreview: (from: CGPoint, to: CGPoint)?
    /// The connector whose style bar is up, and whether it has been changed
    /// yet (the first change is what goes on the undo stack).
    @State private var styling: UUID?
    @State private var styledOnce = false
    /// The node whose label is being typed.
    @State private var editingLabel: UUID?
    /// The pane's size, kept so the model can be measured from outside the
    /// geometry reader (a text box grows as it is typed into).
    @State private var paneSize: CGSize = .zero
    @State private var labelSnapshot = false
    @FocusState private var labelFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // ONLY WHILE THE LAYER HAS A CURSOR OF ITS OWN — the pen's
                // pencil, the crosshair, a hand on an object. AppKit hands
                // a cursorUpdate to whatever the window's hit test finds
                // under the pointer, and while one is the current event
                // SwiftUI answers that hit test with the topmost NSView it
                // hosts, whatever that view's `hitTest` says and whatever
                // `allowsHitTesting` says. Mounted always, with no cursor
                // in cursor mode, this layer was that view for the whole
                // pane: every cursorUpdate went to its host, and the
                // window behind the host put the arrow up over the seams
                // and the words (Sean, 2026-10-02: "the horizontal cursor
                // stuff should work in markdown view mode"). With no tool
                // up the pane is the notebook's, so nothing of ours is
                // over it. `CursorRoutingTests` pins both halves.
                if let cursor {
                    CursorLayer(cursor: cursor)
                        .allowsHitTesting(false)
                }

                Canvas { context, size in render(&context, size: size) }
                    .contentShape(CanvasHitShape(items: drawing.visibleItems,
                                                 everything: mode != .cursor || commandDown
                                                     || connectActive || placing != nil,
                                                 offset: scrollOffset))
                    .gesture(drag(in: geo.size))
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        hover(phase, in: geo.size)
                    }

                // NOT WHILE A TOOL IS ARMED. The handles are real views
                // over the canvas, so the one round the shape just put
                // down would swallow the next press — which, with a node
                // or a line staying armed or ⌘ held over a mark, is the
                // next one, landing beside it (Sean, 2026-09-21: "if i
                // hold cmd, stay in adding that marker mode"; 2026-10-02:
                // "after drawing a rectangle dont exit rectangle mode..").
                // The pane belongs to the tool until the tool is handed
                // back, and Escape is how it is handed back.
                if !penActive, placing == nil, let box = drawing.bounds(of: handleIDs, in: geo.size) {
                    handles(box: box, in: geo.size)
                }

                if let styling, let item = drawing[id: styling], case .connector = item {
                    ConnectorStyleBar(connector: connectorBinding(styling)) { self.styling = nil }
                        .position(screen(styleBarPosition(for: item, in: geo.size)))
                }

                if let editingLabel, let item = drawing[id: editingLabel],
                   case .shape(let shape) = item, shape.kind.isNode {
                    let box = item.bounds(in: geo.size)
                    if shape.kind == .text {
                        textBoxEditor(shape, id: editingLabel, item: item, in: geo.size)
                    } else {
                        TextField("Label", text: labelBinding(editingLabel), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .lineLimit(1...4)
                            .frame(width: max(90, box.width - 8))
                            .position(x: box.midX, y: box.midY - scrollOffset)
                            .focused($labelFocused)
                            .onSubmit { self.editingLabel = nil }
                            .onAppear { labelFocused = true }
                    }
                }
            }
            .coordinateSpace(name: Self.space)
            .onAppear { loadImages(); watchModifiers(); watchKeys() }
            .onDisappear { unwatchModifiers(); unwatchKeys() }
            // The key monitor answers for the layer as it is NOW: put up
            // again from this copy of the view whenever what it reads
            // changes (`KeyInputs`).
            .onChange(of: keyInputs) { _, _ in if keyMonitor != nil { watchKeys() } }
            .onChange(of: geo.size, initial: true) { _, size in
                paneSize = size
                onSize?(size)
                // A note just opened has lines that have never been routed,
                // and a resized pane moves the nodes they run between.
                // reconnect only writes back what actually changed, so this
                // settles in one pass.
                if size.width > 1, size.height > 1 { drawing.reconnect(in: size) }
            }
            .onChange(of: drawing.images.map(\.file)) { _, _ in loadImages() }
            .onChange(of: documentID) { _, _ in
                selection = []; hovered = nil; cropping = nil; styling = nil; editingLabel = nil
            }
            .onChange(of: deselectToken) { _, _ in selection = []; cropping = nil; styling = nil; editingLabel = nil }
            .onChange(of: selection) { _, picked in onSelectionChanged?(!picked.isEmpty) }
            .onReceive(tabletPicks) { rect in pick(byTablet: rect) }
            // A mode change leaves nothing behind it: not a selection, not
            // a crop half-dragged, not an arrow's style bar, not a label
            // being typed. Each of those is a conversation with one mode.
            .onChange(of: mode) { _, _ in
                selection = []; hovered = nil; cropping = nil; styling = nil; editingLabel = nil
            }
            .onChange(of: connectActive) { _, _ in
                selection = []; hovered = nil; cropping = nil; styling = nil; editingLabel = nil
            }
            .onChange(of: pendingLabelEdit) { _, id in
                guard let id, drawing[id: id] != nil else { return }
                beginLabel(id)
                onLabelEditStarted?()
            }
            .onChange(of: editingLabel) { old, new in
                // A text box grows and shrinks to what was typed once the
                // typing is over.
                if let old, new == nil { fitTextBox(old, in: geo.size) }
            }
        }
    }

    // MARK: - Drawing the layer

    private func render(_ context: inout GraphicsContext, size: CGSize) {
        // Everything below is in the document's coordinates.
        context.translateBy(x: 0, y: -scrollOffset)
        for item in drawing.visibleItems { draw(item, in: &context, size: size) }
        if let current { Self.paintLive(current, in: &context, size: size, paper: notePaper) }
        // The shape as it is being dragged out, before it is real.
        if let placing, let preview = placePreview,
           let ghost = placing.item(from: preview.from, to: preview.to, in: size,
                                    colorHex: color.hexString, lineWidth: width) {
            var layer = context
            layer.opacity = 0.65
            draw(ghost, in: &layer, size: size)
        }

        if !penActive {
            for id in chromeIDs {
                guard let item = drawing[id: id] else { continue }
                let corners = item.frameCorners(in: size)
                guard let first = corners.first else { continue }
                var path = Path()
                path.move(to: first)
                for corner in corners.dropFirst() { path.addLine(to: corner) }
                path.closeSubpath()
                let selected = selection.contains(id)
                context.stroke(path, with: .color(Color.accentColor.opacity(selected ? 0.95 : 0.5)),
                               style: StrokeStyle(lineWidth: selected ? 1.5 : 1,
                                                  dash: selected ? [4, 3] : [2, 3]))
            }
        }

        if let marquee { Self.paintMarquee(marquee, in: &context) }

        if let connectPreview {
            var line = Path()
            line.move(to: connectPreview.from)
            line.addLine(to: connectPreview.to)
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: min(max(width, 1.5), 6), dash: [6, 4]))
        }

        // Cropping: what would go is dimmed, what stays is boxed.
        if !penActive, let cropping, let item = drawing[id: cropping], case .image = item {
            let matrix = item.matrix(in: size)
            let kept = Self.cropCorners(cropRect, in: item.baseBounds(in: size)).map { $0.applying(matrix) }
            var outside = Self.polygon(item.frameCorners(in: size))
            outside.addPath(Self.polygon(kept))
            context.fill(outside, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
            context.stroke(Self.polygon(kept), with: .color(.white),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
        }
    }

    /// A stroke still being written, on a context already in the document's
    /// coordinates: the layer's own pen's, and the tablet's in the note
    /// (`NotebookLiveInk`) — ONE painter, so the ink being written is the
    /// ink that lands.
    static func paintLive(_ stroke: Stroke, in context: inout GraphicsContext, size: CGSize,
                          paper: String? = nil) {
        draw(stroke, points: CanvasItem.stroke(stroke).basePoints(in: size), in: &context, paper: paper)
    }

    /// The marquee as it is dragged, in document points — a ⌘-drag's, and
    /// the tablet side switch's over the notes.
    static func paintMarquee(_ rect: CGRect, in context: inout GraphicsContext) {
        let path = Path(rect)
        context.fill(path, with: .color(Color.accentColor.opacity(0.12)))
        context.stroke(path, with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    /// The crop box's corners in the picture's own (untransformed) frame:
    /// top left, top right, bottom right, bottom left.
    static func cropCorners(_ rect: CGRect, in base: CGRect) -> [CGPoint] {
        [CGPoint(x: base.minX + rect.minX * base.width, y: base.minY + rect.minY * base.height),
         CGPoint(x: base.minX + rect.maxX * base.width, y: base.minY + rect.minY * base.height),
         CGPoint(x: base.minX + rect.maxX * base.width, y: base.minY + rect.maxY * base.height),
         CGPoint(x: base.minX + rect.minX * base.width, y: base.minY + rect.maxY * base.height)]
    }

    private func draw(_ item: CanvasItem, in context: inout GraphicsContext, size: CGSize) {
        let centre = item.baseCenter(in: size)
        let transform = item.transform
        context.drawLayer { layer in
            layer.translateBy(x: centre.x + transform.dx * size.width,
                              y: centre.y + transform.dy * size.height)
            layer.rotate(by: .radians(transform.rotation))
            layer.scaleBy(x: transform.scale, y: transform.scale)
            layer.translateBy(x: -centre.x, y: -centre.y)

            switch item {
            case .stroke(let stroke):
                Self.draw(stroke, points: item.basePoints(in: size), in: &layer, paper: notePaper)
            case .image(let image):
                let box = item.baseBounds(in: size)
                if let loaded = images[image.file] {
                    layer.draw(layer.resolve(loaded), in: box)
                } else {
                    // The file is missing or still loading: show its place.
                    layer.stroke(Path(roundedRect: box, cornerRadius: 4),
                                 with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            case .shape(let shape) where shape.kind == .text:
                // A card, not a dashed rectangle with words near it: the
                // fill and the corner are one shape, the words sit inside
                // the same padding the editor uses, and the ink is checked
                // against the fill before it is drawn (Sean, 2026-09-19:
                // "text boxes look like shit… just start over and do
                // better"). While it is being typed into, the field over
                // the top is the box — nothing is drawn underneath it.
                let box = item.baseBounds(in: size)
                let card = Path(roundedRect: box, cornerRadius: TextBoxStyle.cornerRadius)
                if let fill = shape.fillHex, let fillColour = Color(hex: fill) {
                    layer.fill(card, with: .color(fillColour))
                }
                if editingLabel == shape.id { break }
                let inset = CGRect(x: box.minX + TextBoxStyle.padding.width,
                                   y: box.minY + TextBoxStyle.padding.height,
                                   width: max(1, box.width - TextBoxStyle.padding.width * 2),
                                   height: max(1, box.height - TextBoxStyle.padding.height * 2))
                if shape.label.isEmpty {
                    // An empty box has to be findable and grabbable, so it
                    // keeps a quiet card of its own until there are words.
                    if shape.fillHex == nil { layer.fill(card, with: .color(.secondary.opacity(0.07))) }
                    layer.stroke(card, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1))
                    let hint = layer.resolve(Text("Text").font(TextBoxStyle.textFont)
                        .foregroundStyle(.secondary))
                    layer.draw(hint, at: CGPoint(x: inset.minX, y: inset.minY), anchor: .topLeading)
                } else {
                    let ink = Color(hex: TextBoxStyle.readableInk(shape.colorHex, on: shape.fillHex)) ?? .primary
                    let resolved = layer.resolve(Text(shape.label).font(TextBoxStyle.textFont)
                        .foregroundStyle(ink))
                    layer.draw(resolved, in: inset)
                }
            case .shape(let shape):
                let box = item.baseBounds(in: size)
                let path = shape.kind.path(in: box)
                let colour = Color(hex: shape.colorHex) ?? .primary
                if let fill = shape.fillHex, let fillColour = Color(hex: fill) {
                    layer.fill(path, with: .color(fillColour))
                }
                layer.stroke(path, with: .color(colour),
                             style: StrokeStyle(lineWidth: shape.lineWidth, lineCap: .round, lineJoin: .round))
                if !shape.label.isEmpty, editingLabel != shape.id {
                    let resolved = layer.resolve(Text(shape.label).font(.system(size: 13)).foregroundStyle(colour))
                    let room = CGSize(width: max(10, box.width - 12), height: max(10, box.height - 8))
                    let measured = resolved.measure(in: room)
                    layer.draw(resolved, in: CGRect(x: box.midX - measured.width / 2,
                                                    y: box.midY - measured.height / 2,
                                                    width: measured.width, height: measured.height))
                }
            case .connector(let connector):
                Self.draw(connector, points: item.basePoints(in: size), in: &layer)
            }
        }
    }

    /// The line, stopped short of a head so the tip is the point, and the
    /// heads.
    static func draw(_ connector: ConnectorItem, points: [CGPoint], in context: inout GraphicsContext) {
        // The line and its heads come from InkPaths, which is also what
        // the PDF is drawn from: one description of the shape, two places
        // it is painted.
        let (line, heads) = InkPaths.paths(for: connector, points: points)
        guard !points.isEmpty else { return }
        let colour = Color(hex: connector.colorHex) ?? .primary
        context.stroke(line, with: .color(colour),
                       style: StrokeStyle(lineWidth: connector.lineWidth,
                                          lineCap: connector.line == .dotted ? .round : .butt,
                                          lineJoin: .round,
                                          dash: connector.dash()))
        for head in heads { context.fill(head, with: .color(colour)) }
    }

    /// `paper` is what the stroke is painted over, when it is the NOTE:
    /// ink the paper's own colour is shown as its opposite there
    /// (`InkPaths.shownHex`). Nil paints the colour as it is — the tablet's
    /// page, whose paper keeps its ink readable by its own rule.
    static func draw(_ stroke: Stroke, points: [CGPoint], in context: inout GraphicsContext,
                     paper: String? = nil) {
        let hex = paper.map { InkPaths.shownHex(stroke.colorHex, onPaper: $0) } ?? stroke.colorHex
        let colour = Color(hex: hex) ?? .orange
        let (path, filled) = InkPaths.path(for: stroke, points: points)
        // Ink is one filled outline, so the tool's opacity goes on the
        // colour: the whole stroke is laid down once and never darkens
        // where it crosses itself. A legacy stroke has no tool and is
        // painted below exactly as it always was.
        if let tool = stroke.inkTool {
            context.fill(path, with: .color(colour.opacity(tool.opacity)))
            return
        }
        if filled {
            context.fill(path, with: .color(colour))
        } else if !points.isEmpty {
            context.stroke(path, with: .color(colour),
                           style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - The handles

    /// What the outline and the handles are drawn around: the selection, or —
    /// so the buttons are there before anything is clicked — whatever the
    /// pointer is over.
    private var chromeIDs: Set<UUID> {
        if !selection.isEmpty { return selection }
        if let hovered { return [hovered] }
        return []
    }

    /// What the handles are drawn for: the selection, or — so the buttons
    /// are there before anything is clicked — a hovered stroke or shape. A
    /// hovered PICTURE gets the outline only; its buttons wait for a click
    /// (Sean, 2026-09-18: "edit buttons on an image selection should only
    /// appear after the image is clicked").
    private var handleIDs: Set<UUID> {
        if !selection.isEmpty { return CanvasGroups.whole(selection, in: drawing.items) }
        if let hovered, let item = drawing[id: hovered], item.image == nil { return [hovered] }
        return []
    }

    @ViewBuilder
    private func handles(box: CGRect, in size: CGSize) -> some View {
        if let cropping, let item = drawing[id: cropping], case .image = item {
            cropHandles(for: item, box: box, in: size)
        } else if let connector = routedSelection {
            // A routed line has no size and no angle of its own: it has
            // segments, and each one can be pushed sideways (Sean,
            // 2026-09-19, draw.io's way).
            segmentHandles(for: connector, in: size)
        } else {
            objectHandles(box: box, in: size)
        }
    }

    /// The one selected connector, if it is a routed one.
    private var routedSelection: ConnectorItem? {
        guard handleIDs.count == 1, let id = handleIDs.first,
              let item = drawing[id: id], case .connector(let connector) = item,
              connector.isRouted
        else { return nil }
        return connector
    }

    @ViewBuilder
    private func segmentHandles(for connector: ConnectorItem, in size: CGSize) -> some View {
        let path = connector.route.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        ForEach(ConnectorRouting.midpoints(of: path), id: \.index) { segment in
            Circle()
                .fill(.white)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                .shadow(radius: 1.5, y: 0.5)
                .contentShape(Circle().inset(by: -6))
                .position(x: segment.point.x, y: segment.point.y - scrollOffset)
                .help(segment.vertical ? "Drag left or right to move this part of the line"
                                       : "Drag up or down to move this part of the line")
                .onHover { inside in
                    if inside { hoveredHandles.insert("segment\(segment.index)") }
                    else { hoveredHandles.remove("segment\(segment.index)") }
                }
                .gesture(segmentDrag(connector.id, segment: segment.index,
                                     vertical: segment.vertical, in: size))
        }

        // The way back to the heads and the line style, which the object
        // handles would otherwise have carried.
        Handle(systemImage: "slider.horizontal.3", help: "Heads and line style",
               hovered: $hoveredHandles, name: "style")
            .position(x: min(max(path[0].x, 14), max(size.width - 14, 14)),
                      y: min(max(path[0].y - scrollOffset - 16, 14), max(size.height - 14, 14)))
            .onTapGesture { selection = [connector.id]; styling = connector.id; styledOnce = false }
        Handle(systemImage: "trash", help: "Delete (⌫ does too)", hovered: $hoveredHandles, name: "trash")
            .position(x: min(max(path[path.count - 1].x, 14), max(size.width - 14, 14)),
                      y: min(max(path[path.count - 1].y - scrollOffset + 16, 14), max(size.height - 14, 14)))
            .onTapGesture { deleteSelection() }
    }

    /// Pushing one part of a routed line sideways; where it is let go is
    /// where it stays.
    private func segmentDrag(_ id: UUID, segment: Int, vertical: Bool, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if interaction == nil {
                    onBeginChange?()
                    interaction = .handle
                }
                guard interaction == .handle, size.width > 1, size.height > 1 else { return }
                let point = doc(value.location)
                let coordinate = vertical ? point.x / size.width : point.y / size.height
                setOverride(id, segment: segment, vertical: vertical, value: coordinate, in: size)
            }
            .onEnded { _ in
                interaction = nil
                snapshot = [:]
            }
    }

    private func setOverride(_ id: UUID, segment: Int, vertical: Bool, value: Double, in size: CGSize) {
        guard let index = drawing.items.firstIndex(where: { $0.id == id }),
              case .connector(var connector) = drawing.items[index] else { return }
        connector.overrides.removeAll { $0.index == segment }
        connector.overrides.append(ConnectorItem.SegmentOverride(index: segment, vertical: vertical,
                                                                 value: value))
        drawing.items[index] = .connector(connector)
        drawing.reconnect(in: size)
    }

    /// The crop box's corners to drag, and the two ways out (Sean,
    /// 2026-09-18: "a crop button in the bottom left").
    @ViewBuilder
    private func cropHandles(for item: CanvasItem, box: CGRect, in size: CGSize) -> some View {
        let matrix = item.matrix(in: size)
        let corners = Self.cropCorners(cropRect, in: item.baseBounds(in: size)).map { $0.applying(matrix) }
        ForEach(0..<4, id: \.self) { corner in
            Handle(systemImage: "", help: "Drag to set what to keep", hovered: $hoveredHandles,
                   name: "crop-\(corner)", plain: true)
                .position(screen(corners[corner]))
                .gesture(cropDrag(corner: corner, item: item, in: size))
        }
        Handle(systemImage: "checkmark", help: "Crop to the box (↩)", hovered: $hoveredHandles, name: "crop-confirm")
            .position(clamp(CGPoint(x: box.minX + 10, y: box.maxY + 14), in: size))
            .onTapGesture { confirmCrop() }
        Handle(systemImage: "xmark", help: "Leave the picture as it is (esc)", hovered: $hoveredHandles,
               name: "crop-cancel")
            .position(clamp(CGPoint(x: box.minX + 36, y: box.maxY + 14), in: size))
            .onTapGesture { cancelCrop() }
    }

    /// A handle's place on the pane for a point in the document, kept on
    /// the pane.
    private func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 14), max(size.width - 14, 14)),
                y: min(max(point.y - scrollOffset, 14), max(size.height - 14, 14)))
    }

    @ViewBuilder
    private func objectHandles(box: CGRect, in size: CGSize) -> some View {
        let x = { (value: CGFloat) in min(max(value, 14), max(size.width - 14, 14)) }
        let y = { (value: CGFloat) in min(max(value - scrollOffset, 14), max(size.height - 14, 14)) }

        Handle(systemImage: "arrow.clockwise", help: "Drag to rotate (hold ⇧ for 15° steps)",
               hovered: $hoveredHandles, name: "rotate")
            .position(x: x(box.midX), y: y(box.minY - 20))
            .gesture(handleDrag(kind: .rotate, in: size))

        Handle(systemImage: "arrow.up.left.and.arrow.down.right", help: "Drag to scale",
               hovered: $hoveredHandles, name: "scale")
            .position(x: x(box.maxX + 12), y: y(box.maxY + 12))
            .gesture(handleDrag(kind: .scale, in: size))

        // Dragging the ink itself moves it too, but a thin stroke is a small
        // target and a picture under the pointer is not obviously draggable —
        // so there is a button that says so (Sean, 2026-09-18).
        Handle(systemImage: "arrow.up.and.down.and.arrow.left.and.right", help: "Drag to move",
               hovered: $hoveredHandles, name: "move")
            .position(x: x(box.maxX + 12), y: y(box.minY - 12))
            .gesture(handleDrag(kind: .move, in: size))

        Handle(systemImage: "trash", help: "Delete (⌫ does too)", hovered: $hoveredHandles, name: "trash")
            .position(x: x(box.minX - 12), y: y(box.minY - 12))
            .onTapGesture { deleteSelection() }

        // Hold what is picked together, or take it apart — the button says
        // which it will do, and ⌃G does the same (Sean, 2026-09-20).
        if groupingToggle != .nothing {
            let ungrouping = groupingToggle == .ungroup
            Handle(systemImage: ungrouping ? "rectangle.on.rectangle.slash" : "square.on.square",
                   help: ungrouping ? "Ungroup these (⌃G does too)" : "Group these (⌃G does too)",
                   hovered: $hoveredHandles, name: "group")
                .position(x: x(box.midX), y: y(box.maxY + 20))
                .onTapGesture { toggleGrouping() }
        }

        // An arrow's heads and line come from its bar; this is the way back
        // to it once it has gone.
        if let id = handleIDs.first, handleIDs.count == 1, let item = drawing[id: id], case .connector = item {
            Handle(systemImage: "slider.horizontal.3", help: "Heads and line style",
                   hovered: $hoveredHandles, name: "style")
                .position(x: x(box.minX - 12), y: y(box.maxY + 12))
                .onTapGesture { selection = [id]; styling = id; styledOnce = false }
        }

        // A picture can lose its edges; ink is what it is.
        if let id = handleIDs.first, handleIDs.count == 1, let item = drawing[id: id], case .image = item {
            Handle(systemImage: "crop", help: "Crop the picture", hovered: $hoveredHandles, name: "crop")
                .position(x: x(box.minX - 12), y: y(box.maxY + 12))
                .onTapGesture { beginCrop(id) }
            // The words in it, into the note under it (Sean, 2026-09-18).
            Handle(systemImage: "text.viewfinder", help: "Read the writing in the picture into the note, under it",
                   hovered: $hoveredHandles, name: "read")
                .position(x: x(box.midX), y: y(box.maxY + 12))
                .onTapGesture { onReadText?(id) }
        }
    }

    private struct Handle: View {
        let systemImage: String
        let help: String
        @Binding var hovered: Set<String>
        let name: String
        /// A bare white dot — the crop box's corners, which are dragged, not read.
        var plain = false

        var body: some View {
            Group {
                if plain {
                    Circle().fill(.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor))
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                }
            }
            .shadow(radius: 1.5, y: 0.5)
            .contentShape(Circle())
            .help(help)
            .onHover { inside in
                if inside { hovered.insert(name) } else { hovered.remove(name) }
            }
        }
    }

    // MARK: - Cropping

    private func beginCrop(_ id: UUID) {
        guard let item = drawing[id: id], case .image = item else { return }
        selection = [id]
        cropping = id
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private func cropDrag(corner: Int, item: CanvasItem, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let base = item.baseBounds(in: size)
                guard base.width > 0, base.height > 0 else { return }
                // Back through the item's transform, so a turned picture's
                // corners still drag along its own edges.
                let local = doc(value.location).applying(item.matrix(in: size).inverted())
                let point = CGPoint(x: (local.x - base.minX) / base.width,
                                    y: (local.y - base.minY) / base.height)
                cropRect = CanvasEdit.cropRect(cropRect, movingCorner: corner, to: point)
            }
    }

    private func confirmCrop() {
        guard let id = cropping else { return }
        let changed = cropRect.minX > 0.002 || cropRect.minY > 0.002
            || cropRect.maxX < 0.998 || cropRect.maxY < 0.998
        if changed { onCrop?(id, cropRect) }
        cropping = nil
    }

    private func cancelCrop() {
        cropping = nil
    }

    // MARK: - Arrows and labels

    private func beginLabel(_ id: UUID) {
        selection = [id]
        editingLabel = id
        labelSnapshot = false
    }

    /// A text box is as tall as its text — measured on every keystroke, so
    /// the card grows under the caret instead of catching up afterwards.
    private func fitTextBox(_ id: UUID, in size: CGSize) {
        guard case .shape(var shape)? = drawing[id: id], shape.kind == .text, size.width > 0 else { return }
        let aspect = TextBoxStyle.aspect(for: shape.label, boxWidth: shape.width * size.width)
        guard abs(aspect - shape.aspect) > 0.001 else { return }
        shape.aspect = aspect
        drawing[id: id] = .shape(shape)
    }

    /// The box, typed into where it sits: the same font, the same padding,
    /// the same corner and the same width as the card underneath, so the
    /// words do not move when the caret arrives or leaves. Return puts in a
    /// line; Escape (handled with the other keys) is done.
    @ViewBuilder
    private func textBoxEditor(_ shape: ShapeItem, id: UUID, item: CanvasItem, in size: CGSize) -> some View {
        let base = item.baseBounds(in: size)
        let box = item.bounds(in: size)
        let fill = shape.fillHex.flatMap { Color(hex: $0) }
        let inkHex = TextBoxStyle.readableInk(shape.colorHex, on: shape.fillHex)
        let width = max(TextBoxStyle.minimumWidth, base.width)
        let height = max(base.height, TextBoxStyle.height(for: shape.label, width: width))
        TextBoxField(text: labelBinding(id), ink: NSColor(hex: inkHex) ?? .textColor)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: TextBoxStyle.cornerRadius)
                .fill(fill ?? Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: TextBoxStyle.cornerRadius)
                .strokeBorder(Color.accentColor, lineWidth: 1.5))
            .scaleEffect(item.transform.scale)
            .rotationEffect(.radians(item.transform.rotation))
            .position(x: box.midX, y: box.midY - scrollOffset)
    }

    private func labelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { drawing[id: id]?.shape?.label ?? "" },
            set: { text in
                guard case .shape(var shape)? = drawing[id: id] else { return }
                if !labelSnapshot { onBeginChange?(); labelSnapshot = true }
                shape.label = text
                drawing[id: id] = .shape(shape)
                if shape.kind == .text { fitTextBox(id, in: paneSize) }
            })
    }

    private func connectorBinding(_ id: UUID) -> Binding<ConnectorItem> {
        Binding(
            get: { drawing[id: id]?.connector ?? ConnectorItem(start: .zero, end: .zero, colorHex: "#000000") },
            set: { connector in
                if !styledOnce { onBeginChange?(); styledOnce = true }
                drawing[id: id] = .connector(connector)
            })
    }

    /// Under the arrow, kept inside the pane.
    private func styleBarPosition(for item: CanvasItem, in size: CGSize) -> CGPoint {
        let box = item.bounds(in: size)
        return CGPoint(x: min(max(box.midX, 160), max(size.width - 160, 160)),
                       y: min(box.maxY + 34, max(size.height - 24, 24)))
    }

    // MARK: - Gestures

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if interaction == nil { begin(at: doc(value.startLocation), in: size) }
                switch interaction {
                case .drawing:
                    DrawingCursors.pencil.set()
                    let point = Self.normalise(doc(value.location), in: size)
                    // The nib's pressure for THIS event, read off the
                    // event by `PenSampleReader`'s monitor before the
                    // gesture saw it. A tablet's first event makes the
                    // stroke ink with a pressure per point; a mouse or a
                    // trackpad stroke stays the legacy line, drawn as it
                    // always was (Sean, 2026-10-02: "make the text strokes
                    // well implemented to feel natural for writing
                    // letters.. do the same for drawing mode in the
                    // notebook itself"), with the tool on the pen menu.
                    let pen = PenSampleReader.shared.sample
                    if current == nil {
                        onBeginChange?()
                        current = Stroke.starting(at: point, colorHex: color.hexString, width: width, pen: pen,
                                                  tool: tool)
                    } else {
                        current?.append(point, pen: pen)
                    }
                case .moving:
                    apply(translate: CGVector(dx: value.translation.width, dy: value.translation.height),
                          in: size)
                case .marquee(let start, _):
                    marquee = CanvasGeometry.rect(from: start, to: doc(value.location))
                case .connecting(let start, _):
                    // ⇧ holds an arrow to an axis while it is dragged, and
                    // the ghost has to show the line that will really be
                    // put down (Sean, 2026-09-21).
                    connectPreview = (start, Self.dragEnd(doc(value.location), from: start))
                case .placing(let start):
                    let end = placing?.end(doc(value.location), from: start, modifiers: NSEvent.modifierFlags)
                        ?? doc(value.location)
                    // No ghost of a box landing on the node a click is
                    // about to pick up (`CanvasPlacement.release`).
                    let puts = placing?.release(from: start, to: end, clicks: 1,
                                                in: drawing, size: size) == .put
                    placePreview = puts ? (start, end) : nil
                default:
                    break
                }
            }
            .onEnded { value in
                switch interaction {
                case .drawing:
                    if let finished = current { drawing.items.append(.stroke(finished)) }
                    current = nil
                case .connecting(let start, let fromNode):
                    connectPreview = nil
                    let end = Self.dragEnd(doc(value.location), from: start)
                    let hit = drawing.attachable(at: end, in: size)
                    let toNode = hit == fromNode ? nil : hit
                    // A click is not an arrow; a drag is, and so is a click
                    // that started on one node and ended on another.
                    if CanvasGeometry.distance(start, end) >= 8 || toNode != nil {
                        let connector = ConnectorItem(start: Self.normalise(start, in: size),
                                                      end: Self.normalise(end, in: size),
                                                      startNode: fromNode, endNode: toNode,
                                                      colorHex: color.hexString,
                                                      lineWidth: min(max(width, 1.5), 6))
                        onBeginChange?()
                        drawing.items.append(.connector(connector))
                        drawing.reconnect(in: size)
                        selection = [connector.id]
                        styling = connector.id
                        styledOnce = false
                    }
                case .moving:
                    // A double click on a node is how it gets its label.
                    if NSApp.currentEvent?.clickCount == 2,
                       abs(value.translation.width) < 3, abs(value.translation.height) < 3,
                       selection.count == 1, let id = selection.first, let item = drawing[id: id],
                       case .shape(let shape) = item, shape.kind.isNode {
                        beginLabel(id)
                    }
                case .placing(let start):
                    let modifiers = NSEvent.modifierFlags
                    let end = placing?.end(doc(value.location), from: start, modifiers: modifiers)
                        ?? doc(value.location)
                    // A click on a node is the node's while a shape stays
                    // armed: picked, and labelled on the second click.
                    switch placing?.release(from: start, to: end, clicks: NSApp.currentEvent?.clickCount ?? 1,
                                            in: drawing, size: size) ?? .put {
                    case .put:
                        place(from: start, to: end, in: size, modifiers: modifiers)
                    case .pick(let ids):
                        placePreview = nil
                        selection = ids
                    case .label(let id):
                        placePreview = nil
                        beginLabel(id)
                    }
                case .marquee(let start, let additive):
                    let rect = CanvasGeometry.rect(from: start, to: doc(value.location))
                    selection = Self.marqueePicked(rect, in: drawing, size: size,
                                                   adding: additive ? selection : nil)
                    marquee = nil
                default:
                    break
                }
                interaction = nil
                snapshot = [:]
            }
    }

    private func begin(at point: CGPoint, in size: CGSize) {
        // Something is armed: this drag is where it goes. And it is the
        // way out of a label being typed and an arrow's style bar, as any
        // press on the layer is: a shape stays armed now, so the next box
        // is drawn straight after the last one was labelled.
        if placing != nil {
            styling = nil
            editingLabel = nil
            interaction = .placing(from: point)
            return
        }
        // ⌥ from a node draws a connector without the arrow tool being on
        // (Sean, 2026-09-19: "flow chart lines can be drawn by holding
        // option"). It has to start ON a node, so it never steals a stroke.
        if NSEvent.modifierFlags.contains(.option),
           let node = drawing.attachable(at: point, in: size) {
            interaction = .connecting(from: point, node: node)
            connectPreview = (point, point)
            return
        }
        // What the mode makes of this press — and ⌘ is the selector in
        // BOTH of them, which is what the third mode used to be
        // (`CanvasMode.press`). ⌥ from a node draws its line above
        // whatever the answer here is: a modifier held down is asked for
        // by hand, and that is what overrides a mode.
        let flags = NSEvent.modifierFlags
        let press = mode.press(with: flags)
        if press == .draw { interaction = .drawing; return }
        if press == .objects, connectActive {
            interaction = .connecting(from: point, node: drawing.attachable(at: point, in: size))
            connectPreview = (point, point)
            return
        }
        // A click anywhere but the crop's own handles is the way out of it —
        // and out of an arrow's style bar, and a label being typed.
        if cropping != nil { cancelCrop() }
        styling = nil
        editingLabel = nil

        // ⇧ adds to what is already picked, whether the rectangle came
        // from ⌘ or a bare click did.
        let additive = flags.contains(.shift)
        if press == .marquee {
            if !additive { selection = [] }
            interaction = .marquee(start: point, additive: additive)
            marquee = CGRect(origin: point, size: .zero)
            return
        }

        guard let index = drawing.index(at: point, in: size) else {
            selection = []
            interaction = .idle
            return
        }
        let id = drawing.items[index].id
        if additive {
            selection.formUnion(CanvasGroups.whole([id], in: drawing.items))
        } else if !selection.contains(id) {
            selection = CanvasGroups.whole([id], in: drawing.items)
        }
        beginManipulation(in: size)
        interaction = .moving
    }

    /// THE TABLET'S MARQUEE — its nib dragged with a side switch held — let
    /// go over the notes: the end of a ⌘-drag, by the same rule — what it touches, whole groups, ⇧ to add —
    /// and the same way out of a crop, a style bar and a label as a press
    /// on the layer takes. So ⌫ and the handles act on what it picked, as
    /// they do on a ⌘-drag's.
    private func pick(byTablet rect: CGRect) {
        if cropping != nil { cancelCrop() }
        styling = nil
        editingLabel = nil
        let additive = NSEvent.modifierFlags.contains(.shift)
        selection = Self.marqueePicked(rect, in: drawing, size: paneSize, adding: additive ? selection : nil)
    }

    private func handleDrag(kind: HandleKind, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if interaction == nil {
                    if selection.isEmpty, let hovered { selection = [hovered] }
                    beginManipulation(in: size)
                    startAngle = CanvasEdit.angle(of: doc(value.startLocation), about: pivot)
                    interaction = .handle
                }
                guard interaction == .handle else { return }
                switch kind {
                case .rotate:
                    var delta = CanvasEdit.angle(of: doc(value.location), about: pivot) - startAngle
                    if NSEvent.modifierFlags.contains(.shift) {
                        let step = Double.pi / 12
                        delta = (delta / step).rounded() * step
                    }
                    apply(rotate: delta, in: size)
                case .scale:
                    apply(scale: CanvasEdit.factor(from: doc(value.startLocation), to: doc(value.location),
                                                   about: pivot),
                          in: size)
                case .move:
                    apply(translate: CGVector(dx: value.translation.width, dy: value.translation.height),
                          in: size)
                }
            }
            .onEnded { _ in
                interaction = nil
                snapshot = [:]
            }
    }

    /// Freeze what the selection looked like before the gesture: every frame
    /// works from this, so a drag that wanders back where it started leaves
    /// the objects exactly where they were.
    private func beginManipulation(in size: CGSize) {
        let box = drawing.bounds(of: selection, in: size)
        pivot = box.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
        snapshot = Dictionary(uniqueKeysWithValues: drawing.items
            .filter { selection.contains($0.id) }
            .map { ($0.id, $0.transform) })
        onBeginChange?()
    }

    private func apply(translate: CGVector = .zero, scale: Double = 1, rotate: Double = 0, in size: CGSize) {
        for index in drawing.items.indices {
            let item = drawing.items[index]
            guard let original = snapshot[item.id] else { continue }
            drawing.items[index].transform = CanvasEdit.transform(
                item, from: original, translate: translate, scale: scale, rotate: rotate,
                about: pivot, in: size)
        }
        // Attached arrows follow whatever moved.
        drawing.reconnect(in: size)
    }

    private func deleteSelection() {
        delete(handleIDs)
    }

    /// What ⌃G and the button would do next, so the button can say which.
    private var groupingToggle: CanvasGroups.Toggle {
        CanvasGroups.toggle(handleIDs, in: drawing.items)
    }

    /// ⌃G. True when the layer took the key — a toggle with nothing to do
    /// hands it on rather than swallowing it, because a monitor that eats
    /// a key it did nothing with is how typing dies (AGENTS.md).
    @discardableResult
    private func toggleGrouping() -> Bool {
        let picked = handleIDs
        guard let items = CanvasGroups.toggled(picked, in: drawing.items) else { return false }
        onBeginChange?()
        drawing.items = items
        // Grouping widens what is held to every member, so the handles go
        // round the whole thing at once rather than after the next click.
        selection = CanvasGroups.whole(picked, in: items)
        return true
    }

    private func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        onBeginChange?()
        drawing = drawing.removing(ids)
        selection = []
        hovered = nil
        cropping = nil
    }

    // MARK: - Keys

    /// The layer has no keyboard focus of its own — the text view keeps it —
    /// so the keys it answers are watched: ⌫ takes the selection (Sean,
    /// 2026-09-18: "delete key should delete most recently selected item"),
    /// ↩ and esc finish or drop a crop, and ⌘V puts a picture on the layer
    /// when no text view is there to take it.
    ///
    /// Called again whenever `keyInputs` changes, and each call puts the
    /// monitor up afresh: the closure holds a COPY of this view, so
    /// everything plain it reads is as it was when the monitor went up.
    private func watchKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } else { Self.keyWatchers += 1 }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKey(event) ? nil : event
        }
    }

    /// EVERYTHING PLAIN THAT `handleKey` READS — not `@State`, which the
    /// copy reads through to the live value, not the binding, not a
    /// closure — and so what the key monitor is put up again for. A copy of
    /// the view made when the layer appeared answered Esc for the mode it
    /// had then, and the layer does not appear again when the mode changes:
    /// a note opened in cursor mode, the pen then picked up, and Esc read
    /// "no pen" and left it up (`CanvasKeyTests`). A new input read there
    /// goes in here too.
    private struct KeyInputs: Equatable {
        let mode: AppState.CanvasMode
        let placing: CanvasPlacement?
        let connectActive: Bool
    }

    private var keyInputs: KeyInputs { KeyInputs(mode: mode, placing: placing, connectActive: connectActive) }

    private func unwatchKeys() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
        Self.keyWatchers -= 1
    }

    /// How many layers are watching keys. While one is, the tablet page's
    /// box is a step in ITS Esc chain; the page's own monitor answers only
    /// when there is none (`TabletBox.paneAnswersEscape`).
    static private(set) var keyWatchers = 0

    /// True when the layer took the key.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
            DebugLog.write("keyDown ⌘V seen: flags=\(flags.rawValue) editingLabel=\(editingLabel != nil) styling=\(styling != nil) cropping=\(cropping != nil)")
        }
        // A label being typed gets every key but esc, which ends it.
        if editingLabel != nil {
            if event.keyCode == 53 { editingLabel = nil; return true }
            return false
        }
        if styling != nil, event.keyCode == 53 { styling = nil; return true }
        // esc puts the armed shape away again.
        if placing != nil, event.keyCode == 53 { onDisarm?(); return true }
        if cropping != nil, flags.isSubset(of: [.function, .numericPad]) {
            switch event.keyCode {
            case 36, 76: confirmCrop(); return true   // ↩ and enter
            case 53: cancelCrop(); return true         // esc
            default: break
            }
        }
        // The tablet page's box next, and BEFORE the pen: the box is a
        // thing in hand, the pen a mode. ONE CHAIN, so the order is chosen
        // here — two key monitors each taking Esc for itself took it in the
        // order they happened to be added, which every rebuild of the panes
        // changes.
        if event.keyCode == 53, onEscapeBox?(event) == true { return true }
        // Esc puts the pen down (Sean, 2026-10-02: "esc should exit pen
        // mode") — after a label, a style bar, an armed shape, a crop and
        // the page's box have had it, since each of those is the nearer
        // thing to call off.
        if penActive, event.keyCode == 53, flags.isSubset(of: [.function, .numericPad]),
           onEscapePen?() == true {
            return true
        }
        // ⌘Z belongs to the drawing while the pen is up, while something on
        // the layer is picked, or while a shape is waiting to be put down —
        // the three times the last thing done was done HERE (Sean,
        // 2026-09-19: "add undo when drawing"). Any other time, and whenever
        // the drawing has nothing left to undo, it goes on to the text.
        // And never while the tablet's page was written on last: this
        // monitor sees ⌘Z BEFORE the Edit menu's key equivalent does, so
        // the menu's "the page first" is asked here too, or ⌘Z after a
        // stroke on the tablet undid whatever was picked on the layer.
        if event.charactersIgnoringModifiers?.lowercased() == "z",
           Self.takesUndo(layerOwns: canvasOwnsUndo, pageOwns: pageOwnsUndo()) {
            if flags == .command, onUndo?() == true { return true }
            if flags == [.command, .shift], onRedo?() == true { return true }
        }
        // ⌃G holds what is picked together, or takes it apart — one key,
        // both ways (Sean, 2026-09-20: "toggle grouping with the button on
        // the screen or ctrl+g"). ⌘G is the text's Find Again and is not
        // ours to take.
        if flags == .control, event.charactersIgnoringModifiers?.lowercased() == "g" {
            return toggleGrouping()
        }
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            // A text view of ours pastes pictures itself; a field editor or
            // no text at all would let the picture drop on the floor.
            let responder = NSApp.keyWindow?.firstResponder
            if responder is PasteAwareTextView {
                DebugLog.write("⌘V: left to the text view (\(type(of: responder!)))")
                return false
            }
            let taken = onPasteImage?(NSPasteboard.general) ?? false
            DebugLog.write("⌘V: on the layer, first responder \(responder.map { String(describing: type(of: $0)) } ?? "none"), handler=\(onPasteImage == nil ? "nil" : "set") taken=\(taken)")
            return taken
        }
        // Only an explicit selection — not whatever the pointer happens to be
        // over — and only ⌫ or ⌦ on their own.
        if !penActive, !selection.isEmpty, flags.isSubset(of: [.function]),
           event.keyCode == 51 || event.keyCode == 117 {
            delete(selection)
            return true
        }
        return false
    }

    // MARK: - Pointer

    /// The armed object, where the drag put it — and whether the tool is
    /// handed back afterwards.
    ///
    /// NOTHING PUT DOWN LEAVES THE TOOL ARMED. A press that never moved is
    /// no line at all (`CanvasPlacement.connector`), and disarming there
    /// sent the pointer back to the palette for a gesture that produced
    /// nothing — the comment there had said so since it was written while
    /// the `defer` disarmed on every path, this one included.
    /// SOMETHING PUT DOWN leaves it armed too when it is a node or a line,
    /// whatever is held (Sean, 2026-10-02: "after drawing a rectangle dont
    /// exit rectangle mode.."), and when it is a mark put down with ⌘ held,
    /// so a row of ticks is one trip to the palette (Sean, 2026-09-21:
    /// "when placing a marker, if i hold cmd, stay in adding that marker
    /// mode") — `CanvasPlacement.staysArmed`. What went down is the
    /// selection, so ⌫ and ⌘Z take it back without disarming. Escape is
    /// the way out of all of it, as it always was.
    private func place(from: CGPoint, to: CGPoint, in size: CGSize,
                       modifiers: NSEvent.ModifierFlags) {
        placePreview = nil
        guard let placing,
              let item = placing.item(from: from, to: to, in: size,
                                      colorHex: color.hexString, lineWidth: width)
        else { return }
        onBeginChange?()
        drawing.items.append(item)
        selection = [item.id]
        // A text box is put down to be typed in.
        if case .shape(let shape) = item, shape.kind == .text { beginLabel(item.id) }
        if !placing.staysArmed(modifiers) { onDisarm?() }
    }

    /// Where a connector's far end is, ⇧ taken into account. The arrow tool
    /// and an ⌥-drag off a node both build their line by hand rather than
    /// through `CanvasPlacement`, and all three have to hold the same axis
    /// or the key means one thing on one of them.
    static func dragEnd(_ to: CGPoint, from: CGPoint,
                        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) -> CGPoint {
        CanvasGeometry.onAxis(to, from: from, locked: modifiers.contains(.shift))
    }

    /// WHAT A MARQUEE PICKS, wherever it was dragged — ⌘ under the pen, ⌘
    /// over the words, the tablet's side switch over the notes: everything
    /// it touches (`Drawing.ids(touching:)`, which skips a hidden picture),
    /// whole groups (`CanvasGroups.whole`), added to `held` when ⇧ is down.
    /// `rect` in the document's points.
    nonisolated static func marqueePicked(_ rect: CGRect, in drawing: Drawing, size: CGSize,
                                          adding held: Set<UUID>?) -> Set<UUID> {
        let touched = CanvasGroups.whole(drawing.ids(touching: rect, in: size), in: drawing.items)
        return held.map { $0.union(touched) } ?? touched
    }

    /// Whether the layer's key monitor takes ⌘Z / ⇧⌘Z for itself: while it
    /// owns undo, and the tablet's page does not.
    nonisolated static func takesUndo(layerOwns: Bool, pageOwns: Bool) -> Bool { layerOwns && !pageOwns }

    /// Whether ⌘Z is the layer's to take.
    private var canvasOwnsUndo: Bool {
        penActive || !selection.isEmpty || placing != nil || connectActive
    }

    private func hover(_ phase: HoverPhase, in size: CGSize) {
        switch phase {
        case .active(let point):
            commandDown = NSEvent.modifierFlags.contains(.command)
            // The pencil is SET on every move, not registered once: the text
            // view's I-beam and the window's arrow both come back through
            // cursorUpdate events, which fire on entering a rect — so a cursor
            // set here outlives them until the next entry, and the next move
            // sets it again (Sean, 2026-09-18: "still see a normal cursor").
            if penActive { DrawingCursors.pencil.set() }
            // Only the cursor mode hovers. The other two have the whole
            // pane, so nothing is "under the pointer" to pick up, and
            // handles drawn round a hovered object would promise a drag
            // that starts a marquee instead.
            guard mode == .cursor else { hovered = nil; return }
            hovered = drawing.index(at: doc(point), in: size).map { drawing.items[$0].id }
        case .ended:
            // Leaving the ink for a handle beside it must not take the handle
            // away before it can be grabbed.
            let leaving = hovered
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if hoveredHandles.isEmpty, hovered == leaving { hovered = nil }
            }
        }
    }

    /// The layer's own cursor, and nil for "the notebook's": with nil the
    /// `CursorLayer` is not mounted at all (see `body`).
    private var cursor: NSCursor? {
        if placing != nil { return .crosshair }
        if penActive { return DrawingCursors.pencil }
        if connectActive { return .crosshair }
        if interaction == .moving || (interaction == .handle && hoveredHandles.contains("move")) {
            return .closedHand
        }
        // The crosshair wherever a ⌘-drag would pull a rectangle. Not
        // under the pen, though it pulls one there too: the pencil is
        // set by the text view as well as by the layer (see AGENTS), and
        // two answers to one pointer is the flicker that cost seven
        // rounds. The pen stays a pencil and the drag still selects.
        if commandDown, NSEvent.modifierFlags.contains(.command), !drawing.isEmpty { return .crosshair }
        if hovered != nil || !hoveredHandles.isEmpty { return .openHand }
        return nil
    }

    /// ⌘ has to be watched, not asked for: the marquee can start anywhere, so
    /// the layer has to be ready to take a click over plain text the moment
    /// the key goes down — and go back to ignoring them when it comes up.
    private func watchModifiers() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let down = event.modifierFlags.contains(.command)
            if down != commandDown { commandDown = down }
            return event
        }
    }

    private func unwatchModifiers() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
    }

    private func loadImages() {
        guard let mediaDirectory else { return }
        var cache = images
        for image in drawing.images where cache[image.file] == nil {
            if let loaded = DrawingStore.loadImage(image.file, in: mediaDirectory) {
                cache[image.file] = Image(nsImage: loaded)
            }
        }
        if cache.count != images.count { images = cache }
    }

    // MARK: - Geometry

    /// A DOCUMENT point as pane fractions: x held to the pane's width, y
    /// held only at the document's top. The layer scrolls with the text, so
    /// a stroke a screen and a half down a note is at y 1.5 — the old clamp
    /// to 1, from before the layer scrolled, flattened everything drawn
    /// below the first screen onto its bottom edge.
    static func normalise(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: min(max(point.x / size.width, 0), 1), y: max(point.y / size.height, 0))
    }
}

/// What the layer will take a click on: the objects themselves, so a click
/// between them reaches the text — or everything, while the pen is up or ⌘ is
/// held down for a marquee.
struct CanvasHitShape: Shape {
    var items: [CanvasItem]
    var everything: Bool
    /// The scroll offset: the objects are in the document, the shape is on
    /// the pane.
    var offset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        if everything { return Path(rect) }
        return objects(in: rect).applying(CGAffineTransform(translationX: 0, y: -offset))
    }

    private func objects(in rect: CGRect) -> Path {
        var path = Path()
        let size = rect.size
        for item in items {
            let outline = item.outline(in: size)
            guard let first = outline.first else { continue }
            switch item {
            case .image, .shape:
                var quad = Path()
                quad.move(to: first)
                for point in outline.dropFirst() { quad.addLine(to: point) }
                quad.closeSubpath()
                path.addPath(quad)
            case .connector(let connector):
                var line = Path()
                line.move(to: first)
                for point in outline.dropFirst() { line.addLine(to: point) }
                path.addPath(line.strokedPath(StrokeStyle(lineWidth: max(connector.lineWidth, 12), lineCap: .round)))
            case .stroke(let stroke):
                if outline.count == 1 {
                    path.addEllipse(in: CGRect(x: first.x - 7, y: first.y - 7, width: 14, height: 14))
                } else {
                    var line = Path()
                    line.move(to: first)
                    for point in outline.dropFirst() { line.addLine(to: point) }
                    let reach = max(stroke.reach * 2 * item.transform.scale, 14)
                    path.addPath(line.strokedPath(StrokeStyle(lineWidth: reach, lineCap: .round, lineJoin: .round)))
                }
            }
        }
        return path
    }
}

/// The bar that comes up once an arrow is drawn (Sean, 2026-09-18, "similar
/// to draw.io"): a head at either end, or none, and the line between.
private struct ConnectorStyleBar: View {
    @Binding var connector: ConnectorItem
    let done: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Start", selection: $connector.startHead) {
                Text("None").tag(ConnectorItem.Head.none)
                Text("◀").tag(ConnectorItem.Head.arrow)
            }
            .help("The head at the start")
            Picker("Line", selection: $connector.line) {
                ForEach(ConnectorItem.LineStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .help("The line")
            Picker("End", selection: $connector.endHead) {
                Text("None").tag(ConnectorItem.Head.none)
                Text("▶").tag(ConnectorItem.Head.arrow)
            }
            .help("The head at the end")
            Button(action: done) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Done (esc)")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4, y: 2)
        .fixedSize()
    }
}
