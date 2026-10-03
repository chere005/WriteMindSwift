import Foundation
import XCTest
@testable import WriteMind

// THE RECORDED SESSIONS under WriteMindTests/Fixtures (Sean, 2026-10-03:
// "make sure i can develop wacom features without a device plugged in"): a
// stroke, a box select, a lower-hold erase, a double press for undo, a double
// tap for redo, a pressure ramp — each a pen session as the one door heard
// it, raw 10-byte reports and the moment of each, in the file format the app
// records and replays (`PenRecording`).
//
// They were made by running the recipe below through the virtual pen with the
// recorder on — the same thing a person does with the virtual tablet's Record
// button — and a test (`PenFixtureFilesTests`) keeps each file the bytes its
// recipe records, so a fixture cannot drift from what it says it is of. To
// make them again after the format or the virtual pen changes:
//
//     TEST_RUNNER_WRITEMIND_REGENERATE_FIXTURES=1 sh tools/test.sh
//
// (or the same variable on a focused xcodebuild run). A fixture of a session
// recorded on the real tablet is just another file in the folder.
@MainActor
enum PenFixtures {
    struct Recipe {
        let name: String
        let note: String
        let script: (TabletScript) -> Void
    }

    /// WriteMindTests/Fixtures, found from this file.
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Support
        .deletingLastPathComponent()   // WriteMindTests
        .appending(path: "Fixtures", directoryHint: .isDirectory)

    static func url(_ name: String) -> URL { folder.appending(path: "\(name).ndjson") }

    /// A line of ink across the upper third of the page.
    static let line = [(0.20, 0.30), (0.28, 0.33), (0.38, 0.36), (0.50, 0.38), (0.62, 0.37), (0.74, 0.33), (0.80, 0.30)]

    static let recipes: [Recipe] = [
        Recipe(name: "stroke", note: "one stroke of ink: hover, nib down, six moves, nib up, the pen leaves") { pen in
            pen.stroke(line, pressure: 0.5).leave()
        },
        Recipe(name: "box-select",
               note: "the upper switch held as the nib goes down, dragged from (0.2, 0.2) to (0.7, 0.6): a box") { pen in
            pen.hover(0.2, 0.2).hold(.upper) { pen.down(0.5).line(to: 0.7, 0.6, steps: 8).up() }.leave()
        },
        Recipe(name: "lower-hold-erase",
               note: "a line across the middle of the page, then the lower switch held and the nib dragged down across it: the eraser") { pen in
            pen.stroke([(0.2, 0.5), (0.5, 0.5), (0.8, 0.5)])
                .hover(0.5, 0.3)
                .hold(.lower) { pen.down(0.5).line(to: 0.5, 0.7, steps: 8).up() }
                .leave()
        },
        Recipe(name: "double-press-undo",
               note: "a stroke, then a double press of the lower switch with the nib off the tablet: undo") { pen in
            pen.stroke(line).hover(0.5, 0.6).doublePress(.lower).leave()
        },
        Recipe(name: "double-tap-redo",
               note: "a stroke, undone by a double press of the lower switch, then put back by a double tap of the upper: redo") { pen in
            pen.stroke(line).hover(0.5, 0.6).doublePress(.lower).wait(1).tap(.upper).tap(.upper).leave()
        },
        Recipe(name: "pressure-ramp", note: "ten points along a line, the pressure rising from a tenth to full") { pen in
            pen.stroke((0..<10).map { (0.10 + 0.08 * Double($0), 0.5) }, pressure: 0.1, to: 1.0).leave()
        },
    ]

    /// What a recipe records on a fresh rig: the small One by Wacom, held one
    /// quarter turn clockwise.
    static func record(_ recipe: Recipe) -> PenRecording {
        let rig = TabletRig()
        let recorder = PenRecorder()
        rig.input.recorder = recorder
        recipe.script(rig.pen)
        return recorder.recording(extent: rig.input.extent, productID: 0x037A, quarterTurns: 1, created: nil,
                                  note: recipe.note)
    }

    /// A fixture, read from its file.
    static func load(_ name: String) throws -> PenRecording {
        try PenRecording(contentsOf: url(name))
    }

    static var regenerating: Bool {
        ProcessInfo.processInfo.environment["WRITEMIND_REGENERATE_FIXTURES"] != nil
    }
}
