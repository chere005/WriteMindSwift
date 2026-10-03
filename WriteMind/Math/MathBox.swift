import Foundation

/// How a run of glyphs is set: a variable in italic, everything else upright.
enum MathFace: Equatable {
    case italic
    case roman
}

/// The brackets maths is fenced with. Drawn to the height of what they hold.
enum MathFence: Equatable {
    case paren, bracket, brace, bar, doubleBar, floor, ceiling, part

    var open: String {
        switch self {
        case .paren: return "("
        case .bracket: return "["
        case .brace: return "{"
        case .bar: return "|"
        case .doubleBar: return "‖"
        case .floor: return "⌊"
        case .ceiling: return "⌈"
        case .part: return "⟦"
        }
    }

    var close: String {
        switch self {
        case .paren: return ")"
        case .bracket: return "]"
        case .brace: return "}"
        case .bar: return "|"
        case .doubleBar: return "‖"
        case .floor: return "⌋"
        case .ceiling: return "⌉"
        case .part: return "⟧"
        }
    }
}

/// WHAT THE TYPESETTER DECIDED, before anything is painted: a tree of
/// typeset parts — a run of glyphs, a row of them, a fraction, a script, a
/// radical, a fence, a big operator with its limits, a matrix. One builder
/// (`MathBuilder`) turns an expression into it, and two painters read it:
/// `MathLayout` sets it in two dimensions for maths on a line of its own,
/// and `MathTypesetter.inline` writes it into a sentence with raised and
/// lowered scripts. So the derivative a palette shape writes and the
/// formula somebody types are the same thing to both of them, and a rule
/// about how a power or a sum is set is written once.
indirect enum MathBox: Equatable {
    case glyphs(String, MathFace)
    /// A gap, in ems of the type it is set in.
    case space(Double)
    /// A line of parts. `level` is how tightly the whole holds together
    /// (`WLLevel`): what the one painter that has no room for two
    /// dimensions needs to know to put a bracket where it reads wrong
    /// without one.
    case row([MathBox], level: Int)
    /// One over another — with the bar, or without it (a binomial).
    case fraction(MathBox, MathBox, bar: Bool)
    case script(MathBox, sup: MathBox?, sub: MathBox?)
    case radical(MathBox)
    case fenced(MathFence, MathBox)
    /// ∑ ∫ ∏ and their kind, bigger than the line they stand in.
    case large(MathBox, display: Double, inline: Double)
    /// An operator with its limits above and below it: ∑ ∏ lim.
    case limits(MathBox, above: MathBox?, below: MathBox?)
    /// An operator with its limits beside it: ∫.
    case sideLimits(MathBox, above: MathBox?, below: MathBox?)
    case matrix([[MathBox]])
    /// A part that is set one way on a line of its own and another in a
    /// sentence — a binomial coefficient stacks in the one and is Cⁿₖ in
    /// the other.
    case choice(display: MathBox, inline: MathBox)

    /// How tightly it holds together, on the scale of `WLLevel`.
    var level: Int {
        switch self {
        case .row(_, let level): return level
        case .fraction(_, _, let bar): return bar ? WLLevel.product : WLLevel.atom
        case .script: return WLLevel.power
        case .choice(let display, let inline): return min(display.level, inline.level)
        case .glyphs, .space, .radical, .fenced, .large, .limits, .sideLimits, .matrix: return WLLevel.atom
        }
    }

    /// The first thing a reader meets in it, as characters — so that a
    /// `2` set beside another `2` is not read as 22.
    var firstGlyphs: String? {
        switch self {
        case .glyphs(let text, _): return text.isEmpty ? nil : text
        case .row(let items, _): return items.lazy.compactMap(\.firstGlyphs).first
        case .script(let base, _, _): return base.firstGlyphs
        case .large(let box, _, _), .limits(let box, _, _), .sideLimits(let box, _, _): return box.firstGlyphs
        case .choice(let display, _): return display.firstGlyphs
        case .space, .fraction, .radical, .fenced, .matrix: return nil
        }
    }

    /// The last thing, the same way.
    var lastGlyphs: String? {
        switch self {
        case .glyphs(let text, _): return text.isEmpty ? nil : text
        case .row(let items, _): return items.reversed().lazy.compactMap(\.lastGlyphs).first
        case .space, .fraction, .radical, .fenced, .matrix, .script, .large, .limits, .sideLimits: return nil
        case .choice(let display, _): return display.lastGlyphs
        }
    }

    /// The decision in one line of TeX-like text, with the gaps left out —
    /// `\frac{\sin^{2}(x)}{1+x}` — which is how the tests say what was
    /// decided without painting a thing.
    var outline: String {
        switch self {
        case .glyphs(let text, _): return text
        case .space: return ""
        case .row(let items, _): return items.map(\.outline).joined()
        case .fraction(let top, let bottom, let bar):
            return (bar ? "\\frac" : "\\binom") + "{\(top.outline)}{\(bottom.outline)}"
        case .script(let base, let sup, let sub):
            return base.outline + (sub.map { "_{\($0.outline)}" } ?? "") + (sup.map { "^{\($0.outline)}" } ?? "")
        case .radical(let inside): return "\\sqrt{\(inside.outline)}"
        case .fenced(let fence, let inside): return fence.open + inside.outline + fence.close
        case .large(let box, _, _): return box.outline
        case .limits(let box, let above, let below), .sideLimits(let box, let above, let below):
            return box.outline + (below.map { "_{\($0.outline)}" } ?? "") + (above.map { "^{\($0.outline)}" } ?? "")
        case .matrix(let rows):
            return "[" + rows.map { $0.map(\.outline).joined(separator: ",") }.joined(separator: ";") + "]"
        case .choice(let display, _): return display.outline
        }
    }
}

