import Foundation

/// What the maths button offers. Every one of them writes Wolfram Language,
/// which is what a note actually holds (Sean, 2026-09-18) — `#1`, `#2` … are
/// the slots the fields fill in.
struct MathTemplate: Identifiable, Equatable {
    enum Group: String, CaseIterable, Identifiable {
        case calculus = "Calculus"
        case algebra = "Algebra"
        case functions = "Functions"
        case relations = "Relations"
        case symbols = "Symbols"
        case greek = "Greek"

        var id: String { rawValue }
    }

    struct Slot: Equatable {
        let label: String
        let initial: String
    }

    let id: String
    let group: Group
    let name: String
    /// What the palette button shows.
    let glyph: String
    let form: String
    var slots: [Slot] = []

    var initialValues: [String] { slots.map(\.initial) }

    /// What the fields start as when the palette was opened over a
    /// selection that reads as maths: the selection in the first slot, so
    /// the shape picked wraps it — √ of it, the integral of it — and the
    /// rest as they always start. A shape with no slots has nowhere to put
    /// it.
    func values(seed: String?) -> [String] {
        var values = initialValues
        if let seed, !values.isEmpty { values[0] = seed }
        return values
    }

    /// The WL this writes. A slot left empty falls back to what it suggested —
    /// an empty integrand is a slip, not an intention.
    ///
    /// A slot an OPERATOR reaches — the base of `#1^#2`, either side of
    /// `#1 == #2`, the `x` of `x -> 0` — is put in brackets before it goes
    /// in and the result is written in the one canonical spelling, which
    /// takes back the brackets that were not needed: `a + b` as a base is
    /// `(a + b)^2`, not `a + b^2` (the review of 2026-10-03: wrapping a
    /// typed or selected sum in the exponent shape wrote another formula, with
    /// no warning), and `x` is `x^2`. A slot that stands alone between the
    /// brackets and commas of an argument list needs none. Each `#n` is
    /// replaced ONCE, in one pass over the form, so a slot's text that has a
    /// `#2` of its own in it (a pure function `#1 + #2 &`) is never read as
    /// the second slot.
    func wl(_ values: [String]) -> String {
        var out = ""
        var reached = false
        var index = form.startIndex
        while index < form.endIndex {
            let character = form[index]
            let digits = form.index(after: index)
            let end = form[digits...].firstIndex(where: { !$0.isNumber }) ?? form.endIndex
            guard character == "#", digits < end, let number = Int(form[digits..<end]),
                  (1...slots.count).contains(number) else {
                out.append(character)
                index = form.index(after: index)
                continue
            }
            let slot = number - 1
            let typed = slot < values.count ? values[slot].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let text = typed.isEmpty ? slots[slot].initial : typed
            let before = form[..<index].last { !$0.isWhitespace }
            let after = form[end...].first { !$0.isWhitespace }
            let alone = (before == nil || "([{,".contains(before!)) && (after == nil || ")]},".contains(after!))
            out += alone ? text : "(" + text + ")"
            reached = reached || !alone
            index = end
        }
        if reached, let read = WLParser.parse(out) { return WLPrinter.source(read) }
        return out
    }

    static func group(_ group: Group) -> [MathTemplate] { all.filter { $0.group == group } }

    static let all: [MathTemplate] = calculus + algebra + functions + relations + symbols + greek

