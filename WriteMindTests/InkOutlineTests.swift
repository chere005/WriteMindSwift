import SwiftUI
import XCTest
@testable import WriteMind

/// The ink engine: perfect-freehand, ported. Two kinds of test, and both
/// matter. The GOLDEN ones run the upstream TypeScript (v1.2.3, the
/// package's own `inputs.json` and the option sets below, through node)
/// and pin what it printed — a port that has drifted from the original
/// is no longer the thing the cross-platform app will run, and the two
/// would draw the same stroke two ways. The BEHAVIOUR ones say what the
/// outline is FOR, in words, so a later tuning that keeps the numbers
/// but loses the point still fails.
final class InkOutlineTests: XCTestCase {
    private func samples(_ pairs: [[Double]]) -> [InkOutline.Sample] {
        pairs.map { InkOutline.Sample(CGPoint(x: $0[0], y: $0[1]), pressure: $0.count > 2 ? $0[2] : nil) }
    }

    /// What upstream printed for one call, boiled down: the point count,
    /// the sums of both coordinates (any point out of place moves them),
    /// and three points pinned exactly.
    private struct Digest {
        var count: Int
        var sumX: Double, sumY: Double
        var first: [Double], middle: [Double], last: [Double]
    }

    private func assert(_ outline: [CGPoint], matches digest: Digest, _ name: String,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(outline.count, digest.count, "\(name): point count", file: file, line: line)
        guard outline.count == digest.count, !outline.isEmpty else { return }
        XCTAssertEqual(outline.reduce(0) { $0 + $1.x }, digest.sumX, accuracy: 1e-6, "\(name): Σx", file: file, line: line)
        XCTAssertEqual(outline.reduce(0) { $0 + $1.y }, digest.sumY, accuracy: 1e-6, "\(name): Σy", file: file, line: line)
        for (point, expected, which) in [(outline[0], digest.first, "first"),
                                         (outline[outline.count / 2], digest.middle, "middle"),
                                         (outline[outline.count - 1], digest.last, "last")] {
            XCTAssertEqual(point.x, expected[0], accuracy: 1e-9, "\(name): \(which).x", file: file, line: line)
            XCTAssertEqual(point.y, expected[1], accuracy: 1e-9, "\(name): \(which).y", file: file, line: line)
        }
    }

    // MARK: - Golden: the port is the original

    /// Upstream's own snapshot (`getStroke.spec.ts.snap`, "numberPairs"),
    /// point for point.
    func testTheUpstreamSnapshotPointForPoint() {
        let expected: [[Double]] = [
            [0.0, -6.301257552174803], [11.636018860422935, -6.26674669883105],
            [21.51243873239539, -3.2375247496049404], [26.750394037910247, -2.5418384768523667],
            [28.801431236028982, -1.774779649844759], [30.5001657892464, -0.39295703103210844],
            [31.668739741418264, 1.4589521866301545], [32.184803091278624, 3.5870526191962346],
            [31.994323869869596, 5.768531589612508], [31.11724530195434, 7.774987673821868],
            [29.64539774511984, 9.396344390154628], [27.732884027096688, 10.462845262414142],
            [25.579944839016505, 10.862827367745947], [23.411993482192027, 10.554412474136786],
            [21.456015035966367, 9.569891702361161], [19.916800959987505, 8.012344637112221],
            [18.955507374323492, 6.044846867274033], [18.672781971150208, 3.873395928717618],
            [19.098226174812154, 1.7253433079172087], [20.18729586487956, -0.17440931869855447],
            [21.825965157315895, -1.626957349637026], [23.842664944636386, -2.480218622623501],
            [26.026246226751542, -2.644856457137199], [28.14808746701442, -2.103633228444366],
            [29.986031327457816, -0.9132151514581981], [31.347644600723243, 0.801760686920995],
            [32.09036601766882, 2.8617358637052654], [32.13643244988092, 5.051030434104662],
            [31.48102072974659, 7.140424678680727], [30.19275263737579, 8.911158468479826],
            [28.40651018210947, 10.177835508281682], [26.30931342053625, 10.80783437764877],
            [24.12073940719901, 10.735194028654806], [24.122730962089754, 10.735588476852367],
            [11.363981139577065, 6.26674669883105], [0.0, 6.301257552174803],
            [-1.5080366996277015, 6.1181428596769445], [-2.9284262354182404, 5.5794414167149515],
            [-4.178615500814754, 4.716462576464554], [-5.185943436972506, 3.5793627096679916],
            [-5.891864096912908, 2.234230114009889], [-6.255349338712683, 0.7592439591506797],
            [-6.255273383040147, -0.7598694902872919], [-5.891640644442558, -2.23481928924745],
            [-5.185585474772419, -3.5798812861140106], [-4.178143833664817, -4.716880414431626],
            [-2.92786827663537, -5.579734231440797], [-1.5074248778025725, -6.118293632755941],
            [0.0006301257541622322, -6.301257520668516]]
        let outline = InkOutline.stroke(samples([[0, 0], [10, 0], [20, 0], [25, 5], [30, 5]]))
        XCTAssertEqual(outline.count, expected.count)
        for (index, (point, want)) in zip(outline, expected).enumerated() {
            XCTAssertEqual(point.x, want[0], accuracy: 1e-9, "point \(index).x")
            XCTAssertEqual(point.y, want[1], accuracy: 1e-9, "point \(index).y")
        }
    }

