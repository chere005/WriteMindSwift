import AppKit

/// The toolbar's — and the Tab key's — handle on the live NSTextView. SwiftUI
/// owns the text binding; this applies an `Edit` through the text view so undo
/// and the delegate both see it.
final class EditorBridge {
    weak var textView: NSTextView?
    /// A picture on the pasteboard at ⌘V, for whichever text view has the
    /// keyboard — the source editor or a block in the preview. Returns true
    /// when it was taken, and the paste stops there.
    var pasteImage: ((NSPasteboard) -> Bool)?
    /// Opens a block for editing when there is no text view to talk to —
    /// the preview, with nothing clicked yet. Returns true when there will
    /// be one in a moment, so a button press is not lost (Sean, 2026-09-19:
    /// "allow wysiwyg editing including all the buttons on the bar").
    var ensureEditing: (() -> Bool)?
    /// Moving a whole section means nothing inside one block, so while the
    /// preview is up it does it over the whole note instead.
    var moveSectionInDocument: ((Bool) -> Void)?
    /// The same for merging two cells: on the rendered page a cell IS a
    /// block, so the seam between two of them is in no one text view.
    var mergeCellsInDocument: (() -> Void)?
    /// And for splitting one. The cut is only half the job — the bar has
    /// to end up in the seam it leaves (Sean, 2026-09-20: "when dividing
    /// a cell, the cursor should go inbetween the new cells") — and on
    /// the rendered page the armed state is the page's own, held nowhere
    /// near a text view.
    var splitCellInDocument: (() -> Void)?
    /// On the rendered page a cell is a block of the note, not a range in
    /// one text view, so the page itself applies a whole-cell edit.
    var cellRangeInDocument: (() -> NSRange?)?
    var cellEditInDocument: ((@escaping (NSRange, String) -> MarkdownFormatting.Edit?) -> Void)?

    /// ⇧↩ in an evaluation cell. Set by `EditorPane`; nil everywhere the
    /// note cannot be run from, and the text views ask
    /// `evaluatesHere` first so the key keeps its ordinary meaning in
    /// every other cell.
    var runCell: (() -> Void)?
    /// Whether the caret is in an evaluation cell right now.
    var evaluatesHere: (() -> Bool)?

    /// Putting the bar under a cell, on the RENDERED page, which keeps
    /// its armed state itself.
    var armBarInDocument: ((NSRange) -> Void)?

    /// THE CURSOR OF WHICHEVER PANE IS UP (`PaneCaret`), and the note it is
    /// a cursor in. Each pane installs its own reader as it comes up, over
    /// the last pane's; neither takes its away when it goes, because on a
    /// switch the pane going can be taken down after the one coming up has
    /// installed its own, and clearing it then would carry nothing the next
    /// time. The markdown pane's holds its text view weakly.
    var paneCaret: (() -> Carried)?

    /// What a switch carried from the pane that went to the one that
    /// came up.
    struct Carried {
        /// Nil when the pane that went had no cursor at all.
        var caret: PaneCaret?
        var text: String
    }

    /// Held from the switch until the pane that comes up takes it.
    private(set) var carried: Carried?

    /// ⌘T, on the way out of a pane: read before it goes, because the
    /// pane coming up can be built before the one going is taken down.
    func carryCaret() {
        carried = paneCaret?()
    }

    /// The pane that came up takes what was carried — once, and only for
    /// the note it was read in: offsets into another note, or into this
    /// one after it changed, would put the caret somewhere nobody chose.
    /// Nil when there was no switch (a launch, another note).
    func takeCarried(for text: String) -> Carried? {
        defer { carried = nil }
        guard let carried, carried.text == text else { return nil }
        return carried
    }

