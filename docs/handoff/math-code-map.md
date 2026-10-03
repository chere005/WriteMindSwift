# Inserting maths, code and evaluation cells — the map

WriteMind, branch `editor-ux`, 2026-10-02. Sean: "make math and code block insertion sensible..".

## How this was made

Every row was produced by DRIVING THE REAL CODE, not by reading it:

- **source pane** — a `PasteAwareTextView` holding the note, with the caret / selection / armed bar set, and the
  `EditorBridge` call the menu or button makes (`codeBlock`, `insertMath`, the ⌘9 menu item's body). The resulting
  text and caret are what the text view holds afterwards. Undo was measured on the text view's own `UndoManager`.
- **rendered page (before)** — the open cell's editor simulated exactly as `MarkdownPreview` builds it (a
  `BlockTextView` holding the cell's markdown, or a fenced cell's CODE alone), the bridge command run in it, and the
  editor's text spliced back over the cell's range the way `draftBinding` does; the bar through
  `MarkdownPreview.opened`, ⌘9 through `writeInDocument`. "nothing open" uses `openSomething` (the first cell).
- **after** — the source pane through the bridge, and the rendered page through its own path
  (`MarkdownPreview.insertionSpot` → `Insertion.insert` → `landing`), compared: every row came out identical in both
  panes, so the after-tables have one column. The rendered page itself was also driven hosted in a window
  (`RenderedInsertionTests`): the cell is made, opened as code with the caret in it, and one ⌘Z takes it back.

Notation: `⏎` a newline, `|` / `‸` the caret, `[…]` a selection, `…` the note continuing unchanged.
The base note: `# Title⏎⏎One two three four.⏎⏎- apple⏎- banana⏎⏎> quoted line⏎⏎```python⏎print(1)⏎```⏎⏎```wl⏎Sqrt[2]⏎```⏎⏎```eval python⏎x = 1⏎```⏎⏎Last line.`
Maths WL used: `Sqrt[x]`. Code language: Python. Evaluator: Python.

# BEFORE — what each command did

## ⌘8 code (python)

| context | source pane | undo | rendered page |
|---|---|---|---|
| caret mid-paragraph | `…tle⏎⏎One two⏎```python⏎|⏎```⏎ three four.…` | 1 | `…tle⏎⏎One two⏎```python⏎|⏎```⏎ three four.…` |
| caret start of paragraph | `# Title⏎⏎```python⏎|⏎```⏎One two thre…` | 1 | `# Title⏎⏎```python⏎|⏎```⏎One two thre…` |
| caret end of paragraph | `…three four.⏎```python⏎|⏎```⏎⏎- apple⏎- b…` | 1 | `…three four.⏎```python⏎|⏎```⏎⏎- apple⏎- b…` |
| caret mid-heading | `# Ti⏎```python⏎|⏎```⏎tle⏎⏎One two…` | 1 | `# Ti⏎```python⏎|⏎```⏎tle⏎⏎One two…` |
| armed bar (para/list) | `…hree four.⏎⏎```⏎|⏎```⏎⏎- apple⏎- ba…` | ✗ (one ⌘Z left the note half undone) | `…hree four.⏎⏎```⏎|⏎```⏎⏎- apple⏎- ba… {open as code}` |
| selection part of a line | `… Title⏎⏎One ⏎```python⏎two three⏎```⏎| four.⏎⏎- ap…` | 1 | `… Title⏎⏎One ⏎```python⏎two three⏎```⏎| four.⏎⏎- ap…` |
| selection one whole line | `# Title⏎⏎```python⏎One two three four.⏎```|⏎⏎- apple⏎- …` | 1 | `# Title⏎⏎```python⏎One two three four.⏎```|⏎⏎- apple⏎- …` |
| selection several lines (list) | `…hree four.⏎⏎```python⏎- apple⏎- banana⏎```|⏎⏎> quoted l…` | 1 | `…hree four.⏎⏎```python⏎- apple⏎- banana⏎```|⏎⏎> quoted l…` |
| selection over two cells | `…e two three ⏎```python⏎four.⏎⏎- apple⏎```|⏎- banana⏎⏎>…` | 1 | `…e two three ⏎```python⏎four.⏎```|⏎⏎- apple⏎- …` |
| selection reading as maths | `Area ⏎```python⏎x^2 + 1⏎```⏎| here.` | 1 | `Area ⏎```python⏎x^2 + 1⏎```⏎| here.` |
| caret in a list item | `… apple⏎- ban⏎```python⏎|⏎```⏎ana⏎⏎> quote…` | 1 | `… apple⏎- ban⏎```python⏎|⏎```⏎ana⏎⏎> quote…` |
| caret in a quote | `…anana⏎⏎> quo⏎```python⏎|⏎```⏎ted line⏎⏎``…` | 1 | `…anana⏎⏎> quo⏎```python⏎|⏎```⏎ted line⏎⏎``…` |
| caret in a code block | `…ython⏎print(⏎```python⏎|⏎```⏎1)⏎```⏎⏎```w…` | 1 | `…ython⏎print(⏎```python⏎|⏎```⏎1)⏎```⏎⏎```w… {open as code}` |
| caret in a maths block | `…⏎```wl⏎Sqrt[⏎```python⏎|⏎```⏎2]⏎```⏎⏎```e…` | 1 | `…⏎```wl⏎Sqrt[⏎```python⏎|⏎```⏎2]⏎```⏎⏎```e… {open as code}` |
| caret in an eval cell | `…val python⏎x⏎```python⏎|⏎```⏎ = 1⏎```⏎⏎La…` | 1 | `…val python⏎x⏎```python⏎|⏎```⏎ = 1⏎```⏎⏎La… {open as code}` |
| caret in a blank cell | `Above.⏎⏎⏎```python⏎|⏎```⏎⏎⏎Below.` | 1 | `Above.⏎⏎⏎```python⏎|⏎```⏎⏎⏎Below.` |
| caret on empty last line | `Words.⏎```python⏎|⏎```` | 1 | `(no cell to open)` |
| empty note | ````python⏎|⏎```` | 1 | `(no cell to open)` |
| very start of note | ````python⏎|⏎```⏎# Title⏎⏎One…` | 1 | ````python⏎|⏎```⏎# Title⏎⏎One…` |
| very end of note | `…⏎⏎Last line.⏎```python⏎|⏎```` | 1 | `…⏎⏎Last line.⏎```python⏎|⏎```` |
| bar at the very end | `…⏎⏎Last line.⏎⏎```⏎|⏎```` | THROWS (NSRangeException) | `…⏎⏎Last line.⏎⏎```⏎|⏎``` {open as code}` |

