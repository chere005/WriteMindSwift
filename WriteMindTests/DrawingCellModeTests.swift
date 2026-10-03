import AppKit
import CoreGraphics
import XCTest
@testable import WriteMind

// A DRAWING CELL IS STATIC, AND CLICKING INTO IT IS THE ONE WAY TO DRAW IN IT
// (Sean, 2026-10-03: "drawing cells are static unless you enter click into
// it, which forces you into a drawing mode where you can only draw in that
// cell (mouse or wacom into cell (if wacom is in write on notebook mode))
// otherwise you can select and insert like normal or page capture by
// selection from a document camera").
//
// This file holds the rules as the pure functions and the state machines the
// canvas, the store and the tablet ask — a SwiftUI drag cannot be driven from
// a test (the window is never key, and the gesture does not fire for a
// synthesized event), so what a press DOES is decided in one place that can
// be walked.

/// A cell drawn 400 wide, shown at three quarters (300 wide) at (28, 300),
/// and the pane it is on.
private let pane = CGSize(width: 800, height: 600)
private let frame = CellFrame(id: UUID(), line: NSRange(location: 20, length: 59),
                              rect: CGRect(x: 28, y: 300, width: 300, height: 90), scale: 0.75, width: 400,
                              writable: true)

final class StaticDrawingCellTests: XCTestCase {
    /// WHICH SPACE A PRESS IS IN. A cell nobody has entered is not a space at
    /// all: whatever is under the point, the press is the floating layer's.
    /// In cursor mode a drag on a cell's paper used to draw in it, and the
    /// pencil was the pointer over every cell on the page (Sean, 2026-10-03:
    /// "drawing mode seems to keep turning itself on as i'm trying to
    /// navigate").
    func testACellNobodyEnteredIsNoSpaceAtAll() {
        let floating = Stroke(colorHex: "#000000", width: 4,
                              points: [CGPoint(x: 0.05, y: 0.55), CGPoint(x: 0.5, y: 0.55)])
        let layer = Drawing(strokes: [floating])
        let inked = Stroke(colorHex: "#000000", width: 4,
                           points: [CGPoint(x: 0.25, y: 0.15), CGPoint(x: 0.3, y: 0.15)])
        let cells = [frame.id: DrawingCell(width: 400, aspect: 0.3, drawing: Drawing(strokes: [inked]))]
        func at(_ x: CGFloat, _ y: CGFloat, entered: UUID? = nil) -> (space: CanvasSpaceID, item: UUID?) {
            CanvasSpace.at(CGPoint(x: x, y: y), layer: layer, pane: pane, frames: [frame], cells: cells,
                           entered: entered)
        }
        XCTAssertEqual(at(250, 380).space, .floating, "the paper of a cell nobody entered took a press")
        XCTAssertNil(at(250, 380).item)
        XCTAssertEqual(at(103, 345).space, .floating, "nor did its ink, which is the picture's")
        XCTAssertNil(at(103, 345).item, "a cell's own stroke was picked up from outside the cell")
        XCTAssertEqual(at(200, 330).space, .floating)
        XCTAssertEqual(at(200, 330).item, floating.id, "a floating object over a static cell is still the layer's")
    }

    /// And the layer takes no press on a static cell's paper: the clicks reach
    /// the notebook, which selects, moves and inserts around a cell as it
    /// always did.
    func testTheLayerTakesNoPressOnAStaticCellsPaper() {
        var readOnly = frame
        readOnly.id = UUID()
        readOnly.writable = false
        XCTAssertEqual(CellDrawing.paperTaken(frames: [frame, readOnly], entered: nil), [],
                       "the layer took the paper of a cell nobody entered")
    }

    /// The tablet's nib in the notebook: a stroke begun over a static cell is
    /// floating ink over it, exactly as over any other part of the page. It
    /// used to go into the cell — "whatever the pen mode or tablet is doing,
    /// nothing draws into it".
    @MainActor
    func testATabletStrokeBegunOverAStaticCellFloatsOverIt() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-static-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("# Sketch\n".utf8).write(to: dir.appending(path: "Sketch.md"))
        let store = NoteStore(directory: dir)
        store.canvasSize = pane
        store.cellFrames = [frame]
        // Inside the cell: (150, 330) on the pane.
        let stroke = Stroke.starting(at: CGPoint(x: 150.0 / 800.0, y: 330.0 / 600.0), colorHex: "#1C1C1E", width: 3,
                                     pen: .pen(pressure: 0.5), tool: .pen)
        XCTAssertTrue(store.inkFromTablet(stroke))
        XCTAssertEqual(store.drawing.strokes.count, 1, "the stroke over a static cell did not float")
        XCTAssertTrue(store.cells.isEmpty, "and the cell was drawn in")
        XCTAssertEqual(store.drawingSteps, 1)
    }
}
