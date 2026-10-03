import AppKit
import XCTest
@testable import WriteMind

/// The key held during a placement (Sean, 2026-09-21: "if i hold shift,
/// the direction elements become fixed to horizontal or vertical axes"),
/// and what stays armed once something is down (Sean, 2026-10-02: shapes
/// and marks both stay).
final class PlacementModifierTests: XCTestCase {
    private let size = CGSize(width: 400, height: 300)

    // MARK: - ⇧ holds a line to an axis

    func testADragMostlySidewaysGoesFlatAndOneMostlyDownGoesUpright() {
        let from = CGPoint(x: 100, y: 100)
        XCTAssertEqual(CanvasGeometry.onAxis(CGPoint(x: 220, y: 130), from: from),
                       CGPoint(x: 220, y: 100), "nearer the horizontal")
        XCTAssertEqual(CanvasGeometry.onAxis(CGPoint(x: 130, y: 220), from: from),
                       CGPoint(x: 100, y: 220), "nearer the vertical")
        // Backwards and upwards are the same question.
        XCTAssertEqual(CanvasGeometry.onAxis(CGPoint(x: 10, y: 90), from: from),
                       CGPoint(x: 10, y: 100))
        XCTAssertEqual(CanvasGeometry.onAxis(CGPoint(x: 95, y: 10), from: from),
                       CGPoint(x: 100, y: 10))
    }

    func testTheLengthAlongTheAxisIsKeptRatherThanTheLengthOfTheDrag() {
        // The end stays under the pointer in the direction that is left;
        // rounding the ANGLE would slide it away from the pointer instead.
        let end = CanvasGeometry.onAxis(CGPoint(x: 300, y: 140), from: CGPoint(x: 100, y: 100))
        XCTAssertEqual(end.x, 300)
    }

    func testAnUnheldDragIsNotTouched() {
        let to = CGPoint(x: 220, y: 130)
        XCTAssertEqual(CanvasGeometry.onAxis(to, from: CGPoint(x: 100, y: 100), locked: false), to)
    }

    func testOnlySomethingWithADirectionIsHeldToAnAxis() {
        let from = CGPoint(x: 100, y: 100), to = CGPoint(x: 220, y: 130)
        let arrow = CanvasPlacement.line(start: .none, end: .arrow)
        let tick = CanvasPlacement.shape(.check)
        XCTAssertTrue(arrow.hasDirection)
        XCTAssertFalse(tick.hasDirection, "a mark is square already")
        XCTAssertEqual(arrow.end(to, from: from, modifiers: .shift), CGPoint(x: 220, y: 100))
        XCTAssertEqual(tick.end(to, from: from, modifiers: .shift), to, "⇧ means nothing over a mark")
        XCTAssertEqual(arrow.end(to, from: from, modifiers: []), to)
    }

    func testAnArrowHeldToAnAxisIsPutDownOnThatAxis() {
        let from = CGPoint(x: 100, y: 100)
        let placing = CanvasPlacement.line(start: .none, end: .arrow)
        let to = placing.end(CGPoint(x: 300, y: 140), from: from, modifiers: .shift)
        guard case .connector(let line)? = placing.item(from: from, to: to, in: size,
                                                        colorHex: "#ffffff", lineWidth: 3)
        else { return XCTFail("no arrow") }
        XCTAssertEqual(line.start.y, line.end.y, accuracy: 0.0001, "flat, in the pane's fractions")
        XCTAssertEqual(line.end.x, 300 / size.width, accuracy: 0.0001)
    }

    /// The arrow tool and an ⌥-drag off a node build their line by hand,
    /// so they ask the canvas rather than the placement — and have to get
    /// the same answer.
    func testTheArrowToolHoldsTheSameAxis() {
        let from = CGPoint(x: 100, y: 100), to = CGPoint(x: 300, y: 140)
        XCTAssertEqual(DrawingCanvas.dragEnd(to, from: from, modifiers: .shift),
                       CanvasPlacement.line(start: .none, end: .arrow)
                           .end(to, from: from, modifiers: .shift))
        XCTAssertEqual(DrawingCanvas.dragEnd(to, from: from, modifiers: []), to)
    }

    // MARK: - What stays armed

    private let lines: [CanvasPlacement] = [.line(start: .none, end: .none),
                                            .line(start: .none, end: .arrow),
                                            .line(start: .arrow, end: .arrow)]

