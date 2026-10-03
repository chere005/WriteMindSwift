import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A DRAWING CELL AS A PANE SHOWS IT: what is drawn in it, what may be done
/// with its file, and — for a cell WriteMind can only show — its pixels.
struct DrawingCellLook: Equatable {
    /// What is drawn in it. Nil with nothing drawn yet, and for a cell that
    /// is not one this build can draw in.
    var cell: DrawingCell?
    var state: DrawingCellState = .writable
    /// The bytes on disk as a picture, for a read-only cell: a PNG that is
    /// not WriteMind's, or WriteMind's but not readable whole.
    var picture: NSImage?

    /// A cell nothing is known of yet — a line ⌘0 has just written: empty,
    /// and drawn in.
    static let empty = DrawingCellLook()

    /// How big it is shown in a column `column` points wide. A drawing by
    /// `DrawingCells.shown`; a read-only picture at its own size, shrunk
    /// whole to the column, with a line under it saying why it can only be
    /// shown; a cell with nothing to show — still downloading, or a file
    /// that could not be read at all — the one line.
    func shown(column: CGFloat) -> (scale: CGFloat, size: CGSize) {
        let line = MarkdownTextView.lineHeight
        switch state {
        case .writable:
            return DrawingCells.shown(cell, column: column)
        case .placeholder, .readOnly:
            guard case .readOnly = state, let picture, picture.size.width > 0, picture.size.height > 0 else {
                return (1, CGSize(width: max(column, 1), height: line))
            }
            let scale = column > 0 ? min(1, column / picture.size.width) : 1
            return (scale, CGSize(width: picture.size.width * scale, height: picture.size.height * scale + line))
        }
    }

    /// The one line a cell WriteMind cannot draw in shows: why.
    var why: String? {
        switch state {
        case .writable: return nil
        case .readOnly(let why): return why
        case .placeholder: return DrawingCellStore.notDownloaded
        }
    }
}

/// THE NOTE'S DRAWING CELLS, as the panes and the PDF are handed them
/// (`NoteStore.cellLooks`), and where pictures in them are kept.
struct DrawingCellsShown: Equatable {
    var looks: [UUID: DrawingCellLook] = [:]
    /// The folder whose `.drawings/media` the pictures are in.
    var media: URL?

    func look(_ id: UUID) -> DrawingCellLook { looks[id] ?? .empty }

    /// How big each cell is before a column shrinks it — what decides the
    /// height of its row, and so all a layout of the note depends on. A
    /// stroke drawn in a cell changes the cell and not this, so a layout
    /// made for this is not made again on every stroke (`PaneFrames`).
    var footprints: [UUID: CGSize] {
        looks.mapValues { $0.shown(column: .greatestFiniteMagnitude).size }
    }
}

private struct DrawingCellsKey: EnvironmentKey {
    static let defaultValue = DrawingCellsShown()
}

extension EnvironmentValues {
    /// The drawing cells the rendered page shows (`EditorPane`).
    var drawingCells: DrawingCellsShown {
        get { self[DrawingCellsKey.self] }
        set { self[DrawingCellsKey.self] = newValue }
    }
}

/// ONE PAINTER FOR A DRAWING CELL, wherever it is shown: the markdown pane's
/// layout manager, the rendered page's row, the PDF, and the PNG its file
/// is. Each is `DrawingInk` — the painter the PDF already trusts with ink,
/// text boxes, dashes, heads and traced captures — inside the cell's
/// frame, so there is no second renderer to drift from the first.
///
/// Geometry is always asked at (W, W), the cell's own size, so `InkCache`'s
/// fingerprints are the same on screen, in the file and on paper, and never
/// change as the text above the cell reflows.
enum DrawingCellPainter {
    /// What the cell is painted on.
    enum Paper: Equatable {
        /// A pane, whose paper is this colour in its appearance.
        case screen(hex: String)
        /// Paper: white, whatever the window is.
        case white

