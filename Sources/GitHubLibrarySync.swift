import Foundation
import Combine
import CryptoKit
import Darwin

enum GitHubLibraryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct GitHubDataFile: Codable, Equatable, Sendable {
    let path: String
    let sha: String
    let size: Int
}

struct SyncedPositionOrigin: Codable, Equatable, Sendable {
    let file: String
    let item: PWARawPosition
}

struct SyncedPosition: Codable, Identifiable, Sendable {
    let id: String
    let fen: String
    var origins: [SyncedPositionOrigin]
    var title: String { origins.first?.item.title ?? "未命名局面" }
    var categories: [String] { Array(Set(origins.map { $0.item.category })).sorted() }
    var searchText: String { origins.map { $0.item.title + " " + $0.item.category + " " + $0.file }.joined(separator: " ") }
    var position: Position? { try? Position(fen: fen) }
    static func identifier(_ fen: String) -> String { SHA256.hash(data: Data(fen.utf8)).map { String(format: "%02x", $0) }.joined() }
}

struct SyncedFileReport: Codable, Sendable {
    let file: GitHubDataFile
    let total: Int
    let invalid: Int
    let issues: [String]
}

struct GitHubLibrarySnapshot: Codable, Sendable {
    var version = 1
    let awesome: AwesomeResourceIndex
    let pwaCommit: String
    let pwaIndexFile: GitHubDataFile
    let pwaResources: [PWAWebResource]
    let syncedAt: Date
    let files: [SyncedFileReport]
    let positions: [SyncedPosition]
    let downloadedBytes: Int
    let reusedFiles: Int
    var rawCount: Int { files.reduce(0) { $0 + $1.total } }
    var invalidCount: Int { files.reduce(0) { $0 + $1.invalid } }
    var duplicateCount: Int { rawCount - invalidCount - positions.count }
    var sourceBytes: Int { files.reduce(0) { $0 + $1.file.size } }
    var categories: [String] { Array(Set(positions.flatMap(\.categories))).sorted() }
    var resources: [SyncedWebResource] { SyncedWebResource.merge(awesome: awesome, pwa: pwaResources, pwaCommit: pwaCommit) }
    var objectHashes: Set<String> { Set(files.map { $0.file.sha } + [pwaIndexFile.sha]) }
}

/// Only these two explicit public repositories are synchronized. No credentials,
/// user records, images, arbitrary links, scripts or remote code enter this client.
enum GitHubLibraryRemote {
    static let awesomeRepo = "lucaferranti/awesome-xiangqi"
    static let pwaRepo = "dffge552/xiangqi-pwa-offline"
    static let maximumFileBytes = 8 * 1024 * 1024
    static let maximumSourceBytes = 32 * 1024 * 1024
    static let maximumArchiveBytes = 48 * 1024 * 1024
    static let maximumFiles = 1_000
    static let maximumPositions = 50_000
    static let maximumOrigins = 100_000

    struct Tree: Decodable, Sendable {
        let truncated: Bool
        let tree: [Item]
        struct Item: Decodable, Sendable { let path: String; let type: String; let sha: String; let size: Int? }
    }
    private struct Commit: Decodable { let sha: String }
    typealias Fetch = @Sendable (URL, Int) async throws -> Data

