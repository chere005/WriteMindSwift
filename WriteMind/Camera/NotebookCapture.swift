import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// A page of the notebook, lifted off the camera and put on the drawing layer
/// (Sean, 2026-09-18): find the page, square it up so the dot grid is
/// straight even when the notebook was not, and then either keep only the
/// writing — the paper and its dots dropped — or keep the page as
/// photographed, trimmed to its edges. Every page comes out the same size.
enum NotebookCapture {
    /// Just the writing, or the page as photographed.
    enum Mode: String, CaseIterable, Identifiable {
        case ink
        case page
        /// The camera picture as it is — no page found, nothing squared.
        case raw

        var id: String { rawValue }
        var title: String {
            switch self {
            case .ink: return "Just the Writing"
            case .page: return "The Whole Page"
            case .raw: return "The Raw Picture"
            }
        }
    }

    /// The shape every page picture comes out at (Sean, 2026-09-18:
    /// "normalize page images to the same size"). Squaring a page up gives
    /// back a rectangle whose proportions depend on how the page was tilted
    /// towards the camera, so measuring each one would make every capture a
    /// slightly different size. The shape is REMEMBERED instead: the first
    /// page measured sets it, later pages within a tolerance of it are
    /// resampled to exactly it, and one further off is a different notebook
    /// (or the page turned sideways) and sets a new shape.
    struct PageShape: Equatable {
        /// The short side, in pixels — enough for handwriting at 300dpi-ish.
        static let shortSide = 1200
        static let tolerance = 0.12
        /// How much of each side of a found page is cut away before it is
        /// resampled: the corners Vision hands over sit ON the page's edge,
        /// so the edge itself — its shadow, the desk behind a curl — came in
        /// as a dark rim (Sean, 2026-09-18: "drop page edge cruft").
        static let edgeInset = 0.025

        /// Long side over short side, never below 1.
        var ratio: Double

        static func resolve(measured: Double, remembered: Double?) -> PageShape {
            let measured = max(1, measured)
            if let remembered, remembered >= 1, abs(measured - remembered) / remembered <= tolerance {
                return PageShape(ratio: remembered)
            }
            return PageShape(ratio: measured)
        }

        func size(portrait: Bool) -> (width: Int, height: Int) {
            let long = Int((Double(Self.shortSide) * ratio).rounded())
            return portrait ? (Self.shortSide, long) : (long, Self.shortSide)
        }
    }

    /// What a capture produced, and where it sits on the page.
    struct Result {
        var image: NSImage
        /// The normalised page, in pixels.
        var pageSize: CGSize
        /// The picture's box on the page, in page pixels from the top left:
        /// the whole page, or the writing's box.
        var frame: CGRect
        var shape: PageShape
        /// False when no page was found and the whole frame stood in for one
        /// — a shape measured off that is not worth remembering.
        var pageFound: Bool
        /// The same writing traced into outlines, as a one-page PDF (Sean,
        /// 2026-09-19: "make it a vector graphic so it scales well"). Only
        /// `.ink` has one; a photograph of a page is pixels and stays pixels.
        var vector: Data?
    }

    /// Where a capture goes, as fractions of the pane. A whole page fits
    /// inside `pageFraction` of the pane either way; the writing off a page,
    /// or a section of it, is placed at the scale the page would have had,
    /// where it was on the page — so two captures of the same notebook are
    /// the same size on the pane.
    struct Placement: Equatable {
        var center: CGPoint
        var width: Double
    }

