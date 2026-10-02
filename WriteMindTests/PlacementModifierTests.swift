import AppKit
import XCTest
@testable import WriteMind

/// The two keys held during a placement (Sean, 2026-09-21: "when placing a
/// marker, if i hold cmd, stay in adding that marker mode.. if i hold
/// shift, the direction elements become fixed to horizontal or vertical
/// axes"), and what stays armed once something is down.
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
    /// mode..". A node or a line is DRAWN, corner to corner or press to
    /// release, and the next drag draws the next one — no key held.
    func testADrawnShapeOrLineStaysArmedWithNoKeyHeld() {
        for kind in ShapeItem.Kind.allCases where kind.isNode {
            XCTAssertTrue(CanvasPlacement.shape(kind).staysArmed([]), "\(kind.title) went back to the palette")
            XCTAssertTrue(CanvasPlacement.shape(kind).staysArmed(.command), "⌘ changes nothing for \(kind.title)")
        }
        for line in lines {
            XCTAssertTrue(line.staysArmed([]), "\(line.title) went back to the palette")
            XCTAssertTrue(line.staysArmed(.shift), "a row of flat \(line.title)s, one after another")
        }
    }

    /// A MARK IS STILL ONE CLICK, and ⌘ still keeps it (Sean, 2026-09-21:
    /// "when placing a marker, if i hold cmd, stay in adding that marker
    /// mode") — the words ask for ⌘ to keep it, so without ⌘ it goes.
    func testAMarkIsOneClickAndCommandKeepsIt() {
        for kind in ShapeItem.Kind.allCases where !kind.isNode {
            let mark = CanvasPlacement.shape(kind)
            XCTAssertFalse(mark.staysArmed([]), "\(kind.title) is a stamp beside a word, put down once")
            XCTAssertTrue(mark.staysArmed(.command), "⌘ keeps \(kind.title) for a row of them")
            XCTAssertTrue(mark.staysArmed([.command, .shift]))
            XCTAssertFalse(mark.staysArmed(.shift))
            XCTAssertFalse(mark.staysArmed(.option))
        }
    }

    /// The pane takes every drag while a shape is armed, so the footer
    /// says what has it and how to put it away; a mark goes back on its
    /// own, and its line says where it goes.
    func testTheFooterSaysWhatTakesTheDragsAndHowToPutItAway() {
        for placement in ShapeItem.Kind.allCases.map(CanvasPlacement.shape) + lines {
            let line = placement.footer
            XCTAssertTrue(line.hasPrefix(placement.title), "\(line) names \(placement.title)")
            if placement.staysArmed([]) {
                XCTAssertTrue(line.contains("every drag"), "\(line) says the pane is the tool's")
                XCTAssertTrue(line.contains("Esc"), "\(line) says how to put it away")
            } else {
                XCTAssertFalse(line.contains("every drag"), "\(line) promises a second mark")
                XCTAssertTrue(line.contains("click where it goes"), line)
            }
        }
    }
}
