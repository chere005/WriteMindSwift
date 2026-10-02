import Foundation

/// What a stroke is written WITH: a ballpoint, a fountain pen, a pencil, a
/// felt marker, a brush (Sean, 2026-10-02: "it can have themed backgrounds
/// and different pen colors and strokes to write with"). Each is a
/// different answer to the same three questions — how much does pressure
/// widen the line, how do its ends come off, how much of the paper shows
/// through — given to `InkOutline` as an option set.
///
/// **The stroke's `width` keeps meaning what the slider says.** Every
/// tool is calibrated so that at the MIDDLE pressure its line is `nib ×
/// width` across, whatever easing it uses: the size handed to the outline
/// is divided by the easing's own value at the middle, so a change of
/// easing never quietly makes a tool fatter. The pen's nib is 1, so a
/// 3-point pen writes a 3-point line at an ordinary press and the pen
/// menu's swatch is still the truth.
///
/// Stored by its raw value in the sidecar (`Stroke.tool`). A raw value this
/// build does not know — a tool added later, opened in an older copy — is
/// read as the pen rather than refused, because `DrawingStore.load` turns
/// a decode failure into an EMPTY drawing.
enum InkTool: String, Codable, CaseIterable {
    /// A ballpoint or gel pen: the handwriting tool.
    case pen
    /// A fountain pen: hairline with a light touch, swelling under pressure.
    case fountain
    /// A pencil: thin, nearly even, and grey where it is not pressed hard.
    case pencil
    /// A felt-tip marker: broad and even, pressure or none.
    case marker
    /// A brush: from nothing to broad with pressure, and a long tail off.
    case brush

    /// One tool's character. Tapers are in NIBS — the line's width at the
    /// middle pressure — so a bigger pen tapers over a longer run.
    struct Profile: Equatable {
        /// The line's width at the middle pressure, in stroke widths.
        var nib: Double
        /// How much pressure moves the width (perfect-freehand's
        /// `thinning`): 0 is an even line.
        var thinning: Double
        /// How far apart the outline's own points are kept, in sizes —
        /// and a size is never more than a nib (see `size(width:)`).
        var smoothing: Double
        /// How far each point is pulled towards the last: steadier and
        /// laggier as it rises.
        var streamline: Double
        /// The pressure response. Never below the middle at the middle —
        /// see `size(width:)`.
        var easing: InkOutline.Easing
        /// How long the line takes to come up to width, and to go off it.
        var startTaper: Double
        var endTaper: Double
        /// How much of the colour is laid down.
        var opacity: Double
    }

    /// THE TABLE. The pen is tuned for handwriting at 2–4 points: firm,
    /// slightly thinned by pressure (a light stroke is 0.7 of the width,
    /// a hard one 1.3), and streamlined only 0.4 so the ink stays under
    /// the nib — letters that look written with a ballpoint, not a felt
    /// tip. **AND IT HAS NO TAPER, SO BOTH ENDS ARE ROUND**, the way a
    /// ballpoint's are. A taper in perfect-freehand runs all the way down
    /// to nothing — a point — and the last three points of a line are
    /// noise to it, so even a short taper is a spike at least that long:
    /// the first cut tapered the pen a nib in and a nib and a half out,
    /// and every letter came to a point at both ends like a brush's tail
    /// (review, 2026-10-02). The pen's gentle ends come from the pressure
    /// instead: a nib touching down or lifting off writes at 0.7 of the
    /// width. The fountain pen, the pencil and the brush keep their
    /// tapers — a point is what those make.
    var profile: Profile {
        switch self {
        case .pen:
            return Profile(nib: 1, thinning: 0.3, smoothing: 0.5, streamline: 0.4, easing: .linear,
                           startTaper: 0, endTaper: 0, opacity: 1)
        case .fountain:
            return Profile(nib: 1.1, thinning: 0.5, smoothing: 0.6, streamline: 0.45, easing: .easeInOutQuad,
                           startTaper: 0.5, endTaper: 2.5, opacity: 1)
        case .pencil:
            return Profile(nib: 0.85, thinning: 0.15, smoothing: 0.4, streamline: 0.25, easing: .linear,
                           startTaper: 0.5, endTaper: 0.75, opacity: 0.75)
        case .marker:
            return Profile(nib: 2, thinning: 0, smoothing: 0.5, streamline: 0.5, easing: .linear,
                           startTaper: 0, endTaper: 0, opacity: 0.85)
        case .brush:
            return Profile(nib: 2, thinning: 0.8, smoothing: 0.65, streamline: 0.55, easing: .easeOutSine,
                           startTaper: 1, endTaper: 3, opacity: 1)
        }
    }

