#if GITHUB_LIBRARY_SYNC_TESTS
import Foundation

/// Tiny, offline fixtures exercise the real store and parser. The optional live
/// mode is explicit and never selected by verify.sh or the normal test runner.
@main struct GitHubLibrarySyncTests {
    struct Failure: Error { let message: String }
    @MainActor static var checks = 0
    @MainActor static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }; checks += 1
    }
    @MainActor static func requireSnapshot(_ store: GitHubLibraryStore) throws -> GitHubLibrarySnapshot {
        guard let value = store.snapshot else { throw Failure(message: "Missing snapshot: \(store.error ?? store.status)") }
        return value
    }

    actor FixtureRemote {
        enum Mode: Sendable { case normal, networkFailure, mismatchedBlob, truncatedTree, invalidJSON, emptyResources, slowBlob, missingIndex, changedLicense }
        static let awesomeCommit = String(repeating: "a", count: 40)
        static let firstCommit = String(repeating: "b", count: 40)
        static let changedCommit = String(repeating: "c", count: 40)
        static let readme = Data("""
        # Fixture catalog
        ## Engines
        - [原站引擎](https://example.test/engine) - 只读资料
        ## Books
        - [书目](https://example.test/book) - 原书索引
        """.utf8)
        static let html = Data("""
        <script>
        function showGameInstructionsDialog() {
          const content = `<a href="https://example.test/engine">PWA 同一引擎</a>
          <a href="https://example.test/pwa">PWA 独立资料</a>`;
        }
        function closeGameInstructionsDialog() {}
        </script>
        """.utf8)
        let firstFEN: String
        let secondFEN: String
        let thirdFEN: String
        private(set) var requests: [String] = []
        private(set) var slowStarted = false
        var revision = 0
        var mode: Mode = .normal

        init() throws {
            let first = Position.initial
            let second = try first.applying(move: Move(uci: "b2e2")!)
            let third = try second.applying(move: Move(uci: "b9c7")!)
            firstFEN = first.fen; secondFEN = second.fen; thirdFEN = third.fen
        }
        func configure(revision: Int = 0, mode: Mode = .normal) {
            self.revision = revision; self.mode = mode; requests = []; slowStarted = false
        }
        func rawRequests() -> [String] { requests.filter { $0.hasPrefix("https://raw.githubusercontent.com/") && !$0.hasSuffix("/LICENSE") } }
        func data() throws -> [String: Data] {
            let same = try JSONSerialization.data(withJSONObject: [["fen": firstFEN, "name": "同一原始局面", "bestMove": "", "result": "egtb:"]], options: [.sortedKeys])
            let advanced = try JSONSerialization.data(withJSONObject: [["fen": revision == 0 ? secondFEN : thirdFEN, "name": revision == 0 ? "第二局面" : "更新局面"], ["fen": "invalid", "name": "原站坏记录"]], options: [.sortedKeys])
            let html = mode == .emptyResources ? Data("function showGameInstructionsDialog() { const content = `没有链接`; }\nfunction closeGameInstructionsDialog() {}".utf8) : Self.html
            return ["basic-checkmates.json": same, "Chess Patterns/同局面另一类.json": same,
                    "advanced-checkmates.json": mode == .invalidJSON ? Data("{\"notFen\":true}".utf8) : advanced,
                    "index.html": html]
        }
        func treeData() throws -> Data {
            var entries: [[String: Any]] = try data().filter { mode != .missingIndex || $0.key != "index.html" }.map { path, bytes in
                ["path": path, "type": "blob", "sha": GitHubLibraryRemote.blobSHA(bytes), "size": bytes.count]
            }
            // These are intentionally excluded: no model or manifest download.
            entries += [["path": "manifest.json", "type": "blob", "sha": String(repeating: "d", count: 40), "size": 10],
                        ["path": "patterns_index.json", "type": "blob", "sha": String(repeating: "d", count: 40), "size": 10],
                        ["path": "engine/large.nnue", "type": "blob", "sha": String(repeating: "e", count: 40), "size": 100_000_000]]
            return try JSONSerialization.data(withJSONObject: ["truncated": mode == .truncatedTree, "tree": entries], options: [.sortedKeys])
        }
        func fetch(_ url: URL, maximum: Int) async throws -> Data {
            requests.append(url.absoluteString)
            if mode == .networkFailure { throw URLError(.notConnectedToInternet) }
            let bytes: Data
            if url.host == "api.github.com", url.path == "/repos/\(GitHubLibraryRemote.awesomeRepo)/commits/main" {
                bytes = Data("{\"sha\":\"\(Self.awesomeCommit)\"}".utf8)
            } else if url.host == "api.github.com", url.path == "/repos/\(GitHubLibraryRemote.pwaRepo)/commits/main" {
                bytes = Data("{\"sha\":\"\(revision == 0 ? Self.firstCommit : Self.changedCommit)\"}".utf8)
            } else if url.host == "api.github.com", url.path.hasPrefix("/repos/\(GitHubLibraryRemote.pwaRepo)/git/trees/") {
                bytes = try treeData()
            } else if url.host == "raw.githubusercontent.com", url.path.hasSuffix("/LICENSE") {
                if mode == .changedLicense { bytes = Data("Changed license: all rights reserved".utf8) }
                else {
                    let name = url.path.hasPrefix("/\(GitHubLibraryRemote.awesomeRepo)/")
                        ? "awesome-xiangqi-CC0.txt" : "xiangqi-pwa-offline-MIT.txt"
                    bytes = try Data(contentsOf: URL(fileURLWithPath: "Docs/licenses/" + name))
                }
            } else if url.host == "raw.githubusercontent.com", url.path == "/\(GitHubLibraryRemote.awesomeRepo)/\(Self.awesomeCommit)/README.md" {
                bytes = Self.readme
            } else if url.host == "raw.githubusercontent.com" {
                let prefix = "/\(GitHubLibraryRemote.pwaRepo)/\(revision == 0 ? Self.firstCommit : Self.changedCommit)/"
                guard url.path.hasPrefix(prefix), let value = try data()[String(url.path.dropFirst(prefix.count))] else {
                    throw Failure(message: "Unexpected raw request \(url)")
                }
                if mode == .slowBlob, url.path.hasSuffix("advanced-checkmates.json") {
                    slowStarted = true
                    try await Task.sleep(nanoseconds: 20_000_000_000)
                }
                bytes = mode == .mismatchedBlob && url.path.hasSuffix("advanced-checkmates.json") ? Data(repeating: 32, count: value.count) : value
            } else { throw Failure(message: "Unexpected request \(url)") }
            guard bytes.count <= maximum else { throw Failure(message: "Mock response exceeded requested byte limit") }
            return bytes
        }
    }

    @MainActor static func main() async throws {
        if CommandLine.arguments.count > 1 {
            guard CommandLine.arguments.count == 3, ["--live", "--offline"].contains(CommandLine.arguments[1]) else {
                throw Failure(message: "Usage: github-library-sync-tests [--live|--offline <explicit-directory>]")
            }
            let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            if CommandLine.arguments[1] == "--offline" { try await offline(directory: directory) }
            else { try await live(directory: directory) }
            return
        }
        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("github-library-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = try FixtureRemote()
        let fetch: GitHubLibraryRemote.Fetch = { url, maximum in try await remote.fetch(url, maximum: maximum) }
        let store = GitHubLibraryStore(directory: directory.appendingPathComponent("main"))
        try check(!store.isLoaded && store.snapshot == nil, "Store should load lazily")
        await store.synchronize(fetch: fetch)
        try check(store.error == nil && store.isLoaded && !store.isBusy, "First sync failed: \(store.error ?? "unknown")")
        let first = try requireSnapshot(store)
        try check(first.files.count == 3 && first.rawCount == 4 && first.invalidCount == 1, "Raw file/invalid accounting")
        try check(first.positions.count == 2 && first.duplicateCount == 1, "Normalized duplicate accounting")
        let same = first.positions.first { $0.fen == Position.initial.fen }!
        try check(same.origins.count == 2 && same.categories.count == 2, "Same SHA at two paths lost a source category")
        try check(Set(same.origins.map(\.file)) == ["basic-checkmates.json", "Chess Patterns/同局面另一类.json"], "All source paths retained")
        try check(same.origins.allSatisfy { $0.item.index == 1 && $0.item.bestMove == nil && $0.item.result == "egtb:" }, "Source indices/empty answers must remain unverified metadata")
        try check(first.files.first { $0.file.path == "advanced-checkmates.json" }?.issues.first?.contains("第 2 条") == true, "Invalid row retains source index")
        try check(first.pwaIndexFile.path == "index.html" && first.pwaResources.count == 2 && first.awesome.items.count == 2, "Both resource sources loaded")
        try check(first.resources.count == 3, "Exact-URL union did not deduplicate resources")
        let resource = first.resources.first { $0.url.absoluteString == "https://example.test/engine" }!
        try check(resource.origins.count == 2 && Set(resource.origins.map(\.repository)).count == 2, "Resource union lost repository provenance")
        try check(resource.origins.allSatisfy { $0.line > 0 && $0.sourceURL?.absoluteString.contains("#L") == true }, "Resource citations need source lines")
        let firstRaw = await remote.rawRequests()
        try check(firstRaw.count == 4, "First sync should download README + HTML + only 2 distinct data blobs")
        try check(firstRaw.filter { $0.hasSuffix("basic-checkmates.json") || $0.contains("Chess%20Patterns") }.count == 1, "Identical data blob downloaded twice")
        try check(!firstRaw.contains { $0.contains("nnue") || $0.contains("manifest.json") || $0.contains("patterns_index.json") }, "Data sync fetched an excluded asset")
        let objectFiles = try FileManager.default.contentsOfDirectory(atPath: store.objectDirectory.path)
        try check(Set(objectFiles) == Set(first.objectHashes.map { $0 + ".blob" }), "Cache contains unexpected objects")
        try check(first.reusedFiles == 1 && store.completedFiles == 3 && store.totalFiles == 3, "Alias/progress accounting")
        try check(first.downloadedBytes == FixtureRemote.readme.count + FixtureRemote.html.count + first.files.first { $0.file.path == "advanced-checkmates.json" }!.file.size + first.files.first { $0.file.path == "basic-checkmates.json" }!.file.size, "Physical network bytes counted twice")

        await remote.configure()
        await store.synchronize(fetch: fetch)
        let second = try requireSnapshot(store)
        let secondRaw = await remote.rawRequests()
        try check(store.error == nil && secondRaw.isEmpty, "Same SHA sync must not redownload data, README or HTML")
        try check(second.downloadedBytes == 0 && second.reusedFiles == 3, "Zero-data second sync accounting")
        let reviewedRequests = await remote.requests
        try check(reviewedRequests.filter { $0.hasSuffix("/LICENSE") }.count == 2,
                  "Every synchronization must check both exact-revision licenses")
        let preservedArchive = try Data(contentsOf: store.archiveURL)
        await remote.configure(mode: .changedLicense)
        await store.synchronize(fetch: fetch)
        try check(store.error?.contains("许可") == true && (try Data(contentsOf: store.archiveURL)) == preservedArchive,
                  "Changed upstream licensing must fail closed without replacing the existing library")
        await remote.configure()
        let reload = GitHubLibraryStore(directory: store.directory)
        await reload.load()
        try check(reload.error == nil && reload.snapshot?.positions.map(\.id) == second.positions.map(\.id), "Offline load changed positions")
        try check(reload.snapshot?.resources.map(\.id) == second.resources.map(\.id), "Offline load changed resource union")

        // Hash verification applies to cached data too, not only network responses.
        let cached = first.files.first { $0.file.path == "advanced-checkmates.json" }!.file
        try Data("damaged cache".utf8).write(to: store.objectDirectory.appendingPathComponent(cached.sha + ".blob"))
        await remote.configure()
        await store.synchronize(fetch: fetch)
        let repairedRaw = await remote.rawRequests()
        try check(store.error == nil && repairedRaw.count == 1 && repairedRaw[0].hasSuffix("advanced-checkmates.json"), "Bad cached blob was not refetched selectively")

        // Every failed update is transactional: not even formatting in library.json changes.
        for mode in [FixtureRemote.Mode.networkFailure, .mismatchedBlob, .truncatedTree, .invalidJSON, .emptyResources, .missingIndex] {
            let saved = try Data(contentsOf: store.archiveURL)
            await remote.configure(revision: 1, mode: mode)
            await store.synchronize(fetch: fetch)
            try check(store.error != nil && !store.isBusy, "Failed update was not reported: \(mode)")
            try check(try Data(contentsOf: store.archiveURL) == saved && store.snapshot?.pwaCommit == FixtureRemote.firstCommit, "Failed update replaced prior archive: \(mode)")
            try check(Set(try FileManager.default.contentsOfDirectory(atPath: store.objectDirectory.path)) == Set(first.objectHashes.map { $0 + ".blob" }), "Failed update left orphan objects: \(mode)")
        }

        let beforeCancel = try Data(contentsOf: store.archiveURL)
        await remote.configure(revision: 1, mode: .slowBlob)
        let task = Task { await store.synchronize(fetch: fetch) }
        var didStart = false
        for _ in 0..<200 {
            if await remote.slowStarted { didStart = true; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try check(didStart && store.isBusy, "Cancellation test never entered in-flight download")
        task.cancel(); await task.value
        try check(!store.isBusy && store.error == nil && store.status.contains("取消"), "Cancellation failed to finish quietly")
        try check(try Data(contentsOf: store.archiveURL) == beforeCancel, "Cancellation replaced the archive")

        await remote.configure(revision: 1)
        await store.synchronize(fetch: fetch)
        let updated = try requireSnapshot(store)
        let updateRaw = await remote.rawRequests()
        try check(store.error == nil && updated.pwaCommit == FixtureRemote.changedCommit, "New commit did not install")
        try check(updateRaw.count == 1 && updateRaw[0].hasSuffix("advanced-checkmates.json"), "Unchanged blobs were redownloaded after commit change")
        try check(updated.positions.contains { $0.title == "更新局面" } && !updated.positions.contains { $0.title == "第二局面" }, "Snapshot did not replace obsolete rows")
        try check(!FileManager.default.fileExists(atPath: store.objectDirectory.appendingPathComponent(cached.sha + ".blob").path), "Old unreferenced blob not pruned")
        let finalLoad = GitHubLibraryStore(directory: store.directory)
        await finalLoad.load()
        try check(finalLoad.error == nil && finalLoad.snapshot?.pwaCommit == updated.pwaCommit, "Updated snapshot not independently reloadable")

        // A separately written valid archive is protected, even if its JSON differs only by whitespace.
        var external = try Data(contentsOf: store.archiveURL); external.append(10)
        try external.write(to: store.archiveURL, options: .atomic)
        await remote.configure(revision: 1)
        await store.synchronize(fetch: fetch)
        try check(store.error?.contains("另一窗口") == true && (try Data(contentsOf: store.archiveURL)) == external, "Stale store overwrote another writer's archive")

        try await corruptedArchiveTests(snapshot: updated, directory: directory, fetch: fetch, remote: remote)
        try await isolationTests(directory: directory)
        try remoteValidationTests()
        print("PASS: \(checks) GitHub union sync, immutable-blob reuse, source retention, corruption, conflict, cancellation and offline-load checks")
    }

    @MainActor static func corruptedArchiveTests(snapshot: GitHubLibrarySnapshot, directory: URL, fetch: @escaping GitHubLibraryRemote.Fetch, remote: FixtureRemote) async throws {
        let bytes = try JSONEncoder().encode(snapshot)
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("unknown version", { $0["version"] = 99 }),
            ("Int.max size", { value in
                var files = value["files"] as! [[String: Any]]; var file = files[0]["file"] as! [String: Any]
                file["size"] = Int.max; files[0]["file"] = file; value["files"] = files
            }),
            ("Int.max total", { value in var files = value["files"] as! [[String: Any]]; files[0]["total"] = Int.max; value["files"] = files }),
            ("Int.max invalid", { value in var files = value["files"] as! [[String: Any]]; files[0]["invalid"] = Int.max; value["files"] = files }),
            ("duplicate source identity", { value in
                var positions = value["positions"] as! [[String: Any]]
                let index = positions.firstIndex { ($0["origins"] as! [[String: Any]]).count == 2 }!
                var origins = positions[index]["origins"] as! [[String: Any]]; origins[1] = origins[0]
                positions[index]["origins"] = origins; value["positions"] = positions
            }),
            ("source index beyond file", { value in
                var positions = value["positions"] as! [[String: Any]]
                var origins = positions[0]["origins"] as! [[String: Any]]
                var item = origins[0]["item"] as! [String: Any]; item["index"] = 20_001; origins[0]["item"] = item
                positions[0]["origins"] = origins; value["positions"] = positions
            })
        ]
        for (name, mutate) in mutations {
            var object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            mutate(&object)
            let bad = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let decoded = try JSONDecoder().decode(GitHubLibrarySnapshot.self, from: bad)
            var rejected = false
            do { try GitHubLibraryStore.validate(decoded) } catch { rejected = true }
            try check(rejected, "Corrupt snapshot accepted: \(name)")
            let location = directory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            let archive = location.appendingPathComponent("library.json")
            try bad.write(to: archive)
            let store = GitHubLibraryStore(directory: location)
            await store.load()
            try check(store.error != nil && store.snapshot == nil && store.isLoaded, "Corrupt archive did not enter safe read-only state: \(name)")
            await remote.configure()
            await store.synchronize(fetch: fetch)
            let calls = await remote.requests
            try check(calls.isEmpty && (try Data(contentsOf: archive)) == bad, "Read-only archive was fetched/overwritten: \(name)")
        }
        let location = directory.appendingPathComponent("non-json")
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        let archive = location.appendingPathComponent("library.json"), bad = Data("preserve this corrupted original".utf8)
        try bad.write(to: archive)
        let store = GitHubLibraryStore(directory: location)
        await store.load(); await store.synchronize(fetch: fetch)
        try check(store.error != nil && store.snapshot == nil && (try Data(contentsOf: archive)) == bad, "Malformed JSON was not preserved")

        // A new store that loaded 'no file' must not race a subsequent first writer.
        let conflictLocation = directory.appendingPathComponent("first-writer")
        let empty = GitHubLibraryStore(directory: conflictLocation)
        await empty.load()
        try FileManager.default.createDirectory(at: conflictLocation, withIntermediateDirectories: true)
        try bytes.write(to: empty.archiveURL)
        await remote.configure(revision: 1)
        await empty.synchronize(fetch: fetch)
        try check(empty.error?.contains("另一窗口") == true && empty.snapshot == nil && (try Data(contentsOf: empty.archiveURL)) == bytes, "First-sync race overwrote another writer")
    }

    @MainActor static func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<300 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw Failure(message: "Timed out waiting for bounded mock state")
    }

    @MainActor static func isolationTests(directory: URL) async throws {
        let location = directory.appendingPathComponent("multi-store")
        let remoteA = try FixtureRemote(), remoteB = try FixtureRemote()
        let fetchA: GitHubLibraryRemote.Fetch = { url, limit in try await remoteA.fetch(url, maximum: limit) }
        let fetchB: GitHubLibraryRemote.Fetch = { url, limit in try await remoteB.fetch(url, maximum: limit) }
        let first = GitHubLibraryStore(directory: location)
        await first.synchronize(fetch: fetchA)
        let old = try requireSnapshot(first), oldArchive = try Data(contentsOf: first.archiveURL)
        let second = GitHubLibraryStore(directory: location)
        await second.load()

        // startSync owns its task handle immediately, before the task is scheduled.
        // A second click must neither queue a second sync nor replace the handle.
        await remoteA.configure(revision: 1, mode: .slowBlob)
        first.startSync(fetch: fetchA); first.startSync(fetch: fetchA)
        try await waitUntil { await remoteA.slowStarted }
        let firstRequests = await remoteA.requests
        try check(first.isBusy && firstRequests.filter { $0.contains("/commits/main") }.count == 2, "Double click launched two syncs")
        await remoteB.configure(revision: 1)
        await second.synchronize(fetch: fetchB)
        let secondRequests = await remoteB.requests
        try check(second.error != nil && !second.isBusy && secondRequests.isEmpty, "Same-directory lock allowed a competing network sync")
        try check(try Data(contentsOf: first.archiveURL) == oldArchive, "Competing store modified archive under lock")
        first.cancel()
        try await waitUntil { !first.isBusy }
        try check(first.error == nil && first.status.contains("取消") && first.snapshot?.pwaCommit == old.pwaCommit, "startSync cancellation lost its original handle")
        try check(try Data(contentsOf: first.archiveURL) == oldArchive, "Cancel button committed an incomplete archive")

        // Reuse after cancellation proves the old task handle and OS lock released.
        await remoteA.configure(revision: 1)
        first.startSync(fetch: fetchA)
        try await waitUntil { first.snapshot?.pwaCommit == FixtureRemote.changedCommit && !first.isBusy }
        let current = try requireSnapshot(first)
        try check(first.error == nil, "Sync lock/handle was not released after cancellation")
        let currentArchive = try Data(contentsOf: first.archiveURL)
        let currentObjects = Set(current.objectHashes.map { $0 + ".blob" })
        try check(Set(try FileManager.default.contentsOfDirectory(atPath: first.objectDirectory.path)) == currentObjects, "Successful update did not retain exactly referenced objects")

        // A stale second store may redownload an old object before noticing the
        // changed archive digest. Its cleanup must consult the committed snapshot.
        await remoteB.configure(revision: 0)
        await second.synchronize(fetch: fetchB)
        try check(second.error?.contains("另一窗口") == true, "Stale second store failed to detect newer archive")
        try check(try Data(contentsOf: first.archiveURL) == currentArchive, "Stale second store replaced latest archive")
        let afterStale = Set(try FileManager.default.contentsOfDirectory(atPath: first.objectDirectory.path))
        let stillReferenced = currentObjects.union(old.objectHashes.map { $0 + ".blob" })
        try check(currentObjects.isSubset(of: afterStale) && afterStale.isSubset(of: stillReferenced), "Stale failure deleted another store's new cache or retained an unreferenced object")

        // All symlinks point only inside this test's disposable directory.
        let foreign = directory.appendingPathComponent("sentinel-target")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        let sentinel = foreign.appendingPathComponent("keep.txt"), marker = Data("must stay exactly as written".utf8)
        try marker.write(to: sentinel)
        try currentArchive.write(to: foreign.appendingPathComponent("library.json"))
        let rootLink = directory.appendingPathComponent("symlink-root")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: foreign)
        let linked = GitHubLibraryStore(directory: rootLink)
        await remoteB.configure()
        await linked.load(); await linked.synchronize(fetch: fetchB)
        let rootCalls = await remoteB.requests
        try check(linked.error != nil && linked.snapshot == nil && rootCalls.isEmpty, "Symlink library root was followed")
        try check(try Data(contentsOf: sentinel) == marker && Data(contentsOf: foreign.appendingPathComponent("library.json")) == currentArchive, "Symlink root modified target files")

        let objectsLocation = directory.appendingPathComponent("symlink-objects")
        try FileManager.default.createDirectory(at: objectsLocation, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: objectsLocation.appendingPathComponent("objects"), withDestinationURL: foreign)
        let linkedObjects = GitHubLibraryStore(directory: objectsLocation)
        let foreignBefore = Set(try FileManager.default.contentsOfDirectory(atPath: foreign.path))
        await remoteB.configure()
        await linkedObjects.synchronize(fetch: fetchB)
        try check(linkedObjects.error != nil && linkedObjects.snapshot == nil && !FileManager.default.fileExists(atPath: linkedObjects.archiveURL.path), "Symlink objects directory accepted")
        try check(Set(try FileManager.default.contentsOfDirectory(atPath: foreign.path)) == foreignBefore && (try Data(contentsOf: sentinel)) == marker, "Symlink objects cache wrote/pruned outside the library")

        let lockLocation = directory.appendingPathComponent("symlink-lock")
        try FileManager.default.createDirectory(at: lockLocation, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: lockLocation.appendingPathComponent("sync.lock"), withDestinationURL: sentinel)
        let linkedLock = GitHubLibraryStore(directory: lockLocation)
        await remoteB.configure()
        await linkedLock.synchronize(fetch: fetchB)
        let lockCalls = await remoteB.requests
        try check(linkedLock.error != nil && lockCalls.isEmpty && (try Data(contentsOf: sentinel)) == marker, "Symlink lock was followed or target modified")
    }

    @MainActor static func remoteValidationTests() throws {
        for (repo, commit, path) in [("other/repo", FixtureRemote.firstCommit, "basic.json"),
                                     (GitHubLibraryRemote.pwaRepo, "main", "basic.json"),
                                     (GitHubLibraryRemote.pwaRepo, FixtureRemote.firstCommit, "../secret.json"),
                                     (GitHubLibraryRemote.pwaRepo, FixtureRemote.firstCommit, "/basic.json")] {
            var rejected = false
            do { _ = try GitHubLibraryRemote.rawURL(repo: repo, commit: commit, path: path) } catch { rejected = true }
            try check(rejected, "Unsafe raw URL accepted")
        }
        let encoded = try GitHubLibraryRemote.rawURL(repo: GitHubLibraryRemote.pwaRepo, commit: FixtureRemote.firstCommit, path: "Chess Patterns/中文 名.json")
        try check(encoded.path.hasSuffix("Chess Patterns/中文 名.json") && encoded.host == "raw.githubusercontent.com", "Unicode path escaped incorrectly")
    }

    /// Caller opts into real network and selects the only writable data directory.
    /// First call is transactional; second call checks incremental reuse; then a
    /// fresh store loads without a fetch closure or any network operation.
    @MainActor static func live(directory: URL) async throws {
        guard directory.path != "/", directory.path != NSHomeDirectory(), !directory.path.isEmpty else {
            throw Failure(message: "Select a dedicated library directory")
        }
        let store = GitHubLibraryStore(directory: directory)
        await store.synchronize()
        guard store.error == nil else { throw Failure(message: store.error!) }
        let first = try requireSnapshot(store)
        print("LIVE first: awesome=\(first.awesome.commit) pwa=\(first.pwaCommit) files=\(first.files.count) raw=\(first.rawCount) invalid=\(first.invalidCount) unique=\(first.positions.count) duplicate=\(first.duplicateCount) resources=\(first.resources.count) awesomeEntries=\(first.awesome.items.count) pwaLinks=\(first.pwaResources.count) sourceBytes=\(first.sourceBytes) downloaded=\(first.downloadedBytes) reused=\(first.reusedFiles)")
        await store.synchronize()
        guard store.error == nil else { throw Failure(message: store.error!) }
        let second = try requireSnapshot(store)
        if first.pwaCommit == second.pwaCommit && first.awesome.commit == second.awesome.commit {
            try check(second.downloadedBytes == 0 && second.reusedFiles == second.files.count, "Unchanged live versions redownloaded data")
            try check(second.positions.map(\.id) == first.positions.map(\.id), "Unchanged live data altered positions")
        } else { print("LIVE note: upstream advanced between rounds; zero-byte assertion intentionally not applicable") }
        print("LIVE second: files=\(second.files.count) unique=\(second.positions.count) resources=\(second.resources.count) downloaded=\(second.downloadedBytes) reused=\(second.reusedFiles)")
        let offline = GitHubLibraryStore(directory: directory)
        await offline.load()
        guard offline.error == nil else { throw Failure(message: offline.error!) }
        let loaded = try requireSnapshot(offline)
        try check(loaded.pwaCommit == second.pwaCommit && loaded.positions.map(\.id) == second.positions.map(\.id), "Live archive offline reload mismatch")
        try check(loaded.resources.map(\.id) == second.resources.map(\.id), "Live resource union offline mismatch")
        print("LIVE offline: files=\(loaded.files.count) unique=\(loaded.positions.count) resources=\(loaded.resources.count) archive=\(store.archiveURL.path)")
    }

    /// A separate no-network check remains available during upstream rate limits.
    @MainActor static func offline(directory: URL) async throws {
        let store = GitHubLibraryStore(directory: directory)
        await store.load()
        guard store.error == nil else { throw Failure(message: store.error!) }
        let value = try requireSnapshot(store)
        let files = value.files.map(\.file) + [value.pwaIndexFile]
        let groups = Dictionary(grouping: files, by: \.sha)
        var cachedBytes = 0
        for (sha, aliases) in groups {
            let sizes = Set(aliases.map(\.size))
            try check(sizes.count == 1, "Same SHA cache aliases disagree on size: \(sha)")
            let blob = try GitHubLibraryStore.readBounded(store.objectDirectory.appendingPathComponent(sha + ".blob"), maximum: GitHubLibraryRemote.maximumFileBytes)
            try check(blob.count == aliases[0].size && GitHubLibraryRemote.blobSHA(blob) == sha, "Offline source object missing, truncated or corrupted: \(aliases[0].path)")
            cachedBytes += blob.count
        }
        print("OFFLINE: awesome=\(value.awesome.commit) pwa=\(value.pwaCommit) files=\(value.files.count) raw=\(value.rawCount) invalid=\(value.invalidCount) unique=\(value.positions.count) duplicates=\(value.duplicateCount) resources=\(value.resources.count) origins=\(value.positions.reduce(0) { $0 + $1.origins.count }) sourceBytes=\(value.sourceBytes) verifiedBlobs=\(groups.count) cachedBytes=\(cachedBytes) archive=\(store.archiveURL.path)")
    }
}
#endif
