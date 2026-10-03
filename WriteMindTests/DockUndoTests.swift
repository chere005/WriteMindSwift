import XCTest
@testable import WriteMind

/// A dock that made a cell is ONE step on the drawing's stack, and taking
/// that step back takes the cell's line out of the note with it — so the
/// objects are never left in a cell nothing points at — and putting it back
/// puts the line back (`NoteStore.docks`). The pane's write is what this
/// store is handed (`writeCell`); here it is applied to the note's text.
@MainActor
final class DockUndoTests: XCTestCase {
    private var dir: URL!
    private var store: NoteStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# Trip\n\nFirst paragraph.\n\nSecond paragraph.\n".utf8).write(to: dir.appending(path: "Trip.md"))
        store = NoteStore(directory: dir)
        store.writeCell = { [unowned self] edit in
            store.text = (store.text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        }
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func floating() -> CanvasItem {
        .stroke(Stroke(colorHex: "#000000", width: 3,
                       points: [CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.4, y: 0.52)], pressures: [0.4, 0.9],
                       tool: .fountain))
    }

    /// What `EditorPane.dock` does for a new cell, as the store sees it.
    private func dockIntoNewCell(at offset: Int) throws -> (id: UUID, item: CanvasItem) {
        let item = floating()
        store.drawing.items = [item]
        let id = UUID()
        let (updated, _, caret) = CellTypes.open(.drawing, in: store.text, at: offset, minting: id)
        let added = (updated as NSString).length - (store.text as NSString).length
        let opening = (updated as NSString).substring(with: NSRange(location: offset, length: added))
        store.beginDrawingChange()
        var cell = DrawingCell.empty(width: 400)
        cell.drawing.items = [item]
        store.cells[id] = cell
        store.drawing = Drawing()
        store.recordDock(cell: id, offset: offset, opening: opening)
        store.writeCell?(MarkdownFormatting.Edit(range: NSRange(location: offset, length: 0), replacement: opening,
                                                 selection: NSRange(location: caret, length: 0)))
        return (id, item)
    }

    private func hasLine(_ id: UUID) -> Bool {
        DrawingCells.lines(in: store.text).contains { $0.id == id }
    }

    func testTheDockIsOneStepAndTheLineIsInTheNote() throws {
        let start = store.text
        let docked = try dockIntoNewCell(at: (store.text as NSString).range(of: "Second").location)
        XCTAssertTrue(hasLine(docked.id))
        XCTAssertTrue(store.drawing.isEmpty, "the objects left the layer")
        XCTAssertEqual(store.cells[docked.id]?.drawing.items.map(\.id), [docked.item.id])
        XCTAssertEqual(store.drawingSteps, 1)
        XCTAssertNotEqual(store.text, start)
    }

    func testTakingTheStepBackPutsTheObjectsOnTheLayerAndTakesTheLineOut() throws {
        let start = store.text
        let docked = try dockIntoNewCell(at: (store.text as NSString).range(of: "Second").location)
        XCTAssertTrue(store.undoDrawing())
        XCTAssertEqual(store.drawing.items.map(\.id), [docked.item.id], "floating again")
        XCTAssertEqual(store.drawing.items.first?.stroke?.pressures, [0.4, 0.9])
        XCTAssertFalse(hasLine(docked.id), "and no line left over")
        XCTAssertEqual(store.text, start, "the note is as it was, to the byte")
        XCTAssertTrue(store.cells[docked.id]?.drawing.isEmpty ?? true, "nothing hidden in a cell with no line")
    }

    func testPuttingItBackPutsTheLineAndTheObjectsBackInTheCell() throws {
        let docked = try dockIntoNewCell(at: (store.text as NSString).range(of: "Second").location)
        let docked_text = store.text
        XCTAssertTrue(store.undoDrawing())
        XCTAssertTrue(store.redoDrawing())
        XCTAssertTrue(hasLine(docked.id))
        XCTAssertEqual(store.text, docked_text)
        XCTAssertTrue(store.drawing.isEmpty)
        XCTAssertEqual(store.cells[docked.id]?.drawing.items.map(\.id), [docked.item.id])
    }

    func testAnUndoOfSomethingElseLeavesTheDockAlone() throws {
        let docked = try dockIntoNewCell(at: (store.text as NSString).range(of: "Second").location)
        // A later stroke on the layer, and its undo.
        store.beginDrawingChange()
        store.drawing.items.append(floating())
        XCTAssertTrue(store.undoDrawing())
        XCTAssertTrue(hasLine(docked.id), "only the dock's own step takes its line")
    }

    func testANewStepAfterAnUndoDropsTheDockThatWasUndone() throws {
        let docked = try dockIntoNewCell(at: (store.text as NSString).range(of: "Second").location)
        XCTAssertTrue(store.undoDrawing())
        store.beginDrawingChange()                      // the future is given up
        store.drawing.items.append(floating())
        XCTAssertTrue(store.docks.isEmpty)
        XCTAssertFalse(store.redoDrawing(), "nothing to redo, and no line comes back")
        XCTAssertFalse(hasLine(docked.id))
    }
}
