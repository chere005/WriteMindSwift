import XCTest
@testable import WriteMind

/// THE PEN'S STATE MACHINE, WRITTEN AS THE GESTURE (Sean, 2026-10-03: "make
/// sure i can develop wacom features without a device plugged in"). These
/// were hand-built readings with a `side:` and an `upper:` and a time on
/// every line (`TabletPenTests.at`); as a script they read as what the hand
/// does — and the rules they hold are the same, assertion for assertion. The
/// pen alone, with exact frames (`PenBench`); the same gestures through the
/// whole path are in `TabletScriptTests`.
@MainActor
final class TabletPenGestureTests: XCTestCase {
    /// A stroke is hover, down, drags, up, hover; the pressure is what the
    /// nib pressed with, and the lift has none.
    func testAStrokeIsHoverDownDragUpHover() {
        let bench = PenBench()
        bench.script.hover(0.5, 0.5)
        XCTAssertEqual(bench.phases, [.hover])
        bench.script.down(0.3).move(0.5, 0.55, pressure: 0.6).up().move(0.5, 0.55)
        XCTAssertEqual(bench.phases, [.hover, .down, .drag, .up, .hover])
        XCTAssertEqual(bench.samples.map(\.pressure), [0, 0.3, 0.6, 0, 0], "the nib has left at the up")
        XCTAssertTrue(bench.samples.allSatisfy { !$0.sideSwitch && $0.inProximity })
    }

    /// THE UPPER SWITCH HELD AS THE NIB GOES DOWN IS A SELECTION, FROM THE
    /// NIB'S DOWN UNTIL NIB AND SWITCH ARE BOTH UP, and let go mid-drag it is
    /// still the box (Sean, 2026-10-03: "the other button is hold to drag a
    /// selector box"). The switch alone, in the air, starts nothing: pressed
    /// and let go there twice it is a command, which it could not be while
    /// it also began a box.
    func testTheUpperSwitchHeldAsTheNibGoesDownMakesASelection() {
        let bench = PenBench()
        let pen = bench.script
        pen.hover(0.5, 0.5).press(.upper)
        XCTAssertEqual(bench.phases.last, .hover, "the switch alone, in the air, began a box")
        XCTAssertFalse(bench.state.engaged)

        pen.down(0.5)
        XCTAssertEqual(bench.phases.last, .down)
        XCTAssertEqual(bench.samples.last?.sideSwitch, true)
        XCTAssertEqual(bench.samples.last?.eraser, false)
        pen.move(0.55, 0.5)
        XCTAssertEqual(bench.samples.last?.sideSwitch, true)
        pen.release(.upper)
        XCTAssertEqual(bench.phases.last, .drag)
        XCTAssertEqual(bench.samples.last?.sideSwitch, true, "the switch let go mid-drag is still the box")
        pen.up()
        XCTAssertEqual(bench.phases.last, .up)
        XCTAssertEqual(bench.samples.last?.sideSwitch, true)
        pen.move(0.55, 0.5)
        XCTAssertEqual(bench.phases.last, .hover, "and letting go after a box is no click")
        XCTAssertEqual(bench.samples.last?.sideSwitch, false, "a hover is no selection")

        // Ink that has begun stays ink if the switch is pressed under it.
        pen.down(0.5)
        XCTAssertEqual(bench.samples.last?.sideSwitch, false)
        pen.press(.upper)
        XCTAssertEqual(bench.samples.last?.sideSwitch, false)
    }

    /// THE LOWER SWITCH HELD AS THE NIB GOES DOWN IS AN ERASER (Sean,
    /// 2026-10-03: "press and hold to make it an eraser that deletes entire
    /// strokes"), latched for the stroke as the box is, and never a box.
    func testTheLowerSwitchHeldAsTheNibGoesDownMakesAnEraser() {
        let bench = PenBench()
        let pen = bench.script
        pen.hover(0.5, 0.5).press(.lower)
        XCTAssertEqual(bench.phases.last, .hover, "the switch alone, in the air, erased")

        pen.down(0.5)
        XCTAssertEqual(bench.phases.last, .down)
        XCTAssertEqual(bench.samples.last?.eraser, true)
        XCTAssertEqual(bench.samples.last?.sideSwitch, false, "an eraser is no box")
        pen.move(0.55, 0.5)
        XCTAssertEqual(bench.samples.last?.eraser, true)
        pen.release(.lower)
        XCTAssertEqual(bench.samples.last?.eraser, true, "the switch let go mid-stroke: the stroke is still the eraser")
        pen.up()
        XCTAssertEqual(bench.phases.last, .up)
        XCTAssertEqual(bench.samples.last?.eraser, true)
        pen.move(0.55, 0.5)
        XCTAssertEqual(bench.samples.last?.eraser, false, "a hover erases nothing")
        XCTAssertEqual(bench.phases.last, .hover, "and letting go after an eraser is no click")

        // Ink that has begun stays ink if the switch is pressed under it.
        pen.down(0.5)
        XCTAssertEqual(bench.samples.last?.eraser, false)
        pen.press(.lower)
        XCTAssertEqual(bench.samples.last?.eraser, false)
    }

