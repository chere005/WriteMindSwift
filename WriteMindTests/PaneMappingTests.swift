import XCTest
@testable import WriteMind

/// A point beside a paragraph in one mode is beside the same paragraph in
/// the other (Sean, 2026-10-02: "preserve the position of things as much
/// as possible between markdown and wysiwyg mode"). The two panes lay the
/// same cells out at different heights, and `PaneMapping` goes through the
/// cells both of them have.
final class PaneMappingTests: XCTestCase {
    /// The markdown pane, markers hidden: three cells, 14 points apart.
    private let source: [CellSeams.Box] = [
        (top: 20, bottom: 64, offset: 0),
        (top: 78, bottom: 144, offset: 30),
        (top: 158, bottom: 202, offset: 90),
    ]
    /// The rendered page: the same cells from 30, `blockGap` apart.
    private let page: [CellSeams.Box] = [
        (top: 30, bottom: 74, offset: 0),
        (top: 100, bottom: 166, offset: 30),
        (top: 192, bottom: 236, offset: 90),
    ]
    private let width: CGFloat = 600
    private var mapping: PaneMapping {
        PaneMapping(from: source, to: page, fromColumn: MarkdownTextView.column(width: width),
                    toColumn: MarkdownPreview.column(width: width))
    }

    func testTheSameLayoutOnBothSidesIsTheIdentity() {
        let same = PaneMapping(from: source, to: source, fromColumn: MarkdownTextView.column(width: width),
                               toColumn: MarkdownTextView.column(width: width))
        XCTAssertTrue(same.isIdentity)
        for value in stride(from: CGFloat(-20), through: 400, by: 7.5) {
            XCTAssertEqual(same.x(value), value, accuracy: 1e-9)
            XCTAssertEqual(same.y(value), value, accuracy: 1e-9)
        }
        XCTAssertFalse(mapping.isIdentity)
    }

    func testInsideACellByHowFarDownIt() {
        // A third of the way down the second cell, on both sides.
        XCTAssertEqual(mapping.y(100), 122, accuracy: 1e-9)
        XCTAssertEqual(mapping.y(78), 100, accuracy: 1e-9, "its top is its top")
        XCTAssertEqual(mapping.y(144), 166, accuracy: 1e-9, "its bottom its bottom")
    }

    func testInASeamByHowFarAcrossIt() {
        // Half way across the 14 points between the first two cells is
        // half way across the 26 between them on the page.
        XCTAssertEqual(mapping.y(71), 87, accuracy: 1e-9)
    }

    func testAboveTheFirstCellByHowFarDownTheAirAboveIt() {
        XCTAssertEqual(mapping.y(10), 15, accuracy: 1e-9)
        XCTAssertEqual(mapping.y(0), 0, "the top of the document is the top of the document")
        XCTAssertEqual(mapping.y(-12), -12, accuracy: 1e-9, "and above it, the same distance above")
    }

    func testPastTheLastCellByTheDistanceBelowIt() {
        XCTAssertEqual(mapping.y(202 + 300), 236 + 300, accuracy: 1e-9)
    }

    func testAcrossByTheTwoTextColumns() {
        // The markdown pane's words start at its inset and the line
        // fragment's padding; the page's at its side inset.
        let source = MarkdownTextView.column(width: width), page = MarkdownPreview.column(width: width)
        XCTAssertEqual(source.left, 29)
        XCTAssertEqual(page.left, 28)
        XCTAssertEqual(mapping.x(source.left), page.left, accuracy: 1e-9)
        XCTAssertEqual(mapping.x(source.right), page.right, accuracy: 1e-9)
    }

    func testItClimbsEverywhereAndComesBackExactly() {
        let mapping = mapping, back = mapping.inverse
        var last = -CGFloat.infinity
        for y in stride(from: CGFloat(-40), through: 600, by: 0.5) {
            let there = mapping.y(y)
            XCTAssertGreaterThan(there, last, "monotone at \(y)")
            last = there
            XCTAssertEqual(back.y(there), y, accuracy: 1e-9, "round trip at \(y)")
            XCTAssertEqual(back.x(mapping.x(y)), y, accuracy: 1e-9)
        }
    }

    func testAnEmptyNoteMovesOnlyAcross() {
        let empty = PaneMapping(from: [], to: [], fromColumn: MarkdownTextView.column(width: width),
                                toColumn: MarkdownPreview.column(width: width))
        XCTAssertEqual(empty.y(123), 123)
        XCTAssertEqual(empty.x(29), 28, accuracy: 1e-9)
    }

