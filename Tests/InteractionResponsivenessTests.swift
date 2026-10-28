#if INTERACTION_RESPONSIVENESS_TESTS
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct InteractionResponsivenessTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }; checks += 1
    }
    static func ordered(_ lessons: [LearningLesson]) -> [LearningLesson] {
        lessons.sorted {
            let a = LearningStage.allCases.firstIndex(of: $0.stage)!, b = LearningStage.allCases.firstIndex(of: $1.stage)!
            return a == b ? $0.order < $1.order : a < b
        }
    }
    static func main() throws {
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("responsiveness-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LearningReadingCache()
        let source = LearningSource(id: "response-source", title: "测试来源", url: "https://example.com/source", note: "测试")
        let line = StudyLine(id: "response-line", title: "测试线路", intent: "检查", adaptation: "检查",
            moves: [.init("a3a4", "出兵"), .init("a6a5", "应兵"), .init("c3c4", "出兵")])
        let lesson = LearningLesson(id: "response-lesson", title: "测试课", stage: .opening, order: 7,
            summary: "检查", goal: "判断", principle: "观察", whenToAdapt: "变化时", pitfalls: [], sourceIDs: [source.id], lines: [line])
        var builds = 0
        func build() -> LearningReadingCache.Curriculum {
            builds += 1
            return .init(lessons: [lesson], sources: [source], recommended: [lesson])
        }
        for _ in 0..<1_000 {
            let catalog = cache.curriculum(revision: 0, build: build)
            try check(catalog.lessonByID[lesson.id] == lesson && catalog.sources == [source], "Catalog lookup remains source-equivalent")
        }
        try check(builds == 1, "One thousand derived UI reads build the sorted catalog only once")
        _ = cache.curriculum(revision: 1, build: build)
        try check(builds == 2, "A mutation immediately replaces the one cached catalog")
        _ = cache.curriculum(revision: 0, build: build)
        try check(builds == 3, "A differing revision is never accepted, including rollback")
        cache.resetCatalog()
        _ = cache.curriculum(revision: 0, build: build)
        try check(builds == 3, "Replacing the position index does not rebuild unchanged authored content")
        let duplicate = LearningReadingCache.Curriculum(lessons: [lesson, lesson], sources: [], recommended: [])
        try check(duplicate.lessonByID.count == 1 && duplicate.lessonByID[lesson.id] == lesson,
                  "Lookup preserves the previous first-match semantics for duplicate IDs")

        let positions = try line.positions()
        for cursor in positions.indices {
            for _ in 0..<5 {
                try check(cache.resumePosition(line: line, cursor: cursor, acceptedMove: nil) == positions[cursor],
                          "Cached home board exactly matches the actual saved ply")
            }
        }
        let alternative = try Position.initial.applying(move: Move(uci: "c3c4")!)
        try check(cache.resumePosition(line: line, cursor: 0, acceptedMove: "c3c4") == alternative,
                  "An accepted off-reference choice appears on the resume thumbnail")
        try check(cache.resumePosition(line: line, cursor: 0, acceptedMove: "a3a4") == positions[1],
                  "A different accepted choice invalidates the prior thumbnail")
        try check(cache.resumePosition(line: line, cursor: 0, acceptedMove: "not-a-move") == positions[0],
                  "Invalid move metadata cannot invent a moved piece")
        try check(cache.resumePosition(line: line, cursor: -1, acceptedMove: nil) == nil,
                  "Negative saved cursor cannot produce a thumbnail")
        try check(cache.resumePosition(line: line, cursor: positions.count, acceptedMove: nil) == nil,
                  "Out-of-range cursor cannot produce a thumbnail")
        let broken = StudyLine(id: line.id, title: line.title, intent: line.intent, adaptation: line.adaptation,
                              moves: [.init("a0a9", "非法路线")])
        try check(cache.resumePosition(line: broken, cursor: 0, acceptedMove: nil) == nil,
                  "Content replacement with the same ID cannot reuse a stale valid thumbnail")
        try check(cache.resumePosition(line: line, cursor: 0, acceptedMove: nil) == positions[0],
                  "A previously invalid line cannot poison restored valid content")

        let store = LearningStore(directory: directory), model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        let before = try store.exportData()
        let builtInIDs = Set(LearningModel.builtInLessons.map(\.id))
        let expected = ordered(LearningModel.builtInLessons)
        for _ in 0..<50 {
            try check(model.lessons == expected, "Shared catalog preserves exact stage and lesson ordering")
            _ = model.sources; _ = model.recommendedLessons
        }
        try check(try store.exportData() == before, "UI catalog reads never change marks, help, or progress")
        let pack = StudyPack(title: "响应测试", sources: [source], lessons: [lesson])
        try store.importPack(pack, builtInIDs: builtInIDs, builtInSources: LearningModel.builtInSources)
        try check(model.lessons == ordered(LearningModel.builtInLessons + [lesson]), "An imported course is immediately visible without relaunch")
        try check(model.sources.contains(source), "An imported source immediately appears in the shared projection")
        model.lessonID = lesson.id; model.lineID = line.id
        try check(model.lesson == lesson && model.line == line, "Fast active-lesson lookup selects the imported line")
        let importedBytes = try store.exportData()
        _ = model.lessons; _ = model.sources; _ = model.recommendedLessons
        try check(try store.exportData() == importedBytes, "Reading the rebuilt catalog remains non-mutating")

        // A scoped microbenchmark of the exact removed sort path, not a claim
        // about frame rate or end-to-end mouse latency. The checksum consumes
        // results so optimized builds cannot eliminate either loop.
        var beforeTimes: [Double] = [], afterTimes: [Double] = [], checksum = 0
        for _ in 0..<5 {
            var start = Date()
            for _ in 0..<200 {
                let result = ordered(LearningModel.builtInLessons + store.data.importedLessons)
                checksum += result.first?.id.count ?? 0
            }
            beforeTimes.append(Date().timeIntervalSince(start))
            start = Date()
            for _ in 0..<200 { checksum += model.lessons.first?.id.count ?? 0 }
            afterTimes.append(Date().timeIntervalSince(start))
        }
        try check(checksum > 0, "Measured catalog results were consumed")
        print(String(format: "Catalog read microbenchmark (200 reads, median of 5): previous sort %.3f ms, shared projection %.3f ms; not an end-to-end latency measurement",
                     beforeTimes.sorted()[2] * 1_000, afterTimes.sorted()[2] * 1_000))
        print("PASS \(checks) interaction responsiveness checks: shared catalog reuse, invalidation, ordering and truthful single-resume projection")
    }
}
#endif
