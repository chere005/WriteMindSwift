import AppKit
import SwiftUI

/// The rendered note — and, since it is where Sean does the reading, where he
/// writes too.
///
/// Click a block and it becomes a real text view holding THAT BLOCK'S
/// markdown, styled as it is typed, with the whole toolbar live on it: bold,
/// the heading ladder, lists, quotes, indentation, the text style, maths.
/// Return starts the next block, ⌫ in an empty one takes it away, the arrows
/// walk between them, and the line that appears between two blocks adds one
/// wherever it is clicked. Only the block being edited is ever rewritten —
/// the whole document is never converted from rich text back to markdown,
/// which is the lossy step every WYSIWYG markdown editor gets wrong.
struct MarkdownPreview: View {
    @Binding var markdown: String
    /// A link to another note, as written in the markdown ("Other.md#wm-1234").
    var onFollow: ((String) -> Bool)?
    var editable: Bool = true
    /// What the toolbar talks through. The block being edited hands itself to
    /// it, which is what makes the buttons work on this side.
    var bridge: EditorBridge = EditorBridge()
    /// True while a block is open for editing — the bar uses it to decide
    /// whether its buttons do anything.
    var onEditingChanged: ((Bool) -> Void)?
    /// How far the preview has scrolled, so the drawing layer can scroll
    /// with it and a picture stays beside the block it was put next to.
    var onScroll: ((CGFloat) -> Void)?
    /// A click landed on this page rather than on the drawing layer over
    /// it, so whatever is picked up there is let go (Sean, 2026-09-21:
    /// "click away from selected object should deselect"). The source
    /// pane has had this since the text view's own `onClick`; this side
    /// never did, so an object stayed picked up whatever was clicked.
    var onClick: (() -> Void)?
    /// The place at the top of the window — the cell and how far into it
    /// (`CellPlace`) — reported as the page scrolls, and put back when the
    /// page appears, so the two modes show the same place (Sean,
    /// 2026-09-19: "positions stay the same in markdown and wysiwyg
    /// mode"; 2026-10-02: "preserve the position of things as much as
    /// possible between markdown and wysiwyg mode").
    var onTopCell: ((CellPlace) -> Void)?
    var topCell: CellPlace = .top
    /// The cells' boxes on this page, each time they are measured again —
    /// what the drawing layer is shown through (`PaneMapping`).
    var onLayout: (([CellSeams.Box]) -> Void)?
    /// The notebook sections that are folded away — the same set the
    /// markdown editor uses, so the notebook is the same on both sides.
    var collapsed: Set<String> = []
    var onToggleSection: ((String) -> Void)?
    /// False while the pen, the arrow tool or a placement is up: the
    /// pencil owns the note pane then (Sean, 2026-09-20: "cursor only
    /// becomes a pen in the notes pane in drawing mode!!!!!"), so the
    /// pointer is never horizontal and no seam can be armed. The same
    /// switch the markdown pane has, off the same expression.
    var seamsEnabled: Bool = true
    /// What a cell runs as, picked from the badge at its left. There is
    /// no run control here: ⇧↩ runs the cell the caret is in, and a
    /// button for a thing the keyboard already does was the ▶ Sean asked
    /// to be rid of (2026-09-22).
    var onPickEvaluator: ((Evaluator, NSRange) -> Void)?
    /// Which cell is running, by the offset it starts at.
    var runningCell: Int?
    /// The note's drawing cells, as this page paints them in their rows
    /// (`NoteStore.cellLooks`).
    var drawingCells = DrawingCellsShown()
    /// Where the drawing cells are on this page, each time one has moved
    /// (`CellFrame.moved`) — what the drawing layer draws into them by.
    var onDrawingFrames: (([CellFrame]) -> Void)?
    /// The drawing cell the cursor is in, or nil, each time that changes —
    /// its grip is the layer's to show.
    var onDrawingCaret: ((UUID?) -> Void)?

    @State private var rowHeights: [Int: CGFloat] = [:]
    /// The fence lines of the code block being typed in. The editor shows
    /// the code alone; these go back round it on every keystroke.
    @State private var fence: Fence?

    struct Fence: Equatable {
        var open: String
        var close: String
        var language: CodeLanguage { CodeLanguage.colouring(fence: MarkdownFormatting.fenceLanguage(open)) ?? .plain }
    }

    /// WHERE THE CARET IS ON THIS PAGE, and there is only one of it.
    ///
    /// A cell open as its markdown in one text view, or ONE REMINDER'S
    /// WORDS with its box still a live checkbox beside it (Sean,
    /// 2026-09-21: "when modifying a checklist.. the checkboxes remain in
    /// tact and just the text part of the list becomes editable, one at a
    /// time"). Both open at once is what this makes unrepresentable:
    /// `editingRange` below is a window onto it, so every one of the
    /// sixteen places that already wrote `editingRange = nil` closes an
    /// open reminder too, without a line of change at any of them.
    enum Cursor: Equatable {
        case none
        case cell(NSRange)
        /// The range of the item's WORDS, not of its line.
        case item(NSRange)
        /// A DRAWING CELL, by its line: the cell itself is the cursor — lit,
        /// its bracket heavy, the keys its own (`drawingKey`) — and no
        /// editor is ever opened on its line, which is the name of its
        /// file: an editor on it is a way to break it.
        case drawing(NSRange)
    }

    @State private var cursor: Cursor = .none

    /// The cell open for typing — nil while a reminder is, because a
    /// reminder is not a cell and the block still renders around it.
    private var editingRange: NSRange? {
        get { if case .cell(let range) = cursor { return range }; return nil }
        nonmutating set { cursor = newValue.map { .cell($0) } ?? .none }
    }

    /// The reminder open for typing, by the range of its words.
    private var editingItem: NSRange? {
        get { if case .item(let range) = cursor { return range }; return nil }
        nonmutating set {
            if let newValue { cursor = .item(newValue) }
            else if case .item = cursor { cursor = .none }
        }
    }

    /// The CELL something is open in, whichever kind of cursor it is.
    /// Every whole-cell command asks this: with a reminder open, ⌃⌫ and
    /// Duplicate and the Format menu must still mean the checklist, not
    /// the note's first cell (which is what `items.first` gives).
    private var openCell: NSRange? {
        switch cursor {
        case .none: return nil
        case .cell(let range), .drawing(let range): return range
        case .item(let range):
            return NotebookCells.block(containing: range.location, in: markdown)?.range
        }
    }

    /// Where the caret is in the NOTE — the open thing's start plus how
    /// far into its text view the caret sits. The same sum for a cell and
    /// for a reminder, which is why it is written once.
    private var caretInNote: Int {
        let inside = bridge.textView?.selectedRange().location ?? 0
        switch cursor {
        case .none: return 0
        case .cell(let range), .item(let range): return range.location + inside
        case .drawing(let range): return NSMaxRange(range)
        }
    }
    /// The cells held by their brackets — several of them, discontiguous,
    /// and none of them open for typing (Sean, 2026-09-20: "fix selecting
    /// multiple cells by clicking and dragging, shift clicking, or cmd
    /// clicking").
    ///
    /// Separate from `editingRange`, which is the ONE cell open for typing:
    /// a cell you are in and a cell you are holding are different things,
    /// and the rendered page has no text view to keep the second in the way
    /// the markdown pane keeps it in `tv.selectedRanges`.
    @State private var selectedCells: [NSRange] = []
    /// The cells a click on the bracket under the pointer would take,
    /// washed faintly while it is there.
    @State private var promisedCells: [NSRange] = []
    @State private var draft = ""
    /// The words of the one reminder open for typing.
    @State private var itemDraft = ""
    @State private var focusToken = 0
    /// Where the caret lands in whatever opens next.
    @State private var caret: BlockEditor.Caret = .end
    /// WHERE THE POINTER IS ON THIS PAGE — a seam, or a cell's words.
    ///
    /// One reader for both, because the two hand the cursor to each other:
    /// the place the pointer has ARRIVED at is often told before the place
    /// it left, so leaving A took back the cursor B had just set. Each
    /// hover asks "was it me" against this before it hands anything back
    /// (the seams' own `ours`, generalised to the rest of the page).
    enum Spot: Hashable {
        case seam(SeamID)
        /// A rendered cell, by the offset that identifies its row.
        case cell(Int)
    }

    @State private var hovered: Spot?
    /// The cell a drag from a bar is growing from, once it has started —
    /// settled by the first movement and then kept, so dragging back past
    /// the start does not swap ends.
    @State private var seamDragAnchor: NSRange?
    /// What this page's seams last put on the pointer, so one of them
    /// can tell its own cursor from the hand a bracket set on the way
    /// past. Every one of them writes it: which seam put it up is
    /// `hoveredSeam`'s question, and this one is only "is it still
    /// there".
    @State private var seamCursor: NSCursor?
    /// The seam the bar is sitting in, waiting to be typed into. Nothing
    /// is written there until a key says so (Sean, 2026-09-20: "when
    /// clicking in between, the horizontal line appears and that is where
    /// the cursor is"), so clicking about the page leaves no empty cells
    /// behind.
    @State private var armedSeam: SeamID?
    /// What the + on that bar chose: the kind of cell the next thing typed
    /// into it becomes (Sean, 2026-09-20: "pressing the + button on that
    /// bar should bring up the list of style types that the next input
    /// will create a cell the type of"). It rides with the arming and no
    /// longer — `arm` puts it back to plain text every time.
    @State private var armedType: CellTypes.Kind = .text
    /// The armed seam holds the keyboard, because the bar IS the cursor
    /// and there is no text view to hold it on this side.
    @FocusState private var focusedSeam: SeamID?
    /// And a drawing cell that is the cursor holds it, by its row, for the
    /// same reason.
    @FocusState private var focusedDrawing: Int?
    /// How wide the page's content is: a drawing cell is shown in the
    /// column this leaves, and its frame for the layer has to say so.
    @State private var pageWidth: CGFloat = 0
    /// The drawing cells' frames as last told.
    @State private var toldFrames: [CellFrame] = []
    /// A seam the page has to bring into view — the one under an answer a
    /// run has just written, so the bar is somewhere the eye can find.
    @State private var bringIntoView: SeamRow?
    /// How far the page has been scrolled, in the document's own
    /// coordinates — the same number the drawing layer works in.
    @State private var scrolled: CGFloat = 0
    /// The place the page is to open at, until its rows have been measured
    /// and it has been scrolled there. Nothing is reported as the top of
    /// the window meanwhile: the page is at its own top, and saying so
    /// would overwrite the place it was asked to open at.
    @State private var opening: CellPlace?
    /// Where that place is on the page: a mark is put there, and the
    /// page's scroll view is scrolled to put the mark at the top.
    @State private var openingY: CGFloat = 0
    @State private var openingMark = PageMark.Holder()

    /// What a seam is called when the page is scrolled to it. The rows
    /// are identified by their own offsets, which a seam has no unique
    /// one of — two seams can share an offset, and the tail seam's is the
    /// note's length.
    private struct SeamRow: Hashable { var index: Int }
    /// And the bracket column holds it while cells are held, for the same
    /// reason: typing over a selection has to reach somewhere.
    @FocusState private var focusedBrackets: Bool
    /// How tall the window on the page is: the tail seam runs to the
    /// bottom of it, so everything under the last cell can be typed in.
    @State private var pageHeight: CGFloat = 0

    /// WHICH seam — its place down the page, and the offset a cell would
    /// be opened at.
    ///
    /// Not the offset alone: an empty cell at the end of the note has the
    /// zero length that makes the seam above it and the tail seam under it
    /// carry the identical offset, and everything offset-keyed then
    /// answered for both — two bars drawn, two views bound to the same
    /// focus. The index is what tells them apart.
    struct SeamID: Hashable {
        var index: Int
        var offset: Int
    }

    private static let space = "WriteMindPreview"
    /// The air above the first cell and below the last. Not private: the
    /// PDF export lays the same column out on paper and has to start it in
    /// the same place, or the drawing's objects would sit a margin off the
    /// text they were put beside.
    static let topInset: CGFloat = 22
    /// The page's left and right margin, the same both sides.
    static let sideInset: CGFloat = 28

    /// Where this page's words start and end across a pane `width` wide.
    static func column(width: CGFloat) -> PaneMapping.Column {
        PaneMapping.Column(left: sideInset, right: width - sideInset)
    }
    /// The ONE gap between two cells — the same four points everywhere,
    /// whatever the cells are (Sean, 2026-09-19: "gaps should just be a
    /// small fixed padding, not some varying amount"). No block adds
    /// padding of its own on top of it.
    ///
    /// Thin on purpose: cells sit against each
    /// other the way a notebook's do (Sean, 2026-09-19: "there shouldn't
    /// be gaps between cells"), and this is only enough to put the pointer
    /// in — the insertion line itself is drawn over the seam rather than
    /// inside a band of empty page.
    ///
    /// It is still part of the stack, so the brackets and the picture
    /// bands count it — leaving it out put every bracket a strip higher
    /// than its cell, and the error piled up down the page (Sean,
    /// 2026-09-19: "notebook bar placement bugs").
    static let gapHeight: CGFloat = 8

    /// THE AIR BETWEEN TWO CELLS ON THE PAGE, which is the other pane's
    /// rhythm and not this one's own number.
    ///
    /// Sean, 2026-09-22: "make the spacing more uniform.. it's ok on
    /// markdown mode but in rendered mode things get scrunched
    /// together". The source pane puts a BLANK LINE OF THE NOTE between
    /// two cells and the spacing that goes either side of it; this page
    /// was stacking them `gapHeight` apart — 8 points against 26 — so
    /// every boundary on it was a third of the rhythm of the same note
    /// in the other mode, and a page of short cells read as one grey
    /// block.
    ///
    /// It is a SECOND constant because `gapHeight` was doing two jobs:
    /// the air between cells AND the floor under a seam
    /// (`CellSeams.seams(minimum:)`), which is only "enough to put the
    /// pointer in". Raising the one number moved the floor, the source
    /// pane's own paragraph spacing and the landing place of every
    /// pasted picture with it, which is why the two panes had never been
    /// squared up.
    static let blockGap: CGFloat = MarkdownTextView.lineHeight
        + MarkdownTextView.paragraphStyle.lineSpacing

