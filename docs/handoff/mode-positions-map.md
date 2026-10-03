# What does not keep its place across ⌘T (markdown ⇄ rendered)

Read-only map. Worktree `wm-modes`, branch `mode-positions`, at f5285f8.
Paths are relative to `WriteMind/`. Measurements come from a standalone script
(`scratchpad/modemeasure/main.swift`). It rebuilds both panes' layout rules with
the app's own constants, TextKit 1 for the source and NSHostingView for the
rendered blocks, and compiles the real `Math/*.swift` for the maths cell. The
project was not built.

## What the toggle does

- `AppState.toggleMode` (AppState.swift:594-602) flips `mode` inside
  `withAnimation(.easeInOut(duration: 0.15))`. In `EditorPane` the two panes
  are the two branches of one `if` (Views/EditorPane.swift:32-79), so every
  toggle tears one pane down and builds the other from nothing. All
  `@State`, the NSTextView, its selection, its armed bar and its undo stack
  are lost. The drawing layer and the tablet layer are siblings of that `if`
  (EditorPane.swift:84-117), so they keep their identity and their own state.
- The only things carried across are in `NoteStore`: `text`, `drawing`,
  `collapsedHere`, `canvasScroll` and `topCell` (NoteStore.swift:39-47). The
  layer's `scrollOffset` is EditorPane `@State` (EditorPane.swift:13), and
  each pane overwrites it when it reports a scroll.
- **Sean runs with markers hidden.** `defaults read com.seancheren.WriteMind
  showMarkers` returns `0`. The app default is `true` (AppState.swift:473), so
  a fresh install shows raw markdown. Both cases are measured below, because
  the source pane's vertical rhythm is completely different in the two.

## (a) Scroll: which cell is at the top, and where inside it

**What exists.** The two panes agree on a CELL, identified by its character
offset, not on a number of points.
- Source reports the character at the fold: `cell(atTop:)` looks up the glyph
  at `y = scroll - inset + 1` (MarkdownTextView.swift:355-362), on every
  clip-view bounds change (:668-681). It restores by putting that character's
  LINE at the top (`offset(ofCell:)` :366-375), one runloop turn after
  `makeNSView` (:184, :657-665). It skips the restore when the offset is 0.
- Rendered reports `PreviewLayout.topRow`: the last row whose top is at most
  `scroll + 8` (PreviewLayout.swift:18-26), on every `PreviewScrollKey`
  change (MarkdownPreview.swift:386-397). It restores with
  `scrollTo(block.range.location, anchor: .top)` on the last parsed block at
  or before `topCell` (:447-453).

**What drifts.**

1. **The position inside the cell is thrown away, and a round trip snaps up
   to the cell's start.** Source to rendered: the rendered page puts the
   cell's TOP at the top. If the source showed line 3 of a 3-line paragraph,
   the rendered page shows its line 1, so the content drops 44 pt (two lines).
   For a long code cell or paragraph the drop is up to the whole cell, one
   line less (a 40-line code cell is about 840 pt). The rendered page's own
   `scrollTo` then fires `onTopCell(topRow)` and overwrites `store.topCell`
   with the cell's start. So source → rendered → source comes back to the
   cell's first line, not the line that was there. Rendered to source: the
   same loss, in reverse. `topRow` only knows rows, and the source puts that
   row's first line at the top. `TopCellTests.testSwitchingBackAndForthStaysOnTheSameCell`
   (WriteMindTests/PreviewLayoutTests.swift:107-115) pins the snap as intended.
   In that test, scroll 300 comes back as 194, a 106 pt jump. No test covers
   the source side (`cell(atTop:)`, `offset(ofCell:)`).
2. **The two panes use different tolerances, so the cell you see at the top
   often turns into the cell above it.**
   - Source: the fold is read 1 pt down. The last line fragment of cell k-1
     holds its 4 pt of lineSpacing and, with markers hidden, the 8 pt
     `paragraphSpacing` (MarkdownTextView.swift:499-506). The 2 pt blank
     separator line comes next (:507-511, MarkdownSourceStyle.swift:327). A
     fold anywhere in those ~14 pt above cell k reads a character of k-1 or of
     the blank line. `.last(where: location <= topCell)` turns that into
     k-1, so the rendered page opens on k-1. The content drops by k-1's
     rendered height + 26. With markers shown, the band is the whole blank
     line plus spacing, about 26 pt.
   - Rendered: the seam above cell k is `blockGap` = 26 pt and the tolerance
     is 8. A fold 8-26 pt above k (an 18 pt band) reads k-1, and the source
     opens on k-1's first line.
   - On a typical note (cell pitch about 50-70 pt) that is roughly one resting
     scroll position in four or five. The jump is a whole cell.
