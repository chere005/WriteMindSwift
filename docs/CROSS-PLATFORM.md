# For the cross-platform app

A running log of what is built HERE, in the macOS app, that the cross-platform
port (`~/GIT/WriteMindCross`) has still to implement. Sean, 2026-09-21: "keep
a log of things we're working on for the cross platform app to eventually
implement."

**How to keep it.** One entry per change that a user would notice, added in
the same commit as the change, newest at the top. Say what the behaviour IS,
not how this app does it — the port shares no code with this one and an entry
that names a Swift type is an entry it cannot use. Name the rule and the
gesture; the reason belongs here too, because a port that does not know why
will re-argue it. An entry moves to **Done there** when the port has it, and
nothing is deleted: this file is the ledger of the two apps agreeing.

## Open

### ⌘1–⌘0 act on the cell the cursor is in, and a paragraph's second Return leaves it
Sean, 2026-10-03: "pressing cmd1-0 should change type of cell cursor is
currently in, or insert a cell of that type if the cursor is horizontal... a
single return should enter a newline, a second return should remove that
newline, and move the cursor to after that cell".

- **A cell-kind key converts the cell the caret is in, or inserts one at the
  horizontal cursor.** ⌘1–⌘7 (the heading ladder, body) and ⌘8 / ⌘9 (code,
  evaluation) with the caret anywhere in a paragraph, heading, list or quote
  change THAT WHOLE CELL to the kind; at the horizontal cursor between cells,
  or on a new empty line, they make a new cell there. ⌘8/⌘9 on a cell of words
  make the cell a fenced block holding its words — a heading's `#`, a list's
  bullets and a quote's `>` dropped, one line each, inline markup left as
  written — and the caret ends at the end of them. A cell already of that kind
  is left alone and the footer says why; a fenced cell keeps its own rules (⌘9
  turns a code cell into an evaluation cell). The old behaviour — the
  paragraph cut at the caret with the block between the halves, and all the
  rules about never cutting through a span or leaving a half that reads as a
  list — is gone with it: nothing is cut. ⌘0 (a drawing cell) still inserts
  after the cell.
- **Return at the end of a paragraph types a newline; the second Return takes
  it back out and moves the cursor to the horizontal cursor under the cell.**
  Only a paragraph: a heading's Return still makes the next cell at its end,
  a list item its next item, a code cell a newline. The caret sits on the
  typed newline in the cell (no horizontal cursor there yet) until it moves,
  which leaves the newline as an ordinary blank line. The last cell of a note
  with nothing after it keeps the newline — it is the line under the cell —
  and the cursor goes there.

### Drawing cells: one line in the note, one visible file beside it, ⌘0
Sean, 2026-10-02: "on drawing segments, add a dock button which inserts it
into the cell of the existing cursor, and a create cell from drawing which
has a new type of cell.. and drawing cell which is cmd + 0"; asked whether
the files should be hidden or visible, "visible data generally speaking".

- **The line.** `![](_drawings/cells/<UUID>.png)` on a line of its own, a
  blank line either side, the UUID upper case when written. It is a drawing
  cell when the WHOLE trimmed line is exactly that — any alt text, the
  folder exactly, a UUID in either case, `.png` — optionally preceded by
  `<a id="…"></a>`, the anchor a link to the cell writes in front of it.
  Words beside it, another folder, `../`, a name that is not a UUID or
  another extension: a paragraph, as before. Inside a fence (closed or
  not) it is code. The cell is known by its UUID and nothing else. The
  block above a drawing line ends where it ended; it does not run on over
  the image line.
- **The file** is `_drawings/cells/<UUID>.png` in the note's OWN folder —
  so the line is the same at every depth and a moved note never needs it
  rewritten. `_drawings` is the note's data and NEVER a section: never
  listed, never counted, never a name a new or renamed section can take,
  never a place a note or a section is moved to (any letter case). The
  older hidden `.drawings/` sidecars are not moved.
- **What is in the file.** A PNG any reader shows (the cell painted on
  white, at twice its points), and in it, just before IEND, an `iTXt`
  chunk with keyword `WriteMind`, compression flag 1, method 0, empty
  language and translated keyword, and the payload zlib-compressed (a
  standard zlib stream: header, deflate, Adler-32). The payload is JSON
  with sorted keys: `{"aspect", "items", "version": 1, "width"}`. `items`
  are exactly the drawing layer's own objects as the sidecar stores them.
  EVERY FRACTION IS A FRACTION OF `width`, ON BOTH AXES — x in 0…1, y in
  0…`aspect` — so growing the cell moves no point and nothing stretches.
  `width` is the column's width in points when the cell was first drawn
  in; `aspect` is height ÷ width. An empty cell is eight lines of the
  note's text tall; ink within a line of the bottom gets four lines of
  room under it (it never shrinks by itself); dragging it shorter stops at
  the ink plus 12 points, and never under two lines.
- **What each state of the file means.** Nothing there: an empty cell,
  created by the first change. Our PNG, version 1, every object read:
  editable. A PNG with no `WriteMind` chunk: that picture, read-only. Our
  chunk but a newer version, one object that will not decode, a bad CRC
  or a bad stream: its pixels, read-only, one line saying why — never "the
  rest of it". An iCloud placeholder (`.<UUID>.png.icloud`): one line,
  "not downloaded yet", and nothing is ever created over it. Changed by
  another writer since it was read: the write is refused and the cell goes
  read-only. A write only ever goes over the bytes last read or written.
- **Nothing under `_drawings/cells` is ever deleted** — not by emptying a
  cell (it is written empty), not by deleting its line, not by any sweep of
  unused pictures. A note moved to another folder COPIES its cells' files
  there and leaves the originals; renamed, nothing happens; trashed, its
  cells stay, so putting it back works; duplicated, the copy's lines get
  new UUIDs and copies of the files (one id pasted twice stays one id in
  the copy), and a note with no cells is copied byte for byte.
- **⌘0 (Ctrl+0 on the port): a drawing cell here**, also Insert ▸ Drawing
  Cell and Drawing at the bottom of the + on the bar — the one kind there
  that opens the moment it is chosen, because its next input is a stroke.
  One text edit, undone by one undo. At an armed bar the cell is made
  there. In a cell it goes UNDER THE CARET'S OWN SOURCE LINE: after a
  one-line paragraph or heading; in a list, a quote or a paragraph of
  several lines, under the line the caret is on, which makes that cell
  two. A fence is never split (after a code or maths cell), nothing comes
  between an evaluation cell and its answer (after the answer), a drawing
  cell gets the next one after it, a cell of blank lines takes it at the
  caret. On the rendered view with nothing open, at the gap nearest the
  middle of what is on screen — never after the note's first cell for want
  of a caret. The caret ends at the end of the new line; the mode is left
  alone; a drawing cell is never opened as its markdown text.

### A drawing cell is static, and clicking into it is the one way to draw in it
Sean, 2026-10-03: "drawing cells are static unless you enter click into it,
which forces you into a drawing mode where you can only draw in that cell
(mouse or wacom into cell (if wacom is in write on notebook mode)) otherwise
you can select and insert like normal or page capture by selection from a
document camera". It replaces the rule of 2026-10-02 that the cursor draws
on a cell's paper: a drag meant to scroll or select left ink, and a pen used
as a pointer drew at once (see the entry on drawing mode turning on only when
asked for).

- **Static.** A drawing cell shows its picture and nothing draws into it —
  not the pen, not the cursor, not the tablet's pen — whatever the pen mode
  or the tablet is doing. A pen stroke, a placed mark or a tablet stroke over
  one is floating ink on the page, over the picture. The cell is still
  selected by its bracket, moved, deleted, held with others, inserted round,
  and receives pictures the normal way (an insert, a page captured by
  selection from the document camera, Dock). In the markdown view it is the
  static picture it always was and cannot be entered: the rendered page owns
  the mode.
- **Entering is a click.** A press on a writable cell's paper that never
  travels (under 3 points), with the mouse in cursor mode or under the pen
  (a pen click there is the way in, not a dot): the cell is entered and the
  caret goes into it. Not with a shape, a mark or the arrow tool armed
  (those do their own thing where pressed: a tick goes down on the cell,
  floating), not with ⌘ held (the selector), and not through a floating
  object lying over the cell, which takes the click. Under the pen a press
  that does travel is an ordinary stroke from where it began; the click
  leaves no dot and no empty undo step. A read-only cell, or one still
  downloading, is never entered. With the tablet's target the notebook, the
  pen TAPPING a cell (down and up under 3 points) enters it and leaves no
  dot; a stroke that travels is floating ink from where the tip touched
  down. With the target the tablet's own page the pen never touches a cell.
- **In the mode** — shown by a tint and a firm outline on the cell (it does
  not move), "Drawing in this cell" with a Done control on its corner, a line
  in the status bar, and a pencil pointer over it — drawing goes ONLY into
  that cell: a mouse drag, or the tablet's pen on the notebook. Every press
  inside the cell is a stroke (⌘ is still the selector, inside the cell),
  whatever floats over it; every point is held inside the cell, so a stroke
  dragged out runs along its edge and nothing lands outside; the eraser and
  the selection box work on that cell's strokes alone; the page's objects
  show no hover handles. The cell grows to keep its ink, as it always did.
- **Its own undo and redo.** Undo and redo in the mode — the keys, the menu,
  the pen menu and the tablet pen's two buttons — take back and put back the
  strokes made in that cell, newest first, and never touch the page or
  another cell: a step counts as the cell's only when it changed that cell
  alone, so at the first step that touched anything else the cell's undo
  stops, and does nothing rather than reach past it. The tablet page's own
  undo does not come first in a cell, and with nothing left to undo the key
  goes nowhere (not to the typing either).
- **It ends** on Esc, on the Done control, on a press outside the cell — and
  one on another cell enters that one — on a click in the words, a bar or a
  bracket, when the caret leaves the cell (an arrow key, a character typed
  after it), when the cell folds away, goes read-only or leaves the note,
  on another note, a pane coming or going or the markdown view, on picking
  the pen, a shape, the arrow tool, and on every way onto the page (an
  inserted picture or text box, a capture). A pen touch outside the cell
  ends it and draws nothing. It does NOT end by itself between strokes.
- **The mode can end with a press down** (Esc, ⌘P, ⌘T or a keyboard note
  switch with the button held; the cell folding away) and nothing of that
  press goes onto the page. A stroke under way in a cell that is still there
  carries on, held inside the cell, and lands in it when the press ends —
  its points are in the cell's own fractions, so letting go of the cell's
  space mid-stroke makes a mis-scaled stroke on the page. In a cell that has
  gone, or another note, the press is dropped and the rest of the drag does
  nothing. The tablet's pen is the same: a stroke lands in the cell it began
  in, or nowhere if the cell has no frame (never floating over where the
  cell was), and its eraser and selection box stop when the mode does, since
  both would be the page's from then on.
- **⌘Z is the ink's after a stroke in a cell, mouse or pen**: it belongs to
  the drawing until the next keystroke, down to where the drawing stood under
  the stroke, so ⌘Z after Esc or Done never undoes the typing before it.
- **Why a press is decided in one pure place**: a drag gesture cannot be
  driven from a test here, so what a press about a cell means is a function
  of where it began, what is under it, what tool is armed and whether ⌘ is
  down, and the port should keep it as one too.

### Return is a line break, and ⌫ at the start of a cell does nothing
Sean, 2026-10-02: "return should be a newline, backspace at beginning does
nothing..". Two decisions from the cell UX pass below, the same in the
markdown view and the rendered one:
- **Return anywhere inside a cell puts a line break in that cell.** It never
  cuts the cell in two — splitting is a command of its own (⌃D here). The
  rendered view used to split the block at the caret and open the tail; the
  markdown view never did, and the two must leave the same bytes, at the very
  start of a cell included (the newline goes in above the words, and the cells
  are as they were). Return at the END of a paragraph types a newline and
  the second Return leaves (2026-10-03, the first entry above); at the end of
  a heading it still makes the next cell, as the entry below says.