    /// The air above and below a rendered code block: HALF THE TEXT IT
    /// HOLDS, so the box hugs the code and comes out a little bigger
    /// than it (Sean, 2026-09-22: "there shouldn't be so much padding in
    /// the cells themselves, it should be about the size of the text a
    /// little bigger").
    ///
    /// It used to be ONE SOURCE LINE, which is what the ``` line it
    /// stands in for takes in the other pane, so that the two sides laid
    /// a code cell out to exactly the same height. That contract is
    /// deliberately given up here: a full line of air each side made a
    /// one-line cell three and a half lines tall, which is what Sean is
    /// looking at. Nothing depends on the heights being EQUAL: the two
    /// modes come back to the same place by the cell it is in and how far
    /// through it (`CellPlace`, `NoteStore.topCell`), and the drawing
    /// layer goes through the two panes' cells (`PaneMapping`) — never by
    /// a number of points that means one thing on each side.
    static var codePadding: CGFloat { (MarkdownTextView.codeSize / 2).rounded() }
    /// The air under the last cell. All of it is the tail seam now — the
    /// gap, the strip the page used to offer a click on, and the margin
    /// that was under them — because everything below the last cell is
    /// one seam and there has to be somewhere to put a cell down there.
    static let tailHeight: CGFloat = 80 + topInset + gapHeight
    /// How tall the insertion mark itself is — the plus is bigger than
    /// the two points of the bar, and the mark is centred on the seam's
    /// own line.
    static let markHeight: CGFloat = 12