Rendered page, nothing open: `# Title⏎```python⏎⏎```⏎⏎One two thr…`

## maths, own line

| context | source pane | undo | rendered page |
|---|---|---|---|
| caret mid-paragraph | `…tle⏎⏎One two⏎```wl⏎Sqrt[x]⏎```⏎| three four.…` | 1 | `…tle⏎⏎One two⏎```wl⏎Sqrt[x]⏎```⏎| three four.…` |
| caret start of paragraph | `# Title⏎⏎```wl⏎Sqrt[x]⏎```⏎|One two thre…` | 1 | `# Title⏎⏎```wl⏎Sqrt[x]⏎```⏎|One two thre…` |
| caret end of paragraph | `…three four.⏎```wl⏎Sqrt[x]⏎```|⏎⏎- apple⏎- b…` | 1 | `…three four.⏎```wl⏎Sqrt[x]⏎```⏎|⏎⏎- apple⏎- b…` |
| caret mid-heading | `# Ti⏎```wl⏎Sqrt[x]⏎```⏎|tle⏎⏎One two…` | 1 | `# Ti⏎```wl⏎Sqrt[x]⏎```⏎|tle⏎⏎One two…` |
| armed bar (para/list) | `…hree four.⏎⏎```wl⏎Sqrt[x]⏎```|⏎⏎- apple⏎- ba…` | ✗ (one ⌘Z left the note half undone) | `…hree four.⏎⏎```wl⏎Sqrt[x]⏎```⏎|⏎⏎- apple⏎- ba…` |
| selection part of a line | `… Title⏎⏎One ⏎```wl⏎Sqrt[x]⏎```⏎| four.⏎⏎- ap…` | 1 | `… Title⏎⏎One ⏎```wl⏎Sqrt[x]⏎```⏎| four.⏎⏎- ap…` |
| selection one whole line | `# Title⏎⏎```wl⏎Sqrt[x]⏎```|⏎⏎- apple⏎- …` | 1 | `# Title⏎⏎```wl⏎Sqrt[x]⏎```⏎|⏎⏎- apple⏎- …` |
| selection several lines (list) | `…hree four.⏎⏎```wl⏎Sqrt[x]⏎```|⏎⏎> quoted l…` | 1 | `…hree four.⏎⏎```wl⏎Sqrt[x]⏎```⏎|⏎⏎> quoted l…` |
| selection over two cells | `…e two three ⏎```wl⏎Sqrt[x]⏎```|⏎- banana⏎⏎>…` | 1 | `…e two three ⏎```wl⏎Sqrt[x]⏎```⏎|⏎⏎- apple⏎- …` |
| selection reading as maths | `Area ⏎```wl⏎Sqrt[x]⏎```⏎| here.` | 1 | `Area ⏎```wl⏎Sqrt[x]⏎```⏎| here.` |
| caret in a list item | `… apple⏎- ban⏎```wl⏎Sqrt[x]⏎```⏎|ana⏎⏎> quote…` | 1 | `… apple⏎- ban⏎```wl⏎Sqrt[x]⏎```⏎|ana⏎⏎> quote…` |
| caret in a quote | `…anana⏎⏎> quo⏎```wl⏎Sqrt[x]⏎```⏎|ted line⏎⏎``…` | 1 | `…anana⏎⏎> quo⏎```wl⏎Sqrt[x]⏎```⏎|ted line⏎⏎``…` |
| caret in a code block | `…ython⏎print(⏎```wl⏎Sqrt[x]⏎```⏎|1)⏎```⏎⏎```w…` | 1 | `…ython⏎print(⏎```wl⏎Sqrt[x]⏎```⏎|1)⏎```⏎⏎```w… {open as code}` |
| caret in a maths block | `…⏎```wl⏎Sqrt[⏎```wl⏎Sqrt[x]⏎```⏎|2]⏎```⏎⏎```e…` | 1 | `…⏎```wl⏎Sqrt[⏎```wl⏎Sqrt[x]⏎```⏎|2]⏎```⏎⏎```e… {open as code}` |
| caret in an eval cell | `…val python⏎x⏎```wl⏎Sqrt[x]⏎```⏎| = 1⏎```⏎⏎La…` | 1 | `…val python⏎x⏎```wl⏎Sqrt[x]⏎```⏎| = 1⏎```⏎⏎La… {open as code}` |
| caret in a blank cell | `Above.⏎⏎⏎```wl⏎Sqrt[x]⏎```|⏎⏎⏎Below.` | 1 | `Above.⏎⏎⏎```wl⏎Sqrt[x]⏎```|⏎⏎⏎Below.` |
| caret on empty last line | `Words.⏎```wl⏎Sqrt[x]⏎```⏎|` | 1 | `(no cell to open)` |
| empty note | ````wl⏎Sqrt[x]⏎```⏎|` | 1 | `(no cell to open)` |
| very start of note | ````wl⏎Sqrt[x]⏎```⏎|# Title⏎⏎One…` | 1 | ````wl⏎Sqrt[x]⏎```⏎|# Title⏎⏎One…` |
| very end of note | `…⏎⏎Last line.⏎```wl⏎Sqrt[x]⏎```⏎|` | 1 | `…⏎⏎Last line.⏎```wl⏎Sqrt[x]⏎```⏎|` |
| bar at the very end | `…⏎⏎Last line.⏎⏎```wl⏎Sqrt[x]⏎```⏎|` | THROWS (NSRangeException on ⌘Z) | `…⏎⏎Last line.⏎⏎```wl⏎Sqrt[x]⏎```⏎|` |

