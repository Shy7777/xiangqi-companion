#if INTERACTION_REFINEMENT_TESTS
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct InteractionRefinementTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }; checks += 1
    }
    static func repeatedAssessmentCancellation(base: URL) async throws {
        let directory = base.appendingPathComponent("deepen-cancellation")
        let store = LearningStore(directory: directory)
        let model = LearningModel(store: store, coach: TrainingCoach())
        var originalOpen = true
        defer { if originalOpen { model.shutdown() } }
        // Both legal advisor moves preserve this drawn material. A real engine
        // verdict creates pending feedback; the alternative is deliberately not
        // the authored move, so this cannot take the instant reference shortcut.
        let before = try Position(fen: "4k4/9/9/9/9/9/9/9/4A4/3K5 w - - 0 1")
        let fixture = LearningLesson(id: "deepen-cancel-fixture", title: "重复分析取消", stage: .foundation, order: 1,
            summary: "已有反馈不能变回首次作答", goal: "保持记录", principle: "不因取消清除帮助", whenToAdapt: "重新选择", pitfalls: [], sourceIDs: [],
            lines: [StudyLine(id: "line", title: "等价选择", intent: "独立选择", adaptation: "合法变招", startingFEN: before.fen,
                              moves: [StudyMove("e1f2", "活动仕")])])
        try store.importPack(StudyPack(title: "重复分析取消", sources: [], lessons: [fixture]),
                             builtInIDs: Set(LearningModel.builtInLessons.map(\.id)), builtInSources: LearningModel.builtInSources)
        model.startLesson(fixture, mode: .test)
        try check(!model.currentRunUsedHelp && store.data.resume?.wasRetry == false,
                  "Repeat-cancel fixture starts as a genuine first independent attempt")
        model.attempt(Move(uci: "e1d2")!)
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try check(!model.busy && model.hasPendingMove && model.lastAssessment != nil && store.data.decisions.count == 1,
                  "The repeat-cancel fixture must first receive actual engine feedback")
        try check(model.lastAssessment?.verdict == .good || model.lastAssessment?.verdict == .exactBest,
                  "Equivalent advisor move should receive a stable real verdict, not simulated uncertain state")
        try check(!model.currentRunUsedHelp && !model.completed && store.data.runs.isEmpty && store.data.resume?.wasRetry == true,
                  "Pending feedback retains the existing restart protection before in-memory retry is set")
        let run = model.currentRunIdentity, decisions = store.data.decisions.count
        let hints = model.currentRunStatistics.hints, errors = model.currentRunStatistics.errors
        model.deepenStudyAssessment()
        try check(model.busy && model.isAssessingSubmission && model.currentRunUsedHelp && store.data.resume?.wasRetry == true,
                  "Repeating a judged choice must persist assistance before deeper analysis can return")
        model.stopCalculation()
        try check(!model.busy && model.studySubmission == nil && model.studyBoardPosition == before && !model.hasPendingMove,
                  "Cancelling repeated analysis restores the input board without a pending phantom move")
        try check(model.currentRunIdentity == run && model.currentRunUsedHelp && store.data.resume?.wasRetry == true &&
                  model.currentRunStatistics.hints == hints && model.currentRunStatistics.errors == errors &&
                  store.data.decisions.count == decisions && store.data.runs.isEmpty,
                  "Repeat cancellation must keep exposure without inventing another hint, mistake, verdict or completed run")
        model.shutdown(); originalOpen = false
        let restoredStore = LearningStore(directory: directory)
        let restored = LearningModel(store: restoredStore, coach: TrainingCoach())
        defer { restored.shutdown() }
        restored.resumeStudy()
        try check(restored.currentRunIdentity == run && restored.currentRunUsedHelp && restoredStore.data.resume?.wasRetry == true &&
                  restored.position == before && restored.currentRunStatistics.hints == hints && restored.currentRunStatistics.errors == errors,
                  "Restart cannot launder a cancelled repeated assessment into unassisted retrieval")
        restored.attempt(Move(uci: "e1f2")!)
        try check(restored.completed && restoredStore.data.runs.count == 1 && restoredStore.data.runs.last?.independent == false &&
                  restoredStore.data.runs.last?.wasRetry == true && restoredStore.progress(fixture.id, "line").cleanTests == 0,
                  "Changing to the authored move after cancellation must not award independent completion")
    }
    static func main() async throws {
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("interaction-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directory: directory)
        let coach = TrainingCoach(binaryURL: directory.appendingPathComponent("missing-engine"), networkURL: directory.appendingPathComponent("missing-network"))
        let model = LearningModel(store: store, coach: coach)
        defer { model.shutdown() }
        let fixture = LearningLesson(id: "interaction-fixture", title: "交互测试", stage: .opening, order: 1,
            summary: "显示已提交的选择", goal: "先判断", principle: "不预判", whenToAdapt: "回应改变", pitfalls: [], sourceIDs: [],
            lines: [StudyLine(id: "line", title: "线路", intent: "先走", adaptation: "再判断", moves: [StudyMove("a3a4", "推进")])])
        try store.importPack(StudyPack(title: "交互", sources: [], lessons: [fixture]), builtInIDs: Set(LearningModel.builtInLessons.map(\.id)), builtInSources: LearningModel.builtInSources)
        model.startLesson(fixture, mode: .practice)
        let before = model.position, move = Move(uci: "c3c4")!
        let after = try before.applying(move: move)
        model.attempt(move)
        try check(model.busy && model.isAssessingSubmission, "Submission must appear synchronously before the engine can return")
        try check(model.position == before && model.studyBoardPosition == after && model.studyBoardLastMove == move, "Visible submitted board is separate from committed course state")
        try check(store.data.runs.isEmpty && store.data.decisions.isEmpty && !model.completed, "No speculative score or learning record")
        model.stopCalculation()
        try check(model.studySubmission == nil && model.studyBoardPosition == before && !model.busy, "Cancellation restores the exact pre-submission board")
        try check(store.data.runs.isEmpty && store.data.decisions.isEmpty && model.currentRunStatistics.errors == 0, "Cancellation never penalizes an unjudged move")
        model.attempt(move)
        for _ in 0..<200 where model.busy { try await Task.sleep(nanoseconds: 5_000_000) }
        try check(!model.busy && model.studySubmission == nil && model.studyBoardPosition == before, "Engine failure clears transient submission and restores the board")
        try check(model.feedbackKind == "uncertain" && store.data.decisions.isEmpty, "Missing engine does not fabricate judgement")
        model.attempt(move); model.navigate(.home)
        try check(model.studySubmission == nil && model.page == .home, "Navigation cancels any pending presentation")
        try check(StudySubmission(position: before, move: Move(uci: "a0a9")!) == nil, "Illegal moves cannot obtain a submitted presentation")

        let notice = "检验期间查看课程、复习记录或资料可能透露题型与思路，本轮已记为含辅助；返回后仍可继续练习，但不计独立通过。"
        try check(StudyNoticePresentation.isInformational(notice), "Known assistance information can be nonmodal")
        for value in ["记录损坏", "训练安排未保存", "引擎不可用", notice + "写入失败", ""] {
            try check(!StudyNoticePresentation.isInformational(value), "Unknown or combined errors must not be silently downgraded")
        }
        try check(!StudyNoticePresentation.isInformational(nil), "No message is not an informational event")

        let initial = BoardMotionScene(position: .initial)
        for legal in Position.initial.legalMoves() {
            let next = try Position.initial.applying(move: legal)
            let scene = initial.advancing(to: next, move: legal)
            try check(scene.isSingleMove && scene.position == next, "Every genuine one-ply move may animate")
            try check(scene.tokens.first { $0.square == legal.to }?.id == initial.tokens.first { $0.square == legal.from }?.id, "Moving piece keeps identity")
            try check(Set(scene.tokens.map(\.id)).count == scene.tokens.count, "All scene identities remain unique")
            try check(scene.tokens.allSatisfy { next[$0.square] == $0.piece }, "Scene pieces exactly match the real board")
            try check(!scene.advancing(to: .initial, move: legal).isSingleMove, "Undo resets scene instead of animating a fabricated forward move")
        }
        var scene = initial
        for uci in ["b2b9", "a9b9"] { // legal cannon capture, then rook recapture
            let capture = Move(uci: uci)!, next = try scene.position.applying(move: capture)
            let count = scene.tokens.count
            scene = scene.advancing(to: next, move: capture)
            try check(scene.isSingleMove && scene.tokens.count == count - 1, "Capture removes exactly the captured token")
            try check(Set(scene.tokens.map(\.square)).count == scene.tokens.count, "Recaptures have no overlapping tokens")
        }
        let a = try Position.initial.applying(move: Move(uci: "a3a4")!)
        let b = try a.applying(move: Move(uci: "a6a5")!)
        try check(!initial.advancing(to: b, move: Move(uci: "a6a5")!).isSingleMove, "Multi-ply course jumps are not portrayed as one legal move")
        try check(!initial.advancing(to: a, move: nil).isSingleMove, "Imports without a verified move snap honestly")
        try check(!initial.advancing(to: a, move: Move(uci: "c3c4")!).isSingleMove, "Wrong last-move metadata cannot create false animation")
        if ProcessInfo.processInfo.environment["XQ_RUN_ENGINE_TESTS"] == "1" {
            try await repeatedAssessmentCancellation(base: directory)
        } else {
            print("SKIP: live-engine repeated assessment cancellation (use verify.sh --with-engine)")
        }
        print("PASS \(checks) interaction refinement checks: immediate legal submission, cancel/failure isolation, nonmodal information boundaries, identity-preserving board motion and truthful jumps")
    }
}
#endif
