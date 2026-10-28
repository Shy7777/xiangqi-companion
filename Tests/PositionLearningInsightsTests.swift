#if POSITION_LEARNING_INSIGHTS_TESTS
import Foundation

/// Offline board-fact contract tests. Every non-invalid fixture is validated by
/// the application's native rules; the capture oracle is legalMoves(), not a
/// second implementation of cannon, horse-leg, or king-safety rules.
@main
struct PositionLearningInsightsTests {
    struct TestFailure: Error, CustomStringConvertible {
        let description: String
    }

    static func main() throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            if !condition() { throw TestFailure(description: message) }
        }
        func rejects(_ message: String, _ operation: () throws -> Void) throws {
            var rejected = false
            do { try operation() } catch { rejected = true }
            try check(rejected, message)
        }
        func square(_ coordinate: String) -> Square { Square(coordinate: coordinate)! }
        func move(_ uci: String) -> Move { Move(uci: uci)! }
        func fixture(_ name: String, _ pieces: [(String, Character)], side: Side = .red) throws -> Position {
            var value = Position(board: Array(repeating: nil, count: 90), sideToMove: side)
            for (coordinate, symbol) in pieces {
                let location = square(coordinate)
                guard value[location] == nil, let piece = Piece(fenCharacter: symbol) else {
                    throw TestFailure(description: "Malformed fixture \(name): \(coordinate) \(symbol)")
                }
                value[location] = piece
            }
            do { try value.validate() }
            catch { throw TestFailure(description: "Invalid fixture \(name): \(error)") }
            return value
        }
        func mirrored(_ position: Position) throws -> Position {
            var result = Position(board: Array(repeating: nil, count: 90), sideToMove: position.sideToMove.opponent)
            for location in Square.all {
                if let piece = position[location] {
                    result[Square(row: 9 - location.row, col: 8 - location.col)] = Piece(side: piece.side.opponent, kind: piece.kind)
                }
            }
            try result.validate()
            return result
        }
        func mirrored(_ move: Move) -> Move {
            Move(from: Square(row: 9 - move.from.row, col: 8 - move.from.col),
                 to: Square(row: 9 - move.to.row, col: 8 - move.to.col))
        }
        func assertReading(_ position: Position, _ name: String) throws -> PositionReading {
            let original = position
            let reading = try PositionLearningInsights.read(position)
            var opponentTurn = position
            opponentTurn.sideToMove = position.sideToMove.opponent
            let captures = opponentTurn.legalMoves().filter {
                guard let target = opponentTurn[$0.to] else { return false }
                return target.side == position.sideToMove && target.kind != .king
            }
            try check(reading.side == position.sideToMove, "\(name): reading uses actual side to move")
            try check(reading.isInCheck == position.isInCheck(position.sideToMove), "\(name): native check state")
            try check(Set(reading.threats.map(\.move)) == Set(captures), "\(name): exact conditional legal-capture set")
            try check(reading.threats.count == Set(reading.threats.map(\.move)).count, "\(name): no duplicate threats")
            try check(!reading.objective.isEmpty && !reading.shortHint.isEmpty && !reading.details.isEmpty, "\(name): actionable nonempty reading")
            for threat in reading.threats {
                try check(threat.attacker == position[threat.move.from]
                          && threat.target == position[threat.move.to]
                          && threat.attacker.side == position.sideToMove.opponent
                          && threat.target.side == position.sideToMove
                          && threat.target.kind != .king, "\(name): threat carries actual attacker and target")
            }
            let repeated = try PositionLearningInsights.read(position)
            try check(reading == repeated && position == original, "\(name): deterministic and does not mutate board")
            return reading
        }
        func assertExplanation(_ position: Position, _ selected: Move, _ name: String) throws -> MoveLearningExplanation {
            let original = position
            try check(position.legalMoves(from: selected.from).contains(selected), "\(name): fixture move is natively legal")
            let after = try position.applying(move: selected)
            try after.validate()
            let result = try PositionLearningInsights.explain(move: selected, in: position)
            try check(!result.reason.isEmpty && !result.risk.isEmpty && !result.clue.isEmpty && !result.details.isEmpty, "\(name): all explanation levels present")
            try check(result.details.contains { $0.contains(position.notation(for: selected))
                && $0.contains(selected.from.coordinate) && $0.contains(selected.to.coordinate) }, "\(name): auditable notation and coordinates in details")
            try check(result.expandedText.contains(result.reason) && result.expandedText.contains(result.risk)
                      && result.expandedText.contains(result.clue), "\(name): expanded view preserves concise layers")
            try check(!["唯一正确", "必然获胜", "形成优势", "必胜着法", "稳稳赢"].contains { result.expandedText.contains($0) }, "\(name): board facts never invent engine-backed strategic conclusions")
            let repeated = try PositionLearningInsights.explain(move: selected, in: position)
            try check(result == repeated && original == position, "\(name): explanation is deterministic and read only")
            return result
        }

        let initial = try assertReading(.initial, "initial red")
        try check(initial.details.joined().contains("假设") && initial.details.joined().contains("收益"), "Conditional captures are not free-piece claims")
        var initialBlack = Position.initial
        initialBlack.sideToMove = .black
        _ = try assertReading(initialBlack, "initial black")

        let quiet = try fixture("quiet", [("d9", "k"), ("e0", "K"), ("a0", "R"), ("i9", "r")])
        let quietReading = try assertReading(quiet, "quiet")
        try check(quietReading.threats.isEmpty && quietReading.details.joined().contains("不排除"), "No immediate capture does not exclude checks or deeper threats")
        let quietExplanation = try assertExplanation(quiet, move("a0a1"), "quiet development")
        try check(quietExplanation.risk.contains("不能据此认定安全"), "No immediate capture is never advertised as safety")
        try check(quietExplanation.details.joined().contains("数量不等于局面优劣"), "Mobility count is not an advantage score")
        try check(!quietExplanation.reason.contains("胜率") && !quietReading.shortHint.contains("最佳"), "Board observations do not fabricate evaluation or best play")

        let threatened = try fixture("rook threat", [("d9", "k"), ("e0", "K"), ("a6", "r"), ("a2", "N")])
        let threatReading = try assertReading(threatened, "rook threat")
        try check(threatReading.threats.map(\.move.uci) == ["a6a2"], "A rook has the actual horse capture")
        try check(threatReading.shortHint.contains("a2"), "Short observation points to the threatened square")
        let escape = try assertExplanation(threatened, move("a2c3"), "horse escape")
        try check(escape.reason.contains("离开原来的吃子威胁") && escape.risk.contains("不能据此认定安全"), "Escaping one attack is limited to immediate legal captures")
        let blackThreat = try mirrored(threatened)
        let blackReading = try assertReading(blackThreat, "mirrored black threat")
        try check(blackReading.threats.map(\.move) == [mirrored(move("a6a2"))], "Black perspective is not tied to red coordinates")
        let blackEscape = try assertExplanation(blackThreat, mirrored(move("a2c3")), "black horse escape")
        try check(blackEscape.reason.contains("离开原来的吃子威胁"), "Both sides receive the same board-fact explanation")
        let newAttack = try fixture("new capture square", [("d9", "k"), ("e0", "K"), ("a0", "R"), ("c3", "n")])
        let newAttackExplanation = try assertExplanation(newAttack, move("a0c0"), "new capture square")
        try check(newAttackExplanation.reason.contains("增加了对马的吃子落点")
                  && newAttackExplanation.details.joined().contains("c0c3")
                  && newAttackExplanation.details.joined().contains("不是已经执行的连续两着"), "A new attack is conditional rather than an invented extra turn")

        let cannonOne = try fixture("one screen", [("d9", "k"), ("e0", "K"), ("a7", "c"), ("a4", "P"), ("a0", "R")])
        let cannonOneReading = try assertReading(cannonOne, "cannon one screen")
        try check(cannonOneReading.threats.contains { $0.move == move("a7a0") }, "Cannon captures through exactly one screen")
        let cannonZero = try fixture("zero screens", [("d9", "k"), ("e0", "K"), ("a7", "c"), ("a0", "R")])
        let cannonZeroReading = try assertReading(cannonZero, "cannon zero screens")
        try check(!cannonZeroReading.threats.contains { $0.move == move("a7a0") }, "An unobstructed cannon cannot capture like a rook")
        let cannonTwo = try fixture("two screens", [("d9", "k"), ("e0", "K"), ("a7", "c"), ("a4", "P"), ("a2", "N"), ("a0", "R")])
        let cannonTwoReading = try assertReading(cannonTwo, "cannon two screens")
        try check(!cannonTwoReading.threats.contains { $0.move == move("a7a0") }
                  && cannonTwoReading.threats.contains { $0.move == move("a7a2") }, "Cannon stops at its second occupied square")

        let horseOpen = try fixture("horse open leg", [("f9", "k"), ("e0", "K"), ("b4", "n"), ("d3", "R")])
        let horseOpenReading = try assertReading(horseOpen, "horse open leg")
        try check(horseOpenReading.threats.contains { $0.move == move("b4d3") }, "An unblocked horse can capture its actual destination")
        let horseBlocked = try fixture("horse blocked leg", [("f9", "k"), ("e0", "K"), ("b4", "n"), ("c4", "p"), ("d3", "R")])
        let horseBlockedReading = try assertReading(horseBlocked, "horse blocked leg")
        try check(!horseBlockedReading.threats.contains { $0.move == move("b4d3") }, "Horse-leg blockage removes geometric false threats")

        let pinned = try fixture("absolute rook pin", [("d9", "k"), ("e0", "K"), ("d6", "r"), ("d2", "R"), ("a6", "N")])
        let pinnedReading = try assertReading(pinned, "absolute rook pin")
        try check(!pinnedReading.threats.contains { $0.move == move("d6a6") }
                  && pinnedReading.threats.contains { $0.move == move("d6d2") }, "Pinned rook may take the pinning piece but cannot expose its king to capture a horse")

        let exchange = try fixture("capture with recapture", [("d9", "k"), ("e0", "K"), ("a0", "R"), ("a4", "n"), ("b4", "r"), ("c3", "N")])
        let exchangeExplanation = try assertExplanation(exchange, move("a0a4"), "capture with recapture")
        try check(exchangeExplanation.reason.contains("吃掉黑方的马"), "Capture explanation names the actual removed piece")
        try check(exchangeExplanation.risk.contains("有合法回吃") && exchangeExplanation.risk.contains("不代表")
                  && exchangeExplanation.risk.contains("交换划算"), "A recapture is legal evidence, not profitable-exchange advice")
        try check(exchangeExplanation.details.joined().contains("b4a4") && exchangeExplanation.details.joined().contains("c3a4"), "Two-ply recapture evidence contains both native legal moves")
        let exchangeBlack = try mirrored(exchange)
        let exchangeBlackExplanation = try assertExplanation(exchangeBlack, mirrored(move("a0a4")), "black capture with recapture")
        try check(exchangeBlackExplanation.reason.contains("吃掉红方的马") && exchangeBlackExplanation.risk.contains("有合法回吃"), "Recapture evidence respects black's side and piece colors")
        let noRecapture = try fixture("capture without recapture", [("d9", "k"), ("e0", "K"), ("a0", "R"), ("a4", "n"), ("b4", "r")])
        let noRecaptureExplanation = try assertExplanation(noRecapture, move("a0a4"), "capture without recapture")
        try check(noRecaptureExplanation.risk.contains("没有立即回吃"), "A hanging capturer is not hidden by the successful first capture")
        try check(noRecaptureExplanation.details.joined().contains("b4a4")
                  && noRecaptureExplanation.details.joined().contains("不排除其他补偿"), "No immediate recapture does not claim a forced net loss")
        let pinnedRecapture = try fixture("pinned recapturer", [("d9", "k"), ("e0", "K"), ("c0", "R"), ("c3", "n"), ("b3", "r"), ("e7", "r"), ("e2", "N")])
        let pinnedRecaptureExplanation = try assertExplanation(pinnedRecapture, move("c0c3"), "pinned recapturer")
        let takenByRook = try pinnedRecapture.applying(move: move("c0c3")).applying(move: move("b3c3"))
        try takenByRook.validate()
        try check(!takenByRook.legalMoves().contains(move("e2c3")), "Native oracle confirms the geometric horse recapture exposes its king")
        try check(pinnedRecaptureExplanation.risk.contains("没有立即回吃")
                  && pinnedRecaptureExplanation.details.joined().contains("b3c3"), "A pinned pseudo-recapture must not be taught as available defense")
        let unchallengedCapture = try fixture("capture without immediate reply", [("d9", "k"), ("e0", "K"), ("a0", "R"), ("a4", "n")])
        let unchallenged = try assertExplanation(unchallengedCapture, move("a0a4"), "capture without immediate reply")
        try check(unchallenged.risk.contains("不能据此认定安全")
                  && unchallenged.details.joined().contains("单次吃子不等于净得子"), "No immediate capture reply is still not a safety or net-gain guarantee")

        let lineOpen = try fixture("block attack line", [("d9", "k"), ("e0", "K"), ("a6", "r"), ("a0", "N"), ("b2", "R")])
        let block = try assertExplanation(lineOpen, move("b2a2"), "block attack line")
        try check(block.reason.contains("己方马") && block.reason.contains("挡住") && block.reason.contains("通路"), "Interposition explains the actual rook-line mechanism protecting another piece")
        try check(block.risk.contains("刚走的车") && block.details.joined().contains("a6a2"), "Blocking one attack must disclose that the blocking rook itself is capturable")
        let lineBlocked = try fixture("uncover attack line", [("d9", "k"), ("e0", "K"), ("a6", "r"), ("a0", "N"), ("a2", "R")])
        let uncover = try assertExplanation(lineBlocked, move("a2b2"), "uncover attack line")
        try check(uncover.risk.contains("己方马") && uncover.risk.contains("新出现")
                  && uncover.details.joined().contains("a6a0"), "Moving out of danger must not conceal a new attack on the piece left behind")
        let cannonScreen = try fixture("remove cannon screen", [("d9", "k"), ("e0", "K"), ("a7", "c"), ("a4", "N"), ("a0", "R")])
        let removeScreen = try assertExplanation(cannonScreen, move("a4c5"), "remove cannon screen")
        try check(removeScreen.reason.contains("改变了炮架") && removeScreen.reason.contains("己方车")
                  && removeScreen.details.joined().contains("a7a0"), "Removing a screen explains why the old cannon capture disappears")
        let blockLegBefore = try fixture("block horse leg", [("f9", "k"), ("e0", "K"), ("b4", "n"), ("d3", "R"), ("c0", "R")])
        let blockLeg = try assertExplanation(blockLegBefore, move("c0c4"), "block horse leg")
        try check(blockLeg.reason.contains("堵住对方马腿") && blockLeg.reason.contains("己方车")
                  && blockLeg.details.joined().contains("b4d3"), "Horse-leg defense names the geometric mechanism and old legal attack")
        let cannonDanger = try fixture("create enemy cannon screen", [("d9", "k"), ("e0", "K"), ("a7", "c"), ("a0", "N"), ("b2", "R")])
        let insertedScreen = try assertExplanation(cannonDanger, move("b2a2"), "create enemy cannon screen")
        try check(insertedScreen.risk.contains("己方马") && insertedScreen.risk.contains("新出现")
                  && insertedScreen.details.joined().contains("a7a0"), "Putting a piece in a cannon line may enable, not block, the enemy capture")
        try check(!insertedScreen.reason.contains("挡住对方炮") && !insertedScreen.reason.contains("保护己方马"), "Rook-style blocking must not be wrongly generalized to cannons")

        let checked = try fixture("red checked", [("d9", "k"), ("e0", "K"), ("e3", "r"), ("a2", "R")])
        let checkedReading = try assertReading(checked, "red checked")
        try check(checkedReading.isInCheck && checkedReading.objective.contains("先解除将军"), "In-check reading prioritizes legal evasion")
        let evade = try assertExplanation(checked, move("e0f0"), "king evasion")
        try check(evade.reason.contains("解除将军"), "A legal king evasion is explained by its actual immediate purpose")
        let interpose = try assertExplanation(checked, move("a2e2"), "check interposition")
        try check(interpose.reason.contains("解除将军") && interpose.details.joined().contains("e3e2"), "A legal block resolves check but its piece may be captured next")
        let checkedBlack = try mirrored(checked)
        let checkedBlackReading = try assertReading(checkedBlack, "black checked")
        try check(checkedBlackReading.isInCheck && checkedBlackReading.objective.contains("先解除将军"), "Black check is treated symmetrically")
        _ = try assertExplanation(checkedBlack, mirrored(move("e0f0")), "black king evasion")
        let givingCheck = try fixture("give nonterminal check", [("e9", "k"), ("f0", "K"), ("d1", "R")])
        let checkExplanation = try assertExplanation(givingCheck, move("d1e1"), "give nonterminal check")
        try check(checkExplanation.reason.contains("形成将军") && checkExplanation.clue.contains("不把有将军等同于必胜"), "Giving check is a rule fact, not a forced-win claim")

        let mateBefore = try fixture("mating move", [("d9", "k"), ("e0", "K"), ("a2", "r"), ("d1", "r"), ("g2", "n")], side: .black)
        let mateExplanation = try assertExplanation(mateBefore, move("a2e2"), "mating move")
        let mate = try mateBefore.applying(move: move("a2e2"))
        try check(mate.isInCheck(.red) && mate.legalMoves().isEmpty, "Native checkmate fixture is truly terminal")
        let mateReading = try assertReading(mate, "checkmate")
        try check(mateReading.objective.contains("终局") && mateReading.shortHint.contains("不再要求走下一步"), "Checkmate reading does not solicit a nonexistent next move")
        try check(mateExplanation.reason.contains("无合法着") && mateExplanation.risk.contains("规则结论"), "Actual native terminal state is distinguished from finite-search evaluation")
        try rejects("A king cannot escape onto an enemy horse attack") {
            _ = try PositionLearningInsights.explain(move: move("e0f0"), in: mate)
        }
        let stalemate = try fixture("stalemate", [("d9", "k"), ("e0", "K"), ("d2", "r"), ("f2", "r"), ("c0", "n")])
        try check(!stalemate.isInCheck(.red) && stalemate.legalMoves().isEmpty, "Native stalemate fixture is non-check and terminal")
        let stalemateReading = try assertReading(stalemate, "stalemate")
        try check(!stalemateReading.isInCheck && stalemateReading.objective.contains("终局")
                  && stalemateReading.shortHint.contains("不能用停着"), "Xiangqi stalemate must not be presented as a legal pass")

        for illegal in [move("a0b1"), move("a1a2"), move("i9i8"), Move(from: square("a0"), to: square("a0")), Move(from: square("a0"), to: Square(row: -1, col: 0))] {
            try rejects("Illegal move \(illegal.uci) must not receive teaching prose") {
                _ = try PositionLearningInsights.explain(move: illegal, in: quiet)
            }
        }
        try rejects("Own-piece capture must be rejected") {
            _ = try PositionLearningInsights.explain(move: move("a0b0"), in: .initial)
        }
        try rejects("A move which ignores check must be rejected") {
            _ = try PositionLearningInsights.explain(move: move("a2b2"), in: checked)
        }
        var wrongTurn = checked
        wrongTurn.sideToMove = .black
        var noKing = quiet
        noKing[square("d9")] = nil
        var facing = quiet
        facing[square("d9")] = nil
        facing[square("e9")] = Piece(side: .black, kind: .king)
        var outsidePalace = quiet
        outsidePalace[square("e0")] = nil
        outsidePalace[square("a1")] = Piece(side: .red, kind: .king)
        let undersized = Position(board: [], sideToMove: .red)
        for (name, invalid) in [("previous side still in check", wrongTurn), ("missing king", noKing), ("facing generals", facing), ("king outside palace", outsidePalace), ("invalid board size", undersized)] {
            try rejects("Invalid position \(name) must reject reading") {
                _ = try PositionLearningInsights.read(invalid)
            }
            try rejects("Invalid position \(name) must reject explanation before applying any move") {
                _ = try PositionLearningInsights.explain(move: move("a0a1"), in: invalid)
            }
        }

        print("PASS: PositionLearningInsights native board facts; \(assertions) assertions; no engine, network, or persisted writes")
    }
}
#endif
