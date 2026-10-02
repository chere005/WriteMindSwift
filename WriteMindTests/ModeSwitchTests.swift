import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// The two panes, hosted for real, across ⌘T (Sean, 2026-10-03: "preserve
/// the position of things as much as possible between markdown and wysiwyg
/// mode"): the markdown pane's cells laid out with no text view, the place
/// at the top of the window put back on both sides, and the cursor carried.
@MainActor
final class ModeSwitchTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows = []
        super.tearDown()
    }

    /// A note long enough to scroll, whose LAST cell is plain words — the
    /// markdown pane's caret starts there, and the cell the caret is in
    /// shows its markers.
    private let note: String = {
        var cells = ["# A title", "Some **bold** words, and a [link](https://example.com) in them."]
        cells.append("```python\nprint(\"a code cell\")\nx = 1\n```")
        cells.append("- one\n- two\n- three")
        cells.append("## A section")
        for index in 1...14 {
            cells.append("Paragraph \(index), long enough to run onto a second line in a pane six hundred points wide.")
        }
        return cells.joined(separator: "\n\n")
    }()

    private func host<Content: View>(_ view: Content, size: CGSize = CGSize(width: 600, height: 400)) -> NSView {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = host
        windows.append(window)
        settle(host)
        return host
    }

    private func settle(_ view: NSView, for seconds: TimeInterval = 0.4) {
        view.layoutSubtreeIfNeeded()
        view.window?.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        view.layoutSubtreeIfNeeded()
        view.window?.displayIfNeeded()
    }

    private func textView(in view: NSView) -> PasteAwareTextView? {
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        return all(view).compactMap { $0 as? PasteAwareTextView }.first { !($0 is BlockTextView) }
    }

    private func blockEditor(in view: NSView) -> BlockTextView? {
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        return all(view).compactMap { $0 as? BlockTextView }.first
    }

    // MARK: - The markdown pane's cells, with no markdown pane

    func testTheOffscreenLayoutIsTheTextViewsOwn() throws {
        for markers in [false, true] {
            let host = host(MarkdownTextView(text: .constant(note), documentID: nil, bridge: EditorBridge(),
                                             showMarkers: markers))
            let tv = try XCTUnwrap(textView(in: host))
            let live = MarkdownTextView.cellBoxes(in: tv)
            let offscreen = MarkdownTextView.cellBoxes(of: note, width: tv.bounds.width, showMarkers: markers,
                                                       collapsed: [])
            XCTAssertEqual(live.count, offscreen.count, "markers \(markers)")
            XCTAssertGreaterThan(live.count, 15, "the premise: every cell measured")
            for (a, b) in zip(live, offscreen) {
                XCTAssertEqual(a.offset, b.offset)
                XCTAssertEqual(a.top, b.top, accuracy: 0.5, "cell \(a.offset), markers \(markers)")
                XCTAssertEqual(a.bottom, b.bottom, accuracy: 0.5, "cell \(a.offset), markers \(markers)")
            }
        }
    }

    func testTheOffscreenLayoutFoldsWhatThePaneFolds() throws {
        let key = try XCTUnwrap(NotebookOutline.sections(in: note).first { $0.title == "A section" }?.key)
        let host = host(MarkdownTextView(text: .constant(note), documentID: nil, bridge: EditorBridge(),
                                         collapsed: [key], showMarkers: false))
        let tv = try XCTUnwrap(textView(in: host))
        let live = MarkdownTextView.cellBoxes(in: tv)
        let offscreen = MarkdownTextView.cellBoxes(of: note, width: tv.bounds.width, showMarkers: false,
                                                   collapsed: [key])
        XCTAssertLessThan(live.count, 8, "the premise: the section's cells are folded away")
        XCTAssertEqual(live.map(\.offset), offscreen.map(\.offset))
        for (a, b) in zip(live, offscreen) { XCTAssertEqual(a.top, b.top, accuracy: 0.5) }
    }

    // MARK: - The place at the top of the window

    func testTheMarkdownPaneOpensAtThePlaceInsideTheCell() throws {
        // Two thirds of the way into the tenth paragraph.
        let cells = MarkdownParser.positioned(from: note)
        let place = CellPlace(cell: cells[14].range.location, fraction: 2.0 / 3)
        var reported: [CellPlace] = []
        let host = host(MarkdownTextView(text: .constant(note), documentID: nil, bridge: EditorBridge(),
                                         onTopCell: { reported.append($0) }, topCell: place, showMarkers: false))
        let tv = try XCTUnwrap(textView(in: host))
        let scroll = try XCTUnwrap(tv.enclosingScrollView)
        let wanted = try XCTUnwrap(place.y(in: MarkdownTextView.cellBoxes(in: tv)))
        XCTAssertEqual(scroll.contentView.bounds.origin.y, wanted, accuracy: 0.5,
                       "the line the other pane had at its fold, not the cell's first")
        let last = try XCTUnwrap(reported.last)
        XCTAssertEqual(last.cell, place.cell)
        XCTAssertEqual(last.fraction, place.fraction, accuracy: 0.01, "and it says so")
    }

    func testTheRenderedPageOpensAtThePlaceInsideTheCell() throws {
        let cells = MarkdownParser.positioned(from: note)
        let place = CellPlace(cell: cells[14].range.location, fraction: 0.5)
        var reported: [CellPlace] = []
        var layout: [CellSeams.Box] = []
        var scrolled: CGFloat = -1
        _ = host(MarkdownPreview(markdown: .constant(note), onScroll: { scrolled = $0 },
                                 onTopCell: { reported.append($0) }, topCell: place,
                                 onLayout: { layout = $0 }))
        XCTAssertEqual(layout.count, cells.count, "the page says where its cells are")
        let wanted = try XCTUnwrap(place.y(in: layout))
        XCTAssertEqual(scrolled, wanted, accuracy: 1, "half way into the cell, not its top")
        XCTAssertFalse(reported.contains { $0 == CellPlace.at(0, in: layout) },
                       "the page's own top was never reported over the place it was opening at")
        let last = try XCTUnwrap(reported.last)
        XCTAssertEqual(last.cell, place.cell)
        XCTAssertEqual(last.fraction, place.fraction, accuracy: 0.02)
    }

    func testTheRenderedPagesCellsAreTheStackItLaysOut() throws {
        var layout: [CellSeams.Box] = []
        _ = host(MarkdownPreview(markdown: .constant(note), onLayout: { layout = $0 }))
        let first = try XCTUnwrap(layout.first)
        XCTAssertEqual(first.top, MarkdownPreview.topInset + MarkdownPreview.gapHeight, accuracy: 0.5)
        for (a, b) in zip(layout, layout.dropFirst()) {
            XCTAssertEqual(b.top - a.bottom, MarkdownPreview.blockGap, accuracy: 0.5)
        }
    }

    // MARK: - The cursor

    func testTheMarkdownPaneTakesTheCaretItWasHanded() throws {
        let bridge = EditorBridge()
        let words = (note as NSString).range(of: "bold")
        bridge.paneCaret = { EditorBridge.Carried(caret: .text(words), text: self.note) }
        bridge.carryCaret()
        let host = host(MarkdownTextView(text: .constant(note), documentID: nil, bridge: bridge, showMarkers: false))
        let tv = try XCTUnwrap(textView(in: host))
        XCTAssertEqual(tv.selectedRange(), words, "not the end of the note")
        XCTAssertTrue(tv.window?.firstResponder === tv, "and the keyboard with it")
    }

    func testWithNoCaretTheMarkdownPanesCaretGoesToTheCellAtTheTop() throws {
        let bridge = EditorBridge()
        bridge.paneCaret = { EditorBridge.Carried(caret: nil, text: self.note) }
        bridge.carryCaret()
        let cell = MarkdownParser.positioned(from: note)[12].range.location
        let host = host(MarkdownTextView(text: .constant(note), documentID: nil, bridge: bridge,
                                         topCell: CellPlace(cell: cell, fraction: 0.2), showMarkers: false))
        let tv = try XCTUnwrap(textView(in: host))
        XCTAssertEqual(tv.selectedRange(), NSRange(location: cell, length: 0),
                       "where the eye is, so ⌘1 and a pasted picture go there")
    }

    func testTheMarkdownPaneArmsTheBarItWasHanded() throws {
        let bridge = EditorBridge()
        let seam = MarkdownParser.positioned(from: note)[3].range.location
        bridge.paneCaret = { EditorBridge.Carried(caret: .bar(offset: seam, kind: .quote), text: self.note) }
        bridge.carryCaret()
        let host = host(MarkdownTextView(text: .constant(note), documentID: nil, bridge: bridge, showMarkers: false))
        let tv = try XCTUnwrap(textView(in: host))
        XCTAssertEqual(tv.armedSeam, seam)
        XCTAssertEqual(tv.armedType, .quote, "and what its + chose")
    }

    func testTheMarkdownPaneHoldsTheCellsItWasHanded() throws {
        let bridge = EditorBridge()
        let cells = MarkdownParser.positioned(from: note).map(\.range)
        bridge.paneCaret = { EditorBridge.Carried(caret: .cells([cells[1], cells[3]]), text: self.note) }
        bridge.carryCaret()
        let host = host(MarkdownTextView(text: .constant(note), documentID: nil, bridge: bridge, showMarkers: false))
        let tv = try XCTUnwrap(textView(in: host))
        XCTAssertEqual(tv.selectedRanges.map(\.rangeValue), [cells[1], cells[3]])
        XCTAssertEqual(MarkdownTextView.Coordinator.caret(of: tv), .cells([cells[1], cells[3]]),
                       "and hands them on the same way")
    }

    func testACaretCarriedForAnotherNoteIsNotTaken() throws {
        let bridge = EditorBridge()
        bridge.paneCaret = { EditorBridge.Carried(caret: .text(NSRange(location: 3, length: 0)), text: "Another note") }
        bridge.carryCaret()
        let host = host(MarkdownTextView(text: .constant(note), documentID: nil, bridge: bridge, showMarkers: false))
        let tv = try XCTUnwrap(textView(in: host))
        XCTAssertNotEqual(tv.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertNil(bridge.carried, "taken and dropped")
    }

    func testTheRenderedPageOpensTheCellTheCaretWasIn() throws {
        let bridge = EditorBridge()
        let code = MarkdownParser.positioned(from: note)[2].range
        let caret = NSRange(location: (note as NSString).range(of: "x = 1").location + 2, length: 1)
        bridge.paneCaret = { EditorBridge.Carried(caret: .text(caret), text: self.note) }
        bridge.carryCaret()
        let host = host(MarkdownPreview(markdown: .constant(note), bridge: bridge))
        let editor = try XCTUnwrap(blockEditor(in: host), "the code cell is open")
        XCTAssertEqual(editor.string, MarkdownFormatting.fenced((note as NSString).substring(with: code))?.body)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: ("print(\"a code cell\")\n" as NSString).length + 2,
                                                       length: 1))
        // And read back off the page the way ⌘T reads it.
        XCTAssertEqual(bridge.paneCaret?().caret, .text(caret))
    }

    func testTheRenderedPageArmsTheBarItWasHanded() throws {
        let bridge = EditorBridge()
        let seam = MarkdownParser.positioned(from: note)[3].range.location
        bridge.paneCaret = { EditorBridge.Carried(caret: .bar(offset: seam, kind: .quote), text: self.note) }
        bridge.carryCaret()
        _ = host(MarkdownPreview(markdown: .constant(note), bridge: bridge))
        XCTAssertEqual(bridge.barIsUp?(), true)
        XCTAssertEqual(bridge.paneCaret?().caret, .bar(offset: seam, kind: .quote))
    }

    func testTheRenderedPageHoldsTheCellsItWasHanded() throws {
        let bridge = EditorBridge()
        let cells = MarkdownParser.positioned(from: note).map(\.range)
        bridge.paneCaret = { EditorBridge.Carried(caret: .cells([cells[0], cells[4]]), text: self.note) }
        bridge.carryCaret()
        _ = host(MarkdownPreview(markdown: .constant(note), bridge: bridge))
        XCTAssertEqual(bridge.paneCaret?().caret, .cells([cells[0], cells[4]]))
    }
}