    /// Upstream's fixtures with its default options: one point, two, two
    /// that are the same point, and a run of duplicates.
    func testUpstreamsFixturesWithItsDefaults() {
        assert(InkOutline.stroke(samples([[464.91, 286.51]])),
               matches: Digest(count: 44, sumX: 20459.3134592786, sumY: 12619.188551733569,
                               first: [469.8101723753737, 282.75982762462627],
                               middle: [471.5814264041639, 287.5828124667031],
                               last: [468.6606623738596, 281.61020266636405]), "onePoint")
        assert(InkOutline.stroke(samples([[10, 200], [10, 0]])),
               matches: Digest(count: 52, sumX: 519.2008301381652, sumY: 4895.3703648898545,
                               first: [4.893206982421875, 200.0],
                               middle: [7.213239759432362, 32.4684593111267],
                               last: [4.89320700795584, 199.9994893206991]), "twoPoints")
        assert(InkOutline.stroke(samples([[1, 1], [1, 1]])),
               matches: Digest(count: 13, sumX: 13.002145643761844, sumY: 12.998703228619888,
                               first: [6.728352660193719, -0.7849301948399909],
                               middle: [-4.13502188385132, 4.103473900706759],
                               last: [5.243489130398231, -3.241792074134711]), "twoEqualPoints")
        let duplicates: [[Double]] = [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [10, 10], [10, 10], [10, 10],
                                      [10, 10], [10, 10], [100, 100], [100, 100], [100, 100], [100, 100],
                                      [100, 100], [100, 100], [0, 0], [0, 0]]
        assert(InkOutline.stroke(samples(duplicates)),
               matches: Digest(count: 86, sumX: 4134.2266713038, sumY: 4118.648390117324,
                               first: [4.224688080042079, -4.224688080042079],
                               middle: [12.949222619718594, 17.556674096220046],
                               last: [4.225110527725936, -4.224265590111343]), "withDuplicates")
        // "Solves a tricky stroke with only one point."
        var tricky = InkOutline.Options()
        tricky.size = 1
        tricky.thinning = 0.6
        assert(InkOutline.stroke(samples([[464.91, 286.51]]), options: tricky),
               matches: Digest(count: 44, sumX: 20468.043401120805, sumY: 12627.914381942755,
                               first: [465.7241672374853, 286.8458327625147],
                               middle: [465.82211152644874, 287.11252732656965],
                               last: [464.5742486558881, 285.69579918330936]), "onePoint tricky")
    }

