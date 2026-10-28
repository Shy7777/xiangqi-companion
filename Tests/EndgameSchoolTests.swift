import Foundation

@main struct EndgameSchoolTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("Endgame school: \(message)") }
    }
    static func filled(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    @MainActor static func main() async throws {
        let lessons = EndgameSchoolCurriculum.lessons
        let sources = EndgameSchoolCurriculum.sources
        expect(lessons.count == 16, "sixteen intermediate original courses")
        expect(Set(lessons.map(\.id)).count == 16, "unique course IDs")
        expect(sources.count == 2, "catalog and primary university provenance")
        let sourceIDs = Set(sources.map(\.id))
        for source in sources {
            expect(source.id.hasPrefix("endgame-school-"), "isolated source namespace")
            expect(URL(string:source.url)?.scheme == "https", "usable HTTPS reference")
            expect([source.title,source.note].allSatisfy(filled), "scope stated")
        }
        let mateIDs: Set<String> = ["school-pawn-depth-b","school-rook-pawn-exchange-b","school-rook-horse-team-a","school-horse-cannon-team-b"]
        let stalemateIDs: Set<String> = ["school-pawn-king-space-a","school-pawn-depth-a","school-horse-pawn-support-a","school-horse-cannon-team-a"]
        var plies = 0, points = 0, variations = 0, branchPlies = 0
        var identifiers = Set<String>(), starts = Set<String>()
        var previousStarts: [Position] = []
        for lesson in lessons {
            expect(lesson.stage == .endgame, "endgame route")
            expect(lesson.lines.count == 2, "two independent positions per course")
            expect(lesson.estimatedMinutes >= 25, "study rather than one-move sizing")
            expect(lesson.pitfalls.count >= 3, "specific failure conditions")
            expect(lesson.sourceIDs.count == 2 && Set(lesson.sourceIDs).isSubset(of:sourceIDs), "resolved topic provenance")
            expect([lesson.title,lesson.summary,lesson.goal,lesson.principle,lesson.whenToAdapt].allSatisfy(filled), "complete guide")
            let guide = lesson.guide!
            expect(guide.questions.count >= 3 && guide.workflow.count >= 4, "calculation and comparison workflow")
            expect(guide.reading.contains("未取得原书正文") && guide.reading.contains("目录主题对照"), "not misrepresented as book reproduction")
            for line in lesson.lines {
                expect(identifiers.insert(line.id).inserted, "unique line ID")
                expect(line.game == nil && line.intent.contains("原创教学例"), "not fictitious historical or textbook game")
                expect(line.moves.count >= 5, "at least five halfmoves, not a one-move quiz")
                let states = try line.positions()
                let first = states[0]
                expect(starts.insert(first.fen).inserted, "every start genuinely different")
                for other in previousStarts {
                    var mirrored: [Piece?] = []
                    for index in 0..<90 {
                        let row = index / 9
                        let column = 8 - (index % 9)
                        mirrored.append(other.board[row * 9 + column])
                    }
                    expect(first.board != mirrored || first.sideToMove != other.sideToMove, "not left/right mirror padding")
                }
                previousStarts.append(first)
                for (index, state) in states.enumerated() {
                    try state.validate()
                    let decoded = try Position(fen:state.fen)
                    expect(decoded.board == state.board && decoded.sideToMove == state.sideToMove, "every FEN round trip")
                    if index < line.moves.count {
                        let move = Move(uci:line.moves[index].uci)!
                        expect(state.legalMoves().contains(move), "every reference move independently legal")
                        expect([line.moves[index].hint,line.moves[index].explanation].allSatisfy(filled), "every move has factual or authored explanation")
                    }
                }
                let checkpoints = line.checkpoints!
                expect(checkpoints.count >= 2, "multiple learner decisions")
                expect(checkpoints.map(\.ply) == checkpoints.map(\.ply).sorted(), "checkpoint order")
                expect(Set(checkpoints.map(\.ply)).count == checkpoints.count, "checkpoint uniqueness")
                for point in checkpoints {
                    expect((0..<line.moves.count).contains(point.ply), "valid before-move index")
                    expect(states[point.ply].sideToMove == line.studentSide, "intended study side")
                    expect(states[point.ply].legalMoves().count > 0, "checkpoint never after end of game")
                    expect([point.title,point.prompt,point.focus,point.explanation].allSatisfy(filled), "substantive point text")
                    expect(point.explanation == line.moves[point.ply].explanation, "card and move explanation agree")
                    points += 1
                }
                let terminal = states.last!
                let ends = mateIDs.contains(line.id) || stalemateIDs.contains(line.id)
                expect(terminal.legalMoves().isEmpty == ends, "terminal boundary \(line.id)")
                if ends {
                    expect(terminal.isInCheck(terminal.sideToMove) == mateIDs.contains(line.id), "distinguish mate and stalemate \(line.id)")
                }
                for variation in line.variations ?? [] {
                    let branch = try variation.positions(parent:line)
                    expect(branch.first!.fen == states[variation.anchorPly].fen, "branch starts at exact source position")
                    expect(variation.moves.count >= 5, "substantive branch")
                    expect(variation.moves.first?.uci != line.moves[variation.anchorPly].uci, "real divergence")
                    expect([variation.title,variation.condition,variation.explanation].allSatisfy(filled), "trigger and scope explicit")
                    for state in branch { try state.validate(); checks += 1 }
                    for item in variation.moves { expect([item.explanation,item.hint].allSatisfy(filled), "branch explanation") }
                    variations += 1; branchPlies += variation.moves.count
                }
                plies += line.moves.count
            }
        }
        expect(identifiers.count == 32 && starts.count == 32, "32 independently composed starting positions")
        expect(plies == 385 && points == 96, "385 main plies and 96 learner decisions")
        expect(variations == 8 && branchPlies == 63, "eight real alternatives with 63 plies")
        expect(lessons.filter { $0.lines.contains { !($0.variations ?? []).isEmpty } }.count == 8, "branches across eight different courses")
        let decoded = try JSONDecoder().decode([LearningLesson].self, from:JSONEncoder().encode(lessons))
        expect(decoded == lessons, "complete Codable round trip")

        // Specific semantic regressions: a same-destination cannon capture uses
        // different screens after the opponent's two genuinely different replies.
        let cannon = lessons.flatMap(\.lines).first { $0.id == "school-cannon-pawn-screen-b" }!
        let mainStates = try cannon.positions()
        expect(mainStates[2][Square(coordinate:"e9")!]?.kind == .king, "main uses opposing king as screen")
        expect(mainStates[2][Square(coordinate:"d9")!] == nil, "main advisor already moved")
        let alternate = try cannon.variations![0].positions(parent:cannon)
        expect(alternate[1][Square(coordinate:"d9")!]?.kind == .advisor, "alternate advisor remains the screen")
        expect(alternate[1][Square(coordinate:"e9")!] == nil, "alternate king has moved")
        let exchange = lessons.flatMap(\.lines).first { $0.id == "school-winning-simplification-a" }!
        let exchangeStates = try exchange.positions()
        expect(exchangeStates[4].board.compactMap { $0 }.filter { $0.kind == .rook }.isEmpty, "actual rook exchange, not relabelled capture")
        expect(exchange.adaptation.contains("更快"), "slower reference not claimed fastest")
        let cautious = lessons.flatMap(\.lines).first { $0.id == "school-cannon-support-exchange-a" }!
        expect(cautious.checkpoints!.map(\.ply) == [0,2,4], "unstable king-move reference retained for reading, not a required checkpoint")
        print("PASS \(checks) endgame school checks · 16 courses / 32 starts / \(plies) plies / \(points) checkpoints / \(variations) branches / \(branchPlies) branch plies")
        fflush(stdout)

        #if ENDGAME_ENGINE_AUDIT
        if CommandLine.arguments.contains("--repair") {
            let coach = TrainingCoach(); defer { coach.shutdown() }
            for (id, ply) in [("school-rook-pawn-coordination-a",4), ("school-cannon-support-exchange-a",8)] {
                let line = lessons.flatMap(\.lines).first { $0.id == id }!
                let positions = try line.positions()
                let assessment = try await coach.assess(position:positions[ply], move:Move(uci:line.moves[ply].uci)!, movetime:3500)
                let result: [String:Any] = ["id":id,"ply":ply,"verdict":assessment.verdict.rawValue,"before":String(describing:assessment.beforeScore),"after":String(describing:assessment.afterScore),"bestPV":assessment.bestPV,"replyPV":assessment.replyPV]
                print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self)); fflush(stdout)
            }
        }
        if CommandLine.arguments.contains("--engine") {
            let coach = TrainingCoach(); defer { coach.shutdown() }
            let filters = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
            var totals: [String:Int] = [:]
            for lesson in lessons {
                for line in lesson.lines where filters.isEmpty || filters.contains(line.id) {
                    let positions = try line.positions()
                    for point in line.checkpoints ?? [] {
                        let assessment = try await coach.assess(position:positions[point.ply], move:Move(uci:line.moves[point.ply].uci)!, movetime:700)
                        totals[assessment.verdict.rawValue, default:0] += 1
                        let json: [String:Any] = ["id":line.id,"ply":point.ply,"move":assessment.move.uci,"best":assessment.bestMove?.uci ?? "",
                            "verdict":assessment.verdict.rawValue,"before":String(describing:assessment.beforeScore),"after":String(describing:assessment.afterScore)]
                        print(String(decoding:try JSONSerialization.data(withJSONObject:json, options:[.sortedKeys]),as:UTF8.self)); fflush(stdout)
                    }
                }
            }
            print("ENGINE_AUDIT \(totals)")
        }
        #endif
    }
}