    func testOneCell() {
        let one = PaneMapping(from: [(top: 20, bottom: 42, offset: 0)], to: [(top: 30, bottom: 52, offset: 0)],
                              fromColumn: MarkdownTextView.column(width: width),
                              toColumn: MarkdownPreview.column(width: width))
        XCTAssertEqual(one.y(31), 41, accuracy: 1e-9)
        XCTAssertEqual(one.y(100), 110, accuracy: 1e-9)
        XCTAssertEqual(one.inverse.y(one.y(5)), 5, accuracy: 1e-9)
    }

    func testAFoldedSectionHiddenInOnePaneIsNoKnot() {
        // The markdown pane lays a closed section's cells out at no height
        // (`FoldingTypesetter`), the page leaves them out: the points
        // beside them go with the cells round them, and nothing folds back.
        let folded: [CellSeams.Box] = [
            (top: 20, bottom: 42, offset: 0),
            (top: 42, bottom: 42, offset: 10),
            (top: 42, bottom: 42, offset: 20),
            (top: 56, bottom: 78, offset: 30),
        ]
        let shown: [CellSeams.Box] = [
            (top: 30, bottom: 52, offset: 0),
            (top: 78, bottom: 100, offset: 30),
        ]
        let mapping = PaneMapping(from: folded, to: shown, fromColumn: MarkdownTextView.column(width: width),
                                  toColumn: MarkdownPreview.column(width: width))
        XCTAssertEqual(mapping.knots.map(\.from), [0, 20, 42, 56, 78])
        XCTAssertEqual(mapping.y(60), 82, accuracy: 1e-9)
        for y in stride(from: CGFloat(0), through: 120, by: 1) {
            XCTAssertEqual(mapping.inverse.y(mapping.y(y)), y, accuracy: 1e-9)
        }
    }

    func testACellTheOtherPaneHasNotMeasuredYetIsNoKnot() {
        // The page measures its rows a moment after they appear.
        let partial = Array(page.prefix(1))
        let mapping = PaneMapping(from: source, to: partial, fromColumn: MarkdownTextView.column(width: width),
                                  toColumn: MarkdownPreview.column(width: width))
        XCTAssertEqual(mapping.knots.count, 3, "the document's top and the first cell")
        XCTAssertEqual(mapping.y(100), 110, accuracy: 1e-9, "the distance below what is measured")
    }

    func testAPictureTallerThanItsCellOnThePage() {
        // `![](…)` is one 22-point line in the markdown pane and the
        // picture itself on the page.
        let source: [CellSeams.Box] = [(top: 20, bottom: 42, offset: 0), (top: 56, bottom: 78, offset: 20)]
        let page: [CellSeams.Box] = [(top: 30, bottom: 330, offset: 0), (top: 356, bottom: 378, offset: 20)]
        let mapping = PaneMapping(from: source, to: page, fromColumn: MarkdownTextView.column(width: width),
                                  toColumn: MarkdownPreview.column(width: width))
        XCTAssertEqual(mapping.y(31), 180, accuracy: 1e-9, "half way down the line is half way down the picture")
        XCTAssertEqual(mapping.y(60), 360, accuracy: 1e-9, "and the cell under it is under it")
        for y in stride(from: CGFloat(0), through: 200, by: 0.25) {
            XCTAssertEqual(mapping.inverse.y(mapping.y(y)), y, accuracy: 1e-9)
        }
    }

    func testBoxesThatWouldFoldItBackAreDropped() {
        // Upside down, out of order, overlapping: whatever a pane hands in,
        // the knots climb on both sides.
        let odd: [CellSeams.Box] = [(top: 80, bottom: 40, offset: 30), (top: 20, bottom: 60, offset: 0),
                                    (top: 70, bottom: 120, offset: 50)]
        let page: [CellSeams.Box] = [(top: 30, bottom: 70, offset: 0), (top: 90, bottom: 120, offset: 30),
                                     (top: 100, bottom: 160, offset: 50)]
        let mapping = PaneMapping(from: odd, to: page, fromColumn: MarkdownTextView.column(width: width),
                                  toColumn: MarkdownPreview.column(width: width))
        for (a, b) in zip(mapping.knots, mapping.knots.dropFirst()) {
            XCTAssertGreaterThan(b.from, a.from)
            XCTAssertGreaterThan(b.to, a.to)
        }
    }

