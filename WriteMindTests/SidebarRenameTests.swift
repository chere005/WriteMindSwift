import XCTest
@testable import WriteMind

/// Rename in place (Sean, 2026-10-02: "rename in place in the sidebar..
/// double click is rename in sidebar"). The field is the view's; what it
/// commits is `NoteStore.rename`, the one the context menu's alert uses,
/// and this holds what that does with what a hand can type into a field.
@MainActor
final class SidebarRenameTests: XCTestCase {
    private var dir: URL!
    private var store: NoteStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appending(path: "Trips"), withIntermediateDirectories: true)
        try Data("# One\n".utf8).write(to: dir.appending(path: "One.md"))
        try Data("# Two\n".utf8).write(to: dir.appending(path: "Two.md"))
        store = NoteStore(directory: dir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appending(path: name).path)
    }

    private func note(_ file: String) throws -> Note {
        try XCTUnwrap(store.notes.first { $0.url.lastPathComponent == file })
    }

    func testANoteIsRenamedToWhatWasTyped() throws {
        store.rename(try note("One.md"), to: "  Packing list ")
        XCTAssertTrue(exists("Packing list.md"), "the name is trimmed and the file keeps its .md")
        XCTAssertFalse(exists("One.md"))
    }

    func testAnEmptyOrUnchangedNameRenamesNothing() throws {
        store.rename(try note("One.md"), to: "   ")
        store.rename(try note("One.md"), to: "One")
        XCTAssertTrue(exists("One.md"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".md") }.count, 2)
    }

    /// Typing the name of another note never overwrites it: both stay.
    func testANameAlreadyTakenIsMadeUniqueRatherThanOverwritten() throws {
        store.rename(try note("One.md"), to: "Two")
        XCTAssertTrue(exists("Two.md"))
        XCTAssertTrue(exists("Two 2.md"), "the renamed note took the next free name")
        XCTAssertEqual(try String(contentsOf: dir.appending(path: "Two.md"), encoding: .utf8), "# Two\n")
    }

    func testASlashOrColonCannotMakeAPath() throws {
        store.rename(try note("One.md"), to: "a/b: c")
        XCTAssertTrue(exists("a-b- c.md"))
    }

    func testASectionIsRenamedAndItsNotesGoWithIt() throws {
        let section = try XCTUnwrap(store.allSections.first { $0.name == "Trips" })
        try Data("# Rome\n".utf8).write(to: dir.appending(path: "Trips/Rome.md"))
        store.reload()
        store.rename(try XCTUnwrap(store.allSections.first { $0.name == "Trips" }), to: "Journeys")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "Journeys/Rome.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: section.url.path))
    }
}
