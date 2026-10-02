import XCTest
@testable import WriteMind

/// Evaluation cells: what runs, what is refused, and what the answer
/// looks like in the note.
final class EvaluationCellTests: XCTestCase {

    // MARK: - An evaluation cell is not a code cell

    func testAnEvaluationCellIsItsOwnFenceAndACodeCellIsNotOne() {
        XCTAssertEqual(Evaluator.from(fence: "eval python"), .python)
        XCTAssertEqual(Evaluator.from(fence: "eval c++"), .cpp)
        XCTAssertEqual(Evaluator.from(fence: "eval wl"), .wolfram)
        // A CODE cell of the same language is not an evaluation cell and
        // never runs — that is the whole distinction.
        for code in ["python", "cpp", "c++", "wl", "wls", "mathematica"] {
            XCTAssertNil(Evaluator.from(fence: code), code)
            XCTAssertFalse(Evaluator.isEvaluation(fence: code), code)
            XCTAssertEqual(Evaluator.resolve(fence: code), .failure(.notAnEvaluationCell), code)
        }
    }

    func testWhatSomebodyMightTypeByHandStillResolves() {
        XCTAssertEqual(Evaluator.from(fence: "eval py"), .python)
        XCTAssertEqual(Evaluator.from(fence: "eval cpp"), .cpp)
        XCTAssertEqual(Evaluator.from(fence: "eval mathematica"), .wolfram)
        XCTAssertEqual(Evaluator.from(fence: "EVAL Python"), .python)
    }

    /// `wl` STAYS MATHS. The maths fence is the whole info string "wl",
    /// and an evaluation cell's is "eval wl" — different strings, and
    /// the maths cell is untouched.
    func testTheMathsFenceIsNotAnEvaluationCell() {
        XCTAssertTrue(MathMarkup.isMathFence("wl"))
        XCTAssertFalse(MathMarkup.isMathFence(Evaluator.wolfram.fence))
        XCTAssertFalse(Evaluator.isEvaluation(fence: "wl"))
        XCTAssertNil(CodeLanguage.from(fence: "wl"))
    }

    func testAnEvaluationCellIsStillColouredForItsLanguage() {
        XCTAssertEqual(CodeLanguage.colouring(fence: "eval python"), .python)
        XCTAssertEqual(CodeLanguage.colouring(fence: "eval c++"), .cpp)
        XCTAssertEqual(CodeLanguage.colouring(fence: "eval wl"), .wolfram)
        // A code cell is coloured as it always was.
        XCTAssertEqual(CodeLanguage.colouring(fence: "python"), .python)
        // And an evaluation cell naming something unknown is not guessed at.
        XCTAssertEqual(CodeLanguage.colouring(fence: "eval fortran"), .plain)
    }

    func testAnUnknownEnvironmentSaysSoRatherThanRunning() {
        XCTAssertEqual(Evaluator.resolve(fence: "eval fortran"),
                       .failure(.unknownEnvironment("fortran")))
        XCTAssertTrue(Evaluator.Refusal.unknownEnvironment("fortran").message.contains("fortran"))
        for refusal: Evaluator.Refusal in [.notAnEvaluationCell, .unknownEnvironment("x"),
                                           .missingTool(.python)] {
            XCTAssertFalse(refusal.message.isEmpty)
        }
    }

    /// Sean, 2026-09-21: "wl, c++, or python"; 2026-09-22: "add C and
    /// Rust evals", and "default to wolfram" — which is why Wolfram is
    /// first, since the order here is the order the menu offers.
    func testTheEnvironmentsAreTheOnesHeNamedInTheOrderHeWantsThem() {
        XCTAssertEqual(Evaluator.allCases.map(\.badge), ["WL", "PY", "C", "C++", "RS"])
        XCTAssertEqual(Evaluator.allCases.map(\.fence),
                       ["eval wl", "eval python", "eval c", "eval c++", "eval rust"])
        XCTAssertEqual(Evaluator.allCases.first, .wolfram)
    }

