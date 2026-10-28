import Foundation

enum HistoryRuleKind: String, Sendable, Equatable {
    case warning
    case drawSuggestion
    case rulingNeeded
}

struct HistoryRuleStatus: Sendable, Equatable {
    let kind: HistoryRuleKind
    let title: String
    let detail: String
    let evidence: [String]
}

/// Advisory only: never ends a game, changes a result, or declares a rules violation.
enum GameHistoryRules {
    /// The caller supplies an already legal history. This checks prefix shape and exact
    /// board transitions, not a second legal-move replay. Future positions are never read.
    /// Inconsistent input returns nil instead of drawing conclusions from broken evidence.
    static func inspect(positions: [Position], moves: [Move], cursor: Int) -> HistoryRuleStatus? {
        guard !positions.isEmpty, positions.count - 1 == moves.count,
              cursor >= 0, cursor <= moves.count, positions.indices.contains(cursor) else { return nil }
        let current = positions[cursor]
        guard positions[0].board.count == 90, current.board.count == 90,
              (try? positions[0].validate()) != nil, (try? current.validate()) != nil else { return nil }

        var occurrencePlies: [Int] = []
        var quietPlies = 0
        var lastCapture: Int?
        var previousPieceCount = positions[0].board.compactMap { $0 }.count
        for ply in 0...cursor {
            let after = positions[ply]
            guard after.board.count == 90 else { return nil }
            if ply > 0 {
                let before = positions[ply - 1]
                let move = moves[ply - 1]
                guard move.from.isValid, move.to.isValid, move.from != move.to,
                      let moving = before[move.from], moving.side == before.sideToMove,
                      after.sideToMove == before.sideToMove.opponent,
                      after[move.from] == nil, after[move.to] == moving else { return nil }
                if let target = before[move.to], target.side == moving.side || target.kind == .king { return nil }
                var count = 0
                for index in 0..<90 {
                    if after.board[index] != nil { count += 1 }
                    if index != move.from.index && index != move.to.index,
                       before.board[index] != after.board[index] { return nil }
                }
                let captured = before[move.to] != nil
                guard count == previousPieceCount - (captured ? 1 : 0) else { return nil }
                if count < previousPieceCount {
                    quietPlies = 0
                    lastCapture = ply
                } else {
                    quietPlies += 1
                }
                previousPieceCount = count
            }
            // Position equality includes both board and side-to-move, not move counters.
            if after == current { occurrencePlies.append(ply) }
        }

        let repeats = occurrencePlies.count
        let recentOccurrences = occurrencePlies.suffix(8).map(String.init).joined(separator: "、")
        let repetitionEvidence = "相同棋面及行棋方共出现 \(repeats) 次；半步位置：\(recentOccurrences)\(repeats > 8 ? "（仅列最近 8 次）" : "")。"
        let quietEvidence = lastCapture.map { "第 \($0) 半步吃子后，连续 \(quietPlies) 半步未吃子。" }
            ?? "自本段记录起，连续 \(quietPlies) 半步未吃子；未推断记录开始之前的历史。"

        if repeats >= 2 {
            let start = occurrencePlies[repeats - 2]
            var turns: [Side: Int] = [.red: 0, .black: 0]
            var checks: [Side: Int] = [.red: 0, .black: 0]
            for ply in start..<cursor {
                let mover = positions[ply].sideToMove
                turns[mover, default: 0] += 1
                if positions[ply + 1].isInCheck(mover.opponent) { checks[mover, default: 0] += 1 }
            }
            let redEvery = turns[.red, default: 0] > 0 && checks[.red] == turns[.red]
            let blackEvery = turns[.black, default: 0] > 0 && checks[.black] == turns[.black]
            if redEvery || blackEvery {
                let both = redEvery && blackEvery
                let side = redEvery ? "红方" : "黑方"
                return HistoryRuleStatus(
                    kind: .rulingNeeded,
                    title: both ? "双向将军循环，需裁决" : "\(side)连续将军循环，需裁决",
                    detail: "最近一次闭合循环内，\(both ? "双方各自每着" : side + "每着")都形成将军。请核对长将及重复局面规则；这不是正式违规、判负或判和结论，未自动结算。",
                    evidence: [repetitionEvidence, "仅检查最近循环：第 \(start) 至 \(cursor) 半步。",
                               "红方 \(checks[.red, default: 0])/\(turns[.red, default: 0]) 着将军；黑方 \(checks[.black, default: 0])/\(turns[.black, default: 0]) 着将军。"]
                )
            }
            let chases = directChases(positions: positions, moves: moves, start: start, end: cursor)
            if !chases.isEmpty {
                let sides = Set(chases.map(\.side))
                let who = sides.count == 2 ? "双方" : chases[0].side.label
                return HistoryRuleStatus(
                    kind: .rulingNeeded,
                    title: "\(who)疑似长捉，需裁决",
                    detail: "最近闭合循环内，\(who)各自至少两着、且每着都由刚移动的攻子新产生对同一敌子的合法吃子威胁。这里只识别直接新威胁；未判断兑子、保护与长捉规则例外，不认定必然违规，也不自动判胜负。",
                    evidence: [repetitionEvidence, "按棋子身份跟踪目标，不把同类棋子或同一格当作同一敌子；仅检查第 \(start) 至 \(cursor) 半步。"]
                        + chases.map { chase in
                            "\(chase.side.label)追逐同一\(chase.target.side.label)\(chase.target.symbol)（循环起点 \(chase.square.coordinate)）："
                                + chase.attacks.suffix(6).joined(separator: "；")
                                + (chase.attacks.count > 6 ? "（共 \(chase.attacks.count) 着，仅列最近 6 着）" : "") + "。"
                        }
                )
            }
        }

        if current.board.compactMap({ $0 }).allSatisfy({ [.king, .advisor, .elephant].contains($0.kind) }) {
            return HistoryRuleStatus(
                kind: .drawSuggestion, title: "双方已无攻子，建议确认和棋",
                detail: "当前双方只剩将帅、士仕、象相。可按所采用的规则确认和棋；本提示不自动结束对局。",
                evidence: ["棋盘中没有车、马、炮、兵卒。"]
            )
        }
        if quietPlies >= 100 {
            return HistoryRuleStatus(
                kind: .drawSuggestion, title: "连续 \(quietPlies) 半步未吃子，和棋建议",
                detail: "已达到本应用的 100 半步观察阈值。正式自然限着等条件应依所采用的规则核对；本工具不据此自动判和。",
                evidence: [quietEvidence, "70 / 100 半步是训练预警与建议阈值，不是正式裁决。"]
            )
        }
        if repeats >= 3 {
            return HistoryRuleStatus(
                kind: .drawSuggestion, title: "同一局面已出现 \(repeats) 次，和棋建议",
                detail: "请按所采用的规则核对重复过程。这只是和棋建议；有限的直接追逐检测不能排除所有长捉情形，也不会自动结束对局。",
                evidence: [repetitionEvidence, "最近循环未出现某方每着均将军，或每着直接新威胁同一敌子的情形。"]
            )
        }
        if quietPlies >= 70 {
            return HistoryRuleStatus(
                kind: .warning, title: "连续 \(quietPlies) 半步未吃子，留意和棋条件",
                detail: "已达到本应用的 70 半步预警阈值。可考虑改变局面；后续 100 半步仅触发和棋建议，不会自动结算。",
                evidence: [quietEvidence]
            )
        }
        if repeats >= 2 {
            return HistoryRuleStatus(
                kind: .warning, title: "同一局面第二次出现",
                detail: "留意继续重复。本工具没有确认长捉；有限的直接追逐检测不能排除所有长捉情形，也未自动裁决。",
                evidence: [repetitionEvidence, "最近循环未出现某方每着均将军，或每着直接新威胁同一敌子的情形。"]
            )
        }
        return nil
    }