    private static let calculus: [MathTemplate] = [
        MathTemplate(id: "integrate.definite", group: .calculus, name: "Definite integral", glyph: "∫ᵃᵇ",
                     form: "Integrate[#1, {#2, #3, #4}]",
                     slots: [Slot(label: "Integrand", initial: "x^2"), Slot(label: "Variable", initial: "x"),
                             Slot(label: "From", initial: "0"), Slot(label: "To", initial: "1")]),
        MathTemplate(id: "integrate", group: .calculus, name: "Integral", glyph: "∫",
                     form: "Integrate[#1, #2]",
                     slots: [Slot(label: "Integrand", initial: "f[x]"), Slot(label: "Variable", initial: "x")]),
        MathTemplate(id: "sum", group: .calculus, name: "Sum", glyph: "∑",
                     form: "Sum[#1, {#2, #3, #4}]",
                     slots: [Slot(label: "Term", initial: "i^2"), Slot(label: "Index", initial: "i"),
                             Slot(label: "From", initial: "1"), Slot(label: "To", initial: "n")]),
        MathTemplate(id: "product", group: .calculus, name: "Product", glyph: "∏",
                     form: "Product[#1, {#2, #3, #4}]",
                     slots: [Slot(label: "Term", initial: "i"), Slot(label: "Index", initial: "i"),
                             Slot(label: "From", initial: "1"), Slot(label: "To", initial: "n")]),
        MathTemplate(id: "derivative", group: .calculus, name: "Derivative", glyph: "d/dx",
                     form: "D[#1, #2]",
                     slots: [Slot(label: "Of", initial: "f[x]"), Slot(label: "With respect to", initial: "x")]),
        MathTemplate(id: "derivative.n", group: .calculus, name: "nth derivative", glyph: "dⁿ/dxⁿ",
                     form: "D[#1, {#2, #3}]",
                     slots: [Slot(label: "Of", initial: "f[x]"), Slot(label: "With respect to", initial: "x"),
                             Slot(label: "Times", initial: "2")]),
        MathTemplate(id: "limit", group: .calculus, name: "Limit", glyph: "lim",
                     form: "Limit[#1, #2 -> #3]",
                     slots: [Slot(label: "Of", initial: "Sin[x]/x"), Slot(label: "Variable", initial: "x"),
                             Slot(label: "Approaches", initial: "0")]),
        // More of the calculus a page of notes actually uses (Sean,
        // 2026-09-19: "add more under calculus functions and symbols").
        MathTemplate(id: "derivative.partial", group: .calculus, name: "Partial derivative", glyph: "∂/∂x",
                     form: "D[#1, #2]",
                     slots: [Slot(label: "Of", initial: "f[x, y]"), Slot(label: "With respect to", initial: "x")]),
        MathTemplate(id: "derivative.partial.second", group: .calculus, name: "Second partial", glyph: "∂²/∂x²",
                     form: "D[#1, {#2, 2}]",
                     slots: [Slot(label: "Of", initial: "f[x, y]"), Slot(label: "With respect to", initial: "x")]),
        MathTemplate(id: "derivative.partial.mixed", group: .calculus, name: "Mixed partial", glyph: "∂²/∂x∂y",
                     form: "D[#1, #2, #3]",
                     slots: [Slot(label: "Of", initial: "f[x, y]"), Slot(label: "First", initial: "x"),
                             Slot(label: "Then", initial: "y")]),
        MathTemplate(id: "total.derivative", group: .calculus, name: "Total derivative", glyph: "df/dt",
                     form: "Dt[#1, #2]",
                     slots: [Slot(label: "Of", initial: "f[x, t]"), Slot(label: "With respect to", initial: "t")]),
        MathTemplate(id: "integrate.double", group: .calculus, name: "Double integral", glyph: "∬",
                     form: "Integrate[#1, {#2, #3, #4}, {#5, #6, #7}]",
                     slots: [Slot(label: "Integrand", initial: "f[x, y]"), Slot(label: "First variable", initial: "x"),
                             Slot(label: "From", initial: "0"), Slot(label: "To", initial: "1"),
                             Slot(label: "Second variable", initial: "y"), Slot(label: "From", initial: "0"),
                             Slot(label: "To", initial: "1")]),
        MathTemplate(id: "integrate.improper", group: .calculus, name: "Improper integral", glyph: "∫₋∞",
                     form: "Integrate[#1, {#2, -Infinity, Infinity}]",
                     slots: [Slot(label: "Integrand", initial: "Exp[-x^2]"), Slot(label: "Variable", initial: "x")]),
        MathTemplate(id: "integrate.contour", group: .calculus, name: "Contour integral", glyph: "∮",
                     form: "ContourIntegrate[#1, #2]",
                     slots: [Slot(label: "Integrand", initial: "f[z]"), Slot(label: "Variable", initial: "z")]),
        MathTemplate(id: "series.infinite", group: .calculus, name: "Infinite series", glyph: "∑∞",
                     form: "Sum[#1, {#2, #3, Infinity}]",
                     slots: [Slot(label: "Term", initial: "1/n^2"), Slot(label: "Index", initial: "n"),
                             Slot(label: "From", initial: "1")]),
        MathTemplate(id: "series.taylor", group: .calculus, name: "Taylor series", glyph: "Σₜ",
                     form: "Series[#1, {#2, #3, #4}]",
                     slots: [Slot(label: "Of", initial: "Exp[x]"), Slot(label: "Variable", initial: "x"),
                             Slot(label: "About", initial: "0"), Slot(label: "Order", initial: "5")]),
        MathTemplate(id: "limit.infinity", group: .calculus, name: "Limit at infinity", glyph: "lim∞",
                     form: "Limit[#1, #2 -> Infinity]",
                     slots: [Slot(label: "Of", initial: "1/x"), Slot(label: "Variable", initial: "x")]),
        MathTemplate(id: "limit.above", group: .calculus, name: "Limit from above", glyph: "lim⁺",
                     form: "Limit[#1, #2 -> #3, Direction -> \"FromAbove\"]",
                     slots: [Slot(label: "Of", initial: "1/x"), Slot(label: "Variable", initial: "x"),
                             Slot(label: "Approaches", initial: "0")]),
        MathTemplate(id: "limit.below", group: .calculus, name: "Limit from below", glyph: "lim⁻",
                     form: "Limit[#1, #2 -> #3, Direction -> \"FromBelow\"]",
                     slots: [Slot(label: "Of", initial: "1/x"), Slot(label: "Variable", initial: "x"),
                             Slot(label: "Approaches", initial: "0")]),
        MathTemplate(id: "grad", group: .calculus, name: "Gradient", glyph: "∇f",
                     form: "Grad[#1, {#2, #3, #4}]",
                     slots: [Slot(label: "Of", initial: "f[x, y, z]"), Slot(label: "x", initial: "x"),
                             Slot(label: "y", initial: "y"), Slot(label: "z", initial: "z")]),
        MathTemplate(id: "div", group: .calculus, name: "Divergence", glyph: "∇·F",
                     form: "Div[#1, {#2, #3, #4}]",
                     slots: [Slot(label: "Of", initial: "{P, Q, R}"), Slot(label: "x", initial: "x"),
                             Slot(label: "y", initial: "y"), Slot(label: "z", initial: "z")]),
        MathTemplate(id: "curl", group: .calculus, name: "Curl", glyph: "∇×F",
                     form: "Curl[#1, {#2, #3, #4}]",
                     slots: [Slot(label: "Of", initial: "{P, Q, R}"), Slot(label: "x", initial: "x"),
                             Slot(label: "y", initial: "y"), Slot(label: "z", initial: "z")]),
        MathTemplate(id: "laplacian", group: .calculus, name: "Laplacian", glyph: "∇²f",
                     form: "Laplacian[#1, {#2, #3}]",
                     slots: [Slot(label: "Of", initial: "f[x, y]"), Slot(label: "x", initial: "x"),
                             Slot(label: "y", initial: "y")]),
        MathTemplate(id: "integrate.indefinite.n", group: .calculus, name: "Antiderivative", glyph: "∫f dx",
                     form: "Integrate[#1, #2]",
                     slots: [Slot(label: "Integrand", initial: "1/x"), Slot(label: "Variable", initial: "x")]),
    ]

