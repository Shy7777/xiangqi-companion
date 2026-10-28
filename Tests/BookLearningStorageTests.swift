#if BOOK_LEARNING_STORAGE_TESTS
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct BookLearningStorageTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure(message: message) }; checks += 1
    }
    static func rejects(_ action: () throws -> Void) throws {
        do { try action() } catch { checks += 1; return }
        throw Failure(message: "Expected rejection")
    }
    static func main() throws {
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("book-learning-storage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = BookStudySource(bookSHA: String(repeating: "a", count: 64), recordID: "cbl-source-one", nodeID: 1201, title: "本课关键点")
        let alternate = BookStudySource(bookSHA: source.bookSHA, recordID: "cbl-source-two", nodeID: 1201, title: "另一篇同局面")
        let runID = UUID()
        let resume = BookPracticeResume(source: source, unitID: "unit-1", checkpointIndex: 1, stage: "decision",
            positionFEN: Position.initial.fen, studentSide: .red, attemptedMove: nil, hintLevel: 0,
            hints: 0, errors: 0, wasRetry: false, runID: runID, started: now, wasUnseen: true,
            lastMove: nil, completedCheckpointIDs: ["point-0"])
        try check(store.setBookResume(resume), "Book resume persists atomically with source")
        try check(store.bookSource(lessonID: source.lessonID, lineID: source.lineID) == source, "Source is identified by exact edition, record and node")
        try check(LearningStore(directory: directory).data.bookResume == resume, "Book resume survives restart without original text copies")
        try check(store.data.runs.isEmpty && store.data.progress.isEmpty, "Navigation does not award progress")

        let legacyRunID = UUID()
        store.setResume(StudyResume(lessonID: "legacy", lineID: "line", mode: .practice, cursor: 0,
            hints: 0, errors: 0, wasRetry: false, runID: legacyRunID, started: now, wasUnseen: true))
        store.markExposed(source.lessonID, source.lineID, assisted: true, now: now)
        store.finishRun(id: runID, lessonID: source.lessonID, lineID: source.lineID, mode: .test,
            hints: 0, errors: 0, wasRetry: false, wasUnseen: true, now: now.addingTimeInterval(60))
        try check(store.data.resume?.runID == legacyRunID, "Book completion cannot erase another course resume")
        try check(store.data.runs.last?.independent == false && store.data.runs.last?.transfer == false,
            "Recent answer exposure cannot become independent or transfer evidence")
        store.finishRun(id: runID, lessonID: source.lessonID, lineID: source.lineID, mode: .test,
            hints: 0, errors: 0, wasRetry: false, wasUnseen: true, now: now)
        try check(store.data.runs.count == 1, "One accepted attempt cannot be counted twice")
        store.finishRun(id: UUID(), lessonID: source.lessonID, lineID: source.lineID, mode: .test,
            hints: 0, errors: 0, wasRetry: false, wasUnseen: false, now: now.addingTimeInterval(2 * 86400))
        try check(store.data.runs.last?.delayed == true, "Unassisted delayed return earns separate evidence")

        try check(store.registerBookSource(alternate), "Another source can refer to the same legal board")
        func review(_ source: BookStudySource?) {
            store.addReview(lessonID: source?.lessonID, lineID: source?.lineID, title: source?.title ?? "自由对局",
                fen: Position.initial.fen, attempted: "a3a4", suggested: "b0c2", detail: "检查出子", replyPV: ["a6a5"], now: now)
        }
        review(source); review(source); review(alternate); review(nil)
        try check(store.data.reviews.count == 3 && store.data.reviews.first?.occurrences == 2,
            "Repeated same-node errors deduplicate; different book nodes and free play do not lose provenance")
        store.setResume(nil)
        let archive = try store.exportData()
        let restored = LearningStore(directory: directory.appendingPathComponent("restored"))
        _ = try restored.restoreBackup(archive, builtInIDs: [], builtInSources: [])
        try check(restored.data.bookResume == resume && restored.data.bookSources == store.data.bookSources,
            "Backup preserves source references and in-progress classroom")
        try check(restored.data.runs.count == 2 && restored.data.reviews.count == 3, "Backup retains shared evidence")

        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LearningArchive())) as! [String: Any]
        old.removeValue(forKey: "bookResume"); old.removeValue(forKey: "bookSources")
        let decoded = try JSONDecoder().decode(LearningArchive.self, from: JSONSerialization.data(withJSONObject: old))
        try check(decoded.bookResume == nil && decoded.bookSources == nil && decoded.version == 1, "Pre-3.0 archives decode without migration")
        let badSource = BookStudySource(bookSHA: source.bookSHA, recordID: "../escape", nodeID: 0, title: "bad")
        let beforeInvalid = try store.exportData()
        try check(!store.registerBookSource(badSource), "Malformed source identifiers are rejected")
        try check(try store.exportData() == beforeInvalid, "Rejected source leaves published data unchanged")
        var malformed = try JSONSerialization.jsonObject(with: archive) as! [String: Any]
        var invalidResume = malformed["bookResume"] as! [String: Any]
        invalidResume["stage"] = "invented-pass"; malformed["bookResume"] = invalidResume
        try rejects { _ = try restored.restoreBackup(JSONSerialization.data(withJSONObject: malformed), builtInIDs: [], builtInSources: []) }
        try check(restored.data.bookResume == resume, "Invalid resume cannot replace the good archive")
        malformed = try JSONSerialization.jsonObject(with: archive) as! [String: Any]
        malformed["bookSources"] = [:]
        try rejects { _ = try restored.restoreBackup(JSONSerialization.data(withJSONObject: malformed), builtInIDs: [], builtInSources: []) }

        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data("owned fixture".utf8).write(to: blocked)
        let unwritable = LearningStore(directory: blocked)
        try check(!unwritable.setBookResume(resume) && unwritable.data.bookResume == nil && unwritable.data.bookSources == nil,
            "Failed writes do not publish phantom saved progress")
        let corruptDirectory = directory.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let corruptURL = corruptDirectory.appendingPathComponent("learning.json"), corrupt = Data("broken user archive".utf8)
        try corrupt.write(to: corruptURL)
        let protected = LearningStore(directory: corruptDirectory)
        try check(!protected.setBookResume(resume) && !protected.registerBookSource(source), "Corrupt archives are protected from all new book mutations")
        try check(try Data(contentsOf: corruptURL) == corrupt, "Corrupt original bytes are preserved")
        print("PASS \(checks) book-learning storage checks: compatibility, provenance, honest evidence, isolation, backup, atomic failure and corruption protection")
    }
}
#endif
