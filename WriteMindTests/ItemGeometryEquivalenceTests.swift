import XCTest
@testable import WriteMind

/// THE FAST GEOMETRY ANSWERS EXACTLY WHAT THE SLOW ONE DID (Sean, 2026-10-02:
/// "fix the performance of grouped objects"). `CanvasItem`'s box, outline,
/// hit test and marquee test now put an item aside by its envelope and work in
/// one pass over a stroke's points; this holds them against the plain,
/// allocate-everything versions they replaced, over items of every kind, every
/// transform and a lot of points and rectangles.
final class ItemGeometryEquivalenceTests: XCTestCase {
    private let size = CGSize(width: 900, height: 700)
    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15

    private func next() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 11) / Double(UInt64(1) << 53)
    }

    private func transform() -> ItemTransform {
        var t = ItemTransform()
        if next() < 0.8 {
            t.dx = (next() - 0.5) * 0.4
            t.dy = (next() - 0.5) * 0.4
            t.scale = 0.3 + next() * 2.2
            t.rotation = (next() - 0.5) * 6
        }
        return t
    }

    private func items() -> [CanvasItem] {
        var out: [CanvasItem] = []
        for _ in 0..<60 {
            let count = [1, 2, 3, 20, 90][Int(next() * 5) % 5]
            let x0 = next() * 0.8, y0 = next() * 0.8
            let points = (0..<count).map { i in
                CGPoint(x: x0 + 0.002 * Double(i) + next() * 0.01, y: y0 + 0.01 * sin(Double(i)) + next() * 0.01)
            }
            var stroke = Stroke(colorHex: "#000000", width: 1 + next() * 8, points: points,
                                pressures: next() < 0.5 ? points.map { _ in 0.2 + next() * 0.7 } : nil,
                                tool: next() < 0.5 ? .fountain : nil)
            stroke.transform = transform()
            out.append(.stroke(stroke))
        }
        for _ in 0..<12 {
            var image = ImageItem(file: "a.png", center: CGPoint(x: next(), y: next()), width: 0.05 + next() * 0.3,
                                  aspect: 0.4 + next())
            image.transform = transform()
            out.append(.image(image))
        }
        for kind in ShapeItem.Kind.allCases {
            var shape = ShapeItem(kind: kind, center: CGPoint(x: 0.1 + next() * 0.8, y: 0.1 + next() * 0.8),
                                  width: 0.04 + next() * 0.2, aspect: 0.4 + next() * 0.8, colorHex: "#000000")
            shape.transform = transform()
            out.append(.shape(shape))
        }
        for _ in 0..<8 {
            var line = ConnectorItem(start: CGPoint(x: next(), y: next()), end: CGPoint(x: next(), y: next()),
                                     startHead: .none, endHead: .arrow, line: .solid, colorHex: "#000000",
                                     lineWidth: 1 + next() * 5)
            if next() < 0.5 { line.bends = [CGPoint(x: next(), y: next()), CGPoint(x: next(), y: next())] }
            line.transform = transform()
            out.append(.connector(line))
        }
        return out
    }

    // MARK: - The plain versions this replaced

    private func refBaseBounds(_ item: CanvasItem) -> CGRect {
        if case .shape = item { return item.baseBounds(in: size) }
        let points = item.basePoints(in: size)
        guard let first = points.first else { return .zero }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() { rect = rect.union(CGRect(origin: point, size: .zero)) }
        switch item {
        case .stroke(let stroke): rect = rect.insetBy(dx: -stroke.reach, dy: -stroke.reach)
        case .connector(let connector):
            let reach = max(connector.lineWidth / 2, ConnectorItem.headLength(for: connector.lineWidth) / 2)
            rect = rect.insetBy(dx: -reach, dy: -reach)
        default: break
        }
        return rect
    }

    private func refMatrix(_ item: CanvasItem) -> CGAffineTransform {
        let box = refBaseBounds(item)
        let centre = CGPoint(x: box.midX, y: box.midY)
        let t = item.transform
        return CGAffineTransform.identity
            .translatedBy(x: centre.x + t.dx * size.width, y: centre.y + t.dy * size.height)
            .rotated(by: t.rotation).scaledBy(x: t.scale, y: t.scale)
            .translatedBy(x: -centre.x, y: -centre.y)
    }

    private func refOutline(_ item: CanvasItem) -> [CGPoint] {
        let matrix = refMatrix(item)
        return item.basePoints(in: size).map { $0.applying(matrix) }
    }

    private func near(_ point: CGPoint, _ lines: [[CGPoint]], _ reach: CGFloat) -> Bool {
        for line in lines where line.count > 1 {
            for index in 0..<(line.count - 1)
            where CanvasGeometry.distance(point, from: line[index], to: line[index + 1]) <= reach { return true }
        }
        return false
    }

    private func refHit(_ item: CanvasItem, _ point: CGPoint) -> Bool {
        let outline = refOutline(item)
        guard !outline.isEmpty else { return false }
        let scale = item.transform.scale
        switch item {
        case .image:
            return CanvasGeometry.polygon(outline, contains: point)
        case .shape(let shape):
            if shape.kind.isClosed {
                return CanvasGeometry.polygon(outline, contains: point)
                    || near(point, [outline + [outline[0]]], max(shape.lineWidth * scale / 2, 6))
            }
            let matrix = refMatrix(item)
            let lines = shape.kind.polylines(in: item.baseBounds(in: size)).map { $0.map { $0.applying(matrix) } }
            return near(point, lines, max(shape.lineWidth * scale / 2, 6))
        case .connector(let connector):
            return near(point, [outline], max(connector.lineWidth * scale / 2, 6))
        case .stroke(let stroke):
            let reach = max(stroke.reach * scale, 6)
            if outline.count == 1 { return CanvasGeometry.distance(point, outline[0]) <= reach }
            return near(point, [outline], reach)
        }
    }

    private func refIntersects(_ item: CanvasItem, _ rect: CGRect) -> Bool {
        let outline = refOutline(item)
        guard !outline.isEmpty else { return false }
        if outline.contains(where: { rect.contains($0) }) { return true }
        if outline.count == 1 { return false }
        var edges = Array(zip(outline, outline.dropFirst()))
        if item.isClosed, let first = outline.first, let last = outline.last { edges.append((last, first)) }
        for (a, b) in edges where CanvasGeometry.segment(a, b, intersects: rect) { return true }
        return item.isClosed && CanvasGeometry.polygon(outline, contains: CGPoint(x: rect.midX, y: rect.midY))
    }

    // MARK: - Held against them

    func testTheBoxTheOutlineAndTheCornersAreTheSame() {
        for item in items() {
            let box = item.baseBounds(in: size), ref = refBaseBounds(item)
            XCTAssertEqual(box.origin.x, ref.origin.x, accuracy: 1e-9)
            XCTAssertEqual(box.origin.y, ref.origin.y, accuracy: 1e-9)
            XCTAssertEqual(box.width, ref.width, accuracy: 1e-9)
            XCTAssertEqual(box.height, ref.height, accuracy: 1e-9)
            let outline = item.outline(in: size), refOut = refOutline(item)
            XCTAssertEqual(outline.count, refOut.count)
            for (a, b) in zip(outline, refOut) {
                XCTAssertEqual(a.x, b.x, accuracy: 1e-6)
                XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
            }
            let corners = item.frameCorners(in: size)
            let matrix = refMatrix(item)
            let refCorners = [CGPoint(x: ref.minX, y: ref.minY), CGPoint(x: ref.maxX, y: ref.minY),
                              CGPoint(x: ref.maxX, y: ref.maxY), CGPoint(x: ref.minX, y: ref.maxY)]
                .map { $0.applying(matrix) }
            for (a, b) in zip(corners, refCorners) {
                XCTAssertEqual(a.x, b.x, accuracy: 1e-6)
                XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
            }
        }
    }

    func testAHitTestAnswersWhatItAlwaysDid() {
        var hits = 0, tests = 0
        for item in items() {
            let outline = refOutline(item)
            // Points on the item, just off it, and anywhere on the pane.
            var probes: [CGPoint] = outline.prefix(8).map { CGPoint(x: $0.x + (next() - 0.5) * 6, y: $0.y + (next() - 0.5) * 6) }
            probes += outline.prefix(4).map { CGPoint(x: $0.x + (next() - 0.5) * 40, y: $0.y + (next() - 0.5) * 40) }
            for _ in 0..<30 { probes.append(CGPoint(x: next() * size.width, y: next() * size.height)) }
            for point in probes {
                tests += 1
                let fast = item.hitTest(point, in: size), plain = refHit(item, point)
                if plain { hits += 1 }
                XCTAssertEqual(fast, plain, "\(item.kindName) at \(point)")
            }
        }
        XCTAssertGreaterThan(hits, 50, "the probes should land on things (\(hits) of \(tests))")
    }

    func testAMarqueeTestAnswersWhatItAlwaysDid() {
        var hits = 0
        for item in items() {
            for _ in 0..<25 {
                let a = CGPoint(x: next() * size.width, y: next() * size.height)
                let b = CGPoint(x: a.x + (next() - 0.3) * 260, y: a.y + (next() - 0.3) * 260)
                let rect = CanvasGeometry.rect(from: a, to: b)
                let fast = item.intersects(rect, in: size), plain = refIntersects(item, rect)
                if plain { hits += 1 }
                XCTAssertEqual(fast, plain, "\(item.kindName) in \(rect)")
            }
            // A click: a marquee of nothing.
            let point = refOutline(item).first ?? .zero
            let dot = CGRect(origin: point, size: .zero)
            XCTAssertEqual(item.intersects(dot, in: size), refIntersects(item, dot), "\(item.kindName) clicked")
        }
        XCTAssertGreaterThan(hits, 50)
    }
}

private extension CanvasItem {
    var kindName: String {
        switch self {
        case .stroke: return "stroke"
        case .image: return "image"
        case .shape(let shape): return "shape \(shape.kind)"
        case .connector: return "connector"
        }
    }
}
