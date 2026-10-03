import CoreGraphics
import Foundation

/// The spaces between the cells: where the horizontal cursor lives and
/// where a new cell is born.
///
/// Sean, 2026-09-20: "the cursor should be horizontal any space between the
/// two cells… when clicking in between, the horizontal line appears and that
/// is where the cursor is.. typing from here would insert a new cell below
/// that line". ANY space between them — with N cells the page is N + 1
/// seams: one from the top of the page down to the first cell, one between
/// each pair, and one from the last cell to the bottom. What is not a seam
/// is a cell, and there is nothing else on the page.
///
/// That is what replaces the three-point strip round the middle of a gap
/// (`CellInsertions.Gap`) the pointer used to flip in and out of across one
/// space (Sean, 2026-09-20: "cursor is super buggy").
///
/// Pure geometry, so the two panes cannot drift apart: the markdown pane
/// measures its cells off the layout manager and the rendered page off
/// `PreviewLayout.positions`, and neither of those is in this file. Both
/// hand in boxes and get back the same seams.
enum CellSeams {
    struct Seam: Equatable {
        /// Document points, the coordinates the cells were handed in.
        var top: CGFloat
        var bottom: CGFloat
        /// The character offset a new cell is opened at: the next cell's
        /// range.location, or the note's length under the last cell.
        var offset: Int
        /// Where the bar that IS the cursor is drawn — which is NOT the
        /// middle of the seam, because two of the seams on every page are
        /// as tall as the empty page round the note (Sean, 2026-09-20:
        /// "when i select somewhere below the cell, the bar should go
        /// immediately after the last cell, not the random spot below
        /// it's currently at"). The hit area is the whole seam and the
        /// bar is against the cell it belongs to; worked out once, here,
        /// so the two panes draw it in the same place.
        var line: CGFloat
        func contains(_ y: CGFloat) -> Bool { y >= top && y <= bottom }
    }

    /// A cell as the panes measure it: where its block starts and ends down
    /// the page, and the character offset the block begins at.
    typealias Box = (top: CGFloat, bottom: CGFloat, offset: Int)

    /// The seams of a page.
    ///
    /// `cells` are the blocks' boxes. They are sorted here rather than
    /// trusted, and a box handed in upside down is turned the right way up,
    /// because the two panes measure them in quite different ways and a
    /// seam folded inside out would be a hole in the page. `pageTop` and
    /// `pageBottom` are the ends of the scrollable page; `noteLength` is
    /// what the seam under the last cell opens at.
    ///
    /// A seam thinner than `minimum` is widened to it about its middle: the
    /// strip has to be hittable, so the neighbouring cells' edges give way.
    /// At the two ends of the page it is the cell that gives way alone and
    /// the page's edge that holds, because the first seam starts at the top
    /// of the page and the last runs to the bottom of it whatever the note
    /// does in between.
    ///
    /// `firstCellTop` is where a cell WOULD land on a page that has none —
    /// the pane's own top inset, which this file cannot know and the two
    /// panes do not agree on (the rendered page stacks from
    /// `topInset + gapHeight`, the source pane from its text container's
    /// inset). It is the only thing an empty page can put its bar against,
    /// and without it the bar was drawn hard under the divider while the
    /// first character appeared an inset below it.
    static func seams(cells: [Box], pageTop: CGFloat, pageBottom: CGFloat, noteLength: Int,
                      firstCellTop: CGFloat? = nil,
                      minimum: CGFloat = MarkdownPreview.gapHeight) -> [Seam] {
        // Spelled out rather than chained: one map-and-sort over labelled
        // tuples put the type checker past its budget and the file would
        // not compile at all.
        var boxes: [Box] = cells.map { cell in
            Box(top: min(cell.top, cell.bottom), bottom: max(cell.top, cell.bottom), offset: cell.offset)
        }
        boxes.sort { left, right in
            left.top == right.top ? left.bottom < right.bottom : left.top < right.top
        }
        // The page is at least as tall as the note laid out on it: a cell
        // past the end of what the caller called the page would otherwise
        // turn the tail seam inside out.
        let head = min(pageTop, boxes.first?.top ?? pageTop)
        let foot = max(pageBottom, boxes.last?.bottom ?? pageBottom, head)

        guard !boxes.isEmpty else {
            // Nothing written yet: the whole page is one seam, and what is
            // typed in it goes at the end of the note — offset 0 when the
            // note is empty, which is the usual way to meet this.
            // The bar goes where the cell it opens will land, half a gap
            // above it — the head seam's own rule, with the caller's inset
            // standing in for the cell that is not there yet.
            let landing = firstCellTop ?? (head + minimum)
            return [Seam(top: head, bottom: foot, offset: noteLength,
                         line: max(head, landing - minimum / 2))]
        }

        var seams: [Seam] = []
        // How far down the page the cells have reached. Cells that overlap
        // (never, but be safe) leave a seam of no height on the edge they
        // share rather than one that runs backwards.
        var reached = head
        for box in boxes {
            seams.append(fitted(top: reached, bottom: max(reached, box.top), offset: box.offset,
                                minimum: minimum, holding: seams.isEmpty ? .top : .middle))
            reached = max(reached, box.bottom)
        }
        seams.append(fitted(top: reached, bottom: max(reached, foot), offset: noteLength,
                            minimum: minimum, holding: .bottom))
        return seams
    }

