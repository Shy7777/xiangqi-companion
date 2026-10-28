import Foundation
import CryptoKit

struct BookShelfEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let filename: String
    let recordCount: Int
    let importedAt: Date
    var originalFilename: String? = nil
}

struct BookRecordProgress: Codable, Equatable, Sendable {
    var nodeID = 0
    var read = false
    var bookmarked = false
    var attempts = 0
    var matched = 0
    var offBook = 0
    var hints = 0
    var lastVisited: Date?
}

struct BookShelfState: Codable, Sendable {
    var version = 1
    var entries: [BookShelfEntry] = []
    var lastBookID: String?
    var lastRecordByBook: [String: String] = [:]
    var progress: [String: BookRecordProgress] = [:]
}

enum BookLibraryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Private, user-owned books are not bundled into or redistributed with the app.
/// Only the original CBL and a small progress index are persisted: no expanded
/// JSON corpus, images, downloaded runtimes, or per-position disk caches.
struct BookLibraryStorage: Sendable {
    let directory: URL
    var indexURL: URL { directory.appendingPathComponent("shelf.json") }
    static let maximumFileBytes = 32 * 1024 * 1024
    static let maximumIndexBytes = 4 * 1024 * 1024

    init(directory: URL? = nil) {
        let override = ProcessInfo.processInfo.environment["XQ_COMPANION_STATE_DIR"]
        self.directory = directory ?? override.map { URL(fileURLWithPath: $0).appendingPathComponent("books", isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XiangqiCompanionOpenSource/books", isDirectory: true)
    }

    func load() throws -> BookShelfState {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return BookShelfState() }
        let bytes = try Self.readBounded(indexURL, maximum: Self.maximumIndexBytes)
        let state = try JSONDecoder().decode(BookShelfState.self, from: bytes)
        guard state.version == 1, state.entries.count <= 100,
              Set(state.entries.map(\.id)).count == state.entries.count,
              state.entries.allSatisfy({ Self.isSafeID($0.id) && $0.filename == $0.id + ".cbl" }) else {
            throw BookLibraryError.message("棋书索引格式不正确；原文件和学习记录未被覆盖。")
        }
        return state
    }

    func save(_ state: BookShelfState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(state)
        guard bytes.count <= Self.maximumIndexBytes else {
            throw BookLibraryError.message("棋书进度索引超出安全上限；已保留上次保存的文件。")
        }
        try bytes.write(to: indexURL, options: .atomic)
    }

    func url(for entry: BookShelfEntry) throws -> URL {
        guard Self.isSafeID(entry.id), entry.filename == entry.id + ".cbl" else {
            throw BookLibraryError.message("棋书文件名无效。")
        }
        return directory.appendingPathComponent(entry.filename)
    }

    func install(data: Data, document: BookDocument, state: BookShelfState) throws -> BookShelfState {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == document.sourceSHA256, Self.isSafeID(digest) else {
            throw BookLibraryError.message("棋书原始内容校验不一致，未导入。")
        }
        var next = state
        if !next.entries.contains(where: { $0.id == digest }) {
            guard next.entries.count < 100 else { throw BookLibraryError.message("书架已满，请先保留当前资料。") }
            next.entries.append(BookShelfEntry(id: digest, title: document.title, filename: digest + ".cbl",
                                              recordCount: document.records.count, importedAt: Date(), originalFilename: document.sourceFilename))
        }
        let destination = directory.appendingPathComponent(digest + ".cbl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Self.readBounded(destination) == data else {
                throw BookLibraryError.message("书架中的同名原件与导入内容不一致，未覆盖。")
            }
        } else {
            try data.write(to: destination, options: .atomic)
        }
        next.lastBookID = digest
        try save(next)
        return next
    }

    static func readBounded(_ url: URL, maximum: Int = maximumFileBytes) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, let count = size.fileSize, count > 0, count <= maximum else {
            throw BookLibraryError.message("请选择有效的棋书文件（单本不超过 \(maximum / 1024 / 1024) MB）。")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty, data.count <= maximum else { throw BookLibraryError.message("文件大小超出限制。") }
        return data
    }

    private static func isSafeID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
