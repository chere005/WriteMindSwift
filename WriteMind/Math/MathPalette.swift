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
    /// WHAT A SHAPE WITH PARTS WRAPS: the selection the palette was opened
    /// over, or the typed maths the first shape took into its first part —
    /// kept, so that the next shape, and the same one again, wrap it too
    /// rather than falling back to their own suggestions. Typing in the
    /// field lets it go: the field is something else now.
    private(set) var subject: String?
    /// Where the caret belongs in `expression` after a shape was written
    /// into it (in UTF-16 units, as AppKit counts), for the view to put back;
    /// nil when the field's own place for it — the end — is right.
    private(set) var caret: Int?
    /// On a line of its own, or in the sentence.
    var onItsOwnLine = true

    var reading: Reading {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        switch MathMarkup.read(trimmed) {
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
        subject = found.wl
        expression = found.wl
        onItsOwnLine = !found.inline
    }

    // MARK: - Editing

    /// The field was typed in. The picked shape no longer describes it,
    /// so its parts go: they come back when a shape is picked. What the
    /// shapes wrap goes too: it is whatever is in the field now.
    mutating func type(_ text: String) {
        guard text != expression else { return }
        expression = text
        template = nil
        values = []
        subject = nil
        caret = nil
    }

    /// A SHAPE PICKED, and the field and the shapes COMPOSE (Sean's decision
    /// on the review of 2026-10-03; before it a shape overwrote the field, so
    /// `2`, π, `r` could not make `2 Pi r`, and a formula typed was gone with
    /// the next shape):
    ///
    /// - A shape with no parts to fill — a Greek letter, a constant, a
    ///   symbol — is written INTO the field at the caret (`selection`, as the
    ///   field's editor says it; the end when it does not): over what is
    ///   there it would only be typed over. A space goes either side where
    ///   it would run into its neighbour, and the caret ends after it, so
    ///   typing goes on: `2`, π, `r` is `2 Pi r`. This holds for text that
    ///   does not read yet, which is what is typed half way to a formula.
    /// - A shape with parts WRAPS the field, in its first part: what was
    ///   typed or selected and reads as maths, brackets added where the
    ///   shape's operator reaches it (`a + b` into the exponent is
    ///   `(a + b)^2`). What the previous shape wrote is replaced, never
    ///   wrapped, so browsing the shapes does not nest them — and what was
    ///   wrapped (`subject`) is wrapped again by the next one. Over text that
    ///   does not read there is nothing to wrap: the shape is written in
    ///   with the caret, as above, and nothing typed is lost.
    mutating func choose(_ shape: MathTemplate, selection: NSRange? = nil) {
        caret = nil
        if shape.slots.isEmpty {
            compose(shape.wl([]), at: selection)
            return
        }
        if template == nil {
            switch reading {
            case .maths(let canonical): subject = canonical
            case .empty: subject = nil
            case .broken:
                compose(shape.wl(shape.initialValues), at: selection)
                return
            }
        }
        template = shape
        values = shape.values(seed: subject)
        expression = shape.wl(values)
    }

    /// `text` written into the field at the caret, which is now what the
    /// user typed: no shape's parts describe it.
    private mutating func compose(_ text: String, at selection: NSRange?) {
        let written = Self.writing(text, into: expression, at: selection)
        expression = written.field
        caret = written.caret
        template = nil
        values = []
        subject = nil
    }

    /// `text` written into `field` at the END of `selection` — a selection
    /// is never replaced: the editor selects all of the field's text when it
    /// takes the keyboard, and that is not a decision to throw it away —
    /// with a space before it unless it follows nothing or an opening
    /// bracket or a comma, and a space after it always, where the next thing
    /// typed would otherwise be part of it (`Pi` then `r` is `Pir`). The
    /// caret is returned in UTF-16 units, after that space.
    static func writing(_ text: String, into field: String, at selection: NSRange?) -> (field: String, caret: Int) {
        let ns = field as NSString
        var place = ns.length
        if let selection, selection.location != NSNotFound {
            place = min(max(0, selection.location + selection.length), ns.length)
        }
        let before = ns.substring(to: place)
        let after = ns.substring(from: place)
        let lead = before.last.map { !$0.isWhitespace && !"([{,".contains($0) } == true ? " " : ""
        let head = before + lead + text + " "
        return (head + after, head.utf16.count)
    }

    /// A part of the picked shape filled in; the expression follows.
    mutating func setValue(_ text: String, at index: Int) {
        guard let template, values.indices.contains(index) else { return }
        values[index] = text
        expression = template.wl(values)
    }
}
