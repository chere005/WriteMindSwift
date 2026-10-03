import AppKit

/// Live preview for the source editor, without changing a character of the
/// note: the markdown markers stay in the text storage — so the file, the
/// clipboard, undo and Find all still see them — but the layout manager is
/// told to give them a zero-advance control glyph, so they take no width and
/// paint no ink. The paragraph the caret is in keeps its markers visible, so
/// they can still be typed — and for a selection the one its far end is in
/// too (`NSTextView.paragraphsShowingTheirMarkers`).
///
/// `NSLayoutManager` has ONE delegate slot, so this object does
/// `BulletGlyphs`' job in the same pass: the bullet substitution and the
/// hiding are decided per character over one buffer.
final class MarkerHiding: NSObject, NSLayoutManagerDelegate {

    /// Off puts the raw markdown back — the toggle, and the fallback.
    var isEnabled = true

    /// Every marker character in the note, the revealed paragraph aside.
    private(set) var hiddenCharacters = IndexSet()
    private var allMarkers = IndexSet()
    /// FURNITURE: what stays out of sight, or is drawn as something else,
    /// whatever the caret is doing — and where the caret may not go.
    ///
    /// The ordinary hiding shows a paragraph's markers back to you when the
    /// caret arrives, because in the SOURCE pane they are the thing being
    /// typed. On the RENDERED page they are not, and `CellFurniture` is
    /// what decides which is which. This object only carries the answer:
    /// the characters that vanish, the ones drawn as a different glyph, and
    /// the ranges `outside(_:of:)` keeps the caret out of.
    private var furniture = IndexSet()
    private var substitutions: [Int: UniChar] = [:]
    private(set) var furnitureRanges: [NSRange] = []
    /// The paragraphs that keep their markers: the one the caret (or a
    /// selection's start) is in and, for a selection, the one its far end
    /// is in — see `NSTextView.updateHiddenMarkers`.
    private(set) var revealedParagraphs: [NSRange] = []
    /// The caret's paragraph, which is the one nearly every reader means.
    var revealed: NSRange? { revealedParagraphs.first }

    // MARK: - what is hidden

    /// The runs that may vanish: inline syntax only.
    ///
    /// NOT a fence line — `MarkdownSourceStyle` marks the whole ``` line as
    /// `.marker`, and hiding all of it leaves a blank full-height line
    /// rather than closing the gap. NOT `.listMarker` or `.quoteMarker`
    /// either: `BulletGlyphs` already draws those, and a list with no
    /// marker is not a list.
    static func hideable(_ runs: [MarkdownSourceStyle.Run], in text: NSString) -> [NSRange] {
        runs.compactMap { run in
            guard run.kind == .marker || run.kind == .linkURL, run.range.length > 0,
                  NSMaxRange(run.range) <= text.length,
                  !isWholeLine(run.range, in: text)
            else { return nil }
            return run.range
        }
    }