    /// C, C++ and Rust are compiled — two processes, two exit codes — and
    /// the source file's EXTENSION is what tells the compiler what it is
    /// reading, so it belongs to the model and not to the runner.
    func testTheCompiledOnesNameTheirSourceAndTheirStandard() {
        for evaluator in Evaluator.allCases where evaluator.isCompiled {
            let name = evaluator.sourceFile ?? ""
            XCTAssertTrue(name.hasPrefix("cell."), "\(evaluator) has no source file")
            let arguments = evaluator.compileArguments(source: "/tmp/in", output: "/tmp/out")
            XCTAssertEqual(arguments.suffix(3), ["-o", "/tmp/out", "/tmp/in"], "\(evaluator)")
            XCTAssertGreaterThan(arguments.count, 3, "\(evaluator) names no standard")
        }
        XCTAssertEqual(Set(Evaluator.allCases.filter(\.isCompiled)), [.c, .cpp, .rust])
        // Wolfram takes its source as an argument and writes no file.
        XCTAssertNil(Evaluator.wolfram.sourceFile)
        XCTAssertEqual(Evaluator.python.sourceFile, "cell.py")
    }

    /// The sentence that says an environment is not one of ours has to
    /// name the ones that are, and it cannot be allowed to go stale.
    func testTheUnknownEnvironmentSentenceNamesEveryEnvironmentThereIs() {
        let message = Evaluator.Refusal.unknownEnvironment("fortran").message
        for evaluator in Evaluator.allCases {
            XCTAssertTrue(message.contains(evaluator.title), "\(evaluator.title) is not in it")
        }
    }

    func testTheToolsAreLookedForByAbsolutePathAndNeverJustOne() {
        for evaluator in Evaluator.allCases {
            XCTAssertGreaterThan(evaluator.candidates.count, 1, "\(evaluator)")
            for path in evaluator.candidates {
                XCTAssertTrue(path.hasPrefix("/"), "\(path) is not absolute")
            }
        }
        // A GUI app inherits launchd's PATH, which has no Homebrew in it.
        XCTAssertTrue(Evaluator.wolfram.candidates.contains("/opt/homebrew/bin/wolframscript"))
        XCTAssertEqual(Evaluator.python.candidates.first, "/usr/bin/python3")
    }

