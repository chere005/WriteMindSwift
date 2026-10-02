import XCTest
@testable import WriteMind

/// Where the rendered page puts each cell, and where its bracket goes.
final class CellBracketTests: XCTestCase {
    private func rows(_ heights: [CGFloat]) -> [(id: Int, height: CGFloat)] {
        heights.enumerated().map { ($0.offset, $0.element) }
    }

    // MARK: - Moving the page only when it has to move

    /// A bar armed from outside the page — the one under an answer a run
    /// has just written — moves the page only when it is not already in
    /// front of the reader (Sean, 2026-09-22: "make the cursor behavior
    /// after evaluating a cell elegant").
    func testAPlaceAlreadyInFrontOfTheReaderIsNotScrolledTo() {
        XCTAssertTrue(PreviewLayout.onScreen(400, scroll: 0, height: 800))
        XCTAssertTrue(PreviewLayout.onScreen(900, scroll: 600, height: 800))
        XCTAssertFalse(PreviewLayout.onScreen(900, scroll: 0, height: 800), "below the fold")
        XCTAssertFalse(PreviewLayout.onScreen(100, scroll: 600, height: 800), "above it")
    }

    /// A bar a point inside the fold is on screen by arithmetic and not
    /// by eye, so the edges do not count.
    func testTheVeryEDGESOfTheWindowDoNotCount() {
        XCTAssertFalse(PreviewLayout.onScreen(1, scroll: 0, height: 800))
        XCTAssertFalse(PreviewLayout.onScreen(799, scroll: 0, height: 800))
        XCTAssertTrue(PreviewLayout.onScreen(24, scroll: 0, height: 800))
        XCTAssertTrue(PreviewLayout.onScreen(776, scroll: 0, height: 800))
    }

    /// A window nobody has measured yet holds nothing, so the page moves.
    func testAWindowWithNoHeightShowsNothing() {
        XCTAssertFalse(PreviewLayout.onScreen(10, scroll: 0, height: 0))
        XCTAssertFalse(PreviewLayout.onScreen(10, scroll: 0, height: 30))
    }

    func testEveryCellGetsItsPlaceInOrder() {
        let places = PreviewLayout.positions(rows: rows([20, 30, 10]), spacing: 4, top: 10)
        XCTAssertEqual(places[0]?.top, 10)
        XCTAssertEqual(places[0]?.bottom, 30)
        XCTAssertEqual(places[1]?.top, 34)
        XCTAssertEqual(places[1]?.bottom, 64)
        XCTAssertEqual(places[2]?.top, 68)
    }

    func testADrawingOnThePageMovesNoCellAtAll() {
        // The whole of Step 1, in one assertion: there is no argument left
        // to tell the stack about a picture (Sean, 2026-09-20: "don't push
        // other cells around").
        let places = PreviewLayout.positions(rows: rows([20, 20]), spacing: 0, top: 0)
        XCTAssertEqual(places[0]?.top, 0)
        XCTAssertEqual(places[1]?.top, 20)
    }

    func testABracketIsHitOnItsOwnLineAndNotOnTheNext() {
        let outer = CellBrackets.Bracket(key: "Title", depth: 0, top: 0, bottom: 100,
                                         foldable: true, range: NSRange(location: 0, length: 10))
        let inner = CellBrackets.Bracket(key: "cell:1", depth: 1, top: 10, bottom: 40,
                                         range: NSRange(location: 0, length: 4))
        let width = CellBrackets.width
        let outerX = CellBrackets.x(for: 0, in: width)
        let innerX = CellBrackets.x(for: 1, in: width)
        XCTAssertNotEqual(outerX, innerX, "a group is drawn further out than its cells")
        XCTAssertEqual(CellBrackets.bracket(at: CGPoint(x: outerX, y: 50), in: [outer, inner],
                                            width: width)?.key, "Title")
        XCTAssertEqual(CellBrackets.bracket(at: CGPoint(x: innerX, y: 20), in: [outer, inner],
                                            width: width)?.key, "cell:1")
        XCTAssertNil(CellBrackets.bracket(at: CGPoint(x: 0, y: 20), in: [outer, inner], width: width),
                     "the middle of the gutter is not a bracket")
        XCTAssertNil(CellBrackets.bracket(at: CGPoint(x: innerX, y: 90), in: [inner], width: width),
                     "below the cell is not the cell")
    }
}

