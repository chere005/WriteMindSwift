import CoreGraphics

/// WHERE A POINT ON ONE PANE IS ON THE OTHER.
///
/// Sean, 2026-10-03: "preserve the position of things as much as possible
/// between markdown and wysiwyg mode". The two panes lay the same cells out
/// at different heights — the rendered page puts `blockGap` (26 points)
/// between two cells where the markdown pane with its markers hidden puts
/// about 14, a code cell's two fence lines are 44 points of the one against
/// 14 of padding on the other, and the page starts ten points lower — so a
/// picture put beside a paragraph in one mode was a cell or more off it in
/// the other, and further off the further down the note it was (measured
/// on a twelve-cell note: 82 points by the last cell; a thirty-cell page of
/// prose, about 400).
///
/// What the two panes DO share is the cells, by the character offset each
/// one starts at, so this maps through them. Down the page it is piecewise
/// linear between the edges of the cells both panes have measured: inside
/// a cell by how far down that cell, in a seam by how far across the seam,
/// in the air above the first cell by how far down that air, and past the
/// last cell by the distance below it. Across the page it is linear
/// between the two panes' text columns. So it is monotone, it inverts
/// exactly (`inverse`), it is the identity when the two layouts agree, and
/// a cell one pane has not measured yet — or has folded away — is simply
/// not a knot: whatever is beside it goes with the cells round it.
///
/// Pure. The drawing layer, the PDF and the tests ask this one thing.
struct PaneMapping: Equatable {
    /// A pane's text column: where its words start and end across it.
    struct Column: Equatable {
        var left: CGFloat
        var right: CGFloat
    }

    /// One edge of a cell, as the pane a point comes FROM has it and as the
    /// pane it goes TO has it.
    struct Knot: Equatable {
        var from: CGFloat
        var to: CGFloat
    }

    /// The edges, strictly increasing on BOTH sides, starting at the top of
    /// the document, which is the same line in both panes.
    let knots: [Knot]
    let fromColumn: Column
    let toColumn: Column

    /// Nothing moves.
    static let identity = PaneMapping(knots: [Knot(from: 0, to: 0)],
                                      fromColumn: Column(left: 0, right: 1), toColumn: Column(left: 0, right: 1))

    private init(knots: [Knot], fromColumn: Column, toColumn: Column) {
        self.knots = knots
        self.fromColumn = fromColumn
        self.toColumn = toColumn
    }

    /// From one pane's cell boxes to the other's. A cell is a knot only
    /// when BOTH panes have it with some height — the source pane lays a
    /// folded cell out at none, and the rendered page leaves it out — and
    /// only while the edges keep climbing on both sides, so nothing handed
    /// in can fold the mapping back on itself.
    init(from: [CellSeams.Box], to: [CellSeams.Box], fromColumn: Column, toColumn: Column) {
        var theirs: [Int: (top: CGFloat, bottom: CGFloat)] = [:]
        for box in to where theirs[box.offset] == nil {
            theirs[box.offset] = (min(box.top, box.bottom), max(box.top, box.bottom))
        }
        var knots = [Knot(from: 0, to: 0)]
        for box in from.sorted(by: { $0.offset < $1.offset }) {
            guard let other = theirs[box.offset] else { continue }
            let top = min(box.top, box.bottom), bottom = max(box.top, box.bottom)
            guard bottom - top > 0.5, other.bottom - other.top > 0.5 else { continue }
            for knot in [Knot(from: top, to: other.top), Knot(from: bottom, to: other.bottom)] {
                guard let last = knots.last, knot.from > last.from, knot.to > last.to else { continue }
                knots.append(knot)
            }
        }
        self.init(knots: knots, fromColumn: fromColumn, toColumn: toColumn)
    }

    /// The other way: a point on the pane this maps TO, back to the one it
    /// maps from. Exact, because the knots climb on both sides.
    var inverse: PaneMapping {
        PaneMapping(knots: knots.map { Knot(from: $0.to, to: $0.from) },
                    fromColumn: toColumn, toColumn: fromColumn)
    }

    var isIdentity: Bool {
        fromColumn == toColumn && knots.allSatisfy { $0.from == $0.to }
    }

    /// Down the page.
    func y(_ value: CGFloat) -> CGFloat {
        guard let first = knots.first, let last = knots.last else { return value }
        // Above the document's top and below the last cell's bottom, a
        // point keeps its distance from the edge it is beyond.
        if value <= first.from { return first.to + (value - first.from) }
        if value >= last.from { return last.to + (value - last.from) }
        // The last knot at or above the point; there is always one after it.
        var low = 0, high = knots.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if knots[middle].from <= value { low = middle } else { high = middle }
        }
        let a = knots[low], b = knots[high]
        return a.to + (value - a.from) * (b.to - a.to) / (b.from - a.from)
    }

    /// Across it.
    func x(_ value: CGFloat) -> CGFloat {
        let wide = fromColumn.right - fromColumn.left
        let scale = wide > 1 ? (toColumn.right - toColumn.left) / wide : 1
        return toColumn.left + (value - fromColumn.left) * scale
    }

    func point(_ point: CGPoint) -> CGPoint { CGPoint(x: x(point.x), y: y(point.y)) }

    /// A pane's cells after an edit, before they have been measured again:
    /// every cell that starts after the edit started is further on (or
    /// back) by what it added (or took). Their boxes are where they were,
    /// which is where they still nearly are — a line more or less in the
    /// cell being typed in — and the cells keep matching the other pane's
    /// by offset while the typing goes on.
    static func shifted(_ cells: [CellSeams.Box], from old: String, to new: String) -> [CellSeams.Box] {
        let start = editStart(from: old, to: new, within: old.utf16.count)
        guard start < old.utf16.count || old.utf16.count != new.utf16.count else { return cells }
        let moved = new.utf16.count - old.utf16.count
        return cells.map { cell in
            cell.offset > start ? (top: cell.top, bottom: cell.bottom, offset: cell.offset + moved) : cell
        }
    }

    /// Where an edit that made `new` out of `old` starts: how far the two
    /// agree, looked for no further than `within`.
    static func editStart(from old: String, to new: String, within: Int) -> Int {
        zip(old.utf16.prefix(within), new.utf16).prefix { $0 == $1 }.count
    }
}

