import AppKit
import SwiftUI

// ANYTHING DRAWN CAN BE SELECTED AND INSERTED (Sean, 2026-10-02). A box on
// the page offers what the camera's box offers — Image, Writing, Text — and
// they arrive the way the camera's do, at the same scale and under the
// caret. What differs is the source: the camera hands over a photograph to
// be thresholded and traced, the page hands over the strokes themselves.
// So none of this goes near `NotebookCapture.capture` — tracing ink that is
// already clean would only make it worse.
//
// Everything here is pure, in the page's own points (`TabletPage.size`),
// and tested; `NoteStore.takeFromTablet` is where it meets the note.

/// Which of the box's three.
enum TabletChoice: Equatable {
    /// The part of the page inside the box, paper and all, as a picture.
    case image
    /// The strokes the box touches, as strokes on the note's drawing layer.
    case writing
    /// Those strokes read as words, into the note's text.
    case text
}

enum TabletSelection {
    /// A box in page fractions, in the page's points.
    static func pagePoints(_ box: CGRect, pageSize: CGSize) -> CGRect {
        CGRect(x: box.minX * pageSize.width, y: box.minY * pageSize.height,
               width: box.width * pageSize.width, height: box.height * pageSize.height)
    }

    /// The strokes the box TOUCHES, whole, in the page's order — the
    /// notebook's marquee rule (Sean, 2026-09-18: "if it's in the selection
    /// rectangle, it's included, the whole drawing doesn't need to be
    /// highlighted"), asked of the same geometry.
    static func touched(_ strokes: [Stroke], by box: CGRect, pageSize: CGSize) -> [Stroke] {
        let ids = Drawing(strokes: strokes).ids(touching: pagePoints(box, pageSize: pageSize), in: pageSize)
        return strokes.filter { ids.contains($0.id) }
    }

    /// The ink's own box in page points, its reach included — what the
    /// camera's Writing places by (the writing's box on its page).
    static func inkBounds(_ strokes: [Stroke], pageSize: CGSize) -> CGRect? {
        Drawing(strokes: strokes).bounds(of: Set(strokes.map(\.id)), in: pageSize)
    }

    /// The strokes re-expressed on the notebook's layer: the ink box
    /// `frame` (page points) lands centred on `center` (fractions of the
    /// note's pane, the document's coordinates) at `width` of the pane —
    /// what `NotebookCapture.placement` and `NoteStore.placedCenter` say a
    /// capture of that box gets. Every point and every width is scaled by
    /// the one factor; pressures, the tool and the colour go as they are;
    /// each stroke gets a new id (it is a new object, and inserting twice
    /// makes two), and all of them share `group`.
    static func noteStrokes(_ strokes: [Stroke], pageSize: CGSize, frame: CGRect,
                            center: CGPoint, width: Double, pane: CGSize, group: UUID?) -> [Stroke] {
        guard frame.width > 0, pane.width > 0, pane.height > 0 else { return [] }
        let scale = width * pane.width / frame.width
        let middle = CGPoint(x: center.x * pane.width, y: center.y * pane.height)
        return strokes.map { stroke in
            var placed = stroke
            placed.id = UUID()
            placed.group = group
            placed.transform = ItemTransform()
            placed.width = stroke.width * scale
            placed.points = stroke.points.map { point in
                let x = middle.x + (point.x * pageSize.width - frame.midX) * scale
                let y = middle.y + (point.y * pageSize.height - frame.midY) * scale
                return CGPoint(x: x / pane.width, y: y / pane.height)
            }
            return placed
        }
    }
}

/// The page, or part of it, as a picture — drawn by Core Graphics from the
/// same outlines the pane fills (`InkPaths`), with explicit colours: a
/// picture made through SwiftUI or AppKit's dynamic colours takes the
/// window's appearance, and in Dark Mode black ink came out white.
enum TabletRender {
    /// Pixels per page point: a whole page is 1500 × 2400 or so — sharp at
    /// the size a capture lands, and well over what Vision wants for a line
    /// of handwriting.
    static let pixelsPerPoint: CGFloat = 3
    /// Paper left round the ink when it is read, in page points, so a
    /// letter at the edge is not on the edge of the picture.
    static let readingMargin: CGFloat = 16

    /// The part of the page inside `region` (page points), its paper and
    /// everything written over it, cut at the box's edges — "the picture of
    /// a page".
    static func image(of strokes: [Stroke], region: CGRect, pageSize: CGSize, theme: PageTheme = .plain,
                      scale: CGFloat = pixelsPerPoint) -> CGImage? {
        render(region: region, scale: scale, paper: theme.paper.cgColor) { context in
            theme.print(in: context, pageSize: pageSize)
            paint(strokes, in: context, pageSize: pageSize, as: nil)
        }
    }

    /// The strokes alone, BLACK ON WHITE whatever colour they were written
    /// in and whatever the paper, round their own box with a margin — what
    /// Text reads.
    static func ink(of strokes: [Stroke], pageSize: CGSize, scale: CGFloat = pixelsPerPoint) -> CGImage? {
        guard let box = TabletSelection.inkBounds(strokes, pageSize: pageSize) else { return nil }
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        return render(region: box.insetBy(dx: -readingMargin, dy: -readingMargin), scale: scale, paper: white) { context in
            paint(strokes, in: context, pageSize: pageSize, as: black)
        }
    }

    /// Each stroke's outline, filled as the pane fills it — `colour` in
    /// place of the stroke's own, at full strength, when given. The
    /// context is y-down, in page points.
    static func paint(_ strokes: [Stroke], in context: CGContext, pageSize: CGSize, as colour: CGColor?) {
        for stroke in strokes {
            let points = CanvasItem.stroke(stroke).basePoints(in: pageSize)
            let (path, filled) = InkPaths.path(for: stroke, points: points)
            let own = (NSColor(hex: stroke.colorHex) ?? .black).cgColor
            context.addPath(path.cgPath)
            if let tool = stroke.inkTool {
                context.setFillColor(colour ?? own.copy(alpha: CGFloat(tool.opacity)) ?? own)
                context.fillPath()
            } else if filled {
                context.setFillColor(colour ?? own)
                context.fillPath()
            } else {
                // A legacy line cannot be written on the page, but a
                // painter that drops one is a page that loses it.
                context.setStrokeColor(colour ?? own)
                context.setLineWidth(stroke.width)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            }
        }
    }

    /// A bitmap of `region` (page points) at `scale` pixels a point, the
    /// paper laid first, `draw` handed a y-down context in page points.
    private static func render(region: CGRect, scale: CGFloat, paper: CGColor,
                               draw: (CGContext) -> Void) -> CGImage? {
        guard region.width > 0, region.height > 0, scale > 0 else { return nil }
        let width = Int((region.width * scale).rounded(.up))
        let height = Int((region.height * scale).rounded(.up))
        guard width >= 1, height >= 1, width <= 12_000, height <= 12_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(paper)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -region.minX, y: -region.minY)
        draw(context)
        return context.makeImage()
    }
}
