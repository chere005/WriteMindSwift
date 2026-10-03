import AppKit
import XCTest
@testable import WriteMind

/// Sean, 2026-10-03: "cursor behavior around backticks is very weird, fix
/// that". Every anomaly here was found by driving the two editing surfaces
/// headlessly with the keys and clicks that reach them — the markdown pane
/// (`TickPane`) and the rendered page's cell editor (`TickCell`) — and each
/// test failed against the code before this pass unless it says "A GUARD".
///
/// Both are built the way the app builds them (the layout manager's
/// delegate IS the marker hiding, the coordinator IS the text view's
/// delegate), because every one of these lives in the seam between AppKit's
/// own caret movement and the characters the hiding takes the width of.

// MARK: - The two editors, wired as the app wires them

/// The markdown pane: the text view with its folding layout manager, the
/// marker hiding as the layout manager's delegate and the coordinator as
/// the text view's, in a window that is never shown.
final class TickPane {
    let tv = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
    let gutter = NotebookGutter(frame: .zero)
    let insertions: CellInsertions
    let bridge = EditorBridge()
    let coordinator: MarkdownTextView.Coordinator
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
    var window: NSWindow!

    init(_ note: String, width: CGFloat = 400) {
        let folding = FoldingLayoutManager()
        tv.textContainer?.replaceLayoutManager(folding)
        folding.typesetter = FoldingTypesetter(folding.folding)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.font = MarkdownTextView.font
        tv.textContainerInset = MarkdownTextView.inset
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        tv.defaultParagraphStyle = MarkdownTextView.paragraphStyle
        tv.frame.size.width = width
        tv.string = note
        insertions = CellInsertions(frame: tv.bounds)
        bridge.textView = tv
        coordinator = MarkdownTextView(text: .constant(note), documentID: nil, bridge: bridge).makeCoordinator()
        coordinator.gutter = gutter
        coordinator.insertions = insertions
        tv.addSubview(gutter)
        tv.addSubview(insertions)
        tv.delegate = coordinator
        tv.layoutManager?.delegate = coordinator.hiding
        coordinator.hiding.isEnabled = true
        tv.onArmChanged = { [weak insertions] in insertions?.armedOffset = $0 }
        scroll.documentView = tv
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.contentView = scroll
        window.makeFirstResponder(tv)
        coordinator.watchScrolling(of: scroll)
        coordinator.restyle(tv, force: true)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.restyle(tv, force: true)
    }

    /// The debounced restyle a keystroke schedules, let run.
    func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
    func caret(at offset: Int) { tv.setSelectedRange(NSRange(location: offset, length: 0)) }
    func select(_ range: NSRange) { tv.setSelectedRange(range) }
    func key(_ selector: Selector) { tv.doCommand(by: selector) }
    func type(_ characters: String) {
        for ch in characters {
            tv.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }
    var string: String { tv.string }
    var selection: NSRange { tv.selectedRange() }
    var hiding: MarkerHiding { coordinator.hiding }
    var selectedText: String { (tv.string as NSString).substring(with: tv.selectedRange()) }

    /// Where a character is, from the layout as it is NOW.
    func point(of character: Int) -> NSPoint {
        guard let lm = tv.layoutManager, let container = tv.textContainer else { return .zero }
        lm.ensureLayout(for: container)
        let glyph = lm.glyphIndexForCharacter(at: character)
        let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let origin = tv.textContainerOrigin
        return NSPoint(x: origin.x + frag.minX + lm.location(forGlyphAt: glyph).x,
                       y: origin.y + frag.minY)
    }

    /// A double click on a character, with the events AppKit gets: a press,
    /// a release, and the press and release of the second click. The point
    /// is worked out ONCE, from the layout the first click is aimed at.
    func doubleClick(on character: Int) { multiClick(on: character, count: 2) }

    func multiClick(on character: Int, count: Int) {
        let at = point(of: character)
        let inWindow = tv.convert(NSPoint(x: at.x + 2, y: at.y + 8), to: nil)
        func event(_ type: NSEvent.EventType, _ clicks: Int) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clicks, pressure: 1)!
        }
        // The release is queued first: `mouseDown` runs the whole gesture,
        // tracking loop and all, and returns at the release.
        for clicks in 1...count {
            NSApp.postEvent(event(.leftMouseUp, clicks), atStart: false)
            tv.mouseDown(with: event(.leftMouseDown, clicks))
        }
    }

    /// One mouse gesture, with the events AppKit gets: a press at a
    /// character, optionally a drag to another, the release. Both points are
    /// worked out FIRST, from the layout the press is aimed at.
    func mouse(on character: Int, dragTo target: Int? = nil, shift: Bool = false) {
        func place(_ character: Int) -> NSPoint {
            let at = point(of: character)
            return tv.convert(NSPoint(x: at.x + 2, y: at.y + 8), to: nil)
        }
        let down = place(character)
        let up = target.map(place) ?? down
        let flags: NSEvent.ModifierFlags = shift ? [.shift] : []
        func event(_ type: NSEvent.EventType, _ at: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: at, modifierFlags: flags,
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 1)!
        }
        if target != nil { NSApp.postEvent(event(.leftMouseDragged, up), atStart: false) }
        NSApp.postEvent(event(.leftMouseUp, up), atStart: false)
        tv.mouseDown(with: event(.leftMouseDown, down))
    }

    /// A press at a character, a drag THROUGH several others (an event each,
    /// the way a real drag arrives) and the release at the last. Every point
    /// is worked out FIRST, from the layout the press is aimed at. Returns
    /// the selection at each announcement AppKit made of it
    /// (`didChangeSelection`) while the gesture ran.
    @discardableResult
    func drag(from character: Int, through path: [Int]) -> [NSRange] {
        func place(_ character: Int) -> NSPoint {
            let at = point(of: character)
            return tv.convert(NSPoint(x: at.x + 2, y: at.y + 8), to: nil)
        }
        func event(_ type: NSEvent.EventType, _ at: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: at, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 1)!
        }
        let down = place(character)
        let points = path.map(place)
        var announced: [NSRange] = []
        let token = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification,
                                                           object: tv, queue: nil) { [unowned self] _ in
            announced.append(self.selection)
        }
        defer { NotificationCenter.default.removeObserver(token) }
        for point in points { NSApp.postEvent(event(.leftMouseDragged, point), atStart: false) }
        NSApp.postEvent(event(.leftMouseUp, points.last ?? down), atStart: false)
        tv.mouseDown(with: event(.leftMouseDown, down))
        return announced
    }

    /// The text with `|` for the caret, `[ ]` round a selection and ⟨ ⟩
    /// round every character that is hidden — what a failure should show.
    func show() -> String {
        let ns = tv.string as NSString
        var out = ""
        let s = selection
        for i in 0...ns.length {
            if s.length == 0, i == s.location { out += "|" }
            if s.length > 0, i == s.location { out += "[" }
            if s.length > 0, i == NSMaxRange(s) { out += "]" }
            if i < ns.length {
                let ch = ns.substring(with: NSRange(location: i, length: 1))
                let shown = ch == "\n" ? "⏎" : ch
                out += hiding.isHidden(i) ? "⟨\(shown)⟩" : shown
            }
        }
        return out
    }
}