    func testOnlyWolframIsHandedAKernelPath() {
        XCTAssertEqual(Evaluator.wolfram.environment["WolframKernel"], Evaluator.wolframKernel)
        for evaluator in Evaluator.allCases where evaluator != .wolfram {
            XCTAssertNil(evaluator.environment["WolframKernel"], "\(evaluator)")
        }
        // Replaced, not inherited.
        XCTAssertEqual(Evaluator.python.environment["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
    }

    /// Both wolframscript failures exit 255 with nothing on stdout, so
    /// the status cannot tell them apart and stderr has to.
    func testTheTwoWolframFailuresAreToldApartByStderr() {
        // The real words, captured from this machine on 2026-09-21.
        let notActivated = EvalResult(
            stderr: "The Wolfram Engine requires one-time activation on this computer.\n"
                + "Visit https://wolfram.com/engine/free-license to get your free license.\n"
                + "Wolfram ID: Password: \nIncorrect username or password",
            status: 255)
        XCTAssertTrue(CellRunner.wolframNote(notActivated, evaluator: .wolfram)?
            .contains("not activated") ?? false)
        XCTAssertTrue(CellRunner.wolframNote(notActivated, evaluator: .wolfram)?
            .contains("wolframscript -activate") ?? false)
        let noKernel = EvalResult(
            stderr: "A WolframKernel location could not be determined. Use -configure…",
            status: 255)
        XCTAssertTrue(CellRunner.wolframNote(noKernel, evaluator: .wolfram)?
            .contains("kernel was not found") ?? false)
        XCTAssertNil(CellRunner.wolframNote(EvalResult(status: 0), evaluator: .wolfram))
        XCTAssertNil(CellRunner.wolframNote(notActivated, evaluator: .python))
    }

    // MARK: - The Out cell

    func testAnAnswerIsAnOutFenceAndAnOutFenceIsNotACodeLanguage() {
        let cell = EvalOutput.cell(for: EvalResult(stdout: "4\n", status: 0))
        XCTAssertEqual(cell, "```out\n4\n```")
        // Nothing else in the app has to learn about it: it is a plain
        // code block to the highlighter, and not maths.
        XCTAssertNil(CodeLanguage.from(fence: EvalOutput.fence))
        XCTAssertFalse(MathMarkup.isMathFence(EvalOutput.fence))
        XCTAssertTrue(EvalOutput.isOut(.code(language: "out", body: "4")))
        XCTAssertFalse(EvalOutput.isOut(.code(language: "eval python", body: "print(4)")))
        XCTAssertFalse(EvalOutput.isOut(.paragraph("out")))
    }

    func testAnOutCellIsNeverAnEmptyFence() {
        XCTAssertEqual(EvalOutput.body(for: EvalResult(status: 0)), "[no output]")
        XCTAssertEqual(EvalOutput.body(for: EvalResult(stdout: "   \n\n", status: 0)), "[no output]")
    }

    func testTheAppsOwnWordsAreInSquareBracketsAndTheProgramsAreNot() {
        let result = EvalResult(stdout: "hello", stderr: "boom", status: 2,
                                timedOut: true, truncated: true, note: "it did not compile")
        let body = EvalOutput.body(for: result)
        XCTAssertEqual(body.components(separatedBy: "\n").first, "hello")
        XCTAssertTrue(body.contains("[stderr]"))
        XCTAssertTrue(body.contains("boom"))
        XCTAssertTrue(body.contains("[it did not compile]"))
        XCTAssertTrue(body.contains("[output cut at 64 KB]"))
        XCTAssertTrue(body.contains("[timed out]"))
        XCTAssertTrue(body.contains("[exit 2]"))
        // A clean run says nothing about its exit.
        XCTAssertFalse(EvalOutput.body(for: EvalResult(stdout: "hi", status: 0)).contains("[exit"))
    }

    /// OUTPUT MAY NEVER CLOSE ITS OWN FENCE. The parser ends a fenced
    /// block at any line whose TRIMMED form begins with three backticks,
    /// so indenting does not save it — the rest of the note would
    /// re-parse as code.
    func testOutputThatPrintsAFenceCannotEndItsOwnCell() {
        let result = EvalResult(stdout: "before\n```\n   ```swift\nafter", status: 0)
        let cell = EvalOutput.cell(for: result)
        let blocks = MarkdownParser.positioned(from: "```eval python\nx\n```\n\n" + cell)
        XCTAssertEqual(blocks.count, 2, "the answer split the note: \(cell)")
        guard case .code(let language, let body)? = blocks.last?.block else {
            return XCTFail("the answer is not one code block")
        }
        XCTAssertEqual(language, "out")
        XCTAssertTrue(body.contains("after"), "everything the program printed is still there")
    }

    // MARK: - Where the answer goes

    private let note = "# Notes\n\n```eval python\nprint(2 + 2)\n```\n\nAfter it."

    private func cell(_ text: String, at index: Int) -> NSRange {
        MarkdownParser.positioned(from: text)[index].range
    }

    func testTheFirstRunPutsANewCellUnderTheCodeAndLeavesTheRestAlone() {
        let code = cell(note, at: 1)
        let edit = EvalCells.write(EvalResult(stdout: "4", status: 0), under: code, in: note)
        let after = (note as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(after, "# Notes\n\n```eval python\nprint(2 + 2)\n```\n\n```out\n4\n```\n\nAfter it.")
        XCTAssertEqual(MarkdownParser.positioned(from: after).count, 4)
    }

    func testASecondRunReplacesTheFirstAnswerRatherThanPilingUp() {
        let code = cell(note, at: 1)
        let once = (note as NSString).replacingCharacters(
            in: EvalCells.write(EvalResult(stdout: "4", status: 0), under: code, in: note).range,
            with: EvalCells.write(EvalResult(stdout: "4", status: 0), under: code, in: note).replacement)
        let again = EvalCells.write(EvalResult(stdout: "5", status: 0),
                                    under: cell(once, at: 1), in: once)
        let twice = (once as NSString).replacingCharacters(in: again.range, with: again.replacement)
        XCTAssertEqual(twice, "# Notes\n\n```eval python\nprint(2 + 2)\n```\n\n```out\n5\n```\n\nAfter it.")
        XCTAssertEqual(MarkdownParser.positioned(from: twice).count, 4, "one answer, not two")
        // And the words under it are untouched.
        XCTAssertTrue(twice.hasSuffix("After it."))
    }

    /// The tag is the veto: a bare code block a person wrote under their
    /// own code is not an answer and is never overwritten.
    func testAPlainBlockUnderTheCodeIsNotMistakenForAnAnswer() {
        let hand = "```eval python\nprint(1)\n```\n\n```\nmine\n```"
        XCTAssertNil(EvalCells.out(after: cell(hand, at: 0), in: hand))
        let edit = EvalCells.write(EvalResult(stdout: "1", status: 0), under: cell(hand, at: 0), in: hand)
        let after = (hand as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertTrue(after.contains("mine"), "their block was overwritten")
        XCTAssertEqual(MarkdownParser.positioned(from: after).count, 3)
    }

    func testAnAnswerOnlyBelongsToTheCellDirectlyAboveIt() {
        let two = "```eval python\na\n```\n\n```out\nA\n```\n\n```eval python\nb\n```"
        XCTAssertNotNil(EvalCells.out(after: cell(two, at: 0), in: two))
        XCTAssertNil(EvalCells.out(after: cell(two, at: 2), in: two), "the last cell has no answer yet")
    }

    func testOnlyAFencedCellIsRunnable() {
        XCTAssertNotNil(EvalCells.runnable(at: 12, in: note))
        XCTAssertNil(EvalCells.runnable(at: 2, in: note), "the heading is not a cell to run")
    }

    // MARK: - Picking the environment

    func testPickingAnEnvironmentRewritesTheFenceAndNothingElse() {
        let code = cell(note, at: 1)
        guard let edit = EvalCells.setEnvironment(.cpp, of: code, in: note) else {
            return XCTFail("no edit")
        }
        let after = (note as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(after, "# Notes\n\n```eval c++\nprint(2 + 2)\n```\n\nAfter it.")
        // Picking the one it already is changes nothing at all.
        XCTAssertNil(EvalCells.setEnvironment(.python, of: cell(note, at: 1), in: note))
    }

    func testPickingAnEnvironmentOnSomethingThatIsNotAFenceDoesNothing() {
        XCTAssertNil(EvalCells.setEnvironment(.python, of: cell(note, at: 0), in: note))
    }

    // MARK: - In and Out are one group

    /// Sean, 2026-09-21: "input and output cells are grouped together".
    func testAnEvaluationCellAndItsAnswerAreOneGroup() {
        let note = "# Notes\n\n```eval python\nx\n```\n\n```out\n1\n```\n\nAfter it."
        let groups = EvalCells.groups(in: note)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.input, cell(note, at: 1))
        XCTAssertEqual(groups.first?.output, cell(note, at: 2))
        // The bracket embraces both and nothing else.
        XCTAssertEqual((note as NSString).substring(with: groups[0].range),
                       "```eval python\nx\n```\n\n```out\n1\n```")
        XCTAssertTrue(EvalCells.isGrouped(cell(note, at: 1), in: groups))
        XCTAssertTrue(EvalCells.isGrouped(cell(note, at: 2), in: groups))
        XCTAssertFalse(EvalCells.isGrouped(cell(note, at: 0), in: groups), "the heading is not in it")
        XCTAssertFalse(EvalCells.isGrouped(cell(note, at: 3), in: groups))
    }

    func testACellWithNoAnswerYetIsNotAGroup() {
        XCTAssertTrue(EvalCells.groups(in: "```eval python\nx\n```").isEmpty)
        XCTAssertTrue(EvalCells.groups(in: "# Notes\n\nWords.").isEmpty)
        // An OUT cell is not an input, so two of them in a row are not a
        // pair — otherwise a second answer would bracket the first.
        XCTAssertTrue(EvalCells.groups(in: "```out\n1\n```\n\n```out\n2\n```").isEmpty)
    }

    /// The fence above the answer is NOT asked what it says (Sean,
    /// 2026-09-22: "input and output cells still don't appear to be
    /// grouped"). An `out` cell is only ever written by a run, so a cell
    /// with one under it has been run — and every pair in Sean's notes
    /// from before the `eval ` fence existed is written ```python.
    func testAPlainCodeCellWithAnAnswerIsStillAPair() {
        let older = "```python\nprint(1+2)\n```\n\n```out\n3\n```"
        let groups = EvalCells.groups(in: older)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.input, cell(older, at: 0))
        XCTAssertEqual(groups.first?.output, cell(older, at: 1))
    }

    /// Three blank lines in the gap are a `.blank` cell of the note's
    /// own, and the answer below them is still the answer — it was hidden
    /// from its cell, so a re-run piled a SECOND one on and the bracket
    /// went away.
    func testABlankCellInTheGapDoesNotUnpairThem() {
        let spaced = "```eval python\nx\n```\n\n\n\n```out\n1\n```"
        let groups = EvalCells.groups(in: spaced)
        XCTAssertEqual(groups.count, 1, "a gap is not a separation")
        XCTAssertNotNil(EvalCells.out(after: cell(spaced, at: 0), in: spaced))
        // And the blank cell between them is inside the bracket, so its
        // own is drawn inside it too.
        XCTAssertTrue(EvalCells.isGrouped(cell(spaced, at: 1), in: groups))
    }

    /// Sean, 2026-09-22: "the dropdown for evaluator type will become
    /// the In[n] after evaluation". The number is the pair's place in the
    /// note, so a cell with no answer has none at all.
    func testTheNumberIsThePairsPlaceInTheNote() {
        let note = "```eval python\na\n```\n\n```out\nA\n```\n\n"
            + "```eval wl\nb\n```\n\n```out\nB\n```\n\n```eval python\nc\n```"
        let groups = EvalCells.groups(in: note)
        XCTAssertEqual(EvalCells.number(of: cell(note, at: 0), in: groups), 1)
        XCTAssertEqual(EvalCells.number(of: cell(note, at: 1), in: groups), 1, "its answer shares it")
        XCTAssertEqual(EvalCells.number(of: cell(note, at: 2), in: groups), 2)
        XCTAssertEqual(EvalCells.number(of: cell(note, at: 3), in: groups), 2)
        XCTAssertNil(EvalCells.number(of: cell(note, at: 4), in: groups),
                     "a cell that has not been run has no number")

        XCTAssertFalse(EvalCells.isAnswer(cell(note, at: 0), in: groups))
        XCTAssertTrue(EvalCells.isAnswer(cell(note, at: 1), in: groups))
        XCTAssertFalse(EvalCells.isAnswer(cell(note, at: 4), in: groups))
    }

    /// Sean, 2026-09-22: "the dropdown for selecting an evaluator shows
    /// before it's evaluated.. after it's evaluated it disappears and is
    /// replaced by the In[]". So the mark's WORDS say which it is.
    func testTheMarkIsTheEnvironmentUntilItHasRunAndTheNumberAfterwards() {
        XCTAssertEqual(CellMark.title(.input(fence: "eval python", number: nil)), "PY")
        XCTAssertEqual(CellMark.title(.input(fence: "eval wl", number: nil)), "WL")
        XCTAssertEqual(CellMark.title(.input(fence: "eval python", number: 3)), "In[3]")
        XCTAssertEqual(CellMark.title(.output(number: 3)), "Out[3]")
        // A fence this app does not know still opens the menu, and says
        // so rather than naming a language it cannot run.
        XCTAssertEqual(CellMark.title(.input(fence: "eval fortran", number: nil)), "—")
    }

    func testEveryPairInANoteIsItsOwnGroup() {
        let two = "```eval python\na\n```\n\n```out\nA\n```\n\n```eval wl\nb\n```\n\n```out\nB\n```"
        let groups = EvalCells.groups(in: two)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.key)).count, 2, "two groups, two keys")
    }

