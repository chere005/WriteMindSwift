import Foundation

/// A drawing cell's file: a PNG every reader shows, CARRYING ITS OWN
/// OBJECTS — the picture and the data cannot drift apart, because they are
/// one file (Excalidraw's `.excalidraw.png` idea).
///
///     89 50 4E 47 0D 0A 1A 0A      the signature
///     IHDR … IDAT …                the picture, as ImageIO wrote it
///     iTXt "WriteMind" 00          keyword
///          01 00                   compressed, with zlib
///          00 00                   no language, no translated keyword
///          <zlib(JSON, UTF-8)>     the payload
///     IEND
///
/// The payload is `{"aspect":…,"items":[…],"version":1,"width":…}`, keys
/// sorted, and `items` is `CanvasItem`'s own Codable — points, pressures,
/// tools, groups, shapes, connectors, pictures, unconverted, so nothing is
/// lost on the way in or out.
///
/// Pure, and no new dependency: the chunk is spliced into the bytes by hand,
/// with its CRC-32, and the zlib stream is Foundation's raw deflate inside a
/// header and an Adler-32 written here.
enum DrawingCellFile {
    /// What a file turned out to be (the table of states in
    /// docs/CROSS-PLATFORM.md).
    enum Reading: Equatable {
        /// WriteMind's own, this version, every object read: drawn in, and
        /// written back.
        case cell(DrawingCell)
        /// A picture with no WriteMind data in it — shown as it is, never
        /// written over.
        case picture
        /// WriteMind's chunk, but not one this build can read whole: shown
        /// as its pixels, never written over, and the one line says why.
        case unreadable(String)
    }

    /// The `iTXt` keyword the payload goes under.
    static let keyword = "WriteMind"

    private struct Payload: Codable {
        var aspect: Double
        var items: [CanvasItem]
        var version: Int
        var width: Double
    }