    private static let algebra: [MathTemplate] = [
        MathTemplate(id: "power", group: .algebra, name: "Exponent", glyph: "xⁿ",
                     form: "#1^#2",
                     slots: [Slot(label: "Base", initial: "x"), Slot(label: "Exponent", initial: "2")]),
        MathTemplate(id: "fraction", group: .algebra, name: "Fraction", glyph: "a⁄b",
                     form: "(#1)/(#2)",
                     slots: [Slot(label: "Top", initial: "a"), Slot(label: "Bottom", initial: "b")]),
        MathTemplate(id: "sqrt", group: .algebra, name: "Square root", glyph: "√",
                     form: "Sqrt[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "root", group: .algebra, name: "nth root", glyph: "ⁿ√",
                     form: "#1^(1/#2)",
                     slots: [Slot(label: "Of", initial: "x"), Slot(label: "Root", initial: "3")]),
        MathTemplate(id: "abs", group: .algebra, name: "Absolute value", glyph: "|x|",
                     form: "Abs[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "subscript", group: .algebra, name: "Subscript", glyph: "xᵢ",
                     form: "Subscript[#1, #2]",
                     slots: [Slot(label: "Symbol", initial: "x"), Slot(label: "Index", initial: "i")]),
        MathTemplate(id: "factorial", group: .algebra, name: "Factorial", glyph: "n!",
                     form: "Factorial[#1]", slots: [Slot(label: "Of", initial: "n")]),
        MathTemplate(id: "binomial", group: .algebra, name: "Binomial", glyph: "(ⁿₖ)",
                     form: "Binomial[#1, #2]",
                     slots: [Slot(label: "n", initial: "n"), Slot(label: "k", initial: "k")]),
        MathTemplate(id: "solve", group: .algebra, name: "Solve", glyph: "x=?",
                     form: "Solve[#1 == #2, #3]",
                     slots: [Slot(label: "Left", initial: "x^2 - 1"), Slot(label: "Right", initial: "0"),
                             Slot(label: "For", initial: "x")]),
        MathTemplate(id: "expand", group: .algebra, name: "Expand", glyph: "( )ⁿ",
                     form: "Expand[#1]", slots: [Slot(label: "Of", initial: "(x + 1)^2")]),
        MathTemplate(id: "factor", group: .algebra, name: "Factor", glyph: "ab",
                     form: "Factor[#1]", slots: [Slot(label: "Of", initial: "x^2 - 1")]),
        MathTemplate(id: "matrix", group: .algebra, name: "Matrix 2×2", glyph: "⌈⌉",
                     form: "{{#1, #2}, {#3, #4}}",
                     slots: [Slot(label: "a", initial: "a"), Slot(label: "b", initial: "b"),
                             Slot(label: "c", initial: "c"), Slot(label: "d", initial: "d")]),
    ]