/// An expression, decided: WL in, `MathBox` out.
///
/// Sean, 2026-10-03: "maths input should also just allow for an expression
/// so i could insert a function or something and it would appear like the
/// derivatives or integrals". There is no list of shapes here — a derivative,
/// an integral and a sum are three of the heads this knows how to set, and
/// anything else is set as what it is: arithmetic with its powers and
/// fractions, a relation, a function applied to its arguments.
enum MathBuilder {
    static func box(_ expr: WLExpr) -> MathBox { build(expr) }

    /// Set in brackets when it holds together less tightly than `level` —
    /// judged by what was BUILT, so `Plus[a, b]` is a sum here as well as `a + b`.
    static func box(_ expr: WLExpr, atLeast level: Int) -> MathBox {
        let built = build(expr)
        return built.level < level ? .fenced(.paren, built) : built
    }

    // MARK: - Expressions

    private static func build(_ expr: WLExpr) -> MathBox {
        switch expr {
        case .number(let value): return .glyphs(value, .roman)
        case .text(let value): return .glyphs(value, .roman)
        case .symbol(let name): return symbol(name)
        case .blank(let name, let count, let head):
            var items: [MathBox] = []
            if let name { items.append(symbol(name)) }
            items.append(.glyphs(String(repeating: "_", count: count), .roman))
            if let head { items.append(.glyphs(head, .roman)) }
            return .row(items, level: WLLevel.atom)
        case .list(let items): return list(items)
        case .negate(let operand):
            return .row([.glyphs("−", .roman), box(operand, atLeast: WLLevel.product)], level: WLLevel.sum)
        case .prefix(_, let operand):
            return .row([.glyphs("¬", .roman), box(operand, atLeast: WLLevel.relation)], level: WLLevel.not)
        case .postfix(let op, let operand):
            switch op {
            case "&":
                return .row([box(operand, atLeast: WLLevel.function + 1), .space(0.15), .glyphs("&", .roman)],
                            level: WLLevel.function)
            case "'":
                return .row([box(operand, atLeast: WLLevel.factorial), .glyphs("′", .roman)],
                            level: WLLevel.factorial)
            default:
                return .row([box(operand, atLeast: WLLevel.factorial), .glyphs(op, .roman)],
                            level: WLLevel.factorial)
            }
        case .part(let base, let indices):
            return .row([box(base, atLeast: WLLevel.atom),
                         .fenced(.part, commaList(indices.map(build)))], level: WLLevel.atom)
        case .binary(let op, let left, let right): return binary(op, left, right)
        case .call(let head, let args): return call(head, args)
        }
    }

