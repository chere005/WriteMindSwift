import XCTest
@testable import WriteMind

final class PreviewEditingTests: XCTestCase {
    func testANewBlockBetweenTwoOthersGetsABlankLineOnEachSide() {
        let (markdown, caret) = PreviewEditing.insertBlock(in: "# Title\n\nBody", at: 9)
        XCTAssertEqual(markdown, "# Title\n\n\n\nBody")
        XCTAssertEqual(caret, 9)
        XCTAssertEqual((markdown as NSString).substring(from: caret), "\n\nBody")
    }

    func testANewBlockAtTheEndFollowsTheLastOne() {
        let (markdown, caret) = PreviewEditing.insertBlock(in: "Body", at: 4)
        XCTAssertEqual(markdown, "Body\n\n")
        XCTAssertEqual(caret, 6)
    }

    func testANewBlockAtTheStartPushesTheFirstOneDown() {
        let (markdown, caret) = PreviewEditing.insertBlock(in: "Body", at: 0)
        XCTAssertEqual(markdown, "\n\nBody")
        XCTAssertEqual(caret, 0)
    }

    func testANewBlockBesideARunOfEmptyLinesKeepsEveryOneOfThem() {
        // The newlines after the caret are that cell's own content, not
        // the blank line this block needs under it (Sean, 2026-09-20: "one
        // with 8 empty lines"). Reading them as the separator left the
        // cell two lines shorter every time a cell was opened above it.
        let note = "baz\n" + String(repeating: "\n", count: 10) + "# asdf"
        let (markdown, caret) = PreviewEditing.insertBlock(in: note, at: 5)
        XCTAssertEqual(caret, 5)
        let blocks = MarkdownParser.blocks(from: (markdown as NSString)
            .replacingCharacters(in: NSRange(location: caret, length: 0), with: "x"))
        XCTAssertEqual(blocks, [.paragraph("baz"), .paragraph("x"), .blank(lines: 8),
                                .heading(level: 1, text: "asdf")])
    }

    func testABlockInThePlaceOfACellIsSpacedByWhatIsLeftNotByTheHole() {
        // The paragraph comes out to make way for the block that holds it;
        // cut out first, the empty lines either side of the hole read as a
        // blank cell, and the block got a spare line under it.
        let (markdown, caret) = PreviewEditing.insertBlock(in: "A\n\nBody\n\nC",
                                                           replacing: NSRange(location: 3, length: 4))
        XCTAssertEqual(markdown, "A\n\n\n\nC")
        XCTAssertEqual(caret, 3)
    }

    func testANewBlockInAnEmptyNoteIsJustTheCaret() {
        let (markdown, caret) = PreviewEditing.insertBlock(in: "", at: 0)
        XCTAssertEqual(markdown, "")
        XCTAssertEqual(caret, 0)
    }

    func testTheNextBlockIsCutInAtTheCaretAndOpened() {
        // What `BlockEditor` asks for at the end of a cell (an empty tail)
        // and on an empty item that ends its list (the rest of the list).
        // Return in the MIDDLE of a block is a line break in it and never
        // comes here (Sean, 2026-10-02: "return should be a newline"); the
        // cut itself is the same wherever it is asked for.
        let (markdown, editing) = PreviewEditing.split("Top\n\nHello world\n\nBottom",
                                                       at: NSRange(location: 5, length: 11),
                                                       head: "Hello", tail: "world")
        XCTAssertEqual(markdown, "Top\n\nHello\n\nworld\n\nBottom")
        XCTAssertEqual((markdown as NSString).substring(with: editing), "world")
    }

    func testBackspaceInAnEmptyBlockTakesItAndItsBlankLinesAway() {
        // "Top", an empty block, "Bottom".
        let (markdown, previous) = PreviewEditing.removeBlock("Top\n\n\n\nBottom", at: NSRange(location: 5, length: 0))
        XCTAssertEqual(markdown, "Top\n\nBottom")
        XCTAssertEqual(previous, NSRange(location: 0, length: 3))
    }

