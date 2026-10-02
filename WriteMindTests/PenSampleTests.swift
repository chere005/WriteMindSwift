import AppKit
import XCTest
@testable import WriteMind

/// The nib's pressure, off the events a Wacom pen really sends: left-mouse
/// events whose subtype is `.tabletPoint` (measured on Sean's One by Wacom,
/// 2026-10-02). The events here are built the way the system builds them —
/// a CGEvent with the subtype and pressure fields set, then `NSEvent(cgEvent:)`
/// — so what is tested is AppKit's own reading of them, not a stand-in.
final class PenSampleTests: XCTestCase {
    private func event(_ type: CGEventType, subtype: Int64, pressure: Double) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type,
                                       mouseCursorPosition: CGPoint(x: 120, y: 80), mouseButton: .left))
        cg.setIntegerValueField(.mouseEventSubtype, value: subtype)
        cg.setDoubleValueField(.mouseEventPressure, value: pressure)
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    /// A mouse event's pressure field holds 256 levels — 0.42 goes in and
    /// 107/255 comes out (measured here, 2026-10-02) — which is also about
    /// how many distinct levels the One by Wacom showed in a session.
    private static let level = 1.0 / 255

    /// kCGEventMouseSubtypeDefault, …TabletPoint, and the trackpad's touch.
    private let mouse: Int64 = 0, tablet: Int64 = 1, touch: Int64 = 3

    private func pressure(_ sample: PenSample?, file: StaticString = #filePath, line: UInt = #line) -> Double? {
        guard case .pen(let pressure)? = sample else {
            XCTFail("not a pen: \(String(describing: sample))", file: file, line: line)
            return nil
        }
        return pressure
    }

    func testAPensDragCarriesItsPressure() throws {
        let drag = try event(.leftMouseDragged, subtype: tablet, pressure: 0.42)
        XCTAssertEqual(drag.subtype, .tabletPoint, "the CGEvent field is what AppKit reads the subtype from")
        XCTAssertEqual(try XCTUnwrap(pressure(PenSample.reading(drag))), 0.42, accuracy: Self.level)
    }

    func testThePensDownAndUpAreThePenToo() throws {
        let down = try event(.leftMouseDown, subtype: tablet, pressure: 0.2)
        let up = try event(.leftMouseUp, subtype: tablet, pressure: 0)
        XCTAssertEqual(try XCTUnwrap(pressure(PenSample.reading(down))), 0.2, accuracy: Self.level)
        XCTAssertEqual(try XCTUnwrap(pressure(PenSample.reading(up))), 0, accuracy: Self.level)
    }

    func testAMouseDragIsTheMouseWhateverItsPressure() throws {
        XCTAssertEqual(PenSample.reading(try event(.leftMouseDragged, subtype: mouse, pressure: 1)), .mouse)
        XCTAssertEqual(PenSample.reading(try event(.leftMouseDown, subtype: mouse, pressure: 1)), .mouse)
    }

    /// A Force Touch trackpad reports a pressure of its own — a click, not
    /// a nib — and must draw the line a mouse draws.
    func testATrackpadsForceIsNotANib() throws {
        XCTAssertEqual(PenSample.reading(try event(.leftMouseDragged, subtype: touch, pressure: 0.7)), .mouse)
    }

    /// The pen hovering over the tablet is a mouseMoved WITH the tablet
    /// subtype. It says nothing about the nib, and must not move the
    /// reader off what it knew.
    func testAHoverSaysNothing() throws {
        XCTAssertNil(PenSample.reading(try event(.mouseMoved, subtype: tablet, pressure: 0.5)))
        XCTAssertNil(PenSample.reading(try event(.mouseMoved, subtype: mouse, pressure: 0)))
        // The side switch is the right button; it is not ink.
        XCTAssertNil(PenSample.reading(try event(.rightMouseDown, subtype: tablet, pressure: 0.5)))
    }

    /// A pure tablet event — one of the tablet's own type, should the
    /// driver ever send the nib that way — is the pen.
    func testAPureTabletEventIsThePen() throws {
        let cg = try XCTUnwrap(CGEvent(source: nil))
        cg.type = .tabletPointer
        cg.setDoubleValueField(.tabletEventPointPressure, value: 0.6)
        cg.setDoubleValueField(.mouseEventPressure, value: 0.6)
        let tabletEvent = try XCTUnwrap(NSEvent(cgEvent: cg))
        XCTAssertEqual(tabletEvent.type, .tabletPoint)
        XCTAssertEqual(try XCTUnwrap(pressure(PenSample.reading(tabletEvent))), 0.6, accuracy: 1e-3)
    }

    /// Reading `.pressure` off a hover is not safe, so the reading must
    /// never ASK — and nor should it ask a plain mouse, whose pressure
    /// means nothing here. A spy that records the question proves it.
    private final class Spy: PenEvent {
        let type: NSEvent.EventType
        let subtype: NSEvent.EventSubtype
        var asked = false
        init(_ type: NSEvent.EventType, _ subtype: NSEvent.EventSubtype) {
            self.type = type
            self.subtype = subtype
        }
        var pressure: Float { asked = true; return 0.5 }
    }

    func testPressureIsNeverAskedOfAHoverOrAMouse() {
        let hover = Spy(.mouseMoved, .tabletPoint)
        XCTAssertNil(PenSample.reading(hover))
        XCTAssertFalse(hover.asked, "pressure was read off a mouseMoved")

        let mouseDrag = Spy(.leftMouseDragged, .mouseEvent)
        XCTAssertEqual(PenSample.reading(mouseDrag), .mouse)
        XCTAssertFalse(mouseDrag.asked)

        let penDrag = Spy(.leftMouseDragged, .tabletPoint)
        XCTAssertEqual(PenSample.reading(penDrag), .pen(pressure: 0.5))
        XCTAssertTrue(penDrag.asked, "the spy has to be able to see a question")
    }

    func testAPressureOutOfRangeIsClamped() {
        final class Odd: PenEvent {
            let type = NSEvent.EventType.tabletPoint
            let subtype = NSEvent.EventSubtype.tabletPoint
            let pressure: Float
            init(_ pressure: Float) { self.pressure = pressure }
        }
        XCTAssertEqual(PenSample.reading(Odd(1.7)), .pen(pressure: 1))
        XCTAssertEqual(PenSample.reading(Odd(-0.2)), .pen(pressure: 0))
        XCTAssertEqual(PenSample.reading(Odd(.nan)), .pen(pressure: 0))
    }

    func testTheMonitorWatchesTheButtonAndTheTabletAndNothingElse() {
        XCTAssertEqual(PenSample.watched, [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .tabletPoint])
    }

    /// The monitor returns every event it is handed, unchanged — a local
    /// monitor that returns something else, or nil, takes the click away
    /// from the whole app.
    func testTheReaderHandsEveryEventBackUntouched() throws {
        let reader = PenSampleReader()
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                 timestamp: 0, windowNumber: 0, context: nil,
                                                 characters: "a", charactersIgnoringModifiers: "a",
                                                 isARepeat: false, keyCode: 0))
        for given in [try event(.leftMouseDown, subtype: tablet, pressure: 0.3),
                      try event(.leftMouseDragged, subtype: mouse, pressure: 1),
                      try event(.mouseMoved, subtype: tablet, pressure: 0.5),
                      try event(.leftMouseUp, subtype: touch, pressure: 0),
                      key] {
            XCTAssertTrue(reader.pass(given) === given, "\(given.type) came back as something else")
        }
    }

    func testTheReaderRemembersTheNibUntilTheMouseSpeaks() throws {
        let reader = PenSampleReader()
        XCTAssertEqual(reader.sample, .mouse, "nothing seen is the mouse: a stroke drawn then is the legacy line")
        reader.pass(try event(.leftMouseDragged, subtype: tablet, pressure: 0.3))
        XCTAssertEqual(try XCTUnwrap(pressure(reader.sample)), 0.3, accuracy: Self.level)
        reader.pass(try event(.mouseMoved, subtype: tablet, pressure: 0.9))
        XCTAssertEqual(try XCTUnwrap(pressure(reader.sample)), 0.3, accuracy: Self.level, "a hover changed the pressure")
        reader.pass(try event(.leftMouseDown, subtype: mouse, pressure: 1))
        XCTAssertEqual(reader.sample, .mouse, "the trackpad after the pen is the trackpad")
        reader.pass(try event(.leftMouseDragged, subtype: tablet, pressure: 0.8))
        XCTAssertEqual(try XCTUnwrap(pressure(reader.sample)), 0.8, accuracy: Self.level)
    }

    /// The test host IS the app, so the launch has already happened: the
    /// pen's samples arrive one per event, not one per frame.
    func testCoalescingIsOffSoThePenArrivesAtFullRate() {
        XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)
    }
}
