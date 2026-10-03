import Combine
import XCTest
@testable import WriteMind

/// EVERY PEN MODE, WITH NO TABLET (Sean, 2026-10-03: "make sure i can develop
/// wacom features without a device plugged in"): the gesture written as a
/// chain, through the virtual tablet's own pen, the one door, the real packet
/// parser and the real pen state machine, into the page and into the
/// notebook. No sleeping: the clock is the test's.
@MainActor
final class TabletScriptPageTests: XCTestCase {
    private func assertPoint(_ got: CGPoint, _ x: Double, _ y: Double, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(got.x), x, accuracy: 1e-3, message, file: file, line: line)
        XCTAssertEqual(Double(got.y), y, accuracy: 1e-3, message, file: file, line: line)
    }

    private let stroke = [(0.2, 0.3), (0.4, 0.35), (0.6, 0.4), (0.8, 0.3)]

    // MARK: Ink

    func testAStrokeIsHoverDownDragsUpAndOneStrokeOnThePage() throws {
        let rig = TabletRig()
        rig.pen.stroke(stroke, pressure: 0.5)
        XCTAssertEqual(rig.phases, [.hover, .down, .drag, .drag, .drag, .up])
        XCTAssertEqual(rig.page.strokes.count, 1)
        let written = try XCTUnwrap(rig.page.strokes.first)
        XCTAssertEqual(written.points.count, 4, "the lift is no point")
        for (point, want) in zip(written.points, stroke) { assertPoint(point, want.0, want.1) }
        XCTAssertEqual(written.pressures?.count, 4)
        for pressure in written.pressures ?? [] { XCTAssertEqual(pressure, 0.5, accuracy: 1 / 2047) }
    }

    /// The same page fractions whichever way the tablet is held: a gesture is
    /// written where it lands on the page, and the turn is the pen path's
    /// own business.
    func testTheGestureLandsWhereItIsWrittenWhicheverWayTheTabletIsHeld() throws {
        for turns in 0...3 {
            let rig = TabletRig(quarterTurns: turns)
            rig.pen.stroke(stroke)
            let written = try XCTUnwrap(rig.page.strokes.first, "turn \(turns)")
            for (point, want) in zip(written.points, stroke) { assertPoint(point, want.0, want.1, "turn \(turns)") }
        }
    }

    /// A PRESSURE RAMP: the pressure of each point is what the nib pressed
    /// with there, as the report's 2047 steps have it.
    func testAPressureRampComesOutAsARampOfPressures() throws {
        let rig = TabletRig()
        let points = (0..<10).map { (0.1 + 0.08 * Double($0), 0.5) }
        rig.pen.stroke(points, pressure: 0.1, to: 1.0)
        let pressures = try XCTUnwrap(rig.page.strokes.first?.pressures)
        XCTAssertEqual(pressures.count, 10)
        XCTAssertEqual(pressures.first ?? 0, 0.1, accuracy: 1 / 2047)
        XCTAssertEqual(pressures.last ?? 0, 1.0, accuracy: 1 / 2047)
        XCTAssertEqual(pressures, pressures.sorted(), "never lighter than the point before")
        XCTAssertEqual(Set(pressures).count, 10, "every point its own pressure")
    }

    func testATapIsOnePoint() throws {
        let rig = TabletRig()
        rig.pen.hover(0.5, 0.5).down(0.6).up()
        XCTAssertEqual(rig.page.strokes.first?.points.count, 1)
    }

    // MARK: The eraser and the box

    /// THE LOWER SWITCH HELD, THEN THE NIB: an eraser that deletes whole
    /// strokes, as one step.
    func testTheLowerSwitchHeldMakesTheNibAnEraserThatTakesWholeStrokes() {
        let rig = TabletRig()
        rig.pen.stroke([(0.2, 0.5), (0.8, 0.5)])
        rig.pen.stroke([(0.2, 0.9), (0.8, 0.9)])
        XCTAssertEqual(rig.page.strokes.count, 2)
        let steps = rig.page.history.count

        rig.pen.hover(0.5, 0.3).hold(.lower) { rig.pen.down().line(to: 0.5, 0.7).up() }
        XCTAssertEqual(rig.page.strokes.count, 1, "the line the nib crossed goes, whole")
        XCTAssertEqual(rig.page.history.count, steps + 1, "one erasure is one step")
        XCTAssertNil(rig.scribe.stroke, "an eraser leaves no ink")

        XCTAssertTrue(rig.page.undo())
        XCTAssertEqual(rig.page.strokes.count, 2)
    }

    /// WITHOUT the switch the same nib is ink: the same path writes a stroke.
    func testTheSameNibWithNoSwitchWritesInk() {
        let rig = TabletRig()
        rig.pen.stroke([(0.2, 0.5), (0.8, 0.5)])
        rig.pen.hover(0.5, 0.3).down().line(to: 0.5, 0.7).up()
        XCTAssertEqual(rig.page.strokes.count, 2)
    }

    func testTheUpperSwitchHeldMakesTheNibABox() throws {
        let rig = TabletRig()
        rig.pen.hover(0.2, 0.2).hold(.upper) { rig.pen.down().line(to: 0.7, 0.6).up() }
        XCTAssertEqual(rig.page.strokes, [], "a box is no ink")
        let box = try XCTUnwrap(rig.scribe.box.rect)
        assertPoint(box.origin, 0.2, 0.2)
        XCTAssertEqual(Double(box.width), 0.5, accuracy: 1e-3)
        XCTAssertEqual(Double(box.height), 0.4, accuracy: 1e-3)
    }

    /// A tap with the box's switch held puts the box away.
    func testAClickWithTheUpperSwitchHeldPutsTheBoxAway() {
        let rig = TabletRig()
        rig.pen.hover(0.2, 0.2).hold(.upper) { rig.pen.down().line(to: 0.7, 0.6).up() }
        XCTAssertNotNil(rig.scribe.box.rect)
        rig.pen.hover(0.9, 0.9).hold(.upper) { rig.pen.down().up() }
        XCTAssertNil(rig.scribe.box.rect)
    }

    // MARK: Undo and redo

    /// A DOUBLE PRESS OF THE LOWER SWITCH IS UNDO, OF THE UPPER REDO.
    func testADoublePressOfTheLowerSwitchIsUndoAndOfTheUpperRedo() {
        let rig = TabletRig()
        rig.pen.stroke(stroke)
        rig.pen.hover(0.5, 0.5).doublePress(.lower)
        XCTAssertEqual(rig.page.strokes, [], "undone")
        XCTAssertTrue(rig.page.canRedo)
        rig.pen.doublePress(.upper)
        XCTAssertEqual(rig.page.strokes.count, 1, "redone")
        XCTAssertFalse(rig.page.canRedo)
    }

    func testAnUndoIsOneStepAndTheNextDoublePressTakesTheNext() {
        let rig = TabletRig()
        rig.pen.stroke(stroke).stroke([(0.1, 0.8), (0.9, 0.8)])
        rig.pen.doublePress(.lower)
        XCTAssertEqual(rig.page.strokes.count, 1)
        rig.pen.wait(1).doublePress(.lower)
        XCTAssertEqual(rig.page.strokes.count, 0)
    }

    /// A single tap is nothing; so are two taps too far apart, a hold between
    /// them, and two different switches — and the real double press right
    /// after still is.
    func testOnlyTwoQuickTapsOfOneSwitchAreACommand() {
        let rig = TabletRig()
        rig.pen.stroke(stroke).hover(0.5, 0.5)

        rig.pen.tap(.lower)
        XCTAssertEqual(rig.page.strokes.count, 1, "one tap")

        rig.pen.wait(1).tap(.lower)
        XCTAssertEqual(rig.page.strokes.count, 1, "two taps a second apart")

        rig.pen.wait(1).tap(.lower).tap(.upper)
        XCTAssertEqual(rig.page.strokes.count, 1, "a tap of each")

        rig.pen.wait(1).tap(.lower).press(.lower).wait(0.6).release(.lower).tap(.lower)
        XCTAssertEqual(rig.page.strokes.count, 1, "a hold between them is the eraser's, never half of a command")

        rig.pen.wait(1).tap(.lower).tap(.lower)
        XCTAssertEqual(rig.page.strokes.count, 0, "two quick taps of one switch")
    }

    /// Two taps of the upper one, one after the other, are redo.
    func testTwoTapsOfTheUpperSwitchAreRedo() {
        let rig = TabletRig()
        rig.pen.stroke(stroke).doublePress(.lower)
        XCTAssertEqual(rig.page.strokes.count, 0)
        rig.pen.tap(.upper).tap(.upper)
        XCTAssertEqual(rig.page.strokes.count, 1)
    }

    /// With nothing to take back, or put back, a double press does nothing.
    func testADoublePressWithNothingToUndoDoesNothing() {
        let rig = TabletRig()
        rig.pen.hover(0.5, 0.5).doublePress(.lower).doublePress(.upper)
        XCTAssertEqual(rig.page.strokes, [])
        XCTAssertFalse(rig.page.canUndo)
        XCTAssertFalse(rig.page.canRedo)
    }

    // MARK: The marker

    func testTheMarkerSaysWhatTheNibWillBeAsSoonAsTheSwitchIsHeld() throws {
        let rig = TabletRig()
        rig.pen.hover(0.5, 0.5)
        XCTAssertEqual(TabletHoverMarker.mode(of: try XCTUnwrap(rig.input.pen)), .ink)
        rig.pen.press(.lower)
        XCTAssertEqual(TabletHoverMarker.mode(of: try XCTUnwrap(rig.input.pen)), .eraser)
        rig.pen.release(.lower).press(.upper)
        XCTAssertEqual(TabletHoverMarker.mode(of: try XCTUnwrap(rig.input.pen)), .box)
        rig.pen.leave()
        XCTAssertNil(rig.input.pen, "out of reach: no marker")
    }

    // MARK: The funnel

    /// The script is the funnel's: a pen that is switched off writes nothing.
    func testWithTheDeveloperSwitchOffTheScriptWritesNothing() {
        let rig = TabletRig(developerOn: false)
        rig.pen.stroke(stroke)
        XCTAssertEqual(rig.page.strokes, [])
        XCTAssertEqual(rig.samples, [])
        // The control: the same script, switched on, writes.
        rig.input.policy.developerOn = true
        rig.pen.stroke(stroke)
        XCTAssertEqual(rig.page.strokes.count, 1)
    }

    func testARealTabletPluggedInSilencesTheScript() {
        let rig = TabletRig()
        rig.input.policy.realConnected = true
        rig.pen.stroke(stroke)
        XCTAssertEqual(rig.page.strokes, [])
        // The control: unplugged again, the same script writes.
        rig.input.policy.realConnected = false
        rig.pen.stroke(stroke)
        XCTAssertEqual(rig.page.strokes.count, 1)
    }
}

