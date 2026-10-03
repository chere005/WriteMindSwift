import Combine
import XCTest
@testable import WriteMind

/// THE PEN'S LOWER SWITCH, HELD, IS AN ERASER THAT DELETES WHOLE STROKES
/// (Sean, 2026-10-03: "the undo button on the wacom pen should actually be a
/// press and hold to make it an eraser that deletes entire strokes").
final class TabletEraserTests: XCTestCase {
    // MARK: - The geometry

    func testTheNibsPathAgainstAStrokesPolyline() {
        let stroke = [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.6, y: 0.5)]
        XCTAssertTrue(StrokeEraser.touches(stroke, from: CGPoint(x: 0.4, y: 0.4), to: CGPoint(x: 0.4, y: 0.6),
                                           radius: 0.01), "crossing it")
        XCTAssertTrue(StrokeEraser.touches(stroke, from: CGPoint(x: 0.4, y: 0.505), to: CGPoint(x: 0.4, y: 0.505),
                                           radius: 0.01), "a point beside it, within the radius")
        XCTAssertFalse(StrokeEraser.touches(stroke, from: CGPoint(x: 0.4, y: 0.6), to: CGPoint(x: 0.5, y: 0.6),
                                            radius: 0.01), "a path beside it")
        XCTAssertFalse(StrokeEraser.touches(stroke, from: CGPoint(x: 0.7, y: 0.5), to: CGPoint(x: 0.9, y: 0.5),
                                            radius: 0.01), "past its end")
        XCTAssertTrue(StrokeEraser.touches(stroke, from: CGPoint(x: 0.1, y: 0.5), to: CGPoint(x: 0.9, y: 0.5),
                                           radius: 0.01), "along it, and over it")
    }

    func testADotIsErasedByAPathNearIt() {
        let dot = [CGPoint(x: 0.5, y: 0.5)]
        XCTAssertTrue(StrokeEraser.touches(dot, from: CGPoint(x: 0.4, y: 0.5), to: CGPoint(x: 0.6, y: 0.5), radius: 0.01))
        XCTAssertFalse(StrokeEraser.touches(dot, from: CGPoint(x: 0.4, y: 0.6), to: CGPoint(x: 0.6, y: 0.6), radius: 0.01))
        XCTAssertFalse(StrokeEraser.touches([], from: .zero, to: .zero, radius: 1), "nothing is never touched")
    }

    // MARK: - On the page

    private func sample(_ x: Double, _ y: Double, _ phase: TabletSample.Phase, eraser: Bool = true) -> TabletSample {
        TabletSample(page: CGPoint(x: x, y: y), pressure: phase == .up ? 0 : 0.5, phase: phase, sideSwitch: false,
                     inProximity: true, timestamp: 0, eraser: eraser)
    }

    func testTheEraserIsAPathAndNeverInkOrABox() {
        var writing = TabletWriting()
        let ink = TabletInk(colorHex: "#000000", width: 3)
        XCTAssertEqual(writing.consume(sample(0.2, 0.3, .down), ink: ink),
                       .erasing(from: CGPoint(x: 0.2, y: 0.3), to: CGPoint(x: 0.2, y: 0.3)))
        XCTAssertEqual(writing.consume(sample(0.4, 0.3, .drag), ink: ink),
                       .erasing(from: CGPoint(x: 0.2, y: 0.3), to: CGPoint(x: 0.4, y: 0.3)))
        XCTAssertEqual(writing.consume(sample(0.6, 0.3, .drag), ink: ink),
                       .erasing(from: CGPoint(x: 0.4, y: 0.3), to: CGPoint(x: 0.6, y: 0.3)))
        XCTAssertEqual(writing.consume(sample(0.6, 0.3, .up), ink: ink), .erased)
        XCTAssertNil(writing.stroke, "an eraser leaves no ink")
    }

    @MainActor
    func testErasingTakesTheStrokesItTouchesWholeAsOneStepBack() {
        let page = TabletPage(url: nil)
        func stroke(_ y: Double) -> Stroke {
            Stroke(colorHex: "#000000", width: 3, points: [CGPoint(x: 0.2, y: y), CGPoint(x: 0.8, y: y)])
        }
        let high = stroke(0.2), middle = stroke(0.5), low = stroke(0.8)
        [high, middle, low].forEach { page.commit($0) }
        let before = page.history.count

        // A path down across the first two.
        XCTAssertTrue(page.erase(from: CGPoint(x: 0.5, y: 0.1), to: CGPoint(x: 0.5, y: 0.3), radius: StrokeEraser.pageRadius))
        XCTAssertEqual(page.strokes.map(\.id), [middle.id, low.id])
        XCTAssertTrue(page.erase(from: CGPoint(x: 0.5, y: 0.3), to: CGPoint(x: 0.5, y: 0.6), radius: StrokeEraser.pageRadius))
        XCTAssertEqual(page.strokes.map(\.id), [low.id], "whole strokes, and the nib still down")
        XCTAssertFalse(page.erase(from: CGPoint(x: 0.5, y: 0.6), to: CGPoint(x: 0.5, y: 0.65), radius: StrokeEraser.pageRadius),
                       "over nothing, it does nothing")
        page.endErasing()
        XCTAssertEqual(page.history.count, before + 1, "one erasure is one step")

        XCTAssertTrue(page.undo())
        XCTAssertEqual(page.strokes.map(\.id), [high.id, middle.id, low.id], "one ⌘Z brings them all back")

        // The next erasure is a step of its own.
        page.erase(from: CGPoint(x: 0.5, y: 0.75), to: CGPoint(x: 0.5, y: 0.85), radius: StrokeEraser.pageRadius)
        page.endErasing()
        page.erase(from: CGPoint(x: 0.5, y: 0.45), to: CGPoint(x: 0.5, y: 0.55), radius: StrokeEraser.pageRadius)
        page.endErasing()
        XCTAssertEqual(page.strokes.map(\.id), [high.id])
        XCTAssertTrue(page.undo())
        XCTAssertEqual(page.strokes.map(\.id), [high.id, middle.id])
    }

    @MainActor
    func testTheScribeErasesOnThePageAndClaimsCommandZ() {
        let page = TabletPage(url: nil)
        let scribe = TabletScribe(page: page, input: nil)
        var wrote = 0
        scribe.onWrite = { wrote += 1 }
        let line = Stroke(colorHex: "#000000", width: 3, points: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)])
        page.commit(line)
        scribe.consume(sample(0.5, 0.4, .down))
        scribe.consume(sample(0.5, 0.6, .drag))
        scribe.consume(sample(0.5, 0.6, .up))
        XCTAssertTrue(page.strokes.isEmpty)
        XCTAssertGreaterThan(wrote, 0, "⌘Z is the page's")
        XCTAssertNil(scribe.stroke)
    }

    // MARK: - Over the notes

    func testTheNotebookEraserIsAPathInDocumentPoints() {
        var writing = NotebookWriting()
        let place = NotebookPlace(pane: CGSize(width: 800, height: 600), scroll: 100, aspect: 1.0)
        let ink = TabletInk(colorHex: "#000000", width: 3)
        let first = writing.consume(sample(0.5, 0.5, .down), at: place, ink: ink)
        let start = place.inDocument(CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(first, .erasing(from: start, to: start))
        let next = place.inDocument(CGPoint(x: 0.6, y: 0.5))
        XCTAssertEqual(writing.consume(sample(0.6, 0.5, .drag), at: place, ink: ink), .erasing(from: start, to: next))
        XCTAssertEqual(writing.consume(sample(0.6, 0.5, .up), at: place, ink: ink), .erased)
        XCTAssertNil(writing.stroke)
    }

    @MainActor
    func testTheNotebookScribeSendsTheErasure() {
        let scribe = NotebookScribe()
        scribe.place = NotebookPlace(pane: CGSize(width: 800, height: 600), scroll: 0, aspect: 1.0)
        var got: [NotebookErase] = []
        let watching = scribe.erases.sink { got.append($0) }
        defer { watching.cancel() }
        scribe.consume(sample(0.5, 0.5, .down))
        scribe.consume(sample(0.5, 0.6, .drag))
        scribe.consume(sample(0.5, 0.6, .up))
        XCTAssertEqual(got.count, 3)
        XCTAssertEqual(got.last, .end)
        if case .path = got.first {} else { XCTFail("the first is a path") }
    }
}