/// The rendered page's cell editor, as `RenderedCell` in `CellUXTests`
/// builds it, in a window that is never shown.
final class TickCell {
    let tv = BlockTextView(usingTextLayoutManager: false)
    let bridge = EditorBridge()
    private(set) var coordinator: BlockEditor.Coordinator!
    var window: NSWindow!
    private(set) var moves: [BlockEditor.Move] = []
    var hiding: MarkerHiding { coordinator.hiding }

    init(_ text: String, language: CodeLanguage? = nil, width: CGFloat = 400) {
        let editor = BlockEditor(text: .constant(text), font: .systemFont(ofSize: 15), bridge: bridge,
                                 focusToken: 0, leavesOnSecondReturn: language == nil,
                                 keepsNewlines: false, language: language,
                                 onMove: { [weak self] move in self?.moves.append(move) })
        coordinator = BlockEditor.Coordinator(editor)
        tv.delegate = coordinator
        tv.layoutManager?.delegate = coordinator.hiding
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.metrics = .cell
        tv.textContainerInset = BlockEditor.Metrics.cell.inset
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.baseFont = editor.font
        tv.isCode = language != nil
        tv.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        tv.string = text
        coordinator.language = language
        coordinator.restyle(tv)
        bridge.textView = tv
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = tv
        window.makeFirstResponder(tv)
    }

    func caret(at offset: Int) { tv.setSelectedRange(NSRange(location: offset, length: 0)) }
    func select(_ range: NSRange) { tv.setSelectedRange(range) }
    func key(_ selector: Selector) { tv.doCommand(by: selector) }
    func type(_ characters: String) {
        for ch in characters {
            tv.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }
    var string: String { tv.string }
    var selection: NSRange { tv.selectedRange() }
    var selectedText: String { (tv.string as NSString).substring(with: tv.selectedRange()) }

    func point(of character: Int) -> NSPoint {
        guard let lm = tv.layoutManager, let container = tv.textContainer else { return .zero }
        lm.ensureLayout(for: container)
        let glyph = lm.glyphIndexForCharacter(at: character)
        let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let origin = tv.textContainerOrigin
        return NSPoint(x: origin.x + frag.minX + lm.location(forGlyphAt: glyph).x,
                       y: origin.y + frag.minY)
    }

    func doubleClick(on character: Int) {
        let at = point(of: character)
        let inWindow = tv.convert(NSPoint(x: at.x + 2, y: at.y + 8), to: nil)
        func event(_ type: NSEvent.EventType, _ count: Int) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                               clickCount: count, pressure: 1)!
        }
        NSApp.postEvent(event(.leftMouseUp, 1), atStart: false)
        tv.mouseDown(with: event(.leftMouseDown, 1))
        NSApp.postEvent(event(.leftMouseUp, 2), atStart: false)
        tv.mouseDown(with: event(.leftMouseDown, 2))
    }

    func show() -> String {
        let ns = tv.string as NSString
        var out = ""
        let s = selection
        for i in 0...ns.length {
            if s.length == 0, i == s.location { out += "|" }
            if s.length > 0, i == s.location { out += "[" }
            if s.length > 0, i == NSMaxRange(s) { out += "]" }
            if i < ns.length {
                let ch = ns.substring(with: NSRange(location: i, length: 1))
                let shown = ch == "\n" ? "⏎" : ch
                out += hiding.isHidden(i) ? "⟨\(shown)⟩" : shown
            }
        }
        return out
    }
}

private let shiftRight = #selector(NSResponder.moveRightAndModifySelection(_:))
private let shiftLeft = #selector(NSResponder.moveLeftAndModifySelection(_:))
private let shiftDown = #selector(NSResponder.moveDownAndModifySelection(_:))
private let optionShiftRight = #selector(NSResponder.moveWordRightAndModifySelection(_:))
private let backspaceKey = #selector(NSResponder.deleteBackward(_:))
private let forwardKey = #selector(NSResponder.deleteForward(_:))
private let upKey = #selector(NSResponder.moveUp(_:))
private let downKey = #selector(NSResponder.moveDown(_:))

// MARK: - Selecting across a hidden backtick

/// ⇧→ could not get past a hidden backtick. The marker hiding shows the
/// paragraph the SELECTION STARTS in, and a selection grows at its other
/// end: the end walked into a line whose markers were still zero-width, and
/// AppKit steps over a run of zero-advance glyphs as one place — so the
/// selection took the backtick (and the `wl:` after it, four characters in
/// one press), and the press after that put it BACK in front of them. The
/// selection could never be pushed through a line with a code span in it.
final class SelectingAcrossBackticksTests: XCTestCase {
    /// ⇧→ `presses` times from `start`; the selection after each press.
    private func walk(_ pane: TickPane, from start: Int, presses: Int) -> [NSRange] {
        pane.caret(at: start)
        return (0..<presses).map { _ in pane.key(shiftRight); return pane.selection }
    }

    private func assertOneAtATime(_ walked: [NSRange], from start: Int, in text: String,
                                  _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let total = (text as NSString).length - start
        for (index, range) in walked.enumerated() {
            let want = NSRange(location: start, length: min(index + 1, total))
            XCTAssertEqual(range, want, "\(message): press \(index + 1)", file: file, line: line)
            if range != want { return }
        }
    }

    func testShiftRightGoesThroughALineThatOpensWithATick() {
        let note = "alpha\n`foo` bar\nomega"
        let pane = TickPane(note)
        assertOneAtATime(walk(pane, from: 0, presses: 21), from: 0, in: note, "line 2 opens with a tick")
    }

    func testShiftRightGoesThroughATickInTheMiddleOfALine() {
        let note = "alpha\nbar `foo` baz\nomega"
        let pane = TickPane(note)
        assertOneAtATime(walk(pane, from: 0, presses: 24), from: 0, in: note, "a tick mid-line")
    }

    func testShiftRightGoesThroughAWolframSpan() {
        // `wl:` is four hidden characters, which AppKit took in one step.
        let note = "alpha\n`wl:1+1` b\nomega"
        let pane = TickPane(note)
        assertOneAtATime(walk(pane, from: 0, presses: 22), from: 0, in: note, "a wl: span")
    }

    func testShiftRightFromTheEndOfALineGoesThroughTheNextOne() {
        let note = "alpha\n`foo` bar\nomega"
        let pane = TickPane(note)
        assertOneAtATime(walk(pane, from: 5, presses: 16), from: 5, in: note, "from the end of line 1")
    }