    func testWhileTheNoteIsTypedIntoItsCellsAreCarriedAlong() {
        // Never a whole layout on a keystroke: the cells laid out last go
        // along with the edit until the typing stops, and keep matching
        // the page's cells by offset.
        let old = "First\n\nSecond cell\n\nThird"
        let cells: [CellSeams.Box] = [(top: 20, bottom: 42, offset: 0), (top: 56, bottom: 78, offset: 7),
                                      (top: 92, bottom: 114, offset: 20)]
        let typed = PaneMapping.shifted(cells, from: old, to: "First\n\nSecond cell, longer\n\nThird")
        XCTAssertEqual(typed.map(\.offset), [0, 7, 28])
        XCTAssertEqual(typed.map(\.top), cells.map(\.top), "where they were, until they are measured")
        let cut = PaneMapping.shifted(cells, from: old, to: "First\n\nThird")
        XCTAssertEqual(cut.map(\.offset), [0, 7, 7])
        XCTAssertEqual(PaneMapping.shifted(cells, from: old, to: old).map(\.offset), [0, 7, 20])
    }

    /// The scroll's place and the mapping are one idea: the place of a
    /// point among one pane's cells, found among the other's, is where the
    /// mapping puts it.
    func testThePlaceAtTheTopOfTheWindowIsWhereTheMappingPutsIt() {
        for y in stride(from: CGFloat(0), to: 202, by: 1) {
            let place = CellPlace.at(y, in: source)
            XCTAssertEqual(place?.y(in: page) ?? -1, mapping.y(y), accuracy: 1e-9, "at \(y)")
        }
    }
}

/// The objects on the drawing layer, shown on the rendered page through
/// the mapping and written back through it.
final class DrawingPaneTests: XCTestCase {
    private let size = CGSize(width: 600, height: 500)
    private var mapping: PaneMapping {
        PaneMapping(from: [(top: 20, bottom: 64, offset: 0), (top: 78, bottom: 144, offset: 30),
                           (top: 158, bottom: 202, offset: 90)],
                    to: [(top: 30, bottom: 74, offset: 0), (top: 100, bottom: 166, offset: 30),
                         (top: 192, bottom: 236, offset: 90)],
                    fromColumn: MarkdownTextView.column(width: size.width),
                    toColumn: MarkdownPreview.column(width: size.width))
    }

