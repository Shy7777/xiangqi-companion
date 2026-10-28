#if LEARNING_JOURNEY_TESTS
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct LearningJourneyTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure(message: message) }; checks += 1
    }
    static func reject(_ action: () throws -> Void) throws {
        do { try action() } catch { checks += 1; return }
        throw Failure(message: "Expected validation failure")
    }
    static func entry(_ p: Position, name: String, path: String, index: Int) -> LibraryCourseEntry {
        .init(id: LibraryCourseEntry.identifier(fen: p.fen), fen: p.fen, title: name,
              memberships: [.init(groupID: path, title: name, sourceIndex: index, category: path, section: .section(for: path))])
    }
    static func skipNavigationTests(base: URL, first: StudyTarget, second: StudyTarget) throws {
        func item(_ target: StudyTarget) -> LearningPracticeItem {
            .init(kind: .lesson, targetID: target.lesson.id, lineID: target.line.id,
                  title: "独立判断", reason: "先不看答案", mode: .test)
        }
        func fixture(_ name: String, items: [LearningPracticeItem]) throws -> (LearningStore, LearningModel) {
            let store = LearningStore(directory: base.appendingPathComponent("skip-" + name))
            let plan = LearningPracticePlan(id: UUID(), created: Date(), routeID: nil,
                                           title: "跳过测试", reason: "不把跳过当完成", items: items)
            try store.setLearningJourney(.init(selectedRouteID: nil, plan: plan))
            return (store, LearningModel(store: store, coach: TrainingCoach()))
        }

        let (finalStore, final) = try fixture("final", items: [item(first)])
        defer { final.shutdown() }
        final.resumeJourneySession()
        let skippedRun = final.currentRunIdentity
        try check(final.isJourneyStudy && !final.currentRunUsedHelp && finalStore.data.resume?.wasRetry == false,
                  "Final-item fixture starts as an actual bound unassisted test")
        final.notice = "保留已有通知"
        let skippedAt = Date()
        final.skipJourneyItem()
        try check(final.journeyPlan?.isFinished == true && final.journeyPlan?.skippedIndices == [0] &&
                  final.journeyPlan?.completedIndices.isEmpty == true && final.journeyPlan?.activeRunID == nil &&
                  final.page == .courses && final.courseDisplay == .roadmap && !final.completed,
                  "Skipping the final test returns to the route without manufacturing completed study state")
        try check(final.notice == "保留已有通知",
                  "Final skip still emits an ongoing-test assistance warning or erases an unrelated notice")
        try check(final.currentRunUsedHelp && finalStore.data.resume?.runID == skippedRun &&
                  finalStore.data.resume?.wasRetry == true && finalStore.data.resume?.hints == 0 &&
                  finalStore.data.resume?.errors == 0 &&
                  finalStore.data.lastAssisted[LearningStore.key(first.lesson.id, first.line.id)].map { $0 >= skippedAt } == true,
                  "Suppressing the redundant skip warning must preserve exposure and the original resumable run")
        try check(finalStore.data.runs.isEmpty && finalStore.data.decisions.isEmpty &&
                  finalStore.progress(first.lesson.id, first.line.id).cleanTests == 0 &&
                  finalStore.progress(first.lesson.id, first.line.id).completions == 0,
                  "The final skip generated hints, decisions, scores or completions")
        let restoredStore = LearningStore(directory: finalStore.directory)
        let restored = LearningModel(store: restoredStore, coach: TrainingCoach())
        defer { restored.shutdown() }
        restored.resumeStudy()
        try check(restored.currentRunIdentity == skippedRun && restored.currentRunUsedHelp && !restored.isJourneyStudy &&
                  restoredStore.data.runs.isEmpty && restoredStore.data.resume?.wasRetry == true,
                  "Restart laundered a skipped exposed attempt into an independent test or rebound the finished group")

        let (normalStore, normal) = try fixture("normal-navigation", items: [item(first)])
        defer { normal.shutdown() }
        normal.resumeJourneySession(); normal.navigate(.courses)
        try check(normal.notice?.contains("本轮已记为含辅助") == true && normal.currentRunUsedHelp &&
                  normalStore.data.resume?.wasRetry == true && normal.journeyPlan?.skippedIndices.isEmpty == true,
                  "Normal navigation from an ongoing test lost its warning or assistance protection")

        let missing = LearningPracticeItem(kind: .lesson, targetID: "unrelated-missing", lineID: "missing",
                                          title: "另一个计划项", reason: "不能覆盖正在进行的检验", mode: .test)
        let (otherStore, other) = try fixture("unrelated", items: [missing])
        defer { other.shutdown() }
        other.startLesson(first.lesson, line: first.line, mode: .test)
        let otherRun = other.currentRunIdentity
        try check(!other.isJourneyStudy && !other.currentRunUsedHelp, "Unrelated-test fixture must not be bound to the skipped item")
        other.skipJourneyItem()
        try check(other.notice?.contains("本轮已记为含辅助") == true && other.currentRunUsedHelp &&
                  otherStore.data.resume?.runID == otherRun && otherStore.data.resume?.wasRetry == true &&
                  otherStore.data.runs.isEmpty,
                  "Skipping another item silenced or bypassed protection for the genuinely ongoing test")

        let (middleStore, middle) = try fixture("middle", items: [item(first), item(second)])
        defer { middle.shutdown() }
        middle.resumeJourneySession(); middle.skipJourneyItem()
        try check(middle.journeyPlan?.cursor == 1 && middle.journeyPlan?.skippedIndices == [0] &&
                  middle.journeyPlan?.isFinished == false && middle.lessonID == second.lesson.id &&
                  middle.lineID == second.line.id && middle.isJourneyStudy && !middle.currentRunUsedHelp &&
                  middleStore.data.resume?.wasRetry == false,
                  "Skipping a middle item contaminated the next genuine unassisted test")
        try check(middleStore.data.lastAssisted[LearningStore.key(first.lesson.id, first.line.id)] == nil &&
                  middleStore.data.runs.isEmpty && middleStore.data.decisions.isEmpty,
                  "A middle skip pre-recorded a reading transition that did not occur")

        let (failedStore, failed) = try fixture("write-failure", items: [item(first)])
        defer { failed.shutdown() }
        failed.resumeJourneySession()
        let savedPlan = failed.journeyPlan, failedRun = failed.currentRunIdentity
        let archiveURL = failedStore.directory.appendingPathComponent("learning.json")
        let archiveBefore = try Data(contentsOf: archiveURL)
        let previousURL = failedStore.directory.appendingPathComponent("learning.previous.json")
        try FileManager.default.moveItem(at: previousURL, to: failedStore.directory.appendingPathComponent("preserved.previous.json"))
        try FileManager.default.createDirectory(at: previousURL, withIntermediateDirectories: false)
        failed.skipJourneyItem()
        try check(failed.notice?.contains("跳过操作未保存") == true && failed.journeyPlan == savedPlan &&
                  failed.page == .study && !failed.currentRunUsedHelp && failed.currentRunIdentity == failedRun,
                  "Failed skip committed a transition or prematurely marked the still-active attempt assisted")
        try check(failedStore.data.resume?.wasRetry == false &&
                  failedStore.data.lastAssisted[LearningStore.key(first.lesson.id, first.line.id)] == nil &&
                  failedStore.data.runs.isEmpty && (try Data(contentsOf: archiveURL)) == archiveBefore,
                  "Failed skip changed persisted exposure, scoring or the original archive")
    }
    static func main() async throws {
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("journey-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directory: directory)
        let learner = LearningModel(store: store, coach: TrainingCoach())
        defer { learner.shutdown() }
        let routes = LearningRoadmapContent.routes, sources = LearningRoadmapContent.sources
        try check(routes.count == 16 && Set(routes.map(\.id)).count == 16, "Sixteen real capability topics, unique identities")
        try check(sources.count == 8 && Set(sources.map(\.id)).count == 8, "Source references are unique")
        let known = Dictionary(LearningModel.builtInLessons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for route in routes {
            try check(!route.goal.isEmpty && route.principles.count >= 2 && route.pitfalls.count >= 1 && !route.adaptation.isEmpty,
                      "Each route teaches a goal, rules, counterexamples and adaptation")
            try check(!route.lessonIDs.isEmpty && Set(route.lessonIDs).count == route.lessonIDs.count, "Route examples are not duplicated")
            try check(route.sourceIDs.allSatisfy { id in sources.contains { $0.id == id } }, "Real source lookup")
            for id in route.lessonIDs {
                try check(known[id]?.lines.contains { $0.checkpoints?.isEmpty == false } == true, "Every example ID resolves to an existing decision lesson")
            }
            if route.phase == .middlegame { try check(route.pool.sections.isEmpty, "No endgame library mislabeled as middlegame curriculum") }
        }
        let a = entry(.initial, name: "順相局", path: "opening-repertoire.json", index: 1)
        let b = entry(try Position.initial.applying(move: Move(uci: "a3a4")!), name: "飛相對右馬", path: "opening-repertoire.json", index: 2)
        let c = entry(try Position.initial.applying(move: Move(uci: "c3c4")!), name: "順炮直車", path: "opening-repertoire.json", index: 3)
        let pawn = entry(try Position(fen: "4k4/9/9/9/4P4/9/9/9/9/4K4 w - - 0 1"), name: "兵帅", path: "endgames_all.json", index: 1)
        learner.libraryCatalog = .init(pwaCommit: String(repeating: "a", count: 40), entries: [a,b,c,pawn], groups: [])
        let opening = routes.first { $0.phase == .opening }!
        try check(learner.routeEntries(opening).count == 3, "Full opening pool, not hard-coded selected examples")
        try check(LearningRoutePool(sections: [.endgames], material: .pawnOnly).includes(pawn), "Pure pawn structure includes real pawns")
        try check(!LearningRoutePool(sections: [.opening], material: .pawnOnly).includes(a), "Opening full material is not a pawn ending")
        try check(!LearningRoutePool(sections: [.opening], sourcePaths: ["endgames_all.json"]).includes(a), "File and section filters intersect")
        let before = try store.exportData()
        let originalItems = learner.recommendedPracticeItems(route: opening)
        learner.libraryQuery = "not-a-match"; learner.libraryFamily = "不存在"; learner.libraryStatusFilter = 3
        try check(learner.recommendedPracticeItems(route: opening) == originalItems, "Homepage plan does not inherit invisible browser filters")
        try check(try store.exportData() == before, "Read-only planning and coverage create no progress")
        try check(originalItems.count >= 3 && originalItems.count <= 6 && Set(originalItems.map(\.id)).count == originalItems.count, "Bounded real-item plan, no duplicates")
        try check(learner.recommendedPracticeItems(route: opening, diagnostic: true).allSatisfy { $0.mode == .test }, "Diagnostic hides example guidance")
        let coverage = learner.routeCoverage(opening)
        try check(coverage.positionCount == 3 && coverage.practicedPositions == 0 && coverage.independentPositions == 0, "Inventory not completion")
        learner.libraryCatalog = .init(pwaCommit: String(repeating: "a", count: 40), entries: [a], groups: [])
        try check(learner.routeEntries(opening).count == 1, "Replacing snapshot invalidates route pool cache even with same commit")
        learner.libraryCatalog = .init(pwaCommit: String(repeating: "a", count: 40), entries: [a,b,c,pawn], groups: [])
        let target = learner.routeTargets(opening)[0]
        let second = learner.routeTargets(opening)[1]
        let items: [LearningPracticeItem] = [
            .init(kind: .lesson, targetID: target.lesson.id, lineID: target.line.id, title: "第一例", reason: "看一例", mode: .demonstration),
            .init(kind: .lesson, targetID: second.lesson.id, lineID: second.line.id, title: "第二例", reason: "换个应对", mode: .practice)]
        let plan = LearningPracticePlan(id: UUID(), created: Date(), routeID: opening.id, title: opening.title, reason: opening.goal, items: items)
        try plan.validate()
        try store.setLearningJourney(.init(selectedRouteID: opening.id, plan: plan))
        learner.resumeJourneySession()
        try check(learner.isJourneyStudy && learner.journeyPlan?.activeRunID == learner.currentRunIdentity, "Start links the actual run to the intended plan item")
        learner.demoStep(1)
        let savedRun = store.data.resume!.runID
        let savedPlan = learner.journeyPlan!
        let reopenedStore = LearningStore(directory: directory)
        let reopened = LearningModel(store: reopenedStore, coach: TrainingCoach())
        reopened.resumeJourneySession()
        try check(reopened.isJourneyStudy && reopened.cursor == 1 && reopened.currentRunIdentity == savedRun, "Restart restores the same current run and cursor")
        try check(reopened.journeyPlan == savedPlan, "Resume does not reshuffle or regenerate the plan")
        reopened.shutdown()
        learner.goToDemoPly(target.line.moves.count)
        try check(learner.completed && learner.journeyPlan?.completedIndices == [0], "Actual completion marks precisely the current plan item")
        try check(learner.studyCompletionSummary?.independent == false && store.progress(target.lesson.id, target.line.id).cleanTests == 0,
                  "Demonstration completion cannot become independent skill")
        let runs = store.data.runs.count
        learner.completeJourneyItem(runID: learner.currentRunIdentity)
        try check(store.data.runs.count == runs && learner.journeyPlan?.completedIndices == [0], "Completion is idempotent")
        learner.continueJourneySession()
        try check(learner.journeyPlan?.cursor == 1 && learner.isJourneyStudy && learner.lessonID == second.lesson.id,
                  "Next advances to the exact second scheduled item")
        learner.skipJourneyItem()
        try check(learner.journeyPlan?.isFinished == true && learner.journeyPlan?.skippedIndices == [1] && learner.courseDisplay == .roadmap,
                  "Skipping ends the final item visibly instead of wrapping forever")
        try check(store.data.runs.count == runs && store.progress(second.lesson.id, second.line.id).completions == 0,
                  "Skip creates neither a run nor a completion")
        learner.continueJourneySession()
        try check(learner.journeyPlan?.cursor == 1 && learner.journeyPlan?.isFinished == true, "Completed group has a terminal state")
        let archive = try store.exportData()
        _ = try learner.restoreLearningArchive(archive)
        try check(learner.journeyPlan?.isFinished == true, "Backup round trip preserves the terminal group")
        // An unfinished test cannot be consumed by watching its answer, including
        // after the demo was finished and the application has restarted.
        let testItem = LearningPracticeItem(kind: .lesson, targetID: target.lesson.id, lineID: target.line.id,
            title: "独立检验", reason: "不看答案作答", mode: .test)
        let testPlan = LearningPracticePlan(id: UUID(), created: Date(), routeID: opening.id, title: "检验", reason: "独立判断", items: [testItem])
        try store.setLearningJourney(.init(selectedRouteID: opening.id, plan: testPlan))
        learner.resumeJourneySession(); learner.switchMode(.demonstration); learner.goToDemoPly(target.line.moves.count)
        try check(learner.journeyPlan?.completedIndices.isEmpty == true, "Demo does not consume a requested learner-decision item")
        try check(learner.studyCompletionNextTitle == "回到本题，自己走", "Next action explains the still-pending decision")
        learner.continueJourneySession()
        try check(learner.mode == .test && !learner.completed && learner.currentRunUsedHelp, "Returning from demo keeps assistance rather than laundering an independent score")
        learner.switchMode(.demonstration); learner.goToDemoPly(target.line.moves.count)
        let demoStore = LearningStore(directory: directory)
        let demoRestart = LearningModel(store: demoStore, coach: TrainingCoach())
        demoRestart.resumeJourneySession()
        try check(demoRestart.mode == .test && demoRestart.currentRunUsedHelp && demoRestart.isJourneyStudy,
                  "Finished demo -> restart -> requested test retains position-specific exposure")
        demoRestart.shutdown()
        // A review must not inherit the old course run ID or resume the wrong board.
        learner.startLesson(target.lesson, line: target.line, mode: .practice)
        let oldCourseRun = learner.currentRunIdentity
        store.addReview(lessonID: nil, lineID: nil, title: "测试错题", fen: Position.initial.fen,
                        attempted: "a3a4", suggested: "c3c4", detail: "复查回应", replyPV: [])
        let review = store.data.reviews[0]
        let reviewItem = LearningPracticeItem(kind: .review, targetID: review.id.uuidString, title: "错题", reason: "到期重试", mode: .test)
        let reviewPlan = LearningPracticePlan(id: UUID(), created: Date(), routeID: nil, title: "复习", reason: "先回忆", items: [reviewItem])
        try store.setLearningJourney(.init(selectedRouteID: opening.id, plan: reviewPlan))
        learner.resumeJourneySession()
        try check(learner.activeReview?.id == review.id && learner.currentRunIdentity != oldCourseRun && learner.isJourneyStudy,
                  "Review owns a fresh run identity, not the old course's resume")
        store.markReviewAssisted(review.id)
        let reviewStore = LearningStore(directory: directory)
        let reviewRestart = LearningModel(store: reviewStore, coach: TrainingCoach())
        reviewRestart.resumeJourneySession()
        try check(reviewRestart.activeReview?.id == review.id && reviewRestart.lessonID == nil && reviewRestart.currentRunUsedHelp,
                  "Review restart selects the intended review and preserves help, not an unrelated old course")
        reviewRestart.shutdown()
        let missing = LearningPracticeItem(kind: .lesson, targetID: "removed-example", lineID: "missing", title: "缺失例题", reason: "待恢复", mode: .practice)
        let missingPlan = LearningPracticePlan(id: UUID(), created: Date(), routeID: nil, title: "恢复测试", reason: "缺失可跳过", items: [missing])
        try store.setLearningJourney(.init(selectedRouteID: opening.id, plan: missingPlan))
        let runsBeforeMissing = store.data.runs.count
        learner.resumeJourneySession()
        try check(learner.notice?.contains("暂不可用") == true, "Missing lesson does not fabricate a ready state")
        learner.skipJourneyItem()
        try check(learner.journeyPlan?.isFinished == true && learner.journeyPlan?.activeRunID == nil && !learner.isJourneyStudy,
                  "Unavailable item can be skipped outside a study session and cannot rebind a skipped run")
        try check(store.data.runs.count == runsBeforeMissing, "Missing-item recovery never produces scores")
        var invalid = plan; invalid.completedIndices = [2]
        try reject { try invalid.validate() }
        invalid = plan; invalid.skippedIndices = [0]; invalid.completedIndices = [0]
        try reject { try invalid.validate() }
        invalid = plan; invalid.cursor = 1
        try reject { try invalid.validate() }
        let duplicated = LearningPracticePlan(id: UUID(), created: Date(), routeID: nil, title: "x", reason: "x", items: [items[0],items[0]])
        try reject { try duplicated.validate() }
        let originalArchive = try store.exportData()
        try reject { try store.setLearningJourney(.init(selectedRouteID: nil, plan: invalid)) }
        try check(try store.exportData() == originalArchive, "Invalid plan cannot mutate archive")
        let legacy = try JSONDecoder().decode(LearningArchive.self, from: JSONEncoder().encode(LearningArchive()))
        try check(legacy.learningJourney == nil, "Legacy optional field remains compatible")
        learner.libraryQuery = "飛相"; learner.libraryFamily = "顺相／列相／飞相"; learner.libraryBrowserPage = 2
        learner.returnToLibraryBrowser()
        try check(learner.libraryQuery == "飛相" && learner.libraryFamily == "顺相／列相／飞相" && learner.libraryBrowserPage == 2,
                  "Leaving an authored lesson for free browser does not erase filters")
        try skipNavigationTests(base: directory, first: target, second: second)
        print("PASS \(checks) learning-journey checks: 16 content routes, genuine pools, neutral diagnostic, finite groups, skip, exact resume, stored-result summary, backup and filter independence")
    }
}
#endif
