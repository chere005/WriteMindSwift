import CoreGraphics
import Foundation

/// THE PEN'S ERASER, as geometry (Sean, 2026-10-03: "press and hold to make
/// it an eraser that deletes entire strokes"): the path the nib took, a
/// segment at a time, against the polyline of a stroke. A stroke it comes
/// within `radius` of goes whole — never a piece of one — and the same rule
/// serves the page (page fractions), the floating layer and a drawing cell
/// (document points / a cell's own).
enum StrokeEraser {
    /// How near the erasing nib has to come, in page fractions: about two
    /// millimetres on the small One by Wacom.
    static let pageRadius: CGFloat = 0.014
    /// And over the notes, in the document's points.
    static let noteRadius: CGFloat = 7

    /// The least distance between segment a–b and segment c–d: nothing when
    /// they cross.
    static func distance(from a: CGPoint, to b: CGPoint, toSegmentFrom c: CGPoint, to d: CGPoint) -> CGFloat {
        if CanvasGeometry.cross(a, b, c, d) { return 0 }
        return min(CanvasGeometry.distance(a, from: c, to: d), CanvasGeometry.distance(b, from: c, to: d),
                   CanvasGeometry.distance(c, from: a, to: b), CanvasGeometry.distance(d, from: a, to: b))
    }

    /// Whether the nib's path from `a` to `b` (one point when they are the
    /// same) comes within `radius` of the polyline `points` — one point alone
    /// is a dot.
    static func touches(_ points: [CGPoint], from a: CGPoint, to b: CGPoint, radius: CGFloat) -> Bool {
        guard let first = points.first else { return false }
        if points.count == 1 { return CanvasGeometry.distance(first, from: a, to: b) <= radius }
        // The box first: most strokes are nowhere near.
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        if max(a.x, b.x) < minX - radius || min(a.x, b.x) > maxX + radius
            || max(a.y, b.y) < minY - radius || min(a.y, b.y) > maxY + radius { return false }
        for index in 0..<(points.count - 1)
        where distance(from: a, to: b, toSegmentFrom: points[index], to: points[index + 1]) <= radius {
            return true
        }
        return false
    }
}

/// What the eraser did over the notes, in document points — `NotebookScribe`
/// sends it, the drawing layer deletes by it (`DrawingCanvas.erase`).
enum NotebookErase: Equatable {
    /// The nib went from `from` to `to` (one point when they are the same).
    case path(from: CGPoint, to: CGPoint)
    /// The nib came up: the erasure is done, and the next is a new step.
    case end
}