    /// The seam a point is in. Containment, not "the nearest one within
    /// reach": every point between two cells is in the seam there, and a
    /// point on a cell is in no seam at all.
    static func seam(at y: CGFloat, in seams: [Seam]) -> Seam? {
        // Widening can make two seams overlap when the cell between them is
        // shorter than the minimum. The upper one answers; either is a fair
        // reading of a point that is inside both.
        seams.first { $0.contains(y) }
    }

    /// The seam whose bar is nearest a height on the page — where a cell
    /// goes when nothing on the page says where: ⌘0 on the rendered page
    /// with nothing open puts its drawing in the middle of what is on
    /// screen, never above the note's first cell for want of a caret. The
    /// upper of two as near.
    static func nearest(toLine y: CGFloat, in seams: [Seam]) -> Seam? {
        seams.min { abs($0.line - y) < abs($1.line - y) }
    }

    /// The seam an empty selection is sitting IN, as the offset a cell
    /// would be opened at — nil when the caret is in a cell and the
    /// ordinary caret belongs there.
    ///
    /// Arming is what the caret's POSITION means, not a mode a click turns
    /// on (Sean, 2026-09-20: "the mouse cursor and text cursor should both
    /// become horizontal between cells"). So ↓ out of the bottom of a cell
    /// lands on the bar, ↓ again enters the next cell, and ⌃D leaves the
    /// bar between the two halves it just made. Without this, arrowing onto
    /// the blank line between two cells and typing merged them: the
    /// character went in on a line of its own and the parser joined all
    /// three into one paragraph.
    ///
    /// `current` is what is armed already, and it stands while the caret is
    /// still where the arming put it. That covers the two places the offset
    /// alone cannot speak for: offset 0 is both the seam above the first
    /// cell and the first character of it, and the note's length is both
    /// the tail seam and the end of the last cell. It also covers an
    /// ordinary click in a seam, which leaves the caret at the first
    /// character of the cell BELOW.
    static func arm(caret: NSRange, in markdown: String, current: Int?) -> Int? {
        // A selection of anything at all is not a caret in a seam — ⌘A and
        // a bracket click both used to leave the bar armed behind them,
        // and the next character typed threw the selection away.
        guard caret.length == 0 else { return nil }
        let offset = caret.location
        if let current, current == offset { return current }
        let ns = markdown as NSString
        // THE EMPTY LINE UNDER THE LAST CELL. A note that ends in a newline
        // has a line after it with nothing on it, and a caret there is
        // under every cell — the tail seam, which no reading of the offset
        // can mistake for the end of the last cell, because the newline is
        // between them. Return at the end of the last cell and ↓ off it
        // both leave the caret there, and a character typed on it went
        // into the last cell as a second line (`- a` and `x` under it,
        // "Only cell x" on the page) where the rendered page makes a cell.
        // Not when the last cell reaches the very end: a fence with no
        // closing line runs to the end of the note, and a caret there is
        // in its code.
        if offset == ns.length, offset > 0, ns.character(at: offset - 1) == 10 {
            guard let last = MarkdownParser.positioned(from: markdown).last else { return offset }
            return NSMaxRange(last.range) < offset ? offset : nil
        }
        guard offset > 0, offset < ns.length else { return nil }
        // Cheap first. This runs on every caret move, which means on every
        // keystroke, and parsing the whole note for each of them would sit
        // on the typing. Only a caret on a blank line can be in a seam.
        let line = ns.lineRange(for: NSRange(location: offset, length: 0))
        guard offset < NSMaxRange(line),
              ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        // And only the first and last blank line of a run separate two
        // cells; the ones between them are a `.blank` cell — the note's own
        // content, where an ordinary caret belongs.
        guard MarkdownSourceStyle.structuralLines(in: markdown)
            .contains(where: { NSLocationInRange(offset, $0) }) else { return nil }
        let blocks = MarkdownParser.positioned(from: markdown)
        // And a blank line INSIDE a cell is not a space between two.
        // `structuralLines` reads the note line by line and a fenced block
        // is the one cell that can hold an empty line of its own, so an
        // empty code cell — the very thing the + now opens — armed a bar
        // over the caret sitting between its fences.
        guard !blocks.contains(where: { $0.range.location < offset && offset < NSMaxRange($0.range) })
        else { return nil }
        return blocks.first { $0.range.location >= offset }?.range.location ?? ns.length
    }

