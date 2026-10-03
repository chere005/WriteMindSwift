import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// A DRAWING CELL IS A ROW OF THE PAGE in the markdown pane: its line at the
/// top, a sliver tall, and the drawing in the room the typesetter makes under
/// it — in the same line fragment, so the drawing moves with the text in the
/// very frame the text moves. ONE GEOMETRY (`FoldingLayoutManager.cellRect`)
/// is what the painter paints into, what the layer is handed as the cell's
/// frame and what the brackets and seams are made from, so none of them can
/// drift. Measured in a real `MarkdownTextView`, not assumed.
@MainActor
final class DrawingCellLayoutTests: XCTestCase {
    private var windows: [NSWindow] = []
    private let id = UUID(uuidString: "6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6")!
    private var line: String { DrawingCells.line(id) }
    private var note: String { "# Title\n\nAbove\n\n\(line)\n\nBelow" }
    private var lineRange: NSRange { (note as NSString).range(of: line) }

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows = []
        super.tearDown()
    }

    /// A cell 400 wide and 120 tall, with a stroke in it — narrower than
    /// the column a 600-point pane leaves, so it is shown as drawn (s = 1).
    private func cell(width: Double = 400, height: Double = 120) -> DrawingCell {
        DrawingCell(width: width, aspect: height / width,
                    drawing: Drawing(strokes: [Stroke(colorHex: "#D62828", width: 4,
                                                      points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.12)])]))
    }

    private func shown(_ cell: DrawingCell?) -> DrawingCellsShown {
        DrawingCellsShown(looks: [id: DrawingCellLook(cell: cell)], media: nil)
    }

    /// The height of the drawing line's own text, hidden: the sliver the
    /// markers-hidden style sets it in, with no spacing of its own.
    private var sliver: CGFloat {
        NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: MarkdownSourceStyle.structuralSize))
    }

    private func hosted(_ text: String, width: CGFloat = 600, showMarkers: Bool = false, collapsed: Set<String> = [],
                        cells: DrawingCellsShown) throws -> PasteAwareTextView {
        let size = CGSize(width: width, height: 500)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MarkdownTextView(text: .constant(text), documentID: nil,
                                                            bridge: EditorBridge(), collapsed: collapsed,
                                                            showMarkers: showMarkers, drawingCells: cells)
            .frame(width: size.width, height: size.height))
        window.contentView = host
        windows.append(window)
        for _ in 0..<2 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        return try XCTUnwrap(all(host).compactMap { $0 as? PasteAwareTextView }.first { !($0 is BlockTextView) })
    }

    private func layout(of tv: NSTextView) throws -> (FoldingLayoutManager, NSTextContainer) {
        (try XCTUnwrap(tv.layoutManager as? FoldingLayoutManager), try XCTUnwrap(tv.textContainer))
    }

    /// The line fragment the last character of the drawing line is laid out
    /// in: its rect and its used rect, in the container's coordinates.
    private func lastFragment(of range: NSRange, in tv: NSTextView) throws -> (rect: CGRect, used: CGRect) {
        let (layout, container) = try layout(of: tv)
        layout.ensureLayout(for: container)
        let glyph = layout.glyphIndexForCharacter(at: NSMaxRange(range) - 1)
        return (layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil),
                layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil))
    }

    // MARK: - The room under the line

    /// The gap under a drawing cell is the gap under any cell: the room is
    /// inside the fragment, the paragraph spacing still after it.
    func testTheSeamUnderADrawingCellIsTheSeamUnderAnyCell() throws {
        let tv = try hosted(note, cells: shown(cell()))
        let seams = MarkdownTextView.seams(in: tv)
        // Top seam, Title|Above, Above|drawing, drawing|Below, tail.
        XCTAssertEqual(seams.count, 5)
        let underAbove = seams[2], underDrawing = seams[3]
        XCTAssertEqual(underDrawing.offset, (note as NSString).range(of: "Below").location)
        XCTAssertEqual(underDrawing.bottom - underDrawing.top, underAbove.bottom - underAbove.top, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(underDrawing.bottom - underDrawing.top, MarkdownPreview.gapHeight - 0.01)
    }

    // MARK: - The markdown pane is pure text

    /// Sean, 2026-10-02: "don't show or allow drawings in markdown mode on
    /// the notebook itself, only pure text". A drawing line is the line of
    /// text it is in the file: the same height as any other, no room under
    /// it, no frame, nothing painted, and the caret treats it as words.
    func testTheMarkdownPaneShowsADrawingLineAsPlainText() throws {
        let tv = try hosted(note, showMarkers: true, cells: shown(cell()))
        let (layout, _) = try layout(of: tv)
        let plain = try lastFragment(of: (note as NSString).range(of: "Above"), in: tv)
        let fragment = try lastFragment(of: lineRange, in: tv)
        XCTAssertEqual(fragment.used.height, plain.used.height, accuracy: 0.5, "no room for a drawing")
        XCTAssertTrue(layout.drawings.lines.isEmpty)
        XCTAssertTrue(MarkdownTextView.drawingFrames(in: tv).isEmpty, "no frame to draw into")
        XCTAssertTrue(tv.drawingLines.isEmpty)
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: lineRange.location + 3, length: 0))
        XCTAssertNil(tv.drawingCellAtCaret, "the caret is in a line of words")
        XCTAssertEqual(tv.string, note, "and nothing about the text changed")
    }

    /// What the two panes are measured against keeps the cell its height: the
    /// offscreen layout is where the rendered page's mapping and the PDF find
    /// it, and the live pane's being plain text does not touch that.
    func testTheOffscreenLayoutStillGivesTheCellItsHeight() {
        let boxes = MarkdownTextView.cellBoxes(of: note, width: 600, showMarkers: true, collapsed: [],
                                               cells: shown(cell()))
        let box = boxes.first { $0.offset == lineRange.location }
        XCTAssertNotNil(box)
        XCTAssertGreaterThanOrEqual((box?.bottom ?? 0) - (box?.top ?? 0), 120)
    }
}

