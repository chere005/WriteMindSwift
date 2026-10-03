import AppKit
import CoreText

/// MATHS SET IN TWO DIMENSIONS: a `MathBox` measured and placed, ready to
/// be painted by anything with a `CGContext`.
///
/// Sean, 2026-10-03: "maths input should also just allow for an expression
/// so i could insert a function or something and it would appear like the
/// derivatives or integrals". A formula is a sum with a fraction in it with a
/// root in that, and stacked views with a baseline each cannot line those
/// up — `x + a/b` came out with the `x +` level with the top of the
/// fraction. So this is a typesetter, not a pile of stacks: every part has a
/// width, an ascent over the baseline and a descent under it, a row lines its
/// parts up on the one baseline, a fraction hangs its bar on the axis the
/// signs of `+` and `=` are drawn on, a script is raised by how tall its
/// base is, a fence is drawn to the height of what it holds, and a big
/// operator is centred on the axis with its limits over and under it.
///
/// It paints from its own measurements — text with CoreText at the sizes it
/// measured, the rest as filled paths — so what was measured is what lands,
/// and `MathLayoutTests` can say where things are in numbers.
struct MathDrawing {
    /// A run of text: where its baseline starts, y up from the baseline of
    /// the whole.
    struct Run {
        let text: String
        let face: MathFace
        let size: CGFloat
        let origin: CGPoint
    }

    var width: CGFloat = 0
    /// How far it reaches above the baseline, and below it.
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var runs: [Run] = []
    /// Every rule, fence, root and sign that is not text, as one path to be
    /// filled.
    var shapes = CGMutablePath()

    var height: CGFloat { ascent + descent }

    /// Another drawing set down at `offset` from this one's baseline-left.
    mutating func place(_ other: MathDrawing, dx: CGFloat, dy: CGFloat) {
        for run in other.runs {
            runs.append(Run(text: run.text, face: run.face, size: run.size,
                            origin: CGPoint(x: run.origin.x + dx, y: run.origin.y + dy)))
        }
        if !other.shapes.isEmpty {
            shapes.addPath(other.shapes, transform: CGAffineTransform(translationX: dx, y: dy))
        }
        width = max(width, dx + other.width)
        ascent = max(ascent, dy + other.ascent)
        descent = max(descent, other.descent - dy)
    }

    // MARK: - Painting

    /// Paints with the baseline's left end at `origin` — in a context whose
    /// y runs down (a SwiftUI `Canvas`, a flipped view) or up (a PDF, a
    /// bitmap), which it reads off the context's own matrix.
    func draw(in context: CGContext, origin: CGPoint, color: CGColor) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(color)
        context.translateBy(x: origin.x, y: origin.y)
        if context.ctm.d < 0 { context.scaleBy(x: 1, y: -1) }
        if !shapes.isEmpty {
            context.addPath(shapes)
            context.fillPath()
        }
        context.textMatrix = .identity
        for run in runs {
            let line = MathFonts.line(run.text, face: run.face, size: run.size)
            context.textPosition = run.origin
            CTLineDraw(line, context)
        }
    }
}

/// The type maths is set in, measured by what it actually inks: the height
/// of an `x` is not the height of a `d`, and a fraction hung on the first
/// would sit differently from one hung on the second.
enum MathFonts {
    struct Metrics {
        /// How far the pen moves: the text's own advance, or where the ink
        /// stops when it reaches past it — an italic f and an x lean over
        /// the next character otherwise.
        let advance: CGFloat
        /// How far left of the pen the ink starts, which the text is moved
        /// to the right by (an f's tail).
        let leftOverhang: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
    }

    private struct Key: Hashable {
        let text: String
        let italic: Bool
        let size: CGFloat
    }

    private static let lock = NSLock()
    private static var metrics: [Key: Metrics] = [:]

    static func font(_ face: MathFace, size: CGFloat) -> CTFont {
        let base = NSFont.systemFont(ofSize: size)
        var descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        if face == .italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return (NSFont(descriptor: descriptor, size: size) ?? base) as CTFont
    }