    /// A name: a variable in italic, a constant or a Greek letter as its
    /// glyph, anything longer upright.
    static func symbol(_ name: String) -> MathBox {
        let glyph = MathSymbols.glyph(for: name)
        return .glyphs(glyph, MathSymbols.isVariable(glyph) ? .italic : .roman)
    }

    private static func commaList(_ items: [MathBox]) -> MathBox {
        var out: [MathBox] = []
        for (index, item) in items.enumerated() {
            if index > 0 { out.append(.glyphs(",", .roman)); out.append(.space(0.2)) }
            out.append(item)
        }
        return .row(out, level: WLLevel.atom)
    }

    /// `{a, b, c}`; and a list of lists, all rows, is a matrix.
    private static func list(_ items: [WLExpr]) -> MathBox {
        let rows: [[WLExpr]] = items.compactMap { item in
            if case .list(let row) = item, !row.isEmpty { return row }
            return nil
        }
        if !items.isEmpty, rows.count == items.count {
            return .fenced(.paren, .matrix(rows.map { $0.map(build) }))
        }
        return .fenced(.brace, commaList(items.map(build)))
    }

    // MARK: - Operators

    /// Written between two things, spaced the way it is read.
    private static let infix: [String: (glyph: String, space: Double)] = [
        "==": ("=", 0.28), "!=": ("≠", 0.28), "===": ("≡", 0.28), "=!=": ("≢", 0.28),
        "<": ("<", 0.28), "<=": ("≤", 0.28), ">": (">", 0.28), ">=": ("≥", 0.28),
        "->": ("→", 0.28), ":>": (":→", 0.28), "=": ("=", 0.28), ":=": (":=", 0.28),
        "&&": ("∧", 0.22), "||": ("∨", 0.22), "/;": ("/;", 0.22), "/.": ("/.", 0.22),
        ".": ("·", 0.15)
    ]

    private static func binary(_ op: String, _ left: WLExpr, _ right: WLExpr) -> MathBox {
        switch op {
        case "/":
            return .fraction(build(left), build(right), bar: true)
        case "^":
            return power(left, right)
        case "+", "-":
            return sum(.binary(op, left, right))
        case "*":
            return product(.binary(op, left, right))
        default:
            return infixRow(op, left, right)
        }
    }

    /// `a + b - c`, however long, as one row: the terms are walked down the
    /// left of the tree, so a long sum is a loop and not a recursion.
    private static func sum(_ expr: WLExpr) -> MathBox {
        var terms: [(sign: String, term: WLExpr)] = []
        var current = expr
        while case .binary(let op, let left, let right) = current, op == "+" || op == "-" {
            terms.append((op, right))
            current = left
        }
        var items = [box(current, atLeast: WLLevel.sum)]
        for (sign, term) in terms.reversed() {
            items += [.space(0.25), .glyphs(sign == "+" ? "+" : "−", .roman), .space(0.25),
                      box(term, atLeast: WLLevel.sum + 1)]
        }
        return .row(items, level: WLLevel.sum)
    }

    /// `a*b*c`: set side by side, ON ONE LINE, the way maths is — except
    /// where that would read as one number (`2*3` is 2 × 3, not 23), and
    /// where a sign has to say it is a product (`x*2` is x · 2).
    ///
    /// AND WITHOUT THE BRACKETS THE TRADITIONAL FORM DOES NOT DRAW (Sean,
    /// 2026-10-03, on `(-2*x) * (E^-(x^2))` set as "(-2) x" with the e
    /// below the line: "things multiplied should be on the same line
    /// horizontally"). A factor that is itself a product is part of this
    /// one — `a*(b*c)` is a b c, in WL's own FullForm too, where Times
    /// flattens — and a negation in FRONT of the first factor is the
    /// product's sign: `(-2*x)*E^(-x^2)` is −2 x e^{−x²}, not (−2x) e^{−x²}.
    /// What stays in brackets is what the brackets mean: a sum, a fraction
    /// beside a number (2 (1/3) is not 2⅓), a negation anywhere but in front
    /// (`x*(-y)`: `x −y` reads as a subtraction), a power's base. The stored
    /// text is untouched; this is only how it is set.
    private static func product(_ expr: WLExpr) -> MathBox {
        var factors = Self.factors(of: expr)
        var signed = false
        if case .negate(let inner) = factors[0] {
            signed = true
            factors = Self.factors(of: inner) + factors.dropFirst()
        }
        var items: [MathBox] = signed ? [.glyphs("−", .roman)] : []
        items.append(box(factors[0], atLeast: WLLevel.product))
        for factor in factors.dropFirst() {
            let next = box(factor, atLeast: WLLevel.product + 1)
            if let first = next.firstGlyphs?.first, first.isNumber || first == "." {
                let afterNumber = items.last?.lastGlyphs?.last?.isNumber == true
                items += [.space(0.15), .glyphs(afterNumber ? "×" : "·", .roman), .space(0.15)]
            } else {
                items.append(.space(0.1))
            }
            items.append(next)
        }
        // A product with a sign in front is a signed term, as −x is: in a sum
        // or as a base it is bracketed.
        return .row(items, level: signed ? WLLevel.sum : WLLevel.product)
    }

