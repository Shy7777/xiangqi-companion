import Foundation

enum AnalysisViewMode: String, CaseIterable, Identifiable {
    case one, two, three, sequence
    var id: String { rawValue }
    var title: String { switch self { case .one: return "Top 1"; case .two: return "Top 2"; case .three: return "Top 3"; case .sequence: return "双方五步" } }
    var count: Int { switch self { case .two: return 2; case .three: return 3; default: return 1 } }
}

struct AnalysisVariation: Identifiable {
    let id = UUID()
    let positions: [Position]
    let moves: [Move]
    let names: [String]
    let depth: Int
    let truncated: Bool
    /// Store an immutable, legally replayed line. A new engine result or a move
    /// on the main board can never change the open preview's starting position.
    init(position: Position, pv: [String], depth: Int) {
        var positions = [position], moves: [Move] = [], names: [String] = []
        var current = position
        for value in pv.prefix(5) {
            guard let move = Move(uci: value), current.legalMoves(from: move.from).contains(move),
                  let next = try? current.applying(move: move) else { break }
            names.append(current.notation(for: move)); moves.append(move); positions.append(next); current = next
        }
        self.positions = positions; self.moves = moves; self.names = names; self.depth = depth
        truncated = moves.count < min(5, pv.count)
    }
}
