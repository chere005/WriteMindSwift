import AppKit
import XCTest
@testable import WriteMind

/// The list the + on the insertion bar brings up: the app's own names, and
/// nothing invented (Sean, 2026-09-20: "pressing the + button on that bar
/// should bring up the list of style types that the next input will create
/// a cell the type of").
final class CellTypeListTests: XCTestCase {
    func testTheListIsTheAppsOwnVocabulary() {
        XCTAssertEqual(CellTypes.all.map(\.name),
                       ["Body Text",
                        "Title", "Chapter", "Author", "Section", "Subsection", "Subsubsection",
                        "Dots List", "Dashes List", "Numbered List", "To-do List", "Quote",
                        "Code Block",
                        "Drawing"])
    }

    func testTheLadderIsSixDeepAndBodyTextIsNotOneOfItsRungs() {
        // Six headings, his naming (AGENTS.md), and "Body Text" at the top
        // as the plain paragraph every bar starts out as rather than as a
        // seventh rung of the ladder.
        let ladder = CellTypes.all.filter { if case .heading = $0 { return true } else { return false } }
        XCTAssertEqual(ladder.count, 6)
        XCTAssertEqual(CellTypes.all.first, .text)
        XCTAssertFalse(ladder.contains(.heading(.body)))
    }

    func testATableIsNotOnTheListBecauseThereAreNoTables() {
        // The feature came out whole on 2026-09-20 and will be rebuilt.
        XCTAssertFalse(CellTypes.all.map(\.name).contains { $0.localizedCaseInsensitiveContains("table") })
    }

    func testTheGroupsAreTheSameListWithSeparatorsBetweenThem() {
        XCTAssertEqual(CellTypes.groups.flatMap { $0 }, CellTypes.all)
        XCTAssertEqual(CellTypes.groups.count, 5)
        // The one cell that is not words, in a group of its own, last.
        XCTAssertEqual(CellTypes.groups.last, [.drawing])
    }

    /// Chosen on the +, a drawing opens there and then: its next input is
    /// a stroke, and a character waited for would be typed onto its line.
    /// Every other kind waits on the bar for the next thing typed, as it
    /// always has (Sean, 2026-09-20: "the next input will create a cell the
    /// type of").
    func testOnlyTheDrawingOpensAtOnce() {
        XCTAssertEqual(CellTypes.all.filter(\.opensAtOnce), [.drawing])
        XCTAssertFalse(Evaluator.allCases.contains { CellTypes.Kind.evaluation($0).opensAtOnce })
    }

    /// The menu both panes pop at the +. Nothing here can prove what it
    /// looks like on screen; what it can prove is that every entry carries
    /// the kind it names and that the tick is beside the one in hand — the
    /// two ways a menu silently does the wrong thing.
    func testTheMenuCarriesTheKindItNamesAndTicksTheOneInHand() {
        let menu = CellTypeMenu.menu(current: .quote) { _ in }
        let items = menu.items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(items.map(\.title), CellTypes.all.map(\.name))
        XCTAssertEqual(items.map { $0.representedObject as? CellTypes.Kind }, CellTypes.all)
        XCTAssertEqual(items.filter { $0.state == .on }.map(\.title), ["Quote"])
        XCTAssertEqual(menu.items.filter(\.isSeparatorItem).count, CellTypes.groups.count - 1)
        XCTAssertTrue(items.allSatisfy { $0.target != nil && $0.action != nil })
    }

    func testPickingFromTheMenuHandsBackThatKind() {
        var picked: [CellTypes.Kind] = []
        let menu = CellTypeMenu.menu(current: .text) { picked.append($0) }
        for item in menu.items where !item.isSeparatorItem {
            guard let action = item.action else { continue }
            _ = (item.target as? NSObject)?.perform(action, with: item)
        }
        XCTAssertEqual(picked, CellTypes.all)
    }
}

/// What a chosen kind does to the cell a seam opens. Pure, and shared: the
/// markdown pane and the rendered page both open their cell through this.
final class CellTypeOpeningTests: XCTestCase {
    private let note = "First cell\n\nSecond cell"

    private func typed(_ kind: CellTypes.Kind, _ written: String = "x",
                       at offset: Int = 12, in markdown: String? = nil) -> String {
        CellTypes.open(kind, writing: written, in: markdown ?? note, at: offset).markdown
    }

    // MARK: - A character typed at the bar

