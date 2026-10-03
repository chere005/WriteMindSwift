import Foundation

/// Why a piece of maths did not read, and where — so the palette can say
/// "Missing ]" under the field instead of showing a blank, and so nothing
/// broken is ever written into a note without being told (Sean, 2026-10-03:
/// "maths input should also just allow for an expression").
struct WLSyntaxError: Error, Equatable {
    /// One sentence a person can act on.
    let message: String
    /// Where it went wrong, in characters from the start of what was typed:
    /// the token at fault, or the end of the text when something is missing.
    let offset: Int
    let length: Int
}

/// Reads WL. Not the language — the arithmetic, the brackets, the lists,
/// the function calls, and the rest of what a formula is written with:
/// relations and logic, `=` and `:=`, rules, patterns, parts, primes,
/// factorials and pure functions.
enum WLParser {
    /// What it will not read: a text this long, or this deep in brackets,
    /// is not a formula but a mistake, and the recursion that sets it would
    /// otherwise be the app's to survive.
    static let maxTokens = 2000
    static let maxDepth = 300

    static func parse(_ source: String) -> WLExpr? {
        if case .success(let expression) = read(source) { return expression }
        return nil
    }

    /// The expression, or the reason there is none.
    static func read(_ source: String) -> Result<WLExpr, WLSyntaxError> {
        let (tokens, lexical) = lex(source)
        if let lexical { return .failure(lexical) }
        guard !tokens.isEmpty else {
            return .failure(WLSyntaxError(message: "There is nothing to typeset yet.", offset: 0, length: 0))
        }
        guard tokens.count <= maxTokens else {
            return .failure(WLSyntaxError(message: "That is too long to typeset (the limit is \(maxTokens) symbols).",
                                          offset: tokens[maxTokens].offset, length: 1))
        }
        if let unbalanced = bracketError(in: tokens, length: source.count) { return .failure(unbalanced) }
        var parser = Parser(tokens: tokens, end: source.count)
        let expression = parser.expression(0)
        if let expression, parser.isFinished { return .success(expression) }
        // A new line between two complete expressions ends the statement, as
        // it does in a Wolfram notebook: this is one expression too many, and
        // is said so — never read as the product of the two (a = 1⏎b = 2 was
        // a = ((1·b) = 2), and then written into the note as that).
        if expression != nil, parser.error == nil, let next = parser.current, next.lineBreakBefore,
           next.kind != .punct || next.value == "(" || next.value == "{" {
            return .failure(WLSyntaxError(
                message: "Maths holds one expression, and a new line starts a second one (position \(next.offset + 1)): "
                    + "join them with \";\" or insert them one at a time.",
                offset: next.offset, length: next.length))
        }
        return .failure(parser.error ?? parser.unexpectedCurrent())
    }

    // MARK: - Tokens

    struct Token: Equatable {
        enum Kind { case number, symbol, text, op, punct, pattern }
        let kind: Kind
        let value: String
        /// Where it starts in what was typed, and how many characters it
        /// takes there.
        var offset = 0
        var length = 1
        /// Whether a line break (not one inside a comment or a string) lies
        /// between the token before it and this one. At the top level, outside
        /// every bracket, that is where a statement ends.
        var lineBreakBefore = false

        var end: Int { offset + length }
    }

    /// Longest first, so `===` is not `==` and `=`.
    static let operators = ["===", "=!=", "->", ":>", ":=", "==", "!=", "<=", ">=", "&&", "||", "/;", "/.",
                            "+", "-", "*", "/", "^", "<", ">", "=", "!", "&", ";", ".", "'"]

    /// What the page's own typography and a keyboard's autocorrect turn
    /// maths into, put back: typed or pasted, a `−` is a minus, “ ” are the
    /// quotes of a string, × is times — and what is stored is the plain WL.
    private static let typography: [Character: (Token.Kind, String)] = [
        "−": (.op, "-"), "–": (.op, "-"), "—": (.op, "-"),
        "×": (.op, "*"), "·": (.op, "*"), "⋅": (.op, "*"), "∙": (.op, "*"), "÷": (.op, "/"),
        "≤": (.op, "<="), "≥": (.op, ">="), "≠": (.op, "!="), "→": (.op, "->"),
        "′": (.op, "'"), "’": (.op, "'"), "‘": (.op, "'"),
        "∞": (.symbol, "Infinity"), "°": (.symbol, "Degree")
    ]

