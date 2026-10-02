import AppKit
import XCTest
@testable import WriteMind

private let pane = CGSize(width: 1000, height: 500)

/// Flow-chart nodes, the arrows between them, and the marks.
final class ShapeTests: XCTestCase {
    private func node(_ kind: ShapeItem.Kind = .rectangle, at x: Double) -> ShapeItem {
        ShapeItem(kind: kind, center: CGPoint(x: x, y: 0.5), width: 0.2, aspect: 0.5, colorHex: "#000000")
    }

    private func arrow(from a: ShapeItem, to b: ShapeItem) -> ConnectorItem {
        ConnectorItem(start: .zero, end: .zero, startNode: a.id, endNode: b.id, colorHex: "#000000")
    }

    func testShapesAndConnectorsSurviveTheSidecar() throws {
        let a = node(at: 0.2), b = node(.oval, at: 0.7)
        var drawing = Drawing(items: [.shape(a), .shape(b)])
        drawing.items.append(.connector(ConnectorItem(
            start: CGPoint(x: 0.2, y: 0.5), end: CGPoint(x: 0.7, y: 0.5), startNode: a.id, endNode: b.id,
            startHead: .arrow, endHead: .arrow, line: .dashed, colorHex: "#FF0000", lineWidth: 3)))
        let data = try JSONEncoder().encode(drawing)
        let back = try JSONDecoder().decode(Drawing.self, from: data)
        XCTAssertEqual(back, drawing)
        XCTAssertEqual(back.connectors.first?.line, .dashed)
        XCTAssertEqual(back.shapes.map(\.kind), [.rectangle, .oval])
    }

    func testAnAttachedArrowLandsOnTheEdgesOfItsNodes() throws {
        // a spans x 100…300 and b x 600…800 in the 1000-wide pane.
        let a = node(at: 0.2), b = node(at: 0.7)
        var drawing = Drawing(items: [.shape(a), .shape(b), .connector(arrow(from: a, to: b))])
        drawing.reconnect(in: pane)
        let joined = try XCTUnwrap(drawing.connectors.first)
        XCTAssertEqual(joined.start.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(joined.start.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(joined.end.x, 0.6, accuracy: 0.001)
        XCTAssertEqual(joined.end.y, 0.5, accuracy: 0.001)
    }

    func testAnArrowFollowsANodeThatMoves() throws {
        let a = node(at: 0.2), b = node(at: 0.7)
        var drawing = Drawing(items: [.shape(a), .shape(b), .connector(arrow(from: a, to: b))])
        drawing.reconnect(in: pane)
        var moved = try XCTUnwrap(drawing[id: b.id])
        moved.transform.dy = 0.3   // b goes down by 150 points
        drawing[id: b.id] = moved
        drawing.reconnect(in: pane)
        let joined = try XCTUnwrap(drawing.connectors.first)
        XCTAssertGreaterThan(joined.end.y, 0.5, "the end went down with the node")
        XCTAssertLessThan(joined.end.y, 0.8, "and stops at the node's edge, not at its centre")
        // The node is now below and to the right, so the line turns a corner
        // and comes down into the top of it (Sean, 2026-09-19: "lines are
        // always straight with corners").
        XCTAssertEqual(joined.end.x, 0.7, accuracy: 0.001, "in at the middle of the top edge")
        XCTAssertFalse(joined.bends.isEmpty, "by way of a corner")
        for point in joined.route {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite)
        }
    }

    func testAnArrowsOwnMoveIsBakedIntoItsPoints() throws {
        var drawing = Drawing(items: [.connector(ConnectorItem(
            start: CGPoint(x: 0.2, y: 0.5), end: CGPoint(x: 0.4, y: 0.5), colorHex: "#000000"))])
        var dragged = drawing.items[0]
        dragged.transform.dx = 0.1
        drawing.items[0] = dragged
        drawing.reconnect(in: pane)
        let baked = try XCTUnwrap(drawing.connectors.first)
        XCTAssertEqual(baked.transform, ItemTransform())
        XCTAssertEqual(baked.start.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(baked.end.x, 0.5, accuracy: 0.001)
    }

    func testDeletingANodeTakesItsArrowsWithIt() {
        let a = node(at: 0.2), b = node(at: 0.7)
        let free = ConnectorItem(start: CGPoint(x: 0.1, y: 0.9), end: CGPoint(x: 0.3, y: 0.9), colorHex: "#000000")
        let drawing = Drawing(items: [.shape(a), .shape(b), .connector(arrow(from: a, to: b)), .connector(free)])
        XCTAssertEqual(drawing.removing([a.id]).items.map(\.id), [b.id, free.id])
    }

    func testAnOvalIsHitInsideAndACheckMarkOnlyOnItsLine() {
        // 200 × 200, centred at (500, 250).
        let oval = CanvasItem.shape(ShapeItem(kind: .oval, center: CGPoint(x: 0.5, y: 0.5), width: 0.2,
                                              aspect: 1, colorHex: "#000000"))
        XCTAssertTrue(oval.hitTest(CGPoint(x: 500, y: 250), in: pane))
        XCTAssertFalse(oval.hitTest(CGPoint(x: 410, y: 160), in: pane), "the corner of the box is outside the oval")
        XCTAssertEqual(pane.width, 1000)
        // 100 × 100 at (450…550, 200…300): the tick's short arm runs from
        // (458, 255) to (488, 286).
        let check = CanvasItem.shape(ShapeItem(kind: .check, center: CGPoint(x: 0.5, y: 0.5), width: 0.1,
                                               aspect: 1, colorHex: "#000000", lineWidth: 4))
        XCTAssertTrue(check.hitTest(CGPoint(x: 473, y: 270), in: pane))
        XCTAssertFalse(check.hitTest(CGPoint(x: 460, y: 215), in: pane), "the empty top-left corner")
        XCTAssertNotNil(Drawing(items: [oval]).attachable(at: CGPoint(x: 500, y: 250), in: pane))
        XCTAssertNil(Drawing(items: [oval]).attachable(at: CGPoint(x: 100, y: 100), in: pane))
    }

    func testAnArrowIsHitAlongItsLine() {
        let line = CanvasItem.connector(ConnectorItem(start: CGPoint(x: 0.2, y: 0.5), end: CGPoint(x: 0.4, y: 0.5),
                                                      colorHex: "#000000"))
        XCTAssertTrue(line.hitTest(CGPoint(x: 300, y: 252), in: pane))
        XCTAssertFalse(line.hitTest(CGPoint(x: 300, y: 280), in: pane))
    }

    func testATextBoxIsANodeThatGrowsToItsText() {
        XCTAssertTrue(ShapeItem.Kind.text.isNode)
        XCTAssertTrue(ShapeItem.Kind.text.isClosed)
        let short = ShapeItem.textAspect(for: "Hi", boxWidth: 200)
        let long = ShapeItem.textAspect(for: String(repeating: "words and more words ", count: 12), boxWidth: 200)
        XCTAssertGreaterThan(long, short * 3, "twelve lines are far taller than one")
        XCTAssertGreaterThan(short, 0.08)
        XCTAssertEqual(ShapeItem.textAspect(for: "anything", boxWidth: 5), 0.3, "no room: the default")
    }

    func testTheHeadHasItsTipAtTheEnd() {
        let head = ConnectorItem.head(tip: CGPoint(x: 100, y: 50), from: CGPoint(x: 0, y: 50), lineWidth: 2)
        XCTAssertEqual(head.boundingRect.maxX, 100, accuracy: 0.001)
        XCTAssertEqual(head.boundingRect.width, ConnectorItem.headLength(for: 2), accuracy: 0.001)
        XCTAssertEqual(CanvasGeometry.intersection(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10),
                                                   CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 0)),
                       CGPoint(x: 5, y: 5))
        XCTAssertNil(CanvasGeometry.intersection(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
                                                 CGPoint(x: 0, y: 1), CGPoint(x: 10, y: 1)))
    }
}

