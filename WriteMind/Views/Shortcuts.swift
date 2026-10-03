import SwiftUI

/// EVERY KEY THIS APP BINDS, in one list.
///
/// Sean, 2026-09-21, asking for ⌘S, ⌘P, ⌘E, ⌘T and ⌘Y: "unless there's
/// conflicts with those?" The honest answer to that question is not a
/// reading of the file — it is a place where the answer can be CHECKED.
/// ⌃⌘S was on two commands at once, "Hide Notes Sidebar" and "Save
/// Project", and a key equivalent claimed twice goes to whichever menu
/// comes first in the bar: View won, and Save Project could not be pressed
/// from the keyboard at all. Nothing said so, and nothing could.
///
/// `CaseIterable` is the whole point of the shape. A new binding is a new
/// case, `ShortcutTests` walks every case there is, and a clash therefore
/// cannot be added without a test going red. The rule that keeps it true:
/// **a key is bound with `.shortcut(_:)` and never with
/// `.keyboardShortcut(_:modifiers:)`** — the second is how a chord gets
/// into the app without passing through here.
enum Shortcut: CaseIterable {
    // The note, and the window
    case newNote, closeTab, openNotesFolder, save, export
    // What is on screen
    case toggleSidebar, toggleMode, toggleVideo, togglePen
    case collapseSubsections, foldAllSections, unfoldAllSections
    // Undo, twice over: the words and the drawing
    case undo, redo, undoDrawing, redoDrawing
    // Selection
    case expandSelection, selectNextOccurrence, selectAllOccurrences
    // The heading ladder — Title down to Author, then Body Text
    case heading1, heading2, heading3, heading4, heading5, heading6, heading7
    // Marks on the words
    case bold, italic, underline, strikethrough
    case list, quote, outdent, indent
    // Cells
    case splitCell, mergeCells, duplicateCell, moveCellUp, moveCellDown
    case moveSectionUp, moveSectionDown
    // Insert
    case insertImage, codeBlock, evaluationCell, drawingCell
    // The project, and the camera
    case addFolderToProject, saveProject, refreshDevices

    var chord: KeyboardShortcut {
        switch self {
        case .newNote: return KeyboardShortcut("n", modifiers: .command)
        case .closeTab: return KeyboardShortcut("w", modifiers: .command)
        case .openNotesFolder: return KeyboardShortcut("o", modifiers: [.command, .shift])
        case .save: return KeyboardShortcut("s", modifiers: .command)
        case .export: return KeyboardShortcut("e", modifiers: .command)

        case .toggleSidebar: return KeyboardShortcut("k", modifiers: .command)
        case .toggleMode: return KeyboardShortcut("t", modifiers: .command)
        case .toggleVideo: return KeyboardShortcut("y", modifiers: .command)
        case .togglePen: return KeyboardShortcut("p", modifiers: .command)

        case .collapseSubsections: return KeyboardShortcut(";", modifiers: .command)
        case .foldAllSections:
            return KeyboardShortcut(.leftArrow, modifiers: [.command, .option, .shift])
        case .unfoldAllSections:
            return KeyboardShortcut(.rightArrow, modifiers: [.command, .option, .shift])

        case .undo: return KeyboardShortcut("z", modifiers: .command)
        case .redo: return KeyboardShortcut("z", modifiers: [.command, .shift])
        case .undoDrawing: return KeyboardShortcut("z", modifiers: [.command, .option])
        case .redoDrawing: return KeyboardShortcut("z", modifiers: [.command, .option, .shift])

        case .expandSelection: return KeyboardShortcut(".", modifiers: .command)
        case .selectNextOccurrence: return KeyboardShortcut("d", modifiers: .command)
        case .selectAllOccurrences: return KeyboardShortcut("d", modifiers: [.command, .shift])

        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6, .heading7:
            return KeyboardShortcut(KeyEquivalent(Character("\(rung)")), modifiers: .command)

        case .bold: return KeyboardShortcut("b", modifiers: .command)
        case .italic: return KeyboardShortcut("i", modifiers: .command)
        case .underline: return KeyboardShortcut("u", modifiers: .command)
        case .strikethrough: return KeyboardShortcut("x", modifiers: [.command, .shift])
        case .list: return KeyboardShortcut("l", modifiers: [.command, .shift])
        case .quote: return KeyboardShortcut("q", modifiers: [.command, .control])
        case .outdent: return KeyboardShortcut("[", modifiers: .command)
        case .indent: return KeyboardShortcut("]", modifiers: .command)

        case .splitCell: return KeyboardShortcut("d", modifiers: .control)
        case .mergeCells: return KeyboardShortcut("m", modifiers: .control)
        case .duplicateCell: return KeyboardShortcut("d", modifiers: [.control, .shift])
        case .moveCellUp: return KeyboardShortcut(.upArrow, modifiers: [.control, .shift])
        case .moveCellDown: return KeyboardShortcut(.downArrow, modifiers: [.control, .shift])
        case .moveSectionUp: return KeyboardShortcut(.upArrow, modifiers: [.command, .control])
        case .moveSectionDown: return KeyboardShortcut(.downArrow, modifiers: [.command, .control])

        case .insertImage: return KeyboardShortcut("i", modifiers: [.command, .shift])
        case .codeBlock: return KeyboardShortcut("8", modifiers: .command)
        case .evaluationCell: return KeyboardShortcut("9", modifiers: .command)
        case .drawingCell: return KeyboardShortcut("0", modifiers: .command)

        case .addFolderToProject: return KeyboardShortcut("a", modifiers: [.command, .shift])
        case .saveProject: return KeyboardShortcut("s", modifiers: [.command, .shift])
        case .refreshDevices: return KeyboardShortcut("r", modifiers: [.command, .option])
        }
    }