    /// Sean, 2026-10-02: "after drawing a rectangle dont exit rectangle
    /// mode.." and "after placing mark like check mark, i shouldn't leave
    /// place mode similar to drawing rectangles". Nothing put down hands
    /// the tool back, and so the tool itself has no question to ask about
    /// it: the canvas never calls `onDisarm` from `place`.
    func testNothingPutDownHandsTheToolBack() throws {
        let source = try String(contentsOfFile: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "WriteMind/Drawing/DrawingCanvas.swift").path, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func place(from:"))
        let end = try XCTUnwrap(source.range(of: "private func ", range: start.upperBound..<source.endIndex))
        XCTAssertFalse(source[start.lowerBound..<end.lowerBound].contains("onDisarm"),
                       "a shape, a line or a mark went back to the palette after one was put down")
    }

    // MARK: - A click on a node is the node's

    /// A rectangle in the middle of the pane, 80 × 40 points.
    private func chart(_ node: ShapeItem = ShapeItem(kind: .rectangle, center: CGPoint(x: 0.5, y: 0.5),
                                                     width: 0.2, aspect: 0.5, colorHex: "#000000"))
        -> Drawing {
        Drawing(items: [.shape(node)])
    }

    private let onTheNode = CGPoint(x: 205, y: 152)
    private let blank = CGPoint(x: 40, y: 40)

    /// Sean's flow chart is a loop — draw a box, double-click it for its
    /// label, draw the next — and the box staying armed (Sean,
    /// 2026-10-02: "after drawing a rectangle dont exit rectangle
    /// mode..") took both clicks of the double-click: two boxes stacked
    /// on the one clicked, and no label.
    func testADoubleClickOnANodeLabelsItWhileAShapeIsArmed() throws {
        let drawing = chart()
        let id = try XCTUnwrap(drawing.items.first?.id)
        for armed in [CanvasPlacement.shape(.rectangle), .shape(.diamond), .line(start: .none, end: .arrow)] {
            XCTAssertEqual(armed.release(from: onTheNode, to: onTheNode, clicks: 1, in: drawing, size: size),
                           .pick([id]), "the first click of the two picks the node with \(armed.title) armed")
            XCTAssertEqual(armed.release(from: onTheNode, to: onTheNode, clicks: 2, in: drawing, size: size),
                           .label(id), "the second opens its label with \(armed.title) armed")
        }
    }

    /// Everything else a click or a drag did with a shape armed, it still
    /// does.
    func testAClickOnBlankPaperOrADragFromANodeStillDraws() {
        let drawing = chart()
        let box = CanvasPlacement.shape(.rectangle)
        XCTAssertEqual(box.release(from: blank, to: blank, clicks: 1, in: drawing, size: size), .put,
                       "a click on blank paper puts one down at its own size")
        XCTAssertEqual(box.release(from: blank, to: blank, clicks: 2, in: drawing, size: size), .put)
        XCTAssertEqual(box.release(from: onTheNode, to: CGPoint(x: 300, y: 250), clicks: 1,
                                   in: drawing, size: size), .put, "a box drawn from inside a box")
        XCTAssertEqual(box.release(from: onTheNode, to: CGPoint(x: 206, y: 153), clicks: 1,
                                   in: drawing, size: size), .pick(Set(drawing.items.map(\.id))),
                       "a hand that shook a point is still a click")
    }

    /// A mark is a stamp, and a tick in a box is what a box is for.
    func testAMarkClickedOntoANodeGoesDownInIt() {
        let drawing = chart()
        for kind in ShapeItem.Kind.allCases where !kind.isNode {
            XCTAssertEqual(CanvasPlacement.shape(kind).release(from: onTheNode, to: onTheNode, clicks: 1,
                                                               in: drawing, size: size), .put, kind.title)
        }
    }

    /// The same clicks with nothing armed pick a group whole and open no
    /// label in one — and a click means one thing whatever is armed.
    func testANodeInAGroupIsPickedWithItsGroupAndOpensNoLabel() {
        let group = UUID()
        let node = ShapeItem(kind: .rectangle, center: CGPoint(x: 0.5, y: 0.5), width: 0.2, aspect: 0.5,
                             colorHex: "#000000", group: group)
        let partner = ShapeItem(kind: .oval, center: CGPoint(x: 0.1, y: 0.1), colorHex: "#000000", group: group)
        let drawing = Drawing(items: [.shape(node), .shape(partner)])
        let box = CanvasPlacement.shape(.rectangle)
        XCTAssertEqual(box.release(from: onTheNode, to: onTheNode, clicks: 1, in: drawing, size: size),
                       .pick([node.id, partner.id]))
        XCTAssertEqual(box.release(from: onTheNode, to: onTheNode, clicks: 2, in: drawing, size: size),
                       .pick([node.id, partner.id]))
    }

    /// The pane takes every drag while a shape is armed, so the footer
    /// says what has it and how to put it away.
    func testTheFooterSaysWhatTakesTheDragsAndHowToPutItAway() {
        for placement in ShapeItem.Kind.allCases.map(CanvasPlacement.shape) + lines {
            let line = placement.footer
            XCTAssertTrue(line.hasPrefix(placement.title), "\(line) names \(placement.title)")
            XCTAssertTrue(line.contains("Esc"), "\(line) says how to put it away")
            XCTAssertTrue(line.contains("every"), "\(line) says it stays")
        }
    }
}