    func testShiftLeftGoesThroughATickThatEndsTheLineAbove() {
        // The mirror: ⇧← from the start of a line whose line above ends with a
        // hidden tick took the newline and the tick in one press.
        let note = "alpha\n`foo`\nomega"
        let pane = TickPane(note)
        pane.caret(at: 12)
        for press in 1...12 {
            pane.key(shiftLeft)
            XCTAssertEqual(pane.selection, NSRange(location: 12 - press, length: press), "press \(press): \(pane.show())")
            if pane.selection.length != press { return }
        }
        let cell = TickCell(note)
        cell.caret(at: 12)
        for press in 1...12 {
            cell.key(shiftLeft)
            XCTAssertEqual(cell.selection, NSRange(location: 12 - press, length: press), "cell, press \(press): \(cell.show())")
            if cell.selection.length != press { return }
        }
    }

    func testTheLineACommandCrossesIsHiddenAgainOnceItHasRun() {
        // The neighbours are shown for the length of the command only.
        let note = "alpha\n`foo` bar\nomega"
        let pane = TickPane(note)
        pane.caret(at: 0)
        pane.key(shiftRight)
        XCTAssertTrue(pane.hiding.isHidden(6), "line 2 is not where the selection is: \(pane.show())")
        XCTAssertEqual(pane.hiding.revealedParagraphs, [NSRange(location: 0, length: 6)])
    }

    func testOptionShiftRightNeverGivesGroundBack() {
        let note = "alpha\n`foo` bar\nomega"
        let pane = TickPane(note)
        pane.caret(at: 0)
        var end = 0
        for press in 1...8 {
            pane.key(optionShiftRight)
            let now = NSMaxRange(pane.selection)
            XCTAssertGreaterThanOrEqual(now, end, "press \(press) went back from \(end) to \(now)")
            end = now
        }
        XCTAssertEqual(end, (note as NSString).length, "and gets to the end of the note")
    }

    func testTheRenderedCellsSelectionGoesThroughATickToo() {
        // A cell of several lines: the editor hides the markers of the lines
        // the caret is not on, exactly as the pane does.
        let note = "alpha\n`foo` bar\nomega"
        let cell = TickCell(note)
        cell.caret(at: 0)
        for press in 1...21 {
            cell.key(shiftRight)
            XCTAssertEqual(cell.selection, NSRange(location: 0, length: press), "cell, press \(press): \(cell.show())")
            if cell.selection.length != press { return }
        }
    }

    func testWhileItGrowsBothEndsOfASelectionShowTheirMarkers() {
        let note = "`a` x\nmid `b` y\n`c` z"
        let pane = TickPane(note)
        pane.caret(at: 0)
        pane.key(shiftDown)
        pane.key(shiftDown)
        // Line 1's ticks (0, 2), line 2's (10, 12) and line 3's (16, 18).
        XCTAssertFalse(pane.hiding.isHidden(0), "where it started: \(pane.show())")
        XCTAssertFalse(pane.hiding.isHidden(16), "where it is going: \(pane.show())")
        XCTAssertTrue(pane.hiding.isHidden(10), "between them nothing is on the caret's line: \(pane.show())")
    }

    func testTheFirstShiftArrowAfterAMouseSelectionStillAdvances() {
        // A selection made with the mouse can end at the start of a line
        // whose ticks are hidden — the next ⇧→ has to show them first.
        let note = "alpha\n`foo` bar\nomega"
        let pane = TickPane(note)
        pane.select(NSRange(location: 0, length: 6))
        pane.key(shiftRight)
        pane.key(shiftRight)
        XCTAssertEqual(pane.selection, NSRange(location: 0, length: 8), pane.show())
    }

    func testAWholeLineSelectionDoesNotShowTheLineAfterIt() {
        // A GUARD. A triple click takes a line and its newline, so the
        // selection ends at the start of the NEXT line — which is not
        // selected and must not pop its markers out (Sean, 2026-09-20:
        // "the next section shouldn't be highlighted").
        let note = "alpha\n`foo` bar\n`x` omega"
        let pane = TickPane(note)
        pane.select(NSRange(location: 6, length: 10))
        XCTAssertFalse(pane.hiding.isHidden(6), "the line taken shows its own: \(pane.show())")
        XCTAssertTrue(pane.hiding.isHidden(16), "the one after it does not: \(pane.show())")
    }

    func testAKeyboardSelectionThatEndsAtTheStartOfALineShowsIt() {
        // The same range, made with the keys: the caret IS at the start of
        // that line, and the next press steps over its first character.
        let note = "alpha\n`foo` bar\n`x` omega"
        let pane = TickPane(note)
        pane.caret(at: 6)
        pane.key(shiftRight)
        for _ in 0..<9 { pane.key(shiftRight) }
        XCTAssertEqual(pane.selection, NSRange(location: 6, length: 10), pane.show())
        XCTAssertFalse(pane.hiding.isHidden(16), "the caret is at the start of line 3: \(pane.show())")
    }
}

// MARK: - Double click in a line whose markers are hidden

/// The first click of a double click puts the caret in the line, which
/// shows the line's markers, which moves every word in it — and the second
/// click, aimed at the layout the first one saw, landed on the one it left:
/// a double click on "bar" in "`foo` bar" took "foo", and on the "f" of
/// "foo" took the backtick.
final class DoubleClickAcrossBackticksTests: XCTestCase {
    private let note = "alpha\n`foo` bar baz\nomega"

    func testDoubleClickTakesTheWordUnderThePointer() {
        for (word, character) in [("bar", 12), ("baz", 16), ("foo", 8)] {
            let pane = TickPane(note)
            pane.caret(at: 0)
            pane.doubleClick(on: character)
            XCTAssertEqual(pane.selectedText, word, "\(word): \(pane.show())")
        }
    }

    func testDoubleClickOnTheFirstLetterAfterAnOpeningTickTakesTheWordNotTheTick() {
        let pane = TickPane(note)
        pane.caret(at: 0)
        pane.doubleClick(on: 7)
        XCTAssertEqual(pane.selectedText, "foo", pane.show())
    }

    func testTheRenderedCellsDoubleClickAgrees() {
        // A cell of two lines: the caret on the first hides the second's.
        let cell = TickCell("alpha\n`foo` bar baz")
        cell.caret(at: 0)
        cell.doubleClick(on: 12)
        XCTAssertEqual(cell.selectedText, "bar", cell.show())
    }

    // MARK: the layout the pointer was aimed at

    /// A double click on a line the caret is ALREADY IN: click 1 changes
    /// nothing on screen, so click 2 is read against the layout on screen.
    /// Hiding the line "again" put every word the width of its markers to
    /// the left of where the pointer was aimed — double-click the last
    /// letter of "bar" and "baz" was taken (review, 2026-10-03).
    func testDoubleClickOnALineTheCaretIsAlreadyInTakesTheWordUnderThePointer() {
        // 0123456789...  "`foo` bar baz": foo 7-9, bar 12-14, baz 16-18
        for (word, character) in [("foo", 8), ("bar", 12), ("bar", 14), ("baz", 16), ("baz", 18)] {
            let pane = TickPane(note)
            pane.caret(at: 8)
            pane.doubleClick(on: character)
            XCTAssertEqual(pane.selectedText, word, "\(word) at \(character): \(pane.show())")
        }
    }

