import Foundation
import CryptoKit

/// Complete real-game provenance, legality and teaching-checkpoint regression.
@main
struct SystematicContentTests {
    static var checks = 0
    struct SourceRecord {
        let red: String
        let black: String
        let date: String
        let movesHash: String
        let positionsHash: String
    }
    // Frozen from independently converted historical records, not calculated
    // from the curriculum under test. Hash UTF-8 strings joined by LF, no final LF.
    // Source attribution and redistribution boundaries: Docs/LICENSING.md.
    static let records: [String: SourceRecord] = [
        "https://www.xqipu.com/qipu/9907c6bd-4bf4-47f8-bc08-b9bd4bb4668c": .init(
            red: "杨官璘", black: "胡荣华", date: "1979-09-13",
            movesHash: "8b61695908621f99c16f94630cfa55489017f509975bee4c868a739b39de25ad",
            positionsHash: "792e591fb96869eb7a5ab3223166f0342df9b738322d49bb26f53875c7e05cc8"),
        "https://www.xqipu.com/qipu/5b21f642-0697-482d-8a91-d65e52a25bdf": .init(
            red: "胡荣华", black: "杨官璘", date: "1981-01-17",
            movesHash: "3eadc2f589f33680448db5dcc2d2ebf1564b38f2848153daa6bc3c35e4b6abe9",
            positionsHash: "8b1f5043f83067854b0d479bb8ab18ccfa74e5feefdabb2427b0fc367ca69250"),
        "https://www.xqipu.com/qipu/8cf50da2-136c-4262-b1a1-1a633bd31947": .init(
            red: "许银川", black: "吕钦", date: "2010-03-10",
            movesHash: "25f973cef0c4982de58e852e617203c96139f585fd7ee05c28120e72dc11d7ad",
            positionsHash: "c4a76273f20fef5e4dbfb7bf280550126fd6fbb52f8271552e21def275225645"),
        "https://www.xqipu.com/qipu/89473f46-4d12-4fea-8153-bf9e7c00bad5": .init(
            red: "吕钦", black: "许银川", date: "2011-04-11",
            movesHash: "dfaff34e3325fd984868c57677ab58070bf46e4ce627ac14493f30ace8fe1926",
            positionsHash: "3220b7da090983b3ebe558d8c4935f8a4167bb0565e7b87612fbc8dd25840998")
    ]
    static func digest(_ values: [String]) -> String {
        SHA256.hash(data: Data(values.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }
    static func square(_ text: String) -> Square { Square(coordinate: text)! }
    static func has(_ p: Position, _ coordinate: String, _ side: Side, _ kind: PieceKind) -> Bool {
        p[square(coordinate)] == Piece(side: side, kind: kind)
    }
    static func legal(_ p: Position, _ uci: String, as side: Side? = nil) -> Bool {
        var copy = p
        if let side { copy.sideToMove = side }
        return copy.legalMoves().contains(Move(uci: uci)!)
    }
    static func main() throws {
        expect(SystematicCurriculum.lessons.count == 4, "Four distinct complete-game lessons")
        expect(SystematicCurriculum.sources.count == 4, "Four traceable game sources")
        expect(Set(SystematicCurriculum.lessons.map(\.id)).count == 4, "Unique lesson IDs")
        var totalPlies = 0, totalCheckpoints = 0
        var positions: [String: [Position]] = [:]
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let knownSources = Set((SystematicCurriculum.sources + ProfessionalResources.sources).map(\.id))
        for lesson in SystematicCurriculum.lessons {
            expect(lesson.sourceIDs.allSatisfy { knownSources.contains($0) }, "Every game and further-reading source resolves")
            expect(lesson.lines.count == 1, "A complete historical game, not split fragments")
            let line = lesson.lines[0]
            let game = line.game!
            let record = records[game.sourceURL]!
            expect(digest(line.moves.map(\.uci)) == record.movesHash, "Every imported move equals the frozen source record")
            expect(game.red == record.red && game.black == record.black, "Players match source")
            expect(game.date == record.date, "Date matches source")
            expect(line.startingFEN == Position.initialFEN, "Full game must start at the standard initial position")
            let states = try line.positions()
            for p in states { try p.validate(); checks += 1 }
            expect(digest(states.map(\.fen)) == record.positionsHash, "Every FEN equals independent source conversion")
            expect(states.last!.legalMoves().count > 0, "Do not call these record endpoints checkmate/stalemate")
            let checkpoints = line.checkpoints!
            expect((4...6).contains(checkpoints.count), "Four to six substantive checkpoints")
            expect(checkpoints.map(\.ply) == checkpoints.map(\.ply).sorted(), "Checkpoints sorted")
            expect(Set(checkpoints.map(\.ply)).count == checkpoints.count, "No duplicate stop positions")
            expect(Set(checkpoints.map { states[$0.ply].sideToMove }).count == 2, "Both players make decisions")
            for checkpoint in checkpoints {
                expect(checkpoint.ply >= 0 && checkpoint.ply < line.moves.count, "Zero-based before-move checkpoint")
                expect(!checkpoint.title.isEmpty && checkpoint.prompt.count >= 30 && checkpoint.focus.count >= 25 && checkpoint.explanation.count >= 50,
                       "Concrete original learning text")
                expect(line.moves[checkpoint.ply].explanation == checkpoint.explanation, "Played reference has the matching explanation")
            }
            for (ply, move) in line.moves.enumerated() where !checkpoints.contains(where: { $0.ply == ply }) {
                expect(move.explanation == "实战棋谱续着；此步未另附人工注解。", "Unannotated history has no fabricated teacher commentary")
            }
            let guide = lesson.guide!
            expect(guide.questions.count >= 3 && guide.workflow.count >= 4 && guide.reading.count >= 120, "Serious reading, questions and workflow")
            let roundTrip = try decoder.decode(LearningLesson.self, from: encoder.encode(lesson))
            expect(roundTrip == lesson, "Curriculum Codable round trip")
            positions[line.id] = states
            totalPlies += line.moves.count; totalCheckpoints += checkpoints.count
            print("PASS \(game.date) \(game.red)–\(game.black): \(line.moves.count) plies; \(checkpoints.count) checkpoints; all moves/source/FEN/text contracts")
        }
        expect(totalPlies == 421 && totalCheckpoints == 21, "Exact verified content totals")

        let opening = positions["systematic-1981-full"]!
        expect(has(opening[35], "c3", .black, .cannon) && has(opening[35], "c5", .red, .pawn) && has(opening[35], "c6", .red, .horse), "1981 cannon-screen exchange setup")
        expect(legal(opening[35], "c3c6") && legal(opening[36], "c5c6"), "1981 cannon capture and pawn recapture")
        expect(has(opening[58], "g2", .red, .horse) && has(opening[58], "f6", .red, .rook) && has(opening[58], "a0", .black, .cannon), "1981 coordination and counterattack pieces")

        let balance = positions["systematic-2011-full"]!
        expect(has(balance[29], "c5", .black, .pawn) && has(balance[29], "b5", .black, .cannon), "2011 pawn serves as cannon screen")
        expect(legal(balance[31], "b5g5"), "2011 cannon recaptures exchanged rook")
        expect(balance[32].board.compactMap { $0 }.filter { $0.kind == .rook }.isEmpty, "2011 no rooks after the exchange")
        expect(legal(balance[56], "g2g7") && legal(balance[57], "g8g6"), "2011 two successive cannon captures use changed screens")
        expect(has(balance[56], "g6", .red, .horse) && has(balance[57], "g7", .red, .cannon), "First horse and then cannon are screens")

        let calculation = positions["systematic-2010-full"]!
        expect(calculation[34].isInCheck(.red), "2010 checkpoint is a real check, not a generic safety prompt")
        expect(legal(calculation[34], "e0e1") && !calculation[35].isInCheck(.red), "King move truly resolves the check")
        expect(has(calculation[52], "e2", .red, .elephant) && legal(calculation[52], "g2c2"), "Elephant is the cannon screen")
        expect(legal(calculation[53], "a1c2") && has(calculation[54], "c2", .black, .horse), "Horse really recaptures cannon")
        expect(!legal(calculation[59], "g1g8", as: .red) && legal(calculation[60], "g1g8"), "Horse movement changes two blockers to one screen")
        expect(legal(calculation[61], "f5h4"), "Other wing's horse capture must also be counted")
        expect(has(calculation[80], "d3", .black, .horse) && has(calculation[81], "d2", .red, .rook), "Defensive rook occupies a horse-leg square")

        let ending = positions["systematic-1979-full"]!
        expect(ending[72].board.compactMap { $0 }.filter { $0.kind == .rook }.count == 2, "Two rooks before last rook exchange")
        expect(ending[75].board.compactMap { $0 }.filter { $0.kind == .rook }.isEmpty, "Both rooks leave after the actual three-ply sequence")
        expect(has(ending[75], "e2", .red, .elephant) && legal(ending[75], "d4e2"), "Near horse can immediately capture the elephant")
        expect(ending[106].isInCheck(.red) && legal(ending[106], "b1d1"), "1979 cannon move gives real check and cannon block resolves it")
        expect(legal(ending[108], "d1d3") && legal(ending[109], "c3d3"), "Final cannon exchange includes pawn recapture")
        expect(ending[110].board.compactMap { $0 }.filter { $0.kind == .cannon }.isEmpty, "No cannons after the exchange")
        expect(!legal(ending[145], "d3e1") && legal(ending[146], "d3e1", as: .black), "Moving d2 pawn demonstrably opens horse leg toward e1")
        print("PASS TOTAL: \(totalPlies) historical plies; \(totalCheckpoints) checkpoints; \(checks) checks. No engine continuation, no forced-win claims.")
    }
}