    private func stroke(_ points: [CGPoint], group: UUID? = nil) -> CanvasItem {
        .stroke(Stroke(colorHex: "#000000", width: 2,
                       points: points.map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }, group: group))
    }

    func testAnObjectGoesWholeByItsCornerAndIsNotStretched() {
        // A picture beside the second cell, running down past it.
        let picture = CanvasItem.image(ImageItem(file: "p.png", center: CGPoint(x: 0.5, y: 140.0 / 500),
                                                 width: 0.2, aspect: 1))
        let before = picture.bounds(in: size)
        let shown = Drawing(items: [picture]).shown(through: mapping, in: size).items[0].bounds(in: size)
        XCTAssertEqual(shown.width, before.width, accuracy: 1e-9)
        XCTAssertEqual(shown.height, before.height, accuracy: 1e-9)
        XCTAssertEqual(shown.minY, mapping.y(before.minY), accuracy: 1e-9)
        XCTAssertEqual(shown.minY, 102, accuracy: 1e-9, "two points into the second cell on both sides")
        XCTAssertEqual(shown.minX, mapping.x(before.minX), accuracy: 1e-9)
    }

    func testWhatTheLayerDidNotTouchComesBackBitForBit() {
        let drawing = Drawing(items: [stroke([CGPoint(x: 40, y: 90), CGPoint(x: 90, y: 120)]),
                                      .image(ImageItem(file: "p.png", center: CGPoint(x: 0.3, y: 0.31)))])
        let shown = drawing.shown(through: mapping, in: size)
        XCTAssertNotEqual(shown, drawing)
        XCTAssertEqual(drawing.stored(shown, wasShown: shown, through: mapping, in: size), drawing)
    }

    func testAMovedObjectLandsBesideWhatItWasDroppedBeside() {
        let drawing = Drawing(items: [stroke([CGPoint(x: 40, y: 30), CGPoint(x: 90, y: 40)])])
        var shown = drawing.shown(through: mapping, in: size)
        // Dragged on the page to sit 10 points into the third cell.
        let corner = shown.items[0].bounds(in: size).origin
        shown.items[0].transform.dy += Double((202 - corner.y) / size.height)
        let stored = drawing.stored(shown, wasShown: drawing.shown(through: mapping, in: size),
                                    through: mapping, in: size)
        XCTAssertEqual(stored.items[0].bounds(in: size).minY, mapping.inverse.y(202), accuracy: 1e-6)
        XCTAssertEqual(stored.items[0].bounds(in: size).minY, 168, accuracy: 1e-6,
                       "ten points into the third cell there too")
        // And shown again, it is where it was put.
        XCTAssertEqual(stored.shown(through: mapping, in: size).items[0].bounds(in: size).minY, 202, accuracy: 1e-6)
    }

    func testANewObjectGoesBackToTheStoredFrame() {
        let drawing = Drawing()
        let new = stroke([CGPoint(x: 100, y: 110), CGPoint(x: 140, y: 112)])
        let stored = drawing.stored(Drawing(items: [new]), wasShown: drawing, through: mapping, in: size)
        let shownAgain = stored.shown(through: mapping, in: size)
        XCTAssertEqual(shownAgain.items[0].bounds(in: size).minY, new.bounds(in: size).minY, accuracy: 1e-6)
        // Nine points into the second cell on the page, nine into it there.
        XCTAssertEqual(stored.items[0].bounds(in: size).minY, 87, accuracy: 1e-6)
    }

    func testAGroupGoesAsOne() {
        // Writing across the edge of a cell: one word, two strokes, one in
        // the seam and one in the cell. Each by its own corner would pull
        // the letters apart; the group keeps them as they were written.
        let group = UUID()
        let drawing = Drawing(items: [stroke([CGPoint(x: 300, y: 66), CGPoint(x: 310, y: 90)], group: group),
                                      stroke([CGPoint(x: 312, y: 80), CGPoint(x: 330, y: 92)], group: group)])
        let shown = drawing.shown(through: mapping, in: size)
        let before = drawing.items.map { $0.bounds(in: size).origin }
        let after = shown.items.map { $0.bounds(in: size).origin }
        // The group's corner is a fourteenth of the way across the seam
        // under the first cell, and so it is on the page.
        XCTAssertEqual(after[0].y, 74 + 26.0 / 14, accuracy: 1e-9)
        XCTAssertEqual(after[1].y - after[0].y, before[1].y - before[0].y, accuracy: 1e-9)
        XCTAssertEqual(after[1].x - after[0].x, before[1].x - before[0].x, accuracy: 1e-9)
        // And written back as one, they are where they were.
        let back = drawing.stored(shown, wasShown: Drawing(), through: mapping, in: size)
        for (item, origin) in zip(back.items, before) {
            XCTAssertEqual(item.bounds(in: size).origin.y, origin.y, accuracy: 1e-6)
            XCTAssertEqual(item.bounds(in: size).origin.x, origin.x, accuracy: 1e-6)
        }
    }

    func testAnArrowStaysOnItsNodes() {
        // Two boxes in different cells, each moved by its own amount, and
        // the arrow between them still runs from one to the other.
        let top = ShapeItem(kind: .rectangle, center: CGPoint(x: 0.2, y: 40.0 / 500), width: 0.1,
                            aspect: 0.5, colorHex: "#000000")
        let bottom = ShapeItem(kind: .rectangle, center: CGPoint(x: 0.6, y: 180.0 / 500), width: 0.1,
                               aspect: 0.5, colorHex: "#000000")
        var drawing = Drawing(items: [.shape(top), .shape(bottom),
                                      .connector(ConnectorItem(start: CGPoint(x: 0.2, y: 0.08),
                                                               end: CGPoint(x: 0.6, y: 0.36),
                                                               startNode: top.id, endNode: bottom.id,
                                                               colorHex: "#000000"))])
        drawing.reconnect(in: size)
        let shown = drawing.shown(through: mapping, in: size)
        // Each box by its own cell: ten points down for the one in the
        // first, thirty-four for the one in the third.
        XCTAssertEqual(shown.items[0].bounds(in: size).minY - drawing.items[0].bounds(in: size).minY, 10,
                       accuracy: 1e-9)
        XCTAssertEqual(shown.items[1].bounds(in: size).minY - drawing.items[1].bounds(in: size).minY, 34,
                       accuracy: 1e-9)
        guard case .connector(let arrow) = shown.items[2] else { return XCTFail("the arrow") }
        let start = CGPoint(x: arrow.start.x * size.width, y: arrow.start.y * size.height)
        let end = CGPoint(x: arrow.end.x * size.width, y: arrow.end.y * size.height)
        XCTAssertTrue(shown.items[0].bounds(in: size).insetBy(dx: -1, dy: -1).contains(start),
                      "\(start) is on \(shown.items[0].bounds(in: size))")
        XCTAssertTrue(shown.items[1].bounds(in: size).insetBy(dx: -1, dy: -1).contains(end),
                      "\(end) is on \(shown.items[1].bounds(in: size))")
        var again = shown
        again.reconnect(in: size)
        XCTAssertEqual(again, shown, "routed where it is shown, and settled")
    }

    /// ⌃G on the page is ⌃G in the markdown pane: a group is only a name
    /// the members share, and naming them moves none of them in the
    /// sidecar — though on the page, which moves a group by its corner,
    /// a member can then sit where its group's corner says.
    func testGroupingAndUngroupingOnThePageMoveNothingInTheSidecar() throws {
        // One stroke in the seam under the first cell, one in the second.
        let loose = Drawing(items: [stroke([CGPoint(x: 300, y: 66), CGPoint(x: 310, y: 90)]),
                                    stroke([CGPoint(x: 312, y: 100), CGPoint(x: 330, y: 120)])])
        let ids = Set(loose.items.map(\.id)), group = UUID()
        let shown = loose.shown(through: mapping, in: size)
        var grouped = shown
        grouped.items = try XCTUnwrap(CanvasGroups.toggled(ids, in: shown.items, id: group))
        let stored = loose.stored(grouped, wasShown: shown, through: mapping, in: size)
        var expected = loose
        expected.items = try XCTUnwrap(CanvasGroups.toggled(ids, in: loose.items, id: group))
        XCTAssertEqual(stored, expected, "the same sidecar as ⌃G in the markdown pane")

        let regrouped = stored.shown(through: mapping, in: size)
        var ungrouped = regrouped
        ungrouped.items = try XCTUnwrap(CanvasGroups.toggled(ids, in: regrouped.items))
        XCTAssertEqual(stored.stored(ungrouped, wasShown: regrouped, through: mapping, in: size), loose)
    }

    /// Typing in a text box that is grouped with a stroke above it: the
    /// box is where it was, edit after edit, and so is the stroke.
    func testTypingInAGroupedTextBoxOnThePageLeavesItWhereItIs() throws {
        let group = UUID()
        // The stroke's top in the seam under the first cell is the group's
        // corner; the box's top is 100, in the second cell.
        let box = ShapeItem(kind: .text, center: CGPoint(x: 0.6, y: 120.0 / 500), width: 0.2,
                            aspect: 40.0 / 120, colorHex: "#000000", lineWidth: 1, group: group)
        let original = Drawing(items: [stroke([CGPoint(x: 300, y: 66), CGPoint(x: 310, y: 90)], group: group),
                                       .shape(box)])
        var drawing = original
        for label in ["H", "Hi", "Hi there"] {
            let shown = drawing.shown(through: mapping, in: size)
            var typed = shown
            guard case .shape(var shape) = typed.items[1] else { return XCTFail("the box") }
            shape.label = label
            // And it grows to fit, about its middle (`fitTextBox`).
            shape.aspect += 0.05
            typed.items[1] = .shape(shape)
            drawing = drawing.stored(typed, wasShown: shown, through: mapping, in: size)
        }
        XCTAssertEqual(drawing.items[0], original.items[0], "the stroke it is grouped with, bit for bit")
        let typed = try XCTUnwrap(drawing.items[1].shape)
        XCTAssertEqual(typed.label, "Hi there")
        XCTAssertEqual(typed.center, box.center, "not a point up or down the sidecar for any of it")
        XCTAssertEqual(typed.transform, box.transform)
    }

    func testTheIdentityTouchesNothing() {
        let drawing = Drawing(items: [stroke([CGPoint(x: 40, y: 90), CGPoint(x: 90, y: 120)])])
        XCTAssertEqual(drawing.shown(through: .identity, in: size), drawing)
        var moved = drawing
        moved.items[0].transform.dx = 0.1
        XCTAssertEqual(drawing.stored(moved, wasShown: drawing, through: .identity, in: size), moved)
    }
}

