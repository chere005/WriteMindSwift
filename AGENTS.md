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
  returned unchanged or typing dies.
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
  the pane back to the notebook.
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
  for one gesture and hand it back, so picking either puts the mode back to
  `cursor` and picking a mode puts them away. TWO READERS, and everything
  else asks one of them rather than spelling the flags out again —
  `canvasOwnsPane` (do the clicks reach the notebook: the seams on both
  panes, the layer's hit shape) and `paneCursor` (what the pointer is over
  the pane: the pencil, the crosshair, or nil for "the notebook's own
  four"). The list used to be written out in three places, and a fourth
  thing holding the pane meant finding all three.
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
  glyph, was invisible on the page.
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
  kind — the ladder, the three lists, the quote, the fenced block, and
  ⌘9's evaluation cell (`CellTypes.Kind.evaluation`, which is that same
  fenced block with `eval ` on its info string; it is deliberately NOT
  on the + menu, since three environments would triple a list for a
  cell its own key already makes) —
  opens the cell with that marker already in it and is finished, and
  anything else — bold, the text style, maths — opens a PLAIN cell and
  then runs in it. `perform(opensACell:)` tells those from the third
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
  else. Three things about it that are not obvious: the command is applied
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
  be a scroll's worth off. The preview does not scroll the layer (its
  offset is 0 there). The first cut kept objects on the pane and the text's
  exclusion bands moved with the scroll — a picture taller than the pane
  then pushed the text out of reach for good.
- **A new picture goes under the caret, and the note does not move for
  it.** `NoteStore.caretAnchor` (set by `EditorPane`, nil outside the
  source editor) gives the caret's line from `EditorBridge.caretLineFrame`
  — the text view's coordinates ARE the layer's document coordinates — and
  `placedCenter` puts the picture one `MarkdownPreview.gapHeight` under
  that line, flush with the text's left edge. Not 8: the same constant the
  seam between two cells is, so the landing and the seam cannot drift
  apart. Nothing is typed into the note and nothing is pushed aside; the
  picture floats over the words. Shapes and text boxes still land in the
  middle of what is on screen.
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
  heights being equal: the two modes come back to the same CELL by its
  id (`PreviewLayout.topRow`, `NoteStore.topCell`), never by a
  measurement.
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
  the wrong first impression.
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
  ```eval c++ or ```eval rust — ⌘9 makes one, turns the caret's cell
  into one, or at an
  ARMED BAR makes one there (the same rule every other kind-naming
  command follows; it used to ask `caretCell()` and so restyled the
  cell BELOW the bar), ⇧↩
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
                          every camera with a checkmark on the live one
  AppState.swift          UI state: sidebar shown, editor/preview mode, pen
  TestHost.swift          the unit-test host keeps out of ~/Documents
                          and off the camera
                          on/off, pen width and colour (persisted), and the
                          EditorBridge the toolbar talks through
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
  Editor/MarkdownSourceStyle.swift
                          the block's markdown styled as it is typed: markers
                          fade, bold is bold, headings are their size, maths
                          and links are coloured. Runs are pure and tested
  Drawing/Drawing.swift   the objects on the drawing layer: Stroke
                          (normalised 0…1 points, hex colour, width),
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
                          AppKit cursor rect over the text view
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
  Views/PenMenu.swift     the popover under the pen: size slider, circular
                          ColorPicker plus six preset swatches, undo/redo of
                          anything that happened on the layer, clear, Add
                          Image, and how to get hold of an object
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
                          and a status line (file, words, saved time)
  Views/ShapeMenu.swift   the Shapes popover (nodes, the arrow tool) and the
                          Marks popover (checks, crosses, stars, arrows)
  Views/CameraPane.swift  the preview, or a placeholder that says why not;
                          rotate buttons and the section selector (drag a
                          box, then Writing or Page)
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
  block · ⌃⌘↑/↓ move section · ⌃G group/ungroup what is picked on the
  drawing layer · ⌥⌘Z / ⇧⌥⌘Z undo and redo the
  DRAWING (⌘Z does it too while the pen is up) · ⌘D select next occurrence,
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
  rotate left, rotate right, notes pane); the drawing layer's handles
  (rotate, scale, move, trash, and per-kind: crop and read for a picture,
  style for a connector, a circle per segment for a routed one).
- **A recursive SwiftUI view cannot be type-checked** — "opaque return type
  was inferred in terms of itself". The sidebar builds `[SidebarRow]` first
  and draws a flat ForEach; a tree that draws itself by recursion does not
  compile, and flattening is faster anyway.
- **The sidebar is a plain HStack child**, shown or hidden with a transition,
  rather than a NavigationSplitView column — the split view owns its own
  toolbar and collapse gestures, and the bar above has to stay put.

## Traps that have cost real time here

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
  `hitTest` returning nil so it never takes a click.
- **Being ABOVE the text view does not win the cursor either.** The seam
  layer had a cursor rect, a `cursorUpdate` and a `mouseMoved` of its own
  and the pointer over an armed bar was still the upright I-beam (Sean,
  2026-09-20: "the mouse cursor should reliably be horizontal between the
  cells"): the text view's OWN tracking areas hand it those same events
  whoever is on top, and two cursor rects over one point is AppKit's
  choice to make — it chose the text view's. The pencil settled this by
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
  with the pointer. Which view's `cursorUpdate` wins at runtime is not
  unit-testable; the geometry under all of it is, and is.
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
  `cursorUpdate`/`mouseMoved`/`mouseEntered` return without calling
  super there, and `NotebookGutter` carries `.cursorUpdate` in its
  tracking area with ONE reader (`cursor(at:)`) for hand-over-a-bracket
  and arrow-beside-one. Measured through `DebugLog` with the pointer
  driven across the column: the text view goes silent and the gutter
  answers once. **And a control inside a cell keeps the cell's I-beam
  unless it says otherwise** — a checklist's box and the evaluator badge
  are buttons, so `.pointingHand()` (which puts the cell's own cursor
  back on the way out, never the arrow, or it flashes between the two).
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
  to that view whatever is under the pointer.
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
