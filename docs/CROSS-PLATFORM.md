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
  at 0, 0); the tip and the switches count only when ready. The lower
  switch is the selection switch; the upper one does nothing. WebHID
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
  the turned shape, the edge that is its top as it ships drawn heavy, on
  the side the mapping puts that edge — opening the four by name, the
  one in use ticked. Under them one line says what a turn does to what
  the pen is writing on (the page's writing turns with it; a note's
  stays where it was written) and that the heavy edge is the tablet's
  top. It holds for both modes, so it is never hidden in Notebook mode.
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
- **The barrel button is the drawing's marquee**: dragged, it draws the
  same rectangle a ⌘-drag draws; let go, it picks everything it touches,
  whole groups, Shift to add — the ⌘-drag's one rule — so Delete and the
  handles act on it. A barrel click is a ⌘-click.
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
  ink starts no box until it is let go.
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
- **The box is the camera's box**, its three buttons and all. The barrel
  button held and dragged draws it, so does a mouse or trackpad drag; a
  click, the nib going down, or Esc (only while there is a box, and
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
  the nib, `buttons & 2` the barrel button (a selection, not ink),
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

### A point on the drawing layer is held only at the document's top
Points are pane fractions measured from the DOCUMENT's top, so anything drawn
further down a long note than one screen has y > 1. Clamp x to the pane's
width and y at 0 only — a clamp to 0…1 flattens every stroke drawn below the
first screen onto that screen's bottom edge (fixed here 2026-10-02).

## Done there

Nothing yet.
