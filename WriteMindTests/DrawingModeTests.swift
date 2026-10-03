import AppKit
import XCTest
@testable import WriteMind

// DRAWING MODE TURNS ON ONLY WHEN ASKED FOR, AND IS NEVER LEFT ON BEHIND YOU
// (Sean, 2026-10-03: "drawing mode seems to keep turning itself on as i'm
// trying to navigate").
//
// "Drawing mode" is whatever makes a press on the notes into ink or an
// object: the pen, the arrow tool, an armed shape or mark. The tests here
// are the state machine round them — what turns one on, what puts it away,
// and what must never bring one back. The paths found, each with its test:
//
//   * A LAUNCH CAME UP WITH THE PEN (the mode was remembered, and dragged the
//     notes onto the rendered page to show it) — `testALaunchNeverComesUp…`.
//   * ANOTHER NOTE KEPT THE TOOL: a pen, an arrow tool or an armed mark
//     went with Sean to the next note and took its first click —
//     `testSwitchingNotes…`.
//   * A PANE COMING OR GOING — the notes pane put away, the video or the
//     tablet's page shown, the window given to the picture — left it armed
//     for when the notes came back — `testAPaneComingOrGoing…`.
//   * ESC LET GO OF THE PEN AND A SHAPE BUT NOT THE ARROW TOOL —
//     `testEscape…` and `CanvasKeyTests`.
//   * THE TABLET'S NOTEBOOK TARGET was remembered across a launch, so the
//     first ⌘T onto the rendered page made the pen write ink —
//     `testTheTabletsNotebookIsNotRemembered…`.
//   * A DRAWING CELL WAS A PEN OF ITS OWN: in cursor mode a drag, or a nib
//     touching, on a cell's paper drew in it, and the pointer was a pencil
//     over every cell on the page — `DrawingCellModeTests`.

@MainActor
final class DrawingModeLifecycleTests: XCTestCase {
    private var suite: String!
    private var dir: URL!

    override func setUp() {
        super.setUp()
        suite = "WriteMindTests-\(UUID().uuidString)"
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-modes-\(UUID().uuidString)")
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func state() -> AppState { AppState(defaults: UserDefaults(suiteName: suite)!) }

    /// A store with two notes, the first open.
    private func twoNotes() throws -> (store: NoteStore, first: Note.ID, second: Note.ID) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# One\n\nfirst\n".utf8).write(to: dir.appending(path: "One.md"))
        try Data("# Two\n\nsecond\n".utf8).write(to: dir.appending(path: "Two.md"))
        let store = NoteStore(directory: dir)
        let ids = store.notes.map(\.id).sorted()
        let first = try XCTUnwrap(store.selection)
        let second = try XCTUnwrap(ids.first { $0 != first })
        return (store, first, second)
    }

    /// Every way of putting a tool in hand that there is.
    private let tools: [(String, (AppState) -> Void)] = [
        ("the pen", { $0.canvasMode = .pen }),
        ("the arrow tool", { $0.connectActive = true }),
        ("an armed box", { $0.arm(.shape(.rectangle)) }),
        ("an armed tick", { $0.arm(.shape(.check)) }),
        ("an armed arrow line", { $0.arm(.line(start: .none, end: .arrow)) }),
    ]

    // MARK: - A launch

    /// THE MODE WAS REMEMBERED, AND A LAUNCH CAME UP WITH THE PEN DOWN — on
    /// the rendered page, which it had pulled the notes onto to show it.
    /// Nothing Sean did this session had asked for it.
    func testALaunchNeverComesUpWithAToolInHand() {
        let defaults = UserDefaults(suiteName: suite)!
        let first = AppState(defaults: defaults)
        first.canvasMode = .pen
        XCTAssertTrue(first.penActive)

        let launched = AppState(defaults: defaults)
        XCTAssertEqual(launched.canvasMode, .cursor, "a launch came up with the pen down")
        XCTAssertFalse(launched.canvasOwnsPane)
        XCTAssertEqual(launched.mode, .editor, "and the notes were not moved to the rendered page for it")

        // And a value written by an older build is not read either.
        defaults.set("pen", forKey: "canvasMode")
        XCTAssertEqual(AppState(defaults: defaults).canvasMode, .cursor)
        XCTAssertEqual(AppState(defaults: defaults).mode, .editor)
    }