/// The notebook as the target: the tablet fitted onto the notes, the note's
/// own strokes, the layer's marquee and eraser, the note's undo and redo.
@MainActor
final class TabletScriptNotebookTests: XCTestCase {
    private let stroke = [(0.2, 0.3), (0.4, 0.35), (0.6, 0.4), (0.8, 0.3)]

    func testTheStrokeGoesIntoTheNoteAndNotOntoThePage() throws {
        let rig = TabletRig(target: .notebook, notes: true)
        rig.pen.stroke(stroke, pressure: 0.5)
        let notes = try XCTUnwrap(rig.notes)
        XCTAssertEqual(notes.strokes.count, 1)
        XCTAssertEqual(rig.page.strokes, [], "the page is left as it is")
        let written = try XCTUnwrap(notes.strokes.first)
        XCTAssertEqual(written.points.count, 4)
        let place = try XCTUnwrap(rig.notebook.place)
        for (point, want) in zip(written.points, stroke) {
            let expected = place.strokePoint(CGPoint(x: want.0, y: want.1))
            XCTAssertEqual(Double(point.x), Double(expected.x), accuracy: 1e-3)
            XCTAssertEqual(Double(point.y), Double(expected.y), accuracy: 1e-3)
        }
        XCTAssertTrue(notes.store.canUndoDrawing)
        XCTAssertEqual(notes.store.drawingSteps, 1, "one stroke, one step")
    }