    /// A written stroke WITH pressure — the case the Wacom feeds — under
    /// three option sets that between them reach every branch: real
    /// pressure and numeric tapers; simulated pressure, an easing, flat
    /// caps and hairpin corners; tapers over the whole length, negative
    /// thinning and an end easing of its own.
    func testRealPressureCornersAndTapersMatchUpstream() {
        let pen = InkOutline.Options(size: 3, thinning: 0.3, smoothing: 0.5, streamline: 0.4,
                                     simulatePressure: false,
                                     start: .init(taper: .distance(3)), end: .init(taper: .distance(4.5)),
                                     last: true)
        assert(InkOutline.stroke(samples(Self.written), options: pen),
               matches: Digest(count: 63, sumX: 2263.5903552232685, sumY: 3292.0932458576754,
                               first: [19.990813033262576, 82.99605036176777],
                               middle: [50.20072668154093, 73.20418792474747],
                               last: [20.009186966737424, 83.00394963823223]), "written, pen options")

        let zigzag: [[Double]] = [[0, 0], [20, 0], [40, 1], [60, 0], [40, 20], [20, 21], [0, 20], [20, 40],
                                  [40, 41], [60, 40], [61, 40], [61, 40], [80, 60]]
        let corners = InkOutline.Options(size: 10, thinning: 0.6, smoothing: 0.6, streamline: 0.5,
                                         easing: .easeInOutSine, simulatePressure: true,
                                         start: .init(cap: false), end: .init(cap: false, easing: .easeOutCubic),
                                         last: false)
        assert(InkOutline.stroke(samples(zigzag), options: corners),
               matches: Digest(count: 84, sumX: 2600.8508159326148, sumY: 1196.499078795693,
                               first: [0.0, -1.3510819263812164],
                               middle: [69.89419227735345, 52.433102604558066],
                               last: [0.0, -1.3510819263812164]), "zigzag, flat caps")

        let whole = InkOutline.Options(size: 8, thinning: -0.4, smoothing: 0.3, streamline: 0.2,
                                       easing: .easeOutSine, simulatePressure: true,
                                       start: .init(taper: .whole), end: .init(taper: .whole, easing: .easeInQuad),
                                       last: true)
        assert(InkOutline.stroke(samples(Self.written), options: whole),
               matches: Digest(count: 55, sumX: 2010.598144052203, sumY: 3006.270172670842,
                               first: [19.990813033262576, 82.99605036176777],
                               middle: [51.92523549304869, 74.18881324044189],
                               last: [20.009186966737424, 83.00394963823223]), "written, whole tapers")

        var defaults = InkOutline.Options()
        defaults.last = true
        assert(InkOutline.stroke(samples(Self.written), options: defaults),
               matches: Digest(count: 69, sumX: 2783.4710504818686, sumY: 4984.2195381763995,
                               first: [13.731694289321215, 80.49267771572849],
                               middle: [59.98583871048126, 86.87817498078745],
                               last: [13.731945052890751, 80.49205089769508]), "written, defaults, last")
    }

    func testTheStreamlinedPointsMatchUpstream() {
        let pen = InkOutline.Options(size: 3, thinning: 0.3, smoothing: 0.5, streamline: 0.4,
                                     simulatePressure: false,
                                     start: .init(taper: .distance(3)), end: .init(taper: .distance(4.5)),
                                     last: true)
        let points = InkOutline.strokePoints(samples(Self.written), options: pen)
        XCTAssertEqual(points.count, 39)
        XCTAssertEqual(points.reduce(0) { $0 + $1.pressure }, 20.753999999999998, accuracy: 1e-9)
        XCTAssertEqual(points.reduce(0) { $0 + $1.runningLength }, 2255.5521616863375, accuracy: 1e-6)
        XCTAssertEqual(points.last?.runningLength ?? 0, 110.95539148815669, accuracy: 1e-9)
    }

    // MARK: - What the outline is for

    private func width(of outline: [CGPoint], atX x: Double) -> Double {
        // The vertical extent of the outline's crossings of x = const.
        var ys: [Double] = []
        for index in outline.indices {
            let a = outline[index], b = outline[(index + 1) % outline.count]
            guard (a.x - x) * (b.x - x) <= 0, a.x != b.x else { continue }
            let t = (x - a.x) / (b.x - a.x)
            ys.append(a.y + (b.y - a.y) * t)
        }
        guard let low = ys.min(), let high = ys.max() else { return 0 }
        return high - low
    }

    private func line(pressure: Double?, count: Int = 41, length: Double = 200) -> [InkOutline.Sample] {
        (0..<count).map { InkOutline.Sample(CGPoint(x: Double($0) * length / Double(count - 1), y: 50),
                                            pressure: pressure) }
    }