    // MARK: - Where the cursor is left

    /// Sean, 2026-09-21: "after evaluating a cell, the text cursor should
    /// become a horizontal bar after the output" — the cursor a notebook
    /// leaves you with, ready for the next thing.
    func testTheBarGoesUnderTheAnswerAndNotInsideIt() {
        let answered = "```eval python\nx\n```\n\n```out\n1\n```\n\nAfter it."
        let out = cell(answered, at: 1)
        let bar = EvalCells.seam(after: out, in: answered)
        // The start of the cell below, which is the offset both panes
        // read as "the seam under this one".
        XCTAssertEqual(bar, cell(answered, at: 2).location)
        XCTAssertEqual((answered as NSString).substring(from: bar), "After it.")
    }

    /// The caret goes in the blank line the bar is drawn in — where a
    /// click in that seam would have put it — and NOT at the start of
    /// the cell below, which armed the same bar and left every other
    /// reader of "the caret is in that cell" answering for the wrong one.
    func testTheCaretGoesInTheSeamAndNotInTheCellBelowIt() {
        let answered = "```eval python\nx\n```\n\n```out\n1\n```\n\nAfter it."
        let out = cell(answered, at: 1)
        let caret = EvalCells.caret(under: out, in: answered)
        let bar = EvalCells.seam(after: out, in: answered)
        XCTAssertLessThan(caret, bar, "the caret is behind the bar, in the gap")
        XCTAssertEqual(caret, NSMaxRange(out) + 1)
        let line = (answered as NSString).lineRange(for: NSRange(location: caret, length: 0))
        XCTAssertTrue((answered as NSString).substring(with: line)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "a blank line, which is the only thing CellSeams.arm will arm from")
    }