    /// THE CURSOR A NOTEBOOK LEAVES YOU WITH when a cell has finished:
    /// the horizontal bar under its output, ready for the next thing
    /// (Sean, 2026-09-21: "after evaluating a cell, the text cursor
    /// should become a horizontal bar after the output").
    ///
    /// This one DOES take the caret, unlike every other write an
    /// evaluation makes — it is the second half of the ⇧↩ that started
    /// the run, not an interruption of somebody else's typing.
    func armBar(after cell: NSRange, in text: String) {
        if let armBarInDocument { armBarInDocument(cell); return }
        // A CELL OPEN ON THE RENDERED PAGE IS A TEXT VIEW TOO, and this
        // is not the pane it belongs to: `BlockTextView` is a
        // `PasteAwareTextView`, so without this the bar would be armed
        // inside one rendered block — blanking the caret of whatever
        // somebody was typing in, and opening a cell inside that block
        // at the next character.
        guard let tv = textView as? PasteAwareTextView, !(tv is BlockTextView) else { return }
        let ns = tv.string as NSString
        let offset = min(EvalCells.seam(after: cell, in: text), ns.length)
        tv.window?.makeFirstResponder(tv)
        // THE CARET GOES WHERE A CLICK WOULD PUT IT: on the blank line
        // under the answer, which is what `CellSeams.arm` reads to arm
        // the bar — one writer, through
        // `textViewDidChangeSelection`, exactly as every other bar in
        // this pane is armed. Parking it at the START of the cell below
        // armed the same seam and then left every other reader of "the
        // caret is in that cell" answering for the wrong one:
        // `updateHiddenMarkers` is asked BEFORE the arm is set, so a
        // heading under the answer showed its `## ` the moment a cell
        // finished running.
        tv.setSelectedRange(NSRange(location: EvalCells.caret(under: cell, in: text), length: 0))
        // And said out loud for the one place a blank line cannot speak
        // for: an answer at the very end of the note has no separator
        // under it, so there is no caret position `arm` would take.
        if tv.armedSeam != offset { tv.armedSeam = offset }
        tv.scrollRangeToVisible(NSRange(location: offset, length: 0))
    }

    /// WRITING INTO THE NOTE FROM OUTSIDE THE CARET — the one thing an
    /// evaluation does that nothing else here does. The rendered page
    /// installs this; the source pane has none and goes through its text
    /// view, which is the only path in the app that registers undo.
    var writeInDocument: ((MarkdownFormatting.Edit) -> Void)?

    /// An edit nobody typed. It must not take the keyboard and must not
    /// move the caret: the answer to a cell arrives while somebody is
    /// still typing in another one.
    func write(_ edit: MarkdownFormatting.Edit) {
        if let writeInDocument { writeInDocument(edit); return }
        apply(edit, stealingFocus: false)
    }

    /// The insertion bar between two cells, on the RENDERED page, where
    /// there is no text view to read it off. Takes the kind the command
    /// names, if it names one, and OPENS THE CELL THERE. Returns true when
    /// that was the whole of the command and there is nothing left to run.
    /// The markdown pane needs no closure: its bar lives on the very text
    /// view this bridge is holding.
    var armedBar: ((CellTypes.Kind?) -> Bool)?
    /// Whether that bar is up, asked and nothing more. A command that acts
    /// ON a cell — delete it, duplicate it, split it — is not a command
    /// that MAKES one, so it needs to know without making anything.
    var barIsUp: (() -> Bool)?

    /// A command while the bar IS the cursor: THE CELL IS MADE THERE.
    ///
    /// Sean, 2026-09-21: "when in the horizontal input cursor mode, if i
    /// click on something like a style, or a bullet list, or a quoted
    /// section, etc.. it should create a cell at the position of the bar
    /// ready for that type of input." So every command works at a bar,
    /// and works by opening the cell the bar stands for:
    ///
    /// - one that NAMES A KIND — the heading ladder, the three lists, the
    ///   quote, the fenced block — is the whole of the job: the cell opens
    ///   with that marker already in it and the caret where the words go;
    /// - anything else — bold, the text style, maths — opens a PLAIN cell
    ///   and then runs in it, exactly as it would have run in a cell that
    ///   was already open.
    ///
    /// It used to record the kind and wait for a character, which the + on
    /// the bar still does (Sean, 2026-09-20: "the list of style types that
    /// the NEXT INPUT will create a cell the type of") — that is the +'s
    /// job and it keeps it. A button pressed is not a kind chosen from a
    /// list: nothing happened on screen, and pressing Bullet List at a bar
    /// looked broken. Anything with no kind at all did nothing whatsoever.
    ///
    /// What it must never go back to is running in whatever cell the caret
    /// is parked against — the one BELOW the bar in the source pane, and
    /// on the rendered page the note's very FIRST cell, which
    /// `ensureEditing` opened to have somewhere to put it (2026-09-20, two
    /// reviewers). The bar is in no cell; that is why it makes one.
    ///
    /// Returns true when the command is FINISHED, false when the caller
    /// still has to run it — in the cell that has just opened.
    ///
    /// A DRAWING CELL STANDS IN FOR THE BAR UNDER IT: it takes no
    /// characters, so a command with the caret in one — a kind, or
    /// something to write — makes its cell after the drawing, and the
    /// drawing's line is never touched (a `# ` or a fence written onto it
    /// would break it). Here and only here: `isAtArmedBar` is not asked
    /// it, because a command that acts ON a cell — delete it, duplicate
    /// it, move it — acts on the drawing cell as a cell.
    @discardableResult
    private func atArmedBar(_ kind: CellTypes.Kind?) -> Bool {
        if let line = drawingCellAtCursor { armBar(under: line) }
        if let tv = textView as? PasteAwareTextView, tv.armedSeam != nil {
            tv.openArmedSeam(as: kind ?? .text)
            return kind != nil
        }
        return armedBar?(kind) ?? false
    }

