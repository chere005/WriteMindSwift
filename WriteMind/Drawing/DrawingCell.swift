import CoreGraphics
import Foundation

/// What a drawing cell holds: the drawing layer's own objects, measured in
/// the cell rather than on the pane.
///
/// EVERY FRACTION IS A FRACTION OF `width`, ON BOTH AXES: x runs 0…1 and y
/// 0…`aspect`. The floating layer's y is a fraction of the pane's height,
/// which would stretch the ink whenever the cell grew; here growing the cell
/// moves no point, and nothing is ever stretched. Geometry is asked at
/// `size` — (W, W) — so the objects are the very `CanvasItem`s the layer
/// draws, picked, moved and outlined by the code that already does it.
///
/// `width` (W) is the column the cell was first drawn in, in points. A
/// narrower column shows the cell smaller, whole; a wider one never shows
/// it bigger than it was drawn.
struct DrawingCell: Equatable {
    /// What the payload's `version` says this build writes, and the only
    /// one it will write over (`DrawingCellFile`).
    static let version = 1

    var width: Double
    /// Height ÷ width.
    var aspect: Double
    var drawing: Drawing

    var height: Double { width * aspect }
    /// What every geometry question about the objects is asked at.
    var size: CGSize { CGSize(width: width, height: width) }

    /// A cell with nothing in it yet, `DrawingCells.emptyHeight` tall.
    static func empty(width: Double) -> DrawingCell {
        let width = max(width, 1)
        return DrawingCell(width: width, aspect: DrawingCells.emptyHeight / width, drawing: Drawing())
    }

    /// Room to go on drawing: content within a line of the bottom gets four
    /// lines of paper under it, so ink can never be dropped off the bottom
    /// of a cell. NEVER SHRINKS — a cell made taller by hand stays so.
    func fitted(lineHeight: Double) -> DrawingCell {
        guard let bottom = contentBottom, bottom > height - lineHeight else { return self }
        return with(height: bottom + 4 * lineHeight)
    }

    /// The grip, dragged to `toHeight`: never under the content and
    /// `DrawingCells.pad` of air, and never under two lines — a cell with
    /// no height is a cell nothing can hold.
    func resized(toHeight wanted: Double, lineHeight: Double) -> DrawingCell {
        with(height: max(wanted, (contentBottom ?? 0) + DrawingCells.pad, 2 * lineHeight))
    }

    /// OBJECTS MOVED PAST THE CELL'S SIDES OR ITS TOP, SHIFTED BACK IN. A
    /// cell grows downwards to keep its ink (`fitted`) and never up or out,
    /// so a thing dragged off its left edge would be cut off by the cell
    /// round it. Whole groups go as one, by the box of all of them, so the
    /// letters of a word stay together; one wider than the cell keeps its
    /// left edge. The points of a stroke are held inside as they are drawn
    /// (`DrawingCanvas.normalise`); this is for what is MOVED there.
    func keptIn() -> DrawingCell {
        let size = self.size
        var boxes: [UUID: CGRect] = [:]
        for item in drawing.visibleItems {
            let outline = item.outline(in: size)
            guard let first = outline.first else { continue }
            var box = CGRect(origin: first, size: .zero)
            for point in outline.dropFirst() { box = box.union(CGRect(origin: point, size: .zero)) }
            let unit = item.group ?? item.id
            boxes[unit] = boxes[unit].map { $0.union(box) } ?? box
        }
        var shifts: [UUID: CGVector] = [:]
        for (unit, box) in boxes {
            var dx: CGFloat = 0
            if box.minX < 0 { dx = -box.minX } else if box.maxX > size.width { dx = max(size.width - box.maxX, -box.minX) }
            let dy = box.minY < 0 ? -box.minY : 0
            if dx != 0 || dy != 0 { shifts[unit] = CGVector(dx: dx, dy: dy) }
        }
        guard !shifts.isEmpty else { return self }
        var cell = self
        for index in cell.drawing.items.indices {
            let item = cell.drawing.items[index]
            guard let shift = shifts[item.group ?? item.id] else { continue }
            cell.drawing.items[index].transform.dx += Double(shift.dx / size.width)
            cell.drawing.items[index].transform.dy += Double(shift.dy / size.height)
        }
        if cell.drawing.items.contains(where: { $0.connector != nil }) { cell.drawing.reconnect(in: size) }
        return cell
    }

    private func with(height: Double) -> DrawingCell {
        var cell = self
        cell.aspect = height / width
        return cell
    }

    /// How far down the cell the lowest ink reaches, in points: the boxes
    /// the layer hangs its handles off, which take in how far a stroke's
    /// ink spreads past its points. Nil with nothing on show.
    private var contentBottom: Double? {
        drawing.visibleItems.map { Double($0.bounds(in: size).maxY) }.max()
    }
}

/// WHAT THE DRAWING STACK KEEPS A STEP OF: the floating layer AND the cells.
/// One stack for both, so a stroke in a cell is one step like a stroke on
/// the layer, and ⌥⌘Z, ⌘Z after the pen and the tablet pen's two buttons
/// take it back without knowing which it was (`NoteStore.beginDrawingChange`).
struct DrawingState: Equatable {
    var layer: Drawing
    var cells: [UUID: DrawingCell]
}