    /// THE TABLET'S NOTEBOOK TARGET IS THE PEN'S OTHER DRAWING MODE: picked,
    /// it makes every touch of the nib on the rendered page into ink. It was
    /// remembered across a launch, so the first ⌘T made the pen write.
    func testTheTabletsNotebookIsNotRememberedAcrossALaunch() {
        let defaults = UserDefaults(suiteName: suite)!
        let first = AppState(defaults: defaults)
        first.writeOn(.notebook)
        XCTAssertEqual(first.tabletTarget, .notebook, "picked on purpose, it holds for the session")

        XCTAssertEqual(AppState(defaults: defaults).tabletTarget, .page,
                       "a launch must not make the pen write in the notebook")
        defaults.set("notebook", forKey: "tabletTarget")
        XCTAssertEqual(AppState(defaults: defaults).tabletTarget, .page, "nor a value an older build left")
    }

    // MARK: - Navigating

    /// ANOTHER NOTE TAKES NOTHING WITH IT. A pen, the arrow tool or a mark
    /// left armed went to the next note, where every click Sean made to find
    /// his place drew something.
    func testSwitchingNotesPutsEveryToolAway() throws {
        let (store, first, second) = try twoNotes()
        let app = state()
        app.watchNotes(of: store)
        for (name, pick) in tools {
            pick(app)
            XCTAssertTrue(app.canvasOwnsPane, "\(name) was not picked")
            store.openTab(second)
            XCTAssertFalse(app.canvasOwnsPane, "\(name) went with him to the next note")
            XCTAssertEqual(app.canvasMode, .cursor)
            XCTAssertNil(app.placing)
            XCTAssertFalse(app.connectActive)
            store.openTab(first)
            XCTAssertFalse(app.canvasOwnsPane, "\(name) came back with the note he left it in")
        }
    }

    /// Closing a tab is a switch of notes as well.
    func testClosingTheOpenNotePutsTheToolAwayToo() throws {
        let (store, first, second) = try twoNotes()
        store.openTab(second)
        store.openTab(first)
        let app = state()
        app.watchNotes(of: store)
        app.arm(.shape(.check))
        store.closeTab(first)
        XCTAssertNil(app.placing)
        XCTAssertFalse(app.canvasOwnsPane)
    }

    /// The same note again is no switch, and neither is a change inside it.
    func testStayingInTheNoteLeavesTheToolAlone() throws {
        let (store, first, _) = try twoNotes()
        let app = state()
        app.watchNotes(of: store)
        app.arm(.shape(.check))
        store.openTab(first)
        store.text += "typed\n"
        XCTAssertEqual(app.placing, .shape(.check), "nothing was left")
    }

    /// A PANE COMING OR GOING IS A WAY OFF THE PAGE: the notes pane put
    /// away, the video shown or hidden (⌘Y), the window given to the
    /// picture, a tablet picked or let go — each left the tool armed for
    /// the first click when the notes came back.
    func testAPaneComingOrGoingPutsEveryToolAway() {
        let changes: [(String, (AppState) -> Void)] = [
            ("the notes pane going", { $0.showEditor = false }),
            ("the video pane going", { $0.showCamera = false }),
            ("the video pane coming", { $0.showCamera = true }),
            ("the whole window given to the picture", { $0.cameraFullWindow = true }),
            ("a tablet picked", { $0.follow(tabletPicked: true) }),
        ]
        for (name, change) in changes {
            for (tool, pick) in tools {
                let app = state()
                // The video starts shown; the pane coming is a pane that went.
                if name == "the video pane coming" { app.showCamera = false }
                pick(app)
                XCTAssertTrue(app.canvasOwnsPane, "\(tool) was not picked")
                change(app)
                XCTAssertFalse(app.canvasOwnsPane, "\(tool) was left on by \(name)")
            }
        }
        // Not a switch: the same answer again, and the sidebar, which is not
        // a pane the notes are drawn beside.
        let app = state()
        app.arm(.shape(.check))
        app.showCamera = true
        app.follow(tabletPicked: false)
        app.showSidebar.toggle()
        XCTAssertEqual(app.placing, .shape(.check), "nothing changed that is a way off the page")
    }

