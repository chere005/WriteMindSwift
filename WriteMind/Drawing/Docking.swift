import CoreGraphics
import Foundation

// DOCKING: FLOATING OBJECTS INTO A DRAWING CELL, AND A CELL MADE OF THEM.
//
// Sean, 2026-09-22: "add a button for floating elements to dock them to a
// cell wherever the input cursor is", and 2026-10-02: "on drawing segments,
// add a dock button which inserts it into the cell of the existing cursor,
// and a create cell from drawing which has a new type of cell". Everything
// that has to be RIGHT is here and pure — what is lifted off the layer,
// where it lands in the cell — and the store and the panes only carry it
// out (`docs/handoff/drawing-cells-spec.md`, section 9).
//
// The objects are MOVED, not copied: same ids, same groups, same pressures.
// A point keeps its pressure and a group its members, the lockstep rule's
// way (`CanvasSpace.rehome`).

extension Drawing {
    /// What a dock takes off the layer.
    struct Lifted: Equatable {
        /// The layer without them.
        var rest: Drawing
        /// What went, in the order it was drawn.
        var items: [CanvasItem]
    }

    /// `ids` lifted off the layer, as a dock takes them:
    ///
    /// - the selection widened to whole groups (`CanvasGroups.whole`), and
    ///   never a hidden picture — it is not on the page;
    /// - an arrow goes when it is picked, or when BOTH its ends are on things
    ///   that go;
    /// - an arrow with ONE end on something that goes stays on the layer, that
    ///   end let go where it is (`Drawing.removing` would delete it);
    /// - a going arrow keeps the ends that are on things going with it and
    ///   lets go of the rest.
    func lifting(_ ids: Set<UUID>) -> Lifted {
        let whole = CanvasGroups.whole(ids, in: items)
        var going = Set(items.filter { whole.contains($0.id) && !$0.isHidden }.map(\.id))
        for item in items {
            guard case .connector(let connector) = item, !going.contains(connector.id),
                  let start = connector.startNode, let end = connector.endNode,
                  going.contains(start), going.contains(end) else { continue }
            going.insert(connector.id)
        }
        var rest: [CanvasItem] = []
        var lifted: [CanvasItem] = []
        for item in items {
            switch item {
            case .connector(var connector):
                let startGoes = connector.startNode.map(going.contains) ?? false
                let endGoes = connector.endNode.map(going.contains) ?? false
                if going.contains(connector.id) {
                    // Ends on things that stay behind are let go.
                    if let node = connector.startNode, !going.contains(node) { connector.startNode = nil }
                    if let node = connector.endNode, !going.contains(node) { connector.endNode = nil }
                    lifted.append(.connector(connector))
                } else if startGoes || endGoes {
                    if startGoes { connector.startNode = nil }
                    if endGoes { connector.endNode = nil }
                    rest.append(.connector(connector))
                } else {
                    rest.append(item)
                }
            default:
                if going.contains(item.id) { lifted.append(item) } else { rest.append(item) }
            }
        }
        return Lifted(rest: Drawing(items: rest), items: lifted)
    }
}

/// WHERE A DOCK PUTS THE OBJECTS, in the cell's own fractions.
enum Docking {
    /// The box of `items` in the space they are in, as their handles would
    /// be drawn round them. Nil with none on show.
    static func box(of items: [CanvasItem], in size: CGSize) -> CGRect? {
        let boxes = items.filter { !$0.isHidden }.map { $0.bounds(in: size) }
        guard var all = boxes.first else { return nil }
        for box in boxes.dropFirst() { all = all.union(box) }
        return all
    }

    /// A NEW CELL FOR THESE OBJECTS: a cell as wide as the column, `pad`
    /// above the set and `pad` under it, at least two lines tall, with each
    /// object keeping its x on the column. A set wider than the column less
    /// its pad is scaled down to fit it, and one sticking out of either side
    /// is shifted in. `pane` is what the floating layer's fractions are
    /// measured against and `columnLeft` where the column starts, both in
    /// document points.
    static func newCell(for items: [CanvasItem], from pane: CGSize, columnLeft: CGFloat, column: CGFloat,
                        lineHeight: CGFloat) -> DrawingCell? {
        guard column > 0, pane.width > 0, pane.height > 0,
              let floating = box(of: items, in: pane) else { return nil }
        let pad = CGFloat(DrawingCells.pad)
        let width = Double(column)
        // The cell's top is `pad` above the set, so the set's own y is what
        // it was less that, and its x less where the column starts.
        let frame = CellFrame(id: UUID(), line: NSRange(location: 0, length: 0),
                              rect: CGRect(x: columnLeft, y: floating.minY - pad, width: column, height: 1),
                              scale: 1, width: column, writable: true)
        let space = CanvasSpace.cell(frame)
        var placed = items.map { CanvasSpace.rehome($0, from: .floating(pane: pane), to: space) }
        let size = space.size
        if var set = box(of: placed, in: size) {
            let room = column - 2 * pad
            if set.width > room, room > 0 {
                let factor = Double(room / set.width)
                let pivot = CGPoint(x: set.minX, y: set.minY)
                placed = placed.map { item in
                    var item = item
                    item.transform = CanvasEdit.transform(item, from: item.transform, scale: factor,
                                                          about: pivot, in: size)
                    return item
                }
                set = box(of: placed, in: size) ?? set
            }
            // In from either side.
            var shift: CGFloat = 0
            if set.minX < pad { shift = pad - set.minX } else if set.maxX > column - pad { shift = (column - pad) - set.maxX }
            if shift != 0 {
                placed = placed.map { item in
                    var item = item
                    item.transform.dx += Double(shift / size.width)
                    return item
                }
            }
        }
        var cell = DrawingCell(width: width, aspect: 1, drawing: Drawing(items: placed))
        let bottom = box(of: placed, in: size).map { Double($0.maxY + pad) } ?? 0
        let height = max(bottom, 2 * Double(lineHeight), 1)
        cell.aspect = height / width
        return cell.keptIn()
    }