    /// Which rung of the heading ladder this is, 1 through 7. Nil for
    /// everything that is not one.
    var rung: Int {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        case .heading4: return 4
        case .heading5: return 5
        case .heading6: return 6
        default: return 7
        }
    }

    /// The rung a level of the ladder takes. The Format menu builds its
    /// items from `Heading.ladder`, so it asks for the case rather than
    /// making a chord of its own — a chord made outside this file is a
    /// chord the clash test never sees.
    static func heading(_ level: MarkdownFormatting.Heading) -> Shortcut {
        let ladder: [Shortcut] = [.heading1, .heading2, .heading3,
                                  .heading4, .heading5, .heading6, .heading7]
        let rung = MarkdownFormatting.Heading.ladder.firstIndex(of: level) ?? ladder.count - 1
        return ladder[min(max(rung, 0), ladder.count - 1)]
    }

    /// The chord as it is written on a menu — ⌃⌥⇧⌘ in that order, which
    /// is the order macOS itself draws them in, then the key.
    ///
    /// Not decoration: `ShortcutTests` reads the README's table back and
    /// holds it against this, so a key that moves and a key that is added
    /// both fail until the README says so too.
    var written: String {
        let modifiers = chord.modifiers
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        return out + Self.written(chord.key)
    }

    /// The key itself. AppKit keeps the arrows and the delete key in
    /// Unicode's private use area, where they have no glyph of their own.
    static func written(_ key: KeyEquivalent) -> String {
        switch key {
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .delete: return "⌫"
        case .escape: return "esc"
        case .return: return "↩"
        case .tab: return "⇥"
        case .space: return "space"
        default: return String(key.character).uppercased()
        }
    }

    /// What two of these have to differ by, and what the test compares.
    /// A `KeyboardShortcut` is not reliably `Hashable` across the versions
    /// this app builds against, so the two parts it is made of are what
    /// stand in for it.
    var signature: String {
        "\(chord.key.character)+\(chord.modifiers.rawValue)"
    }
}

extension View {
    /// The ONLY way a key is bound in this app — see `Shortcut`.
    func shortcut(_ shortcut: Shortcut) -> some View {
        keyboardShortcut(shortcut.chord)
    }
}
