# Developing the Wacom pen with no tablet

Sean, 2026-10-03: "make sure i can develop wacom features without a device
plugged in." Everything on the pen's path — the page, the notebook, the
eraser, the box, undo and redo by double press, Fit and Real size — can be
tried by hand and tested with nothing plugged in. The how-it-is-built is in
AGENTS.md ("THE PEN DEVELOPS WITH NO TABLET"); this is the how-to.

## The idea in one paragraph

Every source of pen data comes in by **one door**, `TabletInput.receive`, as the
tablet's own word: a raw 10-byte pen report. The real HID reader uses it. So
does the **virtual tablet** (a pad on screen, the mouse is the pen) and a
**replay** of a recorded session. All three go through the real packet parser,
the real pen state machine (`TabletPen`), the real turn and the real scribes, so
a bug found here is a bug the tablet would have shown. **The real tablet always
wins** — plugged in, it silences the stand-ins — and the stand-ins are **off**
unless you switch them on.

## Try a pen feature by hand

1. **Input Devices ▸ Tablet Developer ▸ Virtual Tablet** — tick it. (Off by
   default; remembered. Not offered while a real tablet is plugged in.)
2. **Input Devices ▸ Tablets ▸ Virtual Tablet (developer)** — pick it. The pane
   becomes the page, as with the real tablet, and the **Virtual Tablet** window
   comes up. (Never remembered: a launch never starts in it.)
3. Move the pointer over the pad: the pen hovers (the marker follows). Press: the
   nib is down. The pad is drawn at the page's shape, one quarter turn
   clockwise unless you turned it; the lit dot is the tablet's light.
4. The controls beside the pad:
   - **Pressure** — the slider; the keys 1–9 (a tenth to nine tenths) and 0
     (full), `[` and `]` (a step), or the scroll wheel, over the pad.
   - **Lower switch** (nearer the nib): **Hold** latches it, **Tap**, **Double**
     (two taps) — double is *undo*, held as the nib goes down is the *eraser*.
   - **Upper switch**: the same — double is *redo*, held is the *box*.
   - **Eraser** — the lower switch held on. (The CTL-472's pen has no eraser
     end; this is what its eraser is.)
   - **⇧ held over the pad** is the lower switch and **⌥** the upper, for as long
     as they are down: how to hold one *while drawing*.
   - The pen stays near, where it was, when the pointer leaves the pad for a
     button; **Take the pen away** sends it out of reach.
5. **Write on: Page | Notebook** and **Fit | Real size** are the pane's own, as
   with the tablet.

## Record a session, and play it back

- **Record** (the window, or Input Devices ▸ Tablet Developer ▸ Record Pen
  Session) writes down every report the page hears — from the virtual tablet, a
  replay, or the real tablet when you have one — until you stop. It saves
  `pen-<date>.ndjson` in `~/Library/Application Support/WriteMind/PenRecordings`
  (**Show Pen Recordings in Finder**). What happened — recording, saved (and
  where), nothing heard, a file that cannot be played and its line, a replay
  that would not be heard and why — is said in the **footer** whatever is
  picked (the window is up only while the virtual tablet is the pick, and
  recording the real tablet is the whole point), kept at the foot of the Tablet
  Developer menu, and shown in the window too. **Replay…** says why it cannot
  before it asks for a file.
- **Replay…** plays one back through the same door, on the field it was
  recorded on: at **real speed**, at **½×, 2×, 4× or Max**, or **one event at a
  time** (**Step**). The pen state machine reads the *recorded* times, so a
  double press is still a double press at any speed; only the waiting changes.
  **Stop** lifts the pen where it was (a half-played stroke must not stay down).
- A replay needs the same things a pen does: the virtual switch on, no real
  tablet plugged in, a tablet picked and the page (or a note) on screen.

