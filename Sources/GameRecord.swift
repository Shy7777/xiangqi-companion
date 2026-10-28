import Foundation

/// A portable, versioned score. The complete move list is independent of the
/// currently displayed ply; annotations never stand in for validated moves.
struct GameRecord: Codable, Equatable, Identifiable {
    static let maximumBytes = 262_144
    static let maximumMoves = 1_024
    var format = "xiangqi-companion-record"
    var version = 1
    var id: UUID = UUID()
    var initialFEN: String
    var moves: [String]
    var currentPly: Int? = nil
    var metadata: Metadata? = nil
    var annotations: [Annotation]? = nil

    struct Metadata: Codable, Equatable {
        var title: String? = nil
        var red: String? = nil
        var black: String? = nil
        var event: String? = nil
        var date: String? = nil
        var result: String? = nil
    }
    struct Annotation: Codable, Equatable {
        let ply: Int
        let text: String
    }
    struct Replay {
        let positions: [Position]
        let moves: [Move]
        let names: [String]
    }

    func validate() throws -> Replay {
        guard format == "xiangqi-companion-record", version == 1 else {
            throw GameRecordError.invalid("不支持这个棋谱版本。")
        }
        guard initialFEN.utf8.count <= 180, moves.count <= Self.maximumMoves,
              currentPly.map({ (0...moves.count).contains($0) }) ?? true else {
            throw GameRecordError.invalid("棋谱过长或浏览位置越界；最多 1,024 半步。")
        }
        let labels = [metadata?.title, metadata?.red, metadata?.black, metadata?.event, metadata?.date, metadata?.result]
        guard labels.allSatisfy({ ($0?.utf8.count ?? 0) <= 1_024 }) else {
            throw GameRecordError.invalid("棋谱资料文字过长。")
        }
        if let annotations {
            guard annotations.count <= 256, Set(annotations.map(\.ply)).count == annotations.count,
                  annotations.allSatisfy({ (0...moves.count).contains($0.ply) && $0.text.utf8.count <= 4_096 }) else {
                throw GameRecordError.invalid("注释重复、过长或位置越界。")
            }
        }
        var position = try Position(fen: initialFEN)
        var positions = [position], parsed: [Move] = [], names: [String] = []
        for (index, text) in moves.enumerated() {
            guard text.utf8.count == 4, let move = Move(uci: text) else {
                throw GameRecordError.invalid("第 \(index + 1) 半步不是标准 UCI 着法。")
            }
            do {
                let next = try position.applying(move: move)
                names.append(position.notation(for: move)); parsed.append(move)
                positions.append(next); position = next
            } catch {
                throw GameRecordError.invalid("第 \(index + 1) 半步 \(text) 不合法，整份棋谱未导入。")
            }
        }
        return Replay(positions: positions, moves: parsed, names: names)
    }

    func encoded() throws -> Data {
        _ = try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw GameRecordError.invalid("棋谱文件请控制在 256 KiB 内。") }
        return data
    }

    /// Standard UCI position command, not PGN or Chinese move notation.
    func uciText() throws -> String {
        let replay = try validate()
        return "position fen " + replay.positions[0].fen + (moves.isEmpty ? "" : " moves " + moves.joined(separator: " "))
    }
}

enum GameRecordError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

struct ImportedGameRecord {
    let record: GameRecord
    let replay: GameRecord.Replay
    let notice: String?
}

/// Keep legacy session keys unchanged; added optional fields are backwards compatible.
struct SavedSession: Codable {
    var initialFEN: String
    var moves: [String]
    var cursor: Int
    var flipped: Bool
    var analysisEnabled: Bool
    var milliseconds: Int
    var showArrows: Bool? = nil
    var localTwoPlayer: Bool? = nil
    var recordID: UUID? = nil
    var metadata: GameRecord.Metadata? = nil
    var annotations: [GameRecord.Annotation]? = nil

    var record: GameRecord {
        GameRecord(id: recordID ?? UUID(), initialFEN: initialFEN, moves: moves, currentPly: cursor,
                   metadata: metadata, annotations: annotations)
    }
}