Rendered page, nothing open: `# Title⏎```wl⏎Sqrt[x]⏎```⏎⏎⏎One two thr…`

## maths, inline

| context | source pane | undo | rendered page |
|---|---|---|---|
| caret mid-paragraph | `…tle⏎⏎One two`wl:Sqrt[x]`| three four.…` | 1 | `…tle⏎⏎One two`wl:Sqrt[x]`| three four.…` |
| caret start of paragraph | `# Title⏎⏎`wl:Sqrt[x]`|One two thre…` | 1 | `# Title⏎⏎`wl:Sqrt[x]`|One two thre…` |
| caret end of paragraph | `… three four.`wl:Sqrt[x]`|⏎⏎- apple⏎- …` | 1 | `… three four.`wl:Sqrt[x]`|⏎⏎- apple⏎- …` |
| caret mid-heading | `# Ti`wl:Sqrt[x]`|tle⏎⏎One two…` | 1 | `# Ti`wl:Sqrt[x]`|tle⏎⏎One two…` |
| armed bar (para/list) | `…hree four.⏎⏎`wl:Sqrt[x]`|⏎⏎- apple⏎- ba…` | ✗ (one ⌘Z left the note half undone) | `…hree four.⏎⏎`wl:Sqrt[x]`|⏎⏎- apple⏎- ba…` |
| selection part of a line | `… Title⏎⏎One `wl:Sqrt[x]`| four.⏎⏎- ap…` | 1 | `… Title⏎⏎One `wl:Sqrt[x]`| four.⏎⏎- ap…` |
| selection one whole line | `# Title⏎⏎`wl:Sqrt[x]`|⏎⏎- apple⏎- …` | 1 | `# Title⏎⏎`wl:Sqrt[x]`|⏎⏎- apple⏎- …` |
| selection several lines (list) | `…hree four.⏎⏎`wl:Sqrt[x]`|⏎⏎> quoted l…` | 1 | `…hree four.⏎⏎`wl:Sqrt[x]`|⏎⏎> quoted l…` |
| selection over two cells | `…e two three `wl:Sqrt[x]`|⏎- banana⏎⏎>…` | 1 | `…e two three `wl:Sqrt[x]`|⏎⏎- apple⏎- …` |
| selection reading as maths | `Area `wl:Sqrt[x]`| here.` | 1 | `Area `wl:Sqrt[x]`| here.` |
| caret in a list item | `… apple⏎- ban`wl:Sqrt[x]`|ana⏎⏎> quote…` | 1 | `… apple⏎- ban`wl:Sqrt[x]`|ana⏎⏎> quote…` |
| caret in a quote | `…anana⏎⏎> quo`wl:Sqrt[x]`|ted line⏎⏎``…` | 1 | `…anana⏎⏎> quo`wl:Sqrt[x]`|ted line⏎⏎``…` |
| caret in a code block | `…ython⏎print(`wl:Sqrt[x]`|1)⏎```⏎⏎```w…` | 1 | `…ython⏎print(`wl:Sqrt[x]`|1)⏎```⏎⏎```w… {open as code}` |
| caret in a maths block | `…⏎```wl⏎Sqrt[`wl:Sqrt[x]`|2]⏎```⏎⏎```e…` | 1 | `…⏎```wl⏎Sqrt[`wl:Sqrt[x]`|2]⏎```⏎⏎```e… {open as code}` |
| caret in an eval cell | `…val python⏎x`wl:Sqrt[x]`| = 1⏎```⏎⏎La…` | 1 | `…val python⏎x`wl:Sqrt[x]`| = 1⏎```⏎⏎La… {open as code}` |
| caret in a blank cell | `Above.⏎⏎⏎`wl:Sqrt[x]`|⏎⏎⏎Below.` | 1 | `Above.⏎⏎⏎`wl:Sqrt[x]`|⏎⏎⏎Below.` |
| caret on empty last line | `Words.⏎`wl:Sqrt[x]`|` | 1 | `(no cell to open)` |
| empty note | ``wl:Sqrt[x]`|` | 1 | `(no cell to open)` |
| very start of note | ``wl:Sqrt[x]`|# Title⏎⏎One…` | 1 | ``wl:Sqrt[x]`|# Title⏎⏎One…` |
| very end of note | `…⏎⏎Last line.`wl:Sqrt[x]`|` | 1 | `…⏎⏎Last line.`wl:Sqrt[x]`|` |
| bar at the very end | `…⏎⏎Last line.⏎⏎`wl:Sqrt[x]`|` | THROWS (NSRangeException on ⌘Z) | `…⏎⏎Last line.⏎⏎`wl:Sqrt[x]`|` |

