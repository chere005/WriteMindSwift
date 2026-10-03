# Docking a floating picture into the note

Sean, 2026-09-22:

> add a button for floating elements to dock them to a cell wherever the input
> cursor is.. or drag that button to get an interactive mouse cursor that puts
> the image wherever i release the mouse button.. either between cells or in an
> existing cell .. text can not overlap with an image, the input cursor and
> text can only go above and below a docked image

BUILT 2026-10-02 as the Dock and Make Cell handles over drawing cells (see
`docs/handoff/drawing-cells-spec.md`, section 9, and AGENTS.md): a docked
object goes into a drawing cell (`![](_drawings/cells/<ID>.png)`), not into a
loose picture line. Kept as the record of what was asked; the drag-to-a-seam
half is still open (docs/TODO.md).

Original plan:

## The decision

**Docking writes the picture into the .md file**, as
`![](.drawings/media/<uuid>.jpg)` on a line of its own. A floating picture
stays where it is today — a sidecar object the text knows nothing about — and
docking moves it into the markdown.

That is a change of kind, not of degree, and it is why this is written down
before anything is built: a docked picture becomes part of the note's bytes.
Anything that opens markdown shows it; the note and its `.drawings/media`
folder have to travel together; and the picture stops being an object on the
drawing layer, so it can no longer be dragged, rotated, scaled or cropped
until it is undocked.

The case for it is that it is the only version of this feature that does not
invent a second layout model. Everything Sean asked for falls out of what is
already built:

- *text cannot overlap it* — a cell has its own row in the stack;
- *the caret goes above and below* — that is exactly where the seams are;
- both panes lay it out without being told, because both already lay out cells;
- ⌘Z takes it out the way it takes out any other edit;
- the PDF gets it for nothing;
- and the note stays a markdown file, which is the rule the whole app is built
  on (AGENTS.md: "The NOTE is a markdown file and nothing else; everything
  that is not markdown … lives in a hidden sidecar"). An image reference *is*
  markdown.

### The two I am not proposing, and why

**Exclusion paths.** Keep the picture in the sidecar and have the text flow
round it. This is the version that already existed and was taken out on
2026-09-20 ("all drawing, captured or drawn with the pen tool, are now free
floating and don't belong to cells whatsoever and so don't push other cells
around"). It also carries a trap on record: a full-width exclusion rect made
TextKit 2 lay out nothing at all past it and the whole note vanished, which is
part of why the source pane is still TextKit 1.

**An anchor plus a sidecar flag.** Write `<a id="wm-…"></a>` into the note the
way `/link` does and keep the picture in the sidecar, pointing at the anchor.
The anchor survives editing, but it reserves no space — so the text would
still run under the picture, and "text cannot overlap" would need exclusion
paths after all. It is the first option wearing a hat.

## The model

One new file, `WriteMind/Editor/MarkdownImages.swift`, pure and tested:

- `markdown(file:alt:)` — the line that docks a picture.
- `picture(in: line)` — the `(alt, path)` a line is, **only when the line is
  nothing but the image**. Words round an image are a paragraph that carries a
  picture, which is the inline renderer's business; "text above and below" is
  a statement about the cell.
- `mediaFile(at: path)` — the file inside the note's own media folder that a
  path names, or nil for a picture that lives somewhere else. Only the app's
  own are drawn off the sidecar folder and counted by the media sweep.
- `mediaFiles(in: markdown)` — every picture of the note's own a file points
  at. This is what stops the sweep deleting a docked picture.

And one new block: `MarkdownBlock.picture(alt:path:)`, recognised in
`MarkdownParser.positioned` before the paragraph branch.

## What changes

| Where | What |
| --- | --- |
| `MarkdownImages.swift` | new — the four pure functions above |
| `MarkdownBlocks.swift` | the `.picture` case, and one branch in the line loop |
| `MarkdownPreview.swift` | a `DockedPicture` view, the `.picture` arm of `BlockView`, and a `noteFolder` environment key so a relative path can be resolved |
| `EditorPane.swift` | sets `\.noteFolder`, wires `store.dockPicture` |
| `CellTypes.swift` | `Kind.picture(line:)`, so docking at an armed bar goes through the one block builder every other kind does |
| `EditorBridge.swift` | `dockPicture(_:)` — the armed bar first, then the caret's cell |
| `NoteStore.swift` | `dockImage(_ id:)` — write the line, then take the item out of the drawing, in that order and in one undo step |
| `DrawingCanvas.swift` | the handle, and later the drag |
| `Drawing.swift` | `pruneMedia` reads the notes as well as the sidecars |
| `NoteExport.swift` | the PDF's `noteFolder` |
| `SymbolTests` | the handle's icon name |

## The gestures

**The button** is a handle on a selected picture, beside crop and read. It
docks at the input cursor: at the armed bar if one is up — which is already
"a command at a bar makes the cell there" — otherwise after the cell the caret
is in, because a picture cannot be *inside* a paragraph if text may not
overlap it.

**The drag** is the same handle dragged. It is the more expensive half and
should be its own build, because neither pane publishes its seams: the drawing
layer is above both and knows nothing about where the cells are. It needs
`MarkdownPreview.seams` and `CellInsertions.seams` reported out to the store
the way `onTopCell` already is, and then the canvas can draw the insertion bar
under the pointer and dock at the seam the release lands in. Sean's "or in an
existing cell" is the same thing: the seam under the pointer, which is either
between two cells or the one at the end of the cell it is over.

## The traps

- **The media sweep deletes what no sidecar mentions.** `DrawingStore.pruneMedia`
  reads every `.drawings/*.json` and removes any file in `media` that none of
  them names. A docked picture is in no sidecar — it would be deleted on the
  next sweep, which runs from `NoteStore`. The sweep has to read the notes'
  markdown too. **This one loses a picture if it is missed.**
- **Size is not in markdown.** `![]()` says nothing about how big an image is,
  so a docked picture cannot keep the width it had floating. The rule is the
  column's width, capped at the picture's own, so a thumbnail is not blown up
  and a photograph is brought down. If Sean wants the floated size kept it has
  to be `<img width>`, which is portable HTML like `<u>` and `<span style>`
  but needs the block parser to read HTML.
- **A cell with no height is a cell nothing can hold.** A picture whose file
  is missing must still draw something a line tall, or neither a bracket nor a
  seam can take it — the same reason a `Divider` carries a body.
- **One undo step.** The write goes through the editor bridge and the removal
  through `beginDrawingChange`, which are two undo stacks. They have to be
  ordered so a ⌘Z that puts the line back also puts the picture back, or a
  docked picture can be lost between them.
- **Undocking is not in this plan.** Sean did not ask for it. It is the
  obvious next question and the model supports it — take the line out, put an
  `ImageItem` back — but nothing here builds it.
