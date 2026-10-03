import XCTest
@testable import WriteMind

/// Holding several things on the layer as one (Sean, 2026-09-20: "select
/// drawn (or captured) stuff for grouping, deleting, ungrouping... toggle
/// grouping with the button on the screen or ctrl+g").
final class CanvasGroupTests: XCTestCase {
    private func stroke(_ group: UUID? = nil) -> CanvasItem {
        .stroke(Stroke(colorHex: "#000000", width: 2,
                       points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)], group: group))
    }

    private func picture(_ group: UUID? = nil) -> CanvasItem {
        .image(ImageItem(file: "a.png", group: group))
    }

    private func node(_ group: UUID? = nil) -> CanvasItem {
        .shape(ShapeItem(kind: .rectangle, colorHex: "#000000", group: group))
    }

    // MARK: - What a click picks up

    func testPickingOneMemberPicksTheWholeGroup() {
        let id = UUID()
        let items = [stroke(id), picture(id), node()]
        XCTAssertEqual(CanvasGroups.whole([items[0].id], in: items),
                       Set([items[0].id, items[1].id]))
    }

    func testSomethingInNoGroupIsItselfAlone() {
        let items = [stroke(), picture()]
        XCTAssertEqual(CanvasGroups.whole([items[0].id], in: items), Set([items[0].id]))
    }

    func testPickingNothingStaysNothing() {
        XCTAssertTrue(CanvasGroups.whole([], in: [stroke(UUID())]).isEmpty)
    }

    func testTwoGroupsTouchedAtOnceComeWholeBoth() {
        let a = UUID(), b = UUID()
        let items = [stroke(a), picture(a), node(b), stroke(b), picture()]
        let touched = Set([items[0].id, items[2].id])
        XCTAssertEqual(CanvasGroups.whole(touched, in: items),
                       Set(items.prefix(4).map(\.id)))
    }

    // MARK: - Which way the toggle goes

    func testTwoLooseThingsWouldGroup() {
        let items = [stroke(), picture()]
        XCTAssertEqual(CanvasGroups.toggle(Set(items.map(\.id)), in: items), .group)
    }

    func testAWholeGroupWouldUngroup() {
        let id = UUID()
        let items = [stroke(id), picture(id)]
        XCTAssertEqual(CanvasGroups.toggle(Set(items.map(\.id)), in: items), .ungroup)
    }

    func testOneThingAloneHasNothingToToggle() {
        let items = [stroke()]
        XCTAssertEqual(CanvasGroups.toggle([items[0].id], in: items), .nothing)
        XCTAssertEqual(CanvasGroups.toggle([], in: items), .nothing)
    }

    func testAGroupAndALooseThingWouldGroupRatherThanUngroup() {
        // The loose one joining is the whole point; taking the group apart
        // would be the wrong half of the toggle.
        let id = UUID()
        let items = [stroke(id), picture(id), node()]
        XCTAssertEqual(CanvasGroups.toggle(Set(items.map(\.id)), in: items), .group)
    }

    func testHalfAGroupWouldGroupNotUngroup() {
        // Only half of it is held, so this is not "the whole group".
        let id = UUID()
        let items = [stroke(id), picture(id), node(id)]
        XCTAssertEqual(CanvasGroups.toggle(Set([items[0].id, items[1].id]), in: items), .group)
    }

    // MARK: - Grouping

    func testGroupingGivesEveryOneOfThemTheSameNewId() throws {
        let items = [stroke(), picture(), node()]
        let out = CanvasGroups.grouped(Set(items.prefix(2).map(\.id)), in: items)
        let first = try XCTUnwrap(out[0].group)
        XCTAssertEqual(out[1].group, first)
        XCTAssertNil(out[2].group, "what was not picked keeps out of it")
    }

    /// A group is what is picked. Part of a group picked with a loose thing
    /// makes a new group of exactly those, and what is left behind in the
    /// old one stays there — a subgroup can be made out of a group, and the
    /// old rule that dragged the rest along with it is gone with the
    /// selections that were always whole (`GroupSelectionTests`).
    func testGroupingPartOfAGroupWithALooseThingTakesOnlyWhatWasPicked() throws {
        let id = UUID()
        let items = [stroke(id), picture(id), node(), node(id)]
        let out = CanvasGroups.grouped(Set([items[0].id, items[2].id]), in: items)
        let first = try XCTUnwrap(out[0].group)
        XCTAssertEqual(out[2].group, first)
        XCTAssertNotEqual(first, id, "a new group, not the old one")
        XCTAssertEqual(out[1].group, id, "what was not picked stays where it was")
        XCTAssertEqual(out[3].group, id)
    }

    func testGroupingMovesNothing() {
        let items = [stroke(), picture()]
        let out = CanvasGroups.grouped(Set(items.map(\.id)), in: items)
        XCTAssertEqual(out.map(\.transform), items.map(\.transform))
    }

    func testAGroupOfOneIsNotMade() {
        let items = [stroke(), picture()]
        XCTAssertNil(CanvasGroups.toggled([items[0].id], in: items),
                     "nothing to do, so nothing lands on the undo stack")
    }

    // MARK: - Ungrouping

    func testUngroupingTakesTheIdOffAndLeavesEverythingElse() {
        let id = UUID()
        let items = [stroke(id), picture(id)]
        let out = CanvasGroups.ungrouped(Set(items.map(\.id)), in: items)
        XCTAssertTrue(out.allSatisfy { $0.group == nil })
        XCTAssertEqual(out.map(\.transform), items.map(\.transform), "ungrouping moves nothing")
    }

    func testUngroupingLeavesAnotherGroupAlone() {
        let a = UUID(), b = UUID()
        let items = [stroke(a), picture(a), node(b), stroke(b)]
        let out = CanvasGroups.ungrouped(Set([items[0].id, items[1].id]), in: items)
        XCTAssertNil(out[0].group)
        XCTAssertNil(out[1].group)
        XCTAssertEqual(out[2].group, b)
        XCTAssertEqual(out[3].group, b)
    }

    // MARK: - The toggle, end to end

    func testGroupThenUngroupIsWhereItStarted() {
        let items = [stroke(), picture(), node()]
        let picked = Set(items.map(\.id))
        let grouped = try! XCTUnwrap(CanvasGroups.toggled(picked, in: items))
        XCTAssertTrue(grouped.allSatisfy { $0.group != nil })
        let apart = try! XCTUnwrap(CanvasGroups.toggled(picked, in: grouped))
        XCTAssertEqual(apart, items)
    }

    // MARK: - A connector goes where its nodes go, and carries no group

    func testAConnectorTakesNoGroupOfItsOwn() {
        let line = CanvasItem.connector(ConnectorItem(start: CGPoint(x: 0.1, y: 0.1),
                                                      end: CGPoint(x: 0.4, y: 0.4),
                                                      colorHex: "#000000"))
        let items = [node(), line]
        let out = CanvasGroups.grouped(Set(items.map(\.id)), in: items)
        XCTAssertNotNil(out[0].group)
        XCTAssertNil(out[1].group, "it is held by the nodes at its ends")
    }
}