    /// A PAGE LANDS THE SIZE THE VIEWFINDER SHOWS IT — filling the pane,
    /// give or take the margin that keeps its handles off the edges
    /// (Sean, 2026-09-22: "the drawing and image when selected from the
    /// camera are too small.. they should be the size you can see in the
    /// output viewer").
    ///
    /// It was 0.42, from "make the selection smaller" (Sean, 2026-09-18)
    /// when 60% covered the note — so this is a reversal and is written
    /// down as one. What changed underneath it: a capture no longer
    /// pushes the text about at all (nothing on the drawing layer moves
    /// the text, 2026-09-20), so a big picture costs the note nothing
    /// and there is no reason left to shrink a page you have just taken
    /// a photograph of.
    ///
    /// Still ONE number for every capture, which is the whole point of
    /// the placement maths: two photographs of the same notebook come
    /// out the same size on the pane whether they were taken from a foot
    /// away or three. Matching the viewfinder EXACTLY — the page's real
    /// share of the video frame — would make every capture a different
    /// size, which is the thing `notebookPageShape` exists to prevent.
    static let pageFraction = 0.9

    static func placement(frame: CGRect, pageSize: CGSize, pane: CGSize, nudge: Double) -> Placement {
        let pageWidth = min(pane.width * pageFraction,
                            pane.height * pageFraction * pageSize.width / max(1, pageSize.height))
        let scale = pageWidth / max(1, pageSize.width)
        let dx = (frame.midX - pageSize.width / 2) * scale / pane.width
        let dy = (frame.midY - pageSize.height / 2) * scale / pane.height
        return Placement(center: CGPoint(x: 0.5 + nudge + dx, y: 0.5 + nudge + dy),
                         width: frame.width * scale / pane.width)
    }
    /// The four corners of the page, in image pixels, y up — Vision's and
    /// Core Image's shared convention.
    struct Quad: Equatable {
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomLeft: CGPoint
        var bottomRight: CGPoint
    }

    /// The pixels that are ink, and where they are.
    struct Mask: Equatable {
        var width: Int
        var height: Int
        var ink: [Bool]
        /// The box the ink sits in, or nil when there is none.
        var bounds: (x: Int, y: Int, width: Int, height: Int)? { bounds(within: nil) }