    /// An answer at the very end of the note has no separator under it,
    /// so there is nowhere behind the bar for the caret to go.
    func testTheCaretAtTheEndOfTheNoteIsTheEndOfTheNote() {
        let answered = "```eval python\nx\n```\n\n```out\n1\n```"
        XCTAssertEqual(EvalCells.caret(under: cell(answered, at: 1), in: answered),
                       (answered as NSString).length)
    }

    // MARK: - Which cell the answer belongs to

    /// ⌘D makes two cells with identical text in one keystroke, and the
    /// answer has to go under the one that ran.
    func testTheAnswerLandsOnTheCopyThatWasRunAndNotTheFirstOne() {
        let twice = "```eval python\nx\n```\n\nWords.\n\n```eval python\nx\n```"
        let first = cell(twice, at: 0)
        let second = cell(twice, at: 2)
        XCTAssertNotEqual(first.location, second.location)
        let opening = (twice as NSString).substring(with: second)
        XCTAssertEqual(EvalCells.landing(of: opening, in: twice, startedAt: second.location)?.range,
                       second)
        XCTAssertEqual(EvalCells.landing(of: opening, in: twice, startedAt: first.location)?.range,
                       first, "and the upper one when that is the one that ran")
    }

    func testACellThatIsGoneTakesItsAnswerWithIt() {
        XCTAssertNil(EvalCells.landing(of: "```eval python\nx\n```", in: "# Nothing here",
                                       startedAt: 0))
    }

