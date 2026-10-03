import AppKit
import SwiftUI

/// One block of the note, edited where it sits in the preview.
///
/// It is a real `NSTextView`, and that is the point: every button on the bar
/// goes through `EditorBridge`, and the bridge needs a text view to talk to.
/// With one here, bold, the heading ladder, bullets, quotes, indentation, the
/// text style, ⌘D and the maths menu all work on the rendered page exactly as
/// they do in the source (Sean, 2026-09-18). What it holds is the block's own
/// markdown, styled as it goes — so nothing is hidden and nothing is lost.
struct BlockEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let bridge: EditorBridge
    /// Changing this takes the keyboard.
    var focusToken: Int
    /// Where the caret lands when this editor takes the keyboard.
    var caret: Caret = .end
    var placeholder = ""
    /// HOW THE TEXT IS SET, so an editor standing in for a line of a
    /// rendered list sits on the same baseline as the words it replaced.
    /// A cell's editor has the two points of air and the three points of
    /// leading the source pane uses; an item's editor has neither,
    /// because the `Text` it is drawn over has neither (Sean, 2026-09-21:
    /// "just the text part of the list becomes editable").
    var metrics: Metrics = .cell
    /// One line only: a pasted newline becomes a space, and Return is the
    /// list's rule wherever the caret is — the rest of the words become
    /// the next item (`onSplit`), never a line break. An item of a list
    /// that gains a newline is no longer one item, and the block would be
    /// re-parsed out from under the caret mid-paste.
    var singleLine = false
    /// A PARAGRAPH'S RETURN IS A NEWLINE, AND ITS SECOND ONE LEAVES (Sean,
    /// 2026-10-03: "a single return should enter a newline, a second return
    /// should remove that newline, and move the cursor to after that cell"):
    /// at the end of the words, Return types a newline into the cell; Return
    /// again, with that newline the last thing in it, takes it back out and
    /// puts the cursor on the bar under the cell. False for a heading, which
    /// is one line and makes the next cell at its end.
    var leavesOnSecondReturn = false
    /// A list, a quote or a fenced block: Return adds a line to it rather
    /// than starting a new block.
    var keepsNewlines = false
    /// Set for a fenced code block: what is being typed is CODE, so it is
    /// coloured for its language instead of being read as markdown (Sean,
    /// 2026-09-19: "i want to be able to type code in the code block").
    var language: CodeLanguage?
    /// Return at the END of the cell, on an empty item that ends its list,
    /// or anywhere in one reminder of a checklist: what is behind the caret
    /// stays, what is in front of it is the next cell — or the next
    /// reminder. Inside a cell Return is a line break and this is not
    /// called (Sean, 2026-10-02: "return should be a newline").
    var onSplit: ((String, String) -> Void)?
    var onDeleteEmpty: (() -> Void)?
    /// Backspace at the very start of ONE REMINDER'S words: they join the
    /// reminder above, which is what every list does inside one cell. Nil
    /// for a cell, where ⌫ at the start does nothing (Sean, 2026-10-02:
    /// "backspace at beginning does nothing") — the editor holds the
    /// cell's own text, and AppKit has nothing before offset zero to take.
    var onJoinPrevious: (() -> Void)?
    var onMove: ((Move) -> Void)?

    enum Move { case up, down, out }

    /// Where the caret goes when this editor takes the keyboard.
    enum Caret: Equatable {
        case start
        case end
        /// A character offset into this editor's own text.
        case at(Int)
        /// A selection of this editor's own text — the one the markdown
        /// pane was holding when ⌘T was pressed (`PaneCaret`).
        case range(NSRange)
        /// The x a click landed on, in the editor's own coordinates — so
        /// clicking the middle of a word puts the caret in the middle of
        /// that word, the way clicking text does everywhere else.
        case atX(CGFloat)
    }

    struct Metrics: Equatable {
        var inset: NSSize
        var lineSpacing: CGFloat

        /// A cell of the note, in its own editor.
        static let cell = Metrics(inset: NSSize(width: 0, height: 2), lineSpacing: 3)
        /// One line of a rendered list, drawn over the `Text` it replaces.
        static let listItem = Metrics(inset: .zero, lineSpacing: 0)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> BlockTextView {
        let view = BlockTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.layoutManager?.delegate = context.coordinator.hiding
        // ⌘V with a picture goes on the drawing layer here too, not into the
        // block as nothing (Sean, 2026-09-18).
        view.onPasteImage = { [bridge] in bridge.pasteImage?($0) ?? false }
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = true
        view.isGrammarCheckingEnabled = false
        view.drawsBackground = false
        view.metrics = metrics
        view.singleLine = singleLine
        view.textContainerInset = metrics.inset
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.placeholder = placeholder
        view.baseFont = font
        view.isCode = language != nil
        view.string = text
        context.coordinator.language = language
        context.coordinator.restyle(view)
        return view
    }

    func updateNSView(_ view: BlockTextView, context: Context) {
        context.coordinator.parent = self
        view.placeholder = placeholder
        view.singleLine = singleLine
        if view.metrics != metrics {
            view.metrics = metrics
            view.textContainerInset = metrics.inset
            context.coordinator.restyle(view)
        }
        bridge.textView = view

        if view.baseFont != font || context.coordinator.language != language {
            view.baseFont = font
            view.isCode = language != nil
            context.coordinator.language = language
            context.coordinator.restyle(view)
        }
        // Only take the text from outside when the outside is what changed —
        // otherwise every keystroke would put the caret back at the end.
        if view.string != text, view.window?.firstResponder !== view {
            view.string = text
            context.coordinator.restyle(view)
        }

        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            let caret = caret
            DispatchQueue.main.async {
                guard let window = view.window else { return }
                window.makeFirstResponder(view)
                view.setSelectedRange(view.selection(for: caret))
            }
        }
    }

    static func dismantleNSView(_ view: BlockTextView, coordinator: Coordinator) {
        if coordinator.parent.bridge.textView === view { coordinator.parent.bridge.textView = nil }
        // Nothing may be left that could be undone INTO this view once it is
        // gone (see Coordinator.undoManager).
        coordinator.undoManager.removeAllActions()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .infinity else { return nil }
        return CGSize(width: width, height: nsView.height(fitting: width))
    }

    // MARK: -

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockEditor
        var focusToken = Int.min
        /// This editor's own undo stack. Left to itself an NSTextView puts its
        /// undo actions on the WINDOW's undo manager, and a block editor is
        /// torn down every time the block stops being edited — so ⌘Z later
        /// invoked an action whose text view was long freed, and the app
        /// died (WriteMind-2026-09-18-034439.ips: `_NSUndoStack popAndInvoke`
        /// → objc_msgSend on a dead object). A stack the editor owns dies with
        /// it, and is emptied on the way out for good measure.
        let undoManager = UndoManager()
        /// Draws `- ` as a round bullet while the block is being edited.
        /// The markers of the open cell, hidden the way the source editor
        /// hides them: the `**` and the `#` are still in the text, they
        /// just take no room, and the line the caret is on shows its own
        /// so it can be typed (the to-do list, 2026-09-19: "the rendered
        /// page's cell editor does not do this yet, so clicking a heading
        /// still shows its hashes"). `MarkerHiding` does `BulletGlyphs`'
        /// substitution in the same pass — a layout manager has one
        /// delegate slot — so it stands in for it here too.
        let hiding = MarkerHiding()
        /// The language of the code being typed, when it is code.
        var language: CodeLanguage?

        init(_ parent: BlockEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        func restyle(_ view: BlockTextView) {
            guard let storage = view.textStorage else { return }
            let selection = view.selectedRanges
            let source = view.string
            if let language, language != .plain {
                CodeColours.style(storage, language: language, font: view.baseFont,
                                  paragraph: view.paragraphStyle)
                // Code is code: there are no markdown markers in it to hide.
                hiding.setMarkers([])
                hiding.setFurniture(CellFurniture.Reading())
            } else {
                MarkdownSourceStyle.apply(to: storage, base: view.baseFont,
                                          paragraph: view.paragraphStyle)
                let runs = MarkdownSourceStyle.runs(in: source)
                let text = source as NSString
                hiding.setMarkers(MarkerHiding.hideable(runs, in: text))
                // THE MARKERS ARE FURNITURE HERE, not text to be typed.
                // This is the rendered page: the reader clicked a heading
                // to change its WORDS, or a reminder to change what it
                // says, and the `## ` and the `- [ ] ` that the source
                // pane rightly shows on the caret's line have no business
                // appearing and shunting them sideways (Sean, 2026-09-21:
                // "don't show the markdown characters for header, only
                // edit the text in a reminders list or bullet list").
                // `CellFurniture` is the whole of that rule; the kind of a
                // cell is changed with the ladder and the list buttons,
                // which is what those are for.
                hiding.setFurniture(CellFurniture.read(text, runs: runs))
            }
            view.typingAttributes = [.font: view.baseFont,
                                     .foregroundColor: NSColor.textColor,
                                     .paragraphStyle: view.paragraphStyle]
            view.selectedRanges = selection
            // The glyphs already exist, so the hiding has to invalidate them
            // by hand — the same dance the source editor does.
            if let layout = view.layoutManager {
                let whole = NSRange(location: 0, length: (source as NSString).length)
                layout.invalidateGlyphs(forCharacterRange: whole, changeInLength: 0,
                                        actualCharacterRange: nil)
                layout.invalidateLayout(forCharacterRange: whole, actualCharacterRange: nil)
            }
            view.updateHiddenMarkers(hiding)
            view.invalidateIntrinsicContentSize()
        }

        /// AND THE CARET STAYS OUT OF THE FURNITURE. Hidden characters the
        /// caret can still be put among are worse than visible ones: the
        /// key that looks like it will type at the front of the heading
        /// types between two of its hashes instead, and the line stops
        /// being a heading with nothing on screen to say why. Clicking the
        /// left edge, Home and ⌘← all land on the first character that can
        /// be seen.
        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldRange: NSRange,
                      toCharacterRange newRange: NSRange) -> NSRange {
            MarkerHiding.outside(newRange, of: hiding.furnitureRanges)
        }

        /// The caret moved: the line it left hides its markers again, the
        /// one it arrived on shows them.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? BlockTextView else { return }
            view.updateHiddenMarkers(hiding)
            view.invalidateIntrinsicContentSize()
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? BlockTextView else { return }
            parent.bridge.endOccurrenceRun()
            restyle(view)
            if parent.text != view.string { parent.text = view.string }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let view = textView as? BlockTextView else { return false }
            let text = view.string
            let caret = view.selectedRange()

            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // ⇧↩ RUNS AN EVALUATION CELL — and it arrives here, as
                // an ordinary newline with shift on the event, because
                // macOS binds `insertLineBreak:` to ⌃↩ and leaves ⇧↩
                // alone.
                if EvaluationKeys.isRunNow, parent.bridge.evaluatesHere?() == true {
                    parent.bridge.runCell?()
                    return true
                }
                return newline(in: view, text: text, caret: caret)

            case #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                if EvaluationKeys.isRunNow, parent.bridge.evaluatesHere?() == true {
                    parent.bridge.runCell?()
                    return true
                }
                view.insertText("\n", replacementRange: caret)
                return true

            case #selector(NSResponder.insertTab(_:)):
                if view.isCode {
                    view.apply(CodeTyping.tabbing(in: text, selection: caret, outdent: false))
                    return true
                }
                parent.bridge.indent()
                return true

            case #selector(NSResponder.insertBacktab(_:)):
                if view.isCode {
                    view.apply(CodeTyping.tabbing(in: text, selection: caret, outdent: true))
                    return true
                }
                parent.bridge.outdent()
                return true

            case #selector(NSResponder.deleteBackward(_:)):
                if text.isEmpty {
                    parent.onDeleteEmpty?()
                    return true
                }
                // Between the two halves of a pair, backspace takes both.
                if view.isCode, let edit = CodeTyping.backspace(in: text, selection: caret) {
                    view.apply(edit)
                    return true
                }
                // Nothing to the left at all: the thing this editor holds
                // joins the one above it, which is what a list does. Asked
                // BEFORE the outdent, because an editor that holds one
                // line of a list has no prefix of its own to outdent —
                // the `- [ ] ` is furniture outside it.
                if caret.length == 0, caret.location == 0, let join = parent.onJoinPrevious {
                    join()
                    return true
                }
                // A level of indentation, or the bullet, first — that is
                // the ordinary behaviour of the key on a list and it is
                // already right (`outdentForBackspace`).
                if parent.bridge.outdentForBackspace() { return true }
                // Otherwise, standing just behind a piece of furniture
                // takes the WHOLE piece: `## ` off a heading, `- [ ] ` off
                // a reminder. The caret cannot be inside either, so left
                // alone the key ate one space and the line quietly stopped
                // being a heading — a change nothing on screen announced.
                if caret.length == 0,
                   let piece = MarkerHiding.furnitureBehind(caret.location,
                                                            in: hiding.furnitureRanges) {
                    view.apply(CodeTyping.Edit(range: piece, replacement: "",
                                               selection: NSRange(location: piece.location, length: 0)))
                    return true
                }
                return false

            case #selector(NSResponder.cancelOperation(_:)):
                parent.onMove?(.out)
                return true

            case #selector(NSResponder.moveUp(_:)):
                guard PreviewEditing.lineRange(in: text, at: caret.location).location == 0 else { return false }
                parent.onMove?(.up)
                return true

            case #selector(NSResponder.moveDown(_:)):
                let line = PreviewEditing.lineRange(in: text, at: caret.location)
                guard NSMaxRange(line) >= (text as NSString).length else { return false }
                parent.onMove?(.down)
                return true

            default:
                return false
            }
        }

        /// Return: a line break inside the cell, the next cell at its end —
        /// unless this block is a list, in which case it is the next item,
        /// and an empty item ends the list instead.
        private func newline(in view: BlockTextView, text: String, caret: NSRange) -> Bool {
            if parent.keepsNewlines {
                let lineRange = PreviewEditing.lineRange(in: text, at: caret.location)
                let line = (text as NSString).substring(with: lineRange)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
                guard let continuation = PreviewEditing.listContinuation(for: line) else { return false }
                if continuation.isEmpty {
                    view.insertText("", replacementRange: lineRange)
                    parent.onSplit?((view.string as NSString).substring(to: view.selectedRange().location),
                                    (view.string as NSString).substring(from: view.selectedRange().location))
                } else {
                    view.insertText("\n" + continuation, replacementRange: caret)
                }
                return true
            }
            let ns = text as NSString
            // At the END of the cell the next cell is made under it; one
            // reminder of a checklist is one line, and its Return is the
            // list's rule wherever the caret is. Anywhere else RETURN IS A
            // LINE BREAK WITHIN THE CELL, never a cut through it (Sean,
            // 2026-10-02: "return should be a newline") — it used to split
            // the block at the caret and open the tail, which the source
            // pane never did, and ⌃D is the split. The newline goes in as
            // typed, so the note holds the same bytes it would from the
            // source pane: at the start of a cell, above the words.
            if parent.singleLine || (caret.length == 0 && caret.location == ns.length) {
                if parent.leavesOnSecondReturn, !parent.singleLine {
                    if text.hasSuffix("\n") {
                        // The newline the last Return put there goes, and the
                        // cursor with it: down onto the bar under the cell.
                        view.insertText("", replacementRange: NSRange(location: ns.length - 1, length: 1))
                        parent.onMove?(.down)
                    } else {
                        view.insertText("\n", replacementRange: caret)
                    }
                    return true
                }
                parent.onSplit?(ns.substring(to: caret.location), ns.substring(from: NSMaxRange(caret)))
                return true
            }
            view.insertText("\n", replacementRange: caret)
            return true
        }
    }
}

