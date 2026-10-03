# Cell selection and input insertion — test pass

Sean, 2026-10-02: "do a thorough test of cell selection and input insertion ux
behavior...". Worktree `wm-editor`, branch `editor-ux`. Suite 1330 → 1364, green.

How each verdict was reached:
- **unit** — a test through the pure layer, or a real NSTextView wired the way
  `MarkdownTextView.makeNSView` wires it (coordinator as delegate, gutter, seam
  layer, bridge), keys sent through `doCommand(by:)` as AppKit sends them.
- **screen** — driven in a scratch copy of the built app
  (`com.seancheren.WriteMindScratch`, `WRITEMIND_SCRATCH_NOTES=1`, notes in the
  test host's temp folder; Sean's `/Applications/WriteMind.app` untouched).
  Raw clicks were sent as zero-length `app_drag`s, because `app_click` over a
  text view goes through accessibility and never reaches `mouseDown`.
- **not drivable** — keys (`app_key` does not reach the app), modifier clicks,
  hover, pop-up menus; and `app_type` writes through `AXSelectedText`, which
  bypasses `insertText` — typed at an armed bar it went into the cell below,
  a tool artefact, not a keystroke.

## Inventory

| # | Behaviour | Verdict |
|---|---|---|
| 1 | Click a cell's bracket (markdown pane) — holds the cell | ok (existing unit) |
| 2 | Click a section's bracket — holds every cell under it | ok (unit) |
| 3 | Click an In/Out pair's bracket — holds both | ok (unit) |
| 4 | ⇧-click extends from the last plain click | ok (unit probe); not drivable |
| 5 | ⌘-click puts a cell in / takes it out | ok (existing unit); not drivable |
| 6 | Drag down the brackets holds every cell passed, live | ok — screen |
| 7 | Plain click (no drag) on a bracket that is already held | **FIXED** — did nothing; now takes that bracket's cells alone (rendered page already did). unit + screen |
| 8 | Drag a held bracket / ⌃⇧↑↓ moves the run and keeps it held | ok — screen (Move Cell Down with a held run) |
| 9 | Move two cells held with a hole | **FIXED** — threw NSInvalidArgumentException (see 20) |
| 10 | Gutter hover wash | ok (shared `CellSelection.cells(of:)`, existing unit); hover not drivable |
| 11 | ⌘A then ⌫ / typing (markdown pane) | ok (unit probe) |
| 12 | Click a seam arms the bar | ok — screen, both panes |
| 13 | ↓ / ↑ from a bar armed by a CLICK | **FIXED** — ↓ skipped the cell below (landed on the next bar), ↑ re-armed the same bar. unit |
| 14 | ↓ / ↑ from a bar armed by an arrow | ok (unit) |
| 15 | ↑ on the note's first line / ↓ on its last line | **FIXED** — gave an ordinary caret at the very start/end; now arms the bar above the first cell / under the last, as the rendered page does. unit |
| 16 | ⌫, ⌦, ⌥⌫, Tab, ⇧Tab at an armed bar (markdown pane) | **FIXED** — ⌫ joined the cell below to the one above, ⌦ took its first letter, Tab/⇧Tab indented/outdented it. Now: bar out, note untouched, as on the rendered page. unit |
| 17 | Escape at a bar reached by arrow, then typing | **FIXED** — caret stayed on the separator and the next character welded three cells into one paragraph. unit |
| 18 | ⌃↩ / ⌥↩ at a bar | **FIXED** — inserted a newline into the cell below; now open an empty cell like Return (rendered page reads all three as "\r"). unit |
| 19 | The + menu, and each kind it makes | ok (existing CellTypeTests / ArmedTypeTests); the NSMenu not drivable |
| 20 | ⌫ over two cells held with a hole | **FIXED** — threw (`shouldChangeText(inRanges:)` handed ranges back to front, with a singular-only delegate). Measured on HEAD code too. unit |
| 21 | ⌦ over held cells | **FIXED** — left the blank lines between them standing; now = ⌫. unit |
| 22 | Typing over several held cells (cmd-clicked, or a section's bracket) | **FIXED** — NSTextView replaced only the first range (a section's bracket + a word kept the whole section). Now `CellCommands.typing`, the rendered page's rule, one function for both. unit |
| 23 | Escape with held cells (markdown pane) | **FIXED** — they stayed held (and Escape ran word completion); now let go, as on the rendered page. unit |
| 24 | Typing at an armed bar | ok (existing CellOpeningTests); screen: see app_type note above |
| 25 | Return at the end of a middle cell, then typing | **FIXED** — the arm was checked against seams measured before the Return, so no bar came up and the character became a second line of the cell above. unit |
| 26 | Return at the end of the last cell, then typing | **FIXED** — welded into the last cell; the empty line after a final newline now reads as the tail seam. unit |
| 27 | ⌫ at the start of a cell | decision (D2) |
| 28 | Tab / ⇧Tab inside cells, lists, fences | ok (existing ListEditing / CodeTyping tests) |
| 29 | Delete / Duplicate / Move Cell / Merge / Split at an armed bar — RENDERED page | **FIXED** — Delete Cell deleted the note's FIRST cell, Duplicate copied it, Move moved it, Merge joined the first two. unit + screen |
| 30 | Move Section at an armed bar | **FIXED** — moved the section of the cell below (markdown) / the first section (rendered). unit + screen |
| 31 | Format commands that name a kind at a bar (Quote, Title…) | ok — screen (Quote made a quote cell at the bar) + existing unit |
| 32 | Paste at an armed bar | ok (unit probe: a cell of its own) |
| 33 | Paste over several held cells | fixed by the same path as 22 (the edit over the first range); not separately tested |
| 34 | ⌫ over a held cell that is folded away | ok (unit probe: nothing hidden is deleted, the fold opens) |
| 35 | Drag from a bar on the rendered page over an In/Out pair | **FIXED** — the pair's bracket was read as a cell (`!foldable`), and the cell ABOVE the bar was taken too. unit + screen |
| 36 | Typing over a selection that clips a hidden `**` pair (markdown pane) | **FIXED**, found in passing — threw (same back-to-front root as 20) instead of leaving "xld here". unit |
| 37 | The held selection surviving a switch of pane | not built — only the top cell carries (seen on screen: held cells let go on switching to the rendered page). The wm-modes agent owns positions across modes; see D6 |
| 38 | Insertion of every CellTypes kind (⌘8, ⌘9, maths, + kinds) | ok (existing InsertionTests, ArmedBarFormatTests, CellTypeTests) |
| 39 | ⌘D occurrences, then typing | **BUG, not fixed** — only the first occurrence is replaced (same NSTextView first-range behaviour). Needs real multi-caret design; recorded in docs/TODO.md |

