import Foundation

/// WHAT THE MATHS PALETTE HOLDS, as a value: the expression in its free
/// field, the shape picked (if one is) with the parts that fill it, how it
/// will be set, and whether what is there may be inserted.
///
/// Sean, 2026-10-03: "maths input should also just allow for an expression
/// so i could insert a function or something and it would appear like the
/// derivatives or integrals". The palette used to be a pile of shapes with
/// an editable WL line under them that was shown raw when it did not parse
/// and inserted all the same. The expression is the palette now: a shape
/// is a way of writing one, and `reading` says whether what is in the field
/// parses — and says why not — so that nothing broken is inserted without
/// the palette having said so. The view is `MathMenu`; it holds none of
/// this.
struct MathPalette: Equatable {
    /// What the field says about the expression.
    enum Reading: Equatable {
        /// Nothing typed yet.
        case empty
        /// It parses: this is what will be written, in the one spelling.
        case maths(canonical: String)
        /// It does not, and here is why.
        case broken(WLSyntaxError)
    }

    /// The free field, as typed. It is what Insert writes.
    private(set) var expression = ""
    /// The shape picked, while the expression is still what it writes.
    private(set) var template: MathTemplate?
    /// What fills the picked shape's parts.
    private(set) var values: [String] = []
    /// The selection the palette was opened over, when it read as maths: a
    /// shape picked wraps it.
    private(set) var seed: String?
    /// On a line of its own, or in the sentence.
    var onItsOwnLine = true

    var reading: Reading {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        switch WLParser.read(trimmed) {
        case .success(let parsed): return .maths(canonical: WLPrinter.source(parsed))
        case .failure(let error): return .broken(error)
        }
    }

    /// Whether Insert and Return may write it.
    var canInsert: Bool {
        if case .maths = reading { return true }
        return false
    }

    /// What goes to `Insertion`: the expression in its one spelling, and
    /// where it goes. Nil while it is empty or does not parse.
    var insertion: Insertion.Thing? {
        guard case .maths(let canonical) = reading else { return nil }
        return .maths(canonical, onItsOwnLine: onItsOwnLine)
    }

    /// Why it cannot be inserted, in a sentence; nil when it can, or when
    /// there is nothing yet to be wrong.
    var problem: String? {
        if case .broken(let error) = reading { return error.message }
        return nil
    }

    /// The canonical spelling, when it differs from what was typed — what
    /// the note will actually hold.
    var storedAs: String? {
        guard case .maths(let canonical) = reading,
              canonical != expression.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return canonical
    }

    // MARK: - Opening

    /// OPENED OVER A SELECTION THAT READS AS MATHS, the palette starts from
    /// it (Sean, 2026-10-02: "make math and code block insertion
    /// sensible.."): the expression is the selection, so Insert sets
    /// exactly what was selected, in the sentence when it sits in one; and
    /// a shape picked afterwards takes it into its first slot. With no
    /// selection the field is empty and nothing is picked: the cursor is
    /// in it, ready for an expression.
    mutating func start(seed found: MathSelection.Seed?) {
        guard let found else { return }
        seed = found.wl
        expression = found.wl
        onItsOwnLine = !found.inline
    }

    // MARK: - Editing

    /// The field was typed in. The picked shape no longer describes it,
    /// so its parts go: they come back when a shape is picked.
    mutating func type(_ text: String) {
        guard text != expression else { return }
        expression = text
        template = nil
        values = []
    }

    /// A shape picked. It takes what is wrapped — the selection the palette
    /// opened over, or what was typed in the field and reads as maths —
    /// into its first slot, and the rest start as they always do. What a
    /// previous shape wrote is replaced, not wrapped: browsing the shapes
    /// must not nest them.
    mutating func choose(_ shape: MathTemplate) {
        let subject: String?
        if template == nil, case .maths(let canonical) = reading { subject = canonical } else { subject = seed }
        template = shape
        values = shape.values(seed: subject)
        expression = shape.wl(values)
    }

    /// A part of the picked shape filled in; the expression follows.
    mutating func setValue(_ text: String, at index: Int) {
        guard let template, values.indices.contains(index) else { return }
        values[index] = text
        expression = template.wl(values)
    }
}
