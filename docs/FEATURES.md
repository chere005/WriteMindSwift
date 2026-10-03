# What WriteMind does

The tour. [README](../README.md) is the short version; [AGENTS.md](../AGENTS.md)
is how the code is put together.

- **Notes are files.** `~/Documents/WriteMind/*.md`, one per note, readable
  by anything. The title is the note's first `# heading`, or its file name.
- **Sections are folders.** Make a section in the sidebar and it is a folder
  on disk; a folder inside it is a subsection. The section you have selected
  is where the next new note goes. Drag a note — or a whole section — into
  another one and the file really moves, so Finder agrees with the sidebar.
- **An edit button** puts duplicate and delete on every row, and the order
  you drag rows into is remembered.
- **A markdown editor, and a preview of it.** The bar sits over the editor
  pane; the button on its right lights up while the preview is showing
  (⌘T). Bold, italic, underline, bullets and quote are on the left
  (⌘B ⌘I ⌘U ⇧⌘L ⌃⌘Q); they wrap or unwrap the selection, and undo knows
  about it.
- **Six heading levels, named the way you'd say them.** Title, Chapter,
  Author, Section, Subsection and Subsubsection — the Author line renders
  italic and slightly bigger than the body text. From the `aA` menu, the
  Format menu, or ⌘1 title, ⌘2 chapter, ⌘3 author, ⌘4–⌘6 section to
  subsubsection, ⌘7 back to body.
- **To-do bullets.** A fourth kind of list: `- [ ]` and `- [x]`, GFM's
  own task list, so any other markdown editor reads them too. The list
  button's chevron picks it, the `+` on the insertion bar offers it, and
  Return carries the list on with a fresh empty box. On the rendered page
  the box is a control — click it and the line is ticked, struck through
  and faded; click it again and it is not. Only the box: a click on the
  words opens the cell for typing like any other.
- **Code cells behave like a code editor.** In a fenced block, `(`, `[`,
  `{`, `"`, `'` and a backtick bring their partner; typing the closer
  steps over it; a bracket typed with something selected wraps it;
  backspace between the two takes both; and Tab — or Shift-Tab — indents
  by a four-space-wide tab, every line of a selection at once. Colouring
  knows C, C++, Python, TypeScript, Rust, Java, Bash, Zsh and Wolfram.
