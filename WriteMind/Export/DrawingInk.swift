import AppKit
import SwiftUI

/// The drawing layer, painted onto paper.
///
/// **Why Core Graphics and not the SwiftUI Canvas the screen uses.** A
/// traced capture is a one-page PDF in `.drawings/media` — the whole point
/// of `InkVector` (Sean, 2026-09-19: "make it a vector graphic so it scales
/// well") — and handing one to SwiftUI's `Image` resolves it to pixels at
/// whatever scale it feels like, which would put a photograph of the
/// vectors on the page instead of the vectors. `CGContext.drawPDFPage`
/// copies the page's own drawing into the one being written, so it comes
/// out of the printer as sharp as it went in. Text goes through AppKit, so
/// a label is real selectable text in the file rather than a picture of
/// letters.
///
/// The context arrives in DOCUMENT points with y running DOWN — the
/// coordinates the objects are stored in — so `CanvasItem.matrix(in:)`,
/// `baseBounds(in:)` and the paths are the same ones the canvas uses and
/// an object lands exactly where it sits on the pane.
///
/// Every colour is put through `TextBoxStyle.readableInk` against the paper
/// first. A pen picked to read on a dark window is not a colour that exists
/// on white paper (Sean, 2026-09-19: "be mindful of text color... it should
/// always be visible against the background").
enum DrawingInk {
    /// Everything on the layer, back to front.
    static func draw(_ drawing: Drawing, in context: CGContext, size: CGSize,
                     media: URL?, paper: NSColor = .white) {
        for item in drawing.visibleItems {
            draw(item, in: context, size: size, media: media, paper: paper)
        }
    }

