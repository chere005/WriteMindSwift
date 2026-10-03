import XCTest
@testable import WriteMind

/// A PICTURE DOCKED INTO A CELL has a file of its own, and the media sweep
/// that runs mid-note never takes what an undo could still bring back
/// (docs/handoff/drawing-cells-spec.md, 9.2 and 9.6).
@MainActor
final class DockPictureTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func media(_ name: String, bytes: String = "x") throws {
        let folder = DrawingStore.mediaFolder(in: dir)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: folder.appending(path: name))
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: DrawingStore.mediaURL(name, in: dir).path)
    }

    private func sidecar(_ name: String, naming files: [String]) throws {
        let folder = dir.appending(path: DrawingStore.folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let drawing = Drawing(items: files.map { .image(ImageItem(file: $0)) })
        try JSONEncoder().encode(drawing).write(to: folder.appending(path: "\(name).json"))
    }

    // MARK: - Carrying a picture

    func testAPictureGoesToTheCellAsACopyUnderAnOwnName() throws {
        try media("a.png", bytes: "pixels")
        let image = ImageItem(file: "a.png", center: CGPoint(x: 0.3, y: 0.3), width: 0.2, aspect: 0.5)
        let cell = UUID()
        let carried = try XCTUnwrap(Docking.carryPictures([.image(image)], into: cell, in: dir))
        let moved = try XCTUnwrap(carried.first?.image)
        XCTAssertEqual(moved.id, image.id, "the same picture, moved and not copied")
        XCTAssertEqual(moved.file, "cell-\(cell.uuidString)-\(image.id.uuidString).png")
        XCTAssertEqual(try Data(contentsOf: DrawingStore.mediaURL(moved.file, in: dir)), Data("pixels".utf8))
        XCTAssertTrue(exists("a.png"), "the layer's own file is left for an undo")
    }

    func testAnythingButAPictureIsLeftAlone() throws {
        let stroke = CanvasItem.stroke(Stroke(colorHex: "#000000", width: 2,
                                              points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)]))
        XCTAssertEqual(Docking.carryPictures([stroke], into: UUID(), in: dir), [stroke])
    }

    func testAPictureWhoseFileIsGoneRefusesTheWholeDock() {
        let image = ImageItem(file: "missing.png")
        XCTAssertNil(Docking.carryPictures([.image(image)], into: UUID(), in: dir))
    }

    // MARK: - The sweep

    func testTheSweepStillTakesWhatNothingNames() throws {
        try media("orphan.png")
        try media("used.png")
        try sidecar("Trip", naming: ["used.png"])
        DrawingStore.pruneMedia(in: dir)
        XCTAssertFalse(exists("orphan.png"))
        XCTAssertTrue(exists("used.png"))
    }

    func testTheSweepKeepsWhatTheOpenNoteStillNeeds() throws {
        try media("history.png")
        try media("orphan.png")
        DrawingStore.pruneMedia(in: dir, keeping: ["history.png"])
        XCTAssertTrue(exists("history.png"), "an undo could still bring it back")
        XCTAssertFalse(exists("orphan.png"))
    }

    func testACellsPictureIsNeverSwept() throws {
        let name = "cell-\(UUID().uuidString)-\(UUID().uuidString).png"
        try media(name)
        DrawingStore.pruneMedia(in: dir)
        XCTAssertTrue(exists(name))
    }

    func testNothingIsDeletedWhenASidecarCannotBeRead() throws {
        try media("orphan.png")
        try media("named-only-by-the-broken-one.png")
        let folder = dir.appending(path: DrawingStore.folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appending(path: "Broken.json"))
        DrawingStore.pruneMedia(in: dir)
        XCTAssertTrue(exists("orphan.png"), "a sweep that cannot see everything deletes nothing")
        XCTAssertTrue(exists("named-only-by-the-broken-one.png"))
    }

    func testTheOpenNotesPicturesAreItsLayerItsHistoryItsFutureAndItsCells() throws {
        try Data("# Trip\n".utf8).write(to: dir.appending(path: "Trip.md"))
        let store = NoteStore(directory: dir)
        func image(_ name: String) -> CanvasItem { .image(ImageItem(file: name)) }
        store.drawing = Drawing(items: [image("layer.png")])
        store.beginDrawingChange()              // history now holds the layer as it was
        store.drawing = Drawing(items: [image("later.png")])
        var cell = DrawingCell.empty(width: 400)
        cell.drawing.items = [image("cell-x.png")]
        store.cells[UUID()] = cell
        XCTAssertTrue(store.undoDrawing())      // `later.png` is now in the future
        let names = store.mediaInUse
        XCTAssertTrue(names.isSuperset(of: ["layer.png", "later.png"]), "\(names)")
    }
}
