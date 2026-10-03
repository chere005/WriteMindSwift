import XCTest
@testable import WriteMind

final class MarkdownParserTests: XCTestCase {
    func testHeadingsParagraphsAndRules() {
        let blocks = MarkdownParser.blocks(from: "# Title\n\nline one\nline two\n\n---\n## Sub")
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Title"),
            .paragraph("line one line two"),
            .rule,
            .heading(level: 2, text: "Sub"),
        ])
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(MarkdownParser.blocks(from: "#hashtag"), [.paragraph("#hashtag")])
    }

    func testListsQuotesAndCode() {
        let source = "- a\n- b\n\n1. x\n2) y\n> quoted\n> more\n```swift\nlet a = 1\n\nlet b = 2\n```\nafter"
        XCTAssertEqual(MarkdownParser.blocks(from: source), [
            .bullets(["a", "b"]),
            .numbered(["x", "y"]),
            .quote("quoted more"),
            .code(language: "swift", body: "let a = 1\n\nlet b = 2"),
            .paragraph("after"),
        ])
    }

    func testAListInterruptsAParagraph() {
        XCTAssertEqual(MarkdownParser.blocks(from: "text\n- item"), [.paragraph("text"), .bullets(["item"])])
    }

    func testUnclosedFenceStillRendersAsCode() {
        XCTAssertEqual(MarkdownParser.blocks(from: "```\nx"), [.code(language: nil, body: "x")])
    }

    func testInlineUnderlineTagsBecomeAnAttributeNotText() {
        let rendered = MarkdownInline.attributed("a <u>b</u> **c**")
        XCTAssertEqual(String(rendered.characters), "a b c")
        let runs = rendered.runs.map { (String(rendered[$0.range].characters), $0.underlineStyle != nil) }
        XCTAssertTrue(runs.contains { $0 == ("b", true) }, "\(runs)")
        XCTAssertFalse(runs.contains { $0 == ("a ", true) }, "\(runs)")
    }
}

/// Code is backticks, not indentation (Sean, 2026-09-20: "code blocks are
/// only ``` and ` and `` blocks (multiline, inline, and allows ` inline)").
final class IndentationIsNotCodeTests: XCTestCase {
    func testAnIndentedLineIsStillAParagraph() {
        let blocks = MarkdownParser.blocks(from: "    four spaces in front")
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let text)? = blocks.first {
            XCTAssertEqual(text, "    four spaces in front", "and it keeps its indentation")
        } else {
            XCTFail("got \(blocks)")
        }
    }

    func testAFenceIsStillCode() {
        let blocks = MarkdownParser.blocks(from: "```swift\nlet a = 1\n```")
        guard case .code(let language, let body)? = blocks.first else { return XCTFail("got \(blocks)") }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(body, "let a = 1")
    }

    func testASpanWithABacktickInItIsWrittenWithTwo() {
        let runs = MarkdownSourceStyle.runs(in: "use ``a ` b`` here")
        let code = runs.filter { $0.kind == .code }
        XCTAssertEqual(code.count, 1)
        XCTAssertEqual(("use ``a ` b`` here" as NSString).substring(with: code[0].range), "a ` b")
    }

    func testAnOrdinarySpanStillWorks() {
        let runs = MarkdownSourceStyle.runs(in: "use `code` here")
        XCTAssertEqual(runs.filter { $0.kind == .code }.count, 1)
    }

    func testTheIndentedLinesInsideAListAreStillTheList() {
        let blocks = MarkdownParser.blocks(from: "- one\n    - nested")
        XCTAssertEqual(blocks.count, 1, "one list, got \(blocks)")
    }
}

/// A drawing cell's line (Sean, 2026-10-02: "drawing cell which is cmd + 0";
/// "visible data generally speaking"): `![](_drawings/cells/<ID>.png)` on a
/// line of its own is a cell of its own, with the exact range of its line —
/// the range is what the rendered page writes back over, so a range that
/// ran one character long would eat the newline after it.
final class DrawingLineParsingTests: XCTestCase {
    private let id = UUID(uuidString: "6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6")!
    private var line: String { "![](_drawings/cells/6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6.png)" }

    func testTheLineIsWhatACellWrites() {
        XCTAssertEqual(DrawingCells.line(id), line)
    }

    func testADrawingLineIsADrawingCellWithTheRangeOfItsLine() {
        let note = "Para A\n\n\(line)\n\nPara B"
        let blocks = MarkdownParser.positioned(from: note)
        XCTAssertEqual(blocks.map(\.block), [.paragraph("Para A"), .drawing(id: id, alt: ""), .paragraph("Para B")])
        XCTAssertEqual(blocks[1].range, NSRange(location: 8, length: (line as NSString).length),
                       "the line, and not the newline after it")
    }