    /// The payload's bytes: JSON with its keys sorted, so a cell written
    /// twice is the same bytes twice.
    static func payload(_ cell: DrawingCell) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = Payload(aspect: cell.aspect, items: cell.drawing.items,
                              version: DrawingCell.version, width: cell.width)
        // Every field is a number, a string or an array of them; there is
        // nothing in a cell the encoder can refuse.
        return (try? encoder.encode(payload)) ?? Data()
    }

    /// The payload read back WHOLE OR NOT AT ALL: a version this build does
    /// not know, or a single object that will not decode, and the cell is
    /// read-only — never "the rest of it", which the next save would write
    /// over the file as if it were the whole.
    static func cell(fromPayload data: Data) -> Reading {
        struct Header: Decodable {
            var version: Int?
            var width: Double?
            var aspect: Double?
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            return .unreadable("Its drawing data could not be read.")
        }
        guard header.version == DrawingCell.version else {
            if let version = header.version, version > DrawingCell.version {
                return .unreadable("It was drawn by a newer WriteMind (version \(version)).")
            }
            return .unreadable("Its drawing data is of no version this WriteMind knows.")
        }
        guard let width = header.width, let aspect = header.aspect,
              width.isFinite, aspect.isFinite, width > 0, aspect > 0 else {
            return .unreadable("Its drawing data has no size.")
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .unreadable("Something drawn in it could not be read.")
        }
        return .cell(DrawingCell(width: width, aspect: aspect, drawing: Drawing(items: payload.items)))
    }

    // MARK: - The PNG

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private struct Chunk {
        var type: String
        /// Where the whole chunk is in the file, length to CRC.
        var range: Range<Int>
        var data: Range<Int>
        var crc: UInt32
    }

    /// The chunks in order, up to and including IEND. Nil when the bytes
    /// are not a PNG, or one runs past the end.
    private static func chunks(_ png: [UInt8]) -> [Chunk]? {
        guard png.count >= signature.count, Array(png[0..<signature.count]) == signature else { return nil }
        var chunks: [Chunk] = []
        var at = signature.count
        while at + 12 <= png.count {
            let length = Int(bigEndian(png, at))
            let start = at + 8
            guard length >= 0, start + length + 4 <= png.count else { return nil }
            let type = String(decoding: png[(at + 4)..<start], as: UTF8.self)
            chunks.append(Chunk(type: type, range: at..<(start + length + 4), data: start..<(start + length),
                                crc: bigEndian(png, start + length)))
            if type == "IEND" { return chunks }
            at = start + length + 4
        }
        return nil
    }

    /// Whether a chunk is the one WriteMind writes: an `iTXt` whose keyword
    /// is `WriteMind`.
    private static func isOurs(_ chunk: Chunk, in png: [UInt8]) -> Bool {
        guard chunk.type == "iTXt" else { return false }
        let key = Array(keyword.utf8) + [0]
        return chunk.data.count >= key.count && Array(png[chunk.data.prefix(key.count)]) == key
    }

    /// The PNG with the payload in it, just before IEND — and with any
    /// WriteMind chunk it already carried taken out, so writing a cell
    /// again never stacks a second one. Nil when the bytes are not a PNG.
    static func embed(_ payload: Data, in png: Data) -> Data? {
        let bytes = [UInt8](png)
        guard let chunks = chunks(bytes), let end = chunks.last, end.type == "IEND" else { return nil }
        var out = signature
        for chunk in chunks.dropLast() where !isOurs(chunk, in: bytes) {
            out.append(contentsOf: bytes[chunk.range])
        }
        var text = Array(keyword.utf8) + [0, 1, 0, 0, 0]
        guard let packed = zlib(payload) else { return nil }
        text.append(contentsOf: packed)
        out.append(contentsOf: chunk("iTXt", text))
        out.append(contentsOf: bytes[end.range])
        return Data(out)
    }

    /// What a cell's file holds.
    static func read(_ png: Data) -> Reading {
        let bytes = [UInt8](png)
        guard let chunk = chunks(bytes)?.first(where: { isOurs($0, in: bytes) }) else { return .picture }
        let data = Array(bytes[chunk.data])
        guard crc32(Array("iTXt".utf8) + data) == chunk.crc else {
            return .unreadable("Its drawing data is damaged.")
        }
        // keyword \0, compression flag, method, language \0, translated \0
        var at = keyword.utf8.count + 1
        guard at + 2 <= data.count else { return .unreadable("Its drawing data is damaged.") }
        let compressed = data[at] == 1, method = data[at + 1]
        at += 2
        for _ in 0..<2 {
            guard let zero = data[at...].firstIndex(of: 0) else { return .unreadable("Its drawing data is damaged.") }
            at = zero + 1
        }
        let text = Data(data[at...])
        if !compressed { return cell(fromPayload: text) }
        guard method == 0, let payload = unzlib(text) else {
            return .unreadable("Its drawing data could not be unpacked.")
        }
        return cell(fromPayload: payload)
    }

    private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let body = Array(type.utf8) + data
        return bigEndianBytes(UInt32(data.count)) + body + bigEndianBytes(crc32(body))
    }

    // MARK: - The checksums and the zlib wrapper

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// The PNG chunk's CRC-32 (ISO 3309, the one zip and Ethernet use).
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in bytes { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    /// zlib's own checksum of the uncompressed bytes, which ends the stream.
    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return b << 16 | a
    }

    /// A zlib stream (RFC 1950): a two-byte header, Foundation's deflate —
    /// which is RAW deflate, with neither — and the Adler-32 after it.
    static func zlib(_ data: Data) -> [UInt8]? {
        guard let deflated = try? (data as NSData).compressed(using: .zlib) else { return nil }
        return [0x78, 0x9C] + [UInt8](deflated as Data) + bigEndianBytes(adler32([UInt8](data)))
    }

    /// The bytes inside a zlib stream, or nil when it is not one or its
    /// checksum disagrees with what came out.
    static func unzlib(_ stream: Data) -> Data? {
        let bytes = [UInt8](stream)
        guard bytes.count >= 6, bytes[0] & 0x0F == 8, bytes[1] & 0x20 == 0,
              (UInt16(bytes[0]) << 8 | UInt16(bytes[1])) % 31 == 0 else { return nil }
        let deflated = Data(bytes[2..<(bytes.count - 4)])
        guard let inflated = try? (deflated as NSData).decompressed(using: .zlib) as Data,
              adler32([UInt8](inflated)) == bigEndian(bytes, bytes.count - 4) else { return nil }
        return inflated
    }

    private static func bigEndian(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        bytes[at..<(at + 4)].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
}