/// What sits between the drawing layer on the rendered page and the
/// sidecar: the layer's every write, the way `DrawingCanvas` makes it
/// through `EditorPane.layerDrawing`, and the markdown pane's cells laid
/// out for it.
@MainActor
final class PaneFramesTests: XCTestCase {
    private let size = CGSize(width: 600, height: 500)
    private var mapping: PaneMapping {
        PaneMapping(from: [(top: 20, bottom: 64, offset: 0), (top: 78, bottom: 144, offset: 30),
                           (top: 158, bottom: 202, offset: 90)],
                    to: [(top: 30, bottom: 74, offset: 0), (top: 100, bottom: 166, offset: 30),
                         (top: 192, bottom: 236, offset: 90)],
                    fromColumn: MarkdownTextView.column(width: size.width),
                    toColumn: MarkdownPreview.column(width: size.width))
    }

    private func stroke(_ points: [CGPoint], group: UUID? = nil) -> CanvasItem {
        .stroke(Stroke(colorHex: "#000000", width: 2,
                       points: points.map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }, group: group))
    }

    /// A word of writing across the edge of a cell: two strokes, one group.
    private func word(_ group: UUID) -> Drawing {
        Drawing(items: [stroke([CGPoint(x: 300, y: 66), CGPoint(x: 310, y: 90)], group: group),
                        stroke([CGPoint(x: 312, y: 80), CGPoint(x: 330, y: 92)], group: group)])
    }

    /// One write by the layer: what it is handed, changed, handed back.
    private func write(_ store: inout Drawing, through frames: PaneFrames, _ change: (inout Drawing) -> Void) {
        var layer = frames.shown(store, through: mapping, in: size)
        change(&layer)
        store = frames.stored(layer, over: store, through: mapping, in: size)
    }

    /// `DrawingCanvas.apply` sets one member's transform at a time, and
    /// through a binding every one of those is a write of its own: the
    /// group still goes back as one, frame after frame of a drag.
    func testAGroupDraggedOnThePageOneWriteAtATimeGoesBackAsOne() {
        let frames = PaneFrames()
        let drawing = word(UUID())
        var store = drawing
        let snapshot = frames.shown(store, through: mapping, in: size).items.map(\.transform)
        for step in 1...3 {
            for index in snapshot.indices {
                write(&store, through: frames) {
                    $0.items[index].transform.dy = snapshot[index].dy + Double(10 * step) / Double(size.height)
                }
            }
        }
        let was = drawing.items.map { $0.bounds(in: size).origin }, now = store.items.map { $0.bounds(in: size).origin }
        XCTAssertEqual(now[1].y - now[0].y, was[1].y - was[0].y, accuracy: 1e-9, "the letters as they were written")
        XCTAssertEqual(now[1].x - now[0].x, was[1].x - was[0].x, accuracy: 1e-9)
        // Shown afresh, with nothing remembered, where the drag left it.
        let start = drawing.shown(through: mapping, in: size).items.map { $0.bounds(in: size).origin }
        let page = store.shown(through: mapping, in: size).items.map { $0.bounds(in: size).origin }
        for (onPage, from) in zip(page, start) {
            XCTAssertEqual(onPage.y, from.y + 30, accuracy: 1e-6)
            XCTAssertEqual(onPage.x, from.x, accuracy: 1e-6)
        }
    }

    /// ⌃G on the page names the members and moves none of them in the
    /// sidecar; the page then shows them as the new grouping puts them,
    /// at once — not at the next keystroke, whenever the cells next move.
    func testAfterGroupingThePageShowsTheNewGroupingAtOnce() throws {
        let frames = PaneFrames()
        let loose = Drawing(items: [stroke([CGPoint(x: 300, y: 66), CGPoint(x: 310, y: 90)]),
                                    stroke([CGPoint(x: 312, y: 100), CGPoint(x: 330, y: 120)])])
        let ids = Set(loose.items.map(\.id)), group = UUID()
        var store = loose
        write(&store, through: frames) { $0.items = CanvasGroups.toggled(ids, in: $0.items, id: group) ?? $0.items }
        var expected = loose
        expected.items = try XCTUnwrap(CanvasGroups.toggled(ids, in: loose.items, id: group))
        XCTAssertEqual(store, expected)
        XCTAssertEqual(frames.shown(store, through: mapping, in: size), store.shown(through: mapping, in: size))
    }

    /// The stroke at a group's corner deleted on the page: the rest stay
    /// where they are in the sidecar, and the page shows them by their own
    /// corner straight away.
    func testTakingTheCornerOutOfAGroupMovesNothingElseInTheSidecar() {
        let frames = PaneFrames()
        let drawing = word(UUID())
        var store = drawing
        let corner = drawing.items[0].id
        write(&store, through: frames) { $0 = $0.removing([corner]) }
        XCTAssertEqual(store, drawing.removing([corner]), "bit for bit")
        XCTAssertEqual(frames.shown(store, through: mapping, in: size), store.shown(through: mapping, in: size))
    }

    private let before = "First paragraph.\n\nSecond.\n\nThird.\n\nFourth."
    private let after = "First paragraph.\n\nA paragraph put in above the rest, and long enough to wrap onto "
        + "a second line in a pane this narrow.\n\nSecond.\n\nThird.\n\nFourth."
    private let pane = CGSize(width: 400, height: 600)

    /// A PaneFrames that counts its layouts — each one a whole TextKit
    /// layout of the note.
    private func counted(_ layouts: @escaping () -> Void) -> PaneFrames {
        PaneFrames { text, pane, markers, folds, drawings in
            layouts()
            return MarkdownTextView.cellBoxes(of: text, pane: pane, showMarkers: markers, collapsed: folds,
                                              drawings: drawings)
        }
    }

    /// The page as it measured itself after the edit: the same cells, lower
    /// and further apart than the markdown pane has them.
    private func page(for text: String) -> [CellSeams.Box] {
        MarkdownTextView.cellBoxes(of: text, pane: pane, showMarkers: false, collapsed: []).cells
            .map { (top: $0.top * 1.5 + 10, bottom: $0.bottom * 1.5 + 10, offset: $0.offset) }
    }

    /// While the note is typed into, the layer is SHOWN through the cells
    /// laid out last, carried along by the edit — never a layout on a
    /// keystroke. A position about to be SAVED is worked out from the note
    /// as it is now.
    func testAPositionWrittenAfterAnEditIsWorkedOutFromTheNoteAsItIsNow() throws {
        var layouts = 0
        let frames = counted { layouts += 1 }
        frames.rendered = page(for: after)
        _ = frames.mapping(text: before, size: pane, showMarkers: false, collapsed: [])
        let typing = frames.mapping(text: after, size: pane, showMarkers: false, collapsed: [])
        XCTAssertEqual(layouts, 1, "never a layout on a keystroke")
        let written = frames.mapping(text: after, size: pane, showMarkers: false, collapsed: [], exact: true)
        XCTAssertEqual(layouts, 2)
        let fresh = MarkdownTextView.cellBoxes(of: after, pane: pane, showMarkers: false, collapsed: [])
        let expected = PaneMapping(from: fresh.cells, to: try XCTUnwrap(frames.rendered),
                                   fromColumn: MarkdownTextView.column(width: fresh.width),
                                   toColumn: MarkdownPreview.column(width: fresh.width))
        XCTAssertEqual(written, expected)
        XCTAssertNotEqual(typing, expected, "the premise: carried along, the cells under the edit are off")
    }

    /// A write while the layer was shown through cells carried along by an
    /// edit: what it did not touch stays bit for bit, what it moved lands
    /// where it was dropped among the cells as they are now, and the layer
    /// is then shown the drawing through those.
    func testAWriteWhileTheCellsWereCarriedAlongTouchesOnlyWhatItMoved() throws {
        let frames = counted {}
        frames.rendered = page(for: after)
        _ = frames.mapping(text: before, size: pane, showMarkers: false, collapsed: [])
        let store = Drawing(items: [stroke([CGPoint(x: 40, y: 120), CGPoint(x: 90, y: 140)]),
                                    stroke([CGPoint(x: 40, y: 30), CGPoint(x: 90, y: 36)])])
        let typing = frames.mapping(text: after, size: pane, showMarkers: false, collapsed: [])
        var layer = frames.shown(store, through: typing, in: pane)
        layer.items[1].transform.dy += 20 / Double(pane.height)
        let exact = frames.mapping(text: after, size: pane, showMarkers: false, collapsed: [], exact: true)
        XCTAssertNotEqual(exact.y(130), typing.y(130), "the premise: the first stroke was shown off its place")
        let result = frames.stored(layer, over: store, through: exact, in: pane)
        XCTAssertEqual(result.items[0], store.items[0], "untouched, bit for bit")
        XCTAssertEqual(result.items[1].bounds(in: pane).minY,
                       exact.inverse.y(layer.items[1].bounds(in: pane).minY), accuracy: 1e-6)
        XCTAssertEqual(frames.shown(result, through: exact, in: pane), result.shown(through: exact, in: pane))
    }

    /// A window made taller or shorter wraps no line differently, so the
    /// layout it had holds; one made narrower is laid out once the resize
    /// stops, not on every frame of it — and a write never waits for that.
    func testAResizeLaysTheNoteOutOnceAndAHeightAloneNotAtAll() {
        var layouts = 0
        let frames = counted { layouts += 1 }
        frames.rendered = page(for: before)
        let first = frames.mapping(text: before, size: pane, showMarkers: false, collapsed: [])
        for height in stride(from: CGFloat(590), through: 300, by: -10) {
            XCTAssertEqual(frames.mapping(text: before, size: CGSize(width: pane.width, height: height),
                                          showMarkers: false, collapsed: []), first)
        }
        XCTAssertEqual(layouts, 1, "a short note in a shorter pane wraps where it did")
        for width in stride(from: CGFloat(390), through: 300, by: -10) {
            _ = frames.mapping(text: before, size: CGSize(width: width, height: 300), showMarkers: false,
                               collapsed: [])
        }
        XCTAssertEqual(layouts, 1, "not on every frame of a resize")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(layouts, 2, "once it stops")
        _ = frames.mapping(text: before, size: CGSize(width: 300, height: 300), showMarkers: false, collapsed: [])
        XCTAssertEqual(layouts, 2, "at the width it stopped at")
        _ = frames.mapping(text: before, size: CGSize(width: 280, height: 300), showMarkers: false, collapsed: [],
                           exact: true)
        XCTAssertEqual(layouts, 3)
    }
}