    /// The drawing cell the cursor is in, by its line: the rendered page's
    /// `.drawing` cursor, or the markdown pane's caret on a drawing line.
    private var drawingCellAtCursor: NSRange? {
        if let drawingCursorInDocument { return drawingCursorInDocument() }
        guard let tv = textView as? PasteAwareTextView, !(tv is BlockTextView), tv.armedSeam == nil else { return nil }
        return tv.drawingCellAtCaret
    }

    /// The bar under a drawing cell, armed, in whichever pane is up.
    private func armBar(under line: NSRange) {
        if let armBarInDocument { armBarInDocument(line); return }
        guard let tv = textView as? PasteAwareTextView else { return }
        tv.armedSeam = DrawingCells.seamAfter(line, in: tv.string)
    }

    /// The drawing cell the RENDERED page's cursor is in. Nil with no such
    /// page up — the markdown pane's caret is read off its text view.
    var drawingCursorInDocument: (() -> NSRange?)?
    /// The caret into a drawing cell on the rendered page, which keeps its
    /// own cursor.
    var focusDrawingCellInDocument: ((UUID) -> Void)?

    /// THE CARET INTO A DRAWING CELL — a click on its paper that drew
    /// nothing (`DrawingCanvas.onCellTap`). In the markdown pane, at the end
    /// of its line, with the keyboard: what a click on a line's end does.
    func focusDrawingCell(_ id: UUID) {
        if let focusDrawingCellInDocument { focusDrawingCellInDocument(id); return }
        guard let tv = textView as? PasteAwareTextView, !(tv is BlockTextView),
              let line = DrawingCells.lines(in: tv.string).first(where: { $0.id == id })?.range else { return }
        tv.armedSeam = nil
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: NSMaxRange(line), length: 0))
    }

    /// A drawing cell DUPLICATED: the copy's new id and the original's, for
    /// the store to copy the file by (`NoteStore.copyCells`) — two cells
    /// never share a drawing unless a line was pasted by hand.
    var onFork: (([(old: UUID, new: UUID)]) -> Void)?

    /// Is the bar the cursor right now — asked without touching anything.
    private var isAtArmedBar: Bool {
        if let tv = textView as? PasteAwareTextView, tv.armedSeam != nil { return true }
        return barIsUp?() ?? false
    }

    /// Do it now if there is somewhere to do it, otherwise open a block and
    /// do it as soon as there is. SwiftUI builds the text view a turn or two
    /// after the block opens, so this waits — briefly, and never forever.
    /// `opensACell` is what tells the two kinds of command apart at a bar.
    /// One WRITES something — bold, a style, maths — and a bar is a
    /// perfectly good place to write it, so a cell is opened there and the
    /// command runs in it. The other acts ON a cell — delete it, duplicate
    /// it, move it, split it — and at a bar there is no such cell; making
    /// an empty one to delete is churn in the note and a step on the undo
    /// stack for a gesture that did nothing.
    func perform(opensACell: Bool = true, attempts: Int = 8, _ action: @escaping () -> Void) {
        // At a bar, a cell is opened first and then this runs in it. The
        // commands that name a KIND never reach here: they are finished by
        // the opening itself.
        if opensACell {
            if atArmedBar(nil) { return }
        } else if isAtArmedBar {
            return
        }
        if textView != nil { action(); return }
        guard attempts > 0, ensureEditing?() == true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.perform(opensACell: opensACell, attempts: attempts - 1, action)
        }
    }

    /// The caret's line, in the text view's coordinates — the document's,
    /// for the drawing layer: a pasted or captured picture goes just under
    /// it, flush with the text (Sean, 2026-09-18). Nil without a text view.
    func caretLineFrame() -> CGRect? {
        guard let tv = textView, let layout = tv.layoutManager, let container = tv.textContainer else { return nil }
        layout.ensureLayout(for: container)
        let origin = tv.textContainerOrigin
        let padding = container.lineFragmentPadding
        let length = (tv.string as NSString).length
        let caret = min(tv.selectedRange().location, length)
        var line: CGRect
        if length == 0 || (caret == length && tv.string.hasSuffix("\n")) {
            // The empty line after the last newline, or an empty document.
            line = layout.extraLineFragmentRect
            if line.isEmpty {
                let height = layout.defaultLineHeight(for: tv.font ?? NSFont.systemFont(ofSize: 15))
                line = CGRect(x: 0, y: layout.usedRect(for: container).maxY, width: container.size.width, height: height)
            }
        } else {
            let glyph = layout.glyphIndexForCharacter(at: max(0, min(caret, length - 1)))
            line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        return CGRect(x: line.minX + origin.x + padding, y: line.minY + origin.y,
                      width: max(0, line.width - 2 * padding), height: line.height)
    }

    /// Put `text` into the note as lines of its own at the first line that
    /// starts at or below `y` (the document's coordinates — under a picture),
    /// or at the very end when nothing does. The caret ends up after it.
    func insert(_ text: String, belowDocumentY y: CGFloat) {
        guard let tv = textView, let layout = tv.layoutManager, let container = tv.textContainer else { return }
        layout.ensureLayout(for: container)
        let ns = tv.string as NSString
        var index = ns.length
        let point = CGPoint(x: container.lineFragmentPadding + 1, y: y - tv.textContainerOrigin.y)
        if ns.length > 0, point.y < layout.usedRect(for: container).maxY {
            let glyph = layout.glyphIndex(for: point, in: container)
            let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            var char = min(layout.characterIndexForGlyph(at: glyph), ns.length)
            char = ns.lineRange(for: NSRange(location: char, length: 0)).location
            // The nearest line may be the one ABOVE the picture, ending
            // before the point; the text goes on the line after that one.
            if line.maxY <= point.y + 0.5 {
                char = NSMaxRange(ns.lineRange(for: NSRange(location: char, length: 0)))
            }
            index = min(char, ns.length)
        }
        var block = text.hasSuffix("\n") ? text : text + "\n"
        if index == ns.length, ns.length > 0, ns.character(at: ns.length - 1) != 10 { block = "\n" + block }
        let range = NSRange(location: index, length: 0)
        guard tv.shouldChangeText(in: range, replacementString: block) else { return }
        tv.insertText(block, replacementRange: range)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: index + (block as NSString).length, length: 0))
    }

    /// Return at the end of a list item carries the list on with the next
    /// marker; on an EMPTY item it ends the list instead, taking the marker
    /// away. False when the caret is not at the end of a list item, so the
    /// newline goes in as usual (Sean, 2026-09-18: "don't add another bullet
    /// on return").
    @discardableResult
    func continueList() -> Bool {
        guard let tv = textView else { return false }
        let ns = tv.string as NSString
        let selection = tv.selectedRange()
        guard selection.length == 0 else { return false }
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        guard let next = PreviewEditing.listContinuation(for: line),
              selection.location == lineRange.location + (line as NSString).length
        else { return false }
        if next.isEmpty {
            apply(MarkdownFormatting.Edit(range: NSRange(location: lineRange.location, length: (line as NSString).length),
                                          replacement: "",
                                          selection: NSRange(location: lineRange.location, length: 0)))
        } else {
            apply(MarkdownFormatting.Edit(range: selection, replacement: "\n" + next,
                                          selection: NSRange(location: selection.location + 1 + (next as NSString).length,
                                                             length: 0)))
        }
        return true
    }

    /// ⌘D's run: what it last selected, and whether it is matching whole words.
    private var lastSelection: [NSRange]?
    private var wholeWordRun = false

    /// Called when the text changes: the ranges the run remembers are about a
    /// document that no longer exists.
    func endOccurrenceRun() {
        lastSelection = nil
        wholeWordRun = false
    }

    /// Where the caret or selection is right now — nil when there is no editor.
    var selection: NSRange? { textView?.selectedRange() }

    func focus() { textView?.window?.makeFirstResponder(textView) }

    func select(_ range: NSRange) {
        guard let tv = textView else { return }
        tv.setSelectedRange(MarkdownFormatting.clamp(range, to: (tv.string as NSString).length))
        tv.scrollRangeToVisible(tv.selectedRange())
    }

    func bold() { wrap(open: MarkdownFormatting.bold) }
    func italic() { wrap(open: MarkdownFormatting.italic) }
    func underline() { wrap(open: MarkdownFormatting.underlineOpen, close: MarkdownFormatting.underlineClose) }
    func strikethrough() { wrap(open: MarkdownFormatting.strike) }

    /// The caret's section — heading and everything under it — above the
    /// sibling before it, or below the one after (Sean, 2026-09-19). In the
    /// preview a block is only part of a section, so the note does it.
    func moveSection(up: Bool) {
        if let moveSectionInDocument { moveSectionInDocument(up); return }
        guard let tv = textView,
              let edit = NotebookOutline.moveSection(text: tv.string, selection: tv.selectedRange(), up: up)
        else { return }
        apply(edit)
    }

    /// The key of the notebook section the caret is in — what the fold
    /// commands act on. Nil in the preview, and before the first heading.
    func caretSection() -> String? {
        guard let tv = textView else { return nil }
        let sections = NotebookOutline.sections(in: tv.string)
        return NotebookOutline.section(containing: tv.selectedRange().location, in: sections)?.key
    }

    /// Cut the cell the caret is in at the caret (Sean, 2026-09-19:
    /// "cmd+d and cmd+m to split and merge cells"). The caret is left on
    /// the line between the two halves, and in this pane that is all it
    /// takes: arming follows the caret, so the bar appears there by
    /// itself and there is still one writer of the armed state.
    func splitCell() {
        if let splitCellInDocument { splitCellInDocument(); return }
        maybe(NotebookCells.split)
    }

    /// Join the caret's cell to the one after it — the whole note's job on
    /// the rendered side, where the seam is outside every block.
    func mergeCells() {
        if let mergeCellsInDocument { mergeCellsInDocument(); return }
        maybe(NotebookCells.merge)
    }

    /// The caret's own cell, as a range in the note.
    func caretCell() -> NSRange? {
        if let cellRangeInDocument { return cellRangeInDocument() }
        guard let tv = textView else { return nil }
        return NotebookCells.block(containing: tv.selectedRange().location, in: tv.string)?.range
    }

    /// One step out: word, cell, section, note.
    func expandSelection() {
        perform(opensACell: false) { [weak self] in
            guard let self, let tv = textView,
                  let wider = NotebookCells.expand(tv.selectedRange(), in: tv.string) else { return }
            tv.setSelectedRange(wider)
            tv.scrollRangeToVisible(wider)
        }
    }

    /// ⌫ OVER CELLS THAT ARE HELD — their brackets lit, not a run of
    /// characters inside one. Returns false when the selection is not
    /// that, so the key stays an ordinary backspace.
    ///
    /// Sean, 2026-09-21: "backspace is enough to delete the selected cell
    /// so no need for ^+backspace". The rendered page has answered the
    /// bare key since it had cells (`MarkdownPreview.cellKey`); this is
    /// the source pane catching up, and it is what makes taking ⌃⌫ away
    /// a simplification rather than a loss. `CellSelection.picked` is the
    /// same reading every other whole-cell command uses, so ⌫ takes
    /// exactly the cells the lit brackets say it will.
    @discardableResult
    func deleteHeldCells() -> Bool {
        guard let tv = textView else { return false }
        let cells = MarkdownParser.positioned(from: tv.string).map(\.range)
        let picked = CellSelection.picked(cells: cells, selection: tv.selectedRanges.map(\.rangeValue))
        guard !picked.isEmpty else { return false }
        apply(CellCommands.edits(over: picked, in: tv.string) { CellCommands.delete($0, in: $1) })
        return true
    }

    /// Take the whole cell away and close the stack behind it.
    func deleteCell() {
        cellEdit { CellCommands.delete($0, in: $1) }
    }

    /// The same cell again, under it. A drawing cell's copy is a drawing of
    /// its own: a new id, and a copy of the file (`onFork`), so drawing in
    /// one never draws in the other.
    func duplicateCell() {
        cellEdit { [weak self] cell, text in
            let edit = CellCommands.duplicate(cell, in: text)
            let forked = DrawingCells.forked(edit.replacement)
            guard !forked.ids.isEmpty else { return edit }
            self?.onFork?(forked.ids)
            // An id is the same length whatever it is, so the selection
            // the copy lands with still means what it did.
            return MarkdownFormatting.Edit(range: edit.range, replacement: forked.markdown, selection: edit.selection)
        }
    }

    /// Swap it with the cell above or below — what dragging its bracket
    /// does, and what the menu does without the mouse.
    func moveCell(up: Bool) {
        cellEdit { CellCommands.move($0, up: up, in: $1) }
    }

    /// The cells a whole-cell command acts on: every one whose bracket is
    /// lit, and the caret's own when none is.
    ///
    /// The same rule the gutter draws by (`CellSelection.covers`), so ⌃⌫
    /// takes exactly the cells the eye says it will — and a selection that
    /// is a run of words inside one cell still means that cell, the way it
    /// always has.
    func selectedCells() -> [NSRange] {
        guard let tv = textView else { return [] }
        let cells = MarkdownParser.positioned(from: tv.string).map(\.range)
        let picked = CellSelection.picked(cells: cells, selection: tv.selectedRanges.map(\.rangeValue))
        if !picked.isEmpty { return picked }
        return NotebookCells.block(containing: tv.selectedRange().location, in: tv.string)
            .map { [$0.range] } ?? []
    }

    /// One edit per selected cell, in whichever pane is up.
    private func cellEdit(_ make: @escaping (NSRange, String) -> MarkdownFormatting.Edit?) {
        if let cellEditInDocument { cellEditInDocument(make); return }
        perform(opensACell: false) { [weak self] in
            guard let self, let tv = textView else { return }
            apply(CellCommands.edits(over: selectedCells(), in: tv.string, make: make))
        }
    }

    func list(_ style: MarkdownFormatting.ListStyle) {
        if atArmedBar(.list(style)) { return }
        lines { MarkdownFormatting.toggleList(text: $0, selection: $1, style: style) }
    }

    func heading(_ level: MarkdownFormatting.Heading) {
        if atArmedBar(CellTypes.Kind(level)) { return }
        perform { [weak self] in self?.applyHeading(level) }
    }

    private func applyHeading(_ level: MarkdownFormatting.Heading) {
        guard let tv = textView else { return }
        apply(MarkdownFormatting.setHeading(text: tv.string, selection: tv.selectedRange(), level: level))
    }

    func bullets() {
        if atArmedBar(.list(.dots)) { return }
        lines(MarkdownFormatting.toggleBullets)
    }

    /// ⌘9 AT A BAR MAKES THE CELL THERE, ready to be typed into (Sean,
    /// 2026-09-22: "make sure if the input cursor is horizontal, hitting
    /// cmd+9 puts a new evaluation cell at that position"). Returns true
    /// when that was the whole of the command.
    ///
    /// It is the same rule every other command that NAMES A KIND follows
    /// — the list, the ladder, the quote, the fenced block — and ⌘9 was
    /// the one that did not: it asked for `caretCell()`, and the caret at
    /// a bar is parked against the cell BELOW it, so the key turned that
    /// cell into an evaluation cell instead of making one where the bar
    /// was.
    @discardableResult
    func evaluationCellAtBar(_ evaluator: Evaluator) -> Bool {
        atArmedBar(.evaluation(evaluator))
    }

    /// ⌘0 on the RENDERED page, which decides where its cell goes itself:
    /// under the caret of the cell that is open, or with nothing open in
    /// the middle of what is on screen.
    var drawingCellInDocument: (() -> Void)?

    /// ⌘0 — A DRAWING CELL HERE (Sean, 2026-10-02: "drawing cell which is
    /// cmd + 0"). At a bar it is made there, as every kind is; in a cell it
    /// goes under the caret's own line (`DrawingCells.landing`). One text
    /// edit, so ⌘Z takes it out, and the mode is left alone: the caret is
    /// at the end of the new line.
    ///
    /// Never `caretCell()`: on the rendered page that falls back to the
    /// note's first cell, and a drawing asked for at the bottom of the
    /// screen would appear at the top of the note.
    func drawingCell() {
        if atArmedBar(.drawing) { return }
        if let drawingCellInDocument { drawingCellInDocument(); return }
        guard let tv = textView as? PasteAwareTextView, !(tv is BlockTextView) else { return }
        let at = DrawingCells.landing(caret: NSMaxRange(tv.selectedRange()), in: tv.string)
        MarkdownTextView.openSeam(at: at, as: .drawing, in: tv)
    }

    /// The language goes with the fence the Insert menu writes, and not
    /// with a bar: the + offers one Code Block and so does ⌘8 at a bar.
    func codeBlock(language: String = "") {
        if atArmedBar(.code) { return }
        lines { MarkdownFormatting.codeBlock(text: $0, selection: $1, language: language) }
    }

    func quote() {
        if atArmedBar(.quote) { return }
        lines(MarkdownFormatting.toggleQuote)
    }
    /// Nothing in a drawing cell: it has no lines of words to move in or
    /// out, and standing in for the bar under it would open an empty cell
    /// just to indent it.
    func indent() {
        guard drawingCellAtCursor == nil else { return }
        lines(MarkdownFormatting.indent)
    }

    func outdent() {
        guard drawingCellAtCursor == nil else { return }
        lines(MarkdownFormatting.outdent)
    }

    /// Maths, kept as Wolfram Language whichever way it goes in.
    func insertMath(_ wl: String, display: Bool) {
        perform { [weak self] in self?.applyMath(wl, display: display) }
    }

    private func applyMath(_ wl: String, display: Bool) {
        guard let tv = textView else { return }
        let canonical = WLPrinter.canonical(wl.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !canonical.isEmpty else { return }
        apply(MarkdownFormatting.insertMath(text: tv.string, selection: tv.selectedRange(),
                                            wl: canonical, display: display))
    }

    /// Through `perform`, like every other command on the bar: with
    /// nothing open it opens a cell — at the insertion bar when one is up,
    /// and that is what "ready for that type of input" means for a style
    /// that is not a kind of cell (Sean, 2026-09-21).
    func applySpan(_ style: MarkdownFormatting.SpanStyle) {
        perform { [weak self] in
            guard let self, let tv = textView else { return }
            apply(MarkdownFormatting.applySpan(text: tv.string, selection: tv.selectedRange(),
                                               style: style))
        }
    }

    func removeSpan() {
        perform { [weak self] in
            guard let self, let tv = textView else { return }
            apply(MarkdownFormatting.removeSpan(text: tv.string, selection: tv.selectedRange()))
        }
    }

    /// Sublime Text's ⌘D: the word under the caret first, then one more
    /// occurrence of it per press, each added to the selection — AppKit
    /// carries several selected ranges, and typing then edits all of them.
    ///
    /// The word-bounded flag is remembered between presses, and DROPPED as
    /// soon as the selection stops being the one this made — a click, an
    /// arrow key or an edit starts the run over rather than searching for
    /// whatever the last run happened to be looking for.
    func selectNextOccurrence() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        let ranges = tv.selectedRanges.map(\.rangeValue)
        let continuing = lastSelection.map { previous in
            previous.count == ranges.count && zip(previous, ranges).allSatisfy(NSEqualRanges)
        } ?? false
        if !continuing { wholeWordRun = false }

        guard let step = MarkdownFormatting.selectNextOccurrence(
            in: tv.string, ranges: ranges, wholeWord: wholeWordRun) else { return }
        wholeWordRun = step.wholeWord
        select(step.ranges, in: tv, showing: step.reveal)
    }

    /// Sublime's "Select All Occurrences" — every match of the selection.
    func selectAllOccurrences() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        let ns = tv.string as NSString
        let ranges = MarkdownFormatting.normalise(tv.selectedRanges.map(\.rangeValue), in: ns)
        var term = ranges.last(where: { $0.length > 0 }).map { ns.substring(with: $0) }
        var wholeWord = wholeWordRun
        if term == nil, let caret = ranges.last,
           let word = MarkdownFormatting.wordRange(in: tv.string, at: caret.location) {
            term = ns.substring(with: word)
            wholeWord = true
        }
        guard let term, !term.isEmpty else { return }
        let all = MarkdownFormatting.allOccurrences(in: tv.string, of: term, wholeWord: wholeWord)
        guard let first = all.first else { return }
        wholeWordRun = wholeWord
        select(all, in: tv, showing: first)
    }

    /// AppKit wants them ordered, de-duplicated and non-overlapping, or it
    /// drops the lot and leaves a single caret behind.
    private func select(_ ranges: [NSRange], in tv: NSTextView, showing: NSRange) {
        let ordered = MarkdownFormatting.normalise(ranges, in: tv.string as NSString)
        guard !ordered.isEmpty else { return }
        tv.selectedRanges = ordered.map { NSValue(range: $0) }
        tv.scrollRangeToVisible(showing)
        lastSelection = ordered
    }

    /// Backspace inside a line's prefix. Returns false when nothing was done,
    /// so the text view can fall through to an ordinary delete.
    @discardableResult
    func outdentForBackspace() -> Bool {
        guard let tv = textView,
              let edit = MarkdownFormatting.outdentForBackspace(text: tv.string, selection: tv.selectedRange())
        else { return false }
        apply(edit)
        return true
    }

    private func wrap(open: String, close: String? = nil) {
        perform { [weak self] in
            guard let self, let tv = textView else { return }
            apply(MarkdownFormatting.toggleWrap(text: tv.string, selection: tv.selectedRange(),
                                                open: open, close: close))
        }
    }

    /// The same as `lines`, for an edit that may have nothing to do.
    private func maybe(_ transform: @escaping (String, NSRange) -> MarkdownFormatting.Edit?) {
        perform(opensACell: false) { [weak self] in
            guard let self, let tv = textView, let edit = transform(tv.string, tv.selectedRange()) else { return }
            apply(edit)
        }
    }

    private func lines(_ transform: @escaping (String, NSRange) -> MarkdownFormatting.Edit) {
        perform { [weak self] in
            guard let self, let tv = textView else { return }
            apply(transform(tv.string, tv.selectedRange()))
        }
    }

    /// Several edits, in the order they were handed over — which
    /// `CellCommands.edits` makes back to front, so an earlier one cannot
    /// move the characters a later one names. One undo step for the lot,
    /// because taking three cells away was one gesture.
    private func apply(_ edits: [MarkdownFormatting.Edit]) {
        guard let tv = textView, let storage = tv.textStorage, !edits.isEmpty else { return }
        tv.window?.makeFirstResponder(tv)
        guard tv.shouldChangeText(inRanges: edits.map { NSValue(range: $0.range) },
                                  replacementStrings: edits.map(\.replacement)) else { return }
        storage.beginEditing()
        for edit in edits { storage.replaceCharacters(in: edit.range, with: edit.replacement) }
        storage.endEditing()
        tv.didChangeText()
        // The LAST applied edit is the front-most one: the caret lands
        // where the first of the cells was, not where the last of them was.
        if let landing = edits.last?.selection {
            tv.setSelectedRange(MarkdownFormatting.clamp(landing, to: (tv.string as NSString).length))
            tv.scrollRangeToVisible(tv.selectedRange())
        }
    }

    private func apply(_ edit: MarkdownFormatting.Edit, stealingFocus: Bool = true) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        if stealingFocus { tv.window?.makeFirstResponder(tv) }
        guard tv.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        // Through `shouldChangeText`/`didChangeText` even when nobody
        // typed it: that pair is the only thing in this app that puts an
        // edit on the undo stack, and an answer written into a note has
        // to come back out with ⌘Z the way the words read off a picture
        // do (`NoteStore.readText`).
        let selection = tv.selectedRanges
        storage.replaceCharacters(in: edit.range, with: edit.replacement)
        tv.didChangeText()
        if stealingFocus {
            tv.setSelectedRange(edit.selection)
            tv.scrollRangeToVisible(edit.selection)
        } else {
            // Where the caret was, moved by however much longer the note
            // just got — never dragged to what was written.
            tv.selectedRanges = selection.map {
                NSValue(range: EvalCells.shifted($0.rangeValue, by: edit))
            }
        }
    }
}
