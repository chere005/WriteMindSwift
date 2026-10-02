// A Swift port of perfect-freehand 1.2.3 — getStroke, getStrokePoints,
// getStrokeOutlinePoints, getStrokeRadius, simulatePressure, the
// constants and the vector helpers — from
// https://github.com/steveruizok/perfect-freehand (packages/perfect-freehand/src,
// tag v1.2.3), plus the README's getSvgPathFromStroke and seven of the
// demo's named easings (packages/dev/src/state/easings.ts).
//
// MIT License
//
// Copyright (c) 2021 Stephen Ruiz Ltd
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftUI

/// Ink that looks written: the OUTLINE of a stroke whose width follows
/// the pen's pressure, as one polygon to fill (Sean, 2026-10-02: "make the
/// text strokes well implemented to feel natural for writing letters").
///
/// **A port, not a reimagining.** The cross-platform app will run the
/// TypeScript original over the same samples with the same options, and a
/// stroke has to come out the same shape on both — so this follows the
/// upstream source line for line, its odd corners included (two input
/// points are re-sampled into five and the four new ones lose their
/// pressure; the first point of a stroke defaults to a lighter press than
/// the rest; a step that lands exactly on the last point is dropped). The
/// loops that walk round a cap ACCUMULATE their step the way the
/// JavaScript does, `t += step`, and are not `stride`s: a stride
/// multiplies, the two disagree in the last bit, and that changes how many
/// points a cap gets. `InkOutlineTests` pins the output against numbers
/// printed by the original, so a "tidy-up" that drifts fails there.
///
/// Pure: points in, points out. `InkTool` says which options a pen,
/// pencil or brush uses; `InkPaths` turns the outline into the path both
/// painters fill.
enum InkOutline {
    // MARK: - Types

    /// One input sample: where the nib was and, if the device said,
    /// how hard it was pressed (0…1). nil is "no pressure reported", and
    /// takes upstream's defaults.
    struct Sample: Equatable {
        var point: CGPoint
        var pressure: Double?

        init(_ point: CGPoint, pressure: Double? = nil) {
            self.point = point
            self.pressure = pressure
        }
    }

    /// `StrokePoint`: a streamlined sample, with the running sums the
    /// outline needs.
    struct StrokePoint: Equatable {
        var point: CGPoint
        var pressure: Double
        /// From the previous point.
        var distance: Double
        /// The unit vector from THIS point back to the previous one.
        var vector: CGPoint
        /// Along the line so far.
        var runningLength: Double
    }

    /// `taper: number | boolean`.
    enum Taper: Equatable {
        /// `false` / absent: no taper, and the end gets its cap.
        case none
        /// `true`: taper over the whole line (`max(size, totalLength)`).
        case whole
        /// A number: taper over this distance, in the samples' units.
        case distance(Double)
    }

    /// `options.start` / `options.end`.
    struct End: Equatable {
        var cap: Bool = true
        var taper: Taper = .none
        /// nil is upstream's own default for that end — `t * (2 - t)` at
        /// the start, `--t * t * t + 1` at the end — which is why it is not
        /// simply a default value here: one `End` type serves both.
        var easing: Easing?
    }

    /// `StrokeOptions`, with upstream's defaults.
    struct Options: Equatable {
        /// The base size (diameter) of the stroke.
        var size: Double = 16
        /// The effect of pressure on the stroke's size.
        var thinning: Double = 0.5
        /// How much to soften the stroke's edges.
        var smoothing: Double = 0.5
        /// How much to streamline the stroke.
        var streamline: Double = 0.5
        /// An easing function to apply to each point's pressure.
        var easing: Easing = .linear
        /// Whether to simulate pressure based on velocity.
        var simulatePressure: Bool = true
        var start = End()
        var end = End()
        /// Whether to handle the points as a completed stroke.
        var last: Bool = false
    }

    /// Easings by name, from upstream's demo — a name rather than a
    /// closure, so an `Options` stays a plain value that can be compared,
    /// and the cross-platform table can say which one in a word. Only the
    /// ones something here reaches: the tools' (`InkTool`), upstream's
    /// own taper defaults (easeOutQuad in, easeOutCubic out), and the two
    /// more that the golden option sets in `InkOutlineTests` pin. A tool
    /// that wants another takes it from the same file, by the same name.
    enum Easing: String, CaseIterable {
        case linear
        case easeInQuad, easeOutQuad, easeInOutQuad
        case easeOutCubic
        case easeOutSine, easeInOutSine