## Decisions for Sean (not bugs)

- **D1. A click on one cell's bracket on the rendered page OPENS it for
  typing; in the markdown pane it HOLDS it** (type replaces it, ⌫ deletes it).
  FEATURES.md says "Click its bracket and the whole cell is picked up … The
  same on both sides", but the checklist relies on the bracket opening the
  whole list for typing. Hold on both sides, or keep the rendered page's open?
- **D2. ⌫ at the start of a cell**: the markdown pane joins it to the cell
  above (the same as ⌃M); the rendered page does nothing.
- **D3. Return in the middle of a paragraph**: a line break inside the cell
  in the markdown pane; the rendered page splits it into two cells. (Return
  at the END of a cell now gives a new cell in both.)
- **D4. ← and → at an armed bar** take the bar back and do nothing else, in
  both panes. ↑/↓ step into the neighbouring cell; should ←/→ step too?
- **D5. ⌘A on the rendered page** selects within an open cell, never "all
  cells held"; the markdown pane's ⌘A holds every cell.
- **D6. Held cells across a pane switch**: not carried. Worth doing with the
  positions work in wm-modes, not here.
- **D7. Where Escape leaves the caret** after letting held cells go (markdown
  pane): the start of the first of them. The rendered page has no caret then.

## Seen in passing, not touched

- `NotebookCells.tidied` has no callers and no tests (dead since ad62b1f).
- AGENTS.md's Shortcuts line (⌃⌘S sidebar, ⌃⌘E notes pane…) no longer matches
  `Shortcut` (⌘K, ⌘T, ⌘Y…).
- The two capture-pipeline tests (`NotebookCaptureTests.testAWholeFrame…`,
  `NoteStoreDrawingTests.testTheCaptureButtonComesBack…`) failed in two runs
  while another agent's xcodebuild was running (76 s against an 8 s limit) and
  passed in the others — load, not this change.
