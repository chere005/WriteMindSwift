import CoreGraphics
import XCTest
@testable import WriteMind

/// ONE CANVAS, SEVERAL SPACES: the floating layer measures against the pane,
/// a drawing cell against (W, W) and is shown s times that at its place on
/// the page. Every gesture works in one space, and these are the only
/// conversions between a space and the document.
final class CanvasSpaceTests: XCTestCase {
    private let pane = CGSize(width: 800, height: 600)
    /// A cell drawn 400 wide, shown at three quarters (300 wide) at (28, 300).
    private let frame = CellFrame(id: UUID(), line: NSRange(location: 20, length: 59),
                                  rect: CGRect(x: 28, y: 300, width: 300, height: 90), scale: 0.75, width: 400,
                                  writable: true)

    func testAPointGoesIntoACellAndBackOut() {
        let space = CanvasSpace.cell(frame)
        XCTAssertEqual(space.id, .cell(frame.id))
        XCTAssertEqual(space.size, CGSize(width: 400, height: 400), "geometry is asked at (W, W)")
        XCTAssertEqual(space.clip, frame.rect)
        let document = CGPoint(x: 28 + 150, y: 300 + 45)
        let local = space.fromDocument(document)
        XCTAssertEqual(local.x, 200, accuracy: 1e-9)
        XCTAssertEqual(local.y, 60, accuracy: 1e-9)
        XCTAssertEqual(space.toDocument(local).x, document.x, accuracy: 1e-9)
        XCTAssertEqual(space.toDocument(local).y, document.y, accuracy: 1e-9)
        XCTAssertEqual(space.toDocument(CGRect(x: 0, y: 0, width: 400, height: 120)), frame.rect)

        let floating = CanvasSpace.floating(pane: pane)
        XCTAssertEqual(floating.id, .floating)
        XCTAssertEqual(floating.scale, 1)
        XCTAssertNil(floating.clip)
        XCTAssertEqual(floating.fromDocument(document), document)
        XCTAssertEqual(floating.toDocument(document), document)
    }

    /// Which space a press is in: a FLOATING object under the point first —
    /// the layer is on top of the page — else a writable cell holding the
    /// point, with its object or its paper; else the floating layer. A
    /// read-only cell is no space, and a folded cell has no frame at all.
    func testAFloatingObjectBeatsACellAndACellsObjectBeatsItsPaper() {
        // A floating stroke across the cell, at y = 330 on the page.
        let floating = Stroke(colorHex: "#000000", width: 4,
                              points: [CGPoint(x: 0.05, y: 0.55), CGPoint(x: 0.5, y: 0.55)])
        let layer = Drawing(strokes: [floating])
        // A stroke in the cell, in fractions of W: from (100, 60) to (120, 60)
        // in cell points — on the page (103, 345) to (118, 345).
        let inked = Stroke(colorHex: "#000000", width: 4,
                           points: [CGPoint(x: 0.25, y: 0.15), CGPoint(x: 0.3, y: 0.15)])
        let cells = [frame.id: DrawingCell(width: 400, aspect: 0.3, drawing: Drawing(strokes: [inked]))]
        func at(_ x: CGFloat, _ y: CGFloat, frames: [CellFrame]) -> (space: CanvasSpaceID, item: UUID?) {
            CanvasSpace.at(CGPoint(x: x, y: y), layer: layer, pane: pane, frames: frames, cells: cells)
        }

        let onFloating = at(200, 330, frames: [frame])
        XCTAssertEqual(onFloating.space, .floating, "the layer is on top of the page")
        XCTAssertEqual(onFloating.item, floating.id)

        let onInk = at(103, 345, frames: [frame])
        XCTAssertEqual(onInk.space, .cell(frame.id))
        XCTAssertEqual(onInk.item, inked.id, "the cell's own object")

        let onPaper = at(250, 380, frames: [frame])
        XCTAssertEqual(onPaper.space, .cell(frame.id))
        XCTAssertNil(onPaper.item, "the paper")

        let off = at(600, 100, frames: [frame])
        XCTAssertEqual(off.space, .floating)
        XCTAssertNil(off.item)

        var readOnly = frame
        readOnly.writable = false
        XCTAssertEqual(at(250, 380, frames: [readOnly]).space, .floating, "nothing is drawn in a read-only cell")
        XCTAssertEqual(at(250, 380, frames: []).space, .floating, "a folded cell has no frame and is never picked")
    }

