#if POSITION_LIBRARY_TESTS
import Foundation

@main @MainActor
struct PositionLibraryTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure(message: message) }; checks += 1
    }
    static func reject(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { checks += 1; return }; throw Failure(message: message)
    }
    static func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    static func directory(_ label: String) throws -> URL {
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("position-library-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    static func main() async {
        do {
            let first = Position.initial, second = try first.applying(move: Move(uci: "b2e2")!)
            let revision = UUID()
            let duplicateCounters = first.fen.replacingOccurrences(of: " w - - 0 1", with: " r - - 88 50")
            let payload: [[String: Any]] = [
                ["fen": first.fen, "name": "原始名称", "bestMove": "", "result": "egtb:", "timestamp": "2025-01-01", "sourceURL": "javascript:alert(1)"],
                ["fen": duplicateCounters, "name": "同局面换名称与计数器"],
                ["fen": second.fen, "name": "第二个局面", "bestMove": "a9a8", "result": "红胜", "timestamp": 1740000000],
                ["fen": "bad", "name": "坏格式"],
                ["fen": "9/9/9/9/9/9/9/9/9/9 w - - 0 1", "name": "没有将帅"],
                ["name": "缺少FEN"]]
            let bytes = try data(payload)
            let preview = try PositionLibraryImporter.preview(data: bytes, fileName: "pwa.json", label: "残局参考", existingFENs: [], revision: revision)
            try check(preview.total == 6 && preview.accepted == 2 && preview.duplicates == 1 && preview.invalid == 3, "Import counts do not reconcile")
            try check(preview.total == preview.accepted + preview.duplicates + preview.invalid, "A record vanished from import summary")
            try check(preview.entries[0].fen == first.fen && preview.entries[0].position == first, "FEN normalization changed the board")
            try check(preview.entries[0].category == "残局参考" && preview.entries[0].sourceFile == "pwa.json" && preview.entries[0].title == "原始名称", "File provenance/category was lost")
            try check(preview.entries[0].originalBestMove == nil && preview.entries[0].originalResult == "egtb:", "An empty bestMove became an answer, or result provenance vanished")
            try check(preview.entries[0].originalSource == "javascript:alert(1)", "Untrusted source text was not preserved as inert metadata")
            try check(preview.entries[1].originalBestMove == "a9a8" && preview.entries[1].originalTimestamp == "1740000000", "Unverified move or numeric source timestamp was lost")
            try check(preview.issues.count == 3, "Invalid FEN reasons were not shown")
            let existing = try PositionLibraryImporter.preview(data: bytes, fileName: "same.json", label: "", existingFENs: [first.fen, second.fen], revision: revision)
            try check(existing.accepted == 0 && existing.duplicates == 3 && existing.invalid == 3, "Stored duplicates were not detected")
            let text = try PositionLibraryImporter.preview(data: Data((first.fen + "\n\n" + second.fen).utf8), fileName: "两局.fen", label: "", existingFENs: [], revision: revision)
            try check(text.total == 2 && text.accepted == 2 && text.entries[0].category == "两局", "Plain FEN lines/file category failed")
            let object = try PositionLibraryImporter.preview(data: data(payload[0]), fileName: "single.json", label: "", existingFENs: [], revision: revision)
            try check(object.accepted == 1, "Single-position object failed")
            func lesson(_ id: String, fen: String, move: String) -> LearningLesson {
                LearningLesson(id: id, title: "本机课程", stage: .opening, order: 1, summary: "引用", goal: "研究局面",
                    principle: "不复制记录", whenToAdapt: "重新分析", pitfalls: [], sourceIDs: [],
                    lines: [StudyLine(id: "line", title: "原线路", intent: "研究", adaptation: "分析", startingFEN: fen,
                                      moves: [StudyMove(move, "原课说明")])])
            }
            let courses = [lesson("first", fen: first.fen, move: "b2e2"), lesson("duplicate", fen: duplicateCounters, move: "b2e2"),
                           lesson("illegal-board", fen: "9/9/9/9/9/9/9/9/9/9 w - - 0 1", move: "b9c7"),
                           lesson("second", fen: second.fen, move: "b9c7"), lesson("bad", fen: "bad", move: "b9c7")]
            let references = PositionLibraryCurriculumAdapter.references(from: courses)
            try check(references.count == 2 && references.map(\.fen) == [first.fen, second.fen], "Curriculum references were not normalized/deduplicated")
            try check(references == PositionLibraryCurriculumAdapter.references(from: courses), "Curriculum reference identity changed on redraw")
            try check(references.allSatisfy { $0.originalBestMove == nil && $0.originalResult == nil && $0.sourceFile.contains("本机课程引用") }, "A curriculum reference became an answer or imported file")
            for value in ["-", "--", "none", "null", "undefined", "egtb:", "   ", "需要查詢", "  需要查询  "] {
                let item = try PositionLibraryImporter.preview(data: data(["fen": first.fen, "bestMove": value]), fileName: "x.json", label: "", existingFENs: [], revision: revision)
                try check(item.entries[0].originalBestMove == nil, "Placeholder bestMove became an answer: \(value)")
            }
            for malformed in [Data(), Data("[]".utf8), Data("[".utf8), Data("{\"board\":[]}".utf8), Data([255, 254])] {
                try reject("Unsupported/empty input passed") { _ = try PositionLibraryImporter.preview(data: malformed, fileName: "x", label: "", existingFENs: [], revision: revision) }
            }
            try reject("Oversized file passed") { _ = try PositionLibraryImporter.preview(data: Data(repeating: 32, count: PositionLibraryImporter.maximumBytes + 1), fileName: "x", label: "", existingFENs: [], revision: revision) }
            try reject("Oversized item count passed") { _ = try PositionLibraryImporter.preview(data: data(Array(repeating: ["fen": first.fen], count: PositionLibraryImporter.maximumItems + 1)), fileName: "x", label: "", existingFENs: [], revision: revision) }

            let root = try directory("store"), library = root.appendingPathComponent("library")
            let session = root.appendingPathComponent("session.json"), learning = root.appendingPathComponent("learning.json")
            let sentinel = Data("untouched-session-and-learning".utf8)
            try sentinel.write(to: session); try sentinel.write(to: learning)
            let store = PositionLibraryStore(directory: library)
            try check(!store.isLoaded && !FileManager.default.fileExists(atPath: library.path), "Construction eagerly created/loaded a library")
            await store.loadIfNeeded()
            try check(store.entries.isEmpty && store.isLoaded && !FileManager.default.fileExists(atPath: library.path), "Empty library performed a write/download")
            let prepared = try await store.preview(data: bytes, fileName: "pwa.json", label: "残局参考")
            try check(store.entries.isEmpty && !FileManager.default.fileExists(atPath: store.fileURL.path), "Preview wrote before explicit confirmation")
            let referenced = try await store.preview(data: bytes, fileName: "pwa.json", label: "", existingReferences: Set(references.map(\.fen)))
            try check(referenced.accepted == 0 && referenced.duplicates == 3 && store.entries.isEmpty,
                      "Import duplicated curriculum references into personal storage")
            try store.commit(prepared)
            try check(store.entries.count == 2 && FileManager.default.fileExists(atPath: store.fileURL.path), "Confirmed import was not saved")
            let saved = try Data(contentsOf: store.fileURL)
            try reject("Same preview committed twice") { try store.commit(prepared) }
            try check(try Data(contentsOf: store.fileURL) == saved, "Rejected stale preview changed archive bytes")
            let restored = PositionLibraryStore(directory: library)
            await restored.loadIfNeeded()
            try check(restored.entries == store.entries && restored.error == nil, "Library failed to restore metadata/normalized positions")
            let duplicate = try await restored.preview(data: bytes, fileName: "again.json", label: "")
            try check(duplicate.accepted == 0 && duplicate.duplicates == 3, "Restart lost duplicate identity")
            try reject("All-duplicate preview committed") { try restored.commit(duplicate) }
            try check(try Data(contentsOf: session) == sentinel && Data(contentsOf: learning) == sentinel, "Library import touched analysis or learning state")

            let corruptionDirectory = try directory("corrupt"), corruptionURL = corruptionDirectory.appendingPathComponent("positions.json")
            let corruptBytes = Data("broken-library".utf8); try corruptBytes.write(to: corruptionURL)
            let corrupt = PositionLibraryStore(directory: corruptionDirectory); await corrupt.loadIfNeeded()
            try check(corrupt.error != nil && corrupt.entries.isEmpty, "Corrupt archive silently became writable")
            do { _ = try await corrupt.preview(data: bytes, fileName: "x", label: ""); throw Failure(message: "Corrupt archive accepted import") }
            catch is Failure { throw Failure(message: "Corrupt archive accepted import") } catch { checks += 1 }
            try check(try Data(contentsOf: corruptionURL) == corruptBytes, "Corrupt original was overwritten")
            let forgedDirectory = try directory("invalid-position")
            var forged = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
            var records = forged["entries"] as! [[String: Any]]; records[0]["fen"] = "bad"; forged["entries"] = records
            try data(forged).write(to: forgedDirectory.appendingPathComponent("positions.json"))
            let invalid = PositionLibraryStore(directory: forgedDirectory); await invalid.loadIfNeeded()
            try check(invalid.error != nil && invalid.entries.isEmpty, "Decoded but illegal archive bypassed position validation")
            for fault in ["version", "duplicate-id"] {
                let invalidDirectory = try directory(fault)
                var archive = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
                if fault == "version" { archive["version"] = 2 }
                else {
                    let records = archive["entries"] as! [[String: Any]]
                    archive["entries"] = [records[0], records[0]]
                }
                let invalidBytes = try data(archive), url = invalidDirectory.appendingPathComponent("positions.json")
                try invalidBytes.write(to: url)
                let invalidStore = PositionLibraryStore(directory: invalidDirectory); await invalidStore.loadIfNeeded()
                try check(invalidStore.error != nil && invalidStore.entries.isEmpty, "Invalid archive \(fault) was accepted")
                try check(try Data(contentsOf: url) == invalidBytes, "Invalid archive \(fault) was modified")
            }
            let blockedPath = root.appendingPathComponent("not-a-directory")
            try sentinel.write(to: blockedPath)
            let blocked = PositionLibraryStore(directory: blockedPath)
            let blockedPreview = try await blocked.preview(data: bytes, fileName: "pwa.json", label: "")
            try reject("Filesystem failure was swallowed") { try blocked.commit(blockedPreview) }
            try check(try blocked.entries.isEmpty && Data(contentsOf: blockedPath) == sentinel,
                      "A failed transaction published records or damaged the preexisting file")
            let overflow = PositionLibraryImportPreview(id: UUID(), baseRevision: blockedPreview.baseRevision, sourceFile: "overflow",
                total: PositionLibraryImporter.maximumStoredItems + 1, duplicates: 0, invalid: 0, issues: [],
                entries: Array(repeating: blockedPreview.entries[0], count: PositionLibraryImporter.maximumStoredItems + 1))
            try reject("Stored-item cap could be bypassed") { try blocked.commit(overflow) }

            let cancellation = Task { try await store.preview(data: bytes, fileName: "cancelled", label: "") }
            cancellation.cancel()
            do { _ = try await cancellation.value; throw Failure(message: "Cancelled import still returned a preview") }
            catch is CancellationError { checks += 1 }
            try check(try store.entries.count == 2 && !store.isBusy && Data(contentsOf: store.fileURL) == saved, "Cancellation changed stored positions or left busy state")

            let defaultStore = PositionLibraryStore()
            if ProcessInfo.processInfo.environment["XQ_COMPANION_STATE_DIR"] == nil {
                try check(defaultStore.directory.deletingLastPathComponent().lastPathComponent == "XiangqiCompanionOpenSource", "Default library state path differs from the real application")
            }
            let exports = try store.exportBatches()
            try check(exports.count == 1 && exports[0].count == 2, "Export included built-in references or lost personal entries")
            try check(exports.allSatisfy { $0.count <= PositionLibraryImporter.maximumItems && $0.data.count <= PositionLibraryImporter.maximumBytes }, "An export cannot be reimported under the configured limits")
            let roundTrip = try PositionLibraryImporter.preview(data: exports[0].data, fileName: "personal-export.json", label: "重新导入",
                existingFENs: [], revision: UUID())
            try check(roundTrip.accepted == 2 && roundTrip.invalid == 0 && roundTrip.duplicates == 0, "Export is not valid PWA-compatible import data")
            try check(roundTrip.entries.map(\.fen) == store.entries.map(\.fen) && roundTrip.entries.map(\.title) == store.entries.map(\.title), "Export round trip changed positions or names")
            try check(roundTrip.entries.map(\.originalBestMove) == store.entries.map(\.originalBestMove)
                && roundTrip.entries.map(\.originalResult) == store.entries.map(\.originalResult)
                && roundTrip.entries.map(\.originalSource) == store.entries.map(\.originalSource), "Export promoted or discarded unverified source metadata")
            let exportURL = root.appendingPathComponent("explicit-personal-export.json")
            try exports[0].data.write(to: exportURL, options: .withoutOverwriting)
            try reject("Export overwrote an existing file") { try Data("replacement".utf8).write(to: exportURL, options: .withoutOverwriting) }
            try check(try Data(contentsOf: exportURL) == exports[0].data, "Non-overwriting export modified the original file")
            try reject("Corrupt archive was exported as an empty successful backup") { _ = try corrupt.exportBatches() }

            let third = try second.applying(move: Move(uci: "b9c7")!)
            let beforeRemovalPreview = try await store.preview(data: Data(third.fen.utf8), fileName: "third.fen", label: "")
            let removedID = store.entries[0].id
            try store.remove(id: removedID)
            try check(store.entries.count == 1 && store.entries[0].fen == second.fen, "Removal affected more than the selected personal entry")
            try check(try Data(contentsOf: store.previousFileURL) == saved, "Removal did not preserve the exact prior archive")
            let afterRemovalBytes = try Data(contentsOf: store.fileURL)
            try reject("A preview prepared before removal was committed") { try store.commit(beforeRemovalPreview) }
            try reject("A built-in reference could be removed from personal storage") { try store.remove(id: references[0].id) }
            try reject("An already removed entry was removed twice") { try store.remove(id: removedID) }
            try check(try Data(contentsOf: store.fileURL) == afterRemovalBytes && Data(contentsOf: store.previousFileURL) == saved, "Rejected removal or stale import altered current/previous archive")
            let afterRemoval = PositionLibraryStore(directory: library); await afterRemoval.loadIfNeeded()
            try check(afterRemoval.entries == store.entries, "Removal was not persisted across restart")
            let rescued = root.appendingPathComponent("rescued")
            try FileManager.default.createDirectory(at: rescued, withIntermediateDirectories: true)
            try Data(contentsOf: store.previousFileURL).write(to: rescued.appendingPathComponent("positions.json"))
            let recovery = PositionLibraryStore(directory: rescued); await recovery.loadIfNeeded()
            try check(recovery.entries.count == 2 && recovery.error == nil, "Previous archive cannot recover removed entries")
            try check(try Data(contentsOf: session) == sentinel && Data(contentsOf: learning) == sentinel
                && Data(contentsOf: exportURL) == exports[0].data, "Removal touched learning, analysis, or the original export file")

            // Two already-loaded store instances must not overwrite each other's newer data.
            let conflicting = try await restored.preview(data: Data(third.fen.utf8), fileName: "third.fen", label: "")
            try reject("A stale second store overwrote a newer archive") { try restored.commit(conflicting) }
            try check(restored.entries.count == 2 && (try Data(contentsOf: store.fileURL)) == afterRemovalBytes, "Rejected external change detection mutated memory or disk")
            let currentPreview = try await store.preview(data: Data(third.fen.utf8), fileName: "third.fen", label: "")
            let externallyEdited = afterRemovalBytes + Data("\n".utf8)
            try externallyEdited.write(to: store.fileURL)
            try reject("External file edits were overwritten by import") { try store.commit(currentPreview) }
            try reject("External file edits were overwritten by removal") { try store.remove(id: store.entries[0].id) }
            try check(try Data(contentsOf: store.fileURL) == externallyEdited && store.entries.count == 1, "External-edit conflict changed current bytes or memory")

            let backupFailureDirectory = try directory("backup-failure")
            try saved.write(to: backupFailureDirectory.appendingPathComponent("positions.json"))
            let backupFailure = PositionLibraryStore(directory: backupFailureDirectory); await backupFailure.loadIfNeeded()
            try FileManager.default.createDirectory(at: backupFailure.previousFileURL, withIntermediateDirectories: true)
            try reject("Removal proceeded although its safety backup could not be written") { try backupFailure.remove(id: backupFailure.entries[0].id) }
            try check(try Data(contentsOf: backupFailure.fileURL) == saved && backupFailure.entries.count == 2, "Backup failure partially removed personal entries")
            print("PASS: \(checks) position-library parsing, provenance, preview/commit, export/reimport, recoverable removal and isolated-storage checks")
        } catch { print("FAIL: \(error)"); exit(1) }
    }
}
#endif
