import XCTest
@testable import WriteMind

/// THE HIDDEN `.drawings` BECOMES THE VISIBLE `_drawings` (Sean, 2026-10-02:
/// "visible data generally speaking", then, asked whether the existing
/// folders should move too: "yes"). Against temp folders only — Sean's own
/// notes are never touched by a test.
@MainActor
final class DrawingMigrationTests: XCTestCase {
    private var dir: URL!
    private let fileManager = FileManager.default

    override func setUp() async throws {
        dir = fileManager.temporaryDirectory.appending(path: "WriteMindTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? fileManager.removeItem(at: dir)
    }

    private func path(_ relative: String) -> URL { dir.appending(path: relative) }

    private func write(_ relative: String, _ text: String) throws {
        let url = path(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ relative: String) -> String? {
        try? String(contentsOf: path(relative), encoding: .utf8)
    }

    private func exists(_ relative: String) -> Bool { fileManager.fileExists(atPath: path(relative).path) }

    private func hiddenData() throws {
        try write(".drawings/Trip.json", "sidecar")
        try write(".drawings/media/a.png", "picture a")
        try write(".drawings/media/b.jpg", "picture b")
    }

    func testTheSidecarsAndThePicturesMoveAndTheEmptyHiddenFolderGoes() throws {
        try hiddenData()
        XCTAssertEqual(DrawingStore.migrateHiddenData(in: dir), 2, "the sidecar and the media folder")
        XCTAssertEqual(read("_drawings/Trip.json"), "sidecar")
        XCTAssertEqual(read("_drawings/media/a.png"), "picture a")
        XCTAssertEqual(read("_drawings/media/b.jpg"), "picture b")
        XCTAssertFalse(exists(".drawings"), "emptied, so it goes")
    }

    func testItMergesIntoAVisibleFolderThatIsThereAlreadyAndLeavesItsCellsAlone() throws {
        try hiddenData()
        try write("_drawings/cells/ID.png", "a cell")
        try write("_drawings/media/c.png", "already here")
        DrawingStore.migrateHiddenData(in: dir)
        XCTAssertEqual(read("_drawings/cells/ID.png"), "a cell")
        XCTAssertEqual(read("_drawings/media/c.png"), "already here")
        XCTAssertEqual(read("_drawings/media/a.png"), "picture a")
        XCTAssertEqual(read("_drawings/Trip.json"), "sidecar")
    }

    /// Never over anything: a name that is taken stays where it was, and the
    /// hidden folder stays with it.
    func testANameThatIsTakenIsNotOverwrittenAndStaysBehind() throws {
        try hiddenData()
        try write("_drawings/media/a.png", "the newer one")
        DrawingStore.migrateHiddenData(in: dir)
        XCTAssertEqual(read("_drawings/media/a.png"), "the newer one", "not overwritten")
        XCTAssertEqual(read(".drawings/media/a.png"), "picture a", "and not deleted")
        XCTAssertEqual(read("_drawings/media/b.jpg"), "picture b", "the rest moved")
        XCTAssertTrue(exists(".drawings"), "something is left in it, so it stays")
    }

    func testRunningItAgainOrWithNothingThereDoesNothing() throws {
        XCTAssertEqual(DrawingStore.migrateHiddenData(in: dir), 0)
        try hiddenData()
        DrawingStore.migrateHiddenData(in: dir)
        XCTAssertEqual(DrawingStore.migrateHiddenData(in: dir), 0)
        XCTAssertEqual(read("_drawings/Trip.json"), "sidecar")
    }

    func testWhatIsLeftBehindIsStillFoundByTheLoaderAndThePictures() throws {
        let drawing = Drawing(items: [.image(ImageItem(file: "a.png"))])
        try write(".drawings/media/a.png", "picture a")
        try fileManager.createDirectory(at: path(".drawings"), withIntermediateDirectories: true)
        try JSONEncoder().encode(drawing).write(to: path(".drawings/Trip.json"))
        // A move that could not happen: the name is taken in the visible folder, by a folder.
        try write("_drawings/media/a.png", "other")
        let note = dir.appending(path: "Trip.md")
        XCTAssertEqual(DrawingStore.load(for: note, in: dir).images.map(\.file), ["a.png"])
        try fileManager.removeItem(at: path("_drawings/media/a.png"))
        XCTAssertEqual(DrawingStore.mediaURL("a.png", in: dir).path, path(".drawings/media/a.png").path)
    }

    func testTheSweepDeletesNothingWhileTheHiddenFolderIsStillThere() throws {
        try write(".drawings/Trip.json", "{}")
        try write("_drawings/media/orphan.png", "x")
        DrawingStore.pruneMedia(in: dir)
        XCTAssertTrue(exists("_drawings/media/orphan.png"), "its sidecars name pictures it does not read")
    }

    func testNewDataIsWrittenToTheVisibleFolder() throws {
        let note = dir.appending(path: "Trip.md")
        DrawingStore.save(Drawing(items: [.image(ImageItem(file: "a.png"))]), for: note, in: dir)
        XCTAssertTrue(exists("_drawings/Trip.json"))
        XCTAssertFalse(exists(".drawings"))
    }

    func testOpeningAFolderMovesItsHiddenDrawingsAndTheNoteStillHasItsDrawing() throws {
        try write("Trip.md", "# Trip\n")
        let drawing = Drawing(items: [.image(ImageItem(file: "a.png"))])
        try fileManager.createDirectory(at: path(".drawings"), withIntermediateDirectories: true)
        try JSONEncoder().encode(drawing).write(to: path(".drawings/Trip.json"))
        try write(".drawings/media/a.png", "picture a")
        let store = NoteStore(directory: dir)
        XCTAssertEqual(store.drawing.images.map(\.file), ["a.png"], "the drawing came with it")
        XCTAssertTrue(exists("_drawings/Trip.json"))
        XCTAssertFalse(exists(".drawings"))
        XCTAssertFalse(store.roots.flatMap { $0.sections }.contains { $0.name == "_drawings" },
                       "and it is not a section of the notes")
    }
}
