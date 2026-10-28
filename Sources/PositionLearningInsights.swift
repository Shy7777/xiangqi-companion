import Foundation

/// A legal, immediate capture opportunity, not a claim of material profit or
/// of the opponent's intended/best move. The target is never a general.
struct CaptureThreat: Equatable, Sendable {
    let move: Move
    let attacker: Piece
    let target: Piece
}

struct PositionReading: Equatable, Sendable {
    let side: Side
    let isInCheck: Bool
    let objective: String
    let shortHint: String
    let details: [String]
    /// Opponent captures if the board is held fixed and they are given a turn.
    /// This is deliberately a conditional observation, not an actual null move.
    let threats: [CaptureThreat]
}

struct MoveLearningExplanation: Equatable, Sendable {
    let reason: String
    let risk: String
    let clue: String
    let details: [String]

    var expandedText: String { ([reason, risk, clue] + details).joined() }
}

/// Small deterministic board-reading layer. No engine, score, network, source
/// title, history, or learning state participates in these observations.
enum PositionLearningInsights {
    static func read(_ position: Position) throws -> PositionReading {
        try position.validate()
        let side = position.sideToMove
        let checked = position.isInCheck(side)
        let own = position.legalMoves()
        let threats = captures(in: position, by: side.opponent)
        let objective: String, hint: String
        if own.isEmpty {
            objective = "当前一方已经没有合法着，先核对终局。"
            hint = checked ? "正在被将且无合法应将；不再要求走下一步。" : "没有合法着；象棋中不能用停着继续。"
        } else if checked {
            objective = "先解除将军，再考虑进攻。"
            hint = "先找合法应将：移将、吃掉将军子或挡住攻击线；不是每种方法都一定可行。"
        } else if let threat = threats.first {
            objective = "先核对受攻击棋子的去留，再决定是否主动进攻。"
            hint = "先看\(label(threat.target, at: threat.move.to))：如果现在换对方走，\(label(threat.attacker, at: threat.move.from))有合法吃子落点。"
        } else if own.contains(where: { position[$0.to] != nil }) {
            objective = "先比较能吃的子与对方回吃，再选下一步。"
            hint = "找到一个吃子候选后，继续检查对方能否立即回吃；能吃不等于应该吃。"
        } else {
            objective = "先看将帅安全，再找活动受限的棋子。"
            hint = "检查车、马、炮的通路和落点，选一个能说明目的的调动；活动多不自动等于优势。"
        }
        var details = ["\(side.label)行棋，当前\(checked ? "正在被将" : "未被将军")，共有 \(own.count) 着合法选择。"]
        if threats.isEmpty {
            details.append("保持棋面不变并假设对方行棋，未发现对方一步合法吃子；这不排除将军或多步威胁。")
        } else {
            details.append("以下吃子检查假设棋面保持不变、换对方行棋，不代表对方能跳过你的回合。")
            details += threats.prefix(3).map { "\(label($0.attacker, at: $0.move.from))可吃\(label($0.target, at: $0.move.to))（\($0.move.uci)）；尚未判断交换收益。" }
        }
        return PositionReading(side: side, isInCheck: checked, objective: objective, shortHint: hint,
                               details: details, threats: threats)
    }

