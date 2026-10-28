#if IMPORT_SAFETY_TESTS
import Foundation
import Darwin

#if !APP_TESTS
struct RecommendationArrow { let rank: Int; let move: Move }
#endif

@main @MainActor
struct ImportSafetyTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure(message: message) }
        checks += 1
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { checks += 1; return }
        throw Failure(message: message)
    }
    static func pack(_ id: String, title: String = "Synthetic import fixture") -> StudyPack {
        let lesson = LearningLesson(id: id, title: title, stage: .opening, order: 1,
            summary: "合成局面", goal: "出子", principle: "检查合法着", whenToAdapt: "对手改变时",
            pitfalls: [], sourceIDs: [], lines: [StudyLine(id: "line", title: "合成线路", intent: "出子",
                adaptation: "观察变化", studentSide: .red,
                moves: [StudyMove("b2e2", "移动炮"), StudyMove("b9c7", "黑方出马")])])
        return StudyPack(title: "Synthetic", sources: [], lessons: [lesson])
    }
    static func snapshot(_ store: LearningStore) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(store.data)
    }
    static func main() throws {
        let root = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("xiangqi-import-safety-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = directory.appendingPathComponent("valid.json")
        try Data("12345678".utf8).write(to: valid)
        try check(try SafeLocalFile.read(valid, maximumBytes: 8) == Data("12345678".utf8), "Exact byte limit succeeds")
        try rejects("Larger file accepted") { _ = try SafeLocalFile.read(valid, maximumBytes: 7) }
        try rejects("Negative limit accepted") { _ = try SafeLocalFile.read(valid, maximumBytes: -1) }
        try rejects("Overflowing limit accepted") { _ = try SafeLocalFile.read(valid, maximumBytes: Int.max) }
        try rejects("Directory accepted") { _ = try SafeLocalFile.read(directory, maximumBytes: 8_000_000) }
        try rejects("Remote URL accepted") { _ = try SafeLocalFile.read(URL(string: "https://example.com/file.json")!, maximumBytes: 8) }
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: valid)
        try rejects("Symbolic link accepted") { _ = try SafeLocalFile.read(link, maximumBytes: 8) }
        let fifo = directory.appendingPathComponent("pipe.json")
        guard mkfifo(fifo.path, S_IRUSR | S_IWUSR) == 0 else { throw Failure(message: "Cannot create test FIFO") }
        try rejects("FIFO should fail without waiting for a writer") { _ = try SafeLocalFile.read(fifo, maximumBytes: 8) }
        let large = directory.appendingPathComponent("large.json")
        try Data().write(to: large)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 8_000_001); try handle.close()
        try rejects("8 MB ceiling was not enforced before allocation") { _ = try SafeLocalFile.read(large, maximumBytes: 8_000_000) }

        let storeDirectory = directory.appendingPathComponent("store")
        let store = LearningStore(directory: storeDirectory)
        try store.importPack(pack("first"), builtInIDs: [])
        try check(LearningStore(directory: storeDirectory).data.importedLessons.map(\.id) == ["first"], "Success is durable")
        let before = try snapshot(store)
        let target = storeDirectory.appendingPathComponent("learning.json")
        let original = try Data(contentsOf: target)
        // A directory at the backup path forces a deterministic write failure,
        // independent of permissions and whether tests run as an administrator.
        let backup = storeDirectory.appendingPathComponent("learning.previous.json")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try rejects("Import must report backup/write failure") { try store.importPack(pack("second"), builtInIDs: []) }
        try check(try snapshot(store) == before, "Failed disk commit does not publish imported lessons")
        try check(try Data(contentsOf: target) == original, "Failed commit preserves existing archive bytes")
        try FileManager.default.removeItem(at: backup)
        try rejects("Oversized merged archive accepted") {
            try store.importPack(pack("oversized", title: String(repeating: "x", count: 8_000_000)), builtInIDs: [])
        }
        try check(try snapshot(store) == before && Data(contentsOf: target) == original, "Capacity failure preserves memory and disk")

        let prepared = try pack("duplicate").preparedForImport(existingLessonIDs: ["first"])
        try store.importPack(pack("duplicate"), builtInIDs: [])
        let afterFirst = try snapshot(store)
        try rejects("Stale background validation allowed duplicate import") {
            try store.importPreparedPack(prepared, builtInIDs: [])
        }
        try check(try snapshot(store) == afterFirst, "Stale validation failure makes no change")

        let corruptDirectory = directory.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let corruptURL = corruptDirectory.appendingPathComponent("learning.json")
        let corruptBytes = Data("broken synthetic archive".utf8)
        try corruptBytes.write(to: corruptURL)
        let protected = LearningStore(directory: corruptDirectory)
        let protectedState = try snapshot(protected)
        try rejects("Corrupt protected store accepted import") { try protected.importPack(pack("protected"), builtInIDs: []) }
        try check(try snapshot(protected) == protectedState && Data(contentsOf: corruptURL) == corruptBytes,
                  "Protection preserves corrupt original and rejects phantom courses")
        print("PASS \(checks) import safety checks: bounded regular files, background-validation freshness, transactional import and corrupt archive protection")
    }
}
#endif