    /// The factors of a product, in order, however it was bracketed:
    /// `a*b*c`, `a*(b*c)` and `Times[a, Times[b, c]]` are a, b, c. Anything
    /// else is one factor. Walked with a stack, not by recursion, so a
    /// product of a thousand factors is a loop.
    private static func factors(of expr: WLExpr) -> [WLExpr] {
        var out: [WLExpr] = []
        var pending = [expr]
        while let next = pending.popLast() {
            switch next {
            case .binary("*", let left, let right):
                pending.append(right)
                pending.append(left)
            case .call(.symbol("Times"), let args) where args.count >= 2 && args[0] != .negate(.number("1")):
                // (Times[-1, x] is WL's spelling of -x, and is set as the negation it is.)
                pending.append(contentsOf: args.reversed())
            default:
                out.append(next)
            }
        }
        return out
    }

    private static func infixRow(_ op: String, _ left: WLExpr, _ right: WLExpr) -> MathBox {
        let level = WLParser.level(of: op)
        let (glyph, gap) = infix[op] ?? (op, 0.22)
        if WLParser.isRightAssociative(op) {
            return .row([box(left, atLeast: level + 1), .space(gap), .glyphs(glyph, .roman), .space(gap),
                         box(right, atLeast: level)], level: level)
        }
        var operands: [WLExpr] = []
        var current: WLExpr = .binary(op, left, right)
        while case .binary(let o, let l, let r) = current, o == op {
            operands.append(r)
            current = l
        }
        var items = [box(current, atLeast: level)]
        for operand in operands.reversed() {
            if op == ";" {
                items += [.glyphs(";", .roman), .space(0.3)]
            } else {
                items += [.space(gap), .glyphs(glyph, .roman), .space(gap)]
            }
            items.append(box(operand, atLeast: level + 1))
        }
        return .row(items, level: level)
    }

    /// A power; and `Sin[x]^2` is sin²(x), the power on the name.
    private static func power(_ base: WLExpr, _ exponent: WLExpr) -> MathBox {
        if case .call(.symbol(let name), let args) = base, args.count == 1,
           MathSymbols.powersOnTheName.contains(name), let short = MathSymbols.functions[name],
           isPlain(exponent) {
            return .row([.script(.glyphs(short, .roman), sup: build(exponent), sub: nil),
                         .fenced(.paren, build(args[0]))], level: WLLevel.atom)
        }
        return .script(box(base, atLeast: WLLevel.atom), sup: build(exponent), sub: nil)
    }

    private static func isPlain(_ expr: WLExpr) -> Bool {
        switch expr {
        case .number, .symbol: return true
        default: return false
        }
    }

    // MARK: - Calls

    private static func call(_ head: WLExpr, _ args: [WLExpr]) -> MathBox {
        if case .symbol(let name) = head, let special = special(name, args) { return special }
        let named: MathBox
        if case .symbol(let name) = head { named = functionName(name) } else { named = box(head, atLeast: WLLevel.factorial) }
        return .row([named, .fenced(.paren, commaList(args.map(build)))], level: WLLevel.atom)
    }

    /// `sin`, `ln`, `f`, `Foo`: what a function is called on the page.
    private static func functionName(_ name: String) -> MathBox {
        if let short = MathSymbols.functions[name], !["⌊⌋", "⌈⌉", "‖‖", "·", "×"].contains(short) {
            return .glyphs(short, .roman)
        }
        return symbol(name)
    }

