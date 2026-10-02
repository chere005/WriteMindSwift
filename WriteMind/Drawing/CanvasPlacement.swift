import AppKit
import CoreGraphics
import Foundation

/// What the next gesture on the pane puts down — and for a node or a line
/// every one after it, until it is put away (`staysArmed`). Picking a
/// shape or a mark from the palette arms this; the drag that follows says
/// where the thing starts and where it ends (Sean, 2026-09-19: "when
/// selecting a mark when i click i start the mark and drag and release
/// where the mark ends").
///
/// A MARK IS PUT WHERE IT IS CLICKED, and not before (Sean, 2026-09-21:
/// "the checkmark shouldn't be placed until i click where it goes, like an
/// arrow"). It arrives at one line of text's worth of size, because what a
/// tick is for is standing beside a word; a drag still sizes it by hand.
enum CanvasPlacement: Equatable {
    case shape(ShapeItem.Kind)
    case line(start: ConnectorItem.Head, end: ConnectorItem.Head)

    var title: String {
        switch self {
        case .shape(let kind): return kind.title
        case .line(.none, .none): return "Line"
        case .line(.arrow, .arrow): return "Double-headed Arrow"
        case .line: return "Arrow"
        }
    }

    /// A LINE OR AN ARROW HAS A DIRECTION, and ⇧ holds it to an axis
    /// (Sean, 2026-09-21: "if i hold shift, the direction elements become
    /// fixed to horizontal or vertical axes"). A shape has no direction —
    /// a mark is square already and a node is dragged to whatever box it
    /// is wanted in — so the key means nothing over one of those, and
    /// answering "no" here is what keeps it meaning nothing.
    var hasDirection: Bool {
        if case .line = self { return true }
        return false
    }

    /// Where the far end of this gesture really is: on the axis while ⇧ is
    /// held, and only for something that has a direction.
    func end(_ to: CGPoint, from: CGPoint, modifiers: NSEvent.ModifierFlags) -> CGPoint {
        CanvasGeometry.onAxis(to, from: from,
                              locked: hasDirection && modifiers.contains(.shift))
    }

    /// WHAT IS DRAWN STAYS ARMED; WHAT IS STAMPED IS ONE CLICK. Sean,
    /// 2026-10-02: "after drawing a rectangle dont exit rectangle mode..".
    /// A node is dragged corner to corner and a line press to release —
    /// drawn, as a rectangle tool draws anywhere — and a chart is several
    /// of them, so the next drag draws the next one with no key held,
    /// until the tool is put away: Esc, the same tile again, another tool,
    /// a mode, the pen.
    ///
    /// A MARK IS STILL ONE CLICK, and ⌘ held as it goes down keeps it, so
    /// a row of ticks is one trip to the palette (Sean, 2026-09-21: "when
    /// placing a marker, if i hold cmd, stay in adding that marker mode").
    /// Those words ask for ⌘ to KEEP a marker, which is a marker that goes
    /// back without it — and a tick is a stamp beside one word, where a
    /// box is one of a chart's several. It is read at the moment the
    /// thing goes down, not when it was picked, so the choice is made per
    /// mark. The rule follows the KIND, not the palette it was picked
    /// from: the Marks palette's box, circle and triangle are nodes, and
    /// stay.
    ///
    /// ⌘ is the selector everywhere else on this pane, and that is not a
    /// clash: an armed placement takes the press before any mode or
    /// modifier is asked (`DrawingCanvas.begin`), so while a tool is armed
    /// there is no marquee for it to collide with.
    func staysArmed(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        isDrawn || modifiers.contains(.command)
    }

    /// DRAWN rather than stamped: a node, corner to corner, or a line,
    /// press to release. What is drawn stays armed (`staysArmed`), and a
    /// click on a node is then the node's (`release`).
    var isDrawn: Bool {
        switch self {
        case .line: return true
        case .shape(let kind): return kind.isNode
        }
    }

    /// What a release does while this is armed.
    enum Release: Equatable {
        /// The armed thing goes down, from the press to the release.
        case put
        /// The node clicked is picked up — with its group, as any click
        /// picks one up (`CanvasGroups.whole`).
        case pick(Set<UUID>)
        /// The node double-clicked opens its label.
        case label(UUID)
    }

    /// A CLICK ON A NODE IS THE NODE'S while something drawn is armed.
    /// Sean's flow chart is a loop — draw a box, double-click it to give
    /// it its label, draw the next — and a box that stays armed (Sean,
    /// 2026-10-02: "after drawing a rectangle dont exit rectangle
    /// mode..") took both clicks of the double-click: two boxes at their
    /// own size stacked on the one clicked, and no label. So a press
    /// that never moved, landing on a node, picks it up, and the second
    /// click of a double-click opens its label, as the same clicks do
    /// with nothing armed — a node inside a group picks the group and
    /// opens no label there either. Anywhere else a click still puts one
    /// down at its own size; a drag that starts on a node still draws
    /// (a box round a box); and a mark is a stamp, so a tick clicked onto
    /// a box goes down in it.
    func release(from: CGPoint, to: CGPoint, clicks: Int, in drawing: Drawing, size: CGSize) -> Release {
        guard isDrawn, !Self.isDrag(from: from, to: to),
              let index = drawing.index(at: from, in: size),
              case .shape(let node) = drawing.items[index], node.kind.isNode
        else { return .put }
        let picked = CanvasGroups.whole([node.id], in: drawing.items)
        return clicks == 2 && picked == [node.id] ? .label(node.id) : .pick(picked)
    }