        func callAsFunction(_ t: Double) -> Double {
            switch self {
            case .linear: return t
            case .easeInQuad: return t * t
            case .easeOutQuad: return t * (2 - t)
            case .easeInOutQuad: return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
            case .easeOutCubic: let u = t - 1; return u * u * u + 1
            case .easeOutSine: return sin((t * Double.pi) / 2)
            case .easeInOutSine: return -(cos(Double.pi * t) - 1) / 2
            }
        }
    }

    // MARK: - Constants (constants.ts)

    /// Rate of change for simulated pressure.
    static let rateOfPressureChange = 0.275
    /// PI with a tiny offset, which upstream keeps to dodge a browser
    /// artefact. Kept here so the caps have the same number of points.
    static let fixedPI = Double.pi + 0.0001
    static let startCapSegments = 13
    static let endCapSegments = 29
    static let cornerCapSegments = 13
    /// Distance at the end of a stroke inside which samples are noise.
    static let endNoiseThreshold = 3.0
    static let minStreamlineT = 0.15
    static let streamlineTRange = 0.85
    static let minRadius = 0.01
    /// The first point of a stroke, when it says nothing: lines start slow.
    static let defaultFirstPressure = 0.25
    static let defaultPressure = 0.5
    static let unitOffset = CGPoint(x: 1, y: 1)

    // MARK: - getStroke

    /// The outline polygon round `samples`.
    static func stroke(_ samples: [Sample], options: Options = Options()) -> [CGPoint] {
        outlinePoints(strokePoints(samples, options: options), options: options)
    }

    // MARK: - getStrokeRadius / simulatePressure

    static func strokeRadius(size: Double, thinning: Double, pressure: Double,
                             easing: Easing = .linear) -> Double {
        size * easing(0.5 - thinning * (0.5 - pressure))
    }

    static func simulatePressure(_ previous: Double, distance: Double, size: Double) -> Double {
        // Speed of change — how fast should the pressure be changing?
        let sp = min(1, distance / size)
        // Rate of change — how much of a change is there?
        let rp = min(1, 1 - sp)
        // Accelerate the pressure.
        return min(1, previous + (rp - previous) * (sp * rateOfPressureChange))
    }

    // MARK: - getStrokePoints

    /// Upstream's `isValidPressure`: present and not negative (NaN fails).
    private static func valid(_ pressure: Double?) -> Double? {
        guard let pressure, pressure >= 0 else { return nil }
        return pressure
    }

    static func strokePoints(_ samples: [Sample], options: Options = Options()) -> [StrokePoint] {
        let streamline = options.streamline
        let size = options.size
        let isComplete = options.last

        // If we don't have any points, return an empty array.
        if samples.isEmpty { return [] }

        // Find the interpolation level between points.
        let t = minStreamlineT + (1 - streamline) * streamlineTRange

        var pts = samples

        // Add extra points between the two, to help avoid "dash" lines for
        // strokes with tapered start and ends. Upstream lerps the bare
        // [x, y] here, so these four carry no pressure.
        if pts.count == 2 {
            let last = pts[1]
            pts = [pts[0]]
            for i in 1..<5 {
                pts.append(Sample(V.lrp(pts[0].point, last.point, Double(i) / 4)))
            }
        }

        // If there's only one point, add another point at a 1pt offset.
        if pts.count == 1 {
            pts.append(Sample(V.add(pts[0].point, unitOffset), pressure: pts[0].pressure))
        }

        // Start it out with the first point, which needs no adjustment.
        var strokePoints = [StrokePoint(point: pts[0].point,
                                        pressure: valid(pts[0].pressure) ?? defaultFirstPressure,
                                        distance: 0, vector: unitOffset, runningLength: 0)]

        // Whether we've already reached our minimum length.
        var hasReachedMinimumLength = false
        // The total distance so far.
        var runningLength = 0.0
        // The latest point, for the distance and vector of the next.
        var prev = strokePoints[0]
        let max = pts.count - 1

        for i in 1..<pts.count {
            // At the last point of a completed stroke, the actual input
            // point; otherwise streamline towards it.
            let point = isComplete && i == max ? pts[i].point : V.lrp(prev.point, pts[i].point, t)

            // If the new point is the same as the previous point, skip ahead.
            if V.isEqual(prev.point, point) { continue }

            let distance = V.dist(point, prev.point)
            runningLength += distance

            // At the start of the line, wait until the new point is a
            // certain distance away from the original point, to avoid noise.
            if i < max && !hasReachedMinimumLength {
                if runningLength < size { continue }
                hasReachedMinimumLength = true
            }

            prev = StrokePoint(point: point,
                               pressure: valid(pts[i].pressure) ?? defaultPressure,
                               distance: distance,
                               vector: V.uni(V.sub(prev.point, point)),
                               runningLength: runningLength)
            strokePoints.append(prev)
        }

        // The first point's vector is the second point's.
        strokePoints[0].vector = strokePoints.count > 1 ? strokePoints[1].vector : CGPoint(x: 0, y: 0)
        return strokePoints
    }