    var opacity: Double { profile.opacity }

    // MARK: - On the picker

    /// What the tool is called — in full, for a tooltip and for VoiceOver.
    var title: String {
        switch self {
        case .pen: return "Pen"
        case .fountain: return "Fountain Pen"
        case .pencil: return "Pencil"
        case .marker: return "Marker"
        case .brush: return "Brush"
        }
    }

    /// Under its icon on the picker, where five sit side by side.
    var shortTitle: String {
        switch self {
        case .fountain: return "Fountain"
        default: return title
        }
    }

    /// Its icon. Every one is in SF Symbols 2 or earlier, so all five draw
    /// on macOS 14 (`SymbolTests` checks they exist at all).
    var icon: String {
        switch self {
        case .pen: return "scribble"
        case .fountain: return "signature"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .brush: return "paintbrush.pointed"
        }
    }

    /// One line on what it writes like.
    var help: String {
        switch self {
        case .pen: return "A ballpoint: firm, a little heavier pressed hard, round at both ends — for handwriting"
        case .fountain: return "A fountain pen: a hairline at a light touch, swelling under pressure, a tail off the end"
        case .pencil: return "A pencil: thin, nearly even, and grey where it is not pressed hard"
        case .marker: return "A felt marker: broad and even, pressed or not"
        case .brush: return "A brush: from nothing to broad with pressure, and a long tail off"
        }
    }

    /// The line's width at the middle pressure, in points.
    func nibWidth(width: Double) -> Double { width * profile.nib }

    /// `size` for the outline: the diameter at the middle pressure is
    /// `size × 2 × easing(0.5)`, so dividing that out makes it `nibWidth`.
    /// With no thinning the outline ignores pressure and the easing both,
    /// and the size IS the width.
    ///
    /// **NO TOOL'S SIZE IS MORE THAN ITS NIB.** perfect-freehand reads
    /// `size` as a LENGTH as well: it skips the samples inside the first
    /// `size` of a line, and keeps the outline's points `size × smoothing`
    /// apart. An easing that is below the middle at the middle stretches
    /// both — the fountain pen's first easing (easeInQuad, 0.25 there)
    /// made its size two nibs, so at 3 points it skipped the first 6.6
    /// points of every stroke, drew an e's entry hook as a straight chord
    /// and set its outline points further apart than the line was wide
    /// (review, 2026-10-02). So every easing in the table is at or above
    /// 0.5 at 0.5, and `InkToolTests` holds it.
    func size(width: Double) -> Double {
        let profile = profile
        guard profile.thinning != 0 else { return nibWidth(width: width) }
        return nibWidth(width: width) / (2 * profile.easing(0.5))
    }

    /// Half the widest this ink can lay down, at any pressure — what a
    /// stroke's bounds and its hit testing measure (`Stroke.reach`).
    func reach(width: Double) -> Double {
        let profile = profile
        let size = size(width: width)
        guard profile.thinning != 0 else { return size / 2 }
        let light = InkOutline.strokeRadius(size: size, thinning: profile.thinning, pressure: 0, easing: profile.easing)
        let hard = InkOutline.strokeRadius(size: size, thinning: profile.thinning, pressure: 1, easing: profile.easing)
        return max(light, hard)
    }