    static func explain(move: Move, in position: Position) throws -> MoveLearningExplanation {
        try position.validate()
        let after = try position.applying(move: move)
        // applying() has already established the source piece and both kings.
        let moving = position[move.from]!
        let side = moving.side
        let oldThreats = captures(in: position, by: side.opponent)
        let replies = after.legalMoves()
        let afterThreats = captures(in: after, legalMoves: replies)
        let targetSquares = Set(afterThreats.map { $0.move.to })
        let movedOutOfThreat = oldThreats.contains { $0.move.to == move.from }
            && !targetSquares.contains(move.to)
        let relieved = oldThreats.first { $0.move.to != move.from && !targetSquares.contains($0.move.to) }
        let oldOwn = Set(captures(in: position, by: side).map { $0.move.to })
        let newOwn = captures(in: after, by: side).first {
            $0.move.from == move.to && !oldOwn.contains($0.move.to)
        }
        let captured = position[move.to]
        let checking = after.isInCheck(side.opponent)
        let reason: String
        if replies.isEmpty {
            reason = "这步之后对方无合法着，按当前棋规已结束对局。"
        } else if position.isInCheck(side) {
            reason = "这步先解除将军，让己方将帅不再处于直接攻击中。"
        } else if let captured {
            reason = "这步吃掉\(captured.side.label)的\(captured.symbol)，接着要核对对方能否回吃。"
        } else if checking {
            reason = "这步形成将军，对方必须先解除将军。"
        } else if movedOutOfThreat {
            reason = "这步让\(moving.symbol)离开原来的吃子威胁，落点暂未被对方直接合法吃到。"
        } else if let relieved {
            reason = defenseReason(for: relieved, move: move, after: after)
                ?? "这步使对方原先对己方\(relieved.target.symbol)的直接吃子暂时不再成立。"
        } else if let newOwn {
            reason = "这步为\(moving.symbol)增加了对\(newOwn.target.symbol)的吃子落点，但对方仍有应对机会。"
        } else if [.rook, .horse, .cannon].contains(moving.kind),
                  move.from.row == (side == .red ? 9 : 0), move.to.row != move.from.row {
            reason = "这步把\(moving.symbol)从己方底线走出，下一步重点检查它能接通哪些路线。"
        } else if [.rook, .horse, .cannon, .pawn].contains(moving.kind),
                  !side.hasCrossedRiver(row: move.from.row), side.hasCrossedRiver(row: move.to.row) {
            reason = "这步让\(moving.symbol)越过河界，需要同时检查对方能否直接吃到它。"
        } else {
            reason = "这步调整\(moving.symbol)的活动位置；先看新通路，再核对对手的应对。"
        }

        var details = ["\(position.notation(for: move))（\(move.from.coordinate) → \(move.to.coordinate)）。"]
        if let captured { details.append("这一步实际移除了\(captured.side.label)的\(captured.symbol)，但单次吃子不等于净得子。") }
        if checking { details.append("走后确实将军；\(replies.count) 着合法应对已考虑将帅安全，不代表每着同样好。") }
        if let relieved {
            details.append("走前假设对方行棋时有 \(relieved.move.uci)；走后对方合法着中已没有任何吃\(relieved.move.to.coordinate)这枚\(relieved.target.symbol)的着法。")
        }
        if let newOwn {
            details.append("保持走后棋面不变、暂不计对手应对时，己方新出现 \(newOwn.move.uci) 这一合法吃子落点；它不是已经执行的连续两着。")
        }
        var sameSideAfter = after
        sameSideAfter.sideToMove = side
        let oldMobility = position.legalMoves(from: move.from).count
        let newMobility = sameSideAfter.legalMoves(from: move.to).count
        details.append("仅作活动检查：该子合法落点由 \(oldMobility) 个变为 \(newMobility) 个（保持棋面、暂不计对手应对）；数量不等于局面优劣。")

        let risk: String
        if replies.isEmpty {
            risk = "这是无合法着的规则结论，不需要把有限搜索分数当作胜负证明。"
        } else if let threat = afterThreats.first(where: { $0.move.to == move.to }) {
            let taken = try after.applying(move: threat.move)
            let recapture = taken.legalMoves().first { $0.to == threat.move.to }
            if let recapture {
                risk = "对方现在可以吃到刚走的\(moving.symbol)；下面这条吃子变化中你有合法回吃，但不代表所有吃法都能回吃或交换划算。"
                details.append("可核对的一组吃回：\(after.notation(for: threat.move))（\(threat.move.uci)）→\(taken.notation(for: recapture))（\(recapture.uci)）。只证实两步合法，不评价最终得失。")
            } else {
                risk = "对方现在可以吃到刚走的\(moving.symbol)，并且这条吃子之后没有立即回吃落在同一格的合法着。"
                details.append("风险证据：\(after.notation(for: threat.move))（\(threat.move.uci)）。这不排除其他补偿，也不代表对方必然这样走。")
            }
        } else if let threat = afterThreats.first {
            let existed = oldThreats.contains { $0.move.to == threat.move.to }
            risk = "留意己方\(threat.target.symbol)：对方\(existed ? "仍然" : "新出现")有直接合法吃子机会，别只盯刚移动的棋子。"
            details.append("走后风险证据：\(after.notation(for: threat.move))（\(threat.move.uci)）可吃\(label(threat.target, at: threat.move.to))；不代表这是最佳应招。")
        } else {
            risk = "走后暂未发现对方一步合法吃子；仍需检查将军与更长的变化，不能据此认定安全。"
        }
        let clue: String
        if position.isInCheck(side) || checking {
            clue = "观察线索：先沿将军子的攻击线检查应将，不把有将军等同于必胜。"
        } else if captured != nil || !afterThreats.isEmpty {
            clue = "观察线索：把吃子和回吃各走一步，再比较盘上实际留下的棋子。"
        } else if newOwn != nil {
            clue = "观察线索：轮到对手时，它能否移开目标、挡路或制造将军？逐着验证。"
        } else {
            clue = "观察线索：车看通路、炮看隔子、马看马腿，再检查调动后有没有漏掉原来保护的棋子。"
        }
        return MoveLearningExplanation(reason: reason, risk: risk, clue: clue, details: details)
    }

