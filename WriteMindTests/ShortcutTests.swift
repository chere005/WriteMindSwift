import SwiftUI
import XCTest
@testable import WriteMind

/// The keys, and the promise that no two commands want the same one.
///
/// Sean, 2026-09-21, asking for ⌘S, ⌘P, ⌘E, ⌘T and ⌘Y: "unless there's
/// conflicts with those?" This is the answer, in a form that goes on
/// answering: ⌃⌘S really was on two commands at once, and a key equivalent
/// claimed twice goes to whichever menu comes first in the bar — so "Save
/// Project" simply could not be pressed.
final class ShortcutTests: XCTestCase {
    func testNoTwoCommandsWantTheSameKey() {
        var taken: [String: Shortcut] = [:]
        for shortcut in Shortcut.allCases {
            if let already = taken[shortcut.signature] {
                XCTFail("\(shortcut) and \(already) both want \(shortcut.signature)")
            }
            taken[shortcut.signature] = shortcut
        }
        XCTAssertEqual(taken.count, Shortcut.allCases.count)
    }

    /// The five Sean named, spelled out so that moving one is a decision
    /// somebody makes rather than a rename nobody notices.
    func testTheKeysHeAskedForAreTheKeysHeGets() {
        let wanted: [(Shortcut, Character, EventModifiers)] = [
            (.save, "s", .command),
            (.togglePen, "p", .command),
            (.export, "e", .command),
            (.toggleMode, "t", .command),
            (.toggleVideo, "y", .command),
        ]
        for (shortcut, key, modifiers) in wanted {
            XCTAssertEqual(shortcut.chord.key.character, key, "\(shortcut)")
            XCTAssertEqual(shortcut.chord.modifiers, modifiers, "\(shortcut)")
        }
    }

    /// Sean, 2026-10-02: "drawing cell which is cmd + 0" — the one number
    /// the ladder, ⌘8 and ⌘9 had left free.
    func testADrawingCellIsCommandZero() {
        XCTAssertEqual(Shortcut.drawingCell.chord.key.character, "0")
        XCTAssertEqual(Shortcut.drawingCell.chord.modifiers, .command)
        XCTAssertEqual(Shortcut.drawingCell.written, "⌘0")
    }

    /// The heading ladder is built by a `ForEach` over the levels, so the
    /// menu has to be able to ask for the case rather than making a chord.
    func testEveryRungOfTheLadderHasItsOwnNumber() {
        let keys = MarkdownFormatting.Heading.ladder.map {
            Shortcut.heading($0).chord.key.character
        }
        XCTAssertEqual(keys, ["1", "2", "3", "4", "5", "6", "7"])
        XCTAssertEqual(Set(keys).count, keys.count)
        for level in MarkdownFormatting.Heading.ladder {
            XCTAssertEqual(Shortcut.heading(level).chord.key.character, level.key,
                           "the ladder and the table disagree about \(level.name)")
            XCTAssertEqual(Shortcut.heading(level).chord.modifiers, .command)
        }
    }

    /// The one that was broken. Both still exist; they no longer collide —
    /// and the sidebar has moved off that chord altogether (⌘K).
    func testSavingTheNoteAndSavingTheProjectAreDifferentKeys() {
        XCTAssertNotEqual(Shortcut.save.signature, Shortcut.saveProject.signature)
        XCTAssertNotEqual(Shortcut.saveProject.signature, Shortcut.toggleSidebar.signature,
                          "⌃⌘S was on both of these, and the sidebar won")
        XCTAssertEqual(Shortcut.toggleSidebar.written, "⌘K")
    }

    /// THE README IS THE LIST, so it cannot go stale (Sean, 2026-09-21:
    /// "document the keystrokes in the readme"). Every chord the app
    /// binds is in its table, and the table names no chord the app does
    /// not bind — a shortcut that moves fails here until the README says
    /// so too.
    func testTheReadmeListsEveryKeyAndNoOthers() throws {
        let readme = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "README.md")
        let text = try String(contentsOf: readme, encoding: .utf8)

        // Only the tables: the paragraph under them names ⌘, ⇧ and ⌥ on
        // their own, which are modifiers held down and not chords.
        var written: Set<String> = []
        for line in text.components(separatedBy: "\n") where line.hasPrefix("|") {
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
            guard let keys = columns.dropFirst().first else { continue }
            for token in keys.split(whereSeparator: \.isWhitespace) {
                let word = String(token)
                guard word.contains(where: { "⌃⌥⇧⌘".contains($0) }), word.count > 1 else { continue }
                written.insert(word)
            }
        }
        XCTAssertFalse(written.isEmpty, "no key table found in \(readme.path)")

        let bound = Set(Shortcut.allCases.map(\.written))
        for chord in bound.subtracting(written).sorted() {
            XCTFail("\(chord) is bound but not in the README\'s table")
        }
        for chord in written.subtracting(bound).sorted() {
            XCTFail("the README\'s table names \(chord), which nothing binds")
        }
    }

    /// A key bound outside the table is a key the clash test never sees.
    func testNothingBindsAKeyOutsideTheTable() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // WriteMindTests
            .deletingLastPathComponent()      // the repo
            .appending(path: "WriteMind", directoryHint: .isDirectory)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "no sources found under \(root.path)")

        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                guard line.contains(".keyboardShortcut(") else { continue }
                // `.defaultAction` and `.cancelAction` are Return and
                // Escape in a sheet, not chords on the menu bar; and the
                // table's own call is how every one of them is bound.
                let allowed = line.contains(".defaultAction")
                    || line.contains(".cancelAction")
                    || file.lastPathComponent == "Shortcuts.swift"
                XCTAssertTrue(allowed,
                              "\(file.lastPathComponent):\(number + 1) binds a key outside Shortcut")
            }
        }
    }
}