        var colour: NSColor {
            switch self {
            case .screen(let hex): return NSColor(hex: hex) ?? .textBackgroundColor
            case .white: return .white
            }
        }

        var onScreen: Bool { self != .white }

        /// The grey the one line under a read-only cell is written in: a
        /// colour given outright, because what draws it may not be inside
        /// any appearance at all (a SwiftUI `Canvas`).
        var caption: NSColor {
            let light = (colour.usingColorSpace(.sRGB)?.brightnessComponent ?? 1) > 0.5
            return NSColor(white: light ? 0.42 : 0.66, alpha: 1)
        }
    }

    /// The cell at `origin` (document points, y down) in a column `column`
    /// wide: shrunk by its scale, inside its shown size. The hairline round
    /// it is the pane's (`outline`), never the paper's.
    static func paint(_ look: DrawingCellLook, in context: CGContext, at origin: CGPoint, column: CGFloat,
                      paper: Paper, media: URL?) {
        let (scale, size) = look.shown(column: column)
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: CGRect(origin: origin, size: size))
        if case .writable = look.state {
            guard let cell = look.cell, !cell.drawing.isEmpty else { return }
            context.translateBy(x: origin.x, y: origin.y)
            context.scaleBy(x: scale, y: scale)
            DrawingInk.draw(cell.drawing, in: context, size: cell.size, media: media,
                            paper: paper.colour, onScreen: paper.onScreen)
            return
        }
        var line = CGRect(x: origin.x, y: origin.y, width: size.width, height: MarkdownTextView.lineHeight)
        if case .readOnly = look.state, let picture = look.picture,
           let image = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let box = CGRect(x: origin.x, y: origin.y,
                             width: picture.size.width * scale, height: picture.size.height * scale)
            context.saveGState()
            // A picture is drawn y up; the page is y down.
            context.translateBy(x: box.minX, y: box.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: box.size))
            context.restoreGState()
            line.origin.y = box.maxY
        }
        if let why = look.why {
            DrawingInk.write(why, in: line.insetBy(dx: 0, dy: 2), font: .systemFont(ofSize: 12),
                             colour: paper.caption, alignment: .left, in: context)
        }
    }

    /// The pane's hairline round a cell, lit with the accent while the caret
    /// is in it — the lit outline and the heavy bracket are the cursor in a
    /// cell that takes no characters.
    static func outline(_ rect: CGRect, lit: Bool, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor((lit ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).cgColor)
        let width: CGFloat = lit ? 1.5 : 0.5
        context.setLineWidth(width)
        context.stroke(rect.insetBy(dx: width / 2, dy: width / 2))
        context.restoreGState()
    }

    /// THE CELL'S FILE'S PICTURE: the cell at twice its size on white paper,
    /// light whatever the window is, as a PNG that says it is 144 dots to
    /// the inch — so anything that opens it shows it W × H points, the size
    /// it was drawn. `DrawingCellFile.embed` puts the cell's objects in it.
    static func rendition(_ cell: DrawingCell, media: URL?) -> Data? {
        let points = CGSize(width: max(cell.width, 1), height: max(cell.height, 1))
        let wide = Int((points.width * 2).rounded(.up)), high = Int((points.height * 2).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: wide, height: high, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: wide, height: high))
        // Down the page in points, the way every painter here is handed it.
        context.translateBy(x: 0, y: CGFloat(high))
        context.scaleBy(x: 2, y: -2)
        let paint = {
            DrawingInk.draw(cell.drawing, in: context, size: cell.size, media: media, paper: .white)
        }
        // Light, always: the colours in this app answer the appearance they
        // are drawn in, and a dark one would put white ink on white paper.
        if let light = NSAppearance(named: .aqua) { light.performAsCurrentDrawingAppearance(paint) } else { paint() }
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 144,
                                                        kCGImagePropertyDPIHeight: 144] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
