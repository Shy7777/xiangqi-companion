import Foundation

@main struct AnalysisVariationTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ reason: String) { precondition(value(), reason); checks += 1 }
        check(AnalysisViewMode.allCases.map(\.count) == [1, 2, 3, 1], "Candidate modes must not show unselected arrows")
        let empty = AnalysisVariation(position: .initial, pv: [], depth: 1)
        check(empty.positions == [.initial] && empty.moves.isEmpty && !empty.truncated, "Empty PV invents no moves")
        let invalid = AnalysisVariation(position: .initial, pv: ["a0a9"], depth: 2)
        check(invalid.moves.isEmpty && invalid.truncated, "Illegal first move must stop the line")
        var current = Position.initial, pv: [String] = [], expected = [current]
        for index in 0..<10 {
            let legal = current.legalMoves(), move = legal[(index * 13) % legal.count]
            pv.append(move.uci); current = try current.applying(move: move); expected.append(current)
        }
        for length in 1...10 {
            let result = AnalysisVariation(position: .initial, pv: Array(pv.prefix(length)), depth: length)
            check(result.positions == Array(expected.prefix(min(5, length) + 1)), "PV must replay successive sides from its own start")
            check(result.names.count == min(5, length) && result.depth == length && !result.truncated, "Metadata or limit changed")
        }
        let broken = AnalysisVariation(position: .initial, pv: [pv[0], "bad", pv[2]], depth: 6)
        check(broken.moves.count == 1 && broken.truncated && broken.positions.last == expected[1], "Never skip a broken intermediate move")
        print("PASS \(checks) analysis modes / five-ply legal preview / snapshot isolation checks")
    }
}
