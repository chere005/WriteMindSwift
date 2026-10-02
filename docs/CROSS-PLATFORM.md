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
  it armed, so a row of ticks is one trip. Read the modifier when the thing
  goes DOWN, not when it was picked, so the choice is made per mark. Escape
  is the way out. Hide the selection handles while a tool is armed — they are
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
switching modes comes back to the same CELL by its id and never by a
measurement — so all that is given up is that a long note of code is a
different total height in the two panes. (Sean, 2026-09-22: "there shouldn't
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

## Done there

Nothing yet.