/// Every icon the palettes and the bar ask for has to exist on this macOS:
/// a symbol that is not there draws nothing at all, and the button looks
/// broken (2026-09-19, when `parallelogram` turned out to be macOS 15's).
final class SymbolTests: XCTestCase {
    func testEveryShapeAndMarkHasAnIconThatExists() {
        for kind in ShapeItem.Kind.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil),
                            "\(kind.title) asks for the missing symbol \(kind.symbol)")
        }
    }

    func testEveryToolbarSectionHasAnIconThatExists() {
        for group in ToolGroup.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: group.icon, accessibilityDescription: nil),
                            "\(group.title) asks for the missing symbol \(group.icon)")
        }
    }

    /// The camera pane's own icons are not in any enum, so they are listed
    /// here by hand — `parallelogram` was missing on this macOS and drew
    /// nothing at all (2026-09-19).
    func testEveryCameraPaneIconExists() {
        let icons = ["rectangle.dashed", "crop.rotate", "rotate.left", "rotate.right",
                     "arrow.down.right.and.arrow.up.left", "square.dashed", "video", "video.fill",
                     "video.slash", "video.badge.ellipsis", "exclamationmark.triangle",
                     "doc.viewfinder", "scribble.variable", "xmark",
                     "rectangle.righthalf.inset.filled", "rectangle.lefthalf.inset.filled",
                     // The tablet's pane, which stands where the camera's does.
                     "pencil.tip", "cable.connector.slash", "hand.raised", "ellipsis.circle",
                     // The page's undo, redo and clear, and the box's three.
                     "arrow.uturn.backward", "arrow.uturn.forward", "trash",
                     "photo", "text.viewfinder",
                     // The pane's switch while it is the page.
                     "pencil.tip.crop.circle", "pencil.slash"]
        for icon in icons {
            XCTAssertNotNil(NSImage(systemSymbolName: icon, accessibilityDescription: nil),
                            "the camera pane asks for the missing symbol \(icon)")
        }
    }

    func testEveryListStyleHasAnIconThatExists() {
        for style in MarkdownFormatting.ListStyle.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: style.systemImage, accessibilityDescription: nil),
                            "\(style.title) asks for the missing symbol \(style.systemImage)")
        }
    }
}