/// A sidecar written before groups existed still opens.
final class GroupCodingTests: XCTestCase {
    func testASidecarWithNoGroupKeyReadsBack() throws {
        let json = """
        {"items":[
          {"kind":"stroke","stroke":{"colorHex":"#2FBF71","width":2,"points":[[0.1,0.1],[0.2,0.2]]}},
          {"kind":"image","image":{"file":"a.png","width":0.3,"aspect":1}},
          {"kind":"shape","shape":{"kind":"rectangle","center":[0.5,0.5],"width":0.2,"aspect":0.6,
                                   "colorHex":"#000000","lineWidth":2,"label":"hi"}}
        ]}
        """
        let drawing = try JSONDecoder().decode(Drawing.self, from: Data(json.utf8))
        XCTAssertEqual(drawing.items.count, 3)
        XCTAssertTrue(drawing.items.allSatisfy { $0.group == nil })
        XCTAssertEqual(drawing.items[0].stroke?.colorHex, "#2FBF71")
        XCTAssertEqual(drawing.items[1].image?.file, "a.png")
        XCTAssertEqual(drawing.items[2].shape?.label, "hi")
    }

    func testAGroupSurvivesBeingWrittenAndReadBack() throws {
        let id = UUID()
        let before = Drawing(items: [.stroke(Stroke(colorHex: "#000000", width: 2,
                                                    points: [CGPoint(x: 0, y: 0)], group: id)),
                                     .image(ImageItem(file: "a.png", group: id))])
        let data = try JSONEncoder().encode(before)
        let after = try JSONDecoder().decode(Drawing.self, from: data)
        XCTAssertEqual(after.items.map(\.group), [id, id])
    }
}
