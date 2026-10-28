#if GAME_HISTORY_RULES_TESTS
import Foundation

@main
struct GameHistoryRulesTests {
    struct History {
        var positions: [Position]
        var moves: [Move] = []
        init(_ initial: Position = .initial) { positions = [initial] }
        mutating func play(_ uci: String) throws {
            let move = Move(uci: uci)!
            positions.append(try positions.last!.applying(move: move))
            moves.append(move)
        }
        func status(_ cursor: Int? = nil) -> HistoryRuleStatus? {
            GameHistoryRules.inspect(positions: positions, moves: moves, cursor: cursor ?? moves.count)
        }
    }

    static func main() throws {
        func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
        var horse = History()
        let horseCycle = ["b0c2", "b9c7", "c2b0", "c7b9"]
        for move in horseCycle + horseCycle { try horse.play(move) }
        check(horse.status(0) == nil && horse.status(3) == nil, "Do not count future repetitions")
        check(horse.status(4)?.kind == .warning, "Two occurrences warn")
        check(horse.status(8)?.kind == .drawSuggestion, "Three occurrences suggest a draw")
        check(horse.status(4)?.detail.contains("没有确认长捉") == true, "Do not invent perpetual chase")
        check(horse.status(8)?.evidence.first?.contains("0、4、8") == true, "Repetition evidence is auditable")

        let rookInitial = try Position(fen: "4k4/3R5/9/9/9/4P4/9/9/9/4K4 w - - 0 1")
        var redChecks = History(rookInitial)
        for move in ["d8e8", "e9d9", "e8d8", "d9e9"] { try redChecks.play(move) }
        check(redChecks.status()?.kind == .rulingNeeded && redChecks.status()?.title.hasPrefix("红方") == true, "Red checks on every turn in a legal cycle")
        check(redChecks.status()?.evidence.last?.contains("红方 2/2") == true, "Report check counts, not just sequence length")
        var blackChecks = History(try Position(fen: "4k4/9/9/9/4p4/9/9/9/3r5/4K4 b - - 0 1"))
        for move in ["d1e1", "e0d0", "e1d1", "d0e0"] { try blackChecks.play(move) }
        check(blackChecks.status()?.kind == .rulingNeeded && blackChecks.status()?.title.hasPrefix("黑方") == true, "Black checks on every turn")
        var mixed = History(rookInitial)
        let mixedCycle = ["d8e8", "e9d9", "e8f8", "d9e9", "f8e8", "e9f9", "e8d8", "f9e9"]
        for move in mixedCycle { try mixed.play(move) }
        check(mixed.status()?.kind == .warning, "Some checking moves are not perpetual-check evidence")
        for move in mixedCycle { try mixed.play(move) }
        check(mixed.status()?.kind == .drawSuggestion, "Mixed-check threefold cycle remains advisory")
        var changedCycle = redChecks
        for move in mixedCycle { try changedCycle.play(move) }
        check(changedCycle.status()?.kind == .drawSuggestion, "An earlier all-check cycle does not make the latest mixed cycle perpetual check")
        let mutualStart = try Position(fen: "9/9/4kr3/9/9/9/5c3/9/5R3/4CK3 w - - 0 1")
        var mutual = History(mutualStart)
        for move in ["f1e1", "f3e3", "e1f1", "e3f3"] {
            try mutual.play(move)
            let next = mutual.positions.last!
            try next.validate()
            check(next.isInCheck(next.sideToMove) && !next.isInCheck(next.sideToMove.opponent), "Every mutual-cycle move is a legal countercheck")
        }
        check(mutual.positions.last! == mutualStart, "Legal mutual-check cycle closes")
        check(mutual.status()?.kind == .rulingNeeded && mutual.status()?.title == "双向将军循环，需裁决", "Mutual perpetual-check evidence needs a ruling, not an automatic draw")
        check(mutual.status()?.detail.contains("不是正式") == true && mutual.status()?.evidence.last?.contains("黑方 2/2") == true, "Mutual check has explicit claim boundaries and counts")

        // Follow physical piece identity, not the destination square: the same
        // horse alternates c2/a3 while the rook creates a new legal capture each turn.
        let chaseInitial = try Position(fen: "3k5/9/9/9/9/9/9/2n6/9/R3K4 w - - 0 1")
        var chase = History(chaseInitial)
        let chaseCycle = ["a0c0", "c2a3", "c0a0", "a3c2"]
        for move in chaseCycle { try chase.play(move); try chase.positions.last!.validate() }
        check(chase.positions.last! == chaseInitial && chase.status()?.kind == .rulingNeeded, "A legal physical-piece chase cycle is detected")
        check(chase.status()?.title == "红方疑似长捉，需裁决", "Name the actual chasing side without adjudicating")
        check(chase.status()?.evidence.last?.contains("循环起点 c2") == true && chase.status()?.evidence.last?.contains("可吃 a3") == true, "Moving target identity and actual threatened squares are evidence")
        check(chase.status()?.detail.contains("不认定必然违规") == true && chase.status()?.detail.contains("保护") == true, "Chase does not invent exchange or protected-piece rules")
        check(chase.status(3) == nil, "Unclosed chase evidence cannot read the future or report a closed cycle")
        let trimmedChase = GameHistoryRules.inspect(positions: Array(chase.positions.prefix(4)), moves: Array(chase.moves.prefix(3)), cursor: 3)
        check(trimmedChase == chase.status(3), "Takeback and cursor prefix agree")
        for move in chaseCycle { try chase.play(move) }
        check(chase.status()?.kind == .rulingNeeded && chase.status()?.evidence.first?.contains("3 次") == true, "Chase evidence precedes generic threefold draw suggestion")

        var blackChase = History(try Position(fen: "r3k4/9/2N6/9/9/9/9/9/9/3K5 b - - 0 1"))
        for move in ["a9c9", "c7a6", "c9a9", "a6c7"] { try blackChase.play(move) }
        check(blackChase.status()?.title == "黑方疑似长捉，需裁决", "Black-side chase is not tied to red coordinates")

        let mutualChaseInitial = try Position(fen: "5k3/9/2R6/9/3n5/9/9/9/9/4K4 w - - 0 1")
        var mutualChase = History(mutualChaseInitial)
        for move in ["c7d7", "d5b6", "d7d6", "b6c8", "d6c6", "c8e7", "c6c7", "e7d5"] {
            try mutualChase.play(move); try mutualChase.positions.last!.validate()
            check(!mutualChase.positions.last!.isInCheck(mutualChase.positions.last!.sideToMove), "Mutual chase fixture must not secretly be a checking cycle")
        }
        check(mutualChase.positions.last! == mutualChaseInitial, "Legal mutual direct-chase cycle closes")
        check(mutualChase.status()?.title == "双方疑似长捉，需裁决" && mutualChase.status()?.kind == .rulingNeeded, "Both sides can directly chase without inventing a winner")
        check(mutualChase.status()?.evidence.contains { $0.contains("红方追逐") && $0.contains("循环起点 d5") } == true
              && mutualChase.status()?.evidence.contains { $0.contains("黑方追逐") && $0.contains("循环起点 c7") } == true, "Each side needs its own physical target evidence")

        var staticAttack = History(try Position(fen: "3k5/9/9/9/n8/9/9/9/9/R3K4 w - - 0 1"))
        for move in ["a0a1", "d9d8", "a1a0", "d8d9"] { try staticAttack.play(move) }
        check(staticAttack.status()?.kind == .warning && staticAttack.status()?.title.contains("长捉") == false, "An already-existing static attack is not a new chase")

        var differentTargets = History(try Position(fen: "3k5/9/9/9/9/9/n8/2n6/9/R3K4 w - - 0 1"))
        for move in ["a0c0", "d9d8", "c0a0", "d8d9"] { try differentTargets.play(move) }
        check(differentTargets.status()?.kind == .warning, "Two horses of the same color/type are distinct targets")

        var interruptedChase = History(chaseInitial)
        let interruptedCycle = ["a0c0", "c2a3", "c0c1", "d9d8", "c1a1", "a3c2", "a1a0", "d8d9"]
        for move in interruptedCycle { try interruptedChase.play(move) }
        check(interruptedChase.positions.last! == chaseInitial && interruptedChase.status()?.kind == .warning, "Every own turn, not just two selected turns, must newly chase")
        var latestChanged = chase
        for move in interruptedCycle { try latestChanged.play(move) }
        check(latestChanged.status()?.kind == .drawSuggestion, "Earlier chase does not contaminate the latest interrupted cycle")

        // The moving rook is protecting its own king from the e-file rook.
        // Its apparent horizontal horse captures are illegal self-check, on both turns.
        var pinned = History(try Position(fen: "3kr4/9/9/9/9/9/9/2n6/4R4/4K4 w - - 0 1"))
        for move in ["e1e2", "c2a1", "e2e1", "a1c2"] { try pinned.play(move) }
        var hypotheticalCapture = pinned.positions[1]; hypotheticalCapture.sideToMove = .red
        check(!hypotheticalCapture.legalMoves(from: Move(uci: "e2c2")!.from).contains(Move(uci: "e2c2")!), "Pinned fixture's geometric attack is not a legal capture")
        check(pinned.status()?.kind == .warning, "Static king protection/pins cannot be mistaken for actual capture threats")

        var oppositeSide = History()
        for move in ["a0a1", "b9c7", "a1a2", "c7b9", "a2a0"] { try oppositeSide.play(move) }
        check(oppositeSide.positions[0].board == oppositeSide.positions[5].board && oppositeSide.positions[0].sideToMove != oppositeSide.positions[5].sideToMove, "Fixture differs only in side-to-move")
        check(oppositeSide.status() == nil, "A matching board with the other side to move is not repetition")

        var quiet = History()
        var visited = Set(quiet.positions)
        var seed: UInt64 = 91
        while quiet.moves.count < 100 {
            let current = quiet.positions.last!
            var choices: [(Move, Position)] = []
            for move in current.legalMoves().sorted(by: { $0.uci < $1.uci }) where current[move.to] == nil {
                let next = try current.applying(move: move)
                if !visited.contains(next), !next.isInCheck(next.sideToMove) { choices.append((move, next)) }
            }
            check(!choices.isEmpty, "A legal noncapturing unseen continuation exists")
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let chosen = choices[Int(seed % UInt64(choices.count))]
            quiet.moves.append(chosen.0); quiet.positions.append(chosen.1); visited.insert(chosen.1)
        }
        check(quiet.status(69) == nil, "69 halfmoves stays below the warning threshold")
        check(quiet.status(70)?.kind == .warning && quiet.status(70)?.title.contains("70") == true, "70 noncapturing halfmoves warn")
        check(quiet.status(99)?.kind == .warning, "99 halfmoves remains a warning")
        check(quiet.status(100)?.kind == .drawSuggestion && quiet.status(100)?.title.contains("100") == true, "100 halfmoves suggests, never adjudicates")
        let beforeCapture = quiet.positions.last!
        let captures = beforeCapture.legalMoves().filter { beforeCapture[$0.to] != nil }
        check(!captures.isEmpty, "Deterministic fixture offers a legal capture")
        try quiet.play(captures[0].uci)
        check(quiet.status() == nil, "A real capture resets the noncapture count")
        check(quiet.status(100)?.kind == .drawSuggestion, "A future capture cannot reset an earlier cursor")

        let noAttackers = History(try Position(fen: "3akab2/9/9/9/9/9/9/9/9/2BK1A3 w - - 0 1"))
        check(noAttackers.status()?.kind == .drawSuggestion && noAttackers.status()?.title.contains("无攻子") == true, "Only kings, advisors, and elephants")
        let pawn = History(try Position(fen: "4k4/9/9/9/9/4P4/9/9/9/3K5 w - - 0 1"))
        check(pawn.status() == nil, "A pawn is still an attacking piece")

        check(GameHistoryRules.inspect(positions: [], moves: [], cursor: 0) == nil, "Empty input")
        check(horse.status(-1) == nil && horse.status(9) == nil, "Cursor bounds")
        check(GameHistoryRules.inspect(positions: horse.positions, moves: [], cursor: 0) == nil, "Mismatched arrays")
        var broken = horse
        broken.positions[2].board = []
        check(broken.status(4) == nil, "Malformed prefix board fails closed")
        broken = horse; broken.positions[5].board = []
        broken.moves[4] = Move(from: Square(row: -50, col: 900), to: Square(row: 0, col: 0))
        check(broken.status(4) == horse.status(4), "Do not read malformed future positions or moves")
        broken = horse; broken.moves[0] = Move(uci: "a0a1")!
        check(broken.status() == nil, "Moves must explain the board transition")
        broken = horse; broken.positions[1].sideToMove = .red
        check(broken.status() == nil, "Turns must alternate")
        broken = horse; broken.positions[1].board[45] = Piece(side: .red, kind: .rook)
        check(broken.status() == nil, "An unexplained board mutation fails closed")
        let missingKings = Position(board: Array(repeating: nil, count: 90), sideToMove: .red)
        check(GameHistoryRules.inspect(positions: [missingKings], moves: [], cursor: 0) == nil, "Invalid current position is not a draw")
        print("GameHistoryRules tests passed: legal repetition, checking loops, identity-tracked direct chase and counterexamples, cursor isolation, 70/100 thresholds, capture reset, material, and malformed histories")
    }
}
#endif
