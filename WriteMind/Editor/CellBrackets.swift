import SwiftUI

/// The notebook's cell brackets, drawn beside the rendered page — the same
/// furniture the markdown editor has in its gutter, so the notebook reads
/// the same on both sides (Sean, 2026-09-19: "notebook lines should be
/// visible in markdown and wysiwyg mode").
struct CellBrackets: View {
    struct Bracket: Equatable, Identifiable {
        var key: String
        var depth: Int
        var top: CGFloat
        var bottom: CGFloat
        var collapsed = false
        var selected = false
        /// And whether a real selection is what lights it, rather than the
        /// cell merely being open for typing. The gestures need the
        /// narrower one: a drag off the open cell's bracket is a drag off
        /// a cell nobody picked up, and it must select rather than move
        /// (2026-09-20).
        var held = false
        /// A heading's group: a double-click folds it.
        var foldable = false
        /// An evaluation cell and its answer, embraced by one bracket —
        /// not a cell and not a section. `!foldable` was read as "is a
        /// cell" in three places here, so the pair's own bracket joined
        /// the list a drag walks down and shadowed the two inside it.
        var group = false
        /// What a click selects, in the markdown.
        var range: NSRange

        /// A cell of the note, rather than furniture round some.
        var isCell: Bool { !foldable && !group }

        var id: String { key }
    }

    static let width: CGFloat = 22
    private static let step: CGFloat = 5
    private static let tick: CGFloat = 5
    /// How far a group's bracket reaches past the cells it holds, so an
    /// In/Out pair reads as embraced rather than as a doubled hairline.
    static let overhang: CGFloat = 3
    /// How many levels of nesting fit in the column, ticks and all.
    /// Anything deeper shares the last one rather than being drawn off
    /// the edge and not drawn at all.
    static let deepest = Int((width - 6 - tick) / step)
    /// A margin under the last bracket, so the strip still covers the gap
    /// a block added at the bottom will need before the page re-measures.
    static let tail: CGFloat = 120

    /// How tall the strip has to be to hold them all.
    static func height(of brackets: [Bracket]) -> CGFloat {
        (brackets.map(\.bottom).max() ?? 0) + tail
    }

    let brackets: [Bracket]
    var onSelect: ((NSRange) -> Void)?
    /// A drag down the column, a shift-click or a cmd-click: several cells
    /// at once (Sean, 2026-09-20: "fix selecting multiple cells by clicking
    /// and dragging, shift clicking, or cmd clicking").
    var onSelectCells: (([NSRange]) -> Void)?
    var onToggle: ((String) -> Void)?
    /// WHAT A CLICK ON THE BRACKET UNDER THE POINTER WOULD TAKE (Sean,
    /// 2026-09-22: "hovering over sections on the right side should
    /// faintly indicate what would be selected if clicked"). The cells,
    /// never the bracket's own range, and asked of the same
    /// `CellSelection.cells(of:in:)` the press asks — so the promise and
    /// the press cannot disagree.
    var onHoverCells: (([NSRange]) -> Void)?
    /// Dragged up or down: the cell changes places with its neighbour.
    var onMoveCell: ((NSRange, Bool) -> Void)?
    /// How far it has to go before it is a move and not a click.
    static let dragThreshold: CGFloat = 10
    /// ONE threshold, for settling which gesture this is and for the move
    /// itself. There was a three-point slop in front of it, and three
    /// points of drift between press and release is ordinary with a
    /// mouse: the press settled as a drag, the mouse-up never reached
    /// `click(at:)`, and so a click that wandered neither opened the cell
    /// nor folded the section it double-clicked (2026-09-20).
    static func isDrag(travelled: CGFloat) -> Bool { abs(travelled) >= dragThreshold }
    @State private var hovered: String?
    /// Where a shift-click reaches FROM: the last bracket clicked plainly.
    @State private var anchor: NSRange?
    /// What this press turned out to be, settled the first time it moved.
    @State private var pick: Pick?

