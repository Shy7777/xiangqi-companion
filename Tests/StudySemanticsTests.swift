#if STUDY_SEMANTICS_TESTS
import Foundation

struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct StudySemanticsTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }; checks += 1
    }
    static func same<T: Encodable>(_ first: T, _ second: T) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let lhs = try? encoder.encode(first), let rhs = try? encoder.encode(second) else { return false }
        return lhs == rhs
    }

    static func lesson(id: String, checkpoint: Bool = false) -> LearningLesson {
        var line = StudyLine(id: "line", title: "参考线路", intent: "独立比较选择", adaptation: "应对变化时重新判断",
            startingFEN: checkpoint ? "4k4/9/9/9/9/9/9/9/4A4/3K5 w - - 0 1" : Position.initial.fen,
            moves: (checkpoint ? ["e1f2", "e9f9", "f2e1", "f9e9"] : ["a3a4", "a6a5", "c3c4", "c6c5", "e3e4"])
                .map { StudyMove($0, "参考谱说明", hint: "比较走后局面") })
        if checkpoint {
            line.checkpoints = [0, 2].map { StudyCheckpoint(ply: $0, title: "关键判断", prompt: "在棋盘选择", focus: "看对方回应", explanation: "比较合理着法，不把参考谱等同于引擎唯一答案") }
        }
        return LearningLesson(id: id, title: "交互语义测试", stage: .opening, order: 1,
            summary: "回退保留学习证据", goal: "会判断", principle: "先尝试", whenToAdapt: "对方改变应手", pitfalls: [], sourceIDs: [], lines: [line])
    }

    static func model(base: URL, course: LearningLesson, realEngine: Bool = false) throws -> LearningModel {
        let directory = base.appendingPathComponent(course.id)
        let store = LearningStore(directory: directory)
        try store.importPack(StudyPack(title: "状态回归", sources: [], lessons: [course]),
            builtInIDs: Set(LearningModel.builtInLessons.map(\.id)), builtInSources: LearningModel.builtInSources)
        let coach = realEngine ? TrainingCoach() : TrainingCoach(binaryURL: directory.appendingPathComponent("missing-engine"),
            networkURL: directory.appendingPathComponent("missing-network"))
        return LearningModel(store: store, coach: coach)
    }

    static func standardRewind(base: URL) throws {
        let course = lesson(id: "standard-rewind"), learner = try model(base: base, course: course)
        defer { learner.shutdown() }
        learner.startLesson(course, mode: .test)
        let run = learner.currentRunIdentity
        try check(!learner.canRewindStudy, "An untouched first decision has no previous learner move")
        learner.attempt(Move(uci: "a3a4")!)
        try check(learner.cursor == 1 && learner.awaitingContinue && learner.canRewindStudy,
                  "Accepted reference move exposes rewind before the opponent responds")
        try check(!learner.studyUndoTitle.isEmpty, "Rewind has a user-facing action label")
        let firstDecisions = learner.store.data.decisions
        learner.rewindStudy()
        try check(learner.cursor == 0 && learner.position == .initial && !learner.awaitingContinue && !learner.hasPendingMove,
                  "Rewind returns to the actual position before the student's move")
        try check(learner.currentRunIdentity == run && learner.mode == .practice && learner.currentRunUsedHelp,
                  "Rewinding an unfinished test keeps the run but explicitly becomes assisted practice")
        try check(same(learner.store.data.decisions, firstDecisions) && learner.store.data.runs.isEmpty &&
                  learner.store.data.resume?.wasRetry == true && learner.store.data.resume?.mode == .practice,
                  "Rewind persists retry evidence without deleting an answer or manufacturing a run")
        try check(learner.store.recentlyAssisted(lessonID: course.id, lineID: "line"),
                  "Regular authored courses persist assistance, not only library-generated courses")

        learner.attempt(Move(uci: "a3a4")!); learner.continueStudy()
        learner.hint()
        learner.attempt(Move(uci: "c3c4")!); learner.continueStudy()
        let decisions = learner.store.data.decisions, hints = learner.currentRunStatistics.hints
        try check(learner.cursor == 4 && learner.canRewindStudy, "The opponent response still permits undo of the latest learner decision")
        learner.rewindStudy()
        try check(learner.cursor == 2 && learner.position == learner.studyPositions[2],
                  "Rewind after an opponent move returns two plies, not to the opponent's turn")
        try check(same(learner.store.data.decisions, decisions) && learner.currentRunStatistics.hints == hints && hints == 1,
                  "Neither a previous answer nor consumed help is erased by rewind")
        learner.rewindStudy()
        try check(learner.cursor == 0 && !learner.canRewindStudy, "Repeated rewind stops at the first learner decision")
        learner.navigate(.home)
        try check(!learner.canRewindStudy, "Rewind cannot operate on another workspace page")
        learner.resumeStudy()
        try check(learner.currentRunIdentity == run && learner.currentRunUsedHelp && learner.mode == .practice &&
                  learner.cursor == 0 && learner.currentRunStatistics.hints == hints,
                  "Resume restores the same rewound run and its assistance")
    }

    static func restoredEvidence(base: URL) throws {
        let course = lesson(id: "restored-evidence"), learner = try model(base: base, course: course)
        defer { learner.shutdown() }
        let saved = StudyResume(lessonID: course.id, lineID: "line", mode: .test, cursor: 2,
            hints: 2, errors: 1, wasRetry: true, runID: UUID(), started: Date(), wasUnseen: false)
        learner.startLesson(course, mode: .test, from: saved.cursor, restoring: saved)
        learner.rewindStudy()
        try check(learner.cursor == 0 && learner.currentRunIdentity == saved.runID && learner.mode == .practice,
                  "Restored runs use the same rewind semantics")
        try check(learner.currentRunStatistics.hints == 2 && learner.currentRunStatistics.errors == 1 &&
                  learner.store.data.resume?.hints == 2 && learner.store.data.resume?.errors == 1,
                  "A previously recorded mistake and hint survive both memory and persistence")
    }

    static func completedRun(base: URL) throws {
        let course = lesson(id: "completed-run"), learner = try model(base: base, course: course)
        defer { learner.shutdown() }
        learner.startLesson(course, mode: .test)
        for uci in ["a3a4", "c3c4", "e3e4"] { learner.attempt(Move(uci: uci)!); learner.continueStudy() }
        let run = learner.currentRunIdentity, runs = learner.store.data.runs, progress = learner.store.progress(course.id, "line")
        try check(learner.completed && runs.count == 1 && runs[0].independent && progress.cleanTests == 1,
                  "Fixture first finishes a genuinely clean independent reference test")
        learner.rewindStudy()
        try check(!learner.completed && learner.cursor == 4 && learner.mode == .practice && learner.currentRunIdentity != run,
                  "Reviewing a finished decision opens a new practice run rather than reopening a finalized result")
        try check(learner.currentRunUsedHelp && same(learner.store.data.runs, runs) && same(learner.store.progress(course.id, "line"), progress),
                  "Completed scores are immutable when returning to the final decision")
        learner.attempt(Move(uci: "e3e4")!)
        try check(learner.completed && learner.store.data.runs.count == 2 && same(learner.store.data.runs[0], runs[0]) &&
                  learner.store.data.runs.last?.independent == false && learner.store.progress(course.id, "line").cleanTests == 1,
                  "Finishing a replay cannot overwrite the old run or add an independent pass")
    }

    static func explicitHelpTransition(base: URL) throws {
        let course = lesson(id: "help-transition"), learner = try model(base: base, course: course)
        defer { learner.shutdown() }
        learner.startLesson(course, mode: .test)
        learner.attempt(Move(uci: "a3a4")!); learner.continueStudy()
        let before = learner.position, run = learner.currentRunIdentity, decisions = learner.store.data.decisions
        learner.enterGuidedPractice()
        try check(learner.mode == .practice && learner.position == before && learner.cursor == 2 && learner.currentRunIdentity == run,
                  "Requesting guidance changes mode in place without restarting the line or moving any pieces")
        try check(learner.currentRunUsedHelp && learner.currentRunStatistics.hints == 0 && learner.currentRunStatistics.errors == 0 &&
                  same(learner.store.data.decisions, decisions) && learner.store.data.resume?.wasRetry == true,
                  "Looking at instructional material is exposure, not an invented hint click or mistake")
        learner.attempt(Move(uci: "c3c4")!); learner.continueStudy(); learner.attempt(Move(uci: "e3e4")!)
        try check(learner.completed && learner.store.data.runs.count == 1 && learner.store.data.runs[0].id == run &&
                  !learner.store.data.runs[0].independent && learner.store.progress(course.id, "line").cleanTests == 0,
                  "Finishing after explicit guidance cannot retain the old no-help test status")
    }

    static func checkpointRewind(base: URL) throws {
        let course = lesson(id: "checkpoint-rewind", checkpoint: true), learner = try model(base: base, course: course)
        defer { learner.shutdown() }
        let line = course.lines[0]
        let accepted = StudyResume(lessonID: course.id, lineID: line.id, mode: .test, cursor: 2,
            hints: 2, errors: 1, wasRetry: true, runID: UUID(), started: Date(), wasUnseen: false,
            completedCheckpoints: [0, 2], acceptedCheckpoint: 2, checkpointMove: "f2e1", contentFingerprint: line.contentFingerprint)
        learner.startLesson(course, mode: .test, from: accepted.cursor, restoring: accepted)
        try check(learner.referenceContinuationNeeded && learner.studyDecisionProgress.completed == 2 && learner.canRewindStudy,
                  "Restored accepted checkpoint can be rewound without requiring an in-memory engine verdict")
        learner.rewindStudy()
        try check(learner.cursor == 2 && learner.position == learner.studyPositions[2] && !learner.hasPendingMove &&
                  !learner.referenceContinuationNeeded && learner.studyDecisionProgress.completed == 1,
                  "Undoing accepted checkpoint keeps prior checkpoints and removes the current acceptance")
        try check(learner.store.data.resume?.completedCheckpoints == [0] && learner.store.data.resume?.acceptedCheckpoint == nil &&
                  learner.store.data.resume?.checkpointMove == nil && learner.currentRunStatistics.errors == 1 && learner.currentRunStatistics.hints == 2,
                  "Checkpoint rewind serializes a valid unaccepted decision and retains evidence")
        learner.rewindStudy()
        try check(learner.cursor == 0 && learner.studyDecisionProgress.completed == 0 && !learner.canRewindStudy,
                  "A second rewind visits the previous declared checkpoint instead of an arbitrary half-move")

        let first = StudyResume(lessonID: course.id, lineID: line.id, mode: .practice, cursor: 0,
            hints: 0, errors: 0, wasRetry: false, runID: UUID(), started: Date(), wasUnseen: true,
            completedCheckpoints: [0], acceptedCheckpoint: 0, checkpointMove: "e1f2", contentFingerprint: line.contentFingerprint)
        learner.startLesson(course, mode: .practice, from: 0, restoring: first)
        learner.continueStudy()
        try check(learner.cursor == 2 && learner.studyDecisionProgress.completed == 1, "Continuation reaches the next checkpoint")
        learner.rewindStudy()
        try check(learner.cursor == 0 && learner.studyDecisionProgress.completed == 0 && learner.currentRunIdentity == first.runID,
                  "Undo after checkpoint continuation returns to the preceding decision in the same run")
    }

    static func demonstration(base: URL) throws {
        let course = lesson(id: "demo-rewind"), learner = try model(base: base, course: course)
        defer { learner.shutdown() }
        learner.startLesson(course, mode: .demonstration)
        learner.goToDemoPly(3)
        learner.rewindStudy()
        try check(learner.cursor == 2 && learner.mode == .demonstration && learner.store.data.decisions.isEmpty,
                  "Demonstration previous means one half-move, not a student retry")
        learner.goToDemoPly(course.lines[0].moves.count)
        let runs = learner.store.data.runs
        learner.rewindStudy()
        try check(learner.cursor == course.lines[0].moves.count - 1 && same(learner.store.data.runs, runs) && learner.store.data.decisions.isEmpty,
                  "Returning from completed demonstration preserves its record without recording a learner decision")
    }

    static func referenceFeedback(base: URL) async throws {
        let course = lesson(id: "reference-feedback", checkpoint: true), learner = try model(base: base, course: course, realEngine: true)
        defer { learner.shutdown() }
        learner.startLesson(course, mode: .practice)
        learner.attempt(Move(uci: "e1f2")!)
        try check(learner.busy && !learner.canRewindStudy, "Pending analysis uses cancellation rather than an ambiguous historical rewind")
        let deadline = Date().addingTimeInterval(10)
        while learner.busy && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try check(!learner.busy && learner.referenceContinuationNeeded && learner.lastAssessment != nil,
                  "Real engine accepts the legal drawn reference checkpoint")
        try check(learner.lastAssessment?.verdict == .good || learner.lastAssessment?.verdict == .exactBest,
                  "Reference match fixture has a stable verdict rather than fabricated success")
        try check(learner.feedbackTitle.contains("参考") && learner.feedbackTitle.contains("一致") && learner.feedbackTitle != "这步也可以",
                  "Following the reference is acknowledged explicitly, independent of its engine rank")
        try check(learner.submissionSummary?.contains("参考谱") == true && learner.submissionSummary?.contains("走中") == true,
                  "The short summary cannot contradict the reference-aware headline")
        let decisions = learner.store.data.decisions
        learner.rewindStudy()
        try check(learner.cursor == 0 && !learner.hasPendingMove && learner.studyDecisionProgress.completed == 0 &&
                  same(learner.store.data.decisions, decisions) && learner.currentRunUsedHelp,
                  "Rewinding an actually assessed checkpoint preserves the submitted answer while reopening the board")
    }

    static func referencePolicy() throws {
        let move = Move(uci: "a3a4")!
        for verdict: MoveAssessment.Verdict in [.exactBest, .good, .inaccuracy, .mistake, .uncertain] {
            let assessment = MoveAssessment(move: move, bestMove: move, verdict: verdict, title: "原始引擎评语", detail: "原始证据",
                lossCP: 0, beforeScore: .cp(0), afterScore: .cp(0), replyPV: [], bestPV: [move.uci])
            let good = verdict == .exactBest || verdict == .good
            try check(StudyReferenceFeedback.title(for: assessment, matchesReference: true) ==
                      (good ? "与参考谱一致" : "与参考谱一致 · 需要复核"),
                      "Reference identity must not conceal uncertainty or a detected risk")
            try check(StudyReferenceFeedback.title(for: assessment, matchesReference: false) == assessment.title,
                      "A different choice retains its genuine engine assessment")
            let summary = StudyReferenceFeedback.summary(for: assessment, matchesReference: true, purpose: "目的第一句。其余说明")
            try check(summary.contains("参考谱") || summary.contains("按谱"), "Reference summary acknowledges the actual source match")
            if good {
                try check(summary.contains("目的第一句") && !summary.contains("其余说明") && !summary.contains("也可以"),
                          "Positive source match shows the concise move purpose without dismissive alternative wording")
            } else if verdict == .uncertain {
                try check(summary.contains("不计错"), "Uncertain reference match cannot claim an error or a pass")
            } else {
                try check(summary.contains("风险"), "Poor engine assessment remains visible even for an authored move")
            }
        }
    }

    static func main() async throws {
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("study-semantics-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try referencePolicy()
        try standardRewind(base: directory)
        try restoredEvidence(base: directory)
        try completedRun(base: directory)
        try explicitHelpTransition(base: directory)
        try checkpointRewind(base: directory)
        try demonstration(base: directory)
        if ProcessInfo.processInfo.environment["XQ_RUN_ENGINE_TESTS"] == "1" {
            try await referenceFeedback(base: directory)
        } else {
            print("SKIP: live-engine reference feedback (use verify.sh --with-engine)")
        }
        print("PASS \(checks) study semantics checks: reference-aware feedback, contextual rewind, mode clarity and immutable learning evidence")
    }
}
#endif