    private static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"
    ]

    private static let quotes: Set<Character> = ["\"", "“", "”", "„"]

    static func tokenize(_ source: String) -> [Token] { lex(source).tokens }

    private static func lex(_ source: String) -> (tokens: [Token], error: WLSyntaxError?) {
        var tokens: [Token] = []
        let characters = Array(source)
        var index = 0
        // A line break seen in the white space before the next token. Each
        // pass of the loop below makes at most one white-space skip or
        // adds tokens; `settle` hands the break to the first token added.
        var breakPending = false
        var settled = 0
        func settle() {
            if tokens.count > settled {
                tokens[settled].lineBreakBefore = breakPending
                breakPending = false
                settled = tokens.count
            }
        }

        func at(_ position: Int) -> Character? { position < characters.count ? characters[position] : nil }
        func isDigit(_ character: Character) -> Bool { character.isNumber && superscripts[character] == nil }
        func isWordCharacter(_ character: Character) -> Bool { character.isLetter || isDigit(character) || character == "$" }

        while index < characters.count {
            settle()
            let character = characters[index]
            let start = index
            if tokens.count > maxTokens { break }

            if character.isWhitespace {
                if character.isNewline { breakPending = true }
                index += 1
                continue
            }

            // (* a comment *), which WL skips and so does this. They nest.
            if character == "(", at(index + 1) == "*" {
                var depth = 1
                index += 2
                while index < characters.count, depth > 0 {
                    if characters[index] == "(", at(index + 1) == "*" { depth += 1; index += 2 }
                    else if characters[index] == "*", at(index + 1) == ")" { depth -= 1; index += 2 }
                    else { index += 1 }
                }
                if depth > 0 {
                    return (tokens, WLSyntaxError(message: "A comment (* … is never closed with *).",
                                                  offset: start, length: 2))
                }
                continue
            }

            // \[Alpha] — WL spells Greek letters like this, and they are names.
            if character == "\\", at(index + 1) == "[" {
                var name = "\\["
                index += 2
                while index < characters.count, characters[index] != "]", characters[index].isLetter
                    || characters[index].isNumber {
                    name.append(characters[index]); index += 1
                }
                guard at(index) == "]" else {
                    return (tokens, WLSyntaxError(message: "A \\[Name] is missing its closing ].",
                                                  offset: start, length: index - start))
                }
                index += 1
                tokens.append(Token(kind: .symbol, value: name + "]", offset: start, length: index - start))
                continue
            }

            // ² ³ and their kind: x² is x^2, however it was typed.
            if superscripts[character] != nil {
                tokens.append(Token(kind: .op, value: "^", offset: start, length: 1))
                var digits = ""
                while let next = at(index), let plain = superscripts[next] { digits.append(plain); index += 1 }
                tokens.append(Token(kind: .number, value: digits, offset: start, length: index - start))
                continue
            }

            if isDigit(character) || (character == "." && at(index + 1).map(isDigit) == true) {
                var number = ""
                var seenDot = false
                while let next = at(index) {
                    if isDigit(next) { number.append(next) }
                    else if next == ".", !seenDot { seenDot = true; number.append(next) }
                    else { break }
                    index += 1
                }
                tokens.append(Token(kind: .number, value: number, offset: start, length: index - start))
                continue
            }

            // A name, or a pattern named with it: x_  x__  x_Integer.
            if character.isLetter || character == "$" || character == "_" {
                var name = ""
                while let next = at(index), isWordCharacter(next) { name.append(next); index += 1 }
                if at(index) == "_" || (name.isEmpty && character == "_") {
                    var pattern = name
                    var underscores = 0
                    while at(index) == "_", underscores < 3 { pattern.append("_"); index += 1; underscores += 1 }
                    while let next = at(index), isWordCharacter(next) { pattern.append(next); index += 1 }
                    tokens.append(Token(kind: .pattern, value: pattern, offset: start, length: index - start))
                } else {
                    tokens.append(Token(kind: .symbol, value: name, offset: start, length: index - start))
                }
                continue
            }

            // #, #2, ##, #name — the slot of a pure function.
            if character == "#" {
                var slot = ""
                while at(index) == "#" { slot.append("#"); index += 1 }
                while let next = at(index), isWordCharacter(next) { slot.append(next); index += 1 }
                tokens.append(Token(kind: .symbol, value: slot, offset: start, length: index - start))
                continue
            }

            if quotes.contains(character) {
                var value = ""
                index += 1
                var closed = false
                while let next = at(index) {
                    if next == "\\", let escaped = at(index + 1) {
                        value.append(next); value.append(escaped); index += 2; continue
                    }
                    index += 1
                    if quotes.contains(next) { closed = true; break }
                    value.append(next)
                }
                guard closed else {
                    return (tokens, WLSyntaxError(message: "A string is missing its closing quote.",
                                                  offset: start, length: 1))
                }
                tokens.append(Token(kind: .text, value: value, offset: start, length: index - start))
                continue
            }

            if let (kind, value) = typography[character] {
                tokens.append(Token(kind: kind, value: value, offset: start, length: 1))
                index += 1
                continue
            }

            let rest = String(characters[index..<min(characters.count, index + 3)])
            if let match = operators.first(where: { rest.hasPrefix($0) }) {
                tokens.append(Token(kind: .op, value: match, offset: start, length: match.count))
                index += match.count
                continue
            }

            tokens.append(Token(kind: .punct, value: String(character), offset: start, length: 1))
            index += 1
        }
        settle()
        return (tokens, nil)
    }

    // MARK: - Brackets

    /// The brackets, checked on their own and first: an unbalanced bracket
    /// is the mistake made most often and the one with the plainest thing
    /// to say, and the grammar below would only say "unexpected end".
    private static func bracketError(in tokens: [Token], length: Int) -> WLSyntaxError? {
        let closer: [String: String] = ["(": ")", "[": "]", "{": "}"]
        var open: [Token] = []
        for token in tokens where token.kind == .punct {
            if closer[token.value] != nil { open.append(token); continue }
            guard [")", "]", "}"].contains(token.value) else { continue }
            guard let last = open.popLast() else {
                return WLSyntaxError(
                    message: "Unexpected \"\(token.value)\" at position \(token.offset + 1) — nothing is open to close.",
                    offset: token.offset, length: 1)
            }
            if closer[last.value] != token.value {
                return WLSyntaxError(
                    message: "The \"\(last.value)\" at position \(last.offset + 1) is closed by \"\(token.value)\" "
                        + "at position \(token.offset + 1) — it needs \"\(closer[last.value]!)\".",
                    offset: token.offset, length: 1)
            }
        }
        if let last = open.last {
            return WLSyntaxError(
                message: "Missing \"\(closer[last.value]!)\" — the \"\(last.value)\" at position \(last.offset + 1) "
                    + "is never closed.",
                offset: last.offset, length: 1)
        }
        return nil
    }

    // MARK: - Precedence

    /// How tightly an operator binds: `WLLevel`.
    static func level(of op: String) -> Int {
        switch op {
        case ";": return WLLevel.sequence
        case "=", ":=": return WLLevel.assign
        case "/.": return WLLevel.replace
        case "->", ":>": return WLLevel.rule
        case "/;": return WLLevel.condition
        case "||": return WLLevel.or
        case "&&": return WLLevel.and
        case "==", "!=", "===", "=!=", "<", "<=", ">", ">=": return WLLevel.relation
        case "+", "-": return WLLevel.sum
        case "*", "/": return WLLevel.product
        case ".": return WLLevel.dot
        case "^": return WLLevel.power
        default: return 0
        }
    }

    static func isRightAssociative(_ op: String) -> Bool { ["^", "->", ":>", "=", ":="].contains(op) }

    // MARK: - The parser itself

    private struct Parser {
        let tokens: [Token]
        /// The length of what was typed: where "something is missing" points.
        let end: Int
        var index = 0
        var depth = 0
        /// How many brackets are open here: inside any of them a new line is
        /// white space, as in WL; outside them it ends a statement.
        var open = 0
        var error: WLSyntaxError?

        var isFinished: Bool { index >= tokens.count }
        var current: Token? { index < tokens.count ? tokens[index] : nil }

        mutating func fail(_ message: String, at token: Token?) {
            guard error == nil else { return }
            error = WLSyntaxError(message: message, offset: token?.offset ?? end, length: token?.length ?? 0)
        }

        func unexpectedCurrent() -> WLSyntaxError {
            guard let token = current else {
                return WLSyntaxError(message: "That ends too soon.", offset: end, length: 0)
            }
            return WLSyntaxError(message: "Unexpected \"\(token.value)\" at position \(token.offset + 1).",
                                 offset: token.offset, length: token.length)
        }

        mutating func enter() -> Bool {
            depth += 1
            guard depth <= WLParser.maxDepth else {
                fail("That is nested too deeply to typeset.", at: current)
                return false
            }
            return true
        }

        mutating func expression(_ minimum: Int) -> WLExpr? {
            guard enter() else { return nil }
            defer { depth -= 1 }
            guard var left = unary(minimum) else { return nil }

            while let token = current {
                // `left` is complete, and the next thing starts a new line
                // outside every bracket: that is another statement, not an
                // operand (`a = 1⏎b = 2`) and not a continuation (`a⏎+ b`).
                if token.lineBreakBefore, open == 0 { break }
                if token.kind == .op {
                    // body & — a pure function, written after what it is.
                    if token.value == "&" {
                        guard WLLevel.function >= minimum else { break }
                        index += 1
                        left = .postfix("&", left)
                        continue
                    }
                    let level = WLParser.level(of: token.value)
                    guard level > 0, level >= minimum else { break }
                    index += 1
                    let right = WLParser.isRightAssociative(token.value) ? level : level + 1
                    guard let operand = expression(right) else {
                        fail("Expected an expression after \"\(token.value)\".", at: current)
                        return nil
                    }
                    left = .binary(token.value, left, operand)
                    continue
                }
                // `2 x` is a product in WL, and someone typing into a slot
                // will write it that way.
                if startsPrimary(token), WLLevel.product >= minimum {
                    guard let operand = expression(WLLevel.product + 1) else { return nil }
                    left = .binary("*", left, operand)
                    continue
                }
                break
            }
            return left
        }

        private func startsPrimary(_ token: Token) -> Bool {
            switch token.kind {
            case .number, .symbol, .text, .pattern: return true
            case .punct: return token.value == "(" || token.value == "{"
            case .op: return false
            }
        }

        mutating func unary(_ minimum: Int) -> WLExpr? {
            if let token = current, token.kind == .op {
                switch token.value {
                case "-":
                    index += 1
                    // `-x^2` is -(x^2) and `-a*b` is -(a*b); but in `2^-x*3`
                    // the minus belongs to the exponent alone.
                    guard enter() else { return nil }
                    defer { depth -= 1 }
                    guard let operand = expression(max(minimum, WLLevel.product)) else {
                        fail("Expected an expression after \"-\".", at: current)
                        return nil
                    }
                    return .negate(operand)
                case "+":
                    index += 1
                    guard enter() else { return nil }
                    defer { depth -= 1 }
                    return unary(minimum)
                case "!":
                    index += 1
                    guard enter() else { return nil }
                    defer { depth -= 1 }
                    guard let operand = expression(max(minimum, WLLevel.relation)) else {
                        fail("Expected an expression after \"!\".", at: current)
                        return nil
                    }
                    return .prefix("!", operand)
                default:
                    fail("Expected an expression before \"\(token.value)\".", at: token)
                    return nil
                }
            }
            return postfix()
        }

        mutating func postfix() -> WLExpr? {
            guard var value = primary() else { return nil }
            while let token = current {
                if token.lineBreakBefore, open == 0 { break }
                if token.kind == .punct, token.value == "[" {
                    // m[[i]] — two brackets side by side are a part.
                    if index + 1 < tokens.count, tokens[index + 1].kind == .punct, tokens[index + 1].value == "[",
                       tokens[index + 1].offset == token.end {
                        index += 2
                        guard let indices = list(until: "]"), let close = current,
                              close.kind == .punct, close.value == "]", close.offset == tokens[index - 1].end
                        else {
                            fail("A part m[[i]] is closed with ]].", at: current)
                            return nil
                        }
                        index += 1
                        value = .part(value, indices)
                        continue
                    }
                    index += 1
                    guard let arguments = list(until: "]") else { return nil }
                    value = .call(value, arguments)
                } else if token.kind == .op, token.value == "!" || token.value == "'" {
                    index += 1
                    value = .postfix(token.value, value)
                } else {
                    break
                }
            }
            return value
        }

        mutating func primary() -> WLExpr? {
            guard let token = current else {
                fail(index > 0 ? "Expected an expression after \"\(tokens[index - 1].value)\"."
                     : "There is nothing to typeset yet.", at: nil)
                return nil
            }
            switch token.kind {
            case .number: index += 1; return .number(token.value)
            case .symbol: index += 1; return .symbol(token.value)
            case .text: index += 1; return .text(token.value)
            case .pattern: index += 1; return blank(token.value)
            case .op:
                fail("Expected an expression before \"\(token.value)\".", at: token)
                return nil
            case .punct:
                switch token.value {
                case "(":
                    index += 1
                    open += 1
                    defer { open -= 1 }
                    guard let inner = expression(0) else {
                        if error == nil { fail("Expected an expression inside \"(\".", at: current) }
                        return nil
                    }
                    guard let close = current, close.kind == .punct, close.value == ")" else {
                        fail("Expected \")\" here.", at: current)
                        return nil
                    }
                    index += 1
                    return inner
                case "{":
                    index += 1
                    guard let items = list(until: "}") else { return nil }
                    return .list(items)
                case ")", "]", "}":
                    // Nothing between an opening bracket or a comma and the
                    // bracket that closes: `f[x,]`, `()`.
                    fail(index > 0 ? "Expected an expression after \"\(tokens[index - 1].value)\"."
                         : "Unexpected \"\(token.value)\" at position \(token.offset + 1).", at: token)
                    return nil
                case "|":
                    fail("Unexpected \"|\" at position \(token.offset + 1) — an absolute value is Abs[x] in WL.",
                         at: token)
                    return nil
                default:
                    fail("Unexpected \"\(token.value)\" at position \(token.offset + 1).", at: token)
                    return nil
                }
            }
        }

        /// `x_`, `__`, `_Integer`, `x_Real`: the name before the underscores,
        /// how many, and the head after them.
        private func blank(_ text: String) -> WLExpr {
            let name = text.prefix { $0 != "_" }
            let rest = text.dropFirst(name.count)
            let count = rest.prefix { $0 == "_" }.count
            let head = rest.dropFirst(count)
            return .blank(name: name.isEmpty ? nil : String(name), count: count,
                          head: head.isEmpty ? nil : String(head))
        }

        /// Comma-separated expressions up to a closing bracket.
        mutating func list(until close: String) -> [WLExpr]? {
            open += 1
            defer { open -= 1 }
            var items: [WLExpr] = []
            if let token = current, token.kind == .punct, token.value == close {
                index += 1
                return items
            }
            while true {
                guard let item = expression(0) else { return nil }
                items.append(item)
                guard let token = current, token.kind == .punct else {
                    fail("Expected \",\" or \"\(close)\" here.", at: current)
                    return nil
                }
                if token.value == "," { index += 1; continue }
                if token.value == close { index += 1; return items }
                fail("Expected \",\" or \"\(close)\" here but found \"\(token.value)\".", at: token)
                return nil
            }
        }
    }
}