/// A place down a pane, said by the CELL it is in and how far through it —
/// which is how the top of the window crosses ⌘T, since a number of points
/// means something different on each side.
///
/// It used to be the cell alone: the page came back with that cell's top at
/// the fold, so a window showing the third line of a paragraph came back
/// two lines up, a long code cell up to its whole height up, and a round
/// trip settled on the cell's first line (Sean, 2026-09-19: "positions stay
/// the same in markdown and wysiwyg mode"; 2026-10-03: "preserve the
/// position of things as much as possible").
struct CellPlace: Equatable {
    /// The cell, by the character offset its block starts at.
    var cell: Int
    /// 0 at the cell's top and 1 at its bottom. Below 0 is the seam ABOVE
    /// it — −1 at that seam's top, which is the bottom of the cell before
    /// or the top of the page — so a window resting in the air between two
    /// cells comes back in that air, and not on the cell above it, whose
    /// bottom was nearer than its top.
    var fraction: Double

    /// The top of the page.
    static let top = CellPlace(cell: 0, fraction: -1)

    /// Where `y` is among a pane's cells: the first cell whose bottom is
    /// below it, and how far into that cell or the seam above it. Past the
    /// last cell it is that cell's bottom, which is as far as either pane
    /// can be scrolled with any agreement. Nil on a page with no cells.
    static func at(_ y: CGFloat, in boxes: [CellSeams.Box]) -> CellPlace? {
        let cells = laidOut(boxes)
        guard let last = cells.last else { return nil }
        var above: CGFloat = 0
        for cell in cells {
            if y < cell.bottom {
                if y >= cell.top {
                    return CellPlace(cell: cell.offset, fraction: Double((y - cell.top) / (cell.bottom - cell.top)))
                }
                let air = cell.top - above
                let into = air > 0 ? Double((cell.top - y) / air) : 0
                return CellPlace(cell: cell.offset, fraction: -min(into, 1))
            }
            above = cell.bottom
        }
        return CellPlace(cell: last.offset, fraction: 1)
    }

    /// The same place among another pane's cells. A cell that pane has no
    /// box for — not measured yet, folded away, gone in an edit — falls
    /// back to the top of the last cell before it, which is what the
    /// switch did before it knew about fractions. Nil with no cells.
    func y(in boxes: [CellSeams.Box]) -> CGFloat? {
        let cells = Self.laidOut(boxes)
        guard let first = cells.first else { return nil }
        guard let index = cells.firstIndex(where: { $0.offset == cell }) else {
            return (cells.last { $0.offset <= cell } ?? first).top
        }
        let here = cells[index]
        if fraction >= 0 {
            return here.top + CGFloat(min(fraction, 1)) * (here.bottom - here.top)
        }
        let above = index > 0 ? cells[index - 1].bottom : 0
        return here.top + CGFloat(max(fraction, -1)) * (here.top - above)
    }

    /// The same place after an edit to the note. Its cell is a character
    /// offset, and the panes say where the top of the window is only when
    /// they scroll — so an answer written above the fold, a section moved,
    /// a paste or another app's save left it naming a character of the
    /// cell BEFORE, and the next switch opened a cell up. An edit that
    /// starts before the cell moves it by what the edit added or took;
    /// one at or after its start leaves it where it is. Where the edit
    /// starts is where the two texts stop agreeing, which is only ever
    /// looked for as far as the cell.
    func shifted(from old: String, to new: String) -> CellPlace {
        guard cell > 0 else { return self }
        let agreed = PaneMapping.editStart(from: old, to: new, within: cell)
        guard agreed < cell else { return self }
        let moved = cell + new.utf16.count - old.utf16.count
        return CellPlace(cell: max(agreed, moved), fraction: fraction)
    }

    /// The boxes a place can be in: the right way up, with some height,
    /// down the page.
    private static func laidOut(_ boxes: [CellSeams.Box]) -> [(top: CGFloat, bottom: CGFloat, offset: Int)] {
        boxes.map { (top: min($0.top, $0.bottom), bottom: max($0.top, $0.bottom), offset: $0.offset) }
            .filter { $0.bottom - $0.top > 0.5 }
            .sorted { $0.top < $1.top }
    }
}