    // MARK: - getStrokeOutlinePoints

    private static func taperDistance(_ taper: Taper, size: Double, totalLength: Double) -> Double {
        switch taper {
        case .none: return 0
        case .whole: return Swift.max(size, totalLength)
        case .distance(let distance): return distance
        }
    }

    /// The pressure to start from: an average over the first few points,
    /// which prevents "fat starts", since drawn lines almost always start slow.
    private static func initialPressure(_ points: [StrokePoint], simulate: Bool, size: Double) -> Double {
        points.prefix(10).reduce(points[0].pressure) { acc, current in
            var pressure = current.pressure
            if simulate { pressure = simulatePressure(acc, distance: current.distance, size: size) }
            return (acc + pressure) / 2
        }
    }

    static func outlinePoints(_ points: [StrokePoint], options: Options = Options()) -> [CGPoint] {
        let size = options.size
        let smoothing = options.smoothing
        let thinning = options.thinning
        let shouldSimulatePressure = options.simulatePressure
        let easing = options.easing
        let isComplete = options.last
        let capStart = options.start.cap
        let taperStartEase = options.start.easing ?? .easeOutQuad
        let capEnd = options.end.cap
        let taperEndEase = options.end.easing ?? .easeOutCubic

        // Nothing to do with no points or a stroke with no size.
        if points.isEmpty || size <= 0 { return [] }

        let totalLength = points[points.count - 1].runningLength
        let taperStart = taperDistance(options.start.taper, size: size, totalLength: totalLength)
        let taperEnd = taperDistance(options.end.taper, size: size, totalLength: totalLength)

        // The minimum allowed distance between points (squared).
        let minDistance = pow(size * smoothing, 2)

        var leftPts: [CGPoint] = []
        var rightPts: [CGPoint] = []

        var prevPressure = initialPressure(points, simulate: shouldSimulatePressure, size: size)
        var radius = strokeRadius(size: size, thinning: thinning,
                                  pressure: points[points.count - 1].pressure, easing: easing)
        var firstRadius: Double?
        var prevVector = points[0].vector
        var prevLeftPoint = points[0].point
        var prevRightPoint = prevLeftPoint
        var tempLeftPoint = prevLeftPoint
        var tempRightPoint = prevRightPoint
        // Whether the previous point was a sharp corner, so the same
        // corner is not found twice.
        var isPrevPointSharpCorner = false

        for i in points.indices {
            var pressure = points[i].pressure
            let point = points[i].point
            let vector = points[i].vector
            let distance = points[i].distance
            let runningLength = points[i].runningLength
            let isLastPoint = i == points.count - 1

            // Removes noise from the end of the line.
            if !isLastPoint && totalLength - runningLength < endNoiseThreshold { continue }

            // The radius: half the size with no thinning, otherwise from
            // the (real or simulated) pressure.
            if thinning != 0 {
                if shouldSimulatePressure {
                    pressure = simulatePressure(prevPressure, distance: distance, size: size)
                }
                radius = strokeRadius(size: size, thinning: thinning, pressure: pressure, easing: easing)
            } else {
                radius = size / 2
            }

            if firstRadius == nil { firstRadius = radius }

            // Tapering: the smaller of the two strengths wins.
            let taperStartStrength = runningLength < taperStart
                ? taperStartEase(runningLength / taperStart) : 1
            let taperEndStrength = totalLength - runningLength < taperEnd
                ? taperEndEase((totalLength - runningLength) / taperEnd) : 1
            radius = Swift.max(minRadius, radius * Swift.min(taperStartStrength, taperEndStrength))

            // Sharp corners: if the next vector is at more than a right
            // angle to this one, draw a cap at this point.
            let nextVector = (!isLastPoint ? points[i + 1] : points[i]).vector
            let nextDpr = !isLastPoint ? V.dpr(vector, nextVector) : 1.0
            let prevDpr = V.dpr(vector, prevVector)

            let isPointSharpCorner = prevDpr < 0 && !isPrevPointSharpCorner
            let isNextPointSharpCorner = nextDpr < 0

            if isPointSharpCorner || isNextPointSharpCorner {
                let offset = V.mul(V.per(prevVector), radius)
                let step = 1 / Double(cornerCapSegments)
                var t = 0.0
                while t <= 1 {
                    tempLeftPoint = V.rotAround(V.sub(point, offset), point, fixedPI * t)
                    leftPts.append(tempLeftPoint)
                    tempRightPoint = V.rotAround(V.add(point, offset), point, fixedPI * -t)
                    rightPts.append(tempRightPoint)
                    t += step
                }
                prevLeftPoint = tempLeftPoint
                prevRightPoint = tempRightPoint
                if isNextPointSharpCorner { isPrevPointSharpCorner = true }
                continue
            }

            isPrevPointSharpCorner = false

            // The last point.
            if isLastPoint {
                let offset = V.mul(V.per(vector), radius)
                leftPts.append(V.sub(point, offset))
                rightPts.append(V.add(point, offset))
                continue
            }

            // Regular points: project to either side, and keep a side's
            // point only once it is far enough from that side's last.
            let offset = V.mul(V.per(V.lrp(nextVector, vector, nextDpr)), radius)

            tempLeftPoint = V.sub(point, offset)
            if i <= 1 || V.dist2(prevLeftPoint, tempLeftPoint) > minDistance {
                leftPts.append(tempLeftPoint)
                prevLeftPoint = tempLeftPoint
            }

            tempRightPoint = V.add(point, offset)
            if i <= 1 || V.dist2(prevRightPoint, tempRightPoint) > minDistance {
                rightPts.append(tempRightPoint)
                prevRightPoint = tempRightPoint
            }

            prevPressure = pressure
            prevVector = vector
        }

        // Caps. Tapered ends have none; a very short line may be a dot.
        let firstPoint = points[0].point
        let lastPoint = points.count > 1 ? points[points.count - 1].point : V.add(points[0].point, CGPoint(x: 1, y: 1))

        var startCap: [CGPoint] = []
        var endCap: [CGPoint] = []

        if points.count == 1 {
            if !(taperStart != 0 || taperEnd != 0) || isComplete {
                // `firstRadius || radius`: a zero first radius falls through.
                let dotRadius = (firstRadius ?? 0) != 0 ? firstRadius! : radius
                return dot(firstPoint, radius: dotRadius)
            }
        } else {
            if taperStart != 0 || (taperEnd != 0 && points.count == 1) {
                // The start is tapered: no cap.
            } else if capStart {
                startCap = roundStartCap(firstPoint, rightPoint: rightPts.first ?? firstPoint,
                                         segments: startCapSegments)
            } else {
                startCap = flatStartCap(firstPoint, leftPoint: leftPts.first ?? firstPoint,
                                        rightPoint: rightPts.first ?? firstPoint)
            }

            let direction = V.per(V.neg(points[points.count - 1].vector))

            if taperEnd != 0 || (taperStart != 0 && points.count == 1) {
                // Tapered end: the line runs to the last point.
                endCap = [lastPoint]
            } else if capEnd {
                endCap = roundEndCap(lastPoint, direction: direction, radius: radius, segments: endCapSegments)
            } else {
                endCap = flatEndCap(lastPoint, direction: direction, radius: radius)
            }
        }

        // Left side, round the end, back along the right, round the start.
        return leftPts + endCap + rightPts.reversed() + startCap
    }