    /// THE TWO PALETTES' SHAPES, tile for tile, here and not in their
    /// views so the bar can light the button whose palette holds what is
    /// armed (`AppState.shapesLit`, `marksLit`). The Marks palette shares
    /// the box, the circle and the triangle with the flow chart, and
    /// holds every line.
    static let flowChart: [ShapeItem.Kind] = [.rectangle, .roundedRectangle, .oval, .diamond, .triangle,
                                              .parallelogram]
    static let marks: [ShapeItem.Kind] = [.check, .cross, .question, .star, .rectangle, .oval, .triangle]

    var isOnFlowChart: Bool {
        if case .shape(let kind) = self { return Self.flowChart.contains(kind) }
        return false
    }

    var isOnMarks: Bool {
        switch self {
        case .shape(let kind): return Self.marks.contains(kind)
        case .line: return true
        }
    }

    /// The SF Symbol that stands for it, on the palette and in the footer.
    var symbol: String {
        switch self {
        case .shape(let kind): return kind.symbol
        case .line(.none, .none): return "minus"
        case .line(.arrow, .arrow): return "arrow.left.and.right"
        case .line: return "arrow.right"
        }
    }

    /// What the footer says while this is armed. A pane that takes every
    /// drag needs somewhere on screen that says why — the pen is named
    /// there for the same reason — and a tool that no longer goes back on
    /// its own says how it is put away.
    var footer: String {
        isDrawn ? "\(title): every drag draws one, Esc to stop" : "\(title): click where it goes"
    }

    /// Under this, the drag was a click.
    static let dragThreshold: CGFloat = 4
    /// Nothing smaller than this goes down: a shape two points across is a
    /// slip of the hand, not a shape.
    static let minimumSide: CGFloat = 12

    static func isDrag(from: CGPoint, to: CGPoint) -> Bool {
        max(abs(to.x - from.x), abs(to.y - from.y)) >= dragThreshold
    }

    /// The box a drag puts the shape in. A node takes the rectangle that was
    /// dragged; a mark keeps its square, anchored where the drag began and
    /// growing the way it went, so a check mark is never stretched.
    static func box(from: CGPoint, to: CGPoint, kind: ShapeItem.Kind, in size: CGSize) -> CGRect {
        guard isDrag(from: from, to: to) else {
            // A node is a chart's box and takes a share of the pane; a
            // mark is an annotation and takes a line of the writing.
            let width = kind.isNode ? 0.18 * size.width : ShapeItem.markSide
            return CGRect(x: from.x - width / 2, y: from.y - width * kind.defaultAspect / 2,
                          width: width, height: width * kind.defaultAspect)
        }
        if kind.isNode {
            let box = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                             width: abs(to.x - from.x), height: abs(to.y - from.y))
            return CGRect(x: box.minX, y: box.minY,
                          width: max(box.width, minimumSide), height: max(box.height, minimumSide))
        }
        let side = max(max(abs(to.x - from.x), abs(to.y - from.y)), minimumSide)
        return CGRect(x: to.x >= from.x ? from.x : from.x - side,
                      y: to.y >= from.y ? from.y : from.y - side,
                      width: side, height: side)
    }

    /// The shape a drag makes, in the pane's fractions.
    static func shape(_ kind: ShapeItem.Kind, from: CGPoint, to: CGPoint, in size: CGSize,
                      colorHex: String, lineWidth: Double) -> ShapeItem? {
        guard size.width > 1, size.height > 1 else { return nil }
        let box = self.box(from: from, to: to, kind: kind, in: size)
        // A mark the size of a line of text cannot carry the pen it was
        // drawn with: at eight points a tick in an eighteen-point box is
        // a blob. The BOX is what limits it, so one dragged out big
        // takes the whole pen.
        let stroke = kind.isNode
            ? min(max(lineWidth, 1.5), 4)
            : min(max(lineWidth, 1.5), max(2, Double(box.width) * 0.16))
        return ShapeItem(kind: kind,
                         center: CGPoint(x: box.midX / size.width, y: box.midY / size.height),
                         width: box.width / size.width,
                         aspect: box.height / max(box.width, 1),
                         colorHex: kind.inkHex ?? colorHex, lineWidth: stroke)
    }

    /// The line a drag makes: it starts where the press went down and
    /// ends where it came up (Sean, 2026-09-21: "when drawing an arrow or
    /// line or something, click starts the beginning, release is the end
    /// of the arrow").
    ///
    /// A press that never moved used to put down a short horizontal line
    /// instead, centred on the click. That is a different line from the
    /// one that was asked for, in a different place, and it is the answer
    /// to a question nobody asks — so a press with no drag now puts down
    /// nothing at all and the tool stays armed for the next try.
    static func connector(from: CGPoint, to: CGPoint, in size: CGSize,
                          startHead: ConnectorItem.Head, endHead: ConnectorItem.Head,
                          colorHex: String, lineWidth: Double) -> ConnectorItem? {
        guard size.width > 1, size.height > 1 else { return nil }
        guard isDrag(from: from, to: to) else { return nil }
        let a = from, b = to
        return ConnectorItem(start: CGPoint(x: a.x / size.width, y: a.y / size.height),
                             end: CGPoint(x: b.x / size.width, y: b.y / size.height),
                             startHead: startHead, endHead: endHead,
                             colorHex: colorHex, lineWidth: min(max(lineWidth, 1.5), 6))
    }

    /// The object itself, ready to go on the layer.
    func item(from: CGPoint, to: CGPoint, in size: CGSize, colorHex: String, lineWidth: Double) -> CanvasItem? {
        switch self {
        case .shape(let kind):
            return Self.shape(kind, from: from, to: to, in: size,
                              colorHex: colorHex, lineWidth: lineWidth).map { .shape($0) }
        case .line(let start, let end):
            return Self.connector(from: from, to: to, in: size, startHead: start, endHead: end,
                                  colorHex: colorHex, lineWidth: lineWidth).map { .connector($0) }
        }
    }
}
