import Foundation

/// Maths is kept in Wolfram Language (Sean, 2026-09-18: "use WL for the
/// canonical form of the math inputs"), so what a note holds is text anything
/// can read — `Integrate[x^2, {x, 0, 1}]` — and this is what reads it back so
/// it can be typeset.
///
/// Sean, 2026-10-03: "maths input should also just allow for an expression so
/// i could insert a function or something and it would appear like the
/// derivatives or integrals". So this is no longer the handful of shapes the
/// palette writes: it is the part of the language a formula is written in —
/// arithmetic and powers, relations and logic, assignments and rules, lists,
/// function application, patterns (`x_`), parts, primes, factorials and pure
/// functions. `WLParser` reads it with the reason when it cannot.
indirect enum WLExpr: Equatable {
    case number(String)
    case symbol(String)
    case text(String)
    case list([WLExpr])
    case call(WLExpr, [WLExpr])
    case binary(String, WLExpr, WLExpr)
    case negate(WLExpr)
    /// `!x` — Not.
    case prefix(String, WLExpr)
    /// `n!`, `f'` and `#^2 &`: what is written after the thing.
    case postfix(String, WLExpr)
    /// `m[[i, j]]`.
    case part(WLExpr, [WLExpr])
    /// `x_`, `_`, `x__`, `_Integer` — a name (or none), how many underscores,
    /// and the head it must have (or none).
    case blank(name: String?, count: Int, head: String?)

    /// `Integrate[…]` and friends: a named head with its arguments.
    var application: (name: String, args: [WLExpr])? {
        if case .call(.symbol(let name), let args) = self { return (name, args) }
        return nil
    }

    /// Nothing that needs brackets round it when something is done to it.
    var isAtom: Bool { level >= WLLevel.atom }

    /// How tightly it holds together: what an operator may be written next to
    /// without a bracket. One scale for the printer, the typesetter and the
    /// parser's own precedence.
    var level: Int {
        switch self {
        case .number, .symbol, .text, .list, .call, .part, .blank: return WLLevel.atom
        // `-a*b` is `-(a*b)` and `(-a)*b` is something else: as an operand a
        // negation holds together no tighter than the sum it opens.
        case .negate: return WLLevel.sum
        case .prefix: return WLLevel.not
        case .postfix(let op, _): return op == "&" ? WLLevel.function : WLLevel.factorial
        case .binary(let op, _, _): return WLParser.level(of: op)
        }
    }
}

/// The scale of binding strength, loosest first. WL's own, boiled down to
/// what a page of notes can tell apart.
enum WLLevel {
    static let sequence = 1     // a; b
    static let assign = 2       // =  :=
    static let function = 3     // body &
    static let replace = 4      // /.
    static let rule = 5         // ->  :>
    static let condition = 6    // /;
    static let or = 7           // ||
    static let and = 8          // &&
    static let not = 9          // !a
    static let relation = 10    // == != < <= > >= === =!=
    static let sum = 11         // + -
    static let product = 12     // * /  and two things side by side
    static let dot = 13         // a . b
    static let power = 14       // ^
    static let factorial = 15   // n!  f'
    static let atom = 20
}

/// Back to WL text — the canonical spelling, with the brackets it needs and
/// none it does not. What the maths menu writes into the note comes through
/// here, so two ways of typing the same thing land on one form.
enum WLPrinter {
    static func source(_ expr: WLExpr) -> String {
        switch expr {
        case .number(let value): return value
        case .symbol(let name): return name
        case .text(let value): return "\"\(value)\""
        case .list(let items): return "{" + items.map(source).joined(separator: ", ") + "}"
        case .call(let head, let args):
            return wrapped(head, atLeast: WLLevel.factorial) + "[" + args.map(source).joined(separator: ", ") + "]"
        case .part(let base, let indices):
            return wrapped(base, atLeast: WLLevel.atom) + "[[" + indices.map(source).joined(separator: ", ") + "]]"
        case .blank(let name, let count, let head):
            return (name ?? "") + String(repeating: "_", count: count) + (head ?? "")
        case .negate(let operand):
            return "-" + wrapped(operand, atLeast: WLLevel.product)
        case .prefix(let op, let operand):
            return op + wrapped(operand, atLeast: WLLevel.relation)
        case .postfix(let op, let operand):
            if op == "&" { return wrapped(operand, atLeast: WLLevel.function + 1) + " &" }
            return wrapped(operand, atLeast: WLLevel.factorial) + op
        case .binary(let op, let left, let right):
            let level = WLParser.level(of: op)
            let rightAssociative = WLParser.isRightAssociative(op)
            let leftText = wrapped(left, atLeast: rightAssociative ? level + 1 : level)
            let rightText = wrapped(right, atLeast: rightAssociative ? level : level + 1)
            if op == ";" { return leftText + "; " + rightText }
            let spaced = level <= WLLevel.sum || op == "."
            return leftText + (spaced ? " \(op) " : op) + rightText
        }
    }

    private static func wrapped(_ expr: WLExpr, atLeast level: Int) -> String {
        expr.level < level ? "(" + source(expr) + ")" : source(expr)
    }

    /// Whatever was typed, in canonical form — and left alone if it does not
    /// parse, because half-typed maths is still the user's text.
    static func canonical(_ source: String) -> String {
        guard let expr = WLParser.parse(source) else { return source }
        return Self.source(expr)
    }
}
