import AppKit

/// Deleting text that has hidden markers in it.
///
/// The markers are still in the note — `**` round bold, `~~` round struck
/// text, `#` in front of a heading — they are only drawn with no width. So
/// a selection made with the eye can cut a pair in half: take "**bo" out of
/// "**bold**" and the note is left holding `ld**`, which renders as a stray
/// pair of asterisks (the to-do list: "a selection that spans one `**` of a
/// pair can leave `**bold*` behind").
///
/// A delete therefore takes whole markers, never half of one, and when it
/// takes one half of a pair it takes the other half too — otherwise the
/// text left behind is marked up with an opener that never closes.
///
/// THREE LIMITS, all found by pressing ⌫ next to a backtick (Sean,
/// 2026-10-03: "cursor behavior around backticks is very weird"):
///
/// - Only INLINE syntax is a marker here. A fence line is one `.marker` run
///   — the whole of "```python" — and every delete that touched a letter of
///   its language was widened to all of it, as was typing over "yth".
/// - A key that deletes what is next to the caret takes THAT and nothing
///   else (`completingPairs: false`): the characters beside it are on the
///   caret's own line, where every marker is showing, so no half-pair is
///   left behind out of sight; one ⌫ after a closing backtick took the
///   opening one too, and ⌦ before an opening one took the closing one.
///   A SELECTION, which can be cut across hidden syntax, still completes.
/// - A `wl:` span's pair is its TWO BACKTICKS. The `wl:` in front of the
///   maths is paired with nothing: it used to be matched with the closing
///   tick, so taking either one took the other and left the OPENING tick
///   standing, to pair with the next backtick in the paragraph.
enum MarkerDeletion {
    /// The ranges a delete should really take, biggest location first so a
    /// caller can apply them back to front without recomputing anything.
    /// One range — the one asked for — when there is nothing to widen.
    ///
    /// The FIRST element of the result is the range that was asked for,
    /// widened; the rest are orphaned partners, which are always deleted
    /// outright. A caller replacing rather than deleting needs to tell the
    /// two apart, so `asked(in:)` says which is which.
    static func deletions(for range: NSRange, in source: String, completingPairs: Bool = true) -> [NSRange] {
        // A range that runs off the end is nobody's edit, and the marker
        // maths below would hand back ranges that cannot be applied.
        let length = (source as NSString).length
        let range = NSIntersectionRange(range, NSRange(location: 0, length: length))
        guard range.length > 0 else { return [range] }
        let runs = MarkdownSourceStyle.runs(in: source)
        guard !runs.isEmpty else { return [range] }

        var wanted = range
        let text = source as NSString
        // A marker the delete only clips is taken whole — inline syntax
        // only, never a fence line.
        let inline = runs.filter { $0.kind != .marker || !MarkerHiding.isWholeLine($0.range, in: text) }
        for run in inline where run.kind == .marker {
            let overlap = NSIntersectionRange(run.range, wanted)
            guard overlap.length > 0, overlap.length < run.range.length else { continue }
            wanted = NSUnionRange(wanted, run.range)
        }

        // …and a pair with one half gone loses the other half as well.
        var extra: [NSRange] = []
        for pair in pairs(in: inline) where completingPairs {
            let opener = NSIntersectionRange(pair.open, wanted).length == pair.open.length
            let closer = NSIntersectionRange(pair.close, wanted).length == pair.close.length
            if opener, !closer { extra.append(pair.close) }
            if closer, !opener { extra.append(pair.open) }
        }

        return ([wanted] + extra).sorted { $0.location > $1.location }
    }

    /// Which of `deletions` is the range the user actually selected — the
    /// one a replacement goes into. The others are orphaned markers and
    /// are only ever removed.
    ///
    /// It matters because a delete is not the only thing that can cut a
    /// pair in half: TYPING over such a selection, or pasting into it,
    /// does the same damage and used to go straight through unwidened —
    /// "**bo" replaced by "x" in "**bold** here" left "xld** here".
    static func asked(_ range: NSRange, in deletions: [NSRange]) -> NSRange {
        deletions.first { NSIntersectionRange($0, range).length > 0 } ?? range
    }

    /// The marker either side of a styled run — the two halves that have to
    /// go together.
    static func pairs(in runs: [MarkdownSourceStyle.Run]) -> [(open: NSRange, close: NSRange)] {
        let markers = runs.filter { $0.kind == .marker }
        var out: [(open: NSRange, close: NSRange)] = []
        for run in runs {
            switch run.kind {
            case .bold, .italic, .strikethrough, .code:
                guard let open = markers.first(where: { NSMaxRange($0.range) == run.range.location }),
                      let close = markers.first(where: { $0.range.location == NSMaxRange(run.range) })
                else { continue }
                out.append((open.range, close.range))
            case .math:
                // `, wl:, the maths, ` — the pair is the backticks round the
                // lot, and the `wl:` is just in front of the maths.
                guard let prefix = markers.first(where: { NSMaxRange($0.range) == run.range.location }),
                      let open = markers.first(where: { NSMaxRange($0.range) == prefix.range.location }),
                      let close = markers.first(where: { $0.range.location == NSMaxRange(run.range) })
                else { continue }
                out.append((open.range, close.range))
            default:
                continue
            }
        }
        return out
    }
}

extension NSTextView {
    /// An edit over markers, made whole — what both editors do when a delete
    /// or a typed replacement reaches into one (`MarkerDeletion`): the range
    /// widened over any marker it clips, and a pair it cuts in half given up
    /// with it. The orphaned partner is always removed outright; whatever is
    /// being put in goes where the selection was.
    ///
    /// True: the edit was made HERE, and the one NSTextView was about to make
    /// must not go ahead. False: it needs nothing, go ahead as asked.
    ///
    /// BOTH EDITORS call it. The rendered page's editor had no widening at
    /// all, so a selection that cut half a code span left the other tick
    /// standing there — and the markdown pane took two ticks for one ⌫
    /// (Sean, 2026-10-03: "cursor behavior around backticks is very weird").
    /// Never in a code cell, whose text is code and not markdown.
    func applyMarkerDeletion(range: NSRange, replacement: String?, completingPairs: Bool) -> Bool {
        guard range.length > 0, let replacement, let storage = textStorage else { return false }
        let ranges = MarkerDeletion.deletions(for: range, in: string, completingPairs: completingPairs)
        guard ranges != [range] else { return false }
        let asked = MarkerDeletion.asked(range, in: ranges)
        let strings = ranges.map { $0 == asked ? replacement : "" }
        // In order (`shouldChangeText(over:)`): the deletions come back to
        // front, and "**bo" typed over in "**bold** here" threw instead of
        // leaving "xld here".
        guard shouldChangeText(over: zip(ranges, strings).map { ($0, $1) }) else { return true }
        // Back to front, so an earlier range's location still means what it
        // meant when it was worked out.
        storage.beginEditing()
        for (range, string) in zip(ranges, strings) {
            storage.replaceCharacters(in: range, with: string)
        }
        storage.endEditing()
        didChangeText()
        // After whatever went in, not before it.
        if let last = ranges.last {
            let typed = last == asked ? (replacement as NSString).length : 0
            setSelectedRange(NSRange(location: last.location + typed, length: 0))
        }
        return true
    }
}
