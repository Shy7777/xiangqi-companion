import Foundation
import Combine
import CryptoKit

struct PositionLibraryExport: Sendable {
    let data: Data
    let count: Int
}

@MainActor
final class PositionLibraryStore: ObservableObject {
    @Published private(set) var entries: [LibraryPosition] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var isBusy = false
    @Published private(set) var error: String?
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("positions.json") }
    var previousFileURL: URL { directory.appendingPathComponent("positions.previous.json") }
    private var readOnly = false
    private var revision = UUID()
    private var previewTask: Task<PositionLibraryImportPreview, Error>?
    private var ticket = UUID()
    private var loadTask: Task<Loaded, Error>?
    private var fileDigest: String?

    private struct Archive: Codable, Sendable { var version = 1; let entries: [LibraryPosition] }
    private struct Loaded: Sendable { let entries: [LibraryPosition]; let digest: String? }

    init(directory: URL? = nil) {
        let state = ProcessInfo.processInfo.environment["XQ_COMPANION_STATE_DIR"]
        let base = state.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("XiangqiCompanionOpenSource", isDirectory: true)
        self.directory = directory ?? base.appendingPathComponent("position-library", isDirectory: true)
    }

    /// No filesystem access on application startup; only opening this workspace loads it.
    func loadIfNeeded() async {
        guard !isLoaded else { return }
        let url = fileURL
        if loadTask == nil {
            isBusy = true
            loadTask = Task.detached(priority: .userInitiated) {
                guard FileManager.default.fileExists(atPath: url.path) else { return Loaded(entries: [], digest: nil) }
                let bytes = try Self.readArchiveBytes(url)
                let archive = try JSONDecoder().decode(Archive.self, from: bytes)
                guard archive.version == 1 else { throw PositionLibraryError.invalid("不支持这个局面库版本。") }
                try Self.validate(archive.entries)
                return Loaded(entries: archive.entries, digest: Self.digest(bytes))
            }
        }
        guard let task = loadTask else { return }
        do {
            let loaded = try await task.value
            guard !isLoaded else { return }
            entries = loaded.entries; fileDigest = loaded.digest
        } catch {
            guard !isLoaded else { return }
            readOnly = true
            self.error = "局面库存档无法读取，已保留原文件且停止写入：\(error.localizedDescription)"
        }
        isLoaded = true; loadTask = nil; isBusy = false
    }

    func preview(data: Data, fileName: String, label: String, existingReferences: Set<String> = []) async throws -> PositionLibraryImportPreview {
        await loadIfNeeded()
        try Task.checkCancellation()
        guard !readOnly else { throw PositionLibraryError.invalid(error ?? "局面库只读。") }
        cancelPreview()
        let currentTicket = UUID(); ticket = currentTicket
        let seen = Set(entries.map(\.fen)).union(existingReferences), currentRevision = revision
        isBusy = true; error = nil
        let task = Task.detached(priority: .userInitiated) {
            try PositionLibraryImporter.preview(data: data, fileName: fileName, label: label,
                existingFENs: seen, revision: currentRevision)
        }
        previewTask = task
        defer { if ticket == currentTicket { previewTask = nil; isBusy = false } }
        let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        guard ticket == currentTicket, !Task.isCancelled else { throw CancellationError() }
        return result
    }

    func cancelPreview() { ticket = UUID(); previewTask?.cancel(); previewTask = nil; isBusy = false }

    /// Only call after the user confirms the displayed import summary.
    func commit(_ preview: PositionLibraryImportPreview) throws {
        guard isLoaded else { throw PositionLibraryError.invalid("请先载入局面库并预览文件。") }
        guard !readOnly else { throw PositionLibraryError.invalid(error ?? "局面库只读。") }
        guard preview.baseRevision == revision else { throw PositionLibraryError.invalid("局面库已经变化，请重新预览再确认。") }
        guard !preview.entries.isEmpty else { throw PositionLibraryError.invalid("没有新的有效局面可保存。") }
        try persist(entries + preview.entries)
    }

    /// Removes only a personal snapshot. Built-in references and original files are untouched.
    func remove(id: UUID) throws {
        guard entries.contains(where: { $0.id == id }) else { throw PositionLibraryError.invalid("这不是个人导入局面，不能移除本机课程引用。") }
        try persist(entries.filter { $0.id != id })
    }

    /// Each exported PWA-compatible JSON array is within the import byte/count limits.
    /// No built-in curriculum references enter this store or these exports.
    func exportBatches() throws -> [PositionLibraryExport] {
        guard isLoaded, !readOnly else { throw PositionLibraryError.invalid(error ?? "请先读取局面库。") }
        var result: [PositionLibraryExport] = [], batch = Data("[".utf8), count = 0
        let formatter = ISO8601DateFormatter()
        for entry in entries {
            var item: [String: String] = ["fen": entry.fen, "name": entry.title, "category": entry.category,
                "sourceFile": entry.sourceFile, "importedAt": formatter.string(from: entry.importedAt)]
            item["result"] = entry.originalResult; item["bestMove"] = entry.originalBestMove
            item["timestamp"] = entry.originalTimestamp; item["source"] = entry.originalSource
            let bytes = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys])
            if count > 0 && (count == PositionLibraryImporter.maximumItems || batch.count + bytes.count + 2 > PositionLibraryImporter.maximumBytes) {
                batch.append(93); result.append(PositionLibraryExport(data: batch, count: count)); batch = Data("[".utf8); count = 0
            }
            if count > 0 { batch.append(44) }
            batch.append(bytes); count += 1
        }
        if count > 0 { batch.append(93); result.append(PositionLibraryExport(data: batch, count: count)) }
        return result
    }

    private func persist(_ combined: [LibraryPosition]) throws {
        guard isLoaded, !readOnly else { throw PositionLibraryError.invalid(error ?? "局面库尚未读取或不可写。") }
        try Self.validate(combined)
        let prior = FileManager.default.fileExists(atPath: fileURL.path) ? try Self.readArchiveBytes(fileURL) : nil
        guard prior.map(Self.digest) == fileDigest else { throw PositionLibraryError.invalid("磁盘上的局面库已被修改，请重新打开局面库再操作，避免覆盖较新的数据。") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Archive(entries: combined))
        guard bytes.count <= PositionLibraryImporter.maximumArchiveBytes else { throw PositionLibraryError.invalid("局面库存档超过 32 MB 上限。") }
        // A failed write leaves the old file and published in-memory records unchanged.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let prior { try prior.write(to: previousFileURL, options: .atomic) }
        try bytes.write(to: fileURL, options: .atomic)
        entries = combined; fileDigest = Self.digest(bytes); revision = UUID(); error = nil
    }

    nonisolated private static func readArchiveBytes(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: PositionLibraryImporter.maximumArchiveBytes + 1) ?? Data()
        guard bytes.count <= PositionLibraryImporter.maximumArchiveBytes else { throw PositionLibraryError.invalid("局面库存档过大。") }
        return bytes
    }
    nonisolated private static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    nonisolated private static func validate(_ values: [LibraryPosition]) throws {
        guard values.count <= PositionLibraryImporter.maximumStoredItems,
              Set(values.map(\.id)).count == values.count, Set(values.map(\.fen)).count == values.count else {
            throw PositionLibraryError.invalid("局面库超过 20,000 项，或包含重复编号/局面。")
        }
        for value in values { try PositionLibraryImporter.validate(value) }
    }
}
