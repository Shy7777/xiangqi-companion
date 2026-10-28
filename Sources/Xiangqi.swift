import Foundation

enum Side: String, Codable, CaseIterable, Hashable, Sendable {
    case red, black

    var opponent: Side { self == .red ? .black : .red }
    var label: String { self == .red ? "红方" : "黑方" }
    var forward: Int { self == .red ? -1 : 1 }

    func hasCrossedRiver(row: Int) -> Bool {
        self == .red ? row <= 4 : row >= 5
    }

    func palaceContains(_ square: Square) -> Bool {
        (3...5).contains(square.col) && (self == .red ? (7...9).contains(square.row) : (0...2).contains(square.row))
    }
}

enum PieceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case king, advisor, elephant, horse, rook, cannon, pawn

    fileprivate var fenLetter: Character {
        switch self {
        case .king: return "k"
        case .advisor: return "a"
        case .elephant: return "b"
        case .horse: return "n"
        case .rook: return "r"
        case .cannon: return "c"
        case .pawn: return "p"
        }
    }
}

struct Piece: Codable, Hashable, Sendable {
    var side: Side
    var kind: PieceKind

    var symbol: String {
        switch kind {
        case .king: return side == .red ? "帅" : "将"
        case .advisor: return side == .red ? "仕" : "士"
        case .elephant: return side == .red ? "相" : "象"
        case .horse: return "马"
        case .rook: return "车"
        case .cannon: return "炮"
        case .pawn: return side == .red ? "兵" : "卒"
        }
    }

    var fenCharacter: Character {
        let value = String(kind.fenLetter)
        return Character(side == .red ? value.uppercased() : value)
    }

    init(side: Side, kind: PieceKind) {
        self.side = side
        self.kind = kind
    }

    init?(fenCharacter: Character) {
        guard fenCharacter.isASCII else { return nil }
        side = fenCharacter.isUppercase ? .red : .black
        switch fenCharacter.lowercased() {
        case "k": kind = .king
        case "a": kind = .advisor
        case "b", "e": kind = .elephant
        case "n", "h": kind = .horse
        case "r": kind = .rook
        case "c": kind = .cannon
        case "p": kind = .pawn
        default: return nil
        }
    }
}

/// row 0 is the black home rank; row 9 is the red home rank.
struct Square: Codable, Hashable, Sendable, CustomStringConvertible {
    var row: Int
    var col: Int

    var isValid: Bool { (0..<10).contains(row) && (0..<9).contains(col) }
    var index: Int { row * 9 + col }
    var coordinate: String {
        guard isValid else { return "?" }
        return String(UnicodeScalar(97 + col)!) + String(9 - row)
    }
    var description: String { coordinate }

    static let all: [Square] = (0..<90).map { Square(row: $0 / 9, col: $0 % 9) }

    init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    init?(coordinate: String) {
        let bytes = Array(coordinate.utf8)
        guard bytes.count == 2, (97...105).contains(bytes[0]), (48...57).contains(bytes[1]) else { return nil }
        col = Int(bytes[0] - 97)
        row = 9 - Int(bytes[1] - 48)
    }
}

struct Move: Codable, Hashable, Sendable, CustomStringConvertible {
    var from: Square
    var to: Square

    var uci: String { from.coordinate + to.coordinate }
    var description: String { uci }

    init(from: Square, to: Square) {
        self.from = from
        self.to = to
    }

    init?(uci: String) {
        let characters = Array(uci)
        guard characters.count == 4,
              let from = Square(coordinate: String(characters[0...1])),
              let to = Square(coordinate: String(characters[2...3])), from != to else { return nil }
        self.init(from: from, to: to)
    }
}

enum XiangqiError: Error, LocalizedError, Equatable {
    case malformedFEN(String)
    case invalidPosition(String)
    case illegalMove(String)

    var errorDescription: String? {
        switch self {
        case .malformedFEN(let reason): return "棋局格式不正确：\(reason)"
        case .invalidPosition(let reason): return "棋局不合法：\(reason)"
        case .illegalMove(let reason): return "不能这样走：\(reason)"
        }
    }
}

struct Position: Codable, Hashable, Sendable {
    var board: [Piece?]
    var sideToMove: Side

