import Foundation

@main @MainActor struct GameRecordTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func rejects(_ data: Data, _ reason: String) {
            do { _ = try GameRecordCodec.decode(data); preconditionFailure(reason) }
            catch { checks += 1 }
        }
        func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        let line = ["h2e2", "h9g7", "h0g2", "i9h9", "i0h0", "b9c7"]
        let metadata = GameRecord.Metadata(title: "手动研究", red: "红方", black: "黑方", event: "本机练习", date: "2026-09-07", result: "未结束")
        let score = GameRecord(initialFEN: Position.initial.fen, moves: line, currentPly: 3,
                               metadata: metadata, annotations: [.init(ply: 3, text: "注意出车次序。")])
        let bytes = try score.encoded(), decoded = try GameRecordCodec.decode(bytes)
        check(decoded.record == score, "Own versioned JSON must round-trip its ID, metadata, annotations and display ply")
        check(decoded.replay.positions.count == 7 && decoded.replay.moves.map(\.uci) == line, "All moves are actually replayed")
        let uci = try GameRecordCodec.decode(Data(score.uciText().utf8))
        check(uci.record.moves == line && uci.replay.positions == decoded.replay.positions, "UCI export/import preserves the complete chess record")
        check(uci.record.metadata == nil && uci.record.annotations == nil, "Plain UCI must not invent metadata or annotations")
        for text in ["position startpos moves " + line.joined(separator: " "), line.joined(separator: "\n"),
                     "FEN: " + Position.initial.fen + "\n" + line.joined(separator: "\n")] {
            let record = try GameRecordCodec.decode(Data(text.utf8))
            check(record.record.moves == line && record.replay.positions.last == decoded.replay.positions.last,
                  "Supported standard UCI list must start at the specified or standard initial position")
        }
        let fen = try GameRecordCodec.decode(Data(decoded.replay.positions[3].fen.utf8))
        check(fen.record.moves.isEmpty && fen.replay.positions[0] == decoded.replay.positions[3], "FEN is a snapshot, never a fabricated history")

        var object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        object["moves"] = line + ["a0a9"]
        rejects(try json(object), "An illegal final move must reject the entire record, not import a prefix")
        object["moves"] = [String(repeating: "a", count: 50_000)]
        rejects(try json(object), "Oversized move tokens must be rejected before move parsing")
        object["moves"] = Array(repeating: "a3a4", count: GameRecord.maximumMoves + 1)
        rejects(try json(object), "Move count must be bounded")
        object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        object["version"] = 2; rejects(try json(object), "Unknown schema versions must not silently fall back to a snapshot")
        object["version"] = 1; object["format"] = "other"; rejects(try json(object), "Wrong format identifier must fail")
        object["format"] = "xiangqi-companion-record"; object["currentPly"] = 999; rejects(try json(object), "Invalid cursors must fail")
        object["currentPly"] = 3; object["annotations"] = [["ply": 3, "text": "a"], ["ply": 3, "text": "b"]]
        rejects(try json(object), "Duplicate ply annotations are ambiguous")
        for bad in ["", "position", "fen", "moves", "炮二平五 马8进7", "position startpos nonsense", "a3a4 a3a5"] {
            rejects(Data(bad.utf8), "Unsupported or illegal text may not turn into a fresh initial board")
        }
        rejects(Data(repeating: 32, count: GameRecord.maximumBytes + 1), "File byte size is bounded")
        rejects(Data(("{\"nested\":" + String(repeating: "[", count: 17) + "0" + String(repeating: "]", count: 17) + "}").utf8), "Deep JSON is bounded before decoding")
        let maximumLine = Array(repeating: ["h0g2", "h9g7", "g2h0", "g7h9"], count: GameRecord.maximumMoves / 4).flatMap { $0 }
        let maximumStart = Date()
        let maximumReplay = try GameRecord(initialFEN: Position.initial.fen, moves: maximumLine).validate()
        let maximumDuration = Date().timeIntervalSince(maximumStart)
        check(maximumReplay.positions.count == GameRecord.maximumMoves + 1 && maximumReplay.positions.last == .initial,
              "The complete maximum-length legal score is replayed, not sampled or truncated")

        let redGlyphs: [PieceKind: String] = [.rook: "俥", .horse: "傌", .elephant: "相", .advisor: "仕", .king: "帥", .cannon: "炮", .pawn: "兵"]
        let blackGlyphs: [PieceKind: String] = [.rook: "車", .horse: "馬", .elephant: "象", .advisor: "士", .king: "將", .cannon: "包", .pawn: "卒"]
        let actual = decoded.replay.positions[3]
        let board: [[Any]] = (0..<10).map { row in
            (0..<9).map { col in
                guard let piece = actual[Square(row: row, col: col)] else { return NSNull() }
                return ["type": (piece.side == .red ? redGlyphs : blackGlyphs)[piece.kind]!, "color": piece.side.rawValue, "moved": false] as [String: Any]
            }
        }
        var pwa: [String: Any] = ["board": board, "currentTurn": actual.sideToMove.rawValue,
                                  "gameRecord": [["unverified": "history is deliberately ignored"]], "saveTime": "2026-09-07"]
        let importedPWA = try GameRecordCodec.decode(json(pwa))
        check(importedPWA.replay.positions == [actual] && importedPWA.record.moves.isEmpty, "PWA must import only its exact current board, with no flipping or invented moves")
        check(importedPWA.notice?.contains("未转换") == true && importedPWA.notice?.contains("未还原") == true,
              "PWA history limitation must be explicit in the result shown by the UI")
        pwa["currentTurn"] = "w"; rejects(try json(pwa), "PWA currentTurn only accepts its actual red/black values")
        pwa["currentTurn"] = actual.sideToMove.rawValue
        pwa["board"] = Array(board.prefix(9)); rejects(try json(pwa), "PWA requires exactly ten rows")
        var wrong = board; wrong[0][0] = ["type": "rook", "color": "black"]
        pwa["board"] = wrong; rejects(try json(pwa), "Do not guess alternate piece vocabularies")
        wrong = board; wrong[0][0] = ["type": "俥", "color": "black"]
        pwa["board"] = wrong; rejects(try json(pwa), "A valid glyph with the wrong side is still invalid")
        wrong = board; wrong[0][0] = ["type": "車", "color": "black", "moved": "false"]
        pwa["board"] = wrong; rejects(try json(pwa), "Optional moved must retain the actual boolean type")
        wrong = board; wrong[0][4] = NSNull()
        pwa["board"] = wrong; rejects(try json(pwa), "Imported snapshot needs both kings and full position validation")

        let configured = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"]
        let base = configured.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("xiangqi-record-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oversizeURL = directory.appendingPathComponent("oversized.json")
        try Data(repeating: 32, count: GameRecord.maximumBytes + 1).write(to: oversizeURL)
        do { _ = try GameRecordCodec.read(oversizeURL); preconditionFailure("Oversized disk files must fail before full reading") }
        catch { checks += 1 }
        do { _ = try GameRecordCodec.read(directory); preconditionFailure("Directories are not score files") }
        catch { checks += 1 }
        let model = GameModel(directory: directory)
        model.startLocalTwoPlayer(); model.start()
        check(!model.engine.isRunning && model.isLocalTwoPlayer && !model.analysisEnabled && !model.showArrows,
              "Local two-player startup must not start an engine or show any analysis")
        for move in line { model.play(Move(uci: move)!) }
        check(model.moves.map(\.uci) == line && model.position == decoded.replay.positions.last, "Both humans use the existing alternating legal-move model")
        model.toggleAnalysis(); model.toggleArrows(); model.scheduleAnalysis()
        check(!model.analysisEnabled && !model.showArrows && model.currentAnalysis.isEmpty && model.recommendationArrows.isEmpty && !model.engine.isRunning,
              "Old analysis controls cannot reactivate hints during local two-player mode")
        check(model.saveRecordToLibrary(), "Current full score saves to the bounded local library")
        model.refreshRecordLibrary()
        check(model.recordEntries.count == 1, "One deliberate save creates one document")
        check(model.saveRecordToLibrary() && model.recordEntries.count == 1, "Repeated unchanged saves do not create duplicate files")
        let savedSessionURL = directory.appendingPathComponent("session.json")
        let sessionBefore = try Data(contentsOf: savedSessionURL), beforePosition = model.position
        model.previewRecordEntry(model.recordEntries[0])
        check(model.position == beforePosition && (try? Data(contentsOf: savedSessionURL)) == sessionBefore,
              "Selecting a library entry is read-only until confirmation")
        check(!model.acceptRecordPreview(at: 999) && model.position == beforePosition,
              "Invalid preview cursor must fail before archiving or replacement")
        check(model.previewRecordData(bytes), "Own document opens as a validated pending preview")
        check(model.position == beforePosition && model.moves.map(\.uci) == line, "File preview does not replace the current board")
        check(model.acceptRecordPreview(at: 2) && model.cursor == 2 && model.moves.count == line.count && model.position == decoded.replay.positions[2],
              "Confirmation loads the shown ply while retaining the entire future score")
        check(model.currentRecord.metadata == metadata && model.currentRecord.annotations == score.annotations,
              "Model keeps imported metadata and annotations")
        model.navigate(to: 1); model.play(Move(uci: "b9c7")!)
        check(model.moves.map(\.uci) == ["h2e2", "b9c7"] && model.currentRecord.annotations?.isEmpty == true,
              "Taking a new branch archives the full previous line and drops annotations from the abandoned future")
        model.shutdown()
        let restored = GameModel(directory: directory)
        check(restored.moves == model.moves && restored.position == model.position && restored.isLocalTwoPlayer && !restored.analysisEnabled,
              "Session persists record identity, exact board, full history and local mode")
        check(restored.currentRecord.id == model.currentRecord.id && restored.currentRecord.metadata == metadata,
              "Record ID and metadata remain stable across restart")
        restored.shutdown()

        let analysisDirectory = directory.appendingPathComponent("analysis-entry", isDirectory: true)
        let absentEngine = PikafishEngine(binaryURL: analysisDirectory.appendingPathComponent("not-installed"),
                                         networkURL: analysisDirectory.appendingPathComponent("not-installed.nnue"))
        let entryModel = GameModel(directory: analysisDirectory, engine: absentEngine)
        entryModel.startLocalTwoPlayer()
        check(entryModel.analyzePosition(decoded.replay.positions[2]), "Explicit library/image analysis accepts a valid position")
        check(!entryModel.isLocalTwoPlayer && entryModel.analysisEnabled && entryModel.showArrows,
              "Explicit analysis cannot inherit a former local two-player mode with hints disabled")
        check(entryModel.position == decoded.replay.positions[2] && entryModel.cursor == 0,
              "Imported analysis keeps its exact position, not fabricated previous history")
        entryModel.shutdown()

        // Old saved schema has no new optional keys, including showArrows.
        let legacyDirectory = directory.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacy: [String: Any] = ["initialFEN": Position.initial.fen, "moves": line, "cursor": 2,
                                     "flipped": true, "analysisEnabled": false, "milliseconds": 250]
        let legacyBytes = try json(legacy)
        try legacyBytes.write(to: legacyDirectory.appendingPathComponent("session.json"))
        let legacyImported = try GameRecordCodec.decode(legacyBytes)
        check(legacyImported.record.moves == line && legacyImported.record.currentPly == 2, "Old history JSON imports with its real complete line")
        let oldModel = GameModel(directory: legacyDirectory)
        check(oldModel.cursor == 2 && oldModel.position == decoded.replay.positions[2] && oldModel.flipped && oldModel.showArrows && !oldModel.isLocalTwoPlayer,
              "Legacy session compatibility preserves old preferences and defaults only absent fields")
        oldModel.shutdown()

        let illegalDirectory = directory.appendingPathComponent("illegal-session", isDirectory: true)
        try FileManager.default.createDirectory(at: illegalDirectory, withIntermediateDirectories: true)
        var illegalLegacy = legacy; illegalLegacy["moves"] = line + ["a0a9"]
        let illegalBytes = try json(illegalLegacy), illegalURL = illegalDirectory.appendingPathComponent("session.json")
        try illegalBytes.write(to: illegalURL)
        let illegalModel = GameModel(directory: illegalDirectory)
        illegalModel.shutdown()
        check(illegalModel.isSessionProtected && illegalModel.moves.isEmpty && (try? Data(contentsOf: illegalURL)) == illegalBytes,
              "A legal prefix before a bad move must not partially replace or overwrite the original session")

        let corruptDirectory = directory.appendingPathComponent("corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let corruptURL = corruptDirectory.appendingPathComponent("session.json"), corruptBytes = Data("{broken-original".utf8)
        try corruptBytes.write(to: corruptURL)
        let damaged = GameModel(directory: corruptDirectory)
        check(damaged.isSessionProtected && damaged.sessionRecoveryNotice != nil, "Corrupt session is explicitly protected, not silently treated as a restored initial game")
        damaged.flip(); damaged.play(Move(uci: "a3a4")!); damaged.startLocalTwoPlayer(); damaged.shutdown()
        check((try? Data(contentsOf: corruptURL)) == corruptBytes && damaged.moves.isEmpty,
              "Automatic save, shutdown and ordinary play must not overwrite corrupt user bytes")
        check(!damaged.saveRecordToLibrary(), "Do not archive the placeholder board as a recovered score")
        damaged.newGame()
        check(!damaged.isSessionProtected && damaged.position == .initial, "Explicit new game can proceed only after preserving the original")
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: corruptDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("session-recovery-") }
        check(recoveryFiles.count == 1 && (try? Data(contentsOf: recoveryFiles[0])) == corruptBytes,
              "Explicit recovery keeps an exact, separate copy of the damaged source")
        _ = try JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: corruptURL)); checks += 1
        damaged.shutdown()

        // Capacity is a refusal, not eviction: no existing history is removed.
        let fullDirectory = directory.appendingPathComponent("full", isDirectory: true)
        let history = fullDirectory.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        for index in 0..<GameModel.maximumHistoryCount { try Data("corrupt".utf8).write(to: history.appendingPathComponent("\(index).json")) }
        let full = GameModel(directory: fullDirectory)
        full.startLocalTwoPlayer(); full.play(Move(uci: "a3a4")!)
        let fullPosition = full.position
        full.refreshRecordLibrary()
        check(full.recordEntries.count == GameModel.maximumHistoryCount, "Existing damaged entries remain listed within the capacity")
        full.previewRecordEntry(full.recordEntries[0])
        check(full.recordPreview == nil && full.recordPreviewError != nil && full.recordEntryErrors.count == 1,
              "A damaged entry is visibly unavailable, not substituted with a starting position")
        full.newGame()
        check(full.position == fullPosition && full.moves.count == 1 && full.message.contains("上限"),
              "Failed archive capacity prevents destructive replacement")
        check((try? FileManager.default.contentsOfDirectory(atPath: history.path).count) == GameModel.maximumHistoryCount,
              "Capacity enforcement never deletes old records")
        full.shutdown()

        print("PASS \(checks) portable record / PWA snapshot / legacy history / recovery / local-two-player checks")
        print(String(format: "Maximum 1,024-half-move replay: %.3f seconds", maximumDuration))
    }
}
