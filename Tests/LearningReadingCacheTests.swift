#if LEARNING_READING_CACHE_TESTS
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct LearningReadingCacheTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }; checks += 1
    }
    static func main() throws {
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("reading-cache-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directory: directory), model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        let openingPath = "opening-repertoire.json", endingPath = "endgames_all.json"
        func entry(_ fen: String, _ title: String, _ path: String, index: Int) -> LibraryCourseEntry {
            .init(id: LibraryCourseEntry.identifier(fen: fen), fen: fen, title: title,
                  memberships: [.init(groupID: path, title: title, sourceIndex: index, category: path, section: .section(for: path))])
        }
        let first = entry(Position.initial.fen, "順相局", openingPath, index: 1)
        let second = entry(try Position.initial.applying(move: Move(uci: "a3a4")!).fen, "順炮直車", openingPath, index: 2)
        let ending = entry("4k4/9/9/9/4P4/9/9/9/9/4K4 w - - 0 1", "单兵残局", endingPath, index: 1)
        func catalog(_ entries: [LibraryCourseEntry]) -> LibraryCourseCatalog {
            let groups = [openingPath, endingPath].map { path in
                let ids = entries.filter { $0.memberships.contains { $0.groupID == path } }.map(\.id)
                return LibraryCourseGroup(id: path, title: path, section: .section(for: path), entryIDs: ids, rawCount: ids.count, invalidCount: 0)
            }
            return .init(pwaCommit: String(repeating: "a", count: 40), entries: entries, groups: groups)
        }
        model.libraryCatalog = catalog([first, second, ending]); model.librarySection = nil
        let emptyArchive = try store.exportData()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let cache = LearningReadingCache()
        let key = LearningReadingCache.Query(groupID: nil, section: nil, text: "", family: nil, routeID: nil, status: 0, progressRevision: nil)
        var builds = 0
        func build() -> LearningReadingCache.FilteredResult {
            builds += 1; return .init(entries: [first], validUntil: t0.addingTimeInterval(60))
        }
        for tick in 0..<50 { _ = cache.filteredEntries(query: key, now: t0.addingTimeInterval(Double(tick)), build: build) }
        try check(builds == 1, "Fifty unchanged reads reuse one projection")
        _ = cache.filteredEntries(query: key, now: t0.addingTimeInterval(60), build: build)
        try check(builds == 2, "Exact due boundary invalidates before returning results")
        _ = cache.filteredEntries(query: key, now: t0.addingTimeInterval(-1), build: build)
        try check(builds == 3, "Clock rollback cannot reuse a projection from the future")
        cache.resetCatalog(); _ = cache.filteredEntries(query: key, now: t0, build: build)
        try check(builds == 4, "Same-commit catalog replacement clears cached rows")

        let changedKeys: [LearningReadingCache.Query] = [
            .init(groupID: openingPath, section: nil, text: "", family: nil, routeID: nil, status: 0, progressRevision: nil),
            .init(groupID: nil, section: .opening, text: "", family: nil, routeID: nil, status: 0, progressRevision: nil),
            .init(groupID: nil, section: nil, text: "顺", family: nil, routeID: nil, status: 0, progressRevision: nil),
            .init(groupID: nil, section: nil, text: "", family: "顺炮", routeID: nil, status: 0, progressRevision: nil),
            .init(groupID: nil, section: nil, text: "", family: nil, routeID: "route", status: 0, progressRevision: nil),
            .init(groupID: nil, section: nil, text: "", family: nil, routeID: nil, status: 1, progressRevision: 0),
            .init(groupID: nil, section: nil, text: "", family: nil, routeID: nil, status: 1, progressRevision: 1)
        ]
        for changed in changedKeys {
            let before = builds
            _ = cache.filteredEntries(query: changed, now: t0, build: build)
            try check(builds == before + 1, "Every result-affecting input invalidates")
        }
        var navigationBuilds = 0
        for _ in 0..<30 {
            _ = cache.catalogNavigation { navigationBuilds += 1; return .init(sectionCounts: [:], openingFamilies: []) }
        }
        try check(navigationBuilds == 1, "Navigation counts are computed once per snapshot")
        cache.resetCatalog()
        _ = cache.catalogNavigation { navigationBuilds += 1; return .init(sectionCounts: [:], openingFamilies: []) }
        try check(navigationBuilds == 2, "Navigation invalidates on snapshot replacement")

        try check(model.libraryFilteredEntries(now: t0).map(\.id) == [first.id, second.id, ending.id], "Source order is preserved")
        try check(model.librarySectionCount(.opening) == 2 && model.librarySectionCount(.endgames) == 1 && model.librarySectionCount(.checkmates) == 0,
                  "Source section counts stay exact, including empty sections")
        try check(model.libraryOpeningFamilies == ["顺相／列相／飞相", "顺炮"].sorted(), "Families match canonical original-title grouping")
        for section in LibraryCourseSection.allCases {
            model.librarySection = section
            try check(model.libraryFilteredEntries(now: t0) == model.libraryCatalog.entries(section: section), "Cached section equals source query")
        }
        model.librarySection = nil; model.libraryGroupID = openingPath
        try check(model.libraryFilteredEntries(now: t0).map(\.id) == [first.id, second.id], "Group order and membership survive caching")
        model.librarySection = .endgames
        try check(model.libraryFilteredEntries(now: t0).isEmpty, "Conflicting source filters remain empty")
        model.librarySection = nil; model.libraryGroupID = nil; model.libraryFamily = "顺炮"
        try check(model.libraryFilteredEntries(now: t0).map(\.id) == [second.id], "Family selection invalidates correctly")
        model.libraryFamily = nil; model.libraryQuery = "順炮"
        try check(model.libraryFilteredEntries(now: t0).map(\.id) == [second.id], "Source alias search is preserved")
        model.libraryQuery = "no-such-position"
        try check(model.libraryFilteredEntries(now: t0).isEmpty, "Negative search does not reuse prior matches")
        model.libraryQuery = ""
        let route = model.roadmapRoutes.first { $0.phase == .opening }!
        model.libraryRouteFilterID = route.id
        try check(model.libraryFilteredEntries(now: t0).count == 2, "Route pool restricts current browser")
        model.libraryRouteFilterID = nil
        let coverage = model.routeCoverage(route)
        let targets = model.routeTargets(route)
        for _ in 0..<30 { _ = model.routeCoverage(route); _ = model.libraryGroupProgress(groupID: openingPath); _ = model.libraryFilteredEntries(now: t0) }
        try check(coverage.positionCount == 2 && coverage.practicedPositions == 0 && !targets.isEmpty, "Coverage counts inventory, not completion")
        try check(try store.exportData() == emptyArchive, "Caching is read-only and never adds learning records or scores")
        let revision = store.readingRevision
        store.finishRun(id: UUID(), lessonID: first.lessonID, lineID: LibraryGeneratedStudy.lineID,
                        mode: .test, hints: 0, errors: 0, wasRetry: false, wasUnseen: true, now: t0)
        try check(store.readingRevision > revision, "Nested progress mutation advances the reading revision")
        let updated = model.routeCoverage(route)
        try check(updated.positionCount == 2 && updated.practicedPositions == 1 && updated.independentPositions == 1 && updated.delayedPositions == 0,
                  "New genuine result immediately invalidates route coverage")
        let group = model.libraryGroupProgress(groupID: openingPath)
        try check(group.practiced == 1 && group.independent == 1, "Group progress shares the original score model")
        model.libraryStatusFilter = 1
        try check(model.libraryFilteredEntries(now: t0).map(\.id) == [second.id, ending.id], "Unpracticed filter updates without relaunch")
        model.libraryStatusFilter = 3
        try check(model.libraryFilteredEntries(now: t0).map(\.id) == [first.id], "Independent filter uses cleanTests")
        model.libraryStatusFilter = 2
        let due = store.libraryProgress(entryID: first.id).nextReview!
        try check(model.libraryFilteredEntries(now: due.addingTimeInterval(-1)).isEmpty, "Future review is not yet due")
        try check(model.libraryFilteredEntries(now: due).map(\.id) == [first.id], "Due filter updates at the exact boundary without an archive write")
        try check(model.libraryFilteredEntries(now: due.addingTimeInterval(-1)).isEmpty, "Backward clock change removes no-longer-due item")
        let beforeReading = try store.exportData()
        _ = model.libraryFilteredEntries(now: due); _ = model.routeCoverage(route)
        try check(try store.exportData() == beforeReading, "Time-based read invalidation remains non-mutating")

        store.finishRun(id: UUID(), lessonID: targets[0].lesson.id, lineID: targets[0].line.id,
                        mode: .practice, hints: 1, errors: 0, wasRetry: true, wasUnseen: false, now: t0)
        try check(model.routeCoverage(route).coreCompleted == 1 && model.routeCoverage(route).independentPositions == 1,
                  "Authored core progress invalidates while canonical-position scores remain separate")
        let storeBytes = try store.exportData()
        model.libraryStatusFilter = 0; model.libraryCatalog = catalog([ending])
        try check(model.libraryFilteredEntries(now: t0).map(\.id) == [ending.id], "A same-commit replacement never reuses removed rows")
        try check(model.librarySectionCount(.opening) == 0 && model.libraryOpeningFamilies.isEmpty, "Same-commit replacement invalidates counts and families")
        try check(model.routeCoverage(route).positionCount == 0 && model.routeCoverage(route).coreCompleted == 1,
                  "Snapshot replacement invalidates inventory without erasing actual authored progress")
        try check(model.libraryGroupProgress(groupID: openingPath).practiced == 0, "Removed source group drops only its visible projection")
        try check(try store.exportData() == storeBytes, "Catalog replacement and projection rebuild do not rewrite saved grades")
        model.libraryCatalog = .empty
        try check(model.libraryFilteredEntries(now: t0).isEmpty && model.librarySectionCount(.opening) == 0, "Empty catalog remains safe")
        print("PASS \(checks) learning reading-cache checks")
    }
}
#endif