3. **The id is a character offset, and it goes stale under edits made without
   scrolling.** `topCell` is written only when a pane scrolls. Edits above the
   fold since the last scroll shift the real cell starts but not the stored
   number. Examples: an evaluation's answer written by `writeCell`, a section
   move (⌃⌘↑), an outside edit picked up by the folder watcher, or a paste.
   If 50 characters go in above, the stored offset lands in cell k-1. The
   rendered page opens on k-1 (a whole cell up); the source opens on the
   line holding that character (about a line up).
4. **Possible race, not proven.** `PreviewLayout.topRow` is computed from
   `rowHeights` (MarkdownPreview.swift:393-396). If the scroll preference
   from the `onAppear` `scrollTo` (:452) arrives before the row-height
   preference is in, the positions are 30 + i·26. That makes `topRow` report
   a cell far below the real one, and it stays wrong until the next scroll,
   because a row-height change does not re-fire the scroll key. Untested.
5. **`topCell` belongs to the store, not to the note (adjacent bug, a note
   switch rather than ⌘T).** It is never reset (NoteStore.swift:47; no other
   writer). The source resets it by accident: on a document change,
   `tv.scroll(.zero)` reports 0 (MarkdownTextView.swift:236). The rendered
   page is rebuilt per note (`.id(note.id)`, EditorPane.swift:78), and its
   `onAppear` applies the old note's offset to the NEW note's blocks. Switching
   tabs in rendered mode opens the next note on an arbitrary cell, or on its
   last cell if it is shorter. No note remembers its own scroll.
6. **Small effects.**
   - Near the end of a note neither pane can put the cell at the top: the
     source ends 20 pt under the last line, the rendered page 110 pt
     (`tailHeight`, MarkdownPreview.swift:286). Each clamps differently.
   - The first frame shows the layer at the wrong offset. The rendered page
     can report 0 before its `scrollTo` lands, so the drawing layer, driven
     by whichever pane reported last, jumps for a frame.
   - During the 0.15 s cross-fade both panes are mounted, and
     `bridge.textView` still points at the outgoing source view until it is
     dismantled.
   - A rendered `topCell` inside a folded block (a fold at the very end of
     the note) makes `scrollTo` hit an id that is not on the page and do
     nothing: the page opens at the top. The restore reads the unfiltered
     parse (:449-451); `items` filters folded blocks out (:564-569).

## (b) Caret, armed bar, held cells

Nothing is carried in either direction. `NoteStore` and `AppState` hold no
caret, no bar and no held cells (grep: only `caretAnchor`, a closure).

| Thing | Source side | Rendered side | Across ⌘T |
|---|---|---|---|
| caret / selection | `tv.selectedRanges` on the PasteAwareTextView | `cursor` `@State` `.cell(range)` / `.item(range)` with the caret in a BlockEditor (MarkdownPreview.swift:80-87) | lost |
| armed bar | `PasteAwareTextView.armedSeam` + `armedType` (MarkdownTextView.swift:990-1010) | `armedSeam` / `armedType` / `focusedSeam` `@State` (MarkdownPreview.swift:176-185) | lost |
| held cells | `tv.selectedRanges` (several ranges) | `selectedCells` `@State` (:137) | lost |
| open block / reminder | — | `cursor` (:87) with `draft` / `fence` | lost. The text is safe: every keystroke is already in the note (:1456-1467) |
| drawing-layer selection | `DrawingCanvas.selection` `@State` | same view | **kept** (the canvas is not rebuilt; it resets only on document, canvas-mode or `deselectToken` changes, DrawingCanvas.swift:217-233) |

Where the caret ends up, and what that breaks:

- **Rendered → source: the caret is at the END of the note, with no
  keyboard focus.** `makeNSView` assigns `tv.string = text`
  (MarkdownTextView.swift:97). Measured: a new NSTextView given a 13-character
  string reports `selectedRange` = {13, 0}. `restyle(force:)` puts the same
  selection back (:480, :523). Nothing in `makeNSView` calls
  `makeFirstResponder`; the only calls are :158, :347 and :589, all
  gesture-driven. The end-of-note caret is not cosmetic:
  - The Format menu goes through `EditorBridge.perform`, which acts on
    `textView` whatever the first responder is (EditorBridge.swift:174). ⌘1,
    ⇧⌘L or ⌘9 pressed straight after ⌘T therefore restyle the LAST cell.
  - A picture pasted or captured before a click lands one `gapHeight` under
    the LAST line of the note: `caretAnchor` → `caretLineFrame`
    (EditorPane.swift:136, EditorBridge.swift:184-200,
    NoteStore.swift:888-893). On a long note that is screens below the place
    being looked at.
- **Source → rendered: no cell is open and nothing has the keyboard.** The
  rendered page starts at `cursor = .none`. The first bar command goes
  `perform` → `ensureEditing` → `openSomething`, which opens the note's
  FIRST cell (MarkdownPreview.swift:1605-1615). So ⌘B or ⌘2 straight after
  ⌘T opens and restyles cell 1, wherever the page is scrolled. The doc
  comment at :1602-1603 says "else the block the caret was last in". That
  branch does not exist.
- An armed bar, its + choice and held brackets all vanish. The rendered page
  has no `armedSeam` to restore, and the source has no `armedSeam` until a
  selection change re-derives one (`CellSeams.arm`, :632-644).

## (c) Objects on the drawing layer, against the paragraph they were put beside

**The model.** Every object stores pane fractions (`normalise`: x / width,
y / height, y unclamped below, DrawingCanvas.swift:1311-1313). The layer draws
`scrollOffset` higher (:78-83, :251). In the source that offset is the
clip-view origin, in text-view coordinates (MarkdownTextView.swift:675). On
the rendered page it is `-minY` of a zero-height marker at the top of the
VStack (MarkdownPreview.swift:304-307, 386-387).

So an object has ONE document point, `(fx·W, fy·H)`, in both modes. The pane
is the same size in both. Whatever moves is the TEXT: each pane lays the same
cell out at a different document y and x. The drift is absolute in the
document and does not depend on where the note is scrolled. Every object
(picture, pen stroke, shape, text box, arrow) moves as one rigid sheet;
arrows stay on their nodes.

Note: AGENTS.md:1108 says "The preview does not scroll the layer (its offset
is 0 there)". That is stale. EditorPane.swift:63-66 and :109-112 feed the
rendered page's offset to the layer. The PDF export lays the drawing over the
RENDERED rhythm (Export/NoteExport.swift:58-62), so an object placed in the
markdown pane is off its paragraph in the PDF by the same drift.

**The constants.**