    func testRemovingTheOnlyBlockLeavesNothingToGoBackTo() {
        let (markdown, previous) = PreviewEditing.removeBlock("\n\n", at: NSRange(location: 2, length: 0))
        XCTAssertEqual(markdown, "")
        XCTAssertNil(previous)
    }

    func testListsCarryOnAndEmptyItemsEndThem() {
        XCTAssertEqual(PreviewEditing.listContinuation(for: "- one"), "- ")
        XCTAssertEqual(PreviewEditing.listContinuation(for: "  - nested"), "  - ")
        XCTAssertEqual(PreviewEditing.listContinuation(for: "3. three"), "4. ")
        XCTAssertEqual(PreviewEditing.listContinuation(for: "> quoted"), "> ")
        XCTAssertEqual(PreviewEditing.listContinuation(for: "- "), "")
        XCTAssertEqual(PreviewEditing.listContinuation(for: "2) "), "")
        XCTAssertNil(PreviewEditing.listContinuation(for: "plain prose"))
    }
}

final class MarkdownSourceStyleTests: XCTestCase {
    private func kinds(_ source: String) -> [(String, MarkdownSourceStyle.Kind)] {
        let ns = source as NSString
        return MarkdownSourceStyle.runs(in: source).map { (ns.substring(with: $0.range), $0.kind) }
    }

    func testTheMarkersStepBackAndTheTextTheyWrapIsStyled() {
        let runs = kinds("some **bold** and _italic_ text")
        XCTAssertTrue(runs.contains { $0 == ("**", .marker) })
        XCTAssertTrue(runs.contains { $0 == ("bold", .bold) })
        XCTAssertTrue(runs.contains { $0 == ("italic", .italic) })
        XCTAssertEqual(runs.filter { $0.1 == .marker }.count, 4)
    }

    func testAHeadingIsItsOwnSizeWithoutTheHashes() {
        let runs = kinds("## Section")
        XCTAssertEqual(runs.first?.0, "## ")
        XCTAssertEqual(runs.first?.1, .marker)
        XCTAssertEqual(runs.last?.0, "Section")
        XCTAssertEqual(runs.last?.1, .heading(2))
    }

    func testCodeIsNotMarkdownAndMathsIsCode() {
        let runs = kinds("`**not bold**` and `wl:Pi`")
        XCTAssertTrue(runs.contains { $0 == ("**not bold**", .code) })
        XCTAssertFalse(runs.contains { $0.1 == .bold })
        XCTAssertTrue(runs.contains { $0 == ("wl:", .marker) })
        XCTAssertTrue(runs.contains { $0 == ("Pi", .math) })
    }

    func testLinksListsQuotesAndTheToolbarsOwnHTML() {
        XCTAssertTrue(kinds("[here](Other.md#wm-1)").contains { $0 == ("here", .linkText) })
        XCTAssertTrue(kinds("[here](Other.md#wm-1)").contains { $0 == ("Other.md#wm-1", .linkURL) })
        XCTAssertTrue(kinds("- item").contains { $0 == ("- ", .listMarker) })
        XCTAssertTrue(kinds("2. item").contains { $0 == ("2. ", .listMarker) })
        XCTAssertTrue(kinds("> said").contains { $0 == ("> ", .quoteMarker) })
        XCTAssertTrue(kinds("<u>under</u>").contains { $0 == ("<u>", .marker) })
        XCTAssertTrue(kinds("<span style=\"color: #fff\">x</span>").contains { $0 == ("</span>", .marker) })
    }

    func testRunsNeverReachPastTheText() {
        for source in ["", "*", "**", "`", "[](", "# ", "- ", "_a_ **b** `c` [d](e) <u>f</u>"] {
            let length = (source as NSString).length
            for run in MarkdownSourceStyle.runs(in: source) {
                XCTAssertLessThanOrEqual(NSMaxRange(run.range), length, "\(source): \(run)")
                XCTAssertGreaterThan(run.range.length, 0, "\(source): \(run)")
            }
        }
    }
}
