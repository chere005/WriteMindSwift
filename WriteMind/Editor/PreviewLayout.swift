import CoreGraphics

/// Where the preview's blocks sit: a plain stack, cell then seam then cell.
///
/// Nothing on the drawing layer is in it. Objects float over the note and
/// never move it (Sean, 2026-09-20: "all drawing, captured or drawn with
/// the pen tool, are now free floating and don't belong to cells whatsoever
/// and so don't push other cells around"), so there is one gap between two
/// cells and no block ever carries a push of its own. Pure, and over
/// HEIGHTS rather than positions.
enum PreviewLayout {
    /// Whether a place on the page is in front of the reader right now.
    ///
    /// Asked before the page is moved for a cursor that was armed from
    /// OUTSIDE it — the bar under an answer a run has just written — so
    /// that a one-line answer does not jerk the note under somebody who
    /// can already see where their cursor went (Sean, 2026-09-22: "make
    /// the cursor behavior after evaluating a cell elegant"). The source
    /// pane has always had this for nothing: `scrollRangeToVisible`
    /// moves by the least it can and not at all when the range is
    /// already on screen.
    ///
    /// A `margin` off each edge, because a bar a point inside the fold is
    /// on screen by arithmetic and not by eye.
    static func onScreen(_ y: CGFloat, scroll: CGFloat, height: CGFloat,
                         margin: CGFloat = 24) -> Bool {
        guard height > margin * 2 else { return false }
        return y >= scroll + margin && y <= scroll + height - margin
    }

    /// Where every block ends up, in the scroll content's own coordinates —
    /// what the cell brackets are drawn from.
    static func positions(rows: [(id: Int, height: CGFloat)], spacing: CGFloat,
                          top: CGFloat) -> [Int: (top: CGFloat, bottom: CGFloat)] {
        var out: [Int: (top: CGFloat, bottom: CGFloat)] = [:]
        var y = top
        for row in rows {
            out[row.id] = (y, y + row.height)
            y += row.height + spacing
        }
        return out
    }
}