    func testTheRenderedCellsDoubleClickOnALineTheCaretIsAlreadyInAgrees() {
        let cell = TickCell("alpha\n`foo` bar baz")
        cell.caret(at: 8)
        cell.doubleClick(on: 14)
        XCTAssertEqual(cell.selectedText, "bar", cell.show())
    }

    /// The hidden width in front of the word is five characters for a `wl:`
    /// span and a whole URL for a link, so a short word after one is the
    /// one most easily missed. Both ways in: the caret already in the line,
    /// and arriving from another.
    func testDoubleClickOnAShortWordAfterAMathsSpanTakesIt() {
        // "`wl:x+1` ok go": ok 15-16, go 18-19
        let note = "alpha\n`wl:x+1` ok go\nomega"
        for caret in [10, 0] {
            for (word, character) in [("ok", 15), ("ok", 16), ("go", 18), ("go", 19)] {
                let pane = TickPane(note)
                pane.caret(at: caret)
                pane.doubleClick(on: character)
                XCTAssertEqual(pane.selectedText, word, "caret \(caret), \(word) at \(character): \(pane.show())")
            }
        }
    }

    func testDoubleClickOnAShortWordAfterALinkTakesIt() {
        // "[site](http://example.com) to go": to 33-34, go 36-37
        let note = "alpha\n[site](http://example.com) to go\nomega"
        for caret in [8, 0] {
            for (word, character) in [("to", 33), ("to", 34), ("go", 36), ("go", 37)] {
                let pane = TickPane(note)
                pane.caret(at: caret)
                pane.doubleClick(on: character)
                XCTAssertEqual(pane.selectedText, word, "caret \(caret), \(word) at \(character): \(pane.show())")
            }
        }
    }

    /// The paragraph the caret LEAVES wraps differently with its markers
    /// hidden, so the first click moves the line under it, and the second
    /// is aimed — by the pointer, which has not moved — at where that line
    /// was. It has to be read against the layout the first click saw.
    func testDoubleClickOnALineUnderTheParagraphTheCaretLeavesTakesTheWordUnderThePointer() {
        guard let wrapping = noteWhoseFirstParagraphWrapsWithItsTicks() else {
            return XCTFail("no paragraph wraps differently with its ticks hidden at this width")
        }
        let pane = TickPane(wrapping.note)
        pane.caret(at: 0)
        pane.doubleClick(on: wrapping.target)
        XCTAssertEqual(pane.selectedText, wrapping.word, pane.show())
    }

    /// "`w0x` `w1x` …" as long as it takes to be one line taller with its
    /// ticks showing than hidden; under it a line of plain words to aim at.
    private func noteWhoseFirstParagraphWrapsWithItsTicks() -> (note: String, target: Int, word: String)? {
        for count in 4...40 {
            let spans = (0..<count).map { "`w\($0 % 10)x`" }.joined(separator: " ")
            let note = "\(spans)\nbeta gamma delta\nomega"
            let target = (note as NSString).range(of: "gamma").location + 2
            let probe = TickPane(note)
            probe.caret(at: 0)
            let shown = probe.point(of: target).y
            probe.caret(at: target)
            if probe.point(of: target).y != shown { return (note, target, "gamma") }
        }
        return nil
    }

    func testTripleClickTakesTheLineUnderThePointer() {
        let pane = TickPane("alpha\n`foo` bar baz\n`x` omega")
        pane.caret(at: 0)
        pane.multiClick(on: 12, count: 3)
        XCTAssertEqual(pane.selectedText, "`foo` bar baz\n", pane.show())
        XCTAssertTrue(pane.hiding.isHidden(20), "and the line after it is not shown for it: \(pane.show())")
    }

    func testShiftClickLandsWhereTheEyeAimed() {
        // A GUARD: a click is read against the layout on screen at the
        // press, so a shift-click on a hidden line lands on the character
        // under the pointer — then the line shows its ticks.
        let pane = TickPane(note)
        pane.caret(at: 0)
        pane.mouse(on: 12, shift: true)
        XCTAssertEqual(pane.selection, NSRange(location: 0, length: 12), pane.show())
        XCTAssertFalse(pane.hiding.isHidden(6), "and the end's line shows its ticks once the button is up")
    }

    func testDraggingAcrossAHiddenLineSelectsWhatTheEyeAimedAt() {
        let pane = TickPane(note)
        pane.mouse(on: 2, dragTo: 12)
        XCTAssertEqual(pane.selection, NSRange(location: 2, length: 10), pane.show())
        XCTAssertFalse(pane.hiding.isHidden(6), "the line it ended in shows its ticks once the button is up")
        XCTAssertFalse(pane.hiding.isHidden(0))
    }

    func testDraggingBackwardsAcrossHiddenLinesSelectsWhatTheEyeAimedAt() {
        // The other way round: the moving end is the selection's START, which
        // is what a rule that showed only the start would have shown first.
        // 0-9 "`a` first⏎", 10-23 "`foo` bar baz⏎", 24- "`x` omega": from
        // the "a" of bar (17) up to the "s" of first (7), with the caret on
        // the last line so both of the others are hidden at the press.
        let note = "`a` first\n`foo` bar baz\n`x` omega"
        let pane = TickPane(note)
        pane.caret(at: 28)
        XCTAssertTrue(pane.hiding.isHidden(0) && pane.hiding.isHidden(10), "setup: \(pane.show())")
        pane.mouse(on: 17, dragTo: 7)
        XCTAssertEqual(pane.selection, NSRange(location: 7, length: 10), pane.show())
        XCTAssertFalse(pane.hiding.isHidden(0), "the end it was dragged to shows its ticks once the button is up: \(pane.show())")
        XCTAssertFalse(pane.hiding.isHidden(10), "and so does the one it was pressed in: \(pane.show())")
        XCTAssertTrue(pane.hiding.isHidden(24), "the line it never touched does not: \(pane.show())")
    }

    func testAMouseSelectionIsAnnouncedOnceWhenTheButtonComesUp() {
        // THE PREMISE of there being no rule here for a held button: AppKit
        // posts a selection change only when the gesture ends, so nothing is
        // shown or hidden under a held pointer, whichever way it is dragged
        // (measured, 2026-10-03: five drag events, one announcement, at the
        // release). Were AppKit ever to announce mid-drag, the end under the
        // pointer would show its markers as it was entered and move under
        // it — the fix is then to keep the paragraphs that were showing at
        // the press while the button is down.
        let note = "alpha\n`foo` bar baz\nomega\nlast `x` line"
        for (label, from, path) in [("down", 2, [8, 12, 22, 30]), ("up", 30, [22, 12, 8, 2])] {
            let pane = TickPane(note)
            pane.caret(at: 0)
            let announced = pane.drag(from: from, through: path)
            XCTAssertEqual(announced.count, 1, "\(label): \(announced)")
            XCTAssertEqual(announced.last, pane.selection, "\(label): and it is the whole of it")
            XCTAssertGreaterThan(pane.selection.length, 20, "\(label): the drag went somewhere: \(pane.show())")
        }
    }