    // MARK: - Caps

    private static func dot(_ center: CGPoint, radius: Double) -> [CGPoint] {
        let offsetPoint = V.add(center, CGPoint(x: 1, y: 1))
        let start = V.prj(center, V.uni(V.per(V.sub(center, offsetPoint))), -radius)
        var points: [CGPoint] = []
        let step = 1 / Double(startCapSegments)
        var t = step
        while t <= 1 {
            points.append(V.rotAround(start, center, fixedPI * 2 * t))
            t += step
        }
        return points
    }

    private static func roundStartCap(_ center: CGPoint, rightPoint: CGPoint, segments: Int) -> [CGPoint] {
        var cap: [CGPoint] = []
        let step = 1 / Double(segments)
        var t = step
        while t <= 1 {
            cap.append(V.rotAround(rightPoint, center, fixedPI * t))
            t += step
        }
        return cap
    }

    private static func flatStartCap(_ center: CGPoint, leftPoint: CGPoint, rightPoint: CGPoint) -> [CGPoint] {
        let cornersVector = V.sub(leftPoint, rightPoint)
        let offsetA = V.mul(cornersVector, 0.5)
        let offsetB = V.mul(cornersVector, 0.51)
        return [V.sub(center, offsetA), V.sub(center, offsetB), V.add(center, offsetB), V.add(center, offsetA)]
    }