- **Split a cell, merge two.** ⌃D cuts the cell the cursor is in, in two,
  at the cursor; ⌃M joins it to the one below (or, in the last cell, to the
  one above). Both work in the markdown and on the rendered page. A fence
  is never cut in half, and a heading will not swallow the cell under it.
  They are the only two keys that do either: Return inside a cell is a
  line break within it, and ⌫ at the very start of a cell does nothing
  (Sean, 2026-10-02: "return should be a newline, backspace at beginning
  does nothing").
- **A cell is a thing you can hold.** Click its bracket and the whole
  cell is picked up, not a run of characters: type and it is replaced,
  ⌫ takes it away and the stack closes behind it, ⌃⇧D puts a copy under
  it, ⌃⇧↑ and ⌃⇧↓ move it, and dragging its bracket up or down moves it
  too. The same on both sides of the app, the way a Mathematica notebook
  behaves (Sean, 2026-09-20).
- **And several cells at once.** Drag DOWN the brackets and every cell the
  pointer passes is picked up, live; shift-click reaches from the last one
  clicked to the one under the pointer; cmd-click puts a cell in or takes
  it out, so a selection can have a hole in it. Everything a single cell
  answers to, a handful answers to together: type and all of them are
  replaced by one cell holding what you typed, ⌫ or ⌦ takes exactly them
  and closes the stack, Escape lets go of them, ⌃⇧D copies the run, and
  ⌃⇧↑/⌃⇧↓ walk the whole run up or down the page and leave it held, so
  pressing again moves the same run again. A drag
  that starts on a bracket that is ALREADY HELD moves the run instead —
  that is how both gestures live on one column — and a click on one that
  is held, with no drag, takes that one alone. The bracket the caret is
  merely sitting in does not count as held, or there would be nowhere to
  start a selection from; and a click on the column where there is no
  bracket goes to the text behind it, the way the right margin always has.
- **The insertion line between cells.** The WHOLE space between two cells
  answers, edge to edge — and so does the space above the first and
  everything under the last. Move the pointer into one and it turns on
  its side; click and a line runs across the page with a `+` at the
  margin. The line is drawn against the cell it follows, however tall
  the space is — clicking a long way under the last cell puts it just
  below that cell, not where the pointer happened to be. That line is
  the cursor: the caret stops being drawn, no bracket is lit while it is
  up, and the first thing typed becomes a cell of its own there, Return
  opens an empty one, and Escape or a click anywhere else takes the line
  back without leaving an empty cell behind — as does every other key:
  ⌫, ⌦ and Tab at the line touch neither cell beside it, and a key that
  only moves or scrolls, ⌘↓, ⇧↓ or Page Down, puts the line away and
  then does just that. Press the `+`
  at the end of the line and it drops the kinds of cell down — Body Text, the heading
  ladder from Title to Subsubsection, the three lists, Quote, Code Block
  — and the next thing typed makes a cell of the kind you picked, with
  its marker already written and the caret after it. The Format menu is
  the same list by keyboard: ⌘1 or Quote or a list style at a line picks
  the kind that line will make, rather than restyling the cell beside it,
  and pressing the `+` again shows what you picked. The choice belongs
  to that line and goes with it: click the bar somewhere else and you are
  back to plain text, which is what every bar starts out as. On a
  note with nothing in it yet the line sits where the first cell will
  land, not against the top of the pane. The seams belong to cursor
  mode: with the pen down the drawing layer has the pane and there
  are no seams at all. The markdown pane and the
  rendered page do exactly the same thing, the way a Mathematica notebook
  does on both.
- **The arrow keys walk cell, line, cell.** The line is not only what a
  click makes: ↓ off the bottom of a cell lands ON it, ↓ again goes into
  the next cell, and ↑ comes back the same way — the line above the first
  cell and the one under the last included (not under a code block still
  waiting for its closing fence: the end of the note is in its code, and
  ↓ stays there). Return at the end of a cell
  leaves you on the line under it too, so what you type next is a cell
  of its own; anywhere inside a cell it is a line break within the cell,
  never a split. Getting there by arrow and getting there by click leave
  the page in the same state — type and you get a new cell between the
  two, not a character that welds them into one.
- **The same place, whichever mode.** Switching between the markdown and
  the rendered page (⌘T) reopens on the line you were looking at — the
  same cell and the same way into it, or the same gap between two cells
  — with the caret where it was (the cell it is in opens round it on the
  rendered page), the bar between two cells still armed with whatever its
  + chose, and the cells held by their brackets still held. A picture, a
  stroke or a flow chart sits beside the same words in both modes, and on
  paper: the two modes space the cells differently, and the drawing goes
  with the cells rather than with a number of points down the page.
- **Sections of a note are cells.** A heading owns everything under it
  until the next heading of its rank, and the brackets down the right-hand
  side show the nesting the way a Wolfram notebook does. Click one to fold
  that section away — the note itself is untouched, the caret steps over
  what is hidden, and what you closed is still closed when you come back.
  ⌃⌘↑ and ⌃⌘↓ move the whole section, everything nested in it included.
- **Code is what is inside backticks, and nothing else.** ``` for a
  block, ` for a span, `` `` `` for a span with a backtick in it (Sean,
  2026-09-20). Four spaces at the front of a line is indentation — it is
  drawn indented and stays a paragraph — so Tab is safe anywhere.
- **Indentation that follows the structure.** ⌘] and ⌘[ — or Tab and
  Shift-Tab — move the lines you're on in and out; a quote gains another
  level, anything else gains two spaces. Backspace inside a line's
  indentation takes a level off instead of a character.
- **Link to a note, or to one part of one.** Type `/link` and a banner asks
  you to select the section to point to: open another note, put the cursor in
  a block — or highlight the exact run of text — and click Link Here. The
  highlighted text is marked in that note as linked to, and the link lands
  where you typed `/link`. Links are clickable in the preview.
- **Write in the preview.** Click any block and it opens where it is, with
  its markdown styled as you type — the `**` fades, the word goes bold, a
  heading is heading-sized — and every button on the bar works on it: bold,
  the heading ladder, lists, quotes, indentation, text style, maths. Return
  at the end of a block starts the next one and inside it is a line break
  (in a list it carries the list on), ⌫ in an empty block takes it away
  and at the start of a full one does nothing, ↑ and ↓ move between
  blocks, and the line that appears
  between two blocks adds one there. Only the block you are in is ever
  rewritten; the rest of the file is never touched.
- **A notebook page, off the camera.** With the camera on a dotted notebook,
  the viewfinder button brings the page in: found and squared up first, so a
  notebook that was crooked in the frame comes in straight. The chevron
  beside it picks what arrives — **just the writing**, lifted off the paper
  in the pen's colour with the printed dots left behind — traced into
  outlines and brought in as a vector, so blowing it up keeps the strokes
  sharp — **the whole
  page** as a picture, trimmed to its edges, or **the raw picture** exactly
  as the camera sees it. Either way it is an object you
  can move, scale and rotate like any other, and every page comes in at the
  same size: the notebook's page shape is learned from the first capture and
  kept, so pages line up instead of each being as big as the camera happened
  to see it. The page's own edge is trimmed away on the way in.
- **A section of the page.** The dashed-box button on the video pane lets
  you drag a box over part of the picture and bring in just that — the
  writing inside it, or the picture — squared up and placed where it was on
  the page.
- **The words in a picture, into the note.** Select a picture — a pasted
  screenshot, a captured page, a chunk of writing — and the read button under
  it recognises the text and puts it into the note just below the picture.
  English and Japanese both, kana and numbers included: a Japanese-first
  reading is tried and kept when it finds any, so an English page keeps the
  accuracy an English-first reading gives it. What comes back is markdown —
  a word with a line through it arrives struck out, a word with a ring round
  it in bold, a drawn arrow as →, and a line of algebra as this app's maths,
  raised digits and all. The picture itself is put away rather than deleted,
  and the Revert button on the bar brings it back and takes the words out
  again.
- **A flow chart sketched on paper comes in as a flow chart.** Reading a
  picture that holds one brings the boxes in as nodes — rectangles, rounded
  rectangles, ovals, diamonds, triangles and parallelograms — with the
  words inside them as their
  labels, and the arrows between them as real connectors that follow the
  nodes when they move. It is deliberately hard to trigger: a node is found
  as the PAPER a drawn outline encloses (which survives an arrow touching
  the box), every candidate is named again by a classifier that refuses
  anything it cannot name, a line with nothing at either end is never a
  connector, an arrowhead is only drawn where a barb was actually seen,
  and nothing at all comes out unless the page holds two nodes, or one with
  an arrow on it. A page of ordinary writing gives nothing.
- **Printed dots are not text.** A dot-grid page is recognised by the
  regularity of its dots, which are painted out in the paper's own colour
  before anything is read — so a row of dots never arrives as "・・・".
- **Lists that carry on.** Return at the end of a bullet or a numbered
  item starts the next one; Return on an empty item ends the list. The
  chevron beside the list button picks dots, dashes or numbers — `- `, `* `
  and `1. ` on disk, a round bullet, a dash and a number on the page.
- **The gutter says what it would take.** Hovering a bracket washes the
  cells a click on it would select, faintly — which matters for the ones
  that stand for more than themselves: a section's bracket takes every
  cell under it, an evaluation pair's takes the code and its answer.
- **Evaluation cells, which are not code cells.** A code cell is code you
  are writing about; an evaluation cell is code the note runs, and the file
  says which: ```eval wl, ```eval python, ```eval c, ```eval c++,
  ```eval rust. ⌘9 makes one where the caret is — the way a code block
  goes in, below — or turns a code cell the caret is in into one, the code
  kept; in a cell already running that way it does nothing and the footer
  says so, and in an answer it makes a new cell under the answer. ⇧↩ runs it,
  and nothing else does. At its far left is a badge saying which
  environment it is — click it to pick another and the fence is rewritten
  — and once the cell has been run that becomes `In[n]`, with `Out[n]`
  beside the answer, the way a notebook marks a pair. The mark stays put
  while the cell is open for typing. The answer lands in an ```out
  cell underneath, and running again replaces that answer rather than
  piling another one up. A line in square brackets is the app talking
  (`[no output]`, `[exit 1]`, `[stderr]`); every other line came out of
  the program. The cell and its answer are drawn as ONE GROUP — a bracket
  in the gutter standing round the pair, with each of the two inside it —
  and the cursor is left as the horizontal bar under the answer, ready for
  the next thing; the page scrolls to it, however long the answer was. Any
  cell with an `out` cell under it is a pair, including the ones written
  before evaluation cells had a fence of their own. Nothing runs by itself
  — not on opening a note, not on saving — a plain code cell never runs at
  all, and neither does a cell whose closing ``` has not been typed yet.
- **Code blocks, in five languages.** The `</>` button (⌘8) fences the
  selection or opens an empty block; its chevron tags the fence C, C++,
  Wolfram, Python or TypeScript — at the insertion line too — and the block
  is coloured — in the editor and in the preview — by a palette that has a
  light and a dark half, so it reads either way round.
- **A block always lands as a cell of its own.** A code block, an
  evaluation cell or maths on its own line goes in with a blank line above
  and below it, never glued to the words: in the middle of a paragraph the
  paragraph is cut there and the block goes between the halves — never
  through `code`, maths, **bold** or a link, and never so that the words
  after it would start a list or a heading; in a heading, a list or a
  quote it goes above or below the line the caret is on, so no item is
  split, and part of an item's words selected come out of it while the
  item keeps its bullet; at the insertion line it is made there. What was
  selected becomes what the block holds, and the caret ends inside it,
  where typing goes. A block is never put inside another: ⌘8 in a code
  block does nothing and the footer says why, and anything else asked for
  inside a fenced cell goes in after it — after its answer, when it has
  one, and with the cell's closing ``` written first if it was not typed
  yet. ⌘Z takes the whole of it back in one step, in both panes, and on
  the rendered page what was typed in the cell before stays undoable.
- **Strikethrough.** ⇧⌘X, written `~~like this~~`, struck through in the
  editor and in the preview.
- **Crop a picture.** Select one and the crop button sits at its bottom
  left: drag the corners of the box, then ↩ (or the tick) keeps what is
  inside; esc leaves it alone. ⌘Z on the drawing layer brings the rest back.
- **Flow charts.** The shapes button arms a rectangle, rounded rectangle,
  oval, diamond, triangle or parallelogram; drag on the page from one corner
  to the other and that is where it goes, or click once for one at its own
  size. The shape stays picked — the shapes button stays lit and the
  footer says which — so the next drag draws the next one, until Esc, the
  pen, another tool or the same shape picked again puts it away; a text
  box, a picture or a capture put on the page puts it away too, so the
  next click picks up what arrived. Double-click a node to give it a
  label, with the shape still picked or not: a click on a node picks it
  rather than stacking another on top, and the next drag after the label
  draws the next box. Hold ⌥ and drag from a node
  to draw an arrow — or turn the arrow tool on and drag from anywhere. An
  arrow between two nodes is routed like draw.io's: right angles, the fewest
  corners that join them, round anything in the way, and into its own lane
  when two would run down the same corridor. Every segment carries a small
  circle at its middle — drag it and that part of the line moves, the rest
  following, and where you let go is where it stays. A bar picks the head at
  either end (or none) and a solid, dashed or dotted line. Delete a node and
  its arrows go with it.
- **Text boxes.** The text-box button drops a card you type straight into;
  it floats over the page like a picture — drag, scale, turn, arrow to it —
  and grows to fit what you write, line by line as you write it. What you
  type sits exactly where it will be drawn, in the same font and the same
  padding, so nothing shifts when the caret leaves. Give the card a fill and
  the words are checked against it: ink that would be unreadable on that
  colour is swapped for black or white.
- **The layer floats over the note and never moves it.** A picture, a
  captured page, a text box, ink, a flow chart — none of them is a cell,
  none of them belongs to one, and none of them opens a hole in the words
  (Sean, 2026-09-20: "floating objects like images, drawing, text fields,
  etc completely separate from the cells"). They sit in the note's own
  coordinates and scroll with it; drag one about, move a cell, switch
  modes, and the text stays exactly where it was. A pasted or captured
  picture is dropped one gap under the line the cursor is on, flush with
  the text, and is yours to move from there.
- **Marks.** The next button holds the things drawn all the time — a tick,
  a cross, a query, a star, boxes, circles, triangles, arrows and lines.
  Pick one and then click where it goes: it lands the size of a line of
  writing, a green tick, a red cross and a yellow query, and the handles
  move, size and turn it from there. Drag instead of clicking to size it as
  it goes down; a line or an arrow runs from the press to the release. A
  tick, a cross, a query, a star, a box, a circle, a triangle, a line or
  an arrow all stay picked after one is down — a row of ticks is one trip
  to the palette — with the marks button lit, until Esc, the same tile
  again, or another tool. A tick clicked onto a box goes down in it.
- **A folder can leave the project without leaving the disk.** Right-click
  a folder in the sidebar: *Remove Folder from Project* hides it (Folder ▸
  Hidden Folders brings it back); *Move to Trash* is the one that moves it.
- **⌫ deletes what you last selected** on the drawing layer — writing, ink or
  a picture. ⌘V pastes a picture wherever you are, source or preview. A middle
  click closes a tab.
- **Font, size and colour** for the selected text, from the T button. It
  writes a `<span style="…">`, so other markdown apps still read the note.
- **⌘D, as in Sublime Text.** The word under the cursor, then one more
  occurrence per press, all editable at once. ⇧⌘D takes every one.
- **The viewfinder is whatever shape you want it.** Input Devices ▸ Aspect
  Ratio: Free, 1:1, 4:3, 3:2, 16:9 and the three upright ones. The picture
  is laid out in the largest rectangle of that shape the pane holds, and
  everything that already worked on the picture — the box you drag, the
  zoom, what the capture brings in — works inside it unchanged. Remembered,
  like the turn and the zoom.
- **Double-click the picture and the window IS the picture.** The notes,
  the list and the divider go; the page you are holding up to the camera
  gets the whole screen. Double-click again to come back, or press the
  faint × over the top-left corner. With nothing boxed, a single click
  boxes the whole picture — that was the double-click's job until the
  double-click got a better one.
- **It opens side by side.** Every launch shows the notes and the video
  together, whatever was put away last time.
- **A checklist edits one line at a time.** Click a reminder's words and
  just those words open for typing: the boxes stay boxes and stay tickable,
  including the one beside the line being typed in. Return makes the next
  reminder, ⌫ in an empty one takes it away, ⌫ at the start of a full one
  joins it to the line above, ↑ and ↓ walk the list. The whole list still
  opens as markdown from its bracket in the gutter.
- **Collapse what you're not using.** The notes list and the video from the
  sidebar's header; the notes pane from the corner of the video. ⌘K, ⌘Y.
- **The five keys you reach for.** ⌘S saves what has not reached disk yet
  (it saves itself half a second after you stop typing anyway), ⌘P puts the
  pen up and down (Esc puts it down too), ⌘E exports (PDF, or the project), ⌘T turns the markdown into
  the page and back, ⌘Y shows and hides the video. Every key the app binds
  is in one list (`Shortcut`) and a test says no two commands want the same
  one — ⌃⌘S was quietly on two of them until 2026-09-21.
- **Two modes over one page, and one button between them.** The drawing
  layer is there in the markdown and on the rendered page alike — the
  drawing belongs to the note, not to one way of looking at it — and the
  pen button says which mode the pane is in: press it to put the pen down
  or pick it up. With the pen **up** the notebook has the clicks: the
  words, the bars between the cells and the brackets, and the drawings are
  things you can handle — drag one to move it, or use the buttons that
  appear (move, turn, resize, delete). With the pen **down** it draws, and
  the pointer is a pencil over that pane and nowhere else. In either mode,
  hold **⌘ and drag** to pull a rectangle over the page: it takes
  everything it *touches*, whole or not. The mode is remembered between
  launches and the footer names it whenever the pen is down. **Drawing is
  on the rendered page only**: picking the pen, a shape, a mark or the
  arrow tool while the markdown view shows brings the rendered page up
  under it, ⌘T back to markdown puts the tool down, and the tablet writes
  on the notes only while the rendered page shows. What is drawn shows in
  both views.
- **Several things held as one.** Pick two or more — a marquee, or ⇧-click
  — and **⌃G** holds them together; the same key on a group you have picked
  takes it apart, and a button beside the selection says which it will do.
  After that, clicking any one of them picks up all of them, a rectangle
  that touches one brings the rest, and move, resize, turn and delete are
  over the whole group. Grouping and ungrouping move nothing: a group is
  only a name they share. (The rendered page shows a group moved by its
  top-left corner, so there a member can settle a few points over when it
  joins or leaves one; the markdown, which is what is saved, never moves.)
  Pick a group and something loose together and ⌃G makes one bigger group
  of the lot, so groups nest by swallowing rather than by stacking.
  The pen button itself is still the pen, on and off; its menu also picks
  the size and the colour (a circular colour well plus six swatches). ⌘Z
  undoes a stroke while the pen is up — ⇧⌘Z puts it back — and Undo Drawing
  sits in the Edit menu at ⌥⌘Z whatever has the keyboard.
  Write with a pen on a drawing tablet and the line is **ink**: it thickens
  and thins with how hard the nib is pressed, its ends are round the way a
  ballpoint's are, and a tap is a dot — however quick or shaky the tap,
  and the harder it pressed, the bigger the dot. The pen menu picks what
  the tablet's pen writes with — **pen, fountain pen, pencil, marker or
  brush**. A mouse or the trackpad still draws the even line it always
  did, and nothing already drawn changes.
- **Pictures on the page.** The image button adds one, ⌘V pastes one, and
  they behave like any other object on the layer. Files live in
  `.drawings/media/`; a note's own copies go with it when it moves and go
  when it does.
- **Maths, written as Wolfram Language.** The `f(x)` button opens a pane of
  shapes — integrals with their bounds (single, double and contour), sums
  and infinite series, Taylor series, limits including one-sided ones,
  ordinary, partial and mixed derivatives, grad, div, curl and the
  Laplacian, exponents, roots, fractions, matrices, the trigonometric and
  hyperbolic functions, π, e, ∞, ℝ ℤ ℚ ℂ, ± ≈ ≡ ∝ ∀ ∃ ⇒ ⇔ ∴ ⊥ ∠ and the
  Greek alphabet.
  Fill in the parts, watch it set, and insert it inline or on its own line.
  What the note holds is the WL — `Integrate[x^2, {x, 0, 1}]` — in a code
  span or a ```wl block, so the file is still plain markdown; the preview
  typesets it. Open it over a selection that reads as maths — `x^2 + 1` —
  and it starts from that: Insert sets exactly the selection, in the
  sentence when it sits in one, and a shape picked first wraps it (√ of
  it). Selected words are never thrown away; the maths goes after them.
  A line taken with a triple-click counts. Inside a maths block — or a
  Wolfram cell, or inline maths — what the palette writes goes in as plain
  WL where the caret is, which is how a Greek letter or a ∑ is added to
  maths already there; inside `code` inline maths is refused.
- **Any camera the Mac can see.** The **Input Devices** menu in the menu bar
  lists built-in, USB, Continuity Camera and Desk View devices with a
  checkmark on the live one; plugging one in refreshes the list. The
  camera you pick is remembered; a first launch never asks. Two buttons in
  the corner turn the picture a quarter turn either way, for a camera that
  is mounted sideways.
- **A drawing tablet instead of the camera.** A Wacom tablet plugged in
  is listed in **Input Devices** under the cameras; pick it and the
  pane that showed the video shows a **page** — a sheet at the tablet's
  own shape, read turned a quarter turn clockwise unless you say
  otherwise. **Say how the tablet sits** with the little tablet in the
  page's corner, drawn the way it lies — the lit dot on it is the
  tablet's own status light, so find the light on the tablet and pick
  the picture that has it on the same side: **Landscape** (as it ships,
  light on the left), **Portrait — turned right** (the default, light
  at the top), **Landscape — upside down** (light on the right) or
  **Portrait — turned left** (light at the bottom) — the last two are
  the "flipped" ones, for the other hand. The page turns
  to match and what is written on it turns with it — each stroke stays
  where it is on the tablet, a box left up stays round the same writing
  — and the paper's lines are laid out again for the new shape, the
  margin on the left (held landscape, a ruled page's lines run across
  the long side). A turn is not something ⌘Z takes back: turn it back
  the same way. It holds in the notebook too. The pen writes on it in
  ink that follows its pressure; a tap is a dot, and a ring follows the
  nib while it hovers. The page has **a pen of its own**, on a small bar
  top left above the sheet: the tool (pen, fountain pen, pencil, marker,
  brush), the colour (the six swatches — seven on the blackboard, with
  chalk — or any colour) and the size as you see it — new strokes take
  them, what is written keeps its own. Beside it, **the paper**: plain,
  dot grid (5 mm), ruled (8 mm, a red margin), graph (5 mm squares), a
  yellow legal pad, or a blackboard — measured on the tablet itself, kept
  with the page, and carried into an Image taken off it. Change to a paper
  your ink would not show on and the ink changes with it — chalk on the
  blackboard, black back on white; a colour you picked yourself stays
  through another paper just like the last. The page is still there after
  a relaunch. **⌘Z** straight after writing takes the last stroke back,
  and the corner has undo, redo and a clear of its own — and so do **the
  pen's two buttons**: with the nib off the tablet, a click of the lower
  one (nearer the nib) takes the last stroke back and a click of the upper
  one puts it back (the upper one only while the line at the bottom says
  "pen captured"). Hold either button and drag with the nib down — or drag
  with the mouse or the trackpad — to
  box part of the page, and the camera's three buttons bring it into the
  note: **Image** (that part of the page as a picture, paper and all),
  **Writing** (the strokes the box touches, as strokes in the note,
  pressure and colour kept, held together as one group) or **Text** (read
  into the note as words). They land under the caret, at the size a camera
  capture of a page would. Esc, or a click off the box, puts it away.
  While the page is on screen and WriteMind is in front, **the pen stays
  off the pointer**: WriteMind takes the tablet for itself and the Wacom
  driver hears nothing of it, so the pointer stays where the trackpad
  left it and a tap of the pen clicks nothing. macOS calls that **Input
  Monitoring** and asks about it the first time you pick the tablet —
  allow WriteMind in System Settings › Privacy & Security › Input
  Monitoring (it may want WriteMind quit and reopened). A line at the
  bottom of the page says where things stand: "pen captured", or why the
  pen is still moving the pointer and the one thing to do about it, with
  a button to that setting. Either way the page takes the pen. Put the
  page away (**Hide Page**, ⌘Y) or switch to another app and the pen is
  an ordinary pen again.
- **Or the tablet writes straight into the note.** **Write on: Page |
  Notebook** on the page's bar (and in the View menu) sends the pen to the
  notebook instead: the tablet, turned the way it sits, lands on the
  notes you can see — its own shape, as big as fits and centred, never
  stretched, so handwriting keeps its proportions — and the nib writes
  ink straight into the note's drawing with the notebook's pen (the tool,
  colour and size on the pen menu), pressure and all; a tap is a dot.
  While the pen is near, a faint outline shows where the tablet lands and
  a ring follows the nib. **⌘Z** straight after takes the strokes back, one
  stroke at a time, and once they are all back it is the typing's again;
  **⇧⌘Z** puts them back. The pen's buttons do it here too: a click of the
  lower one, nib off the tablet, undoes the last thing drawn on the note
  and a click of the upper one redoes it. Hold either button and drag with
  the nib down to pick things
  up on the drawing, exactly as a ⌘-drag does — ⌫ and the handles then
  work on them. The page is set aside, dimmed, and kept as it was; the
  switch (or the View menu) sends the pen back to it — Esc stays the
  notes'. Picking the notebook brings the notes into view if they were
  put away, and the page may be hidden while you write in the notes; with
  no note on screen the pen is a pointer again, and the page says so.
- **A bar you can put away a piece at a time.** The toolbar is in
  sections — Style, Structure, Insert, Maths, Flow Chart, Capture — and the
  grip at the end of each one folds it down to a single icon; right-click
  the bar for the list. Every shortcut lives in the **Format** menu, so
  folding a section never takes its keys with it. Hovering a button names
  it, shows its keys and says what it does.
- **Tabs for the notes you have open.** The wheel walks along them, and the
  button at the right-hand end lists every open note — the way back to one
  that has scrolled off the end.
