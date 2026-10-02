import XCTest
@testable import WriteMind

/// A stroke's pressures and tool on disk and in memory. The sidecars in
/// `~/Documents/WriteMind/.drawings` are Sean's, and `DrawingStore.load`
/// turns a decode failure into an EMPTY drawing — so an old sidecar must
/// open unchanged, a new one must round-trip, and nothing a later build
/// writes may empty a note's drawing in this one.
final class StrokeInkTests: XCTestCase {
    func testAnOldStrokeDecodesUnchangedAndIsWrittenBackTheSame() throws {
        let json = """
        {"items": [{"kind": "stroke", "stroke": {"id": "0D7B5B3C-6E44-4C2A-9E83-3C2D5A1F0A11",
          "colorHex": "#F2542D", "width": 3, "points": [[0.2, 0.3], [0.4, 0.5]],
          "transform": {"dx": 0, "dy": 0, "scale": 1, "rotation": 0}}}]}
        """
        let drawing = try JSONDecoder().decode(Drawing.self, from: Data(json.utf8))
        let stroke = try XCTUnwrap(drawing.strokes.first)
        XCTAssertNil(stroke.pressures)
        XCTAssertNil(stroke.tool)
        XCTAssertNil(stroke.inkTool, "an old stroke is the legacy line")
        XCTAssertEqual(stroke.points, [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.4, y: 0.5)])

        // Written back, it carries no key it did not have.
        let written = try JSONEncoder().encode(stroke)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["id", "colorHex", "width", "points", "transform"])
    }

    func testPressuresAndToolSurviveARoundTrip() throws {
        let stroke = Stroke(colorHex: "#1C1C1E", width: 2.5,
                            points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.15), CGPoint(x: 0.3, y: 0.3)],
                            pressures: [0.25, 0.5, 0.875], tool: .fountain)
        let drawing = Drawing(items: [.stroke(stroke)])
        let decoded = try JSONDecoder().decode(Drawing.self, from: JSONEncoder().encode(drawing))
        XCTAssertEqual(decoded, drawing)
        XCTAssertEqual(decoded.strokes.first?.pressures, [0.25, 0.5, 0.875])
        XCTAssertEqual(decoded.strokes.first?.tool, .fountain)
    }

    /// A tool added in a later build, opened in this one, is still ink —
    /// and a pressures array this build cannot read is dropped, not the
    /// note's whole drawing with it.
    func testWhatALaterBuildWritesNeverEmptiesTheDrawing() throws {
        let json = """
        {"items": [
          {"kind": "stroke", "stroke": {"colorHex": "#000000", "width": 3,
                                        "points": [[0.1, 0.1], [0.2, 0.2]], "pressures": [0.4, 0.6],
                                        "tool": "highlighter"}},
          {"kind": "stroke", "stroke": {"colorHex": "#000000", "width": 3,
                                        "points": [[0.3, 0.3]], "pressures": {"curve": "later"}}},
          {"kind": "image", "image": {"file": "page.jpg"}}
        ]}
        """
        let drawing = try JSONDecoder().decode(Drawing.self, from: Data(json.utf8))
        XCTAssertEqual(drawing.items.count, 3)
        XCTAssertEqual(drawing.strokes[0].tool, .pen)
        XCTAssertEqual(drawing.strokes[0].pressures, [0.4, 0.6])
        XCTAssertNil(drawing.strokes[1].pressures)
        XCTAssertEqual(drawing.images.first?.file, "page.jpg")
    }

    // MARK: - Lockstep

    func testAPenStrokeKeepsAPressureForEveryPoint() {
        var stroke = Stroke.starting(at: CGPoint(x: 0.1, y: 0.1), colorHex: "#000000", width: 3,
                                     pen: .pen(pressure: 0.3))
        XCTAssertEqual(stroke.tool, .pen)
        stroke.append(CGPoint(x: 0.12, y: 0.1), pen: .pen(pressure: 0.45))
        stroke.append(CGPoint(x: 0.14, y: 0.11), pen: .mouse)
        stroke.append(CGPoint(x: 0.16, y: 0.12), pen: .pen(pressure: 0.6))
        XCTAssertEqual(stroke.points.count, 4)
        XCTAssertEqual(stroke.pressures, [0.3, 0.45, 0.45, 0.6],
                       "a sample that is not the nib repeats the last pressure, so the arrays never part")
    }

    func testAMouseStrokeStaysTheLegacyLine() {
        var stroke = Stroke.starting(at: CGPoint(x: 0.1, y: 0.1), colorHex: "#000000", width: 3, pen: .mouse)
        stroke.append(CGPoint(x: 0.2, y: 0.1), pen: .mouse)
        stroke.append(CGPoint(x: 0.3, y: 0.1), pen: .pen(pressure: 0.9))
        XCTAssertNil(stroke.tool, "the first event decides, and a mouse decided")
        XCTAssertNil(stroke.pressures)
        XCTAssertEqual(stroke.points.count, 3)
    }

    /// Everything that rewrites a stroke through the item — moving it,
    /// grouping it, deleting what is beside it, copying the note — takes
    /// the whole value, so the pressures go wherever the points go.
    func testEditsThatRewriteTheItemKeepThePressures() {
        let stroke = Stroke(colorHex: "#000000", width: 3,
                            points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.3, y: 0.2)],
                            pressures: [0.2, 0.7], tool: .brush)
        var item = CanvasItem.stroke(stroke)
        item.transform = ItemTransform(dx: 0.1, dy: 0.05, scale: 1.5, rotation: 0.4)
        item.group = UUID()
        let drawing = Drawing(items: [item, .image(ImageItem(file: "x.png"))])
        let kept = drawing.removing([drawing.items[1].id])
        XCTAssertEqual(kept.strokes.first?.pressures, [0.2, 0.7])
        XCTAssertEqual(kept.strokes.first?.tool, .brush)
        XCTAssertEqual(kept.strokes.first?.points.count, kept.strokes.first?.pressures?.count)
    }
}
