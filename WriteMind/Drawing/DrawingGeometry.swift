import CoreGraphics
import Foundation

// Every item is stored normalised to the pane and drawn in view points. The
// transform is applied about the item's own centre in view points, so a
// rotated stroke keeps its shape whatever the pane's aspect ratio is.
extension CanvasItem {
    /// The outline before the transform, in view points: a stroke's own
    /// points, or the four corners of a picture.
    func basePoints(in size: CGSize) -> [CGPoint] {
        switch self {
        case .stroke(let stroke):
            return stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        case .image(let image):
            return Self.corners(center: image.center, width: image.width, aspect: image.aspect, in: size)
        case .shape(let shape):
            // The outline scaled into the box — every polyline of it, so a
            // cross's box still holds both of its strokes.
            return shape.kind.polylines(in: Self.box(center: shape.center, width: shape.width,
                                                      aspect: shape.aspect, in: size)).flatMap { $0 }
        case .connector(let connector):
            // Every corner, not just the ends: a routed line turns right
            // angles, and is drawn, clicked and boxed by the same points.
            if !connector.bends.isEmpty {
                return connector.route.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            }
            return [CGPoint(x: connector.start.x * size.width, y: connector.start.y * size.height),
                    CGPoint(x: connector.end.x * size.width, y: connector.end.y * size.height)]
        }
    }

    /// The box a centred, width-and-aspect item occupies, in view points.
    static func box(center: CGPoint, width: Double, aspect: Double, in size: CGSize) -> CGRect {
        let w = width * size.width
        let h = w * aspect
        return CGRect(x: center.x * size.width - w / 2, y: center.y * size.height - h / 2, width: w, height: h)
    }

