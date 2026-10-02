import SwiftUI
import XCTest
@testable import WriteMind

/// THE LEGACY LINE IS PINNED. Every stroke drawn before 2026-10-02 has no
/// tool and no pressures, and is drawn by the code that drew it then — a
/// smoothed line of one width. These numbers were taken from that code
/// before ink existed; if one of them moves, a change has restyled
/// drawings already sitting in Sean's notes, and that is the change to
/// undo, not the test.
final class InkPathsTests: XCTestCase {
    private func elements(_ path: Path) -> [Path.Element] {
        var out: [Path.Element] = []
        path.forEach { out.append($0) }
        return out
    }

    private let legacy = Stroke(colorHex: "#2D7DD2", width: 3, points: [])

    func testTheLegacyLineIsQuadraticsThroughTheMidpoints() {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 15), CGPoint(x: 35, y: 12),
                      CGPoint(x: 50, y: 30), CGPoint(x: 52, y: 48)]
        let (path, filled) = InkPaths.path(for: legacy, points: points)
        XCTAssertFalse(filled, "a legacy line is stroked at the stroke's width, not filled")
        XCTAssertEqual(elements(path), [
            .move(to: CGPoint(x: 10, y: 10)),
            .quadCurve(to: CGPoint(x: 27.5, y: 13.5), control: CGPoint(x: 20, y: 15)),
            .quadCurve(to: CGPoint(x: 42.5, y: 21), control: CGPoint(x: 35, y: 12)),
            .quadCurve(to: CGPoint(x: 51, y: 39), control: CGPoint(x: 50, y: 30)),
            .line(to: CGPoint(x: 52, y: 48))
        ])
    }

    func testTheLegacyTwoPointLineAndDot() {
        let (line, lineFilled) = InkPaths.path(for: legacy, points: [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 40)])
        XCTAssertFalse(lineFilled)
        XCTAssertEqual(elements(line), [.move(to: .zero), .line(to: CGPoint(x: 30, y: 40))])

        let (dot, dotFilled) = InkPaths.path(for: legacy, points: [CGPoint(x: 10, y: 10)])
        XCTAssertTrue(dotFilled, "a pen that went down and did not move is a filled dot")
        XCTAssertEqual(dot, Path(ellipseIn: CGRect(x: 8.5, y: 8.5, width: 3, height: 3)))

        let (nothing, nothingFilled) = InkPaths.path(for: legacy, points: [])
        XCTAssertTrue(nothing.isEmpty)
        XCTAssertFalse(nothingFilled)
    }

    /// The box, the hit test and the pane's hit shape all read the legacy
    /// stroke's half-width exactly as before.
    func testTheLegacyStrokesBoxAndReachAreUnchanged() {
        XCTAssertNil(legacy.inkTool)
        XCTAssertEqual(legacy.reach, 1.5)
        let size = CGSize(width: 200, height: 100)
        let slanted = CanvasItem.stroke(Stroke(colorHex: "#000000", width: 4,
                                               points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.5, y: 0.6)]))
        XCTAssertEqual(slanted.baseBounds(in: size), CGRect(x: 18, y: 18, width: 84, height: 44))
        // Six points is the floor; a 4-point line reaches 2 either side,
        // so the floor wins — and a fat one reaches half its width.
        let thin = CanvasItem.stroke(Stroke(colorHex: "#000000", width: 4,
                                            points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.5, y: 0.5)]))
        XCTAssertTrue(thin.hitTest(CGPoint(x: 60, y: 55.9), in: size))
        XCTAssertFalse(thin.hitTest(CGPoint(x: 60, y: 56.1), in: size))
        let fat = CanvasItem.stroke(Stroke(colorHex: "#000000", width: 20,
                                           points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.5, y: 0.5)]))
        XCTAssertTrue(fat.hitTest(CGPoint(x: 60, y: 59.9), in: size))
        XCTAssertFalse(fat.hitTest(CGPoint(x: 60, y: 60.1), in: size))
    }

    // MARK: - Ink

    func testAStrokeWithAToolIsAFilledOutline() {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 14), CGPoint(x: 50, y: 30), CGPoint(x: 60, y: 60)]
        let ink = Stroke(colorHex: "#000000", width: 3, points: [], pressures: [0.3, 0.5, 0.6, 0.4], tool: .pen)
        let (path, filled) = InkPaths.path(for: ink, points: points)
        XCTAssertTrue(filled, "ink is one outline, filled")
        XCTAssertFalse(path.isEmpty)
        let box = path.boundingRect
        let reach = ink.reach
        XCTAssertGreaterThanOrEqual(box.minX, 10 - reach - 0.5)
        XCTAssertLessThanOrEqual(box.maxX, 60 + reach + 0.5)
        XCTAssertLessThanOrEqual(box.maxY, 60 + reach + 0.5)
        XCTAssertGreaterThan(box.height, 45, "it runs the length of the samples")
    }

    /// Pressures with no tool is still ink — the pen's — and a tool with
    /// no pressures is ink whose pressure is guessed from speed.
    func testEitherFieldMakesItInk() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 40, y: 5)]
        let pressuresOnly = Stroke(colorHex: "#000000", width: 3, points: [], pressures: [0.5, 0.5, 0.5])
        XCTAssertEqual(pressuresOnly.inkTool, .pen)
        XCTAssertTrue(InkPaths.path(for: pressuresOnly, points: points).filled)
        let toolOnly = Stroke(colorHex: "#000000", width: 3, points: [], tool: .marker)
        XCTAssertEqual(toolOnly.inkTool, .marker)
        XCTAssertTrue(InkPaths.path(for: toolOnly, points: points).filled)
        XCTAssertFalse(InkPaths.path(for: toolOnly, points: points).path.isEmpty)
    }

    /// The arrays are kept in lockstep; if one ever is not, the ink is
    /// still drawn, the missing pressures taken as "none reported".
    func testPressuresShorterThanThePointsStillDraw() {
        let points = (0..<20).map { CGPoint(x: Double($0) * 4, y: 10 + sin(Double($0)) * 3) }
        let ragged = Stroke(colorHex: "#000000", width: 3, points: [], pressures: [0.4, 0.5], tool: .pen)
        let (path, filled) = InkPaths.path(for: ragged, points: points)
        XCTAssertTrue(filled)
        XCTAssertFalse(path.isEmpty)
    }

    /// Finished ink is outlined once; a stroke that grew, a pane that
    /// changed size, a different stroke are each outlined again — and
    /// what comes out of the cache is what the outline would have been.
    func testInkIsOutlinedOnceAndAgainWhenItsSamplesChange() {
        let cache = InkCache()
        var made = 0
        func outline(_ stroke: Stroke, _ points: [CGPoint]) -> Path {
            cache.path(for: stroke, tool: .pen, points: points) {
                made += 1
                return InkPaths.ink(for: stroke, tool: .pen, points: points)
            }
        }
        let stroke = Stroke(colorHex: "#000000", width: 3, points: [], pressures: [0.5, 0.6, 0.7], tool: .pen)
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 5)]
        let once = outline(stroke, points)
        XCTAssertEqual(outline(stroke, points), once)
        XCTAssertEqual(made, 1, "a redraw re-outlined finished ink")
        XCTAssertEqual(once, InkPaths.ink(for: stroke, tool: .pen, points: points))

        var grown = stroke
        grown.append(CGPoint(x: 0.5, y: 0.5), pen: .pen(pressure: 0.8))
        _ = outline(grown, points + [CGPoint(x: 30, y: 9)])
        XCTAssertEqual(made, 2, "the live stroke grew")
        _ = outline(grown, (points + [CGPoint(x: 30, y: 9)]).map { CGPoint(x: $0.x * 2, y: $0.y * 2) })
        XCTAssertEqual(made, 3, "the pane changed size")
        let other = Stroke(colorHex: "#000000", width: 3, points: [], pressures: [0.5, 0.6, 0.7], tool: .pen)
        _ = outline(other, points)
        XCTAssertEqual(made, 4)
        XCTAssertEqual(cache.count, 2, "one slot per stroke, however often it grew")
    }

    // MARK: - Both painters

    /// How much of the colour a stroke lays down where it is thickest, on
    /// SCREEN (`DrawingCanvas.draw`, through a SwiftUI Canvas) and on
    /// PAPER (`DrawingInk.draw`, into Core Graphics), 0…1. A transparent
    /// page, so what is read back is the ink's own alpha.
    @MainActor
    private func coverage(of stroke: Stroke) throws -> (screen: Double, paper: Double) {
        let pane = CGSize(width: 200, height: 100)
        let item = CanvasItem.stroke(stroke)
        let points = item.basePoints(in: pane)
        func alpha(at point: CGPoint, of image: CGImage) -> Double {
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return Double(pixels[(Int(point.y) * width + Int(point.x)) * 4 + 3]) / 255
        }
        let renderer = ImageRenderer(content: Canvas { context, _ in
            DrawingCanvas.draw(stroke, points: points, in: &context)
        }.frame(width: pane.width, height: pane.height))
        renderer.scale = 1
        let screen = try XCTUnwrap(renderer.cgImage)

        let paper = try XCTUnwrap(CGContext(data: nil, width: Int(pane.width), height: Int(pane.height),
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        DrawingInk.draw(item, in: paper, size: pane, media: nil)
        let printed = try XCTUnwrap(paper.makeImage())
        let middle = CGPoint(x: 100, y: 50)
        return (alpha(at: middle, of: screen), alpha(at: middle, of: printed))
    }

    /// A pencil is graphite, not ink: it goes down at its tool's opacity,
    /// the SAME on screen and on paper, and a pen goes down solid on both.
    /// The paper painter has its own branch for ink, and nothing else
    /// would notice it losing the opacity.
    @MainActor
    func testInkGoesDownAtItsToolsOpacityOnScreenAndOnPaper() throws {
        let across = (0...40).map { CGPoint(x: 0.1 + 0.8 * Double($0) / 40, y: 0.5) }
        for tool in [InkTool.pencil, .pen] {
            let stroke = Stroke(colorHex: "#000000", width: 20, points: across,
                                pressures: across.map { _ in 0.5 }, tool: tool)
            let (screen, paper) = try coverage(of: stroke)
            XCTAssertEqual(screen, tool.opacity, accuracy: 0.02, "\(tool) on screen")
            XCTAssertEqual(paper, tool.opacity, accuracy: 0.02, "\(tool) on paper")
        }
        XCTAssertLessThan(InkTool.pencil.opacity, 0.9, "the pencil has to be told apart from the pen")
    }

    /// The ink is drawn from base points in view space, so it scales and
    /// turns with the item's transform like any other object — and the
    /// stroke's box holds the outline.
    func testTheBoxHoldsTheInk() {
        let ink = Stroke(colorHex: "#000000", width: 6, points: [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.3, y: 0.25),
                                                                  CGPoint(x: 0.5, y: 0.5)],
                         pressures: [1, 1, 1], tool: .brush)
        let item = CanvasItem.stroke(ink)
        let size = CGSize(width: 400, height: 300)
        let drawn = InkPaths.path(for: ink, points: item.basePoints(in: size)).path.boundingRect
        let box = item.baseBounds(in: size)
        XCTAssertTrue(box.insetBy(dx: -1, dy: -1).contains(drawn), "\(drawn) spills out of \(box)")
    }
}
