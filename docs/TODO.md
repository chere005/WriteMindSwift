# What is next

The open list. Everything already built is in [FEATURES.md](FEATURES.md); how
it is built is in [AGENTS.md](../AGENTS.md).

**What goes in here: things that are not built, and bugs that are not
fixed.** Not what has yet to be watched on screen — Sean, 2026-09-20:
"don't list things I haven't tested yet in todos", the second time he has
had to say it. Verification is the job, not an item.

## Open

- **Dragging the Dock handle to a seam.** The Dock and Make Cell handles
  are built (2026-10-02: `Docking`, `EditorPane+Docking`); what is not is
  dragging the Dock handle to wherever the pointer is let go (Sean,
  2026-09-22: "or drag that button to get an interactive mouse cursor that
  puts the image wherever i release the mouse button"). A click docks at the
  cursor; the drag would hand `Docking` a seam by the point it ended on
  (`CellSeams.nearest(toLine:)`). Pictures docked in a cell cannot yet be
  cropped or read into text (`NoteStore.cropImage` and `readText` only look at
  the layer).
- **The evaluation cell's margin, two things left.** Sean, 2026-09-22, in one
  message; C and Rust landed from it, "default to wolfram" and "remember last
  used cell type" landed 2026-10-02, these did not.
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
- **An inline code span is two regular expressions, not cmark's rule.** Found
  walking the cursor around backticks (2026-10-03, Sean: "cursor behavior
  around backticks is very weird, fix that"). A backtick string of N opens a
  span that the next string of exactly N closes; `MarkdownSourceStyle` reads
  "`x`" and "``x``" with two patterns instead, so a tick typed AFTER a span's
  closing tick ("`foo``") leaves the span styled and its ticks hidden in both
  editors, where the rendered page (Foundation's markdown) draws all of it as
  text, and "`a``b`" is two spans here and one there. The empty span was
  fixed that day; the grammar is the rest. It is one scanner in
  `MarkdownSourceStyle.runs` and `spans`, and everything that reads them
  (`MarkerDeletion`, `Insertion`) follows.
