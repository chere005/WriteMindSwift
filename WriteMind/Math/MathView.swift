import SwiftUI

/// Maths on a line of its own, set in two dimensions: fractions stack, ∑ and
/// ∏ carry their limits above and below, a root gets its roof, a bracket
/// grows to what it holds. The expression is any WL `WLParser` reads — a
/// derivative from the palette and a formula typed by hand are the same to
/// it (Sean, 2026-10-03: "maths input should also just allow for an
/// expression") — set by `MathLayout` and painted here.
///
/// A line too wide for the page scrolls sideways rather than being cut off.
struct MathView: View {
    let source: String
    var size: CGFloat = 19

    var body: some View {
        switch WLParser.read(source) {
        case .success(let expression):
            let drawing = MathDrawingCache.drawing(for: source, expression: expression, size: size)
            let label = MathTypesetter.reading(source) ?? source
            ViewThatFits(in: .horizontal) {
                MathCanvas(drawing: drawing, label: label)
                ScrollView(.horizontal, showsIndicators: false) {
                    MathCanvas(drawing: drawing, label: label)
                }
            }
        case .failure(let error):
            // Half-typed maths is still the user's text: show it as it stands.
            Text(source)
                .font(.system(size: size, design: .monospaced))
                .foregroundStyle(.secondary)
                .help(error.message)
        }
    }
}

/// One set expression, painted. Its size is what `MathLayout` measured.
struct MathCanvas: View {
    let drawing: MathDrawing
    var label = ""
    /// Room round the ink, so nothing is clipped at the edge of the canvas.
    static let inset: CGFloat = 3

    var body: some View {
        Canvas { context, _ in
            let color = Color.primary.resolve(in: context.environment).cgColor
            context.withCGContext { cg in
                // A Canvas's CGContext is y-down with an identity matrix: only the caller can know (see `draw`).
                drawing.draw(in: cg, origin: CGPoint(x: Self.inset, y: Self.inset + drawing.ascent), color: color,
                             yDown: true)
            }
        }
        .frame(width: MathCanvas.size(of: drawing).width, height: MathCanvas.size(of: drawing).height)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    static func size(of drawing: MathDrawing) -> CGSize {
        CGSize(width: ceil(drawing.width) + inset * 2, height: ceil(drawing.height) + inset * 2)
    }
}

/// A page full of maths is laid out again whenever it is drawn again, and a
/// layout measures every glyph: so the drawings are kept, by what was typed
/// and how big it is set.
enum MathDrawingCache {
    private final class Entry {
        let drawing: MathDrawing
        init(_ drawing: MathDrawing) { self.drawing = drawing }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 400
        return cache
    }()

    static func drawing(for source: String, expression: WLExpr, size: CGFloat) -> MathDrawing {
        let key = "\(size)|\(source)" as NSString
        if let known = cache.object(forKey: key) { return known.drawing }
        let drawing = MathLayout.drawing(for: MathBuilder.box(expression), size: size)
        cache.setObject(Entry(drawing), forKey: key)
        return drawing
    }
}