Rendered page, nothing open: `# Title`wl:Sqrt[x]`⏎⏎One two th…`

## ⌘9 eval (python)

| context | source pane | undo | rendered page |
|---|---|---|---|
| caret mid-paragraph | `…tle⏎⏎One two| three four.⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` | 1 | `…tle⏎⏎One two| three four.⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` |
| caret start of paragraph | `# Title⏎⏎|One two three four.⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` | 1 | `# Title⏎⏎|One two three four.⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` |
| caret end of paragraph | `…hree four.⏎⏎```eval python⏎⏎```|⏎⏎- apple⏎- ba…` | 1 | `… three four.|⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` |
| caret mid-heading | `# Ti|tle⏎⏎```eval python⏎⏎```⏎⏎One two thre…` | 1 | `# Ti|tle⏎⏎```eval python⏎⏎```⏎⏎One two thre…` |
| armed bar (para/list) | `…hree four.⏎⏎```eval python⏎|⏎```⏎⏎- apple⏎- ba…` | ✗ (one ⌘Z left the note half undone) | `…hree four.⏎⏎```eval python⏎|⏎```⏎⏎- apple⏎- ba… {open as code}` |
| selection part of a line | `… Title⏎⏎One [two three] four.⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` | 1 | `… Title⏎⏎One [two three] four.⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` |
| selection one whole line | `# Title⏎⏎[One two three four.]⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` | 1 | `# Title⏎⏎[One two three four.]⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` |
| selection several lines (list) | `…hree four.⏎⏎[- apple⏎- banana]⏎⏎```eval python⏎⏎```⏎⏎> quoted lin…` | 1 | `…hree four.⏎⏎[- apple⏎- banana]⏎⏎```eval python⏎⏎```⏎⏎> quoted lin…` |
| selection over two cells | `…e two three [four.⏎⏎```eval] python⏎⏎```⏎⏎- apple⏎- ba…` | 1 | `…e two three [four.]⏎⏎```eval python⏎⏎```⏎⏎- apple⏎- ba…` |
| selection reading as maths | `Area [x^2 + 1] here.⏎⏎```eval python⏎⏎```` | 1 | `Area [x^2 + 1] here.⏎⏎```eval python⏎⏎```` |
| caret in a list item | `… apple⏎- ban|ana⏎⏎```eval python⏎⏎```⏎⏎> quoted lin…` | 1 | `… apple⏎- ban|ana⏎⏎```eval python⏎⏎```⏎⏎> quoted lin…` |
| caret in a quote | `…anana⏎⏎> quo|ted line⏎⏎```eval python⏎⏎```⏎⏎```python⏎print…` | 1 | `…anana⏎⏎> quo|ted line⏎⏎```eval python⏎⏎```⏎⏎```python⏎print…` |
| caret in a code block | `…ed line⏎⏎```eval python⏎print(|1)⏎```⏎⏎```w…` | 1 | `…ed line⏎⏎```eval python⏎p|rint(1)⏎```⏎… {open as code}` |
| caret in a maths block | `…(1)⏎```⏎⏎```eval python⏎Sqrt[|2]⏎```⏎⏎```e…` | 1 | `…(1)⏎```⏎⏎```eval pyt|hon⏎Sqrt[2]⏎```… {open as code}` |
| caret in an eval cell | `…val python⏎x| = 1⏎```⏎⏎```eval python⏎⏎```⏎⏎Last line.` | 1 | `…val python⏎x| = 1⏎```⏎⏎```eval python⏎⏎```⏎⏎Last line. {open as code}` |
| caret in a blank cell | `Above.⏎⏎⏎|⏎⏎⏎```eval python⏎⏎```⏎⏎Below.` | 1 | `Above.⏎⏎⏎|⏎⏎⏎```eval python⏎⏎```⏎⏎Below.` |
| caret on empty last line | `Words.⏎⏎⏎```eval python⏎⏎```|` | 1 | `(no cell to open)` |
| empty note | ````eval python⏎⏎```|` | 1 | `(no cell to open)` |
| very start of note | `|# Title⏎⏎```eval python⏎⏎```⏎⏎One two thre…` | 1 | `|# Title⏎⏎```eval python⏎⏎```⏎⏎One two thre…` |
| very end of note | `…⏎⏎Last line.⏎⏎```eval python⏎⏎```|` | 1 | `…⏎⏎Last line.|⏎⏎```eval python⏎⏎```` |
| bar at the very end | `…⏎⏎Last line.⏎⏎```eval python⏎|⏎```` | THROWS (NSRangeException on ⌘Z) | `…⏎⏎Last line.⏎⏎```eval python⏎|⏎``` {open as code}` |