| Constant | Value | Where |
|---|---|---|
| body font | system 15 | MarkdownTextView.swift:377 |
| lineSpacing | 4 | :380 |
| `lineHeight` | 22 (measured: 18 + 4) | :392-394 |
| text container inset | 24 × 20 | :85 |
| lineFragmentPadding | 5 (default), so source prose starts at x 29 | |
| `codeSize` | 14.25 | :398 |
| `topInset` | 22 | MarkdownPreview.swift:223 |
| `sideInset` | 28 | :225 |
| `gapHeight` | 8 | :241 |
| `blockGap` | 26 = lineHeight + lineSpacing | :262 |
| `codePadding` | 7 vertical; horizontal 12 | :281; :1995 |
| first rendered cell | at 30 = topInset + gapHeight | :395, :1096, :1107 |
| heading sizes | 28 / 22 / 18 / 16 / 15 / 17 | :2061-2070 (source uses the same: MarkdownSourceStyle.swift:341-350) |
| source cell gap, markers hidden | 4 (lineSpacing) + 8 (paragraphSpacing on the cell's last line) + ~2.4 (separator at 2 pt font) ≈ 14 between inks | MarkdownTextView.swift:483-511, MarkdownSourceStyle.swift:327 |
| source cell gap, markers shown | 4 + a full 22 pt blank line | |
| rendered cell gap | 26, no spacing after the last line of `Text` | |
| code fence lines in the source | full 15 pt lines (22 each), never squashed | MarkdownSourceStyle.swift:288-291 |
| rendered code | 7 + body + 7 in a box at x 40 | |
| rendered evaluation / Out code | behind a 44 + 6 `CellMark` column, x 90 | MarkdownPreview.swift:1957-1963, Eval/CellMark.swift:54 |
| rendered maths | `MathView(size: 21)`, CENTRED | MarkdownPreview.swift:1945-1948; the source shows the WL as monospace at x 29 |
| rendered rule | `Divider` 9 tall; the source shows `---` as a 22 pt line | :1977 |
| rendered lists | 8 pt indent + marker + 8 spacing, items 4 apart | :1879-1935 |
| rendered quote | 3 pt bar + 12 | :1937-1943 |

**Measured: a 12-cell note.** Cells: h1, a long paragraph, h2, 3 bullets, a
3-line ```eval python, its ```out, a ```wl maths cell, a quote, 2 to-dos, a
rule, h3, a 2-line paragraph. Pane 600 pt wide. Each column is the top of the
cell in document points.

| cell | source, markers hidden (Sean) | source, markers shown | rendered | drift vs hidden | drift vs shown |
|---|---:|---:|---:|---:|---:|
| # Lecture notes | 20 | 20 | 30 | +10 | +10 |
| paragraph (3 lines) | 67 | 64 | 89 | +22 | +25 |
| ## Worked example | 143 | 152 | 180 | +37 | +28 |
| bullets ×3 | 183 | 196 | 232 | +49 | +36 |
| ```eval python (3) | 259 | 284 | 323 | +64 | +39 |
| ```out (1) | 376 | 416 | 425 | +49 | +9 |
| ```wl maths | 451 | 504 | 483 | +32 | −21 |
| > quote | 526 | 592 | 566 | +40 | −26 |
| to-dos ×2 | 558 | 636 | 611 | +53 | −25 |
| --- | 612 | 702 | 679 | +67 | −23 |
| ### Summary | 644 | 746 | 714 | +70 | −32 |
| paragraph (2 lines) | 679 | 790 | 761 | **+82** | −29 |
| note height | 745 | 848 | 803 | | |

At 900 pt the drifts are within 1 pt of these: same steps, fewer wraps.

**Per cell, with markers hidden (Sean's setting).** Each figure is the cell
plus the boundary after it, rendered minus source:

| cell kind | drift added |
|---|---:|
| paragraph or list | +12 to +15 |
| heading | +12 (the rendered heading is 4 pt shorter: no trailing lineSpacing) |
| to-dos | +14 |
| quote | +13 |
| rule | +3 |
| maths | +8 (depends on the expression; a fraction or a power makes it taller) |
| fenced code cell (3 lines) | −15 (the two 22 pt fence lines against 2 × 7 padding) |
| Out cell | −17 |

- The page top adds +10 (30 against 20).
- The drift ACCUMULATES. A prose-only note of 30 cells is about
  10 + 29 × 14 ≈ 400 pt off by its end, more than half a screen. A picture
  put beside paragraph 30 in markdown mode shows about 18 lines above it in
  rendered mode, and one put there in rendered mode shows the same distance
  below it in markdown.
- The ~16 pt per boundary is because `blockGap` copies the markers-SHOWN
  rhythm (a full blank line, MarkdownPreview.swift:243-262). Sean's
  markers-hidden source puts ~14 pt between cells, against the page's 26.
- Inside a cell the line pitch matches: 22 pt for prose in both panes, about
  21 pt for code. A code cell's lines sit 15 pt lower in the source (fence
  22 against padding 7).

**Horizontal drift (x of the words, rendered minus source).**

| block | source x | rendered x | drift |
|---|---:|---:|---:|
| prose and headings | 29 | 28 | −1 |
| heading in the caret's cell (source shows `# `) | 42 | 28 | −14 (that cell only) |
| bullets | 39.8 | 50.8 | +11 |
| quote | 42.2 | 43 | +1 |
| plain code | 29 | 40 | +11 |
| evaluation / Out code | 29 | 90 | +61 |
| maths | 29 | centred: for a short expression in a 600 pt pane, start x ≈ 270 | ≈ +240 |

A tick put after a line of maths in one mode is nowhere near it in the other.
Text widths agree to 2 pt for prose (542 against 544), so wraps rarely differ.
Code is 24 pt narrower rendered (74 for an evaluation cell), so long code
lines wrap differently and add more vertical drift.

## (d) Folding, the gutter, an open block editor

- **Folding: kept.** Both panes take `store.collapsedHere` and
  `toggleSection` (EditorPane.swift:45-46, :70-71). The source lays a closed
  section out at zero height (`FoldingTypesetter`, MarkdownTextView.swift:685-701,
  hidden range from the heading's end through the section's end + 1,
  NotebookOutline.swift:44-48). The rendered page leaves out blocks that lie
  wholly in a hidden range (MarkdownPreview.swift:564-569). A closed section
  is its heading plus one boundary in both, so it adds the same per-boundary
  drift as any other cell (about +16). The only position hazard is the
  folded-tail `scrollTo` no-op in (a) 6.
- **Gutter.** Each pane draws its own brackets from its own layout: the
  source's `NotebookGutter` at x W−22…W (MarkdownTextView.swift:711), the
  rendered `CellBrackets` at W−26…W−4 (MarkdownPreview.swift:344-370). They
  follow their own cells, so they drift with the text and 4 pt sideways. The
  hover promise (`CellInsertions.hoveredCells` / `promisedCells`) and held
  brackets do not survive the toggle (b).
- **An open block editor, reminder or code cell on the rendered page: closed
  by ⌘T.** No text is lost. Going back to rendered does not reopen it, and the
  source does not put its caret where it was (b). The `fence` / `draft` state
  goes with it, which is harmless.

## Seen in passing (not position bugs, but the next step will trip on them)

- **Dead code.** `MarkdownTextView.Coordinator.tidying`
  (MarkdownTextView.swift:427-429) is never read. `NotebookCells.tidied`
  (NotebookCells.swift:123) has no caller in the app or the tests. The comment
  at MarkdownTextView.swift:619-621 ("the empty cell it left, if it never
  became one, goes") describes behaviour nothing performs any more.
- **Stale docs.** AGENTS.md:1108 (the rendered page does not scroll the layer)
  and the MarkdownPreview.swift:1602-1603 comment (`openSomething` reopens "the
  block the caret was last in") are both untrue now.
- **Window height moves objects against the text in BOTH modes.** y is a
  fraction of the pane HEIGHT, so a window 100 pt taller moves an object at
  y = 3.0 by 300 pt relative to the words. A cell-anchored or
  points-based y would fix this along with (c).

## Possible directions (for the step that decides; nothing done)

- **(a)** Carry an anchor rather than a bare offset: the cell's offset, the
  character at the fold, and the points from that line's top to the fold.
  Restore the rendered page to the row plus the line's measured offset, not
  `.top`. Use the same tolerance on both sides: for example, "the first cell
  whose BOTTOM is below the fold", so a seam or gap at the top never reads as
  the cell above. Update `topCell` after edits as well as scrolls, by shifting
  it like `EvalCells.shifted`. Reset or remember it per note.
- **(b)** Save the caret on the way out (the source's selected ranges and
  `armedSeam`; the rendered `cursor` + the caret inside it, `armedSeam`,
  `selectedCells`) into `NoteStore`, and replay it on the way in. Source:
  `setSelectedRange` + `makeFirstResponder`. Rendered: `beginEditing(block,
  caret: .at(...))`, `arm`, or `selectCells`. `openSomething` would then use it.
- **(c)** Two honest options:
  1. Make the two layouts agree on every cell top, which would make the
     document coordinates one frame. Either change `blockGap` to the
     markers-hidden rhythm and take the fence-line difference into
     `codePadding`, or move the source.
  2. Keep one pane's document as canonical and map y through the
     per-cell-top correspondence of the other (piecewise linear between
     matched cell tops). The rendered page can afford this: it already knows
     every row's top, and an offscreen TextKit 1 layout of the note at the
     pane width gives the source's.

  The sidecar format need not change for either. Old sidecars hold objects
  drawn in BOTH modes with no record of which, so "open where they were" can
  hold in one mode only. That choice is Sean's.