    /// An unclosed fence parses as a block that runs to the END of the
    /// note, so pasting an answer after it put the ```out line inside the
    /// cell and closed it. `MarkdownFormatting.fenced` reports that by
    /// handing back an EMPTY close rather than nil, which is why the run
    /// has to ask.
    func testAnUnclosedFenceIsReportedByAnEmptyClose() {
        XCTAssertEqual(MarkdownFormatting.fenced("```eval python\nx\n```")?.close, "```")
        XCTAssertEqual(MarkdownFormatting.fenced("```eval python\nx")?.close, "")
    }

    func testTheBarUnderTheLastCellIsTheEndOfTheNote() {
        let answered = "```eval python\nx\n```\n\n```out\n1\n```"
        XCTAssertEqual(EvalCells.seam(after: cell(answered, at: 1), in: answered),
                       (answered as NSString).length)
    }

    // MARK: - ⇧↩ runs it, and nothing else does

    /// macOS binds `insertLineBreak:` to ⌃↩ and says nothing about ⇧↩,
    /// so Return with shift arrives as an ordinary newline and the shift
    /// has to be read off the event. Getting this wrong is silent: the
    /// key simply does nothing.
    func testOnlyShiftReturnRuns() {
        XCTAssertTrue(EvaluationKeys.isRun(.shift))
        XCTAssertFalse(EvaluationKeys.isRun([]), "plain Return is a newline")
        XCTAssertFalse(EvaluationKeys.isRun([.shift, .command]))
        XCTAssertFalse(EvaluationKeys.isRun([.shift, .option]))
        XCTAssertFalse(EvaluationKeys.isRun(.control), "⌃↩ is still a line break")
    }