    /// What a command arriving at an armed bar means in the SOURCE pane —
    /// the same five answers the rendered page reads its keys into
    /// (`MarkdownPreview.seamKey`), so one key does one thing at a bar
    /// whichever pane it is pressed in.
    ///
    /// Return opens an empty cell, ↑ and ↓ walk into the cell beside the
    /// bar, Escape takes the bar back — and everything else takes the bar
    /// back too and is `.pass`: whoever else wants it can have it, which
    /// in this pane is NSTextView, and it may have it only when the key
    /// cannot edit (`handsOn`). The promise of the bar is that clicking
    /// about the page and pressing keys at it leaves the note byte for
    /// byte as it was (docs/FEATURES.md). The source pane used to put the
    /// bar out and then run every command anyway, from the caret the bar
    /// had parked at the start of the cell below: ⌫ there joined that cell
    /// to the one above, ⌦ took its first letter, Tab indented it. The
    /// rendered page has never run them — a seam has no text to run them
    /// in — and that is the answer both give now.
    static func command(_ name: String) -> MarkdownPreview.SeamKey {
        switch name {
        // ⌃↩ and ⌥↩ are Return as well: on the rendered page they arrive
        // as the same "\r".
        case "insertNewline:", "insertLineBreak:", "insertNewlineIgnoringFieldEditor:": return .empty
        case "moveUp:": return .step(up: true)
        case "moveDown:": return .step(up: false)
        case "cancelOperation:": return .disarm
        default: return .pass
        }
    }

    /// Whether a `.pass` key goes on to NSTextView once the bar is out —
    /// true only for one that moves the caret, extends a selection or
    /// scrolls, because NSTextView runs it from the caret the bar parked
    /// IN the cell below, and an edit there is the very thing the bar
    /// promises never to make.
    ///
    /// The first cut ran none of them, so they went with the edits: every
    /// ↓ through a note arms a bar on each separator, and from any of
    /// them ⇧↓ could not start a selection, Page Down did not scroll and
    /// ⌘↓ never reached the end (review, 2026-10-02). On the rendered page
    /// the same keys are `.pass` too, and its scroll view takes the page
    /// keys. ← and → are the exception, `moveBackward:` and `moveForward:`
    /// (⌃B, ⌃F) being the same keys by their Emacs names: they put the bar
    /// away and do nothing else, as on the rendered page, and whether they
    /// should walk out of it the way ↑ and ↓ do is Sean's to say.
    static func handsOn(_ name: String) -> Bool {
        if ["moveLeft:", "moveRight:", "moveBackward:", "moveForward:"].contains(name) { return false }
        return ["move", "page", "scroll", "select"].contains { name.hasPrefix($0) }
            || name == "centerSelectionInVisibleArea:"
    }