/// The cursor carried across ⌘T (Sean, 2026-10-02: "preserve the position
/// of things as much as possible between markdown and wysiwyg mode").
final class PaneCaretTests: XCTestCase {
    private let note = "# Title\n\nA paragraph of words.\n\n```python\nx = 1\ny = 2\n```\n\n- [ ] milk\n- [x] eggs"

    private func range(of piece: String) -> NSRange { (note as NSString).range(of: piece) }

    func testTheMarkdownPanesCursorIsReadAsWhatItIs() {
        let words = range(of: "of words")
        XCTAssertEqual(PaneCaret.source(selection: [words], armed: nil, kind: .text, in: note), .text(words))
        XCTAssertEqual(PaneCaret.source(selection: [NSRange(location: 3, length: 0)], armed: nil, kind: .text,
                                        in: note), .text(NSRange(location: 3, length: 0)))
        let cells = MarkdownParser.positioned(from: note).map(\.range)
        XCTAssertEqual(PaneCaret.source(selection: [cells[1]], armed: nil, kind: .text, in: note),
                       .cells([cells[1]]), "a cell picked up by its bracket")
        XCTAssertEqual(PaneCaret.source(selection: [cells[0], cells[2]], armed: nil, kind: .text, in: note),
                       .cells([cells[0], cells[2]]))
        XCTAssertEqual(PaneCaret.source(selection: [NSRange(location: 8, length: 0)], armed: 9,
                                        kind: .quote, in: note), .bar(offset: 9, kind: .quote))
    }