    /// The markdown view is the other pane: ⌘T onto it puts every tool
    /// down, and ⌘T back does not pick one up.
    func testMarkdownAndBackNeverPicksAToolBackUp() {
        for (tool, pick) in tools {
            let app = state()
            pick(app)
            XCTAssertEqual(app.mode, .preview, "\(tool) draws on the rendered page")
            app.toggleMode()
            XCTAssertEqual(app.mode, .editor)
            XCTAssertFalse(app.canvasOwnsPane, "\(tool) went on into the markdown view")
            app.toggleMode()
            XCTAssertEqual(app.mode, .preview)
            XCTAssertFalse(app.canvasOwnsPane, "\(tool) came back with the rendered page")
        }
    }

    /// A mark STAYS armed while it is used — Sean, 2026-10-02: "after
    /// placing mark like check mark, i shouldn't leave place mode" — and
    /// nothing a mark going down does lets go of it. That rule is as it was;
    /// only leaving ends it.
    func testAMarkStaysArmedThroughEverythingItsOwnUseDoes() {
        let app = state()
        app.arm(.shape(.check))
        app.drawingChanged(steps: 1)
        app.noteTyped()
        app.inkedNote(above: 0)
        app.drawingChanged(steps: 2)
        XCTAssertEqual(app.placing, .shape(.check))
        XCTAssertTrue(app.canvasOwnsPane)
        XCTAssertTrue(app.marksLit)
    }

    // MARK: - Esc

    /// Esc puts away whatever tool is in hand — the pen, the arrow tool, an
    /// armed shape or mark — and is taken only when there was one, so with
    /// none up it is the notebook's.
    func testEscapePutsAwayWhateverToolIsInHand() {
        let app = state()
        XCTAssertFalse(app.escapeTool(), "nothing in hand: the key is not ours")
        for (name, pick) in tools {
            pick(app)
            XCTAssertTrue(app.escapeTool(), "Esc did not take \(name)")
            XCTAssertFalse(app.canvasOwnsPane, "Esc left \(name) on")
            XCTAssertFalse(app.escapeTool(), "a second Esc has nothing to put away")
        }
    }

    // MARK: - Only an explicit act turns one on

