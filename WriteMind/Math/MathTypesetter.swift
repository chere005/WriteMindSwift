import SwiftUI

/// Maths inside a line of prose: one `AttributedString`, with real raised and
/// lowered scripts, so it sits in a paragraph without a view of its own.
/// Anything that would need two dimensions — a stacked fraction, a radical
/// with a roof — is written the linear way here and stacked properly by
/// `MathView` when it is on its own line.
///
/// This is the second painter of one decision: `MathBuilder` turns the
/// expression into a `MathBox`, and `MathLayout` paints it in two dimensions
/// while this writes it on one line. Nothing here knows what a derivative or
/// a sum is — only what a fraction, a script, a fence and a limit are — so
/// anything the builder can set, a palette shape or a formula typed by hand,
/// comes out in the sentence as well.
enum MathTypesetter {
    static func inline(_ source: String, size: CGFloat = 15) -> AttributedString? {
        guard let expr = WLParser.parse(source) else { return nil }
        return render(expr, size: size)
    }

    static func render(_ expr: WLExpr, size: CGFloat) -> AttributedString {
        paint(MathBuilder.box(expr), size: size)
    }

    /// What it says, as plain text — a reading for anything that cannot
    /// show the set maths (VoiceOver, the footer).
    static func reading(_ source: String) -> String? {
        inline(source).map { String($0.characters) }
    }

    // MARK: - Painting a box on one line

    static func paint(_ box: MathBox, size: CGFloat) -> AttributedString {
        switch box {
        case .glyphs(let text, let face):
            return plain(text, size: size, italic: face == .italic)
        case .space(let em):
            return plain(gap(em), size: size)
        case .row(let items, _):
            var out = AttributedString()
            for item in items { out.append(paint(item, size: size)) }
            return out
        case .fraction(let top, let bottom, let bar):
            guard bar else {
                var out = paint(top, size: size)
                out.append(plain("\u{2009}", size: size))
                out.append(paint(bottom, size: size))
                return out
            }
            var out = grouped(top, atLeast: WLLevel.product, size: size)
            out.append(plain("/", size: size))
            out.append(grouped(bottom, atLeast: WLLevel.product + 1, size: size))
            return out
        case .script(let base, let sup, let sub):
            var out = paint(base, size: size)
            if let sup { out.append(script(paint(sup, size: size * 0.7), size: size, raised: true)) }
            if let sub { out.append(script(paint(sub, size: size * 0.7), size: size, raised: false)) }
            return out
        case .radical(let inside):
            var out = plain("√", size: size)
            out.append(grouped(inside, atLeast: WLLevel.atom, size: size))
            return out
        case .fenced(let fence, let inside):
            var out = plain(fence.open, size: size)
            out.append(paint(inside, size: size))
            out.append(plain(fence.close, size: size))
            return out
        case .large(let inner, _, let inline):
            return paint(inner, size: size * inline)
        case .limits(let op, let above, let below), .sideLimits(let op, let above, let below):
            var out = paint(op, size: size)
            if let below { out.append(script(paint(below, size: size * 0.7), size: size, raised: false)) }
            if let above { out.append(script(paint(above, size: size * 0.7), size: size, raised: true)) }
            return out
        case .matrix(let rows):
            var out = AttributedString()
            for (index, row) in rows.enumerated() {
                if index > 0 { out.append(plain("; ", size: size)) }
                for (column, cell) in row.enumerated() {
                    if column > 0 { out.append(plain(", ", size: size)) }
                    out.append(paint(cell, size: size))
                }
            }
            return out
        case .choice(_, let inline):
            return paint(inline, size: size)
        }
    }

    /// A gap, in the characters a line of text has for one.
    private static func gap(_ em: Double) -> String {
        if em >= 0.15 { return " " }
        return em > 0 ? "\u{2009}" : ""       // a thin space, the way maths multiplies
    }

    /// In brackets where it holds together less tightly than a line of
    /// text can show without them.
    private static func grouped(_ box: MathBox, atLeast level: Int, size: CGFloat) -> AttributedString {
        guard box.level < level else { return paint(box, size: size) }
        var out = plain("(", size: size)
        out.append(paint(box, size: size))
        out.append(plain(")", size: size))
        return out
    }

    // MARK: - Pieces

    static func plain(_ string: String, size: CGFloat, italic: Bool = false) -> AttributedString {
        var piece = AttributedString(string)
        piece.font = italic
            ? .system(size: size, design: .serif).italic()
            : .system(size: size, design: .serif)
        return piece
    }

    /// Raised or lowered, and smaller — an exponent, or the bounds of a
    /// sum. What is inside it may be a script of its own, and its offset
    /// is added to, not replaced.
    static func script(_ piece: AttributedString, size: CGFloat, raised: Bool) -> AttributedString {
        var out = piece
        let offset = raised ? size * 0.36 : -size * 0.22
        for (range, current) in out.runs.map({ ($0.range, $0.baselineOffset) }) {
            out[range].baselineOffset = (current ?? 0) + offset
        }
        return out
    }
}

/// How maths is spelled in a note: WL inside a code span for a line of prose,
/// and a `wl` fence for maths on its own. Both are ordinary markdown, so a
/// note still opens anywhere.
enum MathMarkup {
    static let inlinePrefix = "wl:"
    static let fence = "wl"

    static func inline(_ wl: String) -> String { "`" + inlinePrefix + wl + "`" }
    static func block(_ wl: String) -> String { "```" + fence + "\n" + wl + "\n```" }

    /// The WL inside a code span, or nil when the span is just code.
    static func expression(inCode text: String) -> String? {
        guard text.hasPrefix(inlinePrefix) else { return nil }
        let expression = String(text.dropFirst(inlinePrefix.count)).trimmingCharacters(in: .whitespaces)
        return expression.isEmpty ? nil : expression
    }

    /// Only `wl` is maths. `wolfram` used to be an alias for it and is now
    /// a CODE language, set in monospace and coloured (Sean, 2026-09-19:
    /// "make sure to support c, cpp, wolfram, python, typescript code
    /// blocks") — the maths button has always written `wl`.
    static func isMathFence(_ language: String?) -> Bool {
        language?.lowercased() == fence
    }
}