    private enum Pick: Equatable {
        /// It began nowhere: the empty part of the column.
        case nothing
        /// Off a bracket that was already picked — the cell is being moved.
        case moving(NSRange)
        /// Off one that was not — the cells it passes are being taken.
        case picking(anchor: NSRange, cells: [NSRange])
    }

    /// The line a bracket is drawn on, from the right-hand edge.
    static func x(for depth: Int, in width: CGFloat) -> CGFloat {
        width - 6 - CGFloat(min(depth, deepest)) * step
    }

    /// Which bracket a point lands on: the NEAREST one, not the first.
    /// Nesting levels are five points apart, so a tolerance that reaches
    /// the next level over would always answer with whichever happened to
    /// be first in the list.
    static func bracket(at point: CGPoint, in brackets: [Bracket], width: CGFloat) -> Bracket? {
        brackets
            .filter { bracket in
                point.y >= bracket.top - 4 && point.y <= bracket.bottom + 4
                    && abs(point.x - x(for: bracket.depth, in: width)) <= 4
            }
            .min { abs(point.x - x(for: $0.depth, in: width)) < abs(point.x - x(for: $1.depth, in: width)) }
    }

    var body: some View {
        Canvas { context, size in
            for bracket in brackets {
                let line = Self.x(for: bracket.depth, in: size.width)
                let base: CGFloat = bracket.foldable || bracket.group ? 1.5 : 1.1
                let weight = bracket.selected ? base + 1.2 : (bracket.key == hovered ? base + 0.6 : base)
                let colour: Color = bracket.selected || bracket.key == hovered
                    ? .accentColor
                    : Color.secondary.opacity(0.45)

                // A pair's bracket stands proud of the two cells inside
                // it: its ends are theirs exactly, so drawn at the same
                // length it read as a second hairline rather than as a
                // group.
                let over = bracket.group ? Self.overhang : 0
                var path = Path()
                path.move(to: CGPoint(x: line - Self.tick, y: bracket.top - over))
                path.addLine(to: CGPoint(x: line, y: bracket.top - over))
                path.addLine(to: CGPoint(x: line, y: bracket.bottom + over))
                path.addLine(to: CGPoint(x: line - Self.tick, y: bracket.bottom + over))
                context.stroke(path, with: .color(colour),
                               style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))

                if bracket.collapsed {
                    let middle = (bracket.top + bracket.bottom) / 2
                    var mark = Path()
                    mark.move(to: CGPoint(x: line - 4, y: middle - 3.5))
                    mark.addLine(to: CGPoint(x: line, y: middle))
                    mark.addLine(to: CGPoint(x: line - 4, y: middle + 3.5))
                    mark.closeSubpath()
                    context.fill(mark, with: .color(colour))
                }
            }
        }
        .frame(width: Self.width)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                let over = Self.bracket(at: point, in: brackets, width: Self.width)
                if over?.key != hovered {
                    hovered = over?.key
                    onHoverCells?(over.map { CellSelection.cells(of: $0.range, in: cellRanges) } ?? [])
                }
                (over == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
            case .ended:
                hovered = nil
                onHoverCells?([])
            }
        }
        // One gesture, because a tap pair would make the single click wait
        // for the second — the same pause the camera's box had.
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in drag(value) }
                .onEnded { value in finish(value) }
        )
    }

    /// The pointer has moved with the button down. WHICH gesture this is
    /// was settled the first time it moved far enough to be a drag, and a
    /// drag that takes cells reports them as it goes — the brackets light
    /// one after another under the pointer, which is the whole of what a
    /// drag down a notebook's gutter looks like.
    private func drag(_ value: DragGesture.Value) {
        if pick == nil {
            guard Self.isDrag(travelled: value.location.y - value.startLocation.y) else { return }
            pick = began(at: value.startLocation)
        }
        guard case .picking(let anchor, let reported) = pick,
              let over = CellSelection.cell(at: value.location.y, in: cellSpans) else { return }
        let wanted = CellSelection.between(anchor, over, in: cellRanges)
        guard wanted != reported else { return }
        pick = .picking(anchor: anchor, cells: wanted)
        onSelectCells?(wanted)
    }

    /// A drag off a bracket that is NOT already picked selects everything
    /// it passes; off one that IS picked it moves the cell, as it always
    /// has. That is the only way both gestures fit on one column, and it
    /// is Mathematica's own rule.
    private func began(at start: CGPoint) -> Pick {
        guard let bracket = Self.bracket(at: start, in: brackets, width: Self.width) else { return .nothing }
        // HELD, not lit: the cell open for typing is drawn heavy too, and
        // a drag off it is a drag off a cell nobody picked up.
        if bracket.held { return .moving(bracket.range) }
        anchor = bracket.range
        onSelectCells?([bracket.range])
        return .picking(anchor: bracket.range, cells: [bracket.range])
    }

    private func finish(_ value: DragGesture.Value) {
        defer { pick = nil }
        if case .moving(let cell) = pick {
            let travelled = value.location.y - value.startLocation.y
            if Self.isDrag(travelled: travelled) { onMoveCell?(cell, travelled < 0) }
            return
        }
        // A drag that took cells has already said everything it has to say.
        guard pick == nil else { return }
        click(at: value.startLocation)
    }

    /// A press that never moved: shift reaches from the anchor to here, cmd
    /// puts this one in or takes it out, two clicks fold a section, and a
    /// plain one picks the cell up on its own.
    private func click(at point: CGPoint) {
        guard let bracket = Self.bracket(at: point, in: brackets, width: Self.width) else { return }
        // A section's bracket stands for the cells under it, never for
        // itself — there is no text view on this side, so its own range
        // opened the whole section as ONE block to type in and held
        // nothing (Sean, 2026-09-21: "an outer selection isn't always
        // grabbing inner elements").
        let held = CellSelection.cells(of: bracket.range, in: cellRanges)
        let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if modifiers.contains(.shift) {
            let from = reachFrom ?? picked.first ?? held.first ?? bracket.range
            onSelectCells?(CellSelection.between(from, held.last ?? bracket.range, in: cellRanges))
            return
        }
        if modifiers.contains(.command) {
            anchor = held.first
            onSelectCells?(held.reduce(picked) { CellSelection.toggling($1, in: $0) })
            return
        }
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2, bracket.foldable {
            onToggle?(bracket.key)
            return
        }
        anchor = held.first
        if held.count == 1, NSEqualRanges(held[0], bracket.range) {
            onSelect?(bracket.range)
        } else {
            onSelectCells?(held)
        }
    }

    /// The cells' brackets, down the page. A section's is not one of them:
    /// a drag reaches cells, and the section round them lights up by itself
    /// once they are all in.
    private var cellSpans: [CellSelection.Span] { Self.cellSpans(of: brackets) }

    /// The same reading for whatever else on the page walks the cells — a
    /// drag from a bar (`MarkdownPreview.seamDrag`), which asked its own
    /// way and counted an In/Out pair's bracket as one of them.
    static func cellSpans(of brackets: [Bracket]) -> [CellSelection.Span] {
        brackets.filter(\.isCell)
            .sorted { $0.top < $1.top }
            .map { CellSelection.Span(top: $0.top, bottom: $0.bottom, range: $0.range) }
    }

    private var cellRanges: [NSRange] {
        brackets.filter(\.isCell).map(\.range).sorted { $0.location < $1.location }
    }

    /// What is picked right now, as the brackets themselves say: this view
    /// is drawn FROM the page's selection and keeps no second copy of it.
    private var picked: [NSRange] {
        brackets.filter { $0.isCell && $0.held }
            .map(\.range)
            .sorted { $0.location < $1.location }
    }

    /// Where a shift-click reaches from, if that range still names a
    /// bracket. `@State` outlives every edit and every note shown in this
    /// pane, and `CellSelection.between` resolves a stale anchor by raw
    /// offset overlap rather than failing.
    private var reachFrom: NSRange? {
        CellSelection.anchor(anchor, in: brackets.map(\.range))
    }
}