    func testTheDefaultIsStillAPlainParagraph() {
        // Nothing about an ordinary click on the bar changes (Sean,
        // 2026-09-19: "default is always just text").
        XCTAssertEqual(typed(.text), "First cell\n\nx\n\nSecond cell")
    }

    func testEachRungOfTheLadderWritesItsOwnMarker() {
        XCTAssertEqual(typed(.heading(.title)), "First cell\n\n# x\n\nSecond cell")
        XCTAssertEqual(typed(.heading(.header)), "First cell\n\n## x\n\nSecond cell")
        XCTAssertEqual(typed(.heading(.section)), "First cell\n\n### x\n\nSecond cell")
        XCTAssertEqual(typed(.heading(.authorSubheader)), "First cell\n\n###### x\n\nSecond cell")
    }

    func testTheThreeListsAndTheQuote() {
        XCTAssertEqual(typed(.list(.dots)), "First cell\n\n- x\n\nSecond cell")
        XCTAssertEqual(typed(.list(.dashes)), "First cell\n\n* x\n\nSecond cell")
        XCTAssertEqual(typed(.list(.numbered)), "First cell\n\n1. x\n\nSecond cell")
        XCTAssertEqual(typed(.quote), "First cell\n\n> x\n\nSecond cell")
    }

    func testACodeCellTakesTheCharacterInSIDEItsFences() {
        // The one kind that is not a prefix: the character typed at the bar
        // is the first line of the code, not a word in front of a block.
        XCTAssertEqual(typed(.code(.plain)), "First cell\n\n```\nx\n```\n\nSecond cell")
    }

    /// ⌘9 AT A BAR MAKES THE CELL THERE (Sean, 2026-09-22: "make sure if
    /// the input cursor is horizontal, hitting cmd+9 puts a new
    /// evaluation cell at that position"). It is a fenced block like the
    /// Insert menu's, with the info string that makes the note run it.
    func testAnEvaluationCellIsMadeAtTheBarWithItsOwnFence() {
        XCTAssertEqual(typed(.evaluation(.python)),
                       "First cell\n\n```eval python\nx\n```\n\nSecond cell")
        XCTAssertEqual(typed(.evaluation(.wolfram)),
                       "First cell\n\n```eval wl\nx\n```\n\nSecond cell")
        for evaluator in Evaluator.allCases {
            let opened = CellTypes.open(.evaluation(evaluator), writing: "x", in: note, at: 12)
            let made = MarkdownParser.positioned(from: opened.markdown)[1]
            guard case .code(let language, _) = made.block else {
                return XCTFail("\(evaluator.title) did not make a fenced cell")
            }
            XCTAssertTrue(Evaluator.isEvaluation(fence: language),
                          "\(evaluator.title) made a cell the note will not run")
            XCTAssertEqual(Evaluator.from(fence: language), evaluator)
            XCTAssertEqual(made.range, opened.cell, "and it is the cell the caret is in")
        }
    }

    /// The + on the bar offers what it always did: an evaluation cell is
    /// made by its key, not from that list, so the three environments do
    /// not triple the menu.
    func testTheEvaluationKindIsNotOnThePlusMenu() {
        XCTAssertFalse(CellTypes.all.contains { if case .evaluation = $0 { return true } else { return false } })
    }

    // MARK: - A drawing cell

    /// The line on the empty line `insertBlock` made, a blank line either
    /// side, and the caret at the end of it — at a bar, at the note's end,
    /// and in a note with nothing in it.
    func testADrawingIsItsLineWithTheCaretAtTheEnd() {
        let id = UUID()
        let line = DrawingCells.line(id)
        let length = (line as NSString).length
        XCTAssertEqual(line, "![](_drawings/cells/\(id.uuidString).png)")

        let atBar = CellTypes.open(.drawing, in: note, at: 12, minting: id)
        XCTAssertEqual(atBar.markdown, "First cell\n\n\(line)\n\nSecond cell")
        XCTAssertEqual(atBar.caret, 12 + length)
        XCTAssertEqual(atBar.cell, NSRange(location: 12, length: length))

        let atEnd = CellTypes.open(.drawing, in: note, at: (note as NSString).length, minting: id)
        XCTAssertEqual(atEnd.markdown, "First cell\n\nSecond cell\n\n\(line)")
        XCTAssertEqual(atEnd.caret, (atEnd.markdown as NSString).length)

        let alone = CellTypes.open(.drawing, in: "", at: 0, minting: id)
        XCTAssertEqual(alone.markdown, line)
        XCTAssertEqual(alone.caret, length)
        XCTAssertEqual(MarkdownParser.blocks(from: alone.markdown), [.drawing(id: id, alt: "")])
    }