    func testAStraightLineIsAboutSizeWideInTheMiddle() {
        let options = InkOutline.Options(size: 10, thinning: 0.5, simulatePressure: false, last: true)
        let outline = InkOutline.stroke(line(pressure: 0.5), options: options)
        XCTAssertEqual(width(of: outline, atX: 100), 10, accuracy: 0.5,
                       "at the middle pressure a line is as wide as its size")
    }

    func testHarderIsWider() {
        let options = InkOutline.Options(size: 10, thinning: 0.5, simulatePressure: false, last: true)
        let light = width(of: InkOutline.stroke(line(pressure: 0.2), options: options), atX: 100)
        let firm = width(of: InkOutline.stroke(line(pressure: 0.9), options: options), atX: 100)
        XCTAssertGreaterThan(firm, light * 1.5, "pressure has to show")
        XCTAssertEqual(firm, 10 * (1 - 0.5 + 2 * 0.5 * 0.9), accuracy: 0.5)
    }

    func testATaperNarrowsTheEnds() {
        let flat = InkOutline.Options(size: 10, thinning: 0.5, simulatePressure: false, last: true)
        var tapered = flat
        tapered.start.taper = .distance(60)
        tapered.end.taper = .distance(60)
        let middle = width(of: InkOutline.stroke(line(pressure: 0.5), options: tapered), atX: 100)
        let nearStart = width(of: InkOutline.stroke(line(pressure: 0.5), options: tapered), atX: 15)
        let untapered = width(of: InkOutline.stroke(line(pressure: 0.5), options: flat), atX: 15)
        XCTAssertLessThan(nearStart, middle * 0.75)
        XCTAssertLessThan(nearStart, untapered * 0.75)
    }

    func testOnePointIsADot() {
        let options = InkOutline.Options(size: 6, thinning: 0.5, simulatePressure: false, last: true)
        let outline = InkOutline.stroke([InkOutline.Sample(CGPoint(x: 40, y: 40), pressure: 0.5)], options: options)
        XCTAssertGreaterThan(outline.count, 8, "a round thing, not a sliver")
        let box = InkOutline.path(outline).boundingRect
        XCTAssertEqual(box.width, 6, accuracy: 1.6)
        XCTAssertEqual(box.height, 6, accuracy: 1.6)
        XCTAssertTrue(box.insetBy(dx: -1, dy: -1).contains(CGPoint(x: 40, y: 40)))
    }

    func testNothingInIsNothingOut() {
        XCTAssertEqual(InkOutline.stroke([]), [])
        XCTAssertEqual(InkOutline.strokePoints([]).count, 0)
        XCTAssertTrue(InkOutline.path([]).isEmpty)
        var zero = InkOutline.Options()
        zero.size = 0
        XCTAssertEqual(InkOutline.stroke(line(pressure: 0.5), options: zero), [], "no size, no ink")
    }

    func testRepeatedPointsNeverMakeANaN() {
        let still = Array(repeating: InkOutline.Sample(CGPoint(x: 12, y: 12), pressure: 0.4), count: 30)
        for options in [InkOutline.Options(),
                        InkOutline.Options(size: 3, simulatePressure: false, last: true),
                        InkOutline.Options(size: 3, start: .init(taper: .whole), end: .init(taper: .whole))] {
            let outline = InkOutline.stroke(still, options: options)
            XCTAssertFalse(outline.contains { !$0.x.isFinite || !$0.y.isFinite }, "\(options)")
        }
        // Repeats inside a moving stroke, and a pressure that is not a number.
        let jittered = [InkOutline.Sample(CGPoint(x: 0, y: 0), pressure: .nan)]
            + Array(repeating: InkOutline.Sample(CGPoint(x: 5, y: 5), pressure: 0.5), count: 6)
            + [InkOutline.Sample(CGPoint(x: 40, y: 9), pressure: -1)]
        let outline = InkOutline.stroke(jittered, options: InkOutline.Options(size: 4, simulatePressure: false))
        XCTAssertFalse(outline.isEmpty)
        XCTAssertFalse(outline.contains { !$0.x.isFinite || !$0.y.isFinite })
    }