enum GameRecordCodec {
    static func read(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= GameRecord.maximumBytes else {
            throw GameRecordError.invalid("请选择不超过 256 KiB 的棋谱文件。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: GameRecord.maximumBytes + 1) ?? Data()
        guard data.count <= GameRecord.maximumBytes else { throw GameRecordError.invalid("棋谱文件过大。") }
        return data
    }

    static func decode(_ data: Data) throws -> ImportedGameRecord {
        guard !data.isEmpty, data.count <= GameRecord.maximumBytes,
              let text = String(data: data, encoding: .utf8) else {
            throw GameRecordError.invalid("需要 256 KiB 内的 UTF-8 棋谱文本。")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{" {
            try checkJSONDepth(data)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GameRecordError.invalid("JSON 顶层必须是对象。")
            }
            if object["format"] != nil || object["version"] != nil {
                return try validated(JSONDecoder().decode(GameRecord.self, from: data))
            }
            if object["board"] != nil {
                let imported = try JSONDecoder().decode(PWAState.self, from: data)
                return try validated(imported.record(), notice: "仅导入 PWA 当前局面；原 gameRecord 历史未转换、未还原。")
            }
            if object["initialFEN"] != nil && object["cursor"] != nil {
                let session = try JSONDecoder().decode(SavedSession.self, from: data)
                return try validated(session.record, notice: "旧版本机棋谱已完整重放验证。")
            }
            throw GameRecordError.invalid("不是本软件棋谱、旧版记录或支持的 PWA 局面。")
        }
        return try decodeText(trimmed)
    }

    static func validated(_ record: GameRecord, notice: String? = nil) throws -> ImportedGameRecord {
        let replay = try record.validate()
        var normalized = record
        normalized.initialFEN = replay.positions[0].fen
        return ImportedGameRecord(record: normalized, replay: replay, notice: notice)
    }

    private static func decodeText(_ text: String) throws -> ImportedGameRecord {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, words.count <= GameRecord.maximumMoves + 10 else {
            throw GameRecordError.invalid("着序为空或过长；最多 1,024 半步。")
        }
        if words.first == "position" { words.removeFirst() }
        guard !words.isEmpty else { throw GameRecordError.invalid("position 后缺少局面。") }
        var initialFEN = Position.initial.fen
        var values: [String] = []
        var notice: String?
        if words.first == "startpos" {
            words.removeFirst()
            guard words.isEmpty || words.first == "moves" else { throw GameRecordError.invalid("startpos 后请使用 moves。") }
            values = words.first == "moves" ? Array(words.dropFirst()) : []
        } else {
            if words.first?.lowercased() == "fen" || words.first?.lowercased() == "fen:" { words.removeFirst() }
            guard !words.isEmpty else { throw GameRecordError.invalid("缺少 FEN 局面。") }
            if words.first?.contains("/") == true {
                let marker = words.firstIndex(of: "moves")
                let split = marker ?? words.indices.dropFirst().first(where: { words[$0].utf8.count == 4 && Move(uci: words[$0]) != nil }) ?? words.count
                initialFEN = words[..<split].joined(separator: " ")
                values = split < words.count ? Array(words.dropFirst(split + (marker != nil ? 1 : 0))) : []
            } else {
                values = words.first == "moves" ? Array(words.dropFirst()) : words
                guard !values.isEmpty else { throw GameRecordError.invalid("缺少 UCI 着序。") }
                notice = "UCI 着序从标准初始局面完整重放。"
            }
        }
        guard initialFEN.utf8.count <= 180 else { throw GameRecordError.invalid("局面代码过长。") }
        return try validated(GameRecord(initialFEN: initialFEN, moves: values), notice: notice)
    }

    /// The input byte cap also bounds token work; reject pathological nesting
    /// before either Foundation JSON parser traverses it.
    static func checkJSONDepth(_ data: Data) throws {
        var depth = 0, quoted = false, escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 {
                depth += 1
                guard depth <= 16 else { throw GameRecordError.invalid("JSON 嵌套过深。") }
            } else if byte == 125 || byte == 93 { depth -= 1 }
        }
    }

    private struct PWAState: Decodable {
        struct Cell: Decodable { let type: String; let color: String; let moved: Bool? }
        let board: [[Cell?]]
        let currentTurn: String

        func record() throws -> GameRecord {
            guard board.count == 10, board.allSatisfy({ $0.count == 9 }), let turn = Side(rawValue: currentTurn) else {
                throw GameRecordError.invalid("PWA 局面需要严格的 10×9 棋盘及 red / black 行棋方。")
            }
            // Verified upstream index.html @ 3ff21f4502a03f30bb0df55db6f3814ceeb989f5,
            // https://github.com/dffge552/xiangqi-pwa-offline/blob/3ff21f4502a03f30bb0df55db6f3814ceeb989f5/index.html
            // initializePieces L799–833; row 0 = black back rank. No coordinate
            // flipping and no inference from its unverified gameRecord field.
            let red: [String: PieceKind] = ["俥": .rook, "傌": .horse, "相": .elephant, "仕": .advisor, "帥": .king, "炮": .cannon, "兵": .pawn]
            let black: [String: PieceKind] = ["車": .rook, "馬": .horse, "象": .elephant, "士": .advisor, "將": .king, "包": .cannon, "卒": .pawn]
            let cells: [Piece?] = try board.flatMap { row in
                try row.map { cell in
                    guard let cell else { return nil }
                    guard let side = Side(rawValue: cell.color), let kind = (side == .red ? red : black)[cell.type] else {
                        throw GameRecordError.invalid("PWA 棋子类型与颜色不匹配，未猜测或替换棋子。")
                    }
                    return Piece(side: side, kind: kind)
                }
            }
            let position = Position(board: cells, sideToMove: turn)
            try position.validate()
            return GameRecord(initialFEN: position.fen, moves: [], metadata: .init(title: "PWA 导入局面"))
        }
    }
}

struct ManualRecordEntry: Identifiable {
    let id: String
    let url: URL
    let date: Date
    let bytes: Int
    var title: String { url.deletingPathExtension().lastPathComponent }
}

struct ManualRecordPreview: Identifiable {
    let id = UUID()
    let imported: ImportedGameRecord
    let title: String
    var cursor: Int { imported.record.currentPly ?? imported.record.moves.count }
}

enum ManualRecordExportFormat { case json, uci, fen
    var fileExtension: String { self == .json ? "json" : self == .uci ? "uci" : "fen" }
}
