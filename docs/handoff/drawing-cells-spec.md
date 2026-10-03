# Drawing cells, ⌘0, Make Cell and Dock — the final spec

Sean, 2026-10-03: "on drawing segments, add a dock button which inserts it into the cell of the existing
cursor, and a create cell from drawing which has a new type of cell.. and drawing cell which is cmd + 0".

Against main at 0218094 (the three designs were written against f5285f8; nothing between them touches
this). Read-only work: nothing here is built. Other agents are changing the editor's caret/insertion UX,
the pen buttons and mode-switch positions in worktrees right now — §12 names every touch point this
shares with them, so the build rebases onto whatever lands first.

---

## 1. Judging the three designs

| Axis (1–10) | A — portable | B — editable | C — minimal |
|---|---|---|---|
| **Faithful to Sean's words** | **8.** Every row of its dock table reads off his sentence; Make Cell in place. But ⌘0 raises the pen, which he did not ask for and which costs a "pen floor" on ⌘Z. | **7.** Faithful tables. Adds a toolbar button nobody asked for; docks into a text cell always go after the whole cell. | **7.** Faithful, but Drawing is kept off the +, so a mouse user has no way to it but the menu bar. |
| **The note stays markdown; nothing old at risk** | **6.** One self-describing file, the note's sidecar untouched, a body hash against other writers — excellent. But its default is a VISIBLE `_drawings/` folder, which breaks "the notes folder stays a folder of markdown" and needs a `NoteTree` exception, and its launch sweep moves files to the Trash on its own. | **7.** Hidden, never swept, the sidecar untouched. But `../.drawings/media/…` paths mean moving a note rewrites the note's own text. | **5.** Puts the cells INSIDE every note's sidecar `Drawing` — a new Codable surface on the one file that holds all of Sean's floating drawings, with the `isEmpty`, decode-failure and downgrade traps it lists itself, and the base-name sidecar collision inherited. |
| **Native: one builder, one place per button, both panes, undo** | **8.** `Kind.drawing` through `CellTypes.open`; Insert menu and the + only; panes draw the ink, so it can never lag the text; one text undo group pairing both halves. | **7.** Best single catch of the three: every kind-naming command at a drawing cell acts as the bar under it. Cursor-mode drawing in a cell (no mode switch). But a toolbar button, and the canvas paints cells from reported frames, so ink trails the text while typing above it. | **6.** Coupled undo registration is right. No pencil pointer, Drawing off the +, and a flattened model that fights the canvas (every frame re-homes every cell item twice). |
| **Buildable in two ships** | **5.** An SVG writer for every item kind (text boxes wrap; SVG does not), dark-mode classes, CDATA, hash — and a four-deploy plan. | **5.** The same SVG writer, plus a ledger that patches every drawing snapshot newer than a dock. | **7.** Least new code; but flatten/unflatten on every body, stroke widths at a scale, connector routing seeing floating nodes, and an `InkCache` key change on the cache the legacy guarantee leans on. |
| **The traps** (sweep, two stacks, no-height cells, pane positions, export) | **8.** `boundingRect` vs. paragraph spacing, the claim clearing itself on its own write, frames only on a real move, `InkCache` in local points. | **9.** The most complete list: the first-cell fallback, the giant caret, the margin click opening a BlockEditor on the link, a mouse click leaving a dot, the canvas-per-cell monitor trap. | **7.** `isEmpty` deleting the sidecar, the sweep stopping on an unreadable sidecar, a stored rect going stale. |
| **Total** | **35** | **35** | **32** |

**Winner: B**, on the tie-break — axis 2 is AGENTS.md's first rule ("The NOTE is a markdown file and nothing
else"), and B is the only one that keeps the folder hidden AND never deletes a cell file.

**Grafted into B:**

- **From A:** the panes draw the cell (one painter, no lag); Make Cell *in place* at the nearest seam; the
  dock table; one text-undo group pairing the line with the objects; the rendered page's ⌘Z claim (set
  AFTER its own write is told); `CanvasSpace` and "a selection lives in one space"; frames published only
  on a real move; `InkCache` fed cell-local points; the + entry that opens at once; Insert menu, no toolbar
  button; new icons into `SymbolTests`.