    /// `Plus[a, b]` and the rest of FullForm, set as the operators they are.
    private static func fold(_ op: String, _ items: [WLExpr]) -> WLExpr {
        items.dropFirst().reduce(items[0]) { .binary(op, $0, $1) }
    }

    private static let operatorHeads: [String: String] = [
        "Power": "^", "Divide": "/", "Subtract": "-", "Rational": "/", "Rule": "->", "RuleDelayed": ":>",
        "Set": "=", "SetDelayed": ":=", "Equal": "==", "Unequal": "!=", "Less": "<", "Greater": ">",
        "LessEqual": "<=", "GreaterEqual": ">=", "SameQ": "===", "UnsameQ": "=!=", "And": "&&", "Or": "||",
        "Dot": ".", "ReplaceAll": "/.", "Condition": "/;", "Plus": "+", "Times": "*"
    ]

    /// The heads above that take exactly two arguments; `Plus`, `Times`,
    /// `And` and the relations take any number.
    private static let pairsOnly: Set<String> = [
        "Power", "Divide", "Subtract", "Rational", "Rule", "RuleDelayed", "Set", "SetDelayed",
        "ReplaceAll", "Condition"
    ]

    /// Relations and set operations written between their arguments in a
    /// glyph of their own.
    private static let glyphHeads: [String: (glyph: String, level: Int)] = [
        "Element": ("∈", WLLevel.relation), "NotElement": ("∉", WLLevel.relation),
        "Subset": ("⊂", WLLevel.relation), "SubsetEqual": ("⊆", WLLevel.relation),
        "Implies": ("⇒", WLLevel.rule), "Equivalent": ("⇔", WLLevel.rule),
        "Union": ("∪", WLLevel.sum), "Intersection": ("∩", WLLevel.product), "Cross": ("×", WLLevel.product)
    ]

    private static func special(_ name: String, _ args: [WLExpr]) -> MathBox? {
        let count = args.count
        if let op = operatorHeads[name], count >= 2, count == 2 || !pairsOnly.contains(name) {
            // Times[-1, x] is how WL spells -x.
            if name == "Times", case .negate(.number("1")) = args[0] {
                return build(.negate(fold("*", Array(args.dropFirst()))))
            }
            return build(fold(op, args))
        }
        if let (glyph, level) = glyphHeads[name], count >= 2 {
            var items: [MathBox] = []
            for (index, arg) in args.enumerated() {
                if index > 0 { items += [.space(0.22), .glyphs(glyph, .roman), .space(0.22)] }
                items.append(box(arg, atLeast: level + 1))
            }
            return .row(items, level: level)
        }

        switch name {
        case "Minus" where count == 1: return build(.negate(args[0]))
        case "Not" where count == 1: return build(.prefix("!", args[0]))
        case "Sqrt" where count == 1: return .radical(build(args[0]))
        case "Abs" where count == 1: return .fenced(.bar, build(args[0]))
        case "Floor" where count == 1: return .fenced(.floor, build(args[0]))
        case "Ceiling" where count == 1: return .fenced(.ceiling, build(args[0]))
        case "Norm" where count == 1: return .fenced(.doubleBar, build(args[0]))
        case "Norm" where count == 2:
            return .script(.fenced(.doubleBar, build(args[0])), sup: nil, sub: build(args[1]))
        case "Exp" where count == 1:
            return .script(.glyphs("e", .italic), sup: build(args[0]), sub: nil)
        case "Log" where count == 2:
            return .row([.script(.glyphs("log", .roman), sup: nil, sub: build(args[0])),
                         .fenced(.paren, build(args[1]))], level: WLLevel.atom)
        case "Factorial" where count == 1: return build(.postfix("!", args[0]))
        case "Subscript" where count >= 2:
            return .script(box(args[0], atLeast: WLLevel.atom), sup: nil,
                           sub: commaList(args.dropFirst().map(build)))
        case "Superscript" where count == 2:
            return .script(box(args[0], atLeast: WLLevel.atom), sup: build(args[1]), sub: nil)
        case "Binomial" where count == 2:
            let top = build(args[0]), bottom = build(args[1])
            return .choice(display: .fenced(.paren, .fraction(top, bottom, bar: false)),
                           inline: .script(.glyphs("C", .italic), sup: top, sub: bottom))
        case "MatrixForm" where count == 1: return build(args[0])
        case "Integrate": return integral(args)
        case "Sum": return bigOperator("∑", args)
        case "Product": return bigOperator("∏", args)
        case "Limit" where count == 2 || count == 3: return limit(args)
        case "D": return derivative(args, glyph: "∂", minimum: 2)
        case "Dt": return derivative(args, glyph: "d", minimum: 1)
        case "Grad", "Div", "Curl", "Laplacian": return vectorOperator(name, args)
        case "ContourIntegrate" where count == 2:
            return .row([.large(.glyphs("∮", .roman), display: 1.8, inline: 1.3), .space(0.12),
                         box(args[0], atLeast: WLLevel.product), differential(args[1])], level: WLLevel.product)
        default: return nil
        }
    }