    /// Name a defensive mechanism only when both the before/after legal-capture
    /// comparison and the corresponding geometry establish it.
    private static func defenseReason(for threat: CaptureThreat, move: Move, after: Position) -> String? {
        guard after[threat.move.from] == threat.attacker else { return nil }
        let from = threat.move.from, to = threat.move.to
        func strictlyBetween(_ square: Square) -> Bool {
            if from.row == to.row {
                return square.row == from.row && square.col > min(from.col, to.col) && square.col < max(from.col, to.col)
            }
            if from.col == to.col {
                return square.col == from.col && square.row > min(from.row, to.row) && square.row < max(from.row, to.row)
            }
            return false
        }
        switch threat.attacker.kind {
        case .rook where strictlyBetween(move.to):
            return "这步挡住对方车原先吃己方\(threat.target.symbol)的通路。"
        case .cannon where strictlyBetween(move.from) || strictlyBetween(move.to):
            return "这步改变了炮架，对方炮原先吃己方\(threat.target.symbol)的路线暂时不再成立。"
        case .horse:
            let dr = to.row - from.row, dc = to.col - from.col
            let leg = Square(row: from.row + (abs(dr) == 2 ? dr / 2 : 0),
                             col: from.col + (abs(dc) == 2 ? dc / 2 : 0))
            if move.to == leg { return "这步堵住对方马腿，阻止它原先对己方\(threat.target.symbol)的直接吃子。" }
            return nil
        default: return nil
        }
    }

    private static func captures(in position: Position, by side: Side) -> [CaptureThreat] {
        var assumed = position
        assumed.sideToMove = side
        return captures(in: assumed, legalMoves: assumed.legalMoves())
    }

    private static func captures(in position: Position, legalMoves: [Move]) -> [CaptureThreat] {
        legalMoves.compactMap { move -> CaptureThreat? in
            guard let attacker = position[move.from], let target = position[move.to],
                  attacker.side != target.side, target.kind != .king else { return nil }
            return CaptureThreat(move: move, attacker: attacker, target: target)
        }.sorted {
            let lhs = priority($0.target.kind), rhs = priority($1.target.kind)
            return lhs == rhs ? $0.move.uci < $1.move.uci : lhs < rhs
        }
    }

    /// A stable display order only, not material values or a strategic ranking.
    private static func priority(_ kind: PieceKind) -> Int {
        switch kind {
        case .rook: return 0
        case .cannon: return 1
        case .horse: return 2
        case .pawn: return 3
        case .advisor: return 4
        case .elephant: return 5
        case .king: return 6
        }
    }

    private static func label(_ piece: Piece, at square: Square) -> String {
        "\(piece.side.label)\(piece.symbol)（\(square.coordinate)）"
    }
}