    func testTheFirstLineOfANoteAndTheLastAndTheOnlyOne() {
        XCTAssertEqual(MarkdownParser.positioned(from: line).map(\.range),
                       [NSRange(location: 0, length: (line as NSString).length)])
        XCTAssertEqual(MarkdownParser.blocks(from: "\(line)\n\nAfter"), [.drawing(id: id, alt: ""), .paragraph("After")])
        XCTAssertEqual(MarkdownParser.blocks(from: "Before\n\n\(line)\n"), [.paragraph("Before"), .drawing(id: id, alt: "")])
    }

    /// The way a heading ends a paragraph — and the paragraph keeps its own
    /// range: the line does not become part of the words above it.
    func testRightUnderAParagraphItIsItsOwnCellAndTheParagraphKeepsItsRange() {
        let note = "one\ntwo\n\(line)\nthree"
        let blocks = MarkdownParser.positioned(from: note)
        XCTAssertEqual(blocks.map(\.block), [.paragraph("one two"), .drawing(id: id, alt: ""), .paragraph("three")])
        XCTAssertEqual(blocks[0].range, NSRange(location: 0, length: 7))
        XCTAssertEqual(blocks[1].range, NSRange(location: 8, length: (line as NSString).length))
        // And a list above it keeps its own lines.
        let listed = MarkdownParser.positioned(from: "- a\n- b\n\(line)")
        XCTAssertEqual(listed.map(\.block), [.bullets(["a", "b"]), .drawing(id: id, alt: "")])
        XCTAssertEqual(listed[0].range, NSRange(location: 0, length: 7))
    }

    func testInsideAFenceItIsCodeClosedOrNot() {
        XCTAssertEqual(MarkdownParser.blocks(from: "```\n\(line)\n```"), [.code(language: nil, body: line)])
        XCTAssertEqual(MarkdownParser.blocks(from: "```\n\(line)"), [.code(language: nil, body: line)])
    }

    func testAnythingElseIsAParagraphAsItAlwaysWas() {
        let uuid = id.uuidString
        for other in ["Look: \(line)",
                      "\(line) and words",
                      "![](../_drawings/cells/\(uuid).png)",
                      "![](_drawings/media/\(uuid).png)",
                      "![](.drawings/cells/\(uuid).png)",
                      "![](_drawings/cells/not-a-uuid.png)",
                      "![](_drawings/cells/\(uuid).jpg)",
                      "[](_drawings/cells/\(uuid).png)"] {
            XCTAssertEqual(MarkdownParser.blocks(from: other).count, 1, other)
            guard case .paragraph = MarkdownParser.blocks(from: other).first else {
                return XCTFail("\(other) is \(MarkdownParser.blocks(from: other))")
            }
        }
    }

    func testTheAltTextIsFreeAndAnIdInLowerCaseIsTheSameCell() {
        XCTAssertEqual(MarkdownParser.blocks(from: "![a sketch](_drawings/cells/\(id.uuidString).png)"),
                       [.drawing(id: id, alt: "a sketch")])
        XCTAssertEqual(MarkdownParser.blocks(from: "![](_drawings/cells/\(id.uuidString.lowercased()).png)"),
                       [.drawing(id: id, alt: "")])
        XCTAssertEqual(MarkdownParser.blocks(from: "   \(line)  "), [.drawing(id: id, alt: "")],
                       "spaces round the line are the line's")
    }

    /// `/link` writes `<a id="…"></a>` in front of any block that is not a
    /// heading. Read as anything but a drawing, that would turn a drawing
    /// into a paragraph the moment something linked to it.
    func testTheLinkAnchorKeepsItADrawing() throws {
        XCTAssertEqual(MarkdownParser.blocks(from: "<a id=\"wm-1234abcd\"></a>\(line)"), [.drawing(id: id, alt: "")])
        let note = "Above\n\n\(line)\n\nBelow"
        let anchored = MarkdownLinking.anchor(in: note, at: NSRange(location: 12, length: 0))
        let text = try XCTUnwrap(anchored.rewrittenText)
        XCTAssertEqual(MarkdownParser.blocks(from: text),
                       [.paragraph("Above"), .drawing(id: id, alt: ""), .paragraph("Below")])
    }

    func testTheReadersOfTheNoteFindEveryCellOnceAndNoneInAFence() {
        let other = UUID()
        let note = "\(line)\n\n```\n\(DrawingCells.line(other))\n```\n\nWords\n\n\(DrawingCells.line(other))\n\n\(line)"
        XCTAssertEqual(DrawingCells.lines(in: note).map(\.id), [id, other, id])
        XCTAssertEqual(DrawingCells.ids(in: note), [id, other])
        XCTAssertEqual(DrawingCells.lines(in: note).first?.range,
                       NSRange(location: 0, length: (line as NSString).length))
    }
}