    /// A run that IS its whole line — a fence, a lone `---` — which stays
    /// where it is, and is not inline syntax: nothing pairs with it.
    static func isWholeLine(_ range: NSRange, in text: NSString) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= text.length else { return false }
        let line = text.lineRange(for: range)
        let content = text.substring(with: line).trimmingCharacters(in: .newlines)
        return range.length >= (content as NSString).length
    }

    /// Where the caret really goes when it is put at `range`: out of any
    /// piece of furniture, and out of the FRONT of it — a prefix has
    /// nothing to its left but the start of the line, so there is only one
    /// way out. A real selection is left exactly as it was made.
    ///
    /// PAST ALL OF IT, not past the first piece found. The pieces overlap
    /// on purpose: a reminder's `- ` is furniture because it is a list
    /// marker AND the whole `- [ ] ` is furniture because it is a box, and
    /// each of those is true on its own. Taking the first match put the
    /// caret two characters in, between the dash and the bracket — inside
    /// the very thing it was being moved out of.
    static func outside(_ range: NSRange, of furniture: [NSRange]) -> NSRange {
        guard range.length == 0 else { return range }
        var location = range.location
        // Each turn moves strictly forward, and a piece can only be used
        // once, so this cannot spin.
        for _ in 0...furniture.count {
            let ends = furniture.filter {
                $0.length > 0 && location >= $0.location && location < NSMaxRange($0)
            }
            guard let furthest = ends.map({ NSMaxRange($0) }).max() else { break }
            location = furthest
        }
        return NSRange(location: location, length: 0)
    }

    /// A backspace with the caret just behind a piece of furniture takes
    /// the WHOLE piece: the cell stops being a heading, which is what the
    /// key looks like it is doing. Left alone it ate the space out of
    /// `## `, and the heading quietly became a paragraph beginning `##`.
    static func furnitureBehind(_ caret: Int, in furniture: [NSRange]) -> NSRange? {
        furniture.first { $0.length > 0 && NSMaxRange($0) == caret }
    }

    /// What the cell's furniture is, as `CellFurniture` read it.
    func setFurniture(_ reading: CellFurniture.Reading) {
        furnitureRanges = reading.reserved.filter { $0.length > 0 }
        var set = IndexSet()
        for range in reading.hidden where range.length > 0 {
            set.insert(integersIn: range.location..<NSMaxRange(range))
        }
        furniture = set
        substitutions = reading.glyphs
        rebuild()
    }

    /// Call after every re-scan of the markdown.
    func setMarkers(_ markers: [NSRange]) {
        var set = IndexSet()
        for range in markers where range.length > 0 {
            set.insert(integersIn: range.location..<NSMaxRange(range))
        }
        allMarkers = set
        rebuild()
    }

    /// Move the revealed paragraph. Returns the character ranges whose
    /// glyphs the caller must invalidate — empty when nothing changed, so a
    /// caret move inside one paragraph costs nothing at all.
    func setRevealed(_ paragraph: NSRange?) -> [NSRange] {
        setRevealed(paragraph.map { [$0] } ?? [])
    }

    /// The same for several paragraphs — a selection shows the one it starts
    /// in and the one it ends in. Only a paragraph that was NOT revealed and
    /// now is, or the other way round, needs its glyphs made again.
    func setRevealed(_ paragraphs: [NSRange]) -> [NSRange] {
        guard paragraphs != revealedParagraphs else { return [] }
        let previous = revealedParagraphs
        revealedParagraphs = paragraphs
        rebuild()
        return previous.filter { !paragraphs.contains($0) } + paragraphs.filter { !previous.contains($0) }
    }

    private func rebuild() {
        var set = allMarkers
        for revealed in revealedParagraphs { set.remove(integersIn: revealed.location..<NSMaxRange(revealed)) }
        // The furniture goes back in AFTER the reveal has taken its
        // paragraph out, which is the whole point of it.
        set.formUnion(furniture)
        hiddenCharacters = set
    }

    @inline(__always) private func hides(_ characterIndex: Int) -> Bool {
        isEnabled && hiddenCharacters.contains(characterIndex)
    }

    /// For the arrow keys and anything else that has to step over what
    /// cannot be seen.
    func isHidden(_ characterIndex: Int) -> Bool { hides(characterIndex) }

    // MARK: - the mechanism

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>,
                       font: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        // Off means OFF: no hiding and no bullet substitution either, so
        // "show the markdown" shows the markdown and renders nothing at all
        // (Sean, 2026-09-19: "it keeps trying to render when i'm in show
        // only markdown mode").
        guard isEnabled, let storage = layoutManager.textStorage else { return 0 }
        let text = storage.string as NSString
        var newGlyphs: [CGGlyph]?
        var newProperties: [NSLayoutManager.GlyphProperty]?

        for index in 0..<glyphRange.length {
            let character = characterIndexes[index]
            guard character < text.length else { continue }
            if hides(character) {
                // .controlCharacter + .zeroAdvancement: no width, no ink,
                // and — unlike .null — the caret, the word boundaries and
                // glyphRange(forCharacterRange:) all stay honest.
                if newProperties == nil {
                    newProperties = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
                }
                newProperties?[index].insert(.controlCharacter)
            } else if let stands = substitutions[character],
                      case let substitute = BulletGlyphs.glyph(for: stands, in: font),
                      substitute != 0 {
                // Drawn as something else — the box a reminder's `[`
                // becomes. A font with no glyph for it answers 0, which
                // would draw as nothing at all, so the bracket is left
                // alone rather than losing the box altogether.
                if newGlyphs == nil {
                    newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
                }
                newGlyphs?[index] = substitute
            } else if let bullet = BulletGlyphs.markerGlyph(at: character, in: text, font: font) {
                if newGlyphs == nil {
                    newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
                }
                newGlyphs?[index] = bullet
            }
        }

        guard newGlyphs != nil || newProperties != nil else { return 0 }  // 0: generate as usual
        let finalGlyphs = newGlyphs ?? Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        let finalProperties = newProperties
            ?? Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        finalGlyphs.withUnsafeBufferPointer { g in
            finalProperties.withUnsafeBufferPointer { p in
                layoutManager.setGlyphs(g.baseAddress!, properties: p.baseAddress!,
                                        characterIndexes: characterIndexes, font: font,
                                        forGlyphRange: glyphRange)
            }
        }
        return glyphRange.length
    }

    /// A marker is not really a control character, so say what it should do.
    /// (AppKit already gives an unknown control glyph zero advancement; this
    /// is what stops a hidden tab from still tabbing.)
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        hides(charIndex) ? .zeroAdvancement : action
    }
}