        /// The box the ink inside `window` (page pixels, top-left origin)
        /// sits in — the whole mask when there is no window.
        func bounds(within window: CGRect?) -> (x: Int, y: Int, width: Int, height: Int)? {
            let x0 = window.map { max(0, Int($0.minX)) } ?? 0
            let y0 = window.map { max(0, Int($0.minY)) } ?? 0
            let x1 = window.map { min(width, Int($0.maxX.rounded(.up))) } ?? width
            let y1 = window.map { min(height, Int($0.maxY.rounded(.up))) } ?? height
            guard x1 > x0, y1 > y0 else { return nil }
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in y0..<y1 {
                for x in x0..<x1 where ink[y * width + x] {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else { return nil }
            return (minX, minY, maxX - minX + 1, maxY - minY + 1)
        }

        static func == (lhs: Mask, rhs: Mask) -> Bool {
            lhs.width == rhs.width && lhs.height == rhs.height && lhs.ink == rhs.ink
        }
    }

    /// The whole pipeline. `quarterTurns` is how the video pane is turned,
    /// so the page comes in the way it is seen. `region` is a section of the
    /// picture as shown — a fraction of the upright frame, top-left origin —
    /// and only what falls inside it comes in. Nil when nothing was found:
    /// no writing, no page for a whole-page capture, or a section that is
    /// not on the page.
    static func capture(_ mode: Mode, from frame: CIImage, quarterTurns: Int, colour: NSColor,
                        rememberedRatio: Double?, region: CGRect? = nil) -> Result? {
        let upright = rotated(frame, quarterTurns: quarterTurns)
        let quad = mode == .raw ? nil : pageQuad(in: upright)
        // The writing can still be read off a frame the page fills; a photo
        // of "the page" with no page in it would just be the desk — unless
        // the desk is what was pointed at.
        if mode == .page, quad == nil, region == nil { return nil }
        let inset = quad == nil ? 0 : PageShape.edgeInset
        let page = quad.map { rectified(upright, to: $0) } ?? upright
        let (normalised, shape) = self.normalised(page, rememberedRatio: rememberedRatio, inset: inset)
        let size = CGSize(width: normalised.extent.width, height: normalised.extent.height)
        var window = CGRect(origin: .zero, size: size)
        if let region {
            guard let box = pageBox(for: region, quad: quad, frame: upright.extent, inset: inset, pageSize: size)
            else { return nil }
            window = box
        }

        switch mode {
        case .raw:
            return rawPicture(of: upright, region: region)
        case .page:
            let part = region == nil ? normalised : normalised.cropped(to: flipped(window, in: size))
            guard let picture = picture(of: part) else { return nil }
            return Result(image: picture, pageSize: size, frame: window, shape: shape, pageFound: quad != nil)
        case .ink:
            guard let (gray, width, height) = grayscale(normalised, maxWidth: size.width) else { return nil }
            let mask = inkMask(gray: gray, width: width, height: height)
            guard let box = inkBox(of: mask, within: region == nil ? nil : window),
                  let picture = image(from: mask, colour: colour, box: box) else { return nil }
            return Result(image: picture, pageSize: size,
                          frame: CGRect(x: box.x, y: box.y, width: box.width, height: box.height),
                          shape: shape, pageFound: quad != nil,
                          vector: InkVector.pdf(of: mask, box: box, colour: colour))
        }
    }

    /// The frame as it is, or the section of it that was boxed — the frame
    /// stands in for the page, so the placement maths still applies.
    static func rawPicture(of upright: CIImage, region: CGRect?) -> Result? {
        let extent = upright.extent
        var part = upright
        if let region {
            let box = CGRect(x: extent.minX + region.minX * extent.width,
                             y: extent.minY + (1 - region.maxY) * extent.height,
                             width: region.width * extent.width, height: region.height * extent.height).integral
            guard box.width >= 2, box.height >= 2 else { return nil }
            part = upright.cropped(to: box)
        }
        guard let image = picture(of: part) else { return nil }
        let size = part.extent.size
        let ratio = max(size.width, size.height) / max(1, min(size.width, size.height))
        return Result(image: image, pageSize: size, frame: CGRect(origin: .zero, size: size),
                      shape: PageShape(ratio: ratio), pageFound: false)
    }

    /// A box in page pixels (top-left origin) as Core Image counts it (y up).
    static func flipped(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: box.minX, y: size.height - box.maxY, width: box.width, height: box.height)
    }

    // MARK: - A section of the picture

    /// A projective map from the unit square to a quad — the maths behind
    /// CIPerspectiveCorrection, needed here to send points the OTHER way: a
    /// section drawn on the camera picture has to find its place on the
    /// squared-up page. Heckbert's closed form for the square-to-quad case.
    struct Homography: Equatable {
        /// Row-major 3×3.
        var m: [Double]

        /// (0,0) → topLeft, (1,0) → topRight, (1,1) → bottomRight, (0,1) →
        /// bottomLeft: u runs across the page, v runs DOWN it.
        static func unitSquare(to quad: Quad) -> Homography {
            let (x0, y0) = (Double(quad.topLeft.x), Double(quad.topLeft.y))
            let (x1, y1) = (Double(quad.topRight.x), Double(quad.topRight.y))
            let (x2, y2) = (Double(quad.bottomRight.x), Double(quad.bottomRight.y))
            let (x3, y3) = (Double(quad.bottomLeft.x), Double(quad.bottomLeft.y))
            let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
            let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
            if abs(dx3) < 1e-9, abs(dy3) < 1e-9 {
                // A parallelogram: plain affine.
                return Homography(m: [x1 - x0, x3 - x0, x0,
                                      y1 - y0, y3 - y0, y0,
                                      0, 0, 1])
            }
            let det = dx1 * dy2 - dx2 * dy1
            guard abs(det) > 1e-12 else { return Homography(m: [1, 0, 0, 0, 1, 0, 0, 0, 1]) }
            let g = (dx3 * dy2 - dx2 * dy3) / det
            let h = (dx1 * dy3 - dx3 * dy1) / det
            return Homography(m: [x1 - x0 + g * x1, x3 - x0 + h * x3, x0,
                                  y1 - y0 + g * y1, y3 - y0 + h * y3, y0,
                                  g, h, 1])
        }

