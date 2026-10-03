import Foundation

/// The glyphs maths is read in. WL names on the left, what a reader expects
/// on the right — `Pi` is π on the page and stays `Pi` in the file.
enum MathSymbols {
    static let constants: [String: String] = [
        "Pi": "π", "E": "e", "I": "i", "Infinity": "∞", "Degree": "°",
        "EulerGamma": "γ", "GoldenRatio": "φ", "ImaginaryI": "i", "Indeterminate": "?",
        // The number sets, which are plain WL symbols rather than \[names].
        "Reals": "ℝ", "Integers": "ℤ", "Rationals": "ℚ", "Complexes": "ℂ", "Primes": "ℙ",
        "Booleans": "𝔹", "True": "True", "False": "False"
    ]

    /// The rest of the `\[Name]` table: the operators and relations a page
    /// of maths is written with (Sean, 2026-09-19: "add more under calculus
    /// functions and symbols").
    static let operators: [String: String] = [
        "PlusMinus": "±", "MinusPlus": "∓", "TildeTilde": "≈", "Tilde": "∼", "TildeEqual": "≃",
        "Congruent": "≡", "Proportional": "∝", "CenterDot": "⋅", "Times": "×", "Divide": "÷",
        "SmallCircle": "∘", "CirclePlus": "⊕", "CircleTimes": "⊗", "CircleMinus": "⊖",
        "Subset": "⊂", "Superset": "⊃", "SubsetEqual": "⊆", "SupersetEqual": "⊇",
        "Not": "¬", "And": "∧", "Or": "∨", "Implies": "⇒", "Equivalent": "⇔",
        "LeftArrow": "←", "RightArrow": "→", "UpArrow": "↑", "DownArrow": "↓",
        "LongRightArrow": "⟶", "LongLeftArrow": "⟵", "DoubleRightArrow": "⇒",
        "Because": "∵", "Perpendicular": "⊥", "DoubleVerticalBar": "∥", "Angle": "∠",
        "Prime": "′", "DoublePrime": "″", "CenterEllipsis": "⋯", "Ellipsis": "…",
        "VerticalEllipsis": "⋮", "ContourIntegral": "∮", "DoubleContourIntegral": "∯",
        "Integral": "∫", "Sum": "∑", "Product": "∏", "SquareRoot": "√", "Aleph": "ℵ",
        "HBar": "ħ", "ScriptL": "ℓ", "Micro": "µ", "Angstrom": "Å", "Star": "⋆",
        "LessEqual": "≤", "GreaterEqual": "≥", "NotEqual": "≠", "Equal": "=",
        "LeftRightArrow": "↔", "Element": "∈", "NotElement": "∉", "EmptySet": "∅",
        "Infinity": "∞", "Cross": "✕", "Wedge": "∧", "Vee": "∨", "Del": "∇"
    ]

    static let greek: [String: String] = [
        "Alpha": "α", "Beta": "β", "Gamma": "γ", "Delta": "δ", "Epsilon": "ε", "Zeta": "ζ",
        "Eta": "η", "Theta": "θ", "Iota": "ι", "Kappa": "κ", "Lambda": "λ", "Mu": "μ",
        "Nu": "ν", "Xi": "ξ", "Omicron": "ο", "Pi": "π", "Rho": "ρ", "Sigma": "σ",
        "Tau": "τ", "Upsilon": "υ", "Phi": "φ", "Chi": "χ", "Psi": "ψ", "Omega": "ω",
        "CurlyPhi": "ϕ", "CurlyEpsilon": "ϵ", "CurlyTheta": "ϑ", "CurlyKappa": "ϰ",
        "CurlyPi": "ϖ", "CurlyRho": "ϱ", "FinalSigma": "ς",
        "CapitalAlpha": "Α", "CapitalBeta": "Β", "CapitalEpsilon": "Ε", "CapitalZeta": "Ζ",
        "CapitalEta": "Η", "CapitalIota": "Ι", "CapitalKappa": "Κ", "CapitalMu": "Μ",
        "CapitalNu": "Ν", "CapitalOmicron": "Ο", "CapitalRho": "Ρ", "CapitalTau": "Τ",
        "CapitalUpsilon": "Υ", "CapitalChi": "Χ",
        "CapitalDelta": "Δ", "CapitalGamma": "Γ", "CapitalLambda": "Λ", "CapitalOmega": "Ω",
        "CapitalPhi": "Φ", "CapitalPi": "Π", "CapitalPsi": "Ψ", "CapitalSigma": "Σ",
        "CapitalTheta": "Θ", "CapitalXi": "Ξ", "Element": "∈", "NotElement": "∉",
        "Union": "∪", "Intersection": "∩", "PartialD": "∂", "Nabla": "∇",
        "Therefore": "∴", "ForAll": "∀", "Exists": "∃", "EmptySet": "∅"
    ]

