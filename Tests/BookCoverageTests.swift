#if BOOK_COVERAGE_TESTS
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct BookCoverageTests {
    static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let all = LearningModel.builtInLessons
        try BookCoverage.validate(lessons: all)
        try GuidedCatalogValidator.validate(textbooks: GuidedCurriculum.books, chapters: GuidedCurriculum.chapters, lessons: all)
        try StudyPack(title: "release curriculum", sources: LearningModel.builtInSources, lessons: all).validate()
        let inventory = CurriculumInventory(lessons: all)
        check(all.count == 84 && inventory.courses == 48 && inventory.lines == 92 && inventory.uniqueStarts == 73,
              "Public coverage counts only retained playable courses, never excluded textbook excerpts")
        check(inventory.completeGames == 4, "Thematic excerpts must not be counted as new complete historical games")
        let route = GuidedCurriculum.chapters.flatMap(\.lessonIDs)
        check(Set(route) == Set(all.filter(\.isSystematic).map(\.id)) && route.count == Set(route).count,
              "Every core course must appear exactly once in the main study route")
        let thematic = Set(BookCoverage.themes.flatMap(\.lessonIDs))
        check(thematic.isSuperset(of: Set(all.filter(\.isSystematic).map(\.id))), "Core courses need an explicit book-topic mapping")
        for theme in BookCoverage.themes {
            check(theme.lessons(in: all).count == theme.lessonIDs.count, "Theme contains an unresolved lesson")
            check(theme.lessons(in: all).flatMap(\.lines).count >= 2, "A theme cannot be covered by a link alone")
        }
        do {
            try BookCoverage.validate(lessons: all.filter { $0.id != "atlas-preparation" })
            preconditionFailure("Missing curriculum was silently counted as covered")
        } catch { checks += 1 }
        check(BookCoverage.textbook.coverage.contains("尚未取得") && BookCoverage.themes.filter { $0.chapter == 5 }.allSatisfy { $0.boundary.contains("原创") || $0.boundary.contains("不伪造") || $0.boundary.contains("原文") },
              "Topic alignment must not imply a full-text adaptation or fabricate the author's views")

        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("xiangqi-book-tests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directory: directory)
        let model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        let mixed = BookCoverage.themes.first { $0.id == "3.4" }!
        model.startTopicCheck(lessonIDs: mixed.lessonIDs)
        check(model.mode == .test && mixed.lessonIDs.contains(model.lessonID ?? ""), "Mixed test must start a real topic lesson in test mode")
        check(model.queue.count <= 4 && model.queue.allSatisfy { mixed.lessonIDs.contains($0.lesson.id) }, "Mixed queue escaped the selected topic")
        let positions = [model.line?.startingFEN].compactMap { $0 } + model.queue.map { $0.line.startingFEN }
        check(Set(positions).count == positions.count, "Same-position branches inflated a mixed test")
        check(store.data.runs.isEmpty && store.data.reviews.isEmpty, "Launching a test must not award progress")
        let lineID = model.lineID
        let queueIDs = model.queue.map(\.id)
        model.startTopicCheck(lessonIDs: ["absent"])
        check(model.lineID == lineID && model.queue.map(\.id) == queueIDs && model.notice != nil,
              "An unavailable topic should not destroy the current session")
        checks += try materialExposureTests(base: directory)
        print("PASS \(checks) book coverage / route / mixed-test checks; \(inventory.courses) core courses, \(inventory.lines) lines, \(inventory.uniqueStarts) unique starts, \(inventory.checkpoints) checkpoints, \(inventory.variations) variations, \(inventory.completeGames) full games")
    }

    /// Uses real start/navigate/resume/attempt paths. A one-move legacy fixture
    /// makes completion deterministic without launching an engine or faking a verdict.
    private static func materialExposureTests(base: URL) throws -> Int {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let fixture = LearningLesson(id: "exposure-fixture", title: "有具体导读的测试课", stage: .foundation, order: 1,
            summary: "阅读应记录辅助", goal: "比较两种兵的推进", principle: "检查真实局面", whenToAdapt: "对手改变时重新计算",
            pitfalls: ["看答案后仍算独立"], sourceIDs: [], lines: [
                StudyLine(id: "a", title: "先推进边兵", intent: "具体导读会给出方向", adaptation: "不拼接", moves: [StudyMove("a3a4", "边兵向前一步")]),
                StudyLine(id: "b", title: "改推另一兵", intent: "另一种具体方向", adaptation: "不拼接", moves: [StudyMove("c3c4", "另一兵向前一步")])])
        func make(_ name: String) throws -> (LearningStore, LearningModel) {
            let store = LearningStore(directory: base.appendingPathComponent(name, isDirectory: true))
            try store.importPack(StudyPack(title: "曝光测试", sources: [], lessons: [fixture]),
                                 builtInIDs: Set(LearningModel.builtInLessons.map(\.id)), builtInSources: LearningModel.builtInSources)
            return (store, LearningModel(store: store, coach: TrainingCoach()))
        }
        func bytes<T: Encodable>(_ value: T) throws -> Data {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
        }
        let first = fixture.lines[0]

        // The new topic entry ultimately uses the same real test startup path.
        let (store, learner) = try make("page-and-restart")
        learner.startLesson(fixture, line: first, mode: .test)
        check(!learner.currentRunUsedHelp && store.data.resume?.wasRetry == false, "a fresh test begins without fabricated assistance")
        let untouched = try bytes(store.data)
        check(!learner.recordMaterialExposure(lessonID: "missing-course"), "invalid material ID fails closed")
        check((try? bytes(store.data)) == untouched, "invalid ID cannot mutate resume, exposure, counters or persisted fields")
        let rootPosition = learner.position, activeRun = store.data.resume!.runID
        learner.navigate(.resources)
        check(learner.currentRunUsedHelp && store.data.resume?.wasRetry == true, "leaving an unfinished test for materials taints both memory and saved resume")
        check(learner.notice?.contains("含辅助") == true, "the learner is told why independent credit changed")
        check(learner.position == rootPosition && learner.mode == .test && learner.hintLevel == 0,
              "material exposure does not move the board, change mode or invent numbered hints")
        check(learner.recordMaterialExposure(lessonID: fixture.id), "opening the course preview records its actual material")
        check(fixture.lines.allSatisfy { line in
            let key = LearningStore.key(fixture.id, line.id)
            return store.data.exposedLines.contains(key) && store.data.lastAssisted[key] != nil
        }, "preview covers all visible lesson lines, not only the selected one")
        check(store.data.runs.isEmpty && store.data.decisions.isEmpty && store.data.progress.isEmpty,
              "reading is neither an attempt nor course completion")
        check(store.data.resume?.hints == 0 && store.data.resume?.errors == 0 && store.data.resume?.runID == activeRun,
              "reading preserves run identity and actual hint/error counts")
        learner.shutdown()
        let restoredStore = LearningStore(directory: store.directory)
        let restored = LearningModel(store: restoredStore, coach: TrainingCoach())
        restored.resumeStudy()
        check(restored.currentRunUsedHelp && restoredStore.data.resume?.runID == activeRun && restored.position == rootPosition,
              "restart cannot clear assistance or lose the saved board")
        restored.attempt(Move(uci: "a3a4")!)
        check(restored.completed && restoredStore.data.runs.count == 1 && !restoredStore.data.runs[0].independent,
              "a real completed attempt after reading does not earn independent credit")
        check(restoredStore.data.runs[0].hints == 0 && restoredStore.progress(fixture.id, first.id).cleanTests == 0,
              "assistance is retained without falsifying hint counts")
        restored.shutdown()

        // Reading while on another page must still contaminate the same practice
        // if the learner switches it into test mode afterward.
        let (practiceStore, practice) = try make("practice-preview")
        practice.startLesson(fixture, line: first, mode: .practice)
        let beforeNil = try bytes(practiceStore.data)
        check(!practice.recordMaterialExposure(), "unrelated original-site reading does not taint an ordinary practice run")
        check((try? bytes(practiceStore.data)) == beforeNil, "nil with no test/review/saved test has no side effects")
        practice.navigate(.courses)
        practice.recordMaterialExposure(lessonID: fixture.id)
        check(practice.currentRunUsedHelp && practiceStore.data.resume?.wasRetry == true,
              "same-course preview taints an unfinished practice even off the board")
        practice.navigate(.study); practice.switchMode(.test)
        check(practice.currentRunUsedHelp && practiceStore.data.resume?.wasRetry == true,
              "switching guided practice to test cannot wash out reading exposure")
        practice.attempt(Move(uci: "a3a4")!)
        check(practiceStore.data.runs.last?.independent == false, "actual mode-switch completion remains assisted")
        practice.shutdown()

        // A cold startup can open the source reader before resuming its saved
        // test. This exercises the persistent path without an in-memory lesson.
        let (coldStore, cold) = try make("cold-saved-test")
        cold.startLesson(fixture, line: first, mode: .test); cold.shutdown()
        let diskStore = LearningStore(directory: coldStore.directory)
        let diskModel = LearningModel(store: diskStore, coach: TrainingCoach())
        check(diskModel.lesson == nil && diskStore.data.resume?.wasRetry == false, "cold model has a clean saved test but no current lesson")
        check(diskModel.recordMaterialExposure(), "source reader marks a pending saved test before it is resumed")
        diskModel.resumeStudy()
        check(diskModel.currentRunUsedHelp && diskStore.data.resume?.wasRetry == true, "cold-source exposure survives actual resume")
        diskModel.shutdown()

        // Reading a different course also supplies information during an active
        // test; it cannot be used as a loophole around the matching-course check.
        let (otherStore, other) = try make("other-course")
        other.startLesson(fixture, line: first, mode: .test)
        other.recordMaterialExposure(lessonID: "atlas-activity")
        check(other.currentRunUsedHelp && otherStore.data.resume?.wasRetry == true,
              "reading another course still marks the current unfinished test")
        check(otherStore.data.runs.isEmpty && otherStore.data.decisions.isEmpty, "cross-course reading never awards progress")
        other.shutdown()

        for destination: LearningPage in [.home, .courses, .review, .progress] {
            let (navigationStore, navigationModel) = try make("nav-" + destination.rawValue)
            navigationModel.startLesson(fixture, line: first, mode: .test)
            navigationModel.navigate(destination)
            check(navigationModel.currentRunUsedHelp && navigationStore.data.resume?.wasRetry == true,
                  "\(destination.rawValue) exposes course labels or records and cannot bypass the test gate")
            navigationModel.shutdown()
        }

        let (completedStore, completedModel) = try make("completed-history")
        completedModel.startLesson(fixture, line: first, mode: .test)
        completedModel.attempt(Move(uci: "a3a4")!)
        check(completedStore.data.runs.last?.independent == true, "unassisted real completion remains available")
        let historicalRuns = try bytes(completedStore.data.runs), historicalProgress = try bytes(completedStore.data.progress)
        completedModel.recordMaterialExposure(lessonID: fixture.id); completedModel.navigate(.home)
        check((try? bytes(completedStore.data.runs)) == historicalRuns && (try? bytes(completedStore.data.progress)) == historicalProgress,
              "reading after completion cannot retroactively revoke or manufacture completed credit")
        completedModel.shutdown()

        let (reviewStore, reviewModel) = try make("review-reading")
        reviewStore.addReview(lessonID: fixture.id, lineID: first.id, title: "错题", fen: Position.initial.fen,
                              attempted: "h2e2", suggested: "b2e2", detail: "比较炮的方向", replyPV: [])
        let review = reviewStore.data.reviews[0]
        reviewModel.startReview(review)
        check(reviewModel.recordMaterialExposure() && reviewModel.currentRunUsedHelp,
              "reading during a wrong-position review marks current assistance")
        check(reviewStore.data.reviews[0].lastAssisted != nil && reviewStore.data.reviews[0].successfulReviews == 0,
              "review reading is persisted without incrementing success")
        reviewModel.shutdown()
        let restoredReviewStore = LearningStore(directory: reviewStore.directory)
        restoredReviewStore.reviewCompleted(review.id, clean: true)
        check(restoredReviewStore.data.reviews[0].successfulReviews == 0,
              "same-day success after reopening a read-assisted wrong position cannot count as independent review")
        return checks
    }
}
#endif