extension NSTextView {
    /// From `textViewDidChangeSelection` and after an edit. Does nothing
    /// while the caret stays in one paragraph; when it moves, it
    /// re-generates the glyphs of the paragraphs involved and nothing
    /// else. Never `ensureLayout(for: container)` here — that lays out the
    /// whole note.
    func updateHiddenMarkers(_ hiding: MarkerHiding) {
        reveal(paragraphsShowingTheirMarkers(), in: hiding)
    }

    /// WHICH PARAGRAPHS KEEP THEIR MARKERS: the one the caret is in, and for
    /// a selection the one its other end is in too (Sean, 2026-10-03:
    /// "cursor behavior around backticks is very weird"). Only the START was
    /// shown, and a selection grows at its END: ⇧→ walked into a line whose
    /// markers were still zero-width, and AppKit steps over a run of
    /// zero-advance glyphs as one place — so one press took a newline and
    /// the backtick after it, or the backtick and the `wl:` behind it, and
    /// the next took them BACK. The selection could not be pushed through a
    /// line with a code span in it.
    ///
    /// - `neighbours`: the paragraphs either side of those, too — what a
    ///   command that extends the selection is about to cross (`doCommand`
    ///   shows them for the length of the command and no longer, so no
    ///   neighbour ever stays open).
    /// - A selection of WHOLE LINES (a triple click) ends at the start of
    ///   the next line, which it did not take, and which must not show its
    ///   markers for it (Sean, 2026-09-20: "the next section shouldn't be
    ///   highlighted") — unless a KEY made it: the caret really is at the
    ///   start of that line, and the next ⇧→ steps over its first character.
    /// - A mouse gesture needs no rule of its own: AppKit announces the
    ///   selection a drag makes once, when the button comes up (a five-event
    ///   drag, down or up the page, is one `didChangeSelection` at the
    ///   release — `testAMouseSelectionIsAnnouncedOnceWhenTheButtonComesUp`),
    ///   so no line changes width under a held pointer, whichever end of the
    ///   selection is the one being dragged, and both ends show when it is
    ///   let go. Were that ever to change, what would be wanted is the
    ///   paragraphs that were showing at the press kept while the button is
    ///   down — not the start's, which is the end under the pointer in an
    ///   upward drag.
    func paragraphsShowingTheirMarkers(neighbours: Bool = false) -> [NSRange] {
        let text = string as NSString
        // A bar between two cells is in NO cell, so no cell shows its
        // markers. Arming parks the caret at the next cell's first
        // character and this is the second reader of that offset — the
        // brackets were taught not to light in ee1cb44 and this one was
        // not, so clicking the seam above `## Notes` popped the heading's
        // hashes into view and shifted its words right, as if the caret
        // had been put in it (Sean, 2026-09-20: "the next section
        // shouldn't be highlighted when the input cursor is currently
        // that horizontal bar"). Arming with ↓ never did it, because the
        // caret sits on the blank line then — one bar, two behaviours.
        let pane = self as? PasteAwareTextView
        guard pane?.armedSeam == nil else { return [] }
        guard text.length > 0 else { return [NSRange(location: 0, length: 0)] }
        func paragraph(at offset: Int) -> NSRange {
            text.lineRange(for: NSRange(location: min(max(offset, 0), text.length - 1), length: 0))
        }
        let selection = selectedRange()
        var found = [paragraph(at: selection.location)]
        if selectedRanges.count == 1, selection.length > 0 {
            var end = NSMaxRange(selection)
            if pane?.isRunningCommand != true, end > selection.location, text.character(at: end - 1) == 10 {
                end -= 1
            }
            found.append(paragraph(at: end))
        }
        if neighbours {
            for around in found {
                if around.location > 0 { found.append(paragraph(at: around.location - 1)) }
                if NSMaxRange(around) < text.length { found.append(paragraph(at: NSMaxRange(around))) }
            }
        }
        var unique: [NSRange] = []
        for range in found where !unique.contains(range) { unique.append(range) }
        return unique
    }

    /// Show exactly these paragraphs' markers, and make again the glyphs of
    /// every paragraph that changed.
    func reveal(_ paragraphs: [NSRange], in hiding: MarkerHiding) {
        guard let layoutManager, let container = textContainer else { return }
        let text = string as NSString
        let dirty = hiding.setRevealed(paragraphs)
        guard !dirty.isEmpty else { return }
        for range in dirty {
            let clipped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
            guard clipped.length > 0 else { continue }
            layoutManager.invalidateGlyphs(forCharacterRange: clipped, changeInLength: 0,
                                           actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: clipped, actualCharacterRange: nil)
            layoutManager.ensureLayout(forCharacterRange: clipped)
        }
        layoutManager.ensureLayout(forBoundingRect: visibleRect, in: container)
        needsDisplay = true
    }
}
