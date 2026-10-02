import Foundation

extension NoteStore {
    /// RUN A CELL AND PUT THE ANSWER UNDER IT. The only thing in this app
    /// that starts a process, and it starts one only from a press — ⇧↩ in
    /// the cell, and nothing else. There is no run control on screen: a
    /// button for a thing the keyboard already does is what the ▶ was
    /// (Sean, 2026-09-22: "get rid of the play button").
    ///
    /// Every refusal is a sentence in the footer, where the camera's
    /// notices go, and none of them spawns anything or writes a cell.
    ///
    /// The In cell is FOUND AGAIN when the answer comes back, by its own
    /// text rather than by the range it had when the key was pressed: a
    /// run takes time and the note is editable throughout it.
    func runCell(_ cell: NSRange?) {
        guard runningCell == nil, let cell else { return }
        let ns = text as NSString
        guard NSMaxRange(cell) <= ns.length,
              let parts = MarkdownFormatting.fenced(ns.substring(with: cell))
        else {
            notice(Evaluator.Refusal.notAnEvaluationCell.message)
            return
        }
        // AN UNCLOSED FENCE IS NOT A CELL YET. `MarkdownFormatting.fenced`
        // hands back an empty `close` for one rather than nil, and the
        // parser runs such a block to the END OF THE NOTE — so the answer
        // was pasted at that end, its own ```out line closed the cell it
        // was meant to sit under, and the result was swallowed as code.
        guard !parts.close.isEmpty else {
            notice("That cell has no closing ``` yet, so there is nothing to run.")
            return
        }
        let evaluator: Evaluator
        switch Evaluator.resolve(fence: MarkdownFormatting.fenceLanguage(parts.open)) {
        case .success(let found): evaluator = found
        case .failure(let refusal): notice(refusal.message); return
        }

        let source = parts.body
        let opening = ns.substring(with: cell)
        let from = cell.location
        runningCell = from
        Task.detached { [weak self] in
            let outcome = await CellRunner.run(source, as: evaluator)
            await MainActor.run { self?.landed(outcome, of: evaluator, cell: opening, from: from) }
        }
    }

    /// Whether ⇧↩ means "run" where the caret is. Asked by the text
    /// views, which must not swallow the key anywhere else.
    func isEvaluationCell(_ cell: NSRange?) -> Bool {
        guard let cell, NSMaxRange(cell) <= (text as NSString).length,
              let parts = MarkdownFormatting.fenced((text as NSString).substring(with: cell))
        else { return false }
        return Evaluator.isEvaluation(fence: MarkdownFormatting.fenceLanguage(parts.open))
    }

    /// Change what a cell runs as: its fence is rewritten and nothing
    /// else is — not the body, and not any answer already under it.
    func setEnvironment(_ evaluator: Evaluator, of cell: NSRange) {
        guard let edit = EvalCells.setEnvironment(evaluator, of: cell, in: text) else { return }
        writeCell?(edit)
    }

    private func landed(_ outcome: Result<EvalResult, CellRunner.Failure>,
                        of evaluator: Evaluator, cell opening: String, from: Int) {
        runningCell = nil
        let result: EvalResult
        switch outcome {
        case .success(let ran):
            result = ran
        case .failure(.refused(let refusal)):
            notice(refusal.message)
            return
        case .failure(.notHere):
            // A test host or the smoke. Nothing ran and nothing is said.
            return
        case .failure(.couldNotStart(let why)):
            result = EvalResult(status: nil, note: "could not start \(evaluator.title): \(why)")
        }
        guard let landing = EvalCells.landing(of: opening, in: text, startedAt: from) else {
            notice("The cell that was running is not there any more, so its answer was dropped.")
            return
        }
        writeCell?(EvalCells.write(result, under: landing.range, in: text))
        // AND THE BAR GOES UNDER THE ANSWER. The run started with ⇧↩;
        // leaving the cursor below what came back is
        // the other half of that gesture, and it is where the next thing
        // gets typed.
        guard let answered = EvalCells.out(after: landing.range, in: text) else { return }
        writeBar?(answered.range)
    }
}