    static let initialFEN = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1"
    static let initial: Position = try! Position(fen: initialFEN)

    /// Unvalidated construction supports an in-progress board editor. Validate before analysis.
    init(board: [Piece?], sideToMove: Side) {
        self.board = board
        self.sideToMove = sideToMove
    }

    init(fen: String) throws {
        let fields = fen.split(whereSeparator: { $0.isWhitespace })
        guard fields.count == 1 || fields.count == 2 || fields.count == 6 else {
            throw XiangqiError.malformedFEN("需要棋盘与行棋方，或完整的 6 段 FEN")
        }
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 10 else { throw XiangqiError.malformedFEN("棋盘需要 10 行") }
        board = []
        for rank in ranks {
            var cells: [Piece?] = []
            for character in rank {
                if let count = character.wholeNumberValue, character.isASCII, (1...9).contains(count) {
                    cells.append(contentsOf: repeatElement(nil, count: count))
                } else if let piece = Piece(fenCharacter: character) {
                    cells.append(piece)
                } else {
                    throw XiangqiError.malformedFEN("存在无法识别的棋子或空位：\(character)")
                }
                guard cells.count <= 9 else { throw XiangqiError.malformedFEN("每行必须恰好 9 格") }
            }
            guard cells.count == 9 else { throw XiangqiError.malformedFEN("每行必须恰好 9 格") }
            board.append(contentsOf: cells)
        }
        switch fields.count > 1 ? String(fields[1]) : "w" {
        case "w", "r": sideToMove = .red
        case "b": sideToMove = .black
        default: throw XiangqiError.malformedFEN("行棋方应为 w（红）或 b（黑）")
        }
        if fields.count == 6 {
            guard fields[2] == "-", fields[3] == "-",
                  let halfmove = Int(fields[4]), halfmove >= 0,
                  let fullmove = Int(fields[5]), fullmove >= 1 else {
                throw XiangqiError.malformedFEN("FEN 尾部应为 - - 半回合数 回合数")
            }
        }
        try validate()
    }

