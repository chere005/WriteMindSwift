# WriteMind

<img src="assets/logo-512.png" width="80" alt="The WriteMind mark: a one-stroke WM">

A macOS writing app: markdown notes on the left, a live camera on the right.
Photograph a notebook page and the writing comes onto the page as ink, as a
picture, or as text; draw over it, sketch a flow chart, and the notes stay
plain `.md` files in `~/Documents/WriteMind`.

- [What it does](docs/FEATURES.md) — the whole tour
- [AGENTS.md](AGENTS.md) — how the code is put together, and the rules for
  working in it
- [docs/TODO.md](docs/TODO.md) — what is next

## The keys

Every one of these is in the menu bar too — this is the same list, in one
place. `Shortcut` in the app holds it, and a test reads this table back and
fails if the two disagree.

**The note**

| | |
| --- | --- |
| ⌘N | New note |
| ⌘W | Close tab |
| ⌘S | Save what has not reached disk yet (it saves itself half a second after you stop typing) |
| ⌘E | Export — the note as a PDF, or the project (the folders); the format is chosen in the save panel |
| ⇧⌘O | Open the notes folder in Finder |

**What is on screen**

| | |
| --- | --- |
| ⌘T | Markdown ⇄ the rendered page |
| ⌘P | Pen up, pen down |
| ⌘Y | Show or hide the video — or the tablet's page, when the tablet is the input |
| ⌘K | Show or hide the notes list |
| ⌘; | Collapse what is under this cell — or under each cell that is held — and open it again |
| ⌥⇧⌘← ⌥⇧⌘→ | Fold, unfold every section |

**Writing**

| | |
| --- | --- |
| ⌘1 ⌘2 ⌘3 ⌘4 ⌘5 ⌘6 ⌘7 | Title, Chapter, Author, Section, Subsection, Subsubsection, Body Text |
| ⌘B ⌘I ⌘U | Bold, italic, underline |
| ⇧⌘X | Strikethrough |
| ⇧⌘L | List, in whichever style the bar is set to |
| ⌃⌘Q | Quote |
| ⌘8 | Code block |
| ⌘9 | An evaluation cell here — or turn this cell into one |
| ⌘0 | A drawing cell here |
| ⌘] ⌘[ | Indent, outdent |
| ⇧⌘I | Insert a picture |

**Cells and sections**

| | |
| --- | --- |
| ⌃D ⌃M | Split a cell, merge it with the one below |
| ⌃⇧D | Duplicate the cell |
| ⌫ | Delete the cells that are held |
| ⌃⇧↑ ⌃⇧↓ | Move the cell |
| ⌃⌘↑ ⌃⌘↓ | Move the whole section |
| ⌘. | Grow the selection: word, cell, section, note |
| ⌘D ⇧⌘D | Select the next occurrence, select them all |

**Undo**

| | |
| --- | --- |
| ⌘Z ⇧⌘Z | Undo, redo |
| ⌥⌘Z ⌥⇧⌘Z | Undo, redo on the drawing layer, whatever has the keyboard |

**The project, and the camera**

| | |
| --- | --- |
| ⇧⌘S | Save the project |
| ⇧⌘A | Add a folder to the project |
| ⌥⌘R | Look for cameras again |

Inside an evaluation cell, **⇧↩** runs it and the answer goes in an
`out` cell underneath. That one belongs to the cell rather than to a menu:
a menu would take ⇧↩ away from every other piece of text in the app.

Held down rather than pressed: **⌘** pulls a selection rectangle over the
page in either mode, and keeps a mark or an arrow armed after one has been
put down; **⇧** holds a line or an arrow to the horizontal or the vertical;
**⌥** drags a connector out of a flow-chart node.

macOS 14 or later. No dependencies, no package manager.

```sh
sh tools/setup-signing.sh   # once: a local signing certificate
sh tools/run.sh             # Debug build, then open it
sh tools/test.sh            # the unit suite
sh tools/deploy.sh          # Release into /Applications
```

[Building and shipping](docs/BUILDING.md)
