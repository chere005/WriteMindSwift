import SwiftUI

/// The SHAPE of what the pen and the arrow tool leave behind, with no
/// context to draw it into.
///
/// The layer on screen is a SwiftUI `Canvas` and paper is a `CGContext`;
/// they can only be the same lines if the lines themselves live in one
/// place. Everything geometric about a stroke and a connector is here, so
/// `DrawingCanvas` and `DrawingInk` differ only in what they hand the path
/// to.
///
/// `DrawingCanvas.draw(_ stroke:…)` and `draw(_ connector:…)` each carried
/// their own copy of this until 2026-09-19; they are now a call apiece, so
/// a change to how a stroke is smoothed lands on the screen and on paper
/// at the same time.
enum InkPaths {
    /// A stroke: the smoothed line through its samples, or a dot when the
    /// pen went down and did not move. `filled` says which of the two it
    /// is — a dot is filled, a line is stroked.
    ///
    /// The curve is quadratics through the MIDPOINTS of the samples, which
    /// is what takes the corners off a raw mouse trail.
    ///
    /// A stroke with a TOOL (or pressures) is ink: `InkOutline`'s polygon
    /// round the samples, widened by the pressure at each one, always
    /// filled — see `ink(for:tool:points:)`. A stroke with neither is the
    /// legacy line, and the code below that branch is the code that drew
    /// every stroke before 2026-10-02, untouched: `InkPathsTests` pins its
    /// output, so nothing already in Sean's notes can quietly restyle.
    static func path(for stroke: Stroke, points: [CGPoint]) -> (path: Path, filled: Bool) {
        guard let first = points.first else { return (Path(), false) }
        if let tool = stroke.inkTool {
            let path = inkCache.path(for: stroke, tool: tool, points: points) {
                ink(for: stroke, tool: tool, points: points)
            }
            return (path, true)
        }
        if points.count == 1 {
            let dot = CGRect(x: first.x - stroke.width / 2, y: first.y - stroke.width / 2,
                             width: stroke.width, height: stroke.width)
            return (Path(ellipseIn: dot), true)
        }
        var path = Path()
        path.move(to: first)
        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for index in 1..<(points.count - 1) {
                let mid = CGPoint(x: (points[index].x + points[index + 1].x) / 2,
                                  y: (points[index].y + points[index + 1].y) / 2)
                path.addQuadCurve(to: mid, control: points[index])
            }
            path.addLine(to: points[points.count - 1])
        }
        return (path, false)
    }

    /// Ink: the samples (view points, before the transform — the painter's
    /// matrix scales and turns the outline with everything else) paired
    /// with their pressures, outlined by the stroke's tool
    /// (`InkTool.outline`, which is also where a tap becomes a round dot)
    /// and smoothed. A pressure missing at the end of a short array is
    /// "none reported" rather than a crash — the arrays are kept in
    /// lockstep, and this is the belt to those braces.
    static func ink(for stroke: Stroke, tool: InkTool, points: [CGPoint]) -> Path {
        let pressures = stroke.pressures
        let samples = points.enumerated().map { index, point in
            InkOutline.Sample(point, pressure: pressures.flatMap { index < $0.count ? $0[index] : nil })
        }
        return InkOutline.path(tool.outline(samples, width: stroke.width, simulated: pressures == nil))
    }

    /// Every ink outline the painters have asked for, by stroke.
    static let inkCache = InkCache()

    /// A connector: the line, with each end that carries a head pulled back
    /// along its own last segment so the head's TIP is the point, and the
    /// heads themselves as filled triangles.
    static func paths(for connector: ConnectorItem, points: [CGPoint]) -> (line: Path, heads: [Path]) {
        guard points.count >= 2 else { return (Path(), []) }
        let head = ConnectorItem.headLength(for: connector.lineWidth)
        var drawn = points
        if connector.startHead != .none {
            drawn[0] = ConnectorItem.shortened(points[0], from: points[1], by: head * 0.8)
        }
        let last = drawn.count - 1
        if connector.endHead != .none {
            drawn[last] = ConnectorItem.shortened(points[last], from: points[last - 1], by: head * 0.8)
        }
        var line = Path()
        line.move(to: drawn[0])
        for point in drawn.dropFirst() { line.addLine(to: point) }

        var heads: [Path] = []
        if connector.startHead == .arrow {
            heads.append(ConnectorItem.head(tip: points[0], from: points[1], lineWidth: connector.lineWidth))
        }
        if connector.endHead == .arrow {
            heads.append(ConnectorItem.head(tip: points[last], from: points[last - 1],
                                            lineWidth: connector.lineWidth))
        }
        return (line, heads)
    }
}

/// Ink, outlined once and remembered.
///
/// MEASURED FIRST (2026-10-02): a page of 300 strokes of 120 samples takes
/// 5 ms to outline in a Release build and 26–39 ms in Debug, and the layer
/// redraws EVERY stroke on every pen event — about 120 a second, 8 ms
/// apart, once coalescing is off — and on every hover. So finished ink is
/// kept; a legacy line costs next to nothing to rebuild and is not.
///
/// One entry per stroke id, replaced when the samples are not the ones it
/// was made from: the live stroke grows by a point an event and holds one
/// slot, not hundreds. "The samples" is a fingerprint, not the points —
/// how many, the first and the last (in VIEW points, so a resized pane or
/// a page of a different width is a new outline), the width, the tool and
/// how many pressures. That is enough because a stroke's points are never
/// edited in place in this app, only appended to while it is drawn; a
/// gesture that one day rewrites points under the same id (a crop, a
/// smoothing pass) must give the stroke a new id or widen this.
final class InkCache {
    struct Fingerprint: Equatable {
        var count: Int
        var first: CGPoint
        var last: CGPoint
        var width: Double
        var tool: InkTool
        var pressures: Int?
    }

    /// Past this many strokes the cache is dropped and refilled as the
    /// painters ask — a bound, not an eviction policy. The layer paints
    /// every stroke of the note each time, so the bound has to sit above a
    /// whole note of handwriting (a letter is a stroke or three), or a
    /// long one would empty it on every frame; a handwriting outline is a
    /// few kilobytes, so even full it is tens of megabytes, not hundreds.
    static let limit = 8192

    private var entries: [UUID: (fingerprint: Fingerprint, path: Path)] = [:]
    /// The screen paints on the main thread; an export may not.
    private let lock = NSLock()

    var count: Int { lock.withLock { entries.count } }

    func path(for stroke: Stroke, tool: InkTool, points: [CGPoint], make: () -> Path) -> Path {
        guard let first = points.first, let last = points.last else { return make() }
        let fingerprint = Fingerprint(count: points.count, first: first, last: last, width: stroke.width,
                                      tool: tool, pressures: stroke.pressures?.count)
        if let hit = lock.withLock({ entries[stroke.id] }), hit.fingerprint == fingerprint { return hit.path }
        let path = make()
        lock.withLock {
            if entries.count >= Self.limit { entries.removeAll(keepingCapacity: true) }
            entries[stroke.id] = (fingerprint, path)
        }
        return path
    }
}