/// THE PICTURE: one note with a picture and strokes beside its third
/// paragraph, drawn in the markdown pane, rendered in both modes — and the
/// objects are beside the same words in both. Set
/// `WRITEMIND_RENDER_DIR` (as `TEST_RUNNER_WRITEMIND_RENDER_DIR` to the
/// suite) to have the three renders written there to be looked at.
@MainActor
final class ModeRenderTests: XCTestCase {
    private let note = """
    # Where things are

    The first paragraph, which is short.

    The second paragraph is a little longer, so that it runs onto a second line in a pane this wide.

    The third paragraph: the picture and the strokes were put beside this one, in the markdown pane. It wraps onto a second line too.

    ```python
    print("a code cell, whose fences are taller in the markdown pane")
    ```

    - a list
    - of three
    - items

    The last paragraph, under everything, to show the cells below keep their place.
    """
    private let size = CGSize(width: 600, height: 760)
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows = []
        super.tearDown()
    }

    func testThePictureAndTheStrokesStayBesideTheThirdParagraph() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ModeRender-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let picture = try XCTUnwrap(DrawingStore.importImage(Self.picture(), in: folder))

        // Placed in the markdown pane's frame, the one the sidecar keeps:
        // the picture's top level with the third paragraph's, at the right;
        // a line under its first line of words and a tick in the margin.
        let source = MarkdownTextView.cellBoxes(of: note, width: size.width, showMarkers: false, collapsed: [])
        let third = try XCTUnwrap(source.first { $0.offset == (note as NSString).range(of: "The third").location })
        let width: CGFloat = 150, height = width * CGFloat(picture.aspect)
        let drawing = Drawing(items: [
            .image(ImageItem(file: picture.file,
                             center: CGPoint(x: (size.width - 24 - width / 2) / size.width,
                                             y: (third.top + height / 2) / size.height),
                             width: Double(width / size.width), aspect: picture.aspect)),
            .stroke(Stroke(colorHex: "#D62828", width: 3,
                           points: [CGPoint(x: 29, y: third.top + 21), CGPoint(x: 330, y: third.top + 21)]
                            .map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) })),
            .stroke(Stroke(colorHex: "#2D7DD2", width: 3,
                           points: [CGPoint(x: 6, y: third.top + 8), CGPoint(x: 11, y: third.top + 15),
                                    CGPoint(x: 21, y: third.top + 1)]
                            .map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) })),
        ])

        // The markdown pane, its layer straight from the sidecar.
        let sourceHost = host(ZStack {
            MarkdownTextView(text: .constant(note), documentID: nil, bridge: EditorBridge(), showMarkers: false)
            DrawingCanvas(drawing: .constant(drawing), mode: .cursor, color: .black, width: 2,
                          mediaDirectory: folder)
        })
        let tv = try XCTUnwrap(Self.all(sourceHost).compactMap { $0 as? PasteAwareTextView }.first)
        let sourceThird = try XCTUnwrap(MarkdownTextView.cellBoxes(in: tv).first { $0.offset == third.offset })

        // The rendered page, its layer through the page's own cells — the
        // way `EditorPane` shows it — and once more without, to see what
        // that was buying.
        let frames = PaneFrames()
        var renderedHosts: [NSView] = []
        for mapped in [true, false] {
            frames.rendered = nil
            let layer = Binding<Drawing>(
                get: {
                    guard mapped else { return drawing }
                    let mapping = frames.mapping(text: self.note, size: self.size, showMarkers: false, collapsed: [])
                    return frames.shown(drawing, through: mapping, in: self.size)
                },
                set: { _ in })
            renderedHosts.append(host(ZStack {
                MarkdownPreview(markdown: .constant(note), onLayout: { frames.rendered = $0 })
                PaneFramesLayer(frames: frames, drawing: layer, folder: folder)
            }))
        }
        let page = try XCTUnwrap(frames.rendered)
        let pageThird = try XCTUnwrap(page.first { $0.offset == third.offset })
        let mapping = frames.mapping(text: note, size: size, showMarkers: false, collapsed: [])
        let shown = frames.shown(drawing, through: mapping, in: size)

        // Beside the same words: each object as far from the third
        // paragraph's top on the page as it is in the markdown pane.
        for (stored, onPage) in zip(drawing.items, shown.items) {
            XCTAssertEqual(onPage.bounds(in: size).minY - pageThird.top,
                           stored.bounds(in: size).minY - sourceThird.top, accuracy: 1)
        }
        XCTAssertGreaterThan(pageThird.top - sourceThird.top, 20,
                             "the premise: the page puts the third paragraph well below where the markdown pane does")

        if let directory = ProcessInfo.processInfo.environment["WRITEMIND_RENDER_DIR"] {
            let out = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try Self.png(sourceHost).write(to: out.appendingPathComponent("1-markdown.png"))
            try Self.png(renderedHosts[0]).write(to: out.appendingPathComponent("2-rendered.png"))
            try Self.png(renderedHosts[1]).write(to: out.appendingPathComponent("3-rendered-before.png"))
        }
    }

    private func host<Content: View>(_ view: Content) -> NSView {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
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

    private static func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    /// A picture that reads as one: a framed panel with a word in it.
    private static func picture() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 180), flipped: false) { rect in
            NSColor(calibratedRed: 0.98, green: 0.86, blue: 0.45, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.05, alpha: 1).setStroke()
            let frame = NSBezierPath(rect: rect.insetBy(dx: 4, dy: 4))
            frame.lineWidth = 8
            frame.stroke()
            ("a picture" as NSString).draw(at: NSPoint(x: 70, y: 70),
                                           withAttributes: [.font: NSFont.boldSystemFont(ofSize: 34)])
            return true
        }
    }

    private static func png(_ view: NSView) throws -> Data {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}

/// The layer over the rendered page in the render test, redrawn when the
/// page reports its cells — what `EditorPane` gets from observing
/// `PaneFrames`.
private struct PaneFramesLayer: View {
    @ObservedObject var frames: PaneFrames
    @Binding var drawing: Drawing
    let folder: URL

    var body: some View {
        DrawingCanvas(drawing: $drawing, mode: .cursor, color: .black, width: 2, mediaDirectory: folder)
    }
}