Rendered page, nothing open: `# Title⏎⏎```eval python⏎⏎```⏎⏎One two thre…`

### What was wrong before (read off the tables)

1. **Glued, not a cell.** ⌘8 and display maths put ONE newline either side, so the block sat directly against the
   paragraph above and below — no blank line, no seam, no bar between them (`One two⏎```python…```⏎ three four.`).
   The tail kept its leading space, which the parser keeps as indentation.
2. **Into a list item / quote / heading.** Mid-item the item was split: `- ban⏎```…```⏎ana` — `ana` became a
   paragraph, the list was broken. Same for a quote line (`> quo` … `ted line` lost its `>`) and a heading (`# Ti` …
   `tle`).
3. **Fences inside fences.** ⌘8 in a code, maths or evaluation cell, and display maths inside any fenced cell,
   wrote a fence INSIDE the fence: the inner ``` closed the outer cell and the rest of the note re-parsed wrong.
   Inline maths inside code wrote a literal `` `wl:…` `` into the code.
4. **Selected words thrown away.** The maths palette REPLACED any selection with what it wrote — two selected words
   became `Sqrt[x]`, and the palette never showed the selection.
5. **⌘9 ignored the caret.** It always put the new cell AFTER the caret's whole cell (mid-paragraph, mid-list,
   whatever was selected), and left the caret where it was — outside the cell it had just made, or after its
   closing fence. In an `out` cell it turned the ANSWER into an evaluation cell. In a cell already running Python
   it added a second empty one (its own test said "changes nothing" and only checked a prefix).
6. **⌘8 at a bar dropped the language** (`` ``` `` not `` ```python ``).
7. **Maths at a bar was two steps** (open a plain cell, then insert) — and the bar's opening itself was registered
   on the undo stack TWICE (`openSeam` wrapped `insertText`, which already calls `shouldChangeText` /
   `didChangeText`): one ⌘Z after anything opened at a bar left the note half undone mid-note, and at the bar under
   the last cell **threw an NSRangeException** — typing a character at the tail bar and pressing ⌘Z did it too.
8. **Rendered page:** with a cell open, ⌘8/maths wrote raw fences into that cell's editor (shown as raw text in a
   paragraph box, caret after them); ⌘9 converted an open code cell's fence in the note while the open editor kept
   the OLD fence and wrote it back on the next keystroke; with nothing open everything went into the note's FIRST
   cell. A selection in the rendered editor behaved like the source pane's (same bugs).

# AFTER — the same contexts

## ⌘8 code (python)

| context | both panes (note, ‸ caret) | undo |
|---|---|---|
| caret mid-paragraph | `…e⏎⏎One two⏎⏎```python⏎‸⏎```⏎⏎three four…` | 1 |
| caret start of paragraph | `# Title⏎⏎```python⏎‸⏎```⏎⏎One two th…` | 1 |
| caret end of paragraph | `…ee four.⏎⏎```python⏎‸⏎```⏎⏎- apple⏎- …` | 1 |
| caret mid-heading | `# Title⏎⏎```python⏎‸⏎```⏎⏎One two th…` | 1 |
| armed bar (para/list) | `…ee four.⏎⏎```python⏎‸⏎```⏎⏎- apple⏎- …` | 1 |
| selection part of a line | `…Title⏎⏎One⏎⏎```python⏎two three‸⏎```⏎⏎four.⏎⏎- a…` | 1 |
| selection one whole line | `# Title⏎⏎```python⏎One two three four.‸⏎```⏎⏎- apple⏎…` | 1 |
| selection several lines (list) | `…ee four.⏎⏎```python⏎- apple⏎- banana‸⏎```⏎⏎> quoted…` | 1 |
| selection over two cells | `… two three⏎⏎```python⏎four.⏎⏎- apple‸⏎```⏎⏎- banana⏎…` | 1 |
| selection reading as maths | `Area⏎⏎```python⏎x^2 + 1‸⏎```⏎⏎here.` | 1 |
| caret in a list item | `…- banana⏎⏎```python⏎‸⏎```⏎⏎> quoted l…` | 1 |
| caret in a quote | `…```python⏎‸⏎```⏎⏎```python⏎print(1)⏎`…` | 1 |
| caret in a code block | nothing; footer: “The caret is in a code block already, and a code block cannot go inside one.” | — |
| caret in a maths block | `…]⏎```⏎⏎```python⏎‸⏎```⏎⏎```eval pytho…` | 1 |
| caret in an eval cell | `… = 1⏎```⏎⏎```python⏎‸⏎```⏎⏎Last line.` | 1 |
| caret in a blank cell | `Above.⏎⏎⏎⏎```python⏎‸⏎```⏎⏎⏎⏎Below.` | 1 |
| caret on empty last line | `Words.⏎⏎```python⏎‸⏎```` | 1 |
| empty note | ````python⏎‸⏎```` | 1 |
| very start of note | ````python⏎‸⏎```⏎⏎# Title⏎⏎O…` | 1 |
| very end of note | `…Last line.⏎⏎```python⏎‸⏎```` | 1 |
| bar at the very end | `…Last line.⏎⏎```python⏎‸⏎```` | 1 |

