import SwiftUI
import XCTest
@testable import WriteMind

/// The tools: each one a different pressure response, taper and opacity,
/// and every one of them still honest about the width the slider says.
final class InkToolTests: XCTestCase {
    /// A straight line along y = 50, `length` points long, one pressure.
    private func line(_ pressure: Double?, length: Double = 300, count: Int = 61) -> [CGPoint] {
        (0..<count).map { CGPoint(x: Double($0) * length / Double(count - 1), y: 50) }
    }

    private func outline(_ tool: InkTool, width: Double, pressure: Double?, length: Double = 300) -> [CGPoint] {
        let points = line(pressure, length: length)
        let samples = points.map { InkOutline.Sample($0, pressure: pressure) }
        return InkOutline.stroke(samples, options: tool.options(width: width, simulated: pressure == nil,
                                                                 length: length))
    }

    /// How wide the outline is where it crosses x.
    private func width(of outline: [CGPoint], atX x: Double) -> Double {
        var ys: [Double] = []
        for index in outline.indices {
            let a = outline[index], b = outline[(index + 1) % outline.count]
            guard (a.x - x) * (b.x - x) <= 0, a.x != b.x else { continue }
            ys.append(a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x))
        }
        guard let low = ys.min(), let high = ys.max() else { return 0 }
        return high - low
    }

    func testEveryToolIsItsNibWideAtTheMiddlePressure() {
        for tool in InkTool.allCases {
            let measured = width(of: outline(tool, width: 3, pressure: 0.5), atX: 150)
            XCTAssertEqual(measured, tool.nibWidth(width: 3), accuracy: tool.nibWidth(width: 3) * 0.08,
                           "\(tool): the slider's width is the width at an ordinary press")
        }
        XCTAssertEqual(InkTool.pen.nibWidth(width: 3), 3, "the pen's nib IS the stroke's width")
    }

    /// Handwriting at 2–4 points: pressure shows, but a ballpoint is not a
    /// brush — a hard press is under twice a light one.
    func testThePenIsFirmAndOnlySlightlyThinned() {
        let light = width(of: outline(.pen, width: 3, pressure: 0.1), atX: 150)
        let hard = width(of: outline(.pen, width: 3, pressure: 0.9), atX: 150)
        XCTAssertGreaterThan(hard, light * 1.3, "pressure has to show")
        XCTAssertLessThan(hard, light * 2, "a ballpoint, not a brush")
        XCTAssertGreaterThan(light, 3 * 0.6, "a light touch still writes")
        let profile = InkTool.pen.profile
        XCTAssertTrue((0.3...0.45).contains(profile.streamline), "the ink stays under the nib")
        XCTAssertEqual(profile.opacity, 1)
    }

    /// A ballpoint's line is ROUND where it starts and where it stops —
    /// the first cut tapered the pen in and out, and every letter came to
    /// a point at both ends like a brush's tail. A nib's width in from
    /// either end the line is most of its width, as a round cap is.
    func testThePensEndsAreRound() {
        let line = outline(.pen, width: 3, pressure: 0.5)
        XCTAssertGreaterThan(width(of: line, atX: 1), 3 * 0.6, "the start comes to a point")
        XCTAssertGreaterThan(width(of: line, atX: 299), 3 * 0.6, "the end comes to a point")
    }

    /// perfect-freehand reads `size` as a LENGTH too — the samples inside
    /// the first `size` of a line are skipped, the outline's points are
    /// kept `size × smoothing` apart — so a size stretched past the nib by
    /// an easing below the middle at the middle straightens the start of
    /// every stroke and facets its curves.
    func testNoToolsSizeIsLongerThanItsNib() {
        for tool in InkTool.allCases {
            XCTAssertLessThanOrEqual(tool.size(width: 3), tool.nibWidth(width: 3) + 1e-9, "\(tool)")
        }
    }

    func testTheMarkerIgnoresPressure() {
        let light = width(of: outline(.marker, width: 3, pressure: 0.1), atX: 150)
        let hard = width(of: outline(.marker, width: 3, pressure: 0.9), atX: 150)
        XCTAssertEqual(light, hard, accuracy: 0.01)
    }

    func testTheFountainPenAndTheBrushSwellUnderPressure() {
        for tool in [InkTool.fountain, .brush] {
            let light = width(of: outline(tool, width: 3, pressure: 0.1), atX: 150)
            let hard = width(of: outline(tool, width: 3, pressure: 0.9), atX: 150)
            XCTAssertGreaterThan(hard, light * 2.5, "\(tool)")
        }
    }

    /// `reach` is what a stroke's box and hit test are measured with, so
    /// it must hold the widest ink the tool can lay down — and not much more.
    func testReachHoldsTheWidestInk() {
        for tool in InkTool.allCases {
            let widest = width(of: outline(tool, width: 3, pressure: 1), atX: 150) / 2
            XCTAssertGreaterThanOrEqual(tool.reach(width: 3), widest - 0.05, "\(tool)")
            XCTAssertLessThanOrEqual(tool.reach(width: 3), widest * 1.25 + 0.05, "\(tool)")
        }
    }

    /// The full stop, the dot over the i: one sample, or a few that hardly
    /// moved, must come out a round blot about a nib across — not the
    /// sliver a taper ramping up from nothing would leave.
    func testATapIsADotWithEveryTool() {
        for tool in InkTool.allCases {
            let nib = tool.nibWidth(width: 3)
            for points in [[CGPoint(x: 40, y: 40)],
                           [CGPoint(x: 40, y: 40), CGPoint(x: 40.4, y: 40.3), CGPoint(x: 40.6, y: 40.5)],
                           [CGPoint(x: 40, y: 40), CGPoint(x: 41, y: 40), CGPoint(x: 42.5, y: 40.2)]] {
                let stroke = Stroke(colorHex: "#000000", width: 3, points: [],
                                    pressures: points.map { _ in 0.5 }, tool: tool)
                let box = InkPaths.ink(for: stroke, tool: tool, points: points).boundingRect
                XCTAssertGreaterThan(box.height, nib * 0.6, "\(tool), \(points.count) samples: a sliver")
                XCTAssertGreaterThan(box.width, nib * 0.6, "\(tool), \(points.count) samples: a sliver")
            }
            // One sample — what a tap on the tablet is — is ROUND, a nib
            // across, and centred on the tap.
            let tap = Stroke(colorHex: "#000000", width: 3, points: [], pressures: [0.5], tool: tool)
            let box = InkPaths.ink(for: tap, tool: tool, points: [CGPoint(x: 40, y: 40)]).boundingRect
            XCTAssertEqual(box.width, box.height, accuracy: nib * 0.1, "\(tool): a tap is an oval")
            XCTAssertEqual(box.width, nib, accuracy: nib * 0.15, "\(tool): a tap is a nib across")
            XCTAssertEqual(box.midX, 40, accuracy: 0.3)
            XCTAssertEqual(box.midY, 40, accuracy: 0.3)
        }
    }

    /// How much ink a path lays down, in square points — rasterised, so
    /// a sliver that is "there" and invisible counts for what it is.
    private func inked(_ path: Path) -> Double {
        guard !path.isEmpty else { return 0 }
        let box = path.boundingRect.insetBy(dx: -1, dy: -1)
        let scale = 16.0
        let wide = Int((box.width * scale).rounded(.up)), high = Int((box.height * scale).rounded(.up))
        guard wide > 0, high > 0,
              let context = CGContext(data: nil, width: wide, height: high, bitsPerComponent: 8, bytesPerRow: wide,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: wide, height: high))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(path.cgPath)
        context.fillPath()
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let pixels = UnsafeBufferPointer(start: bytes, count: context.bytesPerRow * high)
        return pixels.reduce(0) { $0 + Double($1) / 255 } / (scale * scale)
    }

    private func ink(_ tool: InkTool, width: Double, _ points: [CGPoint], _ pressures: [Double]) -> Path {
        let stroke = Stroke(colorHex: "#000000", width: width, points: [], pressures: pressures, tool: tool)
        return InkPaths.ink(for: stroke, tool: tool, points: points)
    }

    /// EVERY STROKE PAINTS. A taper is a ramp from nothing, and
    /// perfect-freehand keeps only the last sample of a line's final three
    /// points — so a short stroke tapered at both ends came out a sliver,
    /// or three points that are no path at all: saved, selectable, and
    /// invisible. Every tool, every short length, sparse samples and dense
    /// ones: at least most of a dot's worth of ink (a nib-wide dot is 0.73
    /// of a nib squared, drawn).
    func testAShortStrokeOrAWobblyTapAlwaysPaints() {
        for tool in InkTool.allCases {
            for width in [1.0, 2, 3] {
                let nib = tool.nibWidth(width: width)
                for length in stride(from: 0.0, through: 8, by: 0.25) {
                    for spacing in [0.0, 0.3, 0.7] {
                        let count = length == 0 ? 1 : spacing == 0 ? 2 : max(2, Int(length / spacing) + 1)
                        let points = (0..<count).map { index -> CGPoint in
                            let along = count == 1 ? 0 : length * Double(index) / Double(count - 1)
                            return CGPoint(x: 50 + along * 0.8, y: 50 + along * 0.6)
                        }
                        let painted = inked(ink(tool, width: width, points, points.map { _ in 0.5 }))
                        XCTAssertGreaterThan(painted, 0.45 * nib * nib,
                                             "\(tool) at \(width): \(length) pt in \(count) samples is a sliver")
                    }
                }
            }
        }
        // The cases the review found by hand: a 2-point flick at the
        // thinnest pen, a tap whose nib wobbled half a point twelve times,
        // one that wobbled a point five times. And two found by a random
        // search, each a sliver without one rule: a scribble a pencil
        // tapered at both ends with no full-width point between the ramps
        // (`hasBody`), and a shaky pencil dash whose tapers were scaled
        // by the whole length instead of the stretch the outline keeps.
        let flick = (0..<6).map { CGPoint(x: 100 + 1.4 * Double($0) / 5, y: 100 + 1.4 * Double($0) / 5) }
        let wobble = (0..<12).map { CGPoint(x: 100 + ($0 % 2 == 0 ? 0 : 0.5), y: 100 + ($0 % 3 == 1 ? 0.25 : 0)) }
        let shake = (0..<5).map { CGPoint(x: 100 + ($0 % 2 == 0 ? 0 : 1), y: 100 + ($0 % 3 == 1 ? 0.5 : 0)) }
        let scribble = [CGPoint(x: 12, y: 13), CGPoint(x: 12.75, y: 12.5), CGPoint(x: 14.25, y: 11.25),
                        CGPoint(x: 13, y: 12), CGPoint(x: 13, y: 13.75)]
        let shaky = [CGPoint(x: 49.75, y: 49.5), CGPoint(x: 50.25, y: 49.75), CGPoint(x: 50.5, y: 50),
                     CGPoint(x: 51.75, y: 50.5), CGPoint(x: 52, y: 49.25), CGPoint(x: 52.25, y: 50.25),
                     CGPoint(x: 52.5, y: 51), CGPoint(x: 52.5, y: 50.75), CGPoint(x: 52.5, y: 50.25)]
        for (tool, width, points, pressures) in [(InkTool.pen, 1.0, flick, [0.2, 0.35, 0.45, 0.45, 0.35, 0.2]),
                                                 (.pen, 3, wobble, Array(repeating: 0.4, count: 12)),
                                                 (.pen, 2, shake, Array(repeating: 0.4, count: 5)),
                                                 (.pencil, 1, scribble, Array(repeating: 0.5, count: 5)),
                                                 (.pencil, 3, shaky, Array(repeating: 0.5, count: 9))] {
            let nib = tool.nibWidth(width: width)
            let path = ink(tool, width: width, points, pressures)
            XCTAssertGreaterThan(inked(path), 0.45 * nib * nib, "\(tool) at \(width), \(points.count) samples")
            XCTAssertGreaterThan(path.boundingRect.width, nib * 0.6, "\(tool) at \(width), \(points.count) samples")
        }
    }

    /// A TAP IS THE SAME DOT HOWEVER MANY EVENTS IT MADE. One event, two,
    /// a jittery handful, a nib held still for a tenth of a second: the
    /// same round dot where the nib went down, sized by how hard the tap
    /// pressed at its hardest — not by the touch-down (the lightest moment
    /// of a tap), not by the lift-off, and not by the two-sample quirk that
    /// takes the pressure away from four of five points.
    func testATapIsTheSameDotHoweverManyEventsItMade() {
        let down = CGPoint(x: 40, y: 40)
        let taps: [([CGPoint], [Double])] = [
            ([down], [0.6]),
            ([down, CGPoint(x: 40.2, y: 40.1)], [0.08, 0.6]),
            ([down, CGPoint(x: 40.2, y: 40.1), CGPoint(x: 39.9, y: 40.3), CGPoint(x: 40.25, y: 39.8),
              CGPoint(x: 40.1, y: 40.2)], [0.08, 0.3, 0.6, 0.4, 0.2]),
            ((0..<12).map { CGPoint(x: 40 + 0.75 * Double($0 % 3) / 2, y: 40 + 0.5 * Double($0 % 4) / 3) },
             [0.08, 0.2, 0.35, 0.5, 0.6, 0.6, 0.55, 0.5, 0.45, 0.4, 0.3, 0.1])
        ]
        for tool in InkTool.allCases {
            let boxes = taps.map { ink(tool, width: 3, $0.0, $0.1).boundingRect }
            for (box, tap) in zip(boxes, taps) {
                XCTAssertEqual(box.width, boxes[0].width, accuracy: 0.05, "\(tool), \(tap.0.count) events")
                XCTAssertEqual(box.height, boxes[0].height, accuracy: 0.05, "\(tool), \(tap.0.count) events")
                XCTAssertEqual(box.midX, 40, accuracy: 0.3, "\(tool), \(tap.0.count) events: where the nib went down")
                XCTAssertEqual(box.midY, 40, accuracy: 0.3, "\(tool), \(tap.0.count) events: where the nib went down")
            }
        }
        let light = ink(.pen, width: 3, [down], [0.1]).boundingRect.width
        let hard = ink(.pen, width: 3, [down], [0.9]).boundingRect.width
        XCTAssertGreaterThan(hard, light * 1.3, "a harder tap is a bigger dot")
    }

    /// The tapers scale with the stretch the outline keeps points along
    /// — the line less the first `size` (skipped) and the last three
    /// points (noise) — and never take more than a third of it.
    func testTapersGrowWithTheStrokeAndNeverTakeMoreThanAThird() {
        let brush = InkTool.brush
        func tapers(_ length: Double) -> (Double, Double) {
            let options = brush.options(width: 3, simulated: false, length: length)
            func distance(_ taper: InkOutline.Taper) -> Double {
                if case .distance(let d) = taper { return d }
                XCTAssertEqual(taper, .none)
                return 0
            }
            return (distance(options.start.taper), distance(options.end.taper))
        }
        XCTAssertEqual(tapers(0).0, 0)
        XCTAssertEqual(tapers(5).0 + tapers(5).1, 0, "a dash is round at both ends")
        let body = 30 - InkOutline.endNoiseThreshold - brush.size(width: 3)
        let short = tapers(30)
        XCTAssertGreaterThan(short.0, 0)
        XCTAssertGreaterThan(short.1, 0)
        XCTAssertLessThanOrEqual(short.0 + short.1, body / 3 + 1e-9)
        let long = tapers(300)
        XCTAssertEqual(long.0, 6, accuracy: 1e-9, "a nib to come up to width")
        XCTAssertEqual(long.1, 18, accuracy: 1e-9, "three nibs to go off it")
        XCTAssertEqual(InkTool.marker.options(width: 3, simulated: false, length: 300).end.taper, .none)
    }

    func testTheMouseGuessesThePressureAndThePenNeverDoes() {
        for tool in InkTool.allCases {
            XCTAssertTrue(tool.options(width: 3, simulated: true, length: 50).simulatePressure)
            XCTAssertFalse(tool.options(width: 3, simulated: false, length: 50).simulatePressure)
            XCTAssertTrue(tool.options(width: 3, simulated: false, length: 50).last,
                          "the line runs to the nib, live and finished alike")
        }
    }

    func testEveryToolLaysDownSomeColour() {
        for tool in InkTool.allCases {
            XCTAssertTrue(tool.opacity > 0 && tool.opacity <= 1, "\(tool)")
        }
        XCTAssertLessThan(InkTool.pencil.opacity, 1, "graphite, not ink")
    }
}
