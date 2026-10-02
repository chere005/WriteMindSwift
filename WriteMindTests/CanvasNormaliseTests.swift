import XCTest
@testable import WriteMind

/// A point drawn on the layer is kept as a fraction of the pane measured
/// from the DOCUMENT's top, because the layer scrolls with the text — so a
/// stroke a screen and a half down a note is at y 1.5, not at the bottom
/// edge of the first screen. The clamp to 0…1 was written before the layer
/// scrolled, and flattened everything drawn further down a long note onto
/// one line (found 2026-10-02, while the tablet was given the notebook).
final class CanvasNormaliseTests: XCTestCase {
    private let pane = CGSize(width: 400, height: 300)

    func testAPointBelowTheFirstScreenKeepsItsPlaceInTheDocument() {
        let point = DrawingCanvas.normalise(CGPoint(x: 100, y: 450), in: pane)
        XCTAssertEqual(point.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(point.y, 1.5, accuracy: 1e-9, "a screen and a half down is 1.5, not the bottom of the first screen")
    }

    func testTwoPointsFurtherDownStayApart() {
        let a = DrawingCanvas.normalise(CGPoint(x: 100, y: 900), in: pane)
        let b = DrawingCanvas.normalise(CGPoint(x: 100, y: 960), in: pane)
        XCTAssertNotEqual(a.y, b.y, "a stroke down a long note must not collapse onto one line")
    }

    func testThePaneStillHoldsTheSidesAndTheTop() {
        let left = DrawingCanvas.normalise(CGPoint(x: -20, y: -5), in: pane)
        XCTAssertEqual(left, CGPoint(x: 0, y: 0), "nothing above the document's top or off its sides")
        let right = DrawingCanvas.normalise(CGPoint(x: 420, y: 10), in: pane)
        XCTAssertEqual(right.x, 1, accuracy: 1e-9)
    }
}
