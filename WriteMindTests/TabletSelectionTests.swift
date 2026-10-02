import AppKit
import XCTest
@testable import WriteMind

/// The pixel at (x, y) from the TOP LEFT, 0…255 a channel.
func rgb(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let width = image.width, height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let at = (y * width + x) * 4
    return (Int(data[at]), Int(data[at + 1]), Int(data[at + 2]))
}

/// Anything drawn on the page can be selected and inserted (Sean,
/// 2026-10-02): the box takes what it touches, and Image, Writing and Text
/// arrive the way the camera's do — at a capture's scale, under the caret.
@MainActor
final class TabletSelectionTests: XCTestCase {
    private var dir: URL!
    private var store: NoteStore!
    private let pageSize = CGSize(width: 500, height: 800)
    private let pane = CGSize(width: 1000, height: 800)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-tablet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("# Page\n\nnotes\n".utf8).write(to: dir.appending(path: "Page.md"))
        store = NoteStore(directory: dir)
        store.canvasSize = pane
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// A line across the page, a dot, and a line far away.
    private let line = pageStroke([CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.3, y: 0.22), CGPoint(x: 0.4, y: 0.25)],
                                  width: 4, colorHex: "#8E44AD", pressures: [0.2, 0.6, 0.9])
    private let dot = pageStroke([CGPoint(x: 0.3, y: 0.3)], width: 4, pressures: [0.7])
    private let far = pageStroke([CGPoint(x: 0.8, y: 0.85), CGPoint(x: 0.9, y: 0.9)])
    private var page: [Stroke] { [line, dot, far] }
    /// Over the start of the line and the dot, not the far one.
    private let box = CGRect(x: 0.1, y: 0.1, width: 0.25, height: 0.25)

    func testTheBoxTakesWhatItTouchesWhole() {
        XCTAssertEqual(TabletSelection.touched(page, by: box, pageSize: pageSize).map(\.id), [line.id, dot.id],
                       "the line only starts in the box, and comes whole")
        XCTAssertEqual(TabletSelection.touched(page, by: CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3),
                                               pageSize: pageSize), [])
    }

    /// WRITING IS THE STROKES THEMSELVES — pressure, tool and colour kept —
    /// as one group, one step back, at the scale a camera capture of the
    /// same box would have.
    func testWritingIsTheStrokesThemselvesAtTheCapturesScale() throws {
        XCTAssertTrue(store.takeFromTablet(.writing, strokes: page, box: box, pageSize: pageSize))
        let placed = store.drawing.strokes
        XCTAssertEqual(placed.count, 2)
        let group = try XCTUnwrap(placed.first?.group)
        XCTAssertTrue(placed.allSatisfy { $0.group == group }, "one group")
        XCTAssertTrue(placed.allSatisfy { $0.id != line.id && $0.id != dot.id }, "new objects")
        XCTAssertEqual(placed.map(\.pressures), [line.pressures, dot.pressures])
        XCTAssertEqual(placed.map(\.tool), [.pen, .pen])
        XCTAssertEqual(placed.map(\.colorHex), [line.colorHex, dot.colorHex])

        // A whole page lands at 0.9 of the pane, limited here by its
        // height: 720 points tall, so 450 wide for a 500-point page.
        let scale = 450.0 / 500
        XCTAssertEqual(placed[0].width, 4 * scale, accuracy: 1e-9)
        let frame = try XCTUnwrap(TabletSelection.inkBounds([line, dot], pageSize: pageSize))
        let placement = NotebookCapture.placement(frame: frame, pageSize: pageSize, pane: pane, nudge: 0)
        XCTAssertEqual(placement.width * pane.width / frame.width, scale, accuracy: 1e-9,
                       "the camera's own placement says the same scale")
        let first = placed[0].points[0], last = placed[0].points[2]
        let span = hypot((last.x - first.x) * pane.width, (last.y - first.y) * pane.height)
        XCTAssertEqual(span, hypot(0.2 * 500, 0.05 * 800) * scale, accuracy: 1e-6, "every point by the one scale")
        let landed = try XCTUnwrap(store.drawing.bounds(of: Set(placed.map(\.id)), in: pane))
        XCTAssertEqual(landed.midX, placement.center.x * pane.width, accuracy: 1e-6,
                       "with no caret, where it sat on the page")
        XCTAssertEqual(landed.midY, placement.center.y * pane.height, accuracy: 1e-6)

        XCTAssertEqual(store.drawingHistory.count, 1, "one step")
        store.undoDrawing()
        XCTAssertTrue(store.drawing.strokes.isEmpty, "and one step takes all of it back")
    }

    func testWritingLandsUnderTheCaret() throws {
        store.caretAnchor = { CGRect(x: 30, y: 100, width: 500, height: 20) }
        XCTAssertTrue(store.takeFromTablet(.writing, strokes: page, box: box, pageSize: pageSize))
        let landed = try XCTUnwrap(store.drawing.bounds(of: Set(store.drawing.strokes.map(\.id)), in: pane))
        XCTAssertEqual(landed.minX, 30, accuracy: 1e-6, "flush with the text")
        XCTAssertEqual(landed.minY, 120 + MarkdownPreview.gapHeight, accuracy: 1e-6, "a seam under the line")
    }

    func testOneStrokeIsNotAGroup() {
        XCTAssertTrue(store.takeFromTablet(.writing, strokes: page, box: CGRect(x: 0.25, y: 0.27, width: 0.1, height: 0.06),
                                           pageSize: pageSize))
        XCTAssertEqual(store.drawing.strokes.count, 1)
        XCTAssertNil(store.drawing.strokes.first?.group)
    }

    func testABoxOverNothingSaysSoAndChangesNothing() {
        let empty = CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3)
        XCTAssertFalse(store.takeFromTablet(.writing, strokes: page, box: empty, pageSize: pageSize))
        XCTAssertFalse(store.takeFromTablet(.text, strokes: page, box: empty, pageSize: pageSize))
        XCTAssertEqual(store.captureNotice, "There is no writing in that box.")
        XCTAssertTrue(store.drawing.isEmpty)
        XCTAssertTrue(store.drawingHistory.isEmpty, "no step for nothing")
        XCTAssertFalse(store.isCapturing, "and nothing is being read")
    }

    /// IMAGE IS THE PICTURE OF THE PAGE: the paper, the ink in its own
    /// colour, cut at the box.
    func testImageIsThePageInTheBoxPaperAndAll() throws {
        let across = pageStroke([CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)], width: 8, colorHex: "#F2542D",
                                pressures: [0.5, 0.5])
        let elsewhere = pageStroke([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1)], width: 8, colorHex: "#1C1C1E")
        let region = CGRect(x: 100, y: 300, width: 200, height: 200)
        let image = try XCTUnwrap(TabletRender.image(of: [across, elsewhere], region: region, pageSize: pageSize))
        XCTAssertEqual(image.width, 600)
        XCTAssertEqual(image.height, 600)
        let ink = rgb(image, 300, 300)
        XCTAssertGreaterThan(ink.r, 200)
        XCTAssertLessThan(ink.g, 140, "the pen's own red, \(ink)")
        let paper = rgb(image, 300, 30)
        XCTAssertTrue(paper.r > 250 && paper.g > 250 && paper.b > 250, "the paper, \(paper)")
        for y in stride(from: 0, to: 600, by: 20) {
            let pixel = rgb(image, 300, y)
            XCTAssertFalse(pixel.r < 100 && pixel.g < 100, "the line outside the box came in at \(y)")
        }
    }

    func testImageGoesInAsAPictureAtTheCapturesScale() throws {
        let image = CGRect(x: 0.2, y: 0.375, width: 0.4, height: 0.25)
        XCTAssertTrue(store.takeFromTablet(.image, strokes: page, box: image, pageSize: pageSize))
        let picture = try XCTUnwrap(store.drawing.images.first)
        XCTAssertEqual(picture.aspect, 1, accuracy: 1e-9, "200 by 200 page points")
        XCTAssertTrue(picture.file.hasSuffix(".png"))
        XCTAssertNotNil(DrawingStore.loadImage(picture.file, in: dir))
        let placement = NotebookCapture.placement(frame: CGRect(x: 100, y: 300, width: 200, height: 200),
                                                  pageSize: pageSize, pane: pane, nudge: 0)
        XCTAssertEqual(picture.width, placement.width, accuracy: 1e-9)
        XCTAssertEqual(store.drawingHistory.count, 1)
    }

    /// TEXT IS READ OFF BLACK ON WHITE, whatever the pen and whatever the
    /// window: a white pen, drawn in Dark Mode, is still black ink.
    func testTextIsBlackOnWhiteWhateverThePenAndTheAppearance() throws {
        let white = pageStroke([CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.6, y: 0.5)], width: 10, colorHex: "#FFFFFF",
                               pressures: [0.5, 0.5], tool: .pencil)
        var rendered: CGImage?
        try XCTUnwrap(NSAppearance(named: .darkAqua)).performAsCurrentDrawingAppearance {
            rendered = TabletRender.ink(of: [white], pageSize: pageSize)
        }
        let image = try XCTUnwrap(rendered)
        let bounds = try XCTUnwrap(TabletSelection.inkBounds([white], pageSize: pageSize))
        XCTAssertEqual(CGFloat(image.width), (bounds.width + 2 * TabletRender.readingMargin) * 3, accuracy: 1)
        let ink = rgb(image, image.width / 2, image.height / 2)
        XCTAssertTrue(ink.r < 20 && ink.g < 20 && ink.b < 20, "black, at full strength, \(ink)")
        let paper = rgb(image, 4, 4)
        XCTAssertTrue(paper.r > 250 && paper.g > 250 && paper.b > 250, "white, \(paper)")
    }

    /// The whole of Text: the strokes the box touches, read, and put in
    /// under the caret the way the camera's Text is.
    func testTextReadsWhatWasWrittenIntoTheNote() async throws {
        let written = Self.hello(in: pageSize)
        var inserted: (text: String, below: CGFloat)?
        store.insertBelow = { text, below in inserted = (text, below); return true }
        store.caretAnchor = { CGRect(x: 30, y: 100, width: 500, height: 20) }
        XCTAssertTrue(store.takeFromTablet(.text, strokes: written, box: CGRect(x: 0, y: 0, width: 1, height: 0.3),
                                           pageSize: pageSize))
        XCTAssertTrue(store.isCapturing)
        for _ in 0..<200 where store.isCapturing { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(store.isCapturing)
        let read = try XCTUnwrap(inserted, "nothing was read: \(store.captureNotice ?? "")")
        XCTAssertTrue(read.text.uppercased().contains("HELL"), read.text)
        XCTAssertEqual(read.below, 120, "under the caret's line")
    }

    /// HELLO in single strokes, the way a pen writes capitals.
    static func hello(in size: CGSize) -> [Stroke] {
        let height: CGFloat = 60, width: CGFloat = 40, gap: CGFloat = 22
        let letters: [[[CGPoint]]] = [
            [[CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1)], [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)],
             [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)]],
            [[CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1)], [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)],
             [CGPoint(x: 0, y: 0.5), CGPoint(x: 0.8, y: 0.5)], [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]],
            [[CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1)], [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]],
            [[CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1)], [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]],
            [(0...48).map { step in
                let angle = Double(step) / 48 * 2 * .pi
                return CGPoint(x: 0.5 + 0.5 * sin(angle), y: 0.5 - 0.5 * cos(angle))
            }],
        ]
        var strokes: [Stroke] = []
        for (index, letter) in letters.enumerated() {
            let left = 60 + CGFloat(index) * (width + gap), top: CGFloat = 80
            for line in letter {
                // Filled in the way a pen reports a line: a sample every
                // couple of points.
                var points: [CGPoint] = []
                for (a, b) in zip(line, line.dropFirst()) {
                    let steps = max(1, Int(hypot((b.x - a.x) * width, (b.y - a.y) * height) / 2))
                    for step in 0..<steps {
                        let t = CGFloat(step) / CGFloat(steps)
                        points.append(CGPoint(x: (left + (a.x + (b.x - a.x) * t) * width) / size.width,
                                              y: (top + (a.y + (b.y - a.y) * t) * height) / size.height))
                    }
                }
                if let end = line.last {
                    points.append(CGPoint(x: (left + end.x * width) / size.width, y: (top + end.y * height) / size.height))
                }
                strokes.append(pageStroke(points, width: 5, colorHex: "#2D7DD2"))
            }
        }
        return strokes
    }
}

