import XCTest
@testable import WriteMind

final class DrawingStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSaveLoadRenameAndDeleteFollowTheNote() {
        let note = dir.appending(path: "Trip.md")
        let renamed = dir.appending(path: "Trip 2026.md")
        let drawing = Drawing(strokes: [Stroke(colorHex: "#000000", width: 2, points: [CGPoint(x: 0.1, y: 0.2)])])

        DrawingStore.save(drawing, for: note, in: dir)
        XCTAssertEqual(DrawingStore.load(for: note, in: dir), drawing)
        XCTAssertTrue(DrawingStore.url(for: note, in: dir).path.contains("/_drawings/Trip.json"))

        DrawingStore.rename(from: note, to: renamed, in: dir)
        XCTAssertEqual(DrawingStore.load(for: renamed, in: dir), drawing)
        XCTAssertTrue(DrawingStore.load(for: note, in: dir).isEmpty)

        DrawingStore.delete(for: renamed, in: dir)
        XCTAssertTrue(DrawingStore.load(for: renamed, in: dir).isEmpty)
    }

    func testSavingAnEmptyDrawingRemovesTheSidecar() {
        let note = dir.appending(path: "Blank.md")
        DrawingStore.save(Drawing(strokes: [Stroke(colorHex: "#000000", width: 1, points: [.zero])]), for: note, in: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: DrawingStore.url(for: note, in: dir).path))
        DrawingStore.save(Drawing(), for: note, in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: DrawingStore.url(for: note, in: dir).path))
    }
}
