import XCTest
@testable import WriteMind

/// Docking: what a dock lifts off the layer and where it lands in a cell
/// (`Docking`, `Drawing.lifting`) — Sean, 2026-10-02: "add a dock button
/// which inserts it into the cell of the existing cursor, and a create cell
/// from drawing".
final class DockingTests: XCTestCase {
    private let pane = CGSize(width: 600, height: 800)

    private func stroke(_ x: Double, _ y: Double, group: UUID? = nil, width: Double = 0.1) -> CanvasItem {
        .stroke(Stroke(colorHex: "#000000", width: 3,
                       points: [CGPoint(x: x, y: y), CGPoint(x: x + width, y: y + 0.02)], group: group,
                       pressures: [0.3, 0.8], tool: .fountain))
    }

    private func node(_ x: Double, _ y: Double) -> ShapeItem {
        ShapeItem(kind: .rectangle, center: CGPoint(x: x, y: y), width: 0.1, aspect: 0.5, colorHex: "#000000")
    }

    private func arrow(from a: UUID?, to b: UUID?) -> ConnectorItem {
        ConnectorItem(start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.6, y: 0.2), startNode: a, endNode: b,
                      startHead: .none, endHead: .arrow, line: .solid, colorHex: "#000000", lineWidth: 2)
    }

    // MARK: - Lifting

    func testWholeGroupsGoAndNothingElse() {
        let group = UUID()
        let a = stroke(0.1, 0.1, group: group), b = stroke(0.2, 0.1, group: group), c = stroke(0.3, 0.3)
        let lifted = Drawing(items: [a, b, c]).lifting([a.id])
        XCTAssertEqual(lifted.items.map(\.id), [a.id, b.id], "the whole group, in order")
        XCTAssertEqual(lifted.rest.items.map(\.id), [c.id])
    }

    func testAHiddenPictureIsNeverLifted() {
        let hidden = CanvasItem.image(ImageItem(file: "a.png", center: CGPoint(x: 0.5, y: 0.5), width: 0.2,
                                                hidden: true))
        let lifted = Drawing(items: [hidden]).lifting([hidden.id])
        XCTAssertTrue(lifted.items.isEmpty)
        XCTAssertEqual(lifted.rest.items.count, 1)
    }

    func testAnArrowBetweenTwoThingsThatGoGoesToo() {
        let a = node(0.2, 0.2), b = node(0.6, 0.2)
        let line = arrow(from: a.id, to: b.id)
        let lifted = Drawing(items: [.shape(a), .shape(b), .connector(line)]).lifting([a.id, b.id])
        XCTAssertEqual(Set(lifted.items.map(\.id)), [a.id, b.id, line.id])
        XCTAssertTrue(lifted.rest.items.isEmpty)
    }

    func testAnArrowWithOneEndOnSomethingThatGoesStaysAndLetsThatEndGo() throws {
        let a = node(0.2, 0.2), b = node(0.6, 0.2)
        let line = arrow(from: a.id, to: b.id)
        let lifted = Drawing(items: [.shape(a), .shape(b), .connector(line)]).lifting([a.id])
        XCTAssertEqual(lifted.items.map(\.id), [a.id])
        let kept = try XCTUnwrap(lifted.rest.items.compactMap(\.connector).first)
        XCTAssertNil(kept.startNode, "the end on the node that went is let go where it is")
        XCTAssertEqual(kept.endNode, b.id, "the other end is still on its node")
        XCTAssertEqual(kept.start, line.start, "where it was")
    }

    func testAPickedArrowGoesAndLetsGoOfEndsLeftBehind() throws {
        let a = node(0.2, 0.2), b = node(0.6, 0.2)
        let line = arrow(from: a.id, to: b.id)
        let lifted = Drawing(items: [.shape(a), .shape(b), .connector(line)]).lifting([line.id, a.id])
        let went = try XCTUnwrap(lifted.items.compactMap(\.connector).first)
        XCTAssertEqual(went.startNode, a.id)
        XCTAssertNil(went.endNode, "b stayed on the layer")
        XCTAssertEqual(lifted.rest.items.map(\.id), [b.id])
    }

    // MARK: - A new cell

    func testANewCellHoldsTheSetPadUnderItsTopWithTheXKeptOnTheColumn() throws {
        let item = stroke(0.3, 0.5)           // x 180…240, y 400…416 on the pane
        let cell = try XCTUnwrap(Docking.newCell(for: [item], from: pane, columnLeft: 28, column: 400,
                                                 lineHeight: 20))
        XCTAssertEqual(cell.width, 400)
        let size = cell.size
        let box = try XCTUnwrap(Docking.box(of: cell.drawing.items, in: size))
        XCTAssertEqual(box.minY, CGFloat(DrawingCells.pad), accuracy: 3, "the set sits pad under the cell's top")
        let original = try XCTUnwrap(Docking.box(of: [item], in: pane))
        XCTAssertEqual(box.minX, original.minX - 28, accuracy: 0.5, "x kept on the column")
        XCTAssertGreaterThanOrEqual(cell.height, Double(box.maxY + CGFloat(DrawingCells.pad)) - 0.5)
        XCTAssertGreaterThanOrEqual(cell.height, 40, "never under two lines")
    }

    func testPressuresAndIdsSurviveTheMove() throws {
        let item = stroke(0.3, 0.5)
        let cell = try XCTUnwrap(Docking.newCell(for: [item], from: pane, columnLeft: 28, column: 400,
                                                 lineHeight: 20))
        let moved = try XCTUnwrap(cell.drawing.items.first?.stroke)
        XCTAssertEqual(moved.id, item.stroke?.id)
        XCTAssertEqual(moved.pressures, item.stroke?.pressures)
        XCTAssertEqual(moved.tool, .fountain)
    }

    func testASetWiderThanTheColumnIsScaledDownToFit() throws {
        let wide = stroke(0.05, 0.4, width: 0.9)      // 540 pt wide on a 400 column
        let cell = try XCTUnwrap(Docking.newCell(for: [wide], from: pane, columnLeft: 28, column: 400,
                                                 lineHeight: 20))
        let box = try XCTUnwrap(Docking.box(of: cell.drawing.items, in: cell.size))
        XCTAssertLessThanOrEqual(box.width, 400 - 2 * CGFloat(DrawingCells.pad) + 1)
        XCTAssertGreaterThanOrEqual(box.minX, CGFloat(DrawingCells.pad) - 0.5)
        XCTAssertLessThanOrEqual(box.maxX, 400 - CGFloat(DrawingCells.pad) + 0.5)
    }

    func testASetOffTheLeftOfTheColumnIsShiftedIn() throws {
        let off = stroke(0.01, 0.4, width: 0.1)       // starts at x 6, left of the column at 28
        let cell = try XCTUnwrap(Docking.newCell(for: [off], from: pane, columnLeft: 28, column: 400,
                                                 lineHeight: 20))
        let box = try XCTUnwrap(Docking.box(of: cell.drawing.items, in: cell.size))
        XCTAssertGreaterThanOrEqual(box.minX, CGFloat(DrawingCells.pad) - 0.5)
    }

    // MARK: - Into a cell that is there

    private func frame(width: Double = 400, top: CGFloat = 300, height: CGFloat = 160) -> CellFrame {
        CellFrame(id: UUID(), line: NSRange(location: 0, length: 60),
                  rect: CGRect(x: 28, y: top, width: CGFloat(width), height: height),
                  scale: 1, width: CGFloat(width), writable: true)
    }

    func testObjectsOverTheCellKeepTheirPlaceOnScreen() throws {
        let frame = frame()
        let cell = DrawingCell(width: 400, aspect: 0.4, drawing: Drawing())
        let item = stroke(0.3, 0.42)                   // y 336…, inside the cell's 300…460
        let docked = Docking.into(cell, frame: frame, items: [item], from: pane, lineHeight: 20)
        let was = try XCTUnwrap(Docking.box(of: [item], in: pane))
        let now = try XCTUnwrap(Docking.box(of: docked.drawing.items, in: docked.size))
        XCTAssertEqual(now.minX + 28, was.minX, accuracy: 0.5)
        XCTAssertEqual(now.minY + frame.rect.minY, was.minY, accuracy: 0.5, "the place on screen is kept")
    }

    func testObjectsAwayFromTheCellGoUnderItsLowestContent() throws {
        let frame = frame()
        let held = stroke(0.1, 0.0)                   // y fraction 0: the pane's top, rehomed into the cell
        var cell = DrawingCell(width: 400, aspect: 0.4, drawing: Drawing())
        // Something already in the cell, near its top.
        cell.drawing.items = [CanvasSpace.rehome(stroke(0.1, 0.4), from: .floating(pane: pane), to: .cell(frame))]
        let lowest = try XCTUnwrap(cell.drawing.items.map { $0.bounds(in: cell.size).maxY }.max())
        let far = stroke(0.3, 0.1)                    // y 80, nowhere near the cell at 300…460
        let docked = Docking.into(cell, frame: frame, items: [far], from: pane, lineHeight: 20)
        let added = try XCTUnwrap(docked.drawing.items.last)
        XCTAssertEqual(added.bounds(in: docked.size).minY, lowest + CGFloat(DrawingCells.pad), accuracy: 3,
                       "under the lowest content, pad below it")
        _ = held
    }

    func testTheCellGrowsToHoldWhatWasDocked() {
        let frame = frame(height: 30)
        let cell = DrawingCell(width: 400, aspect: 30.0 / 400, drawing: Drawing())
        let item = stroke(0.3, 0.39)                   // y 312…, in a cell that ends at 330
        let docked = Docking.into(cell, frame: frame, items: [item], from: pane, lineHeight: 20)
        let box = Docking.box(of: docked.drawing.items, in: docked.size)
        XCTAssertGreaterThan(docked.height, 30, "ink within a line of the bottom gets paper under it")
        XCTAssertGreaterThanOrEqual(docked.height, Double(box?.maxY ?? 0))
    }

    func testIntoACellShownSmallerKeepsWidthsInTheCellsOwnPoints() throws {
        // A cell drawn at 800 in a column of 400 is shown at half size.
        let frame = CellFrame(id: UUID(), line: NSRange(location: 0, length: 60),
                              rect: CGRect(x: 28, y: 300, width: 400, height: 160), scale: 0.5, width: 800,
                              writable: true)
        let cell = DrawingCell(width: 800, aspect: 0.4, drawing: Drawing())
        let item = stroke(0.3, 0.42)
        let docked = Docking.into(cell, frame: frame, items: [item], from: pane, lineHeight: 20)
        let was = try XCTUnwrap(Docking.box(of: [item], in: pane))
        let now = try XCTUnwrap(Docking.box(of: docked.drawing.items, in: docked.size))
        XCTAssertEqual(now.width * 0.5, was.width, accuracy: 1, "the same size on screen")
    }

    // MARK: - The handles

    func testTheHandlesSitBesideTheBoxAtItsMiddle() {
        let box = CGRect(x: 100, y: 200, width: 80, height: 60)
        let sides = HandleLayout.side(box: box)
        XCTAssertEqual(sides.dock, CGPoint(x: 88, y: 230))
        XCTAssertEqual(sides.make, CGPoint(x: 192, y: 230))
    }

    func testAThinBoxDropsThemToARowUnderIt() {
        let box = CGRect(x: 100, y: 200, width: 80, height: 10)
        let sides = HandleLayout.side(box: box)
        XCTAssertEqual(sides.dock.y, 246)
        XCTAssertEqual(sides.make.y, 246)
    }
}