    static func line(_ text: String, face: MathFace, size: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(face, size: size),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    static func measure(_ text: String, face: MathFace, size: CGFloat) -> Metrics {
        let key = Key(text: text, italic: face == .italic, size: size)
        lock.lock()
        if let known = metrics[key] { lock.unlock(); return known }
        lock.unlock()

        let line = MathFonts.line(text, face: face, size: size)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let blank = text.allSatisfy(\.isWhitespace) || ink.isNull || ink.isEmpty
        let found = Metrics(advance: blank ? advance : max(advance, ink.maxX),
                            leftOverhang: blank ? 0 : max(-ink.minX, 0),
                            ascent: blank ? 0 : max(ink.maxY, 0),
                            descent: blank ? 0 : max(-ink.minY, 0))
        lock.lock()
        if metrics.count > 4000 { metrics.removeAll() }
        metrics[key] = found
        lock.unlock()
        return found
    }
}

enum MathLayout {
    /// The part of the type's size the signs of `+` and `=` sit above the
    /// baseline, which is where a fraction's bar is hung.
    static let axis: CGFloat = 0.25
    /// What a script is set at, against its base.
    static let scriptScale: CGFloat = 0.7
    /// Nothing is set smaller than this, however deep it is in scripts and
    /// fractions: type at a fraction of a point is no use to anyone, and a
    /// size of nothing is the system's own default.
    static let smallest: CGFloat = 5

    /// `box` set at `size` points.
    static func drawing(for box: MathBox, size: CGFloat) -> MathDrawing {
        lay(box, size: size, depth: 0)
    }

    // MARK: - The parts

    private static func lay(_ box: MathBox, size: CGFloat, depth: Int) -> MathDrawing {
        switch box {
        case .glyphs(let text, let face):
            guard !text.isEmpty else { return MathDrawing() }
            let metrics = MathFonts.measure(text, face: face, size: size)
            var out = MathDrawing()
            out.width = metrics.leftOverhang + metrics.advance
            out.ascent = metrics.ascent
            out.descent = metrics.descent
            out.runs = [MathDrawing.Run(text: text, face: face, size: size,
                                        origin: CGPoint(x: metrics.leftOverhang, y: 0))]
            return out

        case .space(let em):
            var out = MathDrawing()
            out.width = CGFloat(em) * size
            return out

        case .row(let items, _):
            var out = MathDrawing()
            for item in items {
                let part = lay(item, size: size, depth: depth)
                out.place(part, dx: out.width, dy: 0)
            }
            return out

        case .fraction(let top, let bottom, let bar):
            return fraction(top, bottom, bar: bar, size: size, depth: depth)

        case .script(let base, let sup, let sub):
            return scripted(base, sup: sup, sub: sub, size: size, depth: depth)

        case .radical(let inside):
            return radical(inside, size: size, depth: depth)

        case .fenced(let fence, let inside):
            return fenced(fence, inside, size: size, depth: depth)

        case .large(let inner, let display, _):
            let scaled = lay(inner, size: size * CGFloat(display), depth: depth)
            // Centred on the axis, where a sign of this size belongs.
            let shift = axis * size - (scaled.ascent - scaled.descent) / 2
            var out = MathDrawing()
            out.place(scaled, dx: 0, dy: shift)
            out.width = scaled.width
            return out

        case .limits(let op, let above, let below):
            return limits(op, above: above, below: below, size: size, depth: depth)

        case .sideLimits(let op, let above, let below):
            return sideLimits(op, above: above, below: below, size: size, depth: depth)

        case .matrix(let rows):
            return matrix(rows, size: size, depth: depth)

        case .choice(let display, _):
            return lay(display, size: size, depth: depth)
        }
    }

    // MARK: - Fractions and scripts

    private static func fraction(_ top: MathBox, _ bottom: MathBox, bar: Bool, size: CGFloat,
                                 depth: Int) -> MathDrawing {
        // The parts of a fraction inside a fraction are smaller, or a
        // continued fraction is a tower.
        let partSize = max(size * (depth == 0 ? 0.96 : 0.82), MathLayout.smallest)
        let numerator = lay(top, size: partSize, depth: depth + 1)
        let denominator = lay(bottom, size: partSize, depth: depth + 1)

        let thickness = bar ? max(size * 0.055, 0.7) : 0
        let gap = size * 0.15
        let padding = bar ? size * 0.12 : size * 0.04
        let width = max(numerator.width, denominator.width) + padding * 2
        let barY = axis * size

        // The denominator's baseline holds still for every denominator of
        // ordinary height; a taller one pushes it down.
        let denominatorHeight = max(denominator.ascent, partSize * 0.74)
        let numeratorBaseline = barY + thickness / 2 + gap + numerator.descent
        let denominatorBaseline = barY - thickness / 2 - gap - denominatorHeight

        var out = MathDrawing()
        out.place(numerator, dx: (width - numerator.width) / 2, dy: numeratorBaseline)
        out.place(denominator, dx: (width - denominator.width) / 2, dy: denominatorBaseline)
        if bar {
            out.shapes.addRect(CGRect(x: padding * 0.5, y: barY - thickness / 2,
                                      width: width - padding, height: thickness))
        }
        out.width = width
        return out
    }