    func testDoubleClickOnPlainTextIsUntouched() {
        // A GUARD: no markers, nothing to undo.
        let pane = TickPane("alpha beta gamma\nomega")
        pane.caret(at: 20)
        pane.doubleClick(on: 8)
        XCTAssertEqual(pane.selectedText, "beta")
    }
}

// MARK: - A backtick is one character to delete

/// Backspace on a visible backtick took the OTHER one too — the partner at
/// the far end of the span — because `MarkerDeletion` completes a pair that
/// a delete cuts in half. That is for a SELECTION cut across hidden
/// markers; a key that deletes the one character you can see goes through
/// the same widening and took two. The rendered page's editor had no
/// widening at all, so the two editors disagreed in both directions.
final class DeletingBackticksTests: XCTestCase {
    private func both(_ note: String, caret: Int, _ selector: Selector) -> (pane: String, cell: String) {
        let pane = TickPane(note)
        pane.caret(at: caret)
        pane.key(selector)
        let cell = TickCell(note)
        cell.caret(at: caret)
        cell.key(selector)
        return (pane.string, cell.string)
    }

    func testBackspaceAfterAClosingTickTakesThatTickOnly() {
        let got = both("a `foo` b", caret: 7, backspaceKey)
        XCTAssertEqual(got.pane, "a `foo b")
        XCTAssertEqual(got.cell, "a `foo b")
    }

    func testBackspaceAfterAnOpeningTickTakesThatTickOnly() {
        let got = both("a `foo` b", caret: 3, backspaceKey)
        XCTAssertEqual(got.pane, "a foo` b")
        XCTAssertEqual(got.cell, "a foo` b")
    }

    func testForwardDeleteOnEitherTickTakesThatTickOnly() {
        XCTAssertEqual(both("a `foo` b", caret: 2, forwardKey).pane, "a foo` b")
        XCTAssertEqual(both("a `foo` b", caret: 6, forwardKey).pane, "a `foo b")
        XCTAssertEqual(both("a `foo` b", caret: 2, forwardKey).cell, "a foo` b")
        XCTAssertEqual(both("a `foo` b", caret: 6, forwardKey).cell, "a `foo b")
    }

    func testBackspaceOnAWolframSpansTicksTakesOneAtATime() {
        // `wl:1+1`: the pair is the two ticks, not the `wl:` and the last.
        let got = both("a `wl:1+1` b", caret: 10, backspaceKey)
        XCTAssertEqual(got.pane, "a `wl:1+1 b")
        XCTAssertEqual(got.cell, "a `wl:1+1 b")
        let open = both("a `wl:1+1` b", caret: 3, backspaceKey)
        XCTAssertEqual(open.pane, "a wl:1+1` b")
    }

    func testBackspaceAfterTwoStarsTakesBothStarsAndNotTheCloser() {
        // A marker of several characters is never cut in half — and that is
        // all a key's delete takes of the syntax. (The cell took one star.)
        let got = both("a **foo** b", caret: 4, backspaceKey)
        XCTAssertEqual(got.pane, "a foo** b")
        XCTAssertEqual(got.cell, "a foo** b")
    }

    func testOptionBackspaceBesideATickTakesTheSameInBothEditors() {
        // ⌥⌫ at the start of a line whose line above ends with a span: a
        // word's worth, which is "`" and the line break — in both.
        let note = "alpha\n`foo`\nomega"
        let got = both(note, caret: 12, #selector(NSResponder.deleteWordBackward(_:)))
        XCTAssertEqual(got.pane, got.cell)
        XCTAssertEqual(got.pane, "alpha\n`fooomega")
    }

    func testTypingOverHalfASpanTakesTheOtherTickInBothEditors() {
        // Unchanged for the pane (Sean's own rule, MarkerDeletion: a
        // SELECTION that cuts a pair in half takes the other half); the
        // rendered page's editor never did, and left "xo`".
        let pane = TickPane("a `foo` b")
        pane.select(NSRange(location: 2, length: 3))
        pane.type("x")
        XCTAssertEqual(pane.string, "a xo b")
        let cell = TickCell("a `foo` b")
        cell.select(NSRange(location: 2, length: 3))
        cell.type("x")
        XCTAssertEqual(cell.string, "a xo b")
    }

    func testDeletingASelectionOfHalfASpanTakesTheOtherTickInTheCellToo() {
        let cell = TickCell("a `foo` b")
        cell.select(NSRange(location: 2, length: 3))
        cell.key(backspaceKey)
        XCTAssertEqual(cell.string, "a o b")
    }

    func testACodeCellIsNeverWidened() {
        // A GUARD. Its text is code, not markdown: a backtick in it is a
        // backtick.
        let cell = TickCell("a `b` c", language: .python)
        cell.select(NSRange(location: 2, length: 2))
        cell.key(backspaceKey)
        XCTAssertEqual(cell.string, "a ` c")
    }

    func testTheWolframPrefixIsNotPairedWithTheClosingTick() {
        // `MarkerDeletion` paired the `wl:` marker with the CLOSING tick, so
        // taking the prefix took the tick at the far end and left the
        // opening one — a stray backtick that pairs with the next one and
        // swallows what is between.
        let text = "a `wl:1+1` b"
        let prefix = NSRange(location: 3, length: 3)
        XCTAssertEqual(MarkerDeletion.deletions(for: prefix, in: text), [prefix])
        let ticks = MarkerDeletion.deletions(for: NSRange(location: 9, length: 1), in: text)
        XCTAssertEqual(ticks, [NSRange(location: 9, length: 1), NSRange(location: 2, length: 1)],
                       "a SELECTION of the closing tick takes the opening one")
    }

    func testACaretDeleteDoesNotCompleteAPair() {
        // The rule itself; the keys above are what use it.
        let text = "a `foo` b"
        XCTAssertEqual(MarkerDeletion.deletions(for: NSRange(location: 6, length: 1), in: text,
                                                completingPairs: false),
                       [NSRange(location: 6, length: 1)])
        XCTAssertEqual(MarkerDeletion.deletions(for: NSRange(location: 6, length: 1), in: text).count, 2,
                       "A GUARD: a selection still does")
    }

    func testAFenceLineIsNotAMarkerPair() {
        // The whole of "```python" is one marker run, so any delete that
        // touched part of it was widened to all of it.
        let text = "```python\nx = 1\n```"
        XCTAssertEqual(MarkerDeletion.deletions(for: NSRange(location: 9, length: 1), in: text),
                       [NSRange(location: 9, length: 1)])
        XCTAssertEqual(MarkerDeletion.deletions(for: NSRange(location: 17, length: 1), in: text),
                       [NSRange(location: 17, length: 1)])
    }
}

// MARK: - A fence with no language is code too

/// A bare ``` fence names no language, and `MarkdownPreview.Fence.language`
/// says `.plain` for it — and for a fence naming one the app has no
/// colouring for. The rendered cell editor took only a NAMED language for
/// code, so a plain code cell was styled and hidden as MARKDOWN: its
/// backticks faded and vanished whenever the caret was on another line of
/// the cell, a `#` at the front of a comment disappeared as a heading's
/// does, and none of it was widened when deleted — the same backtick
/// weirdness in a surface the owner named (review, 2026-10-03; Sean:
/// "a plain fenced block with no language is a code cell: its backticks are
/// never hidden or styled as markdown").
final class PlainCodeCellTests: XCTestCase {
    private let code = "echo `date`\n# a comment with `ticks`\nls `pwd` **x**"