    /// OBJECTS DOCKED INTO A CELL THAT IS THERE. The cell as it is, with the
    /// set added: where the set's box meets the cell on screen the objects
    /// keep that place exactly (shifted the least to sit inside it); where
    /// it does not they go under the cell's lowest content with their x kept
    /// on the column, `pad` below it. The cell grows to hold them.
    static func into(_ cell: DrawingCell, frame: CellFrame, items: [CanvasItem], from pane: CGSize,
                     lineHeight: CGFloat) -> DrawingCell {
        guard pane.width > 0, pane.height > 0 else { return cell }
        let space = CanvasSpace.cell(frame)
        let size = space.size
        var placed = items.map { CanvasSpace.rehome($0, from: .floating(pane: pane), to: space) }
        let pad = CGFloat(DrawingCells.pad)
        if let floating = box(of: items, in: pane), !floating.intersects(frame.rect),
           let set = box(of: placed, in: size) {
            // Under the lowest content, or the cell's top when it is empty.
            let lowest = cell.drawing.visibleItems.map { $0.bounds(in: size).maxY }.max()
            let top = lowest.map { $0 + pad } ?? pad
            let down = top - set.minY
            placed = placed.map { item in
                var item = item
                item.transform.dy += Double(down / size.height)
                return item
            }
        }
        var docked = cell
        docked.drawing.items.append(contentsOf: placed)
        return docked.keptIn().fitted(lineHeight: Double(lineHeight))
    }
}

extension Docking {
    /// A PICTURE GOES TO A CELL WITH A FILE OF ITS OWN: the layer's file is
    /// COPIED into the media folder as `cell-<cell>-<picture>.<ext>` and the
    /// picture renamed to it, so the cell's picture is never swept with the
    /// layer's (`DrawingStore.cellPicturePrefix`) and the layer's own
    /// original is still there for an undo to put back. Nil when a picture's
    /// file cannot be copied — the dock is then refused whole, rather than
    /// leaving a cell with a hole in it.
    static func carryPictures(_ items: [CanvasItem], into cell: UUID, in directory: URL) -> [CanvasItem]? {
        var carried: [CanvasItem] = []
        for item in items {
            guard case .image(var image) = item else { carried.append(item); continue }
            let source = DrawingStore.mediaURL(image.file, in: directory)
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
            let name = "\(DrawingStore.cellPicturePrefix)\(cell.uuidString)-\(image.id.uuidString).\(ext)"
            let target = DrawingStore.mediaURL(name, in: directory)
            if !FileManager.default.fileExists(atPath: target.path) {
                do {
                    try FileManager.default.createDirectory(at: DrawingStore.mediaFolder(in: directory),
                                                            withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: source, to: target)
                } catch {
                    NSLog("WriteMind: could not carry a picture into a drawing cell: \(error)")
                    return nil
                }
            }
            image.file = name
            carried.append(.image(image))
        }
        return carried
    }
}

/// WHERE THE TWO HANDLES SIT, beside the ones already round a floating
/// selection: Dock on the left at the middle, Make Cell on the right. Both
/// move to a row under the box when it is under 16 points tall — beside it
/// they would overlap the corner handles (the same 20 points every handle
/// keeps from the next).
enum HandleLayout {
    static func side(box: CGRect) -> (dock: CGPoint, make: CGPoint) {
        let y = box.height < 16 ? box.maxY + 36 : box.midY
        return (CGPoint(x: box.minX - 12, y: y), CGPoint(x: box.maxX + 12, y: y))
    }
}

/// WHERE A DOCK GOES, from the cursor — strict, never "the first cell for
/// want of one" (`EditorBridge.dockTarget`).
enum DockTarget: Equatable {
    /// An armed bar: a new drawing cell there.
    case bar(offset: Int)
    /// The cursor is in a drawing cell: into it.
    case drawingCell(UUID)
    /// The cursor is in a cell of words: a new drawing cell under the
    /// caret's line.
    case textCell(caret: Int)
}