    private static func scripted(_ base: MathBox, sup: MathBox?, sub: MathBox?, size: CGFloat,
                                 depth: Int) -> MathDrawing {
        let main = lay(base, size: size, depth: depth)
        let scriptSize = max(size * scriptScale, smallest)
        let raised = sup.map { lay($0, size: scriptSize, depth: depth) }
        let lowered = sub.map { lay($0, size: scriptSize, depth: depth) }

        // Raised by how tall what it sits on is — a power of a bracket is
        // higher than a power of an x.
        let up = max(size * 0.41, main.ascent - size * 0.28)
        var down = max(size * 0.18, main.descent + size * 0.06)
        if let raised, let lowered {
            let clear = (up - raised.descent) - (lowered.ascent - down)
            if clear < size * 0.15 { down += size * 0.15 - clear }
        }

        var out = MathDrawing()
        out.place(main, dx: 0, dy: 0)
        let kern = main.width > 0 ? size * 0.03 : 0
        if let raised { out.place(raised, dx: main.width + kern, dy: up) }
        if let lowered { out.place(lowered, dx: main.width + kern, dy: -down) }
        out.width = main.width + kern + max(raised?.width ?? 0, lowered?.width ?? 0)
            + (raised == nil && lowered == nil ? 0 : size * 0.04)
        return out
    }

    // MARK: - Roots

    private static func radical(_ inside: MathBox, size: CGFloat, depth: Int) -> MathDrawing {
        let content = lay(inside, size: size, depth: depth)
        let stroke = max(size * 0.055, 0.8)
        let signWidth = size * 0.62
        let pad = size * 0.05
        let bottom = -(content.descent + size * 0.05)
        let roof = content.ascent + size * 0.14
        let height = roof - bottom

        // The hook, the long stroke down, the stroke up, the roof over what
        // it holds — one line, drawn with a pen of one width.
        let line = CGMutablePath()
        line.move(to: CGPoint(x: size * 0.02, y: bottom + height * 0.42))
        line.addLine(to: CGPoint(x: signWidth * 0.2, y: bottom + height * 0.5))
        line.addLine(to: CGPoint(x: signWidth * 0.5, y: bottom))
        line.addLine(to: CGPoint(x: signWidth, y: roof))
        line.addLine(to: CGPoint(x: signWidth + pad * 2 + content.width, y: roof))
        let inked = line.copy(strokingWithWidth: stroke, lineCap: .butt, lineJoin: .round, miterLimit: 10)

        var out = MathDrawing()
        out.shapes.addPath(inked)
        out.place(content, dx: signWidth + pad, dy: 0)
        out.width = signWidth + pad * 2 + content.width
        out.ascent = max(out.ascent, roof + stroke / 2)
        out.descent = max(out.descent, -bottom + stroke / 2)
        return out
    }

    // MARK: - Fences

    private static func fenced(_ fence: MathFence, _ inside: MathBox, size: CGFloat, depth: Int) -> MathDrawing {
        let content = lay(inside, size: size, depth: depth)
        let axisY = axis * size
        let half = max(max(content.ascent - axisY, content.descent + axisY) + size * 0.06, size * 0.5)
        let top = axisY + half, bottom = axisY - half
        let tall = half / size
        let width = fenceWidth(fence, size: size, tall: tall)
        let pad = size * 0.06

        var out = MathDrawing()
        out.shapes.addPath(fenceShape(fence, open: true, x: 0, width: width, top: top, bottom: bottom, size: size))
        out.place(content, dx: width + pad, dy: 0)
        let closeX = width + pad * 2 + content.width
        out.shapes.addPath(fenceShape(fence, open: false, x: closeX, width: width, top: top, bottom: bottom, size: size))
        out.width = closeX + width
        out.ascent = max(out.ascent, top)
        out.descent = max(out.descent, -bottom)
        return out
    }