        func apply(_ point: CGPoint) -> CGPoint {
            let x = Double(point.x), y = Double(point.y)
            let w = m[6] * x + m[7] * y + m[8]
            guard abs(w) > 1e-12 else { return point }
            return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / w, y: (m[3] * x + m[4] * y + m[5]) / w)
        }

        func inverted() -> Homography {
            let a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
            let cofA = e * i - f * h, cofB = -(d * i - f * g), cofC = d * h - e * g
            let det = a * cofA + b * cofB + c * cofC
            guard abs(det) > 1e-12 else { return self }
            let adjugate = [cofA, -(b * i - c * h), b * f - c * e,
                            cofB, a * i - c * g, -(a * f - c * d),
                            cofC, -(a * h - b * g), a * e - b * d]
            return Homography(m: adjugate.map { $0 / det })
        }
    }

    /// Where the camera picture sits in its pane: fitted whole, centred —
    /// what the preview layer's resizeAspect does.
    static func displayedFrame(of frame: CGSize, in pane: CGSize) -> CGRect {
        guard frame.width > 0, frame.height > 0, pane.width > 0, pane.height > 0 else { return .zero }
        let scale = min(pane.width / frame.width, pane.height / frame.height)
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        return CGRect(x: (pane.width - size.width) / 2, y: (pane.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// A rectangle drawn on the pane, as a fraction of the picture shown in
    /// it (top-left origin), clipped to the picture; nil when it misses it.
    static func region(from rect: CGRect, frame: CGSize, in pane: CGSize) -> CGRect? {
        let shown = displayedFrame(of: frame, in: pane)
        guard shown.width > 0, shown.height > 0 else { return nil }
        let clipped = rect.intersection(shown)
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
        return CGRect(x: (clipped.minX - shown.minX) / shown.width,
                      y: (clipped.minY - shown.minY) / shown.height,
                      width: clipped.width / shown.width, height: clipped.height / shown.height)
    }

    /// Where a section of the camera picture lands on the normalised page:
    /// the section's corners are taken through the page's perspective (or
    /// straight across when no page was found and the frame stands in for
    /// one), past the edge inset, and boxed. In page pixels, top-left
    /// origin, clipped to the page; nil when none of it is on the page.
    static func pageBox(for region: CGRect, quad: Quad?, frame extent: CGRect, inset: Double,
                        pageSize: CGSize) -> CGRect? {
        let corners = [CGPoint(x: region.minX, y: region.minY), CGPoint(x: region.maxX, y: region.minY),
                       CGPoint(x: region.maxX, y: region.maxY), CGPoint(x: region.minX, y: region.maxY)]
        let unit: [CGPoint]
        if let quad {
            let toSquare = Homography.unitSquare(to: quad).inverted()
            unit = corners.map { corner in
                // A fraction of the upright frame, top-left origin → the
                // frame's own pixels, y up, which is where the quad lives.
                toSquare.apply(CGPoint(x: extent.minX + corner.x * extent.width,
                                       y: extent.minY + (1 - corner.y) * extent.height))
            }
        } else {
            unit = corners
        }
        var box: CGRect?
        for point in unit {
            let u = (Double(point.x) - inset) / (1 - 2 * inset)
            let v = (Double(point.y) - inset) / (1 - 2 * inset)
            let dot = CGRect(origin: CGPoint(x: u * pageSize.width, y: v * pageSize.height), size: .zero)
            box = box.map { $0.union(dot) } ?? dot
        }
        guard let box else { return nil }
        let clipped = box.intersection(CGRect(origin: .zero, size: pageSize)).integral
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
        return clipped
    }

    /// The squared-up page, its edge cut away, resampled to the page shape
    /// at the origin.
    static func normalised(_ page: CIImage, rememberedRatio: Double?, inset: Double = 0) -> (CIImage, PageShape) {
        let full = page.extent
        let extent = inset > 0
            ? full.insetBy(dx: full.width * inset, dy: full.height * inset)
            : full
        let portrait = extent.height >= extent.width
        let measured = max(extent.width, extent.height) / max(1, min(extent.width, extent.height))
        let shape = PageShape.resolve(measured: measured, remembered: rememberedRatio)
        let (width, height) = shape.size(portrait: portrait)
        let scaled = page
            .cropped(to: extent)
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / max(1, extent.width),
                                               y: CGFloat(height) / max(1, extent.height)))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return (scaled, shape)
    }

    /// The page as photographed.
    static func picture(of image: CIImage) -> NSImage? {
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return DrawingStore.image(from: cgImage)
    }

    // MARK: - The page

    /// Where the page is. Vision's document segmentation first — it is made
    /// for exactly this — and a plain rectangle search when that finds
    /// nothing, which happens with a page that fills the frame.
    static func pageQuad(in image: CIImage) -> Quad? {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        let document = VNDetectDocumentSegmentationRequest()
        try? handler.perform([document])
        if let found = document.results?.first, found.confidence > 0.5 {
            return quad(from: found, in: image.extent)
        }

        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumAspectRatio = 0.3
        rectangles.minimumSize = 0.25
        rectangles.minimumConfidence = 0.6
        rectangles.quadratureTolerance = 30
        rectangles.maximumObservations = 1
        try? handler.perform([rectangles])
        if let found = rectangles.results?.first {
            return quad(from: found, in: image.extent)
        }
        return nil
    }

    static func quad(from observation: VNRectangleObservation, in extent: CGRect) -> Quad {
        func point(_ normalised: CGPoint) -> CGPoint {
            CGPoint(x: extent.minX + normalised.x * extent.width,
                    y: extent.minY + normalised.y * extent.height)
        }
        return Quad(topLeft: point(observation.topLeft), topRight: point(observation.topRight),
                    bottomLeft: point(observation.bottomLeft), bottomRight: point(observation.bottomRight))
    }

    /// Pull the page's corners out to a rectangle: what squares the grid.
    static func rectified(_ image: CIImage, to quad: Quad) -> CIImage {
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.topLeft = quad.topLeft
        filter.topRight = quad.topRight
        filter.bottomLeft = quad.bottomLeft
        filter.bottomRight = quad.bottomRight
        filter.crop = true
        guard let output = filter.outputImage else { return image }
        return output.transformed(by: CGAffineTransform(translationX: -output.extent.minX,
                                                        y: -output.extent.minY))
    }

    /// Quarter turns clockwise, as the video pane shows them. Core Image's y
    /// points up, so clockwise on screen is a negative angle here.
    static func rotated(_ image: CIImage, quarterTurns: Int) -> CIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }
        let turned = image.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2))
        return turned.transformed(by: CGAffineTransform(translationX: -turned.extent.minX,
                                                        y: -turned.extent.minY))
    }

    // MARK: - The ink

    /// The page as 8-bit grey, no wider than `maxWidth`, top row first.
    static func grayscale(_ image: CIImage, maxWidth: CGFloat) -> (gray: [UInt8], width: Int, height: Int)? {
        let extent = image.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        let scale = min(1, maxWidth / extent.width)
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = Int(extent.width * scale), height = Int(extent.height * scale)
        guard width > 1, height > 1 else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height)
        let context = CIContext(options: [.cacheIntermediates: false])
        // A bitmap render comes out top row first already (Core Image turns
        // its y-up coordinates over for the buffer), which is what the mask
        // and the picture both expect — a flip here would stand the page on
        // its head.
        context.render(scaled, toBitmap: &bytes, rowBytes: width,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        return (bytes, width, height)
    }

    /// Ink is what is darker than the paper around it — a local comparison,
    /// so a shadow across the page is not ink — and then only the marks big
    /// enough to be writing: the printed dots are small blobs, and they go;
    /// a dot grid whose dots are not small goes too, once it is seen to be
    /// a grid.
    static func inkMask(gray: [UInt8], width: Int, height: Int,
                        darkerBy threshold: Int = 28, minimumSize: Int = 7, minimumArea: Int = 20) -> Mask {
        let ink = darkerThanPaper(gray: gray, width: width, height: height, darkerBy: threshold)
        return Mask(width: width, height: height,
                    ink: keepingMarks(ink, width: width, height: height,
                                      minimumSize: minimumSize, minimumArea: minimumArea))
    }

    /// Every pixel darker than the paper round it by `threshold` levels —
    /// the raw ink, dots and specks and page edge included.
    static func darkerThanPaper(gray: [UInt8], width: Int, height: Int, darkerBy threshold: Int = 28) -> [Bool] {
        precondition(gray.count == width * height)
        let mean = localMean(gray, width: width, height: height,
                             radius: localMeanRadius(width: width, height: height))
        var ink = [Bool](repeating: false, count: width * height)
        for index in 0..<(width * height) where Int(mean[index]) - Int(gray[index]) >= threshold {
            ink[index] = true
        }
        return ink
    }

    /// How far the "darker than the paper round it" test looks. It is the
    /// one number that decides how big a solid shape has to be before the
    /// test hollows it out — past about this radius the middle of a blot
    /// is no darker than its own surroundings and stops being ink — so
    /// anything that has to tell a drawn outline from a hollowed-out blob
    /// asks for it rather than guessing (`HandwritingMarks.checkbox`).
    static func localMeanRadius(width: Int, height: Int) -> Int {
        max(8, min(width, height) / 40)
    }

    /// The average of a square window round every pixel, from a summed-area
    /// table so the window's size does not matter.
    static func localMean(_ gray: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        let stride = width + 1
        var sums = [Int](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var rowSum = 0
            for x in 0..<width {
                rowSum += Int(gray[y * width + x])
                sums[(y + 1) * stride + (x + 1)] = sums[y * stride + (x + 1)] + rowSum
            }
        }
        var mean = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let top = max(0, y - radius), bottom = min(height - 1, y + radius)
            for x in 0..<width {
                let left = max(0, x - radius), right = min(width - 1, x + radius)
                let total = sums[(bottom + 1) * stride + (right + 1)] - sums[top * stride + (right + 1)]
                    - sums[(bottom + 1) * stride + left] + sums[top * stride + left]
                let count = (bottom - top + 1) * (right - left + 1)
                mean[y * width + x] = UInt8(clamping: total / count)
            }
        }
        return mean
    }

    /// One connected blob of ink: its box in mask pixels (top-left origin)
    /// and its pixels, as indices into a mask `stride` wide.
    struct Component: Equatable {
        var stride: Int
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int
        var pixels: [Int]

        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
        var area: Int { pixels.count }
        /// How much of its box is ink: 1 for a solid dot, small for a ring.
        var fill: Double { Double(area) / Double(width * height) }
        var centre: (x: Double, y: Double) { (Double(minX + maxX) / 2, Double(minY + maxY) / 2) }
    }

    /// The marks on a page, sorted: every blob, the ones that make up the
    /// printed dot grid, and the ones that are writing.
    struct Marks {
        var width: Int
        var height: Int
        var components: [Component]
        /// Indices into `components` of the dots of a printed grid — nil
        /// when the page has no grid, so a stray dot is not "a lattice".
        var lattice: Set<Int>?
        /// Indices into `components` of what is left once specks, the page
        /// edge and the grid are gone: the writing.
        var writing: [Int]

        var writingComponents: [Component] { writing.map { components[$0] } }

        func mask(of indices: some Sequence<Int>) -> [Bool] {
            var mask = [Bool](repeating: false, count: width * height)
            for index in indices {
                for pixel in components[index].pixels { mask[pixel] = true }
            }
            return mask
        }

        func writingMask() -> [Bool] { mask(of: writing) }
        func latticeMask() -> [Bool]? { lattice.map { mask(of: $0) } }
    }

    /// Connected marks, with the specks, the page edges and the printed dot
    /// grid taken out.
    static func keepingMarks(_ ink: [Bool], width: Int, height: Int,
                             minimumSize: Int, minimumArea: Int) -> [Bool] {
        marks(in: ink, width: width, height: height, minimumSize: minimumSize, minimumArea: minimumArea)
            .writingMask()
    }

    /// Every blob sorted into what it is. A speck is smaller than
    /// `minimumSize` across or `minimumArea` in pixels; a page edge is a mark
    /// most of the width or height of the page; a grid dot is one the
    /// lattice search picked out, whatever its size (Sean, 2026-09-19: "if
    /// the paper has a dot background, make sure to ignore the dots" — at
    /// page resolution a printed dot can reach the speck limit and had been
    /// getting through). An off-grid small mark — an i-dot, a full stop, a
    /// 。— is treated exactly as before.
    static func marks(in ink: [Bool], width: Int, height: Int,
                      minimumSize: Int = 7, minimumArea: Int = 20) -> Marks {
        let all = components(in: ink, width: width, height: height)
        let lattice = dotLattice(among: all, width: width, height: height)
        var writing: [Int] = []
        for (index, component) in all.enumerated() {
            let isSpeck = component.area < minimumArea || max(component.width, component.height) < minimumSize
            let isEdge = component.width > width * 85 / 100 || component.height > height * 85 / 100
            let isDot = lattice?.contains(index) ?? false
            if !isSpeck, !isEdge, !isDot { writing.append(index) }
        }
        return Marks(width: width, height: height, components: all, lattice: lattice, writing: writing)
    }

    /// The 8-connected blobs of a mask, in the order their first pixel is
    /// met reading the mask top row first.
    static func components(in ink: [Bool], width: Int, height: Int) -> [Component] {
        precondition(ink.count == width * height)
        var label = [Int32](repeating: 0, count: width * height)
        var found: [Component] = []
        var next: Int32 = 1
        var stack: [Int] = []

        for start in 0..<(width * height) where ink[start] && label[start] == 0 {
            var pixels: [Int] = []
            var minX = width, maxX = -1, minY = height, maxY = -1
            label[start] = next
            stack.append(start)
            while let index = stack.popLast() {
                pixels.append(index)
                let x = index % width, y = index / width
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let neighbour = ny * width + nx
                    if ink[neighbour], label[neighbour] == 0 {
                        label[neighbour] = next
                        stack.append(neighbour)
                    }
                }
            }
            next += 1
            found.append(Component(stride: width, minX: minX, minY: minY, maxX: maxX, maxY: maxY, pixels: pixels))
        }
        return found
    }

    /// The printed dot grid, found by its regularity rather than its size.
    /// The candidates are the small roundish blobs — no bigger across than
    /// `max(6, shortSide / 80)` (15 px on a normalised page; a printed dot is
    /// 4–10), between 1:2 and 2:1, at least 30% filled — specks included,
    /// since they are mostly dots too and help find the spacing. The spacing
    /// is the median nearest-neighbour distance among them; a candidate is
    /// on the grid when two others sit at that spacing (±15%) in directions
    /// at least 60° apart, so a row of dots counts and a corner counts, and
    /// a full stop next to one dot does not. The grid is believed when at
    /// least `minimumDots` are on it and they are at least half the
    /// candidates. The neighbour search is a sweep along x, and a page with
    /// more candidates than `maximumCandidates` (noise, not a grid) is not
    /// searched at all.
    static func dotLattice(among components: [Component], width: Int, height: Int,
                           tolerance: Double = 0.15, minimumDots: Int = 20,
                           maximumCandidates: Int = 5000) -> Set<Int>? {
        let limit = max(6, min(width, height) / 80)
        var candidates: [(index: Int, x: Double, y: Double)] = []
        for (index, component) in components.enumerated() {
            let long = max(component.width, component.height), short = min(component.width, component.height)
            guard long <= limit, long <= 2 * short, component.fill >= 0.3 else { continue }
            candidates.append((index, component.centre.x, component.centre.y))
        }
        let count = candidates.count
        guard count >= minimumDots, count <= maximumCandidates else { return nil }
        candidates.sort { $0.x < $1.x }

        // Nearest neighbours, sweeping each way along x: once the x gap
        // alone is more than the nearest so far, nothing further is nearer.
        var nearest = [Double](repeating: .infinity, count: count)
        for i in 0..<count {
            for step in [1, -1] {
                var j = i + step
                while j >= 0, j < count, abs(candidates[j].x - candidates[i].x) < nearest[i] {
                    let d = hypot(candidates[j].x - candidates[i].x, candidates[j].y - candidates[i].y)
                    if d < nearest[i] { nearest[i] = d }
                    j += step
                }
            }
        }
        let spacing = nearest.sorted()[count / 2]
        guard spacing.isFinite, spacing >= 3 else { return nil }
        let near = (1 - tolerance) * spacing, far = (1 + tolerance) * spacing

        var lattice = Set<Int>()
        for i in 0..<count {
            var directions: [(dx: Double, dy: Double)] = []
            for step in [1, -1] {
                var j = i + step
                while j >= 0, j < count, abs(candidates[j].x - candidates[i].x) <= far {
                    let dx = candidates[j].x - candidates[i].x, dy = candidates[j].y - candidates[i].y
                    let d = hypot(dx, dy)
                    if d >= near, d <= far { directions.append((dx / d, dy / d)) }
                    j += step
                }
            }
            // Two neighbours at least 60° apart: the cosine between their
            // directions is at most 0.5.
            var apart = false
            for a in 0..<directions.count where !apart {
                for b in (a + 1)..<directions.count
                where directions[a].dx * directions[b].dx + directions[a].dy * directions[b].dy <= 0.5 {
                    apart = true
                    break
                }
            }
            if apart { lattice.insert(candidates[i].index) }
        }
        guard lattice.count >= minimumDots, lattice.count * 2 >= count else { return nil }
        return lattice
    }

    /// The writing's box with a little room round it, kept inside the page —
    /// the writing inside `window` only, when there is one.
    static func inkBox(of mask: Mask, within window: CGRect? = nil,
                       margin: Int = 6) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let box = mask.bounds(within: window) else { return nil }
        let x0 = max(0, box.x - margin), y0 = max(0, box.y - margin)
        let x1 = min(mask.width - 1, box.x + box.width - 1 + margin)
        let y1 = min(mask.height - 1, box.y + box.height - 1 + margin)
        return (x0, y0, x1 - x0 + 1, y1 - y0 + 1)
    }

    /// The ink as a picture with nothing behind it, cropped to the writing —
    /// or to `box`, a part of the page in its pixels.
    static func image(from mask: Mask, colour: NSColor,
                      box: (x: Int, y: Int, width: Int, height: Int)? = nil) -> NSImage? {
        guard let box = box ?? inkBox(of: mask) else { return nil }
        let x0 = box.x, y0 = box.y, width = box.width, height = box.height

        let rgb = colour.usingColorSpace(.deviceRGB) ?? .black
        let r = UInt8(clamping: Int(rgb.redComponent * 255)), g = UInt8(clamping: Int(rgb.greenComponent * 255))
        let b = UInt8(clamping: Int(rgb.blueComponent * 255))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where mask.ink[(y + y0) * mask.width + (x + x0)] {
                let offset = (y * width + x) * 4
                pixels[offset] = r; pixels[offset + 1] = g; pixels[offset + 2] = b; pixels[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return DrawingStore.image(from: cgImage)
    }
}