    // MARK: - What moves when an answer lands

    func testWhatIsBelowTheAnswerMovesAndWhatIsAboveItDoesNot() {
        let edit = MarkdownFormatting.Edit(range: NSRange(location: 10, length: 0),
                                           replacement: "12345",
                                           selection: NSRange(location: 10, length: 0))
        XCTAssertEqual(EvalCells.shifted(NSRange(location: 4, length: 2), by: edit),
                       NSRange(location: 4, length: 2), "above it")
        XCTAssertEqual(EvalCells.shifted(NSRange(location: 20, length: 2), by: edit),
                       NSRange(location: 25, length: 2), "below it")
        XCTAssertEqual(EvalCells.shifted(30, by: edit), 35)
        XCTAssertEqual(EvalCells.shifted(3, by: edit), 3)
    }
}

/// The promise that only a press starts a child, kept by the build.
final class EvaluationSpawnTests: XCTestCase {
    private var sources: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "WriteMind", directoryHint: .isDirectory)
        return (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
    }

    /// ONE FILE STARTS PROCESSES. Before evaluation cells the app started
    /// none at all, and that is worth keeping visible.
    func testNothingButTheRunnerSpawnsAProcess() throws {
        XCTAssertFalse(sources.isEmpty)
        for file in sources where file.lastPathComponent != "CellRunner.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in ["Process(", "NSTask", "posix_spawn", "execv"] {
                XCTAssertFalse(text.contains(needle),
                               "\(file.lastPathComponent) reaches for \(needle)")
            }
        }
    }

    /// AND NOTHING STARTS ONE BY ITSELF. A run is a press: never on
    /// opening a note, never on a save, never from a view's body.
    func testNoRunIsStartedFromLoadingOrSaving() throws {
        let store = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "WriteMind/Notes/NoteStore.swift"), encoding: .utf8)
        for caller in ["runCell(", "CellRunner.run"] {
            XCTAssertFalse(store.contains(caller),
                           "NoteStore.swift itself calls \(caller) — the store loads, saves and watches")
        }
    }

    /// The guard is at the SPAWN, not at the menu: the test host IS the
    /// app, and the tests reach in with @testable.
    func testATestHostRunsNothing() async {
        XCTAssertTrue(TestHost.isActive, "the unit suite is a test host")
        let outcome = await CellRunner.run("print('no')", as: .python)
        guard case .failure(.notHere) = outcome else {
            return XCTFail("a test host got as far as \(outcome)")
        }
    }
}