    func testADrawingAddsExactlyOneDrawingCellWhereverTheBarIs() {
        let notes = ["", "First cell\n\nSecond cell", "# Title\n\nBody\n\n- one\n- two",
                     "baz\n" + String(repeating: "\n", count: 10) + "# asdf", "Only cell", "Only cell\n"]
        for note in notes {
            let before = MarkdownParser.blocks(from: note)
            let seams = MarkdownPreview.seams(
                rows: MarkdownParser.positioned(from: note).map { (id: $0.range.location, height: CGFloat(30)) },
                noteLength: (note as NSString).length, pageHeight: 600)
            for (index, seam) in seams.enumerated() {
                let id = UUID()
                var wanted = before
                wanted.insert(.drawing(id: id, alt: ""), at: index)
                XCTAssertEqual(MarkdownParser.blocks(from: CellTypes.open(.drawing, in: note, at: seam.offset,
                                                                          minting: id).markdown),
                               wanted, "seam \(index) of \(note.debugDescription)")
            }
        }
    }

    func testTheCellIsReallyOfThatKindAndTheNeighboursAreUntouched() {
        let wanted: [CellTypes.Kind: MarkdownBlock] = [
            .heading(.section): .heading(level: 3, text: "x"),
            .list(.dots): .bullets(["x"]),
            .list(.dashes): .dashes(["x"]),
            .list(.numbered): .numbered(["x"]),
            .quote: .quote("x"),
            .code(.plain): .code(language: nil, body: "x"),
            .text: .paragraph("x"),
        ]
        for (kind, block) in wanted {
            let opened = CellTypes.open(kind, writing: "x", in: note, at: 12)
            XCTAssertEqual(MarkdownParser.blocks(from: opened.markdown),
                           [.paragraph("First cell"), block, .paragraph("Second cell")],
                           "\(kind.name)")
        }
    }

    // MARK: - Return at the bar, with nothing typed

    func testReturnOpensAnEmptyCellOfTheChosenKind() {
        // The marker goes in on its own and the caret lands after it, so
        // the cell IS that kind before a word is in it.
        XCTAssertEqual(typed(.list(.dots), ""), "First cell\n\n- \n\nSecond cell")
        XCTAssertEqual(typed(.quote, ""), "First cell\n\n> \n\nSecond cell")
        XCTAssertEqual(typed(.heading(.title), ""), "First cell\n\n# \n\nSecond cell")
        XCTAssertEqual(typed(.code(.plain), ""), "First cell\n\n```\n\n```\n\nSecond cell")
        XCTAssertEqual(typed(.text, ""), "First cell\n\n\n\nSecond cell")
    }

    func testTheCaretIsWhereTheWordsGo() {
        // After the marker, and between the fences — not at the top of the
        // cell and not after the closing fence.
        XCTAssertEqual(CellTypes.open(.list(.dots), in: note, at: 12).caret, 14)
        XCTAssertEqual(CellTypes.open(.heading(.section), in: note, at: 12).caret, 16)
        XCTAssertEqual(CellTypes.open(.code(.plain), in: note, at: 12).caret, 16)
        XCTAssertEqual(CellTypes.open(.text, in: note, at: 12).caret, 12)
    }

    // MARK: - The cell the page opens for typing

    func testTheCellRangeIsTheWholeOfTheNewCell() {
        XCTAssertEqual(CellTypes.open(.list(.dots), writing: "x", in: note, at: 12).cell,
                       NSRange(location: 12, length: 3))
        XCTAssertEqual(CellTypes.open(.code(.plain), writing: "x", in: note, at: 12).cell,
                       NSRange(location: 12, length: 9))
        XCTAssertEqual(CellTypes.open(.text, writing: "x", in: note, at: 12).cell,
                       NSRange(location: 12, length: 1))
        // An empty plain cell is a run of blank lines with no length at all.
        XCTAssertEqual(CellTypes.open(.text, in: note, at: 12).cell,
                       NSRange(location: 12, length: 0))
    }

    // MARK: - Every seam of every note