The file is NDJSON, one object a line, keys sorted: a header
(`{"format":"writemind-pen-stream","version":1,"source":…,"productID":…,
"width":…,"height":…,"quarterTurns":…,"note":…}`), then
`{"report":"02 e0 b0 1d 8e 12 00 00 14 00","t":0.008}` — `t` is seconds from the
first event, the report is the tablet's ten bytes in hex. A session made while
WriteMind did not hold the tablet (the Wacom driver's events) has no bytes and is
recorded as `{"reading":{…},"t":…}` instead. A file that is not whole is not
played, and the status line says which line is wrong. **A file is not trusted**:
the field and every count are numbers a tablet could have (finite, 0 to 65535 —
a report carries a count in two bytes), a pressure is 0 to 1, `t` is between 0
and a day and never goes backwards, and a report is a ten-byte pen report; a file
with anything else in it is refused with its line.

**A bug seen once on the real tablet is a file**: turn Record on, reproduce it,
and the recording is the reproduction — commit it as a fixture.

## Test a pen feature with no tablet

Write the gesture, not the packets (`WriteMindTests/Support/TabletScript.swift`):

```swift
let rig = TabletRig()                         // page, pen, funnel, scribes — a virtual clock
rig.pen.hover(0.5, 0.5).down(0.4).move(0.6, 0.5).up()
rig.pen.hold(.lower) { rig.pen.down().line(to: 0.5, 0.7).up() }   // the eraser
rig.pen.doublePress(.lower)                   // undo
rig.pen.tap(.upper).tap(.upper)               // redo
XCTAssertEqual(rig.page.strokes.count, 1)
```

1. **`TabletRig(target: .page)`** is the whole path — the virtual pen through
   the one door into `TabletPage`. **`TabletRig(target: .notebook, notes: true)`**
   adds a real `NoteStore` and plays the drawing layer's part (the eraser's
   deletions, the marquee's pick, by the layer's own rules); `rig.notes` has
   the store, the strokes and the selection. `quarterTurns:` and `extent:` set
   how the tablet is held and which one it is.
2. **Coordinates are page fractions** (u, v) — where the stroke is on the page as
   you see it, whichever way the tablet is held. `hoverCounts` / `moveCounts`
   take raw counts.
3. **Time is the test's.** Every call moves the virtual clock a step (8 ms, the
   tablet's ~120 reports a second); `wait(seconds)`, `tap` and `doublePress`
   move it further. Nothing sleeps. A double press is two 80 ms taps 120 ms
   apart, inside the pen's own limits (`TabletPen.tapLimit`, `doubleWindow`).
4. **The state machine alone**: `PenBench` feeds a script's *exact* frames to a
   bare `TabletPen` (a pressure of 0.3 stays 0.3 instead of the report's
   614/2047) — for tests of the pen's rules themselves.
5. **A replay in a test**: `rig.play(try PenFixtures.load("stroke"), speed: …)`,
   then assert the page or the note. The fixtures in `WriteMindTests/Fixtures`
   are a stroke, a box select, a lower-hold erase, a double press for undo, a
   double tap for redo and a pressure ramp. Each is the bytes its recipe in
   `PenFixtures` records, and a test keeps it so; to make them again after the
   format or the virtual pen changes:
   `TEST_RUNNER_WRITEMIND_REGENERATE_FIXTURES=1 sh tools/test.sh`.
6. **A new pen feature, step by step**: write the gesture on the rig and watch it
   fail for the reason you expect; build the feature; try it by hand on the
   virtual tablet; record the session worth keeping; commit it under
   `Fixtures/` with a recipe in `PenFixtures` (or as a plain recorded file) and
   a replay test that asserts the document outcome.

## What it does not do

- It does not open, seize or send anything to the real tablet, ever — nothing
  here touches `LiveTabletHID`, which still refuses under the test host.
- It cannot say whether the real pen's buttons are the buttons the code thinks
  (which physical switch is 0x02 is the Linux driver's word; the log line
  `tablet: first click of the pen's … switch` is how a real session checks it).
- The virtual pen reports only when something changes; a real tablet repeats
  itself about 133 times a second. The pen state machine reads stamps and
  changes, so the two agree — but a feature that depends on the *rate* of
  reports has to be tried on the real tablet.
