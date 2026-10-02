import Foundation

/// Where an Out cell goes, and what gets replaced when the same cell is
/// run again.
///
/// FOUND BY POSITION, VETOED BY THE TAG: the answer to a cell is the block
/// immediately after it, and only when that block is an `out` fence. By
/// position, because every other cell identity in this app is a character
/// offset and a note is not a database; vetoed by the tag, because
/// otherwise a re-run would overwrite whatever the person happened to have
/// written under the code.
enum EvalCells {
    /// The cell the caret is in, if it is a fenced block — what ⌘9 runs.
    static func runnable(at caret: Int, in text: String) -> PositionedBlock? {
        guard let block = MarkdownParser.positioned(from: text)
            .first(where: { NSLocationInRange(caret, $0.range) || $0.range.location == caret })
        else { return nil }
        guard case .code = block.block else { return nil }
        return block
    }

    /// The Out cell belonging to this one, if it has one already.
    ///
    /// The blank cells in between are stepped over. A run of three or more
    /// empty lines is a `.blank` block — the note's own spacing, not the
    /// editor's — so pressing Return twice in the gap under a cell used to
    /// hide its answer from it: a re-run piled a SECOND answer on instead
    /// of replacing the first, and the pair stopped being a pair.
    static func out(after cell: NSRange, in text: String) -> PositionedBlock? {
        let blocks = MarkdownParser.positioned(from: text)
        guard let index = blocks.firstIndex(where: { $0.range.location == cell.location }),
              let answer = answer(after: index, in: blocks)
        else { return nil }
        return blocks[answer]
    }

    /// Where the answer to `blocks[index]` is, over blocks already parsed.
    /// The one reader of "what counts as the block below this one", so the
    /// answer, the re-run and the bracket cannot drift apart.
    private static func answer(after index: Int, in blocks: [PositionedBlock]) -> Int? {
        var next = index + 1
        while next < blocks.count, case .blank = blocks[next].block { next += 1 }
        guard next < blocks.count, EvalOutput.isOut(blocks[next].block) else { return nil }
        return next
    }

    /// The edit that puts a result under a cell: over the Out cell that is
    /// already there, or a new one after it.
    ///
    /// Replacing uses the Out block's OWN range and never
    /// `CellCommands.extent`, which deliberately swallows the blank line
    /// after a cell and would glue the answer to whatever is below.
    static func write(_ result: EvalResult, under cell: NSRange,
                      in text: String) -> MarkdownFormatting.Edit {
        let written = EvalOutput.cell(for: result)
        if let existing = out(after: cell, in: text) {
            return MarkdownFormatting.Edit(range: existing.range, replacement: written,
                                           selection: NSRange(location: existing.range.location,
                                                              length: 0))
        }
        return CellCommands.paste(written, after: cell, in: text)
    }

    /// A range that was measured before an edit, where it is afterwards.
    ///
    /// An Out cell lands BELOW the cell that was run, so anything the
    /// person is holding further down the note — a cell open for typing, a
    /// handful held by their brackets, the bar between two of them —
    /// moves by however much longer the note just got. Nothing else shifts
    /// those, because nothing else edits a note from outside the pane the
    /// caret is in.
    static func shifted(_ range: NSRange, by edit: MarkdownFormatting.Edit) -> NSRange {
        let change = (edit.replacement as NSString).length - edit.range.length
        guard change != 0, range.location >= NSMaxRange(edit.range) else { return range }
        return NSRange(location: range.location + change, length: range.length)
    }

    static func shifted(_ offset: Int, by edit: MarkdownFormatting.Edit) -> Int {
        let change = (edit.replacement as NSString).length - edit.range.length
        guard change != 0, offset >= NSMaxRange(edit.range) else { return offset }
        return offset + change
    }

    /// AN EVALUATION CELL AND ITS ANSWER ARE ONE GROUP — the In/Out pair
    /// a notebook draws one bracket round (Sean, 2026-09-21: "input and
    /// output cells are grouped together").
    ///
    /// It is not a section: nothing is folded and nothing is nested by
    /// it in the note. It is two adjacent cells the gutter embraces, so
    /// that the answer visibly belongs to the code above it and moving
    /// your eye down the margin tells you which is which.
    struct Group: Equatable {
        var input: NSRange
        var output: NSRange
        var key: String
        /// The two of them, end to end.
        var range: NSRange {
            NSRange(location: input.location, length: NSMaxRange(output) - input.location)
        }
    }

    /// AN OUT CELL IS AN ANSWER, WHATEVER RAN: the pair is a fenced cell
    /// with an `out` cell under it, and the fence above is not asked what
    /// it says.
    ///
    /// The tag is the whole test because nothing but `EvalOutput.cell(for:)`
    /// ever writes an `out` fence — so a cell with one under it HAS been
    /// run, whatever this version of the app would make of its language
    /// today. Asking `Evaluator.isEvaluation` as well split the file in
    /// two: `out(after:)` would replace that block on a re-run, calling it
    /// the cell's answer, while the gutter refused to bracket the two
    /// together (Sean, 2026-09-22: "input and output cells still don't
    /// appear to be grouped"). Every pair written before the `eval ` fence
    /// existed — when a plain ```python cell was the thing that ran — is
    /// in Sean's notes still, and every one of them is a pair.
    static func groups(in text: String) -> [Group] {
        let blocks = MarkdownParser.positioned(from: text)
        var out: [Group] = []
        for (index, block) in blocks.enumerated() {
            guard case .code = block.block, !EvalOutput.isOut(block.block),
                  let found = answer(after: index, in: blocks)
            else { continue }
            out.append(Group(input: block.range, output: blocks[found].range,
                             key: "eval:\(block.range.location)"))
        }
        return out
    }