    private struct DirectChase {
        let side: Side
        let target: Piece
        let square: Square
        let attacks: [String]
    }

    /// Deliberately narrower than tournament chase rules. A target must receive a
    /// new legal capture threat from the piece that just moved, on *every* turn
    /// of the chasing side, with at least two such turns in the latest cycle.
    /// Only rook/horse/cannon/pawn movers are considered. Discovered threats,
    /// exchange value, protected-piece exemptions and combined tactics are not
    /// inferred. Fixed 90-cell identity tracking and two single-origin legal-move
    /// queries per cycle ply keep work linear in the supplied history length;
    /// this never enumerates full-board legal moves or invokes an engine.
    private static func directChases(positions: [Position], moves: [Move], start: Int, end: Int) -> [DirectChase] {
        let initial = positions[start]
        var identities: [Int?] = initial.board.enumerated().map { $0.element == nil ? nil : $0.offset }
        var common: [Side: Set<Int>] = [:]
        var counts: [Side: Int] = [:]
        var evidence: [Side: [Int: [String]]] = [:]
        for ply in start..<end {
            let before = positions[ply], after = positions[ply + 1], move = moves[ply]
            let side = before.sideToMove
            counts[side, default: 0] += 1
            // A true closed board cycle cannot restore captured pieces. Refuse
            // an unexpected capture instead of assigning a new target identity.
            guard before[move.to] == nil, let movingID = identities[move.from.index], let moving = before[move.from] else { return [] }
            let originalIDs = identities
            identities[move.to.index] = movingID; identities[move.from.index] = nil
            var newTargets = Set<Int>()
            if [.rook, .horse, .cannon, .pawn].contains(moving.kind) {
                // The threat is conditional on the opponent not removing it;
                // setting the hypothetical mover reuses exact native self-check
                // and piece-movement rules, without pretending a reply was played.
                var hypothetical = after; hypothetical.sideToMove = side
                let oldTargets = Set(before.legalMoves(from: move.from).compactMap { capture -> Int? in
                    guard let target = before[capture.to], target.side != side, target.kind != .king else { return nil }
                    return originalIDs[capture.to.index]
                })
                for capture in hypothetical.legalMoves(from: move.to) {
                    guard let target = after[capture.to], target.side != side, target.kind != .king,
                          let targetID = identities[capture.to.index], !oldTargets.contains(targetID) else { continue }
                    newTargets.insert(targetID)
                    evidence[side, default: [:]][targetID, default: []].append("第 \(ply + 1) 半步 \(move.uci) 后可吃 \(capture.to.coordinate)")
                }
            }
            common[side] = common[side].map { $0.intersection(newTargets) } ?? newTargets
        }
        return Side.allCases.flatMap { side -> [DirectChase] in
            guard counts[side, default: 0] >= 2 else { return [] }
            return (common[side] ?? []).sorted().compactMap { targetID in
                guard let piece = initial.board[targetID], let attacks = evidence[side]?[targetID],
                      attacks.count == counts[side] else { return nil }
                return DirectChase(side: side, target: piece, square: Square(row: targetID / 9, col: targetID % 9), attacks: attacks)
            }
        }
    }
}
