import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WriteMind

/// THE PAD ON SCREEN, headless: real mouse and key events sent to the pad
/// view — the way the window server would — and what comes out the other
/// end on the page (Sean, 2026-10-03: "make sure i can develop wacom features
/// without a device plugged in"). Nothing here is shown on a screen.
@MainActor
final class VirtualPadViewTests: XCTestCase {
    private struct Bench {
        let rig: TabletRig
        let tablet: VirtualTablet
        let pad: VirtualPadView
        let window: NSWindow
    }

    private let size = CGSize(width: 200, height: 320)

    /// A pad in a window nobody sees, wired to the funnel as the app wires it.
    private func bench(turns: Int = 1) -> Bench {
        let rig = TabletRig(quarterTurns: turns)
        let tablet = VirtualTablet(clock: rig.clock)
        tablet.geometry = { [unowned rig] in (rig.input.extent, rig.input.quarterTurns) }
        rig.input.attach(tablet)
        let pad = VirtualPadView(frame: NSRect(origin: .zero, size: size))
        pad.tablet = tablet
        pad.quarterTurns = turns
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = pad
        return Bench(rig: rig, tablet: tablet, pad: pad, window: window)
    }

    /// A mouse event at (x, y) of the pad, from its top left.
    private func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double, at time: TimeInterval,
                       flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: size.height - y), modifierFlags: flags,
                           timestamp: time, windowNumber: 0, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }

    private func key(_ characters: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: 0)!
    }

    private func drag(_ bench: Bench, from a: (Double, Double), to b: (Double, Double), flags: NSEvent.ModifierFlags = [],
                      steps: Int = 6) {
        let pad = bench.pad, clock = bench.rig.clock
        clock.advance(by: 0.01)
        pad.mouseMoved(with: mouse(.mouseMoved, a.0, a.1, at: clock.now, flags: flags))
        clock.advance(by: 0.01)
        pad.mouseDown(with: mouse(.leftMouseDown, a.0, a.1, at: clock.now, flags: flags))
        for step in 1...steps {
            clock.advance(by: 0.01)
            let along = Double(step) / Double(steps)
            pad.mouseDragged(with: mouse(.leftMouseDragged, a.0 + (b.0 - a.0) * along, a.1 + (b.1 - a.1) * along,
                                         at: clock.now, flags: flags))
        }
        clock.advance(by: 0.01)
        pad.mouseUp(with: mouse(.leftMouseUp, b.0, b.1, at: clock.now, flags: flags))
    }

    func testThePointerIsAFractionOfThePadFromItsTopLeft() {
        let b = bench()
        let middle = b.pad.fraction(of: mouse(.mouseMoved, 100, 160, at: 0))
        XCTAssertEqual(Double(middle.x), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Double(middle.y), 0.5, accuracy: 1e-9)
        let corner = b.pad.fraction(of: mouse(.mouseMoved, 0, 0, at: 0))
        XCTAssertEqual(corner, .zero)
        let off = b.pad.fraction(of: mouse(.mouseMoved, 500, -40, at: 0))
        XCTAssertEqual(off, CGPoint(x: 1, y: 0), "past the edge is on it")
    }

    /// MOVE = HOVER, PRESS = TIP DOWN: a drag across the pad is a stroke on
    /// the page, where it was drawn.
    func testADragOnThePadIsAStrokeOnThePage() throws {
        let b = bench()
        drag(b, from: (40, 80), to: (160, 240))
        XCTAssertEqual(b.rig.page.strokes.count, 1)
        let stroke = try XCTUnwrap(b.rig.page.strokes.first)
        XCTAssertEqual(stroke.points.count, 7)
        XCTAssertEqual(Double(stroke.points[0].x), 0.2, accuracy: 1e-3)
        XCTAssertEqual(Double(stroke.points[0].y), 0.25, accuracy: 1e-3)
        XCTAssertEqual(Double(stroke.points.last?.x ?? 0), 0.8, accuracy: 1e-3)
        XCTAssertEqual(Double(stroke.points.last?.y ?? 0), 0.75, accuracy: 1e-3)
        XCTAssertTrue(b.tablet.isNear, "the pen stays near, hovering, when the nib lifts")
        XCTAssertFalse(b.tablet.isDown)
    }

    func testTheSliderIsHowHardThePenPresses() throws {
        let b = bench()
        b.tablet.pressure = 0.9
        drag(b, from: (40, 80), to: (160, 80))
        for pressure in try XCTUnwrap(b.rig.page.strokes.first?.pressures) {
            XCTAssertEqual(pressure, 0.9, accuracy: 1 / 2047)
        }
    }

    /// ⇧ HELD OVER THE PAD IS THE LOWER SWITCH: the eraser, a way to hold a
    /// switch while drawing.
    func testShiftHeldIsTheEraser() {
        let b = bench()
        drag(b, from: (40, 160), to: (160, 160))
        XCTAssertEqual(b.rig.page.strokes.count, 1)
        // The pointer hovers over the pad with ⇧ down, then goes down on it.
        b.rig.clock.advance(by: 0.01)
        b.pad.mouseMoved(with: mouse(.mouseMoved, 100, 100, at: b.rig.clock.now, flags: .shift))
        drag(b, from: (100, 100), to: (100, 220), flags: .shift)
        XCTAssertEqual(b.rig.page.strokes, [], "the line it crossed went")
        XCTAssertTrue(b.rig.page.undo())
        XCTAssertEqual(b.rig.page.strokes.count, 1)
    }

    func testOptionHeldIsTheBox() throws {
        let b = bench()
        b.rig.clock.advance(by: 0.01)
        b.pad.mouseMoved(with: mouse(.mouseMoved, 40, 64, at: b.rig.clock.now, flags: .option))
        drag(b, from: (40, 64), to: (140, 192), flags: .option)
        XCTAssertEqual(b.rig.page.strokes, [])
        let box = try XCTUnwrap(b.rig.scribe.box.rect)
        XCTAssertEqual(Double(box.width), 0.5, accuracy: 1e-3)
        XCTAssertEqual(Double(box.height), 0.4, accuracy: 1e-3)
    }

    /// Letting the key go lets the switch go: the next stroke is ink.
    func testLettingTheKeyGoMakesTheNextStrokeInkAgain() {
        let b = bench()
        b.rig.clock.advance(by: 0.01)
        b.pad.mouseMoved(with: mouse(.mouseMoved, 100, 100, at: b.rig.clock.now, flags: .shift))
        b.rig.clock.advance(by: 0.01)
        b.pad.mouseMoved(with: mouse(.mouseMoved, 100, 100, at: b.rig.clock.now))
        drag(b, from: (40, 160), to: (160, 160))
        XCTAssertEqual(b.rig.page.strokes.count, 1)
    }

    func testPressureKeysAndBrackets() {
        let b = bench()
        b.pad.keyDown(with: key("7"))
        XCTAssertEqual(b.tablet.pressure, 0.7)
        b.pad.keyDown(with: key("]"))
        XCTAssertEqual(b.tablet.pressure, 0.75, accuracy: 1e-9)
        b.pad.keyDown(with: key("["))
        b.pad.keyDown(with: key("["))
        XCTAssertEqual(b.tablet.pressure, 0.65, accuracy: 1e-9)
        b.pad.keyDown(with: key("0"))
        XCTAssertEqual(b.tablet.pressure, 1)
        b.pad.keyDown(with: key("a"))
        XCTAssertEqual(b.tablet.pressure, 1, "not a pressure key")
        b.pad.keyDown(with: key("3", flags: .command))
        XCTAssertEqual(b.tablet.pressure, 1, "⌘3 is not the pad's")
    }

    func testTheWheelIsThePressure() throws {
        let b = bench()
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 20,
                                       wheel2: 0, wheel3: 0))
        let wheel = try XCTUnwrap(NSEvent(cgEvent: cg))
        b.tablet.pressure = 0.5
        b.pad.scrollWheel(with: wheel)
        XCTAssertGreaterThan(b.tablet.pressure, 0.5, "scrolling up presses harder")
        b.pad.scrollWheel(with: wheel)
        b.pad.scrollWheel(with: wheel)
        XCTAssertLessThanOrEqual(b.tablet.pressure, 1)
    }

    func testThePadFirstTakesAClickAndAKey() {
        let b = bench()
        XCTAssertTrue(b.pad.acceptsFirstMouse(for: nil))
        XCTAssertTrue(b.pad.acceptsFirstResponder)
        XCTAssertTrue(b.pad.needsPanelToBecomeKey, "a click on the pad is how its keys are had")
        XCTAssertTrue(b.pad.isFlipped, "fractions from the top left")
    }

    /// The pad is drawn: the tablet's light where the light is, and the pen
    /// where it is. A bitmap of it has more than one colour in it.
    func testThePadDrawsTheTabletsLightAndThePen() throws {
        let b = bench()
        b.pad.frame = NSRect(origin: .zero, size: size)
        func render() throws -> NSBitmapImageRep {
            let rep = try XCTUnwrap(b.pad.bitmapImageRepForCachingDisplay(in: b.pad.bounds))
            b.pad.cacheDisplay(in: b.pad.bounds, to: rep)
            return rep
        }
        func colours(_ rep: NSBitmapImageRep) -> Set<String> {
            var seen = Set<String>()
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                        seen.insert(String(format: "%.1f %.1f %.1f", c.redComponent, c.greenComponent, c.blueComponent))
                    }
                }
            }
            return seen
        }
        let empty = colours(try render())
        XCTAssertGreaterThan(empty.count, 1, "a pad with its light and its caption")
        b.tablet.padMove(to: CGPoint(x: 0.5, y: 0.5))
        b.tablet.padDown(at: CGPoint(x: 0.5, y: 0.5))
        let down = colours(try render())
        XCTAssertNotEqual(down, empty, "the pen is drawn where it is")
    }
}