    var body: some View {
        // The window on the page, measured from OUTSIDE the scroll view:
        // the tail seam runs to the bottom of it. A preference from a
        // GeometryReader in the scroll view's background never arrived —
        // the tail came out 110 points tall against a 700 point window,
        // so the space under a short note answered nothing.
        GeometryReader { window in
        ScrollViewReader { page in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Reports how far the content has scrolled, in the same
                // coordinates the drawing layer works in.
                GeometryReader { proxy in
                    Color.clear.preference(key: PreviewScrollKey.self,
                                           value: -proxy.frame(in: .named(Self.space)).minY)
                        .preference(key: PreviewWidthKey.self, value: proxy.size.width)
                }
                .frame(height: 0)

                // A seam above every cell and one under the last: the
                // page is cell, seam, cell, seam, and nothing else. By
                // INDEX, because `seams` is built from these same rows in
                // this same order and two of them can share an offset.
                let seams = self.seams
                let cells = items
                // The In/Out pairs, read off the note once for the whole
                // page rather than once per row.
                let pairs = EvalCells.groups(in: markdown)
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, item in
                    seamView(index < seams.count ? seams[index] : nil, index: index)
                        .id(SeamRow(index: index))
                    // The page's margin is INSIDE the cell — `cell(_:)`
                    // applies it — so a seam is the full width of the
                    // page and so is the row above it, and there is no
                    // strip down either side that answers nothing.
                    cell(item, in: pairs)
                        .id(item.id)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(key: PreviewRowHeights.self,
                                                       value: [item.id: proxy.size.height])
                            }
                        }
                }
                seamView(cells.count < seams.count ? seams[cells.count] : nil, index: cells.count)
                    .id(SeamRow(index: cells.count))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Where the page is to open, as a point the scroll view can be
            // scrolled to.
            .background(alignment: .topLeading) {
                PageMark(holder: openingMark)
                    .frame(width: 0, height: 0)
                    .padding(.top, openingY)
                    .allowsHitTesting(false)
            }
            // No padding above or below either: the air at the two ends
            // of the page is SEAM, not margin, and the head and tail
            // seams carry it themselves (`topInset` in the one,
            // `tailHeight` in the other).
            // The cell brackets, in the margin the page already leaves.
            .overlay(alignment: .topTrailing) {
                CellBrackets(brackets: cellBrackets,
                             onSelect: { beginEditing($0) },
                             onSelectCells: { selectCells($0) },
                             onToggle: { onToggleSection?($0) },
                             onHoverCells: { promisedCells = $0 },
                             onMoveCell: { range, up in
                                 // Through `moving`, which moves the SPANS:
                                 // the closure this used to hand `cellEdit`
                                 // threw its span away and moved the dragged
                                 // cell once per span, so a selection with a
                                 // hole in it wrote the swapped text into the
                                 // note twice over (2026-09-20).
                                 let cells = heldCells.contains { NSEqualRanges($0, range) }
                                     ? heldCells : [range]
                                 applyCellEdits(CellCommands.moving(cells, up: up, in: markdown))
                             })
                    // As tall as the brackets go, not a fixed 4000 points:
                    // past that the page had cells with no bracket beside
                    // them (Sean, 2026-09-19: "make sure the notebook bars
                    // on the side work properly in markdown and wysiwyg
                    // mode").
                    .frame(height: CellBrackets.height(of: cellBrackets), alignment: .top)
                    // Clear of the scroller, and clear of the page's own
                    // right margin.
                    .padding(.trailing, 4)
                    .allowsHitTesting(editable)
                    // The keyboard, while cells are held. There is no text
                    // view on this side to hear it — the same hole the
                    // armed seam had, and the same answer.
                    .focusable(editable && !selectedCells.isEmpty)
                    .focusEffectDisabled()
                    .focused($focusedBrackets)
                    .onKeyPress(phases: .down) { press in cellsKey(press) }
            }
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(PreviewRowHeights.self) { heights in
            var measured = rowHeights
            for (id, height) in heights where abs((measured[id] ?? -1) - height) > 0.5 {
                measured[id] = height
                rowHeights[id] = height
            }
            // Only a page every row of which has been measured: a row
            // still at no height puts every cell under it a row too high.
            guard let cells = Self.cells(of: items.map { ($0.id, measured[$0.id]) }) else { return }
            onLayout?(cells)
            tellDrawingFrames(cells)
            // And the place it was asked to open at, now that it can be
            // found.
            markOpening(in: cells)
        }
        // AFTER the update that moved the mark, and a turn after that:
        // asked in the same breath as the move, the page scrolled to where
        // the mark WAS.
        .onChange(of: openingY) { _, _ in if opening != nil { openAtPlace() } }
        .onPreferenceChange(PreviewScrollKey.self) { offset in
            onScroll?(offset)
            // Kept, because the page has to know whether a bar armed
            // from outside it is already on screen before it moves for
            // one (`bringIntoView`).
            if scrolled != offset { scrolled = offset }
            // Which place the fold is on, for the other mode to open at.
            guard opening == nil,
                  let cells = Self.cells(of: items.map { ($0.id, rowHeights[$0.id]) }),
                  let top = CellPlace.at(offset, in: cells)
            else { return }
            onTopCell?(top)
        }
        .onPreferenceChange(PreviewWidthKey.self) { width in
            guard abs(width - pageWidth) > 0.5 else { return }
            pageWidth = width
            tellDrawingFrames()
        }
        .onChange(of: drawingCells) { _, _ in tellDrawingFrames() }
        .environment(\.drawingCells, drawingCells)
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: cursor) { _, cursor in
            onEditingChanged?(cursor != .none)
            onDrawingCaret?(drawingCell(of: cursor))
        }
        .onChange(of: focusedDrawing) { _, focused in
            // Whatever else takes the keyboard takes it from the drawing
            // cell, as from the bar.
            if case .drawing(let line) = cursor, focused != line.location { cursor = .none }
        }
        // The pen going up takes the bar with it.
        .onChange(of: seamsEnabled) { _, enabled in if !enabled { disarm() } }
        .onChange(of: focusedSeam) { _, focused in
            // Whatever else takes the keyboard takes it from the bar.
            if armedSeam != nil, focused != armedSeam { armedSeam = nil }
        }
        // The page catching up with a bar that was armed from outside it.
        // `onChange` runs after the rows have been rebuilt, which is the
        // first moment the answer's own row is on the page to scroll to.
        .onChange(of: bringIntoView) { _, wanted in
            guard let wanted else { return }
            // AFTER THE ROWS ARE ON THE PAGE, AND AFTER THEY ARE LAID
            // OUT. `onChange` is the first of those and is why the
            // scroll is asked for here rather than in `armSeam` — an
            // answer is written into `markdown` a moment before, and a
            // proxy asked then scrolls to a row that does not exist yet.
            // The second is why there is a beat after it: a screenful of
            // output has to be measured before the page knows where its
            // seam went.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                defer { bringIntoView = nil }
                // A PAGE THAT DOES NOT MOVE WHEN IT DOES NOT HAVE TO.
                // The answer to `2 + 2` is one line, and jerking the
                // note under the reader for a bar already in front of
                // them is the opposite of what the scroll is for (Sean,
                // 2026-09-22: "make the cursor behavior after evaluating
                // a cell elegant"). The source pane has always been like
                // this — `scrollRangeToVisible` moves by the least it
                // can and not at all when the range is already on screen
                // — and this is that rule, said out loud because SwiftUI
                // has no equivalent.
                guard let line = seams.indices.contains(wanted.index)
                        ? seams[wanted.index].line : nil,
                      !PreviewLayout.onScreen(line, scroll: scrolled, height: pageHeight)
                else { return }
                // And when it does move: THE SEAM, low on the page,
                // carried rather than jumped. Low because what you have
                // just made is above it and worth seeing; the seam and
                // not the answer above it because a row taller than the
                // window cannot be scrolled to its BOTTOM at all —
                // SwiftUI clamps that to keeping its top in view, which
                // is to say it does not move (measured, 2026-09-22).
                withAnimation(.easeOut(duration: 0.22)) {
                    page.scrollTo(wanted, anchor: UnitPoint(x: 0, y: 0.8))
                }
            }
        }
        .onAppear {
            // Open where the markdown pane was left: the same place in the
            // same cell, once the rows have been measured — which they can
            // be already, the heights arriving before the page appears.
            if topCell != .top {
                opening = topCell
                if let cells = Self.cells(of: items.map { ($0.id, rowHeights[$0.id]) }) { markOpening(in: cells) }
            }
            guard editable else { return }
            // The cursor, read on the way out of this page by ⌘T — and
            // the one the markdown pane was holding, put back.
            bridge.paneCaret = { EditorBridge.Carried(caret: paneCaret, text: markdown) }
            if let carried = bridge.takeCarried(for: markdown), let caret = carried.caret {
                reopen(caret)
            }
            // Every button on the bar works on this side: pressing one with
            // nothing clicked opens a block first (Sean, 2026-09-19: "allow
            // wysiwyg editing including all the buttons on the bar").
            bridge.ensureEditing = { openSomething() }
            bridge.moveSectionInDocument = { up in moveWholeSection(up: up) }
            bridge.mergeCellsInDocument = { mergeCells() }
            bridge.splitCellInDocument = { splitCell() }
            bridge.cellRangeInDocument = { openCell ?? items.first?.range }
            bridge.cellEditInDocument = { make in cellEdit(make) }
            // And what a Format command means while the BAR is the cursor.
            // There is no text view on this side for the bridge to read the
            // armed state off, so it asks: ⌘1 at a bar used to fall through
            // to `ensureEditing`, which opened the note's FIRST cell and
            // titled that (2026-09-20).
            bridge.armedBar = { kind in
                guard let seam = armedSeam else { return false }
                // THE CELL IS MADE THERE, now (Sean, 2026-09-21: "if i
                // click on something like a style, or a bullet list, or a
                // quoted section, etc.. it should create a cell at the
                // position of the bar ready for that type of input").
                // Recording the kind and waiting for a character is the
                // + on the bar's job, and it keeps it; a button pressed
                // has to do something the moment it is pressed.
                openSeam(.empty, as: kind ?? .text, at: seam.offset)
                // A kind IS the whole command. Anything else still has to
                // run, and by the time `perform` comes back round the
                // cell it runs in is open.
                return kind != nil
            }
            bridge.barIsUp = { armedSeam != nil }
            // ⌘8, ⌘9 and the maths palette: this page holds the note and
            // where its caret is in it, so it asks `Insertion` itself.
            bridge.insertInDocument = { thing in insert(thing) }
            bridge.drawingCellInDocument = { drawingCellHere() }
            bridge.drawingCursorInDocument = {
                if case .drawing(let line) = cursor { return line }
                return nil
            }
            bridge.focusDrawingCellInDocument = { id in
                guard let line = DrawingCells.lines(in: markdown).first(where: { $0.id == id })?.range else { return }
                beginDrawing(line)
            }
            // An answer written under a cell while somebody is typing in
            // another one: the note changes, and everything holding a raw
            // offset further down it moves by the same amount. Nothing
            // else edits this note from outside the caret, which is why
            // nothing else has had to do this.
            // The bar under a cell that has just finished running.
            bridge.armBarInDocument = { cell in
                armSeam(beside: cell, below: true, bringingIntoView: true)
            }
            bridge.writeInDocument = { edit in
                let ns = markdown as NSString
                guard NSMaxRange(edit.range) <= ns.length else { return }
                markdown = ns.replacingCharacters(in: edit.range, with: edit.replacement)
                switch cursor {
                case .none: break
                case .cell(let range): cursor = .cell(EvalCells.shifted(range, by: edit))
                case .item(let range): cursor = .item(EvalCells.shifted(range, by: edit))
                case .drawing(let range): cursor = .drawing(EvalCells.shifted(range, by: edit))
                }
                selectedCells = selectedCells.map { EvalCells.shifted($0, by: edit) }
                if let seam = armedSeam {
                    // THE INDEX MOVES TOO. A `SeamID` is index AND
                    // offset, and an answer written above an armed bar
                    // adds a whole cell — so the seam that was fifth is
                    // now sixth. Shifting only the offset left an id
                    // matching no drawn seam, `focusedSeam` stopped
                    // equalling `armedSeam`, and the watcher above read
                    // that as "something else took the keyboard" and
                    // put the bar out.
                    let moved = EvalCells.shifted(seam.offset, by: edit)
                    let found = seams.indices.filter { seams[$0].offset == moved }
                    let index = found.min { abs($0 - seam.index) < abs($1 - seam.index) } ?? seam.index
                    let id = SeamID(index: index, offset: moved)
                    armedSeam = id
                    focusedSeam = id
                }
            }
        }
        .onDisappear {
            onEditingChanged?(false)
            bridge.ensureEditing = nil
            bridge.moveSectionInDocument = nil
            bridge.mergeCellsInDocument = nil
            bridge.splitCellInDocument = nil
            bridge.cellRangeInDocument = nil
            bridge.cellEditInDocument = nil
            bridge.armedBar = nil
            bridge.barIsUp = nil
            bridge.insertInDocument = nil
            bridge.drawingCellInDocument = nil
            bridge.drawingCursorInDocument = nil
            bridge.focusDrawingCellInDocument = nil
            bridge.writeInDocument = nil
            bridge.armBarInDocument = nil
        }
        .environment(\.openURL, OpenURLAction { url in
            let destination = url.absoluteString
            // A note link is relative, so it arrives with no scheme.
            guard url.scheme == nil || url.scheme == "file",
                  let onFollow, onFollow(destination) else { return .systemAction }
            return .handled
        })
        .onAppear { pageHeight = window.size.height }
        .onChange(of: window.size.height) { _, height in pageHeight = height }
        }
        }
    }

    // MARK: - What is on the page

    /// A rendered block, or the one being edited — which may be a block that
    /// is not in the document yet, and so has to be carried separately.
    private struct Item: Identifiable {
        let id: Int
        let range: NSRange
        let block: MarkdownBlock?
        let isEditing: Bool
    }

    /// What a folded section hides, in the markdown.
    private var hidden: [NSRange] {
        NotebookOutline.hiddenRanges(in: markdown, collapsed: collapsed)
    }

    private var items: [Item] {
        let folded = hidden
        let parsed = MarkdownParser.positioned(from: markdown).filter { block in
            // A block inside a closed section is not on the page at all.
            !folded.contains { NSIntersectionRange($0, block.range).length == block.range.length }
        }
        guard let editing = editingRange, editable else {
            return parsed.map { Item(id: $0.range.location, range: $0.range, block: $0.block, isEditing: false) }
        }

        func overlaps(_ range: NSRange) -> Bool {
            NSIntersectionRange(range, editing).length > 0 || range.location == editing.location
        }
        let edited = Item(id: editing.location, range: editing,
                          block: parsed.first { overlaps($0.range) }?.block, isEditing: true)

        var items: [Item] = []
        var placed = false
        for positioned in parsed {
            if overlaps(positioned.range) {
                if !placed { items.append(edited); placed = true }
                continue
            }
            if !placed, positioned.range.location > editing.location {
                items.append(edited)
                placed = true
            }
            items.append(Item(id: positioned.range.location, range: positioned.range,
                              block: positioned.block, isEditing: false))
        }
        if !placed { items.append(edited) }
        return items
    }

    /// A bracket for every cell, and one further out for every section
    /// that holds them.
    private var cellBrackets: [CellBrackets.Bracket] {
        let shown = items
        guard !shown.isEmpty else { return [] }
        let places = PreviewLayout.positions(rows: shown.map { ($0.id, rowHeights[$0.id] ?? 0) },
                                             spacing: Self.blockGap, top: Self.topInset + Self.gapHeight)
        let sections = NotebookOutline.sections(in: markdown)
        var out: [CellBrackets.Bracket] = []

        // An evaluation cell and its answer are ONE GROUP, with a
        // bracket round the pair (Sean, 2026-09-21: "input and output
        // cells are grouped together").
        let groups = EvalCells.groups(in: markdown)
        for group in groups {
            let inside = shown.filter {
                NSEqualRanges($0.range, group.input) || NSEqualRanges($0.range, group.output)
            }
            let boxes = inside.compactMap { places[$0.id] }
            guard boxes.count == 2, let top = boxes.map(\.top).min(),
                  let bottom = boxes.map(\.bottom).max(), bottom - top > 1
            else { continue }
            let held = CellSelection.holds(group.range, cells: inside.map(\.range),
                                           selection: selectedCells)
            out.append(CellBrackets.Bracket(key: group.key,
                                            depth: NotebookOutline.cellDepth(at: group.input.location,
                                                                             in: sections),
                                            top: top, bottom: bottom,
                                            selected: held, held: held, group: true,
                                            range: group.range))
        }

        for item in shown {
            guard let place = places[item.id], place.bottom - place.top > 1 else { continue }
            var depth = NotebookOutline.cellDepth(at: item.range.location, in: sections)
            if EvalCells.isGrouped(item.range, in: groups) { depth += 1 }
            // Lit and HELD are not the same thing: the cell open for
            // typing is drawn heavy with nothing picked up, and the
            // gestures may not read that as a cell being held
            // (2026-09-20).
            let held = CellSelection.covers(item.range, selectedCells)
            out.append(CellBrackets.Bracket(key: "cell:\(item.id)", depth: depth,
                                            top: place.top, bottom: place.bottom,
                                            selected: openCell == item.range || held,
                                            held: held, range: item.range))
        }

        for section in sections {
            let inside = shown.filter {
                NSIntersectionRange($0.range, section.range).length == $0.range.length
            }
            let places = inside.compactMap { places[$0.id] }
            guard let first = places.map(\.top).min(), let last = places.map(\.bottom).max(),
                  last - first > 1
            else { continue }
            // Held when every cell under it is — not when one selected
            // range happens to cover the characters, which cells picked
            // up one at a time never do (`CellSelection.holds`).
            let held = CellSelection.holds(section.range, cells: inside.map(\.range),
                                           selection: selectedCells)
            out.append(CellBrackets.Bracket(key: section.key, depth: section.depth,
                                            top: first, bottom: last,
                                            collapsed: collapsed.contains(section.key),
                                            selected: held, held: held,
                                            foldable: true, range: section.range))
        }
        return out
    }

    @ViewBuilder
    private func row(_ item: Item, in groups: [EvalCells.Group]) -> some View {
        if item.isEditing {
            BlockEditor(text: draftBinding,
                        font: BlockView.editingNSFont(item.block),
                        bridge: bridge,
                        focusToken: focusToken,
                        caret: caret,
                        placeholder: fence == nil
                            ? "Write something — ⌘1 a title, ⇧⌘L a list, ⌃⌘Q a quote"
                            : "Type the code",
                        keepsNewlines: Self.keepsNewlines(item.block),
                        language: fence?.language,
                        onSplit: { head, tail in split(head: head, tail: tail) },
                        onDeleteEmpty: { removeBlock() },
                        onMove: { move($0) })
                // The same room the rendered block has — nothing at all
                // for prose, the code block's own twelve for a fence — so
                // opening a cell moves no text (Sean, 2026-09-19: "gaps
                // should just be a small fixed padding").
                .padding(.horizontal, fence == nil ? 0 : 12)
                .padding(.vertical, fence == nil ? 0 : MarkdownPreview.codePadding)
                // A code block being typed in keeps looking like a code
                // block, so nothing jumps when it is clicked.
                .background(fence == nil ? AnyShapeStyle(Color.accentColor.opacity(0.07))
                                         : AnyShapeStyle(CodeColours.background),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.35)))
                // AND THE BADGE STAYS. Opening the cell swaps the
                // rendered block for a text view, and the badge went
                // with it — at the very moment you are most likely to
                // want to know what the cell runs as (Sean, 2026-09-22:
                // "the indicator for WL/Python/C++ never goes away").
                // Beside it rather than inside it, in the margin the
                // page already leaves, so the words do not move for it.
                .padding(.leading, openMark(item, in: groups) == nil ? 0 : CellMark.width + 6)
                .overlay(alignment: .topLeading) {
                    if let role = openMark(item, in: groups) {
                        CellMark(role: role, isRunning: runningCell == item.range.location,
                                 onPick: { onPickEvaluator?($0, item.range) })
                    }
                }
        } else if let block = item.block {
            // NO .textSelection here. A selectable Text takes the click
            // itself, so tapping the WORDS of a block did nothing and only
            // the empty space beside them opened it — which reads as "I
            // can't edit this" (Sean, 2026-09-19: "i still cant do things
            // like edit code or text etc in wysiwyg editing"). Selecting
            // text is what the editor that opens is for.
            BlockView(block: block,
                      onToggleTodo: { index in tickTodo(item.range, at: index) },
                      evaluation: evaluation(of: item, in: groups),
                      editing: checklistEditing(in: item.range, block: block),
                      drawingLit: cursor == .drawing(item.range))
                .frame(maxWidth: .infinity, alignment: .leading)
                // The faint promise a hover over the gutter makes. An
                // overlay of colour rather than a background, so a code
                // cell's own dark fill still shows through it and the
                // page does not move by a point for it.
                .padding(.vertical, 2)
                .overlay {
                    if promisedCells.contains(where: { NSEqualRanges($0, item.range) }) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.12))
                            .allowsHitTesting(false)
                    }
                }
                .padding(.vertical, -2)
        }
    }

    /// THE WHOLE ROW IS THE CELL, margins and all — the pointer and the
    /// click both.
    ///
    /// AN I-BEAM OVER THE WORDS (Sean, 2026-09-21: "in wysiwyg mode as i
    /// hover over text and such it should be a text edit cursor"): a
    /// rendered block is SwiftUI `Text` with no cursor rects of its own,
    /// so the pointer over the page was the arrow — a page you can click
    /// into and type in, saying nothing of the sort.
    ///
    /// AND OVER THE MARGINS TOO (Sean, 2026-09-22: "the mouse cursor
    /// behavior should be the same in wysiwyg and markdown mode"). The
    /// page's 28-point side inset used to be applied from OUTSIDE the
    /// row, so the hover and the tap were sized to the text column and
    /// the two strips down the sides answered nothing at all: sliding
    /// sideways off the words flipped the pointer to an arrow an inch
    /// before the pane edge, where the other pane — whose margin is the
    /// text container's own inset — is an I-beam right out to it. The
    /// same inset, applied INSIDE, keeps the words exactly where they
    /// were and hands the margin to the cell it belongs to.
    ///
    /// It covers the OPEN cell as well, which had no cursor of its own
    /// outside its text view at all: the ring of padding inside its
    /// highlighted box, and the strip under the badge, were arrow.
    ///
    /// Set on every move rather than pushed, and handed back on the way
    /// out, for the reasons the seams are: a pushed cursor loses to
    /// cursorUpdate, and `NSCursor.set()` is global and sticks until
    /// something else sets one. The "was it me" question is `hovered`,
    /// so the seam the pointer has just arrived at does not have its
    /// cursor taken back by the cell it left.
    @ViewBuilder
    private func cell(_ item: Item, in groups: [EvalCells.Group]) -> some View {
        if case .drawing? = item.block, !item.isEditing {
            drawingRow(item)
        } else {
            textCell(item, in: groups)
        }
    }

    /// A DRAWING CELL'S ROW. A tap on it — which reaches it only where the
    /// drawing layer does not take it, right of a narrow cell — puts the
    /// cursor in the cell and never opens an editor on its line. No I-beam
    /// over it: over its paper the pointer is the layer's pencil.
    private func drawingRow(_ item: Item) -> some View {
        row(item, in: [])
            .padding(.horizontal, Self.sideInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { beginDrawing(item.range) }
            .focusable(editable)
            .focusEffectDisabled()
            .focused($focusedDrawing, equals: item.id)
            .onKeyPress(phases: .down) { press in drawingKey(press, in: item.range) }
    }

    @ViewBuilder
    private func textCell(_ item: Item, in groups: [EvalCells.Group]) -> some View {
        row(item, in: groups)
            .padding(.horizontal, Self.sideInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // A CHECKLIST'S ITEMS OWN THEIR OWN CLICKS, so a click on a
            // reminder opens that reminder and not the whole cell (Sean,
            // 2026-09-21). The bracket in the gutter is still how the
            // whole list is opened, which is how a list's kind is changed
            // and how a reminder is unmade.
            .onTapGesture {
                guard !item.isEditing, let block = item.block, !Self.isChecklist(block) else { return }
                beginEditing(item.range)
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active:
                    // Not while the pen, the arrow tool or a placement
                    // owns the pane: the pointer there is the layer's,
                    // and two answers to one pointer is the flicker that
                    // cost seven rounds.
                    guard editable, seamsEnabled else { return }
                    if hovered != .cell(item.id) { hovered = .cell(item.id) }
                    let put = Self.textCursor
                    put.set()
                    if seamCursor !== put { seamCursor = put }
                case .ended:
                    let ours = hovered == .cell(item.id)
                    if ours { hovered = nil }
                    let back = Self.cursor(hovering: false, ours: ours, put: seamCursor)
                    if ours { seamCursor = nil }
                    back?.set()
                }
            }
    }

    /// THE OPEN CELL'S OWN MARK, when the cell being typed in is an
    /// evaluation cell and this page has an environment menu to offer.
    /// Nil for prose, for a plain code cell, and on paper.
    private func openMark(_ item: Item, in groups: [EvalCells.Group]) -> CellMark.Role? {
        guard editable, onPickEvaluator != nil, let fence else { return nil }
        let language = MarkdownFormatting.fenceLanguage(fence.open)
        guard Evaluator.isEvaluation(fence: language) else { return nil }
        return .input(fence: language, number: EvalCells.number(of: item.range, in: groups))
    }

    /// What a cell's own left margin says: `In[n]` or the environment
    /// over the code, `Out[n]` over its answer, and nothing at all over
    /// any other block. Nil too while the page is read-only — the PDF
    /// carries no controls — and when nothing has wired the menu up.
    private func evaluation(of item: Item, in groups: [EvalCells.Group]) -> BlockView.Evaluation? {
        guard editable, onPickEvaluator != nil, case .code(let language, _) = item.block
        else { return nil }
        let cell = item.range
        if let number = EvalCells.number(of: cell, in: groups),
           EvalCells.isAnswer(cell, in: groups) {
            return BlockView.Evaluation(role: .output(number: number), isRunning: false,
                                        onPick: { _ in })
        }
        guard Evaluator.isEvaluation(fence: language) else { return nil }
        return BlockView.Evaluation(
            role: .input(fence: language, number: EvalCells.number(of: cell, in: groups)),
            isRunning: runningCell == cell.location,
            onPick: { onPickEvaluator?($0, cell) })
    }

    static func isChecklist(_ block: MarkdownBlock?) -> Bool {
        if case .todos = block { return true }
        return false
    }

    /// What a rendered checklist needs to let ONE of its items be typed
    /// in. Nil for every other kind of cell, and nil too when the walk
    /// and the parser disagree about how many reminders are in the cell —
    /// an item editor bound to the wrong line is worse than none.
    private func checklistEditing(in cell: NSRange, block: MarkdownBlock?) -> BlockView.ChecklistEditing? {
        guard editable, case .todos(let shown)? = block else { return nil }
        let found = ListEditing.reminders(in: cell, of: markdown as NSString)
        guard found.count == shown.count else { return nil }
        return BlockView.ChecklistEditing(
            openWords: editingItem,
            items: found,
            text: itemBinding,
            focusToken: focusToken,
            caret: caret,
            bridge: bridge,
            onOpen: { reminder, caret in openItem(reminder.text, caret: caret) },
            onSplit: { head, tail in splitItem(head: head, tail: tail) },
            onDeleteEmpty: { removeItem() },
            onJoinPrevious: { joinItemToPrevious() },
            onMove: { moveFromItem($0) })
    }

    /// One seam: the WHOLE space between two cells, top to bottom and
    /// edge to edge — the air above the first cell, the strip between two
    /// of them, and everything under the last (Sean, 2026-09-20: "the
    /// cursor should be horizontal any space between the two cells").
    ///
    /// The pointer turns on its side anywhere inside it and a click ARMS
    /// it: a bar runs across the page and that bar is the cursor, which
    /// is why no block is left open behind it. The note is not touched
    /// until a key arrives — clicking about the page used to leave an
    /// empty cell everywhere it had been.
    @ViewBuilder
    private func seamView(_ seam: CellSeams.Seam?, index: Int) -> some View {
        // A seam the page has not measured yet still holds the stack
        // apart, or every cell would jump a gap up and back.
        let height = seam.map { max(0, $0.bottom - $0.top) } ?? Self.gapHeight
        if let seam, editable, seamsEnabled {
            let id = SeamID(index: index, offset: seam.offset)
            Color.clear
                .frame(height: height)
                // From the TOP of the seam, offset to the line the seam
                // itself names, and not centred in it: the tail seam is
                // everything under the last cell, so centring put the bar
                // hundreds of points down an empty page (Sean,
                // 2026-09-20: "when i select somewhere below the cell,
                // the bar should go immediately after the last cell, not
                // the random spot below it's currently at"). The whole
                // seam is still the hit area.
                .overlay(alignment: .top) {
                    if armedSeam == id || hovered == .seam(id) {
                        HStack(spacing: 6) {
                            // The + is a button, and the only thing on the
                            // bar that is: the rest of the seam arms and
                            // nothing more.
                            Button { choose(in: id) } label: {
                                Image(systemName: "plus.circle.fill").font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help("What the next thing typed here becomes")
                            Capsule().frame(height: 2)
                        }
                        // A hint while the pointer is only passing, the
                        // cursor itself once it is armed (Sean,
                        // 2026-09-21: "the bar that appears when moving
                        // the cursor is a much fainter one until it is
                        // clicked").
                        .foregroundStyle(Color.accentColor.opacity(armedSeam == id ? 1 : 0.26))
                        // Drawn inside the page's margin though the seam
                        // itself reaches both edges: the bar is furniture
                        // and lines up with the words, the hit area is
                        // the whole width.
                        .padding(.horizontal, Self.sideInset)
                        // An overlay, and taller than the seam it is in:
                        // the strip between two cells is eight points and
                        // the mark is twelve, and the page must not move
                        // when the pointer arrives.
                        .frame(height: Self.markHeight)
                        // An offset rather than padding, for the same
                        // reason: it moves the mark without asking the
                        // page for room.
                        .offset(y: seam.line - seam.top - Self.markHeight / 2)
                        .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let point):
                        if hovered != .seam(id) { hovered = .seam(id) }
                        // Set on every move, not pushed once: the text
                        // views either side put their own cursors back
                        // the moment the pointer touches them.
                        let put = Self.cursor(hovering: true,
                                              onPlus: Self.plusTarget(in: seam).contains(point))
                        put?.set()
                        if seamCursor !== put { seamCursor = put }
                    case .ended:
                        // Whether the pointer was on THIS seam, read
                        // before it is forgotten: the seam it has moved
                        // on to may have claimed the pointer already.
                        let ours = hovered == .seam(id)
                        if ours { hovered = nil }
                        // And handed back on the way out. There is no
                        // text view under the pointer on this side to put
                        // its own cursor back, so the horizontal I-beam
                        // followed the pointer over the words, the
                        // toolbar and the sidebar — the same trap
                        // `CursorLayer` was written for.
                        let back = Self.cursor(hovering: false, ours: ours, put: seamCursor)
                        if ours { seamCursor = nil }
                        back?.set()
                    }
                }
                .onTapGesture { arm(id) }
                // Dragging a bar up or down takes the cells it passes
                // (Sean, 2026-09-21: "clicking and draging a bar up or
                // down can select cells") — the same command a drag down
                // the bracket column gives, from the other side of the
                // page. In the seam's own coordinates, so the y is turned
                // back into the page's before the cells are asked.
                .gesture(
                    DragGesture(minimumDistance: CellInsertions.dragThreshold,
                                coordinateSpace: .local)
                        .onChanged { value in
                            dragSeam(from: seam, by: value.translation.height,
                                     to: seam.top + value.location.y)
                        }
                        .onEnded { _ in seamDragAnchor = nil }
                )
                // The bar has to hear the keyboard, and there is no text
                // view on this side to hear it for us.
                .focusable()
                .focusEffectDisabled()
                .focused($focusedSeam, equals: id)
                .onKeyPress(phases: .down) { press in key(press, in: id) }
                .help("Click for the line, then type — or Return for an empty cell")
        } else {
            // Read-only, or the pen is up: the space is still there, it
            // just does nothing at all.
            Color.clear.frame(height: height)
        }
    }

    /// A box ticked, or unticked. The note is the only place the answer
    /// lives — there is no state beside it to get out of step.
    private func tickTodo(_ block: NSRange, at index: Int) {
        onClick?()
        guard editable,
              let edit = MarkdownFormatting.toggleTodo(text: markdown, block: block, item: index)
        else { return }
        // Where the caret was, before the button took the keyboard. A box
        // and a caret share a row for the first time here: pressing the
        // box makes it first responder, and without this the words you
        // were in the middle of typing stop taking what you type.
        let held = editingItem != nil ? bridge.textView?.selectedRange().location : nil
        markdown = (markdown as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        // A tick is one character for one (`toggleTodo`, and a test says
        // so), so nothing the caret was measured against has moved.
        guard let held else { return }
        caret = .at(held)
        focusToken += 1
    }

    /// A drag that began on a bar: the cells between where it started and
    /// where it is now. It is a selection, not an insertion point, so the
    /// bar goes out — a cursor between two cells and three cells held at
    /// once are two different answers to "where am I".
    private func dragSeam(from seam: CellSeams.Seam, by travelled: CGFloat, to y: CGFloat) {
        guard let drag = Self.seamDrag(from: seam, by: travelled, to: y, anchor: seamDragAnchor,
                                       brackets: cellBrackets) else { return }
        seamDragAnchor = drag.anchor
        armedSeam = nil
        editingRange = nil
        selectedCells = drag.cells
    }

    /// The cells a drag from a bar has passed, and the one it is growing
    /// from — settled by its first movement (`anchor`, once there is one).
    ///
    /// CELLS, read the column's own way (`CellBrackets.cellSpans`). This
    /// asked `!foldable`, which counts an In/Out pair's bracket as a cell:
    /// it is listed before the cells, so a drag down from the bar over a
    /// pair anchored on the pair's range, a drag up over it stopped on it,
    /// and `between` — reading positions in that list — took every
    /// bracket listed between, the cell ABOVE the bar included.
    static func seamDrag(from seam: CellSeams.Seam, by travelled: CGFloat, to y: CGFloat, anchor: NSRange?,
                         brackets: [CellBrackets.Bracket]) -> (anchor: NSRange, cells: [NSRange])? {
        let spans = CellBrackets.cellSpans(of: brackets)
        let anchor = anchor
            ?? CellSelection.cell(fromSeamAt: seam.line, goingDown: travelled > 0, in: spans)
        guard let anchor, let over = CellSelection.cell(at: y, in: spans) else { return nil }
        return (anchor, CellSelection.between(anchor, over, in: spans.map(\.range)))
    }

    /// The + on the bar, in the seam view's OWN coordinates — the same
    /// region `CellSeams` hands the markdown pane, moved to the top of
    /// the seam because that is where this pane's hover reports from.
    /// Both panes put their + at their own left margin and neither
    /// measures the rest of it.
    ///
    /// WITHOUT the markdown pane's four points of slack, because here
    /// the press is not this rect: it is a real `Button` inside an
    /// `HStack` that starts at `sideInset`, and the hand shown outside
    /// it fell through to the seam's own tap, which arms the bar and
    /// opens no menu at all. The pane that reads this rect for the
    /// click keeps the slack; the pane that only draws a cursor with it
    /// cannot afford a point of it.
    static func plusTarget(in seam: CellSeams.Seam) -> CGRect {
        CellSeams.plusTarget(in: seam, leading: sideInset, grip: 0).offsetBy(dx: 0, dy: -seam.top)
    }

    /// What the pointer should be over a seam, and what it should be put
    /// back to on the way out.
    ///
    /// The + is a button, so over the + it is the hand — the same one
    /// the notebook brackets in the gutter use, so the app says "this
    /// does something" the one way (Sean, 2026-09-20: "it should be a
    /// pointer over the + button"). Over the rest of the seam the I-beam
    /// lies on its side.
    ///
    /// `NSCursor.set()` is global and sticks until something else sets
    /// one. Nothing on the rendered page does: the blocks are SwiftUI
    /// `Text` with no cursor rects at all. So a seam hands the arrow
    /// back on the way out — but only its OWN, and BOTH halves of that
    /// are needed, because each alone is a way to take a cursor that
    /// was never ours.
    ///
    /// `ours` is the seam's own answer to "was the pointer on me", and
    /// it is what tells one seam from the next: the seam the pointer
    /// has ARRIVED at is often told before the one it left, so leaving
    /// A took back the cursor B had just set. But only a seam writes
    /// that down, and a seam is not the only thing on this page that
    /// claims the pointer — the gutter's brackets set the hand and the
    /// split divider its own resize cursor on the way in, and leaving
    /// sideways onto one then put a plain arrow over it. `put` is what
    /// this page's seams last set, and if that is not still what is on
    /// screen then somebody else has the pointer and it is not ours to
    /// hand back.
    /// What the words of a rendered cell put on the pointer: the ordinary
    /// I-beam, upright — the cell is text, and it is clicked into and
    /// typed in. The seam's is the same I-beam ON ITS SIDE, which is how
    /// the two read as one idea rather than two.
    static var textCursor: NSCursor { .iBeam }

    static func cursor(hovering: Bool, onPlus: Bool = false, ours: Bool = false,
                       put: NSCursor? = nil, current: NSCursor = .current) -> NSCursor? {
        if hovering { return onPlus ? .pointingHand : .iBeamCursorForVerticalLayout }
        guard ours, let put, current === put else { return nil }
        return .arrow
    }

    // MARK: - The seams

    /// The spaces between the cells on this page.
    private var seams: [CellSeams.Seam] {
        Self.seams(rows: items.map { ($0.id, rowHeights[$0.id] ?? 0) },
                   noteLength: (markdown as NSString).length, pageHeight: pageHeight)
    }

    /// The mark moved to the place the page is to open at, and scrolled to
    /// once it is there (`openingY`'s watcher) — or now, when it already is.
    private func markOpening(in cells: [CellSeams.Box]) {
        guard let wanted = opening else { return }
        let y = max(0, wanted.y(in: cells) ?? 0)
        if y == openingY { openAtPlace() } else { openingY = y }
    }

    /// Scroll to the place the page was asked to open at, and from then on
    /// say where the top of the window is. Through the page's own scroll
    /// view, to the point.
    ///
    /// And SAID, once it is there, to the drawing layer and the store: a
    /// scroll view moved by hand is not one SwiftUI moved, and its scroll
    /// preference was not seen to follow it in a window off the screen —
    /// left to it, the layer could sit a whole page off the words.
    private func openAtPlace() {
        DispatchQueue.main.async {
            defer { opening = nil }
            guard let mark = openingMark.view, let scroll = mark.enclosingScrollView,
                  let document = scroll.documentView else { return }
            document.layoutSubtreeIfNeeded()
            let at = mark.convert(NSPoint.zero, to: document)
            let clip = scroll.contentView
            var wanted = clip.bounds
            wanted.origin.y = document.isFlipped ? at.y : at.y - wanted.height
            clip.scroll(to: clip.constrainBoundsRect(wanted).origin)
            scroll.reflectScrolledClipView(clip)
            let y = document.isFlipped ? clip.bounds.origin.y : document.bounds.height - clip.bounds.maxY
            onScroll?(y)
            scrolled = y
            if let cells = Self.cells(of: items.map { ($0.id, rowHeights[$0.id]) }),
               let top = CellPlace.at(y, in: cells) {
                onTopCell?(top)
            }
        }
    }

    /// The cells' boxes on the page, from the rows' measured heights — nil
    /// while any row has yet to be measured, because a row at no height
    /// puts every cell under it a row too high.
    static func cells(of rows: [(id: Int, height: CGFloat?)]) -> [CellSeams.Box]? {
        var measured: [(id: Int, height: CGFloat)] = []
        for row in rows {
            guard let height = row.height else { return nil }
            measured.append((id: row.id, height: height))
        }
        let places = PreviewLayout.positions(rows: measured, spacing: blockGap, top: topInset + gapHeight)
        return measured.compactMap { row in
            places[row.id].map { CellSeams.Box(top: $0.top, bottom: $0.bottom, offset: row.id) }
        }
    }

    /// The same seams the markdown pane has, measured off the stack
    /// instead of off the glyphs: `CellSeams` is the one model, and the
    /// two panes only differ in how they find the cells' boxes.
    ///
    /// `pageHeight` is the window on the page. The tail reaches the
    /// bottom of it when the note is shorter than the window, and
    /// `tailHeight` under the last cell when it is longer — either way
    /// everything below the last cell is seam.
    static func seams(rows: [(id: Int, height: CGFloat)], noteLength: Int,
                      pageHeight: CGFloat) -> [CellSeams.Seam] {
        let places = PreviewLayout.positions(rows: rows, spacing: blockGap,
                                             top: topInset + gapHeight)
        let cells: [CellSeams.Box] = rows.compactMap { row in
            guard let place = places[row.id] else { return nil }
            return CellSeams.Box(top: place.top, bottom: place.bottom, offset: row.id)
        }
        let bottom = (cells.last?.bottom ?? 0) + tailHeight
        return CellSeams.seams(cells: cells, pageTop: 0, pageBottom: max(pageHeight, bottom),
                               noteLength: noteLength,
                               // An empty note has no cell for the bar to
                               // sit against; the stack says where the
                               // first one would land.
                               firstCellTop: topInset + gapHeight)
    }

    /// What a key pressed in an armed seam means.
    ///
    /// Pure, because the awkward ones are not obvious: an arrow and a
    /// delete arrive as characters too — in Unicode's private use area,
    /// where AppKit keeps the function keys — and ⌘S is not an S.
    enum SeamKey: Equatable {
        /// A printable character: the cell opens and this goes in it.
        case write(String)
        /// Return: an empty cell, open for typing.
        case empty
        /// Escape: the bar goes out and the note is untouched.
        case disarm
        /// An arrow: the bar walks into the cell beside it, so ↓ and ↑ go
        /// cell, bar, cell the way they do in the markdown pane. It
        /// writes nothing either.
        case step(up: Bool)
        /// Nobody's business here; whoever else wants the key can have it.
        case pass
    }

    static func seamKey(characters: String, modifiers: EventModifiers) -> SeamKey {
        if characters == "\u{1B}" { return .disarm }
        if characters == "\r" || characters == "\n" { return .empty }
        // AppKit keeps the function keys in Unicode's private use area.
        if characters == "\u{F700}" { return .step(up: true) }
        if characters == "\u{F701}" { return .step(up: false) }
        // ⌘S is not an S. Shift is, though — it is how a capital arrives.
        guard modifiers.isDisjoint(with: [.command, .control]), !characters.isEmpty else { return .pass }
        let printable = characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
        return printable ? .write(characters) : .pass
    }

    /// What that key does to the NOTE: the cell the seam stands for, of
    /// whatever kind the + chose, with what was typed already in it, the
    /// range it is edited at and the fences if it turned out to be code.
    ///
    /// Nil for a key that only takes the bar back, and that is the whole
    /// promise of the armed state — arming and then clicking away leaves
    /// the markdown byte for byte as it was. The opening itself is
    /// `CellTypes.open`, the same one rule both panes follow.
    static func opened(_ key: SeamKey, as type: CellTypes.Kind = .text, at offset: Int,
                       in markdown: String)
        -> (markdown: String, editing: NSRange, draft: String, fence: Fence?)? {
        let written: String
        switch key {
        case .write(let characters): written = characters
        case .empty: written = ""
        case .disarm, .step, .pass: return nil
        }
        let opened = CellTypes.open(type, writing: written, in: markdown, at: offset)
        let source = (opened.markdown as NSString).substring(with: opened.cell)
        // A fenced cell is opened as its CODE, the way a click on one is:
        // the fences stay put and what is typed is coloured for them.
        guard let parts = MarkdownFormatting.fenced(source) else {
            return (opened.markdown, opened.cell, source, nil)
        }
        return (opened.markdown, opened.cell, parts.body, Fence(open: parts.open, close: parts.close))
    }

    // MARK: - Cells held by their brackets

    /// What a key means while cells are HELD, which is not what the same
    /// key means in a seam: Return opens an empty cell in a seam and has
    /// nothing to say over a selection, and a delete only puts the bar out
    /// there while here it takes the cells.
    enum CellKey: Equatable {
        /// A printable character: the cells go, and one cell with this
        /// already in it takes their place. Typing over a selection.
        case replace(String)
        /// ⌫ or ⌦: they go, and nothing takes their place.
        case remove
        /// Escape: the brackets go out and the note is untouched.
        case clear
        /// Nobody's business here.
        case pass
    }

    static func cellKey(characters: String, modifiers: EventModifiers) -> CellKey {
        // ⌃⌫ is the Delete Cell menu item and never reaches this, and ⌘S
        // is not an S. Shift is, though — it is how a capital arrives.
        guard modifiers.isDisjoint(with: [.command, .control]) else { return .pass }
        if characters == "\u{1B}" { return .clear }
        if characters == "\u{8}" || characters == "\u{7F}" { return .remove }
        guard !characters.isEmpty else { return .pass }
        let printable = characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
        return printable ? .replace(characters) : .pass
    }

    // MARK: - Editing

    /// Cells picked up by their brackets: shown, not opened. Whatever else
    /// was holding a cursor lets go — a block open for typing and an armed
    /// seam are both a cursor, and three lit brackets are a third.
    private func selectCells(_ ranges: [NSRange]) {
        onClick?()
        guard editable else { return }
        disarm()
        dropHover()
        editingRange = nil
        selectedCells = ranges
        guard !ranges.isEmpty else { return }
        // A turn late: the column is only focusable once there is
        // something in it, and it is this write that puts it there.
        DispatchQueue.main.async { focusedBrackets = true }
    }

    /// A key while cells are held.
    private func cellsKey(_ press: KeyPress) -> KeyPress.Result {
        guard !selectedCells.isEmpty else { return .ignored }
        // Escape and the deletes by name: what `characters` carries for
        // them is AppKit's business, and the meaning is not.
        let characters: String
        switch press.key {
        case .escape: characters = "\u{1B}"
        case .delete: characters = "\u{8}"
        case .deleteForward: characters = "\u{7F}"
        default: characters = press.characters
        }
        switch Self.cellKey(characters: characters, modifiers: press.modifiers) {
        case .clear:
            selectedCells = []
            return .handled
        case .remove:
            replaceCells(with: "")
            return .handled
        case .replace(let typed):
            replaceCells(with: typed)
            return .handled
        case .pass:
            return .ignored
        }
    }

    /// The held cells taken away, and — for a character typed — one cell
    /// put where they were with that character already in it.
    ///
    /// Delete then open one — `CellCommands.typing`, the one rule both
    /// panes follow. The markdown pane used to leave this to NSTextView,
    /// which types over the first range of a discontiguous selection and
    /// keeps the rest.
    private func replaceCells(with typed: String) {
        guard let edit = CellCommands.typing(typed, over: selectedCells, in: markdown) else { return }
        selectedCells = []
        editingRange = nil
        markdown = (markdown as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        guard !typed.isEmpty else { return }
        // The cell the character went into, open with the caret after it.
        let cell = CellTypes.cell(at: edit.selection.location, in: markdown)
        fence = nil
        draft = (markdown as NSString).substring(with: cell)
        editingRange = cell
        caret = .end
        focusToken += 1
    }

    /// A click in a seam: the bar goes there and takes the keyboard.
    /// Nothing is written — the note is not touched until a key arrives.
    private func arm(_ id: SeamID) {
        onClick?()
        guard editable, seamsEnabled else { return }
        // The bar IS the cursor, so nothing else may be holding one: the
        // block that was open closes, caret and all (Sean, 2026-09-20:
        // "the mouse cursor and text cursor should both become horizontal
        // between cells"), and the brackets let go of what they held.
        editingRange = nil
        selectedCells = []
        armedType = Self.arming(id, over: armedSeam, keeping: armedType)
        armedSeam = id
        focusedSeam = id
    }

    /// What the kind on a bar becomes when the bar is armed at `id`.
    ///
    /// Re-arming the seam that is ALREADY armed keeps whatever the +
    /// chose for it, and arming anywhere else is plain text (Sean,
    /// 2026-09-19: "default is always just text"). The markdown pane has
    /// always done this — `PasteAwareTextView.armedSeam` only lets go
    /// when the bar MOVES — and this side threw the choice away
    /// unconditionally, so pressing the + a second time to check the
    /// choice reset it to Body Text while popping the menu with the old
    /// one still ticked (2026-09-20).
    static func arming(_ id: SeamID, over armed: SeamID?, keeping type: CellTypes.Kind) -> CellTypes.Kind {
        armed == id ? type : .text
    }

    /// The + on the bar: the kinds of cell, and the one picked stays with
    /// this seam until it disarms.
    private func choose(in id: SeamID) {
        let current = armedSeam == id ? armedType : .text
        // Armed first, because the choice belongs to a bar that is up —
        // and because the mark the + is drawn on is held on the page by
        // the hover until then, and the pointer is about to be over a
        // menu instead.
        arm(id)
        // A turn late, so that arming has reached the screen before the
        // menu takes the run loop.
        DispatchQueue.main.async {
            CellTypeMenu.popUp(current: current, at: NSEvent.mouseLocation, in: nil) { kind in
                armedType = kind
                if kind.opensAtOnce { openSeam(.empty, as: kind, at: id.offset) }
            }
        }
    }

    /// The bar goes out, and it lets the keyboard go with it.
    ///
    /// Both, always. `focusedSeam` left pointing at a seam that is no
    /// longer armed is a view still asserting first responder against the
    /// block editor that has just opened — they raced, and the second
    /// character typed went to the seam, failed its own guard and was
    /// dropped.
    private func disarm() {
        armedSeam = nil
        // The kind the + chose was this bar's, and the bar has gone.
        armedType = .text
        focusedSeam = nil
    }

    /// The seam under the pointer stops being one, though the pointer
    /// has not moved: a cell opened where it was, or the brackets took
    /// the page.
    ///
    /// The cursor has to be handed back HERE. `.ended` comes later, when
    /// the pointer finally moves, and by then no seam answers for it —
    /// so the horizontal I-beam went with the pointer to the toolbar and
    /// the sidebar, which is the leak the hand-back exists to stop. The
    /// same question `.ended` asks, so that a cursor somebody else has
    /// set in the meantime is still left alone.
    private func dropHover() {
        let back = Self.cursor(hovering: false, ours: true, put: seamCursor)
        hovered = nil
        seamCursor = nil
        back?.set()
    }

    /// A key while this seam is armed.
    private func key(_ press: KeyPress, in id: SeamID) -> KeyPress.Result {
        guard armedSeam == id else { return .ignored }
        // Escape, Return and the arrows by name: what `characters` carries
        // for them is AppKit's business, and the meaning is not.
        let characters: String
        switch press.key {
        case .escape: characters = "\u{1B}"
        case .return: characters = "\r"
        case .upArrow: characters = "\u{F700}"
        case .downArrow: characters = "\u{F701}"
        default: characters = press.characters
        }
        let meaning = Self.seamKey(characters: characters, modifiers: press.modifiers)
        switch meaning {
        case .pass:
            // Whatever it was, the bar is not what it was meant for, and
            // a bar left armed off the top of a scrolled page opens a
            // cell somewhere he cannot see (docs/FEATURES.md: "Escape, an
            // arrow or a click anywhere else takes the line back without
            // leaving an empty cell behind"). The markdown pane's
            // `doCommand(by:)` does the same, and hands the key on to
            // NSTextView only when it cannot edit (`CellSeams.handsOn`).
            disarm()
            return .ignored
        case .disarm:
            disarm()
            return .handled
        case .step(let up):
            walk(from: id, up: up)
            return .handled
        case .empty, .write:
            // The kind is read here, before `openSeam` disarms and puts
            // it back to plain text.
            openSeam(meaning, as: armedType, at: id.offset)
            return .handled
        }
    }

    /// ↑ or ↓ out of the bar: into the cell above or the cell below it,
    /// which is the other half of walking cell, bar, cell. At the two ends
    /// of the note there is no cell that way and the bar simply stays.
    private func walk(from id: SeamID, up: Bool) {
        let cells = items
        if up {
            guard id.index > 0 else { return }
            beginEditing(cells[id.index - 1].range)
        } else {
            guard id.index < cells.count else { return }
            beginEditing(cells[id.index].range, caret: .start)
        }
    }

    /// ↑ or ↓ off the end of a CELL: the bar beside it, not the next cell
    /// and never a new one (the plan's step 4 — "Nothing is written until
    /// a key says so"). ↓ off the last cell used to run `insertBlock` at
    /// the end of the note, so an arrow key wrote two newlines into the
    /// file and left an empty cell behind every time it was pressed.
    private func armSeam(beside cell: NSRange, below: Bool, bringingIntoView: Bool = false) {
        editingRange = nil
        let cells = items
        let all = seams
        guard let index = cells.firstIndex(where: { $0.range.location == cell.location }) else { return }
        let wanted = below ? index + 1 : index
        guard wanted >= 0, wanted < all.count else { return }
        arm(SeamID(index: wanted, offset: all[wanted].offset))
        // A BAR OFF THE BOTTOM OF THE WINDOW IS NO CURSOR AT ALL. An
        // answer is written whole and can be a screenful of it, so the
        // bar under a cell that has just run is routinely below the
        // fold — and the page does not move for an arm no pointer made.
        // The markdown pane has always scrolled
        // (`EditorBridge.armBar`); this one is asked through the state
        // below, because `armSeam` is outside `body` and the row it
        // wants does not EXIST yet: the answer was written into
        // `markdown` a moment ago and SwiftUI has not rebuilt the page,
        // so a proxy asked here scrolls to an id that is not on it and
        // does nothing at all (measured, 2026-09-22).
        if bringingIntoView { bringIntoView = SeamRow(index: wanted) }
    }

    /// The cell that key opens, put on the page: the note as `opened` made
    /// it, and the new cell being edited with what was typed already in it.
    private func openSeam(_ key: SeamKey, as type: CellTypes.Kind, at offset: Int) {
        disarm()
        dropHover()
        guard let opened = Self.opened(key, as: type, at: offset, in: markdown) else { return }
        markdown = opened.markdown
        // A drawing cell is never opened as its markdown: the line is the
        // file's name, and an editor on it is a way to break it. The cell
        // itself is the cursor — and whatever was open is closed, since a
        // drawing under its caret's line has just moved the rest of it.
        guard type != .drawing else {
            beginDrawing(opened.editing, clicked: false)
            return
        }
        // Plain text unless the + on this bar said otherwise, whatever the
        // cell above it was (Sean, 2026-09-19: "default is always just
        // text").
        fence = opened.fence
        draft = opened.draft
        editingRange = opened.editing
        // Behind what was typed — which for an empty cell is the same place.
        caret = .end
        focusToken += 1
    }

    /// THE CURSOR INTO A DRAWING CELL on this page. The other cursors go
    /// out, as they do for any: a bar, an open cell, cells held.
    private func beginDrawing(_ line: NSRange, clicked: Bool = true) {
        guard editable else { return }
        if clicked { onClick?() }
        disarm()
        dropHover()
        selectedCells = []
        cursor = .drawing(line)
        // A turn late, the way the brackets take the keyboard: a row this
        // very edit made is not on the page to be focused yet.
        DispatchQueue.main.async { focusedDrawing = line.location }
    }

    /// The drawing cell a cursor is in, by its id.
    private func drawingCell(of cursor: Cursor) -> UUID? {
        guard case .drawing(let line) = cursor, NSMaxRange(line) <= (markdown as NSString).length else { return nil }
        return DrawingCells.parse((markdown as NSString).substring(with: line)
            .trimmingCharacters(in: .whitespaces))?.id
    }

    /// A key while a drawing cell is the cursor — the table both panes keep
    /// (`DrawingCells.Key`). For anything that writes, the cell stands in
    /// for the bar under it.
    private func drawingKey(_ press: KeyPress, in line: NSRange) -> KeyPress.Result {
        guard cursor == .drawing(line) else { return .ignored }
        // Escape, Return, the arrows and the deletes by name: what
        // `characters` carries for them is AppKit's business.
        let characters: String
        switch press.key {
        case .escape: characters = "\u{1B}"
        case .return: characters = "\r"
        case .upArrow: characters = "\u{F700}"
        case .downArrow: characters = "\u{F701}"
        case .delete: characters = "\u{8}"
        case .deleteForward: characters = "\u{7F}"
        default: characters = press.characters
        }
        let after = DrawingCells.seamAfter(line, in: markdown)
        switch DrawingCells.key(characters: characters, chord: !press.modifiers.isDisjoint(with: [.command, .control])) {
        case .write(let typed):
            openSeam(.write(typed), as: .text, at: after)
        case .empty:
            openSeam(.empty, as: .text, at: after)
        case .hold:
            selectCells([line])
        case .step(let up):
            armSeam(beside: line, below: !up)
        case .leave:
            cursor = .none
            focusedDrawing = nil
        case .pass:
            return .ignored
        }
        return .handled
    }

    /// Where the drawing cells are on this page, told to the layer over it
    /// — only when one has moved. Off the stack the page is laid out by,
    /// at the page's left margin, in the column its margins leave.
    private func tellDrawingFrames(_ measured: [CellSeams.Box]? = nil) {
        guard let onDrawingFrames,
              let cells = measured ?? Self.cells(of: items.map { ($0.id, rowHeights[$0.id]) }) else { return }
        let frames = Self.drawingFrames(blocks: items.map { ($0.id, $0.range, $0.block) }, cells: cells,
                                        column: max(0, pageWidth - Self.sideInset * 2), shown: drawingCells)
        guard CellFrame.moved(toldFrames, frames) else { return }
        toldFrames = frames
        onDrawingFrames(frames)
    }

    /// The frames of the drawing cells among a page's rows, measured as
    /// `cells`: each at the column's left, the size it is shown in it.
    static func drawingFrames(blocks: [(id: Int, range: NSRange, block: MarkdownBlock?)], cells: [CellSeams.Box],
                              column: CGFloat, shown: DrawingCellsShown) -> [CellFrame] {
        blocks.compactMap { row in
            guard case .drawing(let id, _)? = row.block,
                  let box = cells.first(where: { $0.offset == row.id }) else { return nil }
            let look = shown.look(id)
            let (scale, size) = look.shown(column: column)
            return CellFrame(id: id, line: row.range,
                             rect: CGRect(x: sideInset, y: box.top, width: size.width, height: size.height),
                             scale: scale, width: look.cell.map { CGFloat($0.width) } ?? column,
                             writable: look.state == .writable)
        }
    }

    /// ⌘0 on this page: the cell goes where `drawingCellLanding` says.
    private func drawingCellHere() {
        guard let at = Self.drawingCellLanding(open: openCell, caret: caretInNote, seams: seams,
                                               middle: scrolled + pageHeight / 2, in: markdown)
        else { return }
        openSeam(.empty, as: .drawing, at: at)
    }

    /// WHERE ⌘0 PUTS A DRAWING ON THIS PAGE: under the caret's line of the
    /// cell that is open — the markdown pane's own rule — or, with nothing
    /// open, at the seam nearest the middle of what is on screen. Never
    /// after the note's first cell for want of an open one, which is where
    /// `caretCell()` would put it.
    static func drawingCellLanding(open: NSRange?, caret: Int, seams: [CellSeams.Seam],
                                   middle: CGFloat, in markdown: String) -> Int? {
        if open != nil { return DrawingCells.landing(caret: caret, in: markdown) }
        return CellSeams.nearest(toLine: middle, in: seams)?.offset
    }

    /// Every keystroke goes straight into the note, at the block's own range.
    /// Nothing is held back to be "committed", so a click anywhere else, a
    /// crash, or a save in between can never lose what was typed.
    private var draftBinding: Binding<String> {
        Binding(get: { draft }, set: { typed in
            draft = typed
            guard let range = editingRange else { return }
            let ns = markdown as NSString
            guard NSMaxRange(range) <= ns.length else { return }
            let stored = fence.map {
                MarkdownFormatting.refenced(open: $0.open, body: typed, close: $0.close)
            } ?? typed
            markdown = ns.replacingCharacters(in: range, with: stored)
            editingRange = NSRange(location: range.location, length: (stored as NSString).length)
        })
    }

    // MARK: - One reminder of a checklist

    /// Open ONE item's words, with its box left alone. The other cursors
    /// go out the way `beginEditing` puts them out — two cursors is what
    /// he was looking at before. `clicked` is false for the one way in
    /// that is not a click (`reopen`).
    private func openItem(_ words: NSRange, caret: BlockEditor.Caret, clicked: Bool = true) {
        guard editable else { return }
        if clicked { onClick?() }
        disarm()
        selectedCells = []
        itemDraft = (markdown as NSString).substring(with: words)
        editingItem = words
        self.caret = caret
        focusToken += 1
    }

    /// Every keystroke straight into the note, over the item's words and
    /// nothing else — the box, the marker and the indent are outside the
    /// range, so they cannot be typed over or deleted by accident.
    private var itemBinding: Binding<String> {
        Binding(get: { itemDraft }, set: { typed in
            itemDraft = typed
            guard let range = editingItem else { return }
            let ns = markdown as NSString
            guard NSMaxRange(range) <= ns.length else { return }
            markdown = ns.replacingCharacters(in: range, with: typed)
            editingItem = NSRange(location: range.location, length: (typed as NSString).length)
        })
    }

    /// Return in an item: the next reminder, open and empty.
    private func splitItem(head: String, tail: String) {
        guard let range = editingItem,
              let split = ListEditing.split(markdown, item: range, head: head, tail: tail)
        else { return }
        markdown = split.markdown
        openItem(split.editing, caret: .start)
    }

    /// Backspace in an item with nothing in it: the item goes. The last
    /// one of a checklist takes the cell with it, which is what ⌫ in an
    /// empty CELL has always done.
    private func removeItem() {
        guard let range = editingItem,
              let gone = ListEditing.removeEmpty(markdown, item: range)
        else { return }
        if let above = gone.editing {
            markdown = gone.markdown
            openItem(above, caret: .end)
            return
        }
        // Nothing above it in the list: if the cell has no reminders left
        // it goes too, and the note closes up behind it.
        let cell = openCell
        markdown = gone.markdown
        cursor = .none
        guard let cell,
              let block = MarkdownParser.positioned(from: gone.markdown)
                .first(where: { $0.range.location == cell.location })
        else { return }
        if case .blank = block.block {
            let (updated, previous) = PreviewEditing.removeBlock(gone.markdown, at: block.range)
            markdown = updated
            if let previous { beginEditing(previous) }
        }
    }

    /// Backspace at the start of words that are not empty: they join the
    /// reminder above.
    private func joinItemToPrevious() {
        guard let range = editingItem,
              let joined = ListEditing.joinPrevious(markdown, item: range)
        else { return }
        markdown = joined.markdown
        guard let above = ListEditing.reminder(
            forText: NSRange(location: joined.editing.location, length: 0),
            in: joined.markdown as NSString) ?? nearestReminder(at: joined.editing.location)
        else { return }
        openItem(above.text, caret: .at(joined.editing.location - above.text.location))
    }

    private func nearestReminder(at offset: Int) -> Reminder? {
        let ns = joinedText
        let line = ns.lineRange(for: NSRange(location: min(offset, max(ns.length - 1, 0)), length: 0))
        return ListEditing.reminder(onLineAt: line, in: ns)
    }

    private var joinedText: NSString { markdown as NSString }

    /// ↑ and ↓ inside an item walk the list before they leave the cell,
    /// and Escape puts the caret away.
    private func moveFromItem(_ move: BlockEditor.Move) {
        guard let range = editingItem, let cell = openCell else { return }
        let all = ListEditing.reminders(in: cell, of: markdown as NSString)
        let here = all.firstIndex { $0.text.location == range.location }
        switch move {
        case .out:
            cursor = .none
        case .up:
            if let here, here > 0 { openItem(all[here - 1].text, caret: .end) }
            else { armSeam(beside: cell, below: false) }
        case .down:
            if let here, here + 1 < all.count { openItem(all[here + 1].text, caret: .end) }
            else { armSeam(beside: cell, below: true) }
        }
    }

    private func beginEditing(_ range: NSRange, caret: BlockEditor.Caret = .end, clicked: Bool = true) {
        guard editable else { return }
        // EVERY WAY INTO A CELL comes through here — a bracket, an arrow
        // off the next cell, a cell moved or duplicated, the one ⌫ left
        // behind — and a drawing cell is never opened as its line.
        if MarkdownParser.positioned(from: markdown)
            .contains(where: { NSEqualRanges($0.range, range) && $0.block.isDrawing }) {
            return beginDrawing(range, clicked: clicked)
        }
        if clicked { onClick?() }
        // Two cursors is what he was looking at before: a block with a
        // caret in it is not a seam with a bar in it, and neither of them
        // is a handful of cells held by their brackets.
        disarm()
        selectedCells = []
        let ns = markdown as NSString
        guard NSMaxRange(range) <= ns.length else { return }
        let source = ns.substring(with: range)
        // A fenced block is opened as its CODE: the fences stay put and
        // what is typed is coloured for the language they name.
        if let parts = MarkdownFormatting.fenced(source) {
            fence = Fence(open: parts.open, close: parts.close)
            draft = parts.body
        } else {
            fence = nil
            draft = source
        }
        editingRange = range
        self.caret = caret
        focusToken += 1
    }

    /// Something to type in: whatever is already open, else the cell at
    /// the top of the window — where the eye is, and not the note's first
    /// cell, which a command pressed straight after ⌘T used to open and
    /// restyle wherever the page was scrolled — and a new one when the
    /// note is empty.
    private func openSomething() -> Bool {
        guard editable else { return false }
        if cursor != .none { return true }
        let shown = items
        guard let first = shown.first else {
            insertBlock(at: (markdown as NSString).length)
            return true
        }
        let top = Self.cells(of: shown.map { ($0.id, rowHeights[$0.id]) })
            .flatMap { CellPlace.at(scrolled, in: $0) }
        beginEditing((shown.first { $0.id == top?.cell } ?? first).range)
        return true
    }

    /// This page's cursor, as ⌘T carries it (`PaneCaret`): the armed bar,
    /// the cells held, or the caret in whatever is open.
    private var paneCaret: PaneCaret? {
        if let seam = armedSeam { return .bar(offset: seam.offset, kind: armedType) }
        if !selectedCells.isEmpty { return .cells(selectedCells) }
        let inside = bridge.textView?.selectedRange() ?? NSRange(location: 0, length: 0)
        switch cursor {
        case .none: return nil
        case .cell(let range): return PaneCaret.rendered(open: range, inside: inside, fence: fence?.open)
        case .item(let words): return PaneCaret.rendered(open: words, inside: inside, fence: nil)
        // The markdown pane's caret in a drawing cell is at its line's end.
        case .drawing(let line): return .text(NSRange(location: NSMaxRange(line), length: 0))
        }
    }

    /// The cursor the markdown pane was holding when ⌘T was pressed, put
    /// back on this page — without the click every other way of opening
    /// a cell is, which would let go of whatever the drawing layer has
    /// picked up (it is kept across the switch).
    private func reopen(_ caret: PaneCaret) {
        switch caret.opening(in: markdown) {
        case .cell(let range, let selection)?:
            beginEditing(range, caret: .range(selection), clicked: false)
        case .item(let words, let selection)?:
            openItem(words, caret: .range(selection), clicked: false)
        case .drawing(let line)?:
            beginDrawing(line, clicked: false)
        case .cells(let ranges)?:
            selectedCells = ranges
            DispatchQueue.main.async { focusedBrackets = true }
        case .bar(let offset, let kind)?:
            guard seamsEnabled else { return }
            let found = seams.firstIndex { $0.offset == offset }
                ?? items.firstIndex { $0.range.location == offset }
                ?? (offset >= (markdown as NSString).length ? items.count : nil)
            guard let index = found else { return }
            let id = SeamID(index: index, offset: offset)
            // A turn late, the way the brackets take the keyboard: the
            // seam has to be on the page before it can be focused, and a
            // focus that does not take reads as the bar being put out.
            DispatchQueue.main.async {
                armedSeam = id
                armedType = kind
                focusedSeam = id
            }
        case nil:
            break
        }
    }

    /// Moving a section from the preview moves it in the whole note, with
    /// the block being edited standing in for the caret.
    /// Where each cell sits on the rendered page, measured.
    private var places: [Int: (top: CGFloat, bottom: CGFloat)] {
        PreviewLayout.positions(rows: items.map { ($0.id, rowHeights[$0.id] ?? 0) },
                                spacing: Self.blockGap, top: Self.topInset + Self.gapHeight)
    }

    /// A whole-cell edit — delete, duplicate, move — over the note: every
    /// cell whose bracket is lit, and the one that is open (or the first)
    /// when none is. A cell on this side is a block, so the edit cannot go
    /// through one block's own text view (Sean, 2026-09-20: "make cells
    /// behave like mathematica cells").
    ///
    /// Back to front, through `CellCommands.edits`, which is what lets ⌃⌫
    /// take three cells at once: an edit made in front of another would
    /// have moved the characters the second one names.
    private func cellEdit(_ make: (NSRange, String) -> MarkdownFormatting.Edit?) {
        applyCellEdits(CellCommands.edits(over: heldCells, in: markdown, make: make))
    }

    /// The cells a whole-cell command acts on: every one whose bracket is
    /// held, and the one open for typing (or the first) when none is.
    private var heldCells: [NSRange] {
        selectedCells.isEmpty
            ? [openCell ?? items.first?.range].compactMap { $0 }
            : selectedCells
    }

    /// What is still held after a whole-cell command: the cells the edit's
    /// landing selection covers.
    ///
    /// Three cells moved or duplicated stay held, so pressing ⌃⇧↓ twice
    /// walks the same three down the page. The page used to let go of them
    /// and open the landing cell for typing, and the second press then
    /// moved one cell out of the run it had just made. The markdown pane
    /// never had the fault — `tv.selectedRanges` keeps the run — and the
    /// two panes are meant to behave the same (2026-09-20).
    static func stillHeld(after landing: NSRange, in text: String) -> [NSRange] {
        CellSelection.picked(cells: MarkdownParser.positioned(from: text).map(\.range),
                             selection: [landing])
    }

    private func applyCellEdits(_ edits: [MarkdownFormatting.Edit]) {
        guard let landing = edits.last?.selection else { return }
        var text = markdown as NSString
        for edit in edits { text = text.replacingCharacters(in: edit.range, with: edit.replacement) as NSString }
        let updated = text as String
        let wasHolding = !selectedCells.isEmpty
        markdown = updated
        let still = Self.stillHeld(after: landing, in: updated)
        if wasHolding, !still.isEmpty {
            selectedCells = still
            editingRange = nil
            // The column keeps the keyboard, the way it had it before the
            // command: what is held can be typed over, moved again, taken.
            DispatchQueue.main.async { focusedBrackets = true }
            return
        }
        selectedCells = []
        // Follow the cell: to where it went, or to whatever moved up into
        // the place of the one that was taken away.
        if let block = MarkdownParser.positioned(from: updated)
            .first(where: { NSLocationInRange(landing.location, $0.range)
                || $0.range.location == landing.location }) {
            beginEditing(block.range)
        } else {
            editingRange = nil
        }
    }

    /// Joining the open cell to the one after it. The seam is between two
    /// blocks, so it is the note that is edited, not the block's own text
    /// view (Sean, 2026-09-19: "cmd+d and cmd+m to split and merge cells").
    private func mergeCells() {
        let caret = caretInNote
        guard let edit = NotebookCells.merge(text: markdown,
                                             selection: NSRange(location: caret, length: 0))
        else { return }
        let updated = (markdown as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        markdown = updated
        // Stay in the cell the two became.
        if cursor != .none,
           let block = MarkdownParser.positioned(from: updated)
            .first(where: { NSLocationInRange(edit.selection.location, $0.range) }) {
            beginEditing(block.range)
        }
    }

    /// Cutting the open cell in two, and leaving the bar between the
    /// halves (Sean, 2026-09-20: "when dividing a cell, the cursor should
    /// go inbetween the new cells").
    ///
    /// The note's edit and not the block's, the same as the merge: the
    /// moment the cut is made the two halves are two blocks, and the
    /// block editor that was holding the caret is holding a range that
    /// spans both of them. Closing it and arming the seam under the head
    /// is what "the cursor is between the cells" means on this side —
    /// the markdown pane gets there by the caret alone, but there is no
    /// caret here to follow.
    private func splitCell() {
        let caret = caretInNote
        guard let cell = NotebookCells.block(containing: caret, in: markdown),
              let edit = NotebookCells.split(text: markdown,
                                             selection: NSRange(location: caret, length: 0))
        else { return }
        markdown = (markdown as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        // Nothing before the cut moved, so the head still begins where the
        // whole cell did — and the seam under it is the one between them.
        armSeam(beside: cell.range, below: true)
    }

    // MARK: - ⌘8, ⌘9 and the maths palette

    /// WHERE THIS PAGE'S CARET IS, IN THE NOTE — what `Insertion` is asked
    /// with, so the page and the source pane give one answer for one place
    /// (Sean, 2026-10-02: "make math and code block insertion sensible..").
    ///
    /// The bar is its own offset. An open cell's caret is the cell's start
    /// plus how far into its editor the caret is — past the fence line for
    /// a code cell, whose editor holds its code alone; an open reminder's,
    /// its words' start plus that. Cells held by their brackets are the
    /// first of them, whole. With nothing open, it is where `openSomething`
    /// would have put the caret: the end of the note's first cell.
    static func insertionSpot(in markdown: String, cursor: Cursor, fence: Fence?, inEditor: NSRange?,
                              bar: Int?, held: [NSRange]) -> (selection: NSRange, atBar: Bool) {
        if let bar { return (NSRange(location: bar, length: 0), true) }
        let inside = inEditor ?? NSRange(location: 0, length: 0)
        switch cursor {
        case .cell(let range):
            let lead = fence.map { ($0.open as NSString).length + 1 } ?? 0
            return (NSRange(location: range.location + lead + inside.location, length: inside.length), false)
        case .item(let words):
            return (NSRange(location: words.location + inside.location, length: inside.length), false)
        case .none:
            if let first = held.min(by: { $0.location < $1.location }) { return (first, false) }
            let end = MarkdownParser.positioned(from: markdown).first.map { NSMaxRange($0.range) } ?? 0
            return (NSRange(location: end, length: 0), false)
        }
    }

    /// The cell an insertion left the caret in, and where the caret goes in
    /// the editor that opens it: past the fence line in a fenced cell.
    static func landing(at caret: Int, in markdown: String) -> (cell: NSRange, caret: Int) {
        let cell = CellTypes.cell(at: caret, in: markdown)
        let source = (markdown as NSString).substring(with: cell)
        let lead = MarkdownFormatting.fenced(source).map { ($0.open as NSString).length + 1 } ?? 0
        return (cell, max(0, caret - cell.location - lead))
    }

    /// An insertion that stays in the words of the cell open in front of
    /// it — inline maths, the bare WL in a maths cell — in that editor's
    /// own coordinates, so it goes through the editor and onto the
    /// editor's own undo stack like a keystroke. Nil for anything that
    /// makes a cell: that is the note's, and opens the cell it made.
    static func editorEdit(_ edit: MarkdownFormatting.Edit, cursor: Cursor, fence: Fence?,
                           draftLength: Int) -> MarkdownFormatting.Edit? {
        guard !edit.replacement.contains("\n") else { return nil }
        let start: Int
        switch cursor {
        case .none: return nil
        case .cell(let range): start = range.location + (fence.map { ($0.open as NSString).length + 1 } ?? 0)
        case .item(let words): start = words.location
        }
        guard edit.range.location >= start, NSMaxRange(edit.range) <= start + draftLength,
              edit.selection.location >= start else { return nil }
        return MarkdownFormatting.Edit(
            range: NSRange(location: edit.range.location - start, length: edit.range.length),
            replacement: edit.replacement,
            selection: NSRange(location: edit.selection.location - start, length: edit.selection.length))
    }

    /// What `Insertion` says, carried out on this page: in the open
    /// editor when it stays in its words, otherwise over the note — and
    /// then the cell the caret landed in opens, a code cell as its code,
    /// with the caret where typing goes.
    private func insert(_ thing: Insertion.Thing) {
        guard editable else { return }
        let inEditor = cursor == .none ? nil : bridge.textView?.selectedRange()
        let spot = Self.insertionSpot(in: markdown, cursor: cursor, fence: fence, inEditor: inEditor,
                                      bar: armedSeam?.offset, held: selectedCells)
        switch Insertion.insert(thing, in: markdown, at: spot.selection, atBar: spot.atBar) {
        case .refused(let why):
            bridge.say?(why.message)
        case .edit(let edit):
            let open = ((editingItem == nil ? draft : itemDraft) as NSString).length
            if !spot.atBar, bridge.textView != nil,
               let local = Self.editorEdit(edit, cursor: cursor, fence: fence, draftLength: open) {
                bridge.applyInsertion(local)
                return
            }
            let before = markdown, was = cursor, held = selectedCells, bar = armedSeam
            let caretWas = inEditor?.location ?? 0
            // THE EDITOR WITH THE KEYBOARD LETS GO FIRST. A cell made where
            // the open one started has the same place on the page, so
            // SwiftUI hands it the same editor — and an editor holding the
            // keyboard takes no text from outside, so it kept the old
            // words and the next keystroke wrote them over the code.
            bridge.textView?.window?.makeFirstResponder(nil)
            markdown = (markdown as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
            let landing = Self.landing(at: edit.selection.location, in: markdown)
            beginEditing(landing.cell, caret: .at(landing.caret))
            offerUndo(restoring: before, cursor: was, caret: caretWas, held: held, bar: bar)
        }
    }

    /// ONE ⌘Z TAKES IT BACK, the way it does in the source pane. A change
    /// to the whole note has no text view of its own to be undone in, so
    /// the way back is put on the undo stack of the editor the new cell
    /// opened in — first, under anything typed into it afterwards, and
    /// gone with that editor when the cell closes, the way everything
    /// typed in a cell on this page is. It waits for that editor: SwiftUI
    /// builds it a turn or two after the cell opens.
    ///
    /// AND IT GOES ON TOP of what that editor's stack holds already. A cell
    /// that opens where the open one started is handed the same editor —
    /// ⌘9 turning a code cell rewrites only its fence line, so it IS the
    /// same cell — and emptying the stack first (as this did until the
    /// review of 2026-10-02) took away the undo of everything typed in it,
    /// which the source pane's ⌘9 never does. The steps under the way back
    /// are reached only through it, and it reopens the cell they were
    /// typed in, as it was, before any of them is undone.
    private func offerUndo(restoring before: String, cursor was: Cursor, caret: Int, held: [NSRange],
                           bar: SeamID?, attempts: Int = 10) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            guard let view = bridge.textView as? BlockTextView, view.window?.firstResponder === view,
                  let undo = view.undoManager
            else {
                if attempts > 0 {
                    offerUndo(restoring: before, cursor: was, caret: caret, held: held, bar: bar,
                              attempts: attempts - 1)
                }
                return
            }
            undo.registerUndo(withTarget: view) { view in
                view.window?.makeFirstResponder(nil)
                markdown = before
                switch was {
                case .cell(let range): beginEditing(range, caret: .at(caret))
                case .item(let words): openItem(words, caret: .at(caret))
                case .none:
                    cursor = .none
                    selectedCells = held
                    if let bar { arm(bar) }
                }
            }
        }
    }

    private func moveWholeSection(up: Bool) {
        let caret = openCell?.location ?? 0
        guard let edit = NotebookOutline.moveSection(text: markdown,
                                                     selection: NSRange(location: caret, length: 0), up: up)
        else { return }
        let updated = (markdown as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        markdown = updated
        // Follow the section to where it went.
        if cursor != .none {
            let parsed = MarkdownParser.positioned(from: updated)
            let landing = edit.selection.location
            if let block = parsed.first(where: { NSLocationInRange(landing, $0.range) }) ?? parsed.first {
                beginEditing(block.range)
            }
        }
    }

    private func insertBlock(at offset: Int) {
        guard editable else { return }
        let (updated, opened) = PreviewEditing.insertBlock(in: markdown, at: offset)
        markdown = updated
        // Always a plain text cell, whatever the cell above it was (Sean,
        // 2026-09-19: "default is always just text").
        fence = nil
        draft = ""
        editingRange = NSRange(location: opened, length: 0)
        caret = .start
        focusToken += 1
        disarm()
        dropHover()
    }

    private func split(head: String, tail: String) {
        guard let range = editingRange, fence == nil else { return }
        let (updated, editing) = PreviewEditing.split(markdown, at: range, head: head, tail: tail)
        markdown = updated
        draft = tail
        editingRange = editing
        caret = .start
        focusToken += 1
    }

    private func removeBlock() {
        guard let range = editingRange else { return }
        let (updated, previous) = PreviewEditing.removeBlock(markdown, at: range)
        markdown = updated
        if let previous {
            beginEditing(previous)
        } else {
            editingRange = nil
        }
    }

    private func move(_ move: BlockEditor.Move) {
        guard let range = editingRange else { return }
        switch move {
        case .out:
            disarm()
            editingRange = nil
        case .up:
            armSeam(beside: range, below: false)
        case .down:
            armSeam(beside: range, below: true)
        }
    }

    /// Return adds a line to a list, a quote or a fenced block; anywhere else
    /// it starts the next block.
    private static func keepsNewlines(_ block: MarkdownBlock?) -> Bool {
        switch block {
        case .bullets, .todos, .dashes, .numbered, .quote, .code: return true
        default: return false
        }
    }

    // MARK: - Rendering

    struct BlockView: View {
        let block: MarkdownBlock
        /// Ticking the nth box of a task list. Nil on paper and anywhere
        /// else the note cannot be written to.
        var onToggleTodo: ((Int) -> Void)?
        /// What a code cell needs to be run and to say what it runs as.
        /// Nil on paper and anywhere else the note cannot be written to —
        /// the PDF export builds a `BlockView` with nothing but its block.
        var evaluation: Evaluation?

        struct Evaluation {
            var role: CellMark.Role
            var isRunning: Bool
            var onPick: (Evaluator) -> Void
        }

        /// What a CHECKLIST needs to let one of its items be typed in.
        /// Nil for every other kind of block, and nil on paper — the PDF
        /// export builds a `BlockView` with nothing but its block, and
        /// an `ImageRenderer` draws an AppKit text view as nothing at all.
        var editing: ChecklistEditing?
        /// A drawing cell that is the page's cursor: its outline is lit.
        var drawingLit = false
        @Environment(\.notePaper) private var paper
        @Environment(\.drawingCells) private var drawingCells

        /// The one item of a checklist that is open for typing, and
        /// everything it needs to be.
        ///
        /// Keyed by the RANGE OF ITS WORDS and not by an index: an index
        /// goes stale the moment a line is added above it, and this view
        /// is rebuilt from the note on every keystroke.
        struct ChecklistEditing {
            var openWords: NSRange?
            /// The reminders of this cell, in the order they are drawn.
            var items: [Reminder]
            var text: Binding<String>
            var focusToken: Int
            var caret: BlockEditor.Caret
            var bridge: EditorBridge
            var onOpen: (Reminder, BlockEditor.Caret) -> Void
            var onSplit: (String, String) -> Void
            var onDeleteEmpty: () -> Void
            var onJoinPrevious: () -> Void
            var onMove: (BlockEditor.Move) -> Void

            func isOpen(_ index: Int) -> Bool {
                guard let openWords, index < items.count else { return false }
                return NSEqualRanges(openWords, items[index].text)
            }
        }

        var body: some View {
            // ONE LINE SPACING FOR THE WHOLE NOTE, not one for
            // paragraphs alone. The source pane sets it on its paragraph
            // style, which every line of the note is laid out with; here
            // it was on `.paragraph` and nowhere else, so a bullet, a
            // quote or a heading that wrapped came out four points a
            // line tighter than the same words in the other mode — and
            // tighter than the paragraph beside it, which is what made
            // the page read as scrunched even where the gaps were right.
            content.lineSpacing(MarkdownTextView.paragraphStyle.lineSpacing)
        }

        @ViewBuilder
        private var content: some View {
            switch block {
            case .heading(let level, let text):
                Text(MarkdownInline.attributed(text, baseSize: Self.headingSize(level), paper: paper))
                    .font(Self.headingFont(level))
                    .italic(level == 6)
                    .foregroundStyle(level >= 5 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            case .paragraph(let text):
                Text(MarkdownInline.attributed(text, paper: paper))
                    .font(.system(size: 15))
            case .bullets(let items):
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            Text(MarkdownInline.attributed(item, paper: paper)).font(.system(size: 15))
                        }
                    }
                }
                .padding(.leading, 8)
            case .todos(let items):
                // A task list: the box is the control, and only the box —
                // and it STAYS the control while the words beside it are
                // being typed (Sean, 2026-09-21: "when modifying a
                // checklist.. the checkboxes remain in tact and just the
                // text part of the list becomes editable, one at a time").
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button { onToggleTodo?(index) } label: {
                                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 14))
                                    .foregroundStyle(item.done ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(onToggleTodo == nil)
                            .help(item.done ? "Done — click to undo it" : "Click when it is done")
                            // A BOX IS A BUTTON, so it takes the hand —
                            // the app's own rule for the + on the bar and
                            // for the brackets, and the cell's I-beam was
                            // running straight over it.
                            .pointingHand(enabled: onToggleTodo != nil)
                            words(of: item, at: index)
                        }
                    }
                }
                .padding(.leading, 8)
            case .dashes(let items):
                // The same list, written with `* `, marked with a dash.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\u{2013}").foregroundStyle(.secondary)
                            Text(MarkdownInline.attributed(item, paper: paper)).font(.system(size: 15))
                        }
                    }
                }
                .padding(.leading, 8)
            case .numbered(let items):
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                            Text(MarkdownInline.attributed(item, paper: paper)).font(.system(size: 15))
                        }
                    }
                }
                .padding(.leading, 8)
            case .quote(let text):
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.6)).frame(width: 3)
                    Text(MarkdownInline.attributed(text, paper: paper))
                        .font(.system(size: 15))
                        .italic()
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            case .code(let language, let body) where MathMarkup.isMathFence(language):
                // Maths on its own line, set properly rather than shown as code.
                MathView(source: body, size: 21)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .code(let language, let body):
                // THE EVALUATOR'S DROPDOWN SITS AT THE FAR LEFT of a code
                // cell (Sean, 2026-09-21: "this type of cell has a drop
                // down icon on the far left picking the evaluator
                // environment.. WL just meant a WL icon there"). Picking
                // one rewrites the cell's fence, so the note carries the
                // choice and there is no second place for it to disagree
                // with. Not on an Out cell: an answer is not run.
                HStack(alignment: .top, spacing: 6) {
                    if let evaluation {
                        CellMark(role: evaluation.role, isRunning: evaluation.isRunning,
                                 onPick: evaluation.onPick)
                    }
                    codeBody(language, body)
                }
            case .blank(let lines):
                // A cell of empty lines: as tall as those lines, and
                // clickable, so it can be typed into (Sean, 2026-09-20).
                Color.clear
                    .frame(height: CGFloat(lines) * MarkdownTextView.lineHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .rule:
                // The only padding left on the page, and it is the rule's
                // own body rather than space round it: a `Divider` is one
                // point tall, and a one-point cell is a cell that neither
                // a bracket nor a seam can hold — the seams either side
                // would be widened to the 8 pt minimum straight through
                // it, and there would be nowhere left to click the rule.
                Divider().frame(height: 9)
            case .drawing(let id, _):
                DrawingCellRow(look: drawingCells.look(id), media: drawingCells.media, lit: drawingLit)
            }
        }

        /// Coloured when the fence names a language this app knows, plain
        /// monospace otherwise (Sean, 2026-09-19). The same size and the
        /// same spacing the source pane sets code at, and one source line
        /// of padding above and below — which is exactly what the two ```
        /// lines take over there. A code cell is then the same height on
        /// both sides, which it was not: the source showed two fence lines
        /// (about 44 points) where the page showed 24 points of padding,
        /// and a note full of code drifted a block at a time.
        @ViewBuilder
        private func codeBody(_ language: String?, _ body: String) -> some View {
            Text(CodeColours.attributed(body,
                                        language: CodeLanguage.colouring(fence: language) ?? .plain,
                                        size: MarkdownTextView.codeSize))
                .lineSpacing(MarkdownTextView.paragraphStyle.lineSpacing)
                .padding(.horizontal, 12)
                .padding(.vertical, MarkdownPreview.codePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CodeColours.background, in: RoundedRectangle(cornerRadius: 6))
        }


        /// ONE REMINDER'S WORDS: the rendered text, with the editor drawn
        /// OVER it when this is the item that is open.
        ///
        /// An overlay, not a swap. The `Text` keeps the row's height and
        /// its baseline whatever is over it, so opening an item moves
        /// neither the box beside it nor the cells, the seams, the
        /// brackets or the floating ink below it — all of which are laid
        /// out from the measured height of this row (`PreviewRowHeights`
        /// → `PreviewLayout.positions`). Swapping the `Text` for a text
        /// view grows the line by about five points, and everything under
        /// it slides.
        @ViewBuilder
        private func words(of item: TodoItem, at index: Int) -> some View {
            let open = editing?.isOpen(index) ?? false
            // An empty reminder still has to be a line tall, or there is
            // nothing to click and nowhere to draw the editor.
            Text(MarkdownInline.attributed(item.text.isEmpty ? " " : item.text, paper: paper))
                .font(.system(size: 15))
                // Done is struck through and faded, the way a finished
                // line in a notebook is.
                .strikethrough(item.done, color: .secondary)
                .foregroundStyle(item.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(open ? 0 : 1)
                .overlay(alignment: .topLeading) {
                    if open, let editing {
                        BlockEditor(text: editing.text,
                                    font: .systemFont(ofSize: 15),
                                    bridge: editing.bridge,
                                    focusToken: editing.focusToken,
                                    caret: editing.caret,
                                    metrics: .listItem,
                                    singleLine: true,
                                    onSplit: editing.onSplit,
                                    onDeleteEmpty: editing.onDeleteEmpty,
                                    onJoinPrevious: editing.onJoinPrevious,
                                    onMove: editing.onMove)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    guard let editing, index < editing.items.count else { return }
                    editing.onOpen(editing.items[index], Self.landing(in: item.text, at: point.x))
                }
        }

        /// Where the caret goes for a click at `x`. On the words as they
        /// were WRITTEN, when what is drawn is character for character
        /// what is in the note; at the end when it is not, because
        /// `**bold**` renders four characters shorter than it is written
        /// and an x through the rendered line means nothing in the source.
        static func landing(in source: String, at x: CGFloat) -> BlockEditor.Caret {
            let drawn = String(MarkdownInline.attributed(source).characters)
            return drawn == source ? .atX(x) : .end
        }

        /// Title · Header · Section · Subsection · Subsubsection · Author
        /// subheader — the last is italic and slightly BIGGER than body (15),
        /// not smaller, which is the whole point of it.
        static func headingSize(_ level: Int) -> CGFloat {
            switch level {
            case 1: return 28
            case 2: return 22
            case 3: return 18
            case 4: return 16
            case 5: return 15
            default: return 17
            }
        }

        static func headingFont(_ level: Int) -> Font {
            let size = headingSize(level)
            switch level {
            case 1: return .system(size: size, weight: .bold)
            case 2, 3, 4, 5: return .system(size: size, weight: .semibold)
            default: return .system(size: size, weight: .regular)
            }
        }

        /// What the in-place editor writes in. The heading sizes come from the
        /// `#` markers as they are typed, so this is only about code.
        static func editingNSFont(_ block: MarkdownBlock?) -> NSFont {
            if case .code = block { return .monospacedSystemFont(ofSize: 13, weight: .regular) }
            return .systemFont(ofSize: 15)
        }
    }
}


/// What the blocks are being drawn ON, as `#RRGGBB`.
///
/// Nil on screen, where the preview's background is the very thing the
/// colours were picked against. The PDF export sets it to white, because
/// paper is white whatever the window is, and a `<span style="color:…">`
/// that reads on a dark editor is not there at all on a printed page
/// (Sean, 2026-09-19: "be mindful of text color... it should always be
/// visible against the background"). `MarkdownInline` does the checking;
/// this only says what it is checking against.
struct NotePaperKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var notePaper: String? {
        get { self[NotePaperKey.self] }
        set { self[NotePaperKey.self] = newValue }
    }
}


/// The measured height of every block — what the stack is laid out from.
private struct PreviewRowHeights: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// How wide the page's content is.
private struct PreviewWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PreviewScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A point on the rendered page that its scroll view can be scrolled to
/// exactly: an NSView of NO SIZE, so the window's hit test never finds it
/// and no cursorUpdate is ever routed to it (the eighth cause, AGENTS.md).
struct PageMark: NSViewRepresentable {
    /// The view, for the page to measure — held weakly, so a page torn
    /// down takes it with it.
    final class Holder {
        weak var view: NSView?
    }

    let holder: Holder

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        holder.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { holder.view = view }
}
