import AppKit
import CoreImage
import XCTest
@testable import WriteMind

/// A page drawn in code: paper, a grid of printed dots, a shadow down one
/// side, and one thick pen stroke. Only the stroke is ink.
final class NotebookCaptureTests: XCTestCase {
    private let width = 120, height = 90

    private func page(shadow: Bool = true) -> [UInt8] {
        var gray = [UInt8](repeating: 235, count: width * height)
        // A shadow: the left third is darker, evenly — not ink.
        if shadow {
            for y in 0..<height { for x in 0..<40 { gray[y * width + x] = 190 } }
        }
        // Printed dots every 12 pixels, 2×2, a little darker than the paper.
        for y in stride(from: 6, to: height, by: 12) {
            for x in stride(from: 6, to: width, by: 12) {
                for dy in 0..<2 { for dx in 0..<2 { gray[(y + dy) * width + x + dx] -= 45 } }
            }
        }
        // The pen: a 5-pixel-thick line from (20, 40) to (100, 40).
        for y in 38...42 { for x in 20...100 { gray[y * width + x] = 25 } }
        return gray
    }

    func testTheStrokeIsInkAndTheDotsAndTheShadowAreNot() {
        let mask = NotebookCapture.inkMask(gray: page(), width: width, height: height)
        XCTAssertTrue(mask.ink[40 * width + 60], "the middle of the stroke is ink")
        XCTAssertTrue(mask.ink[40 * width + 25], "the stroke is ink where it crosses the shadow too")
        XCTAssertFalse(mask.ink[6 * width + 6], "a printed dot is not ink")
        XCTAssertFalse(mask.ink[20 * width + 10], "shadow is not ink")
        XCTAssertFalse(mask.ink[20 * width + 41], "the shadow's edge is not ink")

        let bounds = try! XCTUnwrap(mask.bounds)
        XCTAssertEqual(bounds.y, 38)
        XCTAssertEqual(bounds.height, 5)
        XCTAssertEqual(bounds.x, 20)
        XCTAssertEqual(bounds.width, 81)
    }

    func testAPageWithNothingWrittenOnItGivesNoPicture() {
        var blank = page()
        for y in 38...42 { for x in 20...100 { blank[y * width + x] = 235 } }
        let mask = NotebookCapture.inkMask(gray: blank, width: width, height: height)
        XCTAssertNil(mask.bounds)
        XCTAssertNil(NotebookCapture.image(from: mask, colour: .black))
    }

    func testThePictureIsCroppedToTheWritingWithALittleRoom() throws {
        let mask = NotebookCapture.inkMask(gray: page(), width: width, height: height)
        let image = try XCTUnwrap(NotebookCapture.image(from: mask, colour: .systemBlue))
        // 81 wide and 5 tall, plus a 6 pixel margin on each side.
        XCTAssertEqual(image.size.width, 93)
        XCTAssertEqual(image.size.height, 17)
    }

    func testAMarkTheWidthOfThePageIsAnEdgeNotWriting() {
        var gray = [UInt8](repeating: 235, count: width * height)
        for x in 0..<width { gray[45 * width + x] = 20; gray[46 * width + x] = 20; gray[47 * width + x] = 20 }
        let mask = NotebookCapture.inkMask(gray: gray, width: width, height: height)
        XCTAssertNil(mask.bounds)
    }

