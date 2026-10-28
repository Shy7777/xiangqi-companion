#if ROUTE_DIRECTORY_TESTS
import Foundation

struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct RouteDirectoryTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static let routeID = "route-opening-activity"
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }; checks += 1
    }
    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func model(directory: URL) -> LearningModel {
        LearningModel(store: LearningStore(directory: directory),
            coach: TrainingCoach(binaryURL: directory.appendingPathComponent("missing-engine"),
                                 networkURL: directory.appendingPathComponent("missing-network")))
    }
    static func route(_ learner: LearningModel) throws -> LearningRoute {
        guard let route = learner.roadmapRoutes.first(where: { $0.id == routeID }) else {
            throw Failure(message: "The actual opening activity route is missing")
        }
        return route
    }
    static func open(_ target: StudyTarget, in learner: LearningModel, mode: StudyMode = .practice, resume: Bool = true) {
        learner.openRouteStudyTarget(routeID: routeID, lessonID: target.lesson.id, lineID: target.line.id,
                                    mode: mode, resumeExisting: resume)
    }
    static func isCurrent(_ target: StudyTarget, _ learner: LearningModel) -> Bool {
        learner.lessonID == target.lesson.id && learner.lineID == target.line.id
    }

    /// These tests exercise directory navigation, not search accuracy. Restore
    /// an already assessed, legally accepted last checkpoint, then use the real
    /// completion transition. No engine verdict or clean score is fabricated.
    static func completeAcceptedFixture(_ learner: LearningModel) throws {
        guard let lesson = learner.lesson, let line = learner.line, let points = line.checkpoints,
              let last = points.last, line.moves.indices.contains(last.ply) else {
            throw Failure(message: "Directory fixture must contain declared decision checkpoints")
        }
        var saved = StudyResume(lessonID: lesson.id, lineID: line.id, mode: .practice, cursor: last.ply,
            hints: learner.currentRunStatistics.hints, errors: learner.currentRunStatistics.errors, wasRetry: true,
            runID: learner.currentRunIdentity, started: Date(), wasUnseen: false,
            completedCheckpoints: points.map(\.ply), acceptedCheckpoint: last.ply,
            checkpointMove: line.moves[last.ply].uci, contentFingerprint: line.contentFingerprint)
        saved.routeID = routeID
        learner.startLesson(lesson, line: line, mode: .practice, from: last.ply, restoring: saved)
        try check(learner.referenceContinuationNeeded && learner.currentStudyRoute?.id == routeID,
                  "Valid assessed checkpoint restore retains standalone route context")
        learner.continueStudy()
        try check(learner.completed && learner.store.data.runs.contains(where: { $0.id == saved.runID && !$0.independent }),
                  "The actual completion transition records exactly this assisted fixture run")
    }

    static func directoryAndOrder(base: URL) throws {
        let learner = model(directory: base.appendingPathComponent("directory-order"))
        defer { learner.shutdown() }
        let section = try route(learner), targets = learner.routeTargets(section)
        let expected = ["systematic-opening-transition/systematic-1981-full",
                        "repertoire-screen-high-rook/repertoire-screen-high-rook-1",
                        "repertoire-screen-high-rook/repertoire-screen-high-rook-2"]
        try check(targets.map(\.id) == expected && Set(targets.map { $0.lesson.id }).count == 2,
                  "The real activity route lists all three ordered examples across both lessons")
        try check(learner.routeCoverage(section).coreCount == 3 && learner.routeCoverage(section).coreCompleted == 0,
                  "Directory row count and route completion denominator use the same targets")
        learner.openRouteExamples(routeID: routeID)
        try check(learner.page == .courses && learner.courseDisplay == .roadmap && learner.selectedLearningRoute.id == routeID,
                  "Opening examples stays in the route directory instead of the unrelated free catalog")
        try check(learner.store.data.runs.isEmpty && learner.store.data.decisions.isEmpty,
                  "Browsing the directory is not completing or answering a lesson")

        open(targets[0], in: learner, resume: false)
        let firstRun = learner.currentRunIdentity, firstPosition = learner.position, firstPly = learner.cursor
        try check(learner.page == .study && isCurrent(targets[0], learner) && learner.currentStudyRoute?.id == routeID && !learner.isJourneyStudy,
                  "Selecting a directory row opens exactly that standalone line")
        try check(learner.nextRouteStudyTarget?.id == targets[1].id && targets[0].lesson.id != targets[1].lesson.id,
                  "Next example crosses the parent lesson boundary in route order")
        try check(learner.store.data.resume?.routeID == routeID && learner.store.data.resume?.runID == firstRun,
                  "Standalone route identity is persisted with the existing study resume")
        learner.openCurrentStudyCatalog()
        try check(learner.page == .courses && learner.courseDisplay == .roadmap && learner.selectedLearningRoute.id == routeID &&
                  learner.currentRunIdentity == firstRun && learner.position == firstPosition && learner.cursor == firstPly,
                  "Returning to this directory preserves the active run and exact board")
        try check(learner.routeStudyTargetIsResumable(targets[0]) && !learner.routeStudyTargetIsResumable(targets[1]),
                  "Only the unfinished matching directory row advertises resume")
        open(targets[0], in: learner)
        try check(learner.currentRunIdentity == firstRun && learner.cursor == firstPly && learner.position == firstPosition,
                  "Selecting the resumable row does not silently restart it")

        for index in targets.indices {
            try check(isCurrent(targets[index], learner), "Route traversal selected a different example than its visible order")
            try completeAcceptedFixture(learner)
            try check(learner.routeCoverage(section).coreCompleted == index + 1 && learner.routeCoverage(section).coreCount == 3,
                      "Each genuinely completed line updates exactly one row and the shared header count")
            let completedRunCount = learner.store.data.runs.count
            if index + 1 < targets.count {
                try check(learner.nextRouteStudyTarget?.id == targets[index + 1].id && learner.studyCompletionNextTitle.contains("下一篇"),
                          "Completion offers the next visible route example, not another random session")
                learner.continueAfterStudy()
                try check(isCurrent(targets[index + 1], learner) && learner.currentStudyRoute?.id == routeID &&
                          !learner.isJourneyStudy && !learner.completed && learner.store.data.runs.count == completedRunCount,
                          "Continuing starts only the next example and never pre-completes it")
            } else {
                try check(learner.nextRouteStudyTarget == nil && learner.studyCompletionNextTitle.contains("目录"),
                          "The final example offers the directory rather than looping back to the first")
                learner.continueAfterStudy()
                try check(learner.page == .courses && learner.courseDisplay == .roadmap && learner.selectedLearningRoute.id == routeID &&
                          learner.store.data.runs.count == completedRunCount,
                          "Final continuation returns to the original directory without an extra run")
            }
        }

        let previousRuns = try encoded(learner.store.data.runs), previousProgress = try encoded(learner.store.data.progress)
        open(targets[0], in: learner, mode: .demonstration, resume: false)
        try check(isCurrent(targets[0], learner) && learner.mode == .demonstration && !learner.completed &&
                  !learner.routeStudyTargetIsResumable(targets[2]),
                  "A previously completed example remains directly accessible for rereading")
        try check(try encoded(learner.store.data.runs) == previousRuns && encoded(learner.store.data.progress) == previousProgress,
                  "Opening an already completed row does not erase or add historical scores")
        learner.goToDemoPly(1)
        try check(try encoded(learner.store.data.runs) == previousRuns && learner.routeCoverage(section).coreCompleted == 3,
                  "Looking at one step does not masquerade as a new completion")
        learner.goToDemoPly(targets[0].line.moves.count)
        try check(learner.store.data.runs.count == 4 && learner.store.progress(targets[0].lesson.id, targets[0].line.id).demonstrations == 1 &&
                  learner.store.progress(targets[0].lesson.id, targets[0].line.id).completions == 1 && learner.routeCoverage(section).coreCompleted == 3,
                  "Completing a reread records only a demonstration, never another practiced line or clean test")
        try check(try encoded(Array(learner.store.data.runs.prefix(3))) == previousRuns,
                  "Rereading cannot mutate any of the three finalized run records")
    }

    static func detachedFromOtherQueues(base: URL) throws {
        let learner = model(directory: base.appendingPathComponent("queue-isolation"))
        defer { learner.shutdown() }
        let targets = learner.routeTargets(try route(learner))
        let items = targets.prefix(2).map { LearningPracticeItem(kind: .lesson, targetID: $0.lesson.id, lineID: $0.line.id,
            title: "旧训练中的谱例", reason: "保留但不自动接入新目录练习", mode: .practice) }
        let plan = LearningPracticePlan(id: UUID(), created: Date(), routeID: routeID, title: "旧训练组", reason: "隔离导航范围", items: items)
        try learner.store.setLearningJourney(.init(selectedRouteID: routeID, plan: plan))
        learner.resumeJourneySession()
        let oldRun = learner.currentRunIdentity, originalPlan = learner.journeyPlan!
        try check(learner.isJourneyStudy && isCurrent(targets[0], learner), "Fixture must begin bound to the same target in an older training group")
        learner.queue = [targets[2]]; learner.libraryPlanIDs = ["old-library-item"]
        open(targets[0], in: learner)
        try check(learner.currentRunIdentity == oldRun && learner.isJourneyStudy && learner.journeyPlan?.id == originalPlan.id &&
                  learner.journeyPlan?.cursor == originalPlan.cursor && learner.journeyPlan?.completedIndices == originalPlan.completedIndices,
                  "Continue on the same unfinished row preserves its actual run and legitimate old journey membership")
        open(targets[0], in: learner, resume: false)
        try check(!learner.isJourneyStudy && learner.currentStudyRoute?.id == routeID && learner.currentRunIdentity != oldRun,
                  "Explicit restart from the directory creates a standalone run rather than rebinding the same old journey item")
        try check(learner.remainingPlanCount == 0 && learner.queue.isEmpty && learner.queuedReviews.isEmpty && learner.libraryPlanIDs.isEmpty,
                  "Standalone directory start clears stale legacy next-item queues")
        try check(learner.journeyPlan?.id == originalPlan.id && learner.journeyPlan?.cursor == originalPlan.cursor &&
                  learner.journeyPlan?.completedIndices == originalPlan.completedIndices && learner.journeyPlan?.skippedIndices == originalPlan.skippedIndices,
                  "Starting from the directory leaves the old plan's completed/skipped positions unchanged")
        try completeAcceptedFixture(learner)
        try check(learner.journeyPlan?.completedIndices == originalPlan.completedIndices && learner.journeyPlan?.cursor == originalPlan.cursor,
                  "Completing a standalone example cannot consume the same-named item in the old journey")
        learner.queue = [targets[2]]
        learner.continueAfterStudy()
        try check(isCurrent(targets[1], learner) && learner.currentStudyRoute?.id == routeID && !learner.isJourneyStudy,
                  "Route-next takes priority over an unrelated legacy queue even if one is present")
    }

    static func resumeAndExposure(base: URL) throws {
        let directory = base.appendingPathComponent("restart-context")
        let learner = model(directory: directory)
        let targets = learner.routeTargets(try route(learner))
        open(targets[0], in: learner, mode: .test, resume: false)
        let run = learner.currentRunIdentity, before = learner.position, ply = learner.cursor
        try check(!learner.currentRunUsedHelp && learner.store.data.resume?.routeID == routeID,
                  "Direct first-time no-hint selection begins with its own clean route context")
        learner.openCurrentStudyCatalog()
        try check(learner.currentRunUsedHelp && learner.store.data.resume?.wasRetry == true && learner.store.data.resume?.runID == run &&
                  learner.currentRunStatistics.hints == 0 && learner.currentRunStatistics.errors == 0 && learner.store.data.decisions.isEmpty,
                  "Reading the directory during a test preserves normal assistance rules without inventing answers or hints")
        let otherRoute = learner.roadmapRoutes.first { $0.id != routeID }!
        learner.selectLearningRoute(id: otherRoute.id)
        try check(learner.selectedLearningRoute.id == otherRoute.id && learner.currentStudyRoute?.id == routeID,
                  "Browsing another topic cannot overwrite the active study's originating route")
        learner.openCurrentStudyCatalog()
        try check(learner.selectedLearningRoute.id == routeID && learner.currentRunIdentity == run && learner.position == before,
                  "Return-to-directory restores the study's route rather than the most recently browsed topic")
        learner.shutdown()

        let reopened = model(directory: directory)
        defer { reopened.shutdown() }
        reopened.resumeStudy()
        try check(reopened.currentStudyRoute?.id == routeID && reopened.currentRunIdentity == run && reopened.cursor == ply &&
                  reopened.position == before && reopened.currentRunUsedHelp && !reopened.isJourneyStudy,
                  "Application restart restores route, board, run identity and assistance together")
        try check(reopened.routeStudyTargetIsResumable(targets[0]) && !reopened.routeStudyTargetIsResumable(targets[1]),
                  "Resume affordance survives application restart and stays line-specific")
        open(targets[0], in: reopened, mode: .demonstration)
        try check(reopened.currentRunIdentity == run && reopened.cursor == ply && reopened.currentRunUsedHelp && reopened.mode == .test,
                  "Directory continue restores the actual previous mode and attempt without laundering its assistance")
        open(targets[0], in: reopened, mode: .practice, resume: false)
        try check(reopened.currentRunIdentity != run && reopened.currentStudyRoute?.id == routeID && reopened.currentRunUsedHelp,
                  "Explicit restart creates a new route run while retaining recent help exposure")
    }

    static func sharedLessonJourneyContext(base: URL) throws {
        let learner = model(directory: base.appendingPathComponent("shared-lesson-context"))
        defer { learner.shutdown() }
        let firstRoute = learner.roadmapRoutes.first { $0.id == "route-opening-transition" }!
        let nextRoute = learner.roadmapRoutes.first { $0.id == "route-practice-review" }!
        let shared = learner.routeTargets(firstRoute).first { target in
            learner.routeTargets(nextRoute).contains { $0.id == target.id }
        }!
        learner.openRouteStudyTarget(routeID: firstRoute.id, lessonID: shared.lesson.id, lineID: shared.line.id,
                                    mode: .practice, resumeExisting: false)
        let priorRun = learner.currentRunIdentity
        try check(learner.currentStudyRoute?.id == firstRoute.id && !learner.isJourneyStudy,
                  "Shared-course fixture first belongs to the explicitly chosen standalone route")
        let item = LearningPracticeItem(kind: .lesson, targetID: shared.lesson.id, lineID: shared.line.id,
            title: "新主题里的同一谱例", reason: "按当前训练组的主题理解任务", mode: .practice)
        let plan = LearningPracticePlan(id: UUID(), created: Date(), routeID: nextRoute.id,
            title: "另一个主题的新训练组", reason: "共享谱例不沿用旧面包屑", items: [item])
        try learner.store.setLearningJourney(.init(selectedRouteID: nextRoute.id, plan: plan))
        learner.resumeJourneySession()
        try check(learner.isJourneyStudy && learner.currentRunIdentity != priorRun && isCurrent(shared, learner) &&
                  learner.currentStudyRoute?.id == nextRoute.id && learner.store.data.resume?.routeID == nextRoute.id,
                  "An explicit new journey route overrides the old same-lesson standalone breadcrumb")
        try check(learner.journeyPlan?.id == plan.id && learner.journeyPlan?.activeRunID == learner.currentRunIdentity &&
                  learner.journeyPlan?.completedIndices.isEmpty == true && learner.store.data.runs.isEmpty,
                  "Changing route context does not complete the shared example or the new plan")
        learner.openCurrentStudyCatalog()
        try check(learner.selectedLearningRoute.id == nextRoute.id && learner.page == .courses && learner.courseDisplay == .roadmap,
                  "The shared example returns to its newly assigned journey route, not the stale previous route")
    }

    static func invalidTargetsAndLegacy(base: URL) throws {
        let learner = model(directory: base.appendingPathComponent("invalid-targets"))
        defer { learner.shutdown() }
        let targets = learner.routeTargets(try route(learner))
        open(targets[0], in: learner, resume: false)
        let before = learner.position, run = learner.currentRunIdentity, page = learner.page, originalCursor = learner.cursor
        let snapshot = try learner.store.exportData()
        let other = learner.routeTargets(learner.roadmapRoutes.first { $0.id == "route-opening-tempo" }!).first!
        let invalid = [("missing-route", targets[0].lesson.id, targets[0].line.id),
                       (routeID, "missing-lesson", targets[0].line.id),
                       (routeID, targets[0].lesson.id, "missing-line"),
                       (routeID, other.lesson.id, other.line.id),
                       (routeID, targets[0].lesson.id, targets[1].line.id)]
        for (route, lesson, line) in invalid {
            learner.openRouteStudyTarget(routeID: route, lessonID: lesson, lineID: line, mode: .test)
            try check(learner.currentRunIdentity == run && learner.page == page && learner.position == before && learner.cursor == originalCursor &&
                      learner.currentStudyRoute?.id == routeID && isCurrent(targets[0], learner),
                      "Unknown, mismatched or out-of-route targets cannot partially change the active study")
            try check(try learner.store.exportData() == snapshot, "Rejecting an invalid route target must not mutate saved learning data")
        }
        learner.openRouteExamples(routeID: "missing-route")
        try check(learner.page == page && learner.currentRunIdentity == run && learner.position == before,
                  "Unknown directory route does not navigate away or cancel the current study")

        var saved = learner.store.data.resume!
        saved.routeID = nil
        let legacyData = try encoded(saved)
        var object = try JSONSerialization.jsonObject(with: legacyData) as! [String: Any]
        object.removeValue(forKey: "routeID")
        let legacy = try JSONDecoder().decode(StudyResume.self, from: JSONSerialization.data(withJSONObject: object))
        try check(legacy.routeID == nil && legacy.runID == saved.runID && legacy.lessonID == saved.lessonID && legacy.cursor == saved.cursor,
                  "Old resumes without routeID remain decodable with unchanged study identity")
        let oldVersion = model(directory: base.appendingPathComponent("legacy-context"))
        defer { oldVersion.shutdown() }
        oldVersion.selectLearningRoute(id: routeID)
        oldVersion.startLesson(targets[0].lesson, line: targets[0].line, mode: legacy.mode, from: legacy.cursor, restoring: legacy)
        try check(oldVersion.currentStudyRoute == nil && oldVersion.currentRunIdentity == legacy.runID,
                  "A legacy standalone resume does not invent an originating route from the current sidebar selection")
    }

    static func main() throws {
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("route-directory-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try directoryAndOrder(base: directory)
        try detachedFromOtherQueues(base: directory)
        try resumeAndExposure(base: directory)
        try sharedLessonJourneyContext(base: directory)
        try invalidTargetsAndLegacy(base: directory)
        print("PASS \(checks) route directory checks: complete ordered examples, explicit target selection, cross-lesson next, resumable context and isolated learning records")
    }
}
#endif