    /// Whether the END of the note is inside its last cell: a fence whose
    /// closing line has not been typed runs to the end of the note
    /// (`Insertion.isClosed`), so a caret there is in its code and there
    /// is no bar under it. A cell opened there went in as two more lines
    /// of the same code.
    static func endsInCode(_ markdown: String) -> Bool {
        guard let last = MarkdownParser.positioned(from: markdown).last, case .code = last.block else { return false }
        return !Insertion.isClosed(last.range, markdown as NSString)
    }

    /// Where ↑ or ↓ at a bar puts the caret: at the END of the cell above
    /// it, or the START of the cell below — the rendered page's `walk`,
    /// which opens those same cells with the caret at those same ends.
    /// Nil at the two ends of the note, where there is no cell that way and
    /// the bar stays where it is.
    ///
    /// Read off the bar's OFFSET, never off the caret: a click parks the
    /// caret at the first character of the cell below, so ↓ from there
    /// went to that cell's second line — on a one-line cell, the bar under
    /// it, skipping the cell altogether — and ↑ went to the blank line the
    /// bar stands for and armed the same bar again, which looked like the
    /// key doing nothing.
    static func step(from offset: Int, up: Bool, in markdown: String) -> Int? {
        let cells = MarkdownParser.positioned(from: markdown).map(\.range)
        if up { return cells.last { $0.location < offset }.map(NSMaxRange) }
        return cells.first { $0.location >= offset }?.location
    }