    static func corners(center: CGPoint, width: Double, aspect: Double, in size: CGSize) -> [CGPoint] {
        let box = box(center: center, width: width, aspect: aspect, in: size)
        return [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
    }

    /// A picture and a closed shape are hit anywhere inside; a stroke, an
    /// open mark and a connector only on the line.
    var isClosed: Bool {
        switch self {
        case .image: return true
        case .shape(let shape): return shape.kind.isClosed
        case .stroke, .connector: return false
        }
    }

    /// The box the item occupies before the transform. A stroke's ink
    /// reaches out from its samples, so its `reach` is added on every side.
    func baseBounds(in size: CGSize) -> CGRect {
        if case .shape(let shape) = self {
            // The box the shape was drawn into, not the outline's extent — a
            // check mark's handles should hold its box, not hug the tick.
            return Self.box(center: shape.center, width: shape.width, aspect: shape.aspect, in: size)
        }
        // A STROKE'S BOX IS WORKED OUT IN ONE PASS OVER ITS POINTS, with no
        // array made of them: this runs under every hit test, every handle
        // and every redraw of the layer, and for a note full of ink it was
        // two arrays of every point per question (Sean, 2026-10-02: "fix the
        // performance of grouped objects").
        if case .stroke(let stroke) = self {
            guard let first = stroke.points.first else { return .zero }
            var minX = first.x * size.width, maxX = minX
            var minY = first.y * size.height, maxY = minY
            for point in stroke.points.dropFirst() {
                let x = point.x * size.width, y = point.y * size.height
                if x < minX { minX = x } else if x > maxX { maxX = x }
                if y < minY { minY = y } else if y > maxY { maxY = y }
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -stroke.reach, dy: -stroke.reach)
        }
        let points = basePoints(in: size)
        guard let first = points.first else { return .zero }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() { rect = rect.union(CGRect(origin: point, size: .zero)) }
        switch self {
        case .stroke(let stroke):
            // `Stroke.reach`: half the widest the ink can go at the
            // hardest press for a stroke with a tool (0.65 of a nib for
            // the pen), and half the width for a legacy one, as before.
            rect = rect.insetBy(dx: -stroke.reach, dy: -stroke.reach)
        case .connector(let connector):
            let reach = max(connector.lineWidth / 2, ConnectorItem.headLength(for: connector.lineWidth) / 2)
            rect = rect.insetBy(dx: -reach, dy: -reach)
        case .image, .shape:
            break
        }
        return rect
    }

    func baseCenter(in size: CGSize) -> CGPoint {
        let rect = baseBounds(in: size)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// Where the item's centre actually is now.
    func placedCenter(in size: CGSize) -> CGPoint {
        let centre = baseCenter(in: size)
        return CGPoint(x: centre.x + transform.dx * size.width,
                       y: centre.y + transform.dy * size.height)
    }

    /// Rotate and scale about the item's own centre, then translate.
    func matrix(in size: CGSize) -> CGAffineTransform {
        matrix(about: baseCenter(in: size), in: size)
    }

    /// The same, for a centre already worked out — `baseCenter` is a pass
    /// over every point of a stroke, and what asks for the matrix often has
    /// the box in hand.
    func matrix(about centre: CGPoint, in size: CGSize) -> CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(x: centre.x + transform.dx * size.width,
                          y: centre.y + transform.dy * size.height)
            .rotated(by: transform.rotation)
            .scaledBy(x: transform.scale, y: transform.scale)
            .translatedBy(x: -centre.x, y: -centre.y)
    }

    /// The outline where it is now.
    func outline(in size: CGSize) -> [CGPoint] {
        let matrix = matrix(in: size)
        // A stroke's points go from the pane's fractions to where they are
        // now in ONE array, not two.
        if case .stroke(let stroke) = self {
            return stroke.points.map {
                CGPoint(x: $0.x * size.width, y: $0.y * size.height).applying(matrix)
            }
        }
        return basePoints(in: size).map { $0.applying(matrix) }
    }

    /// The four corners of the item's own box where they are now — the box
    /// leans over with the item, which is what the selection outline draws.
    func frameCorners(in size: CGSize) -> [CGPoint] {
        let box = baseBounds(in: size)
        let matrix = matrix(about: CGPoint(x: box.midX, y: box.midY), in: size)
        return [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            .map { $0.applying(matrix) }
    }

    /// Every point of the item, where it is now, lies inside this box, grown
    /// by `slack` — the cheap question a hit test and a marquee ask before
    /// any of the item's own points are visited. One pass, no array of them.
    func envelope(in size: CGSize, slack: CGFloat = 0) -> CGRect {
        bounds(in: size).insetBy(dx: -slack, dy: -slack)
    }

    /// How far past the outline a click still hits: the line's own width.
    private var lineSlack: CGFloat {
        switch self {
        case .shape(let shape): return CGFloat(shape.lineWidth * transform.scale)
        case .connector(let connector): return CGFloat(connector.lineWidth * transform.scale)
        case .stroke(let stroke): return CGFloat(stroke.reach * transform.scale)
        case .image: return 0
        }
    }

    /// The upright box around the item where it is now — what the handles
    /// hang off.
    func bounds(in size: CGSize) -> CGRect {
        let corners = frameCorners(in: size)
        guard let first = corners.first else { return .zero }
        var rect = CGRect(origin: first, size: .zero)
        for corner in corners.dropFirst() { rect = rect.union(CGRect(origin: corner, size: .zero)) }
        return rect
    }

    /// Does a click at this point land on the item? On the ink, not on the box
    /// around it — otherwise one big stroke would swallow every click near it.
    func hitTest(_ point: CGPoint, in size: CGSize) -> Bool {
        // Most items on a pane are nowhere near the pointer: they are put
        // aside by their box, which is a few multiplications, before any of
        // their points are touched.
        guard envelope(in: size, slack: 8 + lineSlack).contains(point) else { return false }
        let outline = outline(in: size)
        guard !outline.isEmpty else { return false }
        switch self {
        case .image:
            return CanvasGeometry.polygon(outline, contains: point)
        case .shape(let shape):
            if shape.kind.isClosed {
                return CanvasGeometry.polygon(outline, contains: point)
                    || Self.near(point, polylines: [outline + [outline[0]]],
                                 reach: max(shape.lineWidth * transform.scale / 2, 6))
            }
            let matrix = matrix(in: size)
            let lines = shape.kind.polylines(in: baseBounds(in: size)).map { $0.map { $0.applying(matrix) } }
            return Self.near(point, polylines: lines, reach: max(shape.lineWidth * transform.scale / 2, 6))
        case .connector(let connector):
            return Self.near(point, polylines: [outline], reach: max(connector.lineWidth * transform.scale / 2, 6))
        case .stroke(let stroke):
            let reach = max(stroke.reach * transform.scale, 6)
            if outline.count == 1 { return CanvasGeometry.distance(point, outline[0]) <= reach }
            return Self.near(point, polylines: [outline], reach: reach)
        }
    }

    private static func near(_ point: CGPoint, polylines: [[CGPoint]], reach: CGFloat) -> Bool {
        for line in polylines {
            guard line.count > 1 else { continue }
            for index in 0..<(line.count - 1)
            where CanvasGeometry.distance(point, from: line[index], to: line[index + 1]) <= reach {
                return true
            }
        }
        return false
    }

    /// Where a line from `centre` towards `target` leaves the item — the
    /// point an arrow attached to it lands on. The outermost crossing of the
    /// outline, so a star's arrow stops at its points; the centre itself when
    /// the target is inside.
    func boundaryPoint(from centre: CGPoint, towards target: CGPoint, in size: CGSize) -> CGPoint {
        let outline = outline(in: size)
        guard outline.count > 1 else { return centre }
        var edges = Array(zip(outline, outline.dropFirst()))
        if let first = outline.first, let last = outline.last { edges.append((last, first)) }
        var best: (t: CGFloat, point: CGPoint)?
        for (a, b) in edges {
            guard let hit = CanvasGeometry.intersection(centre, target, a, b) else { continue }
            let t = CanvasGeometry.distance(centre, hit)
            if best == nil || t > best!.t { best = (t, hit) }
        }
        return best?.point ?? centre
    }

    /// Does the marquee touch the item at all? Touching is enough — the whole
    /// drawing does not have to be inside the rectangle.
    func intersects(_ rect: CGRect, in size: CGSize) -> Bool {
        // The outline is inside the envelope: a marquee that misses the
        // envelope misses the item.
        // A thousandth of a point of slack: the outline's own corner and the
        // envelope's are the same number worked out two ways, and either can
        // be a rounding error outside the other.
        let envelope = envelope(in: size, slack: 0.001)
        guard !(rect.maxX < envelope.minX || rect.minX > envelope.maxX
                || rect.maxY < envelope.minY || rect.minY > envelope.maxY) else { return false }
        let outline = outline(in: size)
        guard !outline.isEmpty else { return false }
        if outline.contains(where: { rect.contains($0) }) { return true }
        if outline.count == 1 {
            // A dot has no length to cross with; the point test above is it.
            return false
        }
        var edges = Array(zip(outline, outline.dropFirst()))
        if isClosed, let first = outline.first, let last = outline.last { edges.append((last, first)) }
        for (a, b) in edges where CanvasGeometry.segment(a, b, intersects: rect) { return true }
        // A marquee drawn entirely inside a picture still selects it.
        return isClosed && CanvasGeometry.polygon(outline, contains: CGPoint(x: rect.midX, y: rect.midY))
    }
}

extension Drawing {
    /// The upright box around a set of items — the frame the handles hang off.
    func bounds(of ids: Set<UUID>, in size: CGSize) -> CGRect? {
        let boxes = items.filter { ids.contains($0.id) && !$0.isHidden }.map { $0.bounds(in: size) }
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}

/// The geometry a selection needs, kept pure so it can be tested without a view.
enum CanvasGeometry {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// A drag held to an axis: the far end put back onto the horizontal or
    /// the vertical through the near one, whichever of the two the drag was
    /// already closer to (Sean, 2026-09-21: "if i hold shift, the direction
    /// elements become fixed to horizontal or vertical axes").
    ///
    /// Distance along the axis is kept and the other component thrown away,
    /// rather than the length being kept and the angle rounded: a line
    /// snapping to the axis should not also change how long it is, and the
    /// end has to stay under the pointer along the direction that is left.
    /// A drag exactly on the diagonal goes horizontal, which is arbitrary
    /// and has to be SOME answer; the next point of movement settles it.
    static func onAxis(_ to: CGPoint, from: CGPoint, locked: Bool = true) -> CGPoint {
        guard locked else { return to }
        return abs(to.x - from.x) >= abs(to.y - from.y)
            ? CGPoint(x: to.x, y: from.y)
            : CGPoint(x: from.x, y: to.y)
    }

    /// Distance from a point to a line segment.
    static func distance(_ point: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, a) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        return distance(point, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    static func segment(_ a: CGPoint, _ b: CGPoint, intersects rect: CGRect) -> Bool {
        if rect.contains(a) || rect.contains(b) { return true }
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        for index in 0..<4 where cross(a, b, corners[index], corners[(index + 1) % 4]) { return true }
        return false
    }

    /// Do two segments cross? Orientation signs, with the collinear cases
    /// folded in by the on-segment check.
    static func cross(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        let d1 = direction(p3, p4, p1), d2 = direction(p3, p4, p2)
        let d3 = direction(p1, p2, p3), d4 = direction(p1, p2, p4)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        if d1 == 0, onSegment(p3, p4, p1) { return true }
        if d2 == 0, onSegment(p3, p4, p2) { return true }
        if d3 == 0, onSegment(p1, p2, p3) { return true }
        if d4 == 0, onSegment(p1, p2, p4) { return true }
        return false
    }

    private static func direction(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)
    }

    private static func onSegment(_ a: CGPoint, _ b: CGPoint, _ point: CGPoint) -> Bool {
        min(a.x, b.x) <= point.x && point.x <= max(a.x, b.x)
            && min(a.y, b.y) <= point.y && point.y <= max(a.y, b.y)
    }

    /// Where segment a–b crosses segment c–d, or nil when it does not.
    static func intersection(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let r = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let s = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-9 else { return nil }
        let ac = CGPoint(x: c.x - a.x, y: c.y - a.y)
        let t = (ac.x * s.y - ac.y * s.x) / denominator
        let u = (ac.x * r.y - ac.y * r.x) / denominator
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return CGPoint(x: a.x + t * r.x, y: a.y + t * r.y)
    }

    static func polygon(_ points: [CGPoint], contains point: CGPoint) -> Bool {
        guard points.count > 2 else { return false }
        var inside = false
        var j = points.count - 1
        for i in points.indices {
            let a = points[i], b = points[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// Moving, scaling and rotating a selection. Pure, and shared by the drag of
/// the items themselves and the drags of the handles, so one item and a group
/// of twelve behave the same way.
enum CanvasEdit {
    /// Where `item` ends up after a gesture that started with `original`:
    /// dragged by `translate`, then scaled by `scale` and turned by `rotate`
    /// about `pivot`.
    static func transform(_ item: CanvasItem, from original: ItemTransform,
                          translate: CGVector = .zero, scale: Double = 1, rotate: Double = 0,
                          about pivot: CGPoint, in size: CGSize) -> ItemTransform {
        guard size.width > 0, size.height > 0 else { return original }
        var snapshot = item
        snapshot.transform = original
        let placed = snapshot.placedCenter(in: size)
        let moved = CGPoint(x: placed.x + translate.dx, y: placed.y + translate.dy)
        let offset = CGPoint(x: moved.x - pivot.x, y: moved.y - pivot.y)
        let c = cos(rotate), s = sin(rotate)
        let turned = CGPoint(x: pivot.x + scale * (offset.x * c - offset.y * s),
                             y: pivot.y + scale * (offset.x * s + offset.y * c))
        let base = item.baseCenter(in: size)

        var result = original
        result.scale = max(0.02, original.scale * scale)
        result.rotation = original.rotation + rotate
        result.dx = (turned.x - base.x) / size.width
        result.dy = (turned.y - base.y) / size.height
        return result
    }

    /// A picture with only the part inside `rect` (fractions of it, top-left
    /// origin) left, on a new file: the kept part stays exactly where it was
    /// on the pane, and the transform is untouched.
    static func crop(_ item: ImageItem, to rect: CGRect, file: String, aspect: Double,
                     in size: CGSize) -> ImageItem {
        guard size.width > 0, size.height > 0 else { return item }
        let whole = CanvasItem.image(item)
        let base = whole.baseBounds(in: size)
        // The kept part's centre before the transform, and where it is now.
        let centre = CGPoint(x: base.minX + rect.midX * base.width, y: base.minY + rect.midY * base.height)
        let placed = centre.applying(whole.matrix(in: size))
        var cropped = item
        cropped.file = file
        cropped.width = item.width * rect.width
        cropped.aspect = aspect
        // The transform turns and scales about the item's own centre and then
        // moves it by (dx, dy), so the new centre goes where the kept part is
        // now, less that move.
        cropped.center = CGPoint(x: (placed.x - item.transform.dx * size.width) / size.width,
                                 y: (placed.y - item.transform.dy * size.height) / size.height)
        return cropped
    }

    /// One corner of the crop box dragged to `point` (fractions of the
    /// picture): 0 top left, 1 top right, 2 bottom right, 3 bottom left. The
    /// box stays inside the picture and never thinner than `minimum`.
    static func cropRect(_ rect: CGRect, movingCorner corner: Int, to point: CGPoint,
                         minimum: CGFloat = 0.05) -> CGRect {
        let x = min(max(point.x, 0), 1), y = min(max(point.y, 0), 1)
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch corner {
        case 0: minX = min(x, maxX - minimum); minY = min(y, maxY - minimum)
        case 1: maxX = max(x, minX + minimum); minY = min(y, maxY - minimum)
        case 2: maxX = max(x, minX + minimum); maxY = max(y, minY + minimum)
        default: minX = min(x, maxX - minimum); maxY = max(y, minY + minimum)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The angle of a point about the pivot — the rotate handle's whole maths.
    static func angle(of point: CGPoint, about pivot: CGPoint) -> Double {
        atan2(Double(point.y - pivot.y), Double(point.x - pivot.x))
    }

    /// How much bigger the drag has made the selection. Clamped so a flick
    /// through the pivot cannot turn an object inside out.
    static func factor(from start: CGPoint, to current: CGPoint, about pivot: CGPoint) -> Double {
        let before = CanvasGeometry.distance(start, pivot)
        guard before > 1 else { return 1 }
        return min(max(Double(CanvasGeometry.distance(current, pivot) / before), 0.05), 20)
    }
}