    /// One and a half turns, so a sharp turn at the very end is covered.
    private static func roundEndCap(_ center: CGPoint, direction: CGPoint, radius: Double,
                                    segments: Int) -> [CGPoint] {
        var cap: [CGPoint] = []
        let start = V.prj(center, direction, radius)
        let step = 1 / Double(segments)
        var t = step
        while t < 1 {
            cap.append(V.rotAround(start, center, fixedPI * 3 * t))
            t += step
        }
        return cap
    }

    private static func flatEndCap(_ center: CGPoint, direction: CGPoint, radius: Double) -> [CGPoint] {
        [V.add(center, V.mul(direction, radius)),
         V.add(center, V.mul(direction, radius * 0.99)),
         V.sub(center, V.mul(direction, radius * 0.99)),
         V.sub(center, V.mul(direction, radius))]
    }

    // MARK: - getSvgPathFromStroke

    /// The outline as a closed path, smoothed through the midpoints of its
    /// points — upstream's `getSvgPathFromStroke`: `M p0 Q p1 mid(p1,p2)`
    /// then `T` to each later midpoint, which (a T reflects the last
    /// control through the point it is at, and the reflection of p(i)
    /// through mid(p(i), p(i+1)) IS p(i+1)) is a quadratic through every
    /// midpoint with each outline point as its control. Fewer than four
    /// points is no path, as upstream says. Fill it NONZERO — the outline
    /// crosses itself at a tight turn, and even-odd would punch a hole there.
    static func path(_ outline: [CGPoint]) -> Path {
        var path = Path()
        guard outline.count >= 4 else { return path }
        path.move(to: outline[0])
        path.addQuadCurve(to: V.med(outline[1], outline[2]), control: outline[1])
        for i in 2..<(outline.count - 1) {
            path.addQuadCurve(to: V.med(outline[i], outline[i + 1]), control: outline[i])
        }
        path.closeSubpath()
        return path
    }

    // MARK: - vec.ts

    /// Upstream's vector helpers, by their upstream names. The `…Into`
    /// variants there are allocation-free copies of these for a hot loop;
    /// a CGPoint is a value, so one spelling serves both.
    fileprivate enum V {
        static func neg(_ a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }
        static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
        static func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
        static func mul(_ a: CGPoint, _ n: Double) -> CGPoint { CGPoint(x: a.x * n, y: a.y * n) }
        static func div(_ a: CGPoint, _ n: Double) -> CGPoint { CGPoint(x: a.x / n, y: a.y / n) }
        /// Perpendicular rotation.
        static func per(_ a: CGPoint) -> CGPoint { CGPoint(x: a.y, y: -a.x) }
        /// Dot product.
        static func dpr(_ a: CGPoint, _ b: CGPoint) -> Double { a.x * b.x + a.y * b.y }
        static func isEqual(_ a: CGPoint, _ b: CGPoint) -> Bool { a.x == b.x && a.y == b.y }
        static func len(_ a: CGPoint) -> Double { hypot(a.x, a.y) }
        static func dist2(_ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = a.x - b.x, dy = a.y - b.y
            return dx * dx + dy * dy
        }
        static func uni(_ a: CGPoint) -> CGPoint { div(a, len(a)) }
        static func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.y - b.y, a.x - b.x) }
        static func med(_ a: CGPoint, _ b: CGPoint) -> CGPoint { mul(add(a, b), 0.5) }
        /// Rotate `a` round `c` by `r` radians.
        static func rotAround(_ a: CGPoint, _ c: CGPoint, _ r: Double) -> CGPoint {
            let s = sin(r), co = cos(r)
            let px = a.x - c.x, py = a.y - c.y
            let nx = px * co - py * s
            let ny = px * s + py * co
            return CGPoint(x: nx + c.x, y: ny + c.y)
        }
        /// Interpolate from `a` to `b` by `t`.
        static func lrp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { add(a, mul(sub(b, a), t)) }
        /// Project `a` in the direction `b` by `c`.
        static func prj(_ a: CGPoint, _ b: CGPoint, _ c: Double) -> CGPoint { add(a, mul(b, c)) }
    }
}