- **⌫ with the caret at the first character of a cell does nothing.** It never
  joins the cell to the one above — merging is a command of its own (⌃M
  here). Inside a cell ⌫ is ordinary, a line break Return put in included. In
  a markdown source view this means the key must be caught before the editor
  takes the blank line above; an editor that holds one cell's own text has
  nothing before offset zero and gets it for free.
- **Lists, quotes and code keep their own rules**, unchanged: Return at the
  end of an item makes the next item and on an empty item ends the list;
  inside an item's words on the rendered view the rest of them become the
  next item (one reminder of a checklist is one line, so its Return is always
  that); a quote carries its marker on; a code cell's Return is a newline
  anywhere in it, its end included; ⌫ inside a list marker's indentation
  takes a level off; ⌫ in an empty cell removes it; ⌫ at the start of a
  reminder's words joins them to the reminder above (one list, inside one
  cell); ⌫ just behind a heading's hidden marker on the rendered view takes
  the marker. A cell of empty lines is the note's own, and ⌫ in it takes a
  line as it always has.

### Keys at the insertion bar, and cells held by their brackets
Sean, 2026-10-02: "do a thorough test of cell selection and input insertion
ux behavior...". What a test pass across both views settled, each the same in
the markdown view and the rendered one:
- **A key at the bar.** Return makes an empty cell there; ↑ goes into the cell
  above (caret at its end), ↓ into the cell below (at its start), and at the
  top or bottom of the note the bar stays; every other key takes the bar
  back, and Escape, ←, → and every key that could edit — ⌫, ⌦, Tab — do
  nothing else. A key pressed at a bar must never edit the cell beside it. A
  key that only moves, selects or scrolls — Page Down, Home, End, ⌘↓, ⇧↓ —
  still does that once the bar is out; swallowing those with the edits left
  no way to start a selection or page down from a bar. Where the caret is
  left, if the view has one, is inside a cell, never on the empty line
  between two: a character typed there joins the cells either side into one
  paragraph. And whatever shows the caret's cell — its lit bracket, its
  markers shown for typing — has to hear about it even when the caret was
  already there, as it is after a click on the bar.
- **The arrows reach every bar**, the one above the first cell and the one
  under the last included, and Return at the end of a cell leaves you on the
  bar under it — what is typed next is a new cell, not a second line of the
  one above. There is no bar under a code block whose closing fence has not
  been typed: it runs to the end of the note, and ↓ off it stays in its code.
- **A command that acts on a cell does nothing at a bar**: delete,
  duplicate, move, split, merge, move section. The bar is in no cell; a
  fallback to "the first cell" turns Delete Cell at a bar into deleting the
  top of the note.
- **Cells held by their brackets**: typing (or pasting) replaces ALL of them
  with one plain cell holding what was typed, where the first was; ⌫ and ⌦
  both take them and close the stack; Escape lets go; a click on a bracket
  that is already held, with no drag, takes that one alone. A text widget
  that edits only the first range of a multiple selection is not enough
  here — and the replacement is whole cells, never reshaped on its way in by
  the editor's own tidying of markdown markers: that lost a `#` typed over a
  section and a closing backtick from a cell nobody held.
- **A drag from a bar** takes cells only — never the bracket round an
  evaluation pair as if it were one, which took the cell above the bar too.

### A code block, an evaluation cell or maths always lands as a cell of its own
Sean, 2026-10-02: "make math and code block insertion sensible..". One rule
for the code button / its key, the evaluation-cell key and the maths palette,
asked with the whole note and where the caret is, and the same answer in the
markdown and the rendered view.
- **At the insertion bar** the cell is made there — with the code language
  picked under the button (the + on the bar offers the plain one).
- **Never nested.** Inside a fenced block: the same kind does nothing and
  the status line says why (a code block in code; an evaluation cell in a
  cell already running in that environment). The evaluation key in any
  other fenced cell turns it into one — except an answer, after which a new
  cell is made. Maths in a block that is already Wolfram Language (maths,
  a Wolfram evaluation cell, Wolfram code) goes in as the bare WL at the
  caret, on a line between the fences (given one when there is none).
  Inline maths in other code is refused. Anything else goes AFTER the
  block — after its answer when it has one, never between code and what
  it said. A fence whose closing line has not been typed runs to the end
  of the note: the caret at its very end is inside it, and a cell made
  after it writes the closing fence first, or the new fence would close
  it. Inline spans follow the same two rules: maths in a `wl:` span goes
  in bare, inline maths in another code span is refused.
- **A cell of its own**: a blank line above and below. A paragraph is cut
  at the caret (the spaces at the cut dropped; at the front of its words
  the block goes above, at the end below) — never through an inline span
  (code, maths, bold, italic, struck, a link, a tag: the cut goes to its
  nearer edge), and never where either half, on a line of its own, would
  read as something else ("- it was late." a list, "# 42" a heading,
  "---" a rule, three backticks a fence): the cut moves on a word instead,
  nothing typed is escaped. A heading, a list, a quote or a
  rule is cut only between lines — above the caret's line when the caret
  is at the front of its words or in its marker, below otherwise — so no
  item's words are split and no marker is left bare. On an empty line of a
  run of empty lines that is a cell of its own, the block takes that one
  line and the rest stay.