    /// getSvgPathFromStroke: through the midpoints, closed — and fewer than
    /// four points is no path at all, as upstream's helper says.
    func testThePathRunsThroughTheMidpointsAndCloses() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        var elements: [Path.Element] = []
        InkOutline.path(square).forEach { elements.append($0) }
        XCTAssertEqual(elements, [
            .move(to: CGPoint(x: 0, y: 0)),
            .quadCurve(to: CGPoint(x: 10, y: 5), control: CGPoint(x: 10, y: 0)),
            .quadCurve(to: CGPoint(x: 5, y: 10), control: CGPoint(x: 10, y: 10)),
            .closeSubpath
        ])
        XCTAssertTrue(InkOutline.path(Array(square.prefix(3))).isEmpty)
    }

    func testEveryNamedEasingRunsFromZeroToOne() {
        for easing in InkOutline.Easing.allCases {
            XCTAssertEqual(easing(0), 0, accuracy: 1e-9, "\(easing)")
            XCTAssertEqual(easing(1), 1, accuracy: 1e-9, "\(easing)")
        }
    }

    /// How long a page of handwriting takes to outline. Not a pass mark —
    /// a ceiling far above anything acceptable, so a pathological change
    /// fails and an ordinary one does not — and the number goes in the
    /// log, which is what decides whether the outlines need a cache.
    func testAPageOfWritingOutlinesInGoodTime() {
        let options = InkTool.pen.options(width: 3, simulated: false, length: 300)
        let strokes = (0..<300).map { index -> [InkOutline.Sample] in
            (0..<120).map { step in
                let t = Double(step) / 119
                return InkOutline.Sample(CGPoint(x: Double(index % 20) * 40 + 30 * t + 4 * sin(t * 9),
                                                 y: Double(index / 20) * 30 + 10 * cos(t * 7)),
                                         pressure: 0.3 + 0.4 * sin(t * .pi))
            }
        }
        let start = Date()
        var total = 0
        for stroke in strokes { total += InkOutline.path(InkOutline.stroke(stroke, options: options)).isEmpty ? 0 : 1 }
        let seconds = Date().timeIntervalSince(start)
        print("InkOutline: 300 strokes x 120 points outlined and pathed in \(Int(seconds * 1000)) ms")
        XCTAssertEqual(total, 300)
        XCTAssertLessThan(seconds, 5)
    }

    /// x, y, pressure — an upstroke, a loop and a hook, made in node with
    /// the same arithmetic the golden numbers were printed from.
    static let written: [[Double]] = [
        [20.0, 83.0, 0.2], [21.84, 78.86, 0.246], [23.65, 74.51, 0.286], [25.38, 70.02, 0.321],
        [27.02, 65.45, 0.352], [28.54, 60.88, 0.38], [29.9, 56.4, 0.408], [31.09, 52.1, 0.436],
        [32.1, 48.06, 0.466], [32.92, 44.37, 0.498], [33.54, 41.09, 0.534], [33.98, 38.27, 0.571],
        [34.24, 35.94, 0.611], [34.34, 34.1, 0.651], [34.3, 32.75, 0.69], [34.14, 31.86, 0.725],
        [33.91, 31.38, 0.755], [33.62, 31.26, 0.779], [33.31, 31.43, 0.794], [33.02, 31.85, 0.799],
        [32.78, 32.44, 0.796], [32.63, 33.17, 0.783], [32.59, 34.0, 0.763], [32.69, 34.91, 0.736],
        [32.95, 35.9, 0.704], [33.38, 36.99, 0.669], [34.01, 38.19, 0.633], [34.82, 39.56, 0.598],
        [35.83, 41.14, 0.565], [37.02, 42.98, 0.534], [38.38, 45.13, 0.506], [39.89, 47.63, 0.48],
        [41.53, 50.51, 0.455], [43.27, 53.78, 0.429], [45.08, 57.44, 0.402], [46.92, 61.46, 0.371],
        [48.76, 65.8, 0.336], [50.56, 70.39, 0.295], [52.3, 75.15, 0.248], [53.94, 80.01, 0.195]]
}
