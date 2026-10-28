import Foundation

/// Stable piece identities for one real legal move. A course jump, import,
/// edited board or reversal is a fresh scene, never an invented animated line.
struct BoardMotionScene: Equatable {
    struct Token: Identifiable, Equatable {
        let id: Int
        let piece: Piece
        var square: Square
    }
    let position: Position
    let tokens: [Token]
    let isSingleMove: Bool

    init(position: Position) {
        self.position = position
        tokens = Square.all.compactMap { square in
            position[square].map { Token(id: square.index, piece: $0, square: square) }
        }
        isSingleMove = false
    }
    private init(position: Position, tokens: [Token]) {
        self.position = position; self.tokens = tokens; isSingleMove = true
    }
    func advancing(to next: Position, move: Move?) -> BoardMotionScene {
        guard next != position, let move,
              (try? position.applying(move: move)) == next else { return BoardMotionScene(position: next) }
        let updated = tokens.compactMap { token -> Token? in
            if token.square == move.to { return nil }
            var result = token
            if result.square == move.from { result.square = move.to }
            return result
        }
        return BoardMotionScene(position: next, tokens: updated)
    }
}