    func testACaretInWordsOpensItsCellWithTheCaretInPlace() {
        let caret = NSRange(location: range(of: "words").location, length: 0)
        let cell = MarkdownParser.positioned(from: note)[1].range
        XCTAssertEqual(cell, range(of: "A paragraph of words."), "the premise: the paragraph's cell")
        XCTAssertEqual(PaneCaret.text(caret).opening(in: note),
                       .cell(cell, selection: NSRange(location: caret.location - cell.location, length: 0)))
    }

    func testACaretInCodeIsCountedFromAfterTheFence() {
        // The open code cell's editor holds the code alone.
        let caret = NSRange(location: range(of: "y = 2").location + 2, length: 1)
        let cell = MarkdownParser.positioned(from: note)[2].range
        guard case .cell(let opened, let selection)? = PaneCaret.text(caret).opening(in: note)
        else { return XCTFail("the code cell opens") }
        XCTAssertEqual(opened, cell)
        XCTAssertEqual(selection, NSRange(location: ("x = 1\n" as NSString).length + 2, length: 1))
        // And back: the page's caret, put into the note.
        XCTAssertEqual(PaneCaret.rendered(open: cell, inside: selection, fence: "```python"), .text(caret))
    }

    func testACaretInAChecklistOpensItsReminder() {
        let caret = NSRange(location: range(of: "eggs").location + 1, length: 0)
        let words = range(of: "eggs")
        XCTAssertEqual(PaneCaret.text(caret).opening(in: note),
                       .item(words, selection: NSRange(location: 1, length: 0)))
        XCTAssertEqual(PaneCaret.rendered(open: words, inside: NSRange(location: 1, length: 0), fence: nil),
                       .text(caret))
    }

