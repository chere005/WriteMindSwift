import XCTest
@testable import WriteMind

/// A write that a test needed and did not get — thrown, so the test fails
/// there and then rather than going on to assert about nothing.
struct CellNotWritten: Error {
    var result: DrawingCellStore.Write
}

/// The cells' files, in a temp folder and never in ~/Documents/WriteMind:
/// `_drawings/cells/<ID>.png` beside the note — visible (Sean, 2026-10-02:
/// "visible data generally speaking") — written only over the bytes last
/// read or written, never over a placeholder, and never deleted.
final class DrawingCellStoreTests: XCTestCase {
    private var dir: URL!
    private let id = UUID(uuidString: "6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6")!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appending(path: "Ideas"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var note: URL { dir.appending(path: "Trip.md") }

    private let strokeID = UUID()

    private func cell(_ x: Double = 0.2) -> DrawingCell {
        DrawingCell(width: 600, aspect: 0.3,
                    drawing: Drawing(strokes: [Stroke(id: strokeID, colorHex: "#000000", width: 2,
                                                      points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: x, y: 0.2)])]))
    }

    private func written(_ cell: DrawingCell, known: Data? = nil) throws -> Data {
        let result = DrawingCellStore.write(cell, rendition: DrawingCellFileTests.png(), id: id,
                                            besides: note, known: known)
        guard case .written(let bytes) = result else { throw CellNotWritten(result: result) }
        return bytes
    }

    func testTheFolderIsBesideTheNoteAndTheLineFindsItAtEveryDepth() {
        let section = dir.appending(path: "Ideas/Plan.md")
        XCTAssertEqual(DrawingCellStore.url(id, besides: note).path,
                       dir.appending(path: "_drawings/cells/\(id.uuidString).png").path)
        XCTAssertEqual(DrawingCellStore.url(id, besides: section).path,
                       dir.appending(path: "Ideas/_drawings/cells/\(id.uuidString).png").path)
        // The line's path, read the way any markdown reader reads it —
        // relative to the note — is the file, at any depth.
        for place in [note, section] {
            let target = DrawingCells.line(id).dropFirst(4).dropLast()
            XCTAssertEqual(URL(string: String(target), relativeTo: place)?.standardizedFileURL.path,
                           DrawingCellStore.url(id, besides: place).standardizedFileURL.path)
        }
    }

    func testNothingThereIsAnEmptyCellTheFirstWriteMakes() throws {
        XCTAssertEqual(DrawingCellStore.load(id, besides: note),
                       DrawingCellStore.Loaded(cell: nil, state: .writable, known: nil))
        let bytes = try written(cell())
        XCTAssertEqual(try Data(contentsOf: DrawingCellStore.url(id, besides: note)), bytes)
        XCTAssertEqual(DrawingCellStore.load(id, besides: note),
                       DrawingCellStore.Loaded(cell: cell(), state: .writable, known: bytes))
    }

    func testAWriteGoesOnlyOverTheBytesLastReadOrWritten() throws {
        let first = try written(cell(0.2))
        let second = try written(cell(0.3), known: first)
        XCTAssertNotEqual(first, second)

        // Another writer: a second instance, iCloud, an editor.
        let theirs = try XCTUnwrap(DrawingCellFile.embed(DrawingCellFile.payload(cell(0.9)),
                                                         in: DrawingCellFileTests.png(width: 30)))
        try theirs.write(to: DrawingCellStore.url(id, besides: note))
        let refused = DrawingCellStore.write(cell(0.4), rendition: DrawingCellFileTests.png(), id: id,
                                             besides: note, known: second)
        XCTAssertEqual(refused, .refused(DrawingCellStore.changedElsewhere))
        XCTAssertEqual(refused.state, .readOnly(DrawingCellStore.changedElsewhere), "and the cell goes read-only")
        XCTAssertEqual(try Data(contentsOf: DrawingCellStore.url(id, besides: note)), theirs, "theirs is kept")

        // Something there that was never read is not ours either.
        let never = DrawingCellStore.write(cell(0.4), rendition: DrawingCellFileTests.png(), id: id,
                                           besides: note, known: nil)
        guard case .refused = never else { return XCTFail("wrote over a file it had never read") }
        XCTAssertEqual(try Data(contentsOf: DrawingCellStore.url(id, besides: note)), theirs)
    }

    func testAPictureThatIsNotACellIsShownAndNeverWrittenOver() throws {
        let picture = DrawingCellFileTests.png()
        let file = DrawingCellStore.url(id, besides: note)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try picture.write(to: file)
        let loaded = DrawingCellStore.load(id, besides: note)
        XCTAssertNil(loaded.cell)
        XCTAssertEqual(loaded.state, .readOnly(DrawingCellStore.notOurs))
        XCTAssertEqual(loaded.known, picture, "its pixels are what is shown")
        // Even handed the very bytes it read.
        let result = DrawingCellStore.write(cell(), rendition: DrawingCellFileTests.png(), id: id,
                                            besides: note, known: picture)
        XCTAssertEqual(result, .refused(DrawingCellStore.notOurs))
        XCTAssertEqual(try Data(contentsOf: file), picture)
    }

    func testAnICloudPlaceholderIsNeverCreatedOver() throws {
        let placeholder = DrawingCellStore.placeholder(id, besides: note)
        XCTAssertEqual(placeholder.lastPathComponent, ".\(id.uuidString).png.icloud")
        try FileManager.default.createDirectory(at: placeholder.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("bplist".utf8).write(to: placeholder)
        XCTAssertEqual(DrawingCellStore.load(id, besides: note).state, .placeholder)
        let result = DrawingCellStore.write(cell(), rendition: DrawingCellFileTests.png(), id: id,
                                            besides: note, known: nil)
        XCTAssertEqual(result, .refused(DrawingCellStore.notDownloaded))
        XCTAssertFalse(FileManager.default.fileExists(atPath: DrawingCellStore.url(id, besides: note).path))
        // Nor copied over.
        let other = UUID()
        let source = dir.appending(path: "Ideas/Plan.md")
        _ = DrawingCellStore.write(cell(), rendition: DrawingCellFileTests.png(), id: other,
                                   besides: source, known: nil)
        DrawingCellStore.copy(other, to: id, from: source, to: note)
        XCTAssertFalse(FileManager.default.fileExists(atPath: DrawingCellStore.url(id, besides: note).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: placeholder.path))
    }

    /// WriteMind never deletes anything under `_drawings/cells`: a cell
    /// emptied is a cell written empty, and a copy leaves its original.
    func testNothingIsEverDeleted() throws {
        let drawn = try written(cell())
        let emptied = try written(DrawingCell.empty(width: 600), known: drawn)
        XCTAssertEqual(DrawingCellStore.load(id, besides: note).cell, DrawingCell.empty(width: 600))
        XCTAssertEqual(try Data(contentsOf: DrawingCellStore.url(id, besides: note)), emptied)

        let section = dir.appending(path: "Ideas/Plan.md")
        DrawingCellStore.copy(id, to: id, from: note, to: section)
        XCTAssertEqual(try Data(contentsOf: DrawingCellStore.url(id, besides: section)), emptied)
        XCTAssertEqual(try Data(contentsOf: DrawingCellStore.url(id, besides: note)), emptied, "the original stays")
        // And a copy never goes over a file already there.
        let other = try XCTUnwrap(DrawingCellFile.embed(DrawingCellFile.payload(cell(0.7)), in: DrawingCellFileTests.png()))
        try other.write(to: DrawingCellStore.url(id, besides: section))
        DrawingCellStore.copy(id, to: id, from: note, to: section)
        XCTAssertEqual(try Data(contentsOf: DrawingCellStore.url(id, besides: section)), other)
    }

    /// The sweep of `.drawings/media` deletes every picture no sidecar names
    /// — and a cell's file is named by no sidecar at all. It must never be
    /// looked at.
    func testTheMediaSweepNeverTouchesACellsFile() throws {
        let bytes = DrawingCellFileTests.png()
        let sectionNote = dir.appending(path: "Ideas/Plan.md")
        let sectionBytes = DrawingCellFileTests.png(width: 30)
        for (place, data) in [(note, bytes), (sectionNote, sectionBytes)] {
            let file = DrawingCellStore.url(id, besides: place)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: file)
        }
        let orphan = DrawingStore.mediaURL("ORPHAN.png", in: dir)
        try FileManager.default.createDirectory(at: orphan.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DrawingCellFileTests.png().write(to: orphan)

        DrawingStore.pruneMedia(in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path), "the premise: the sweep ran")
        XCTAssertEqual(try Data(contentsOf: DrawingCellStore.url(id, besides: note)), bytes)
        XCTAssertEqual(try Data(contentsOf: DrawingCellStore.url(id, besides: sectionNote)), sectionBytes)
    }

    func testAForkChangesTheIdsAndNothingElse() {
        let a = UUID(), b = UUID()
        let newA = UUID(), newB = UUID()
        var minted = [newA, newB]
        let note = "# Trip\n\n\(DrawingCells.line(a))\n\nWords\n\n  \(DrawingCells.line(b))\n\n```\n\(DrawingCells.line(a))\n```\n\n<a id=\"wm-1\"></a>\(DrawingCells.line(a))"
        let forked = DrawingCells.forked(note) { minted.removeFirst() }
        XCTAssertEqual(forked.ids.map(\.old), [a, b])
        XCTAssertEqual(forked.ids.map(\.new), [newA, newB])
        // The pasted line names one drawing, and so does its copy; the
        // line inside the fence is code, and code is not touched.
        XCTAssertEqual(forked.markdown,
                       "# Trip\n\n\(DrawingCells.line(newA))\n\nWords\n\n  \(DrawingCells.line(newB))\n\n```\n\(DrawingCells.line(a))\n```\n\n<a id=\"wm-1\"></a>\(DrawingCells.line(newA))")
        XCTAssertEqual(DrawingCells.forked("No cells here.").markdown, "No cells here.")
        XCTAssertTrue(DrawingCells.forked("No cells here.").ids.isEmpty)
    }
}