/// The same place, whichever mode is showing (Sean, 2026-09-19: "positions
/// stay the same in markdown and wysiwyg mode"; 2026-10-02: "preserve the
/// position of things as much as possible between markdown and wysiwyg
/// mode"). The two sides lay a note out at different heights, so what
/// carries across is the CELL at the top and how far into it — not the
/// number of points scrolled.
final class TopCellTests: XCTestCase {
    /// The rendered page's cells.
    private let page: [CellSeams.Box] = [
        (top: 20, bottom: 80, offset: 0),
        (top: 94, bottom: 180, offset: 12),
        (top: 194, bottom: 600, offset: 40),
        (top: 614, bottom: 700, offset: 90),
    ]
    /// The same cells as the markdown pane lays them out: closer together,
    /// the long one a little shorter.
    private let source: [CellSeams.Box] = [
        (top: 20, bottom: 74, offset: 0),
        (top: 88, bottom: 170, offset: 12),
        (top: 184, bottom: 560, offset: 40),
        (top: 574, bottom: 660, offset: 90),
    ]

    func testTheTopOfThePageIsTheAirAboveTheFirstCell() {
        XCTAssertEqual(CellPlace.at(0, in: page), CellPlace(cell: 0, fraction: -1))
        XCTAssertEqual(CellPlace.top.y(in: source), 0)
    }

    func testScrollingPastACellMovesTheAnswerOn() {
        XCTAssertEqual(CellPlace.at(100, in: page)?.cell, 12)
        XCTAssertEqual(CellPlace.at(300, in: page)?.cell, 40)
        XCTAssertEqual(CellPlace.at(5_000, in: page), CellPlace(cell: 90, fraction: 1),
                       "past the last cell is its bottom")
    }

    func testThePlaceInsideACellIsKept() {
        // Half way down the long cell on the page is half way down it in
        // the markdown pane — not its top, which is where the switch used
        // to put it: 397 came back as 194, two hundred points up.
        let place = CellPlace.at(397, in: page)
        XCTAssertEqual(place, CellPlace(cell: 40, fraction: 0.5))
        XCTAssertEqual(place?.y(in: source), 372)
    }

    func testTheAirBetweenTwoCellsIsNotTheCellAbove() {
        // Seven points above the long cell, in the 14-point seam over it:
        // the window is showing the air before cell 40, and the switch
        // used to read it as the cell above and open a whole cell up.
        let place = CellPlace.at(187, in: page)
        XCTAssertEqual(place?.cell, 40)
        XCTAssertEqual(place?.fraction ?? 0, -0.5, accuracy: 1e-9)
        XCTAssertEqual(place?.y(in: source) ?? 0, 177, accuracy: 1e-9, "half way across the seam there too")
    }

    func testSwitchingBackAndForthStaysOnTheSameLine() {
        var scroll: CGFloat = 300
        for _ in 0..<4 {
            let there = CellPlace.at(scroll, in: page)?.y(in: source) ?? -1
            scroll = CellPlace.at(there, in: source)?.y(in: page) ?? -1
            XCTAssertEqual(scroll, 300, accuracy: 1e-9, "modes do not walk the page")
        }
    }

    func testACellThePaneHasNotMeasuredFallsBackToTheCellBefore() {
        // Folded away on the other side, or not measured yet: the top of
        // the last cell before it, which is what the switch always did.
        let place = CellPlace(cell: 40, fraction: 0.5)
        let without = page.filter { $0.offset != 40 }
        XCTAssertEqual(place.y(in: without), 94)
    }

    func testAnEmptyPageHasNoPlace() {
        XCTAssertNil(CellPlace.at(0, in: []))
        XCTAssertNil(CellPlace.top.y(in: []))
    }

    func testAnEditAboveThePlaceMovesItWithItsCell() {
        let before = "First cell\n\n## A heading\n\nWords under it"
        let place = CellPlace(cell: 26, fraction: 0.25)
        // Words added to the first cell: nine characters in front of it.
        let after = "First cell and more\n\n## A heading\n\nWords under it"
        XCTAssertEqual(place.shifted(from: before, to: after), CellPlace(cell: 35, fraction: 0.25))
        // Taken out again.
        XCTAssertEqual(CellPlace(cell: 35, fraction: 0.25).shifted(from: after, to: before), place)
    }

    func testAnEditInOrAfterThePlacesCellLeavesIt() {
        let before = "First cell\n\n## A heading\n\nWords under it"
        let place = CellPlace(cell: 12, fraction: 0.5)
        XCTAssertEqual(place.shifted(from: before, to: before + " and more"), place)
        XCTAssertEqual(place.shifted(from: before, to: "First cell\n\n## A heading!\n\nWords under it"), place)
        XCTAssertEqual(CellPlace.top.shifted(from: before, to: "x" + before), .top)
    }

