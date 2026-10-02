import AppKit
import SwiftUI
import XCTest
@testable import WriteMind

/// A note on paper (Sean, 2026-09-19: "export as pdf").
///
/// Three things are checked here and they are separable on purpose: where
/// the page breaks land (`PagePlan`, pure arithmetic over measured
/// heights), what the file turns out to be (`NotePDF`, opened back up with
/// CGPDFDocument), and whether a traced capture is still vectors when it
/// gets there (`DrawingInk`, blown up eight times and looked at).
@MainActor
final class NotePDFTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "WriteMindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Where the breaks land

    func testAPageBreakLandsBetweenCellsAndNeverInsideOne() {
        // Three cells of 300pt with 20pt of air between them: two fit on a
        // 700pt sheet and the third cannot, so it moves whole.
        let cells = [PagePlan.Piece(id: 0, top: 0, bottom: 300),
                     PagePlan.Piece(id: 1, top: 320, bottom: 620),
                     PagePlan.Piece(id: 2, top: 640, bottom: 940)]
        let pages = PagePlan.pages(for: cells, pageHeight: 700)

        XCTAssertEqual(pages.map(\.pieces), [[0, 1], [2]])
        XCTAssertEqual(pages[0].top, 0)
        XCTAssertEqual(pages[1].top, 640, "the sheet starts at the top of the cell that moved to it")
        XCTAssertEqual(pages.map(\.scale), [1, 1], "nothing had to be shrunk")
        assertNothingIsCut(cells, on: pages, pageHeight: 700)
    }

    func testAnObjectTallerThanAPageGetsOneToItselfShrunkToFit() {
        let pieces = [PagePlan.Piece(id: 0, top: 0, bottom: 100),
                      PagePlan.Piece(id: 1, top: 120, bottom: 1120),
                      PagePlan.Piece(id: 2, top: 1140, bottom: 1240)]
        let pages = PagePlan.pages(for: pieces, pageHeight: 500)

        XCTAssertEqual(pages.map(\.pieces), [[0], [1], [2]], "the tall one shares its sheet with nothing")
        XCTAssertEqual(pages[1].top, 120)
        XCTAssertEqual(pages[1].scale, 0.5, accuracy: 1e-9, "a 1000pt object on 500pt of paper is halved")
        XCTAssertEqual(pages[0].scale, 1)
        XCTAssertEqual(pages[2].scale, 1)
        assertNothingIsCut(pieces, on: pages, pageHeight: 500)
    }

    func testTwoThingsThatOverlapAreNeverPartedByABreak() {
        // Ink drawn over a picture is one drawing, and one drawing cannot
        // be halfway down two sheets.
        let pieces = [PagePlan.Piece(id: 0, top: 0, bottom: 400),
                      PagePlan.Piece(id: 1, top: 380, bottom: 700)]
        let pages = PagePlan.pages(for: pieces, pageHeight: 600)

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].pieces, [0, 1])
        XCTAssertEqual(pages[0].scale, 600.0 / 700, accuracy: 1e-9, "welded, so the pair is shrunk together")
    }

    func testANoteWithNothingInItIsStillOneSheetOfPaper() {
        XCTAssertEqual(PagePlan.pages(for: [], pageHeight: 700),
                       [PagePlan.Page(top: 0, scale: 1, pieces: [])])
    }

    /// Every piece is on exactly one sheet, and wholly inside it — which is
    /// the same sentence as "no line of text is cut in half", because a
    /// cell is the smallest thing this ever moves.
    private func assertNothingIsCut(_ pieces: [PagePlan.Piece], on pages: [PagePlan.Page],
                                    pageHeight: CGFloat, file: StaticString = #filePath,
                                    line: UInt = #line) {
        XCTAssertEqual(pages.flatMap(\.pieces).sorted(), pieces.map(\.id).sorted(),
                       "every cell is on exactly one sheet", file: file, line: line)
        for page in pages {
            let room = pageHeight / page.scale
            for id in page.pieces {
                guard let piece = pieces.first(where: { $0.id == id }) else { continue }
                XCTAssertGreaterThanOrEqual(piece.top, page.top - 0.001, file: file, line: line)
                XCTAssertLessThanOrEqual(piece.bottom, page.top + room + 0.001,
                                         "cell \(id) hangs off the bottom of its sheet",
                                         file: file, line: line)
            }
        }
    }

    // MARK: - What the file turns out to be

    func testWhatComesOutIsAPDFWithOneSheetPerPageOfContent() throws {
        // Four blocks of 200pt, 220pt apart, down a 400pt-wide document.
        // US Letter leaves 504pt across, so the document is blown up by
        // 1.26 and a sheet holds 684 / 1.26 = 542pt of it: two blocks
        // (420pt) fit and three (640pt) do not.
        let pieces = (0..<4).map { index in
            let frame = CGRect(x: 0, y: CGFloat(index) * 220, width: 400, height: 200)
            return NotePDF.Piece(frame: frame) { context in
                context.setFillColor(NSColor.black.cgColor)
                context.fill(frame)
            }
        }
        let data = try XCTUnwrap(NotePDF.data(pieces, documentWidth: 400))
        XCTAssertEqual(data.prefix(4).map { Character(UnicodeScalar($0)) }.map(String.init).joined(), "%PDF")

        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(document.numberOfPages, 2)
        let box = try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, PagePlan.paper.width)
        XCTAssertEqual(box.height, PagePlan.paper.height)
    }

    func testATracedCaptureIsStillVectorsOnThePage() throws {
        // A capture as the camera makes one: the writing traced to a
        // one-page PDF in .drawings/media.
        let media = DrawingStore.mediaFolder(in: dir)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let traced = try XCTUnwrap(InkVector.pdf(of: filled(12), box: (0, 0, 12, 12), colour: .black))
        try traced.write(to: media.appending(path: "trace.pdf"))

        // A 80x80 pane, the picture half its width in the middle of it:
        // the box runs from 20 to 60 on both axes.
        let pane = CGSize(width: 80, height: 80)
        let item = CanvasItem.image(ImageItem(file: "trace.pdf", center: CGPoint(x: 0.5, y: 0.5),
                                              width: 0.5, aspect: 1))
        let piece = NotePDF.Piece(frame: item.bounds(in: pane)) { context in
            DrawingInk.draw(item, in: context, size: pane, media: self.dir)
        }
        // Small paper, so the raster below stays small: 100x100 with a 10pt
        // margin is 80pt of room, which is the pane at one to one.
        let data = try XCTUnwrap(NotePDF.data([piece], documentWidth: 80,
                                              paper: CGSize(width: 100, height: 100), margin: 10))

        XCTAssertNil(data.range(of: Data("/Subtype /Image".utf8)),
                     "a picture of the vectors was embedded instead of the vectors")

        // The sheet starts at the top of the only piece on it, so the
        // capture's left edge is 10 (margin) + 20 (its place on the pane)
        // across, and it runs 40pt down from the top margin.
        let ink = Self.raster(data, scale: 8)
        let edge = Int(30 * 8)
        let middle = Int(30 * 8)
        XCTAssertGreaterThan(ink(edge + 8, middle), 240, "inside the capture")
        XCTAssertLessThan(ink(edge - 8, middle), 15, "outside it")
        let across = (edge - 4...edge + 4).map { ink($0, middle) }
        let soft = across.filter { (16.0..<240.0).contains($0) }
        XCTAssertLessThanOrEqual(soft.count, 1, "blown up eight times a raster would ramp: \(across)")
    }

    func testTheWholeNoteGoesOnThePaperAsTextWithItsDrawingOverIt() throws {
        let markdown = """
        # A morning

        The first paragraph, which is here to be read on paper.

        - one
        - two
        """
        let drawing = Drawing(strokes: [Stroke(colorHex: "#2D7DD2", width: 3,
                                               points: [CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.7, y: 0.85)])])
        let data = try XCTUnwrap(NoteExport.pdf(markdown: markdown, drawing: drawing, media: dir,
                                                pane: CGSize(width: 600, height: 700)))
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertGreaterThanOrEqual(document.numberOfPages, 1)
        XCTAssertEqual(try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox).width, PagePlan.paper.width)
        // Real text, not a picture of it: a PDF that carries words carries
        // the font they are set in.
        XCTAssertNotNil(data.range(of: Data("/Type /Font".utf8)),
                        "the cells came out as pixels rather than as text")

        // And it is the right way up, inside the margin. The first cell
        // starts AT the top margin — a sheet begins at the top of the
        // first thing on it — so the title is printed in its own box just
        // below it, and the margin itself is bare paper.
        let ink = Self.raster(data, scale: 1)
        let margin = Int(PagePlan.margin)
        XCTAssertGreaterThan(Self.dark(ink, x: margin...(margin + 300), y: (margin + 2)...(margin + 30)), 40,
                             "nothing is printed where the title should be")
        XCTAssertEqual(Self.dark(ink, x: 0...Int(PagePlan.paper.width - 1), y: 0...(margin - 4)), 0,
                       "something is printed above the top margin")
        XCTAssertEqual(Self.dark(ink, x: 0...(margin - 4), y: 0...Int(PagePlan.paper.height - 1)), 0,
                       "something is printed in the left margin")
    }

    /// A picture put beside a paragraph in the markdown pane is beside it
    /// on paper, which is laid out the rendered way (Sean, 2026-10-02:
    /// "preserve the position of things as much as possible between
    /// markdown and wysiwyg mode") — without the mapping it went on paper
    /// a growing distance above the words it was put beside.
    @MainActor
    func testAnObjectGoesOnPaperBesideTheWordsItWasPutBeside() throws {
        let markdown = (1...8).map {
            "Paragraph \($0) of a note, with words enough in it to run onto a second line at this width, and on."
        }.joined(separator: "\n\n")
        let pane = CGSize(width: 600, height: 700)
        let source = MarkdownTextView.cellBoxes(of: markdown, width: pane.width, showMarkers: false, collapsed: [])
        guard source.count == 8 else { return XCTFail("the premise: eight cells laid out, not \(source.count)") }
        XCTAssertGreaterThan(source[6].bottom - source[6].top, 30, "the premise: two lines, the stroke under the first")
        // The paper's own stack: the same cells, `blockGap` apart from
        // where the page starts them.
        var y = MarkdownPreview.topInset + MarkdownPreview.gapHeight
        let paper: [CellSeams.Box] = source.map { cell in
            defer { y += cell.bottom - cell.top + MarkdownPreview.blockGap }
            return (top: y, bottom: y + cell.bottom - cell.top, offset: cell.offset)
        }
        let seventh = source[6]
        let drawing = Drawing(strokes: [Stroke(colorHex: "#D62828", width: 2,
                                               points: [CGPoint(x: 0.1, y: (seventh.top + 12) / pane.height),
                                                        CGPoint(x: 0.5, y: (seventh.top + 12) / pane.height)])])
        let placed = NoteExport.drawingOnPaper(drawing, markdown: markdown, cells: paper, pane: pane,
                                               markers: false, folds: [])
        XCTAssertEqual(placed.items[0].bounds(in: pane).minY - paper[6].top,
                       drawing.items[0].bounds(in: pane).minY - seventh.top, accuracy: 0.01)
        XCTAssertGreaterThan(paper[6].top - seventh.top, 50, "the premise: the paper puts the words well lower")
    }

    // MARK: - Ink that can be read on paper

    func testAPenColourThatWouldVanishOnPaperIsDarkened() {
        // Yellow is a fine pen on a dark window and is nothing at all on
        // white paper (Sean, 2026-09-19: "be mindful of text color").
        XCTAssertEqual(DrawingInk.ink("#FFFF00", on: .white).hexString, "#000000")
        XCTAssertEqual(DrawingInk.ink("#2D7DD2", on: .white).hexString, "#2D7DD2", "ink that reads is left alone")
        XCTAssertEqual(DrawingInk.ink("#222222", on: NSColor(hex: "#111111")!).hexString, "#FFFFFF",
                       "dark on dark goes the other way")
    }

    func testASpanColourIsCheckedAgainstThePaperItIsPrintedOn() {
        let source = "at <span style=\"color: #FFFF00\">dawn</span>"
        let onPaper = MarkdownInline.attributed(source, paper: NoteExport.paperHex)
        let onScreen = MarkdownInline.attributed(source)

        let printed = onPaper.runs.compactMap(\.foregroundColor).map(\.hexString)
        XCTAssertTrue(printed.contains("#000000"), "yellow words would be blank paper: \(printed)")
        let shown = onScreen.runs.compactMap(\.foregroundColor).map(\.hexString)
        XCTAssertTrue(shown.contains("#FFFF00"), "on screen the colour is left exactly as it was written")
    }

    // MARK: - Helpers

    /// A mask with every pixel inked — a traced block of solid writing.
    private func filled(_ size: Int) -> NotebookCapture.Mask {
        NotebookCapture.Mask(width: size, height: size, ink: [Bool](repeating: true, count: size * size))
    }

    /// How many pixels of that box carry ink worth seeing.
    private static func dark(_ ink: (Int, Int) -> Double, x: ClosedRange<Int>, y: ClosedRange<Int>) -> Int {
        var count = 0
        for row in y {
            for column in x where ink(column, row) > 60 { count += 1 }
        }
        return count
    }

    /// The first page of `data`, drawn into a bitmap at `scale`, as ink
    /// coverage 0…255 by pixel — x across, y DOWN from the top of the
    /// sheet (a bitmap context's first row is its top one). The same trick
    /// as `InkVectorTests`: a vector edge stays an edge however far it is
    /// blown up, and a raster turns into a ramp.
    private static func raster(_ data: Data, scale: CGFloat) -> (Int, Int) -> Double {
        let page = CGPDFDocument(CGDataProvider(data: data as CFData)!)!.page(at: 1)!
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)
        // COPIED out: the buffer belongs to the context, and reading it
        // after that goes away takes the test host with it.
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let pixels = Array(UnsafeBufferPointer(start: bytes, count: context.bytesPerRow * context.height))
        let bytesPerRow = context.bytesPerRow
        return { x, y in 255 - Double(pixels[y * bytesPerRow + x]) }
    }
}