    /// THE WHOLE LIST OF WAYS A TOOL GOES ON, read off the sources, so a new
    /// path that turns one on by itself fails here: the pen button and ⌘P
    /// (`togglePen`), a palette tile (`arm`) and the arrow tool's own switch
    /// (a `Toggle` on `connectActive`, which is no assignment). Outside
    /// those, everything that writes the tool state writes it OFF.
    func testNothingTurnsAToolOnButTheButtonsThatAskForIt() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "WriteMind", directoryHint: .isDirectory)
        let sources = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
        XCTAssertGreaterThan(sources.count, 50)
        let assignment = try NSRegularExpression(
            pattern: #"\b(canvasMode|connectActive|placing)\s*=\s*([^=\n][^\n]*)$"#)
        let allowed: Set<String> = [
            "func togglePen() { canvasMode = penActive ? .cursor : .pen }",
            "placing = placing == placement ? nil : placement",
        ]
        var writers: [String] = []
        for file in sources {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, raw) in lines.enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("//") else { continue }
                let range = NSRange(line.startIndex..., in: line)
                guard let match = assignment.firstMatch(in: line, range: range),
                      let name = Range(match.range(at: 1), in: line),
                      let valueRange = Range(match.range(at: 2), in: line) else { continue }
                // `let placing = …` and `var placing = …` make a name; they write no tool.
                let before = line[..<name.lowerBound].trimmingCharacters(in: .whitespaces)
                guard !before.hasSuffix("let"), !before.hasSuffix("var") else { continue }
                var value = line[valueRange].trimmingCharacters(in: .whitespaces)
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: " },)"))
                let off = ["nil", "false", ".cursor"].contains(value)
                if !off && !allowed.contains(line) { writers.append("\(file.lastPathComponent):\(index + 1): \(line)") }
            }
        }
        XCTAssertEqual(writers, [], "a tool is turned on by something that is not a button or a key")
    }

    /// And the one switch that turns a tool on without an assignment is the
    /// arrow tool's own toggle, in the shapes palette.
    func testTheArrowToolIsSwitchedOnOnlyByItsOwnToggle() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "WriteMind", directoryHint: .isDirectory)
        let sources = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
        var bindings: [String] = []
        for file in sources {
            for (index, line) in (try String(contentsOf: file, encoding: .utf8)).components(separatedBy: "\n").enumerated()
            where line.contains("$appState.connectActive") {
                bindings.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(bindings.map { String($0.split(separator: ":")[0]) }, ["ShapeMenu.swift"])
    }

    // MARK: - Seeing it

    /// THE FOOTER NAMES EVERY TOOL IN HAND, in the one place that says why a
    /// pane swallows its clicks. The pen and an armed shape were named; THE
    /// ARROW TOOL AND THE TABLET'S WRITING IN THE NOTEBOOK WERE NOT — a drag
    /// that drew an arrow, or a nib that left ink, with nothing on the pane to
    /// say it was on.
    func testTheFooterNamesEveryToolInHandAndNothingElse() {
        let app = state()
        XCTAssertEqual(app.toolLines, [], "nothing in hand, nothing said")

        app.canvasMode = .pen
        XCTAssertEqual(app.toolLines.map(\.words), ["Pen: every drag draws, Esc to stop"])
        app.canvasMode = .cursor
        XCTAssertEqual(app.toolLines, [])

        app.connectActive = true
        XCTAssertEqual(app.toolLines.map(\.words), ["Arrow tool: drag from one thing to another, Esc to stop"],
                       "the arrow tool took every drag and said nothing")
        app.connectActive = false

        app.arm(.shape(.rectangle))
        XCTAssertEqual(app.toolLines.map(\.words), ["Rectangle: every drag draws one, Esc to stop"])
        app.arm(.shape(.check))
        XCTAssertEqual(app.toolLines.map(\.words), ["Check Mark: every click puts one down, Esc to stop"])
        app.putToolsAway()
        XCTAssertEqual(app.toolLines, [])
    }

    /// The tablet's pen writing in the notebook is a mode of its own, and it
    /// is named while it is live: a tablet is the input, the notebook is its
    /// target, and the rendered page is up for it to write on.
    func testTheTabletWritingInTheNotebookIsNamedWhileItIsLive() {
        let app = state()
        app.follow(tabletPicked: true)
        XCTAssertEqual(app.toolLines, [], "the page is the target: the notes' footer has nothing to say")
        app.writeOn(.notebook)
        XCTAssertEqual(app.mode, .preview)
        XCTAssertEqual(app.toolLines.map(\.words), ["Tablet pen: writing on the notebook"])

        app.toggleMode()
        XCTAssertEqual(app.toolLines, [], "over the markdown view the pen is a pointer, and nothing is written")
        app.toggleMode()
        XCTAssertEqual(app.toolLines.map(\.words), ["Tablet pen: writing on the notebook"])

        app.follow(tabletPicked: false)
        XCTAssertEqual(app.toolLines, [], "no tablet is the input")
    }

    /// A symbol that does not exist draws as nothing at all.
    func testEveryLineHasASymbolThatExists() {
        let app = state()
        app.follow(tabletPicked: true)
        app.writeOn(.notebook)
        var lines = app.toolLines
        app.canvasMode = .pen
        lines += app.toolLines
        app.connectActive = true
        lines += app.toolLines
        app.arm(.shape(.check))
        lines += app.toolLines
        XCTAssertGreaterThanOrEqual(lines.count, 4)
        for line in lines {
            XCTAssertNotNil(NSImage(systemSymbolName: line.symbol, accessibilityDescription: nil),
                            "\(line.words) is drawn with \(line.symbol)")
        }
    }
}