    func testAnEditThatTakesThePlacesCellLeavesItAtTheEdit() {
        let before = "First cell\n\nSecond\n\nThird"
        let place = CellPlace(cell: 12, fraction: 0.5)
        // "Second" and the line after it gone: the place is where they were.
        XCTAssertEqual(place.shifted(from: before, to: "First cell\n\nThird").cell, 12)
        XCTAssertEqual(place.shifted(from: before, to: "First").cell, 5)
    }
}

/// One gap, the same everywhere (Sean, 2026-09-19: "there shouldn't be
/// gaps between cells" / "gaps should just be a small fixed padding, not
/// some varying amount").
final class CellSpacingTests: XCTestCase {
    func testTheGapBetweenCellsIsSmallAndFixed() {
        XCTAssertLessThanOrEqual(MarkdownPreview.gapHeight, 10)
        XCTAssertGreaterThan(MarkdownPreview.gapHeight, 0, "the pointer still has to fit in it")

        // AND THE PAGE'S OWN RHYTHM IS THE OTHER PANE'S (Sean,
        // 2026-09-22: "make the spacing more uniform.. in rendered mode
        // things get scrunched together"). A blank line of the note plus
        // the spacing that goes round it, which is what separates two
        // cells in the source — not the floor a seam is allowed to
        // shrink to, which is all `gapHeight` ever was.
        XCTAssertEqual(MarkdownPreview.blockGap,
                       MarkdownTextView.lineHeight
                           + MarkdownTextView.paragraphStyle.lineSpacing, accuracy: 0.001)
        XCTAssertGreaterThan(MarkdownPreview.blockGap, MarkdownPreview.gapHeight * 2,
                             "the page was stacking cells a third of a line apart")
    }

    func testEverySeamIsThatSameGap() {
        let rows = [(id: 1, height: CGFloat(40)), (id: 2, height: CGFloat(120)),
                    (id: 3, height: CGFloat(18))]
        let places = PreviewLayout.positions(rows: rows, spacing: MarkdownPreview.blockGap,
                                             top: MarkdownPreview.topInset)
        XCTAssertEqual(places[2]!.top - places[1]!.bottom, MarkdownPreview.blockGap, accuracy: 0.001)
        XCTAssertEqual(places[3]!.top - places[2]!.bottom, MarkdownPreview.blockGap, accuracy: 0.001)
    }
}

/// A rendered code cell is a box round its code and not much more.
final class CodeCellHeightTests: XCTestCase {
    /// What the RENDERED page gives a fenced cell: the body at the source
    /// pane's size and spacing, and the padding.
    private func rendered(bodyLines: Int) -> CGFloat {
        CGFloat(bodyLines) * MarkdownTextView.lineHeight + 2 * MarkdownPreview.codePadding
    }

    /// Sean, 2026-09-22: "there shouldn't be so much padding in the cells
    /// themselves, it should be about the size of the text a little
    /// bigger". A one-line cell used to be three and a half lines tall.
    func testTheBoxHugsTheCodeItHolds() {
        let line = MarkdownTextView.lineHeight
        XCTAssertLessThan(rendered(bodyLines: 1), line * 2,
                          "one line of code is a box a little bigger than one line")
        XCTAssertGreaterThan(rendered(bodyLines: 1), line, "and not tighter than the text itself")
    }

    func testThePaddingIsHalfTheTextRatherThanAWholeSourceLine() {
        XCTAssertEqual(MarkdownPreview.codePadding,
                       (MarkdownTextView.codeSize / 2).rounded(), accuracy: 0.001)
        // THE OLD CONTRACT, GIVEN UP ON PURPOSE. The padding used to be
        // one source line, so that a code cell was exactly as tall as the
        // other pane's ``` body ``` — a full line of air each side. The
        // two modes come back to the same CELL by its id and never by a
        // measurement, so nothing depended on it.
        XCTAssertLessThan(MarkdownPreview.codePadding, MarkdownTextView.lineHeight / 2)
    }

    func testTheRenderedPageSetsCodeAtTheSizeTheSourceDoes() {
        XCTAssertEqual(MarkdownTextView.codeSize, MarkdownTextView.font.pointSize * 0.95)
    }

    func testASourceLineIsTheFontsLineHeightPlusItsSpacing() {
        XCTAssertEqual(MarkdownTextView.lineHeight,
                       NSLayoutManager().defaultLineHeight(for: MarkdownTextView.font)
                           + MarkdownTextView.paragraphStyle.lineSpacing)
        XCTAssertGreaterThan(MarkdownTextView.lineHeight, 15, "a sane line for a 15-point font")
    }
}