/// A text view that is exactly as tall as what is in it, with a line of grey
/// text when it is empty.
final class BlockTextView: PasteAwareTextView {
    var placeholder = ""
    var baseFont: NSFont = .systemFont(ofSize: 15)
    /// How the text is set — see `BlockEditor.Metrics`.
    var metrics: BlockEditor.Metrics = .cell
    /// One line only: a newline that arrives by paste becomes a space.
    var singleLine = false

    /// This view's own paragraph style, built from its metrics. Not the
    /// shared static any more: an editor standing in for one line of a
    /// rendered list has to sit on that line's baseline, and three points
    /// of leading is what would push it off.
    var paragraphStyle: NSParagraphStyle { Self.paragraphStyle(metrics) }

    /// What is selected for a `BlockEditor.Caret`: the range it names, or
    /// the caret where `offset(for:)` puts it.
    func selection(for caret: BlockEditor.Caret) -> NSRange {
        if case .range(let range) = caret {
            return MarkdownFormatting.clamp(range, to: (string as NSString).length)
        }
        return NSRange(location: offset(for: caret), length: 0)
    }

    /// Where the caret goes for a `BlockEditor.Caret`.
    func offset(for caret: BlockEditor.Caret) -> Int {
        let length = (string as NSString).length
        switch caret {
        case .start: return 0
        case .end: return length
        case .at(let offset): return min(max(offset, 0), length)
        case .range(let range): return min(max(range.location, 0), length)
        case .atX(let x):
            guard let layout = layoutManager, let container = textContainer, length > 0 else {
                return length
            }
            layout.ensureLayout(for: container)
            let origin = textContainerOrigin
            let point = CGPoint(x: x - origin.x, y: layout.usedRect(for: container).midY)
            let glyph = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: nil)
            var index = layout.characterIndexForGlyph(at: glyph)
            // Past the middle of the last glyph is past the last glyph.
            let box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            if point.x > box.midX { index += 1 }
            return min(max(index, 0), length)
        }
    }
    /// Set while the cell is a fenced block: brackets close themselves and
    /// Tab is indentation (Sean, 2026-09-19: "in a code cell in wysiwyg
    /// add basic features like auto {} () [] and tab inserts a 4space
    /// width tab"). Off in prose, where "(" is just a bracket.
    var isCode = false

    /// The pair goes in with the bracket, and typing the closer steps over
    /// the one that is already there. A single-line editor also flattens
    /// whatever newlines arrive with a paste.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if singleLine, let typed = string as? String, typed.contains(where: \.isNewline) {
            let flat = typed.split(whereSeparator: \.isNewline).joined(separator: " ")
            return super.insertText(flat, replacementRange: replacementRange)
        }
        guard isCode, let typed = string as? String,
              let edit = CodeTyping.typing(typed, in: self.string, selection: selectedRange())
        else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
    }

    /// One edit, applied — what the coordinator hands over for Tab and for
    /// a backspace between two halves of a pair.
    @discardableResult
    func apply(_ edit: CodeTyping.Edit) -> Bool {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return false }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        return true
    }

    static func paragraphStyle(_ metrics: BlockEditor.Metrics) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = metrics.lineSpacing
        // The same four-space grid the markdown pane uses (Sean,
        // 2026-09-19: "indentation and tab width is 4 spaces").
        style.tabStops = []
        style.defaultTabInterval = MarkdownTextView.tabWidth
        return style
    }

    /// A cell's, which is what everything but a list item uses.
    static let paragraphStyle: NSParagraphStyle = paragraphStyle(.cell)

    func height(fitting width: CGFloat) -> CGFloat {
        guard let container = textContainer, let manager = layoutManager else { return 22 }
        container.containerSize = NSSize(width: max(width, 1), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container).height
        return max(ceil(used), baseFont.pointSize * 1.3) + metrics.inset.height * 2
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height(fitting: bounds.width))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]
        (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width,
                                                   y: textContainerInset.height),
                                       withAttributes: attributes)
    }
}