/// The marker says what the pen will be: held in the air, and for the stroke.
final class TabletMarkerModeTests: XCTestCase {
    private func hover(holding: PenSwitch? = nil, eraser: Bool = false, box: Bool = false) -> TabletSample {
        TabletSample(page: .zero, pressure: 0, phase: holding == nil && !eraser && !box ? .hover : .drag,
                     sideSwitch: box, inProximity: true, timestamp: 0, eraser: eraser, holding: holding)
    }

    func testTheMarkerSaysInkEraserOrBox() {
        XCTAssertEqual(TabletHoverMarker.mode(of: hover()), .ink)
        XCTAssertEqual(TabletHoverMarker.mode(of: hover(holding: .lower)), .eraser, "held in the air")
        XCTAssertEqual(TabletHoverMarker.mode(of: hover(holding: .upper)), .box)
        XCTAssertEqual(TabletHoverMarker.mode(of: hover(eraser: true)), .eraser, "latched for the stroke")
        XCTAssertEqual(TabletHoverMarker.mode(of: hover(box: true)), .box)
    }

    func testAHoverCarriesTheSwitchHeldInTheAir() {
        var pen = TabletPen()
        var extent = TabletExtent(width: 15200, height: 9500)
        func feed(_ lower: Bool, _ time: TimeInterval) -> [TabletSample] {
            pen.consume(TabletReading(kind: .point(counts: CGPoint(x: 7600, y: 4750), tip: false,
                                                   switches: lower ? [.lower] : [], pressure: 0, buttons: 0),
                                      timestamp: time, native: false), extent: &extent, quarterTurns: 1)
        }
        XCTAssertNil(feed(false, 1).first?.holding)
        XCTAssertEqual(feed(true, 2).first?.holding, .lower, "pressed in the air: the marker can say eraser")
        XCTAssertNil(feed(false, 3).first?.holding, "let go")
    }
}
