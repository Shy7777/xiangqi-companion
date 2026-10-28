import Foundation

/// Imported snapshots are research material, never scored lessons or verified answers.
struct LibraryPosition: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let fen: String
    let title: String
    let category: String
    let sourceFile: String
    let importedAt: Date
    let originalResult: String?
    let originalBestMove: String?
    let originalTimestamp: String?
    let originalSource: String?

    var position: Position? { try? Position(fen: fen) }
}

struct PositionLibraryImportPreview: Identifiable, Sendable {
    let id: UUID
    let baseRevision: UUID
    let sourceFile: String
    let total: Int
    let duplicates: Int
    let invalid: Int
    let issues: [String]
    let entries: [LibraryPosition]
    var accepted: Int { entries.count }
}

enum PositionLibraryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

enum PositionLibraryImporter {
    static let maximumBytes = 8 * 1024 * 1024
    static let maximumItems = 10_000
    static let maximumStoredItems = 20_000
    static let maximumArchiveBytes = 32 * 1024 * 1024

    static func preview(data: Data, fileName: String, label: String, existingFENs: Set<String>,
                        revision: UUID, now: Date = Date()) throws -> PositionLibraryImportPreview {
        guard data.count <= maximumBytes else { throw PositionLibraryError.invalid("文件超过 8 MB，请拆成较小的局面包。") }
        guard let text = String(data: data, encoding: .utf8) else { throw PositionLibraryError.invalid("文件需要 UTF-8 编码。") }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        guard !content.isEmpty else { throw PositionLibraryError.invalid("文件为空，没有可导入的局面。") }
        let sourceFile = clean(fileName, limit: 255) ?? "本地文件"
        let category = clean(label, limit: 80) ?? clean((sourceFile as NSString).deletingPathExtension, limit: 80) ?? "未分类"
        let rawItems: [Any]
        if content.first == "[" || content.first == "{" {
            let json = try JSONSerialization.jsonObject(with: Data(content.utf8))
            if let array = json as? [Any] { rawItems = array }
            else if let object = json as? [String: Any], object["fen"] != nil { rawItems = [object] }
            else { throw PositionLibraryError.invalid("JSON 需要是含 fen 的条目数组或单个局面，不支持棋谱走子记录。") }
        } else {
            rawItems = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        guard !rawItems.isEmpty, rawItems.count <= maximumItems else {
            throw PositionLibraryError.invalid("每个文件需要 1–10,000 个局面。")
        }
        var seen = existingFENs, entries: [LibraryPosition] = [], duplicateCount = 0, invalidCount = 0, issues: [String] = []
        for (index, raw) in rawItems.enumerated() {
            if index % 64 == 0 { try Task.checkCancellation() }
            do {
                let item = raw as? [String: Any]
                guard let fen = item?["fen"] as? String ?? raw as? String, fen.count <= 256 else {
                    throw PositionLibraryError.invalid("缺少有效的 fen 字符串。")
                }
                let position = try Position(fen: fen)
                guard seen.insert(position.fen).inserted else { duplicateCount += 1; continue }
                let result = clean(item?["result"] as? String, limit: 500)
                let best = clean(item?["bestMove"] as? String, limit: 500)
                let source = clean(item?["sourceURL"] as? String ?? item?["source"] as? String, limit: 1_000)
                entries.append(LibraryPosition(id: UUID(), fen: position.fen,
                    title: clean(item?["name"] as? String ?? item?["title"] as? String, limit: 200) ?? "局面 \(index + 1)",
                    category: category, sourceFile: sourceFile, importedAt: now,
                    originalResult: result, originalBestMove: isPlaceholder(best) ? nil : best,
                    originalTimestamp: clean(item?["timestamp"] as? String ?? (item?["timestamp"] as? NSNumber)?.stringValue, limit: 120), originalSource: source))
            } catch is CancellationError { throw CancellationError() }
            catch {
                invalidCount += 1
                if issues.count < 12 { issues.append("第 \(index + 1) 项：\(error.localizedDescription)") }
            }
        }
        return PositionLibraryImportPreview(id: UUID(), baseRevision: revision, sourceFile: sourceFile,
            total: rawItems.count, duplicates: duplicateCount, invalid: invalidCount, issues: issues, entries: entries)
    }

    static func validate(_ entry: LibraryPosition) throws {
        guard entry.fen.count <= 256, try Position(fen: entry.fen).fen == entry.fen,
              !entry.title.isEmpty, entry.title.count <= 200, !entry.category.isEmpty, entry.category.count <= 80,
              !entry.sourceFile.isEmpty, entry.sourceFile.count <= 255,
              entry.originalResult.map({ $0.count <= 500 }) ?? true,
              entry.originalBestMove.map({ $0.count <= 500 }) ?? true,
              entry.originalTimestamp.map({ $0.count <= 120 }) ?? true,
              entry.originalSource.map({ $0.count <= 1_000 }) ?? true else {
            throw PositionLibraryError.invalid("局面库包含无效位置或超长元数据。")
        }
    }
    private static func clean(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
    }
    private static func isPlaceholder(_ value: String?) -> Bool {
        guard let value else { return true }
        return ["", "-", "--", "null", "none", "undefined", "egtb:", "需要查詢", "需要查询"]
            .contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