## maths, own line

| context | both panes (note, ‸ caret) | undo |
|---|---|---|
| caret mid-paragraph | `…e⏎⏎One two⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎three four…` | 1 |
| caret start of paragraph | `# Title⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎One two th…` | 1 |
| caret end of paragraph | `…ee four.⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎- apple⏎- …` | 1 |
| caret mid-heading | `# Title⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎One two th…` | 1 |
| armed bar (para/list) | `…ee four.⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎- apple⏎- …` | 1 |
| selection part of a line | `… two three⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎four.⏎⏎- a…` | 1 |
| selection one whole line | `…ee four.⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎- apple⏎- …` | 1 |
| selection several lines (list) | `…- banana⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎> quoted l…` | 1 |
| selection over two cells | `…⏎⏎- apple⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎- banana⏎⏎…` | 1 |
| selection reading as maths | `…ea x^2 + 1⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎here.` | 1 |
| caret in a list item | `…- banana⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎> quoted l…` | 1 |
| caret in a quote | `… line⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎```python⏎pri…` | 1 |
| caret in a code block | `…``wl⏎Sqrt[x]‸⏎```⏎⏎```wl⏎Sqrt[2]⏎```⏎⏎``…` | 1 |
| caret in a maths block | `…``wl⏎Sqrt[Sqrt[x]‸2]⏎```⏎⏎``…` | 1 |
| caret in an eval cell | `… = 1⏎```⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎Last line.` | 1 |
| caret in a blank cell | `Above.⏎⏎⏎⏎```wl⏎Sqrt[x]‸⏎```⏎⏎⏎⏎Below.` | 1 |
| caret on empty last line | `Words.⏎⏎```wl⏎Sqrt[x]‸⏎```` | 1 |
| empty note | ````wl⏎Sqrt[x]‸⏎```` | 1 |
| very start of note | ````wl⏎Sqrt[x]‸⏎```⏎⏎# Title⏎⏎O…` | 1 |
| very end of note | `…Last line.⏎⏎```wl⏎Sqrt[x]‸⏎```` | 1 |
| bar at the very end | `…Last line.⏎⏎```wl⏎Sqrt[x]‸⏎```` | 1 |