/// The three marks are icons, and they have to look like the thing.
final class MarkArtworkTests: XCTestCase {
    private func box(_ kind: ShapeItem.Kind) -> CGRect {
        let points = kind.unitPolylines.flatMap { $0 }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!,
                      width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    func testEveryMarkIsInsetSoARoundCapStaysInItsBox() {
        // A cap is half the stroke wide and hangs off the end of the
        // line; on the edge of the unit square it hangs out of the box
        // the handles are drawn round.
        for kind in [ShapeItem.Kind.check, .cross, .star, .question] {
            let box = box(kind)
            XCTAssertGreaterThanOrEqual(box.minX, 0.04, "\(kind) touches the left edge")
            XCTAssertGreaterThanOrEqual(box.minY, 0.04, "\(kind) touches the top edge")
            XCTAssertLessThanOrEqual(box.maxX, 0.96, "\(kind) touches the right edge")
            XCTAssertLessThanOrEqual(box.maxY, 0.96, "\(kind) touches the bottom edge")
        }
    }

    func testTheCrossIsSquareAndCentred() {
        let box = box(.cross)
        XCTAssertEqual(box.width, box.height, accuracy: 0.001)
        XCTAssertEqual(box.midX, 0.5, accuracy: 0.001)
        XCTAssertEqual(box.midY, 0.5, accuracy: 0.001)
    }

    func testTheTicksShortArmIsAboutTwoFifthsOfItsLong() {
        let tick = ShapeItem.Kind.check.unitPolylines[0]
        XCTAssertEqual(tick.count, 3)
        func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
        let short = length(tick[0], tick[1]), long = length(tick[1], tick[2])
        XCTAssertEqual(short / long, 0.4, accuracy: 0.12, "a tick, not a wide V")
        XCTAssertLessThan(tick[1].x, 0.5, "the knee is left of centre")
        XCTAssertGreaterThan(tick[1].y, tick[0].y, "and below where it starts")
    }

    func testTheQuestionMarkIsAHookOverADot() {
        // Sean, 2026-09-21: "yellow ?". A question mark is two strokes
        // — the hook, and the dot under it — and the hook has to go
        // OVER the top and come back down to a stem in the middle, or
        // it is a bent line.
        let parts = ShapeItem.Kind.question.unitPolylines
        XCTAssertEqual(parts.count, 2, "the hook and the dot")
        let hook = parts[0], dot = parts[1]

        let top = hook.min { $0.y < $1.y }!
        XCTAssertLessThan(top.y, 0.25, "the bowl goes over the top")
        XCTAssertEqual(top.x, 0.5, accuracy: 0.08, "and its apex is over the middle")
        XCTAssertLessThan(hook.min { $0.x < $1.x }!.x, 0.35, "round the left")
        XCTAssertGreaterThan(hook.max { $0.x < $1.x }!.x, 0.65, "and round the right")

        let stem = hook.last!
        XCTAssertEqual(stem.x, 0.5, accuracy: 0.03, "the stem comes back to the middle")
        XCTAssertGreaterThan(stem.y, 0.55, "below the bowl")
        XCTAssertLessThan(stem.y, 0.78)
        XCTAssertGreaterThan(hook.first!.y, top.y, "and it starts below its own apex")
    }

    func testTheQuestionMarksDotIsADotUnderTheStem() {
        let parts = ShapeItem.Kind.question.unitPolylines
        let hook = parts[0], dot = parts[1]
        func length(_ line: [CGPoint]) -> CGFloat {
            zip(line, line.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        }
        // A round cap draws the dot, so the segment under it is barely
        // there — long enough that no renderer drops it, short enough
        // that it is a dot and not a dash.
        XCTAssertLessThan(length(dot), 0.03, "a dot, not a dash")
        XCTAssertGreaterThan(length(dot), 0, "but not nothing, which some renderers drop")
        XCTAssertEqual(dot[0].x, 0.5, accuracy: 0.03, "under the stem")
        XCTAssertGreaterThan(dot[0].y, hook.last!.y + 0.08, "with a gap below it")
    }

    func testTheStarIsAFivePointedStarAndNotASpider() {
        let star = ShapeItem.Kind.star.unitPolylines[0]
        XCTAssertEqual(star.count, 10)
        let centre = CGPoint(x: 0.5, y: 0.5)
        func radius(_ point: CGPoint) -> CGFloat { hypot(point.x - centre.x, point.y - centre.y) }
        let outer = radius(star[0]), inner = radius(star[1])
        // The classic proportion is the outer radius over phi squared.
        XCTAssertEqual(inner / outer, 0.382, accuracy: 0.02)
    }
}