    /// WHICH `In[n]` A CELL IS: the nth answered pair in the note,
    /// counted from the top, and nil for a cell that has not been run.
    ///
    /// Sean, 2026-09-22: "show in and out to the left of input and output
    /// cells similar to mathematica.. the dropdown for evaluator type
    /// will become the In[n] after evaluation".
    ///
    /// BY POSITION IN THE NOTE, not by the order the cells were run in.
    /// A notebook numbers In[] at evaluation time and the pair keeps that
    /// number for the session; there is no session here — a note is a
    /// file, it is opened tomorrow, and the only thing in it that could
    /// carry a number is the fence, which is not ours to scribble in. So
    /// the number is READ OFF THE NOTE like everything else: insert a
    /// pair above another and the one below renumbers, which is what
    /// anybody reading the file top to bottom would call them anyway.
    static func number(of cell: NSRange, in groups: [Group]) -> Int? {
        groups.firstIndex {
            NSEqualRanges($0.input, cell) || NSEqualRanges($0.output, cell)
        }.map { $0 + 1 }
    }

    /// Whether this cell is the ANSWER half of its pair — `Out[n]` rather
    /// than `In[n]`.
    static func isAnswer(_ cell: NSRange, in groups: [Group]) -> Bool {
        groups.contains { NSEqualRanges($0.output, cell) }
    }

    /// Whether a cell is inside a group — which is what pushes its own
    /// bracket one step in, so the group's sits outside it. Containment,
    /// not the two ends: a blank cell standing between the code and its
    /// answer is inside the bracket the group draws and has to be drawn
    /// inside it too.
    static func isGrouped(_ cell: NSRange, in groups: [Group]) -> Bool {
        groups.contains {
            cell.location >= $0.range.location && NSMaxRange(cell) <= NSMaxRange($0.range)
        }
    }

    /// WHICH OF SEVERAL IDENTICAL CELLS WAS THE ONE THAT RAN.
    ///
    /// A cell is found again by its own text when the answer comes back,
    /// because a run takes time and the note is editable throughout it —
    /// but ⌘D makes two cells with identical text in one keystroke, and
    /// first-wins then put the answer under the copy ABOVE the one that
    /// was run, taking its bracket and its bar with it. Where the run
    /// started from is the tie break; nothing else in the note can speak
    /// for it, and it is still right after an edit has moved the cell.
    static func landing(of opening: String, in text: String, startedAt: Int) -> PositionedBlock? {
        let ns = text as NSString
        return MarkdownParser.positioned(from: text)
            .filter { ns.substring(with: $0.range) == opening }
            .min { abs($0.range.location - startedAt) < abs($1.range.location - startedAt) }
    }

    /// WHERE THE CARET GOES when the bar is armed under an answer: the
    /// blank line the bar is drawn in, which is where a CLICK in that
    /// seam would have put it.
    ///
    /// It matters that it is the separator and not the start of the cell
    /// below. The source pane arms from the caret
    /// (`CellSeams.arm`, through `textViewDidChangeSelection`), and every
    /// other reader of "the caret is in that cell" is asked on the way
    /// past — so a caret parked in the next cell armed the right bar and
    /// still revealed that cell's `## ` as it went by.
    static func caret(under cell: NSRange, in text: String) -> Int {
        let end = (text as NSString).length
        return min(NSMaxRange(cell) + 1, seam(after: cell, in: text), end)
    }

    /// WHERE THE BAR GOES WHEN A CELL HAS FINISHED: the start of the
    /// next cell, which is the offset both panes already read as "the
    /// seam under this one" (arming parks the caret at the separator and
    /// `NotebookCells.block(containing:)` reads that as the cell below).
    /// The end of the note when there is nothing after it.
    static func seam(after cell: NSRange, in text: String) -> Int {
        let blocks = MarkdownParser.positioned(from: text)
        if let index = blocks.firstIndex(where: { $0.range.location == cell.location }),
           index + 1 < blocks.count {
            return blocks[index + 1].range.location
        }
        return (text as NSString).length
    }

    /// Changing a cell's environment rewrites its fence and nothing else
    /// — the body is untouched, and so is any Out cell under it. This is
    /// also what TURNS A CELL INTO AN EVALUATION CELL (⌘9 over a fenced
    /// block, through `Insertion`): the fence goes from `python` to
    /// `eval python`, and a code cell becomes a cell the note runs.
    ///
    /// The open line is replaced whole rather than patched, because an
    /// info string is one opaque string to the parser and picking it
    /// apart is how a second reader of it gets invented.
    static func setEnvironment(_ evaluator: Evaluator, of cell: NSRange,
                               in text: String) -> MarkdownFormatting.Edit? {
        let ns = text as NSString
        guard NSMaxRange(cell) <= ns.length else { return nil }
        let open = ns.lineRange(for: NSRange(location: cell.location, length: 0))
        let line = ns.substring(with: open).trimmingCharacters(in: .newlines)
        guard line.trimmingCharacters(in: .whitespaces).hasPrefix("```") else { return nil }
        let replacement = "```" + evaluator.fence
        guard replacement != line else { return nil }
        return MarkdownFormatting.Edit(
            range: NSRange(location: open.location, length: (line as NSString).length),
            replacement: replacement,
            selection: NSRange(location: open.location + (replacement as NSString).length, length: 0))
    }
}