    static func validSHA(_ value: String) -> Bool {
        value.count == 40 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func blobSHA(_ data: Data) -> String {
        var bytes = Data("blob \(data.count)\0".utf8); bytes.append(data)
        return Insecure.SHA1.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func rawURL(repo: String, commit: String, path: String) throws -> URL {
        guard [awesomeRepo, pwaRepo].contains(repo), validSHA(commit), !path.isEmpty,
              !path.hasPrefix("/"), !path.contains("\\"), !path.components(separatedBy: "/").contains(".."),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw GitHubLibraryError.invalid("上游文件地址不合法。")
        }
        return URL(string: "https://raw.githubusercontent.com/\(repo)/\(commit)/")!.appendingPathComponent(path)
    }
    static func latestCommit(repo: String, fetch: Fetch) async throws -> String {
        guard [awesomeRepo, pwaRepo].contains(repo) else { throw GitHubLibraryError.invalid("不支持此资料仓库。") }
        let url = URL(string: "https://api.github.com/repos/\(repo)/commits/main")!
        let value = try JSONDecoder().decode(Commit.self, from: await fetch(url, 2 * 1024 * 1024))
        guard validSHA(value.sha) else { throw GitHubLibraryError.invalid("GitHub 未返回有效版本。") }
        // Review the license attached to the exact revision before using its
        // content. A changed license requires an explicit maintainer review.
        let license = try await fetch(rawURL(repo: repo, commit: value.sha, path: "LICENSE"), 64 * 1024)
        try validateLicense(license, repository: repo)
        return value.sha
    }
    static func validateLicense(_ data: Data, repository: String) throws {
        let expected: String
        switch repository {
        case awesomeRepo: expected = "6be3b7507d71bbe066974ab1dbfd01ef1b33c9f7c7995a8df0402ad6361872dd"
        case pwaRepo: expected = "7419e5e47154db9e6ceb915093bdbbf16f0fbfcbb9030a4698769be47f909077"
        default: throw GitHubLibraryError.invalid("未审核的资料仓库。")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw GitHubLibraryError.invalid("上游许可不是有效 UTF-8。")
        }
        let normalized = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let digest = SHA256.hash(data: normalized).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else {
            throw GitHubLibraryError.invalid("上游许可文本已变化或无法核对，已停止同步并保留旧资料。请等待新版核验许可。")
        }
    }
    static func dataFiles(tree: Data) throws -> [GitHubDataFile] {
        let decoded = try JSONDecoder().decode(Tree.self, from: tree)
        guard !decoded.truncated else { throw GitHubLibraryError.invalid("GitHub 文件列表不完整，保留旧资料，请稍后重试。") }
        let files = try decoded.tree.filter { $0.type == "blob" && PWADataParser.isDataPath($0.path) }.map { item in
            guard validSHA(item.sha), let size = item.size, size > 0, size <= maximumFileBytes else {
                throw GitHubLibraryError.invalid("上游文件尺寸或指纹异常：\(item.path)")
            }
            return GitHubDataFile(path: item.path, sha: item.sha, size: size)
        }.sorted { $0.path < $1.path }
        guard !files.isEmpty, files.count <= maximumFiles, Set(files.map(\.path)).count == files.count,
              Dictionary(grouping: files, by: \.sha).values.allSatisfy({ Set($0.map(\.size)).count == 1 }),
              files.reduce(0, { $0 + $1.size }) <= maximumSourceBytes else {
            throw GitHubLibraryError.invalid("题库列表为空、重复或超过 32 MiB 同步上限；旧资料不变。")
        }
        return files
    }
    static func indexFile(tree: Data) throws -> GitHubDataFile {
        let decoded = try JSONDecoder().decode(Tree.self, from: tree)
        let files = decoded.tree.filter { $0.type == "blob" && $0.path == "index.html" }
        guard !decoded.truncated, files.count == 1, let item = files.first, validSHA(item.sha),
              let size = item.size, size > 0, size <= maximumFileBytes else {
            throw GitHubLibraryError.invalid("PWA 资源目录源文件不完整，未替换已有目录。")
        }
        return GitHubDataFile(path: item.path, sha: item.sha, size: size)
    }
    static func group(_ sources: [PWASourceFile]) throws -> [SyncedPosition] {
        var items: [SyncedPosition] = [], indices: [String: Int] = [:], origins = 0
        for source in sources {
            for item in source.positions {
                if origins % 128 == 0 { try Task.checkCancellation() }
                origins += 1
                guard origins <= maximumOrigins else { throw GitHubLibraryError.invalid("上游条目超过同步容量。") }
                let origin = SyncedPositionOrigin(file: source.path, item: item)
                if let index = indices[item.fen] { items[index].origins.append(origin) }
                else {
                    guard items.count < maximumPositions else { throw GitHubLibraryError.invalid("不同局面超过同步容量。") }
                    indices[item.fen] = items.count
                    items.append(SyncedPosition(id: SyncedPosition.identifier(item.fen), fen: item.fen, origins: [origin]))
                }
            }
        }
        return items
    }

    /// Bounded streaming keeps a changed remote response from allocating an
    /// unbounded Data value. Ephemeral session does not write a second URL cache.
    static func fetch(_ url: URL, maximumBytes: Int) async throws -> Data {
        guard url.scheme == "https", ["api.github.com", "raw.githubusercontent.com"].contains(url.host),
              maximumBytes > 0, maximumBytes <= maximumFileBytes else { throw GitHubLibraryError.invalid("拒绝非上游数据请求。") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("XiangqiCompanion-LocalLibrary/2.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let final = http.url, final.scheme == "https", ["api.github.com", "raw.githubusercontent.com"].contains(final.host) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GitHubLibraryError.invalid(status == 403 || status == 429 ? "GitHub 暂时限流，已有离线资料仍可用。" : "资料请求失败（\(status)），已有资料不变。")
        }
        guard response.expectedContentLength <= maximumBytes else { throw GitHubLibraryError.invalid("上游响应超出文件大小限制。") }
        var bytes = Data(); bytes.reserveCapacity(min(maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in stream {
            if bytes.count % 65_536 == 0 { try Task.checkCancellation() }
            guard bytes.count < maximumBytes else { throw GitHubLibraryError.invalid("上游响应超过大小限制。") }
            bytes.append(byte)
        }
        return bytes
    }
}

@MainActor final class GitHubLibraryStore: ObservableObject {
    @Published private(set) var snapshot: GitHubLibrarySnapshot?
    @Published private(set) var isLoaded = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = "同步两个 GitHub 的完整目录和局面数据"
    @Published private(set) var completedFiles = 0
    @Published private(set) var totalFiles = 0
    @Published private(set) var error: String?
    let directory: URL
    var archiveURL: URL { directory.appendingPathComponent("library.json") }
    var objectDirectory: URL { directory.appendingPathComponent("objects", isDirectory: true) }
    private var syncTask: Task<Void, Never>?
    private var loadTask: Task<(GitHubLibrarySnapshot, String)?, Error>?
    private var ticket = UUID()
    private var storedDigest: String?
    private var readOnly = false

    init(directory: URL? = nil) {
        let base = ProcessInfo.processInfo.environment["XQ_COMPANION_STATE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("XiangqiCompanionOpenSource", isDirectory: true)
        self.directory = directory ?? base.appendingPathComponent("github-library", isDirectory: true)
    }

    func load() async {
        guard !isLoaded else { return }
        let url = archiveURL
        if loadTask == nil {
            loadTask = Task.detached(priority: .userInitiated) {
                try Self.safeDirectory(url.deletingLastPathComponent(), create: false)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let data = try Self.readBounded(url, maximum: GitHubLibraryRemote.maximumArchiveBytes)
                let value = try JSONDecoder().decode(GitHubLibrarySnapshot.self, from: data)
                try Self.validate(value)
                return (value, Self.digest(data))
            }
        }
        do {
            let value = try await loadTask!.value
            guard !isLoaded else { return }
            snapshot = value?.0
            storedDigest = value?.1
            status = value.map { "\($0.0.resources.count) 项资源 · \($0.0.positions.count) 个不同局面" } ?? "还未同步"
        } catch {
            readOnly = true; self.error = "同步资料无法读取，原文件保留：\(error.localizedDescription)"
        }
        isLoaded = true; loadTask = nil
    }

    func startSync(fetch: @escaping GitHubLibraryRemote.Fetch = { url, limit in try await GitHubLibraryRemote.fetch(url, maximumBytes: limit) }) {
        guard !isBusy, syncTask == nil else { return }
        syncTask = Task { defer { syncTask = nil }; await synchronize(fetch: fetch) }
    }
    func cancel() { syncTask?.cancel(); status = "正在取消；已完成同步的资料保留" }

    func synchronize(fetch: @escaping GitHubLibraryRemote.Fetch = { url, limit in try await GitHubLibraryRemote.fetch(url, maximumBytes: limit) }) async {
        await load()
        guard !isBusy, !readOnly, !Task.isCancelled else { return }
        let currentTicket = UUID(); ticket = currentTicket; isBusy = true; error = nil
        completedFiles = 0; totalFiles = 0; status = "核对两个仓库的最新版本…"
        defer { if ticket == currentTicket { isBusy = false } }
        var lockFD: Int32 = -1
        defer { if lockFD >= 0 { _ = flock(lockFD, LOCK_UN); _ = close(lockFD) } }
        do {
            try Self.safeDirectory(directory, create: true)
            lockFD = open(directory.appendingPathComponent("sync.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
                if lockFD >= 0 { _ = close(lockFD); lockFD = -1 }
                throw GitHubLibraryError.invalid("另一个窗口正在同步，请等待它完成。")
            }
            async let awesomeVersion = GitHubLibraryRemote.latestCommit(repo: GitHubLibraryRemote.awesomeRepo, fetch: fetch)
            async let pwaVersion = GitHubLibraryRemote.latestCommit(repo: GitHubLibraryRemote.pwaRepo, fetch: fetch)
            let (awesomeCommit, pwaCommit) = try await (awesomeVersion, pwaVersion)
            try checkTicket(currentTicket)
            let treeURL = URL(string: "https://api.github.com/repos/\(GitHubLibraryRemote.pwaRepo)/git/trees/\(pwaCommit)?recursive=1")!
            let treeBytes = try await fetch(treeURL, 3 * 1024 * 1024)
            let files = try GitHubLibraryRemote.dataFiles(tree: treeBytes)
            let pwaIndexFile = try GitHubLibraryRemote.indexFile(tree: treeBytes)
            totalFiles = files.count
            let index: AwesomeResourceIndex
            var downloadedBytes = 0
            if let old = snapshot?.awesome, old.commit == awesomeCommit { index = old }
            else {
                let readme = try await fetch(GitHubLibraryRemote.rawURL(repo: GitHubLibraryRemote.awesomeRepo, commit: awesomeCommit, path: "README.md"), 1024 * 1024)
                guard let text = String(data: readme, encoding: .utf8) else { throw GitHubLibraryError.invalid("资源目录不是有效 UTF-8。") }
                index = try AwesomeResourceIndex.parse(markdown: text, commit: awesomeCommit, fetchedAt: Date())
                downloadedBytes += readme.count
            }
            let objects = objectDirectory
            try Self.safeDirectory(objects, create: true)
            // Also discard objects left by an interrupted previous process. The
            // held lock prevents deleting another active download's work.
            pruneObjects(keeping: snapshot?.objectHashes ?? [])
            let htmlURL = objects.appendingPathComponent(pwaIndexFile.sha + ".blob")
            let html: Data
            if let saved = try? Self.readBounded(htmlURL, maximum: GitHubLibraryRemote.maximumFileBytes),
               saved.count == pwaIndexFile.size, GitHubLibraryRemote.blobSHA(saved) == pwaIndexFile.sha { html = saved }
            else {
                html = try await fetch(GitHubLibraryRemote.rawURL(repo: GitHubLibraryRemote.pwaRepo, commit: pwaCommit, path: "index.html"), GitHubLibraryRemote.maximumFileBytes)
                guard html.count == pwaIndexFile.size, GitHubLibraryRemote.blobSHA(html) == pwaIndexFile.sha else { throw GitHubLibraryError.invalid("PWA 资源页指纹不一致。") }
                downloadedBytes += html.count
            }
            guard let htmlText = String(data: html, encoding: .utf8) else { throw GitHubLibraryError.invalid("PWA 资源页不是有效 UTF-8。") }
            let pwaResources = try PWADataParser.parseResources(html: htmlText)
            try Task.checkCancellation()
            try html.write(to: htmlURL, options: .atomic)
            var sources: [PWASourceFile] = [], reports: [SyncedFileReport] = [], reused = 0
            // Fetch each unique blob once, retaining every path as a provenance.
            let groups = Dictionary(grouping: files, by: \.sha).values.map { $0.sorted { $0.path < $1.path } }.sorted { $0[0].path < $1[0].path }
            var iterator = groups.makeIterator()
            try await withThrowingTaskGroup(of: ([PWASourceFile], [SyncedFileReport], Int, Int).self) { group in
                func submit(_ sameBlob: [GitHubDataFile]) {
                    group.addTask {
                        let file = sameBlob[0], objectURL = objects.appendingPathComponent(file.sha + ".blob")
                        let data: Data; let cached: Bool
                        if let saved = try? Self.readBounded(objectURL, maximum: GitHubLibraryRemote.maximumFileBytes),
                           saved.count == file.size, GitHubLibraryRemote.blobSHA(saved) == file.sha { data = saved; cached = true }
                        else {
                            data = try await fetch(GitHubLibraryRemote.rawURL(repo: GitHubLibraryRemote.pwaRepo, commit: pwaCommit, path: file.path), GitHubLibraryRemote.maximumFileBytes)
                            guard data.count == file.size, GitHubLibraryRemote.blobSHA(data) == file.sha else { throw GitHubLibraryError.invalid("文件指纹不一致，未采用：\(file.path)") }
                            cached = false
                        }
                        var parsed: [PWASourceFile] = [], summaries: [SyncedFileReport] = []
                        for alias in sameBlob {
                            let source = try PWADataParser.parse(data: data, path: alias.path)
                            parsed.append(source)
                            summaries.append(SyncedFileReport(file: alias, total: source.total, invalid: source.invalid, issues: source.issues))
                        }
                        try Task.checkCancellation()
                        if !cached { try data.write(to: objectURL, options: .atomic) }
                        return (parsed, summaries, cached ? 0 : data.count, cached ? sameBlob.count : sameBlob.count - 1)
                    }
                }
                for _ in 0..<4 { if let next = iterator.next() { submit(next) } }
                while let result = try await group.next() {
                    try checkTicket(currentTicket)
                    sources += result.0; reports += result.1; downloadedBytes += result.2; reused += result.3
                    completedFiles += result.1.count
                    status = "同步局面 \(completedFiles) / \(totalFiles)"
                    if let next = iterator.next() { submit(next) }
                }
            }
            try checkTicket(currentTicket)
            status = "合并重复局面，保留全部分类与出处…"
            let ordered = sources.sorted { $0.path < $1.path }
            let positions = try await Task.detached(priority: .userInitiated) { try GitHubLibraryRemote.group(ordered) }.value
            let next = GitHubLibrarySnapshot(awesome: index, pwaCommit: pwaCommit, pwaIndexFile: pwaIndexFile, pwaResources: pwaResources, syncedAt: Date(),
                files: reports.sorted { $0.file.path < $1.file.path }, positions: positions, downloadedBytes: downloadedBytes, reusedFiles: reused)
            try checkTicket(currentTicket)
            try Self.validate(next)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(next)
            guard bytes.count <= GitHubLibraryRemote.maximumArchiveBytes else { throw GitHubLibraryError.invalid("同步索引超出容量，保留旧资料。") }
            guard try currentDigest() == storedDigest else { throw GitHubLibraryError.invalid("另一窗口已更新本机资料，请重新打开后同步。") }
            try bytes.write(to: archiveURL, options: .atomic)
            snapshot = next; storedDigest = Self.digest(bytes)
            pruneObjects(keeping: next.objectHashes)
            status = "已同步 \(next.resources.count) 项资源 · \(positions.count) 个不同局面"
        } catch {
            if ticket == currentTicket {
                if error is CancellationError { status = "已取消；已有资料保留" }
                else { self.error = error.localizedDescription; status = "更新未完成；已有资料仍可使用" }
                // Failed/cancelled updates cannot accumulate unreferenced download objects.
                if lockFD >= 0 { pruneObjects(keeping: snapshot?.objectHashes ?? []) }
            }
        }
    }

    nonisolated static func validate(_ value: GitHubLibrarySnapshot) throws {
        // Validate each integer before any derived sum. A corrupt but valid JSON
        // Int.max must be rejected, never overflow during launch-time loading.
        guard value.files.count <= GitHubLibraryRemote.maximumFiles,
              value.files.allSatisfy({ report in
                  report.file.size > 0 && report.file.size <= GitHubLibraryRemote.maximumFileBytes
                      && report.total >= 0 && report.total <= PWADataParser.maximumItems
                      && report.invalid >= 0 && report.invalid <= report.total
                      && report.issues.count <= 12 && report.issues.allSatisfy { $0.count <= 2_048 }
              }) else { throw GitHubLibraryError.invalid("同步文件统计超过合法范围。") }
        guard value.version == 1, GitHubLibraryRemote.validSHA(value.pwaCommit), GitHubLibraryRemote.validSHA(value.awesome.commit),
              value.awesome.version == 1, !value.awesome.items.isEmpty, value.awesome.items.count <= 5_000,
              !value.files.isEmpty, value.files.count <= GitHubLibraryRemote.maximumFiles, value.positions.count <= GitHubLibraryRemote.maximumPositions,
              value.sourceBytes <= GitHubLibraryRemote.maximumSourceBytes,
              value.pwaIndexFile.path == "index.html", GitHubLibraryRemote.validSHA(value.pwaIndexFile.sha),
              value.pwaIndexFile.size > 0, value.pwaIndexFile.size <= GitHubLibraryRemote.maximumFileBytes,
              !value.pwaResources.isEmpty, value.pwaResources.count <= 500,
              Set(value.pwaResources.map(\.id)).count == value.pwaResources.count,
              value.downloadedBytes >= 0, value.reusedFiles >= 0, value.reusedFiles <= value.files.count,
              value.syncedAt.timeIntervalSince1970.isFinite,
              Set(value.files.map { $0.file.path }).count == value.files.count,
              Set(value.positions.map(\.id)).count == value.positions.count,
              value.rawCount >= value.invalidCount + value.positions.count, value.invalidCount >= 0 else {
            throw GitHubLibraryError.invalid("同步索引结构或统计无效。")
        }
        let paths = Set(value.files.map { $0.file.path })
        let totals = Dictionary(uniqueKeysWithValues: value.files.map { ($0.file.path, $0.total) })
        var originCount = 0
        var originIDs = Set<String>(), counts: [String: Int] = [:]
        for report in value.files {
            guard PWADataParser.isDataPath(report.file.path), GitHubLibraryRemote.validSHA(report.file.sha),
                  report.file.size > 0, report.file.size <= GitHubLibraryRemote.maximumFileBytes,
                  report.total >= report.invalid, report.invalid >= 0 else { throw GitHubLibraryError.invalid("同步文件索引异常。") }
        }
        for item in value.awesome.items {
            guard ["http", "https"].contains(item.url.scheme?.lowercased() ?? ""), item.url.host != nil else { throw GitHubLibraryError.invalid("目录链接协议不合法。") }
        }
        for item in value.pwaResources {
            guard let url = URL(string: item.url), ["http", "https"].contains(url.scheme), url.host != nil,
                  url.user == nil, url.password == nil, item.id == item.url, item.sourceLine > 0,
                  item.title.count <= 256, item.url.utf8.count <= 8_192 else { throw GitHubLibraryError.invalid("PWA 资源链接不合法。") }
        }
        for position in value.positions {
            originCount += position.origins.count
            guard originCount <= GitHubLibraryRemote.maximumOrigins, !position.origins.isEmpty,
                  position.id == SyncedPosition.identifier(position.fen), try Position(fen: position.fen).fen == position.fen,
                  position.origins.allSatisfy({ paths.contains($0.file) && $0.item.fen == position.fen && $0.item.index > 0 }) else {
                throw GitHubLibraryError.invalid("同步索引包含无效局面或失效出处。")
            }
            for origin in position.origins {
                guard origin.item.index <= (totals[origin.file] ?? 0),
                      originIDs.insert(origin.file + "\0" + String(origin.item.index)).inserted,
                      origin.item.title.count <= 256, origin.item.category.count <= 256,
                      (origin.item.bestMove?.count ?? 0) <= 2_000, (origin.item.result?.count ?? 0) <= 2_000 else {
                    throw GitHubLibraryError.invalid("同步出处重复或超出原文件范围。")
                }
                counts[origin.file, default: 0] += 1
            }
        }
        guard originCount == value.rawCount - value.invalidCount else { throw GitHubLibraryError.invalid("同步条目数量不一致。") }
        guard value.files.allSatisfy({ counts[$0.file.path, default: 0] == $0.total - $0.invalid }) else { throw GitHubLibraryError.invalid("逐文件来源统计不一致。") }
    }
    private func checkTicket(_ expected: UUID) throws { try Task.checkCancellation(); if ticket != expected { throw CancellationError() } }
    nonisolated static func readBounded(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size <= maximum else { throw GitHubLibraryError.invalid("同步文件类型或大小不正确。") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw GitHubLibraryError.invalid("同步文件过大。") }
        return data
    }
    nonisolated private static func safeDirectory(_ url: URL, create: Bool) throws {
        if !FileManager.default.fileExists(atPath: url.path), create { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        // A missing first-run directory is fine for a read-only load.
        if !create, !FileManager.default.fileExists(atPath: url.path) { return }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw GitHubLibraryError.invalid("同步目录被替换或不是普通文件夹，停止读写以保护数据。") }
    }
    nonisolated private static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private func currentDigest() throws -> String? {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return nil }
        return Self.digest(try Self.readBounded(archiveURL, maximum: GitHubLibraryRemote.maximumArchiveBytes))
    }
    /// Only content-addressed files in this service's private cache are removable.
    private func pruneObjects(keeping hashes: Set<String>) {
        guard (try? Self.safeDirectory(directory, create: false)) != nil,
              (try? Self.safeDirectory(objectDirectory, create: false)) != nil else { return }
        var protected = hashes
        // Another store may have loaded an older snapshot before obtaining the
        // lock. Never remove blobs referenced by the currently committed file.
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            guard let data = try? Self.readBounded(archiveURL, maximum: GitHubLibraryRemote.maximumArchiveBytes),
                  let current = try? JSONDecoder().decode(GitHubLibrarySnapshot.self, from: data),
                  (try? Self.validate(current)) != nil else { return }
            protected.formUnion(current.objectHashes)
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: objectDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return }
        for url in files {
            let hash = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "blob", GitHubLibraryRemote.validSHA(hash), !protected.contains(hash),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