    // MARK: - Calculus

    /// `dx`: the d upright, what it is of beside it.
    private static func differential(_ variable: WLExpr) -> MathBox {
        .row([.space(0.18), .glyphs("d", .roman), box(variable, atLeast: WLLevel.atom)], level: WLLevel.atom)
    }

    /// What one iterator `{x, a, b}` of an integral is: the variable and its
    /// bounds. A bare `x` is an indefinite integral.
    private static func integralIterator(_ spec: WLExpr) -> (variable: WLExpr, lower: WLExpr?, upper: WLExpr?)? {
        guard case .list(let parts) = spec else { return (spec, nil, nil) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    /// `Integrate[f, {x, a, b}, {y, c, d}]`: a sign for each variable with
    /// its limits beside it, then the integrand, then the differentials
    /// innermost-first — ∫ₐᵇ ∫꜀ᵈ f dy dx, which is how WL's own order reads.
    private static func integral(_ args: [WLExpr]) -> MathBox? {
        guard args.count >= 2 else { return nil }
        var iterators: [(variable: WLExpr, lower: WLExpr?, upper: WLExpr?)] = []
        for spec in args.dropFirst() {
            guard let iterator = integralIterator(spec) else { return nil }
            iterators.append(iterator)
        }
        let sign = MathBox.large(.glyphs("∫", .roman), display: 1.8, inline: 1.3)
        let signs: [MathBox] = iterators.map { iterator in
            guard iterator.lower != nil || iterator.upper != nil else { return sign }
            return .sideLimits(sign, above: iterator.upper.map(build), below: iterator.lower.map(build))
        }
        var display = signs
        display.append(.space(0.12))
        let body = box(args[0], atLeast: WLLevel.product)
        let differentials = iterators.reversed().map { differential($0.variable) }

        // In a sentence a double integral is ∫∫ with its limits after it.
        var inline = display
        if iterators.count > 1 {
            inline = [.large(.glyphs(String(repeating: "∫", count: iterators.count), .roman), display: 1.8, inline: 1.3)]
            for iterator in iterators where iterator.lower != nil || iterator.upper != nil {
                inline.append(.script(.space(0), sup: iterator.upper.map(build), sub: iterator.lower.map(build)))
            }
            inline.append(.space(0.12))
        }
        let tail = [body] + differentials
        return .choice(display: .row(display + tail, level: WLLevel.product),
                       inline: .row(inline + tail, level: WLLevel.product))
    }

    /// ∑ and ∏, one for each iterator: the index below, the end above.
    /// `{i, n}` is 1 to n; `{i, {a, b, c}}` is i ∈ that list.
    private static func bigOperator(_ sign: String, _ args: [WLExpr]) -> MathBox? {
        guard args.count >= 2 else { return nil }
        var signs: [MathBox] = []
        for spec in args.dropFirst() {
            let above: MathBox?
            let below: MathBox
            switch spec {
            case .list(let parts) where parts.count == 3:
                below = .row([build(parts[0]), .space(0.15), .glyphs("=", .roman), .space(0.15), build(parts[1])],
                             level: WLLevel.atom)
                above = build(parts[2])
            case .list(let parts) where parts.count == 2:
                if case .list = parts[1] {
                    below = .row([build(parts[0]), .space(0.15), .glyphs("∈", .roman), .space(0.15), build(parts[1])],
                                 level: WLLevel.atom)
                    above = nil
                } else {
                    below = .row([build(parts[0]), .space(0.15), .glyphs("=", .roman), .space(0.15),
                                  .glyphs("1", .roman)], level: WLLevel.atom)
                    above = build(parts[1])
                }
            case .list:
                return nil
            default:
                below = build(spec)
                above = nil
            }
            signs.append(.limits(.large(.glyphs(sign, .roman), display: 1.7, inline: 1.25), above: above, below: below))
        }
        return .row(signs + [.space(0.12), box(args[0], atLeast: WLLevel.product)], level: WLLevel.product)
    }

    /// `Limit[f, x -> a]`, and with `Direction -> "FromAbove"` (or -1) a
    /// little + after the a, `"FromBelow"` (or 1) a −.
    private static func limit(_ args: [WLExpr]) -> MathBox? {
        guard case .binary("->", _, _) = args[1] else { return nil }
        var under = [build(args[1])]
        if args.count == 3, case .binary("->", .symbol("Direction"), let direction) = args[2] {
            switch direction {
            case .text("FromAbove"), .negate(.number("1")): under.append(.glyphs("\u{207A}", .roman))
            case .text("FromBelow"), .number("1"): under.append(.glyphs("\u{207B}", .roman))
            default: break
            }
        }
        return .row([.limits(.glyphs("lim", .roman), above: nil, below: .row(under, level: WLLevel.atom)),
                     .space(0.15), box(args[0], atLeast: WLLevel.product)], level: WLLevel.product)
    }

    /// `D[f, x]` is ∂f/∂x; `D[f, {x, n}]` ∂ⁿf/∂xⁿ; `D[f, x, y]` ∂²f/∂x∂y —
    /// and `Dt` the same with d.
    private static func derivative(_ args: [WLExpr], glyph: String, minimum: Int) -> MathBox? {
        guard args.count >= minimum else { return nil }
        if args.count == 1 {
            return .row([.glyphs(glyph, .roman), box(args[0], atLeast: WLLevel.power)], level: WLLevel.atom)
        }
        var variables: [(variable: WLExpr, order: WLExpr?)] = []
        for spec in args.dropFirst() {
            if case .list(let parts) = spec {
                guard parts.count == 2 else { return nil }
                variables.append((parts[0], parts[1]))
            } else {
                variables.append((spec, nil))
            }
        }
        let orders = variables.map { $0.order ?? .number("1") }
        let total: WLExpr
        if orders.allSatisfy({ if case .number(let n) = $0 { return Int(n) != nil } else { return false } }) {
            total = .number(String(orders.reduce(0) { sum, order in
                if case .number(let n) = order { return sum + (Int(n) ?? 0) }
                return sum
            }))
        } else {
            total = fold("+", orders)
        }
        let operatorSign: MathBox = .glyphs(glyph, .roman)
        let numerator = MathBox.row([total == .number("1") ? operatorSign
                            : .script(operatorSign, sup: build(total), sub: nil),
                          box(args[0], atLeast: WLLevel.power)], level: WLLevel.atom)
        var denominator: [MathBox] = []
        for (index, part) in variables.enumerated() {
            if index > 0 { denominator.append(.space(0.1)) }
            let wrt = MathBox.row([operatorSign, box(part.variable, atLeast: WLLevel.atom)], level: WLLevel.atom)
            if let order = part.order, order != .number("1") {
                denominator.append(.script(wrt, sup: build(order), sub: nil))
            } else {
                denominator.append(wrt)
            }
        }
        return .fraction(numerator, .row(denominator, level: WLLevel.atom), bar: true)
    }

    /// ∇f, ∇·F, ∇×F, ∇²f.
    private static func vectorOperator(_ name: String, _ args: [WLExpr]) -> MathBox? {
        guard let operand = args.first else { return nil }
        let nabla = MathBox.glyphs("∇", .roman)
        var items: [MathBox] = [name == "Laplacian"
                                ? .script(nabla, sup: .glyphs("2", .roman), sub: nil) : nabla]
        if name == "Div" { items.append(.glyphs("·", .roman)) }
        if name == "Curl" { items.append(.glyphs("×", .roman)) }
        items += [.space(0.08), box(operand, atLeast: WLLevel.power)]
        return .row(items, level: WLLevel.product)
    }
}