    /// FIT, OR REAL SIZE: the same point on the tablet lands in two places
    /// on the notes, by the two rules.
    func testFitAndRealSizeLandTheSamePenInTwoPlaces() throws {
        func landing(_ scale: NotebookScale) throws -> CGPoint {
            let rig = TabletRig(target: .notebook, notes: true)
            rig.notes?.place(scale: scale)
            rig.pen.hover(0.25, 0.25).down().up()
            return try XCTUnwrap(rig.notes?.strokes.first?.points.first)
        }
        let fit = try landing(.fit), real = try landing(.real)
        let place = NotebookPlace(pane: CGSize(width: 800, height: 600), scroll: 0,
                                  aspect: 0.625, scale: .fit)
        var big = place
        big.scale = .real
        big.millimetres = CGSize(width: 95, height: 152)
        let wantFit = place.strokePoint(CGPoint(x: 0.25, y: 0.25))
        let wantReal = big.strokePoint(CGPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(Double(fit.x), Double(wantFit.x), accuracy: 1e-3)
        XCTAssertEqual(Double(fit.y), Double(wantFit.y), accuracy: 1e-3)
        XCTAssertEqual(Double(real.x), Double(wantReal.x), accuracy: 1e-3)
        XCTAssertEqual(Double(real.y), Double(wantReal.y), accuracy: 1e-3)
        XCTAssertNotEqual(fit.x, real.x, accuracy: 0.01, "Fit and Real size are two different mappings")
    }

    func testTheLowerSwitchHeldErasesWholeStrokesOfTheNote() throws {
        let rig = TabletRig(target: .notebook, notes: true)
        let notes = try XCTUnwrap(rig.notes)
        rig.pen.stroke([(0.2, 0.5), (0.8, 0.5)])
        rig.pen.stroke([(0.2, 0.9), (0.8, 0.9)])
        XCTAssertEqual(notes.strokes.count, 2)

        rig.pen.hover(0.5, 0.3).hold(.lower) { rig.pen.down().line(to: 0.5, 0.7).up() }
        XCTAssertEqual(notes.strokes.count, 1, "the line the nib crossed goes, whole, and the other stays")
        // The step the layer takes for an erasure is the layer's own
        // (`TabletEraseLayerTests`); the rig's stand-in takes one too, and a
        // count asserted on it would test the stand-in. What the note's undo
        // does with it is the store's.
        XCTAssertTrue(notes.store.undoDrawing())
        XCTAssertEqual(notes.strokes.count, 2, "one ⌘Z brings it back")
    }

    func testTheUpperSwitchHeldPicksWithTheMarqueeAndWritesNothing() throws {
        let rig = TabletRig(target: .notebook, notes: true)
        let notes = try XCTUnwrap(rig.notes)
        rig.pen.stroke([(0.2, 0.2), (0.3, 0.2)])
        rig.pen.stroke([(0.2, 0.8), (0.3, 0.8)])
        let first = try XCTUnwrap(notes.strokes.first?.id)
        let ink = notes.strokes.count

        rig.pen.hover(0.1, 0.1).hold(.upper) { rig.pen.down().line(to: 0.5, 0.4).up() }
        XCTAssertEqual(notes.selection, [first], "what the marquee touches, and only that")
        XCTAssertEqual(notes.strokes.count, ink, "a marquee writes nothing")
    }

    func testADoublePressIsTheNotesDrawingUndoAndRedo() throws {
        let rig = TabletRig(target: .notebook, notes: true)
        let notes = try XCTUnwrap(rig.notes)
        rig.pen.stroke(stroke)
        XCTAssertEqual(notes.strokes.count, 1)
        rig.pen.hover(0.5, 0.5).doublePress(.lower)
        XCTAssertEqual(notes.strokes.count, 0, "the lower switch, twice, took the stroke back")
        XCTAssertTrue(notes.store.canRedoDrawing)
        rig.pen.doublePress(.upper)
        XCTAssertEqual(notes.strokes.count, 1, "and the upper put it back")
        XCTAssertEqual(rig.page.strokes, [], "never the page's")
    }

    /// Switching the target in the middle sends the next stroke to the other.
    func testAimingTheNibAtThePageSendsTheNextStrokeThere() throws {
        let rig = TabletRig(target: .notebook, notes: true)
        let notes = try XCTUnwrap(rig.notes)
        rig.pen.stroke(stroke)
        rig.input.aim(at: .page)
        rig.pen.stroke(stroke)
        XCTAssertEqual(notes.strokes.count, 1)
        XCTAssertEqual(rig.page.strokes.count, 1)
    }
}

/// The script is the pen's state machine alone, too, with exact frames.
@MainActor
final class TabletScriptPenBenchTests: XCTestCase {
    func testTheSamePenTheStateMachineAlone() {
        let bench = PenBench()
        bench.script.hover(0.5, 0.5).down(0.3).move(0.6, 0.5, pressure: 0.6).up()
        XCTAssertEqual(bench.phases, [.hover, .down, .drag, .up])
        XCTAssertEqual(bench.samples[1].pressure, 0.3, "exact, not the report's 614/2047")
        XCTAssertEqual(bench.samples[2].pressure, 0.6)
    }

    func testAHoldIsTheEraserAndADoublePressIsAClick() {
        let bench = PenBench()
        bench.script.hover(0.5, 0.5)
        let mark = bench.mark
        bench.script.hold(.lower) { bench.script.down().up() }
        XCTAssertEqual(bench.since(mark).map(\.phase), [.hover, .down, .up, .hover])
        XCTAssertEqual(bench.since(mark).map(\.eraser), [false, true, true, false])
        let after = bench.mark
        bench.script.doublePress(.upper)
        XCTAssertEqual(bench.since(after).last?.phase, .click(.upper))
    }
}
