import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import WriteMind

/// A drawing cell's file: a PNG any reader shows, carrying its own objects
/// in an `iTXt` chunk. The objects go in and come out WHOLE — every kind,
/// every field — or the cell is read-only; there is no "the rest of it".
final class DrawingCellFileTests: XCTestCase {
    /// A picture as ImageIO writes one, which is what a cell's rendition is.
    static func png(width: Int = 40, height: Int = 20) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: 10, height: 6))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private let strokeID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private var inkCell: DrawingCell {
        let stroke = Stroke(id: strokeID, colorHex: "#1C1C1E", width: 3,
                            points: [CGPoint(x: 0.0412, y: 0.0731), CGPoint(x: 0.0419, y: 0.0733)],
                            pressures: [0.42, 0.47], tool: .pen)
        return DrawingCell(width: 640, aspect: 0.3125, drawing: Drawing(items: [.stroke(stroke)]))
    }

    /// Every kind the layer has, with every field that has ever been added
    /// to one: what a cell has to carry without losing a thing. Made once
    /// per test, so its ids are the same every time it is asked for.
    private lazy var everything: DrawingCell = {
        let group = UUID()
        let node = ShapeItem(kind: .rectangle, center: CGPoint(x: 0.2, y: 0.1), width: 0.2, colorHex: "#2D7DD2",
                             fillHex: "#FFFFFF", label: "Start", group: group)
        let box = ShapeItem(kind: .text, center: CGPoint(x: 0.7, y: 0.12), width: 0.25, colorHex: "#000000",
                            label: "a text box\nof two lines")
        let mark = ShapeItem(kind: .check, center: CGPoint(x: 0.9, y: 0.2), width: 0.03, colorHex: "#34C759",
                             transform: ItemTransform(dx: 0.01, dy: -0.02, scale: 1.5, rotation: 0.3))
        let routed = ConnectorItem(start: CGPoint(x: 0.3, y: 0.1), end: CGPoint(x: 0.6, y: 0.12),
                                   startNode: node.id, endNode: box.id, startHead: .none, endHead: .arrow,
                                   line: .dashed, colorHex: "#000000", lineWidth: 2,
                                   bends: [CGPoint(x: 0.45, y: 0.1), CGPoint(x: 0.45, y: 0.12)],
                                   overrides: [.init(index: 1, vertical: true, value: 0.45)])
        let legacy = Stroke(colorHex: "#FF3B30", width: 2,
                            points: [CGPoint(x: 0.1, y: 0.3), CGPoint(x: 0.2, y: 0.31), CGPoint(x: 0.3, y: 0.29)],
                            group: group)
        let ink = Stroke(colorHex: "#1C1C1E", width: 4,
                         points: [CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.52, y: 0.41)],
                         pressures: [0.1, 0.9], tool: .fountain)
        let picture = ImageItem(file: "A.png", center: CGPoint(x: 0.5, y: 0.2), width: 0.3, aspect: 0.75,
                                hidden: true)
        return DrawingCell(width: 512.5, aspect: 0.45,
                           drawing: Drawing(items: [.shape(node), .shape(box), .shape(mark), .connector(routed),
                                                    .stroke(legacy), .stroke(ink), .image(picture)]))
    }()

    // MARK: - The payload

    func testThePayloadIsTheseBytes() {
        let json = "{\"aspect\":0.3125,\"items\":[{\"kind\":\"stroke\",\"stroke\":{\"colorHex\":\"#1C1C1E\","
            + "\"id\":\"11111111-2222-3333-4444-555555555555\",\"points\":[[0.0412,0.0731],[0.0419,0.0733]],"
            + "\"pressures\":[0.42,0.47],\"tool\":\"pen\","
            + "\"transform\":{\"dx\":0,\"dy\":0,\"rotation\":0,\"scale\":1},\"width\":3}}],"
            + "\"version\":1,\"width\":640}"
        XCTAssertEqual(String(decoding: DrawingCellFile.payload(inkCell), as: UTF8.self), json)
    }

    func testEveryKindComesBackAsItWent() {
        XCTAssertEqual(DrawingCellFile.cell(fromPayload: DrawingCellFile.payload(everything)), .cell(everything))
        XCTAssertEqual(DrawingCellFile.cell(fromPayload: DrawingCellFile.payload(inkCell)), .cell(inkCell))
        // A legacy stroke goes in with neither of ink's fields, and comes
        // out the line it always was.
        guard case .cell(let back) = DrawingCellFile.cell(fromPayload: DrawingCellFile.payload(everything)),
              let legacy = back.drawing.strokes.first else { return XCTFail("no cell") }
        XCTAssertNil(legacy.pressures)
        XCTAssertNil(legacy.tool)
        XCTAssertFalse(String(decoding: DrawingCellFile.payload(everything), as: UTF8.self)
                        .contains("\"pressures\":null"))
    }

    func testAnEmptyCellIsACellAndNotNothing() {
        let empty = DrawingCell.empty(width: 600)
        XCTAssertEqual(DrawingCellFile.cell(fromPayload: DrawingCellFile.payload(empty)), .cell(empty))
    }

    func testAPayloadThisBuildCannotReadWholeIsReadOnly() {
        func reading(_ json: String) -> DrawingCellFile.Reading {
            DrawingCellFile.cell(fromPayload: Data(json.utf8))
        }
        guard case .unreadable(let newer) = reading("{\"aspect\":0.5,\"items\":[],\"version\":2,\"width\":600}")
        else { return XCTFail("version 2 was read") }
        XCTAssertTrue(newer.contains("version 2"), newer)
        // One object that will not decode, beside one that will: never the
        // one that will, on its own, for the next save to write back as if
        // it were the whole drawing.
        let good = String(decoding: DrawingCellFile.payload(inkCell), as: UTF8.self)
        let bad = good.replacingOccurrences(of: "[{\"kind\":\"stroke\"",
                                            with: "[{\"kind\":\"hologram\",\"hologram\":{}},{\"kind\":\"stroke\"")
        XCTAssertNotEqual(bad, good, "the premise: an object this build has never heard of")
        guard case .unreadable = reading(bad) else { return XCTFail("one bad object let the rest through") }
        guard case .unreadable = reading("{\"aspect\":0.5,\"items\":[],\"width\":600}") else {
            return XCTFail("no version was read as this one")
        }
        guard case .unreadable = reading("{\"aspect\":0,\"items\":[],\"version\":1,\"width\":600}") else {
            return XCTFail("a cell with no height was read")
        }
        guard case .unreadable = reading("not json") else { return XCTFail("nonsense was read") }
    }

    // MARK: - The PNG

    func testTheFileIsStillAPictureEveryReaderShows() throws {
        let png = Self.png()
        let file = try XCTUnwrap(DrawingCellFile.embed(DrawingCellFile.payload(everything), in: png))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(file as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 20)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        // The chunk is just before IEND, and IEND is still the end.
        XCTAssertEqual(Array(file.suffix(8)), [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
        XCTAssertNotNil(file.range(of: Data("iTXtWriteMind\0\u{1}\0\0\0".utf8)))
    }

    func testTheFileRoundTripsByteForByte() throws {
        let png = Self.png()
        let file = try XCTUnwrap(DrawingCellFile.embed(DrawingCellFile.payload(everything), in: png))
        XCTAssertEqual(DrawingCellFile.read(file), .cell(everything))
        guard case .cell(let back) = DrawingCellFile.read(file) else { return XCTFail("not read") }
        XCTAssertEqual(DrawingCellFile.payload(back), DrawingCellFile.payload(everything))
        // Written again over its own file, it is the same file: the old
        // chunk is replaced, never stacked under a second one.
        XCTAssertEqual(DrawingCellFile.embed(DrawingCellFile.payload(back), in: file), file)
    }

    func testAPictureWithNoChunkIsAPicture() {
        XCTAssertEqual(DrawingCellFile.read(Self.png()), .picture)
        XCTAssertEqual(DrawingCellFile.read(Data("GIF89a".utf8)), .picture)
        XCTAssertNil(DrawingCellFile.embed(DrawingCellFile.payload(inkCell), in: Data("GIF89a".utf8)),
                     "a chunk goes into a PNG or nowhere")
    }

    func testDamageIsReadOnlyAndSaysSo() throws {
        let file = try XCTUnwrap(DrawingCellFile.embed(DrawingCellFile.payload(inkCell), in: Self.png()))
        let bytes = [UInt8](file)
        let chunk = try XCTUnwrap(file.range(of: Data("iTXtWriteMind".utf8))).lowerBound

        // A bit flipped in the payload: the chunk's CRC says so.
        var flipped = bytes
        flipped[bytes.count - 12 - 6] ^= 0x01
        guard case .unreadable = DrawingCellFile.read(Data(flipped)) else { return XCTFail("bad CRC was read") }

        // A stream that is not zlib, under a CRC that is right for it.
        var garbled = bytes
        let text = chunk + 4 + "WriteMind".utf8.count + 5
        garbled[text] = 0x00
        let length = Int(UInt32(bytes[chunk - 4]) << 24 | UInt32(bytes[chunk - 3]) << 16
                         | UInt32(bytes[chunk - 2]) << 8 | UInt32(bytes[chunk - 1]))
        let crc = DrawingCellFile.crc32(Array(garbled[chunk..<(chunk + 4 + length)]))
        garbled.replaceSubrange((chunk + 4 + length)..<(chunk + 8 + length),
                                with: [UInt8(crc >> 24 & 0xFF), UInt8(crc >> 16 & 0xFF),
                                       UInt8(crc >> 8 & 0xFF), UInt8(crc & 0xFF)])
        guard case .unreadable = DrawingCellFile.read(Data(garbled)) else { return XCTFail("bad zlib was read") }

        // A newer WriteMind's cell, perfectly well made.
        let newer = Data("{\"aspect\":0.5,\"items\":[],\"version\":2,\"width\":600}".utf8)
        let file2 = try XCTUnwrap(DrawingCellFile.embed(newer, in: Self.png()))
        guard case .unreadable = DrawingCellFile.read(file2) else { return XCTFail("version 2 was read") }
    }

    /// The two checksums, against the values every implementation agrees on.
    func testTheChecksumsAreTheStandardOnes() throws {
        XCTAssertEqual(DrawingCellFile.crc32(Array("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(DrawingCellFile.crc32(Array("IEND".utf8)), 0xAE42_6082)
        XCTAssertEqual(DrawingCellFile.adler32(Array("Wikipedia".utf8)), 0x11E6_0398)
        let text = Data("{\"aspect\":0.3125}".utf8)
        let stream = try XCTUnwrap(DrawingCellFile.zlib(text))
        XCTAssertEqual(Array(stream.prefix(2)), [0x78, 0x9C])
        XCTAssertEqual(DrawingCellFile.unzlib(Data(stream)), text)
        var broken = stream
        broken[broken.count - 1] ^= 0xFF
        XCTAssertNil(DrawingCellFile.unzlib(Data(broken)), "an Adler-32 that disagrees")
    }
}

/// The cell's own size: fractions of W on both axes, so it grows and shrinks
/// by its height alone and never stretches what is in it.
final class DrawingCellTests: XCTestCase {
    private let line = 22.0
    private let strokeID = UUID()

    private func cell(withInkDownTo y: Double, width: Double = 600, height: Double = 200) -> DrawingCell {
        let stroke = Stroke(id: strokeID, colorHex: "#000000", width: 2,
                            points: [CGPoint(x: 0.1, y: 0.05), CGPoint(x: 0.2, y: y / width)])
        return DrawingCell(width: width, aspect: height / width, drawing: Drawing(items: [.stroke(stroke)]))
    }

    func testAnEmptyCellIsEightLinesTall() {
        let empty = DrawingCell.empty(width: 600)
        XCTAssertEqual(empty.width, 600)
        XCTAssertEqual(empty.height, DrawingCells.emptyHeight, accuracy: 1e-9)
        XCTAssertEqual(DrawingCells.emptyHeight, Double(8 * MarkdownTextView.lineHeight), accuracy: 1e-9)
        XCTAssertTrue(empty.drawing.isEmpty)
        XCTAssertEqual(empty.size, CGSize(width: 600, height: 600), "geometry is asked at (W, W)")
    }

    func testInkNearTheBottomGetsRoomBelowItAndTheCellNeverShrinks() {
        let near = cell(withInkDownTo: 190).fitted(lineHeight: line)
        // 190 plus the stroke's half-width, then four lines.
        XCTAssertEqual(near.height, 190 + 1 + 4 * line, accuracy: 1e-6)
        XCTAssertEqual(near.width, 600, "growing moves no point and stretches nothing")
        XCTAssertEqual(near.drawing, cell(withInkDownTo: 190).drawing)
        XCTAssertEqual(cell(withInkDownTo: 100).fitted(lineHeight: line).height, 200, accuracy: 1e-9,
                       "ink well clear of the bottom changes nothing")
        let tall = cell(withInkDownTo: 20, height: 900)
        XCTAssertEqual(tall.fitted(lineHeight: line).height, 900, accuracy: 1e-9, "never shrinks")
    }

    func testTheGripStopsAtTheInkAndAtTwoLines() {
        let inked = cell(withInkDownTo: 150)
        XCTAssertEqual(inked.resized(toHeight: 400, lineHeight: line).height, 400, accuracy: 1e-9)
        XCTAssertEqual(inked.resized(toHeight: 10, lineHeight: line).height, 150 + 1 + DrawingCells.pad,
                       accuracy: 1e-6, "never under the ink and its air")
        XCTAssertEqual(DrawingCell.empty(width: 600).resized(toHeight: 0, lineHeight: line).height, 2 * line,
                       accuracy: 1e-9, "a cell with no height is a cell nothing can hold")
    }
}