/// The panel, built and not shown.
@MainActor
final class VirtualTabletPanelTests: XCTestCase {
    private func parts() -> (TabletController, AppState) {
        let suite = "WriteMindTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = TabletController(defaults: defaults, hid: StandInHID(), input: TabletInput(), live: false)
        return (controller, AppState(defaults: defaults))
    }

    func testThePanelIsAFloatingUtilityWindowThatIsNotShownYet() throws {
        let (controller, state) = parts()
        let panel = VirtualTabletPanel.makePanel(tablet: controller.developer.virtual, developer: controller.developer,
                                                 appState: state, input: controller.input)
        XCTAssertEqual(panel.title, "Virtual Tablet")
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertFalse(panel.isVisible, "building it shows nothing")
        let content = try XCTUnwrap(panel.contentView)
        XCTAssertTrue(content is FirstMouseHostingView<VirtualTabletView>)
        XCTAssertGreaterThan(content.fittingSize.width, 560, "the pad beside its controls")
        XCTAssertGreaterThan(content.fittingSize.height, 330)
        XCTAssertLessThan(content.fittingSize.height, 700, "a small window, not a page")
    }

    /// The panel's contents, laid out and drawn without a screen: the pad and
    /// the controls are there.
    func testThePanelsContentsAreLaidOutAndDrawn() throws {
        let (controller, state) = parts()
        let hosting = NSHostingView(rootView: VirtualTabletView(tablet: controller.developer.virtual,
                                                                developer: controller.developer, appState: state,
                                                                input: controller.input))
        hosting.frame = NSRect(x: 0, y: 0, width: 660, height: 480)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let hit = view as? T { return hit }
            for sub in view.subviews { if let hit = find(type, in: sub) { return hit } }
            return nil
        }
        let pad = try XCTUnwrap(find(VirtualPadView.self, in: hosting), "the pad is in the panel")
        XCTAssertTrue(pad.tablet === controller.developer.virtual)
        XCTAssertEqual(pad.frame.height, VirtualTabletView.padBox, accuracy: 1, "a tall pad fills its box's height")
        XCTAssertEqual(pad.frame.width / pad.frame.height, 0.625, accuracy: 0.02,
                       "the pad is the tablet's turned shape, one quarter turn clockwise")
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        var colours = Set<String>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    colours.insert(String(format: "%.1f %.1f %.1f %.1f", c.redComponent, c.greenComponent,
                                          c.blueComponent, c.alphaComponent))
                }
            }
        }
        XCTAssertGreaterThan(colours.count, 3, "the pad, its light, the controls and their text are drawn — not a blank")
    }

    /// HIDING THE PANEL, OR CLOSING IT, TAKES THE PEN AWAY: the pen is not
    /// left hovering, near a page, with no window to take it away from.
    func testHidingOrClosingThePanelTakesThePenAway() {
        let clock = VirtualClock()
        let tablet = VirtualTablet(clock: clock)
        tablet.geometry = { (TabletExtent(width: 15200, height: 9500), 1) }
        let panel = VirtualTabletPanel()
        panel.attach(tablet)
        XCTAssertFalse(panel.isVisible)

        tablet.padMove(to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertTrue(tablet.isNear, "the premise: the pen is near")
        panel.hide()
        XCTAssertFalse(tablet.isNear, "hidden: the pen goes out of reach")
        XCTAssertNil(tablet.padPoint)

        tablet.padMove(to: CGPoint(x: 0.4, y: 0.4))
        tablet.padDown(at: CGPoint(x: 0.4, y: 0.4))
        XCTAssertTrue(tablet.isDown)
        panel.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertFalse(tablet.isNear, "closed with the red button: the pen goes with it")
        XCTAssertFalse(tablet.isDown, "and a nib that was down is lifted")
    }

}