    func testACaretBetweenTwoCellsOpensNothing() {
        XCTAssertNil(PaneCaret.text(NSRange(location: 8, length: 0)).opening(in: note))
    }

    func testEveryCaretInEveryCellComesBackWhereItWas() {
        // Into the page and out again, at every character the page can put
        // a caret on.
        var opened = 0
        for location in 0...(note as NSString).length {
            let caret = PaneCaret.text(NSRange(location: location, length: 0))
            if caret.opening(in: note) != nil { opened += 1 }
            switch caret.opening(in: note) {
            case .cell(let cell, let selection)?:
                let source = (note as NSString).substring(with: cell)
                let fence = MarkdownFormatting.fenced(source)?.open
                let back = PaneCaret.rendered(open: cell, inside: selection, fence: fence)
                guard case .text(let range) = back else { return XCTFail() }
                // A caret on a fence line has nowhere in the code to be:
                // it lands at the nearest end of it.
                if fence == nil { XCTAssertEqual(back, caret, "at \(location)") }
                else { XCTAssertLessThanOrEqual(abs(range.location - location), 10, "at \(location)") }
            case .item(let words, let selection)?:
                let back = PaneCaret.rendered(open: words, inside: selection, fence: nil)
                guard case .text(let range) = back else { return XCTFail() }
                XCTAssertTrue(NSLocationInRange(range.location, words) || range.location == NSMaxRange(words))
            case .cells, .bar, .drawing:
                XCTFail("a caret is a caret, and this note has no drawing cell")
            case nil:
                break
            }
        }
        XCTAssertGreaterThan(opened, 60, "the premise: nearly every character is in a cell")
    }
}
