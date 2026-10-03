import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A plain-text NSTextView for markdown source. Smart quotes and dashes are
/// off because they corrupt markdown; spelling stays on because it is prose.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    /// Changing this resets the undo stack — a new note is not an edit of the old one.
    let documentID: String?
    let bridge: EditorBridge
    /// Called the moment `/link` is completed, with the caret's position.
    var onLinkTrigger: ((Int) -> Void)?
    /// A picture on the pasteboard. Returns true when it was taken, and the
    /// paste stops there.
    var onPasteImage: ((NSPasteboard) -> Bool)?
    /// A click in the text — the drawing layer drops its selection on it.
    var onClick: (() -> Void)?
    /// The cursor to show instead of the I-beam — the pencil while the pen
    /// is up. The text view owns the cursor over the text, so it has to be
    /// the one to change it.
    var cursor: NSCursor?
    /// How far the text has scrolled, so the drawing layer can scroll with it.
    var onScroll: ((CGFloat) -> Void)?
    /// The place at the top of the window — the cell and how far into it
    /// — reported as it scrolls, and put back once when the pane appears.
    var onTopCell: ((CellPlace) -> Void)?
    var topCell: CellPlace = .top
    /// The notebook sections that are closed, by key. Their bodies are laid
    /// out with no height and never drawn, and the note's text is not
    /// touched (Sean, 2026-09-19: "show the notebook grouping and
    /// collapsing on the side").
    var collapsed: Set<String> = []
    /// A bracket in the gutter was clicked.
    var onToggleSection: ((String) -> Void)?
    /// False hides the markdown markers — `**`, `#`, the link's URL — while
    /// leaving them in the file, so the editor reads as the finished page
    /// (Sean, 2026-09-19: "allow wysiwyg editing"). The paragraph the caret
    /// is in always shows its own, so they can be typed.
    var showMarkers: Bool = false
    /// False while the pen, the arrow tool or a placement is up: the
    /// pencil owns the note pane then (Sean, 2026-09-20: "cursor only
    /// becomes a pen in the notes pane in drawing mode!!!!!"), so the
    /// pointer is never horizontal and no seam can be armed.
    var seamsEnabled: Bool = true
    /// The note's drawing cells, as this pane paints them under their lines
    /// (`NoteStore.cellLooks`).
    var drawingCells = DrawingCellsShown()
    /// Where the drawing cells are on this pane, each time one has moved
    /// (`CellFrame.moved`) — what the drawing layer draws into them by.
    var onDrawingFrames: (([CellFrame]) -> Void)?
    /// The drawing cell the caret is in, or nil, each time that changes —
    /// its grip is the layer's to show.
    var onDrawingCaret: ((UUID?) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        // TextKit 1, on purpose: `MarkerHiding` and `BulletGlyphs` are
        // NSLayoutManagerDelegate glyph substitution, which TextKit 2 has
        // no equivalent of — a faded `#` and a `- ` drawn as a bullet both
        // go through it. (The first reason was exclusion paths, which
        // TextKit 2 laid out nothing past; those went with the bands on
        // 2026-09-20, this one did not.)
        let tv = PasteAwareTextView(usingTextLayoutManager: false)
        // A layout manager that can fold: closed sections get line
        // fragments of no height, and are not drawn.
        let folding = FoldingLayoutManager()
        tv.textContainer?.replaceLayoutManager(folding)
        folding.typesetter = FoldingTypesetter(folding.folding)
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = false
        tv.font = Self.font
        tv.textColor = .textColor
        tv.insertionPointColor = .textColor
        // What the caret goes back to: it is hidden while a seam is armed,
        // because the line across the page IS the cursor then.
        tv.caretColour = tv.insertionPointColor
        tv.textContainerInset = Self.inset
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                                                 height: .greatestFiniteMagnitude)
        tv.defaultParagraphStyle = Self.paragraphStyle
        tv.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.textColor,
                               .paragraphStyle: Self.paragraphStyle]
        tv.string = text
        tv.frame = NSRect(origin: .zero, size: scroll.contentSize)

        scroll.documentView = tv
        // ONE delegate slot: this object substitutes the bullet glyphs and
        // hides the markers in the same pass.
        tv.layoutManager?.delegate = context.coordinator.hiding
        context.coordinator.hiding.isEnabled = !showMarkers
        bridge.textView = tv

        // The cell brackets ride with the text, in the margin the text
        // container already leaves on the right.
        let gutter = NotebookGutter(frame: NSRect(x: tv.bounds.width - NotebookGutter.width, y: 0,
                                                  width: NotebookGutter.width, height: tv.bounds.height))
        gutter.autoresizingMask = [.minXMargin, .height]
        gutter.onToggle = { [weak coordinator = context.coordinator] key in
            coordinator?.parent.onToggleSection?(key)
        }
        // Clicking a bracket picks the cell up — its heading and everything
        // under it — the way a Wolfram notebook does (Sean, 2026-09-19: "i
        // want to select, hide, etc").
        gutter.onSelect = { [weak coordinator = context.coordinator, weak tv] range in
            guard let coordinator, let tv else { return }
            coordinator.select([range], in: tv)
        }
        // And several of them — a drag down the column, a shift-click or a
        // cmd-click. NSTextView carries a discontiguous selection natively,
        // so holding three cells here IS three selected ranges: typing
        // replaces all three, and the brackets light from the same list.
        gutter.onSelectCells = { [weak coordinator = context.coordinator, weak tv] ranges in
            guard let coordinator, let tv else { return }
            coordinator.select(ranges, in: tv)
        }
        // Every cell that is HELD moves, and not only the one under the
        // pointer: a bracket drag is the same command as ⌃⇧↑/⌃⇧↓, and
        // dragging one cell out of a run of three that were picked up
        // together is nobody's idea of moving them.
        gutter.onMoveCell = { [weak coordinator = context.coordinator, weak tv] range, up in
            guard let coordinator, let tv else { return }
            let held = CellSelection.picked(cells: MarkdownParser.positioned(from: tv.string).map(\.range),
                                            selection: tv.selectedRanges.map(\.rangeValue))
            let cells = held.contains { NSEqualRanges($0, range) } ? held : [range]
            coordinator.apply(CellCommands.moving(cells, up: up, in: tv.string), in: tv)
        }
        tv.addSubview(gutter)
        context.coordinator.gutter = gutter

        // The insertion line between two cells, over the text and out of
        // the way of every click that is not in a seam.
        let insertions = CellInsertions(frame: tv.bounds)
        insertions.autoresizingMask = [.width, .height]
        insertions.onClick = { onClick?() }
        gutter.onClick = { onClick?() }
        // The promise a hover makes, painted over the words by the layer
        // that already knows where they are.
        gutter.onHoverCells = { [weak insertions] cells in insertions?.hoveredCells = cells }
        insertions.onArm = { [weak tv] offset in
            guard let tv = tv as? PasteAwareTextView else { return }
            tv.armedSeam = offset
            tv.setSelectedRange(NSRange(location: min(offset, (tv.string as NSString).length),
                                        length: 0))
            tv.window?.makeFirstResponder(tv)
        }
        // The text view's `armedSeam` is the one truth about whether a
        // seam is armed; this is how the layer hears it, whoever set it —
        // a click, an arrow key, a note switch, the pen going up.
        tv.onArmChanged = { [weak insertions] offset in insertions?.armedOffset = offset }
        // And the + hands its choice back to the same one truth.
        // Dragging a bar up or down takes the cells it passes, the same
        // command the bracket gutter's drag gives (Sean, 2026-09-21).
        insertions.onSelectCells = { [weak coordinator = context.coordinator, weak tv] ranges in
            guard let coordinator, let tv else { return }
            // A drag is a selection, not an insertion point: the bar it
            // started from goes out, or the note would have a cursor
            // between two cells AND three cells held at once.
            (tv as? PasteAwareTextView)?.armedSeam = nil
            coordinator.select(ranges, in: tv)
        }
        insertions.onChoose = { [weak tv] kind in
            guard let tv else { return }
            tv.armedType = kind
            if kind.opensAtOnce { tv.openArmedSeam(as: kind) }
        }
        tv.addSubview(insertions)
        context.coordinator.insertions = insertions

        context.coordinator.documentID = documentID
        context.coordinator.watchScrolling(of: scroll)
        context.coordinator.show(drawingCells, in: tv)
        (tv.layoutManager as? FoldingLayoutManager)?.onPainted = { [weak coordinator = context.coordinator, weak tv] in
            guard let coordinator, let tv else { return }
            coordinator.tellDrawingFrames(in: tv)
        }
        // The cursor, read on the way out of this pane by ⌘T.
        bridge.paneCaret = { [weak tv] in
            guard let tv else { return EditorBridge.Carried(caret: nil, text: "") }
            return EditorBridge.Carried(caret: Coordinator.caret(of: tv), text: tv.string)
        }
        // Where its seams and its column are, for a dock (`EditorBridge.paneSeams`).
        bridge.paneSeams = { [weak tv, weak coordinator = context.coordinator] in
            guard let tv else { return [] }
            return MarkdownTextView.seams(in: tv, cells: coordinator?.cells)
        }
        bridge.paneColumn = { [weak tv] in
            guard let tv, let container = tv.textContainer else { return nil }
            return (tv.textContainerOrigin.x + container.lineFragmentPadding,
                    FoldingLayoutManager.column(of: container))
        }
        // Whatever the rendered page was showing, show that: the same
        // place at the top of the window, and its cursor where it was.
        let carried = bridge.takeCarried(for: text)
        let place = topCell
        context.coordinator.restore(place, in: scroll) { [weak coordinator = context.coordinator] tv in
            guard let carried else { return }
            coordinator?.put(carried.caret, at: place, in: tv)
        }
        // The glyphs already exist by now (the string was set above), so
        // the styling and the hiding have to invalidate them by hand —
        // without this nothing is styled and nothing hides.
        context.coordinator.restyle(tv, force: true)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        bridge.textView = tv
        context.coordinator.parent = self
        if let tv = tv as? PasteAwareTextView {
            // The closures capture this frame's view, so they are replaced,
            // not kept: an old one would paste into the note that was open
            // when the editor was built.
            tv.onPasteImage = { onPasteImage?($0) ?? false }
            tv.onClick = onClick
            // Only the override. Showing it under a pointer that has not
            // moved is the drawing layer's, which is put up with it and
            // sets it on its next turn (`CursorLayer`): this used to set
            // it as well, by `bounds` — which for the scroll view's
            // document view takes in the formatting bar as soon as the
            // note is scrolled — and with no thought for whether this app
            // had the pointer at all.
            if tv.cursorOverride !== cursor {
                tv.cursorOverride = cursor
                tv.window?.invalidateCursorRects(for: tv)
            }
        }

        context.coordinator.setSeams(enabled: seamsEnabled)
        context.coordinator.show(drawingCells, in: tv)
        context.coordinator.collapsed = collapsed
        context.coordinator.applyFolding()
        if context.coordinator.hiding.isEnabled == showMarkers {
            context.coordinator.hiding.isEnabled = !showMarkers
            context.coordinator.restyle(tv, force: true)
        }

        if context.coordinator.documentID != documentID {
            context.coordinator.documentID = documentID
            // The bar belongs to the note it was armed in. This pane is
            // NOT rebuilt on a switch — only the rendered page carries
            // `.id(note.id)` — so an armed seam that is not put out here
            // arrives in the next note with a stale offset, no caret at
            // all (the colour comes back through this property and no
            // other), and a bar painted across a page at a y that means
            // nothing.
            (tv as? PasteAwareTextView)?.armedSeam = nil
            tv.string = text
            tv.undoManager?.removeAllActions()
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.scroll(.zero)
            context.coordinator.restyle(tv, force: true)
            return
        }
        if tv.string != text {
            // The same for an edit that arrived from outside — the folder
            // watch picking up another app's save, or undo from the menu.
            // Neither goes through `mouseDown` or `doCommand`.
            (tv as? PasteAwareTextView)?.armedSeam = nil
            let selection = tv.selectedRange()
            tv.string = text
            let clamped = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
            tv.setSelectedRange(clamped)
            context.coordinator.applyFolding(force: true)
            context.coordinator.restyle(tv, force: true)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let tv = scroll.documentView as? NSTextView, coordinator.parent.bridge.textView === tv {
            coordinator.parent.bridge.textView = nil
        }
        coordinator.undoManager.removeAllActions()
    }

    /// Where each cell is down the page, in the text view's own
    /// coordinates: the top and bottom of the lines its block is laid out
    /// on, and the character offset it begins at.
    ///
    /// Measured over WHOLE LINES rather than over the block's glyph range.
    /// A `.blank` cell's range stops one line short of the lines it stands
    /// for — its last character is the newline that ends the line before
    /// the last — and measuring the range alone put 22 pt of the cell's
    /// own body into the seam under it. Widening to the lines the range
    /// touches is a no-op for a paragraph, a heading or a list, whose last
    /// character is on the last line they occupy.
    static func cellBoxes(in tv: NSTextView) -> [CellSeams.Box] {
        guard let layout = tv.layoutManager, let container = tv.textContainer else { return [] }
        return cellBoxes(of: tv.string, layout: layout, container: container, origin: tv.textContainerOrigin)
    }

    /// The same boxes off any layout of the note — the text view's own,
    /// or the one `cellBoxes(of:width:showMarkers:collapsed:)` makes with
    /// no text view at all.
    private static func cellBoxes(of string: String, layout: NSLayoutManager, container: NSTextContainer,
                                  origin: CGPoint) -> [CellSeams.Box] {
        let text = string as NSString
        guard text.length > 0 else { return [] }
        layout.ensureLayout(for: container)
        var boxes: [CellSeams.Box] = []
        for block in MarkdownParser.positioned(from: string) {
            let start = min(max(block.range.location, 0), text.length - 1)
            let end = min(max(NSMaxRange(block.range), start), text.length - 1)
            let lines = NSUnionRange(text.lineRange(for: NSRange(location: start, length: 0)),
                                     text.lineRange(for: NSRange(location: end, length: 0)))
            let rect = box(of: lines, layout: layout, container: container)
            // A block inside a closed section is laid out with no height
            // at all (`FoldingTypesetter`) and is not on the page: it is
            // still parsed, so leaving it in piled a seam per hidden block
            // on the fold, each widened to the 8 pt minimum about the same
            // point, over the top of the text below. `refreshBrackets`
            // has always made the same check, which is why the brackets
            // looked right while the pointer did not.
            guard rect.height > 1 else { continue }
            boxes.append(CellSeams.Box(top: rect.minY + origin.y, bottom: rect.maxY + origin.y,
                                       offset: block.range.location))
        }
        return boxes
    }

    /// The box a run of the note takes on the page, in the text
    /// container's coordinates: its glyphs' bounding rect, and every
    /// drawing cell in it — a cell's drawing is in the room under its line
    /// (`CellLines`), one geometry for everything that asks
    /// (`FoldingLayoutManager.cellRect`), so whether `boundingRect` takes
    /// that room in is never relied on. No height at all for a run that is
    /// folded away.
    static func box(of characters: NSRange, layout: NSLayoutManager, container: NSTextContainer) -> CGRect {
        let glyphs = layout.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        guard rect.height > 1, let folding = layout as? FoldingLayoutManager else { return rect }
        for line in folding.drawings.lines where NSIntersectionRange(line.range, characters).length > 0 {
            if let cell = folding.cellRect(line, in: container, origin: .zero) { rect = rect.union(cell) }
        }
        return rect
    }

    /// Where this pane's drawing cells are, in the text view's own
    /// coordinates — the document's, for the drawing layer over it.
    static func drawingFrames(in tv: NSTextView) -> [CellFrame] {
        guard let layout = tv.layoutManager as? FoldingLayoutManager, let container = tv.textContainer else { return [] }
        let column = FoldingLayoutManager.column(of: container)
        return layout.drawings.lines.compactMap { line in
            guard let rect = layout.cellRect(line, in: container, origin: tv.textContainerOrigin) else { return nil }
            let look = layout.drawings.shown.look(line.id)
            return CellFrame(id: line.id, line: line.range, rect: rect, scale: look.shown(column: column).scale,
                             width: look.cell.map { CGFloat($0.width) } ?? column,
                             writable: look.state == .writable)
        }
    }

    /// THE BOXES THIS PANE WOULD GIVE THE NOTE, with no text view on
    /// screen — what the rendered page needs to show the drawing layer
    /// where this pane put it (`PaneMapping`), and what the PDF needs to
    /// put it on paper. The same TextKit 1 stack `makeNSView` builds — the
    /// folding typesetter, the marker hiding, the styling of `restyle` —
    /// at a pane `width` wide, so the lines wrap where this pane wraps
    /// them. What it cannot know is the caret: in the text view the cell
    /// the caret is in shows its markers, which can wrap that one cell
    /// differently. Its drawing cells take the room they take there
    /// (`cells`), or every cell under one would be laid out a drawing too
    /// high.
    static func cellBoxes(of text: String, width: CGFloat, showMarkers: Bool,
                          collapsed: Set<String>, cells: DrawingCellsShown = DrawingCellsShown()) -> [CellSeams.Box] {
        guard !text.isEmpty, width > inset.width * 2 else { return [] }
        let storage = NSTextStorage(string: text, attributes: [.font: font, .paragraphStyle: paragraphStyle])
        let layout = FoldingLayoutManager()
        layout.typesetter = FoldingTypesetter(layout.folding)
        layout.folding.hidden = NotebookOutline.hiddenRanges(in: text, collapsed: collapsed)
        // The text was in the storage before the layout manager was, so no
        // edit has told it where the drawing lines are.
        _ = layout.drawings.read(text, edited: 0)
        let hiding = MarkerHiding()
        hiding.isEnabled = !showMarkers
        layout.delegate = hiding
        let container = NSTextContainer(size: NSSize(width: width - inset.width * 2,
                                                     height: .greatestFiniteMagnitude))
        _ = layout.drawings.show(cells, column: FoldingLayoutManager.column(of: container))
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        style(storage, with: hiding)
        let whole = NSRange(location: 0, length: storage.length)
        layout.invalidateGlyphs(forCharacterRange: whole, changeInLength: 0, actualCharacterRange: nil)
        layout.invalidateLayout(forCharacterRange: whole, actualCharacterRange: nil)
        return cellBoxes(of: text, layout: layout, container: container,
                         origin: CGPoint(x: inset.width, y: inset.height))
    }

    /// The same, for a PANE of `size`: the text view is the pane's width
    /// less a scroller when one stands beside a note too long for the pane
    /// (`textWidth(pane:noteHeight:)`). Returns the width it was laid out
    /// at, and how tall the note is at the pane's full width — the one
    /// number that decides the scroller, so a pane only made taller or
    /// shorter can tell from it whether its layout still holds.
    static func cellBoxes(of text: String, pane size: CGSize, showMarkers: Bool, collapsed: Set<String>,
                          drawings: DrawingCellsShown = DrawingCellsShown())
        -> (cells: [CellSeams.Box], width: CGFloat, height: CGFloat) {
        let cells = cellBoxes(of: text, width: size.width, showMarkers: showMarkers, collapsed: collapsed,
                              cells: drawings)
        let height = (cells.last?.bottom ?? 0) + inset.height
        let width = textWidth(pane: size, noteHeight: height)
        guard width < size.width else { return (cells, size.width, height) }
        return (cellBoxes(of: text, width: width, showMarkers: showMarkers, collapsed: collapsed, cells: drawings),
                width, height)
    }

    /// How wide the text is in a pane of `size` holding a note `noteHeight`
    /// tall: the pane's width, less a scroller beside a note too long for
    /// the pane — with a mouse plugged in macOS shows legacy scrollers,
    /// which take room (17 points, measured), and a line laid out 17
    /// points wider wraps somewhere else.
    static func textWidth(pane size: CGSize, noteHeight: CGFloat) -> CGFloat {
        guard noteHeight > size.height, NSScroller.preferredScrollerStyle == .legacy else { return size.width }
        return size.width - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    /// The air round the text: the text container's inset, the same in
    /// the text view and in `cellBoxes(of:width:showMarkers:collapsed:)`.
    static let inset = NSSize(width: 24, height: 20)

    /// Where this pane's words start and end across a pane `width` wide:
    /// the inset and the line fragment's own padding, each side.
    static func column(width: CGFloat) -> PaneMapping.Column {
        PaneMapping.Column(left: inset.width + lineFragmentPadding, right: width - inset.width - lineFragmentPadding)
    }

    /// A text container's own padding each side of a line, which this pane
    /// leaves at the default.
    private static let lineFragmentPadding = NSTextContainer().lineFragmentPadding

    /// The note's styling, put on the text: the source styled the way the
    /// rendered blocks are and the markers that may vanish handed to
    /// `hiding` — or, with the markers showing (`hiding` off), plain
    /// attributes and nothing to hide. One description for the text view
    /// (`Coordinator.restyle`) and the offscreen layout.
    static func style(_ storage: NSTextStorage, with hiding: MarkerHiding) {
        let source = storage.string
        let text = source as NSString
        let whole = NSRange(location: 0, length: text.length)
        if hiding.isEnabled {
            MarkdownSourceStyle.apply(to: storage, base: MarkdownTextView.font,
                                      paragraph: MarkdownTextView.paragraphStyle)
            // The blank line between two cells, and a fence's own
            // line, are drawn a few points tall: the gap between two
            // cells is then the same on this side as on the rendered
            // page, and a note is nearly the same height in both.
            let small = NSFont.systemFont(ofSize: MarkdownSourceStyle.structuralSize)
            let tight = NSMutableParagraphStyle()
            tight.setParagraphStyle(MarkdownTextView.paragraphStyle)
            tight.lineSpacing = 0
            tight.paragraphSpacing = 0
            // The gap belongs to the cell above it, not to the blank
            // lines between: one cell, one gap, whatever the file has
            // between them (Sean, 2026-09-20: "cells still aren't
            // stacked with an even small spacing between them").
            let spaced = NSMutableParagraphStyle()
            spaced.setParagraphStyle(MarkdownTextView.paragraphStyle)
            spaced.paragraphSpacing = MarkdownPreview.gapHeight
            for line in MarkdownSourceStyle.cellEndLines(in: source) {
                let range = NSIntersectionRange(line, whole)
                guard range.length > 0 else { continue }
                storage.addAttribute(.paragraphStyle, value: spaced, range: range)
            }
            for line in MarkdownSourceStyle.structuralLines(in: source) {
                let range = NSIntersectionRange(line, whole)
                guard range.length > 0 else { continue }
                storage.addAttributes([.font: small, .paragraphStyle: tight], range: range)
            }
            // A DRAWING CELL'S LINE is the name of its file and nothing to
            // read: a sliver tall, drawn in no colour, with the cell's gap
            // under it — under the drawing, which the typesetter puts
            // between the two (`CellLines`).
            let drawn = NSMutableParagraphStyle()
            drawn.setParagraphStyle(MarkdownTextView.paragraphStyle)
            drawn.lineSpacing = 0
            drawn.paragraphSpacing = MarkdownPreview.gapHeight
            for line in DrawingCells.lines(in: source) {
                let range = NSIntersectionRange(text.lineRange(for: line.range), whole)
                guard range.length > 0 else { continue }
                storage.addAttributes([.font: small, .foregroundColor: NSColor.clear, .paragraphStyle: drawn],
                                      range: range)
            }
            hiding.setMarkers(MarkerHiding.hideable(MarkdownSourceStyle.runs(in: source), in: text))
        } else {
            storage.setAttributes([.font: MarkdownTextView.font,
                                   .foregroundColor: NSColor.textColor,
                                   .paragraphStyle: MarkdownTextView.paragraphStyle],
                                  range: whole)
            hiding.setMarkers([])
        }
    }

    /// The spaces between those cells: where the pointer is horizontal and
    /// where a click opens a new cell (Sean, 2026-09-20: "the cursor
    /// should be horizontal any space between the two cells").
    ///
    /// The page runs from the top of the text view to the bottom of the
    /// text laid out in it — `usedRect` is in the CONTAINER's coordinates,
    /// so it takes the origin too, or the tail seam starts an inset too
    /// high — or to the bottom of the view when the note is shorter than
    /// the window, so the empty space under the last cell is all seam.
    static func seams(in tv: NSTextView, cells: [CellSeams.Box]? = nil) -> [CellSeams.Seam] {
        guard let layout = tv.layoutManager, let container = tv.textContainer else { return [] }
        let bottom = layout.usedRect(for: container).maxY + tv.textContainerOrigin.y
        return CellSeams.seams(cells: cells ?? cellBoxes(in: tv), pageTop: 0,
                               pageBottom: max(tv.bounds.height, bottom),
                               noteLength: (tv.string as NSString).length,
                               // On a note with no cells at all there is
                               // nothing to put the bar against, and the
                               // text container's inset is where the first
                               // line will come out.
                               firstCellTop: tv.textContainerOrigin.y)
    }

    /// Whether the caret is on the first line of the page (`top`) or the
    /// last — the LINE AS LAID OUT, so a long first paragraph that wraps
    /// still takes ↑ to its own first line before it takes it to the bar.
    /// An empty note has one line, which is both.
    static func isOnEndLine(of tv: NSTextView, top: Bool) -> Bool {
        guard let layout = tv.layoutManager, let container = tv.textContainer else { return false }
        let length = (tv.string as NSString).length
        guard length > 0 else { return true }
        layout.ensureLayout(for: container)
        let caret = min(tv.selectedRange().location, length)
        // A caret after a final newline is on the line under it — the extra
        // line fragment, which has no glyph to ask about.
        if caret == length, (tv.string as NSString).character(at: length - 1) == 10 { return !top }
        func line(_ character: Int) -> CGRect {
            layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: character), effectiveRange: nil)
        }
        let here = line(min(caret, length - 1))
        let end = line(top ? 0 : length - 1)
        return abs(here.minY - end.minY) < 0.5
    }

    /// Open a cell at an armed seam: the blank lines that make what is
    /// typed next a block of its own, the marker for whatever kind the +
    /// chose, and the caret where the words go.
    ///
    /// `CellTypes.open` decides all of that — one rule for both panes —
    /// and only what it ADDS is typed in, at the seam, rather than the
    /// whole note being replaced by its answer: undo then takes the
    /// opening in one step and the restyle does not re-run over every
    /// character of a long note. That holds with a kind chosen too,
    /// because the command it runs only ever touches the line the caret
    /// was left on, which is inside what the opening just added.
    ///
    /// INTO THE STORAGE, between `shouldChangeText` and `didChangeText`,
    /// as every other edit nobody typed is (`EditorBridge.apply`) — never
    /// `insertText(_:replacementRange:)` inside that pair: that one does
    /// its own pair, so the opening went on the undo stack twice and ⌘Z
    /// took it out once and then failed on the second, stale, copy
    /// (`NSRangeException`, measured 2026-10-02 in a hosted editor).
    static func openSeam(at offset: Int, as type: CellTypes.Kind = .text, in tv: NSTextView) {
        let text = tv.string as NSString
        let place = min(max(offset, 0), text.length)
        let (updated, _, caret) = CellTypes.open(type, in: tv.string, at: place)
        let added = (updated as NSString).length - text.length
        guard added >= 0 else { return }
        if added > 0 {
            let opening = (updated as NSString).substring(with: NSRange(location: place, length: added))
            let range = NSRange(location: place, length: 0)
            // ONE CHANGE, ONE STEP OF UNDO. `insertText` asks
            // `shouldChangeText` and calls `didChangeText` itself, so
            // wrapping it in a second pair put the opening on the undo
            // stack twice: one ⌘Z took it out twice over — half the note
            // mid-note, and an exception at the end of it, where the second
            // removal ran past the last character (2026-10-02).
            guard tv.shouldChangeText(in: range, replacementString: opening) else { return }
            tv.textStorage?.replaceCharacters(in: range, with: opening)
            tv.didChangeText()
        }
        tv.setSelectedRange(NSRange(location: min(caret, (tv.string as NSString).length), length: 0))
        tv.window?.makeFirstResponder(tv)
    }

    static let font = NSFont.systemFont(ofSize: 15)
    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        // A tab lands on the same four-space grid the indent button uses,
        // so a note written with tabs and one written with spaces line up
        // (Sean, 2026-09-19: "indentation and tab width is 4 spaces").
        style.tabStops = []
        style.defaultTabInterval = MarkdownTextView.tabWidth
        return style
    }()

    /// How tall one line of the source pane is: the font's own line
    /// height plus the space between lines. The rendered page matches a
    /// code cell against this — see `MarkdownPreview.codePadding`.
    static let lineHeight: CGFloat = {
        NSLayoutManager().defaultLineHeight(for: font) + paragraphStyle.lineSpacing
    }()

    /// The size the source pane sets code at: a little under the body, so
    /// a monospace line is not visibly bigger than the prose round it.
    static let codeSize: CGFloat = font.pointSize * 0.95

    /// Four spaces of the editor's own font.
    static let tabWidth: CGFloat = {
        let space = ("    " as NSString).size(withAttributes: [.font: MarkdownTextView.font]).width
        return max(space, 8)
    }()

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        var documentID: String?
        /// The editor's own undo stack, not the window's: the source editor
        /// is torn down whenever the preview comes up, and undo actions left
        /// on the window's manager would point at a freed text view (the
        /// same crash BlockEditor.Coordinator.undoManager explains).
        let undoManager = UndoManager()
        /// Draws `- ` as a round bullet AND hides the markers.
        let hiding = MarkerHiding()
        /// Used by the preview's block editor; kept here so both editors
        /// answer to the same glyph rules.
        let bullets = BulletGlyphs()
        /// The re-scan is debounced: styling a long note is tens of
        /// milliseconds, and it must never sit on a keystroke.
        private var restyleWork: DispatchWorkItem?
        /// What was last styled, and whether it was styled at all — so a
        /// pass that would change nothing is not made.
        private var lastStyled: String?
        private var lastStyledRendered = true

        /// The cells' boxes as `refreshBrackets` last measured them, and how
        /// wide the text view was then: the first measure is made before
        /// the view has a size, and a resize relays every line.
        private(set) var cells: [CellSeams.Box] = []
        private var cellsWidth: CGFloat = 0
        /// The notebook's closed sections, and what was last folded away.
        var collapsed: Set<String> = []
        private var lastHidden: [NSRange] = []
        /// The drawing cells' frames as last told, and the cell the caret
        /// was last said to be in.
        /// Nil until the first time — a pane tells what it has once, even
        /// nothing, because the page that is gone may have left frames of its
        /// own with the layer (`EditorPane.forgetFrames`).
        private var drawingFrames: [CellFrame]?
        private var caretDrawing: UUID?
        weak var gutter: NotebookGutter?
        weak var insertions: CellInsertions?
        private weak var scrollView: NSScrollView?
        private var scrollObserver: NSObjectProtocol?

        init(_ parent: MarkdownTextView) { self.parent = parent }

        deinit {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        /// The seams come and go with the pen: with it up the whole note
        /// pane belongs to the pencil, so the layer is hidden — which is
        /// also what stops it hit testing — and anything armed goes out.
        func setSeams(enabled: Bool) {
            guard let insertions else { return }
            let away = !enabled
            guard insertions.isHidden != away else { return }
            insertions.isHidden = away
            // The text view cuts its cursor rects from the layer's seams
            // and a hidden layer hands over none, so it has to be asked
            // again — or the pointer stays on its side over a pane the
            // pencil has just taken.
            if let tv = insertions.superview { tv.window?.invalidateCursorRects(for: tv) }
            guard away else { return }
            (insertions.superview as? PasteAwareTextView)?.armedSeam = nil
            insertions.disarm()
        }

        /// What the drawing cells show, handed over again: a cell that is
        /// another size now is laid out again — and everything under it,
        /// which moves — one that only looks different is painted again, and
        /// nothing else is touched. A stroke drawn in a cell is a repaint of
        /// that cell, never a relayout of the note.
        func show(_ shown: DrawingCellsShown, in tv: NSTextView) {
            guard let layout = tv.layoutManager as? FoldingLayoutManager, let container = tv.textContainer,
                  let storage = tv.textStorage else { return }
            let changed = layout.drawings.show(shown, column: FoldingLayoutManager.column(of: container))
            if let first = changed.relayout.map(\.location).min(), first < storage.length {
                layout.invalidateLayout(forCharacterRange: NSRange(location: first, length: storage.length - first),
                                        actualCharacterRange: nil)
                tv.sizeToFit()
                tv.needsDisplay = true
                refreshBrackets(in: tv)
                return
            }
            for range in changed.repaint {
                guard let line = layout.drawings.lines.first(where: { $0.range == range }),
                      let rect = layout.cellRect(line, in: container, origin: tv.textContainerOrigin) else { continue }
                tv.setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
            }
        }

        /// Where the drawing cells are, told to the layer over this pane —
        /// only when one has moved, which on most keystrokes none has.
        func tellDrawingFrames(in tv: NSTextView) {
            let frames = MarkdownTextView.drawingFrames(in: tv)
            if let told = drawingFrames, !CellFrame.moved(told, frames) { return }
            drawingFrames = frames
            // A turn late: this runs inside a view update, and what it
            // tells is SwiftUI state.
            let tell = parent.onDrawingFrames
            DispatchQueue.main.async { tell?(frames) }
        }

        /// The drawing cell the caret is in — its outline lit here, its grip
        /// the layer's to show — told when it changes.
        private func tellDrawingCaret(in tv: NSTextView) {
            guard let pane = tv as? PasteAwareTextView, let layout = tv.layoutManager as? FoldingLayoutManager
            else { return }
            let here = pane.armedSeam == nil
                ? pane.drawingCellAtCaret.flatMap { line in layout.drawings.lines.first { $0.range == line }?.id }
                : nil
            guard here != caretDrawing else { return }
            caretDrawing = here
            layout.drawings.lit = here
            tv.needsDisplay = true
            let tell = parent.onDrawingCaret
            DispatchQueue.main.async { tell?(here) }
        }

        /// Style the source the way the preview's blocks are styled, then
        /// work out which markers can vanish and re-generate their glyphs.
        ///
        /// With the markers showing it does the opposite: plain attributes,
        /// no markers to hide, nothing substituted — the note exactly as it
        /// is written. And it does NOTHING AT ALL when neither the text nor
        /// the mode has changed since the last pass, because this is on the
        /// end of a keystroke (Sean, 2026-09-19: "it keeps trying to render
        /// when i'm in show only markdown mode").
        func restyle(_ tv: NSTextView, force: Bool = false) {
            guard let storage = tv.textStorage, let layout = tv.layoutManager else { return }
            let source = tv.string
            guard force || source != lastStyled || hiding.isEnabled != lastStyledRendered else { return }
            lastStyled = source
            lastStyledRendered = hiding.isEnabled

            let selection = tv.selectedRanges
            let whole = NSRange(location: 0, length: (source as NSString).length)
            MarkdownTextView.style(storage, with: hiding)
            // The caret stands in for the bar under a drawing cell only
            // while its line is hidden; shown, the line is text like any.
            (tv as? PasteAwareTextView)?.drawingStandIns = hiding.isEnabled
            tv.typingAttributes = [.font: MarkdownTextView.font,
                                   .foregroundColor: NSColor.textColor,
                                   .paragraphStyle: MarkdownTextView.paragraphStyle]
            tv.selectedRanges = selection

            layout.invalidateGlyphs(forCharacterRange: whole, changeInLength: 0, actualCharacterRange: nil)
            layout.invalidateLayout(forCharacterRange: whole, actualCharacterRange: nil)
            tv.updateHiddenMarkers(hiding)
            tv.sizeToFit()
            refreshBrackets(in: tv)
        }

        /// The same, a moment after the typing stops.
        func scheduleRestyle(_ tv: NSTextView) {
            restyleWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                restyle(tv)
            }
            restyleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        /// Several edits at once, in the order `CellCommands.edits` made
        /// them — back to front, so an earlier one cannot move the
        /// characters a later one names. One undo step, because taking or
        /// moving three cells was one gesture.
        func apply(_ edits: [MarkdownFormatting.Edit], in tv: NSTextView) {
            guard let storage = tv.textStorage, !edits.isEmpty,
                  tv.shouldChangeText(over: edits.map { ($0.range, $0.replacement) }) else { return }
            storage.beginEditing()
            for edit in edits { storage.replaceCharacters(in: edit.range, with: edit.replacement) }
            storage.endEditing()
            tv.didChangeText()
            // The LAST of them is the front-most edit, so its selection is
            // the one nothing that came after has moved.
            if let landing = edits.last?.selection {
                tv.setSelectedRange(MarkdownFormatting.clamp(landing, to: (tv.string as NSString).length))
                tv.scrollRangeToVisible(tv.selectedRange())
            }
            restyle(tv, force: true)
        }

        /// One edit to the note, through the text view so undo sees it.
        func apply(_ edit: MarkdownFormatting.Edit, in tv: NSTextView) {
            guard let storage = tv.textStorage,
                  tv.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
            tv.didChangeText()
            tv.setSelectedRange(edit.selection)
            tv.scrollRangeToVisible(edit.selection)
            restyle(tv, force: true)
        }

        /// What the brackets hold, selected — one cell, or as many as the
        /// gesture reached.
        ///
        /// Through `normalise` because AppKit DROPS THE WHOLE SELECTION if
        /// the ranges are out of order, overlapping or duplicated, and the
        /// only sign of it is a single caret where three cells should be.
        ///
        /// Only ONE cell is scrolled to. A drag down the gutter arrives
        /// here on every move, and scrolling under a drag moves the
        /// brackets out from under the pointer — which reads as the next
        /// cell, which scrolls again. A click has nothing to fight with.
        func select(_ wanted: [NSRange], in tv: NSTextView) {
            let ranges = MarkdownFormatting.normalise(wanted, in: tv.string as NSString)
                .filter { $0.length > 0 }
            tv.window?.makeFirstResponder(tv)
            guard !ranges.isEmpty else {
                // Cmd-clicking the last held cell out of the selection:
                // what is left is a caret where it began, not the cells
                // still lit because nothing was handed over to replace
                // them.
                tv.setSelectedRange(NSRange(location: tv.selectedRange().location, length: 0))
                refreshBrackets(in: tv)
                return
            }
            tv.selectedRanges = ranges.map { NSValue(range: $0) }
            if ranges.count == 1 { tv.scrollRangeToVisible(ranges[0]) }
            refreshBrackets(in: tv)
        }

        /// Tab inside a fenced code block: four spaces in, or one level
        /// out. False when the caret is not in a fence, and then the
        /// markdown indent command has it as before.
        private func fenceTab(_ tv: NSTextView, outdent: Bool) -> Bool {
            guard CodeTyping.inFence(tv.string, selection: tv.selectedRange()),
                  let storage = tv.textStorage else { return false }
            let edit = CodeTyping.tabbing(in: tv.string, selection: tv.selectedRange(),
                                          outdent: outdent, unit: MarkdownFormatting.indentUnit)
            guard tv.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return true }
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
            tv.didChangeText()
            tv.setSelectedRange(edit.selection)
            return true
        }

        /// The caret moved: the paragraph it left hides its markers again
        /// and the one it arrived in shows them.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Where the caret IS says whether a seam is armed (the plan's
            // step 3, from Sean, 2026-09-20: "the mouse cursor and text
            // cursor should both become horizontal between cells"). Only
            // a click used to arm one, so ↓ onto the blank line between
            // two cells and a character merged them into one paragraph —
            // and everything that moves the selection without a mouse
            // down (a bracket click, ⌘A, a toolbar command, `/link`) left
            // the bar armed behind it, ready to throw the selection away.
            if let tv = tv as? PasteAwareTextView {
                let wanted = parent.seamsEnabled
                    ? CellSeams.arm(caret: tv.selectedRange(), in: tv.string, current: tv.armedSeam)
                    : nil
                // Only a seam the PAGE has. A caret on the blank line
                // beside a closed section reads as a separator in the
                // text and is not one on the page — the cells inside the
                // fold are not laid out — and arming it would turn the
                // caret off with no bar drawn in its place.
                //
                // MEASURED NOW, and not read off the layer: the layer is
                // measured again once the text has changed, and NSTextView
                // moves the caret INSIDE its own edit, before that. Return
                // at the end of a cell put the caret on the new separator
                // and asked the seams from before the Return, which had no
                // seam there — so the bar never came up, and the next
                // character joined the cell above as a second line of it.
                // Only while the caret is on a separator at all, which is
                // the one time this is asked.
                tv.armedSeam = wanted.flatMap { offset in
                    MarkdownTextView.seams(in: tv).contains { $0.offset == offset } ? offset : nil
                }
            }
            // AFTER the arming, never before it: whether a paragraph
            // shows its markers is read off `armedSeam` too, and asking
            // first got the answer for the move before this one — the
            // cell left behind stayed revealed and the one arrived in
            // stayed hidden, each for one keystroke.
            tv.updateHiddenMarkers(hiding)
            refreshBrackets(in: tv)
            tellDrawingCaret(in: tv)
        }

        /// Put that place in that cell back at the top of the window — the
        /// line the rendered page had at its fold, or the air between two
        /// cells it was resting in. The layout has to exist first, and at
        /// makeNSView it does not, so this waits a turn — the same turn the
        /// brackets wait for. `then` runs in that turn, before the scroll
        /// is measured: putting the caret back reveals its cell's markers,
        /// which can move every line under it.
        func restore(_ place: CellPlace, in scroll: NSScrollView, then: @escaping (NSTextView) -> Void) {
            DispatchQueue.main.async { [weak scroll] in
                guard let scroll, let tv = scroll.documentView as? NSTextView else { return }
                then(tv)
                guard place != .top, let y = place.y(in: MarkdownTextView.cellBoxes(in: tv)) else { return }
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        /// This pane's cursor, as ⌘T carries it: the armed bar, the cells
        /// held, or the caret — the caret only while this pane has the
        /// keyboard, since one left behind by a click elsewhere is not
        /// where anybody is typing.
        static func caret(of tv: NSTextView) -> PaneCaret? {
            let pane = tv as? PasteAwareTextView
            let caret = PaneCaret.source(selection: tv.selectedRanges.map(\.rangeValue), armed: pane?.armedSeam,
                                         kind: pane?.armedType ?? .text, in: tv.string)
            if case .text = caret, tv.window?.firstResponder !== tv { return nil }
            return caret
        }

        /// The cursor ⌘T carried, put back, and the keyboard with it — the
        /// pane that went was being typed in. With NO cursor carried the
        /// caret goes to the start of the cell at the top of the window,
        /// where the eye is, and not the end of the note where a new text
        /// view leaves it: ⌘1 and a pasted picture both go by the caret,
        /// and titled the last cell and landed under the last line. The
        /// keyboard stays where it was then.
        func put(_ caret: PaneCaret?, at place: CellPlace, in tv: NSTextView) {
            let length = (tv.string as NSString).length
            guard let caret else {
                tv.setSelectedRange(NSRange(location: min(max(place.cell, 0), length), length: 0))
                return
            }
            switch caret {
            case .text(let range):
                tv.setSelectedRange(MarkdownFormatting.clamp(range, to: length))
            case .cells(let ranges):
                // Not `select`, which scrolls a lone cell into view: the
                // window is already where the other pane had it.
                let held = MarkdownFormatting.normalise(ranges, in: tv.string as NSString).filter { $0.length > 0 }
                guard !held.isEmpty else { return }
                tv.selectedRanges = held.map { NSValue(range: $0) }
            case .bar(let offset, let kind):
                guard let tv = tv as? PasteAwareTextView else { return }
                // The way a click in a seam arms it (`CellInsertions.onArm`):
                // the bar first, so the caret parked at its offset reads
                // as the bar standing and not as a caret in the cell below.
                let at = min(max(offset, 0), length)
                tv.armedSeam = at
                tv.setSelectedRange(NSRange(location: at, length: 0))
                // After it: arming afresh puts the kind back to plain text.
                if tv.armedSeam == at { tv.armedType = kind }
            }
            tv.window?.makeFirstResponder(tv)
        }

        /// The drawing layer scrolls with the text, so it is told how far.
        func watchScrolling(of scroll: NSScrollView) {
            scrollView = scroll
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self] _ in
                guard let self, let scroll = self.scrollView else { return }
                let offset = scroll.contentView.bounds.origin.y
                self.parent.onScroll?(offset)
                guard let tv = scroll.documentView as? NSTextView else { return }
                if self.cellsWidth != tv.bounds.width {
                    self.cells = MarkdownTextView.cellBoxes(in: tv)
                    self.cellsWidth = tv.bounds.width
                }
                if let place = CellPlace.at(offset, in: self.cells) { self.parent.onTopCell?(place) }
            }
        }

        /// Fold what is closed, and redraw the brackets. Cheap when nothing
        /// has changed, because it is called on every update.
        func applyFolding(force: Bool = false) {
            guard let scroll = scrollView, let tv = scroll.documentView as? NSTextView,
                  let layout = tv.layoutManager as? FoldingLayoutManager, let container = tv.textContainer
            else { return }
            let hidden = NotebookOutline.hiddenRanges(in: tv.string, collapsed: collapsed)
            if force || hidden != lastHidden {
                lastHidden = hidden
                layout.folding.hidden = hidden
                let whole = NSRange(location: 0, length: (tv.string as NSString).length)
                layout.invalidateLayout(forCharacterRange: whole, actualCharacterRange: nil)
                layout.ensureLayout(for: container)
                tv.sizeToFit()
                tv.needsDisplay = true
                snapCaretOutOfHiding(in: tv)
            }
            refreshBrackets(in: tv)
        }

        /// Where each section's bracket goes, measured off the laid-out text.
        func refreshBrackets(in tv: NSTextView) {
            guard let gutter, let layout = tv.layoutManager, let container = tv.textContainer else { return }
            // The frame by hand, every time. At makeNSView the text view is
            // still zero-sized, and an autoresizing mask that starts from
            // nothing has nothing to grow from — which is why the brackets
            // were not there at all (Sean, 2026-09-19: "where's
            // wolfram/jupyter style notebook implementation?").
            let wanted = NSRect(x: tv.bounds.width - NotebookGutter.width, y: 0,
                                width: NotebookGutter.width, height: max(tv.bounds.height, 1))
            if gutter.frame != wanted { gutter.frame = wanted }
            let text = tv.string as NSString
            let origin = tv.textContainerOrigin
            // EVERY cell gets a bracket, and the sections that group them
            // get one further out — Wolfram's own furniture (Sean,
            // 2026-09-19: "i want wolfram/jupyter style notebook brackets").
            let sections = NotebookOutline.sections(in: tv.string)
            // Every range, not the first one: several cells held at once
            // are several selected ranges, and reading only `selectedRange`
            // lit the last of them alone.
            let selection = tv.selectedRanges.map(\.rangeValue)

            // The cell the caret is in — the one the rendered page would be
            // editing — so its bracket is the one drawn heavy. Unless the
            // bar between two cells is the cursor: arming parks the caret
            // at the separator, which `NotebookCells.block(containing:)`
            // reads as the start of the cell BELOW, and that cell was
            // then drawn heavy under a bar that was not in it (Sean,
            // 2026-09-20: "the next section shouldn't be highlighted when
            // the input cursor is currently that horizontal bar"). While
            // a seam is armed the caret is in no cell at all. A real
            // selection is untouched — it is not the caret.
            let armed = (tv as? PasteAwareTextView)?.armedSeam != nil
            let caret = !armed && selection.count == 1 ? selection[0] : nil
            let caretCell = caret?.length == 0
                ? NotebookCells.block(containing: caret?.location ?? 0, in: tv.string)?.range
                : nil

            // The cells, measured once: a SECTION's bracket is held when
            // every cell under it is, and that cannot be asked of its own
            // characters (`CellSelection.holds`).
            let blocks = MarkdownParser.positioned(from: tv.string)
            let cellRanges = blocks.map(\.range)

            func bracket(key: String, depth: Int, range: NSRange, foldable: Bool,
                         group: Bool = false) -> NotebookGutter.Bracket? {
                let clipped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
                guard clipped.length > 0 else { return nil }
                let box = MarkdownTextView.box(of: clipped, layout: layout, container: container)
                guard box.height > 1 else { return nil }
                // Lit and HELD are not the same thing: the caret's own
                // cell is drawn heavy with nothing selected, and the
                // gestures may not read that as a cell the user is
                // holding (2026-09-20).
                let held = CellSelection.holds(clipped, cells: cellRanges, selection: selection)
                let picked = held || NotebookGutter.isPicked(clipped, selection: selection,
                                                             caretCell: foldable ? nil : caretCell)
                return NotebookGutter.Bracket(key: key, depth: depth,
                                              top: box.minY + origin.y, bottom: box.maxY + origin.y,
                                              collapsed: collapsed.contains(key), selected: picked,
                                              held: held, range: clipped, foldable: foldable,
                                              group: group)
            }

            var brackets = sections.compactMap { section -> NotebookGutter.Bracket? in
                let end = min(max(section.contentEnd, NSMaxRange(section.headingRange)), text.length)
                let start = min(section.range.location, text.length)
                guard end > start else { return nil }
                return bracket(key: section.key, depth: section.depth,
                               range: NSRange(location: start, length: end - start), foldable: true)
            }

            // An evaluation cell and its answer are ONE GROUP, with a
            // bracket round the pair (Sean, 2026-09-21: "input and
            // output cells are grouped together").
            let groups = EvalCells.groups(in: tv.string)
            for group in groups {
                let depth = NotebookOutline.cellDepth(at: group.input.location, in: sections)
                if let embrace = bracket(key: group.key, depth: depth,
                                         range: group.range, foldable: false, group: true) {
                    brackets.append(embrace)
                }
            }

            // The cells themselves: one per block, drawn inside whichever
            // section holds them — and one step further in when a group
            // holds them too.
            for block in blocks {
                var depth = NotebookOutline.cellDepth(at: block.range.location, in: sections)
                if EvalCells.isGrouped(block.range, in: groups) { depth += 1 }
                if let cell = bracket(key: "cell:\(block.range.location)", depth: depth,
                                      range: block.range, foldable: false) {
                    brackets.append(cell)
                }
            }
            gutter.brackets = brackets
            // Measured once here, where every change to the layout comes
            // through, and read by the scroll: the top of the window is a
            // place among these (`CellPlace`), on every tick of a scroll.
            let cells = MarkdownTextView.cellBoxes(in: tv)
            self.cells = cells
            cellsWidth = tv.bounds.width
            tellDrawingFrames(in: tv)

            if let insertions {
                let wanted = NSRect(origin: .zero, size: NSSize(width: tv.bounds.width,
                                                                height: max(tv.bounds.height, 1)))
                if insertions.frame != wanted { insertions.frame = wanted }
                insertions.measure(MarkdownTextView.seams(in: tv, cells: cells))
                // The same boxes the gutter's brackets are drawn from, so
                // a drag down a bar picks up exactly what a drag down the
                // brackets does.
                insertions.cellSpans = brackets
                    .filter(\.isCell)
                    .map { (top: $0.top, bottom: $0.bottom, range: $0.range) }
            }
        }

        /// The caret never sits in a line nobody can see: it steps to the
        /// end of what is folded, or to the start of it when it was coming
        /// backwards.
        func snapCaretOutOfHiding(in tv: NSTextView) {
            let selection = tv.selectedRange()
            let snapped = Self.snap(selection, out: lastHidden, backwards: false)
            if snapped != selection { tv.setSelectedRange(snapped) }
        }

        static func snap(_ range: NSRange, out hidden: [NSRange], backwards: Bool) -> NSRange {
            guard range.length == 0 else { return range }
            for fold in hidden where fold.length > 0
                && range.location > fold.location && range.location < NSMaxRange(fold) {
                return NSRange(location: backwards ? fold.location : NSMaxRange(fold), length: 0)
            }
            return range
        }

        /// Moving the caret INTO a closed section puts it the other side of
        /// it instead — and into the hidden line of a drawing cell, to one
        /// end of it (`DrawingCells.snap`).
        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldRange: NSRange,
                      toCharacterRange newRange: NSRange) -> NSRange {
            let backwards = newRange.location < oldRange.location
            return snapped(Self.snap(newRange, out: lastHidden, backwards: backwards), in: textView,
                           backwards: backwards)
        }

        /// Out of the middle of a drawing cell's line, while it is hidden.
        private func snapped(_ range: NSRange, in textView: NSTextView, backwards: Bool) -> NSRange {
            guard let pane = textView as? PasteAwareTextView, pane.drawingStandIns else { return range }
            return DrawingCells.snap(range, lines: pane.drawingLines, backwards: backwards)
        }

        /// The same for a selection of SEVERAL ranges — and THIS is what
        /// lets there be one.
        ///
        /// A delegate that answers only the singular method above gets
        /// asked only that one, and AppKit then collapses every multiple
        /// selection down to a single range on its way in. The gutter's
        /// drag handed five cells over, `selectedRanges` took one, and one
        /// bracket lit (2026-09-20, with the offsets logged either side of
        /// the assignment to prove where they went). Nothing to do with
        /// the ranges being out of order, which is what the same symptom
        /// looked like when ⌘D's run first hit it.
        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRanges oldRanges: [NSValue],
                      toCharacterRanges newRanges: [NSValue]) -> [NSValue] {
            let backwards = (newRanges.first?.rangeValue.location ?? 0)
                < (oldRanges.first?.rangeValue.location ?? 0)
            return newRanges.map {
                NSValue(range: snapped(Self.snap($0.rangeValue, out: lastHidden, backwards: backwards), in: textView,
                                       backwards: backwards))
            }
        }

        /// No red underline in a drawing cell's line: it is a file's name,
        /// and under it is the drawing.
        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange)
            -> Int {
            let lines = (textView as? PasteAwareTextView)?.drawingLines ?? []
            return lines.contains { NSIntersectionRange($0, affectedCharRange).length > 0 } ? 0 : value
        }

        /// And an edit that would reach into one opens it first, rather than
        /// changing text nobody can see.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            if !lastHidden.isEmpty {
                let reach = affectedCharRange.length == 0
                    ? NSRange(location: max(0, affectedCharRange.location - 1), length: 1)
                    : affectedCharRange
                if let fold = lastHidden.first(where: { NSIntersectionRange($0, reach).length > 0 }) {
                    // Open whichever section owns that fold and let him try
                    // again, rather than changing text nobody can see.
                    if let section = NotebookOutline.sections(in: textView.string).first(where: {
                        collapsed.contains($0.key)
                            && $0.hiddenRange(in: (textView.string as NSString).length) == fold
                    }) {
                        parent.onToggleSection?(section.key)
                    }
                    return false
                }
            }
            // The edit that replaces held cells asks this of itself, and
            // goes through as made: it is whole cells, but trimmed of what
            // the note keeps at either end, so it can begin or end inside a
            // marker — and widened over one, the widening applied ITS edit
            // and refused this. A `#` typed over a section was lost and the
            // note began with two blank lines; a cell nobody held lost its
            // closing backtick (review, 2026-10-02).
            if replacingHeld { return true }
            if let replacementString,
               !typeOverHeldCells(textView, range: affectedCharRange, replacement: replacementString) {
                return false
            }
            return widenedEdit(textView, range: affectedCharRange, replacement: replacementString)
        }

        /// An edit over hidden markers takes them whole, and takes a pair
        /// together — see `MarkerDeletion`. True means "go ahead as asked",
        /// which is the answer for everything that is not such an edit.
        ///
        /// Deleting is not the only way to cut a pair in half: TYPING over
        /// such a selection and pasting into it do the same, and both went
        /// straight through while this only looked at empty replacements
        /// — "**bo" typed over in "**bold** here" left "xld** here". The
        /// widened range takes the replacement; the orphaned partner is
        /// always removed outright.
        ///
        /// Only while the markers ARE hidden: with the raw markdown
        /// showing, what is selected is what the eye saw, and half a `**`
        /// is then a fair thing to delete.
        private func widenedEdit(_ tv: NSTextView, range: NSRange,
                                 replacement: String?) -> Bool {
            guard hiding.isEnabled, range.length > 0,
                  let replacement, let storage = tv.textStorage else { return true }
            let ranges = MarkerDeletion.deletions(for: range, in: tv.string)
            guard ranges != [range] else { return true }
            let asked = MarkerDeletion.asked(range, in: ranges)
            let strings = ranges.map { $0 == asked ? replacement : "" }
            // In order (`shouldChangeText(over:)`): the deletions come back
            // to front, and "**bo" typed over in "**bold** here" threw
            // instead of leaving "xld here".
            guard tv.shouldChangeText(over: zip(ranges, strings).map { ($0, $1) }) else { return false }
            // Back to front, so an earlier range's location still means
            // what it meant when it was worked out.
            storage.beginEditing()
            for (range, string) in zip(ranges, strings) {
                storage.replaceCharacters(in: range, with: string)
            }
            storage.endEditing()
            tv.didChangeText()
            // After whatever went in, not before it.
            if let last = ranges.last {
                let typed = last == asked ? (replacement as NSString).length : 0
                tv.setSelectedRange(NSRange(location: last.location + typed, length: 0))
            }
            restyle(tv, force: true)
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.bridge.endOccurrenceRun()
            scheduleRestyle(tv)
            refreshBrackets(in: tv)
            if parent.text != tv.string { parent.text = tv.string }
            let caret = tv.selectedRange().location
            if MarkdownLinking.justTypedTrigger(in: tv.string, caret: caret) {
                parent.onLinkTrigger?(caret)
            }
        }

        /// Tab and Shift-Tab move a line in and out; Backspace does too, but
        /// only while the caret is still inside the line's prefix — past that
        /// it has to stay an ordinary backspace or the note cannot be edited.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                // Inside a fence, Tab is indentation: four spaces, which is
                // what the file should hold (Sean, 2026-09-20).
                if fenceTab(textView, outdent: false) { return true }
                parent.bridge.indent()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                if fenceTab(textView, outdent: true) { return true }
                parent.bridge.outdent()
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                // Whole cells held: the key takes them and closes the
                // stack behind them, which is what ⌃⌫ was for. A run of
                // characters inside one cell is not that and falls
                // through to the ordinary delete.
                if parent.bridge.deleteHeldCells() { return true }
                if parent.bridge.outdentForBackspace() { return true }
                // ⌫ AT THE VERY START OF A CELL DOES NOTHING (Sean,
                // 2026-10-02: "backspace at beginning does nothing"). Left
                // to NSTextView it took the blank line above and welded the
                // cell onto the one over it — the merge, which is ⌃M's and
                // nobody else's. True is "handled", and nothing was.
                return NotebookCells.atTheStartOfACell(textView.selectedRange(), in: textView.string)
            case #selector(NSResponder.deleteForward(_:)):
                // ⌦ the same, as the rendered page's column has it
                // (`MarkdownPreview.cellKey`). Left to NSTextView it took
                // the words of every held cell and left the blank lines
                // between them standing — the stack never closed.
                return parent.bridge.deleteHeldCells()
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                // ⇧↩ RUNS AN EVALUATION CELL, and means exactly what it
                // always meant anywhere else — which is why both
                // questions are asked before the key is taken.
                if EvaluationKeys.isRunNow, parent.bridge.evaluatesHere?() == true {
                    parent.bridge.runCell?()
                    return true
                }
                guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
                // Return on a list item carries the list on (Sean, 2026-09-18).
                return parent.bridge.continueList()
            case #selector(NSResponder.cancelOperation(_:)):
                // Escape lets go of cells HELD by their brackets, the way
                // the rendered page's column does (`MarkdownPreview.cellKey`).
                // NSTextView's own answer to Escape is word completion over
                // whatever is selected.
                return parent.bridge.letGoOfHeldCells()
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
                return armEndSeam(textView, up: selector == #selector(NSResponder.moveUp(_:)))
            default:
                return false
            }
        }

        /// ↑ OFF THE TOP OF THE FIRST CELL AND ↓ OFF THE BOTTOM OF THE LAST
        /// LAND ON THE BAR THERE, as they do off every other cell (Sean,
        /// 2026-09-20: "the mouse cursor and text cursor should both become
        /// horizontal between cells"; docs/FEATURES.md: "↓ off the bottom
        /// of a cell lands ON it"). Between two cells the caret gets there
        /// by itself — there is a blank line for it to land on, and
        /// `CellSeams.arm` reads it — but above the first cell there is no
        /// line at all, and under the last there is none unless the note
        /// ends in a newline: NSTextView put the caret at the very start or
        /// the very end of the note instead, an ordinary caret, so the bar
        /// above the first cell and under the last could only be clicked.
        /// The rendered page has always armed them (`armSeam(beside:)`).
        ///
        /// Armed first and then the caret moved, the way a click arms one,
        /// so `arm` keeps it. False — NSTextView's own move — anywhere but
        /// the first or last line of the page, and under a fence that
        /// never closed: the end of the note is in its code
        /// (`CellSeams.endsInCode`, the rule `CellSeams.arm` keeps for the
        /// empty line after a final newline), and what was typed at that
        /// bar went in as two more lines of the code.
        private func armEndSeam(_ textView: NSTextView, up: Bool) -> Bool {
            guard parent.seamsEnabled, let tv = textView as? PasteAwareTextView, tv.armedSeam == nil,
                  tv.selectedRanges.count == 1, tv.selectedRange().length == 0,
                  MarkdownTextView.isOnEndLine(of: tv, top: up),
                  up || !CellSeams.endsInCode(tv.string) else { return false }
            let seams = MarkdownTextView.seams(in: tv)
            guard let seam = up ? seams.first : seams.last else { return false }
            let offset = min(seam.offset, (tv.string as NSString).length)
            tv.armedSeam = offset
            tv.setSelectedRange(NSRange(location: offset, length: 0))
            tv.scrollRangeToVisible(tv.selectedRange())
            return true
        }

        /// Typing over SEVERAL held cells — or pasting over them — replaces
        /// them all with one cell, the rendered page's rule, through
        /// `CellCommands.typing`. NSTextView left to itself replaces only
        /// the first of the ranges and keeps the rest. One range is left to
        /// NSTextView, which already does the same thing with it.
        ///
        /// Only an edit OVER THE FIRST SELECTED RANGE is the user's: that
        /// is the one range NSTextView hands over for a keystroke or a
        /// paste. A whole-cell command moving or copying the same held
        /// cells asks about its own spans, and must go through as made.
        ///
        /// True: NSTextView goes ahead as asked. False: the edit was made
        /// here and NSTextView's is not wanted.
        private func typeOverHeldCells(_ tv: NSTextView, range: NSRange, replacement: String) -> Bool {
            guard tv.selectedRanges.count > 1, tv.selectedRanges.first?.rangeValue == range else { return true }
            let cells = MarkdownParser.positioned(from: tv.string).map(\.range)
            let held = CellSelection.picked(cells: cells, selection: tv.selectedRanges.map(\.rangeValue))
            guard let edit = CellCommands.typing(replacement, over: held, in: tv.string) else { return true }
            replacingHeld = true
            defer { replacingHeld = false }
            apply(edit, in: tv)
            return false
        }

        /// True while that edit is going in: it asks `shouldChangeText`
        /// itself, with the held ranges still selected, and the delegate
        /// lets it through untouched.
        private var replacingHeld = false
    }
}

