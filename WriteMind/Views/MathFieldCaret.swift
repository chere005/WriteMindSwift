import AppKit

/// WHERE THE CARET IS IN THE MATHS PALETTE'S EXPRESSION FIELD, read off the
/// field's editor and put back on it. SwiftUI's `TextField` of macOS 14 has
/// no selection to bind, and the shapes compose with what was typed AT THE
/// CARET (`MathPalette.choose`): `2`, then π, then `r` is `2 Pi r`. The
/// palette decides what goes where; this is only the two doors to AppKit,
/// and both ask that the editor hold EXACTLY the text the palette does, so a
/// part field's editor, or the note's text view, or a field that has not
/// caught up with a write yet, is never mistaken for the expression.
enum MathFieldCaret {
    /// The editor of the field that has the keyboard in `window`, when it
    /// holds `text`.
    private static func editor(holding text: String, in window: NSWindow?) -> NSTextView? {
        guard let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor, editor.string == text
        else { return nil }
        return editor
    }

    /// The selection in the field now, in UTF-16 units; nil when the field
    /// does not have the keyboard (or has not caught up with `text`).
    static func selection(holding text: String, in window: NSWindow?) -> NSRange? {
        editor(holding: text, in: window)?.selectedRange()
    }

    /// Puts the caret at `location`. False when the field does not hold
    /// `text` (yet): it takes a turn of the run loop after a write for the
    /// field's editor to show it.
    @discardableResult
    static func place(_ location: Int, holding text: String, in window: NSWindow?) -> Bool {
        guard let editor = editor(holding: text, in: window), location <= (text as NSString).length else { return false }
        editor.setSelectedRange(NSRange(location: location, length: 0))
        return true
    }

    /// `place`, asked again a few times while the field catches up: the
    /// palette's write reaches its editor a turn or two after the click. If
    /// it never does, the caret is left where the field puts it, at the end.
    static func settle(_ location: Int, holding text: String, attempts: Int = 4,
                       window: @escaping () -> NSWindow? = { NSApp.keyWindow }) {
        DispatchQueue.main.async {
            if place(location, holding: text, in: window()) || attempts <= 1 { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                settle(location, holding: text, attempts: attempts - 1, window: window)
            }
        }
    }
}