    func testNoBacktickOfAPlainCodeCellIsEverHidden() {
        let cell = TickCell(code, language: .plain)
        let length = (code as NSString).length
        for caret in [0, 14, length] {
            cell.caret(at: caret)
            XCTAssertTrue((0..<length).allSatisfy { !cell.hiding.isHidden($0) }, "caret \(caret): \(cell.show())")
        }
        XCTAssertTrue(cell.hiding.furnitureRanges.isEmpty, "and a # is not a heading's furniture")
    }

    func testAPlainCodeCellIsNotStyledAsMarkdown() {
        let cell = TickCell(code, language: .plain)
        let storage = cell.tv.textStorage!
        let text = code as NSString
        let tick = text.range(of: "`").location
        XCTAssertEqual(storage.attribute(.foregroundColor, at: tick, effectiveRange: nil) as? NSColor, .labelColor,
                       "a backtick is not a faded marker")
        let hash = text.range(of: "# a comment").location
        XCTAssertEqual(storage.attribute(.font, at: hash, effectiveRange: nil) as? NSFont, cell.tv.baseFont,
                       "a # is not a heading")
        let stars = text.range(of: "**x**").location + 2
        XCTAssertEqual(storage.attribute(.font, at: stars, effectiveRange: nil) as? NSFont, cell.tv.baseFont,
                       "and ** is not bold")
    }

    func testAPlainCodeCellIsNeverWidened() {
        // The same as the .python guard above, for the language that is none.
        let cell = TickCell("a `b` c", language: .plain)
        cell.select(NSRange(location: 2, length: 2))
        cell.key(backspaceKey)
        XCTAssertEqual(cell.string, "a ` c")
    }

    func testAKeyBesideATickInAPlainCodeCellTakesOneCharacter() {
        let cell = TickCell("a `b` c", language: .plain)
        cell.caret(at: 5)
        cell.key(backspaceKey)
        XCTAssertEqual(cell.string, "a `b c")
    }

    func testAPlainCodeCellKeepsAllOfThisWhenItsTextIsSetFromOutside() {
        // `updateNSView` restyles when the text comes from outside; the cell
        // still reads as code, not as markdown, after it.
        let cell = TickCell("x", language: .plain)
        cell.tv.string = code
        cell.coordinator.restyle(cell.tv)
        XCTAssertTrue((0..<(code as NSString).length).allSatisfy { !cell.hiding.isHidden($0) }, cell.show())
    }

    func testTheMarkdownPanesBareFenceIsCodeToo() {
        // A GUARD: the pane never read the inside of a fence as markdown, so
        // the cell editor now agrees with it.
        let note = "alpha\n```\necho `date`\n# a comment\n```\nomega"
        let pane = TickPane(note)
        pane.caret(at: 0)
        let body = (note as NSString).range(of: "echo `date`\n# a comment")
        XCTAssertTrue((body.location..<NSMaxRange(body)).allSatisfy { !pane.hiding.isHidden($0) }, pane.show())
        XCTAssertTrue(pane.hiding.furnitureRanges.isEmpty)
    }

    func testAProseCellStillHidesItsTicksAndAFencedOneStillIsCode() {
        // GUARDS for both sides of the line this draws.
        let prose = TickCell("alpha\n`foo` bar")
        prose.caret(at: 0)
        XCTAssertTrue(prose.hiding.isHidden(6), prose.show())
        let python = TickCell("x = 1\n`y`", language: .python)
        python.caret(at: 0)
        XCTAssertFalse(python.hiding.isHidden(6), python.show())
    }
}

// MARK: - The fence lines of a code block

/// Backspace in "```python" took the whole line, typing over "yth" replaced
/// the whole line with the letter, and ⌫ at the start of the first line of
/// code (or ⌦ at the end of the fence line) joined that line onto the fence
/// — "```pythonx = 1" — so the first line of the program became the
/// language and the colouring went with it; the same at the closing fence,
/// which stopped being one, and the block swallowed the rest of the note.
final class FenceLineEditingTests: XCTestCase {
    //                  0123456 789...
    private let note = "intro\n\n```python\nx = 1\n```\n\nafter"
    // "```python" is 7…15, its newline 16, "x = 1" 17…21, newline 22, "```" 23…25.

    func testBackspaceInTheLanguageTakesOneCharacter() {
        let pane = TickPane(note)
        pane.caret(at: 16)
        pane.key(backspaceKey)
        XCTAssertEqual(pane.string, "intro\n\n```pytho\nx = 1\n```\n\nafter")
    }

    func testBackspaceAfterAFenceTickTakesThatTickOnly() {
        let pane = TickPane(note)
        pane.caret(at: 8)
        pane.key(backspaceKey)
        XCTAssertEqual(pane.string, "intro\n\n``python\nx = 1\n```\n\nafter")
    }

    func testTypingOverPartOfALanguageKeepsTheRestOfTheLine() {
        let pane = TickPane(note)
        pane.select(NSRange(location: 11, length: 3))
        pane.type("x")
        XCTAssertEqual(pane.string, "intro\n\n```pxon\nx = 1\n```\n\nafter")
    }

    func testBackspaceAtTheStartOfTheFirstLineOfCodeDoesNothing() {
        let pane = TickPane(note)
        pane.caret(at: 17)
        pane.key(backspaceKey)
        XCTAssertEqual(pane.string, note)
        XCTAssertEqual(pane.selection, NSRange(location: 17, length: 0))
    }

    func testForwardDeleteAtTheEndOfTheFenceLineDoesNothing() {
        let pane = TickPane(note)
        pane.caret(at: 16)
        pane.key(forwardKey)
        XCTAssertEqual(pane.string, note)
    }