    /// A stretch of the page as the POINTER reads it: a seam, where the
    /// I-beam lies on its side, or everything else, where it stands up.
    struct Band: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var horizontal: Bool
    }

    /// The page cut into those stretches, top to bottom, touching and
    /// never overlapping.
    ///
    /// For the markdown pane's text view, which hands them to AppKit as
    /// its cursor rects. It cannot hand over "the I-beam everywhere
    /// except the seams" in one rect, and its own I-beam over the whole
    /// of itself with the seam layer's rects laid on top is two rects
    /// over one point — AppKit picks between them, and it picked the
    /// I-beam (Sean, 2026-09-20: "the mouse cursor should reliably be
    /// horizontal between the cells"). Cut this way, nothing the text
    /// view says claims a seam in the first place.
    static func bands(seams: [Seam], pageTop: CGFloat, pageBottom: CGFloat) -> [Band] {
        guard pageBottom > pageTop else { return [] }
        var out: [Band] = []
        // WHOLE PIXELS. A cursor rect can only be drawn on pixel edges,
        // and the point test the events use reads the same seam as a
        // float — so on a boundary that fell mid-pixel the two answered
        // differently and a pointer crawling across it chattered between
        // the two cursors (Sean, 2026-09-21: "it's while the mouse is
        // moving slowly"). Both now read `pixels`.
        let seams = seams.map { seam -> Seam in
            var seam = seam
            let edges = pixels(seam)
            seam.top = edges.top
            seam.bottom = edges.bottom
            return seam
        }
        // How far down the page the bands have reached. Widening can
        // leave two seams overlapping, and a band that ran backwards is
        // a cursor rect AppKit throws away — with it the I-beam is back.
        var reached = pageTop
        for seam in seams.sorted(by: { $0.top < $1.top }) {
            let top = min(max(seam.top, reached), pageBottom)
            let bottom = min(max(seam.bottom, top), pageBottom)
            if top > reached { out.append(Band(top: reached, bottom: top, horizontal: false)) }
            if bottom > top { out.append(Band(top: top, bottom: bottom, horizontal: true)) }
            reached = max(reached, bottom)
        }
        if reached < pageBottom { out.append(Band(top: reached, bottom: pageBottom, horizontal: false)) }
        return out
    }

    /// A seam's edges snapped OUT to whole pixels — the only edges a
    /// cursor rect can have, and therefore the only edges the point test
    /// may use if the two are to agree.
    static func pixels(_ seam: Seam) -> (top: CGFloat, bottom: CGFloat) {
        (seam.top.rounded(.down), seam.bottom.rounded(.up))
    }

    /// How far outside a seam the pointer has to get before the cursor
    /// stops being the horizontal one. Enough to cover a pixel of
    /// rounding either way, and small enough that nobody sees it.
    static let pointerSlack: CGFloat = 2

    /// Which seam the POINTER should be shown as being in — not the same
    /// question as which seam a CLICK lands in, which is `seam(at:)` and
    /// is exact.
    ///
    /// It is sticky: once the pointer is being shown as in a seam it
    /// stays in that seam until it is clearly out of it. Two mechanisms
    /// set this cursor (a rect AppKit owns and a point test the events
    /// use), they meet on the seam's own edge, and a pointer moving
    /// slowly across that edge made each of them answer in turn — which
    /// is the flicker. Nothing else needed to change: neither answer was
    /// wrong, they were just not the same answer at the same place.
    ///
    /// `showing` is the offset of the seam the pointer is being shown in.
    static func pointerSeam(at y: CGFloat, in seams: [Seam], showing: Int?,
                            slack: CGFloat = pointerSlack) -> Seam? {
        if let showing, let held = seams.first(where: { $0.offset == showing }) {
            let edges = pixels(held)
            if y >= edges.top - slack, y <= edges.bottom + slack { return held }
        }
        return seams.first { seam in
            let edges = pixels(seam)
            return y >= edges.top && y <= edges.bottom
        }
    }

    // MARK: - The + at the end of the bar

    /// How wide the + is drawn: a ten-point dot with a cross cut in it.
    static let plusSize: CGFloat = 10
    /// And how much slack there is round it. Sean, 2026-09-20: "it should
    /// be a pointer over the + button" — a ten-point dot on an
    /// eight-point bar is not a target anybody hits exactly, so the
    /// pointer and the click both read four points more than is drawn.
    static let plusGrip: CGFloat = 4

    /// The dot itself, on the seam's own line.
    ///
    /// `leading` is the only thing the two panes do not share: the
    /// markdown pane draws its + outside the text container's inset, the
    /// rendered page inside its own margin. Everything else about it —
    /// how big it is, that it is centred on `line`, how much slack it
    /// answers for — is one answer here beside the line it sits on,
    /// because a + measured twice is a + the two panes can disagree
    /// about.
    static func plus(onTheLineAt line: CGFloat, leading: CGFloat) -> CGRect {
        CGRect(x: leading, y: line - plusSize / 2, width: plusSize, height: plusSize)
    }

    /// The patch of page the + answers for: the dot with its slack round
    /// it, clipped to the seam it is drawn on.
    ///
    /// Clipped because the CLICK already is — the seam layer takes no
    /// mouse down outside a seam — so a pointer that turned into a hand
    /// five points up into the cell above would be promising a press
    /// that never arrives.
    ///
    /// `grip` is nought for a pane whose + is a real button. The slack
    /// is only ever honest where the same rect is read for the press:
    /// the markdown pane measures the click against this, the rendered
    /// page has a SwiftUI `Button` at its margin and this is nothing but
    /// the cursor, and four points of hand outside the button is the
    /// broken promise the clipping exists to stop, sideways.
    static func plusTarget(in seam: Seam, leading: CGFloat, grip: CGFloat = plusGrip) -> CGRect {
        let target = plus(onTheLineAt: seam.line, leading: leading)
        let top = max(target.minY - grip, seam.top)
        let bottom = min(target.maxY + grip, seam.bottom)
        return CGRect(x: target.minX - grip, y: top,
                      width: target.width + grip * 2, height: max(0, bottom - top))
    }

    /// Whether a point is on the +. Inclusive on all four edges, the way
    /// `Seam.contains` is: the bottom edge of a seam is in the seam, and
    /// the + drawn across it has to be pressable at the same point.
    static func onPlus(_ point: CGPoint, of seam: Seam, leading: CGFloat) -> Bool {
        let target = plusTarget(in: seam, leading: leading)
        guard target.height > 0 else { return false }
        return point.x >= target.minX && point.x <= target.maxX
            && point.y >= target.minY && point.y <= target.maxY
    }

    // MARK: - Holding the pointer still

    /// Whether a fresh measurement is really a different set of seams.
    ///
    /// Both panes re-measure on every keystroke, every caret move, every
    /// restyle and every scroll, off floats that come out of the text
    /// layout. Treating a difference of a hundredth of a point as a move
    /// tore the whole cursor-rect set down and built it again, and
    /// between the two there is no rect of ours under the pointer — the
    /// text view's upright I-beam is what is left (Sean, 2026-09-20: "it
    /// does flicker sometimes back to a cursor"). A seam has moved when
    /// the eye could see it move; below that the old seams stand and
    /// nothing is torn down at all.
    static func moved(_ seams: [Seam], from old: [Seam], tolerance: CGFloat = 0.5) -> Bool {
        guard seams.count == old.count else { return true }
        return zip(seams, old).contains { fresh, was in
            fresh.offset != was.offset
                || abs(fresh.top - was.top) > tolerance
                || abs(fresh.bottom - was.bottom) > tolerance
                || abs(fresh.line - was.line) > tolerance
        }
    }

    /// What is left of a rect with a hole taken out of it: up to four
    /// pieces, touching and never overlapping.
    ///
    /// Two cursor rects over one point is AppKit's choice to make and it
    /// does not make ours (AGENTS.md: "Being ABOVE the text view does not
    /// win the cursor either"), so the +'s rect is not laid ON the seam's
    /// — the seam's is cut round it.
    static func cut(_ rect: CGRect, around hole: CGRect) -> [CGRect] {
        let hole = hole.intersection(rect)
        guard !hole.isNull, !hole.isEmpty else { return rect.isEmpty ? [] : [rect] }
        var out: [CGRect] = []
        if hole.minY > rect.minY {
            out.append(CGRect(x: rect.minX, y: rect.minY,
                              width: rect.width, height: hole.minY - rect.minY))
        }
        if hole.maxY < rect.maxY {
            out.append(CGRect(x: rect.minX, y: hole.maxY,
                              width: rect.width, height: rect.maxY - hole.maxY))
        }
        if hole.minX > rect.minX {
            out.append(CGRect(x: rect.minX, y: hole.minY,
                              width: hole.minX - rect.minX, height: hole.height))
        }
        if hole.maxX < rect.maxX {
            out.append(CGRect(x: hole.maxX, y: hole.minY,
                              width: rect.maxX - hole.maxX, height: hole.height))
        }
        return out
    }

    /// Which edge of a seam stays put when it is too thin to be hit.
    private enum Edge { case top, middle, bottom }

    private static func fitted(top: CGFloat, bottom: CGFloat, offset: Int,
                               minimum: CGFloat, holding edge: Edge) -> Seam {
        // Where the bar goes, before any widening: half a gap under the
        // cell above it, or — for the seam at the top of the page, which
        // has no cell above it — half a gap above the cell below. On the
        // eight points between two ordinary cells the two readings meet
        // in the middle, which is where the bar has always been drawn;
        // on the tall seams at the two ends of the page they are the
        // difference between a bar against the note and a bar adrift in
        // the empty page.
        let line: CGFloat
        switch edge {
        // Between two cells the bar is EQUALLY spaced between them, in
        // the middle of the space it belongs to (Sean, 2026-09-21: "bar
        // spaced equally between cells"). On an eight-point seam that is
        // where half a gap under the cell above already put it; on a
        // wider one — the markdown pane's seams carry a blank line's own
        // height as well as the gap — it is not, and the bar sat against
        // the cell above with a visible gap under it.
        case .middle: line = (top + bottom) / 2
        // The two ENDS of the page are not spaces between two cells: they
        // are the whole of the empty page above the first cell and below
        // the last, and a bar in the middle of one of those is adrift
        // (Sean, 2026-09-20: "the bar should go immediately after the
        // last cell"). Each hugs the cell it belongs to.
        case .top: line = bottom - minimum / 2
        case .bottom: line = top + minimum / 2
        }
        guard bottom - top < minimum else {
            return Seam(top: top, bottom: bottom, offset: offset, line: line)
        }
        // Too thin to hit: the seam is widened and the bar goes back to
        // the middle of it, because that is where the eye already put it
        // — between the two cells that are nearly touching.
        switch edge {
        case .top: return Seam(top: top, bottom: top + minimum, offset: offset, line: top + minimum / 2)
        case .bottom: return Seam(top: bottom - minimum, bottom: bottom, offset: offset, line: bottom - minimum / 2)
        case .middle:
            let middle = (top + bottom) / 2
            return Seam(top: middle - minimum / 2, bottom: middle + minimum / 2, offset: offset, line: middle)
        }
    }
}