/// The text view itself, with two things NSTextView will not do on its own:
/// a pasted picture goes on the drawing layer instead of being dropped on the
/// floor (a plain-text view ignores images), and a click says so, so the
/// objects on that layer can let go of their selection.
class PasteAwareTextView: NSTextView {
    var onPasteImage: ((NSPasteboard) -> Bool)?
    var onClick: (() -> Void)?
    /// The general pasteboard, except in a test, which brings its own.
    var pasteboard: NSPasteboard = .general
    /// The seam between two cells the caret is sitting in: nothing has
    /// been written there, and the first character typed opens a cell
    /// first (Sean, 2026-09-20: "if i start typing it inserts a cell
    /// immediately after the cursor/line which disappear").
    var armedSeam: Int? {
        didSet {
            guard armedSeam != oldValue else { return }
            // The line drawn across the page IS the cursor while a seam
            // is armed (Sean, 2026-09-20: "the horizontal line appears
            // and that is where the cursor is"), so the caret is not
            // drawn as well — two cursors is what he was looking at.
            insertionPointColor = armedSeam == nil ? caretColour : .clear
            // A seam armed afresh is plain text, always (Sean,
            // 2026-09-19: "default is always just text"). The choice is
            // the bar's, so it goes when the bar moves or goes out, and
            // the + sets it again afterwards.
            armedType = .text
            onArmChanged?(armedSeam)
        }
    }
    /// What the + on the bar chose: the kind of cell the next thing typed
    /// into this seam becomes (Sean, 2026-09-20: "pressing the + button on
    /// that bar should bring up the list of style types that the next
    /// input will create a cell the type of").
    var armedType: CellTypes.Kind = .text
    /// The caret's own colour, read once when the editor is built, so it
    /// can come back when the seam goes.
    var caretColour: NSColor = .textColor
    /// The layer that draws the bar, told of every change and not only of
    /// the disarms: the caret arms a seam too now, and a bar the layer was
    /// never told about would be a cursor nobody can see.
    var onArmChanged: ((Int?) -> Void)?