    func testBackspaceAtTheStartOfTheClosingFenceDoesNotUncloseTheBlock() {
        let pane = TickPane(note)
        pane.caret(at: 23)
        pane.key(backspaceKey)
        XCTAssertEqual(pane.string, note)
        XCTAssertEqual(MarkdownParser.blocks(from: pane.string).count, 3, "intro, the code, after")
    }

    func testForwardDeleteAtTheEndOfTheLastLineOfCodeDoesNothing() {
        let pane = TickPane(note)
        pane.caret(at: 22)
        pane.key(forwardKey)
        XCTAssertEqual(pane.string, note)
    }

    func testTheKeysStillEditTheCodeItself() {
        // A GUARD: only the two line breaks that make the fences are kept.
        let pane = TickPane(note)
        pane.caret(at: 20)
        pane.key(backspaceKey)
        XCTAssertEqual(pane.string, "intro\n\n```python\nx  1\n```\n\nafter")
        pane.caret(at: 18)
        pane.key(forwardKey)
        XCTAssertEqual(pane.string, "intro\n\n```python\nx 1\n```\n\nafter")
    }

    func testAnEmptyFirstLineOfCodeCanStillBeTakenOut() {
        // The newline that ends an EMPTY first line is code's, not the fence's.
        let pane = TickPane("```python\n\nx = 1\n```")
        pane.caret(at: 10)
        pane.key(forwardKey)
        XCTAssertEqual(pane.string, "```python\nx = 1\n```")
    }

    func testAFenceThatNeverClosesStillKeepsItsOpeningBreak() {
        let pane = TickPane("```python\nx = 1")
        pane.caret(at: 10)
        pane.key(backspaceKey)
        XCTAssertEqual(pane.string, "```python\nx = 1")
        pane.caret(at: 15)
        pane.key(backspaceKey)
        XCTAssertEqual(pane.string, "```python\nx = ", "A GUARD: the end of the code is code's")
    }

    func testTheLineBreaksAreOnlyProtectedAsKeyboardDeletes() {
        // A selection that takes one is the user's own choice and goes.
        let pane = TickPane(note)
        pane.select(NSRange(location: 16, length: 2))
        pane.key(backspaceKey)
        XCTAssertEqual(pane.string, "intro\n\n```python = 1\n```\n\nafter")
    }
}

// MARK: - A span with nothing in it is not a span

/// "``" has nothing between its ticks, and the rendered page draws it as
/// two backticks — but the markdown pane read it as an empty span and hid
/// both when the caret left the line: type two backticks, move on, and
/// they were gone. Likewise the first two of a ``` in a sentence, and a
/// backtick typed in front of a span's own.
final class EmptyCodeSpanTests: XCTestCase {
    private func markers(_ source: String) -> [String] {
        let text = source as NSString
        return MarkerHiding.hideable(MarkdownSourceStyle.runs(in: source), in: text).map { text.substring(with: $0) }
    }

    func testTwoTicksWithNothingBetweenThemAreText() {
        XCTAssertEqual(markers("a ``"), [])
        XCTAssertEqual(markers("a `` b"), [])
        XCTAssertEqual(MarkdownSourceStyle.runs(in: "a ``").count, 0)
    }

    func testThreeTicksInASentenceAreText() {
        XCTAssertEqual(markers("a ```"), [])
    }

    func testATickTypedInFrontOfASpanLeavesItAllText() {
        // "a ``foo` b": the rendered page draws every tick of it.
        XCTAssertEqual(markers("a ``foo` b"), [])
        XCTAssertEqual(String(MarkdownInline.attributed("a ``foo` b").characters), "a ``foo` b")
    }

    func testASpanOfOneSpaceIsStillASpan() {
        // A GUARD: "` `" holds something.
        XCTAssertEqual(markers("a ` ` b"), ["`", "`"])
    }

    func testOrdinarySpansAreUntouched() {
        XCTAssertEqual(markers("a `foo` b"), ["`", "`"])
        XCTAssertEqual(markers("a ``fo`o`` b"), ["``", "``"])
        XCTAssertEqual(markers("a `wl:1+1` b"), ["`", "wl:", "`"])
    }

    func testTheSpansOfACellCutNeverIncludeAnEmptyOne() {
        XCTAssertTrue(MarkdownSourceStyle.spans(in: "a `` b").isEmpty)
    }
}

// MARK: - Up and down inside a wrapped cell

/// ↑ and ↓ in the rendered page's editor went to the neighbouring cell
/// whenever the caret was on the first or last LOGICAL line — a paragraph
/// that wraps is one logical line however tall, so the arrows left a
/// wrapped cell from anywhere in it, a long code span's line included.
final class WrappedCellArrowTests: XCTestCase {
    private let long = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen"

    func testUpOnALaterVisualLineStaysInTheCell() {
        let cell = TickCell(long, width: 180)
        cell.caret(at: 60)
        let before = cell.selection.location
        cell.key(upKey)
        XCTAssertTrue(cell.moves.isEmpty, "went to the cell above: \(cell.moves)")
        XCTAssertLessThan(cell.selection.location, before, "and went up a line")
    }

    func testDownOnAnEarlierVisualLineStaysInTheCell() {
        let cell = TickCell(long, width: 180)
        cell.caret(at: 10)
        cell.key(downKey)
        XCTAssertTrue(cell.moves.isEmpty, "went to the cell below: \(cell.moves)")
        XCTAssertGreaterThan(cell.selection.location, 10)
    }

    func testUpOnTheFirstVisualLineLeavesTheCell() {
        // A GUARD.
        let cell = TickCell(long, width: 180)
        cell.caret(at: 10)
        cell.key(upKey)
        XCTAssertEqual(cell.moves, [.up])
    }

    func testDownOnTheLastVisualLineLeavesTheCell() {
        // A GUARD.
        let cell = TickCell(long, width: 180)
        cell.caret(at: (long as NSString).length - 2)
        cell.key(downKey)
        XCTAssertEqual(cell.moves, [.down])
    }

    func testAWrappedCodeSpanIsWalkedLikeAnyOtherWords() {
        let spanned = "one two three four five six `a code span that is long enough to wrap around the cell` end"
        let cell = TickCell(spanned, width: 180)
        cell.caret(at: 60)
        cell.key(upKey)
        XCTAssertTrue(cell.moves.isEmpty)
    }
}

// MARK: - What was already right, pinned

/// Walked on the way to the fixes above and found right, or pinned because
/// the fixes reach them: they stay right.
final class BacktickGuardTests: XCTestCase {
    /// Typing at the four edges of `` `foo` `` and of `**foo**`: outside,
    /// inside, inside, outside — the same in both editors and for both.
    func testTypingAtTheEdgesOfASpanIsTheSameForCodeBoldAndInBothEditors() {
        for (note, open, close) in [("a `foo` b", 1, 1), ("a **foo** b", 2, 2)] {
            let start = 2, end = 2 + open + 3
            for (name, at, inside) in [("before the opener", start, false), ("after the opener", start + open, true),
                                       ("before the closer", end, true), ("after the closer", end + close, false)] {
                let pane = TickPane(note)
                pane.caret(at: at)
                pane.type("x")
                pane.settle()
                let cell = TickCell(note)
                cell.caret(at: at)
                cell.type("x")
                XCTAssertEqual(pane.string, cell.string, "\(note) \(name): the two editors")
                let code = MarkdownSourceStyle.runs(in: pane.string).first {
                    $0.kind == .code || $0.kind == .bold
                }
                let typed = pane.selection.location - 1
                let isIn = code.map { NSLocationInRange(typed, $0.range) } ?? false
                XCTAssertEqual(isIn, inside, "\(note) \(name): the x went \(inside ? "inside" : "outside")")
            }
        }
    }

