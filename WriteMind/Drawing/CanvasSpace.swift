import CoreGraphics
import Foundation

/// Which drawing a gesture on the layer works on: the floating one over the
/// note, or one drawing cell's.
enum CanvasSpaceID: Hashable {
    case floating
    case cell(UUID)
}

/// WHERE A DRAWING CELL IS ON THE PANE ON SCREEN, as that pane laid it out —
/// the source pane off its text layout (`FoldingLayoutManager.cellRect`),
/// the rendered page off its stack. What the drawing layer draws into and
/// the tablet routes a stroke by. A folded cell has none.
struct CellFrame: Equatable {
    var id: UUID
    /// Its line in the note.
    var line: NSRange
    /// Where it is painted, its shown size, in document points.
    var rect: CGRect
    /// Document points per cell point: s, under 1 in a column narrower
    /// than the one it was drawn in (`DrawingCells.shown`).
    var scale: CGFloat
    /// W — what its objects are measured against, in cell points.
    var width: CGFloat
    /// Whether anything may be drawn in it: a read-only cell, or one still
    /// downloading, takes no strokes and no placements.
    var writable: Bool

    /// Whether frames have changed enough to tell anybody: a cell came,
    /// went or changed what it is, or one moved by more than half a point
    /// — the tolerance `CellSeams.moved` holds the seams to. A pane
    /// measures on every keystroke, and a frame told every time would be
    /// a redraw of the layer every time.
    static func moved(_ old: [CellFrame], _ new: [CellFrame]) -> Bool {
        guard old.count == new.count else { return true }
        return zip(old, new).contains { a, b in
            a.id != b.id || a.line != b.line || a.writable != b.writable || a.width != b.width
                || abs(a.scale - b.scale) > 0.001
                || abs(a.rect.minX - b.rect.minX) > 0.5 || abs(a.rect.minY - b.rect.minY) > 0.5
                || abs(a.rect.width - b.rect.width) > 0.5 || abs(a.rect.height - b.rect.height) > 0.5
        }
    }
}

/// ONE CANVAS, SEVERAL SPACES. The floating layer measures its objects
/// against the pane; a drawing cell measures its own against (W, W) and is
/// shown s times that size at its place on the page. Every gesture the
/// layer has — a stroke, a click, the marquee, the handles, ⌫, ⌃G — works
/// on one space's drawing at that space's size, and these are the only
/// conversions between a space and the document (`DrawingCanvas`).
struct CanvasSpace: Equatable {
    var id: CanvasSpaceID
    /// The document point of the space's (0, 0).
    var origin: CGPoint
    /// What its objects are measured against: the pane, or (W, W).
    var size: CGSize
    /// Document points per space point: 1, or s.
    var scale: CGFloat
    /// What it is drawn inside, in document points: a cell's rect, or
    /// nothing for the floating layer.
    var clip: CGRect?

    static func floating(pane: CGSize) -> CanvasSpace {
        CanvasSpace(id: .floating, origin: .zero, size: pane, scale: 1, clip: nil)
    }

    static func cell(_ frame: CellFrame) -> CanvasSpace {
        CanvasSpace(id: .cell(frame.id), origin: frame.rect.origin,
                    size: CGSize(width: frame.width, height: frame.width),
                    scale: max(frame.scale, 0.0001), clip: frame.rect)
    }

    func toDocument(_ point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }

    func fromDocument(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }

    func toDocument(_ rect: CGRect) -> CGRect {
        CGRect(origin: toDocument(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }

    /// AN OBJECT FROM ONE SPACE IN ANOTHER, where it was in the document:
    /// every normalised field of every kind — points, centre, width, a
    /// connector's ends, bends and dragged segments, the transform's move —
    /// taken one for one, and every width in points (a stroke's, a shape's
    /// line, a connector's) times `from.scale ÷ to.scale`, so it is the
    /// same size on screen. Ids, groups, pressures and tools are kept as
    /// they are: a point moves with its pressure, the lockstep rule's way
    /// (AGENTS.md — beside `TabletPage.turned` and
    /// `TabletSelection.noteStrokes`).
    static func rehome(_ item: CanvasItem, from: CanvasSpace, to: CanvasSpace) -> CanvasItem {
        guard from.size.width > 0, from.size.height > 0, to.size.width > 0, to.size.height > 0,
              from.scale > 0, to.scale > 0 else { return item }
        // A length in `from`'s points is this many of `to`'s.
        let k = Double(from.scale / to.scale)
        func point(_ fraction: CGPoint) -> CGPoint {
            let there = to.fromDocument(from.toDocument(CGPoint(x: fraction.x * from.size.width,
                                                                 y: fraction.y * from.size.height)))
            return CGPoint(x: there.x / to.size.width, y: there.y / to.size.height)
        }
        func across(_ fraction: Double) -> Double { fraction * Double(from.size.width) * k / Double(to.size.width) }
        var transform = item.transform
        transform.dx = transform.dx * Double(from.size.width) * k / Double(to.size.width)
        transform.dy = transform.dy * Double(from.size.height) * k / Double(to.size.height)
        switch item {
        case .stroke(var stroke):
            stroke.points = stroke.points.map(point)
            stroke.width *= k
            stroke.transform = transform
            return .stroke(stroke)
        case .image(var image):
            image.center = point(image.center)
            image.width = across(image.width)
            image.transform = transform
            return .image(image)
        case .shape(var shape):
            shape.center = point(shape.center)
            shape.width = across(shape.width)
            shape.lineWidth *= k
            shape.transform = transform
            return .shape(shape)
        case .connector(var connector):
            connector.start = point(connector.start)
            connector.end = point(connector.end)
            connector.bends = connector.bends.map(point)
            connector.overrides = connector.overrides.map { override in
                // A dragged segment is one coordinate: x for an upright
                // segment, y for a level one.
                var moved = override
                let value = CGFloat(override.value)
                moved.value = override.vertical
                    ? Double(point(CGPoint(x: value, y: 0)).x)
                    : Double(point(CGPoint(x: 0, y: value)).y)
                return moved
            }
            connector.lineWidth *= k
            connector.transform = transform
            return .connector(connector)
        }
    }

    /// WHICH SPACE A PRESS IS IN, by its first point (document points), and
    /// the object under it there. A DRAWING CELL IS STATIC: the only cell a
    /// press can be in is the one ENTERED (`entered`, cell drawing mode),
    /// and inside its frame it is that cell's whatever else is under the
    /// point — a floating object over it included, since in that mode
    /// nothing else on the page reacts — with the cell's own object under
    /// the point or none for its paper. Every other press, over a cell
    /// that was not entered or none at all, is the floating layer's, with
    /// its object under the point if there is one. A read-only cell, and one
    /// still downloading, is no space at all; a folded cell has no frame.
    static func at(_ point: CGPoint, layer: Drawing, pane: CGSize, frames: [CellFrame],
                   cells: [UUID: DrawingCell], entered: UUID? = nil) -> (space: CanvasSpaceID, item: UUID?) {
        if let entered,
           let frame = frames.first(where: { $0.id == entered && $0.writable && $0.rect.contains(point) }) {
            let space = CanvasSpace.cell(frame)
            let drawing = cells[frame.id]?.drawing ?? Drawing()
            let item = drawing.index(at: space.fromDocument(point), in: space.size).map { drawing.items[$0].id }
            return (.cell(frame.id), item)
        }
        if pane.width > 0, pane.height > 0, let index = layer.index(at: point, in: pane) {
            return (.floating, layer.items[index].id)
        }
        return (.floating, nil)
    }
}