    // MARK: - The caret in a drawing cell

    /// The note's drawing cells' lines, as the layout reads them after
    /// every edit (`CellLines`) — none in a text view that does not lay
    /// drawing cells out, such as a rendered page's open block.
    var drawingLines: [NSRange] {
        (layoutManager as? FoldingLayoutManager)?.drawings.lines.map(\.range) ?? []
    }

    /// The drawing cell the caret is in, by its line — with the markers
    /// shown as well as hidden: a command that names a kind of cell must
    /// never write its marker onto a drawing's line either way.
    var drawingCellAtCaret: NSRange? { DrawingCells.cell(atCaret: selectedRange(), lines: drawingLines) }

    /// Whether the KEYS stand in for the bar under a drawing cell — while
    /// its line is hidden (`restyle`). Shown, the line is ordinary text and
    /// typed in as text.
    var drawingStandIns = false

    /// A DRAWING CELL TAKES NO CHARACTERS (docs: the caret key table,
    /// `DrawingCells.Key`): for anything that writes, the caret in one
    /// stands in for the bar under it. Nil whenever a bar is the cursor
    /// already — the bar above a cell parks the caret at the cell's start.
    private var standingIn: NSRange? {
        drawingStandIns && armedSeam == nil ? drawingCellAtCaret : nil
    }