- **From C:** a PNG rendition painted by `DrawingInk` (the PDF's own painter) instead of an SVG writer;
  `Drawing.lifting`; the sweep that deletes nothing when a sidecar will not decode; ⌘0 as a pure text
  edit (no mode change); clearing the floating selection after a dock so one ⌘Z reaches the text.

**Replaced in B, and why:**

| B had | Final | Why |
|---|---|---|
| SVG with JSON in `<metadata>` | **PNG with the JSON in an `iTXt` chunk** (Excalidraw's `.excalidraw.png` idea) | One file still — picture and data cannot drift — but the picture is painted by `DrawingInk`, the painter the PDF already trusts, so there is no second renderer for text boxes, dashes, heads and traced PDFs. Every markdown reader shows a PNG. |
| `owningFolder/.drawings/media/<ID>.svg`, path `../` per section depth, rewritten on a move | **`.drawings/cells/<ID>.png` beside the note**, the same bytes at every depth | A note's line never has to be rewritten; a section moved in Finder carries its drawings; `NoteTree.read` already skips hidden folders. |
| A ledger patching every snapshot | **Text-undo pairing + one idempotent `reconciled` pass after drawing undo/redo** | No snapshot is ever rewritten; the invariant is enforced where a restore happens. |
| The canvas paints cells | **The panes paint cells; the canvas edits them** | A cell is a row of the page; its ink moves with the text in the same frame. |
| Dock into a text cell: after the cell | **Under the caret's own source line** | Sean, 2026-09-22: "in an existing cell .. the input cursor and text can only go above and below a docked image". For a one-line paragraph that IS after the cell; in a list or a multi-line paragraph the drawing lands under the line he is on. |
| A toolbar button | none | EVERY BUTTON HAS EXACTLY ONE PLACE, and the bar must fit half a window. |

---

## 2. Reading the ask

- **"drawing segments"** — a selection of FLOATING objects on the drawing layer: strokes, a group, a
  picture, shapes, arrows (what the handles already appear round).
- **"a dock button which inserts it into the cell of the existing cursor"** — a handle that moves the
  selection to wherever the input cursor is: into the drawing cell the caret is in, at the armed bar, or
  into the caret's text cell at the caret's line.
- **"a create cell from drawing which has a new type of cell"** — a handle that turns the selection into a
  **drawing cell**, a new kind of cell, right where the drawing is.
- **"drawing cell which is cmd + 0"** — ⌘0 makes an empty drawing cell at the cursor. ⌘0 is unbound today
  (`Shortcut` has ⌘1–⌘9 and nothing on 0).

Two ships: **Ship 1** — the drawing cell and ⌘0 (everything that makes a cell exist, show, draw, size,
undo, save and print). **Ship 2** — Make Cell and Dock (two handles on one machine: lifting floating
objects into a cell, across the two undo stacks). Ship 2 needs Ship 1.

---

## 3. The bytes

### 3.1 The line in the note

One line, blank lines either side, exactly what `CellTypes.open` writes for any cell:

```
Para A

![drawing](.drawings/cells/6F1C2E7A-3B4D-4C5E-9F60-718293A4B5C6.png)

Para B
```

- The path is **relative to the note**, and the same at every depth: `.drawings/cells/` is a hidden folder
  in the NOTE'S OWN folder (for a root note that is the `.drawings/` that already holds the sidecars).
- The UUID is `UUID().uuidString` (upper case). The alt text is free; WriteMind writes `drawing`.
- WriteMind keys the cell on the UUID and nothing else.

### 3.2 The file: `<note folder>/.drawings/cells/<ID>.png`

A PNG that every reader shows, carrying its own strokes:

```
89 50 4E 47 0D 0A 1A 0A          signature
IHDR … sRGB … IDAT …             the picture: the cell painted by DrawingInk on white, 2× its points
iTXt  "WriteMind" 00             keyword
      01 00                      compression flag 1, method 0 (zlib)
      00 00                      empty language tag, empty translated keyword
      <zlib(JSON, UTF-8)>        the payload, §3.3
IEND
```

- The chunk goes in just before `IEND`, spliced into the bytes ImageIO wrote. CRC-32 and the zlib wrapper
  (2-byte header + `NSData.compressed(using: .zlib)`'s raw deflate + Adler-32) are written by hand, pure,
  in `DrawingCellFile` — no new dependency.
- Picture: `width × aspect·width` points at 2×, white paper, light appearance, through the same painter
  as the PDF (§5.2). Rewritten whenever the cell is.

### 3.3 The payload (JSON, `sortedKeys`)

```json
{"aspect":0.3125,"items":[{"kind":"stroke","stroke":{"colorHex":"#1C1C1E","id":"…",
 "points":[[0.0412,0.0731],[0.0419,0.0733]],"pressures":[0.42,0.47],"tool":"pen",
 "transform":{"dx":0,"dy":0,"rotation":0,"scale":1},"width":3}}],"version":1,"width":640}
```

- `items` is `CanvasItem`'s own Codable, unchanged: points, pressures, tool, groups, shapes, connectors,
  pictures. Nothing is converted, so nothing is lost.
- **Every fraction is a fraction of `width` on BOTH axes**: x in 0…1, y in 0…`aspect`. Growing the cell
  moves no point, and a resize never stretches ink (the floating layer's y is a fraction of the pane's
  height, which would).
- `width` (W) is the column's width in points when the cell first got content. `aspect` is height ÷ W.
- Decoded element by element: an unknown `version`, or one item that will not decode, makes the cell
  READ-ONLY (§3.5) — never "the rest", never written over.

### 3.4 The parser

`MarkdownBlock.drawing(id: UUID, alt: String)`. A line is one when, trimmed, it matches

```
^(?:<a id="[^"]*"></a>)?!\[([^\]\n]*)\]\(\.drawings/cells/([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})\.png\)$
```

- In `MarkdownParser.positioned`, in the non-fence branch right after headings: `flush(); blockStart =
  lineStart; emit(.drawing(…)); continue` — so it is checked after the fence branch (inside a fence, even an
  unclosed one, it is code) and it ends an open paragraph or list the way a heading does.
- The optional `<a id>` prefix is what `/link` writes in front of "any other block"
  (`MarkdownLinking.anchor`); without it, linking to a drawing cell would turn it into a paragraph.
- Words beside the image, another folder, `../`, a non-UUID or another extension: a paragraph, as today.
- `DrawingCells.parse(_:)`, `lines(in:) -> [(id, range)]`, `ids(in:)` — pure, one reader for everyone.

### 3.5 What WriteMind does with each state of the file

| On disk | Shown | Written? |
|---|---|---|
| nothing | an empty cell, 8 lines tall | the first change creates it |
| our PNG, version 1, every item read | the cell, editable | yes — only while the bytes are the ones last read or written (`NoteWriting.mayWrite(dataOnDisk:known:)`) |
| a PNG with no WriteMind chunk | that picture, read-only | never |
| our chunk, but unknown version / bad item / bad CRC / bad zlib | its pixels, read-only, one line saying why | never |
| `.<ID>.png.icloud` (not downloaded) | one line: "This drawing has not downloaded yet." | never — and never created over |
| changed by another writer since it was read | what was read; the write is refused, the footer says so, the cell goes read-only | no |

A read-only cell can still be held, moved, deleted and duplicated as a cell; nothing can be drawn in it.
**WriteMind never deletes anything under `.drawings/cells/`.**

---

## 4. The model

```swift
// Drawing/DrawingCell.swift (pure)
struct DrawingCell: Equatable {
    static let version = 1
    var width: Double              // W, points
    var aspect: Double             // height ÷ W
    var drawing: Drawing           // items in fractions of W, both axes
    var height: Double { width * aspect }
    var size: CGSize { CGSize(width: width, height: width) }   // what geometry is asked with
    static func empty(width: Double) -> DrawingCell            // 8 × MarkdownTextView.lineHeight tall
    /// Content within one line of the bottom → 4 lines of room below it. Never shrinks.
    func fitted(lineHeight: Double) -> DrawingCell
    /// The grip: never under the content plus `pad`, never under 2 lines.
    func resized(toHeight: Double, lineHeight: Double) -> DrawingCell
}

/// What the drawing stack keeps a step of: the floating layer AND the cells.
struct DrawingState: Equatable { var layer: Drawing; var cells: [UUID: DrawingCell] }

// Drawing/DrawingCellFile.swift (pure): encode/decode the payload; PNG embed/read
enum DrawingCellFile {
    enum Reading: Equatable { case cell(DrawingCell), picture, unreadable(String) }
    static func payload(_ cell: DrawingCell) -> Data
    static func cell(fromPayload: Data) -> Reading
    static func embed(_ payload: Data, in png: Data) -> Data?
    static func read(_ png: Data) -> Reading
}

// Drawing/DrawingCellStore.swift: the files
enum DrawingCellStore {
    static func folder(besides note: URL) -> URL      // <note folder>/.drawings/cells
    static func url(_ id: UUID, besides note: URL) -> URL
    static func load(_ id: UUID, besides note: URL) -> (state: DrawingCellState, known: Data?)
    static func write(_ cell: DrawingCell, rendition: Data, id: UUID, besides note: URL,
                      known: Data?) -> Data?           // the bytes written, or nil when refused
    static func copy(_ id: UUID, to newID: UUID, from note: URL, to other: URL)
}
```

**`NoteStore`** gains:

- `@Published var cells: [UUID: DrawingCell]` — the open note's cells, loaded in `loadText(for:)` for every
  id in the text, and lazily when the text gains a new id (the `$text` sink). Kept OUT of `drawing`, so
  `clearDrawing()` (`drawing = Drawing()`), `Drawing.isEmpty` and the sidecar's save/delete never see them.
- `cellStates: [UUID: DrawingCellState]` (`.writable`, `.readOnly(why)`, `.placeholder`), `cellKnown:
  [UUID: Data]` (the bytes last read or written) and `cellSaved: [UUID: DrawingCell]` (dirty check).
- `cellFrames: [CellFrame]` — reported by the pane on screen (§5.4), read by tablet routing.
- `drawingHistory` / `drawingFuture` become `[DrawingState]`. `beginDrawingChange()` pushes
  `DrawingState(layer: drawing, cells: cells)`; `undoDrawing()` / `redoDrawing()` restore both halves.
  `drawingSteps` keeps its meaning. (External code reads only `.count`.)
- Saves: `$cells` schedules the same 300 ms debounce as `$drawing`; `saveDrawingNow()` writes the sidecar as
  today and every DIRTY writable cell (paint on main, encode and write off main, as `TabletPage` does).
  `flushPendingSave()` writes them synchronously. A cell restored by undo to "no content" is written as
  an empty cell at its last W and aspect — a file is never removed.
- `WriteMindApp`: `.onReceive(store.$cells) { _ in appState.drawingChanged(steps: store.drawingSteps) }`
  beside the existing `$drawing` one.

---

## 5. Showing it, in both panes

### 5.1 Size

`DrawingCells.shown(_ cell: DrawingCell?, column: CGFloat) -> (scale: CGFloat, size: CGSize)`:
W = `cell?.width ?? column`; **s = min(1, column ÷ W)**; size = (W·s, H·s), H = `cell?.height ??
emptyHeight`; never under 2 lines (a read-only placeholder: 1 line — a cell with no height is a cell
nothing can hold). A drawing never grows past the size it was drawn at; in a narrower column it shrinks
WHOLE — ink widths too, like a picture. The cell sits at the column's left.

The column: rendered page = pane − 2·`MarkdownPreview.sideInset`; source pane = the text container's width
− 2·`lineFragmentPadding`; PDF = the rendered page's.

### 5.2 One painter

`Export/DrawingCellPainter.swift`:

```swift
enum DrawingCellPainter {
    enum Paper { case screen(hex: String), white }
    /// The cell at `origin` (document points), scaled by s, clipped to W·s × H·s.
    static func paint(_ cell: DrawingCell, in context: CGContext, origin: CGPoint, scale: CGFloat,
                      paper: Paper, picture: (String) -> URL?)
}
```

It translates, scales, clips and calls `DrawingInk.draw(cell.drawing, in:size: cell.size, …)`. Geometry is
always asked at (W, W), so `InkCache`'s fingerprints are the same on screen, in the PNG and in the PDF, and
never change as text reflows above the cell. `DrawingInk` gains one option: on `.screen`, stroke and
connector colours go through `InkPaths.shownHex(_:onPaper:)` (the screen's rule) instead of
`readableInk`. The hairline outline (lit with the accent when it is the caret's cell) is drawn by the panes,
never on paper.

### 5.3 Source pane (`MarkdownTextView`, TextKit 1)

- **Height — the typesetter.** `FoldingTypesetter.willSetLineFragmentRect` asks the fold first (zero, as
  today); then a `CellLines` object the coordinator owns: for the LAST fragment of a drawing line it adds
  h = H·s to `lineRect` and `usedRect`, baseline untouched — the line's text at the top, the drawing under
  it, the paragraph spacing (the gap) still at the bottom. Height changes invalidate that line's layout
  only.
- **Style.** With markers hidden, `restyle` gives a drawing line `structuralSize` type, a clear colour,
  `lineSpacing` 0 and `paragraphSpacing = gapHeight`. With markers shown (raw), the line is ordinary text
  and the drawing is still drawn under it — positions hold in all three views.
- **Paint.** `FoldingLayoutManager.drawBackground(forGlyphRange:at:)` paints each drawing line's cell with
  `DrawingCellPainter` (`.screen`). `CellLines.rect(…)` is the ONE geometry the painter, the frames and
  `cellBoxes` read, so they cannot drift.
- **`cellBoxes(in:)`** takes a drawing cell's box from `CellLines.rect` plus its text line, not from
  `boundingRect` — whether that includes a widened used rect is measured by a hosted test, not assumed.
- **The caret.** A zero-length selection on a drawing line is "the caret in the drawing cell".
  `PasteAwareTextView.drawInsertionPoint(in:color:turnedOn:)` draws nothing there (the lit outline and the
  heavy bracket are the cursor) — a caret the height of the fragment is the alternative.
- **Snapping** (markers hidden only), in `willChangeSelectionFromCharacterRanges`, the fold snap's place:
  `DrawingCells.snap(_:lines:backwards:)` — strictly inside a drawing line goes to its end moving forward,
  to its start moving back; a range that covers part of a line covers all of it. ← from the start and → from
  the end leave the cell.
- **Spelling.** `textView(_:shouldSetSpellingState:range:)` returns 0 inside drawing lines.

### 5.4 Frames for the canvas

```swift
struct CellFrame: Equatable { var id: UUID; var line: NSRange; var rect: CGRect /* document pts */
                              var scale: CGFloat; var width: CGFloat /* W */; var writable: Bool }
```

Source: `MarkdownTextView.drawingFrames(in:)` from `CellLines.rect`, reported from `refreshBrackets` (the
pass that measures the seams). Rendered: from `PreviewLayout.positions` + `sideInset` + `shown`. Each pane
calls `onDrawingFrames` ONLY when a frame moved by more than half a point (`CellSeams.moved`'s tolerance);
`EditorPane` hands them to `DrawingCanvas(cellFrames:)` and `store.cellFrames`. Folded cells have no frame.

### 5.5 Rendered page (`MarkdownPreview`)

- `BlockView`'s `.drawing` arm: a `Canvas` of the shown size painting through
  `context.withCGContext { DrawingCellPainter.paint(…, .screen) }`, plus the outline. It reads
  `@Environment(\.drawingCells)` (cells, states, column, lit id, the cell folder). Under export it is never
  used (§10.1).
- `Cursor` gains `.drawing(NSRange)`. `openCell` returns it (so ⌃⌫, ⌃⇧D, ⌃⇧↑/↓ act on it);
  `editingRange` is nil for it; `caretInNote` is its end.
- The row never calls `beginEditing` (that opened a BlockEditor on the link text). Its tap — reached only
  where the canvas does not take it, i.e. right of a narrow cell — sets `.drawing`. It sets no I-beam on
  hover: over the paper the pointer is the layer's (§7.4).
- Keys: the row is `.focusable()`, `.focused($focusedDrawing, equals: item.id)`, `.onKeyPress` →
  `DrawingCells.key` (§6). Focus leaving it ends `.drawing`, as `focusedSeam` does for a bar.
- `openSeam(_:as:at:)`: when what opened is a drawing cell, `cursor = .drawing(cell)` — never a BlockEditor.

---

## 6. The caret in a drawing cell (both panes)

A drawing cell takes no characters. **For anything that writes, it stands in for the bar under it.**

`DrawingCells.key(characters:modifiers:) -> Key` (pure, one table for both panes):

| Key | Does |
|---|---|
| a printable character | a text cell AFTER the drawing cell with that character in it (the bar under it, typed into) |
| Return | an empty cell after it, open for typing |
| ⌫ / ⌦ | the cell is HELD (selected whole, bracket held) — ⌫ on a held cell then deletes it, as today. One stray key never deletes a drawing. |
| ↑ / ↓ | the bar above / below it |
| Esc | rendered page: the cursor goes; source pane: nothing new |
| ⌘ / ⌃ chords | pass |

Source pane: `PasteAwareTextView.insertText` (typing only, `{NSNotFound, 0}`) and `doCommand(by:)` arm the
seam after the drawing cell (`armedSeam = DrawingCells.seamAfter(…)`) and go on exactly as at a bar;
`deleteBackward:` selects the line; `paste(_:)` opens a plain cell after it first, then pastes.

**Commands** — `EditorBridge.atArmedBar(_:)` (and only it; NOT `isAtArmedBar`) asks first whether the caret
is in a drawing cell and, if so, arms the seam after it:

- kind-naming commands — ⌘1–⌘7, the lists, the quote, ⌘8, ⌘9 at a bar, ⌘0 — make their cell after the
  drawing cell; the image line is never touched;
- writing commands — bold, spans, maths — open a plain cell after it and run there;
- commands ON a cell — delete, duplicate, move, fold, expand — act on the drawing cell as a cell;
- `NotebookCells.split` returns nil for a drawing cell (as for code); `merge` returns nil when either cell is
  a drawing cell; indent/outdent do nothing there; ⇧↩ runs nothing (`evaluatesHere` is false).

---

## 7. Drawing into it, editing it, sizing it

### 7.1 One canvas, several spaces

```swift
// Drawing/CanvasSpace.swift (pure)
enum CanvasSpaceID: Hashable { case floating, cell(UUID) }
struct CanvasSpace: Equatable {
    var id: CanvasSpaceID
    var origin: CGPoint      // document point of the space's (0, 0)
    var size: CGSize         // what items are measured against: the pane, or (W, W)
    var scale: CGFloat       // document points per space point: 1, or s
    var clip: CGRect?        // a cell's rect, document points
    static func floating(pane: CGSize) -> CanvasSpace
    static func cell(_ frame: CellFrame) -> CanvasSpace
    func toDocument(_ p: CGPoint) -> CGPoint
    func fromDocument(_ p: CGPoint) -> CGPoint
    func toDocument(_ r: CGRect) -> CGRect
    /// Every normalised field of every kind — points, centre, width, bends, overrides, dx/dy — moved
    /// one for one; point widths × from.scale ÷ to.scale; ids, groups, pressures, tools kept.
    static func rehome(_ item: CanvasItem, from: CanvasSpace, to: CanvasSpace) -> CanvasItem
}
```

`rehome` maps points one for one and keeps the pressures as they are: it joins **THE LOCKSTEP RULE**'s list
in AGENTS.md beside `TabletPage.turned` and `TabletSelection.noteStrokes`.

`DrawingCanvas` keeps ONE key monitor, one `CursorLayer`, one gesture. It gains `cellFrames`, a binding to
`store.cells`, `@State active: CanvasSpaceID` (where the selection and the gesture live — **a selection
lives in one space**; picking in another drops it), and three reads that everything goes through:
`activeDrawing` (a `Binding<Drawing>`), `activeSpace`, and `point(_:)` = `activeSpace.fromDocument(doc(_:))`.
Every existing gesture — click, ⌘-marquee, the tablet's switch marquee, the handles, ⌫, ⌃G, crop, labels,
placements, ⌥-arrows — then runs unchanged on the active space's drawing at the active space's size; handle
positions come from `activeSpace.toDocument(box)`. `render` draws the floating layer as today and, for the
active cell only, its chrome (outlines, live stroke, marquee, crop dim) under the cell's transform and clip.
`documentID` changing resets `active` to `.floating`.

### 7.2 Which space a press is in

`CanvasSpace.at(_:…)`: a floating object under the point → floating (the layer is on top); else a cell
frame holding the point → that cell (its item under the point, or its paper); else floating. **The first
point decides** for everything a press puts down — a stroke, a shape, a mark, a text box, an arrow — and a
marquee picks in the space it started in. A read-only cell takes no strokes or placements.

### 7.3 What a press does

`CanvasMode.press(with:onCellPaper:)` (pure, `CanvasModeTests`):

| Mode | Press | Result |
|---|---|---|
| either | ⌘ held | the marquee, in that space |
| either | ⌥ from a node | an arrow, in that space |
| pen | anywhere | a stroke, into the space under the first point |
| cursor | on an object (floating or in a cell) | picks it up and moves it |
| cursor | on a cell's paper, and it travels 3 pt — or the first sample is a nib | a stroke into the cell (the mouse makes the legacy line, the nib ink) |
| cursor | on a cell's paper, never travels, not a nib | no dot: the caret goes into the cell (`onCellTap` → `EditorBridge.focusDrawingCell`) |
| cursor | elsewhere | through to the notebook, as today |

In cursor mode the stroke starts only past the threshold, so a click leaves no empty drawing step behind.
`CanvasHitShape` gains the cell rects (paper is the layer's in cursor mode).

### 7.4 The pointer

Over a writable cell's paper in cursor mode the layer's `cursor` is the pencil — the SAME path as the open
hand over an object (`CursorLayer` mounted only while it has one, `CursorRectView.claim` answering the text
view's, the seam layer's and the gutter's moves). The rendered page's drawing row sets no cursor.

### 7.5 Growth and the grip

- Every gesture that changes a cell ends with `store.fitCell(id)` → `DrawingCell.fitted` — same step, no new
  one. Ink can never be dropped off the bottom; past the sides and top, points are held inside
  (`normalise` already holds x to 0…1 and y ≥ 0), objects moved there are shifted back in.
- **The grip:** a `Handle` (`arrow.up.and.down`, "Drag to make the drawing taller or shorter") at the bottom
  centre of the caret's drawing cell, cursor mode, nothing picked. One drawing step per drag;
  `DrawingCell.resized`.

### 7.6 The tablet in Notebook mode

`NoteStore.inkFromTablet(_:)` routes by the stroke's first point against `cellFrames`: inside a writable cell
it is `rehome`d into that cell (one step, then `fitCell`); otherwise it floats, as today. Pressures keep
their length (`TabletNotebookTests`).

### 7.7 Undo inside the drawing

A stroke, a move, a resize, a growth, a delete in a cell — each is one step on the existing drawing stack
(`DrawingState`). The pen's two switches and ⌥⌘Z / ⇧⌥⌘Z get cells for nothing.

**⌘Z after a cursor-mode stroke in a cell** would undo the typing (nothing is picked, the pen is down).
`AppState.tabletInkFloor` generalises to **`inkFloor`**, set by `inkedNote(above:)` — called by the tablet's
landing as today AND by the layer when a cursor-mode stroke lands in a cell — so ⌘Z takes the strokes back
down to the floor, then goes to the text. Under the pen, or with something picked, the layer already owns
⌘Z.

---

## 8. ⌘0, and where it lives

- `Shortcut.drawingCell` → `KeyboardShortcut("0", modifiers: .command)`; README row `| ⌘0 | A drawing cell
  here |` (`ShortcutTests` holds the README to it); AGENTS' shortcut line gains it.
- **Insert menu:** "Drawing Cell" after Code Block, `.shortcut(.drawingCell)`, disabled with no note. It never
  converts a cell, so Insert, not Format.
- **The +:** `CellTypes.Kind` gains `case drawing`, name "Drawing", in a fifth group of its own;
  `Kind.opensAtOnce` is true for it alone — chosen on the +, it opens at once in both panes
  (`CellTypeMenu`'s choose, `MarkdownPreview.choose(in:)`), because its next input is a stroke and waiting
  for a character would type onto the image line.
- **Toolbar:** nothing.

**One builder.** `CellTypes.opening(.drawing, …)` writes the line on the empty block line `insertBlock` made
and puts the caret at its end. `CellTypes.open(_:writing:in:at:minting: UUID = UUID())` — the id is a
parameter, so tests pass one and Ship 2 mints its own.

`EditorBridge.drawingCell()`:

```swift
func drawingCell() {
    if atArmedBar(.drawing) { return }                 // a bar — or a drawing cell standing in for the one under it
    if let drawingCellInDocument { drawingCellInDocument(); return }   // the rendered page decides
    guard let tv = textView as? PasteAwareTextView, !(tv is BlockTextView) else { return }
    let at = DrawingCells.landing(caret: NSMaxRange(tv.selectedRange()), in: tv.string)
    MarkdownTextView.openSeam(at: at, as: .drawing, in: tv)
}
```

`DrawingCells.landing(caret:in:) -> Int` — **under the caret's own source line**; the last line of a cell is
the cell's end; a fence is never split (after the fenced cell, and for an In, after its Out —
`EvalCells.groups`); a drawing cell gives its own end; a `.blank` cell gives the caret's offset
(`insertBlock`'s blank-cell rule keeps the run's lines).

| Where the cursor is | ⌘0 makes | Bytes, before → after |
|---|---|---|
| an armed bar | the cell there | `One\n\nTwo` (bar at 5) → `One\n\n![drawing](…)\n\nTwo` |
| in a drawing cell | the next one, after it | `![drawing](…A…)` → `![drawing](…A…)\n\n![drawing](…B…)` |
| a one-line paragraph, anywhere in it | after it | `Hello world\n\nNext` → `Hello world\n\n![drawing](…)\n\nNext` |
| a list, on item b | under b; the list is two lists | `- a\n- b\n- c` → `- a\n- b\n\n![drawing](…)\n\n- c` |
| a fenced or maths cell | after it | after the closing fence |
| an evaluation cell | after its Out | after the ```` ```out ```` fence |
| rendered page, nothing open | at the seam nearest the middle of what is on screen (`CellSeams.nearest(toLine:in:)`) | — |

Never `cellRangeInDocument`'s `items.first` fallback. Afterwards the caret is in the new cell (source: the
line's end; rendered: `.drawing`) and the mode is left alone — in cursor mode the cell already draws. ⌘0 is
one TEXT edit: ⌘Z in the source pane takes it out (after any strokes the ink claim took back first). On the
rendered page it has no undo, exactly like ⌘8 and ⌘9 there today.

---

## 9. Ship 2 — Make Cell and Dock

### 9.1 The handles

On a FLOATING selection only — not a cell's, not while cropping, not under the pen, not while a tool is
armed — beside the ones already there:

| Handle | Icon | Tip | Place |
|---|---|---|---|
| Dock | `text.insert` | "Dock into the cell at the cursor" | (minX − 12, midY) |
| Make Cell | `rectangle.badge.plus` | "Make a drawing cell of this, here" | (maxX + 12, midY) |

Both move to y = maxY + 36 when the box is under 16 pt tall (closer, they overlap the corner handles):
`HandleLayout.side(box:)`, pure. AGENTS' handle inventory gains Dock, Make Cell and the cell grip.

### 9.2 What moves

`Drawing.lifting(_ ids:) -> Lifted { rest: Drawing; items: [(index: Int, item: CanvasItem)]; detached:
[Detached] }`, pure:

- the selection widened to whole groups (`CanvasGroups.whole`); hidden pictures never;
- an arrow goes when it is picked, or when both its attached ends go;
- an arrow with ONE end on something that goes stays floating, that end let go where it is
  (`Drawing.removing` would delete it).

The objects are **moved, not copied**: same ids, groups, pressures. A picture's file is COPIED to
`.drawings/cells/<cellID>-<itemID>.<ext>` and the item renamed to it; `DrawingInk` resolves a cell's
pictures there (the `picture:` closure, plus a small image cache so a drag does not re-read a JPEG per
frame). `NoteStore.cropImage` and `readText` find an id in a cell too (`NoteStore.locate`), and a crop of a
cell picture writes into the cell folder.

### 9.3 Make Cell — in place

The seam nearest the selection box's top (`CellSeams.nearest(toLine:in:)` over the pane's own seams, through
`EditorBridge.seams()`). A new cell there: W = the column, s = 1; each object keeps its x on the column and
the set sits `DrawingCells.pad` (12 pt) under the cell's top; a set wider than W − 2·pad is scaled down
(`CanvasEdit.transform`), one sticking out is shifted in; height = the set's + 2·pad, at least 2 lines. The
text below moves down by the cell; other floating objects keep their document place, as they do under typing.

### 9.4 Dock — at the cursor

`EditorBridge.dockTarget() -> DockTarget?` is STRICT: `.bar(offset)` | `.drawingCell(UUID)` |
`.textCell(caret: Int)` | nil — never the first-cell fallback.

| Cursor | Dock does |
|---|---|
| in a drawing cell | INTO it. If the set's box meets the cell they keep their place on screen exactly (shifted the least to sit inside, scaled down only if wider); otherwise they go under the cell's lowest content, x kept. The cell grows. Drawing only. |
| an armed bar | a new drawing cell there holding them (`CellTypes.open(.drawing, minting:)`) — A COMMAND AT A BAR MAKES THE CELL THERE |
| a text cell | a new drawing cell at `DrawingCells.landing` — under the caret's line, text above and below |
| none (rendered page, nothing open) | Make Cell |
| a read-only drawing cell | nothing moves; the footer says the cell cannot be written |

After any dock the floating selection is let go and the caret is in the cell, so a second Dock adds to it.

### 9.5 Undo across the two stacks

1. **Order:** the line first, then the objects. If the pane refuses the write (`shouldChangeText` false —
   e.g. into a fold), nothing moves.
2. **Every dock is one drawing step** (`beginDrawingChange()` before the objects move).
3. **A dock that makes a cell, source pane:** `EditorBridge.openDrawingCell(at:id:pairing:)` opens one group
   on the text view's OWN undo manager (`breakUndoCoalescing`, the insertion through
   `shouldChangeText`/`didChangeText`, `registerUndo(withTarget: store) { $0.undock(record) }`, whose undo
   registers `redock`). One ⌘Z or ⇧⌘Z takes both halves; it survives later typing because it is just a group
   on the stack. Nothing picked, pen down → nothing else claims ⌘Z.
4. **A dock that makes a cell, rendered page** (no structural undo there): `AppState.dockClaim` — ⌘Z =
   `store.takeBackDock()` (the line out by its UUID through `writeInDocument`, then `undock`), ⇧⌘Z =
   `putBackDock()` (the line back through `CellTypes.open(.drawing, minting: record.cell)` at its offset,
   then `redock`). Set AFTER the dock's own write is told (that write fires `noteTyped`); re-set after each
   take/put back; ended by any other text or drawing change, a mode switch, a note switch. The Undo and Redo
   items ask it after the page's claim and before the drawing's.
5. **A dock INTO a cell** has no text half: `inkedNote(above:)` — ⌘Z takes it off the drawing stack.
6. **Reconcile.** `DockRecord { cell, line, offset, originals: [(index, item)], docked: [CanvasItem],
   detached: [Detached], undocked: Bool }` in `NoteStore.docks`, cleared with the history.
   `DrawingState.undocking(_:)` / `redocking(_:)` are pure and idempotent (undocking first copies the cell's
   CURRENT versions into `docked`, so a redo keeps edits made in the cell). After every `undoDrawing` /
   `redoDrawing`, `reconciled(records)` takes the items of every UNDOCKED record out of the restored cell and
   back onto the layer — so no drawing redo can put docked objects into a cell whose line ⌘Z took away. A
   cell deleted by hand is not "undocked": it stays deleted, drawing and all.

| Order of keys after Make Cell | Ends with |
|---|---|
| ⌘Z | line out, objects floating as they were |
| ⌘Z, ⇧⌘Z | line in, objects in the cell |
| ⌥⌘Z | objects floating, the line an empty cell (⌫⌫ removes it) |
| ⌥⌘Z, then ⌘Z | line out, objects floating — once, no duplicates |
| ⌥⌘Z, ⌘Z, then ⇧⌥⌘Z | objects floating (the redo is reconciled), line out — never objects hidden in a line-less cell |
| ⌫⌫ on the cell, then ⌥⌘Z | the cell stays deleted |

### 9.6 The sweep

- `DrawingStore.pruneMedia(in:keeping:)` keeps every file the OPEN note's drawing, history, future and dock
  records name (today ⌘S runs the sweep mid-note, and an undo after it brings back a picture whose file is
  gone); and **deletes nothing at all if any sidecar fails to decode** (today it skips that sidecar and then
  deletes its pictures).
- `.drawings/cells/` is never looked in.

---

## 10. Everything else

### 10.1 Export / PDF

`NoteExport.pdf(markdown:drawing:cells:noteFolder:media:pane:)`: a `.drawing` block takes its shown height at
the export column with NO `ImageRenderer`, and a `NotePDF.Piece` paints it with `DrawingCellPainter(.white)`
— vector, like the layer. `ExportMenu` passes `store.cells`.

### 10.2 Copies, moves, trash

- **Duplicate Note:** the copy's drawing lines get new ids (`DrawingCells.forked`) and their files are copied
  — the copy is the gesture's own new file. Two notes never share a drawing.
- **Duplicate Cell (⌃⇧D)** on a drawing cell: the same fork (`EditorBridge.onFork` → `store.copyCells`).
- A line pasted by hand keeps its id: both places show one drawing and edit one file. Nothing is lost.
- **Moving a note to another section:** its cell files are COPIED into the new folder's `.drawings/cells/`;
  the originals stay. Rename: nothing. Trashing a note: its cells stay, so putting it back from the Trash
  works. Trashing a section: they go with the folder.

### 10.3 Folding, eval, maths, links

A folded drawing cell has zero height, no frame, no routing; the PDF prints it, as it prints every fold.
A drawing line in a fence is code; `EvalCells.answer(after:)` pairs only fences; no cell lands between an In
and its Out; `isMathFence` is untouched. `/link` onto a drawing cell writes its anchor prefix, which the
parser takes (§3.4).

### 10.4 Positions between the modes

A drawing cell is a cell: the two modes come back to it by `topCell`, like any other. Inside it everything is
in the cell's own fractions, so the drawing is the same in both; the cell's height differs only by s.

### 10.5 Small things

The footer's word count and `Note.make`'s snippet skip drawing lines.

### 10.6 docs/CROSS-PLATFORM.md (one entry per ship, same commit)

Ship 1: the line and the regex; the PNG and its `iTXt` chunk; the payload and fractions-of-W; the file-state
table; s = min(1, column ÷ W); the press table; the caret key table; ⌘0 (Ctrl+0) and `landing`; never delete
a cell file. Ship 2: lifting; Make Cell's seam; the dock table; the undo pairing and `reconciled`; picture
copies into the cell folder. The port draws cells from the payload with perfect-freehand and writes the PNG
the same way.

---

## 11. Traps

1. **The media sweep** deletes what no sidecar names → cell files are never swept; cell pictures live in the
   cell folder; the sweep keeps history/records and stops on an unreadable sidecar.
2. **Two undo stacks** → one text group pairing both halves; the rendered page's claim; `reconciled` after
   every drawing restore.
3. **The rendered page has no structural undo, and the source pane's dies on a mode switch** → the claim,
   and the drawing step that always remains.
4. **The claim clears itself on its own write** (`noteTyped`) → set after the write is told.
5. **`cellRangeInDocument` falls back to `items.first`** → ⌘0 and Dock use strict readers.
6. **A cell with no height cannot be held** → 2 lines minimum, 1 for a placeholder.
7. **`boundingRect` vs. a widened used rect** → one geometry (`CellLines.rect`), measured in a hosted text view.
8. **A giant caret** → not drawn in a drawing line.
9. **A wrapped drawing line (raw mode)** → the height goes on its LAST fragment only.
10. **Kind commands writing `# ` or a fence onto the image line** → the drawing cell stands in for the bar
    under it.
11. **Typing, pasting or ⌫ inside the hidden line** → the key table; snapping; ⌫ holds first.
12. **Red spelling marks over the paper** → `shouldSetSpellingState` 0 in drawing lines.
13. **`/link`'s `<a id>` prefix** would turn the cell into a paragraph → the parser takes it.
14. **A click on the row's margin opening a BlockEditor on the link** → `.drawing`, never `beginEditing`.
15. **A mouse click on paper leaving a dot / an empty step** → cursor-mode strokes start past 3 pt.
16. **⌘Z after a cursor-mode stroke undoing the typing** → `inkFloor`.
17. **A canvas per cell** = a key monitor per cell (the two-monitor Esc trap) → one canvas, spaces.
18. **The eighth cursor cause** → the pencil over paper is the open hand's mechanism; the row sets no I-beam.
19. **Frames published on every keystroke** → only on a half-point move.
20. **`InkCache` keyed on absolute points** → every painter paints cell items at (W, W).
21. **Clear Drawing / `Drawing.isEmpty` / a decode failure emptying cells** → cells are not in `Drawing`;
    any decode failure makes a cell read-only, never rewritten.
22. **Another writer** (a second instance, iCloud, an editor) → `mayWrite` per cell file; `.icloud`
    placeholders never created over.
23. **The rendered page losing its armed bar when a handle is clicked** (focus moving off `focusedSeam`) →
    a hosted test clicks the Dock handle with a bar armed and the bar must still be the target.
24. **A missing SF Symbol draws nothing** → `text.insert`, `rectangle.badge.plus`, `arrow.up.and.down` join
    `SymbolTests` (ShapeTests.swift).
25. **Sidecars collide by base name across sections** (existing, flagged separately) → cells are keyed by
    their own UUID and avoid it.

---

## 12. The two ships

Each: every new test shown FAILING first, `sh tools/test.sh`, quit the running copy, `sh tools/deploy.sh`,
reopen. Touch points shared with the agents working now — `EditorBridge.atArmedBar`/`perform`,
`PasteAwareTextView.insertText`/`doCommand`/`paste`, `MarkdownPreview`'s cursor and `openSeam`,
`DrawingCanvas`'s handles and placement — are rebased onto whatever they land; the pure files have no
overlap.

### Ship 1 — the drawing cell and ⌘0

**New:** `Editor/DrawingCells.swift` (line, parse, lines, ids, landing, seamAfter, shown, key, snap, forked,
pad, emptyHeight) · `Drawing/DrawingCell.swift` (`DrawingCell`, `DrawingState`) ·
`Drawing/DrawingCellFile.swift` (payload, PNG `iTXt`, CRC-32, zlib wrap) · `Drawing/DrawingCellStore.swift` ·
`Drawing/CanvasSpace.swift` (`CanvasSpace`, `CellFrame`, `rehome`, `at`) · `Export/DrawingCellPainter.swift`.

**Changed:** `MarkdownBlocks` (case + branch) · `CellTypes` (`.drawing`, `opening`, `open(minting:)`, fifth
group, `opensAtOnce`) · `CellInsertions` (`CellTypeMenu` opens at once) · `CellSeams` (`nearest`) ·
`NotebookCells` (split/merge refuse) · `NotebookFolding` (typesetter height, layout-manager painter,
`CellLines`) · `MarkdownSourceStyle` · `MarkdownTextView` (style, frames, caret, snapping, spelling, key
stand-ins, `cellBoxes`) · `MarkdownPreview` (`.drawing` cursor and row, keys, frames, environment,
`openSeam`, `choose`) · `EditorBridge` (`drawingCell`, `focusDrawingCell`, stand-in, `seams`,
`drawingCellAtCaret`, `onFork`) · `DrawingCanvas` (spaces, press, hit shape, chrome, grip, pencil, cell tap)
· `AppState` (`press(with:onCellPaper:)`, `inkFloor`) · `NoteStore` (cells, states, `DrawingState`
history, load/save, `inkFromTablet` routing, `fitCell`, `resizeCell`, duplicate fork, move copy) ·
`TabletNotebook` · `EditorPane` · `Export/DrawingInk` (screen paper) · `Export/NoteExport` ·
`Views/ExportMenu` · `Views/Shortcuts` · `WriteMindApp` (Insert item, `$cells`) · `Notes/Note`.
**Docs:** README (⌘0 row), AGENTS (a standing rule for drawing cells, the lockstep list, the shortcut line,
the grip in the handle inventory, the wiring map), FEATURES, CROSS-PLATFORM.

**Tests:**

- `MarkdownParserTests` — a drawing line is `.drawing` with its exact range (the line, no newline); first
  line of a note; right under a paragraph it is its own block and the paragraph keeps its range; inside a
  fence (closed or not) it is code; words beside it, `../`, another folder, a non-UUID, `.jpg` → paragraph;
  the `/link` prefix keeps it a drawing (and `MarkdownLinking.anchor` on one keeps it parsing).
- `DrawingCellFileTests` — payload bytes exact and round trip for every item kind (pressures, tools, a
  legacy stroke, groups, a routed connector, a text box); PNG with the chunk still decodes as an image
  (`CGImageSource`) and round-trips byte for byte; no chunk → `.picture`; bad CRC / bad zlib / version 2 /
  one bad item → `.unreadable`.
- `DrawingCellStoreTests` (temp folder) — the folder for a root note and a section note; a write refused
  when the disk is not what was known, and the cell goes read-only; nothing ever deleted; `NoteTree.read`
  lists no `.drawings`; `.icloud` placeholder never created over.
- `CellTypeTests` / `ArmedBarTests` — `open(.drawing, minting:)` bytes at a bar, at the note's end, in an
  empty note; the caret at the line's end; five groups, Drawing last; `opensAtOnce`; choosing it on the +
  opens it in both panes.
- `DrawingCellCommandTests` — every row of §8's table, bytes exact; the rendered page with nothing open never
  uses the first cell (fails first against `caretCell()`).
- `DrawingCellKeyTests` — the §6 table; source pane hosted: a character opens a text cell after with it, Return
  an empty one, ⌫ holds and ⌫ again deletes, ⌘1/⌘8/⌘9/lists/quote leave the image line byte-identical and
  make their cell after, ⌃D/⌃M refuse, indent is a no-op, ⌘V opens a cell first; `snap` both directions.
- `DrawingCellLayoutTests` (a real `MarkdownTextView` hosted) — the drawing line's fragment is its text line
  + H·s (±0.5); `cellBoxes` includes it; the seam under it is `gapHeight`; raw mode keeps the drawing; a
  folded cell has zero height and no frame; a wrapped line adds height once; no caret is drawn; no spelling
  state in the line. `PreviewLayoutTests`: the row is the shown height.
- `CanvasSpaceTests` — `toDocument`/`fromDocument` round trip; `at`: a floating object beats a cell, a cell
  item beats its paper, a folded cell is never picked; `rehome` for every kind: outlines equal in document
  points (±0.01), pressures the same array, ids and groups kept, widths ÷ s.
- `CanvasModeTests` — the §7.3 table.
- `NoteStoreDrawingTests` — a stroke in a cell is one step and ⌥⌘Z restores the cell; Clear Drawing leaves
  cells; growth on landing; a resize is one step; only dirty cells are written; a note switch flushes;
  `inkFloor` after a cursor-mode cell stroke (⌘Z takes it, then the typing). `TabletNotebookTests`: a tablet
  stroke starting in a cell lands there with every pressure.
- `NotePDFTests` — a drawing cell's piece at its frame and height, no renderer for it.
- `DuplicateTests` — Duplicate Note and Duplicate Cell fork ids and copy files; moving a note copies its
  cell files and leaves the originals.
- `ShortcutTests` (⌘0, the README row), `SymbolTests` (`arrow.up.and.down`).

### Ship 2 — Make Cell and Dock

**New:** `Drawing/Docking.swift` (`lifting`, `DockRecord`, `undocking`, `redocking`, `reconciled`,
`placeInNewCell`, `dockInto`, `HandleLayout`).

**Changed:** `DrawingCanvas` (the two handles) · `EditorBridge` (`dockTarget`,
`openDrawingCell(at:id:pairing:)`) · `MarkdownPreview` (strict target, opening with an id, the claim's
hooks) · `NoteStore` (`makeCell`, `dock`, `undock`, `redock`, `takeBackDock`, `putBackDock`, reconcile,
picture copies, `locate`, `mediaInUse`) · `AppState` (`dockClaim`, `dockOwnsUndo`) · `WriteMindApp` (Undo/Redo
ask the claim) · `Drawing.swift` (`pruneMedia(in:keeping:)`, stop on unreadable) · `Export/DrawingInk`
(`picture:` resolver, image cache). **Docs:** AGENTS (handle inventory; the sweep rule; the dock rule),
`docs/PLAN-docking.md` marked built and superseded by drawing cells, FEATURES, CROSS-PLATFORM.

**Tests:**

- `LiftingTests` — whole groups; an arrow with both ends carried; a one-ended arrow left floating, detached at
  its point; a picked free arrow goes; hidden pictures never.
- `DockPlacementTests` — a new cell: x kept on the column, 12 pt pad, scaled to fit, shifted in, height;
  into a cell: overlap keeps document positions (±0.01), otherwise under the lowest content, the cell grows;
  at s ≠ 1 widths ÷ s.
- `DockTargetTests` — every row of §9.4; an eval In → after its Out; the rendered page with nothing open →
  nil (fails first); a read-only cell refuses.
- `MakeCellTests` — the nearest seam in both panes (pure, on seams); the set lands within the pad of where
  it was; the text below moves down by the cell.
- `DockUndoTests` — source pane hosted: every row of §9.5's table, ids and transforms equal, nothing lost or
  duplicated; rendered page: the claim takes back and puts back, survives its own write, ends at typing.
- `DrawingStoreTests` — a picture named only by the open note's undo history survives ⌘S (fails first); an
  unreadable sidecar stops the sweep (fails first); `.drawings/cells` untouched.
- `DockPictureTests` — a docked picture's file is copied into the cell folder and painted from there; crop and
  read on a cell picture.
- `HandleLayoutTests` — Dock and Make Cell never within 20 pt of the corner handles; under 16 pt tall they
  drop to the row below.
- `SymbolTests` — `text.insert`, `rectangle.badge.plus`.

---

## 13. Decisions for Sean

1. **Hidden or visible folder.** Cell files go in a hidden `.drawings/cells/` beside the note — the house
   rule that the notes folder stays a folder of markdown. Obsidian does not show anything inside a
   dot-folder, so there a drawing cell is a broken image; a visible `_drawings/` would fix that and put one
   non-markdown folder in every section. Built hidden unless you say otherwise; it is one constant.

---

## 14. Not in these two ships

Undocking (a cell's drawing back onto the floating layer) and PLAN-docking's drag-the-handle-to-a-seam —
neither was asked for now; the model supports both (the record, `rehome`, `CellSeams.nearest`).

---

## 15. DECIDED by Sean, 2026-10-02: visible

Asked "hidden `.drawings/cells/` or visible `_drawings/`?", Sean answered: **"visible data generally
speaking"**. So drawing cell files go in a VISIBLE `_drawings/cells/<ID>.png` beside the note (the line
in the .md is `![](_drawings/cells/<ID>.png)` — the same bytes at every depth, so a moved note never
needs its line rewritten), and:
- `NoteTree.read` must NOT list `_drawings` as a section (it is the note's data, not a folder of notes) —
  a pure rule with a test, and the sidebar, the section count, "new section" and drag-to-move all go
  through it; a note may never be created or moved into `_drawings`.
- Every rule that applied to `.drawings/cells` (never swept, follows a note's rename/move/trash/duplicate,
  survives a decode failure) applies to `_drawings/cells`.
- The EXISTING hidden `.drawings/` (floating drawings' sidecars and media) is NOT moved in these ships —
  moving Sean's existing data is its own decision and its own ship.