    func testAChosenKindAddsExactlyOneCellOfThatKindWhereverTheBarIs() {
        // The same invariant the plain opening keeps, with a kind chosen:
        // one more cell, of the kind that was picked, at the seam's own
        // index, and the rest of the note untouched.
        let notes = ["",
                     "First cell\n\nSecond cell",
                     "# Title\n\nBody\n\n- one\n- two",
                     "baz\n" + String(repeating: "\n", count: 10) + "# asdf",
                     "Only cell",
                     "Only cell\n"]
        let kinds: [(CellTypes.Kind, MarkdownBlock)] = [
            (.heading(.section), .heading(level: 3, text: "x")),
            (.list(.dots), .bullets(["x"])),
            (.quote, .quote("x")),
            (.code(.plain), .code(language: nil, body: "x")),
        ]
        for note in notes {
            let before = MarkdownParser.blocks(from: note)
            let seams = MarkdownPreview.seams(
                rows: MarkdownParser.positioned(from: note).map { (id: $0.range.location, height: CGFloat(30)) },
                noteLength: (note as NSString).length, pageHeight: 600)
            for (index, seam) in seams.enumerated() {
                for (kind, block) in kinds {
                    let opened = CellTypes.open(kind, writing: "x", in: note, at: seam.offset)
                    var wanted = before
                    wanted.insert(block, at: index)
                    XCTAssertEqual(MarkdownParser.blocks(from: opened.markdown), wanted,
                                   "\(kind.name) at seam \(index) of \(note.debugDescription)")
                }
            }
        }
    }
}

/// The ladder on a line with nothing on it. ⌘1 over a selection leaves the
/// blank lines inside it alone, and must go on doing so; a cell that has
/// only just been opened is blank and still has to become what was chosen.
final class HeadingOnAnEmptyLineTests: XCTestCase {
    func testALadderOverASelectionStillLeavesItsBlankLinesAlone() {
        let text = "one\n\ntwo"
        let edit = MarkdownFormatting.setHeading(text: text, selection: NSRange(location: 0, length: 8),
                                                 level: .title)
        XCTAssertEqual(edit.replacement, "# one\n\n# two")
    }

    func testACaretOnABlankLineIsLeftAloneUnlessTheOpeningAsks() {
        let text = "one\n\ntwo"
        let left = MarkdownFormatting.setHeading(text: text, selection: NSRange(location: 4, length: 0),
                                                 level: .title)
        XCTAssertEqual(left.replacement, "\n", "the blank line keeps its shape")
        let marked = MarkdownFormatting.setHeading(text: text, selection: NSRange(location: 4, length: 0),
                                                   level: .title, evenIfEmpty: true)
        XCTAssertEqual(marked.replacement, "# \n")
        XCTAssertEqual(marked.selection, NSRange(location: 6, length: 0), "the caret is after the marker")
    }
}

/// A blank line inside a cell is not a space between two.
final class BlankLineInsideACellTests: XCTestCase {
    func testTheEmptyLineInACodeCellArmsNoBar() {
        // The caret goes there the moment the + opens an empty Code Block,
        // and a bar armed over it would take the caret off the page — the
        // line is the note's own content, the way the middle of a run of
        // blank lines is.
        let note = "First cell\n\n```\n\n```\n\nSecond cell"
        XCTAssertNil(CellSeams.arm(caret: NSRange(location: 16, length: 0), in: note, current: nil))
        // The seams either side of the block still answer.
        XCTAssertEqual(CellSeams.arm(caret: NSRange(location: 11, length: 0), in: note, current: nil), 12)
        XCTAssertEqual(CellSeams.arm(caret: NSRange(location: 21, length: 0), in: note, current: nil), 22)
    }
}