    /// The outline of one stroke written with this tool — the samples in
    /// view points, `simulated` when the device reported no pressure. The
    /// one way in for every painter (`InkPaths.ink`), and the rule the
    /// cross-platform app copies step for step (docs/CROSS-PLATFORM.md).
    ///
    /// **A TAP IS A DOT, HOWEVER MANY EVENTS IT MADE.** Two kinds of
    /// stroke are taps: one whose every sample is within half a nib of
    /// where the nib went down (it never left its own footprint), and one
    /// the outline measures shorter than its own end noise. perfect-
    /// freehand treats the last three points of a line as noise
    /// (`endNoiseThreshold`) and keeps nothing there but the final sample,
    /// so a stroke that short is ALL end: tapered at both ends it came out
    /// three points, which is no path at all — a wobbly tap or a quick
    /// flick at a thin pen was saved, selectable and invisible (review,
    /// 2026-10-02) — and untapered it is a lopsided blob as wide as the
    /// flick was long. A tap is drawn as ONE sample, where the nib went
    /// down, pressed as hard as the tap was at its hardest, handed over
    /// twice — which perfect-freehand draws as its own round dot (one
    /// sample ALONE it gives a neighbour one point off on both axes, a
    /// little diagonal dash). One event, two, a jittery handful or a nib
    /// held still: the same dot in the same place, sized by how hard it
    /// pressed, and it neither wanders nor shrinks while the nib is down.
    ///
    /// The length is the one the outline itself goes by: the
    /// `runningLength` of the last streamlined point
    /// (`InkOutline.strokePoints`, which the tapers do not change), not
    /// the polyline through the raw samples — streamlining pulls the line
    /// in, and the samples skipped at its start still count towards it.
    /// The tapers are scaled by that same number (`options`), and a line
    /// tapered at both ends that keeps no point at full width between the
    /// two ramps (`hasBody`) is drawn with neither: both ramps run down to
    /// nothing, and with nothing between them the line is a sliver.
    func outline(_ samples: [InkOutline.Sample], width: Double, simulated: Bool) -> [CGPoint] {
        guard let first = samples.first else { return [] }
        let untapered = options(width: width, simulated: simulated, length: 0)
        let points = InkOutline.strokePoints(samples, options: untapered)
        let length = points.last?.runningLength ?? 0
        let footprint = nibWidth(width: width) / 2
        let still = samples.allSatisfy { hypot($0.point.x - first.point.x, $0.point.y - first.point.y) <= footprint }
        if still || length < InkOutline.endNoiseThreshold {
            let hardest = samples.compactMap(\.pressure).filter { $0 >= 0 }.max()
            let dot = InkOutline.Sample(first.point, pressure: hardest)
            return InkOutline.stroke([dot, dot], options: untapered)
        }
        var options = options(width: width, simulated: simulated, length: length)
        if !Self.hasBody(points, length: length, options: options) {
            options.start.taper = .none
            options.end.taper = .none
        }
        return InkOutline.outlinePoints(points, options: options)
    }

    /// Whether a line tapered at BOTH ends keeps a point at full width
    /// between them: a streamlined point, neither the first nor the last,
    /// past the start's ramp and further from the end than both the end's
    /// ramp and the noise the outline drops there. With none, every point
    /// it draws is on a ramp, and both ramps run down to nothing.
    static func hasBody(_ points: [InkOutline.StrokePoint], length: Double,
                        options: InkOutline.Options) -> Bool {
        guard case .distance(let start) = options.start.taper,
              case .distance(let end) = options.end.taper else { return true }
        return points.dropFirst().dropLast().contains {
            $0.runningLength >= start && length - $0.runningLength >= max(end, InkOutline.endNoiseThreshold)
        }
    }

    /// The options for one stroke: its width, whether the pressure is real
    /// (`simulated` false) or has to be guessed from speed, and its length
    /// as the outline measures it (see `outline`).
    ///
    /// The tapers never take more than a third, between them, of the
    /// stretch the outline keeps points along — the length less the first
    /// `size` (skipped) and the last three points (noise) — and an end
    /// whose taper would be under a quarter of a nib gets no taper at all,
    /// which is a round end. A taper is a ramp from NOTHING, so on a
    /// stroke shorter than its own ramps it leaves a sliver. Scaling,
    /// rather than a cut-off, keeps two strokes of nearly the same length
    /// looking nearly the same.
    ///
    /// `last` is always true: the line runs to where the nib IS, live and
    /// finished alike, so nothing jumps when the pen comes up.
    func options(width: Double, simulated: Bool, length: Double) -> InkOutline.Options {
        let profile = profile
        let nib = nibWidth(width: width)
        let size = size(width: width)
        var start = profile.startTaper * nib
        var end = profile.endTaper * nib
        let wanted = start + end
        if wanted > 0 {
            // The stretch the outline keeps points along: past the
            // samples it skips at the start (the first `size`) and short
            // of the ones it drops as noise at the end.
            let body = length - InkOutline.endNoiseThreshold - size
            let share = min(1, max(0, body) / 3 / wanted)
            start *= share
            end *= share
        }
        if start < nib / 4 { start = 0 }
        if end < nib / 4 { end = 0 }
        return InkOutline.Options(size: size,
                                  thinning: profile.thinning,
                                  smoothing: profile.smoothing,
                                  streamline: profile.streamline,
                                  easing: profile.easing,
                                  simulatePressure: simulated,
                                  start: InkOutline.End(cap: true, taper: start > 0 ? .distance(start) : .none),
                                  end: InkOutline.End(cap: true, taper: end > 0 ? .distance(end) : .none),
                                  last: true)
    }
}