    /// AN OBJECT MOVED BETWEEN SPACES STAYS WHERE IT WAS ON THE PAGE: every
    /// kind, every normalised field, outlines equal in document points; ids,
    /// groups, pressures and tools kept as they are (the lockstep rule); the
    /// widths in points scaled by from.scale ÷ to.scale, so a line is the
    /// same width on screen in either space.
    func testAnObjectMovedBetweenSpacesStaysWhereItWasOnThePage() {
        let floating = CanvasSpace.floating(pane: pane)
        let cell = CanvasSpace.cell(frame)
        let group = UUID()
        let node = ShapeItem(kind: .rectangle, center: CGPoint(x: 0.1, y: 0.58), width: 0.08, colorHex: "#2D7DD2",
                             lineWidth: 3, fillHex: "#FFFFFF", label: "Start", group: group)
        let box = ShapeItem(kind: .text, center: CGPoint(x: 0.3, y: 0.6), width: 0.1, colorHex: "#000000",
                            label: "a text box\nof two lines")
        let mark = ShapeItem(kind: .check, center: CGPoint(x: 0.2, y: 0.55), width: 0.03, colorHex: "#34C759",
                             transform: ItemTransform(dx: 0.01, dy: -0.02, scale: 1.5, rotation: 0.3))
        let items: [CanvasItem] = [
            .stroke(Stroke(colorHex: "#1C1C1E", width: 3,
                           points: [CGPoint(x: 0.1, y: 0.55), CGPoint(x: 0.2, y: 0.6), CGPoint(x: 0.3, y: 0.58)],
                           transform: ItemTransform(dx: 0.02, dy: 0.01, scale: 1.2, rotation: -0.2), group: group,
                           pressures: [0.2, 0.5, 0.9], tool: .fountain)),
            .stroke(Stroke(colorHex: "#FF3B30", width: 2,
                           points: [CGPoint(x: 0.1, y: 0.6), CGPoint(x: 0.3, y: 0.61)])),
            .shape(node), .shape(box), .shape(mark),
            .connector(ConnectorItem(start: CGPoint(x: 0.12, y: 0.56), end: CGPoint(x: 0.3, y: 0.62),
                                     startHead: .none, endHead: .arrow, line: .dashed, colorHex: "#000000",
                                     lineWidth: 2, bends: [CGPoint(x: 0.2, y: 0.56), CGPoint(x: 0.2, y: 0.62)],
                                     overrides: [.init(index: 1, vertical: true, value: 0.21)])),
            .image(ImageItem(file: "A.png", center: CGPoint(x: 0.25, y: 0.6), width: 0.1, aspect: 0.75)),
        ]
        for item in items {
            let moved = CanvasSpace.rehome(item, from: floating, to: cell)
            XCTAssertEqual(moved.id, item.id)
            XCTAssertEqual(moved.group, item.group)
            let before = item.outline(in: floating.size)
            let after = moved.outline(in: cell.size).map { cell.toDocument($0) }
            XCTAssertEqual(before.count, after.count, "\(item.id)")
            for (a, b) in zip(before, after) {
                XCTAssertEqual(a.x, b.x, accuracy: 0.01, "\(item.id)")
                XCTAssertEqual(a.y, b.y, accuracy: 0.01, "\(item.id)")
            }
            // And back out, to where it started.
            let back = CanvasSpace.rehome(moved, from: cell, to: floating)
            for (a, b) in zip(before, back.outline(in: floating.size)) {
                XCTAssertEqual(a.x, b.x, accuracy: 0.01)
                XCTAssertEqual(a.y, b.y, accuracy: 0.01)
            }
            XCTAssertEqual(back.transform.scale, item.transform.scale, accuracy: 1e-9)
            XCTAssertEqual(back.transform.rotation, item.transform.rotation, accuracy: 1e-9)
        }

        // The widths: ÷ s, so the same on screen. The lockstep rule: the
        // pressures are the very array, the tool the same tool.
        guard case .stroke(let ink) = CanvasSpace.rehome(items[0], from: floating, to: cell) else { return XCTFail() }
        XCTAssertEqual(ink.width, 3 / 0.75, accuracy: 1e-9)
        XCTAssertEqual(ink.pressures, [0.2, 0.5, 0.9])
        XCTAssertEqual(ink.tool, .fountain)
        XCTAssertEqual(ink.points.count, 3)
        guard case .stroke(let legacy) = CanvasSpace.rehome(items[1], from: floating, to: cell) else { return XCTFail() }
        XCTAssertNil(legacy.pressures, "a legacy stroke stays one")
        XCTAssertNil(legacy.tool)
        guard case .shape(let shape) = CanvasSpace.rehome(items[2], from: floating, to: cell) else { return XCTFail() }
        XCTAssertEqual(shape.lineWidth, 3 / 0.75, accuracy: 1e-9)
        XCTAssertEqual(shape.label, "Start")
        XCTAssertEqual(shape.fillHex, "#FFFFFF")
        guard case .connector(let arrow) = CanvasSpace.rehome(items[5], from: floating, to: cell) else { return XCTFail() }
        XCTAssertEqual(arrow.lineWidth, 2 / 0.75, accuracy: 1e-9)
        XCTAssertEqual(arrow.line, .dashed)
        XCTAssertEqual(arrow.endHead, .arrow)
        XCTAssertEqual(arrow.overrides.count, 1)
    }

    /// Frames are told only when one has moved by more than half a point,
    /// or a cell came, went or changed what it is.
    func testFramesAreToldOnlyWhenOneHasMoved() {
        var nudged = frame
        nudged.rect.origin.y += 0.4
        XCTAssertFalse(CellFrame.moved([frame], [nudged]), "under half a point is the same frame")
        nudged.rect.origin.y += 0.2
        XCTAssertTrue(CellFrame.moved([frame], [nudged]))
        var taller = frame
        taller.rect.size.height += 1
        XCTAssertTrue(CellFrame.moved([frame], [taller]))
        var readOnly = frame
        readOnly.writable = false
        XCTAssertTrue(CellFrame.moved([frame], [readOnly]), "what may be done with it changed")
        XCTAssertTrue(CellFrame.moved([frame], []), "a cell went")
        XCTAssertTrue(CellFrame.moved([], [frame]), "a cell came")
        XCTAssertFalse(CellFrame.moved([frame], [frame]))
        XCTAssertFalse(CellFrame.moved([], []))
    }
}
