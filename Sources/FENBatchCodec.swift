import Foundation

struct FENBatchResult: Sendable {
    let total: Int
    let accepted: Int
    let invalid: Int
    let duplicates: Int
    let issues: [String]
    /// PWA-compatible [{fen,name,...original metadata}]. Only validated positions.
    let jsonData: Data
    /// Canonical six-field FEN, one position per line; titles intentionally omitted.
    let fenText: String
    /// Canonical FEN plus a title, one position per line; accepted by this codec.
    let namedFENText: String
}

enum FENBatchError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let value) = self { return value }; return nil }
}

/// A local, non-persisting data conversion. No engine commands, URLs, or source
/// annotations are executed; an original bestMove never becomes an answer key.
enum FENBatchCodec {
    static let maximumBytes = 8 * 1_024 * 1_024
    static let maximumItems = 10_000
    private struct Candidate {
        let location: String
        var fen: String?
        var title: String?
        var metadata: [String: Any] = [:]
        var problem: String?
    }

    static func convert(text: String) throws -> FENBatchResult {
        guard text.utf8.count <= maximumBytes else { throw FENBatchError.invalid("输入超过 8 MiB，请分批转换。") }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        guard !content.isEmpty else { throw FENBatchError.invalid("请粘贴 JSON，或带行棋方的 FEN；题名可放同一行或下一行。") }
        let candidates: [Candidate]
        if content.first == "[" || content.first == "{" {
            let json = try JSONSerialization.jsonObject(with: Data(content.utf8))
            let items: [Any]
            if let array = json as? [Any] { items = array }
            else if let item = json as? [String: Any], item["fen"] != nil { items = [item] }
            else { throw FENBatchError.invalid("JSON 应为含 fen 的条目数组或单个局面对象，不是目录或棋谱历史。") }
            guard !items.isEmpty, items.count <= maximumItems else { throw FENBatchError.invalid("每批需要 1–10,000 个局面。") }
            candidates = items.enumerated().map { index, item in
                let values = item as? [String: Any]
                let fen = values?["fen"] as? String ?? item as? String
                let title = ["name", "title", "typeFull", "type"].compactMap { values?[$0] as? String }
                    .map(cleanTitle).first(where: { !$0.isEmpty })
                return Candidate(location: "第 \(index + 1) 项", fen: fen, title: title, metadata: values ?? [:],
                    problem: fen == nil ? "缺少字符串 fen" : nil)
            }
        } else {
            candidates = try readLines(content)
        }
        guard candidates.count <= maximumItems else { throw FENBatchError.invalid("每批最多 10,000 个局面。") }
        var seen = Set<String>(), output: [[String: Any]] = []
        var fens: [String] = [], named: [String] = [], issues: [String] = []
        var invalid = 0, duplicates = 0
        for (offset, candidate) in candidates.enumerated() {
            if offset.isMultiple(of: 64) { try Task.checkCancellation() }
            do {
                if let problem = candidate.problem { throw FENBatchError.invalid(problem) }
                guard let fen = candidate.fen, fen.utf8.count <= 512 else { throw FENBatchError.invalid("缺少 FEN 或 FEN 过长") }
                // Require an explicit side; never silently turn a pasted puzzle into red-to-move.
                let parts = fen.split(whereSeparator: { $0.isWhitespace })
                guard parts.count == 2 || parts.count == 6 else { throw FENBatchError.invalid("FEN 需要明确 w/r（红）或 b（黑）行棋方") }
                let position = try Position(fen: fen)
                guard seen.insert(position.fen).inserted else { duplicates += 1; continue }
                let title = candidate.title.map(cleanTitle).flatMap { $0.isEmpty ? nil : $0 } ?? "局面 \(offset + 1)"
                var entry = candidate.metadata
                entry["fen"] = position.fen; entry["name"] = title
                output.append(entry); fens.append(position.fen); named.append(position.fen + " " + title)
            } catch is CancellationError { throw CancellationError() }
            catch {
                invalid += 1
                if issues.count < 12 { issues.append("\(candidate.location)：\(String(error.localizedDescription.prefix(256)))") }
            }
        }
        let jsonData = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        guard jsonData.count <= maximumBytes else { throw FENBatchError.invalid("转换后的 JSON 超过 8 MiB，请减少本批条目。") }
        return FENBatchResult(total: candidates.count, accepted: output.count, invalid: invalid, duplicates: duplicates,
            issues: issues, jsonData: jsonData, fenText: fens.joined(separator: "\n"), namedFENText: named.joined(separator: "\n"))
    }

    private static func readLines(_ text: String) throws -> [Candidate] {
        var result: [Candidate] = [], pending: Candidate?
        for (offset, raw) in text.components(separatedBy: .newlines).enumerated() {
            if offset.isMultiple(of: 64) { try Task.checkCancellation() }
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let first = line.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            let looksLikeBoard = first.filter { $0 == "/" }.count >= 2
                && first.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "/") }
            if looksLikeBoard {
                if let current = pending { result.append(current) }
                pending = splitFENLine(line, location: "第 \(offset + 1) 行")
                if pending?.title != nil { result.append(pending!); pending = nil }
            } else if var current = pending, current.title == nil {
                current.title = cleanTitle(line); result.append(current); pending = nil
            } else {
                result.append(Candidate(location: "第 \(offset + 1) 行", problem: "题名前没有 FEN，或这一行不是局面"))
            }
            guard result.count + (pending == nil ? 0 : 1) <= maximumItems else { throw FENBatchError.invalid("每批最多 10,000 个局面。") }
        }
        if let current = pending { result.append(current) }
        return result
    }

    private static func splitFENLine(_ line: String, location: String) -> Candidate {
        var fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 2 else { return Candidate(location: location, problem: "FEN 缺少行棋方") }
        // The upstream converter also accepts “board w中文题名”; only Chinese/non-ASCII
        // attached titles are accepted, so “white” cannot silently become side w.
        if let side = fields[1].first, ["w", "r", "b"].contains(String(side)), fields[1].count > 1 {
            let suffix = String(fields[1].dropFirst())
            if suffix.first?.isASCII == false { fields[1] = String(side); fields.insert(suffix, at: 2) }
        }
        guard ["w", "r", "b"].contains(fields[1]) else { return Candidate(location: location, problem: "行棋方应为 w/r（红）或 b（黑）") }
        let fenCount: Int
        if fields.count > 2 && fields[2] == "-" {
            guard fields.count >= 6 else { return Candidate(location: location, problem: "完整 FEN 尾部需要 - - 半回合数 回合数") }
            fenCount = 6
        } else { fenCount = 2 }
        let title = fields.count > fenCount ? fields.dropFirst(fenCount).joined(separator: " ") : nil
        return Candidate(location: location, fen: fields.prefix(fenCount).joined(separator: " "), title: title)
    }

    private static func cleanTitle(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        return String(scalars.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }
}