/// Whose ⌘Z it is once there is a page to write on.
@MainActor
final class TabletUndoTests: XCTestCase {
    func testThePageOwnsItStraightAfterWritingUntilTheNoteChanges() {
        let state = AppState(defaults: UserDefaults(suiteName: "WriteMindTests-\(UUID().uuidString)")!)
        state.follow(tabletPicked: true)
        XCTAssertFalse(state.pageOwnsUndo, "nothing written yet: ⌘Z is the note's")
        state.pageWritten()
        XCTAssertTrue(state.pageOwnsUndo)
        state.notebookChanged()
        XCTAssertFalse(state.pageOwnsUndo, "typed in the note since: the note's again")
        state.pageWritten()
        state.showCamera = false
        XCTAssertFalse(state.pageOwnsUndo, "the page is put away: an undo there would not be seen")
        state.showCamera = true
        XCTAssertTrue(state.pageOwnsUndo)
        state.follow(tabletPicked: false)
        XCTAssertFalse(state.pageOwnsUndo, "the camera is the input: there is no page to undo on")
    }

    /// THE DRAWING LAYER'S KEY MONITOR SEES ⌘Z BEFORE THE EDIT MENU DOES (a
    /// local monitor runs ahead of a key equivalent — measured), so it asks
    /// the page's claim as well: with something picked on the layer and a
    /// stroke just written on the page, ⌘Z goes on to the menu, which gives
    /// it to the page.
    func testTheLayerHandsTheKeyOnWhileThePageOwnsIt() {
        let state = AppState(defaults: UserDefaults(suiteName: "WriteMindTests-\(UUID().uuidString)")!)
        state.follow(tabletPicked: true)
        state.canvasSelection = true
        XCTAssertTrue(DrawingCanvas.takesUndo(layerOwns: state.drawingOwnsUndo, pageOwns: state.pageOwnsUndo))
        state.pageWritten()
        XCTAssertFalse(DrawingCanvas.takesUndo(layerOwns: state.drawingOwnsUndo, pageOwns: state.pageOwnsUndo),
                       "⌘Z after a stroke on the page undid the layer")
        state.notebookChanged()
        XCTAssertTrue(DrawingCanvas.takesUndo(layerOwns: state.drawingOwnsUndo, pageOwns: state.pageOwnsUndo))
        XCTAssertFalse(DrawingCanvas.takesUndo(layerOwns: false, pageOwns: false))
    }
}
