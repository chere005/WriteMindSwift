import Foundation

/// WHAT A SELECTION MEANS TO THE MATHS PALETTE: whether it reads as maths,
/// so the palette starts from it, and whether the maths about to go in still
/// holds it, so it may take the selection's place.
///
/// Sean, 2026-10-02: "make math and code block insertion sensible..". The
/// palette used to REPLACE whatever was selected with what it wrote, and
/// showed nothing of the selection while it was open: select "x^2 + 1",
/// pick √, and the note said `Sqrt[x]`; select two words, pick π, and the
/// words were gone with nothing on screen to say where. Now the selection
/// is what the palette opens with when it reads as maths — Insert typesets
/// exactly it, and a shape picked after puts it in the shape's first slot
/// (√ of it) — and selected words are never thrown away.
enum MathSelection {
    /// What the palette opens with: the selection's WL, and whether it sits
    /// inside a line of words — in which case the maths goes in the
    /// sentence rather than on a line of its own.
    struct Seed: Equatable {
        var wl: String
        var inline: Bool
    }

    /// The WL a selection reads as, in the one spelling the palette writes —
    /// nil for words. WL parses "the area" as the product of two symbols
    /// and "Area" as one, so a selection with a WORD in it is words
    /// whatever the parser says: a name of two or more letters that is not
    /// one the maths is set with (`Pi`, `Infinity`, `Sin`), not a `\[Name]`
    /// and not the head of a call (`Sqrt[2]`). A variable is one letter.
    /// The newline at an end is not part of it: a triple-click takes the
    /// line's own with it (the review of 2026-10-02 — the most common way
    /// to take a line read as words). One in the middle is two lines.
    static func reading(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline),
              let expression = WLParser.parse(trimmed)
        else { return nil }
        let tokens = WLParser.tokenize(trimmed)
        let words = tokens.indices.contains { index in
            let name = tokens[index].value
            guard tokens[index].kind == .symbol, name.count >= 2, !name.hasPrefix("\\[") else { return false }
            if index + 1 < tokens.count, tokens[index + 1].kind == .punct, tokens[index + 1].value == "[" {
                return false
            }
            return MathSymbols.constants[name] == nil && MathSymbols.functions[name] == nil
        }
        return words ? nil : WLPrinter.source(expression)
    }

    /// Whether `wl` still holds the selected text — it IS it, or has it
    /// inside, a whole term of it and not a letter of some name. Only then
    /// may the maths take the selection's place.
    static func holds(_ wl: String, selected: String) -> Bool {
        guard let read = reading(selected), let part = WLParser.parse(read),
              let whole = WLParser.parse(WLPrinter.canonical(wl))
        else { return false }
        return contains(whole, part)
    }

    private static func contains(_ whole: WLExpr, _ part: WLExpr) -> Bool {
        if whole == part { return true }
        switch whole {
        case .list(let items): return items.contains { contains($0, part) }
        case .call(let head, let arguments): return contains(head, part) || arguments.contains { contains($0, part) }
        case .binary(_, let left, let right): return contains(left, part) || contains(right, part)
        case .negate(let operand): return contains(operand, part)
        case .number, .symbol, .text: return false
        }
    }

    /// The seed for the selection `selection` of `text`, or nil when there
    /// is no selection or it is words.
    static func seed(in text: String, selection: NSRange) -> Seed? {
        let ns = text as NSString
        let selection = MarkdownFormatting.clamp(selection, to: ns.length)
        guard selection.length > 0, let wl = reading(ns.substring(with: selection)) else { return nil }
        let first = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let before = ns.substring(with: NSRange(location: first.location, length: selection.location - first.location))
        let last = ns.lineRange(for: NSRange(location: NSMaxRange(selection) - 1, length: 0))
        let after = ns.substring(with: NSRange(location: NSMaxRange(selection),
                                               length: max(0, NSMaxRange(last) - NSMaxRange(selection))))
        let inLine = !before.trimmingCharacters(in: .whitespaces).isEmpty
            || !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Seed(wl: wl, inline: inLine)
    }
}
