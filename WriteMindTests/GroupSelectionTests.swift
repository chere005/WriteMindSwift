import XCTest
@testable import WriteMind

/// A SUBGROUP, and more held with ⌘ (Sean, 2026-10-02: "object grouping is
/// really slow. optimize that.. it should also be quick/easy to select a
/// subgroup and include more with holding cmd"). A click still picks a whole
/// group; ⌘ is the Finder's — one object into or out of what is held, a
/// group's member on its own — and ⌃G over a part of a group makes that part
/// a group, leaving the rest where it was.
final class GroupSelectionTests: XCTestCase {
    private func stroke(_ group: UUID? = nil) -> CanvasItem {
        .stroke(Stroke(colorHex: "#000000", width: 2,
                       points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)], group: group))
    }

    private func word(_ letters: Int, group: UUID = UUID()) -> [CanvasItem] {
        (0..<letters).map { _ in stroke(group) }
    }

    // MARK: - ⌘ takes one object in or out

    func testCommandFlipsOneObjectInOrOutOfWhatIsHeld() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(CanvasGroups.flipped(a, in: []), [a])
        XCTAssertEqual(CanvasGroups.flipped(b, in: [a]), [a, b])
        XCTAssertEqual(CanvasGroups.flipped(a, in: [a, b]), [b], "taken out again")
    }

    /// A press with ⌘ on an object that never moves is a pick; one that
    /// drags is the marquee, and `nil` leaves it to that.
    func testACommandClickPicksAndACommandDragDoesNot() {
        let id = UUID(), other = UUID()
        let start = CGPoint(x: 50, y: 50)
        XCTAssertEqual(DrawingCanvas.commandRelease(pick: id, from: start, to: CGPoint(x: 51, y: 50), held: [other]),
                       [id, other])
        XCTAssertNil(DrawingCanvas.commandRelease(pick: id, from: start, to: CGPoint(x: 90, y: 50), held: [other]),
                     "a drag from an object is a marquee")
        XCTAssertNil(DrawingCanvas.commandRelease(pick: nil, from: start, to: start, held: [other]),
                     "over empty paper there is no object to flip")
    }

    // MARK: - What the handles are drawn round

    /// The selection is what it says: a subgroup is not grown back to the
    /// whole group for the handles, ⌫ or ⌃G.
    func testTheHandlesGoRoundTheSubgroupAndNotTheWholeGroup() {
        let letters = word(5)
        let drawing = Drawing(items: letters)
        let some = Set(letters.prefix(2).map(\.id))
        XCTAssertEqual(DrawingCanvas.handled(selection: some, hovered: nil, in: drawing), some)
        XCTAssertEqual(DrawingCanvas.handled(selection: [], hovered: letters[3].id, in: drawing), [letters[3].id],
                       "the hovered stroke, before anything is picked")
        XCTAssertEqual(DrawingCanvas.handled(selection: [], hovered: nil, in: drawing), [])
    }

    // MARK: - ⌃G over part of a group

    func testGroupingPartOfAGroupTakesOnlyThatPart() throws {
        let old = UUID()
        let letters = word(6, group: old)
        let part = Set(letters[1...3].map(\.id))
        let out = CanvasGroups.grouped(part, in: letters)
        let new = try XCTUnwrap(out[1].group)
        XCTAssertNotEqual(new, old)
        XCTAssertEqual(out.filter { $0.group == new }.map(\.id), letters[1...3].map(\.id), "just what was picked")
        XCTAssertEqual(out.filter { $0.group == old }.count, 3, "the rest keeps its group")
    }

    func testWhatIsLeftOfAGroupAsOneObjectIsLetGo() throws {
        let old = UUID()
        let letters = word(3, group: old)
        let loose = stroke()
        let out = CanvasGroups.grouped([letters[0].id, letters[1].id, loose.id], in: letters + [loose])
        let new = try XCTUnwrap(out[0].group)
        XCTAssertEqual(out[1].group, new)
        XCTAssertEqual(out[3].group, new)
        XCTAssertNil(out[2].group, "a group of one is no group")
    }

    func testUngroupingPartOfAGroupFreesOnlyThatPart() {
        let old = UUID()
        let letters = word(5, group: old)
        let out = CanvasGroups.ungrouped([letters[0].id, letters[1].id], in: letters)
        XCTAssertNil(out[0].group)
        XCTAssertNil(out[1].group)
        XCTAssertEqual(out.filter { $0.group == old }.count, 3)
    }

    func testOneMemberTakenOutOfAPairLeavesNoGroupOfOne() {
        let old = UUID()
        let letters = word(2, group: old)
        let out = CanvasGroups.ungrouped([letters[0].id], in: letters)
        XCTAssertTrue(out.allSatisfy { $0.group == nil })
    }

    // MARK: - A drag is one write

    /// Moving what is held used to write the drawing back once per member —
    /// on the rendered page every write is mapped back through the markdown
    /// pane's cells, and 210 of them took five seconds a frame. The
    /// transform is worked out on one copy.
    func testManipulatingTheHeldMovesThemAndNothingElseInOneValue() {
        let size = CGSize(width: 900, height: 700)
        let letters = word(40)
        let others = [stroke(), stroke()]
        let drawing = Drawing(items: letters + others)
        let held = Set(letters.map(\.id))
        let snapshot = Dictionary(uniqueKeysWithValues: letters.map { ($0.id, $0.transform) })
        let moved = drawing.manipulated(snapshot, translate: CGVector(dx: 30, dy: -12), about: .zero, in: size)
        for (before, after) in zip(drawing.items, moved.items) {
            XCTAssertEqual(after.id, before.id)
            if held.contains(before.id) {
                XCTAssertNotEqual(after.transform, before.transform, "a held object stayed put")
            } else {
                XCTAssertEqual(after.transform, before.transform, "something not held moved")
            }
        }
        // The same answer the object-by-object loop gave.
        var oneByOne = drawing
        for index in oneByOne.items.indices {
            let item = oneByOne.items[index]
            guard let original = snapshot[item.id] else { continue }
            oneByOne.items[index].transform = CanvasEdit.transform(
                item, from: original, translate: CGVector(dx: 30, dy: -12), about: .zero, in: size)
        }
        oneByOne.reconnect(in: size)
        XCTAssertEqual(moved, oneByOne)
    }
}