/// The bar in the markdown pane, with a kind chosen on it — end to end
/// through the text view, which is where the two have to meet.
final class ArmedTypeTests: XCTestCase {
    private func armed(_ text: String, at offset: Int, as kind: CellTypes.Kind) -> PasteAwareTextView {
        let view = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 800))
        view.string = text
        view.setSelectedRange(NSRange(location: offset, length: 0))
        view.armedSeam = offset
        view.armedType = kind
        return view
    }

    private func type(_ character: String, in view: PasteAwareTextView) {
        view.insertText(character, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func testTypingAtABarSetToSectionMakesASectionCell() {
        let view = armed("First cell\n\nSecond cell", at: 12, as: .heading(.section))
        type("x", in: view)
        XCTAssertEqual(view.string, "First cell\n\n### x\n\nSecond cell")
        XCTAssertEqual(view.selectedRange().location, 17, "the caret is after what was typed")
    }

    func testReturnAtABarSetToACodeBlockOpensOneWithTheCaretInside() {
        let view = armed("First cell\n\nSecond cell", at: 12, as: .code(.plain))
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(view.string, "First cell\n\n```\n\n```\n\nSecond cell")
        XCTAssertEqual(view.selectedRange().location, 16)
    }

    func testTheChoiceGoesWithTheBarAndTheNextOneIsPlainTextAgain() {
        let view = armed("First cell\n\nSecond cell", at: 12, as: .quote)
        view.armedSeam = 0
        XCTAssertEqual(view.armedType, .text, "a seam armed afresh is plain text")
        view.armedType = .quote
        view.armedSeam = nil
        XCTAssertEqual(view.armedType, .text, "and so is the pane with no bar up at all")
    }

    func testTheKindIsSpentWhenTheCellIsOpened() {
        let view = armed("First cell\n\nSecond cell", at: 12, as: .list(.dots))
        type("x", in: view)
        XCTAssertEqual(view.string, "First cell\n\n- x\n\nSecond cell")
        XCTAssertNil(view.armedSeam)
        XCTAssertEqual(view.armedType, .text)
        // And the next character is an ordinary one, in the cell just made.
        type("y", in: view)
        XCTAssertEqual(view.string, "First cell\n\n- xy\n\nSecond cell")
    }

    func testEscapeAtABarWithAKindChosenWritesNothingAtAll() {
        let view = armed("First cell\n\nSecond cell", at: 12, as: .heading(.title))
        view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(view.string, "First cell\n\nSecond cell")
        XCTAssertNil(view.armedSeam)
        XCTAssertEqual(view.armedType, .text)
    }
}

/// The same bar on the rendered page: one list, one result.
final class PreviewArmedTypeTests: XCTestCase {
    private let note = "First cell\n\nSecond cell"

    func testBothPanesOpenTheSameCellForTheSameChoice() {
        let plain = CellTypes.open(.text, writing: "x", in: note, at: 12).markdown
        // A kind that opens at once never waits on the bar for a character;
        // what it opens is below.
        for kind in CellTypes.all where !kind.opensAtOnce {
            let page = MarkdownPreview.opened(.write("x"), as: kind, at: 12, in: note)
            let pane = CellTypes.open(kind, writing: "x", in: note, at: 12)
            XCTAssertEqual(page?.markdown, pane.markdown, "\(kind.name)")
            // And the choice reached the note at all: every kind but the
            // default writes something a plain paragraph does not.
            guard kind != .text else { continue }
            XCTAssertNotEqual(page?.markdown, plain, "\(kind.name) is not a plain paragraph")
        }
    }

    /// What the page writes when Drawing is chosen on its +: the cell, as
    /// the markdown pane writes it, with a fresh id.
    func testTheRenderedPageOpensADrawingAsTheMarkdownPaneDoes() throws {
        let opened = try XCTUnwrap(MarkdownPreview.opened(.empty, as: .drawing, at: 12, in: note))
        let id = try XCTUnwrap(DrawingCells.ids(in: opened.markdown).first)
        XCTAssertEqual(opened.markdown, CellTypes.open(.drawing, in: note, at: 12, minting: id).markdown)
    }

    func testACodeCellIsHandedOverAsItsCodeWithTheFencesKept() {
        let opened = MarkdownPreview.opened(.write("x"), as: .code(.plain), at: 12, in: note)
        XCTAssertEqual(opened?.draft, "x", "the fences are not typed in")
        XCTAssertEqual(opened?.fence, MarkdownPreview.Fence(open: "```", close: "```"))
        XCTAssertEqual(opened?.editing, NSRange(location: 12, length: 9))
    }

    func testAChosenKindIsWhatTheCellBeingEditedHolds() {
        let opened = MarkdownPreview.opened(.write("x"), as: .heading(.section), at: 12, in: note)
        XCTAssertEqual(opened?.draft, "### x")
        XCTAssertEqual(opened?.editing, NSRange(location: 12, length: 5))
        XCTAssertNil(opened?.fence)
    }

    func testEveryKeyThatOnlyTakesTheBarBackStillWritesNothing() {
        for kind in CellTypes.all {
            XCTAssertNil(MarkdownPreview.opened(.disarm, as: kind, at: 12, in: note), "\(kind.name)")
            XCTAssertNil(MarkdownPreview.opened(.step(up: true), as: kind, at: 12, in: note), "\(kind.name)")
        }
    }
}