    func testTypingBackticksOpensAndClosesASpan() {
        let pane = TickPane("a ")
        pane.caret(at: 2)
        pane.type("`foo`")
        pane.settle()
        XCTAssertEqual(pane.string, "a `foo`")
        XCTAssertEqual(MarkdownSourceStyle.runs(in: pane.string).map(\.kind), [.marker, .code, .marker])
    }

    func testThreeBackticksAtTheStartOfALineAreAFenceLine() {
        let pane = TickPane("")
        pane.type("```")
        pane.settle()
        XCTAssertEqual(MarkdownSourceStyle.runs(in: pane.string).map(\.range), [NSRange(location: 0, length: 3)])
        pane.type("python")
        pane.settle()
        XCTAssertEqual(MarkdownSourceStyle.runs(in: pane.string).map(\.range), [NSRange(location: 0, length: 9)])
    }

    func testATickTypedInsideASpanSplitsItWhereTheRendererWouldToo() {
        let pane = TickPane("a `foo` b")
        pane.caret(at: 5)
        pane.type("`")
        pane.settle()
        XCTAssertEqual(pane.string, "a `fo`o` b")
        XCTAssertEqual(MarkdownSourceStyle.runs(in: pane.string).filter { $0.kind == .code }.map(\.range),
                       [NSRange(location: 3, length: 2)])
    }

    func testHomeAndEndInAWrappedSpanGoByTheLineAsLaid() {
        let long = "one two three four five six seven eight nine ten `code span that is long enough to wrap around the line` eleven"
        let pane = TickPane(long + "\nnext", width: 220)
        pane.caret(at: 60)
        for offset in 0..<(long as NSString).length {
            XCTAssertFalse(pane.hiding.isHidden(offset), "the whole paragraph shows its ticks: \(offset)")
        }
        pane.key(#selector(NSResponder.moveToBeginningOfLine(_:)))
        let home = pane.selection.location
        pane.key(#selector(NSResponder.moveToEndOfLine(_:)))
        let end = pane.selection.location
        XCTAssertGreaterThan(home, 0, "Home is the start of the line as laid out, not of the paragraph")
        XCTAssertLessThan(end, (long as NSString).length, "and End its end")
        XCTAssertLessThan(home, end)
    }

    func testUndoPutsAWidenedDeleteBackWhole() {
        // The rendered page's editor widens now: its undo has to take it back.
        for editor in ["pane", "cell"] {
            let note = "a `foo` b"
            if editor == "pane" {
                let pane = TickPane(note)
                pane.select(NSRange(location: 2, length: 3))
                pane.key(backspaceKey)
                XCTAssertEqual(pane.string, "a o b")
                pane.tv.undoManager?.undo()
                XCTAssertEqual(pane.string, note, "pane")
            } else {
                let cell = TickCell(note)
                cell.select(NSRange(location: 2, length: 3))
                cell.key(backspaceKey)
                XCTAssertEqual(cell.string, "a o b")
                cell.tv.undoManager?.undo()
                XCTAssertEqual(cell.string, note, "cell")
            }
        }
    }

    func testUndoPutsASingleTickBack() {
        let pane = TickPane("a `foo` b")
        pane.caret(at: 7)
        pane.key(backspaceKey)
        XCTAssertEqual(pane.string, "a `foo b")
        pane.tv.undoManager?.undo()
        XCTAssertEqual(pane.string, "a `foo` b")
    }

    func testDownArrowWalksIntoAndOutOfACodeBlockLineByLine() {
        // The fence lines are never hidden, and every step lands somewhere.
        let note = "intro\n\n```python\nx = 1\ny = 2\n```\n\nafter"
        let pane = TickPane(note)
        pane.caret(at: 2)
        var seen: [Int] = []
        for _ in 0..<8 {
            pane.key(downKey)
            seen.append(pane.selection.location)
            for offset in [7, 8, 9, 29, 30, 31] { XCTAssertFalse(pane.hiding.isHidden(offset), "fence tick \(offset)") }
        }
        XCTAssertEqual(Array(seen.prefix(6)), [6, 7, 17, 23, 29, 33], "the bar, the fence, two lines of code, the fence, the bar")
    }

    func testReturnAtTheEndOfTheFenceLineStartsTheCodeWithABlankLine() {
        let pane = TickPane("```python\nx = 1\n```")
        pane.caret(at: 9)
        pane.key(#selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(pane.string, "```python\n\nx = 1\n```")
        XCTAssertEqual(MarkdownParser.blocks(from: pane.string).count, 1)
    }

    func testRightArrowWalksTheTicksOfAFenceLineOneAtATime() {
        let pane = TickPane("intro\n\n```python\nx\n```")
        pane.caret(at: 7)
        for press in 1...4 {
            pane.key(#selector(NSResponder.moveRight(_:)))
            XCTAssertEqual(pane.selection.location, 7 + press)
        }
    }

    func testTheCaretNeverRestsInsideAClosedSectionAndASelectionStillWalksThroughIt() {
        let note = "# Open\n\ntext `a` end\n\n# Closed\n\nbody `b` here\n\n# Next\n\nafter `c`"
        let pane = TickPane(note)
        pane.coordinator.collapsed = ["Closed"]
        pane.coordinator.applyFolding(force: true)
        let hidden = NotebookOutline.hiddenRanges(in: note, collapsed: ["Closed"])
        XCTAssertFalse(hidden.isEmpty, "the premise")
        pane.caret(at: 19)
        for press in 1...30 {
            pane.key(#selector(NSResponder.moveRight(_:)))
            let at = pane.selection.location
            XCTAssertFalse(hidden.contains { at > $0.location && at < NSMaxRange($0) }, "press \(press): \(at)")
        }
        // A selection is left as it was made — it takes what is folded with
        // it, one character at a time, and the hidden ticks inside do not
        // stall it.
        pane.caret(at: 19)
        for press in 1...30 {
            pane.key(shiftRight)
            XCTAssertEqual(pane.selection, NSRange(location: 19, length: press), "shift press \(press)")
        }
    }
}