    /// The names in `greek` that are LETTERS, which is what a symbol spelled
    /// out is read as — `Alpha`, `Theta` and `Pi` typed in a formula are
    /// α, θ and π, with or without the `\[ ]` (Sean, 2026-10-03: Greek letters
    /// spelled out). `Union` and `Element` are WL's names for functions and
    /// stay names when they stand alone.
    static let letters: [String: String] = greek.filter { name, _ in
        !["Element", "NotElement", "Union", "Intersection", "PartialD", "Nabla",
          "Therefore", "ForAll", "Exists", "EmptySet"].contains(name)
    }

    /// The functions that are set upright and lower case, the way they are read.
    static let functions: [String: String] = [
        "Sin": "sin", "Cos": "cos", "Tan": "tan", "Cot": "cot", "Sec": "sec", "Csc": "csc",
        "ArcSin": "arcsin", "ArcCos": "arccos", "ArcTan": "arctan",
        "Sinh": "sinh", "Cosh": "cosh", "Tanh": "tanh",
        "Log": "ln", "Log10": "log₁₀", "Log2": "log₂", "Exp": "exp",
        "Max": "max", "Min": "min", "Mod": "mod", "Gcd": "gcd", "Det": "det",
        "ArcSinh": "arcsinh", "ArcCosh": "arccosh", "ArcTanh": "arctanh",
        "Erf": "erf", "Erfc": "erfc", "Gamma": "Γ", "Beta": "B", "Zeta": "ζ",
        "Floor": "⌊⌋", "Ceiling": "⌈⌉", "Norm": "‖‖", "Re": "Re", "Im": "Im",
        "Arg": "arg", "Conjugate": "conj", "Tr": "tr", "Rank": "rank",
        "Dot": "·", "Cross": "×", "Trace": "tr", "Sign": "sgn"
    ]

    /// The ones `sin²(x)` is written for: a power goes on the NAME, not on
    /// the bracket after it.
    static let powersOnTheName: Set<String> = [
        "Sin", "Cos", "Tan", "Cot", "Sec", "Csc", "Sinh", "Cosh", "Tanh", "Log", "Log10", "Log2",
        "ArcSin", "ArcCos", "ArcTan"
    ]

    static let relations: [String: String] = [
        "==": "=", "!=": "≠", "<=": "≤", ">=": "≥", "<": "<", ">": ">",
        "->": "→", "+": "+", "-": "−", "*": "·", "/": "/"
    ]

    /// `\[Alpha]` → α, `Pi` → π, `Theta` → θ, anything else as it stands.
    static func glyph(for symbol: String) -> String {
        if symbol.hasPrefix("\\["), symbol.hasSuffix("]") {
            let name = String(symbol.dropFirst(2).dropLast())
            return greek[name] ?? operators[name] ?? constants[name] ?? name
        }
        return constants[symbol] ?? letters[symbol] ?? symbol
    }

    /// A single letter is a variable and is set in italic — `x`, `θ`, `x1`;
    /// `sin`, a capital Greek letter and `Pi` are not.
    static func isVariable(_ glyph: String) -> Bool {
        guard let first = glyph.first, first.isLetter, !isCapitalGreek(first),
              let scalar = first.unicodeScalars.first, scalar.value < 0x2100   // not ℝ ℤ ℚ ℂ or 𝔹
        else { return false }
        return glyph.dropFirst().allSatisfy { $0.isNumber && $0.isASCII }
    }

    private static func isCapitalGreek(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x391...0x3A9).contains(scalar.value)
    }
}