- **A selection is the content**: code verbatim, the text either side
  staying cells (all of an item's words take the item; part of one line's
  words come out of it, and the line keeps its marker and the rest, the
  block above it or below it; a span whose words are all selected goes
  whole, markers too). The selection is read without the spaces and the
  newline at its ends, so a triple-clicked line counts. Maths replaces a
  selection only when the maths still holds it — the selection reads as
  maths (no word in it: a name of two or more letters that is not one the
  maths is set with and not a function's head) and is a whole term of
  what is inserted; otherwise the words stay and the maths goes after
  them. The palette opens with a selection that reads as maths, inline
  when it sits inside a line; a shape picked then takes it into its first
  slot. A selection with a fence in it is refused.
- **The caret ends where typing goes** (between an empty block's fences, at
  the end of what it was given, at the end of display maths), and **one
  undo takes the whole insertion back** in both views — in the rendered
  view the new cell opens for typing and the undo lives with it, ON TOP of
  what that cell's editor could already undo: the evaluation key on an
  open code cell is the same cell, and what was typed in it stays
  undoable.
- Port note: the opening at the bar must be ONE change on the undo stack; a
  wrapper that announces a change around a call that announces it again
  registers it twice, and undo then runs past the end of the text.

### ⌘T keeps everything where it was
Sean, 2026-10-02: "preserve the position of things as much as possible
between markdown and wysiwyg mode". The two modes lay the same cells out
at different heights — the rendered page leaves a full blank line's air
between two cells where the markdown view, markers hidden, leaves about
half that; a code cell's fence lines are full lines in one and a little
padding in the other — so anything carried across as a number of points
lands somewhere else. Three things cross, all by the CELLS the two views
share (a cell is known by the character offset it starts at):

- **Drawings are kept in ONE view's frame and shown in the other through
  the cells.** Keep them where the markdown view puts them (that is where
  a launch opens and where captures land under the caret, so it is where
  existing drawings were made). The rendered view maps a point
  piecewise-linearly between the edges of the cells both views have laid
  out: inside a cell by how far down it, in the gap between two by how far
  across the gap, above the first cell by how far down the air above it,
  past the last by the distance below it; across, linearly between the
  two text columns. It must be monotone and exactly invertible (the same
  knots, swapped) and the identity when the layouts agree; a cell only
  one view has (folded, not measured yet) is no knot. An object moves
  WHOLE by the top left of its box — never stretched — a group by the top
  left of the whole group, and an arrow point by point with its ends put
  back on its nodes. Whatever is drawn, dragged, dropped or cropped on the
  rendered view goes back through the inverse — a group by the corner of
  all of it, even when the canvas writes its members one at a time;
  anything whose corner did not move keeps the offset it was shown with,
  so a label typed, a colour, grouping, ungrouping or deleting a member
  moves nothing in the stored frame (the rendered view then shows the new
  grouping by its corner at once); anything it did not touch is written
  back exactly as stored. A position about to be saved is worked out from
  the markdown view's layout as the note is now, never from one carried
  along while typing or resizing; that layout is redone when the width
  changes, not the height. The PDF, laid out the rendered way, uses the
  same mapping.
- **The top of the window is a cell and how far into it**: 0 at its top,
  1 at its bottom, between −1 and 0 in the gap above it. Both views read
  it by one rule — the first cell whose bottom is below the top edge —
  and put the same fraction back. It belongs to the open note (another
  note opens at its top) and moves with its cell when an edit lands above
  it.
- **The cursor goes with it**: a caret or selection (in note offsets), the
  cells held by their brackets, or the bar between two cells with the
  kind its + chose. On the rendered view the cell round the caret opens
  with the caret at the same character (after the fence line, for code;
  in one reminder's words, for a checklist); on the markdown view the
  caret is put back and takes the keyboard. With no cursor, the markdown
  view's caret goes to the start of the cell at the top of the window,
  and a command on the rendered view opens that cell — never the end or
  the start of the note, which nobody is looking at.

### Double-click renames a note or a section in the sidebar
Sean, 2026-10-02: "rename in place in the sidebar.. double click is rename in
sidebar".
- **Double-click a row and its title becomes a text field**, words selected, in
  the same row; Return commits, Esc cancels, losing the keys commits (as in
  Finder). A single click still selects at once — the double-click is
  recognised beside the click, not after waiting out it.
- **One rename**: the field commits through the same store call the context
  menu's Rename… uses (`/` and `:` become `-`, a taken name gets " 2", an empty
  or unchanged one does nothing). A project's top folder is not renamed here.
- **Port trap**: set the field's focus on the next tick after it appears — set
  as it appears, the notes' own text view keeps the keys — and select its words
  only through a FIELD editor, never a select-all down the responder chain
  (it selected the whole note).

### Dock and Make Cell (floating objects into a drawing cell)
Sean, 2026-09-22 and 2026-10-02: "a dock button which inserts it into the cell
of the existing cursor, and a create cell from drawing which has a new type of
cell".
- **Two handles on a FLOATING selection** (not a cell's): Dock at the left,
  Make Cell at the right, both in the middle of the side — a row under the box
  instead when it is under 16 pt tall.
- **The objects are moved, not copied** (same ids, groups, pressures), lifted
  with whole groups; an arrow goes when picked or when both its ends go; an
  arrow with one end on something that goes stays and lets that end go where it
  is. A picture's file is COPIED to `cell-<cell>-<picture>.<ext>` in the media
  folder (never swept) and the picture renamed.
- **Where**: a drawing cell the cursor is in → into it (the objects' place on
  screen kept when their box meets the cell, else under its lowest content; the
  cell grows); an armed bar → a new cell there; a cell of words → a new cell
  under the caret's line; no cursor, or Make Cell → the seam nearest the box's
  top. A new cell is the column wide, `pad` above and under the set, x kept on
  the column, scaled down only when wider.
- **Undo**: the dock is ONE step on the drawing stack, and the step carries the
  cell's line with it — undo takes the line out of the note, redo puts it back
  (keyed by the step number; a new step drops the undone dock). Do it on the
  layer as the pane SHOWS it, so the rendered page's mapping is respected.
- **Port traps** (found driving the app, 2026-10-02): a page that sizes a
  drawing cell from the width it is OFFERED, with a legacy scroller that appears
  when the page gets taller, loops forever — size it from the window's width and
  let it hang into the margin. And a platform text engine may construct its own
  layout helper subclass through the base initializer; give a custom one an
  initializer it can call.

### Subgroups: ⌘-click picks one object, and a drag of a group is one write
Sean, 2026-10-02: "object grouping is really slow. optimize that.. it should
also be quick/easy to select a subgroup and include more with holding cmd".
- **The selection is exact.** A click or a marquee grows to whole groups once,
  when it picks; nothing grows it again afterwards (handles, delete and the
  group key act on exactly what is held). ⌘-click on an object flips that ONE
  object in or out of the selection, a group's member on its own; a ⌘-drag
  that starts on an object adds what it touches; over empty paper a ⌘-drag is
  the marquee, replacing.
- **Grouping takes what is picked and no more**: part of a group makes a group
  of that part and the rest keeps the old one; a group left with one member is
  let go. Ungrouping a part frees just that part.
- **Speed**: a transform of the selection (move, scale, turn) is worked out on
  one copy of the drawing and written ONCE. Where the page maps writes back
  through another layout, a write per member is quadratic — it was 4.9 s a
  frame for a 210-member group.

### The tablet over the notes: Fit or Real size
Sean, 2026-10-02: "a toggle from scaling to real drawing size or the mapping
to the entire visible screen". Only with a tablet writing in the notebook.
- **Fit** (default): the whole tablet, turned the way it is held, as big as
  fits the visible notes less a margin, centred, never stretched.
- **Real size**: the tablet's active area in millimetres at 72/25.4 points
  per millimetre (a point is 1/72 inch — use the platform's logical unit),
  centred on the visible notes and NOT shrunk when the pane is smaller. The
  pen over the part that is off the notes writes along the edge (clamp the
  pane position), and the outline is clipped.
- Two icons on the tablet bar where the page's pen and paper sit (reserve the
  same width for both so the row does not change size between modes), a View
  menu item, remembered.

### The Wacom pen's buttons: hold = eraser / box, double press = undo / redo
Sean, 2026-10-03: "the undo button on the wacom pen should actually be a press
and hold to make it an eraser that deletes entire strokes .. a double press of
that same button is undo ... the other button is hold to drag a selector box (as
if clicking and dragging), and double tap to redo".
- **Lower switch (nearer the nib, BTN_STYLUS 0x02)**: held as the nib goes down it
  is an ERASER, latched for the stroke; every stroke the nib's path comes within
  a small radius of is deleted WHOLE (page: ~0.014 of the page; over the notes:
  7 points + the ink's reach, on the floating layer and in writable drawing
  cells; pictures, shapes and arrows are left). One erasure — nib down to nib up
  — is ONE undo step, taken at its first deletion. The switch held on after the
  nib lifts is the eraser still.
- **Upper switch (0x04)**: held as the nib goes down it is the selector box, as
  both switches were; both at once is the box.
- **A tap** is a press let go in the air within 0.4 s with the nib up; **two taps
  of the same switch within 0.6 s** are the command (lower = undo, upper = redo).
  One tap, a hold, a tap with the nib touching, or taps of different switches are
  nothing, and a hold clears the tap before it.

### The markdown view has no floating drawing, and the drawing data is visible
Sean, 2026-10-02: "don't show or allow drawings in markdown mode on the notebook
itself, only pure text", then "drawing cells should still appear in markdown,
just not the other drawn content on top of the notebook itself"; asked whether
the existing hidden `.drawings` folders should move to a visible `_drawings`:
"yes"; and whether a cell's bracket opens the cell or selects it: "select".
- **Markdown view**: no floating drawing layer over it (keep the pane's size for
  what is measured against it), no pen, handles or shapes. Drawing CELLS still
  show there under their line and are held, moved and deleted like any cell;
  they are drawn in on the rendered view only. A drop of a picture or box
  switches to the rendered page first.
- **`.drawings` → `_drawings`** (sidecars `<note>.json` and `media/`, beside the
  cells' `cells/`): move each item once, at load, never over anything and
  deleting nothing; a taken name stays in the hidden folder, which readers fall
  back to and which blocks the media sweep; remove an emptied hidden folder.
- **A bracket click selects the cell on both views**, and Return opens a held
  cell (a checklist is entered as a whole that way).

### Drawing mode turns on only when asked for, and is never left on behind you
Sean, 2026-10-03: "drawing mode seems to keep turning itself on as i'm
trying to navigate".

Drawing mode is whatever makes a press on the notes into ink or an object:
the pen, the arrow tool, an armed shape or mark, and the tablet's pen
writing in the notebook. One rule: a tool goes ON only by an act of the
user's — the pen button or its key, a palette tile, the arrow tool's
switch, the tablet's Write on: Notebook switch — and goes away on each of
these, which were all ways of finding a tool still on:

- **A launch has no tool in hand.** The pen is not remembered across a
  launch (it is a tool in hand, not a setting like the pen's size or
  colour); neither is the tablet's notebook target, which is the page.
  A launch is on the markdown view, in the notebook's own mode.
- **The tablet's notebook target is a tool in hand like the others**, and
  is put away by the four things below, along with every other tool: the
  nib is back on its own page afterwards, and coming back picks nothing
  up. A mouse tool picked, a picture or text box dropped on the page and a
  click into a drawing cell do NOT put it away — it is the nib's, and the
  nib tapping a cell is how it enters one. No key puts it away (Esc is the
  notes'); the footer names the switch that does.
- **Another note takes nothing with it.** The open note changing — a tab
  picked or closed, a note opened from the list or by a link — puts every
  tool away. The same note again, and typing or drawing in it, do not.
- **A pane coming or going puts every tool away**: the notes pane put
  away, the video or the tablet's page shown or hidden, the whole window
  given to the picture, a tablet picked or let go. Only a change counts: a
  pane set to what it already was does nothing. The note list is not one of
  these. The markdown view puts every tool away as before, and going back
  to the rendered page picks nothing up.
- **Esc puts away whatever is in hand**: the pen, the arrow tool, an armed
  shape or mark, an entered drawing cell. It is taken only when something
  was in hand, so with nothing up it belongs to the notes (an armed bar, a
  block being edited). The arrow tool had no key out before. Each tool's
  Esc is its own step in the layer's key chain; a port should test the real
  chain with the real wiring rather than one function that nothing calls.
- **A mark or shape still stays armed while it is being used** — the
  rule from 2026-10-02 is unchanged: putting one down does not hand the
  tool back. Leaving, Esc, another tool, the same tile again or a way onto
  the page ends it, as it did.
- **The cursor never draws, and a drawing cell is static.** A drag with
  the pen up, or a pen used as a pointer, over a drawing cell used to ink
  in it, and the pointer was a pencil over every cell on the page. Now
  nothing draws into a drawing cell because the pen is down or the pointer
  is over it, and the tablet's pen writing in the notebook floats its ink
  over a cell like over any other part of the page; the click that enters a
  cell to draw in it is described in the entry on drawing cells being static.
- **The footer names every tool in hand**, in the accent colour, each with
  how to put it away: "Pen: every drag draws, Esc to stop", the armed
  shape or mark as before, "Arrow tool: drag from one thing to another,
  Esc to stop", and "Tablet pen: writing on the notebook, pick Page on the
  tablet's bar to stop" while the tablet is the input and the rendered page
  is up. The last two had no word on screen at all before.

### Drawing happens on the rendered page only
Sean, 2026-10-02: "only allow drawing in wysiwyg mode, both from wacom and
from the pen cursor tool". It reverses 2026-09-19's "drawing should be
allowed in either wysiwyg and markdown mode" — for DRAWING; what is drawn
still shows in both views (the drawing goes through the two panes' cells).
- **Picking a tool brings the rendered page up.** The pen (button or ⌘P), the
  arrow tool, an armed shape or mark, and the tablet's Write-on-Notebook all
  go through one call that does what the ⌘T switch does when the markdown
  view is up (the place and the cursor travel with it). Put it in each
  tool's own setter, so no button or key has to remember it.
- **⌘T back to markdown puts every tool down**; going forward again picks
  none up. Putting a tool down on the rendered page switches nothing.
- **A pen remembered from last time comes up on the rendered page** — a
  launch starts on markdown, and the two may not disagree.
- **The tablet's notebook layer is mounted only over the rendered page.** With
  it away the pen has no note to write on and is a pointer, and the page
  says "Show the rendered page (⌘T) to write on the notes".

### A drawn shape stays armed, and so does a mark
Sean, 2026-10-02: "after drawing a rectangle dont exit rectangle mode.."
and then "after placing mark like check mark, i shouldn't leave place mode
similar to drawing rectangles".
- **What stays**: everything armed — a flow-chart node (dragged corner to
  corner, or clicked for one at its own size), a line or an arrow (press
  to release), and a mark: tick, cross, query, star. Once one is down the
  tool is still armed and the next press puts down the next one, with no
  key held. There is no per-kind rule and no ⌘ rule to port: the ⌘-keeps-a-
  mark entry below is superseded the same day.
- **The ways out**: Esc; the same palette tile again (light the armed
  tile, so it can be found); another tile; the arrow tool — the arrow tool
  and an armed shape each put the other away, since an armed shape is
  asked for the press first and would take every drag meant for the
  arrow; a mode or the pen; and EVERY way something is dropped on the
  page to be typed in or picked up — a text box or a picture from the bar
  or the Insert menu, a capture from the camera or the tablet — which
  would otherwise lose its click to the armed shape. Route them all
  through one call; the first cut here did the bar's two and missed the
  menu's and the captures.
- **While armed**: the footer names it and says every drag draws one and
  Esc stops it; the bar lights the palette button whose palette holds it,
  as it lights the pen (both buttons for a box, circle or triangle, which
  are on both palettes); the pointer stays the crosshair and the selection
  handles stay hidden; what was just drawn is selected, so delete and
  undo take it back without disarming.
- **A click on a node is the node's** while a node or a line is armed:
  the flow chart is drawn as a loop — a box, a double-click for its
  label, the next box — and an armed box took both clicks of the
  double-click, stacking two boxes on the one clicked. A press that never
  moved and lands on a node picks it (its whole group), and a
  double-click opens its label, by the same rule as with nothing armed
  (a node in a group opens none). Anywhere else a click puts a node down
  at its own size; a drag that starts inside a node still draws; a mark
  clicked onto a node goes down in it; no ghost is drawn for a click
  that will pick. The next press ends a label being typed or a style
  bar, so the next box follows the label straight away.
- **Kept as it was**: an armed tool takes the press before any mode or
  modifier; a press that never moved puts down no line and leaves the
  tool armed.

### The pen's two buttons undo and redo the last drawing
Sean, 2026-10-02: "make the wacom buttons undo and redo last drawing". The
One by Wacom's pen has two switches on the barrel; each is its own bit of
the raw report (the entry on taking the tablet: 0x02 the lower one, nearer
the nib, 0x04 the upper). What the port has to copy:

- **A click is a command.** A side switch pressed and let go with the nib
  UP the whole time, the pen in reach, is a click: the LOWER switch
  undoes the last drawing, the UPPER redoes it. It fires as the switch is
  let go, once per click however long it was held or however far the pen
  moved meanwhile, and never repeats.
- **Whose undo, by where the pen writes.** In Page mode it is the page's
  own undo and redo — exactly what the page's two corner buttons do, and
  ⌘Z/Ctrl+Z is the page's afterwards as it is after them. In Notebook
  mode it is the note's drawing undo and redo — the very same functions
  the drawing-undo keys call, never a second history — and only while
  notes are on screen. With nothing to take back or put back the click
  does nothing: no sound, no empty step, no claim on the key.
- **The box is begun by the nib now.** A switch HELD AS THE NIB GOES
  DOWN — either switch — makes the stroke the box (the page's selection
  box, the notebook's marquee); once begun it goes on, as it always did,
  while the nib or the switch is down — the switch let go mid-drag is
  still the box, and so is the nib lifted with the switch held — and it
  ends when both are up; and a tap with the switch held is the box's own
  click (puts a box away on the page; a ⌘-click on the note). The switch
  alone in the air begins nothing any more — it used to begin the box
  there, which a click could not have been told from. Letting the switch
  go after a box is the box's end, never a click.
- **What is not a click**, and arms nothing: the nib touching while the
  switch is held; a switch pressed under a stroke or a box, whether let go
  under it or after the lift; a switch already held as the pen comes into
  reach, or held as it leaves; both switches at once (nothing says which
  was meant — wait for both to be let go); and a raw report that is not
  "ready". Treat an unready report's switches as UNKNOWN: neither pressed
  nor released — read as "let go", one at the edge of the tablet's reach
  could make a click of a switch still held (a precaution; how this
  pen's reports end there was never measured).
- **One switch by pointer events.** Pointer events carry one barrel button
  (`buttons & 2`, the OS's "right button"), and nothing in them says which
  of the two it was: take it for the lower one — undo — and say in the
  docs that redo needs the raw reports (WebHID), where both bits are. The
  hover-time press is a pointer event with `pressure === 0` and
  `buttons & 2`; the click is the matching release with the nib never
  having touched in between. (The Mac's driver events do carry the upper
  one, as 0x4 in their mask, seen with the nib down; the Mac reads it.)
- **The log** writes the first click of each switch in a session: which
  physical button is 0x02 is the Linux driver's word (BTN_STYLUS is the
  lower one) and was never measured on this pen — if undo and redo come
  out swapped, that line says which bit was pressed, and the fix is to
  swap the two in the one place that maps them.
- **The tips** on the page's own Undo and Redo buttons name the pen's
  buttons, and Redo's says it needs the pen captured.

### The tablet's picture shows its light
Sean, 2026-10-02: "make the tablet orientation icon show the led on the
tablet for the icon to give orientation". The little tablet in the page's
corner (the orientation entry below) first marked the tablet's top edge
with a heavy line — a mark no tablet has, so it told him nothing. A
picture gives orientation only by something he can find on the thing on
the desk, and that is its status light. What the port has to copy:

- **One fact, and the pen's own turn.** On the One by Wacom lying
  landscape as it ships (the frame the pen's raw coordinates have their
  origin top left in) the LED is just inside the LEFT edge, half way
  down: the raw landscape point (0, 0.5). Carry that one point through
  the same quarter-turn mapping the pen's coordinates take — do not write
  a table of four, which can drift from the one the pen writes by — and
  it lands left, top, right, bottom for 0, 1, 2, 3 turns clockwise.
- **The picture**: the outline at the turned shape (short side 0.625 of
  the long), and a dot just inside the edge the light is on, half way
  along it, clear of the outline's line by a hair. Sizes as fractions of
  the glyph's long side: line 1/12, the gap 1/24, the dot 1/4.5 across
  (never under 3 points — far bigger than the real one, because at 14
  points it has to be seen). Nothing else is marked: the tag and the
  cable are real too, but the four pictures tell apart by the light
  alone.
- **Lit, so it is a light and not a hole**: the outline takes the
  control's colour and the dot never does — a blue white (#A8DCFF) on a
  dark ground, a full blue (#0A7AFF) on a light one, with a soft glow of
  the same colour about half the dot's width. Choose it by the GROUND,
  not by the appearance alone: the list of four is dark or light with
  the appearance, but the corner's button sits on glass over the pane's
  black, a dark ground in both (a mid grey, about #6E706F, in light),
  and takes the blue white in both.
- **The words say it too.** Each row's second line is what was done to
  the tablet and where that leaves its light — "As it ships · light on
  the left", "A quarter turn clockwise · light at the top", "Turned half
  way round, for the other hand · light on the right", "A quarter turn
  anticlockwise, for the other hand · light at the bottom" — with
  "· light at the top" kept from wrapping apart, and the list wide enough
  that the default's line does not wrap at all. The hover tip is the
  name and that line. The line under the four ends "The dot is the
  tablet's light — on the left as it ships."

### Ink the colour of the note's paper is shown as its opposite
A stroke keeps the colour it was written in, but on the NOTE it is painted
black or white — whichever reads — when its contrast with the note's paper
is under 1.5 (WCAG ratio). Decided at paint time from the current
appearance, never stored. Without it the tablet page's near-black writing,
taken into a note in Dark Mode, is in the drawing and invisible, and so is
a white pen's stroke in a light note. (Sean, 2026-10-02: "images and text
work from a selection, but taking the writing itself doesn't".) The
tablet's own page does not do this: its paper has its own readability rule.

### The app takes the tablet itself, so the pen stops moving the pointer
Sean, 2026-10-02, with the page up and the pointer flying round the other
display under his pen: "how can i disable wacom from taking over my
mouse?", "shouldn't WriteMind need some permissions like this?", "fix the
wacom not being captured by writemind properly issues". Asking the Wacom
driver does not work — its scripting interface answers every read and
ignores every write (measured on driver 6.4.14-2) — so the app opens the
tablet's HID device EXCLUSIVELY and reads the pen's raw reports itself.
While it holds the device nothing else hears the tablet: the driver goes
quiet and the pointer stays put. What the port has to copy:

- **Held only while all three are true**: a tablet is the chosen input
  and plugged in; what the pen writes on is on screen (the page, or in
  Notebook mode a note); and the app is the active one. Any one of them
  going closes the device at once, and the pen is an ordinary pen again —
  in the app's own notebook, and in every other app. Closing mid-stroke
  ends the stroke where it was. And the hold follows the pick: another
  tablet chosen while one is held closes the one and opens the other.
- **The permission, and a first launch never asks.** On macOS this is
  Input Monitoring. It is only ever READ, and nothing is opened until it
  reads granted (the system's own open would ask by itself); the question
  goes up only as the direct result of the user picking the tablet from
  the input list. Picking it again asks again.
- **Electron: node-hid holds it, WebHID only reads it.** To HOLD the
  device the open has to be exclusive, and that is `node-hid` in the main
  process: on macOS it opens exclusively by default (hidapi's seize —
  the same call this app makes) and needs the same Input Monitoring
  permission. Electron has no call of its own for that one; the
  `node-mac-permissions` module reads it and asks for it
  (`getAuthStatus('input-monitoring')`,
  `askForInputMonitoringAccess()`) — read it before every open, ask only
  from the pick.
  WebHID in the renderer (`navigator.hid.requestDevice({filters:
  [{vendorId: 0x056a}]})`, from a user gesture — the pick IS that
  gesture; `navigator.hid.getDevices()` afterwards reads what was granted
  without asking) gives the raw reports and so the counts, but as far as
  is known it does not open the device exclusively, so by itself it does
  not stop the pointer — check before relying on it. On Windows the
  vendor driver usually holds the device and the open is refused; on
  Linux the kernel's own wacom driver has it and detaching that is not
  something to do uninvited. Refused anywhere: fall back (below).
- **Which device.** Vendor 0x056A, the picked tablet's product id. The
  One by Wacom has two HID interfaces: the one that is a mouse to the OS
  (usage page 1, usage 2, 10-byte input reports) carries the pen and is
  the one that has to be held; the other (vendor page 0xFF00, 64-byte
  reports) carries nothing anyone reads.
- **The raw pen report** (One by Wacom, the Bamboo-pen class): report id
  2, ten bytes with the id. Byte 1 is flags — 0x80 in range, 0x40
  proximity (x and y are valid), 0x20 ready (tip, switches and pressure
  are valid), 0x08 eraser end, 0x04 upper side switch, 0x02 lower side
  switch, 0x01 tip. x is little-endian at bytes 2–3 and y at 4–5, in the
  tablet's RAW LANDSCAPE counts from the top left, y increasing downward
  (0…15200 × 0…9500 on the small one, 100 counts a millimetre) —
  whichever way the vendor driver's own orientation is set, and the same
  frame the quarter turn in the entry below assumes. Pressure is
  little-endian at 6–7, 0…2047, scaled to 0…1. Byte 8 is the distance
  from the surface. Out of range is the pen leaving; in range without
  proximity is the pen coming near with no position yet (never a point
  at 0, 0); the tip and the switches count only when ready, and an
  unready report says NOTHING about the switches — neither pressed nor
  let go (the entry at the top). Each switch is its own: held as the nib
  goes down, either makes the stroke a selection; clicked in the air, the
  lower undoes and the upper redoes. WebHID
  hands the report without its id byte (`event.reportId === 2`, nine
  data bytes) — shift the offsets by one. Anything that is not exactly
  this report is logged in hex and ignored, never guessed at.
- **The mode.** With no vendor driver running the tablet is a plain
  relative mouse and sends no pen reports until feature report id 2 is
  set to 2. Read it first; set it only if it is not already 2; put back
  what it was on closing. (`device.receiveFeatureReport(2)` /
  `sendFeatureReport(2, Uint8Array.of(2))`.)
- **The extent is the raw sensor's**, from a table by product id, widened
  by the farthest count the pen is seen to reach — never what the vendor
  driver reports, which is in ITS orientation (a driver set to portrait
  said 9499 × 15199 for a tablet whose counts run to 15200 × 9500).
- **One route at a time.** The raw reports become the same pen samples
  the pointer events do — same pen state, same turn, same stream. From
  the first raw report until the device is closed, pen pointer events
  are swallowed and draw nothing (one stroke by two routes would be
  two). If pen pointer events made more than half a second after that
  first report keep arriving, something else still hears the tablet: log
  it once and say so.
- **The fallback is the entry below**, unchanged: no permission, an open
  refused, no device, or a device held whose reports cannot be read, and
  the page still takes the pen from pointer events, with the pointer
  moving. That last one matters: held, nothing else hears the tablet, so
  unreadable reports would be a pen that writes nowhere. 32 reports in a
  row inside a second with none of them a pen report, before any pen
  report has been read since the device was opened, and the app closes
  it, says it cannot read what the tablet sends, and does not open it
  again until the tablet is picked or plugged in again. Try the open again when something
  changes (the app coming back to the front is one, and is when a
  permission given in the system's settings is first seen), never on a
  timer.
- **One line in the pane** says the one useful thing: held — "pen
  captured"; never asked — pick the tablet again to be asked, with a
  button to the permission's setting; refused — the permission by name,
  with the same button; allowed but still refused by the OS — quit and
  reopen; held by somebody else or failed — why, with the OS's own error
  number; and, held but pointer events still coming, that the pointer
  may still move.
- **The log** gets one line for each of: the permission as read and as
  answered, capture start and stop, each device opened and closed with
  its result, the mode report, the first twelve raw reports in hex and
  the first of each unknown kind after, the first parsed sample, and —
  with each capture's first report — whether the pen was already down
  (the driver then saw the button go down and never sees it come up).
  Never one per sample.

### The tablet's orientation, by name, and the writing turning with it
Sean, 2026-10-02: "make sure i can orient the page with the device by
rotating or flipping to make it match portrait or landscape". What the
port has to copy:

- **Four ways round, Wacom's own**, each a number of quarter turns
  clockwise from the landscape the tablet ships in: Landscape (0, as it
  ships), Portrait — turned right (1, THE DEFAULT), Landscape — upside
  down (2, "flipped": half way round, for the other hand), Portrait —
  turned left (3). That number is the only thing stored, remembered
  across launches; it is the `quarterTurns` the page's mapping already
  takes ((x, y) on a W × H tablet → (1 − y/H, x/W) for one turn).
- **One control, in the page's corner, where the two quarter-turn
  buttons were**: a little tablet drawn the way it lies — its outline at
  the turned shape, with the tablet's status light on it (the entry
  above: "The tablet's picture shows its light") — opening the four by
  name, the one in use ticked. Under them one line says what a turn does
  to what the pen is writing on (the page's writing turns with it; a
  note's stays where it was written) and what the picture's dot is. It
  holds for both modes, so it is never hidden in Notebook mode.
  It is the only control for the turn (one place per button), and the
  way it already sits picked again is no change.
- **Everything in page fractions turns in one go**: every stroke on the
  page, the whole undo history, a selection box left up (onto its turned
  corners, so it is round the same writing), and a stroke or a box half
  drawn (so the rest of it joins on where the pen is). Clockwise one
  turn is (u, v) → (1 − v, u); two (1 − u, 1 − v); three (v, 1 − u).
  Four quarter turns, or a turn and its inverse, must come back to the
  same numbers within floating error — test it. Strokes keep their
  pressures and widths (widths are in page points on an 800-long side
  whichever way round); a turned stroke is a new object.
- **Not an undo step, on purpose**: the turn says how the tablet lies on
  the desk, which undo cannot change; undoing it would leave every stroke
  a quarter turn off where it was written. Undo after a turn brings back
  the page as it was, the way round it is now.
- **The paper is laid for the new shape, not turned**: held landscape, a
  ruled page has its lines across the long side, 8 mm apart down the
  short side, and its margin on the left; dots and squares stay 5 mm. So
  writing that sat on the lines crosses them after a quarter turn — on
  purpose, since the lines are for the writing done the new way round.
- **In Notebook mode the note does not turn** — its strokes are the
  note's — but the tablet's area on the notes does, and a stroke under
  way when the turn changes is dropped rather than finished a quarter
  turn away from its start.

### The tablet writes straight into the note
Sean, 2026-10-02: "do the same for drawing mode in the notebook itself and
let the wacom control that as well.. as a separate mode". What the port
has to copy:

- **A switch, "Write on: Page | Notebook"**, on the page pane's bar and
  nowhere else on screen (a menu may mirror it), remembered, the page by
  default. Picking the notebook brings the notes into view if they were
  put away. NO KEY changes it — Escape in particular stays the notes'
  (an armed insertion bar, a block being edited, held cells, the link
  banner): the mode is one that is lived in, and a key that sent the pen
  home took every Escape away from the notes for as long as it was on.
  The switch keeps one shape and one place in both modes — it comes
  first on the bar, and the page's own controls are hidden IN THEIR
  PLACE while the pen writes in the notebook — so it never moves under
  the pointer that pressed it; at the narrow default width it is the two
  names, not two bare icons.
- **The tablet is fitted onto the notes on screen**: the drawing layer's
  own visible frame (below the tab and formatting bars, above the footer,
  in both the source and the rendered view), and in it the tablet's
  turned shape — the same (u, v) the page uses, after the quarter turn —
  as big as fits less a 12-point margin, centred, NEVER stretched, so
  handwriting keeps its proportions. A point is (area.x + u × area.width,
  area.y + v × area.height) on the pane, plus the scroll offset to be in
  the document, divided by the pane's width and height to be a stroke's
  point — and not clamped to one pane's height: a point further down a
  long note is past 1.
- **The nib writes the note's own strokes** with the NOTEBOOK pen's tool,
  colour and width (the pen menu's, never the page's), a pressure a
  point, the lift no point (a tap is a dot): the same stroke a pen
  stroke drawn on the note itself would be. One stroke is one undo step,
  taken as it lands; and Ctrl/⌘+Z straight after it takes the stroke back
  — not the typing, though the keyboard is still in the text — until the
  text is typed in again, only while the notes are on screen, and only
  down to where the drawing's undo stood under the first such stroke:
  past that the next undo is the typing's, not an older drawing step's
  (count steps taken and taken back, not the capped history's length).
  Redo stays the drawing's until the typing. The stroke being written is
  drawn on a layer of its own over the drawing, by the drawing's own
  painter. A stroke or a marquee under way when another note is opened
  is dropped, and a notes view rebuilt beside a pane that came or went
  must not leave the pen with nowhere to write.
- **While the pen is near**, a faint dashed outline of the area and the
  page's hover ring show over the notes, taking no clicks.
- **A barrel button held as the nib goes down is the drawing's marquee**:
  dragged, it draws the same rectangle a ⌘-drag draws; with the nib and
  the button both up, it picks everything it touches, whole groups, Shift to add —
  the ⌘-drag's one rule — so Delete and the handles act on it. A tap with
  the button held is a ⌘-click; the button clicked in the air is the
  note's drawing undo or redo (the entry at the top).
- **What is on screen decides**: in Notebook mode it is a note being on
  screen (the page may be put away) that takes the pen off the pointer
  and swallows its events; with no note open the pen is an ordinary pen.
  Switching with both on screen changes nothing there. Switching drops a
  stroke or a box half-done for either.
- **The page is set aside**, untouched: dimmed, one line ("The pen is
  writing on the notebook" — or, with no note on screen, that there is
  none and the pen is a pointer until there is), no box can be drawn on
  it, and its own pen, paper, undo, redo and clear are hidden; the turn
  stays, since it is the tablet's. On the web the area mapping needs the tablet's own counts
  (WebHID) or, from screen-mapped PointerEvents, the OS's own mapping of
  the tablet onto the screen — the same caveat as the page's entry.

### The page has papers, and a pen of its own
Sean, 2026-10-02: "it can have themed backgrounds and different pen colors
and strokes to write with". What the port has to copy:

- **Six papers**, each a sheet colour, a print and an ink that reads on
  it. The print is measured in THE TABLET'S MILLIMETRES (its active area:
  the small One by Wacom is 15200 × 9500 counts at 100 a millimetre, 152 ×
  95 mm, turned as the page is turned; a tablet of unknown size is taken
  to be 152 mm along its long side at its own shape) and laid down in
  fractions of the page, so it scales with the sheet and a bigger tablet
  gets more lines, not wider ones. Weights are millimetres too.

  | Paper | Sheet | Print | Ink |
  |---|---|---|---|
  | `plain` | `#FFFFFF` | nothing | `#1C1C1E` |
  | `dotGrid` | `#FFFFFF` | `#9A9A9A` dots 0.5 mm across, 5 mm apart | `#1C1C1E` |
  | `ruled` | `#FFFFFF` | `#9EC3E6` lines 0.2 mm, 8 mm apart from 16 mm down, edge to edge, to the last at least 4 mm above the foot; a `#E57373` margin 0.25 mm at 16 mm, top to bottom | `#1C1C1E` |
  | `graph` | `#FFFFFF` | `#A9CBE8` lines 0.15 mm, 5 mm squares, edge to edge | `#1C1C1E` |
  | `legal` | `#FBF2A0` | the ruling in `#8DB1D3`; a DOUBLE `#D9534F` margin, 0.2 mm, at 16 and 17.2 mm | `#1C1C1E` |
  | `blackboard` | `#1E2A24` | nothing | chalk `#F1EFE6` |

  Dots and graph lines sit on a centred lattice: as many as fit at 5 mm,
  the first at (length − (n − 1) × 5) / 2, so both edges keep the same
  margin. The pane and an Image taken off the page print the SAME paper
  in the same place (here one printer serves both, and a test compares
  them pixel for pixel); Text never sees a paper — it is the ink alone,
  black on white. The paper is the page's: the page file gains `"theme"`
  (the raw names above), read forgivingly — absent or unknown is `plain`,
  and costs nothing else. Changing it is not an undo step.
- **The page's pen is its own** — tool, colour, size, remembered apart
  from the notebook's pen (chalk on a blackboard must not leave the
  notebook writing white on white). New strokes take it as it is when the
  nib goes down; strokes already written keep theirs. Both sit on one
  small bar in the page pane's top-left corner, ABOVE the sheet so it is
  never on the writing — the pen's button shows its ink as a dot on a
  chip of the paper, so near-black ink shows on a dark bar — each opening
  a small panel: the pen's (the tool picker, the size slider, the six
  swatches plus a colour well, and the paper's own ink as a seventh
  swatch when it is not one of the six; the swatch in use ringed outside
  itself, so the ring never lands on its own colour) and the paper's (a
  row a paper, with a swatch of its real print). A dark sheet (the board)
  gets a faint light edge over its paper so it shows on the black pane;
  a picture of the page has no edge.
- **When the paper changes, ink the change leaves unreadable becomes the
  paper's own**: under a WCAG 2 contrast ratio of 2 against the new
  sheet AND lower than it was against the old one (black onto the board
  1.1, chalk off it, the amber swatch onto the legal pad: 1.8 on white,
  1.6 there). A colour that read no worse on the old paper was picked on
  one like it and is left alone — amber from plain to ruled stays amber,
  black picked on the board stays black — and picking the paper already
  in use changes nothing.
- **One tool picker, in both places**: a button per tool — Pen, Fountain
  (Pen), Pencil, Marker, Brush — its icon over its name, the one in use
  lit. The notebook's pen menu has it too, in the same order (tool, size,
  colour), and there it is a TABLET'S:
  a pen stroke in the notebook (`pointerType === 'pen'`) is written with
  the picked tool, while a mouse or trackpad stroke stays the plain line
  with no tool, exactly as before.

### A drawing tablet is an input, chosen like a camera
The list of inputs that holds the cameras lists any drawing tablet plugged
in, under them, by the name on its box ("One by Wacom (CTL-472)"). Picking
one turns the camera off and the pane that showed the video shows a PAGE
instead — a sheet at the tablet's own shape — and picking a camera gives
the pane back to the video. The pick is remembered the way the camera's
is, the two picks forget each other, and a first launch asks nothing: no
permission prompt until the tablet has been picked by hand at least once,
and only as the direct result of that pick (Sean, 2026-10-02: "wacom
should basically just be chosen as if it were an input display").

The tablet is read turned a quarter turn clockwise unless turned back
(Sean, same day: "i want to rotate the wacom 90 degrees clockwise"): a
point (x, y) on a W × H tablet, origin top left, is (1 − y/H, x/W) on
the page, and the page is H/W wide. The turn is remembered; two buttons
on the pane turned it a quarter at a time, and one control by name has
taken their place (the entry at the top). While the pen is near the
tablet a marker on the page shows where the nib is.

Where the platform can stop the pen moving the pointer while this page
is up, it should — the pen is a writing instrument on the page, the
trackpad and mouse still drive everything else, and a pen tap must never
click whatever the pointer happens to be over. (How: the entry at the
top — the app takes the tablet's HID device itself; the vendor driver
cannot be asked.) ONLY while it is up: with
the pane put away the pen is an ordinary pen again, or the notebook's
own pen has nothing to draw with. The switch that shows and hides the
pane, its menu item and its panel call it the page while the tablet is
the input, and the panel drops the camera's own rows. Where it cannot, or the
user has refused it, the page still takes the pen and the pane says in
one line why the pointer moves with it, offering the setting that would
change that. On the web that is a `pointerType: 'pen'` PointerEvent over
the page, its pressure and its eraser/barrel buttons, with
`setPointerCapture` and `preventDefault` so it does nothing else; the
side (barrel) button held is a selection, not ink.

### The tablet's page, and taking a piece of it into the note
The page is "the picture of a page" (Sean, 2026-10-02: "in normal mode its
as if we were looking at the picture of a page, and anything drawn can be
selected and inserted"). What the port has to copy:

- **The model.** The page's strokes are the drawing layer's own strokes —
  ink, a pressure a point, a tool — with points as fractions of the page
  (0…1 across and down from the top left) and widths in the page's own
  points: its LONG side is 800 whichever way it is turned. The pen's width
  goes on as it is seen: the page pen's width divided by the page's scale
  on screen at the moment of writing, so 3 points writes 3 points where it
  is being watched, and the ink grows and shrinks with the page after
  that. The nib down starts a stroke, every move appends a point with its
  pressure, the lift finishes it WITHOUT a point of its own (it has no
  pressure, and a last point at none pinches every end) — so a tap is one
  point, drawn as a dot. Ink ends where the nib lifts, whatever the
  barrel button is doing, and a barrel button still held from a stroke of
  ink makes no box of the next stroke until it is let go.
- **Kept, not in the notes.** One page, in the app's own data
  (Application Support here; the user-data folder in Electron), never in
  the notes folder. Saved half a second after the pen rests. A file that
  cannot be read is renamed `TabletPage.corrupt-<date>.json` and the page
  starts blank — never written over; a file with one unreadable stroke
  keeps the rest, is copied aside first, and is then written back with
  what could be read (so it is copied aside once, not at every launch).
  A save writes over the file only while it holds what this page last
  read or wrote; anything else is another copy of the app's, kept, and
  the page is written beside it as `TabletPage.conflict-<date>.json`. A
  build of the app with an id of its own keeps a page file of its own. Undo is whole pages, a stroke
  or a clear a step, for the session. The file is
  `{"version":1,"quarterTurns":n,"theme":"plain","strokes":[…]}`, the
  strokes in the sidecar's own shape, so either app opens the other's
  page (`theme` came with the papers — the entry above).
- **The ink turns with the sheet.** Turning the tablet a quarter turn
  makes a tall page wide, so every stroke (and the undo history) is turned
  too: clockwise, (u, v) → (1 − v, u). That keeps each stroke where it is
  on the tablet — it is exactly the mapping one turn on. The file records
  the turn its strokes are in, and a page opens turned to fit.
- **The box is the camera's box**, its three buttons and all. The nib
  dragged with a barrel button held draws it (either button; the button
  alone in the air draws nothing — a click of it there is undo or redo,
  the entry at the top), so does a mouse or trackpad drag; a tap with the
  button held, the nib going down to write, or Esc (only while there is a
  box, and
  never an Esc meant for a popover, a dialog or a field) puts it away —
  one Esc, asked in one order: a label being typed, a style bar, an armed
  shape, a crop, the box, and last the pen mode. **Image** is the box as it stands, paper and all, as a PNG.
  **Writing** is the strokes the box TOUCHES, whole, re-expressed as
  strokes on the note's layer with new ids, pressure, tool and colour
  kept, one group (a single stroke gets none), one undo step. **Text** is
  those strokes drawn black on white — explicit colours, never the
  window's: drawn through anything theme-aware, Dark Mode's black came
  out white — and read by the same recogniser the camera's Text uses,
  never through the camera's thresholding. Image and Writing land the way
  a camera capture lands: the page at 0.9 of the pane, the piece where it
  was on that page, under the caret when there is one.
- **⌘Z (Ctrl+Z) is the page's straight after writing on it**, until the
  note's text or drawing changes, and only while the page is the input
  and on screen — the pen is in one hand and the key under the other, and
  the keyboard focus is still in the note.
- **Electron.** The page is a `<canvas>` taking `pointerdown` /
  `pointermove` / `pointerup` with `pointerType === 'pen'`: `pressure` is
  the nib, `buttons & 2` the barrel button (held as the nib goes down, a
  selection, not ink; pressed and released at `pressure === 0` with no
  contact between, undo),
  `getCoalescedEvents()` gives every sample between two frames (the Mac
  app turns coalescing off for the same reason), and `setPointerCapture`
  plus `preventDefault()` keep the stroke on the page. Pointer events
  arrive in SCREEN coordinates through the OS's own tablet mapping, not
  in tablet counts; reading the counts themselves (and so the quarter turn
  in the entry above) means WebHID's raw reports, which needs a permission
  per device — the entry at the top has the report's layout and the
  rules for holding the device. Draw the finished
  strokes to one canvas and the live stroke to another on top, so 120
  samples a second redraw one stroke and not the page.

### With no tool up, nothing sits over the notebook
In cursor mode the pointer over the note is the notebook's, in both panes:
the I-beam over the words, the I-beam on its side over the space between two
cells, the hand on the + and on a bracket, the arrow beside a bracket. The
drawing layer goes over the page only while it has a pointer of its own — the
pen's pencil, the ⌘ crosshair, a hand on an object, an armed tool — and an
invisible layer left over the page with nothing to show is not harmless: here
it took every pointer update for the whole pane and answered with the arrow,
so the horizontal pointer between cells kept turning into one (Sean,
2026-10-02: "the horizontal cursor stuff should work in markdown view mode").
When the layer's pointer goes with the pointer held still — Esc puts the pen
down, ⌘ is let go, the pointer slides off an object — the notebook's pointer
for that spot comes back at once, not on the next move; and a layer that
arrives under a still pointer shows its own at once. While it is up, its
pointer is the only one over the part of the page it covers — the gutter,
the seams and the words show the same, and light no bracket and no seam,
because a press there is the drawing's — and it covers the note only, never
the bars above and below it. Every region answers for where the pointer IS
now, never for where the last event said it was.

### A pen writes ink; a mouse still draws the line it always drew
A stroke made with a stylus is INK: the outline of a line whose width
follows how hard the nib is pressed, filled. Build it with perfect-freehand
— the TypeScript original; this app runs a line-for-line port of 1.2.3,
pinned against the original's own output, so the same package with the
same options draws the same stroke the same shape. Feed it `[x, y,
pressure]` per sample, in screen points before any scale or rotation of
the stroke, with `simulatePressure: false` and `last: true` (the line runs
to where the nib IS, so nothing jumps at pen-up), and fill the outline
through its midpoints (the README's `getSvgPathFromStroke`) with the
NONZERO rule — it crosses itself at a tight turn.

Read the pressure from `PointerEvent.pressure` only when `pointerType` is
`'pen'`, on pointerdown and on pointermove while it is pressed. A mouse
reports 0.5 while a button is down and a touch reports something of its
own, and neither is a nib; a hover carries nothing to read. Take every
sample — `getCoalescedEvents()` on each pointermove — because a pen sends
about 120 a second and the shape is drawn from all of them. The stroke's
FIRST sample decides what it is: a pen makes ink, a mouse or a finger
makes the old one-width smoothed line, unchanged. Every stroke already
drawn has no pressure and must look exactly as it did; that is a promise,
not a default.

The pens (Sean, 2026-10-02: "different pen colors and strokes to write
with"). The nib is in multiples of the stroke's width and the tapers in
nibs; at the middle pressure every line is `nib × width` across, so pass
`size = nib × width ÷ (2 × easing(0.5))` (just `nib × width` when
thinning is 0) and the width slider keeps meaning what it says. Every
easing here is at or above 0.5 at 0.5, so no size is more than its nib —
perfect-freehand reads `size` as a length too (the samples it skips at a
line's start, the spacing of the outline's points). The easings are the
perfect-freehand demo's, by name.

| tool     | nib  | thinning | smoothing | streamline | easing        | start taper | end taper | opacity |
| -------- | ---- | -------- | --------- | ---------- | ------------- | ----------- | --------- | ------- |
| pen      | 1    | 0.3      | 0.5       | 0.4        | linear        | none        | none      | 1       |
| fountain | 1.1  | 0.5      | 0.6       | 0.45       | easeInOutQuad | 0.5 nib     | 2.5 nibs  | 1       |
| pencil   | 0.85 | 0.15     | 0.4       | 0.25       | linear        | 0.5 nib     | 0.75 nib  | 0.75    |
| marker   | 2    | 0        | 0.5       | 0.5        | linear        | none        | none      | 0.85    |
| brush    | 2    | 0.8      | 0.65      | 0.55       | easeOutSine   | 1 nib       | 3 nibs    | 1       |

The pen is a ballpoint, round at both ends: a taper in perfect-freehand
always runs down to a point, and on handwriting that is a brush's tail on
every letter.

One stroke, step for step (`InkTool.outline` here). The short-stroke rules
decide whether the dot over an i is drawn at all, so copy them exactly.
`n` is the nib in points (`nib × width`); every length is in the samples'
own screen points; `3` is perfect-freehand's END_NOISE_THRESHOLD.

1. `pts = getStrokePoints(samples, options)` with the tool's options and
   no tapers (tapers do not change it), and `length =
   pts.at(-1).runningLength` — perfect-freehand's own total length, the
   one its outline goes by. NOT the polyline through the raw samples:
   streamlining pulls the line in, and samples skipped at its start still
   count towards it, so the two differ on exactly the short strokes these
   rules are about.
2. A TAP IS A DOT. If every sample is within `n ÷ 2` of the first, or
   `length < 3`, draw `getStroke([s, s], options)` where `s` is the FIRST
   sample's point carrying the HARDEST pressure of the stroke (ignoring
   negative and NaN; none if there is none). perfect-freehand keeps only
   the final sample of a line's last 3 points, so a shorter stroke is all
   end — tapered at both ends its outline is 3 points, which is no path at
   all. Two identical samples are perfect-freehand's own round dot; one
   sample alone it turns into a little diagonal dash. A tap is then the
   same dot however many events it made.
3. Tapers: `body = length − 3 − size`, `share = min(1, max(0, body) ÷ 3 ÷
   ((startTaper + endTaper) × n))`, `start = startTaper × n × share`,
   `end = endTaper × n × share`; an end whose taper is under `n ÷ 4`
   gets none (`taper: false`). Caps are always `true`.
4. If BOTH ends are tapered and no point of `pts` other than the first
   and the last has `runningLength ≥ start` and `length − runningLength ≥
   max(end, 3)`, taper neither: both ramps run down to nothing, and with
   no full-width point between them the line is a sliver.
5. `getStrokeOutlinePoints(pts, options)` with those tapers.

Opacity goes on the colour of the one filled outline, so a stroke never
darkens where it crosses itself.

The stored stroke gained two optional fields: `pressures`, an array of
0…1 PARALLEL to `points` (one per point, always the same length — anything
that rewrites a stroke's points rewrites its pressures in step), and
`tool` — `"pen"`, `"fountain"`, `"pencil"`, `"marker"` or `"brush"`. Both
are absent on old strokes and on mouse strokes, and a stroke with neither
is the old line. Read an unknown tool as `"pen"` and a pressures value you
cannot read as absent: never fail a whole drawing over either.
(Sean, 2026-10-02.)

### An evaluation cell is not a code cell
Two different things that look alike: code you are writing ABOUT, and code
the document RUNS. Put the difference in the file — `eval python` against
`python` — so another editor, and a reader, can see it too, and so a code
block can never run by being looked at the right way. One key makes an
evaluation cell or converts the cell you are in (keeping its code); a
different key runs it. On macOS that run key is ⇧↩, and it arrives as an
ordinary newline: the system binds the line-break selector to ⌃↩ and says
nothing about ⇧↩, so read the shift off the event being handled. Do not
make it a menu shortcut — a menu key equivalent takes that chord away from
every text view in the app. Colour the body for its language anyway: the
distinction is about what the cell DOES, not what it looks like.

### Cells that run, and everything that must refuse to
An evaluation cell runs on a key and on nothing else. At its left is ONE
control, a badge saying which environment it is that changes the fence when
you pick another — and it never goes away, not while the cell is open for
typing, which is the moment you are most likely to want to know. There is no
run button beside it: a button for a thing the keyboard already does is one
control too many, and the badge is then the only thing in that margin, which
is what makes it readable at a glance down a page of cells. The answer is written into the document as another fenced
block tagged `out`, directly under the cell; running again replaces that
block and nothing else. Found by POSITION, vetoed by the TAG — the block
below, and only if it is tagged — so a re-run can never overwrite something
a person wrote there. Inside it, a line in square brackets is the app
talking and every other line came out of the process; a run that printed
nothing still writes `[no output]`, so a run always looks like one. Escape
any output line that would close the fence, or the rest of the document
re-parses as code.

The refusals matter more than the feature. Only a press starts a child —
never on open, on save, on reload or from a view's body — and that is
worth a test that reads the sources, not a comment. Keep process spawning
to ONE file and fail the build on a second. Put the test-environment guard
at the spawn, not at the menu: a test host may BE the app. The child never
writes the document; the answer comes back in memory and goes in through
whatever path registers undo. Shell cells are refused permanently: the text
of a fence is not evidence the owner typed it. And a tool that is missing,
or installed but not licensed, gets a sentence someone can act on — resolve
tools from a candidate list of absolute paths, because a GUI app inherits
the launcher's PATH and will not find anything in /opt or /usr/local.
(Sean, 2026-09-21.)

### The viewfinder has a shape, and it is one number
An aspect-ratio control on the camera: Free plus the usual ratios in both
orientations, on the same dropdown that picks the input, since it is the
same question — what am I pointing this at. Implement it as the SHAPE OF
THE VIEWFINDER, not a crop of the camera's frame and not a device setting:
lay the whole camera view out in the largest rectangle of that shape the
pane holds, and let everything already measured in pane points — the
selection box, the zoom, what a capture brings in — be measured against
that rectangle instead. Nothing else has to learn about it. Offer both
orientations as separate entries rather than a ratio plus a flip: a page is
photographed upright and a whiteboard sideways, and which you want is not a
modifier of the other. A pane too small to hold anything hands back what it
was given — every coordinate downstream divides by those numbers. Remember
the choice: the shape you photograph pages in belongs to your notebook, not
to this launch. (Sean, 2026-09-21.)

### Double-click the viewfinder to make the window the viewfinder
And double-click again, or press a faint × drawn over its top-left corner,
to come back. Two ways out, because a window that is nothing but a picture
has to say how to leave it, and one of them has to be visible. Do NOT
remember the state across a launch: coming up as nothing but a viewfinder
is a window whose documents have vanished, and an answer drawn on the
picture is not good enough for the first second of a launch. Filling the
window also has to turn the pane back on if it had been put away, or it is
a black rectangle with no way out. Watch what the double-click displaces:
here it took "box the whole picture", which moved onto the single click
that until then did nothing when there was no box. (Sean, 2026-09-21.)

### The README's key table is generated-checked, not hand-kept
List every shortcut in the README, and have a test read that table back and
hold it against the binding table: every chord bound must appear, and the
table must name no chord nothing binds. A shortcut that moves then fails the
build until the document says so too. Cheap, and the alternative is a page
that is wrong within a month. (Sean, 2026-09-21: "document the keystrokes in
the readme.")

### A checklist is edited one item at a time, boxes intact
Clicking a reminder opens THAT reminder's words — not the whole list as one
text field. The boxes stay live controls the whole time, including while the
line beside one is being typed in. Four things make it work:
- **Draw the editor OVER the label, do not swap it for one.** The rendered
  text keeps the row's height and baseline, so opening an item moves neither
  the box beside it nor anything below it. A swap grows the line by a few
  points and every later row, rule and floating object slides.
- **One cursor, not two flags.** A single `none | cell | item` value with the
  old "which cell is open" as a computed window onto it: every existing place
  that closed a cell now closes an open item too, with no change at all.
- **Key the open item by the RANGE OF ITS WORDS, not by an index.** An index
  goes stale the moment a line is added above it, and the view is rebuilt
  from the document on every keystroke.
- **One walk over the lines.** The tick and the editor must agree about which
  reminder is the third one; counting a line's indent in characters in one
  place and in UTF-16 units in another is how they stop agreeing.
Also: a tick must replace exactly one character with one, or ticking a box
moves the caret of the item being typed in; restore the caret after a tick
anyway, because pressing the box takes the keyboard. Return splits the item
and starts the next unticked; backspace in an empty item removes it; backspace
at the start of a full one joins it to the item above; a paste with newlines
in it is flattened, or the block re-parses under the caret. (Sean, 2026-09-21.)

### One list of every key, and a test that they differ
Bind every shortcut through a single enumerated table and walk all of its
cases in a test that fails on a duplicate. Here ⌃⌘S was on two commands at
once — "Hide Notes Sidebar" and "Save Project" — and a key equivalent claimed
twice goes to whichever menu comes first in the bar, so one of the two simply
could not be pressed and nothing said so. The rule that keeps the table
honest is that binding a key any other way is itself a test failure. The keys
themselves: ⌘S save, ⌘P draw, ⌘E export, ⌘T source/rendered, ⌘Y the second
pane. (Sean, 2026-09-21: "cmd s for save, cmd p for toggling draw mode, cmd e
for export, cmd r for toggling markdown, cmd t for toggling the video pane..
unless there's conflicts with those?")

### The rendered pane says "you can type here"
Hovering the words of a rendered block gives a text I-beam; hovering the space
between two cells gives the same I-beam ON ITS SIDE, with a faint line drawn;
clicking there makes the line solid — that is the cursor now — with the
"new cell" affordance at its left end. A rendered block is usually a label
with no cursor of its own, so without this the pointer over a whole editable
page is an arrow, which says the opposite of the truth. One reader for "where
is the pointer" covering BOTH the cells and the seams: the place the pointer
arrives at is often told before the place it left, so leaving a cell took back
the cursor the seam had just set. Set the cursor on every move rather than
pushing it, and hand it back on the way out, and set nothing at all while a
drawing tool owns the pane. (Sean, 2026-09-21.)

### Two keys held while a mark or an arrow is placed
- **⌘ keeps the tool.** Placing a mark hands the tool back and sends the
  pointer to the palette for the next one; holding ⌘ as it goes down leaves
  it armed, so a row of ticks is one trip. (SUPERSEDED 2026-10-02: every
  armed tool stays with no key held — the entry at the top — and there is
  no modifier to read.) Escape is the way out. Hide the selection handles while a tool is armed — they are
  views over the canvas and the one round the mark just placed swallows the
  click that would have placed the next.
- **⇧ holds a line to an axis.** Only for what HAS a direction (lines and
  arrows; a mark is square already, and a node is dragged to whatever box it
  is wanted in). Keep the distance along the axis and throw the other
  component away, rather than keeping the length and rounding the angle: the
  end has to stay under the pointer along the direction that is left. The
  ghost shown during the drag must be the line that will really be put down.
- **Nothing put down leaves the tool armed** either way: a press that never
  moved is no line at all, and disarming there sends the pointer back to the
  palette for a gesture that produced nothing.
(Sean, 2026-09-21.)

### A command at the insertion bar makes the cell there
While the horizontal insertion bar between two cells is the cursor, pressing
anything on the toolbar or in the Format menu must CREATE a cell at the bar,
ready for that input — not quietly record a preference and wait for a
keystroke, and never act on whatever cell the caret happens to be parked
against (that is the cell BELOW the bar, or the document's first cell when
there is no text view at all). Three sorts of command, and they differ:
- one that names a KIND of cell (a heading, a list, a quote, a fenced block)
  opens the cell with that marker in it and the caret where the words go, and
  is then finished;
- one that writes something else (bold, a text style, maths) opens a PLAIN
  cell and runs in it;
- one that acts ON a cell (delete, duplicate, move, split, merge) still does
  nothing: an empty cell made to be deleted is churn in the document and a
  step on the undo stack for a gesture that did nothing.
A "+" affordance on the bar itself is the exception and may go on meaning
"the next thing typed here becomes this" — a menu choice is not a button
press. (Sean, 2026-09-21.)

### A list edits its words and nothing else
In the WYSIWYG pane, opening a bullet list or a list of reminders shows the
BULLETS AND THE BOXES, not `- ` and `[ ]`. Three different answers, and they
are not the same:
- the caret may not enter the head of the line — the indent, the marker, the
  box. Hidden characters the caret can still be put among are worse than
  visible ones. A click on the left edge, Home and ⌘← all land on the first
  character that can be seen, and past ALL of the furniture, not past the
  first piece of it;
- a bullet's `- ` is DRAWN (as a round bullet) and reserved; hiding it would
  leave a list with no marker, which is not a list;
- a reminder's `- [x] ` is one piece: the marker and the brackets are drawn
  as nothing and the `[` is drawn as a box, ticked or not — so the cell being
  edited reads exactly like the cell that was clicked.
Backspace does the ordinary thing first (a level of indent, then the bullet)
and only then takes a whole piece of furniture. Watch the font: a glyph a
font does not have is drawn as NOTHING, so check before substituting and
leave the characters showing if it is missing. (Sean, 2026-09-21: "only edit
the text in a reminders list or bullet list and have normal bullet editing
behavior.")

### A heading shows no hashes on the rendered page
In the WYSIWYG pane, clicking a heading to edit its words must NOT reveal its
`## `. The source pane is right to show the markers on the caret's own line —
there they ARE the text being typed — but the rendered page is not the source,
and the marker appearing shoves the words sideways as you click them. Call
such a marker FURNITURE: hidden whatever the caret does, and somewhere the
caret cannot go (a click on the left edge, Home and ⌘← all land on the first
character that can be seen). A backspace standing just behind furniture takes
the WHOLE piece, so the cell stops being a heading — otherwise the key eats
one space, the line silently stops being a heading, and nothing on screen says
so. The heading is changed with the ladder instead. (Sean, 2026-09-21: "when
in wysiwyg mode, don't show the markdown characters for header.")

### The session is not the only way into the user's notes
A run of the app that has been pointed at a scratch notes folder — a smoke
check, a test host — must have its SESSION redirected too. A session names its
folders and its open notes by absolute path and restores unsaved buffers by
writing them over whatever is on disk, so restoring one puts a "safe" run back
in the real notes folder. Two redirections, not one. (2026-09-21, after a
scratch run was watched opening the real notes.)

### The two icons on an add row are one height
Where a row offers "new note" and "new section" side by side, the two icons
are drawn to ONE height constant and measured, not eyeballed. A platform icon
whose art includes a badge is as tall as art-plus-badge, so the shape inside
it comes out short — here `folder.badge.plus` drew an 11.9 pt folder beside a
13 pt page. Use the plain folder and put the + inside it. (2026-09-21.)

### An answer leaves the cursor under it
Evaluating a cell ends with the insertion bar on the seam BELOW the output,
not back in the code — a notebook's ⇧↩ is "run this and let me carry on", and
carrying on happens after the answer. This is the one write an evaluation
makes that DOES take the caret: every other one (the output cell itself)
goes in without stealing focus, because it may land while somebody is typing
somewhere else, and the two must not be confused. Where the bar goes is the
start of the block after the output, which is the offset both panes already
read as "the seam under this one"; the end of the document when there is
nothing after it. (Sean, 2026-09-21: "after evaluating a cell, the text
cursor should become a horizontal bar after the output.")

### An evaluation cell and its answer are one group
The gutter draws one bracket round the In/Out pair, and each of the two
cells keeps its own bracket one step further in. It is NOT a section: it
folds nothing, it nests nothing in the document, and it is not written into
the file — it is read back off the blocks every time, an evaluation fence
with an `out` fence directly under it. That keeps it true with no state to
get stale: delete the answer and the group is gone; run the cell and it is
back. (Sean, 2026-09-21: "input and output cells are grouped together.")

### An out cell is an answer, whatever ran
The pair is a fenced cell with an `out` cell under it, and the fence above it
is NOT asked what it says. Nothing but a run ever writes an `out` fence, so a
cell with one under it has been run — whatever that version of the app would
make of its language today. Asking a second question ("is this an evaluation
cell?") split one model in two: the re-run replaced that block, calling it the
cell's answer, while the gutter refused to bracket the two together, and every
pair written before the `eval ` fence existed stopped looking like a pair. And
the blank cells in the gap are stepped over: three empty lines are a block of
the note's own, and pressing Return twice under a cell must not hide its
answer from it. (Sean, 2026-09-22: "input and output cells still don't appear
to be grouped.")

### A bracket in the gutter is one of three things
A section folds, a cell is a block of the note, and a group embraces an In/Out
pair. Every gesture in the column — the drag that takes cells, what a
shift-click reaches between, what counts as already picked, the spans an
insertion bar is dragged across — needs "is this a cell", and `not foldable`
is not that question once a third kind exists: the pair's own bracket joined
the list a drag walks down, anchored on the merged range and shadowed the two
cells inside it. Give the bracket the kind and ask ONE reader for it.

And a group has to LOOK like one: its top and bottom are exactly its members',
so drawn at the same length it reads as a second hairline five points over,
not as something round them. It stands a few points proud at each end. Nesting
also runs out of column — levels are a few points apart in a fixed strip — so
the drawn depth is clamped, and anything deeper shares the last line rather
than being drawn off the edge and not drawn at all.

### A cursor written into the page has to be scrolled to
A bar armed by a gesture is under the pointer; a bar armed because a cell
finished running is wherever the answer ended, and an answer is written whole
— a screenful of it is ordinary. So the pane that arms it scrolls to it, the
same as the one that has always done so. Two things make that harder than it
sounds, both measured (2026-09-22): the row it wants DOES NOT EXIST at the
moment the answer is written, so a scroll asked for there silently does
nothing and it has to wait for the page to be rebuilt AND laid out; and a row
taller than the window cannot be scrolled to its BOTTOM — that clamps to
keeping its top in view, which is to say it does not move at all. Scroll to
the SEAM, centred, and give the seams their own ids to be scrolled to.

### The caret goes in the seam, not in the cell below it
Where the bar is armed and where the caret is parked are two different
offsets: the bar is the next cell's start, the caret is the blank line above
it. Putting both at the cell's start armed the right bar and left every other
reader of "the caret is in that cell" answering for the wrong one — the
markers a heading hides came back the moment a cell finished running, because
that reader is asked on the way past, before the arm is set.

### Two identical cells, and the answer belongs to one of them
A cell is found again by its own text when the answer comes back, because a
run takes time and the note is editable throughout it. But one keystroke
duplicates a cell, and first-wins then puts the answer under the copy ABOVE
the one that ran — with its bracket and its cursor. Keep where the run started
and take the nearest match. And refuse a cell whose closing fence has not been
typed yet: such a block parses to the end of the note, so the answer is pasted
past the end and its own opening line closes the cell it was meant to sit
under.

### A hover in the gutter promises what a click would take
The bracket under the pointer lights, and the cells it would select are washed
faintly at the same time (Sean, 2026-09-22: "hovering over sections on the
right side should faintly indicate what would be selected if clicked"). The
point of it is the brackets that stand for something other than themselves — a
section stands for the cells under it, an In/Out pair for the two in it — where
the bracket alone says how FAR the selection reaches but not what it takes.
Ask the same function the press asks, so the promise and the press cannot
disagree; paint it over the words rather than in the column, because the
column is twenty-odd points wide and the answer is the width of the page; and
draw it UNDER the insertion bar, which is a cursor and has to keep reading as
one.

### A section's heading is one of the cells it takes
It is not a container in the file — a section is a heading and the blocks
after it — so the wash covers the heading too, and so does the selection. That
falls out of asking one function; it is worth knowing before someone "fixes"
the heading out of the list.

### The badge stays while the cell is being typed in
A cell open for editing is a different view from the cell rendered, so
anything drawn beside the rendered one disappears the moment it is clicked
into — and what a cell RUNS AS is exactly what you want on screen while you
are writing it. Build that badge once, outside both, and let the block and
the open editor put the same one in the same place. (Sean, 2026-09-22: "the
indicator for WL/Python/C++ never goes away, and get rid of the play
button.")

### The key that makes a kind of cell works at the bar too
Every command that NAMES a kind of cell has to make that cell where the
insertion bar is, not act on whatever cell the caret happens to be parked
against — the bar is in no cell, and the caret at one is against the cell
BELOW it. The heading ladder, the lists, the quote and the fenced block all
went through that rule; the evaluation key did not, because it asked for "the
caret's cell" directly, so pressing it at a bar turned the NEXT cell into an
evaluation cell instead of making one. An evaluation cell is a fenced block
with `eval ` on its info string and nothing else, so it joins that list as one
more kind rather than as a second block builder. (Sean, 2026-09-22: "make sure
if the input cursor is horizontal, hitting cmd+9 puts a new evaluation cell at
that position etc".)

### The rendered page's rhythm is the source pane's, and it is one constant
A WYSIWYG page stacks its blocks some fixed distance apart; the source pane
puts a BLANK LINE OF THE NOTE between two cells. Those are different numbers,
and if the page's is the smaller one the whole note reads as scrunched next to
the same note in the other mode. Derive it: a blank line plus the line spacing
that goes round it, so the two cannot drift.

The trap is that the same constant was doing two jobs — the air between two
cells AND the FLOOR under a seam ("enough to put the pointer in"). Raising the
one number moved the floor, the source pane's own paragraph spacing and the
landing place of every pasted picture with it, which is why the two panes had
never been squared up. Two constants.

And then the page has to be uniform, which means no block carrying air of its
own: the line spacing belongs on every kind of block and not on paragraphs
alone (a bullet or a quote that wraps was four points a line tighter than the
paragraph beside it); a rule's clickable body is its own HEIGHT, not padding
that leaks into the gaps either side; a cell of blank lines is as tall as
those lines really are; and a cell opened for typing keeps the height it had
rendered, or clicking into a code cell drops everything below it twenty points
and lifts it back when you click out. (Sean, 2026-09-22: "make the spacing
more uniform.. it's ok on markdown mode but in rendered mode things get
scrunched together".)

### The two panes answer for the same places with the same pointer
A rendered page and a source pane are built out of completely different
machinery, so every region of the window has to be gone through one at a time
and given ONE owner and ONE answer. Three that were wrong here, all of the
same shape: a region nobody answered for, or two mechanisms answering for one.

The page's side margins belonged to nothing. The inset was applied from
OUTSIDE the row, so the hover and the click were sized to the text column and
the strips down the sides did neither — sliding sideways off the words flipped
the pointer to an arrow an inch before the pane edge, where the source pane,
whose margin is its text container's own inset, stays a text cursor out to the
edge. Apply the inset INSIDE the row: the words do not move and the margin
belongs to the cell it is beside, pointer and click alike. That covers the
open editor too, which had no cursor of its own outside its text view at all.

The bracket column had two owners. The source pane's text view laid a
full-width I-beam rect straight under the column, so the hand appeared while
the pointer moved and the I-beam whenever it stopped, scrolled, or the note
reflowed and the rects were rebuilt. Cursor rects are torn down and rebuilt; a
tracking area is not. Stop at the column's edge in the text view (rects AND the
cursorUpdate/mouseMoved/mouseEntered paths, which must not fall through to the
superclass there), and give the column's own view a `.cursorUpdate` tracking
area with one reader for "hand over a bracket, arrow beside one".

And a control inside a cell keeps the cell's cursor unless it says otherwise:
a checklist's box and an evaluation cell's badge are buttons and take the
pointing hand, the way the + on the insertion bar already does. (Sean,
2026-09-22: "the mouse cursor behavior should be the same in wysiwyg and
markdown mode".)

### A page that does not move when it does not have to
Carrying the view to a cursor that was armed from outside it — the bar under
an answer a run has just written — is only kind when the cursor is somewhere
the reader cannot see. The answer to `2 + 2` is one line; jerking the note
under somebody who is already looking at the right place is the opposite of
what the scroll is for. Ask first, with a margin off each edge, because a bar
a point inside the fold is on screen by arithmetic and not by eye. A native
text view has this for nothing — scroll-range-to-visible moves by the least it
can, and not at all when the range is already up — so it only has to be said
out loud on the side that stacks its own views.

And when it does move: carried, not jumped. A short animation, landing the
seam low on the page rather than centred, because what you have just made is
above it and worth seeing. (Sean, 2026-09-22: "make the cursor behavior after
evaluating a cell elegant".)

### A code cell is a box round its code
The padding inside a rendered fenced block should be about the size of the
text it holds, so the box comes out a little bigger than the code and not much
more. A whole line of air each side — which is what the other pane spends on
the two fence lines it actually shows — makes a one-line cell three and a half
lines tall, and a page of short cells reads as a column of empty boxes.

The reason it was a whole line is worth knowing before it is put back: it made
a code cell EXACTLY as tall in both modes. That contract is not needed —
switching modes comes back to the same cell and how far into it, and drawings
go through the cells both views share (see "⌘T keeps everything where it
was") — so all that is given up is that a long note of code is a different
total height in the two panes. (Sean, 2026-09-22: "there shouldn't
be so much padding in the cells themselves, it should be about the size of the
text a little bigger".)

### In[n] and Out[n] down the left, and the pair lines up
A notebook writes the pair's number in the margin beside both halves. Do the
same, in ONE column, because the thing that makes a pair read as one thing is
that the two boxes start at the same x — the answer had no mark at all, so its
box began a badge's width to the left of the code's and the eye caught that
before anything else.

The mark changes with the cell's state and so does its KIND. A cell that has
not run has something to decide, so its mark is the environment menu drawn as
a button; a cell that has run has a number instead, so its mark is a plain
label, and so is its answer's. The margin is then a record of what ran rather
than a row of controls. Nothing is lost when the menu goes: the fence still
says what the cell runs as, in the file and in the other pane.

The number is READ OFF THE NOTE — the nth answered pair, counted from the top
— and not kept from the run. A notebook numbers In[] at evaluation time and
holds it for the session; a note is a file that gets opened again tomorrow,
and the only place a number could be kept is the fence, which is not ours to
scribble in. Inserting a pair above another renumbers the one below, which is
what anybody reading the file top to bottom would call them anyway.

One platform trap: a SwiftUI `Menu` cannot be made to look like an ordinary
button. Under the borderless style it draws its own disclosure arrow, on the
LEFT, and throws the label's background and border away. A plain button that
pops a real menu at the pointer is the way to a control that looks like the
one you drew. (Sean, 2026-09-22: "show in and out to the left of input and
output cells similar to mathematica.. this dropdown icon should look like a
button and be positioned well".)

### A compiled cell and an interpreted one are two shapes, not five cases
Adding an environment should be adding a row to the model and nothing else.
What varies between them is small and belongs to the model: the fence tag, the
badge, the colouring, where the tool might be, whether it COMPILES, what its
source file is called (the extension is what tells a compiler what it is
reading) and what the compiler is handed. The runner then has two shapes — one
child, or a build and then a run — and no list of languages in it at all.

Two things that bite when the list grows. A tool installed by a language's own
installer is in the HOME directory and nowhere a list of system paths would
look: rustup puts rustc in ~/.cargo/bin, so the candidate list has to be able
to name it. And any sentence that says "that is not one of X, Y or Z" must be
GENERATED from the list, or it goes stale the first time the list changes and
tells the reader something false. (Sean, 2026-09-22: "add C and Rust evals".)

### A capture lands the size the viewfinder showed it
A photograph of a notebook page, and the writing traced off one, should come
onto the page at the size you were just looking at in the camera pane — not a
thumbnail of it. The old fraction was set when a picture still pushed the text
about and a big one covered the note; once captures float free of the text
(nothing on the drawing layer moves the text), there is no reason left to
shrink a page you have just taken a photograph of.

Keep it ONE number for every capture. Matching the viewfinder exactly — the
page's real share of the video frame — would make every capture a different
size depending on how far away the camera was, which is the thing the
remembered page shape exists to prevent: two photographs of the same notebook
have to come out the same size on the page. (Sean, 2026-09-22: "the drawing
and image when selected from the camera are too small.. they should be the
size you can see in the output viewer".)

### Traced writing is NOT thinned
For one day the trace was eroded to a fraction of its measured stroke width and
cleaned twice; that is rolled back (Sean, 2026-10-02: "the text isn't coming
through crisp and backgrounds aren't being ignored etc.. it was working better
before"). Erosion roughened every edge and turned grid dots into specks the
lattice search no longer caught. If the port picked either entry up, take it
out: threshold, clean once, trace.

### Esc puts the pen down
With the pen up, Esc goes back to the cursor (Sean, 2026-10-02: "esc should
exit pen mode"). It is asked after the nearer things Esc already calls off — a
label being typed, a connector's style bar, an armed shape, a crop — and it is
taken only when the pen was up, so Esc in cursor mode is still the text's.

### A point on the drawing layer is held only at the document's top
Points are pane fractions measured from the DOCUMENT's top, so anything drawn
further down a long note than one screen has y > 1. Clamp x to the pane's
width and y at 0 only — a clamp to 0…1 flattens every stroke drawn below the
first screen onto that screen's bottom edge (fixed here 2026-10-02).

## Done there

Nothing yet.
