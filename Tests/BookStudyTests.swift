import Foundation

@main
struct BookStudyTests {
    @MainActor
    static func main() async throws {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"] ?? NSTemporaryDirectory())
            .appendingPathComponent("book-study-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let fixture = base.appendingPathComponent("测试.CBL")
        let bytes = makeFixture()
        try bytes.write(to: fixture)
        let directory = base.appendingPathComponent("private-books")
        let model = BookStudyModel(directory: directory)
        await model.bootstrap()
        await model.importBook(url: fixture)
        try check(model.document?.records.count == 2, "CBL imported into a private book shelf")
        try check(model.notice?.contains("已导入") == true, "Import status is truthful")
        let record = try require(model.record)
        try check(model.currentNode?.comment == "局面导读\r\n繁體原文，不应改写。", "Original commentary including script and CRLF is unchanged")
        try check(model.choices.count == 2 && model.branchPoints.count == 1, "All root alternatives remain navigable")
        try check(model.position == .initial && model.currentPly == 0, "Source position starts intact")
        model.setMode(.recall)
        try check(model.mode == .recall && !model.referenceRevealed, "Practice hides later reference material")
        model.attempt(Move(uci: "a3a4")!)
        try check(model.feedback.contains("主线一致") && model.isAwaitingReply, "Exact book move is acknowledged as exact, not also acceptable")
        model.forward()
        try check(model.currentPly == 2 && !model.isAwaitingReply, "Explicit opponent response returns control to the learner")
        model.attempt(Move(uci: "c3c4")!)
        try check(!model.canGoForward && model.status(for: record.id).matched == 2, "End of line records matching attempts, not mastery")
        model.back()
        try check(model.currentPly == 2 && model.status(for: record.id).attempts == 2, "Undo does not erase practice history")
        model.restart()
        try check(model.currentPly == 0 && !model.referenceRevealed, "Restart returns to the actual practice anchor")
        model.attempt(Move(uci: "e3e4")!)
        try check(model.currentPly == 0 && model.feedback.contains("不等于错误") && model.analysisPosition != model.position,
                  "Unrecorded legal move is not falsely graded wrong and can be analyzed separately")
        model.hint()
        try check(model.hintLevel == 1 && model.arrows.isEmpty, "First hint identifies only a piece")
        model.hint()
        try check(model.arrows.count == 1 && model.status(for: record.id).hints == 2, "Second hint shows the book line, not engine Top1")
        model.attempt(Move(uci: "c3c4")!)
        try check(model.feedback.contains("收录的变招"), "Alternative source line is recognized")
        model.forward()
        try check(!model.canPractice && model.feedback.contains("走完"), "Opponent's terminal reply reports completion, not a nonexistent student turn")
        model.backToBranch()
        try check(model.currentPly == 0 && model.referenceRevealed, "Returning to branch comparison is explicitly assisted")
        model.setMode(.reading)
        let finalNode = record.nodes.first(where: { $0.comment == "原注：这一线的结果。\r\n" })!
        model.go(to: finalNode.id)
        try check(model.currentNode?.comment == "原注：这一线的结果。\r\n" && model.currentPly == 3,
                  "Jump to commentary follows its complete parent path")
        model.markRead(); model.toggleBookmark()
        try check(model.status(for: record.id).read && model.status(for: record.id).bookmarked, "Reading status and bookmark are independent explicit actions")
        let counts = model.status(for: record.id)
        await model.importBook(url: fixture)
        try check(model.shelf.count == 1 && model.status(for: record.id) == counts, "Reimporting identical bytes is idempotent and keeps progress including visit timestamp")
        let restored = BookStudyModel(directory: directory)
        await restored.bootstrap()
        try check(restored.record?.id == record.id && restored.nodeID == finalNode.id && restored.status(for: record.id) == counts,
                  "App reload restores book, record, exact node and evidence")
        restored.nextRecord()
        try check(restored.isTextOnly && !restored.canPractice && restored.currentNode?.comment == "纯文字导读。", "Reading-only records remain available without fake exercises")
        restored.previousRecord()
        try check(restored.nodeID == finalNode.id, "Returning through the directory resumes the prior location")
        let original = try Data(contentsOf: fixture)
        try check(original == bytes, "Source CBL is byte-for-byte unchanged")
        let saved = try BookLibraryStorage(directory: directory).load()
        let sourceCopy = try Data(contentsOf: BookLibraryStorage(directory: directory).url(for: saved.entries[0]))
        try check(sourceCopy == bytes, "Private original archive is a byte-identical copy")
        let bad = base.appendingPathComponent("bad.cbl"); try Data("not a CBL".utf8).write(to: bad)
        await restored.importBook(url: bad)
        try check(restored.shelf.count == 1 && restored.record?.id == record.id && restored.notice?.contains("未导入") == true,
                  "Bad import preserves current book and shelf")
        var oversized = saved
        oversized.lastRecordByBook["test"] = String(repeating: "x", count: BookLibraryStorage.maximumIndexBytes)
        let indexBefore = try Data(contentsOf: BookLibraryStorage(directory: directory).indexURL)
        do {
            try BookLibraryStorage(directory: directory).save(oversized)
            throw NSError(domain: "BookStudyTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Oversized index was saved"])
        } catch is BookLibraryError { }
        try check(try Data(contentsOf: BookLibraryStorage(directory: directory).indexURL) == indexBefore,
                  "Over-limit save preserves readable prior index")
        print("Book study: workflow, text-fidelity and persistence checks passed")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "BookStudyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture value"]) }
        return value
    }
    static func check(_ passed: Bool, _ message: String) throws {
        if !passed { throw NSError(domain: "BookStudyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func makeFixture() -> Data {
        var bytes = [UInt8](repeating: 0, count: 12_288)
        func put(_ data: [UInt8], at offset: Int) { bytes.replaceSubrange(offset..<(offset+data.count), with: data) }
        func text(_ value: String, at offset: Int) { put(Array(value.data(using: .utf16LittleEndian)!), at: offset) }
        func integer(_ value: Int, at offset: Int) { put((0..<4).map { UInt8((value >> (8*$0)) & 255) }, at: offset) }
        put(Array("CCBridgeLibrary\0".utf8), at: 0); integer(3, at: 16); bytes[20] = 9
        text("测试棋书", at: 64)
        let pieceCode: [PieceKind: UInt8] = [.rook: 1, .horse: 2, .elephant: 3, .advisor: 4, .king: 5, .cannon: 6, .pawn: 7]
        for index in 0..<2 {
            let start = 4096 * (index + 1)
            put(Array("CCBridge Record\0".utf8), at: start); bytes[start+19] = 2; bytes[start+20] = UInt8(index+1)
            text(index == 0 ? "4.1.01中炮巡河炮对屏风马" : "4.1.02文字说明", at: start+180)
            integer(1, at: start+2112); integer(1, at: start+2116)
            for square in Square.all {
                if let piece = Position.initial[square] { bytes[start+2120+square.index] = (piece.side == .red ? 16 : 32) + pieceCode[piece.kind]! }
            }
            var cursor = start+2214
            func node(_ flag: UInt8, _ uci: String?, _ comment: String? = nil) {
                let move = uci.flatMap(Move.init(uci:))
                put([flag, 0, UInt8(move?.from.index ?? 0), UInt8(move?.to.index ?? 0)], at: cursor); cursor += 4
                if flag & 4 != 0 {
                    let raw = Array((comment ?? "").data(using: .utf16LittleEndian)!)
                    integer(raw.count, at: cursor); cursor += 4; put(raw, at: cursor); cursor += raw.count
                }
            }
            if index == 0 {
                node(4, nil, "局面导读\r\n繁體原文，不应改写。")
                node(2, "a3a4"); node(0, "a6a5"); node(5, "c3c4", "原注：这一线的结果。\r\n")
                node(0, "c3c4"); node(1, "c6c5")
            } else { node(5, nil, "纯文字导读。") }
        }
        return Data(bytes)
    }
}