    /// The bar under a drawing cell, armed — the cell it opens is the next
    /// thing done.
    private func armBar(under line: NSRange) {
        armedSeam = DrawingCells.seamAfter(line, in: string)
    }

    /// NO CARET IN A DRAWING CELL while its line is hidden: the line's
    /// fragment is as tall as the drawing under it, and a caret that tall
    /// down the page is not a cursor anybody asked for — the lit outline
    /// and the heavy bracket are the cursor there. With the line shown it
    /// is typed in, so its caret is one line of it, at the top.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard drawingCellAtCaret != nil else { return super.drawInsertionPoint(in: rect, color: color, turnedOn: flag) }
        if drawingStandIns { return super.drawInsertionPoint(in: rect, color: .clear, turnedOn: flag) }
        super.drawInsertionPoint(in: NSRect(x: rect.minX, y: rect.minY, width: rect.width,
                                            height: min(rect.height, MarkdownTextView.lineHeight)),
                                 color: color, turnedOn: flag)
    }

    /// Open the cell an armed seam stands for, if one is armed. The offset
    /// is taken and the bar put out BEFORE the note is touched, so the
    /// insertion that opens the cell is not read as a second arming.
    @discardableResult
    private func openArmedSeam() -> Bool {
        // The kind is read before the bar goes out: letting go of the seam
        // is what puts it back to plain text.
        openArmedSeam(as: armedType)
    }

    /// The same, for a KIND named by the thing that asked — a button on the
    /// bar, a Format command — rather than by the + on the seam.
    @discardableResult
    func openArmedSeam(as type: CellTypes.Kind) -> Bool {
        guard let offset = armedSeam else { return false }
        armedSeam = nil
        MarkdownTextView.openSeam(at: offset, as: type, in: self)
        return true
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // A range the caller NAMED means that range. Typing arrives with
        // {NSNotFound, 0} — AppKit's way of saying "wherever the caret is"
        // — and where the caret is, is the seam; but this is the same
        // funnel `EditorBridge.insert(_:belowDocumentY:)` puts the words
        // read off a picture through, and those go under the picture, not
        // at a bar somebody armed at the top of the note ten minutes ago.
        // The bar goes out, because the offset it held has just moved.
        guard replacementRange.location == NSNotFound else {
            armedSeam = nil
            return super.insertText(string, replacementRange: replacementRange)
        }
        // A character typed in a drawing cell: a text cell after it, with
        // the character in it.
        if let line = standingIn { armBar(under: line) }
        guard openArmedSeam() else {
            return super.insertText(string, replacementRange: replacementRange)
        }
        // Opening the cell moved everything after the seam along, so the
        // range the event arrived with means nothing now: what was typed
        // goes where the caret was left, between the new blank lines.
        super.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// A key while a seam is armed — what the rendered page's seam does
    /// with the same key, read through `CellSeams.command`. Return opens
    /// the empty cell there; ↑ and ↓ walk into the cell above or below,
    /// and at the two ends of the note, where there is none, the bar
    /// stays; everything else — Escape, a delete, Tab, Page Down — puts
    /// the bar out and leaves the note exactly as it was, because clicking
    /// about the page must never leave an empty cell behind, and a key
    /// pressed at a bar must never edit the cell beside it. A key that
    /// only moves, selects or scrolls then does that (`CellSeams.handsOn`).
    override func doCommand(by selector: Selector) {
        if let line = standingIn {
            switch DrawingCells.key(command: selector) {
            case .empty:
                armBar(under: line)
                openArmedSeam()
                return
            case .hold:
                // Held whole, its bracket with it; ⌫ again takes it
                // (`EditorBridge.deleteHeldCells`).
                setSelectedRange(line)
                return
            case .step(let up):
                // The bar first, so the caret parked at its offset reads
                // as the bar and not as a caret in a cell (`CellSeams.arm`).
                let offset = up ? line.location : DrawingCells.seamAfter(line, in: string)
                armedSeam = offset
                setSelectedRange(NSRange(location: offset, length: 0))
                return
            case .write, .leave, .pass:
                break
            }
        }
        guard let offset = armedSeam else { return super.doCommand(by: selector) }
        let type = armedType
        let meaning = CellSeams.command(NSStringFromSelector(selector))
        switch meaning {
        case .empty, .write:
            armedSeam = nil
            MarkdownTextView.openSeam(at: offset, as: type, in: self)
        case .step(let up):
            guard let caret = CellSeams.step(from: offset, up: up, in: string) else { return }
            armedSeam = nil
            setSelectedRange(NSRange(location: caret, length: 0))
            scrollRangeToVisible(selectedRange())
        case .disarm, .pass:
            armedSeam = nil
            // THE CARET IN A CELL, NEVER ON THE LINE THE BAR STANDS FOR: at
            // the start of the cell below, where a click on the bar leaves
            // it, and under the last cell at the end of that one. Arrowed
            // onto the bar it sat on the blank line between two cells, and
            // once the bar was out the next character went in on that line
            // and welded the cells either side into one paragraph — the
            // merge arming exists to stop.
            let caret = CellSeams.step(from: offset, up: false, in: string)
                ?? CellSeams.step(from: offset, up: true, in: string) ?? offset
            // Set EVEN WHERE IT ALREADY IS. A click parks the caret right
            // there, so putting the bar away moved nothing; skipping the
            // set when nothing moved meant no selection change, and the
            // brackets and the marker hiding — which hear that the bar has
            // gone only through one — went on answering for it: no bracket
            // lit, and "## Notes" kept its hashes hidden with the caret in
            // front of them (review, 2026-10-02). NSTextView announces an
            // unchanged selection all the same (measured, 2026-10-02).
            setSelectedRange(NSRange(location: min(caret, (string as NSString).length), length: 0))
            // From that caret, so a key that moves starts in a cell.
            if meaning == .pass, CellSeams.handsOn(NSStringFromSelector(selector)) {
                super.doCommand(by: selector)
            }
        }
    }

    /// The layer that knows where the seams are. It is this view's own
    /// subview, so there is nothing to keep in step: the text view asks
    /// it rather than holding a second copy of the geometry.
    private var seamLayer: CellInsertions? { subviews.compactMap { $0 as? CellInsertions }.first }

    /// What the seam layer wants the pointer to be at a point of this
    /// view, and nil where it wants nothing and the words have it —
    /// which is everywhere, while the pen is up and the layer is
    /// hidden.
    ///
    /// ASKED rather than worked out here. This view used to decide for
    /// itself that a seam means the I-beam on its side, which was the
    /// same answer as the layer's right up until the + wanted a hand;
    /// two views answering one point separately is a disagreement one
    /// event wide, and the event that arrives last is the one the
    /// pointer gets.
    private func seamCursor(at point: NSPoint) -> NSCursor? {
        guard let seamLayer else { return nil }
        return seamLayer.cursor(at: convert(point, to: seamLayer))
    }

    /// The bracket column, which this view draws no text in and answers
    /// no cursor for of its own — `NotebookGutter` is the only thing that
    /// does, and it says hand over a bracket and arrow beside one.
    ///
    /// ONLY WHERE THERE IS A GUTTER. An open block on the rendered page is
    /// a `BlockTextView`, which is one of these with no gutter and its
    /// words right out to its edge; read as a column, its last 22 points
    /// were the arrow over words, and a block narrower than that was
    /// nothing else (`NoGutterCursorTests`).
    private func inGutter(_ point: NSPoint) -> Bool {
        gutterLayer != nil && point.x >= max(0, bounds.width - NotebookGutter.width)
    }

    /// The gutter, asked the way the seam layer is: it is this view's own
    /// subview, so there is nothing to keep in step.
    private var gutterLayer: NotebookGutter? { subviews.compactMap { $0 as? NotebookGutter }.first }

    /// Shown over the text instead of the I-beam while set (the pen's pencil).
    var cursorOverride: NSCursor? {
        didSet {
            guard cursorOverride !== oldValue else { return }
            updateTrackingAreas()
            window?.invalidateCursorRects(for: self)
        }
    }

    /// While the pen is up the text view does not track the mouse at all:
    /// NSTextView's own tracking areas are what hand it the moves it
    /// answers with the I-beam, and overriding those handlers still let an
    /// I-beam through now and then (Sean, 2026-09-18: "the text selection
    /// cursor keeps popping up randomly"). No tracking area, no move, no
    /// I-beam. They come back with the pen down. (A cursorUpdate is not
    /// the tracking area's owner's: AppKit sends it to whatever the
    /// window's hit test finds at the pointer — AGENTS.md, the eighth
    /// cause — which under the pen is the drawing layer's host, and its
    /// monitor swallows it.)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if cursorOverride != nil {
            trackingAreas.forEach(removeTrackingArea)
            return
        }
        // Rebuilding them is itself one of the moments the I-beam comes
        // back: NSTextView makes its tracking areas again on every
        // scroll and every relayout, and the pointer has not moved, so
        // nothing else will put the bar's cursor back until it does
        // (Sean, 2026-09-20: "it does flicker sometimes back to a
        // cursor").
        //
        // Only for a pointer that is really on the page, though. This is
        // asked of the WINDOW, which answers wherever the pointer is —
        // the sidebar, the toolbar, off the screen — and `NSCursor.set()`
        // is global, so a cursor set from here for a pointer somewhere
        // else stays on it: nothing over there installs one of its own to
        // take it back. VISIBLE rect and not `bounds`, which is the check
        // the pen can afford three lines of its own away: this view is
        // the scroll view's document view and is taller than the pane, so
        // the formatting bar ABOVE it converts to a y inside the note as
        // soon as the note is scrolled.
        guard let window else { return }
        let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(pointer),
              layerCursor(at: window.mouseLocationOutsideOfEventStream) == nil else { return }
        seamCursor(at: pointer)?.set()
    }

    /// The pointer over the text — and over the spaces between the cells,
    /// where it lies on its side.
    ///
    /// NOT super's one I-beam over the whole view with the seam layer's
    /// rects laid on top of it: two rects over one point and AppKit
    /// picks which of them wins, and it kept picking the I-beam (Sean,
    /// 2026-09-20: "the mouse cursor should reliably be horizontal
    /// between the cells"). The view is cut into bands instead — a
    /// cell's stretch takes the upright I-beam, a seam's the one on its
    /// side — so no rect of this view's ever claims a seam. The bracket
    /// column keeps the upright one, as it always had, because the seams
    /// stop short of it.
    override func resetCursorRects() {
        if let cursorOverride {
            addCursorRect(visibleRect, cursor: cursorOverride)
            return
        }
        let seams = seamLayer?.pointerSeams ?? []
        guard !seams.isEmpty else { return super.resetCursorRects() }
        let page = max(0, bounds.width - NotebookGutter.width)
        // And the + is a button, so its patch of the bar is the hand —
        // cut out of the seam's own rect and not laid over it, because
        // this view and the layer above it disagreeing over one point
        // is AppKit's choice to make and it does not make ours.
        let plus = seamLayer?.pointerPlus ?? .null
        for band in CellSeams.bands(seams: seams, pageTop: bounds.minY, pageBottom: bounds.maxY) {
            let height = band.bottom - band.top
            guard band.horizontal else {
                // THE GUTTER IS NOT THE TEXT VIEW'S TO ANSWER FOR. This
                // rect used to run the full width, straight under the
                // bracket column — so the pointer over a bracket got the
                // hand from `NotebookGutter.mouseMoved` while it was
                // moving and this I-beam whenever it stopped, scrolled or
                // the note reflowed and the rects were rebuilt. Two
                // mechanisms over one point, which is the trap this file
                // already knows by name (Sean, 2026-09-22: "the mouse
                // cursor behavior should be the same in wysiwyg and
                // markdown mode" — the rendered page has one answer
                // there and always did).
                addCursorRect(NSRect(x: bounds.minX, y: band.top, width: page, height: height),
                              cursor: .iBeam)
                continue
            }
            let strip = NSRect(x: bounds.minX, y: band.top, width: page, height: height)
            for piece in CellSeams.cut(strip, around: plus) {
                addCursorRect(piece, cursor: .iBeamCursorForVerticalLayout)
            }
            let onPlus = plus.intersection(strip)
            if !onPlus.isNull, !onPlus.isEmpty { addCursorRect(onPlus, cursor: .pointingHand) }
        }
    }

    /// What a cursorUpdate puts up at a point of this view, and nil for
    /// the words — NSTextView's own I-beam. One answer per region, each
    /// from that region's own reader: the pen's override, the seam
    /// layer's over a seam, the GUTTER'S over the bracket column.
    ///
    /// The seams: this view's tracking areas hand it the moves wherever
    /// the pointer is in it — over the seam layer as much as over the
    /// words — and answering them with the I-beam put the upright cursor
    /// back a moment after the layer had set the bar's. The pencil beat
    /// that by taking the tracking areas away (AGENTS.md: "The pencil
    /// cursor wins by swallowing cursorUpdate events"), which a seam
    /// cannot do because the text either side of it still wants its
    /// I-beam. So the text view asks the layer and says the same thing.
    ///
    /// The gutter: a cursorUpdate does not go to the view whose tracking
    /// area made it. AppKit hit-tests the window at the pointer and sends
    /// it to whatever answers (AGENTS.md: the eighth cause) — in the
    /// column that is the gutter itself, whose `hitTest` takes the whole
    /// column while a cursorUpdate is current, since this view's own
    /// `hitTest` is nil in its inset margin. Should one come HERE in the
    /// column all the same, the gutter's reader answers it: returning
    /// without a word, as this did, leaves nobody answering at all.
    func cursorForUpdate(at point: NSPoint) -> NSCursor? {
        if let cursorOverride { return cursorOverride }
        if inGutter(point), let gutter = gutterLayer { return gutter.cursor(at: convert(point, to: gutter)) }
        return seamCursor(at: point)
    }

    /// At the POINTER and not at the event — see `routedPoint(of:)`.
    override func cursorUpdate(with event: NSEvent) {
        guard let cursor = cursorForUpdate(at: routedPoint(of: event)) else {
            return super.cursorUpdate(with: event)
        }
        cursor.set()
    }

    /// The cursor a drawing layer up over this point of the window is
    /// showing — the ⌘ crosshair, a hand on an object, the pencil over a
    /// block of the rendered page — and nil where none is. While one is,
    /// the pointer and the press are the canvas's, so this view's moves
    /// give the layer's answer rather than a second one of their own
    /// (the gutter's `mouseMoved` says why that is a flicker).
    private func layerCursor(at windowPoint: NSPoint) -> NSCursor? {
        CursorLayer.CursorRectView.claim(at: windowPoint, in: window)
    }

    override func mouseMoved(with event: NSEvent) {
        if let cursor = cursorOverride ?? layerCursor(at: event.locationInWindow) { return cursor.set() }
        // ASK FIRST, and do not call super when the answer is ours.
        // NSTextView's own mouseMoved sets the I-beam, so calling it
        // before setting the bar's cursor set TWO cursors per event —
        // upright, then horizontal — and at the rate a moving pointer
        // generates events the first of them is on screen long enough to
        // see. It is not an edge case and does not depend on where the
        // pointer is in the seam, which is why it survived pixel-aligning
        // the edges and the stickiness: Sean, 2026-09-21, "even side to
        // side it flickers".
        let point = convert(event.locationInWindow, from: nil)
        if inGutter(point) { return }
        if let cursor = seamCursor(at: point) {
            return cursor.set()
        }
        super.mouseMoved(with: event)
    }

    /// NSTextView answers a mouseEntered with the I-beam as well, and
    /// AppKit synthesises one whenever the tracking areas are rebuilt
    /// under a pointer that never moved — so the bar was left with an
    /// upright cursor on it until it was nudged.
    override func mouseEntered(with event: NSEvent) {
        if let cursor = cursorOverride ?? layerCursor(at: event.locationInWindow) { return cursor.set() }
        let point = convert(event.locationInWindow, from: nil)
        if inGutter(point) { return }
        if let cursor = seamCursor(at: point) {
            return cursor.set()
        }
        super.mouseEntered(with: event)
    }

    /// Paste stays ENABLED when the pasteboard holds a picture. A plain-text
    /// NSTextView tells the Edit menu that Paste is disabled unless there is
    /// text to paste, and a disabled item swallows ⌘V before `paste(_:)` is
    /// ever called — which is why a screenshot could not be pasted while
    /// copied text could (Sean, three times, 2026-09-18; the paste log
    /// showed ⌘V handed to the text view and nothing after it).
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSText.paste(_:)) || item.action == #selector(NSTextView.pasteAsPlainText(_:)),
           onPasteImage != nil, Self.holdsPicture(pasteboard) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    /// Image data, or a file that is an image.
    static func holdsPicture(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: [.tiff, .png]) != nil { return true }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.contains { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
    }

    override func paste(_ sender: Any?) {
        let taken = onPasteImage?(pasteboard) == true
        DebugLog.write("paste: in \(type(of: self)) handler=\(onPasteImage == nil ? "nil" : "set") taken=\(taken) types=\((pasteboard.types ?? []).map(\.rawValue).joined(separator: ","))")
        if taken { return }
        // Text pasted into an armed seam is a new cell, the same as a
        // character typed there. A picture is not — it floats over the
        // note, and opening a cell for it would leave an empty one. Pasted
        // in a drawing cell, it is a cell after the drawing.
        if let line = standingIn { armBar(under: line) }
        openArmedSeam()
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        let taken = onPasteImage?(pasteboard) == true
        DebugLog.write("pasteAsPlainText: in \(type(of: self)) handler=\(onPasteImage == nil ? "nil" : "set") taken=\(taken)")
        if taken { return }
        if let line = standingIn { armBar(under: line) }
        openArmedSeam()
        super.pasteAsPlainText(sender)
    }

    override func mouseDown(with event: NSEvent) {
        // A click anywhere in the text puts the insertion bar out.
        armedSeam = nil
        onClick?()
        super.mouseDown(with: event)
    }
}