    /// One object, where it sits.
    static func draw(_ item: CanvasItem, in context: CGContext, size: CGSize,
                     media: URL?, paper: NSColor = .white) {
        context.saveGState()
        context.concatenate(item.matrix(in: size))
        switch item {
        case .stroke(let stroke) where stroke.inkTool != nil:
            // Ink: the filled outline, at the tool's opacity — the same
            // path the screen fills (`InkPaths`), nonzero like it.
            let (path, _) = InkPaths.path(for: stroke, points: item.basePoints(in: size))
            let opacity = CGFloat(stroke.inkTool?.opacity ?? 1)
            context.setFillColor(ink(stroke.colorHex, on: paper).withAlphaComponent(opacity).cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
        case .stroke(let stroke):
            let (path, filled) = InkPaths.path(for: stroke, points: item.basePoints(in: size))
            context.setFillColor(ink(stroke.colorHex, on: paper).cgColor)
            context.setStrokeColor(ink(stroke.colorHex, on: paper).cgColor)
            context.addPath(path.cgPath)
            if filled {
                context.fillPath()
            } else {
                context.setLineWidth(stroke.width)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            }
        case .image(let image):
            picture(image, box: item.baseBounds(in: size), in: context, media: media)
        case .shape(let shape) where shape.kind == .text:
            card(shape, box: item.baseBounds(in: size), in: context, paper: paper)
        case .shape(let shape):
            figure(shape, box: item.baseBounds(in: size), in: context, paper: paper)
        case .connector(let connector):
            let (line, heads) = InkPaths.paths(for: connector, points: item.basePoints(in: size))
            let colour = ink(connector.colorHex, on: paper)
            context.setStrokeColor(colour.cgColor)
            context.setFillColor(colour.cgColor)
            context.setLineWidth(connector.lineWidth)
            context.setLineCap(connector.line == .dotted ? .round : .butt)
            context.setLineJoin(.round)
            let dash = connector.dash()
            context.setLineDash(phase: 0, lengths: dash)
            context.addPath(line.cgPath)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            for head in heads {
                context.addPath(head.cgPath)
                context.fillPath()
            }
        }
        context.restoreGState()
    }

    // MARK: - The kinds of object

    /// A picture. A PDF is stamped in as the vectors it is; anything else
    /// is a grid of pixels and is drawn as one. A file that has gone
    /// missing leaves nothing on the paper — the dashed box the canvas
    /// shows in its place is a message to the person editing, not part of
    /// the note.
    private static func picture(_ image: ImageItem, box: CGRect, in context: CGContext, media: URL?) {
        guard let media, box.width > 0, box.height > 0 else { return }
        let url = DrawingStore.mediaURL(image.file, in: media)
        context.saveGState()
        // Inside the box, y runs UP again: that is how both a PDF page and
        // a CGImage expect to be drawn.
        context.translateBy(x: box.minX, y: box.maxY)
        context.scaleBy(x: 1, y: -1)
        let frame = CGRect(x: 0, y: 0, width: box.width, height: box.height)
        if url.pathExtension.lowercased() == "pdf",
           let provider = CGDataProvider(url: url as CFURL),
           let page = CGPDFDocument(provider)?.page(at: 1) {
            let pageBox = page.getBoxRect(.mediaBox)
            if pageBox.width > 0, pageBox.height > 0 {
                context.scaleBy(x: frame.width / pageBox.width, y: frame.height / pageBox.height)
                context.translateBy(x: -pageBox.minX, y: -pageBox.minY)
                context.drawPDFPage(page)
            }
        } else if let loaded = NSImage(contentsOf: url),
                  let cgImage = loaded.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: frame)
        }
        context.restoreGState()
    }

    /// A text box: the card, then the words inside the same padding the
    /// editor types into. An EMPTY box prints nothing but its fill — the
    /// outline and the grey word "Text" are there to be clicked, and paper
    /// cannot be clicked.
    private static func card(_ shape: ShapeItem, box: CGRect, in context: CGContext, paper: NSColor) {
        let card = Path(roundedRect: box, cornerRadius: TextBoxStyle.cornerRadius)
        var behind = paper
        if let fill = shape.fillHex, let colour = NSColor(hex: fill) {
            behind = colour
            context.setFillColor(colour.cgColor)
            context.addPath(card.cgPath)
            context.fillPath()
        }
        guard !shape.label.isEmpty else { return }
        let inset = CGRect(x: box.minX + TextBoxStyle.padding.width,
                           y: box.minY + TextBoxStyle.padding.height,
                           width: max(1, box.width - TextBoxStyle.padding.width * 2),
                           height: max(1, box.height - TextBoxStyle.padding.height * 2))
        write(shape.label, in: inset, font: TextBoxStyle.font,
              colour: ink(shape.colorHex, on: behind), alignment: .left, in: context)
    }

    /// A node or a mark: the outline, its fill, and its label in the middle.
    private static func figure(_ shape: ShapeItem, box: CGRect, in context: CGContext, paper: NSColor) {
        let path = shape.kind.path(in: box).cgPath
        var behind = paper
        if let fill = shape.fillHex, let colour = NSColor(hex: fill) {
            behind = colour
            context.setFillColor(colour.cgColor)
            context.addPath(path)
            context.fillPath()
        }
        let colour = ink(shape.colorHex, on: behind)
        context.setStrokeColor(colour.cgColor)
        context.setLineWidth(shape.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()

        guard !shape.label.isEmpty else { return }
        let room = CGRect(x: box.minX + 6, y: box.minY + 4,
                          width: max(10, box.width - 12), height: max(10, box.height - 8))
        let font = NSFont.systemFont(ofSize: 13)
        let height = min(room.height, measured(shape.label, font: font, width: room.width))
        write(shape.label,
              in: CGRect(x: room.minX, y: box.midY - height / 2, width: room.width, height: height),
              font: font, colour: colour, alignment: .center, in: context)
    }

    // MARK: - Ink and words

    /// The colour, or the nearest one that can be read on what it is being
    /// drawn on. `TextBoxStyle` owns the rule; this is where the rest of
    /// the layer asks it.
    static func ink(_ hex: String, on background: NSColor) -> NSColor {
        let readable = TextBoxStyle.readableInk(hex, on: background.hexString)
        return NSColor(hex: readable) ?? .black
    }

    /// How tall `text` is at this width.
    private static func measured(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return ceil(bounds.height)
    }

    /// Words into a y-down context, as TEXT — AppKit is told the context is
    /// flipped, so it lays the lines out downwards and the glyphs the right
    /// way up.
    private static func write(_ text: String, in rect: CGRect, font: NSFont, colour: NSColor,
                              alignment: NSTextAlignment, in context: CGContext) {
        guard !text.isEmpty, rect.width > 1, rect.height > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: colour, .paragraphStyle: paragraph])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}
