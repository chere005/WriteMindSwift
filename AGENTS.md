# Working in WriteMind

The baseline for all of Sean's repos lives in ~/GIT/AgentSuite/AGENTS.md
and is imported here; this file holds only what is true of THIS repo.
@../AgentSuite/AGENTS.md

A macOS-only writing app: a markdown editor on the left, a live camera on the
right, a sidebar of notes that are plain `.md` files in `~/Documents/WriteMind`.
Native SwiftUI + AppKit, one Xcode project, no web layer, no server, no package
manager, no dependencies. The README is deliberately short: the tour is
`docs/FEATURES.md`, building and shipping is `docs/BUILDING.md`, the open
list is `docs/TODO.md`, what the cross-platform port has still to pick up
from here is `docs/CROSS-PLATFORM.md` (Sean, 2026-09-21: "keep a log of
things we're working on for the cross platform app to eventually
implement" — one entry per noticeable change, in the same commit as the
change), and THIS file is how the code is put together.

- [Standing rules](#standing-rules) — the things that cost real time when
  they are broken: whose data the notes are, what a section is, how the app
  is signed, and the one that catches everybody, **deploy after every small
  change**.
- [How it is wired](#how-it-is-wired) — a file-by-file map of the app, the
  shortcuts, and the rules each part follows.
- [Traps that have cost real time here](#traps-that-have-cost-real-time-here)
  — read this before debugging anything that looks impossible.

Two words on the shape of the thing. The NOTE is a markdown file and nothing
else; everything that is not markdown — pen strokes, pictures, flow-chart
nodes, text boxes — lives in a hidden sidecar beside it and is drawn on a
layer over the text. The camera pane is a viewfinder: it finds a notebook
page, squares it up, and hands the result to the same drawing layer. Nothing
here is a database, and nothing rewrites a file the user did not type in.

Started 2026-09-18 on Sean's word, from the AgentSuite baseline. It is not a
Mind-suite clone: it shares no canon bytes with CalMind's lineage and never
will (there is no TypeScript here to share). It IS in the suite's release
machinery — CoreMind's `bin/dtp.sh` and `bin/deploy.sh` know it as an
independent target, and its lane reports to seancheren.com/status through
CoreMind's `bin/report-status.sh`.

## Standing rules

- **`~/Documents/WriteMind` is Sean's data.** The files there are his notes,
  readable by anything that opens markdown. The app writes ONLY the note that
  is open, only after he typed in it (a 500 ms debounce), and only through
  `NoteStore.saveNow()`. Nothing rewrites, renames or reorders a file on its
  own; a rename or a trash is a gesture in the sidebar. Tests never touch that
  folder — `DrawingStoreTests` makes its own temp directory, and the parser
  and formatting tests are pure.
- **THE SMOKE RUNS AGAINST A SCRATCH FOLDER, AND A SAVE NEVER CLOBBERS.**
  On 2026-09-20 a deploy took two cells out of Sean's note. `tools/smoke.sh`
  launches the built bundle to see that it stays up and then `kill`s it —
  and that copy had opened his real session, his real note, and answered
  the SIGTERM by flushing a save of whatever it was holding. The baseline
  rule covers it in one line: a check that can reach the real thing is not
  a check. Two locks, and keep both. The smoke sets
  `WRITEMIND_SCRATCH_NOTES`, which `TestHost.isActive` reads exactly as it
  reads XCTest's variables, so that run keeps its notes in a temp folder
  and leaves the camera alone — it is read from the ENVIRONMENT and
  nowhere else, so an app Sean launches can never fall into it. And
  `NoteStore.saveNow` asks `NoteWriting.mayWrite` first: the app owns the
  file only while the bytes on disk are the bytes it last read or wrote,
  and anything else means another writer — a second instance, a script,
  another editor — whose work is not ours to throw away. It keeps the
  buffer, says so in the footer, and lets the folder watcher bring the
  newer file in.
- **A SECTION IS A FOLDER.** The sidebar tree is the folder tree under the
  notes directory — `Ideas/` is a section, `Ideas/2026/` a subsection — so a
  note moved in WriteMind is moved in Finder and vice versa. Nothing is
  invented and nothing is a database. The section selected in the sidebar is
  where a new note goes (`NoteStore.targetSection`, falling back to the open
  note's own folder, then the root). Dragging a row MOVES THE FILE; trashing
  a section trashes its notes, the same as Finder, and recoverable the same
  way.
- **The row order is the one thing the filesystem cannot hold.** Markdown
  files have no order and a listing is alphabetical, so a dragged row's place
  lives in `.writemind/order.json` — a list of names per folder, relative to
  the root. Anything not named there sorts after what is, newest first, so a
  note made outside WriteMind still appears. Every operation that adds,
  renames, moves or trashes a row keeps that file honest; a stale name in it
  is harmless, an ABSENT one is what makes a new note appear at the bottom.
- **A folder can be out of the project and still on disk.** "Remove Folder
  from Project" on a section puts its path in `Project.excluded` (and the
  session's, for a project with no file); `NoteTree.read(excluding:)` skips
  it and the footer's Folder ▸ Hidden Folders brings it back. It exists
  because Move to Trash on a folder really moves it (Sean, 2026-09-18, after
  it took his notes with it). Every hand-off of `projects.folders` to
  `store.setFolders` passes `excluding: projects.excluded` too.
- **The drawing is a sidecar, not a note edit.** Pen strokes live in
  `~/Documents/WriteMind/.drawings/<note>.json` (hidden, one file per note,
  removed when the drawing is cleared) so the notes folder stays a folder of
  markdown. `DrawingStore` follows a rename and a trash; a note file with no
  sidecar is the normal case.
- **INK IS PERFECT-FREEHAND, AND A STROKE WITH NO TOOL IS THE LINE IT
  ALWAYS WAS.** Sean, 2026-10-02: "make the text strokes well implemented
  to feel natural for writing letters.. do the same for drawing mode in
  the notebook itself". `InkOutline` is a line-for-line Swift port of
  perfect-freehand 1.2.3 (Steve Ruiz, MIT — the notice and the version are
  in its header): samples with a pressure each go in, the OUTLINE of a
  stroke whose width follows the pressure comes out, and `InkOutline.path`
  runs it through its midpoints to be filled nonzero. It is a port, not a
  reimagining — the cross-platform app will run the TypeScript original,
  and one stroke has to come out one shape on both — so `InkOutlineTests`
  pins it against numbers the original printed under node: upstream's own
  snapshot point for point, its fixtures, and option sets that reach real
  pressure, tapers, flat caps and hairpin corners. Its cap loops
  ACCUMULATE `t += step` as the JavaScript does; a `stride` multiplies,
  disagrees in the last bit, and changes how many points a cap gets.
  `InkTool` is the table of pens — pen, fountain pen, pencil, marker,
  brush — each an option set and an opacity, calibrated so that at the
  MIDDLE pressure the line is `nib × width` whatever the easing (the size
  is divided by `2 × easing(0.5)`): the slider still means what it says,
  and the pen's nib is 1. No easing in the table is below the middle at
  the middle, because perfect-freehand reads `size` as a LENGTH too — the
  samples it skips at a line's start, the spacing of the outline's points
  — and the fountain pen's first easing made its size two nibs: a
  straight chord for the entry of every e, and facets on its loops. **The
  pen has no taper and both its ends are round**, a ballpoint's: a taper
  here always runs down to a point, and the first cut put one on both
  ends of every letter; pressure alone thins a nib touching down or
  lifting off (0.7 of the width).
  **A TAP IS A DOT AND EVERY STROKE PAINTS** — `InkTool.outline` is the
  one way in, for both painters. perfect-freehand keeps only the final
  sample of a line's last three points (its end noise), so a stroke it
  measures shorter than that is all end: tapered at both ends it came out
  three points, which is NO path — a wobbly tap or a flick at a thin pen
  was saved, selectable and invisible. Such a stroke, and one whose every
  sample stays within half a nib of the first, is a tap: ONE sample at
  the touch-down with the tap's hardest pressure, handed over twice,
  which perfect-freehand draws as its own round dot (a lone sample on its
  own it turns into a short diagonal dash). So a tap is the same dot
  however many events it made, and does not wander or shrink while the
  nib is held. Every length in these rules is the outline's own — the
  last streamlined `runningLength` — never the raw polyline. The tapers
  shrink with a short stroke so the two never take more than a third of
  the stretch the outline keeps points along, an end whose taper would be
  under a quarter of a nib has none, and a line tapered at both ends with
  no full-width point between the ramps has neither — a taper is a ramp
  from nothing, and two of them with nothing between are a sliver.
  `InkToolTests` sweeps every tool over short strokes and measures the
  ink actually laid down.
  `Stroke` gained `pressures` and `tool`, both `decodeIfPresent`, and both
  forgiving: a tool this build does not know reads as the pen, a pressures
  array it cannot read as none, because `DrawingStore.load` empties a
  drawing that fails to decode. **THE LOCKSTEP RULE: `pressures` is
  PARALLEL to `points`, and whatever writes one writes the other in the
  same breath.** Today that is `Stroke.starting(at:…)` and
  `append(_:pen:)`, and two maps that move every point one for one and
  keep the pressures as they are — the tablet page's turn
  (`TabletPage.turned`) and Writing taken off it
  (`TabletSelection.noteStrokes`) — and nothing else: every other edit
  (move, turn, group, delete, a duplicated note) carries the whole value.
  So a split, a crop or a merge added later keeps the two the same length. `InkPaths` reads a
  missing pressure as "none reported" rather than crash; that is a belt,
  not permission. **THE LEGACY GUARANTEE: a stroke with neither field —
  everything drawn before 2026-10-02, and every mouse or trackpad stroke
  still — goes down the old branch of `InkPaths.path` and the old
  painters' code, untouched.** The CODE is untouched; the INPUT is not
  quite: coalescing is off for the whole app (below), so a mouse or
  trackpad stroke drawn from now on carries every drag sample where it
  used to carry about one a frame — more points in its sidecar, and a
  little less for the midpoint smoothing to round off. Strokes already
  drawn keep the points they were saved with. `InkPathsTests` pins that
  branch's elements, its dot, its box and its hit reach, numbers taken
  from the code before ink existed; a change that moves one has restyled
  drawings already in Sean's notes. `Stroke.reach` is what a stroke's box and hit
  test measure — half the widest the ink can go, and for the legacy line
  `width / 2`, the same arithmetic as before.
  **The notebook's pen gets its pressure from `PenSampleReader`**, a
  local NSEvent monitor on the left-mouse events and `.tabletPoint` that
  notes the pressure of an event whose SUBTYPE is `.tabletPoint` — a
  Wacom pen's strokes are ordinary left-mouse events with that subtype —
  and returns every event unchanged; the drag gesture reads it while the
  same event is being handled. The stroke's FIRST event decides what it
  is: a nib makes ink — the pen menu's tool, `AppState.penTool`, the pen
  unless another is picked — with a pressure per point, a mouse or a
  trackpad makes the legacy line (a Force Touch trackpad reports a
  pressure of its own; the subtype says it is not a nib). Pressure is
  read off nothing else: `.pressure` on an event that does not define it
  is an Objective-C exception that kills the app (a key event, measured),
  and a spy in `PenSampleTests` proves the reading never even asks a
  hover. A mouse event's pressure field is 8-bit (0.42 goes in, 107/255
  comes out). Coalescing is off from launch so all of the pen's ~120
  samples a second arrive — for every pointer, the mouse's too: one
  switch at launch (see the trap below) — and finished ink is
  outlined once per stroke (`InkCache`, by id and a fingerprint of the
  samples) — measured first: 300 strokes of 120 samples took 5 ms in
  Release and 26–39 in Debug on EVERY redraw, and the layer redraws on
  every pen event.
- **THE WACOM IS AN INPUT DEVICE, CHOSEN EXACTLY LIKE A CAMERA.** Sean,
  2026-10-02: "wacom should basically just be chosen as if it were an
  input display". `TabletController` finds Wacom tablets by IOKit's own
  notices for a USB DEVICE with vendor 0x056A — a registry read, which
  opens nothing and asks nothing — and Input Devices lists them under the
  cameras ("One by Wacom (CTL-472)", named for the box, not the USB
  descriptor). Picking one turns the camera off and the pane that showed
  the video shows THE PAGE (`TabletPane`); picking a camera gives it
  back. Both menus go through `InputDevices.pick`, and
  `AppState.inputSource` is DERIVED from the pick — one writer, fed by
  the controller, never stored — so ⌘Y, the pane's switch and the
  whole-window view work on whichever pane it is. The tablet is read
  TURNED a quarter turn clockwise by default (Sean, same day: "i want to
  rotate the wacom 90 degrees clockwise"): counts (x, y), origin top
  left, extent (W, H) → page (u, v) = (1 − y/H, x/W), and the page is
  H/W wide; `tabletQuarterTurns` holds it, remembered. **HOW IT SITS HAS A
  NAME** (Sean, same day: "make sure i can orient the page with the device
  by rotating or flipping to make it match portrait or landscape"):
  `TabletOrientation` is Wacom's own four — Landscape (as it ships, 0),
  Portrait — turned right (1, the default), Landscape — upside down (2,
  Wacom's "flipped": half way round, for the other hand) and Portrait —
  turned left (3). ONE CONTROL, in the pane's corner where the two
  quarter-turn buttons were (`TabletOrientationButton`): the tablet drawn
  the way it lies, opening the four by name in a popover (a `Menu` is an
  AppKit control hosted over the pane) whose last line says what a turn
  does to what the pen writes on, and what the drawing's dot is. **THE
  PICTURE SHOWS THE TABLET'S LIGHT, WHERE THE LIGHT REALLY IS** (Sean,
  same day: "make the tablet orientation icon show the led on the tablet
  for the icon to give orientation"). The first glyph drew the edge that
  is the tablet's top as it ships HEAVY — a mark no tablet has, so it
  told him nothing; a picture gives orientation only by something he can
  find on the thing on the desk. On the One by Wacom lying landscape as
  it ships — Wacom's own product photo of the small one, the frame the
  pen's raw counts have their origin top left in — the status LED is a
  small dot just inside the LEFT edge, half way down (the fabric tag is
  on the right edge above the middle, the cable leaves the top; neither
  is drawn — four pictures at 14 points tell apart by the light alone,
  rendered and looked at). That is ONE FACT, `TabletOrientation.led`
  (0, 0.5), and everything about the light is it carried through the
  pen's own quarter turns: `ledPoint` is `TabletMapping.page` of it —
  never a second table of four, which could drift from the one the pen
  writes by — `ledEdge` the edge that point is on (left, top, right,
  bottom for 0…3), `lightPlace` that edge in words. `TabletGlyph` is the
  outline at the turned shape and a dot just inside that edge, half way
  along it (`outline`, `light`: pure, tested at the corner's 14, the
  popover's 26 and bigger, and the rendered view's lit pixels are held
  to them), LIT — a colour of its own, never the outline's, with a
  glow, so it is a light and not a hole — BY THE GROUND IT IS ON
  (`lightHex(onPane:dark:)`): a blue white on a dark ground, a full blue
  on a light one. A popover is dark or light with the appearance; the
  corner's glass is over the pane's black and is dark in both (#202423
  and #6E706F as the window server composites it — `ImageRenderer`
  draws no material, so a probe window was captured, 2026-10-02), so
  the corner's button says `onPane` and is lit pale in both: chosen by
  the appearance alone, the full blue was 1.25 to 1 on that glass. The
  corner's button, each row of the popover and the tip all say it: a
  row's second line is what was done to the tablet and where that leaves
  its light ("A quarter turn clockwise · light at the top", the light's
  words held together by no-break spaces), the popover is as wide as
  that line needs for the way it sits by default (`PickList.width`, 350
  against the paper's 310), and its footer ends "The dot is the tablet's
  light — on the left as it ships." A first cut put the CONTROL
  on the bar beside the two buttons it should have replaced — two controls
  for one turn, at either end of one row, which EVERY BUTTON HAS EXACTLY
  ONE PLACE forbids, and the bar squeezed to fit it. ONE WRITER:
  `AppState.orientTablet`, and the way it already sits picked again
  publishes nothing. It is the tablet's, so it holds for Page and Notebook
  mode alike and is never set aside.
- **WRITEMIND TAKES THE TABLET ITSELF: THE DRIVER'S WRITES ARE IGNORED,
  SO ITS HID DEVICE IS SEIZED.** Sean, 2026-10-02, with the page up and
  the pointer flying round the other display under his pen: "how can i
  disable wacom from taking over my mouse?", "i did, it's still
  controlling my mouse", "shouldn't WriteMind need some permissions like
  this?", "fix the wacom not being captured by writemind properly
  issues". The first build asked the Wacom driver for a CONTEXT with
  `pContextMovesSystemCursor` false, over its Apple Event interface
  (Wacom's Driver Request Interface). **That cannot work on this driver,
  and the evidence is measured** (driver 6.4.14-2, probes that day): to
  'WaWT' (WacomTabletDriver, `com.wacom.wacomtablet`) every READ answers
  — `core/cnte` one tablet, `core/getd` Xdim 9499, Ydim 15199, "One by
  Wacom", the pen's mapping and mode — and EVERY WRITE IS IGNORED:
  `core/crel` for a context returned an empty reply, five ways, and no
  context existed afterwards; `core/setd` of the pen's screen mapping
  returned an empty reply, four ways, and read back unchanged; the
  dictionary's own 'Core' class is errAEEventNotHandled (-1708); and
  'WaCM' (TabletDriver.app) only counts tablets. Nor does
  `CGAssociateMouseAndMouseCursorPosition(0)` hold the pointer — the
  driver posts absolute positions: 493 pointer moves in 509 pen events.
  So `WacomDriver.swift`, its Automation prompt, its usage string and
  its tests are GONE, whole — nothing of that path is kept, and do not
  bring it back for this driver. **So WriteMind takes the device**
  (`Tablet/TabletCapture.swift`): the tablet's USB interface 0 carries
  ONE HID device with two clients — WindowServer's event service and the
  driver's `IOHIDLibUserClient` (ioreg) — and a device opened with
  `kIOHIDOptionsTypeSeizeDevice` delivers nothing to anybody else
  (IOHIDFamily: the other clients' reports are dropped until the seizing
  client closes), so the driver goes quiet, the pointer stays where the
  trackpad left it, and WriteMind reads the pen's raw reports itself.
  Closing gives the driver the pen back. (Written before the seize had
  been run against the real tablet — nothing but the app itself may open
  it — so what the driver does when its reports stop, and whether it
  takes them up again cleanly, is read from the first sessions' log; if
  the open is refused or the driver keeps posting, the fallback and the
  pane's line below are what Sean sees.) **HELD ONLY WHILE ALL THREE
  ARE TRUE** — a tablet
  is the input and plugged in, what the pen writes on is on screen (the
  page, or in Notebook mode a note: `TabletInput.targetIsShowing`), and
  WriteMind is the active app — and let go the moment any one goes: a
  pen held for a page nobody can see writes nowhere and leaves the
  notebook's own pen dead, and in another app the pen is that app's.
  **AND THE HOLD FOLLOWS THE PICK**: another tablet picked while one is
  held (two plugged in) lets go of the one and takes the other — left
  held, the first went on writing under "pen captured" and the one
  ticked in the menu was a dead pen.
  `TabletCapture` is that rule as a VALUE (conditions in, `ask` / `seize`
  / `release` out; an open that lands late is known by its attempt
  number and is nobody's), `TabletController` is its shell, and the
  doors to macOS are the `TabletHID` protocol so the tests put a
  stand-in there. **INPUT MONITORING, AND A FIRST LAUNCH NEVER ASKS**:
  the tablet's HID device is a mouse to macOS
  (`RequiresTCCAuthorization`), so opening it needs Input Monitoring —
  and IOKit's own open ASKS BY ITSELF if nobody has. So the permission
  is only ever READ (`IOHIDCheckAccess`) — and only once a tablet is the
  input — and NOTHING IS OPENED UNTIL IT READS GRANTED; the question
  (`IOHIDRequestAccess`) goes up only as the direct result of Sean
  picking the tablet from a menu. Picking it again is how a pick
  remembered from before, or a question put away, gets asked. There is
  no usage string for Input Monitoring; the grant is keyed to the
  signature (`tools/signing.sh`). **`LiveTabletHID` REFUSES UNDER
  `TestHost` ON THE FIRST LINE OF EVERY DOOR** — the test host is the
  app, and from it an ask is a prompt on Sean's screen and an open is
  his tablet taken from under his hand — and `LiveTabletHIDTests` proves
  it with spies standing where IOKit is first touched. NEVER open or
  seize the real tablet, send it a report, or send the driver an Apple
  Event from a test, a script or a probe; reading the registry is the
  limit. Opening, the mode report and closing run on a queue of their
  own (a control request to a device that has stopped answering waits
  out the USB stack); the reports are scheduled on the MAIN run loop in
  the common modes. **WHAT IS CLOSED DIES ON THE MAIN THREAD**: neither
  the close nor the unscheduling waits for a report already on its way
  up, and IOKit's loop there holds the device by a bare pointer and
  copies into the report buffer — so the buffer is freed in a block on
  the main queue, behind it, and the device's last reference is not
  dropped before that block has run (`LiveTabletHID.close`). And
  "register nil" does not take the callback off (IOKit's set is hashed
  on callback and context, compared by context): `sink` going nil is
  what stops the reports. **THE RAW REPORT** (`WacomPenPacket`, the
  Bamboo-pen class's layout as the Linux driver reads it — the layout,
  none of its GPL code): id 2, ten bytes; byte 1 is 0x80 in range, 0x40 proximity (x
  and y are good), 0x20 ready (tip, switches and pressure are good),
  0x08 eraser, 0x04 upper switch, 0x02 lower switch, 0x01 tip; x and y
  little-endian at 2 and 4, RAW LANDSCAPE counts from the top left, y
  down; pressure little-endian at 6, 0…2047; distance at 8. Anything
  that is not exactly that — the second interface sends 64 bytes under
  the same id — is written to the log in hex and left alone; nothing is
  guessed. **AND A HELD TABLET THAT CANNOT BE READ IS GIVEN BACK**: held,
  the driver hears nothing, so reports this build cannot read would be a
  pen that writes nowhere at all — 32 in a row inside a second with not
  one of them the pen's, before the pen has been read once in that
  capture, and `TabletCapture.reported` lets go, the pane says it cannot
  read what the tablet sends, the page writes from the driver's events
  again, and only a pick (or a replug) tries it again. With no driver running the tablet is a plain relative mouse
  until feature report [2, 2] sets the pen's mode, so the mode is read,
  set only if it is not already the pen's (a tablet the driver set up
  is sent nothing), and put back on closing. **ONE FUNNEL, ONE ROUTE AT
  A TIME**: a raw report becomes the same `TabletReading` an event does
  and goes through the same `TabletPen`, the same turn and the same
  sample stream (`TabletInput.raw`); from the first raw report of a
  capture until the tablet is let go the driver's events are swallowed
  and draw nothing, and letting go lifts the pen (`rawEnded`). Events
  the driver made well after that first report (`stragglers`) mean it
  still hears the tablet — logged once, and the pane says the pointer
  may still move. **THE FALLBACK IS THE DRIVER'S EVENTS**, exactly as
  before WriteMind took the tablet: native
  `.tabletPoint`/`.tabletProximity` and mouse events with a tablet
  subtype, a LOCAL monitor and a GLOBAL one (the global route counts
  only while WriteMind is in front), the same sample by two routes
  counted once by its timestamp. A refused open (`kIOReturnExclusiveAccess`
  0xe00002c5: somebody else has seized it; `kIOReturnNotPermitted`
  0xe00002e2 with the permission reading granted: macOS wants the app
  quit and reopened), no permission, no device, or reports that cannot
  be read, and the page still
  writes from those events — with the pointer moving — and the pane's
  ONE LINE (`TabletPane.line`, in `Views/TabletStatusLine.swift`, pure)
  says the one useful thing: pick again to be asked, the Input
  Monitoring switch (with a button to it), quit and reopen, or why with
  IOKit's number. Held, it says "pen captured" and nothing more. A
  refused open is tried again at the next change — coming back to the
  front is one, and is also when a permission given in System Settings
  is first seen — never in a loop of its own. While the tablet is the
  input AND its target is on screen (`TabletInput.isCapturing`) the
  local monitor SWALLOWS every pen event — a tap must never click
  whatever the pointer happens to be over — and hands everything else
  back untouched; otherwise it hands back everything. The pressure is
  read only off an event that defines it (a spy in `TabletReadingTests`
  proves a hover is never asked). **THE EXTENT IS THE RAW SENSOR'S**: a
  table by product id (0x037A → 15200 × 9500 counts, 100 a millimetre),
  WIDENED to the farthest count ever seen so a wrong entry can never
  clip the page — and never the driver's (the trap below). **THE LOG IS
  HOW A SESSION IS READ** (/tmp/writemind-debug.log, one line each,
  never one per sample): every status change, what Input Monitoring
  reads whenever that changes, the pick's question and its answer,
  capture start and stop, each HID device opened (usage page, usage, the
  IOReturn in hex) and closed, what the mode report read and whether it
  was set, the first twelve raw reports of a pick in hex and the first
  of each unknown kind after, the first parsed reading, each capture's
  first report as it starts delivering — WITH WHETHER THE PEN WAS DOWN
  (`TabletInput.penAsTaken`: a pen tap is what brings WriteMind to the
  front, so the tablet can be taken with the nib on it, and the driver,
  cut off, never posts its button coming up; what macOS makes of that
  has not been seen — if a session shows a stuck button or drag beside
  that line, hold the seize until the driver's events say the pen is
  up) — the first event
  of each kind from each monitor, the first of the driver's events to
  arrive while the tablet is held, and the driver still posting.
- **THE PAGE IS THE PICTURE OF A PAGE, AND ANYTHING ON IT CAN BE TAKEN.**
  Sean, 2026-10-02: "in normal mode its as if we were looking at the
  picture of a page, and anything drawn can be selected and inserted".
  `TabletPage` is the page: the drawing layer's own `Stroke`s — ink, a
  pressure a point, a tool — whose points are FRACTIONS OF THE PAGE and
  whose widths are in the PAGE'S OWN POINTS, the long side `TabletPage.longSide` (800)
  whichever way it is turned, so the outline (`InkCache`), a box and a
  cut-out are all worked once in one space and the pane only scales them.
  The page pen's width goes on as it is SEEN — `TabletInk.width` divides
  by the page's scale on screen, so a 3-point pen writes 3 points where
  it is writing — and from then on the ink is part of the picture. It is
  kept in Application Support/WriteMind/TabletPage.json — **never in
  ~/Documents/WriteMind**, which is Sean's notes and their sidecars, and
  in `TestHost.supportDirectory` under the test host — saved half a second
  after the pen rests, off the main thread, and flushed on quitting; the
  flush waits for a save already on the queue, because AppKit exits the
  moment it returns. **BOTH LOCKS, AS FOR A NOTE**: the file is named
  for the BUILD (`TabletPage.fileName`) — any bundle id but the app's own
  keeps `TabletPage-<id>.json`, because Application Support is found by
  the app's NAME and a scratch copy is given an id of its own to be
  driven at all, and with one fixed name it opened Sean's page and wrote
  over it; and a save writes only over the bytes it last read or wrote
  (`NoteWriting.mayWrite(dataOnDisk:known:)`) — anything else is another
  writer's, left alone, and the page is written beside it as
  `TabletPage.conflict-<date>.json` from then on. **A BAD FILE IS SET
  ASIDE, NEVER WIPED**: one that is not a page is moved to
  `TabletPage.corrupt-<date>.json` and the page starts blank; one with a
  stroke that will not read keeps the rest and is copied there first,
  and what could be read is written back over it at once — or it was
  copied aside again at every launch.
  Undo is whole pages, a stroke a step and a clear a step, sixty deep, the
  session's and not the file's. **THE INK TURNS WITH THE SHEET**: the
  page is the tablet's shape turned, so a quarter turn makes a tall
  page wide, and fractions left where they were would stretch every
  letter — `align(to:)` turns every stroke, and the history with it, so
  each stays where it is ON THE TABLET (`TabletPage.turned` of a page
  point is `TabletMapping.page` one turn on, tested for every turn). The
  file says which turn its strokes are in, so a page opens turned to fit.
  **EVERYTHING IN PAGE FRACTIONS TURNS IN ONE BREATH** —
  `TabletScribe.align(to:)`, which every turn goes through (the corner's
  control, the `onChange` for any other, the pane coming up): the strokes
  and the history, THE BOX LEFT UP — turned onto exactly its turned
  corners (`TabletPage.turned(_ box:)`), so it is over the same writing;
  it used to be put away — and a stroke or a side-switch box HALF-DRAWN
  (`TabletWriting.turn`), so the rest of it, read the new way round by
  the funnel, joins on where the nib is. The turn is pure and tested for
  every delta from every turn, and round trips: four quarter turns, a
  turn and its inverse, a turn four on, are no turn within floating
  error. **A TURN IS DELIBERATELY NOT AN UNDO STEP**: it says how the
  tablet lies on the desk, which ⌘Z cannot change — a step that put the
  strokes back the old way round would leave the tablet held the new way
  and every stroke a quarter turn off where it was written on it. So the
  history turns with it (Undo after a turn is the page before, the way
  round it is now), and the way back is the same control, which turns
  the tablet back too. **The paper's print does not turn; it is laid for
  the sheet's new shape** (`layout(millimetres:)` is handed the turned
  millimetres) — held landscape, the ruling runs across the long side
  and the margin is on the left, as on a sheet that shape; the ink,
  written on the tablet, is what turns. So writing that sat on the
  rulings crosses them after a quarter turn — on purpose: the new
  writing, done the new way round, is what the lines are for, and the
  popover says the lines are laid out again (`PageThemeTests` holds the
  landscape layout; every paper was rendered every way round once,
  offscreen, 2026-10-02).
  A turned stroke gets a NEW ID — `InkCache` knows an outline by id and a
  fingerprint a turn can leave the same — and so does every stroke Writing
  puts in the note; both map points one for one and carry the pressures
  as they are, which is how they keep the lockstep rule above.
  **The samples become ink in `TabletWriting`**, a value walked sample by
  sample in the tests: the nib down starts a stroke with
  `Stroke.starting(…, pen: .pen(pressure:))`, a drag appends, the lift
  finishes it WITHOUT a point of its own (it reports no pressure, and the
  notebook's pen does not take its mouse-up either) — so a tap is one
  point, which the ink draws as a dot. A side switch HELD AS THE NIB GOES
  DOWN — either switch — makes the stroke a box instead and never ink;
  under 1% of the page it is the box's click (a tap with the switch
  held), which puts a box away. The switch alone, in the air, begins
  nothing: it used to begin the box there, and now it is a command (THE
  PEN'S TWO BUTTONS, below). Once begun the box goes on while the nib or
  the switch is down, as it always has. **INK ENDS WHERE THE NIB LIFTS**,
  whatever the switch is doing: asked as "nib or switch", a switch pressed
  under ink and held past the lift went on drawing in the air at no
  pressure — and a switch held over from ink makes no box of the next
  stroke until it is let go (`TabletPen.switchHeldOver`). `TabletScribe`
  is its shell and the ONE
  consumer of `TabletInput.samples` — and the notebook is the second
  target, chosen there (the rule after next). **120 SAMPLES A SECOND REDRAW ONE STROKE**: the stroke
  being written is `TabletScribe.stroke`, watched by its own layer; the
  page (`TabletPage.strokes`, watched by the finished-ink layer, which is
  `Equatable`) changes once a stroke; the box is `TabletBox`, watched by
  its own; the hover marker watches the funnel. `TabletScribeTests` holds
  the page silent through a hundred and twenty samples and a sample's cost
  under 4 ms on a page of four hundred strokes. All of it is SwiftUI — no
  hosted NSView over the pane (the eighth cause, below).
  **The box is the camera's `SectionBox`**, its look, its gestures and its
  three buttons (`help: .tabletPage` says what they do here), over the
  sheet in page fractions: a mouse or trackpad drag draws it, the nib with
  a side switch held draws the same one, a click on the sheet or the pane
  round it puts it away and so does the nib going down to write; Esc puts
  it away and is
  taken ONLY while there is one, and only for the page's own window with
  no field being typed in (`TabletBox.putsAway`). **ONE ESC CHAIN**: the
  box is a step in the drawing layer's (`DrawingCanvas.handleKey`: a
  label, a style bar, an armed shape, a crop, THE BOX, then the pen), and
  the pane's own monitor answers only while no layer
  watches keys (`DrawingCanvas.keyWatchers`, `TabletBox.paneAnswersEscape`) — two
  monitors each taking Esc for itself took it in the order they were
  added, which every rebuild of the panes changes. Its three go
  through `NoteStore.takeFromTablet` and land the way the camera's do:
  **Image** is the box as it is, paper and all, a PNG drawn by Core
  Graphics (`TabletRender`); **Writing** is the strokes the box TOUCHES,
  whole — the marquee's rule — re-expressed as the notebook's strokes
  (`TabletSelection.noteStrokes`), pressure, tool and colour kept, ONE
  group (a lone stroke gets none: ⌃G would read a group of one as one to
  take apart), ONE step; **Text** is those strokes rendered BLACK ON WHITE
  — explicit sRGB in a bitmap, because anything drawn through SwiftUI or
  a dynamic colour takes the window's appearance and Dark Mode's black is
  white — and read by the SAME path the camera's Text takes
  (`readIntoNote`), never through `captureNotebook(.ink)`, which would
  threshold clean ink a second time. Image and Writing are placed by
  `pageScaleLanding`, which the camera's captures now share: the page at
  `NotebookCapture.pageFraction` of the pane, under the caret when there
  is one — one scale for a box of writing whichever of the two it came
  off. **⌘Z IS THE PAGE'S STRAIGHT AFTER WRITING ON IT**
  (`AppState.pageOwnsUndo`): the page never has the keyboard, the pen is
  in one hand and ⌘Z under the other, and left to the focus ⌘Z after a
  stroke undid the TYPING in the note. The page owns it from a stroke, an
  undo, a redo or a clear on it until the note's text or drawing changes,
  and only while the page is the input and on screen; the corner has its
  own undo, redo and clear besides. The drawing layer's key monitor sees
  ⌘Z BEFORE the Edit menu does — a local monitor runs ahead of a key
  equivalent, measured — so it asks the page's claim too
  (`DrawingCanvas.takesUndo`); without that, ⌘Z after a stroke undid
  whatever was picked on the layer.
- **THE PAGE HAS PAPERS AND A PEN OF ITS OWN.** Sean, 2026-10-02: "it
  can have themed backgrounds and different pen colors and strokes to
  write with". `PageTheme` is the paper — plain, dot grid, ruled, graph,
  legal pad, blackboard — and each is three things: the sheet's colour
  (explicit sRGB hex, never a dynamic colour), what is printed on it, and
  an ink that reads on it (near-black, chalk on the board). **THE PRINT IS
  MEASURED IN THE TABLET'S MILLIMETRES AND LAID DOWN IN PAGE FRACTIONS**:
  ruled 8 mm apart from two rulings down with a red margin two rulings
  in, the legal pad the same with a DOUBLE margin, dots and squares 5 mm,
  as many as fit and centred, weights in millimetres too — so on the
  small One by Wacom held turned a ruling is 8/152 of the page whatever
  size the pane shows it, and a bigger tablet gets more lines, not fatter
  ones. The millimetres come from `TabletExtent.countsPerMillimetre` (100
  in the table); widening moves the edge and not the scale, and a tablet
  nobody measured is taken to be 152 mm along its long side. `layout(millimetres:)` is the pure part, tested;
  **`print` IS THE ONE PRINTER** — the pane's `TabletPaperLayer` and
  Image's `TabletRender.image` both call it with the same page and the
  same millimetres, and `PagePaperPrintTests` renders the two for every
  paper and compares them pixel for pixel (and that they print anything
  at all, so two blanks cannot agree). Text never sees a paper: it is
  the ink alone, black on white. The paper is THE PAGE'S, saved in
  TabletPage.json (`theme`, `decodeIfPresent`, a paper this build does not
  know opens plain and costs nothing else) and NOT an undo step. **The
  page's pen is not the notebook's**: `AppState.pageInkTool`,
  `pageInkHex`, `pageInkWidth`, remembered in the defaults — chalk on a
  blackboard would otherwise leave the notebook writing white on white.
  New strokes take it as it stands when the nib goes down
  (`Stroke.starting(…, tool:)`); strokes already written keep theirs.
  **WHEN THE PAPER CHANGES, INK THE CHANGE LEAVES UNREADABLE BECOMES THE
  PAPER'S OWN** (`AppState.pagePaperChanged`, `PageTheme.ink(_:after:)`):
  under a WCAG contrast of 2 on the new paper AND lower than it was on the
  old — black onto the board (1.1), chalk off it, the amber swatch onto
  the legal pad (1.8 on white, 1.6 there). That is all a change answers
  for. Asked of the new paper alone, it threw away colours picked on
  purpose: the paper in use picked again turned black chosen on the board
  to chalk, and amber picked on plain went black on the way to ruled,
  with nothing behind it changed. A colour that read no worse before was
  picked on a paper like this one, and stays; and the paper in use picked
  again is no change at all (`TabletPane.choose`). Both live on ONE SMALL
  BAR top left of the pane (`TabletBar`), in the band above the sheet, so
  it is never on the writing: the pen (its tool's icon, and a dot of its
  ink ON A CHIP OF THE PAPER, `InkChip` — on the corner's dark glass
  alone the first ink of all, near-black, was an empty ring) and the
  paper (a swatch printed by `print` itself, heavier); each opens a
  popover — the colour well and the slider are AppKit views, and in a
  popover they are in a window of their own, not hosted over the pane
  (the eighth cause). The tool picker, the size row and the colour row
  are ONE view each (`PenControls.swift`), shared with the notebook's pen
  menu, whose picker sets `AppState.penTool` — the tool a TABLET'S nib
  writes with in the notebook — and both menus have them in one order:
  tool, size, colour. The swatch in use is ringed OUTSIDE itself, a gap
  away: a ring on the swatch was black on the black one, the page pen's
  first ink, and white on chalk in Dark Mode. A mouse or a trackpad
  stroke is the legacy line whatever is picked: `Stroke.starting` gives a
  tool only to a nib. The board's faint light edge, which makes a dark
  sheet a sheet on the pane's black, is drawn OVER the paper layer and in
  the pane only — under it, the layer's own fill covered it
  (`TabletSheetEdgeTests`).
- **THE NOTEBOOK IS THE PEN'S OTHER TARGET, AND THE PAGE IS LEFT AS IT
  IS.** Sean, 2026-10-02: "make the text strokes well implemented to feel
  natural for writing letters.. do the same for drawing mode in the
  notebook itself and let the wacom control that as well.. as a separate
  mode". **Write on: Page | Notebook** is a switch on the page's bar
  (`TabletBar`, `TabletTargetSwitch`) and nowhere else on screen;
  `AppState.tabletTarget`, remembered, the page unless the notebook is
  picked. The View menu mirrors it as it mirrors Draw — "Write on the
  Notebook with the Tablet", no key, only while a tablet is the input —
  and both go through `AppState.writeOn`, which BRINGS THE NOTES INTO
  VIEW when the notebook is picked (leaving the whole-window page too): a
  pen writing in a note nobody can see writes nowhere. **The tablet held
  turned is FITTED onto the notes on screen** (`NotebookPlace`, pure): the
  drawing layer's own frame — below the tab bar and the formatting bar,
  above the footer, the source pane and the rendered page alike — and in
  it the tablet's turned shape as big as fits less 12 points, centred,
  never stretched, because a letter written on the tablet has to keep its
  proportions in the note; on the PANE, not the document, so the pen
  writes on what can be seen wherever the note is scrolled. A sample's
  page fraction (`TabletSample.page`, after the turn) goes `onPane` →
  `inDocument` (a scroll's worth down, the layer's `doc`) → `strokePoint`
  (fractions of the pane on BOTH axes) — the layer's own pen's point
  WITHOUT `DrawingCanvas.normalise`'s clamp, which pins a point a screen
  or more down a long note to the bottom of the first screen.
  `NotebookMappingTests` holds the fit, the centring and the four quarter
  turns through the funnel's own `TabletMapping`. **The nib writes the
  note's own strokes** (`NotebookWriting`, walked sample by sample;
  `NotebookScribe`, its shell): `Stroke.starting` with the nib's sample
  and the NOTEBOOK pen — `penTool`, `penColorHex`, `penWidth`, never the
  page's — `append` per drag, the lift no point, so a tap is a dot:
  exactly the stroke the layer's own pen makes. It lands through
  `NoteStore.inkFromTablet`, which takes `beginDrawingChange` AS IT LANDS:
  one stroke, one step, and one given up half-way leaves no empty step.
  **⌘Z IS THE STROKE'S STRAIGHT AFTER IT** (`AppState.tabletInkOwnsUndo`,
  part of `drawingOwnsUndo`): the keyboard is still in the note's text,
  and left to it ⌘Z undid the typing. From the stroke until the text is
  typed in (`noteTyped`, off `store.$text`), only while the notes are on
  screen, and **ONLY DOWN TO THE FLOOR**: the claim remembers where the
  drawing's undo stood under the first stroke since the typing
  (`tabletInkFloor`, in `NoteStore.drawingSteps` — every step taken less
  every one taken back, not held to the sixty the history keeps, whose
  count stands still under a new step once full) and is told where it
  stands on every change to the drawing (`drawingChanged`). Once the
  strokes, and whatever the layer did after them, are taken back, the
  next thing to undo is the typing: an undo that went on into the
  drawing undid an older step there and left the newer words standing.
  ⇧⌘Z stays the drawing's until the typing (`drawingOwnsRedo`), to put
  back what ⌘Z took. **The stroke being written is drawn by the layer's own
  painter** (`DrawingCanvas.paintLive`, which the layer's pen now calls
  too) on its own layer over the drawing (`NotebookTabletLayer`,
  `NotebookLiveInk`), so 120 samples a second redraw one stroke and not
  the note. While the pen is near, a faint dashed outline of the area and
  the page's own hover marker (`TabletHoverMarker`) show over the notes —
  SwiftUI shapes and a `Canvas`, hit testing off, no NSView (the eighth
  cause). **ANOTHER NOTE UNDER THE NIB TAKES NOTHING WITH IT**: the layer
  stays up when the tab changes, so `NotebookPlace` carries the note's id
  and the scribe drops whatever was under way when it changes — a stroke
  begun in one note landed in the next, half its points a scroll below
  the rest; a scroll or a resize in the same note keeps it. **NOR
  DOES A TURN**: the note's strokes are the note's and never turn
  with the tablet, but the area the tablet lands on does —
  `NotebookPlace.quarterTurns`, read off the turn like the aspect —
  and the rest of a stroke under way would land a quarter turn away
  from its start, so it is dropped too (`NotebookTurnTests`). **AND A
  LAYER GOING LETS GO ONLY WITH THE LAST** (`NotebookScribe.layerWent`):
  the notes pane is built again when a pane beside it comes or goes
  (⌘Y), SwiftUI can bring the new one up first, and the old one's going
  left the new one with no place and no way into the note — every stroke
  after it drawn live and landed nowhere; the coming one hands its place
  back besides. **A side switch held as the nib goes down is the layer's
  marquee**: drawn while it is dragged (`paintMarquee`, the ⌘-drag's
  look), and when the nib and the switch are both up it goes to the
  layer (`NotebookScribe.picks` → `DrawingCanvas.pick(byTablet:)`) and
  picks by `marqueePicked` — `Drawing.ids(touching:)`, whole groups by
  `CanvasGroups.whole`, ⇧ to add — the ONE rule the ⌘-drag's end now
  calls too; so ⌫ and the handles act on it as on a ⌘-drag's (and under
  the pen, as there, it picks with no handles drawn). A tap with the switch
  held is a ⌘-click; the switch clicked in the air is the note's drawing
  undo or redo (the rule below). **WHAT IS ON SCREEN DECIDES, BY TARGET**:
  `TabletInput.aim(at:)` (fed from the app, as the turn now is too) and
  two counts — pages, and notebooks: a note open under its layer, counted
  by `NotebookTabletLayer` appearing — give `targetIsShowing`, and both
  the funnel's swallowing and the hold on the tablet follow it. In
  Notebook mode the page may be put away; with no note open there is
  nothing to write on and the pen is a pointer. Switching with both up
  is no change at all: the tablet stays held, for either. Switching drops
  whatever was half-done for either (`TabletScribe.dropUnderWay`): the
  lift of a stroke begun on the page lands nowhere, and the page's box
  goes. The samples' one consumer is made the moment a tablet is the
  input (`TabletScribe.shared`, from the app), since in Notebook mode the
  page's pane may never have been on screen. **NO KEY CHANGES THE
  TARGET**: an Esc that sent the pen back to the page was the last step
  of the layer's chain for a day, and a local monitor sees a key before
  the notes do — so in a mode that is remembered and lived in, every Esc
  meant for the notes (an armed seam, a block being edited, held cells,
  the /link banner) went to the tablet instead, and with the page put
  away the pen was silently a pointer. The switch and the View menu are
  the way.
  **THE PAGE SET ASIDE**: in Notebook mode the sheet is dimmed with one
  line (`PageSetAside`, which takes the clicks on the sheet so no box is
  drawn on it) that follows what is on screen
  (`TabletInput.notebookIsShowing`, `TabletPane.setAsideLine`): "The pen
  is writing on the notebook" while a note is up, and while none is, that
  there is none and the pen is a pointer until there is — the funnel and
  the hold on the tablet have let go then, and the line said otherwise. The page's
  pen and paper, its undo, redo and clear and its hover marker are out of
  play, and the turn stays — it is the tablet's, and holds for the
  notebook. **THE BAR FITS ITS PANE**: the bar and the corner's buttons
  are ONE ROW (`TabletPane.topRow`), so the bar is offered what the
  corner leaves and takes the first of its shapes that fits
  (`ViewThatFits`): the switch with "Write on" and an icon a name, the
  two names alone — what the default 420 gets; two bare icons there read
  as one more paper control beside the swatch — the two icons, or on a
  row of its own over the pen and paper. Laid over each other, a bar that
  grew a switch would run under the corner. **THE SWITCH NEVER MOVES
  UNDER THE POINTER THAT PRESSED IT**: it comes first on the bar, and in
  Notebook mode the page's controls, the bar's and the corner's, are SET
  ASIDE IN THEIR PLACE (`View.setAside`: not drawn, not hit, not read
  out, still measured) — taken out, the room they left made the switch
  grow its words in Notebook mode and lose them in Page mode, and the
  button just pressed jumped. Measured offscreen, 2026-10-02, with the
  turn's one control in the corner: "Write on" from 456 points up, the
  names from 372, the icons below that. The switch is two buttons, not a
  segmented `Picker` (an NSSegmentedControl, hosted, over the pane), and
  the one in use is lit with the primary colour, never the accent.
- **THE PEN'S TWO BUTTONS UNDO AND REDO THE LAST DRAWING.** Sean,
  2026-10-02: "make the wacom buttons undo and redo last drawing". His pen
  (the One by Wacom's LP-190K) has two switches on the barrel, and each
  is its own bit of the raw report (`PenSwitch`: 0x02 the LOWER, nearer
  the nib, 0x04 the UPPER — the Linux driver's BTN_STYLUS and
  BTN_STYLUS2; the upper used to be read as nothing). **A CLICK — pressed
  and let go with the nib UP the whole time, in reach — is a command: the
  lower takes back the last drawing, the upper puts it back.** It fires as
  the switch is LET GO, once a click however long it was held and however
  far the pen moved, so that holding a switch and then putting the nib
  down is still the box, and letting go after a box is not a click. The
  pen's own state tells the two apart (`TabletPen.clicked`, pure, walked
  in `TabletPenTests`): a press seen in the air with nothing else held
  ARMS that switch (`armed`); the nib touching while it is held, a switch
  already held as the pen comes into reach, the pen leaving, the other
  switch joining in (two at once say nothing about which was meant), and
  a raw report that is not ready — its switches are NIL, "cannot say"
  (`TabletReading.Kind.point(switches:)`), because read as "let go" an
  unready report at the edge of the tablet's reach could make a click of
  a switch still held (a precaution: how the LP-190K's reports end there
  is unmeasured) — all disarm it and owe nothing; only the armed switch
  read as let go, nib still up, is the click. A switch pressed under a
  stroke or a box is nothing, during and after. **SO THE BOX IS BEGUN BY
  THE NIB**: a side switch alone, in the air, used to begin the box (the
  driver's right-button drag), and a click could then be no command; now
  the box begins with the nib going down with a switch held — either
  switch, where the upper used to write ink — and once begun goes on as
  it always did, while the nib or the switch is down (the switch let go
  mid-drag, or the nib lifted with it held, is still the box). The click comes down
  the one stream as a sample of its own kind, `TabletSample.Phase.click`,
  by both routes (`TabletInputTests`, raw reports and the driver's events
  alike); `TabletWriting` and `NotebookWriting` ignore it. **ONE PLACE
  SAYS WHOSE UNDO IT IS** (`TabletScribe.command`, by the funnel's target,
  which is `AppState.tabletTarget`): in Page mode the page's own
  `undo`/`redo`, what the corner's two buttons do, `onWrite` (⌘Z the
  page's) only when something changed; in Notebook mode the note's
  drawing undo and redo — `NoteStore.undoDrawing`/`redoDrawing`
  THEMSELVES, the two ⌥⌘Z and ⇧⌥⌘Z call, never a second undo beside them
  — through `NotebookScribe.takeBack`/`putBack` and the way in the notes
  pane hands over as its layer comes up (`NotebookScribe.writes(into:
  telling:)`, which also carries the stroke's way in, so the tests go
  through the same wiring), only with notes on screen. With nothing to
  take back or put back nothing happens: no beep, no step, no claim on
  ⌘Z. **BY THE DRIVER'S EVENTS THE UPPER IS THE MASK'S 0x4**: the
  fallback route sends the lower switch as the right button (mask 0x2),
  and the upper only in the mask, `penUpperSide` — measured on the nib's
  own events (`/tmp/writemind-debug.log`, 2026-10-02: a leftMouseDown
  with mask 0x5, a leftMouseUp with 0x4) — so either switch held as the
  nib goes down is the box by both routes (`TabletReading.point`). No
  hover has been seen carrying 0x4, so the upper's click in the air —
  REDO — IS PROMISED ONLY WITH THE CAPTURE, and the page's Redo tip says
  so (`TabletPane.undoTip`, `redoTip`: both name the pen's buttons). **WHICH
  PHYSICAL BUTTON IS 0x02 IS THE LINUX DRIVER'S WORD, NOT MEASURED**: the
  first click of each switch in a pick is written to the log
  (`TabletInput.noteFirstClick`), so a session in which undo and redo come
  out on the wrong buttons says which bit the finger pressed — swap the
  two in `TabletScribe.command` and nowhere else.
- **A project is a list of folders in a JSON file** (`Project`,
  `.writemind-project`) — Sublime Text's shape. What is NOT in it is the
  session: which notes are open, which one is in front, and any text that had
  not reached disk. That lives in Application Support, one file per project
  plus a `default.json` for "no project yet" (`ProjectSession`), which is why
  closing an unsaved project is safe and why a launch comes back where it
  left off. The session's file name is the project's name plus a hash of its
  full path — two projects called the same thing in different folders must
  not share one.
- **A STABLE SIGNATURE IS WHAT MAKES "ALWAYS ALLOW" HOLD.** macOS remembers
  a camera or folder grant against the app's CODE SIGNATURE, so ad-hoc
  signing — a different signature every build — made every rebuild look like
  a new app and ask again. `tools/setup-signing.sh` puts a self-signed
  code-signing certificate in the login keychain and `tools/build.sh` uses it
  when it is there (`WRITEMIND_SIGN_IDENTITY` overrides; a real Apple
  Development identity works too). Without it the build still works and says
  out loud that the prompts will come back. The keychain asks for a password
  once, in a dialog — that is macOS's question to Sean, not something to
  script around. Two things had to be right before it worked, both of them
  silent failures: **the PKCS#12 must use the old PBE algorithms**
  (`-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`, and a
  non-empty password), because OpenSSL 3's defaults make `security import`
  report "MAC verification failed (wrong password?)", which is not a password
  problem at all; and **the identity's name has spaces**, so passing it
  through a shell string that gets split turned
  `CODE_SIGN_IDENTITY=WriteMind Local Signing` into the build action 'Local'.
  Proof it works is the designated requirement being IDENTICAL across two
  builds: `identifier "com.seancheren.WriteMind" and certificate leaf = H"…"`.
  Check that, not just that the build passed. **And check it after
  `tools/test.sh` too**: `xcodebuild test` rebuilds and re-signs the very
  same Debug bundle, and while test.sh signed ad-hoc and build.sh used the
  certificate, the two took turns at being "a new app" — every test run
  undid the grant, and Sean was asked again and again (2026-09-18). Both
  scripts now source `tools/signing.sh` and call its `signed_xcodebuild`;
  any new script that runs xcodebuild into build/DerivedData must do the
  same. The test host also no longer touches what the prompts guard:
  `TestHost.isActive` (XCTest in the environment or the process) sends
  `NoteStore()` to a scratch folder and stops `CameraController` reconnecting
  the remembered camera. Builds from Xcode's own Run button still sign ad-hoc
  (`CODE_SIGN_IDENTITY = "-"` in the pbxproj) and will ask.
- **Every captured page is the same size, by memory not by measurement.**
  Squaring a page up (CIPerspectiveCorrection) returns a rectangle whose
  proportions depend on how the page was tilted towards the camera, so
  measuring each capture made every page a slightly different size. The
  notebook's page shape (long side ÷ short side) is learned from the first
  page that was actually found and kept in `notebookPageShape`; later pages
  within 12% of it are resampled to exactly that shape, further off
  re-learns (a different notebook, or the page sideways). A frame with no
  page found is never remembered. The picture then lands at the page's
  scale: `NotebookCapture.placement` fits a whole page into
  `pageFraction` of the pane and puts the writing where it was on that
  page, so captures line up. **That fraction is 0.9 — the size the
  viewfinder showed it** (Sean, 2026-09-22: "the drawing and image when
  selected from the camera are too small.. they should be the size you
  can see in the output viewer"), a reversal of "make the selection
  smaller" from 2026-09-18 and written down as one: what changed
  underneath is that a capture no longer pushes the text about at all,
  so a big picture costs the note nothing. It stays ONE number for
  every capture — matching the viewfinder exactly, by the page's real
  share of the video frame, would make every capture a different size,
  which is what `notebookPageShape` exists to prevent. **THE TRACE IS
  NOT THINNED.** It was, for a day — eroded to a third of its measured
  width, then cleaned a second time for the grid dots the erosion let
  through — and Sean had it taken out (2026-10-02: "the text isn't
  coming through crisp and backgrounds aren't being ignored etc.. it was
  working better before"). Erosion on a thresholded mask chews the
  edges of every stroke and shrinks a printed dot into something the
  lattice search no longer recognises; both are worse than heavy ink.
  If the weight comes up again, it wants a different tool than a mask
  eroded pixel by pixel.
- **INK THE COLOUR OF THE PAPER IS SHOWN AS ITS OPPOSITE, ON THE NOTE.**
  Sean, 2026-10-02: "images and text work from a selection, but taking
  the writing itself doesn't". It did: fourteen strokes a time were in
  his sidecar, in the page's near-black ink (#1C1C1E, picked for white
  paper), on a Dark Mode note whose paper is #1E1E1E. The same hole was
  under the notebook's own black swatch, and under a white pen's strokes
  in a note opened in Light. `InkPaths.shownHex(_:onPaper:)` is the rule
  — below a contrast of `seen` (1.5) with the note's paper a stroke is
  painted black or white, whichever reads, as the note's text is — and it
  is asked when the stroke is PAINTED (`DrawingCanvas.draw(…paper:)`, the
  live stroke and the tablet's notebook layer too), never stored: the
  stroke keeps the colour it was written in and the appearance can change
  under it. The tablet's PAGE passes no paper; its ink is kept readable by
  the paper's own rule. Paper export already did this (`DrawingInk.ink`).
- **Every NSTextView gets its OWN undo manager.** Left to itself an
  NSTextView registers its undo actions on the window's undo manager, and
  both editors here are torn down routinely — a `BlockEditor` whenever its
  block stops being edited, the source `MarkdownTextView` whenever the
  preview comes up. ⌘Z afterwards invoked an action whose text view had
  been freed, and the app died in `_NSUndoStack popAndInvoke` (crash report
  WriteMind-2026-09-18-034439.ips). Each coordinator owns an `UndoManager`,
  hands it over in `undoManager(for:)`, and empties it in
  `dismantleNSView`. Any new text view must do the same.
- **DEPLOY AFTER EVERY SMALL CHANGE.** Sean, 2026-09-19: "always deploy
  after a small change". The installed bundle is the only place he sees this
  app, so a finished change is not finished until it is in
  `/Applications/WriteMind.app`. The loop per change is: patch,
  `sh tools/test.sh`, quit the running copy, `sh tools/deploy.sh`,
  `open /Applications/WriteMind.app`, then the one-line reply. Never hold a
  finished change back waiting for the next one and never stack three asks
  behind one build — a build carrying five changes is one version he cannot
  pin a regression to.
- **Do not rebuild under a running app.** `tools/build.sh` and
  `tools/test.sh` rewrite build/DerivedData/…/WriteMind.app in place, and
  test.sh launches it as the test host on top of that. An instance Sean
  opened from that bundle while a build was rewriting it gets killed by the
  kernel when it pages in code that no longer matches its signature — which
  looks like "the app closes as soon as it opens" (Sean, 2026-09-18). Run
  the builds and the tests first, launch with `tools/run.sh` last, and then
  leave the bundle alone.
- **The drawing layer never has keyboard focus, so it WATCHES keys.**
  `DrawingCanvas.watchKeys` is a local NSEvent monitor: ⌫/⌦ delete the
  explicit selection (never a merely hovered object), ↩/esc finish or drop a
  crop, and ⌘V takes a picture off the pasteboard when the first responder
  is not one of our `PasteAwareTextView`s (those paste pictures themselves;
  `BlockTextView` inherits it and asks `EditorBridge.pasteImage`). The
  monitor returns nil to swallow a key — anything it does not take must be
  returned unchanged or typing dies. **THE MONITOR HOLDS A COPY OF THE
  VIEW**: its closure, made in `onAppear`, captured the layer as it was
  then, and every plain input `handleKey` reads — the mode, an armed
  shape, the arrow tool — stayed as it was then; the layer does not
  appear again when they change. A note opened in cursor mode, the pen
  picked up: Esc read "no pen" and the pen stayed up, and ⌘Z and ⌫ asked
  the same stale mode. `@State`, the binding and the closures read
  through to the live value; the plain inputs are `KeyInputs`, and the
  monitor is put up again from the new copy whenever they change
  (`CanvasKeyTests` sends Esc through `NSApp.sendEvent`, which is where
  local monitors are asked). An input `handleKey` starts reading goes in
  `KeyInputs` too.
- **THE PANE HAS ONE MODE, AND THERE ARE TWO OF THEM.** Sean, 2026-09-21:
  "drop the cursor and select buttons.. clicking the pen outside of the
  dropdown is the toggle between pen and cursor.. in both modes holding
  cmd is how to get the selector". `AppState.CanvasMode` is that switch —
  `cursor` and `pen`, kept in the defaults like the pen's size and colour,
  and named in the footer whenever it is not `cursor`, because a pane that
  swallows every click and comes up that way after a launch needs
  somewhere on screen that says why. `penActive` is a question about the
  mode and is stored nowhere. ONE BUTTON on the bar says which, and
  pressing it toggles; the cursor and the marquee each had one beside it,
  which was three buttons for two answers. A remembered `select` from
  before decodes to nothing and `CanvasMode(rawValue:) ?? .cursor` gives
  the pane back to the notebook. **Esc puts the pen down** (Sean,
  2026-10-02: "esc should exit pen mode") — `AppState.escapePen()`, the
  one writer beside `togglePen`, asked from `DrawingCanvas.handleKey`
  AFTER a label, a style bar, an armed shape, a crop and the tablet
  page's box have had the key, and taking it only when there was a pen
  to put down.
  **What a press does is `CanvasMode.press(with:)` and nothing else
  decides it**: ⌘ is the selector in BOTH modes, so it is asked BEFORE the
  mode — a modifier held down is asked for by hand, and that is what
  overrides a mode. Under the pen a ⌘-drag used to draw a stroke over the
  thing it was meant to be picking up. The pointer stays a pencil there
  even so: the pencil is set by the text view as well as by the layer, and
  two answers to one pointer is the flicker that cost seven rounds.
- **A MARK IS AN ICON, AND IT GOES WHERE IT IS CLICKED.** Sean,
  2026-09-21: "the checkmark shouldn't be placed until i click where it
  goes, like an arrow.. it's far too big, it would be a checkmark next
  to a piece of text.. and a similarly sized red x and yellow ?". So
  EVERYTHING on the palette arms `CanvasPlacement` — nodes, marks and
  lines alike — and nothing puts an object down in the middle of the
  pane on its own (`NoteStore.addShape` is gone; the click is the
  placement). Three things say what a mark is, and all three are in the
  model rather than in a view. `ShapeItem.markSide` is how big it
  arrives: ONE LINE OF THE NOTE'S TEXT, in points off
  `MarkdownTextView.font` — as a fraction of the pane it was four lines
  tall on a wide window and half that on a narrow one, and what a tick
  has to match is the writing beside it. `Kind.inkHex` is what colour it
  means — a green tick, a red cross, a yellow query, from the app's own
  preset swatches, because a black tick beside a red cross says nothing;
  it is nil for a node and for a star, which take the pen's. And the
  stroke is limited by the BOX and not only by the pen: an eight-point
  pen in an eighteen-point box is a blob. A drag still sizes a mark by
  hand and a dragged mark takes the whole pen. A LINE OR AN ARROW runs
  from the press to the release and nowhere else; a press that never
  moved puts down NOTHING and leaves the tool armed, where it used to
  put down a short horizontal line centred on the click — a different
  line from the one asked for, in a different place.
- **A SHAPE STAYS ARMED; A MARK IS ONE CLICK.** Sean, 2026-10-02: "after
  drawing a rectangle dont exit rectangle mode..". Until then every
  placement went back to the palette once something was down, and only ⌘
  held as it went down kept the tool. `CanvasPlacement.staysArmed` now
  answers by the KIND: a node (the flow chart's six, wherever it was
  picked — the Marks palette's box, circle and triangle are nodes) and a
  line or an arrow are DRAWN, corner to corner or press to release, a
  chart is several of them, and the next drag draws the next one with no
  key held. A mark — tick, cross, query, star — is still one click and ⌘
  still keeps it: Sean's words for it ("if i hold cmd, stay in adding
  that marker mode") ask for ⌘ to KEEP a marker, which is a marker that
  goes back without it, and a tick is a stamp beside one word. An armed
  tool is put away by Esc (the layer's chain, as before); the same tile
  picked again (`AppState.arm`, the palettes' one writer, and the armed
  tile is lit); another tile; the arrow tool, which now puts an armed
  shape away as arming a shape always put the arrow tool away (`begin`
  asks the placement first, so a shape left beside it would take every
  drag meant for the arrow); a mode, the pen, ⌘P; and EVERY WAY ONTO THE
  PAGE — the bar's Text Box, the pen menu's Add Image, Insert ▸ Image…
  and Insert ▸ Text Box, the camera's capture and the tablet's
  (`AppState.putToolsAway`). Each of those put the pen down so what
  arrived could be typed in or picked up, and a shape left armed took
  that click and put a box down on it; the first cut routed the bar's
  two and missed the other four, so `CanvasModeTests` now reads the
  sources and fails on a call that drops something on the page without
  it. While it is armed the footer names it after the mode, in the same
  colour (`CanvasPlacement.footer`: "Rectangle: every drag draws one,
  Esc to stop"), and the bar lights the button whose palette holds it,
  as it lights the pen and the arrow tool (`AppState.shapesLit`,
  `marksLit`; both for the box, circle and triangle the two palettes
  share, from the one list each palette is laid out from,
  `CanvasPlacement.flowChart` and `marks`) — the lit tile alone was
  inside a popover that closes as it is picked. The pointer stays the
  crosshair and the handles stay hidden; what was just drawn is the
  selection, so ⌫ and ⌘Z take it back without disarming. The placement
  is asked before any mode, modifier or object under the pointer, and
  **A CLICK ON A NODE IS THE NODE'S** (`CanvasPlacement.release`): Sean's
  flow chart is a loop — draw a box, double-click it for its label, draw
  the next — and a box left armed took both clicks of the double-click,
  two boxes at their own size stacked on the one clicked and no label.
  With a node or a line armed, a press that never moved and lands on a
  node picks it, its group whole, and the second click of a double-click
  opens its label — the same answer as with nothing armed, a node in a
  group opening none. Anywhere else a click puts a node down at its own
  size; a drag that starts inside a node still draws; a mark clicked
  onto a node goes down in it, a tick in a box; and the drag shows no
  ghost of a box over the node it is about to pick. A placement press
  ends a label being typed and an arrow's style bar, as any press on the
  layer does, so the next box follows the last label straight away.
- **A group is a shared id, and every rule about it is in `CanvasGroups`.**
  Sean, 2026-09-20: "toggle grouping with the button on the screen or
  ctrl+g". `group: UUID?` sits on `Stroke`, `ImageItem` and `ShapeItem`
  (in `CodingKeys`, in the memberwise init, `decodeIfPresent` so an older
  sidecar still opens); a `ConnectorItem` has none, because it is held by
  the nodes at its ends and follows them. Nothing about a group is
  positional, so ungrouping moves nothing. The canvas holds NO rule of its
  own: `whole(_:in:)` grows a selection (click, marquee and `handleIDs`
  all go through it), `toggle(_:in:)` says which way ⌃G goes, and
  `toggled(_:in:)` returns nil for a no-op so it never reaches the undo
  stack. ⌃G is in `handleKey`, and it returns FALSE when there was nothing
  to do — a key monitor that swallows a key it did not use is how typing
  dies. One toggle both ways: two or more not-already-one-group become a
  group, a whole group comes apart, and a group plus something loose
  GROUPS (it swallows, so bigger groups are built without unpicking the
  smaller ones first) — which is why `grouped` also re-labels members that
  were not themselves picked, or half a group would be left behind.
  The arrow tool and an armed placement are NOT modes: they take the pane
  until they are put away — the arrow tool until it is switched off, a
  node or a line until Esc or another tool, a mark for one click (the
  rule above) — so picking either puts the mode back to `cursor`, picking
  a mode puts them away, and each puts the other away. TWO READERS, and
  everything else asks one of them rather than spelling the flags out
  again — `canvasOwnsPane` (do the clicks reach the notebook: the seams
  on both panes, the layer's hit shape) and `paneCursor` (what the
  pointer is over the pane: the pencil, the crosshair, or nil for "the
  notebook's own four"). The list used to be written out in three
  places, and a fourth thing holding the pane meant finding all three.
  The marquee is one rule wherever the drag came from — ⌘ under the pen,
  ⌘ over the words — and every one of them ends in
  `Drawing.ids(touching:)`, which skips a hidden picture exactly as
  `index(at:)` and `bounds(of:)` do: a rectangle over blank space must not
  hand ⌫ something nothing on screen said was there.
- **The pencil cursor wins by swallowing cursorUpdate events.** A
  cursorUpdate event is how AppKit hands a view its turn to set the cursor
  — the text view's I-beam, the window's arrow — and cursor rects, a pushed
  cursor and setting the pencil on every hover all lost to it (Sean, three
  times, 2026-09-18). `CursorLayer.CursorRectView` runs a local NSEvent
  monitor: while it has a cursor and the pointer is over it, cursorUpdate
  events are returned as nil and every mouseMoved/drag sets the pencil. The
  text view under the pen (`PasteAwareTextView.cursorOverride`) answers with
  the pencil too, for the moves the monitor lets through — and, since even
  that let an I-beam through now and then (a fourth report), it drops its
  own tracking areas while the override is set (`updateTrackingAreas`), so
  no cursor event reaches it at all; and the layer sets the pencil once
  more on the next run-loop turn, after whatever the dispatch did. The
  pencil itself is black with a white halo at 28pt — the first, a thin white
  glyph, was invisible on the page. SWALLOWED, NOT ANSWERED: routed, a
  cursorUpdate reaches the layer's SwiftUI host and never
  `CursorRectView.cursorUpdate`, and the window behind the host answers
  with the arrow. And the layer is mounted only while it has a cursor at
  all — see the eighth cause under the traps. The notebook views the pen
  does not take the tracking areas from — the gutter, and under the ⌘
  crosshair or a hand all three — ask `CursorRectView.claim` on every move
  and give the layer's answer, so a move is never answered twice.
- **THE PENCIL HAS TO BE HANDED BACK WHEN THE POINTER LEAVES THE APP.**
  `NSCursor.set()` is global and sticks until something else sets one, and
  nothing outside this app ever will — so the pencil followed the pointer
  onto the desktop, onto Finder, onto everything (Sean, 2026-09-21: "make
  sure the draw pen only shows while its in the notes pane, not outside
  the app"). `CursorLayer.CursorRectView.cursor(_:at:in:wasInside:)` deals
  with the pointer leaving the note for somewhere else IN THE WINDOW; it
  cannot deal with this one, because no mouse-moved event is delivered at
  all once the pointer is somebody else's. Three watchers cover it, and
  each is needed: a GLOBAL NSEvent monitor (the only thing that sees a
  move going to another app — it can watch and not modify, which is all
  this needs, and its arrival IS the news), `NSWindow.didResignKey`, and
  `NSApplication.didResignActive`. They all go through `handBack`, which
  asks the pure `reclaimed(cursor:wasInside:)` so it fires once and only
  when the pencil was ours to begin with.

- **An armed seam IS the cursor, so the caret is turned off — and it has
  to come back.** A click in the space between two cells arms it: the line
  drawn across the page is where typing will go (Sean, 2026-09-20: "when
  clicking in between, the horizontal line appears and that is where the
  cursor is"), and a caret blinking somewhere else at the same time is two
  cursors. `PasteAwareTextView.armedSeam` sets `insertionPointColor` to
  clear and puts `caretColour` back the moment it goes, so every path that
  disarms — a key, a click, the pen going up — must go through that
  property and not round it, or the note is left with no caret at all.
  And a bar that is the cursor LIGHTS NOTHING: arming parks the caret at
  the separator, `NotebookCells.block(containing:)` reads that as the
  start of the cell below, and the next cell was drawn heavy under a bar
  that was not in it (Sean, 2026-09-20: "the next section shouldn't be
  highlighted when the input cursor is currently that horizontal bar").
  `Coordinator.refreshBrackets` takes no `caretCell` while `armedSeam` is
  set, and the rendered page drops `editingRange` when it arms; a real
  selection is untouched, because that is not the caret.
  EVERY reader of "the caret is in that cell" needs telling, and they
  were found one at a time: the brackets, then `updateHiddenMarkers`
  (which revealed the neighbour's `## ` the moment the bar was armed by
  a click, and not when it was armed by ↓ — `textViewDidChangeSelection`
  sets `armedSeam` BEFORE it asks, or the answer is for the move before
  this one), then `EditorBridge`. A COMMAND AT A BAR MAKES THE CELL
  THERE (Sean, 2026-09-21: "if i click on something like a style, or a
  bullet list, or a quoted section, etc.. it should create a cell at the
  position of the bar ready for that type of input"). The bar is in no
  cell, so `EditorBridge.atArmedBar` makes one: a command that NAMES a
  kind — the ladder, the three lists, the quote —
  opens the cell with that marker already in it and is finished, and
  anything else — bold, the text style — opens a PLAIN cell and then
  runs in it. ⌘8, ⌘9 and the maths palette make theirs there through
  `Insertion` (the rule after the next), as one edit and one step of
  undo. `perform(opensACell:)` tells those from the third
  sort, the commands that act ON a cell — delete, duplicate, move,
  split, merge — which still do nothing at a bar, because an empty cell
  made to be deleted is churn in the note and a step on the undo stack
  for a gesture that did nothing. It used to record the kind and wait
  for a character, which is what the + on the bar does and goes on
  doing; a BUTTON pressed has to do something the moment it is pressed,
  and one that named no kind did nothing whatsoever. Left alone it restyled whatever cell the caret was
  parked against: the one BELOW the bar in the source pane, and on the
  rendered page the note's FIRST cell, because with no text view
  `perform` fell through to `ensureEditing`.
  Which seam a point is in is `CellSeams`, once, for both panes — the
  markdown pane measures the cells' boxes off the layout manager
  (`MarkdownTextView.cellBoxes`) and the rendered page off the stack
  (`MarkdownPreview.seams`), and neither of them decides what a seam is.
  `CellInsertions` only draws it and takes the click; on the rendered
  page the seam is a view of its own, armed by `MarkdownPreview.arm`,
  and `MarkdownPreview.seamKey` says what a key pressed in one means.
  WHERE the bar is drawn is `Seam.line`, not the middle of the seam: the
  seam under the last cell is the whole of the empty page below it, and
  the bar at its middle sat hundreds of points adrift of the note (Sean,
  2026-09-20: "the bar should go immediately after the last cell, not
  the random spot below it's currently at"). The line is against the
  cell it follows; the hit area is still the whole seam. On a note with
  NO cells there is nothing to sit against, so the pane hands in
  `firstCellTop` — its own inset, which `CellSeams` cannot know and the
  two panes do not agree on (`topInset + gapHeight` on the rendered
  page, `textContainerOrigin.y` in the source). Without it the bar was
  against the very top edge and the first character came out an inset
  below it.
- **The + on the bar chooses a KIND, and there is only one block
  builder.** Sean, 2026-09-20: "pressing the + button on that bar should
  bring up the list of style types that the next input will create a cell
  the type of". It is not a second way to make a cell. The seam opens its
  plain cell through `PreviewEditing.insertBlock` exactly as it always
  did, and then `CellTypes.opening` runs the SAME command the Format menu
  runs — `setHeading`, `toggleList`, `toggleQuote`, `codeBlock` — over the
  cell that just opened. `CellTypes.open` is the whole rule and both panes
  call it; anything that wants a new kind adds a case there and nowhere
  else — `Insertion` builds ⌘8's, ⌘9's and the palette's cells with it
  too, so `.code` carries a language (the + offers the plain one) and
  `.evaluation` an environment (not on the + menu: three environments
  would triple a list for a cell its own key already makes). And THE
  BAR'S OPENING IS ONE CHANGE: `MarkdownTextView.openSeam` replaces the
  characters between one `shouldChangeText` and one `didChangeText`; it
  used to call `insertText` between them, which asks and tells for
  itself, so the opening went on the undo stack twice — one ⌘Z after
  typing at the bar under the last cell threw an NSRangeException
  (2026-10-02, measured with undo grouped by hand). Three things about it that are not obvious: the command is applied
  while the cell is still EMPTY and the character is typed afterwards, so
  `- `, `> `, `### ` and a pair of fences all leave the caret exactly
  where the words go; `setHeading` needs `evenIfEmpty: true` for that,
  because a blank line inside a selection must otherwise keep its shape.
  The choice lives on the armed seam and nowhere else
  (`PasteAwareTextView.armedType`, `MarkdownPreview.armedType`) and goes
  back to plain text the moment the bar moves or goes out — setting
  `armedSeam` resets it, so no path can leave a stale kind behind. The
  menu itself is `CellTypeMenu`, an NSMenu in BOTH panes: the mark the +
  sits on is only drawn while its seam is hovered or armed, and a SwiftUI
  `Menu` whose label goes off the page closes with it. Which means the
  markdown pane must ask whether the + is DRAWN before it takes a click
  as a press of one (`CellInsertions.marked`, read by `draw` and by
  `mouseDown`): `plusTarget` is nine points either side of the bar, so
  on an ordinary eight-point seam it is the whole of it, and the plain
  click that moves the bar to another seam popped the menu as well.
  And RE-ARMING THE SEAM THAT IS ALREADY ARMED KEEPS THE CHOICE, both
  sides — `PasteAwareTextView.armedSeam.didSet` short-circuits and
  `MarkdownPreview.arming` says the same thing — or pressing the + a
  second time to look at the choice throws it away behind the menu that
  is still ticking it.
- **A BLOCK ASKED FOR IS A CELL OF ITS OWN, AND `Insertion` SAYS
  WHERE.** Sean, 2026-10-02: "make math and code block insertion
  sensible..". ⌘8 (and the code button, and Insert ▸ Code Block), ⌘9 and
  the maths palette all go through `EditorBridge.insert`, which asks the
  pure `Insertion.insert` with the whole note and the caret in it — the
  bar's offset while the bar is the cursor; on the rendered page
  `MarkdownPreview.insertionSpot` reads it out of the open cell, past the
  fence line of a code cell, so both panes give ONE answer — and gets
  back one edit or a refusal said in the footer (`EditorBridge.say`).
  The rules, in the order asked: AT THE BAR the cell is made there, ⌘8's
  language with it. INSIDE A FENCED BLOCK nothing is ever nested: the
  same kind does nothing and says why (⌘8 in code; ⌘9 in a cell already
  running in that environment); ⌘9 in any other fenced cell turns it into
  one, the 2026-09-21 rule, except an `out` answer, which is never code;
  maths in a block that is already Wolfram Language (```wl, ```eval wl,
  Wolfram code) goes in as the BARE WL at the caret, since composing one
  is what the palette's α and ∑ are for; inline maths in any other code
  is refused; anything else goes AFTER the block as a cell — after its
  answer when it has one, never between code and what it said. A BLOCK
  IS A CELL — a blank line above and below, never glued into a paragraph
  or an item: a paragraph is cut at the caret, spaces at the cut dropped
  (at the front of its words the block goes above, at the end below);
  a heading, a list, a quote or a rule is cut only BETWEEN LINES — above
  the caret's line when the caret is at the front of its words or in its
  marker, below it otherwise — so no item's words are split and no
  marker is left bare; on an empty line of a blank cell the block takes
  that one line and the rest stay the note's. A SELECTION IS THE CONTENT:
  code and evaluation cells take it verbatim, the text either side
  staying cells (an item's words take the item, marker and all); maths
  takes a selection's place only when it still HOLDS it
  (`MathSelection.holds`: the selection reads as WL — no word in it — and
  is a whole term of the maths), otherwise the words stay and the maths
  goes after them; the palette opens SEEDED from a selection that reads
  as maths, in the sentence when it sits in one, and a shape picked then
  takes it into its first slot; a selection with a fence in it is
  refused. THE CARET ENDS WHERE TYPING GOES — between an empty block's
  fences, at the end of what it was given, at the end of display maths'
  WL, after inline maths, which stays in the sentence (never in front of
  a marker) and is a plain cell of its own where there are no words. ONE
  ⌘Z TAKES IT BACK: the source pane applies the one edit; the rendered
  page sends an edit that stays in its open cell's words (inline maths,
  bare WL) through that cell's editor, and otherwise changes the note,
  opens the cell the caret landed in (a code cell as its code) and puts
  the way back on that editor's own undo stack (`offerUndo`). The cell's
  text is `CellTypes.open`'s, its spacing `PreviewEditing.insertBlock`'s
  (`replacing:` a selection, the spacing read off the note as it is).
  The map of what each command did before, context by context in both
  panes, is in the commit that made this.
- **Arming is a reading of where the caret is, not a mode a click turns
  on.** `CellSeams.arm` answers it from the selection alone, and
  `textViewDidChangeSelection` is the only place the markdown pane sets
  `armedSeam` from — so ↓ onto the blank line between two cells arms
  that seam (it used to be an ordinary caret there, and one character
  merged the two cells into one paragraph), and everything that moves
  the selection without a mouse down — a bracket click, ⌘A, a toolbar
  command, `/link`, a note switch — disarms by arriving somewhere else.
  Two places the offset cannot speak for: 0 is both the seam above the
  first cell and the start of it, and the note's length is both the tail
  seam and the end of the last cell, so an arm AT the caret's own offset
  always stands and the next move clears it. **One writer.** The text
  view's `armedSeam` is it; `CellInsertions.armedOffset` mirrors it
  through `onArmChanged` and looks the geometry up in its own `seams`
  every time it draws, because a stored rectangle goes stale — the old
  one was left painted across the next note at a y that meant nothing.
- **A funnel is not only keystrokes.** `insertText(_:replacementRange:)`
  opens an armed seam only when the range is `{NSNotFound, 0}`, which is
  what AppKit passes for typing. A caller that NAMES a range means that
  range: `EditorBridge.insert(_:belowDocumentY:)` is the only route the
  words read off a picture have, and opening the seam instead dropped
  them wherever the bar happened to be.
- **A middle click on a tab needs AppKit, and hit testing is not enough.**
  SwiftUI has no middle-button gesture, and an NSView behind the tab that
  claimed `otherMouseDown` in `hitTest` never received it. `MiddleClickCatcher`
  keeps a weak table of its views and one `otherMouseDown` monitor asks each
  view whether the click is inside its `visibleRect` (converted into the
  view's own coordinates — SwiftUI's global space and the window's disagree
  about the titlebar), then swallows the event.
- **Arrows are two-point items with attachments; `reconnect` keeps them
  honest.** A `ConnectorItem` stores its two ends as pane fractions plus an
  optional node id per end. It has a transform like everything else so the
  shared move/scale/rotate maths works on it, but `Drawing.reconnect(in:)` —
  called after every `apply` in the canvas and after a new arrow — bakes that
  transform back into the points and then puts every attached end on the
  edge of its node (`boundaryPoint`: the outermost crossing of the node's
  outline). Anything that moves items must call it, or arrows lag behind.
  Deleting goes through `Drawing.removing`, which takes attached arrows too.
  Shapes are unit-square polylines scaled into a box (`ShapeItem.Kind`); the
  drawn path may be a true curve (oval, rounded rectangle) while the
  polyline is what is hit and what arrows land on.
- **The drawing layer scrolls with the text.** Objects are in the
  DOCUMENT: their pane fractions are measured from the document's top, and
  `DrawingCanvas` draws and hits everything `scrollOffset` higher — the
  editor reports its clip-view scroll through `MarkdownTextView.onScroll`,
  `EditorPane` hands it to the canvas and to `NoteStore.canvasScroll`, so a
  new object lands in the visible part (`visibleCenter`). Every incoming
  gesture point goes through `doc(_:)` and every handle position through
  `screen(_:)`/`clamp`; a new gesture or overlay must do the same or it will
  be a scroll's worth off. **And `normalise` holds y only at the
  document's top** — a stroke a screen and a half down is at y 1.5. Its
  old clamp to 1, from before the layer scrolled, flattened every stroke
  and arrow drawn below the first screen of a long note onto that
  screen's bottom edge (found 2026-10-02; `CanvasNormaliseTests`). Both
  panes scroll the layer: the rendered page reports how far its content
  has moved (`MarkdownPreview.onScroll`) exactly as the markdown pane
  does. The first cut kept objects on the pane and the text's
  exclusion bands moved with the scroll — a picture taller than the pane
  then pushed the text out of reach for good.
- **THE SIDECAR KEEPS THE MARKDOWN PANE'S FRAME, AND THE RENDERED PAGE
  SHOWS IT THROUGH THE CELLS.** Sean, 2026-10-02: "preserve the position
  of things as much as possible between markdown and wysiwyg mode". The
  two panes lay the same cells out at different heights — `blockGap` (26)
  between cells on the page against about 14 in the markdown pane with
  its markers hidden, a code cell's two 22-point fence lines against 7
  points of padding each side, the page starting ten points lower — so
  with one frame for both, a picture put beside a paragraph in one mode
  was a cell or more off it in the other, further the further down
  (measured on a twelve-cell note: 82 points by the last cell; a
  thirty-cell page of prose, about 400). Objects are stored as they always
  were, in the MARKDOWN pane's document — the launch always opens there,
  and a capture lands under that pane's caret, so that is where nearly
  everything in Sean's sidecars was put; old sidecars open where they
  were in that mode, and the format did not change. The rendered page
  shows them through `PaneMapping`, from the markdown pane's cells to its
  own by the character offset each starts at: piecewise linear down the
  page — inside a cell by how far down it, in a seam by how far across
  it, above the first cell by how far down the air above it, past the
  last by the distance below it — and linear across between the two text
  columns. Monotone, exact to invert, the identity when the layouts
  agree; a cell one pane has no box for (folded, not measured yet) is no
  knot. **ONE PLACE CONVERTS, AND IT IS THE LAYER'S BINDING**:
  `EditorPane.layerDrawing` hands `DrawingCanvas` the drawing SHOWN in
  the page's frame (`Drawing.shown`) and takes back what the layer did
  through the inverse (`Drawing.stored`), so drawing, hit testing, the
  handles, a drag, a new stroke and a placement all happen in the frame
  on screen and the canvas knows nothing of two panes — do not add a
  conversion inside it. An object moves WHOLE, by where the mapping puts
  the top left of its box, and a GROUP by the top left of all of it
  (letters of a word must not part where the word crosses a cell's
  edge); a connector goes point by point, x and y apart so a routed
  line's corners stay square, and `reconnect` puts its ends back on its
  nodes. **What was shown as one goes back as one**, and that is the
  group as it was SHOWN: `DrawingCanvas.apply` writes ONE MEMBER AT A
  TIME (a binding's every `items[i] =` is a write of its own), so each
  write puts the whole group back by the corner of all of it — put back
  member by member, each by its own corner, a group came apart on every
  frame of a drag, and a text box grouped under a stroke went ten points
  up the sidecar for every letter typed in it (found in review,
  2026-10-02; `PaneFramesTests`). A unit whose corner is where it was
  shown — a label, a colour, ⌃G, a member deleted — keeps the offset it
  was shown with, exactly: grouping, ungrouping and deleting move nothing
  in the sidecar, and the page, which moves a group by its corner, shows
  the new grouping at once (`PaneFrames.stored` forgets what the layer
  wrote). A unit the layer did not touch comes back bit for bit — a drag
  writes the whole drawing every frame, and every write is a save. What
  the STORE puts on the layer by a place on the pane — the middle of the
  window, a capture's landing, the tablet's nib, the chart read off the
  camera — goes through `NoteStore.landed` (`paneMapping`, set by the
  editor pane), and a crop is made on the picture as the page shows it
  and put back through `Drawing.stored`, so the kept part stays where it
  was on the page. The markdown pane's cells, which the rendered page
  needs with that pane not on screen, are laid out offscreen by the very
  same TextKit 1 stack and styling (`MarkdownTextView.cellBoxes(of:pane:…)`,
  `style`), cached in `PaneFrames` per note, width, markers and folds — a
  pane only made taller or shorter wraps nothing differently unless a
  scroller comes or goes, which the note's height says — dropped on every
  switch, and only when there is a drawing to show. While the note is
  typed into or the window dragged, the cells laid out last are SHOWN
  carried along and laid out again 150 ms after it stops; anything about
  to be SAVED (the layer's writes, `landed`, the crop) asks for them
  `exact` and they are laid out there and then — a picture pasted after
  a paragraph was put in above it, carried along, was saved that
  paragraph's height off. The PDF lays the note out the rendered way, so
  it puts the drawing on paper through the same mapping
  (`NoteExport.drawingOnPaper`). `ModeRenderTests` draws one note with a
  picture and strokes beside its third paragraph in both modes (and the
  page without the mapping, where the line under that paragraph's first
  line sat under the second paragraph's last).
- **A new picture goes under the caret, and the note does not move for
  it.** `NoteStore.caretAnchor` (set by `EditorPane`, nil outside the
  source editor) gives the caret's line from `EditorBridge.caretLineFrame`
  — the text view's coordinates ARE the layer's document coordinates — and
  `placedCenter` puts the picture one `MarkdownPreview.gapHeight` under
  that line, flush with the text's left edge. Not 8: the same constant the
  seam between two cells is, so the landing and the seam cannot drift
  apart. Nothing is typed into the note and nothing is pushed aside; the
  picture floats over the words. Shapes and text boxes still land in the
  middle of what is on screen, and so does a picture on the rendered page,
  which has no caret line to give — from where it is on that page into
  the frame the sidecar keeps (`NoteStore.landed`).
- **THE RENDERED PAGE'S RHYTHM IS THE SOURCE PANE'S, AND IT IS NOT
  `gapHeight`.** Sean, 2026-09-22: "make the spacing more uniform.. it's
  ok on markdown mode but in rendered mode things get scrunched
  together". `MarkdownPreview.blockGap` is the air between two cells —
  `MarkdownTextView.lineHeight` plus the paragraph style's `lineSpacing`,
  which is the blank line the other pane puts there and the spacing round
  it — and it is what `PreviewLayout.positions` stacks with, in the page,
  the seams and the PDF alike. `gapHeight` is 8 and stays 8: it is the
  FLOOR under a seam (`CellSeams.seams(minimum:)`), enough to put the
  pointer in, and it is also the source pane's own `paragraphSpacing` and
  where a pasted picture lands. One constant for two jobs is why the
  panes were never squared up — the page stacked cells 8 points apart
  where the source put 26, and raising the number moved the floor with
  it. A WIDER GAP IS A WIDER SEAM, and so a wider band for the
  horizontal pointer and a bigger target for the +, all for free.
  Uniform also means NO BLOCK CARRIES AIR OF ITS OWN: `lineSpacing` is on
  `BlockView.body` rather than on `.paragraph` alone (a wrapped bullet or
  quote was four points a line tighter than the paragraph beside it), a
  rule's clickable body is a `frame(height:)` and not padding that leaks
  into the gaps, `.blank` is `lines * MarkdownTextView.lineHeight`, and a
  cell OPEN for typing pads by `codePadding` like the rendered one — with
  12 there, clicking into a code cell dropped everything below it twenty
  points and lifted it back on the way out.
- **A CODE CELL IS A BOX ROUND ITS CODE.** `MarkdownPreview.codePadding`
  is half the code's own size, so the box is a little bigger than the
  text (Sean, 2026-09-22: "there shouldn't be so much padding in the
  cells themselves"). It was ONE SOURCE LINE, which made a code cell
  exactly as tall as the other pane's `` ``` body ``` `` — a contract
  given up on purpose, because a full line of air each side made a
  one-line cell three and a half lines tall and nothing depended on the
  heights being equal: the two modes come back to the same place by the
  cell it is in and how far through it (`CellPlace`), and the drawing
  layer goes through the two panes' cells (`PaneMapping`).
- **⌘T KEEPS THE PLACE, THE CURSOR AND WHAT IS HELD.** Sean, 2026-10-02:
  "preserve the position of things as much as possible between markdown
  and wysiwyg mode". The two panes are two views torn down and built
  again on every switch; what crosses is in the store and the bridge.
  **The top of the window is a `CellPlace`** (`NoteStore.topCell`): the
  cell, by its offset, and how far into it — 0…1 down the cell, below 0
  in the seam above it — read by both panes by the ONE rule, "the first
  cell whose bottom is below the fold", with no tolerance on either side.
  It used to be the cell alone, put back with its top at the fold: line
  three of a paragraph came back two lines up, a long code cell up to its
  whole height, a round trip settled on the cell's first line, and a
  window resting in a seam opened a whole cell up because the two panes
  read the fold with different slack (1 point against 8). The place is
  the open note's — a note switch resets it — and moves with its cell
  when an edit lands above it without a scroll (`CellPlace.shifted`).
  The rendered page puts it back once its rows are measured (they can be
  BEFORE `onAppear`, so it checks there too), through its own scroll
  view (`PageMark`, a zero-size NSView — never one with a size, see the
  eighth cause), and says nothing of its own top until it has.
  **The cursor is a `PaneCaret`**: a caret or selection in the note's
  offsets, cells held by their brackets, or the bar and its + choice.
  `AppState.toggleMode` reads it off the pane going (`EditorBridge.
  carryCaret`, before the switch: the pane coming up can be built first)
  and the pane coming up takes it once, for the same text only
  (`takeCarried`). The markdown pane puts the caret back and takes the
  keyboard; with no cursor carried it puts the caret at the start of the
  top cell rather than the end of the note, where ⌘1 titled the last
  cell and a pasted picture landed under the last line. The rendered page
  opens the cell round the caret with the same selection in its editor
  (after the fence, for code; one reminder's words, for a checklist), arms
  the bar, or holds the cells — without the click every other way in is,
  which would drop the drawing layer's selection, kept across the switch.
  With nothing open, a command there opens the cell at the top of the
  window, not the note's first.
- **Nothing on the drawing layer moves the text.** Objects float: no
  exclusion band, no per-block push, no anchor, no re-homing, no bracket
  (Sean, 2026-09-20: "all drawing, captured or drawn with the pen tool,
  are now free floating and don't belong to cells whatsoever and so don't
  push other cells around"). `PreviewLayout.positions` is a pure stack —
  cell, `gapHeight`, cell — and the text container's `exclusionPaths` is
  never set. Anything that "needs" a band back is reading the model wrong;
  `docs/PLAN-cells-and-floating.md` is the model. DOCKING is the other
  state and is not built: `docs/PLAN-docking.md` is that plan, and it
  turns on one decision — a docked picture is written into the .md as an
  image line, so it becomes a CELL and the text is above and below it
  because that is what a cell is. **The source editor is
  still TextKit 1**, but not for that reason any more: `MarkerHiding` and
  `BulletGlyphs` are `NSLayoutManagerDelegate` glyph substitution — the
  faded `#` and the `- ` drawn as a bullet — which TextKit 2 has no
  equivalent of. (The old reason: a full-width exclusion rect made TextKit
  2 lay out nothing at all past it, and the whole note vanished.)
- **A picture on the pasteboard does not enable Paste by itself.** A
  plain-text NSTextView validates the Edit menu's Paste item against what it
  can read — text — so with only a screenshot on the pasteboard the item is
  disabled and ⌘V is swallowed before `paste(_:)` runs; copied text pasted
  fine, which hid it for three reports. `PasteAwareTextView.
  validateUserInterfaceItem` says yes when `holdsPicture` does. Read a paste
  problem from /tmp/writemind-debug.log (`DebugLog`), not the unified log:
  NSLog from a launched app is redacted there as <private>, and a `log`
  shell function shadows /usr/bin/log in Sean's shell besides.
- **A refused folder is not a dead end.** `NoteStore` reports `accessDenied`
  when the folder cannot be read or created, and the sidebar offers "Choose
  Folder…" — a folder the user PICKS is granted by macOS there and then,
  whatever the Documents permission said, and the choice is remembered in
  `notesDirectoryPath`. `useDefaultFolder()` goes back to
  `~/Documents/WriteMind`.
- **No sandbox, on purpose.** The app reads a real folder in Sean's home and
  writes there; sandboxing would move that to a container and require a
  user-selected bookmark for the folder he actually asked for. It is a local
  app, not a store app: `CODE_SIGN_IDENTITY = "-"` in the pbxproj, no team,
  hardened runtime off, and the scripts swap in the local certificate (see
  the signature trap above). Camera access is a TCC prompt keyed to the bundle
  id `com.seancheren.WriteMind` plus the usage string in the generated
  Info.plist (`INFOPLIST_KEY_NSCameraUsageDescription` in the pbxproj).
- **A first launch never asks for the camera.** `CameraController` only
  reconnects a device the user already picked (`lastCameraDeviceID` in
  UserDefaults); the prompt fires the first time the Input Devices menu is
  used. Keep it that way — a writing app that opens with a camera dialog is
  the wrong first impression. The tablet keeps the same rule
  (`lastTabletID`), and the two picks are exclusive: picking one forgets
  the other.
- **A to-do is a list STYLE, not a cell of its own.** Sean, 2026-09-21:
  "add a bullet type which are todo bullets that can be checked or
  unchecked". It is GFM's task list in the file — `- [ ] ` and `- [x] ` —
  so `MarkdownFormatting.ListStyle.todo` sits beside dots, dashes and
  numbered, and the list button, the Format menu and the `+` on the
  insertion bar all pick it up from `allCases` without being told. Three
  things it needed that the others did not. The parser reads a task
  BEFORE a plain bullet, because `- [ ] milk` starts with `- ` and would
  otherwise be a bullet whose words begin with a box. `ListStyle.matches`
  for dots and dashes says NO to a task for the same reason — asking for
  dots on a task list read it as already styled and took the markers off
  instead of swapping them. And `stripListMarker` takes the box with the
  dash, or the new marker landed in front of the old box. Ticking is
  `MarkdownFormatting.toggleTodo`, which rewrites ONE character — the box
  — so the words, the indentation and whichever of `-`, `*`, `+` the line
  was written with survive a tick; the note is the only place the answer
  lives, and there is no state beside it to get out of step.
- **The heading ladder is Sean's naming, and it is six deep** (2026-09-18):
  Title `#` · Header `##` · Section `###` · Subsection `####` ·
  Subsubsection `#####` · **Author subheader `######`**, which the preview
  renders ITALIC AND SLIGHTLY BIGGER than body (17pt against 15) rather than
  as a smaller sixth-rank heading — that inversion is the point of it, so do
  not "fix" it to match a web renderer. `MarkdownFormatting.Heading` owns the
  names and the markers; the bar's ⌘1–⌘7 (⌘1 title, ⌘2 chapter, ⌘3 author, ⌘4–⌘6 sections, ⌘7 body) and the preview's
  `headingFont` both read from it. Applying a level a line already has takes
  it back to body.
- **Indenting with a caret moves the whole paragraph** (Sean, 2026-09-18:
  "indenting text indents the whole block of text, not just the first line").
  `blockOrSelection` widens a caret to the run of plain paragraph lines
  around it; a list item, a quote line, a heading and a fence each stand
  alone, because Tab on the second bullet has to nest THAT bullet and not the
  list. A real selection is always taken as given.
- **Tab, Shift-Tab and Backspace are structure keys.** Tab indents the lines
  the selection touches, Shift-Tab outdents, and Backspace outdents ONLY
  while the caret is still inside the line's prefix (`prefixLength`) — past
  that it must stay an ordinary backspace or the note cannot be edited.
  They go through `textView(_:doCommandBy:)`, so one code path serves the
  keys and the ⌘[ / ⌘] buttons. Indent nests a quote (`> ` again) and shifts
  anything else by two spaces; outdent takes spaces first, then a quote
  marker, so Shift-Tab on a top-level quote unquotes it.
- **The bar has to fit the pane it lives in.** It is inside the editor pane,
  so its width is whatever the split gives it, and an HStack that does not
  fit overflows in BOTH directions — the first cut pushed Bold out under the
  sidebar and cut the right-hand control off at the divider. That is why the
  preview is ONE lit button rather than a segmented pair (Sean, 2026-09-18:
  "preview is a single button that is highlighted when active"), why the
  icons are 12.5pt in 24pt squares with no spacing between them, and why the
  bar is `.clipped()`. Adding a control means checking it still fits a
  half-width window.
- **`/link` writes an anchor into the OTHER note.** Typing `/link` at a word
  boundary raises the banner; the target is whatever note is open when "Link
  Here" is pressed, at the caret or over the highlighted run. A highlighted
  run becomes `<mark id="wm-…">…</mark>` — which is both the anchor and the
  annotation Sean asked for, "that it's highlighted and linked to"; a heading
  needs nothing written (its slug IS the anchor); any other block gets
  `<a id="wm-…"></a>` in front of it. All portable HTML, never a private
  marker. `NoteStore.completeLink` edits the TARGET through the open note and
  the SOURCE on disk, then re-opens the source — the editor never shows a
  stale copy of a file that changed underneath it.
- **The preview is editable, block by block, and that is the whole trick.**
  Clicking a rendered block opens a field holding THAT BLOCK'S markdown,
  styled as the block, and the commit replaces only that block's source
  range. The document is never round-tripped from attributed text back to
  markdown — that conversion is lossy, and losing it would be losing Sean's
  notes. `MarkdownParser.positioned` is what makes it possible: every block
  carries the range it was parsed from. Changing the parser means keeping
  those ranges exact.
- **Font, size and colour are `<span style="…">` on the selection.** Sean
  chose that over a document-wide typeface (2026-09-18) — same trade as
  `<u>`: portable HTML that other markdown readers understand. Only the
  ticked parts go in, and "System" means no `font-family` at all.
  `MarkdownInline` renders those spans and folds the span's font together
  with the bold/italic the markdown already carried, rather than overwriting
  it — that is what `inlinePresentationIntent` is being read for.
- **⌘D is Sublime's, and it is bulletproof on purpose.** The ranges handed
  back to AppKit are clamped, sorted, de-duplicated and non-overlapping
  (`MarkdownFormatting.normalise`) because `selectedRanges` DROPS THE WHOLE
  SELECTION if any of that is wrong, and a stale range outliving an edit is
  the normal case, not an edge one. The run is word-bounded once a press
  expanded a caret into a word, and it ENDS on any edit or on a selection the
  run did not make — otherwise the next ⌘D hunts for whatever the last run
  was looking at. ⌃⌘G takes every occurrence at once.
- **Text transforms are pure functions with tests beside them.** The
  toolbar's bold/italic/underline/bullets are `MarkdownFormatting` (an
  `Edit` = range + replacement + selection, applied by `EditorBridge` through
  the NSTextView so undo sees it); the preview is `MarkdownParser` (blocks)
  and `MarkdownInline` (spans); the sidebar title is `Note.make`. Views only
  call them. A behaviour change lands there, with its test in
  `WriteMindTests/`, never in a view.
- **Underline is `<u>…</u>`.** Markdown has no underline; the tag is the
  portable answer and the preview renders it as an attribute. Do not invent a
  marker that only this app reads.
- **The pbxproj uses synchronized root groups** (`objectVersion = 77`): every
  file under `WriteMind/` is in the app target and every file under
  `WriteMindTests/` is in the test target, without editing the project file.
  Adding a Swift file is creating it. The version lives in that file too —
  `MARKETING_VERSION`, once per configuration, four in all — and the release
  lane rewrites every occurrence and refuses to ship if they disagree.
- **`sh tools/dtp.sh` / `sh tools/tdtp.sh`.** The deploy IS the Mac bundle:
  `tools/deploy.sh` builds Release into `dist/WriteMind.app`, smokes it (it
  launches and stays up eight seconds), and installs it at
  `/Applications/WriteMind.app` — before the tag, so a broken build leaves
  the version untagged and the re-run reuses it. Then a bare `x.y.0` tag and
  an atomic push. `--web` / `--mac` are accepted for CoreMind's orchestrator
  and change nothing; `--ios` / `--android` are refused by name.
- **One heavy build at a time** (baseline). `xcodebuild` here is one; a
  device or desktop build in a sibling repo is another. Queue, never overlap.

- **RUNNING A CELL IS THE MOST DANGEROUS THING THIS APP DOES, and it is
  refused by default.** Sean, 2026-09-21: "finish the work on evaluation
  cells", and "evaluation cells are completely different from code
  cells". An evaluation cell is ```eval wl, ```eval python, ```eval c,
  ```eval c++ or ```eval rust — ⌘9 makes one where the caret is, turns
  a fenced cell the caret is in into one, or at an ARMED BAR makes one
  there (`Insertion`'s rule, above; it used to ask `caretCell()`, so at
  a bar it restyled the cell BELOW the bar and anywhere else it ignored
  the caret and went after the whole cell), ⇧↩
  runs it AND NOTHING ELSE DOES, the badge at its left picks the
  environment, and the answer goes under it in an ```out cell.
  **`CellMark` IS THE MARGIN**, one column for both halves of a pair so
  that the two boxes start at the same x — the answer had none, and its
  box began a badge's width left of the code's. What it says and what
  KIND of thing it is both follow the cell's state (Sean, 2026-09-22:
  "the dropdown for selecting an evaluator shows before it's
  evaluated.. after it's evaluated it disappears and is replaced by the
  In[]"): a cell with nothing decided carries the environment menu
  drawn as a button, a cell that has run carries `In[n]` as a plain
  label and its answer `Out[n]`. The number is
  `EvalCells.number(of:in:)` — the nth pair in the NOTE, not the order
  things were run in, because there is no session and the only place a
  number could be kept is the fence. It is built outside both the
  rendered block and the open editor so clicking into a cell to type
  does not take it away ("the indicator for WL/Python/C++ never goes
  away, and get rid of the play button"). **A SwiftUI `Menu` cannot be
  made to look like a button**: under `.borderlessButton` it draws its
  own chevron on the LEFT and discards the label's background and
  border, so the mark is a plain `Button` popping `EvaluatorMenu` at
  `NSEvent.mouseLocation`, the same way `CellTypeMenu` serves the + on
  the insertion bar. A PLAIN CODE CELL NEVER RUNS: that
  distinction is the feature, and it is in the file so that another
  editor can see it too. ⇧↩ arrives as `insertNewline:`, not
  `insertLineBreak:` (macOS gives that one to ⌃↩), so the shift is
  read off `NSApp.currentEvent`; and it is NOT a menu shortcut,
  because a menu key equivalent would take ⇧↩ from every text view in
  the app.
  The app is unsandboxed with the hardened runtime off, so a child runs
  with his full privileges and inherits WriteMind's TCC identity — a
  Python cell that opens ~/Documents raises a prompt with the notes app's
  name on it. So, all of it checked by tests rather than trusted:
  **`CellRunner` is the only file that may say `Process(`**, and a test
  walks every source and fails on a second one; **a run starts only from
  a press** — never on opening a note, never on a save, never from a
  view's body, and `NoteStore.swift` itself may not call it; **the guard
  is `TestHost.isActive` on the first line of the spawn**, not a disabled
  menu item, because `tools/test.sh` makes the Debug app the test host and
  the suite reaches in with `@testable` (and `tools/smoke.sh` kills only
  the app's pid, so a child started there would be orphaned); **the child
  never touches the .md** — the answer comes back in memory and goes in
  through the editor bridge, so ⌘Z takes it out the way it takes out the
  words read off a picture; and **a shell fence is never run at all**,
  because the text of a fence is not evidence Sean typed it.
  `wl` STAYS MATHS: Wolfram code is ```wls, which was already a code
  fence, and nothing may ever be appended to a `wl` fence because
  `MathMarkup.isMathFence` compares the whole info string.
  ADDING AN ENVIRONMENT IS ADDING A ROW to `Evaluator` and nothing
  else: the tag, the badge, the colouring, the candidate paths, and —
  for a compiled one — `sourceFile` (the extension is what tells the
  compiler what it is reading) and `compileArguments`. `CellRunner` has
  TWO SHAPES, `isCompiled` or not, and no list of languages in it.
  rustc lives in `~/.cargo/bin`, which is the one place a list of
  system paths never looks, so `candidates` builds a home-relative
  path; and `Refusal.unknownEnvironment`'s sentence is GENERATED from
  `allCases`, because a hand-written "not Python, C++ or Wolfram" goes
  stale the first time the list changes.
  Wolfram needs `-code` and it needs HOME. `wolframscript <path>` opens
  an INTERACTIVE session and prints a banner; `-file` runs the file
  and shows no value; `-code` shows the value of the last expression,
  which is what an Out cell is for. And under a replaced environment
  with no HOME it prints NOTHING and exits 0 — the worst failure
  there is, because it looks like a cell that ran and had nothing to
  say. Both measured, 2026-09-21. Its stdin is the null device so
  that an unactivated engine asking for a Wolfram ID gets EOF and
  exits instead of hanging; the app never types into that prompt.
  **A CELL AND ITS ANSWER ARE ONE GROUP, AND THE GROUP IS DERIVED.**
  Sean, 2026-09-21: "input and output cells are grouped together".
  `EvalCells.groups(in:)` reads the pairs back off the blocks every
  time — a fenced cell with an `out` cell under it — so nothing is
  written into the note for it and nothing can go stale.
  **THE FENCE ABOVE IS NOT ASKED WHAT IT SAYS**, and one `answer(after:)`
  is the only reader of "the block below this one" so that the bracket,
  the re-run and `out(after:)` cannot drift apart. Only
  `EvalOutput.cell(for:)` writes an `out` fence anywhere in this app, so
  a cell with one under it HAS been run — and every pair in Sean's notes
  from before the `eval ` fence existed is written ```python, so asking
  `Evaluator.isEvaluation` as well meant the pairs he was looking at were
  not pairs (Sean, 2026-09-22: "input and output cells still don't appear
  to be grouped"). It steps over the blank cells in the gap, too: three
  empty lines are a `.blank` block of the note's own, and Return pressed
  twice under a cell used to hide its answer from it — a re-run then
  piled a SECOND answer on instead of replacing the first. Both panes draw a bracket at the pair's own depth over
  `group.range` and push each member cell to `depth + 1`
  (`EvalCells.isGrouped`); it is not a section, it folds nothing and
  it nests nothing. And the run ENDS WITH THE BAR under the answer
  (Sean, same day: "after evaluating a cell, the text cursor should
  become a horizontal bar after the output") —
  `EditorBridge.armBar(after:in:)`, which is the one write an
  evaluation makes that DOES take the caret, against `writeCell`,
  which must never steal focus because it can land while somebody is
  typing somewhere else. In the source pane the selection is set
  BEFORE `armedSeam` — and the caret goes on the BLANK LINE under the
  answer (`EvalCells.caret(under:in:)`), where a click would have put
  it, not at the start of the cell below: `CellSeams.arm` reads the
  caret, so that is the one writer, and a caret parked in the next cell
  armed the right bar while every other reader of "the caret is in that
  cell" answered for the wrong one — `updateHiddenMarkers` is asked on
  the way past and brought a heading's `## ` back every time a cell
  finished. The rendered page arms its own seam through
  `armBarInDocument`, and that one SCROLLS: a bar no gesture put there
  is wherever the answer ended, and an answer is written whole. Two
  things make it harder than it sounds, both measured 2026-09-22 —
  the row does not exist yet when the answer is written, so a
  `ScrollViewProxy` asked in `armSeam` scrolls to nothing at all
  (`bringIntoView` waits for `onChange` and a beat after it); and a row
  TALLER THAN THE WINDOW cannot be scrolled to its `.bottom`, which
  clamps to keeping its top in view and does not move. The seams carry
  their own ids and the page is scrolled to the SEAM. **And only when it
  has to** (Sean, 2026-09-22: "make the cursor behavior after evaluating
  a cell elegant"): `PreviewLayout.onScreen` is asked first, with a
  margin off each edge, because the answer to `2 + 2` is one line and
  jerking the note under somebody already looking at the right place is
  the opposite of what the scroll is for — the source pane has had this
  for nothing all along, since `scrollRangeToVisible` moves by the least
  it can. When it does move it is carried and not jumped: a short
  `easeOut`, landing the seam 0.8 down the page rather than centred,
  because what has just been made is above it.
  **A HOVER IN THE GUTTER PROMISES WHAT A CLICK WOULD TAKE.** Sean,
  2026-09-22: "hovering over sections on the right side should faintly
  indicate what would be selected if clicked". Both gutters report
  `CellSelection.cells(of:in:)` for the bracket under the pointer —
  `onHoverCells`, the SAME call `mouseDown`/`click` makes, so the
  promise and the press cannot disagree — and the cells are washed at
  `controlAccentColor` 0.12. It is painted over the WORDS and not in the
  column: `CellInsertions.wash` in the source pane (that layer already
  has the cells' boxes, and it draws under the bars, which are cursors
  and must keep reading as such), an overlay on the row in the rendered
  page.
  **A BRACKET IS ONE OF THREE THINGS**, and `!foldable` is not how to
  ask which. `Bracket.isCell` is — a section folds, a cell is a block,
  a group embraces an In/Out pair — because `cellSpans`, `cellRanges`
  and `picked` in BOTH gutters read "is this a cell" and counted the
  pair's own bracket as one. A group also has to LOOK like one: its top
  and bottom are exactly its members', so at the same length it read as
  a doubled hairline rather than as something round them, and it is
  drawn `overhang` proud at each end and at a section's weight. The
  drawn depth is CLAMPED to the column (`deepest`): six heading levels
  plus a group is more nesting than 22 points of gutter can hold, and a
  bracket past the left edge is not drawn at all.
  **THE NEAREST CELL, NOT THE FIRST.** `EvalCells.landing(of:in:startedAt:)`
  re-finds the cell that ran by its own text — the note is editable
  while it runs — and breaks a tie with the offset the run started
  from, because ⌘D makes two cells with identical text in one keystroke
  and first-wins put the answer under the copy ABOVE the one that ran.
  And an UNCLOSED fence is refused: `MarkdownFormatting.fenced` hands
  back an empty `close` rather than nil for one, the parser runs such a
  block to the end of the note, and the answer pasted after it closed
  the cell it was meant to sit under.

## How it is wired

```
WriteMind/
  WriteMindApp.swift      @main; the window; the menus — File > New Note,
                          View > sidebar / preview toggles, and the
                          "Input Devices" menu (InputDevicesMenu) listing
                          every camera with a checkmark on the live one,
                          and under them any Wacom tablet plugged in
  AppState.swift          UI state: sidebar shown, editor/preview mode, pen
                          on/off, pen width, colour and tablet tool, the
                          tablet page's own pen, where the tablet writes
                          (all persisted), and the EditorBridge the
                          toolbar talks through
  TestHost.swift          the unit-test host keeps out of ~/Documents
                          and off the camera
  Notes/Note.swift        a row: url, modified, title (first # heading, else
                          the file name), a two-line snippet
  Notes/NoteStore.swift   ~/Documents/WriteMind: the list, the open note's
                          text and drawing, debounced autosave, a
                          DispatchSource watch on the folder so an edit in
                          another app shows up, new/rename/trash
  Camera/CameraController.swift
                          AVCaptureDevice discovery (built-in, external,
                          Continuity, Desk View), the session, permission,
                          select/turn off, hot-plug refresh
  Camera/CameraPreview.swift
                          AVCaptureVideoPreviewLayer in an NSView
  Camera/TextRecognition.swift
                          the words in a picture, by Vision, as lines in
                          reading order — flattened on white first, since a
                          captured chunk of writing is ink on nothing; what
                          is read with little confidence or is not mostly
                          letters (a doodle, the dot grid) is dropped
  Camera/NotebookCapture.swift
                          a notebook page off the camera: Vision finds the
                          page (document segmentation, then rectangles),
                          CIPerspectiveCorrection squares it, PageShape
                          trims its edge and resamples it to one remembered
                          size, and then Mode.page keeps the photo (a JPEG)
                          while Mode.ink keeps the writing — a local-mean
                          threshold keeps what is darker than the paper round
                          it, and connected-component filtering drops the
                          printed dots and the page edge. A `region` (a box
                          drawn on the video pane) goes through Homography —
                          the perspective, inverted — to its box on the
                          page. Placement puts the result where it was on
                          the page, at the page's scale. The mask, shape,
                          homography and placement maths are pure and tested
  Editor/MarkdownTextView.swift
                          the NSTextView (plain text; smart quotes and dashes
                          OFF because they corrupt markdown; spelling on).
                          Return at the end of a list item carries the list
                          on (EditorBridge.continueList)
  Editor/BulletGlyphs.swift
                          `- ` drawn as a round bullet: a TextKit 1 layout
                          delegate swaps the dash's glyph, the file keeps the
                          dash
  Editor/MarkdownFormatting.swift
                          toggleWrap / toggleBullets — pure, tested
  Editor/EditorBridge.swift
                          applies an Edit through the text view (undo-safe)
  Editor/MarkdownBlocks.swift
                          MarkdownParser (headings, paragraphs, bullets,
                          numbered, quotes, fenced code, rules) and
                          MarkdownInline (Foundation's inline markdown + <u>)
  Editor/MarkdownPreview.swift
                          the rendered view, block by block — and the editor
                          on that side: click a block and it opens in a
                          BlockEditor; the gap between two blocks adds one;
                          Return splits, ⌫ in an empty block removes it, the
                          arrows walk between blocks. Every keystroke goes
                          straight into the note at the block's own range
  Editor/BlockEditor.swift
                          one block in a real NSTextView, sized to its text,
                          handed to the EditorBridge so the whole bar works
                          on it. Return in a list carries the list on
  Editor/PreviewEditing.swift
                          the document surgery — insert, split, remove, list
                          continuation. Pure, tested
  Editor/Insertion.swift  where ⌘8's, ⌘9's and the maths palette's block
                          goes and what it holds, as one edit or a
                          refusal — both panes. Pure, tested

  Editor/PaneMapping.swift
                          a point on one pane on the other, through the
                          cells both have (PaneMapping), and the top of the
                          window as a cell and how far into it (CellPlace).
                          Pure, tested
  Editor/PaneCaret.swift  the cursor ⌘T carries: a caret, cells held, or the
                          bar; read off one pane, opened on the other. Pure
  Drawing/DrawingPanes.swift
                          the drawing shown on the rendered page and written
                          back: items whole, groups as one, connectors point
                          by point (Drawing.shown, Drawing.stored)
  Editor/MarkdownSourceStyle.swift
                          the block's markdown styled as it is typed: markers
                          fade, bold is bold, headings are their size, maths
                          and links are coloured. Runs are pure and tested
  Drawing/Drawing.swift   the objects on the drawing layer: Stroke
                          (normalised 0…1 points, hex colour, width, and
                          for ink a pressure per point and the tool),
                          ImageItem (a file in .drawings/media, its centre,
                          its width as a fraction of the pane, its aspect),
                          ItemTransform (dx/dy as fractions, scale, rotation),
                          CanvasItem, Drawing, and DrawingStore — the sidecar,
                          the pictures, and the sweep of the ones no note
                          points at any more
  Drawing/Shapes.swift    ShapeItem (nodes and marks: unit outlines, paths)
                          and ConnectorItem (arrows: heads, line style,
                          attachments)
  Drawing/DrawingGeometry.swift
                          where an object actually is: base points, the
                          matrix (rotate and scale about its own centre IN
                          VIEW POINTS, then translate), hit testing on the
                          ink, marquee intersection (touching is enough), and
                          CanvasEdit — the move/scale/rotate maths a group and
                          a single object share. Pure, and tested
  Drawing/DrawingCanvas.swift
                          the layer: one Canvas, plus the handles. With the
                          pen up it takes the whole pane and draws; with the
                          pen down its contentShape is only the objects, so
                          every other click reaches the text. ⌘ makes the
                          whole pane a marquee
  Drawing/CursorLayer.swift
                          the pencil (and open/closed hand) cursor, as a real
                          AppKit cursor rect over the text view — mounted
                          only while the layer has a cursor of its own;
                          `region` and `claim` (whose pointer it is)
  Drawing/InkPaths.swift  the ONE geometry source for a stroke and a
                          connector, on screen and on paper: the legacy
                          line, or ink's filled outline (InkCache keeps it
                          per stroke)
  Drawing/InkOutline.swift
                          perfect-freehand 1.2.3 ported line for line (MIT,
                          Steve Ruiz): samples with pressure in, the outline
                          of a stroke whose width follows them out, and the
                          path through its midpoints. Pure; pinned against
                          the original's own numbers
  Drawing/InkTool.swift   pen, fountain pen, pencil, marker, brush — each an
                          option set and an opacity, calibrated so a line at
                          an ordinary press is the slider's width, and a
                          name and an icon for the picker; `outline` is the
                          one way from samples to ink, where a tap becomes
                          a dot and no stroke comes out a sliver
  Drawing/PenSample.swift the nib's pressure off every left-mouse event whose
                          subtype is a tablet's, by a local monitor that
                          hands each event back as it came
  Notes/MarkdownLinking.swift
                          `/link`: the trigger, the anchors (mark / heading
                          slug / <a id>), and the markdown a link is made of
  Editor/MarkdownSpans.swift
                          <span style> on the selection, and ⌘D's search
  Math/WLExpression.swift Wolfram Language — the canonical form maths is kept
                          in (Sean, 2026-09-18). WLParser reads it, WLPrinter
                          writes it back in one spelling
  Math/MathTypesetter.swift
                          the glyph tables (Pi → π, \[Alpha] → α, Sin → sin)
                          and inline maths as an AttributedString with real
                          raised and lowered scripts
  Math/MathView.swift     maths on its own line, in two dimensions: stacked
                          fractions, ∑ with its bounds, √ with its roof
  Math/MathTemplates.swift
                          the palette — every entry writes WL with #1, #2 …
                          filled in from its fields
  Math/MathSelection.swift
                          whether a selection reads as maths (the palette
                          opens with it) and whether maths still holds it
  Views/ContentView.swift top bar over [sidebar | HSplitView(editor, camera)]
  Views/TopBar.swift      text style menu (the heading ladder) · B I U ·
                          bullets · quote · code block · T · outdent/indent ·
                          maths ·
                          image · shapes · marks · capture · pen · the
                          preview toggle. 11pt icons in 22pt squares, one
                          point apart; a control with a menu carries its
                          chevron inside itself (SplitBarControl). Plus the
                          show-sidebar button, which appears here only while
                          the sidebar is hidden — the HIDE button is on the
                          sidebar itself (Sean, 2026-09-18)
  Views/PenMenu.swift     the popover under the pen: the tool a tablet's nib
                          writes with, size slider, circular ColorPicker
                          plus six preset swatches, undo/redo of anything
                          that happened on the layer, clear, Add Image, and
                          how to get hold of an object
  Views/PenControls.swift the pen's controls, one view each, for the
                          notebook's pen and the page's: InkToolPicker (a
                          button a tool, its icon over its name), the size
                          row, the colour row
  Views/TextStyleMenu.swift
                          the T popover: font, size, colour, and which of the
                          three the span actually carries
  Views/LinkBanner.swift  "Select section to point to", up until the target
                          is picked or the user backs out
  Notes/NoteTree.swift    NoteSection (a folder), the recursive read, and
                          NoteOrder (.writemind/order.json)
  Notes/Project.swift     the .writemind-project file and the cached session
  Notes/ProjectStore.swift
                          the open project: folders, its file, save/open
  Views/TabBar.swift      the open notes, the one in front lit, shown even
                          with nothing open; ⌘W closes a tab rather than
                          the window, a middle click too. The
                          wheel walks along the row a tab at a time, the +
                          tab at the end is New Note, and the button on the
                          right lists everything open (Sean, 2026-09-18)
  Views/MathMenu.swift    the maths dropdown: one scrolling pane of shapes,
                          the fields for the one picked, the WL it writes
                          (editable), and how it will be set
  Views/SidebarView.swift the tree, flattened to the rows that show; the
                          video toggle, edit mode (duplicate and trash on
                          every row — the trash arms red on one click and
                          acts on the next, no dialog), new section, new
                          note; drag to move a note or a section into
                          another section
  Views/EditorPane.swift  editor or preview with the DrawingCanvas over it,
                          the tablet's layer over that, and a status line
                          (file, words, saved time); PaneFrames, the two
                          panes' cells and the drawing shown between them
  Views/NotebookTabletLayer.swift
                          the tablet writing in the note: its live stroke
                          and marquee, the area's outline and the hover
                          marker while the pen is near; the notes pane's
                          word to the tablet (on screen, where, which pen)
  Views/ShapeMenu.swift   the Shapes popover (nodes, the arrow tool) and the
                          Marks popover (checks, crosses, stars, arrows),
                          laid out from `CanvasPlacement.flowChart` and
                          `marks`, the lists the bar lights its buttons by
  Views/CameraPane.swift  the preview, or a placeholder that says why not;
                          rotate buttons and the section selector (drag a
                          box, then Writing or Page)
  Views/TabletPane.swift  the same pane when a tablet is the input: the page
                          at the tablet's turned shape, the hover marker,
                          the page's undo, redo and clear, how the tablet
                          sits (TabletOrientationButton: the tablet drawn
                          the way it lies, its light where the light is,
                          its popover the four by name;
                          every turn handed to TabletScribe.align), the
                          bar, the one line about the pen, and the page
                          set aside while the pen writes in the notebook
  Views/TabletStatusLine.swift
                          that one line's words, pure: pen captured, or
                          why the pen also moves the pointer and the one
                          thing to do about it (Input Monitoring, quit
                          and reopen, IOKit's number)
  Views/TabletBar.swift   the bar top left of the page: Write on: Page |
                          Notebook (TabletTargetSwitch), then the page's
                          pen (its ink on a chip of the paper, InkChip;
                          its popover: tool, size, colour) and its paper
                          (a menu of papers, a swatch each, PaperSwatch),
                          in the first of its shapes that fits; setAside;
                          PickList and PickRow, the one picker popover the
                          paper's and the turn's are both built from, each
                          as wide as its rows' words need
  Views/TabletPageView.swift
                          the sheet's layers, each at its own rate: the
                          paper and what its theme prints, the finished
                          ink (Equatable), the stroke
                          being written, and the box — SectionBox itself
  Views/InputDevicePicker.swift
                          the pane's copy of the Input Devices list
  Tablet/TabletCapture.swift
                          WriteMind taking the tablet itself:
                          WacomPenPacket (one raw report read, pure),
                          TabletCapture (when to ask, seize and release —
                          a value, pure), the TabletHID protocol, and
                          LiveTabletHID — Input Monitoring and the HID
                          device opened to seize, refusing under TestHost
  Tablet/TabletController.swift
                          the tablets on the USB bus (IOKit notices), the
                          pick, and TabletCapture's shell: the three
                          conditions gathered, its commands carried out,
                          the reports turned into readings, the status;
                          InputDevices.pick for both kinds of input
  Tablet/TabletInput.swift
                          the pen from both routes through one funnel:
                          the tablet's size in counts and millimetres,
                          the reading of an event, counts to the turned
                          page, the pen's state, the sample stream, the
                          raw route and the driver's events ignored
                          while it delivers, and whether its target is
                          on screen
  Tablet/TabletOrientation.swift
                          how the tablet sits, by Wacom's four names, as
                          quarter turns; where its status light is (one
                          point on the tablet as it ships, through the
                          pen's own turn); and TabletGlyph, the tablet
                          drawn that way round with the light lit
  Tablet/TabletPage.swift the page: strokes in page fractions and page
                          points, its paper, undo/redo/clear, the ink
                          (and a box) turned with the sheet, the file in
                          Application Support (a bad one set aside, never
                          wiped)
  Tablet/PageTheme.swift  the papers: each one's colour, its ink, what it
                          prints in the tablet's millimetres (layout,
                          pure and tested) and the one printer for the
                          pane and a picture; the readability rule
  Tablet/TabletWriting.swift
                          samples to ink and boxes (TabletWriting, pure),
                          TabletInk, TabletBox, and TabletScribe — the one
                          consumer of the samples, which picks the target
  Tablet/TabletNotebook.swift
                          the pen's other target: TabletTarget, the
                          tablet fitted onto the notes
                          (NotebookPlace, pure), samples to the note's
                          strokes and the marquee (NotebookWriting, pure),
                          and NotebookScribe, its shell
  Tablet/TabletSelection.swift
                          what a box touches, Writing re-expressed on the
                          notebook, and TabletRender: the page as a
                          picture, the ink black on white for Text
  Support/Color+Hex.swift #RRGGBB both ways
  Assets.xcassets/AppIcon.appiconset
                          every size of the icon, RENDERED — never edited —
                          by tools/make-icons.sh from assets/logo-square.svg
WriteMindTests/           XCTest, @testable import WriteMind
assets/                   logo.svg — the WM mark, the family's one-stroke
                          monogram (CalMind CM, AcctMind AM) in ink blue;
                          logo-square.svg, the full-bleed cut for the icon;
                          logo-512.png for the README
tools/                    build.sh run.sh test.sh (both source signing.sh)
                          setup-signing.sh make-icons.sh build-platforms.sh
                          smoke.sh deploy.sh dtp.sh tdtp.sh
```

- **Shortcuts**: ⌘N new note · ⌃⌘S sidebar · ⌃⌘E notes pane · ⌃⌘C camera
  pane · ⇧⌘P editor/preview · ⌘B ⌘I ⌘U · ⇧⌘X strikethrough · ⇧⌘L the list
  (dots, dashes or numbers, whichever the chevron picked) · ⌃⌘Q quote ·
  ⌘[ ⌘] outdent/indent (⇥ and ⇧⇥ too) · ⌘1–⌘7 the heading ladder (title,
  chapter, author, section, subsection, subsubsection, body) · ⌘8 code
  block · ⌘9 evaluation cell · ⌃⌘↑/↓ move section · ⌃G group/ungroup what is picked on the
  drawing layer · ⌥⌘Z / ⇧⌥⌘Z undo and redo the
  DRAWING (⌘Z does it too while the pen is up; ⌘Z and ⇧⌘Z are the
  tablet page's straight after the pen wrote on it; a click of the tablet
  pen's lower button, nib off the tablet, is undo and of its upper button
  redo — the page's in Page mode, the note's drawing's in Notebook mode) ·
  ⌘D select next occurrence,
  ⌃⌘G all of them · ⌥⌘R refresh cameras · ⇧⌘O open the notes folder.
- **EVERY FORMATTING SHORTCUT LIVES IN THE FORMAT MENU**, not on the toolbar
  button that does the same thing. A button inside a collapsed section of the
  bar is not in the view tree, and a `.keyboardShortcut` attached to it stops
  working the moment that section is put away (Sean, 2026-09-19: "each
  section of the toolbar should be collapsable"). `FormatMenu` in
  WriteMindApp.swift is the one place they are declared; the buttons carry
  the keys in their tooltips only.
- **The toolbar is sections, and a section can be put away.** `ToolGroup`
  (Style, Structure, Insert, Maths, Flow Chart, Capture — maths and flow
  charts are their own, Sean 2026-09-19: "basically completely separate
  things"); `BarGroup` draws one, the grip at its end collapses it, the
  bar's context menu lists them all, and `AppState.collapsedToolGroups`
  remembers. Tooltips are the app's own (`BarTip`, an anchor preference
  hosted by the bar), not `.help()`: they appear after a beat and then keep
  up with the pointer. `.help()` is still what `BarButton` uses OUTSIDE the
  bar — the sidebar header — through `\.barTipsEnabled`.
- **Colours are given twice, light and dark.** `CodeColours.pair(light:dark:)`
  builds an `NSColor` that answers the appearance it is asked in. Nothing
  that carries text uses `controlAccentColor`: the accent can be yellow, and
  yellow on white is not text (Sean, 2026-09-19: "be mindful of text color").
- **A missing SF Symbol draws NOTHING.** `parallelogram` is macOS 15's, and
  on 14 the palette button came out blank (2026-09-19). `SymbolTests` walks
  every shape, tool group and list style and fails on a name this macOS does
  not have; add new icons to it.
- **Folding is a typesetter, not an edit.** A closed notebook section is
  laid out with zero-height line fragments (`FoldingTypesetter`) and not
  drawn (`FoldingLayoutManager`) — the note's text is never touched, so
  nothing can be lost by collapsing. `NotebookOutline` works out the
  sections and their keys (the heading's words, plus an ordinal for
  repeats), `NoteStore.collapsedSections` remembers them per note and
  `ProjectSession` persists them. The caret is snapped out of a hidden range
  and an edit that would reach into one opens the section instead.
- **A flow-chart line is routed, and the route is baked in.**
  `Drawing.reconnect(in:)` runs `ConnectorRouting.path` for every connector
  with an end on a node and stores the corners in `ConnectorItem.bends`, so
  drawing, hit testing and the handles all read one list of points. The
  router tries all four sides by all four sides and takes the fewest corners,
  then the shortest; a path that crosses a node is not a candidate, and the
  detours are only reached when nothing direct is clear. A segment dragged by
  hand becomes a `SegmentOverride` that survives re-routing. reconnect only
  writes an item back when it CHANGED — it runs on every layout pass, and an
  unconditional assignment would schedule a save each time.
- **The top bar is a view inside the editor pane, not an NSToolbar.** Sean,
  2026-09-18: "menubar should only be on the edit text pane" — it sits over
  the text (and over the preview, and over the empty state), never across the
  sidebar or the camera, and is "always there" whatever the columns do.
- **Every launch comes up side by side.** `AppState.init` sets `showEditor`
  and `showCamera` to true whatever the defaults hold (Sean, 2026-09-19:
  "default video always to side by side"). Hiding a pane is a gesture for a
  minute, not a preference — and a launch that came up with the video hidden
  cost him a hunt for the way back. The keys are still written on every
  toggle; they are simply not read at startup.
- **EVERY BUTTON HAS EXACTLY ONE PLACE.** Sean, 2026-09-19: "there should
  only be one show/hide button for the video feed.. do an audit of the
  placement of all buttons in the app and clean it up". The rule that came
  out of that audit: **a pane's switch lives on a DIFFERENT pane, once** —
  because a switch on the pane it hides cannot bring it back.
  - the VIDEO's switch: the editor's bar, right of the preview button, and
    nowhere else (it used to be in the sidebar header too — removed).
  - the NOTES pane's switch: the video's top-right corner.
  - the SIDEBAR's: its own header, with the way back on the editor's bar,
    shown only while the sidebar is hidden — the two are never both up.
  - ⌃⌘S / ⌃⌘E / ⌃⌘C in the View menu for all three. A MENU item is not a
    second button; a second button on screen is.
  - the video's switch is the PAGE'S while the tablet is the input — one
    pane, two faces — and says so: the button, its View menu item, the
    panel under its chevron and the whole-window × take their words from
    `InputSource.words`, and the panel drops the camera's own rows (the
    page turns in its own corner).
  Moved 2026-09-21, on Sean's word ("move the markdown toggle and video
  button to the menubar above the sidebar"): the MARKDOWN toggle and the
  VIDEO switch are on the SIDEBAR's bar now, which reads edit · add
  section · separator · markdown · video. The rule is unchanged and the
  move obeys it better — neither switch is on the pane it governs.
  New Note left that bar altogether: it is `SidebarRow.add`, a
  note-shaped row with a + in it at the top of the list and at the top
  of every section, so the way to make a note is where the note will
  land. The duplicate that stays is the `+` tab and ⌘N.
  The rest of the inventory, so the next audit has a baseline: sidebar
  header (collapse, edit, new section, new note); sidebar row in edit mode
  (duplicate, trash); sidebar footer (the Folder menu); the tab bar (tabs,
  `+`, the overflow list); the editor bar (the six ToolGroups, then preview
  and video); the video's corner (select section, zoom, fit-when-zoomed,
  rotate left, rotate right, notes pane); the tablet page's corner
  (undo, redo, clear — in play only while the pen writes on the page —
  how the tablet sits, the four by name, in play in both modes, notes
  pane), its bar on the other side (Write on: Page | Notebook, mirrored
  in the View menu with no key, then the page's pen and its paper — the
  same proviso) and its box (Image, Writing, Text — the video's own
  three); the drawing layer's handles (rotate, scale, move, trash, and
  per-kind: crop and read for a picture, style for a connector, a circle
  per segment for a routed one).
- **A recursive SwiftUI view cannot be type-checked** — "opaque return type
  was inferred in terms of itself". The sidebar builds `[SidebarRow]` first
  and draws a flat ForEach; a tree that draws itself by recursion does not
  compile, and flattening is faster anyway.
- **The sidebar is a plain HStack child**, shown or hidden with a transition,
  rather than a NavigationSplitView column — the split view owns its own
  toolbar and collapse gestures, and the bar above has to stay put.

## Traps that have cost real time here

- **The Wacom driver's dimensions are ORIENTED; the pen's counts are
  not.** Asked for the tablet's size the driver answers in whatever
  orientation ITS OWN setting has — on Sean's Mac, set to portrait, Xdim
  9499 × Ydim 15199 — while the counts the pen sends, by NSEvent
  `absoluteX/Y` and by raw report alike, stay in the RAW LANDSCAPE frame
  (x was seen up to 13217, past that "width"). WriteMind took the
  driver's answer as the extent and then turned it again by its own
  quarter turn: every stroke landed in the wrong place on a page of the
  wrong shape (2026-10-02). The extent is the raw sensor's — the table
  by product id, widened by what the pen reaches (`TabletExtent.known`)
  — and the driver is never asked. The same goes for anything else it
  reports about geometry: its mapping and orientation are its own
  business, upstream of nothing WriteMind reads.
- **A LEGACY SCROLLER TAKES 17 POINTS OF THE TEXT.** With a mouse plugged
  in macOS shows legacy scrollers, and the markdown pane's scroller hides
  itself only while the note fits: beside a long note the text view is the
  pane less 17 points (measured 2026-10-02, a 600-point pane's clip view
  583 wide), and a layout made at the pane's width wraps somewhere else.
  `MarkdownTextView.cellBoxes(of:pane:…)` lays out at the narrower width
  when the note is taller than the pane and the scrollers are legacy.
- **A SCROLL VIEW MOVED BY HAND IS NOT ONE SWIFTUI MOVED.** The rendered
  page opens at its place by scrolling its own NSScrollView's clip view
  (`MarkdownPreview.openAtPlace`); in a window off the screen its scroll
  preference never followed, so the drawing layer would have been told 0
  with the page a screen down. It says where it went itself. The mark it
  scrolls to is moved by state, so it is read a turn after the update
  that moved it (`onChange(of: openingY)`) — read in the same breath it
  is where it WAS — and the rows' heights can arrive BEFORE `onAppear`
  (measured: a place asked for in `onAppear` alone was never put back),
  so both ask.
- **IOKit's HID open asks for Input Monitoring by itself.** A HID device
  that is a keyboard, a mouse or a touchpad to macOS carries
  `RequiresTCCAuthorization`, and `IOHIDDeviceOpen` on one calls
  `IOHIDRequestAccess` on its way in — a prompt, if nobody has answered.
  The Wacom's pen interface is a mouse. So "a first launch never asks"
  is kept by never opening it until `IOHIDCheckAccess` reads granted
  (`TabletCapture.changed`), not by being careful about when the ask is
  made.
- **A USB device is not found by its vendor alone.** `IOServiceMatching(
  "IOUSBHostDevice")` with a bare `idVendor` is read by the USB family's
  own matching rules, which want a vendor AND a product (or a class), and
  it matched NOTHING — the One by Wacom plugged into Sean's Mac was never
  listed, so there was no page to pick (Sean, 2026-10-02: "i don't see
  the wacom page"). Put the vendor in `IOPropertyMatch`
  (`TabletController.usbMatching`); `TabletUSBMatchingTests` finds every
  USB device on the machine by its vendor alone.

- **`@Published` fires in `willSet`.** Inside a `$selection.sink`,
  `self.selection` is still the OLD note. The first cut of `NoteStore` saved
  the outgoing note correctly and then re-loaded it instead of the new one.
  The sink uses the value the publisher hands it; `loadText(for:)` takes an
  id for exactly this reason.
- **A SwiftUI patch that asserts its way through several files can leave the
  tree half-edited.** Two changes here were written into some files and not
  others because a later `assert old in s` failed and the earlier writes had
  already landed — the camera-pane button went missing from the bar that way
  and was only caught by reading the app's accessibility tree, not by the
  build, which was perfectly happy. Check the thing you added is actually
  there.
- **A `Codable` default value is not a decoding default.** The synthesized
  `init(from:)` ignores `= ItemTransform()` and fails on a sidecar written
  before that property existed — and `DrawingStore.load` turns a decode
  failure into an empty drawing, so old drawings would have silently
  vanished. `Stroke`, `ImageItem` and `Drawing` decode by hand, with
  `decodeIfPresent`, and `Drawing` still reads the old `strokes` array.
- **A pushed `NSCursor` loses to the text view.** `NSTextView` sets the
  I-beam from its own tracking area on every mouse move, so `.onHover` +
  `NSCursor.push()` flickered straight back to a text cursor — which is why
  the pen had no pencil. `CursorLayer` is an AppKit view above it with a real
  cursor rect (and a tracking area as the belt to those braces), and
  `hitTest` returning nil so it never takes a click — and mounted only while
  it has a cursor of its own, because a hosted view over the pane is what
  every cursorUpdate there is routed to (the eighth cause below).
- **Being ABOVE the text view does not win the cursor either.** The seam
  layer had a cursor rect, a `cursorUpdate` and a `mouseMoved` of its own
  and the pointer over an armed bar was still the upright I-beam (Sean,
  2026-09-20: "the mouse cursor should reliably be horizontal between the
  cells"): the text view's OWN tracking areas hand it the same moves
  whoever is on top, a cursorUpdate goes to whichever view the window's
  hit test finds at the pointer — the text view, on a seam's sticky edge
  (the eighth cause, below) — and two cursor rects over one point is
  AppKit's choice to make — it chose the text view's. The pencil settled this by
  taking the text view's tracking areas away; a seam cannot, because the
  text either side of it still wants its I-beam. So the text view is
  told: `PasteAwareTextView` asks `CellInsertions.pointerSeams` — the
  layer's own seams, never a second copy of the geometry — answers
  `cursorUpdate` and `mouseMoved` over a seam with the horizontal I-beam,
  and cuts its cursor rects into `CellSeams.bands` so that no rect of its
  own ever covers a seam in the first place.
- **A CURSOR RECT IS THE WRONG MECHANISM; A TRACKING AREA IS THE RIGHT
  ONE.** The bar's cursor was right "in most of the right spots" and
  dropped back to the I-beam now and then (Sean, 2026-09-20: "it does
  flicker sometimes back to a cursor"). Four causes, none of them the
  whole of it:
  1. **Rects are torn down and rebuilt; a tracking area is not.**
     `invalidateCursorRects` discards the set, and until
     `resetCursorRects` runs again there is no rect of ours under the
     pointer at all — the text view's I-beam is what is left. The seam
     layer's tracking area now carries `.cursorUpdate`, so it owns the
     cursor across every rebuild and the rects are the belt to those
     braces rather than the mechanism.
  2. **An idle re-measure counted as a move.** `refreshBrackets` measures
     the seams off the text layout on every keystroke, every caret move,
     every restyle (which invalidates the layout of the WHOLE note) and
     every scroll, and `seams` invalidated both views' rects whenever any
     float differed. `CellSeams.moved` compares with half a point of
     tolerance and `CellInsertions.measure` keeps the old seams when
     nothing has really moved, so a page sitting still tears nothing
     down. `seams` is `private(set)` to keep that the only way in.
  3. **Two views answering one point separately.** The layer said "a
     seam is the horizontal I-beam" and the text view said it too, which
     was the same answer until the + wanted a hand. Both now call
     `CellInsertions.cursor(at:)`, and the text view cuts the +'s patch
     out of its own rects (`CellSeams.cut`) instead of laying one over
     the other.
  4. **NSTextView answers a mouseEntered with the I-beam, and AppKit
     synthesises one whenever the tracking areas are rebuilt under a
     pointer that never moved** — every scroll, every relayout. Nothing
     follows it until the pointer moves, so the bar sat under an upright
     cursor until it was nudged. `PasteAwareTextView.mouseEntered` and
     the tail of its `updateTrackingAreas` put the seam's cursor back;
     `CellInsertions.mouseEntered` does the same for the layer. **Only
     for a pointer that is on the page**, though, and that is the trap
     inside the answer: `mouseLocationOutsideOfEventStream` is a WINDOW
     location and AppKit gives it wherever the pointer is, `NSCursor.set()`
     is global, and the sidebar and the toolbar install no cursor of
     their own to take one back. Every seam runs to the left edge and the
     tail is most of a short note, so a pointer parked on the sidebar
     converted to a negative x inside a seam and went horizontal there.
     Two checks: `visibleRect.contains` at the call (`bounds` is not
     enough — the text view is the scroll view's document view, so the
     formatting bar above the pane maps into the note as soon as it is
     scrolled), and `CellInsertions.seam(at:)` answering nothing for a
     point that is not on the layer at all.
  A SIXTH, and the one that survived all of the above: the two
  mechanisms meet on a seam's own EDGE and answered differently there.
  The rects can only be drawn on pixel edges; the point test read the
  same seam as a float. A pointer moving slowly across the boundary
  therefore got each answer in turn (Sean, 2026-09-21: "cursor still
  flickers between horizontal and vertical… it's while the mouse is
  moving slowly"). Neither answer was wrong — they were not the SAME
  answer at the same place. So `CellSeams.pixels` snaps a seam's edges
  out to whole pixels and BOTH `bands` and the point test read those,
  and `CellSeams.pointerSeam` makes the pointer's reading sticky: the
  seam it is already being shown in keeps it until it is two points
  clear. Sticky for the CURSOR only — a click still asks the exact
  `seam(at:)`, because arming the wrong seam is worse than a flicker.
  A SEVENTH, and the one that was actually left: TWO CURSORS PER
  EVENT. `PasteAwareTextView.mouseMoved` called `super` first and then
  set the bar's cursor — and NSTextView's own `mouseMoved` sets the
  I-beam, so every single move event put an upright cursor up and then
  a horizontal one over it. At the rate a moving pointer generates
  events the first of them is on screen long enough to see, which is
  why it looked like a flicker and why it did not depend on where in
  the seam the pointer was: Sean, 2026-09-21, "even side to side it
  flickers". ASK FIRST, and do not call super at all when the answer is
  ours — for `mouseMoved` and for `mouseEntered` both. Nothing is lost:
  over a seam there is no text for NSTextView's handler to do anything
  with.
  AN EIGHTH, and the one under all of them: A CURSORUPDATE GOES WHERE THE
  WINDOW'S HIT TEST SAYS, AND WHILE ONE IS CURRENT SWIFTUI ANSWERS THAT
  HIT TEST WITH THE TOPMOST NSVIEW IT HOSTS. AppKit does not hand a
  cursorUpdate to the view whose tracking area made it:
  `_routeCursorUpdateEvent` hit-tests the window's frame view at
  `mouseLocationOutsideOfEventStream` and sends `cursorUpdate:` to
  whatever answers. And with a cursorUpdate as the current event the
  hosting view answers with the topmost NSView it hosts at that point
  WHATEVER that view's own `hitTest` says — `.allowsHitTesting(false)`
  does not stop it and neither does `hitTest → nil` (`.hidden()` and a
  zero frame do; `isHidden`, `.opacity(0)` and `.disabled(true)` do
  not) — and the event goes to that view's HOST, not to the view, and up
  to the window, which puts the ARROW up. `CursorLayer` was mounted
  always, with no cursor in cursor mode, so it was that view for the
  whole pane: moves set the horizontal I-beam through the tracking-area
  owners, and every cursorUpdate — each rect edge crossed, each rebuild
  of the rects — set the arrow, so where the pointer ended up depended
  on which came last, which looked like x mattering (Sean, 2026-10-02:
  "the horizontal cursor stuff should work in markdown view mode").
  Measured that day on macOS 26.6.2 with `NSCursor.currentSystem`,
  AppKit's disassembly and hosted probes; and it is why 2026-09-22
  looked fixed — that check logged which of OUR handlers answered, and
  on this path none of them ran. What came out of it:
  - **Nothing hosted sits over the notebook unless it has a cursor of
    its own.** `DrawingCanvas` mounts `CursorLayer` only while the layer
    has one — the pencil, a crosshair, a hand on an object. A layer that
    IS mounted must swallow cursorUpdates in its monitor, as the pen's
    always has, because answered by routing they reach its host and the
    arrow. PUT UP under a still pointer it sets its cursor itself on
    the next turn, and only while the app is active, the window key and
    frontmost under the pointer — AppKit's own cursorUpdate for the new
    rects goes to the layer's host and comes out as the arrow (a probe
    with that set taken out showed the arrow); the text view's
    `updateNSView` no longer sets the pencil as well. TAKEN DOWN it does
    nothing: AppKit rebuilds the window's cursor rects as the view
    leaves and sends the owner of the rect now under the pointer a
    cursorUpdate, and that owner answers — the arrow it used to set
    there was this bug. Measured 2026-10-02 in a scratch copy driven
    from the View menu with the pointer held still on the tail seam
    (`NSCursor.currentSystem` polled: bar, pencil, bar; under
    `-NSDebugCursorRects` the cursorUpdates after "Stop Drawing" went to
    `CellInsertions`) and in a probe where nothing else changed. A
    cursorUpdate POSTED to the window is not routed at all — it carries
    no tracking area and reached no view; one was tried here and taken
    out.
  - **While a layer IS up, the pointer under it is the layer's.**
    `CursorRectView.claim(at:in:)` names the cursor of a layer over a
    window point, and the text view's, the seam layer's and the gutter's
    moves and entries ask it first and give the same answer — and light
    no seam and no bracket, because the press there is the canvas's.
    Their tracking areas still hand them every move, and a hand, a bar
    or an I-beam set between the monitor's two sets of the layer's
    cursor was two answers to one event (the seventh cause again) under
    the ⌘ crosshair, a hand on an object, and the pencil over the
    gutter, whose tracking area the pen never took (`LayerClaimTests`).
  - **A HOSTED VIEW'S `visibleRect` IS NOT CUT TO ITS BOUNDS.** Measured
    on 26.6.2: the note's layer had a visible rect from the bottom of
    the window to the top — over the formatting bar, the tab bar and the
    footer — and an infinite one in `viewWillMove(toWindow: nil)`, where
    its conversion from the window is also off by the rest of the pane.
    `CursorRectView.region` is `bounds ∩ visibleRect` and is what the
    monitor, the tracking area, the mount and `claim` read; as
    `visibleRect` it put the pencil up over the formatting bar
    (`CursorLayerRegionTests`).
  - **A cursorUpdate is answered at the POINTER, not at the event**
    (`NSView.routedPoint(of:)`, in CellInsertions.swift): the event's
    location can be a move behind the point AppKit routed by, and a
    handler reading it answers for a place the pointer has left. The
    text view, the seam layer and the gutter all read the pointer; moves
    still read their event.
  - **Every view a cursorUpdate can reach answers it, from the region's
    one reader**, because falling through to NSView's default is the
    window's arrow. The seam layer is hit only where `seam(at:)` takes
    the point and `pointerSeam` answers wherever that does. The gutter's
    `hitTest` takes the WHOLE column while a cursorUpdate is current
    (a click, still only on a bracket): a TextKit 1 NSTextView's
    `hitTest` is nil in its own inset margins, so beside a bracket the
    hit test found the scroll view's CLIP VIEW, which answered with the
    document cursor — the upright I-beam — against the gutter's arrow on
    every move (seen on screen 2026-10-02, I-beam then arrow;
    `BracketColumnRoutingTests` hosts the real editor and asks). The
    text view's own `cursorUpdate` asks `NotebookGutter.cursor(at:)` too
    (`cursorForUpdate`), for the event it is handed in the column if it
    ever is — it used to return without a word there.
  `CursorRoutingTests` hosts the canvas over a stand-in in a window that
  is never shown and asks the window's own hit test with a cursorUpdate
  current: the notebook in cursor mode, the layer's host under the pen.
  It also puts a point under the real pointer by moving that window, to
  check the handlers read the pointer and not the event. THE RENDERED
  PAGE IS NO DIFFERENT FOR IT: over a SwiftUI block a routed
  cursorUpdate now reaches the page's own scroll container instead of
  the layer's host, and either way the answer is the window's arrow
  (probed both ways, 2026-10-02) — the page's cursors are set on hover,
  and a cursorUpdate there is still nobody's to answer.
  On the rendered page there was a fifth with the same face: the seam
  handed the cursor back by looking at what was on screen
  (`current == .iBeamCursorForVerticalLayout`), and the seam the pointer
  ARRIVES at is often told before the one it left, so leaving A took back
  the cursor B had just set. `MarkdownPreview.cursor` takes BOTH halves
  of "only what I put up", because either alone takes a cursor that is
  not ours: `ours` — the seam's own answer to "was the pointer on me",
  which is what tells one seam from the next — and `put`, what this
  page's seams last set, still being what is on screen. Only a seam
  writes `hoveredSeam`, and a seam is not the only thing here that
  claims the pointer: the gutter's brackets are an overlay over the
  right-hand end of every seam and set the hand on the way IN, so
  `ours` alone put a plain arrow over a bracket that is still clickable.
  And a hover the CODE clears — `openSeam`, `insertBlock`, `selectCells`
  — hands the cursor back itself (`dropHover`), because the `.ended`
  that arrives later answers for nobody and the horizontal I-beam left
  with the pointer. Which view a cursorUpdate REACHES is testable after
  all — the window's own hit test, asked with one current (the eighth
  cause) — and so is the geometry under all of it. What is still not is
  the cursor on the screen.
- **ONE OWNER AND ONE ANSWER FOR EVERY REGION, AND THE TWO PANES GIVE THE
  SAME ONE.** Sean, 2026-09-22: "the mouse cursor behavior should be the
  same in wysiwyg and markdown mode". Three were wrong, all the same
  shape. **The rendered page's side margins belonged to nothing**: the
  28-point inset was applied from OUTSIDE the row, so its hover and its
  tap were sized to the text column and the strips either side answered
  neither — `MarkdownPreview.cell(_:)` applies the inset INSIDE now, the
  words do not move, and that covers the OPEN editor too, which had no
  cursor of its own outside its text view. **The bracket column had
  two**: `PasteAwareTextView.resetCursorRects` laid a full-width I-beam
  under it, so the hand showed while the pointer moved and the I-beam
  whenever it stopped or the rects were rebuilt. Both are clipped to
  `bounds.width - NotebookGutter.width` now, `inGutter` makes
  `mouseMoved`/`mouseEntered` return without calling super there and
  `cursorUpdate` ask the gutter, the gutter's `hitTest` takes the whole
  column for a routed cursorUpdate (the eighth cause), and
  `NotebookGutter` carries `.cursorUpdate` in its
  tracking area with ONE reader (`cursor(at:)`) for hand-over-a-bracket
  and arrow-beside-one. Measured through `DebugLog` with the pointer
  driven across the column: on the moves the text view goes silent and
  the gutter answers once. **And a control inside a cell keeps the
  cell's I-beam unless it says otherwise** — a checklist's box and the
  evaluator badge are buttons, so `.pointingHand()` (which puts the
  cell's own cursor back on the way out, never the arrow, or it flashes
  between the two).
- **The + on the bar is a button, so it takes the pointing hand** — the
  same cursor the notebook brackets in the gutter use, so the app says
  "this does something" the one way (Sean, 2026-09-20: "it should be a
  pointer over the + button"). Its region is `CellSeams.plusTarget`,
  beside the `line` both panes already draw it on: four points more
  generous than the ten-point dot, because a small control is hard to hit
  exactly, and CLIPPED TO THE SEAM, because the click is — the layer
  takes no mouse down outside a seam, so a hand five points up in the
  cell above would promise a press that never arrives. THE SLACK IS ONLY
  HONEST WHERE THE SAME RECT IS READ FOR THE PRESS, which is the markdown
  pane, where `pressesPlus` measures the click against it. On the
  rendered page the press is a real SwiftUI `Button` at the margin and
  the rect is nothing but a cursor, so it takes `grip: 0` and the hand
  sits inside the button — four points of hand to the left of it fell
  through to the seam's own tap, which arms the bar and opens no menu:
  the same broken promise, sideways. The other thing the two panes do not
  share is where their own left margin is (`CellInsertions.plusLeading`,
  `MarkdownPreview.sideInset`).
- **A cell opened where the open one started gets the SAME editor.** The
  rendered page's rows are keyed by where their cell starts, so a block
  made above the open cell — at the front of its words — opens at that
  cell's offset, and SwiftUI updates the editor already there instead of
  building one. `BlockEditor.updateNSView` takes no text from outside
  while its view holds the keyboard, so it kept the old paragraph and the
  next keystroke wrote it over the new code. `MarkdownPreview.insert`
  takes the keyboard away first (`makeFirstResponder(nil)`) and so does
  its undo; the undo also empties the stack an editor brings from the
  cell it was before (`RenderedInsertionTests`).
- **`NSApplication.shared` turns mouse coalescing back ON.** Setting
  `NSEvent.isMouseCoalescingEnabled = false` in `WriteMindApp.init` did
  nothing at all: that init runs before the application is made, and
  making it resets the flag (measured 2026-10-02 — false, make the app,
  true; `finishLaunching` leaves it alone). It is set on
  `NSApplication.didFinishLaunchingNotification`, where the pen's reader
  starts too, and `PenSampleTests` reads the flag in the test host —
  which IS the launched app — so a move back into `init` fails there.
- **A stored property called `body` in a `View` is a redeclaration**, and
  `swiftc -parse` will not tell you — it type-checks fine and fails in the
  build. Three of the maths views had `let body: WLExpr` before they were
  renamed to `term`.
- **A MULTIPLE selection needs the PLURAL delegate method.** A delegate
  that implements `textView(_:willChangeSelectionFromCharacterRange:
  toCharacterRange:)` and not the `…FromCharacterRanges:toCharacterRanges:`
  one gets asked only the singular question, and AppKit then collapses
  every multiple selection down to ONE range on its way in. Setting
  `tv.selectedRanges` looked as if it had been rejected: the gutter drag
  handed five cells over, one bracket lit, and the offsets logged either
  side of the assignment were right (2026-09-20). It is not the ranges
  being unsorted — that is a different failure with the same face, and it
  is what the same symptom was blamed on when ⌘D's run first hit it. The
  coordinator answers both now, snapping each range out of what is folded.
- **A LIT BRACKET IS NOT A HELD ONE.** The caret's own cell is drawn
  heavy — that is what says which cell you are typing in, and the
  rendered page lights the cell open for editing the same way — so there
  is always exactly one bracket calling itself selected with nothing
  selected at all. `Bracket.selected` means "draw this heavy";
  `Bracket.held` means "a real selection covers this", and every GESTURE
  reads `held`. Reading `selected` made a drag from the caret's own
  bracket reorder the note, a plain click on it do nothing whatever, and
  a cmd-click quietly add a cell nobody had clicked — three reviewers,
  one root (2026-09-20). Both panes carry both flags.
  **AN OUTER BRACKET IS HELD BY ITS CELLS, not by its own characters.**
  `CellSelection.covers` asks whether ONE selected range holds the whole
  of a range — deliberately, because the union of two cells picked up
  separately would swallow the blank line between them and light every
  bracket out to the margin. But cells picked up one at a time ARE
  several ranges, so no one of them ever covered the section round them
  and the outer bracket stayed grey with every cell in it held (Sean,
  2026-09-21: "highlighting all of this should have highlighted all the
  outermost cells"). `CellSelection.holds` asks it of the cells instead —
  `cells(of:in:)`, then `covers` on each — and both panes call it for
  every bracket, a cell's own included: a cell holds itself, a section
  holds all of its cells, and two cells out of three still light nothing
  outside themselves.
- **The gutter takes only the clicks it has a bracket for.** Its
  22-point column is 22 of the text container's own 24 points of right
  margin, so a `hitTest` that answers for the WHOLE column eats the click
  that puts the caret at the end of a line — and, worse, the one that
  reaches `PasteAwareTextView.mouseDown`, which is the path that puts an
  armed seam out (2026-09-20: the bar stayed drawn with no caret
  anywhere). A drag loses nothing by the narrower rule: the press lands
  on a bracket, and after a mouse down every drag and the mouse up come
  to that view whatever is under the pointer. The POINTER is another
  matter: while a cursorUpdate is the current event the whole column is
  the gutter's (the eighth cause, under the cursor traps).
- **The background app tools CAN drive a drag, and cannot hold a
  modifier.** `app_drag` says "delivered via raw input… unverified" and
  then works: a path of points arrives as a real `mouseDown` and a dozen
  `mouseDragged`s, in both the AppKit gutter and a SwiftUI `DragGesture`
  (2026-09-20, the events logged through `DebugLog`). What it cannot do is
  ⇧-click or ⌘-click — `app_click` has no modifiers and goes through
  AXSelectedTextRange over a text view anyway, never reaching a view's
  `mouseDown` — and the screen-takeover card the display-scope tools raise
  needs somebody at the machine to answer it. An earlier note here said a
  drag could not be driven at all; it can.
- **The shell's working directory persists between tool calls** (baseline).
  Every script here starts with `cd "$(dirname "$0")/.."` so it does not
  matter where it was invoked from.