    /// A SIDE SWITCH PRESSED TWICE IN THE AIR IS A COMMAND (Sean, 2026-10-03:
    /// "a double press of that same button is undo", "double tap to redo"):
    /// two quick taps with the nib up the whole time. It says which switch,
    /// it fires as the second is LET GO — so that holding it and putting the
    /// nib down can still be the eraser or the box — and once, however far
    /// the pen moved meanwhile. One tap alone is nothing.
    func testADoublePressOfASwitchInTheAirIsTheCommandAndASingleOneNothing() {
        let bench = PenBench()
        let pen = bench.script
        pen.hover(0.5, 0.5)
        XCTAssertEqual(bench.phases, [.hover])
        pen.press(.lower)
        XCTAssertEqual(bench.phases.last, .hover, "pressed: nothing yet")
        XCTAssertEqual(bench.state.armed, .lower)
        pen.move(0.55, 0.5)
        XCTAssertEqual(bench.phases.last, .hover, "held: it does not repeat")
        pen.release(.lower).move(0.9, 0.9)
        XCTAssertEqual(bench.phases.last, .hover, "one tap alone is nothing")

        pen.press(.lower)
        XCTAssertEqual(bench.phases.last, .hover)
        let before = bench.mark
        pen.release(.lower)
        let click = bench.since(before)
        XCTAssertEqual(click.map(\.phase), [.click(.lower)], "the lower switch, pressed twice in the air")
        XCTAssertEqual(click.first?.sideSwitch, false, "a command, not a selection")
        XCTAssertEqual(click.first?.eraser, false)
        XCTAssertEqual(click.first?.pressure, 0)
        XCTAssertEqual(click.first?.inProximity, true, "the marker stays where the pen is")
        XCTAssertFalse(bench.state.engaged)
        XCTAssertNil(bench.state.armed)
        pen.move(0.9, 0.9)
        XCTAssertEqual(bench.phases.last, .hover, "once a command")

        // A third tap is the first of the next pair.
        pen.press(.lower).release(.lower)
        XCTAssertEqual(bench.phases.last, .hover)

        pen.tap(.upper)
        pen.tap(.upper)
        XCTAssertEqual(bench.phases.last, .click(.upper), "the upper switch, twice")
    }

    /// Two taps are a double press only if they are the SAME switch, close
    /// together, and both TAPS — a hold is the eraser or the box, never half
    /// of a command.
    func testOnlyTwoQuickTapsOfOneSwitchAreADoublePress() {
        let bench = PenBench()
        let pen = bench.script
        pen.hover(0.5, 0.5)
        var clicks: Int { bench.samples.filter { if case .click = $0.phase { return true } else { return false } }.count }

        // Different switches.
        pen.tap(.lower).tap(.upper)
        XCTAssertEqual(clicks, 0, "a tap of each is no command")

        // Too far apart.
        pen.wait(1).tap(.lower).wait(1).tap(.lower)
        XCTAssertEqual(clicks, 0, "a second tap a second later")

        // A hold between them.
        pen.wait(1).tap(.lower).press(.lower).wait(1).release(.lower)
        XCTAssertEqual(clicks, 0, "the second press was held, not tapped")
        pen.press(.lower).release(.lower)
        XCTAssertEqual(clicks, 0, "and a hold leaves no tap behind it")

        // And the real thing, right after.
        pen.wait(1).tap(.lower).tap(.lower)
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(bench.phases.last, .click(.lower))
    }

    /// NOT WHILE THE NIB IS DOWN: a switch pressed and let go under a
    /// stroke of ink, or under a box, is no command — the stroke goes on as
    /// it was — and one pressed under ink and let go after the lift is
    /// none either.
    func testASwitchPressedWhileTheNibIsDownIsNoClick() {
        // Under ink.
        var bench = PenBench()
        var pen = bench.script
        pen.hover(0.5, 0.5)
        var mark = bench.mark
        pen.down(0.5).press(.lower).release(.lower).press(.upper).release(.upper).up()
        XCTAssertEqual(bench.since(mark).map(\.phase), [.down, .drag, .drag, .drag, .drag, .up],
                       "a switch under the ink did something")

        // Under a box: the lower one pressed while the upper holds the box.
        bench = PenBench()
        pen = bench.script
        pen.hover(0.5, 0.5).press(.upper)
        mark = bench.mark
        pen.down(0.5).press(.lower).release(.lower).up().release(.upper)
        XCTAssertEqual(bench.since(mark).map(\.phase), [.down, .drag, .drag, .drag, .up],
                       "a switch under the box did something")

        // Pressed under ink, let go after the lift.
        bench = PenBench()
        pen = bench.script
        pen.hover(0.5, 0.5).down(0.5).press(.upper)
        mark = bench.mark
        pen.up()
        XCTAssertEqual(bench.since(mark).map(\.phase), [.up])
        mark = bench.mark
        pen.release(.upper)
        XCTAssertEqual(bench.since(mark).map(\.phase), [.hover], "the nib touched while it was held")
    }

    /// The marker says what the nib WILL be as soon as a switch is held.
    func testHoldingASwitchInTheAirSaysWhatTheNibWillBe() {
        let bench = PenBench()
        bench.script.hover(0.5, 0.5).press(.lower)
        XCTAssertEqual(bench.samples.last?.holding, .lower)
        bench.script.release(.lower).press(.upper)
        XCTAssertEqual(bench.samples.last?.holding, .upper)
        bench.script.release(.upper)
        XCTAssertNil(bench.samples.last?.holding)
    }

    /// A pressure ramp is the exact pressure of each report, never rounded.
    func testAPressureRampIsExactOnThePenAlone() {
        let bench = PenBench()
        bench.script.stroke((0..<5).map { (0.1 + 0.1 * Double($0), 0.5) }, pressure: 0.2, to: 0.6)
        let pressures = bench.samples.filter { $0.phase == .down || $0.phase == .drag }.map(\.pressure)
        XCTAssertEqual(pressures.count, 5)
        for (got, want) in zip(pressures, [0.2, 0.3, 0.4, 0.5, 0.6]) { XCTAssertEqual(got, want, accuracy: 1e-12) }
    }
}