    static func fenceWidth(_ fence: MathFence, size: CGFloat, tall: CGFloat) -> CGFloat {
        switch fence {
        case .paren, .brace: return size * min(0.26 + 0.05 * max(tall - 0.5, 0), 0.5)
        case .bracket, .floor, .ceiling: return size * 0.28
        case .part: return size * 0.38
        case .bar: return size * 0.2
        case .doubleBar: return size * 0.3
        }
    }

    /// One bracket as a shape to be filled: a crescent for a parenthesis,
    /// bars and arms for the rest, drawn to `top` and `bottom` whatever the
    /// type's own height is.
    static func fenceShape(_ fence: MathFence, open: Bool, x: CGFloat, width: CGFloat, top: CGFloat,
                           bottom: CGFloat, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let thick = max(size * 0.06, 0.8)
        let height = top - bottom
        let middle = (top + bottom) / 2
        // Local x from the fence's own outer edge, mirrored for the closer.
        func px(_ local: CGFloat) -> CGFloat { open ? x + local : x + width - local }
        func bar(at local: CGFloat, from: CGFloat, to: CGFloat, thickness: CGFloat) {
            let edge = open ? px(local) : px(local) - thickness
            path.addRect(CGRect(x: edge, y: from, width: thickness, height: to - from))
        }
        func arm(top atTop: Bool, from local: CGFloat, length: CGFloat) {
            let y = atTop ? top - thick : bottom
            let edge = open ? px(local) : px(local) - length
            path.addRect(CGRect(x: edge, y: y, width: length, height: thick))
        }

        switch fence {
        case .paren:
            // The outer curve bulges to the outside, the inner one lies
            // inside it, and the two meet at the tips: thin at the ends,
            // full in the middle.
            let tip = width * 0.85
            let outerMiddle = width * 0.08
            let outerControl = 2 * outerMiddle - tip
            let innerControl = 2 * (outerMiddle + thick * 1.15) - tip
            path.move(to: CGPoint(x: px(tip), y: top))
            path.addQuadCurve(to: CGPoint(x: px(tip), y: bottom), control: CGPoint(x: px(outerControl), y: middle))
            path.addQuadCurve(to: CGPoint(x: px(tip), y: top), control: CGPoint(x: px(innerControl), y: middle))
            path.closeSubpath()
        case .brace:
            // Two arcs in and one point out at the middle, stroked with a
            // pen of one width.
            let line = CGMutablePath()
            let tip = width * 0.9, stem = width * 0.52, point = width * 0.12
            let reach = min(height * 0.16, width * 1.1)
            line.move(to: CGPoint(x: px(tip), y: top - thick / 2))
            line.addQuadCurve(to: CGPoint(x: px(stem), y: top - reach), control: CGPoint(x: px(stem), y: top - thick / 2))
            line.addLine(to: CGPoint(x: px(stem), y: middle + reach))
            line.addQuadCurve(to: CGPoint(x: px(point), y: middle), control: CGPoint(x: px(stem), y: middle))
            line.addQuadCurve(to: CGPoint(x: px(stem), y: middle - reach), control: CGPoint(x: px(stem), y: middle))
            line.addLine(to: CGPoint(x: px(stem), y: bottom + reach))
            line.addQuadCurve(to: CGPoint(x: px(tip), y: bottom + thick / 2), control: CGPoint(x: px(stem), y: bottom + thick / 2))
            path.addPath(line.copy(strokingWithWidth: thick, lineCap: .round, lineJoin: .round, miterLimit: 10))
        case .bracket:
            bar(at: width * 0.3, from: bottom, to: top, thickness: thick)
            arm(top: true, from: width * 0.3, length: width * 0.6)
            arm(top: false, from: width * 0.3, length: width * 0.6)
        case .floor:
            bar(at: width * 0.3, from: bottom, to: top, thickness: thick)
            arm(top: false, from: width * 0.3, length: width * 0.6)
        case .ceiling:
            bar(at: width * 0.3, from: bottom, to: top, thickness: thick)
            arm(top: true, from: width * 0.3, length: width * 0.6)
        case .part:
            bar(at: width * 0.15, from: bottom, to: top, thickness: thick)
            bar(at: width * 0.15 + thick * 1.8, from: bottom, to: top, thickness: thick)
            arm(top: true, from: width * 0.15, length: width * 0.75)
            arm(top: false, from: width * 0.15, length: width * 0.75)
        case .bar:
            bar(at: width * 0.5 - thick / 2, from: bottom, to: top, thickness: thick)
        case .doubleBar:
            bar(at: width * 0.5 - thick * 1.4, from: bottom, to: top, thickness: thick)
            bar(at: width * 0.5 + thick * 0.4, from: bottom, to: top, thickness: thick)
        }
        return path
    }