    func testAQuarterTurnKeepsTheFrameAtTheOrigin() {
        let frame = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let turned = NotebookCapture.rotated(frame, quarterTurns: 1)
        XCTAssertEqual(turned.extent.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(turned.extent.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(turned.extent.width, 300, accuracy: 0.001)
        XCTAssertEqual(turned.extent.height, 400, accuracy: 0.001)
        XCTAssertEqual(NotebookCapture.rotated(frame, quarterTurns: 0).extent, frame.extent)
    }

    func testEveryPageComesOutTheSameShape() {
        let first = NotebookCapture.PageShape.resolve(measured: 1.40, remembered: nil)
        XCTAssertEqual(first.ratio, 1.40)
        XCTAssertEqual(NotebookCapture.PageShape.resolve(measured: 1.47, remembered: 1.40).ratio, 1.40,
                       "a page tilted a little keeps the remembered shape")
        XCTAssertEqual(NotebookCapture.PageShape.resolve(measured: 1.62, remembered: 1.40).ratio, 1.62,
                       "a different notebook sets a new shape")
        XCTAssertEqual(NotebookCapture.PageShape.resolve(measured: 0.7, remembered: nil).ratio, 1,
                       "the ratio is long over short, never below 1")

        let upright = first.size(portrait: true)
        XCTAssertEqual(upright.width, 1200)
        XCTAssertEqual(upright.height, 1680)
        let sideways = first.size(portrait: false)
        XCTAssertEqual(sideways.width, 1680)
        XCTAssertEqual(sideways.height, 1200)
    }

    func testTheWholePageIsResampledToTheShape() throws {
        let page = CIImage(color: .gray).cropped(to: CGRect(x: 10, y: 20, width: 300, height: 400))
        let (normalised, shape) = NotebookCapture.normalised(page, rememberedRatio: nil)
        XCTAssertEqual(shape.ratio, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(normalised.extent, CGRect(x: 0, y: 0, width: 1200, height: 1600))
        let picture = try XCTUnwrap(NotebookCapture.picture(of: normalised))
        XCTAssertEqual(DrawingStore.pixelSize(of: picture), CGSize(width: 1200, height: 1600))
    }

    func testAPagePictureIsStoredAsAJPEG() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let small = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 30, height: 20))
        let picture = try XCTUnwrap(NotebookCapture.picture(of: small))
        let imported = try XCTUnwrap(DrawingStore.importImage(picture, in: folder, jpegQuality: 0.8))
        XCTAssertTrue(imported.file.hasSuffix(".jpg"))
        XCTAssertEqual(imported.pixelWidth, 30)
        XCTAssertEqual(imported.pixelHeight, 20)
        XCTAssertNotNil(DrawingStore.loadImage(imported.file, in: folder))
    }

    /// Sean, 2026-09-22: "the drawing and image when selected from the
    /// camera are too small.. they should be the size you can see in the
    /// output viewer". A page fills the pane the way the viewfinder fills
    /// it, less a margin — not the two-fifths it used to take.
    func testAPageLandsAtTheSizeTheViewfinderShowsIt() {
        let page = CGSize(width: 1200, height: 1600), pane = CGSize(width: 900, height: 600)
        let whole = NotebookCapture.placement(frame: CGRect(origin: .zero, size: page),
                                              pageSize: page, pane: pane, nudge: 0)
        // Its HEIGHT is what fills the pane: a portrait page in a pane
        // wider than it is tall is held by the short way.
        let height = whole.width * pane.width * 1600 / 1200
        XCTAssertEqual(height / pane.height, 0.9, accuracy: 0.001)
        XCTAssertGreaterThan(NotebookCapture.pageFraction, 0.8, "it used to be two fifths")
        XCTAssertLessThan(NotebookCapture.pageFraction, 1,
                          "and it keeps its handles off the edges")
    }

