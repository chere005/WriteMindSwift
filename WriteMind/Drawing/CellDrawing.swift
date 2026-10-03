import CoreGraphics
import Foundation

/// WHAT A DRAWING CELL TAKES, AND WHEN — CELL DRAWING MODE.
///
/// A drawing cell is STATIC: it shows its picture and nothing draws into it —
/// not the pen, not the cursor, not the tablet's nib — whatever the pen mode
/// or the tablet is doing, and it is selected, moved, deleted, held with
/// others, inserted around and handed pictures the way every cell is. CLICKING
/// INTO IT — a mouse click, or the pen's tip tapping it — ENTERS CELL DRAWING
/// MODE for that cell (Sean, 2026-10-03: "drawing cells are static unless you
/// enter click into it, which forces you into a drawing mode where you can
/// only draw in that cell (mouse or wacom into cell (if wacom is in write on
/// notebook mode)) otherwise you can select and insert like normal or page
/// capture by selection from a document camera"). In that mode drawing — a
/// mouse drag, or the Wacom pen when its target is the notebook — goes ONLY
/// into that cell, clipped to it, onto its own undo and redo, and nothing else
/// on the page reacts to the pen. It ends on Esc, on a press outside the cell,
/// on another note, pane or mode, on another tool, and from the Done control
/// on the cell; it does not end by itself between strokes (`AppState.cellDrawing`
/// is the state, and the one place that says so).
///
/// Everything here is pure and is what the canvas, the store and the tablet's
/// notebook ask, so what a press does about a cell is decided in one place.
enum CellDrawing {
    /// A PRESS UNDER THIS MANY POINTS IS A CLICK: it enters a cell, leaves no
    /// dot and no empty step behind it, and puts the caret in the cell; one
    /// that moves further is a drag, which is whatever the mode makes of one
    /// (the pen's stroke floats over the cell, the cursor's does nothing).
    static let clickTravel: CGFloat = 3

    static func isClick(travelled: CGFloat) -> Bool { travelled < clickTravel }

    /// The cells' paper the layer takes a press on, in document points: every
    /// writable cell's — to see whether the press is a click into it (a
    /// stroke never goes in on a press of its own) — and no read-only one's.
    /// Everything else is the notebook's: the words, the bars between cells,
    /// the brackets.
    static func paperTaken(frames: [CellFrame]) -> [CGRect] {
        frames.filter(\.writable).map(\.rect)
    }

    /// WHAT A PRESS IS ABOUT A DRAWING CELL, by where it began.
    enum Contact: Equatable {
        /// Not about a cell: the press is whatever the mode makes of it.
        case none
        /// Inside the ENTERED cell: the press is the cell's — a stroke, or
        /// (⌘) its marquee — whatever else is under the point.
        case drawing(UUID)
        /// On a static, writable cell: a click here enters it. Pressed and
        /// let go under `clickTravel`; moved, it is an ordinary press.
        case click(UUID)
        /// Outside the entered cell: the way out. The canvas leaves the mode
        /// and asks again with nothing entered, so a cell clicked next is
        /// entered in its turn.
        case leaving
    }

    /// `coveredByObject`: a floating object is under the point, which takes
    /// the click. `tool`: a shape, a mark or the arrow tool is armed, which
    /// does its own thing where it is pressed (a tick goes down ON the cell,
    /// floating). `command`: ⌘ is the selector and picks, it does not enter.
    static func contact(at point: CGPoint, entered: UUID?, frames: [CellFrame], coveredByObject: Bool,
                        tool: Bool, command: Bool) -> Contact {
        if let entered {
            let inside = frames.contains { $0.id == entered && $0.writable && $0.rect.contains(point) }
            return inside ? .drawing(entered) : .leaving
        }
        guard !coveredByObject, !tool, !command,
              let frame = frames.first(where: { $0.writable && $0.rect.contains(point) })
        else { return .none }
        return .click(frame.id)
    }

    /// CLIPPED TO THE CELL: a point in the cell's own fractions — of its
    /// width on both axes, y running 0…the cell's height over its width —
    /// held inside it on every side, so a stroke dragged out of a cell runs
    /// along its edge and leaves nothing outside it.
    static func hold(_ fraction: CGPoint, in frame: CellFrame) -> CGPoint {
        let aspect = frame.width > 0 && frame.scale > 0 ? frame.rect.height / frame.scale / frame.width : 0
        return CGPoint(x: min(max(fraction.x, 0), 1), y: min(max(fraction.y, 0), aspect))
    }

    /// The same in the page's points: a point held inside the cell's rect.
    static func hold(document point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
    }

    /// Whether the cell can be in the mode: it has a frame on the pane that is
    /// up, and may be drawn in. Folded away, read-only or out of the note, it
    /// cannot, and the mode ends with it.
    static func enterable(_ id: UUID, in frames: [CellFrame]) -> Bool {
        frames.contains { $0.id == id && $0.writable }
    }
}
