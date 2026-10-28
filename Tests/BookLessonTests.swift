#if BOOK_LESSON_TESTS
import Foundation

#if !APP_TESTS
struct RecommendationArrow { let rank: Int; let move: Move }
#endif

@main @MainActor
struct BookLessonTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }; checks += 1
    }
    static func assessment(_ move: Move, _ verdict: MoveAssessment.Verdict = .good,
                           pv: [String] = ["a6a5", "c3c4"]) -> MoveAssessment {
        MoveAssessment(move: move, bestMove: Move(uci: "a3a4"), verdict: verdict,
                       title: "测试评价", detail: "固定核验结果，不依赖引擎安装。", lossCP: verdict == .mistake ? 300 : 20,
                       beforeScore: .cp(30), afterScore: .cp(10), replyPV: pv, bestPV: ["a3a4", "a6a5"])
    }
    @MainActor final class Gate {
        var pending: [(Move, CheckedContinuation<MoveAssessment, Error>)] = []
        func assess(_ position: Position, _ move: Move, _ time: Int) async throws -> MoveAssessment {
            try await withCheckedThrowingContinuation { pending.append((move, $0)) }
        }
        func finish(_ verdict: MoveAssessment.Verdict = .good) {
            let (move, continuation) = pending.removeFirst()
            continuation.resume(returning: BookLessonTests.assessment(move, verdict))
        }
    }
    static func drain(_ model: BookLessonModel) async throws {
        for _ in 0..<500 {
            if !model.isThinking { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw Failure(message: "A deterministic injected evaluation did not finish")
    }
    static func waitGate(_ gate: Gate) async throws {
        for _ in 0..<500 {
            if !gate.pending.isEmpty { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw Failure(message: "Injected assessment never started")
    }

    static func main() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"] ?? NSTemporaryDirectory())
            .appendingPathComponent("book-lesson-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture()
        var date = Date(timeIntervalSince1970: 1_780_000_000)
        var verdict = MoveAssessment.Verdict.good
        var shouldFail = false
        var evaluated: [Position] = []
        var replyCalls = 0
        var injectedPV = ["a6a5", "c3c4"]
        let coach = TrainingCoach()
        defer { coach.shutdown() }
        func make(_ directory: String, gate: Gate? = nil) -> BookLessonModel {
            let store = LearningStore(directory: root.appendingPathComponent(directory))
            let book = BookStudyModel(directory: root.appendingPathComponent("books"))
            let result = BookLessonModel(book: book, store: store, coach: coach,
                assess: { position, move, time in
                    if let gate { return try await gate.assess(position, move, time) }
                    if shouldFail { throw TrainingCoachError.noEvaluation }
                    return assessment(move, verdict, pv: injectedPV)
                }, evaluate: { position, _ in
                    evaluated.append(position)
                    return [EngineLine(rank: 1, depth: 12, score: .cp(20), pv: ["a3a4", "a6a5"], timeMS: 1, nodes: 10, wdl: nil)]
                }, reply: { position, _ in replyCalls += 1; return position.legalMoves().first }, now: { date })
            result.install(document: fixture.0, catalog: fixture.1)
            return result
        }

        let model = make("normal")
        try check(model.stage == .reading && model.canStart && model.studentSide == .red, "Source-backed lesson opens at a real decision")
        model.startDecision()
        model.submit(Move(uci: "e3e4")!)
        try check(model.position != .initial && model.position.sideToMove == .black && model.isThinking,
                  "Any legal off-book move lands synchronously before async assessment")
        try check(model.studentSide == .red && model.lastMove?.uci == "e3e4", "Submitting never steals the student's side")
        await Task.yield(); try await drain(model)
        try check(model.referenceMatch == .offBook && model.canAdvance, "A good off-book move passes judgment without pretending to reproduce the source")
        try check(model.store.data.runs.count == 1 && model.store.data.runs[0].independent, "The shared ledger records independent evidence")
        try check(!model.store.data.runs[0].transfer, "An unseen source checkpoint is not mislabeled as a validated transfer exercise")
        try check(model.store.data.decisions[0].ply == 0 && model.store.data.decisions[0].outcome == "alternative",
                  "Decision uses the shared ledger's backward-compatible alternative outcome")
        model.completeCheckpoint(); model.completeCheckpoint()
        try check(model.store.data.runs.count == 1 && model.stage == .summary, "Completion is idempotent")
        try check(!model.summary.contains(model.nextReason), "A checkpoint summary cannot announce the next course while this course still has questions")
        model.startComparison(nodeID: 1)
        let firstLine = model.position
        model.startComparison(nodeID: 4)
        try check(model.position != firstLine && model.studentSide == .red, "Both source alternatives start at the same divergence and preserve student identity")
        model.nextReply()
        try check(model.position.sideToMove == .red && model.studentSide == .red, "A single source opponent reply is explicit")
        model.returnToAnchor()
        try check(model.position == .initial && model.canAdvance, "Returning to the branch preserves already earned evidence")
        model.nextCheckpoint()
        try check(model.checkpointIndex == 1 && model.position.sideToMove == .red, "Next source checkpoint has an explicit anchor")
        model.startDecision(); model.submit(Move(uci: "c3c4")!); await Task.yield(); try await drain(model)
        try check(model.referenceMatch == .mainline && model.store.data.decisions.last?.ply == 2,
                  "Source node index is not confused with actual half-move ply")
        let backup = try model.store.exportData()
        let backupStore = LearningStore(directory: root.appendingPathComponent("backup-restored"))
        try backupStore.restoreBackup(backup, builtInIDs: [], builtInSources: [])
        try check(backupStore.data.runs.count == 2 && backupStore.data.decisions.count == 2 && backupStore.data.bookResume != nil,
                  "Completed source judgments export and restore through the existing archive validator")
        model.selectCheckpoint(index: 2)
        try check(model.studentSide == .black && model.completedCount == 2,
                  "Selecting another decision preserves completions and uses that decision's original side")
        model.startDecision(); model.submit(Move(uci: "c6c5")!); await Task.yield(); try await drain(model)
        try check(model.studentSide == .black && model.position.sideToMove == .red && model.store.data.decisions.last?.ply == 1,
                  "Black students remain black after moving, and branch node 4 is correctly stored as ply 1")

        let sourceWalk = make("source-walk")
        let walkedUnit = fixture.1.units[0]
        let laterSource = BookStudySource(bookSHA: walkedUnit.sourceHash, recordID: walkedUnit.recordID,
                                         nodeID: 2, title: "第二题")
        let unvisitedSource = BookStudySource(bookSHA: walkedUnit.sourceHash, recordID: walkedUnit.recordID,
                                             nodeID: 4, title: "未访问分支")
        let repliesBeforeSource = replyCalls
        sourceWalk.startComparison(nodeID: 1); sourceWalk.nextReply()
        try check(sourceWalk.comparisonNodeID == 2 && sourceWalk.store.data.lastAssisted[laterSource.key] == nil,
                  "Reaching a later decision position alone does not expose its unshown answer")
        sourceWalk.nextReply()
        try check(sourceWalk.comparisonNodeID == 3 && sourceWalk.store.data.lastAssisted[laterSource.key] == date,
                  "Playing a source answer marks that answer's parent checkpoint assisted")
        try check(sourceWalk.store.data.lastAssisted[unvisitedSource.key] == nil,
                  "A source comparison does not pre-expose unrelated unvisited branches")
        let sourceLeaf = sourceWalk.position
        try check(!sourceLeaf.legalMoves().isEmpty && !sourceWalk.canPlayReply,
                  "A source leaf stops playback even when the position still has legal engine moves")
        sourceWalk.nextReply(); await Task.yield()
        try check(sourceWalk.position == sourceLeaf && replyCalls == repliesBeforeSource && !sourceWalk.isThinking,
                  "A source leaf cannot silently fall through to an engine reply")
        let sourceWalkRestored = make("source-walk")
        sourceWalkRestored.selectCheckpoint(index: 1); sourceWalkRestored.startDecision()
        sourceWalkRestored.submit(Move(uci: "c3c4")!); await Task.yield(); try await drain(sourceWalkRestored)
        try check(sourceWalkRestored.store.data.runs.last?.independent == false,
                  "A later answer seen during source comparison remains assisted after restart")

        let malformedSource = make("malformed-source"), malformedFixture = makeFixture(invalidSourceReply: true)
        malformedSource.install(document: malformedFixture.0, catalog: malformedFixture.1)
        malformedSource.startComparison(nodeID: 1)
        let beforeMalformed = malformedSource.position, repliesBeforeMalformed = replyCalls
        try check(!malformedSource.canPlayReply, "An invalid source continuation is not playable")
        malformedSource.nextReply(); await Task.yield()
        try check(malformedSource.position == beforeMalformed && replyCalls == repliesBeforeMalformed,
                  "An illegal source continuation never substitutes an unmarked engine move")

        let engineWalk = make("engine-walk")
        engineWalk.startDecision(); engineWalk.submit(Move(uci: "a3a4")!)
        await Task.yield(); try await drain(engineWalk); engineWalk.nextReply()
        try check(engineWalk.store.data.lastAssisted[laterSource.key] == nil,
                  "An engine PV reaching a source anchor has not yet supplied that anchor's answer")
        engineWalk.nextReply()
        try check(engineWalk.store.data.lastAssisted[laterSource.key] == date
                  && engineWalk.store.data.lastAssisted[unvisitedSource.key] == nil,
                  "A displayed engine-PV move exposes only matching before-FEN source checkpoints")
        let engineWalkRestored = make("engine-walk")
        engineWalkRestored.selectCheckpoint(index: 1); engineWalkRestored.startDecision()
        engineWalkRestored.submit(Move(uci: "c3c4")!); await Task.yield(); try await drain(engineWalkRestored)
        try check(engineWalkRestored.store.data.runs.last?.independent == false,
                  "An answer shown by an engine PV cannot later become independent source evidence")

        injectedPV = ["a6a5"]
        let freshReply = make("fresh-reply")
        freshReply.startDecision(); freshReply.submit(Move(uci: "a3a4")!)
        await Task.yield(); try await drain(freshReply); freshReply.nextReply()
        let repliesBeforeFresh = replyCalls
        freshReply.nextReply(); await Task.yield(); try await drain(freshReply)
        try check(replyCalls == repliesBeforeFresh + 1 && freshReply.store.data.lastAssisted[laterSource.key] == date,
                  "A newly computed engine reply also marks any source question matching its before-FEN")
        injectedPV = ["a6a5", "c3c4"]

        let wholeRecord = make("whole-record")
        let exposedUnit = fixture.1.units[0], untouchedUnit = fixture.1.units[1]
        let wholeSources = exposedUnit.checkpoints.map {
            BookStudySource(bookSHA: exposedUnit.sourceHash, recordID: exposedUnit.recordID,
                            nodeID: $0.anchorNodeID, title: exposedUnit.title + " · " + $0.title)
        }
        let untouchedSource = BookStudySource(bookSHA: untouchedUnit.sourceHash, recordID: untouchedUnit.recordID,
                                             nodeID: untouchedUnit.checkpoints[0].anchorNodeID, title: untouchedUnit.title)
        wholeRecord.markWholeRecordExposed()
        try check(wholeSources.allSatisfy {
            wholeRecord.store.data.exposedLines.contains($0.key) && wholeRecord.store.data.lastAssisted[$0.key] == date
        }, "Opening complete original notes/branches exposes every checkpoint in this record")
        try check(!wholeRecord.store.data.exposedLines.contains(untouchedSource.key)
                  && wholeRecord.store.data.lastAssisted[untouchedSource.key] == nil,
                  "Whole-record exposure never contaminates another source record")
        let wholeRestored = make("whole-record")
        try check(wholeSources.allSatisfy { wholeRestored.store.data.lastAssisted[$0.key] == date },
                  "Every whole-record assistance timestamp survives reopening the learning archive")
        wholeRestored.startDecision(); wholeRestored.submit(Move(uci: "a3a4")!)
        await Task.yield(); try await drain(wholeRestored)
        try check(wholeRestored.store.data.runs.last?.independent == false,
                  "The current checkpoint remains assisted after reading the whole record and restarting")
        wholeRestored.selectCheckpoint(index: 1); wholeRestored.startDecision()
        wholeRestored.submit(Move(uci: "c3c4")!); await Task.yield(); try await drain(wholeRestored)
        try check(wholeRestored.store.data.runs.last?.independent == false
                  && wholeRestored.store.data.runs.last?.lineID == "node-2",
                  "A later checkpoint cannot claim independence after its answer was in the complete original text")
        wholeRestored.selectUnit(id: untouchedUnit.id); wholeRestored.startDecision()
        wholeRestored.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(wholeRestored)
        try check(wholeRestored.store.data.runs.last?.independent == true
                  && wholeRestored.store.data.runs.last?.lessonID == untouchedSource.lessonID,
                  "An unrelated untouched unit can still earn independent evidence")
        let wholeRestoredAgain = make("whole-record")
        wholeRestoredAgain.selectUnit(id: exposedUnit.id); wholeRestoredAgain.selectCheckpoint(index: 2)
        wholeRestoredAgain.startDecision(); wholeRestoredAgain.submit(Move(uci: "c6c5")!)
        await Task.yield(); try await drain(wholeRestoredAgain)
        try check(wholeRestoredAgain.store.data.runs.last?.independent == false
                  && wholeRestoredAgain.store.data.runs.last?.lineID == "node-4",
                  "Even a previously unattempted branch checkpoint remains assisted through a second restart")

        let assisted = make("assisted")
        assisted.markReadingExposed(); assisted.startDecision()
        assisted.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(assisted)
        try check(assisted.store.data.runs.count == 1 && !assisted.store.data.runs[0].independent,
                  "Reading the source immediately before answering is not independent")
        let restored = make("assisted")
        try check(restored.stage == .summary && restored.assistedCount == 1, "Restart restores source and completion from the shared ledger")
        restored.selectUnit(id: fixture.1.units[0].id); restored.startDecision()
        restored.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(restored)
        try check(restored.store.data.runs.allSatisfy { !$0.independent }, "Reopening cannot erase recent reading or assistance")
        date = date.addingTimeInterval(48 * 3600)
        try check(restored.dueBookSources.count == 1 && restored.dueReviewCount == 1,
                  "An ordinarily completed source checkpoint becomes a visible due retest")
        let dueSource = restored.dueBookSources[0]
        try check(restored.startSourceReview(dueSource) && restored.stage == .decision && restored.currentSource?.key == dueSource.key,
                  "An ordinary due retest opens the exact source directly in unassisted decision mode")
        restored.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(restored)
        try check(restored.store.data.runs.last?.independent == true && restored.store.data.runs.last?.delayed == true,
                  "A genuinely delayed unassisted retry can earn independent evidence")
        try check(restored.dueBookSources.isEmpty && restored.dueReviewCount == 0,
                  "A completed delayed retest leaves the due list until its next scheduled date")

        let hints = make("hints")
        hints.startDecision(); hints.requestHint()
        try check(hints.hintLevel == 1 && hints.arrows.isEmpty && evaluated.isEmpty,
                  "First hint states the question/focus without candidate arrows")
        hints.requestHint(); await Task.yield(); try await drain(hints)
        try check(hints.hintLevel == 2 && hints.arrows.count == 1 && hints.engineAnchorPosition == .initial,
                  "Second hint offers real evaluated candidates anchored to the original student viewpoint")
        let hintsRestored = make("hints")
        try check(hintsRestored.stage == .decision && hintsRestored.hintLevel == 2, "Hint level and assisted status persist across restart")
        hintsRestored.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(hintsRestored)
        try check(hintsRestored.store.data.runs.last?.hints == 2 && hintsRestored.store.data.runs.last?.independent == false,
                  "Persisted hints cannot turn into a clean run")
        let answer = make("answer")
        answer.startDecision(); answer.revealAnswer()
        try check(answer.stage == .comparison && !answer.canAdvance && answer.store.data.runs.isEmpty,
                  "Showing the original answer never marks success")
        let answerRestored = make("answer")
        answerRestored.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(answerRestored)
        try check(answerRestored.store.data.runs.last?.independent == false, "Reopening after seeing an answer remains assisted")

        verdict = .uncertain
        let uncertain = make("uncertain")
        uncertain.startDecision(); uncertain.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(uncertain)
        try check(uncertain.store.data.runs.isEmpty && uncertain.store.data.reviews.isEmpty && !uncertain.canAdvance,
                  "Even an exact source match cannot pass with an uncertain engine verdict")
        uncertain.completeCheckpoint()
        try check(uncertain.stage == .feedback && uncertain.store.data.runs.isEmpty, "No UI action can force uncertain evidence to complete")
        shouldFail = true
        uncertain.reassess(); await Task.yield(); try await drain(uncertain)
        try check(uncertain.store.data.decisions.count == 1 && uncertain.store.data.runs.isEmpty,
                  "Engine failure adds no invented verdict or completion")
        shouldFail = false; verdict = .good
        uncertain.reassess(); await Task.yield(); try await drain(uncertain)
        try check(uncertain.canAdvance && uncertain.store.data.runs.count == 1,
                  "The same pending legal move can be re-evaluated after uncertainty/failure")

        verdict = .mistake
        let wrong = make("wrong")
        wrong.startDecision(); wrong.submit(Move(uci: "e3e4")!); await Task.yield(); try await drain(wrong)
        try check(wrong.store.data.runs.isEmpty && wrong.store.data.reviews.count == 1, "A meaningful engine mistake becomes a source-linked review, not a completion")
        let review = wrong.store.data.reviews[0]
        let origin = wrong.store.bookSource(lessonID: review.lessonID!, lineID: review.lineID!)
        try check(origin?.nodeID == 0 && origin?.recordID == fixture.1.units[0].recordID, "The review resolves to its exact source node")
        wrong.nextReply()
        try check(wrong.replyStepCount == 1 && wrong.studentSide == .red && wrong.position.sideToMove == .red,
                  "Engine PV is played one ply at a time while learner side remains red")
        wrong.returnToAnchor(); verdict = .good
        wrong.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(wrong)
        try check(wrong.store.data.runs.last?.errors == 1 && wrong.store.data.runs.last?.independent == false,
                  "Undo/retry preserves the original error and cannot upgrade evidence")
        try check(wrong.startReview(review) && wrong.position == .initial && wrong.stage == .decision,
                  "A wrong-answer review returns to its source checkpoint")
        let reviewBackup = LearningStore(directory: root.appendingPathComponent("review-backup"))
        try reviewBackup.restoreBackup(wrong.store.exportData(), builtInIDs: [], builtInSources: [])
        try check(reviewBackup.data.reviews.count == 1, "Source-linked wrong answers are backup-compatible")
        date = date.addingTimeInterval(48 * 3600)
        try check(wrong.dueReviewItems.count == 1 && wrong.dueBookSources.isEmpty && wrong.dueReviewCount == 1,
                  "An unresolved wrong answer is not duplicated by the ordinary retest queue")
        let otherEdition = BookStudySource(bookSHA: String(repeating: "b", count: 64), recordID: dueSource.recordID,
                                          nodeID: dueSource.nodeID, title: dueSource.title)
        try check(!wrong.startSourceReview(otherEdition), "A due retest from another book edition cannot target the current source")

        let analysis = make("analysis")
        analysis.startDecision(); analysis.prepareForAnalysis()
        let analysisRestored = make("analysis")
        analysisRestored.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(analysisRestored)
        try check(analysisRestored.store.data.runs.last?.independent == false, "Direct analysis is durable assistance")

        let gate = Gate(), changing = make("changing", gate: Gate())
        // Separate gate verifies an intentionally cancellation-insensitive async provider.
        let cancelled = make("cancelled", gate: gate)
        cancelled.startDecision(); cancelled.submit(Move(uci: "e3e4")!); try await waitGate(gate)
        cancelled.cancelEvaluation(); gate.finish(); await Task.yield()
        try check(!cancelled.isThinking && cancelled.store.data.runs.isEmpty && cancelled.assessment == nil,
                  "Cancelled async results are dropped even if the provider ignores cancellation")
        cancelled.reassess(); try await waitGate(gate)
        cancelled.selectUnit(id: fixture.1.units[1].id); gate.finish(); await Task.yield()
        try check(cancelled.selectedUnit?.id == fixture.1.units[1].id && cancelled.position == .initial && cancelled.store.data.runs.isEmpty,
                  "Switching lessons invalidates all old engine writes and boards")
        cancelled.selectUnit(id: fixture.1.units[0].id); cancelled.startDecision()
        cancelled.submit(Move(uci: "a3a4")!); try await waitGate(gate); gate.finish(); await Task.yield(); try await drain(cancelled)
        try check(cancelled.store.data.runs.last?.independent == false,
                  "Navigating away from a submitted attempt cannot erase the fact of retrying")
        changing.suspend()

        let resume = make("interrupted", gate: gate)
        resume.startDecision(); resume.submit(Move(uci: "a3a4")!); try await waitGate(gate)
        let interrupted = make("interrupted")
        try check(interrupted.stage == .decision && interrupted.position == .initial && !interrupted.canAdvance,
                  "Restart during a pending search safely restores the source anchor without invented grading")
        resume.suspend(); gate.finish(); await Task.yield()
        interrupted.submit(Move(uci: "a3a4")!); await Task.yield(); try await drain(interrupted)
        try check(interrupted.store.data.runs.last?.independent == false, "An interrupted replay remains explicitly assisted")
        try check(fixture.0.records[0].nodes[0].comment == "原注\r\n保持原文。" && model.book.document == nil,
                  "The lesson does not rewrite or fabricate the book's source reading tree")
        let invalid = make("invalid"), invalidFixture = makeFixture(invalidSecond: true)
        invalid.install(document: invalidFixture.0, catalog: invalidFixture.1)
        invalid.selectUnit(id: invalidFixture.1.units[1].id)
        try check(!invalid.canStart, "An invalid new source cannot accidentally reuse a previous valid anchor")
        invalid.startDecision(); invalid.submit(Move(uci: "a3a4")!)
        try check(invalid.store.data.runs.isEmpty && invalid.store.data.decisions.isEmpty,
                  "An invalid source cannot create evidence through a stale board")
        print("PASS \(checks) book lesson checks: source identity, legal alternatives, evidence, restore, cancellation, feedback and review")
    }

    static func makeFixture(invalidSecond: Bool = false, invalidSourceReply: Bool = false) -> (BookDocument, BookCourseCatalog) {
        let hash = String(repeating: "a", count: 64)
        let codes: [PieceKind: UInt8] = [.rook: 1, .horse: 2, .elephant: 3, .advisor: 4, .king: 5, .cannon: 6, .pawn: 7]
        let board: [UInt8] = Square.all.map { square in
            guard let piece = Position.initial[square] else { return 0 }
            return (piece.side == .red ? 16 : 32) + codes[piece.kind]!
        }
        let nodes: [BookNode] = [
            .init(id: 0, parentID: nil, childIDs: [1, 4], uci: nil, comment: "原注\r\n保持原文。", sourceOffset: 0, flags: 4, reservedByte: 0),
            .init(id: 1, parentID: 0, childIDs: [2], uci: "a3a4", comment: "原谱走边兵。", sourceOffset: 0, flags: 4, reservedByte: 0),
            .init(id: 2, parentID: 1, childIDs: [3], uci: invalidSourceReply ? "a6a4" : "a6a5", comment: "", sourceOffset: 0, flags: 0, reservedByte: 0),
            .init(id: 3, parentID: 2, childIDs: [], uci: "c3c4", comment: "下一判断。", sourceOffset: 0, flags: 4, reservedByte: 0),
            .init(id: 4, parentID: 0, childIDs: [5], uci: "c3c4", comment: "另一支。", sourceOffset: 0, flags: 4, reservedByte: 0),
            .init(id: 5, parentID: 4, childIDs: [], uci: "c6c5", comment: "", sourceOffset: 0, flags: 0, reservedByte: 0)]
        let records = (1...2).map { number in
            BookRecord(id: "fixture-\(number)", title: "原始标题\(number)", displayTitle: "测试谱\(number)", chapterNumber: 4,
                sectionID: "section", sectionTitle: "测试章节", startingFEN: Position.initial.fen,
                initialBoard: number == 2 && invalidSecond ? Array(repeating: 0, count: 90) : board,
                sideToMove: "w", nodes: nodes, rootNodeID: 0, isSupplement: false, sourceOffset: 0, sourceByteCount: 0, issues: [])
        }
        let comparison = BookCourseComparison(branchNodeID: 0, firstNodeID: 1, secondNodeID: 4,
            title: "同一分歧", prompt: "比较两步的条件。", explanation: "从相同起点逐步看结果。")
        let checkpoints: [BookCourseCheckpoint] = [
            .init(id: "cp-0", anchorNodeID: 0, annotationNodeID: 1, referenceNodeID: 1, title: "第一题",
                  prompt: "判断下一步。", explanation: "对照原注核验。", focus: "直接威胁", tier: .edited, comparison: comparison),
            .init(id: "cp-2", anchorNodeID: 2, annotationNodeID: 3, referenceNodeID: 3, title: "第二题",
                  prompt: "再作判断。", explanation: "对照结果。", focus: "后续变化", tier: .edited, comparison: nil),
            .init(id: "cp-4", anchorNodeID: 4, annotationNodeID: 5, referenceNodeID: 5, title: "黑方题",
                  prompt: "黑方判断。", explanation: "对照另一支。", focus: "黑方应招", tier: .edited, comparison: nil)]
        let units = records.enumerated().map { index, record in
            BookCourseUnit(id: "unit-\(index)", recordID: record.id, sourceHash: hash, sectionID: "section", title: record.displayTitle,
                tier: .edited, goal: "形成判断", connection: "连接此前例子", checkpoints: checkpoints,
                nextUnitID: index == 0 ? "unit-1" : nil, nextReason: "下篇比较另一应招。", relatedUnits: [], excludedNodeIDs: [], availabilityNote: "可练")
        }
        let source = BookDocument(id: hash, title: "测试棋书", sourceFilename: "fixture.cbl", sourceSHA256: hash,
                                 sourceByteCount: 1, records: records, chapters: [], issues: [])
        let catalog = BookCourseCatalog(sourceHash: hash, sections: [], units: units, firstRoundUnitIDs: ["unit-0"],
            stats: .init(readableRecordCount: 2, practiceRecordCount: 2, editedRecordCount: 2, sourceGuidedRecordCount: 0,
                         readingOnlyRecordCount: 0, checkpointCount: 6, editedCheckpointCount: 6, comparisonCount: 2,
                         excludedNodeCount: 0, recordsWithExcludedNodes: 0))
        return (source, catalog)
    }
}
#endif
