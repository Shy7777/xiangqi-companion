#if FEN_BATCH_CODEC_TESTS
import Foundation

@main @MainActor struct FENBatchCodecTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }; checks += 1
    }
    static func rejects(_ text: String) throws {
        do { _ = try FENBatchCodec.convert(text: text) }
        catch { checks += 1; return }
        throw Failure(message: "Expected malformed/oversized input rejection")
    }
    static func main() async throws {
        let first = Position.initial, second = try first.applying(move: Move(uci: "b2e2")!)
        let short = first.fen.split(separator: " ").prefix(2).joined(separator: " ")
        let shortSecond = second.fen.split(separator: " ").prefix(2).joined(separator: " ")
        let batch = try FENBatchCodec.convert(text: "\u{feff}\(short) 中炮参考\n\n\(second.fen)\n第二行题名\n\(first.fen) 重复别名\n不是局面\n9/9/9/9/9/9/9/9/9/9 w 坏棋盘")
        try check(batch.total == 5 && batch.accepted == 2 && batch.duplicates == 1 && batch.invalid == 2, "Summary accounting")
        try check(batch.total == batch.accepted + batch.duplicates + batch.invalid, "Every candidate accounted")
        try check(batch.issues.count == 2 && batch.issues[0].contains("第 6 行"), "Original line diagnostics")
        try check(batch.fenText == first.fen + "\n" + second.fen, "Canonical FEN output")
        try check(batch.namedFENText.contains("中炮参考") && batch.namedFENText.contains("第二行题名"), "Inline/next-line titles")
        let imported = try PositionLibraryImporter.preview(data: batch.jsonData, fileName: "converted.json", label: "", existingFENs: [], revision: UUID())
        try check(imported.accepted == 2 && imported.invalid == 0 && imported.entries[1].title == "第二行题名", "JSON payload must import unchanged")
        let plainImported = try PositionLibraryImporter.preview(data: Data(batch.fenText.utf8), fileName: "converted.fen", label: "", existingFENs: [], revision: UUID())
        try check(plainImported.accepted == 2 && plainImported.invalid == 0, "Plain FEN must remain importer compatible")
        let namedRoundTrip = try FENBatchCodec.convert(text: batch.namedFENText)
        try check(namedRoundTrip.jsonData == batch.jsonData, "Named text round trip")

        let metadata: [[String: Any]] = [["fen": short, "name": "保留原标记", "result": "egtb:", "bestMove": "a0a1\0", "source": "javascript:neverRun()", "classification": ["type": "原分类"], "materialValue": ["redValue": 5]], ["fen": second.fen, "type": "原始子力"], ["fen": 123], ["name": "缺 FEN"]]
        let json = try JSONSerialization.data(withJSONObject: metadata)
        let fromJSON = try FENBatchCodec.convert(text: String(decoding: json, as: UTF8.self))
        try check(fromJSON.total == 4 && fromJSON.accepted == 2 && fromJSON.invalid == 2, "JSON schema and validation")
        let restored = try JSONSerialization.jsonObject(with: fromJSON.jsonData) as! [[String: Any]]
        try check(restored[0]["source"] as? String == "javascript:neverRun()" && restored[0]["bestMove"] as? String == "a0a1\0", "Original metadata must remain inert, not executed or promoted")
        try check((restored[0]["classification"] as? [String: String])?["type"] == "原分类" && (restored[0]["materialValue"] as? [String: Int])?["redValue"] == 5, "Nested PWA metadata retained")
        try check(restored[1]["name"] as? String == "原始子力", "Unnamed structured position uses source type")
        let one = try FENBatchCodec.convert(text: String(decoding: JSONSerialization.data(withJSONObject: metadata[0]), as: UTF8.self))
        try check(one.accepted == 1, "Single FEN object")
        let arrayStrings = try FENBatchCodec.convert(text: String(decoding: JSONSerialization.data(withJSONObject: [first.fen, second.fen]), as: UTF8.self))
        try check(arrayStrings.accepted == 2, "FEN string array")

        let attached = try FENBatchCodec.convert(text: short + "中文题名")
        try check(attached.accepted == 1 && attached.namedFENText.hasSuffix("中文题名"), "Upstream attached Chinese title form")
        let noTitles = try FENBatchCodec.convert(text: "\(short)\n\(shortSecond)")
        try check(noTitles.accepted == 2 && noTitles.namedFENText.contains("局面 1"), "Adjacent bare FEN lines are two positions")
        let slashTitle = try FENBatchCodec.convert(text: "\(short)\n车/炮的比较")
        try check(slashTitle.accepted == 1 && slashTitle.namedFENText.hasSuffix("车/炮的比较"), "A slash in the following title is not a new board")
        let invalidSide = try FENBatchCodec.convert(text: short.replacingOccurrences(of: " w", with: " white") + "\n" + first.fen.split(separator: " ")[0])
        try check(invalidSide.invalid == 2 && invalidSide.accepted == 0, "Never infer missing or English turn text")
        let badTail = try FENBatchCodec.convert(text: short + " - - 0\n" + shortSecond + " - x 0 1")
        try check(badTail.invalid == 2, "Malformed full FEN metadata rejected")
        let aliases = short.replacingOccurrences(of: "n", with: "h").replacingOccurrences(of: "N", with: "H")
            .replacingOccurrences(of: "b", with: "e").replacingOccurrences(of: "B", with: "E").replacingOccurrences(of: " w", with: " r")
        let normalize = try FENBatchCodec.convert(text: aliases + "\n" + first.fen)
        try check(normalize.accepted == 1 && normalize.duplicates == 1 && normalize.fenText == first.fen, "Canonical aliases/counters deduplicate")
        let longTitle = try FENBatchCodec.convert(text: short + " " + String(repeating: "长", count: 500))
        let longJSON = try JSONSerialization.jsonObject(with: longTitle.jsonData) as! [[String: String]]
        try check(longJSON[0]["name"]?.count == 200, "Importer-compatible bounded titles")
        let manyErrors = try FENBatchCodec.convert(text: Array(repeating: "not fen", count: 30).joined(separator: "\n"))
        try check(manyErrors.invalid == 30 && manyErrors.issues.count == 12 && manyErrors.accepted == 0, "Bounded diagnostic list")
        for text in ["", "  \n", "[", "[]", "{\"files\":[]}", "{\"board\":[]}"] { try rejects(text) }
        try rejects(String(repeating: " ", count: FENBatchCodec.maximumBytes + 1))
        try rejects(Array(repeating: short, count: FENBatchCodec.maximumItems + 1).joined(separator: "\n"))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FENBatchCodec.convert(text: first.fen)
        }
        do { _ = try await cancelled.value; throw Failure(message: "Cancelled conversion ran") }
        catch is CancellationError { checks += 1 }
        print("PASS: \(checks) FEN batch validation, text/JSON/title round-trip, metadata, limits and cancellation checks")
    }
}
#endif
