import SwiftUI

/// DOCK AND MAKE CELL, carried out (`Docking`, `NoteStore.docks`). The two
/// handles on a selection of floating objects (`DrawingCanvas`) land here.
///
/// Done on the layer as the pane SHOWS it (`layerDrawing`): on the rendered
/// page that is the markdown pane's frame seen through the page's own cells,
/// and the objects are lifted, measured and put down in the frame the eye is
/// in. The cell they go to is in the cell's own space, which is the same
/// whichever pane it is made from. ONE step on the drawing's stack
/// (`beginDrawingChange`), which a dock that made a cell takes the cell's
/// line out of the note with (`NoteStore.docks`).
extension EditorPane {
    /// DOCK: into the cell at the cursor — a drawing cell takes them, a bar
    /// or a cell of words gets a new drawing cell for them, and with no
    /// cursor at all it is Make Cell.
    func dock(_ ids: Set<UUID>) {
        dockObjects(ids, target: appState.editor.dockTarget())
    }

    /// MAKE CELL: a new drawing cell at the seam nearest the objects.
    func makeCell(_ ids: Set<UUID>) {
        dockObjects(ids, target: nil)
    }

    private func dockObjects(_ ids: Set<UUID>, target: DockTarget?) {
        guard store.selectedNote != nil else { return }
        var lifted = layerDrawing.wrappedValue.lifting(ids)
        guard !lifted.items.isEmpty else { return }
        let pane = store.canvasSize
        let lineHeight = MarkdownTextView.lineHeight

        let media = store.owningFolder(for: store.selectedNote!.url)

        // INTO A CELL THAT IS THERE.
        if case .drawingCell(let id)? = target {
            guard let frame = drawingFrames.first(where: { $0.id == id }) else {
                store.notice("That drawing is folded away — open its section to dock into it.")
                return
            }
            guard frame.writable else {
                store.notice("That drawing cannot be drawn in, so nothing was docked into it.")
                return
            }
            guard let carried = Docking.carryPictures(lifted.items, into: id, in: media) else {
                store.notice("A picture could not be copied into that drawing, so nothing was docked.")
                return
            }
            lifted.items = carried
            store.beginDrawingChange()
            let cell = store.cells[id] ?? .empty(width: Double(frame.width))
            store.cells[id] = Docking.into(cell, frame: frame, items: lifted.items, from: pane,
                                           lineHeight: lineHeight)
            layerDrawing.wrappedValue = lifted.rest
            return
        }

        // A NEW CELL, where the cursor says — or nearest the objects.
        guard let column = appState.editor.paneColumn?() else { return }
        let offset: Int
        switch target {
        case .bar(let at)?:
            offset = at
        case .textCell(let caret)?:
            offset = DrawingCells.landing(caret: caret, in: store.text)
        default:
            guard let box = Docking.box(of: lifted.items, in: pane),
                  let seam = CellSeams.nearest(toLine: box.minY, in: appState.editor.paneSeams?() ?? [])
            else { return }
            offset = seam.offset
        }
        let id = UUID()
        guard let carried = Docking.carryPictures(lifted.items, into: id, in: media) else {
            store.notice("A picture could not be copied into the new drawing, so nothing was docked.")
            return
        }
        guard let cell = Docking.newCell(for: carried, from: pane, columnLeft: column.left,
                                         column: column.width, lineHeight: lineHeight) else { return }
        let place = min(max(offset, 0), (store.text as NSString).length)
        let (updated, _, caret) = CellTypes.open(.drawing, in: store.text, at: place, minting: id)
        let added = (updated as NSString).length - (store.text as NSString).length
        guard added >= 0 else { return }
        let opening = (updated as NSString).substring(with: NSRange(location: place, length: added))

        store.beginDrawingChange()
        store.cells[id] = cell
        layerDrawing.wrappedValue = lifted.rest
        store.recordDock(cell: id, offset: place, opening: opening)
        appState.editor.write(MarkdownFormatting.Edit(range: NSRange(location: place, length: 0),
                                                       replacement: opening,
                                                       selection: NSRange(location: caret, length: 0)))
        // The cursor goes into the cell, so a second Dock adds to it. A turn
        // late: the row this edit made is not on the page yet.
        DispatchQueue.main.async { appState.editor.focusDrawingCell(id) }
    }
}
