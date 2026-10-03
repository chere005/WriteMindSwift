# What is next

The open list. Everything already built is in [FEATURES.md](FEATURES.md); how
it is built is in [AGENTS.md](../AGENTS.md).

**What goes in here: things that are not built, and bugs that are not
fixed.** Not what has yet to be watched on screen — Sean, 2026-09-20:
"don't list things I haven't tested yet in todos", the second time he has
had to say it. Verification is the job, not an item.

## Open

- **Dragging the divider between the notes and the video is groggy.** Sean,
  2026-10-02: "resizing the screen by dragging the middle vertical line is
  groggy". The HSplitView's divider lags the pointer. Not yet looked into;
  the likely weight is what a width change runs on every frame — the
  note's offscreen layout for the pane mapping (`PaneFrames`, which now
  waits 150 ms after a resize stops, but check it holds), the drawing
  layer's redraw, the tablet pane's page relayout — and `Instruments` on a
  drag is the first step, not a guess.

- **Docking a floating picture into the note.** Sean, 2026-09-22: "add a
  button for floating elements to dock them to a cell wherever the input
  cursor is.. or drag that button to get an interactive mouse cursor that
  puts the image wherever i release the mouse button.. text can not
  overlap with an image". Planned in full in
  [PLAN-docking.md](PLAN-docking.md), including the one decision that is
  Sean's — docking writes `![](.drawings/media/…)` into the .md, which is
  what makes the picture a cell and so makes everything else fall out of
  what is already built. The button is one build, the drag is another
  (neither pane publishes its seams, and the drawing layer is above both).
- **The evaluation cell's margin, four things.** Sean, 2026-09-22, in one
  message; C and Rust landed from it, these did not.
  - **A new evaluation cell is Wolfram** ("default to wolfram"). ⌘9 writes
    whatever `AppState.evaluator` holds, which starts as Python.
  - **And then it is whichever was used last** ("remember last used cell
    type when inserting"). The choice would have to be remembered in the
    defaults the way the pen's size and colour are, and written whenever a
    cell is made or its environment picked.
  - **The marks sit further left, and the cells do not move**
    ("align further to the left but keep the cell start the same").
    `CellMark` is a 44-point column in front of the cell, so moving the
    marks left moves the code with them. The cells' left edge has to stay
    where it is, which means the mark goes in the page's own margin — an
    overlay rather than a row in the stack — and that margin
    (`MarkdownPreview.sideInset`, 28) is narrower than `Out[10]`.
  - **The environment is an icon, not two letters** ("use icons for WL,
    CPP, Python"). `Evaluator.badge` is `WL` / `PY` / `C` / `C++` / `RS`
    today. There is no SF Symbol for a language, so this means art —
    and `SymbolTests` exists because a missing symbol name draws
    NOTHING on this macOS, so whatever is used has to be checked the
    same way.
- **Flow charts, further.** Six shapes come off a sketch now. A tick, a
  cross and a star are read by the classifier and deliberately left as
  ink: they are marks in a note rather than objects, and the app already
  reads a tick in a drawn box as a task item, so putting one on the page
  here as well would read the same ink twice. Worth revisiting if Sean
  wants a tick he can drag.
- **Tables, from scratch.** The feature came out whole on 2026-09-20 (Sean:
  "tables is weird right now... just completely remove tables as a feature
  and we'll rebuild that from scratch"). Gone with it: the GFM block and
  its parsing, the grid you typed in, the toolbar button and ⌃⌘T, and
  reading a ruled table off a photograph, which existed only to write one.
  `git show` the removal commit for the old one when the new one is wanted.
- **⌘D's run types over the first occurrence only.** Found in the cell
  test pass (2026-10-02, Sean: "do a thorough test of cell selection and
  input insertion ux behavior..."): NSTextView types over the FIRST range
  of a multiple selection and keeps the rest, so ⌘D twice over "cat and
  cat" and "dog" typed leaves "dog and cat" — against what
  `EditorBridge.selectNextOccurrence` promises. Held cells were given
  their own rule that pass; Sublime's run needs every range replaced and
  a caret left in each, and NSTextView does not keep several empty
  carets, so it wants a design of its own rather than a patch.