    func testTheWritingIsPlacedWhereItWasOnThePageAtThePagesScale() {
        let page = CGSize(width: 1200, height: 1600), pane = CGSize(width: 900, height: 600)
        // The page itself: its share of the pane's height tall, in the middle.
        let pageHeight = 600 * NotebookCapture.pageFraction
        let pageWidth = pageHeight * 1200 / 1600
        let scale = pageWidth / 1200
        let whole = NotebookCapture.placement(frame: CGRect(origin: .zero, size: page),
                                              pageSize: page, pane: pane, nudge: 0)
        XCTAssertEqual(whole.center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(whole.center.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(whole.width, pageWidth / 900, accuracy: 0.0001)
        // Writing in the top-left quarter lands up and left of the middle,
        // a quarter of the page's size.
        let ink = NotebookCapture.placement(frame: CGRect(x: 0, y: 0, width: 600, height: 800),
                                            pageSize: page, pane: pane, nudge: 0)
        XCTAssertEqual(ink.width, 600 * scale / 900, accuracy: 0.0001)
        XCTAssertEqual(ink.center.x, 0.5 - 300 * scale / 900, accuracy: 0.0001)
        XCTAssertEqual(ink.center.y, 0.5 - 400 * scale / 600, accuracy: 0.0001)
        // Two captures of the same notebook: the same size on the pane.
        let again = NotebookCapture.placement(frame: CGRect(origin: .zero, size: page),
                                              pageSize: page, pane: pane, nudge: 0.03)
        XCTAssertEqual(again.width, whole.width, accuracy: 0.0001)
        XCTAssertEqual(again.center.x, 0.53, accuracy: 0.0001)
    }

    func testOnlyTheWritingInsideAWindowCounts() {
        let mask = NotebookCapture.inkMask(gray: page(), width: width, height: height)
        // The stroke runs from x 20 to 100; a window over the left of it
        // sees x 20 to 59, plus the 6-pixel margin.
        let box = try! XCTUnwrap(NotebookCapture.inkBox(of: mask, within: CGRect(x: 0, y: 0, width: 60, height: 90)))
        XCTAssertEqual(box.x, 14)
        XCTAssertEqual(box.width, 52)
        XCTAssertEqual(box.y, 32)
        XCTAssertEqual(box.height, 17)
        XCTAssertNil(NotebookCapture.inkBox(of: mask, within: CGRect(x: 0, y: 0, width: 60, height: 30)),
                     "a window with no writing in it")
    }

    func testTheHomographySendsTheQuadsCornersToTheUnitSquare() {
        // A page seen tilted: narrower at the top.
        let quad = NotebookCapture.Quad(topLeft: CGPoint(x: 1, y: 2), topRight: CGPoint(x: 3, y: 2),
                                        bottomLeft: CGPoint(x: 0, y: 0), bottomRight: CGPoint(x: 4, y: 0))
        let toQuad = NotebookCapture.Homography.unitSquare(to: quad)
        let toSquare = toQuad.inverted()
        func near(_ a: CGPoint, _ b: CGPoint, _ what: String) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-6, what)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-6, what)
        }
        near(toQuad.apply(CGPoint(x: 1, y: 1)), quad.bottomRight, "(1,1) is the bottom right")
        near(toQuad.apply(CGPoint(x: 0, y: 1)), quad.bottomLeft, "(0,1) is the bottom left")
        near(toSquare.apply(quad.topLeft), CGPoint(x: 0, y: 0), "top left")
        near(toSquare.apply(quad.topRight), CGPoint(x: 1, y: 0), "top right")
        near(toSquare.apply(quad.bottomRight), CGPoint(x: 1, y: 1), "bottom right")
        near(toSquare.apply(quad.bottomLeft), CGPoint(x: 0, y: 1), "bottom left")
        near(toSquare.apply(CGPoint(x: 2, y: 2)), CGPoint(x: 0.5, y: 0), "the middle of the top edge")
    }

    func testABoxOnThePaneBecomesAFractionOfThePictureShown() throws {
        // A 400×300 picture in an 800×400 pane is shown 533 wide and 400
        // tall, in the middle: from x 133 to 667.
        let frame = CGSize(width: 400, height: 300), pane = CGSize(width: 800, height: 400)
        let shown = NotebookCapture.displayedFrame(of: frame, in: pane)
        XCTAssertEqual(shown.minX, 400.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(shown.width, 1600.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(shown.height, 400, accuracy: 0.001)

        let region = try XCTUnwrap(NotebookCapture.region(
            from: CGRect(x: 0, y: 100, width: 400, height: 100), frame: frame, in: pane))
        XCTAssertEqual(region.minX, 0, accuracy: 1e-6, "clipped to the picture")
        XCTAssertEqual(region.width, (400 - 400.0 / 3.0) / (1600.0 / 3.0), accuracy: 1e-6)
        XCTAssertEqual(region.minY, 0.25, accuracy: 1e-6)
        XCTAssertEqual(region.height, 0.25, accuracy: 1e-6)
        XCTAssertNil(NotebookCapture.region(from: CGRect(x: 0, y: 0, width: 100, height: 100),
                                            frame: frame, in: pane),
                     "a box beside the picture is nothing")
    }

    func testASectionFindsItsBoxOnThePagePastTheInset() throws {
        let extent = CGRect(x: 0, y: 0, width: 400, height: 300)
        // A page that fills the frame exactly, y up as Vision counts it.
        let square = NotebookCapture.Quad(topLeft: CGPoint(x: 0, y: 300), topRight: CGPoint(x: 400, y: 300),
                                          bottomLeft: CGPoint(x: 0, y: 0), bottomRight: CGPoint(x: 400, y: 0))
        let page = CGSize(width: 1200, height: 900)
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        let plain = try XCTUnwrap(NotebookCapture.pageBox(for: region, quad: square, frame: extent,
                                                          inset: 0, pageSize: page))
        XCTAssertEqual(plain, CGRect(x: 300, y: 225, width: 600, height: 450))

        // Past a 10% inset, 0.25 of the frame is (0.25 − 0.1) / 0.8 of the page.
        let inset = try XCTUnwrap(NotebookCapture.pageBox(for: region, quad: square, frame: extent,
                                                          inset: 0.1, pageSize: page))
        // Boxed to whole pixels, so an edge may sit one pixel out.
        XCTAssertEqual(inset.minX, 225, accuracy: 1)
        XCTAssertEqual(inset.maxX, 975, accuracy: 1)
        XCTAssertEqual(inset.minY, 168.75, accuracy: 1)
        XCTAssertEqual(inset.maxY, 731.25, accuracy: 1)

        XCTAssertNil(NotebookCapture.pageBox(for: CGRect(x: 0.99, y: 0.99, width: 0.01, height: 0.01),
                                             quad: square, frame: extent, inset: 0.1, pageSize: page),
                     "a section outside the inset page is nothing")
        let noPage = try XCTUnwrap(NotebookCapture.pageBox(for: region, quad: nil, frame: extent,
                                                           inset: 0, pageSize: page))
        XCTAssertEqual(noPage, plain, "with no page found the frame stands in for one")
    }

    /// A camera frame drawn in code: a slightly turned page on a dark desk,
    /// with a thick stroke on it — the whole pipeline, Vision included.
    private func cameraFrame() -> CIImage {
        let width = 1920, height = 1080
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.25, green: 0.22, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: 960, y: 540)
        context.rotate(by: 4 * .pi / 180)
        context.setFillColor(CGColor(red: 0.95, green: 0.94, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: -330, y: -470, width: 660, height: 940))
        context.setStrokeColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.setLineWidth(9)
        context.move(to: CGPoint(x: -200, y: 100))
        context.addLine(to: CGPoint(x: 200, y: 140))
        context.strokePath()
        context.restoreGState()
        return CIImage(cgImage: context.makeImage()!)
    }

    func testAWholeFrameGoesThroughBothPipelinesInReasonableTime() {
        let frame = cameraFrame()
        let pageStart = Date()
        let page = NotebookCapture.capture(.page, from: frame, quarterTurns: 0, colour: .black, rememberedRatio: nil)
        let pageTime = Date().timeIntervalSince(pageStart)
        let inkStart = Date()
        let ink = NotebookCapture.capture(.ink, from: frame, quarterTurns: 0, colour: .black, rememberedRatio: nil)
        let inkTime = Date().timeIntervalSince(inkStart)
        print("capture timing: page \(pageTime)s (found: \(page != nil)), ink \(inkTime)s")
        XCTAssertNotNil(ink, "the stroke on the page is writing")
        XCTAssertLessThan(pageTime, 8, "the whole page took \(pageTime)s")
        XCTAssertLessThan(inkTime, 8, "the writing took \(inkTime)s")
        if let page {
            XCTAssertTrue(page.pageFound)
            XCTAssertEqual(min(page.pageSize.width, page.pageSize.height), 1200, accuracy: 0.5)
        }
    }

    func testTheRawPictureIsTheFrameOrTheBoxedPartOfIt() throws {
        let frame = cameraFrame()
        let whole = try XCTUnwrap(NotebookCapture.capture(.raw, from: frame, quarterTurns: 0, colour: .black,
                                                          rememberedRatio: nil))
        XCTAssertEqual(whole.pageSize, CGSize(width: 1920, height: 1080))
        XCTAssertFalse(whole.pageFound)
        XCTAssertEqual(DrawingStore.pixelSize(of: whole.image), CGSize(width: 1920, height: 1080))
        let part = try XCTUnwrap(NotebookCapture.capture(.raw, from: frame, quarterTurns: 0, colour: .black,
                                                         rememberedRatio: nil,
                                                         region: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        XCTAssertEqual(part.pageSize, CGSize(width: 960, height: 540))
    }

    func testTheGreyReadoutIsTopRowFirst() throws {
        // Black on top, white below: the first row must be dark.
        let bottom = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20))
        let top = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 20, width: 40, height: 20))
        let image = top.composited(over: bottom)
        let (gray, width, height) = try XCTUnwrap(NotebookCapture.grayscale(image, maxWidth: 40))
        XCTAssertEqual(width, 40)
        XCTAssertEqual(height, 40)
        XCTAssertLessThan(gray[0], 30)
        XCTAssertGreaterThan(gray[(height - 1) * width], 225)
    }
}