    private static let functions: [MathTemplate] = [
        MathTemplate(id: "sin", group: .functions, name: "Sine", glyph: "sin",
                     form: "Sin[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "cos", group: .functions, name: "Cosine", glyph: "cos",
                     form: "Cos[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "tan", group: .functions, name: "Tangent", glyph: "tan",
                     form: "Tan[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "arctan", group: .functions, name: "Arctangent", glyph: "arctan",
                     form: "ArcTan[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "log", group: .functions, name: "Natural log", glyph: "ln",
                     form: "Log[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "logbase", group: .functions, name: "Log to a base", glyph: "log",
                     form: "Log[#1, #2]",
                     slots: [Slot(label: "Base", initial: "2"), Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "exp", group: .functions, name: "Exponential", glyph: "eˣ",
                     form: "Exp[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "arcsin", group: .functions, name: "Arcsine", glyph: "arcsin",
                     form: "ArcSin[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "arccos", group: .functions, name: "Arccosine", glyph: "arccos",
                     form: "ArcCos[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "sinh", group: .functions, name: "Hyperbolic sine", glyph: "sinh",
                     form: "Sinh[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "cosh", group: .functions, name: "Hyperbolic cosine", glyph: "cosh",
                     form: "Cosh[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "tanh", group: .functions, name: "Hyperbolic tangent", glyph: "tanh",
                     form: "Tanh[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "log10", group: .functions, name: "Log base 10", glyph: "log₁₀",
                     form: "Log10[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "erf", group: .functions, name: "Error function", glyph: "erf",
                     form: "Erf[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "gammaf", group: .functions, name: "Gamma function", glyph: "Γ(x)",
                     form: "Gamma[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "floor", group: .functions, name: "Floor", glyph: "⌊x⌋",
                     form: "Floor[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "ceiling", group: .functions, name: "Ceiling", glyph: "⌈x⌉",
                     form: "Ceiling[#1]", slots: [Slot(label: "Of", initial: "x")]),
        MathTemplate(id: "norm", group: .functions, name: "Norm", glyph: "‖x‖",
                     form: "Norm[#1]", slots: [Slot(label: "Of", initial: "v")]),
        MathTemplate(id: "dot", group: .functions, name: "Dot product", glyph: "a·b",
                     form: "Dot[#1, #2]",
                     slots: [Slot(label: "First", initial: "a"), Slot(label: "Second", initial: "b")]),
        MathTemplate(id: "cross", group: .functions, name: "Cross product", glyph: "a×b",
                     form: "Cross[#1, #2]",
                     slots: [Slot(label: "First", initial: "a"), Slot(label: "Second", initial: "b")]),
    ]

    private static let relations: [MathTemplate] = [
        MathTemplate(id: "equal", group: .relations, name: "Equals", glyph: "=",
                     form: "#1 == #2",
                     slots: [Slot(label: "Left", initial: "x"), Slot(label: "Right", initial: "y")]),
        MathTemplate(id: "notequal", group: .relations, name: "Not equal", glyph: "≠",
                     form: "#1 != #2",
                     slots: [Slot(label: "Left", initial: "x"), Slot(label: "Right", initial: "y")]),
        MathTemplate(id: "le", group: .relations, name: "At most", glyph: "≤",
                     form: "#1 <= #2",
                     slots: [Slot(label: "Left", initial: "x"), Slot(label: "Right", initial: "y")]),
        MathTemplate(id: "ge", group: .relations, name: "At least", glyph: "≥",
                     form: "#1 >= #2",
                     slots: [Slot(label: "Left", initial: "x"), Slot(label: "Right", initial: "y")]),
        MathTemplate(id: "rule", group: .relations, name: "Goes to", glyph: "→",
                     form: "#1 -> #2",
                     slots: [Slot(label: "From", initial: "x"), Slot(label: "To", initial: "0")]),
    ]

    private static let symbols: [MathTemplate] = [
        MathTemplate(id: "pi", group: .symbols, name: "Pi", glyph: "π", form: "Pi"),
        MathTemplate(id: "e", group: .symbols, name: "e", glyph: "e", form: "E"),
        MathTemplate(id: "i", group: .symbols, name: "i", glyph: "i", form: "I"),
        MathTemplate(id: "infinity", group: .symbols, name: "Infinity", glyph: "∞", form: "Infinity"),
        MathTemplate(id: "degree", group: .symbols, name: "Degree", glyph: "°", form: "Degree"),
        MathTemplate(id: "gamma", group: .symbols, name: "Euler's constant", glyph: "γ", form: "EulerGamma"),
        MathTemplate(id: "phi", group: .symbols, name: "Golden ratio", glyph: "φ", form: "GoldenRatio"),
        MathTemplate(id: "partial", group: .symbols, name: "Partial", glyph: "∂", form: "\\[PartialD]"),
        MathTemplate(id: "nabla", group: .symbols, name: "Nabla", glyph: "∇", form: "\\[Nabla]"),
        MathTemplate(id: "element", group: .symbols, name: "Element of", glyph: "∈", form: "\\[Element]"),
    ] + [
        // The rest as a table: a name, the glyph, and the WL that writes it.
        ("plusminus", "Plus or minus", "±", "\\[PlusMinus]"),
        ("minusplus", "Minus or plus", "∓", "\\[MinusPlus]"),
        ("approx", "Approximately", "≈", "\\[TildeTilde]"),
        ("congruent", "Identical to", "≡", "\\[Congruent]"),
        ("proportional", "Proportional to", "∝", "\\[Proportional]"),
        ("centerdot", "Centre dot", "⋅", "\\[CenterDot]"),
        ("times", "Times", "×", "\\[Times]"),
        ("compose", "Composed with", "∘", "\\[SmallCircle]"),
        ("oplus", "Direct sum", "⊕", "\\[CirclePlus]"),
        ("otimes", "Tensor product", "⊗", "\\[CircleTimes]"),
        ("union", "Union", "∪", "\\[Union]"),
        ("intersection", "Intersection", "∩", "\\[Intersection]"),
        ("subset", "Subset of", "⊂", "\\[Subset]"),
        ("subseteq", "Subset or equal", "⊆", "\\[SubsetEqual]"),
        ("notelement", "Not an element of", "∉", "\\[NotElement]"),
        ("forall", "For all", "∀", "\\[ForAll]"),
        ("exists", "There exists", "∃", "\\[Exists]"),
        ("not", "Not", "¬", "\\[Not]"),
        ("and", "And", "∧", "\\[And]"),
        ("or", "Or", "∨", "\\[Or]"),
        ("implies", "Implies", "⇒", "\\[Implies]"),
        ("equivalent", "If and only if", "⇔", "\\[Equivalent]"),
        ("leftarrow", "Left arrow", "←", "\\[LeftArrow]"),
        ("therefore", "Therefore", "∴", "\\[Therefore]"),
        ("because", "Because", "∵", "\\[Because]"),
        ("perpendicular", "Perpendicular to", "⊥", "\\[Perpendicular]"),
        ("parallel", "Parallel to", "∥", "\\[DoubleVerticalBar]"),
        ("angle", "Angle", "∠", "\\[Angle]"),
        ("prime", "Prime", "′", "\\[Prime]"),
        ("doubleprime", "Double prime", "″", "\\[DoublePrime]"),
        ("ellipsis", "And so on", "⋯", "\\[CenterEllipsis]"),
        ("contourintegral", "Contour integral", "∮", "\\[ContourIntegral]"),
        ("aleph", "Aleph", "ℵ", "\\[Aleph]"),
        ("emptyset", "Empty set", "∅", "\\[EmptySet]"),
        ("hbar", "h-bar", "ħ", "\\[HBar]"),
        ("reals", "The reals", "ℝ", "Reals"),
        ("integers", "The integers", "ℤ", "Integers"),
        ("rationals", "The rationals", "ℚ", "Rationals"),
        ("complexes", "The complex numbers", "ℂ", "Complexes"),
    ].map { id, name, glyph, form in
        MathTemplate(id: "symbol." + id, group: .symbols, name: name, glyph: glyph, form: form)
    }

    private static let greek: [MathTemplate] = [
        ("Alpha", "α"), ("Beta", "β"), ("Gamma", "γ"), ("Delta", "δ"), ("Epsilon", "ε"),
        ("Theta", "θ"), ("Lambda", "λ"), ("Mu", "μ"), ("Pi", "π"), ("Rho", "ρ"),
        ("Sigma", "σ"), ("Tau", "τ"), ("Phi", "φ"), ("Psi", "ψ"), ("Omega", "ω"),
        ("CapitalDelta", "Δ"), ("CapitalSigma", "Σ"), ("CapitalOmega", "Ω"),
        ("CapitalPhi", "Φ"), ("CapitalTheta", "Θ")
    ].map { name, glyph in
        MathTemplate(id: "greek." + name, group: .greek, name: name, glyph: glyph,
                     form: "\\[" + name + "]")
    }
}
