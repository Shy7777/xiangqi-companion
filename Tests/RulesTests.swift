import Foundation

@main
struct RulesTests {
    static var checks = 0

    static func expect(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError("FAILED: \(message)") }
    }

    static func expectThrow(_ message: String, _ body: () throws -> Void) {
        checks += 1
        do { try body(); fatalError("FAILED: expected error: \(message)") } catch { }
    }

    static func square(_ coordinate: String) -> Square { Square(coordinate: coordinate)! }
    static func move(_ uci: String) -> Move { Move(uci: uci)! }
    static func has(_ position: Position, _ uci: String) -> Bool {
        let value = move(uci)
        return position.legalMoves(from: value.from).contains(value)
    }

    static func fixture(_ pieces: [(String, Side, PieceKind)], side: Side = .red) -> Position {
        var value = Position(board: Array(repeating: nil, count: 90), sideToMove: side)
        value[square("e0")] = Piece(side: .red, kind: .king)
        value[square("d9")] = Piece(side: .black, kind: .king)
        for (coordinate, pieceSide, kind) in pieces {
            value[square(coordinate)] = Piece(side: pieceSide, kind: kind)
        }
        return value
    }

    static func perft(_ position: Position, depth: Int) throws -> Int {
        if depth == 0 { return 1 }
        let moves = position.legalMoves()
        if depth == 1 { return moves.count }
        return try moves.reduce(0) { $0 + (try perft(position.applying(move: $1), depth: depth - 1)) }
    }

    /// Optional differential test against the actual Pikafish executable, without NNUE searching.
    static func engineMoves(_ position: Position, executable: String) throws -> Set<String> {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = URL(fileURLWithPath: executable).deletingLastPathComponent()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data("position fen \(position.fen)\ngo perft 1\nquit\n".utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        expect(process.terminationStatus == 0, "Pikafish perft exits cleanly")
        let response = String(decoding: data, as: UTF8.self)
        expect(response.contains("Nodes searched:"), "Pikafish returned perft results")
        return Set(response.split(separator: "\n").compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let candidate = String(line[..<colon])
            return Move(uci: candidate) == nil ? nil : candidate
        })
    }

    static func compareRandomGames(executable: String) throws {
        var seed: UInt64 = 0xC0FFEE
        var samples = 0
        for _ in 0..<3 {
            var position = Position.initial
            for ply in 0..<100 {
                let moves = position.legalMoves()
                if moves.isEmpty { break }
                try position.validate()
                if ply % 5 == 0 {
                    let own = Set(moves.map(\.uci))
                    let engine = try engineMoves(position, executable: executable)
                    expect(own == engine, "legal move parity at \(position.fen); extra=\(own.subtracting(engine)), missing=\(engine.subtracting(own))")
                    samples += 1
                }
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                position = try position.applying(move: moves[Int((seed >> 32) % UInt64(moves.count))])
            }
        }
        print("PASS: Pikafish legal-move parity across \(samples) sampled positions")
    }

    static func main() throws {
        expect(square("a0") == Square(row: 9, col: 0), "UCI red home rank")
        expect(square("i9") == Square(row: 0, col: 8), "UCI black home rank")
        expect(Move(uci: "h2e2")?.uci == "h2e2", "UCI round trip")
        expect(Move(uci: "a0a0") == nil && Move(uci: "i9j9") == nil && Move(uci: "A0a1") == nil, "invalid UCI")
        expect(Position.initial.board.count == 90, "90 board cells")
        expect(Position.initial.board.compactMap { $0 }.count == 32, "32 initial pieces")
        expect(Position.initial.fen == Position.initialFEN, "FEN round trip")
        expect(try Position(fen: Position.initialFEN.replacingOccurrences(of: "n", with: "h").replacingOccurrences(of: "N", with: "H")) == Position.initial, "horse alias")
        expectThrow("bad rank count") { _ = try Position(fen: "9/9/9/9/9/9/9/9/9 w") }
        expectThrow("bad rank width") { _ = try Position(fen: "rnbakabnr/99/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w") }
        expectThrow("bad piece") { _ = try Position(fen: Position.initialFEN.replacingOccurrences(of: "rnb", with: "rnx")) }
        expectThrow("bad side") { _ = try Position(fen: Position.initialFEN.replacingOccurrences(of: " w ", with: " x ")) }
        expectThrow("missing king") { _ = try Position(fen: "9/9/9/9/9/9/9/9/9/9 w") }
        expectThrow("facing generals") { _ = try Position(fen: "4k4/9/9/9/9/9/9/9/9/4K4 w") }
        expectThrow("king outside palace") { try fixture([("e0", .red, .rook), ("a0", .red, .king)]).validate() }
        expectThrow("advisor outside diagonals") { try fixture([("e1", .red, .advisor), ("e2", .red, .advisor)]).validate() }
        expectThrow("elephant crossed river") { try fixture([("c5", .red, .elephant)]).validate() }
        expectThrow("pawn moved backwards") { try fixture([("a2", .red, .pawn)]).validate() }

        let checkedFEN = "4k4/9/9/9/9/4p4/9/9/4r4/4K4 w - - 0 1"
        let checked = try Position(fen: checkedFEN)
        expect(checked.isInCheck(.red), "current side may be in check")
        expectThrow("wrong side while previous mover in check") {
            _ = try Position(fen: checkedFEN.replacingOccurrences(of: " w ", with: " b "))
        }
        expect(has(checked, "e0e1"), "capture checker if king remains safe")

        let initial = Position.initial
        expect(initial.legalMoves().count == 44, "initial legal move count = 44")
        let depth2 = try perft(initial, depth: 2)
        expect(depth2 == 1920, "initial perft 2 = 1920, got \(depth2)")
        let depth3 = try perft(initial, depth: 3)
        expect(depth3 == 79666, "initial perft 3 = 79666, got \(depth3)")
        expect(initial.legalMoves(from: square("a9")).isEmpty, "cannot move opponent")
        expect(initial.legalMoves(from: square("a1")).isEmpty, "empty origin")
        expectThrow("illegal move") { _ = try initial.applying(move: move("a0b1")) }

        let opened = try initial.applying(move: move("h2e2"))
        expect(opened.sideToMove == .black, "turn alternates")
        expect(opened[square("h2")] == nil && opened[square("e2")] == Piece(side: .red, kind: .cannon), "move applies once")
        expect(initial[square("h2")] != nil, "original position unchanged")
        expect(try Position(fen: opened.fen) == opened, "played position FEN round trip")

        var cannon = fixture([("a2", .red, .cannon), ("a6", .black, .rook)])
        expect(!has(cannon, "a2a6"), "cannon cannot capture without screen")
        expect(has(cannon, "a2a5"), "cannon quiet move before target")
        cannon[square("a4")] = Piece(side: .red, kind: .pawn)
        expect(has(cannon, "a2a6"), "cannon captures over friendly screen")
        expect(!has(cannon, "a2a5"), "cannon cannot land beyond screen on empty square")
        let captured = try cannon.applying(move: move("a2a6"))
        expect(captured[square("a6")] == Piece(side: .red, kind: .cannon), "captured piece replaced")
        cannon[square("a5")] = Piece(side: .black, kind: .pawn)
        expect(!has(cannon, "a2a6"), "cannon cannot jump two screens")
        cannon[square("a6")] = Piece(side: .red, kind: .rook)
        expect(!has(cannon, "a2a6"), "cannon cannot capture friendly piece")

        var horse = fixture([("b2", .red, .horse)])
        expect(has(horse, "b2c4") && has(horse, "b2d3"), "horse open legs")
        horse[square("b3")] = Piece(side: .black, kind: .pawn)
        expect(!has(horse, "b2c4") && has(horse, "b2d3"), "horse vertical leg blocks only related moves")
        horse[square("c2")] = Piece(side: .red, kind: .pawn)
        expect(!has(horse, "b2d3"), "horse horizontal leg blocked")
        let edgeHorse = fixture([("a1", .red, .horse)])
        expect(edgeHorse.legalMoves(from: square("a1")).count == 3, "horse edge destinations")

        var elephant = fixture([("c0", .red, .elephant)])
        expect(has(elephant, "c0a2") && has(elephant, "c0e2"), "elephant diagonal move")
        elephant[square("b1")] = Piece(side: .black, kind: .pawn)
        expect(!has(elephant, "c0a2") && has(elephant, "c0e2"), "elephant eye")
        let riverElephant = fixture([("c4", .red, .elephant)])
        expect(!has(riverElephant, "c4e6") && has(riverElephant, "c4e2"), "elephant cannot cross river")
        let blackElephant = fixture([("c5", .black, .elephant)], side: .black)
        expect(!has(blackElephant, "c5e3") && has(blackElephant, "c5e7"), "black elephant river symmetric")

        let advisor = fixture([("e1", .red, .advisor)])
        expect(Set(advisor.legalMoves(from: square("e1")).map(\.uci)) == Set(["e1d0", "e1f0", "e1d2", "e1f2"]), "advisor palace diagonals")
        let edgeAdvisor = fixture([("d2", .red, .advisor)])
        expect(!has(edgeAdvisor, "d2c3") && has(edgeAdvisor, "d2e1"), "advisor cannot leave palace")
        let king = fixture([])
        expect(!has(king, "e0d0"), "king may not enter facing-generals file")
        expect(has(king, "e0f0") && !has(king, "e0e2"), "king one orthogonal step")
        var edgeKing = king
        edgeKing[square("e0")] = nil
        edgeKing[square("f2")] = Piece(side: .red, kind: .king)
        expect(!has(edgeKing, "f2g2") && !has(edgeKing, "f2f3"), "king cannot leave palace")

        let preRiverPawn = fixture([("a3", .red, .pawn)])
        expect(has(preRiverPawn, "a3a4") && !has(preRiverPawn, "a3b3") && !has(preRiverPawn, "a3a2"), "pawn before river")
        let postRiverPawn = fixture([("b5", .red, .pawn)])
        expect(has(postRiverPawn, "b5a5") && has(postRiverPawn, "b5c5") && has(postRiverPawn, "b5b6") && !has(postRiverPawn, "b5b4"), "pawn after river")
        let lastRankPawn = fixture([("a9", .red, .pawn)])
        expect(has(lastRankPawn, "a9b9") && lastRankPawn.legalMoves(from: square("a9")).count == 1, "pawn at last rank moves sideways")
        let blackPawn = fixture([("b4", .black, .pawn)], side: .black)
        expect(has(blackPawn, "b4b3") && has(blackPawn, "b4a4") && !has(blackPawn, "b4b5"), "black pawn direction")

        var pinned = fixture([("e5", .red, .rook)])
        pinned[square("d9")] = nil
        pinned[square("e9")] = Piece(side: .black, kind: .king)
        expect(!pinned.generalsFaceEachOther, "piece screens generals")
        expect(!has(pinned, "e5d5") && has(pinned, "e5e6"), "cannot expose facing generals")
        expect(!has(pinned, "e5e9"), "king is not captured as an ordinary piece")
        let rookPin = fixture([("e8", .black, .rook), ("e3", .red, .rook)])
        expect(!has(rookPin, "e3a3") && has(rookPin, "e3e8"), "self-check pin and capture attacker")

        let rookCheck = fixture([("e8", .black, .rook), ("a2", .red, .rook)])
        expect(rookCheck.isInCheck(.red), "rook check")
        expect(!has(rookCheck, "a2a3") && has(rookCheck, "a2e2"), "must resolve check by blocking")
        let horseCheck = fixture([("d2", .black, .horse)])
        expect(horseCheck.isInCheck(.red), "horse check")
        var horseBlocked = horseCheck
        horseBlocked[square("d1")] = Piece(side: .red, kind: .rook)
        expect(!horseBlocked.isInCheck(.red), "blocked horse does not check")
        let cannonCheck = fixture([("e8", .black, .cannon), ("e4", .black, .pawn)])
        expect(cannonCheck.isInCheck(.red), "cannon check with screen")
        let noScreenCheck = fixture([("e8", .black, .cannon)])
        expect(!noScreenCheck.isInCheck(.red), "cannon no check without screen")
        let pawnCheck = fixture([("d0", .black, .pawn)])
        expect(pawnCheck.isInCheck(.red), "crossed black pawn checks sideways")

        expect(initial.notation(for: move("h2e2")) == "炮二平五", "red cannon notation")
        expect(initial.notation(for: move("h0g2")) == "马二进三", "red horse notation")
        expect(initial.notation(for: move("a0a1")) == "车九进一", "red rook notation")
        expect(initial.notation(for: move("b7e7")) == "炮2平5", "black cannon notation")
        let stackedRooks = fixture([("a2", .red, .rook), ("a4", .red, .rook)])
        expect(stackedRooks.notation(for: move("a4b4")) == "前车平八", "front rook notation")
        expect(stackedRooks.notation(for: move("a2b2")) == "后车平八", "rear rook notation")
        let stackedPawns = fixture([("a5", .red, .pawn), ("a6", .red, .pawn), ("a7", .red, .pawn)])
        expect(stackedPawns.notation(for: move("a6b6")) == "中兵平八", "middle pawn notation")
        let ambiguousPawns = fixture([("a5", .red, .pawn), ("a6", .red, .pawn), ("c5", .red, .pawn), ("c6", .red, .pawn)])
        expect(ambiguousPawns.notation(for: move("a6b6")).contains("a6→b6"), "ambiguous pawn notation has coordinates")

        let encoder = JSONEncoder()
        let saved = try encoder.encode(opened)
        expect(try JSONDecoder().decode(Position.self, from: saved) == opened, "Codable position round trip")
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--engine"), CommandLine.arguments.indices.contains(flagIndex + 1) {
            try compareRandomGames(executable: CommandLine.arguments[flagIndex + 1])
        }
        print("PASS: \(checks) checks, perft(1)=44, perft(2)=\(depth2), perft(3)=\(depth3)")
    }
}