    /// This model represents a board snapshot, so move counters are intentionally normalized.
    var fen: String {
        var ranks: [String] = []
        for row in 0..<10 {
            var rank = ""
            var empty = 0
            for col in 0..<9 {
                if let piece = self[Square(row: row, col: col)] {
                    if empty > 0 { rank += String(empty); empty = 0 }
                    rank.append(piece.fenCharacter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { rank += String(empty) }
            ranks.append(rank)
        }
        return ranks.joined(separator: "/") + (sideToMove == .red ? " w" : " b") + " - - 0 1"
    }

    subscript(_ square: Square) -> Piece? {
        get {
            guard square.isValid, board.indices.contains(square.index) else { return nil }
            return board[square.index]
        }
        set {
            guard square.isValid, board.indices.contains(square.index) else { return }
            board[square.index] = newValue
        }
    }

    /// Current side may be in check. The previous mover may not leave their own king in check.
    func validate() throws {
        guard board.count == 90 else { throw XiangqiError.invalidPosition("棋盘需要 90 格") }
        for side in Side.allCases {
            let pieces = Square.all.compactMap { square -> (Square, Piece)? in
                guard let piece = self[square], piece.side == side else { return nil }
                return (square, piece)
            }
            guard pieces.filter({ $0.1.kind == .king }).count == 1 else {
                throw XiangqiError.invalidPosition("\(side.label)必须有且只有一个\(side == .red ? "帅" : "将")")
            }
            for kind in PieceKind.allCases where kind != .king {
                let limit = kind == .pawn ? 5 : 2
                guard pieces.filter({ $0.1.kind == kind }).count <= limit else {
                    throw XiangqiError.invalidPosition("\(side.label)的\(Piece(side: side, kind: kind).symbol)数量超出上限")
                }
            }
            for (square, piece) in pieces {
                let localRow = side == .black ? square.row : 9 - square.row
                switch piece.kind {
                case .king:
                    guard side.palaceContains(square) else {
                        throw XiangqiError.invalidPosition("将帅必须位于九宫内")
                    }
                case .advisor:
                    guard side.palaceContains(square), (localRow + square.col) % 2 == 1 else {
                        throw XiangqiError.invalidPosition("士仕必须位于九宫内的斜线交点")
                    }
                case .elephant:
                    let permitted = [(0, 2), (0, 6), (2, 0), (2, 4), (2, 8), (4, 2), (4, 6)]
                    guard permitted.contains(where: { $0.0 == localRow && $0.1 == square.col }) else {
                        throw XiangqiError.invalidPosition("象相必须位于己方合法象位，不能过河")
                    }
                case .pawn:
                    guard localRow >= 3, localRow >= 5 || square.col % 2 == 0 else {
                        throw XiangqiError.invalidPosition("兵卒不能后退，未过河时必须位于原来的兵线")
                    }
                default: break
                }
            }
        }
        if generalsFaceEachOther {
            throw XiangqiError.invalidPosition("将帅不能在同一条线上直接照面")
        }
        if isInCheck(sideToMove.opponent) {
            throw XiangqiError.invalidPosition("未轮到走棋的一方仍在被将军，请检查行棋方或棋子位置")
        }
    }

    var generalsFaceEachOther: Bool {
        guard let red = kingSquare(for: .red), let black = kingSquare(for: .black) else { return false }
        return red.col == black.col && interveningPieces(from: red, to: black) == 0
    }

    func kingSquare(for side: Side) -> Square? {
        Square.all.first { self[$0] == Piece(side: side, kind: .king) }
    }

    func isInCheck(_ side: Side) -> Bool {
        guard let king = kingSquare(for: side) else { return true }
        return Square.all.contains { square in
            guard let piece = self[square], piece.side == side.opponent else { return false }
            return attacks(from: square, to: king, piece: piece)
        }
    }

    func legalMoves(from origin: Square? = nil) -> [Move] {
        guard board.count == 90, kingSquare(for: sideToMove) != nil else { return [] }
        let origins = origin.map { [$0] } ?? Square.all
        var result: [Move] = []
        for from in origins {
            guard let piece = self[from], piece.side == sideToMove else { continue }
            for to in pseudoDestinations(from: from, piece: piece) {
                if let target = self[to], target.side == piece.side || target.kind == .king { continue }
                let move = Move(from: from, to: to)
                let next = applyingUnchecked(move)
                if !next.isInCheck(sideToMove) { result.append(move) }
            }
        }
        return result
    }

    func applying(move: Move) throws -> Position {
        guard legalMoves(from: move.from).contains(move) else {
            throw XiangqiError.illegalMove("\(move.from.coordinate) → \(move.to.coordinate)")
        }
        return applyingUnchecked(move)
    }

    private func applyingUnchecked(_ move: Move) -> Position {
        var next = self
        next[move.to] = self[move.from]
        next[move.from] = nil
        next.sideToMove = sideToMove.opponent
        return next
    }

    func notation(for move: Move) -> String {
        guard move.from.isValid, move.to.isValid, let piece = self[move.from] else {
            return "\(move.from.coordinate) → \(move.to.coordinate)"
        }
        let sameFile = Square.all.filter {
            $0.col == move.from.col && self[$0] == piece
        }.sorted { piece.side == .red ? $0.row < $1.row : $0.row > $1.row }
        let prefix: String
        var needsCoordinates = false
        if sameFile.count == 2, let index = sameFile.firstIndex(of: move.from) {
            prefix = (index == 0 ? "前" : "后") + piece.symbol
        } else if sameFile.count == 3, let index = sameFile.firstIndex(of: move.from) {
            prefix = ["前", "中", "后"][index] + piece.symbol
        } else {
            prefix = piece.symbol + fileNumber(move.from.col, side: piece.side)
            needsCoordinates = sameFile.count > 3
        }
        // Two separate pawn stacks can have the same 前兵/后兵 name; append coordinates.
        if piece.kind == .pawn && sameFile.count > 1 {
            needsCoordinates = needsCoordinates || (0..<9).contains { col in
                col != move.from.col && Square.all.filter { $0.col == col && self[$0] == piece }.count > 1
            }
        }
        let deltaRow = move.to.row - move.from.row
        let action = deltaRow == 0 ? "平" : (deltaRow * piece.side.forward > 0 ? "进" : "退")
        let target: String
        if deltaRow == 0 || [.horse, .advisor, .elephant].contains(piece.kind) {
            target = fileNumber(move.to.col, side: piece.side)
        } else {
            target = number(abs(deltaRow), side: piece.side)
        }
        let value = prefix + action + target
        return needsCoordinates ? value + "（\(move.from.coordinate)→\(move.to.coordinate)）" : value
    }

    private func fileNumber(_ col: Int, side: Side) -> String {
        number(side == .red ? 9 - col : col + 1, side: side)
    }

    private func number(_ value: Int, side: Side) -> String {
        let chinese = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return side == .red && chinese.indices.contains(value) ? chinese[value] : String(value)
    }

    private func pseudoDestinations(from: Square, piece: Piece) -> [Square] {
        let deltas: [(Int, Int)]
        switch piece.kind {
        case .king: deltas = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        case .advisor: deltas = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        case .elephant: deltas = [(2, 2), (2, -2), (-2, 2), (-2, -2)]
        case .horse: deltas = [(2, 1), (2, -1), (-2, 1), (-2, -1), (1, 2), (-1, 2), (1, -2), (-1, -2)]
        case .pawn:
            deltas = piece.side.hasCrossedRiver(row: from.row) ? [(piece.side.forward, 0), (0, 1), (0, -1)] : [(piece.side.forward, 0)]
        case .rook, .cannon:
            var result: [Square] = []
            for (dr, dc) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                var target = Square(row: from.row + dr, col: from.col + dc)
                var screened = false
                while target.isValid {
                    if self[target] == nil {
                        if !screened { result.append(target) }
                    } else if piece.kind == .rook {
                        result.append(target)
                        break
                    } else if !screened {
                        screened = true
                    } else {
                        result.append(target)
                        break
                    }
                    target = Square(row: target.row + dr, col: target.col + dc)
                }
            }
            return result
        }
        return deltas.compactMap { dr, dc in
            let target = Square(row: from.row + dr, col: from.col + dc)
            return target.isValid && attacks(from: from, to: target, piece: piece) ? target : nil
        }
    }

    private func attacks(from: Square, to: Square, piece: Piece) -> Bool {
        guard from != to, from.isValid, to.isValid else { return false }
        let dr = to.row - from.row
        let dc = to.col - from.col
        switch piece.kind {
        case .king:
            if dc == 0, self[to] == Piece(side: piece.side.opponent, kind: .king), interveningPieces(from: from, to: to) == 0 {
                return true
            }
            return abs(dr) + abs(dc) == 1 && piece.side.palaceContains(to)
        case .advisor:
            return abs(dr) == 1 && abs(dc) == 1 && piece.side.palaceContains(to)
        case .elephant:
            return abs(dr) == 2 && abs(dc) == 2 && !piece.side.hasCrossedRiver(row: to.row)
                && self[Square(row: from.row + dr / 2, col: from.col + dc / 2)] == nil
        case .horse:
            guard (abs(dr) == 2 && abs(dc) == 1) || (abs(dr) == 1 && abs(dc) == 2) else { return false }
            let leg = Square(row: from.row + (abs(dr) == 2 ? dr / 2 : 0), col: from.col + (abs(dc) == 2 ? dc / 2 : 0))
            return self[leg] == nil
        case .rook:
            return interveningPieces(from: from, to: to) == 0
        case .cannon:
            let count = interveningPieces(from: from, to: to)
            return self[to] == nil ? count == 0 : count == 1
        case .pawn:
            return (dr == piece.side.forward && dc == 0)
                || (dr == 0 && abs(dc) == 1 && piece.side.hasCrossedRiver(row: from.row))
        }
    }

    /// nil for a diagonal; otherwise the number strictly between the endpoints.
    private func interveningPieces(from: Square, to: Square) -> Int? {
        guard from != to, from.row == to.row || from.col == to.col else { return nil }
        let dr = from.row == to.row ? 0 : (to.row > from.row ? 1 : -1)
        let dc = from.col == to.col ? 0 : (to.col > from.col ? 1 : -1)
        var cursor = Square(row: from.row + dr, col: from.col + dc)
        var count = 0
        while cursor != to {
            if self[cursor] != nil { count += 1 }
            cursor = Square(row: cursor.row + dr, col: cursor.col + dc)
        }
        return count
    }
}
