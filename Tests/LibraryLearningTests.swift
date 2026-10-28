#if LIBRARY_LEARNING_TESTS
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct LibraryLearningTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static let commit = "3ff21f4502a03f30bb0df55db6f3814ceeb989f5"
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure(message: message) }; checks += 1
    }
    static func rejects(_ action: () throws -> Void) throws {
        do { try action() } catch { checks += 1; return }
        throw Failure(message: "Expected rejection")
    }
    static func entry(_ position: Position, index: Int, group: String = "opening-repertoire.json") -> LibraryCourseEntry {
        let membership = LibraryCourseMembership(groupID: group, title: "测试局面 \(index)", sourceIndex: index,
            category: PWADataParser.category(for: group), section: .section(for: group))
        return LibraryCourseEntry(id: LibraryCourseEntry.identifier(fen: position.fen), fen: position.fen,
            title: membership.title, memberships: [membership])
    }
    static func rows(_ position: Position, _ budget: Int) async throws -> [EngineLine] {
        let move = position.legalMoves().sorted { $0.uci < $1.uci }.first!
        return [EngineLine(rank: 1, depth: 12, score: .cp(20), pv: [move.uci], timeMS: budget, nodes: nil, wdl: nil)]
    }
    static func wait(_ model: LearningModel) async throws {
        for _ in 0..<200 {
            if !model.libraryPreparing { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw Failure(message: "Preparation did not finish")
    }
    static func catalog(_ entries: [LibraryCourseEntry]) -> LibraryCourseCatalog {
        let ids = entries.map(\.id)
        return LibraryCourseCatalog(pwaCommit: commit, entries: entries,
            groups: [LibraryCourseGroup(id: "opening-repertoire.json", title: "开局定式", section: .opening,
                entryIDs: ids, rawCount: entries.count, invalidCount: 0)])
    }
    static func main() async throws {
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("xiangqi-library-learning-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directory: directory)
        let model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        let a = entry(.initial, index: 1)
        let b = entry(try Position.initial.applying(move: Move(uci: "a3a4")!), index: 2)
        let c = entry(try Position.initial.applying(move: Move(uci: "c3c4")!), index: 3)
        model.libraryCatalog = catalog([a, b, c])
        try check(model.lessons.count == LearningModel.builtInLessons.count, "The catalog is not 10,000 imported courses")
        try check(store.data.libraryStudy == nil && store.data.progress.isEmpty, "Browsing/indexing creates no progress or cache")
        model.startLibraryEntry(a, evaluate: rows)
        try await wait(model)
        try check(model.isLibraryStudy && model.lessonID == a.lessonID && model.page == .study, "Generated lesson resolves through the existing study board")
        try check(model.isCheckpointStudy && model.currentCheckpoint?.ply == 0, "Reference match must take the assessment path")
        try check(model.position == .initial && model.studyPhase == .studentTurn, "Learner must actually submit a move")
        try check(store.data.runs.isEmpty && model.libraryProgress(entryID: a.id).completions == 0, "Generation is not completion")
        try check(store.data.importedLessons.isEmpty && model.lessons.count == LearningModel.builtInLessons.count + 1, "Only the active generated lesson is resolved, never imported")
        try check(!model.recommendedLessons.contains(where: { $0.id == a.lessonID }), "Generated items do not inflate authored book coverage")
        try check(model.referenceLineName == "引擎参考线", "A generated line is never labeled a historical original")
        let active = store.data.libraryStudy!
        let resume = store.data.resume!
        let disk = try Data(contentsOf: directory.appendingPathComponent("learning.json"))
        try check(disk.count < 30_000, "One selected lesson stays small")
        let reopenedStore = LearningStore(directory: directory)
        let reopened = LearningModel(store: reopenedStore, coach: TrainingCoach())
        reopened.libraryCatalog = model.libraryCatalog; reopened.resumeStudy()
        try check(reopened.line?.contentFingerprint == active.lesson.lines[0].contentFingerprint && reopened.position == model.position,
                  "Restart restores the exact line without regenerating a different engine PV")
        try check(reopenedStore.data.resume?.runID == resume.runID, "Resume preserves run identity")
        reopened.shutdown()
        // An external answer viewed before the first test is also assisted.
        store.markLibraryExposed(entryID: c.id)
        model.startLibraryEntry(c, mode: .test, evaluate: rows); try await wait(model)
        try check(model.currentRunUsedHelp && store.data.resume?.wasRetry == true, "Prior source answer exposure follows canonical FEN")
        model.startLibraryEntry(a, mode: .practice, evaluate: rows); try await wait(model)
        model.retryStudy()
        try check(store.libraryWasRecentlyAssisted(entryID: a.id), "Retry persists position-level assistance")
        model.startLibraryEntry(b, mode: .practice, evaluate: rows); try await wait(model)
        model.startLibraryEntry(a, mode: .test, evaluate: rows); try await wait(model)
        try check(model.currentRunUsedHelp, "A retry -> B -> A does not reset assistance")
        try check(store.data.libraryStudy?.entryID == a.id && store.data.importedLessons.isEmpty, "Replacing the single cache does not append courses")
        try check(store.data.resume?.lessonID == store.data.libraryStudy?.lesson.id, "New resume resolves to the atomically installed reference")
        var alias = a
        alias = LibraryCourseEntry(id: a.id, fen: a.fen, title: "另一个源名", memberships: [
            LibraryCourseMembership(groupID: "Chess Patterns/别名.json", title: "不同标题", sourceIndex: 9, category: "别名", section: .patterns)])
        model.libraryCatalog = catalog([alias, b, c])
        model.startLibraryEntry(alias, mode: .test, evaluate: rows); try await wait(model)
        try check(model.currentRunUsedHelp && model.lessonID == a.lessonID, "Source aliases share the same assistance and progress identity")
        model.libraryCatalog = catalog([a, b, c])
        // Failed or cancelled generation leaves the exact archive and board alone.
        let priorBytes = try store.exportData(), priorBoard = model.position, priorID = model.lessonID
        let priorGroup = model.libraryGroupID, priorSection = model.librarySection
        model.startLibraryEntry(b, evaluate: { _, _ in throw Failure(message: "offline engine failure") })
        try await wait(model)
        try check(try store.exportData() == priorBytes && model.position == priorBoard && model.lessonID == priorID,
                  "Failed generation never replaces the saved line or live board")
        try check(model.libraryGroupID == priorGroup && model.librarySection == priorSection,
                  "Failed preparation must not redirect the old lesson's next-position scope")
        model.notice = nil
        model.startLibraryEntry(b, evaluate: { _, _ in try await Task.sleep(nanoseconds: 300_000_000); return [] })
        try check(model.libraryPreparing, "Preparing is a real cancellable state")
        model.cancelCurrentOperation(); try await Task.sleep(nanoseconds: 30_000_000)
        try check(!model.libraryPreparing && model.position == priorBoard && model.lessonID == priorID,
                  "Cancel prevents a late response from changing the lesson")
        try check(try store.exportData() == priorBytes, "Cancelled generation preserves progress and resume")
        try check(model.libraryGroupID == priorGroup && model.librarySection == priorSection,
                  "Cancelled preparation leaves the current source scope intact")
        // Newer selection wins even if an evaluator ignores cancellation.
        model.startLibraryEntry(b, evaluate: { p, ms in try? await Task.sleep(nanoseconds: 100_000_000); return try await rows(p, ms) })
        model.startLibraryEntry(c, evaluate: rows); try await wait(model)
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(model.lessonID == c.lessonID && store.data.libraryStudy?.entryID == c.id, "New selection rejects a stale generated lesson")
        // Backup round-trip knows about the active generated lesson and fingerprint.
        let backup = try store.exportData()
        model.libraryPlanIDs = [a.id, b.id]
        _ = try model.restoreLearningArchive(backup)
        try check(model.libraryPlanIDs.isEmpty && model.page == .home, "Restoring clears the obsolete working plan")
        model.resumeStudy()
        try check(model.lessonID == c.lessonID && model.line != nil, "Backup round-trip retains generated resolver and resume")
        var malformed = try JSONSerialization.jsonObject(with: backup) as! [String: Any]
        var generated = malformed["libraryStudy"] as! [String: Any]; generated["entryID"] = String(repeating: "0", count: 64)
        malformed["libraryStudy"] = generated
        let beforeRejected = try store.exportData()
        try rejects { _ = try model.restoreLearningArchive(JSONSerialization.data(withJSONObject: malformed)) }
        try check(try store.exportData() == beforeRejected && model.lessonID == c.lessonID, "Malformed generated backup cannot corrupt the active course")
        // Progress filtering is used by both the visible browser and next selection.
        store.finishRun(id: UUID(), lessonID: a.lessonID, lineID: LibraryGeneratedStudy.lineID, mode: .practice,
                        hints: 1, errors: 0, wasRetry: false, wasUnseen: true)
        model.openLibraryCourses(section: .opening); model.libraryStatusFilter = 1
        try check(!model.libraryFilteredEntries.contains(where: { $0.id == a.id }), "Practiced positions leave the unpracticed filter")
        try check(model.libraryProgress(entryID: a.id).cleanTests == 0, "Guided practice is not independent success")
        model.libraryCatalog = catalog([c]); model.libraryStatusFilter = 0
        try check(!model.libraryCanContinue, "Single-entry current group cannot pretend another position exists")
        // Optional current-study field permits all old archives to decode.
        let legacy = LearningArchive()
        let legacyBytes = try JSONEncoder().encode(legacy)
        let old = try JSONDecoder().decode(LearningArchive.self, from: legacyBytes)
        try check(old.libraryStudy == nil && old.version == 1, "Older version-1 data remains supported")
        let protectedDirectory = directory.appendingPathComponent("protected")
        try FileManager.default.createDirectory(at: protectedDirectory, withIntermediateDirectories: true)
        let corrupt = Data("not-json".utf8)
        let corruptURL = protectedDirectory.appendingPathComponent("learning.json")
        try corrupt.write(to: corruptURL)
        let protected = LearningStore(directory: protectedDirectory)
        try rejects { try protected.installLibraryStudy(active) }
        try check(try Data(contentsOf: corruptURL) == corrupt, "Corrupt user archives remain byte-for-byte protected")
        print("PASS \(checks) library-learning integration checks: all-position scheduling, single-slot storage, exact resume, source-bound help, retry across topics, cancellation, failure, backup and progress filters")
    }
}
#endif