## maths, inline

| context | both panes (note, ‸ caret) | undo |
|---|---|---|
| caret mid-paragraph | `…e⏎⏎One two`wl:Sqrt[x]`‸ three fou…` | 1 |
| caret start of paragraph | `# Title⏎⏎`wl:Sqrt[x]`‸One two th…` | 1 |
| caret end of paragraph | `…hree four.`wl:Sqrt[x]`‸⏎⏎- apple⏎…` | 1 |
| caret mid-heading | `# Ti`wl:Sqrt[x]`‸tle⏎⏎One t…` | 1 |
| armed bar (para/list) | `…ee four.⏎⏎`wl:Sqrt[x]`‸⏎⏎- apple⏎- …` | 1 |
| selection part of a line | `… two three`wl:Sqrt[x]`‸ four.⏎⏎- …` | 1 |
| selection one whole line | `…hree four.`wl:Sqrt[x]`‸⏎⏎- apple⏎…` | 1 |
| selection several lines (list) | `…e⏎- banana`wl:Sqrt[x]`‸⏎⏎> quoted…` | 1 |
| selection over two cells | `….⏎⏎- apple`wl:Sqrt[x]`‸⏎- banana⏎…` | 1 |
| selection reading as maths | `…ea x^2 + 1`wl:Sqrt[x]`‸ here.` | 1 |
| caret in a list item | `…pple⏎- ban`wl:Sqrt[x]`‸ana⏎⏎> quo…` | 1 |
| caret in a quote | `…ana⏎⏎> quo`wl:Sqrt[x]`‸ted line⏎⏎…` | 1 |
| caret in a code block | nothing; footer: “Maths goes in words or in a maths block — inside code it would only be typed as code.” | — |
| caret in a maths block | `…``wl⏎Sqrt[Sqrt[x]‸2]⏎```⏎⏎``…` | 1 |
| caret in an eval cell | nothing; footer: “Maths goes in words or in a maths block — inside code it would only be typed as code.” | — |
| caret in a blank cell | `Above.⏎⏎⏎⏎`wl:Sqrt[x]`‸⏎⏎⏎⏎Below.` | 1 |
| caret on empty last line | `Words.⏎⏎`wl:Sqrt[x]`‸` | 1 |
| empty note | ``wl:Sqrt[x]`‸` | 1 |
| very start of note | `# `wl:Sqrt[x]`‸Title⏎⏎One…` | 1 |
| very end of note | `…Last line.`wl:Sqrt[x]`‸` | 1 |
| bar at the very end | `…Last line.⏎⏎`wl:Sqrt[x]`‸` | 1 |

## ⌘9 eval (python)