    // MARK: - Big operators

    /// ∑ ∏ lim: the operator on the baseline's axis, what it runs over
    /// above it and what it runs from under it, each centred on it.
    private static func limits(_ op: MathBox, above: MathBox?, below: MathBox?, size: CGFloat,
                               depth: Int) -> MathDrawing {
        let sign = lay(op, size: size, depth: depth)
        let limitSize = max(size * scriptScale, smallest)
        let over = above.map { lay($0, size: limitSize, depth: depth) }
        let under = below.map { lay($0, size: limitSize, depth: depth) }
        let gap = size * 0.1
        let width = max(sign.width, over?.width ?? 0, under?.width ?? 0)

        var out = MathDrawing()
        out.place(sign, dx: (width - sign.width) / 2, dy: 0)
        if let over { out.place(over, dx: (width - over.width) / 2, dy: sign.ascent + gap + over.descent) }
        if let under { out.place(under, dx: (width - under.width) / 2, dy: -(sign.descent + gap + under.ascent)) }
        out.width = width
        return out
    }

    /// ∫: the limits beside the sign — the end at the top of it, the start
    /// at the foot.
    private static func sideLimits(_ op: MathBox, above: MathBox?, below: MathBox?, size: CGFloat,
                                   depth: Int) -> MathDrawing {
        let sign = lay(op, size: size, depth: depth)
        let limitSize = max(size * scriptScale, smallest)
        let over = above.map { lay($0, size: limitSize, depth: depth) }
        let under = below.map { lay($0, size: limitSize, depth: depth) }

        var out = MathDrawing()
        out.place(sign, dx: 0, dy: 0)
        var width = sign.width
        // An integral sign leans: its top is to the right of its foot, so
        // the limit at the top starts at its edge and the one at the foot
        // under the middle of it.
        if let over {
            out.place(over, dx: sign.width + size * 0.02, dy: sign.ascent - over.ascent - size * 0.04)
            width = max(width, sign.width + size * 0.02 + over.width)
        }
        if let under {
            out.place(under, dx: sign.width * 0.66, dy: -sign.descent + under.descent + size * 0.04)
            width = max(width, sign.width * 0.66 + under.width)
        }
        out.width = width + size * 0.04
        return out
    }

    // MARK: - Matrices

    private static func matrix(_ rows: [[MathBox]], size: CGFloat, depth: Int) -> MathDrawing {
        let laid = rows.map { $0.map { lay($0, size: size, depth: depth) } }
        let columns = laid.map(\.count).max() ?? 0
        guard columns > 0 else { return MathDrawing() }

        var widths = [CGFloat](repeating: 0, count: columns)
        for row in laid { for (index, cell) in row.enumerated() { widths[index] = max(widths[index], cell.width) } }
        // Every row at least as tall as a line of type, so a row of `1 2`
        // does not sit closer to its neighbours than a row of `a b`.
        let ascents = laid.map { row in max(row.map(\.ascent).max() ?? 0, size * 0.66) }
        let descents = laid.map { row in max(row.map(\.descent).max() ?? 0, size * 0.18) }
        let rowGap = size * 0.4, columnGap = size * 0.9
        let height = zip(ascents, descents).map { $0 + $1 }.reduce(0, +) + rowGap * CGFloat(max(laid.count - 1, 0))

        var out = MathDrawing()
        var y = axis * size + height / 2
        for (rowIndex, row) in laid.enumerated() {
            y -= ascents[rowIndex]
            var x: CGFloat = 0
            for column in 0..<columns {
                if column < row.count {
                    out.place(row[column], dx: x + (widths[column] - row[column].width) / 2, dy: y)
                }
                x += widths[column] + columnGap
            }
            y -= descents[rowIndex] + rowGap
        }
        out.width = widths.reduce(0, +) + columnGap * CGFloat(columns - 1)
        out.ascent = max(out.ascent, axis * size + height / 2)
        out.descent = max(out.descent, height / 2 - axis * size)
        return out
    }
}