/// `_drawings` is a note's data, not a section: never listed, never made,
/// never a place a note goes. And the cells follow a note the way the spec
/// says — copied on a move, forked on a duplicate, left alone on a rename.
@MainActor
final class DrawingCellNoteTests: XCTestCase {
    private var dir: URL!
    private var store: NoteStore!
    private let id = UUID(uuidString: "6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6")!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appending(path: "Ideas"), withIntermediateDirectories: true)
        try Data("# Trip\n\nBefore\n\n\(DrawingCells.line(id))\n\nAfter\n".utf8).write(to: dir.appending(path: "Trip.md"))
        // With a byte-order mark, which reading it as a string and writing
        // that back would lose.
        try Data([0xEF, 0xBB, 0xBF] + Array("# Plan\r\n".utf8)).write(to: dir.appending(path: "Ideas/Plan.md"))
        store = NoteStore(directory: dir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func tripNote() throws -> Note {
        try XCTUnwrap(store.notes.first { $0.url.lastPathComponent == "Trip.md" })
    }

    /// A cell's file where the note's line points — its bytes, as they are
    /// on disk, are all that following a note is about.
    private func drawn(besides note: URL, width: Int = 40) throws -> Data {
        let bytes = DrawingCellFileTests.png(width: width)
        let file = DrawingCellStore.url(id, besides: note)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file)
        return bytes
    }

    func testTheSidebarNeverListsANotesDrawings() throws {
        let trip = try tripNote()
        _ = try drawn(besides: trip.url)
        _ = try drawn(besides: dir.appending(path: "Ideas/Plan.md"), width: 30)
        try FileManager.default.createDirectory(at: dir.appending(path: "_Drawings/cells"), withIntermediateDirectories: true)
        let tree = NoteTree.read(directory: dir, root: dir, order: NoteOrder())
        XCTAssertEqual(tree.sections.map(\.name), ["Ideas"])
        XCTAssertEqual(tree.sections.first?.sections.map(\.name), [])
        store.reload()
        XCTAssertEqual(store.allSections.map(\.name), ["Notes", "Ideas"])
        XCTAssertFalse(NoteTree.isSection(dir.appending(path: "_drawings")))
        XCTAssertFalse(NoteTree.isSection(dir.appending(path: "_DRAWINGS")))
        XCTAssertTrue(NoteTree.isSection(dir.appending(path: "drawings")))
        XCTAssertTrue(NoteTree.isSection(dir.appending(path: "_drawings 2")))
    }

    func testNoSectionIsMadeWithItsName() throws {
        let made = try XCTUnwrap(store.createSection(named: "_drawings"))
        XCTAssertEqual(made.name, "_drawings 2", "a section by that name would vanish from the sidebar")
    }

    func testNoSectionIsRenamedToIt() throws {
        let ideas = try XCTUnwrap(store.allSections.first { $0.name == "Ideas" })
        store.rename(ideas, to: "_Drawings")
        XCTAssertEqual(store.allSections.map(\.name), ["Notes", "_Drawings 2"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "_Drawings 2/Plan.md").path))
    }

    func testNothingIsMovedIntoIt() throws {
        let trip = try tripNote()
        _ = try drawn(besides: trip.url)
        let data = NoteSection(url: dir.appending(path: "_drawings"), name: "_drawings", depth: 1,
                               notes: [], sections: [])
        XCTAssertFalse(store.move(trip, to: data))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "Trip.md").path))
        let ideas = try XCTUnwrap(store.allSections.first { $0.name == "Ideas" })
        XCTAssertFalse(store.move(ideas, to: data))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "Ideas/Plan.md").path))
    }

    func testMovingANoteCopiesItsCellsAndLeavesTheOriginals() throws {
        let trip = try tripNote()
        let bytes = try drawn(besides: trip.url)
        let ideas = try XCTUnwrap(store.allSections.first { $0.name == "Ideas" })
        XCTAssertTrue(store.move(trip, to: ideas))
        let moved = dir.appending(path: "Ideas/Trip.md")
        XCTAssertTrue(try String(contentsOf: moved, encoding: .utf8).contains(DrawingCells.line(id)),
                      "the line is not rewritten")
        XCTAssertEqual(DrawingCellStore.load(id, besides: moved).known, bytes)
        XCTAssertEqual(try Data(contentsOf: dir.appending(path: "_drawings/cells/\(id.uuidString).png")), bytes,
                       "the original stays")
    }

    func testRenamingANoteLeavesItsCellsWhereItsLineFindsThem() throws {
        let trip = try tripNote()
        let bytes = try drawn(besides: trip.url)
        store.rename(trip, to: "Journey")
        let renamed = dir.appending(path: "Journey.md")
        XCTAssertEqual(DrawingCellStore.load(id, besides: renamed).known, bytes)
    }

    func testDuplicatingANoteForksItsCellsAndCopiesTheirFiles() throws {
        let trip = try tripNote()
        let bytes = try drawn(besides: trip.url)
        let original = try String(contentsOf: trip.url, encoding: .utf8)
        let copy = try XCTUnwrap(store.duplicate(trip))
        let text = try String(contentsOf: copy.url, encoding: .utf8)
        let ids = DrawingCells.ids(in: text)
        XCTAssertEqual(ids.count, 1)
        let new = try XCTUnwrap(ids.first)
        XCTAssertNotEqual(new, id, "two notes never share a drawing")
        XCTAssertEqual(text, original.replacingOccurrences(of: id.uuidString, with: new.uuidString),
                       "and nothing but the id changed")
        XCTAssertEqual(DrawingCellStore.load(new, besides: copy.url).known, bytes)
        XCTAssertEqual(try String(contentsOf: trip.url, encoding: .utf8), original, "the original is untouched")
        XCTAssertEqual(DrawingCellStore.load(id, besides: trip.url).known, bytes)
    }

    func testANoteWithNoCellsIsStillCopiedByteForByte() throws {
        let plan = try XCTUnwrap(store.notes.first { $0.url.lastPathComponent == "Plan.md" })
        let copy = try XCTUnwrap(store.duplicate(plan))
        XCTAssertEqual(try Data(contentsOf: copy.url), try Data(contentsOf: plan.url))
    }
}