| context | both panes (note, ‸ caret) | undo |
|---|---|---|
| caret mid-paragraph | `…e⏎⏎One two⏎⏎```eval python⏎‸⏎```⏎⏎three four…` | 1 |
| caret start of paragraph | `# Title⏎⏎```eval python⏎‸⏎```⏎⏎One two th…` | 1 |
| caret end of paragraph | `…ee four.⏎⏎```eval python⏎‸⏎```⏎⏎- apple⏎- …` | 1 |
| caret mid-heading | `# Title⏎⏎```eval python⏎‸⏎```⏎⏎One two th…` | 1 |
| armed bar (para/list) | `…ee four.⏎⏎```eval python⏎‸⏎```⏎⏎- apple⏎- …` | 1 |
| selection part of a line | `…Title⏎⏎One⏎⏎```eval python⏎two three‸⏎```⏎⏎four.⏎⏎- a…` | 1 |
| selection one whole line | `# Title⏎⏎```eval python⏎One two three four.‸⏎```⏎⏎- apple⏎…` | 1 |
| selection several lines (list) | `…ee four.⏎⏎```eval python⏎- apple⏎- banana‸⏎```⏎⏎> quoted…` | 1 |
| selection over two cells | `… two three⏎⏎```eval python⏎four.⏎⏎- apple‸⏎```⏎⏎- banana⏎…` | 1 |
| selection reading as maths | `Area⏎⏎```eval python⏎x^2 + 1‸⏎```⏎⏎here.` | 1 |
| caret in a list item | `…- banana⏎⏎```eval python⏎‸⏎```⏎⏎> quoted l…` | 1 |
| caret in a quote | `… line⏎⏎```eval python⏎‸⏎```⏎⏎```python⏎pri…` | 1 |
| caret in a code block | `… line⏎⏎```eval python⏎print(‸1)⏎```⏎⏎``…` | 1 |
| caret in a maths block | `…)⏎```⏎⏎```eval python⏎Sqrt[‸2]⏎```⏎⏎``…` | 1 |
| caret in an eval cell | nothing; footer: “This is a Python evaluation cell already.” | — |
| caret in a blank cell | `Above.⏎⏎⏎⏎```eval python⏎‸⏎```⏎⏎⏎⏎Below.` | 1 |
| caret on empty last line | `Words.⏎⏎```eval python⏎‸⏎```` | 1 |
| empty note | ````eval python⏎‸⏎```` | 1 |
| very start of note | ````eval python⏎‸⏎```⏎⏎# Title⏎⏎O…` | 1 |
| very end of note | `…Last line.⏎⏎```eval python⏎‸⏎```` | 1 |
| bar at the very end | `…Last line.⏎⏎```eval python⏎‸⏎```` | 1 |

### The rules now (`WriteMind/Editor/Insertion.swift`)

1. At the armed bar the cell is made there (unchanged), now with ⌘8's language and as one undo step.
2. Inside a fenced block nothing is ever nested. Same kind → nothing, and the footer says why (⌘8 in a code
   block; ⌘9 in a cell already running in that environment). ⌘9 in any other fenced cell converts it (Sean's
   2026-09-21 rule) — except an `out` answer, after which a new cell is made. Maths in a block that is already
   Wolfram Language (```wl, ```eval wl, Wolfram code) goes in as the bare WL at the caret. Anything else goes AFTER
   the block as its own cell — after its answer when it has one. Inline maths in non-WL code is refused (footer).
3. A block is a cell of its own (blank line above and below). A paragraph is cut at the caret (spaces at the cut
   dropped); at the front of its words the block goes above, at the end below. Line cells — heading, list, quote,
   rule — are cut only between lines: above the caret's line when the caret is at the front of its words or in its
   marker, below it otherwise. On an empty line of a blank cell the block takes that one line.
4. A selection becomes the content: code/eval verbatim, the text either side staying cells (a marker or indent left
   with no words goes with them). Maths replaces a selection only when it still HOLDS it (the selection reads as
   WL and is a whole term of the maths); otherwise the words stay and the maths goes after them. The palette opens
   SEEDED from a selection that reads as maths (inline when it sits inside a line). A selection containing a fence
   is refused (footer).
5. The caret ends where typing goes: between an empty block's fences, at the end of the content, at the end of
   display maths' WL, after inline maths.
6. One ⌘Z takes the whole insertion back — the source pane applies one edit; the rendered page applies it to the
   note and puts the way back on the new cell's editor's undo stack. An insertion that stays in the open cell's
   words (inline maths, bare WL) goes through that editor.
7. Both panes ask the one function with the note and the caret in it; the rendered page reads its caret out of the
   open cell (past the fence line for a code cell).

### Uncertain / not done

- Maths with a selection that does not read as maths: the brief said "else wrapped"; I chose to KEEP the words and
  put the maths after them, because wrapping prose in a maths span/block is never what is meant and throwing it
  away was bug 4. Flag if "wrapped" meant something specific.
- Maths in a maths block goes in bare at the caret rather than "does nothing": the palette's α, ∑, ∞ are exactly what
  composing a ```wl block needs. A caret mid-expression gives what it gives (`Sqrt[Sqrt[x]2]`).
- ⌘9 inside a ```wl MATHS block still converts it (existing rule) — with the Python evaluator that makes WL code a
  Python cell. Left as Sean's rule; worth a look.
- The rendered page's undo for an insertion lives on the new cell's editor: clicking out of that cell drops it, the
  way every keystroke's undo on that page is dropped when its cell closes.
- `EditorBridge.insert(_:belowDocumentY:)` (the words read off a picture) wraps `insertText` in a second
  `shouldChangeText`/`didChangeText` pair exactly as `openSeam` did — very likely the same double undo
  registration. Not touched (outside this part); worth its own fix.