/// THE PICTURE: one note with a drawing cell holding three strokes, on the
/// rendered page (the markdown pane is pure text and paints none), light and dark — the cell painted where each pane tells the layer
/// it is, on that pane's own paper. Set `WRITEMIND_RENDER_DIR` (as
/// `TEST_RUNNER_WRITEMIND_RENDER_DIR` to the suite) to have the four
/// renders written there to be looked at.
@MainActor
final class DrawingCellRenderTests: XCTestCase {
    private let size = CGSize(width: 600, height: 520)
    private let id = UUID(uuidString: "6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6")!
    private var note: String {
        """
        # A drawing cell

        The paragraph above the cell, which runs onto a second line in a pane this wide so the cell is not at the top.

        \(DrawingCells.line(id))

        The paragraph under it, to show that the text below moves down for the cell.
        """
    }
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows = []
        super.tearDown()
    }

    /// 400 wide, 120 tall: a red line across at a tenth of W down, a blue
    /// tick, and a black fountain-pen stroke with pressures.
    private var cell: DrawingCell {
        var ink = Stroke.starting(at: CGPoint(x: 0.55, y: 0.18), colorHex: "#1C1C1E", width: 5,
                                  pen: .pen(pressure: 0.2), tool: .fountain)
        for (index, pressure) in [0.5, 0.9, 0.7, 0.3].enumerated() {
            ink.append(CGPoint(x: 0.6 + Double(index) * 0.05, y: 0.18 + (index % 2 == 0 ? 0.05 : -0.02)),
                       pen: .pen(pressure: pressure))
        }
        return DrawingCell(width: 400, aspect: 0.3, drawing: Drawing(strokes: [
            Stroke(colorHex: "#D62828", width: 6, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1)]),
            Stroke(colorHex: "#2D7DD2", width: 4,
                   points: [CGPoint(x: 0.12, y: 0.2), CGPoint(x: 0.16, y: 0.26), CGPoint(x: 0.24, y: 0.15)]),
            ink,
        ]))
    }

    private struct Pane {
        var view: NSView
        var frames: [CellFrame]
    }

    private func rendered(dark: Bool) throws -> (markdown: Pane, page: Pane) {
        let shown = DrawingCellsShown(looks: [id: DrawingCellLook(cell: cell)], media: nil)
        var sourceFrames: [CellFrame] = []
        let source = host(MarkdownTextView(text: .constant(note), documentID: nil, bridge: EditorBridge(),
                                           showMarkers: false, drawingCells: shown,
                                           onDrawingFrames: { sourceFrames = $0 }), dark: dark)
        var pageFrames: [CellFrame] = []
        let page = host(MarkdownPreview(markdown: .constant(note), drawingCells: shown,
                                        onDrawingFrames: { pageFrames = $0 }), dark: dark)
        return (Pane(view: source, frames: sourceFrames), Pane(view: page, frames: pageFrames))
    }

    func testTheRenderedPagePaintsTheCellWhereItTellsTheLayerItIs() throws {
        let (markdown, page) = try rendered(dark: false)
        XCTAssertTrue(markdown.frames.isEmpty, "the markdown pane is pure text: no cell to draw in")
        try check(page, dark: false, name: "the rendered page")
        try write(markdown.view, as: "cells-1-markdown-light.png")
        try write(page.view, as: "cells-2-rendered-light.png")
    }

    func testInDarkModeTheCellIsPaintedOnTheDarkPaper() throws {
        let (markdown, page) = try rendered(dark: true)
        XCTAssertTrue(markdown.frames.isEmpty, "the markdown pane is pure text: no cell to draw in")
        try check(page, dark: true, name: "the rendered page")
        try write(markdown.view, as: "cells-3-markdown-dark.png")
        try write(page.view, as: "cells-4-rendered-dark.png")
    }

    /// One frame, the cell's size as drawn; the red line's middle is red
    /// where the frame says the cell is, and the cell's paper beside it is
    /// the pane's own.
    private func check(_ pane: Pane, dark: Bool, name: String) throws {
        XCTAssertEqual(pane.frames.count, 1, "\(name) told \(pane.frames.count) frames")
        let frame = try XCTUnwrap(pane.frames.first)
        XCTAssertEqual(frame.id, id)
        XCTAssertEqual(frame.width, 400, accuracy: 0.01, name)
        XCTAssertEqual(frame.scale, 1, accuracy: 0.001, name)
        XCTAssertEqual(frame.rect.size.height, 120, accuracy: 0.5, name)
        XCTAssertTrue(frame.writable)

        let rep = try Self.bitmap(pane.view)
        let scale = CGFloat(rep.pixelsWide) / pane.view.bounds.width
        func colour(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
            try XCTUnwrap(rep.colorAt(x: Int((x * scale).rounded()), y: Int((y * scale).rounded()))?
                .usingColorSpace(.sRGB), "\(name): no pixel at \(x), \(y)")
        }
        // The red line runs across at a tenth of W down the cell.
        let onLine = try colour(frame.rect.minX + 200, frame.rect.minY + 40)
        XCTAssertGreaterThan(onLine.redComponent, 0.6, "\(name): no red ink where the line should be: \(onLine)")
        XCTAssertLessThan(onLine.greenComponent, 0.4, "\(name): \(onLine)")
        XCTAssertLessThan(onLine.blueComponent, 0.4, "\(name): \(onLine)")
        // Paper in the cell, under the line and clear of the other strokes.
        let paper = try colour(frame.rect.minX + 200, frame.rect.minY + 100)
        if dark {
            XCTAssertLessThan(paper.brightnessComponent, 0.3, "\(name): the cell is painted on the dark paper: \(paper)")
        } else {
            XCTAssertGreaterThan(paper.brightnessComponent, 0.9, "\(name): the cell is painted on the light paper: \(paper)")
        }
        // Nothing of the cell's leaks past its frame.
        let beside = try colour(frame.rect.maxX + 60, frame.rect.minY + 40)
        XCTAssertEqual(beside.redComponent, paper.redComponent, accuracy: 0.05, "\(name): beside the cell is paper")
    }

    private func host<Content: View>(_ view: Content, dark: Bool) -> NSView {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = host
        windows.append(window)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        return host
    }

    private static func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func write(_ view: NSView, as name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["WRITEMIND_RENDER_DIR"] else { return }
        let out = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let png = try XCTUnwrap(try Self.bitmap(view).representation(using: .png, properties: [:]))
        try png.write(to: out.appendingPathComponent(name))
    }
}
