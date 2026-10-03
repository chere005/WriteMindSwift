import CoreGraphics
import Foundation

/// WHAT A DRAWING CELL TAKES, AND WHEN. A drawing cell is STATIC: it shows
/// its picture and nothing draws into it — not the pen, not the cursor, not
/// the tablet's nib — until it is ENTERED (Sean, 2026-10-03: "drawing cells
/// are static unless you enter click into it"). Everything here is pure, and
/// the canvas, the store and the tablet's notebook all ask it.
enum CellDrawing {
    /// The cells' paper the layer takes a press on, in document points: the
    /// entered cell's and nobody else's. The rest is the notebook's — a click
    /// on a static cell selects it, puts the caret in it, moves it, inserts
    /// around it — and in cursor mode the pointer over it is the arrow, not a
    /// pencil.
    static func paperTaken(frames: [CellFrame], entered: UUID?) -> [CGRect] {
        guard let entered else { return [] }
        return frames.filter { $0.writable && $0.id == entered }.map(\.rect)
    }
}
