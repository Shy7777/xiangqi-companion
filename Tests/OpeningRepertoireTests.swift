import Foundation

@main
struct OpeningRepertoireTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else {
                FileHandle.standardError.write(Data(("FAILED: " + message + "\n").utf8))
                preconditionFailure(message)
            }
        }
        let lessons = OpeningRepertoireCurriculum.lessons
        let sources = OpeningRepertoireCurriculum.sources
        let sourceIDs = Set(sources.map(\.id))
        let screenReference = try NSRegularExpression(pattern: "(?:借|以)\\s*([a-i][0-9])")
        check(lessons.count == 16, "The original opening research section contains sixteen substantive lessons")
        check(Set(lessons.map(\.id)).count == 16, "Unique lesson ids")
        check(OpeningRepertoireCurriculum.originMoves.count == 16, "Every study position has a reproducible origin")
        check(sourceIDs.count == sources.count, "Unique source ids")
        for source in sources {
            check(URL(string: source.url)?.scheme == "https", "Primary reference uses HTTPS")
            check(source.note.count >= 30, "Attribution and adaptation boundary are explicit")
        }
        var lineIDs = Set<String>(), exactLines = Set<String>(), initialPositions = Set<String>()
        var allPlies = 0, allPoints = 0, variationPlies = 0, blackLines = 0
        var export: [[String: Any]] = []
        for lesson in lessons {
            let key = String(lesson.id.dropFirst("repertoire-".count))
            check(lesson.id.hasPrefix("repertoire-"), "Stable integration ids")
            check(lesson.lines.count == 2, "Two complete research branches in \(lesson.id)")
            check(lesson.stage == .opening && lesson.isSystematic, "All research courses include a study guide")
            check(lesson.sourceIDs.allSatisfy { sourceIDs.contains($0) }, "Sources resolve")
            check([lesson.goal, lesson.principle, lesson.whenToAdapt].allSatisfy { $0.count >= 25 }, "Specific advanced lesson contract")
            check(lesson.pitfalls.count >= 3 && Set(lesson.pitfalls).count == lesson.pitfalls.count, "Specific distinct pitfalls")
            check(lesson.guide?.questions.count == 3 && lesson.guide?.workflow.count == 5, "Operational guide")
            check(lesson.guide?.reading.contains("软件原创") == true && lesson.guide?.reading.contains("并非") == true, "No fabricated author or book adaptation")
            guard let origin = OpeningRepertoireCurriculum.originMoves[key] else { fatalError("Missing origin \(key)") }
            var position = Position.initial
            for uci in origin.split(separator: " ") {
                guard let move = Move(uci: String(uci)) else { fatalError("Invalid origin UCI") }
                position = try position.applying(move: move)
                try position.validate(); checks += 1
            }
            check(position.sideToMove == .black, "All research positions begin at a black-response fork")
            check(initialPositions.insert(position.fen).inserted, "Do not count a transposition as an extra lesson")
            check(position.fen != Position.initial.fen, "New research starts beyond the old first-turn introduction")
            check(lesson.lines[0].moves.first?.uci != lesson.lines[1].moves.first?.uci, "Alternative must change the actual opponent response")
            var endings = Set<String>()
            for line in lesson.lines {
                check(line.startingFEN == position.fen, "FEN matches origin replay: \(line.id)")
                check(line.moves.count == 12, "Twelve substantive continuation plies: \(line.id)")
                check(lineIDs.insert(line.id).inserted, "Unique line id")
                check(exactLines.insert(line.startingFEN + line.moves.map(\.uci).joined()).inserted, "No duplicate full lines")
                check(line.game == nil, "Original continuations are not labeled as complete historical games")
                check(line.intent.contains("原创") && line.adaptation.contains("非唯一"), "Do not overclaim line authority")
                let states = try line.positions()
                check(states.count == 13, "Every intermediate state expands")
                check(endings.insert(states.last!.fen).inserted, "Branches leave genuinely different positions")
                for state in states { try state.validate(); checks += 1 }
                for (ply, item) in line.moves.enumerated() {
                    check(item.explanation.count >= 15 && item.hint.count >= 15, "Every move has factual explanation and substantive question: \(line.id)")
                    let state = states[ply], move = Move(uci: item.uci)!
                    if state[move.from]?.kind == .cannon, state[move.to] != nil,
                       let match = screenReference.firstMatch(in: item.explanation, range: NSRange(item.explanation.startIndex..., in: item.explanation)),
                       let range = Range(match.range(at: 1), in: item.explanation) {
                        let named = Square(coordinate: String(item.explanation[range]))!
                        let rowStep = move.to.row == move.from.row ? 0 : move.to.row > move.from.row ? 1 : -1
                        let colStep = move.to.col == move.from.col ? 0 : move.to.col > move.from.col ? 1 : -1
                        var row = move.from.row + rowStep, col = move.from.col + colStep
                        var occupied: [Square] = []
                        while row != move.to.row || col != move.to.col {
                            let square = Square(row: row, col: col)
                            if state[square] != nil { occupied.append(square) }
                            row += rowStep; col += colStep
                        }
                        check(occupied == [named], "Explicit cannon-screen explanation must match the actual board: \(line.id) \(item.uci)")
                    }
                }
                let points = line.checkpoints ?? []
                check(points.count == 3 && Set(points.map(\.ply)).count == 3, "Three independent learning decisions")
                if line.title.hasPrefix("易错") {
                    check(!points.contains { $0.ply == 0 } && line.intent.contains("不作为正确答案"), "A known inferior first move must never be a required answer")
                }
                for point in points {
                    check(states[point.ply].sideToMove == line.studentSide, "Checkpoint asks the correct side")
                    check(!point.title.isEmpty && point.prompt.count >= 15 && point.focus.count >= 15, "Specific decision contract")
                    export.append(["lineID": line.id, "ply": point.ply, "fen": states[point.ply].fen,
                                   "uci": line.moves[point.ply].uci, "side": line.studentSide.rawValue])
                }
                let data = try JSONEncoder().encode(line)
                let restored = try JSONDecoder().decode(StudyLine.self, from: data)
                check(restored == line && restored.contentFingerprint == line.contentFingerprint, "Stable save/import fingerprint")
                for variation in line.variations ?? [] {
                    let expanded = try variation.positions(parent: line)
                    check(variation.anchorPly == 0 && variation.moves.count == 8, "Eight-ply explicit comparative branch")
                    check(expanded.first == states.first, "Branch has the exact source position")
                    check(variation.moves.first?.uci != line.moves.first?.uci, "Variation changes a real first move")
                    check(Array(lesson.lines[1].moves.prefix(8)) == variation.moves, "Canvas is consistent with complete second branch")
                    check(variation.condition.count >= 20 && variation.explanation.count >= 35, "Condition and interpretation are present")
                    variationPlies += variation.moves.count
                }
                allPlies += line.moves.count; allPoints += points.count
                if line.studentSide == .black { blackLines += 1 }
            }
            check(lesson.lines[0].variations?.count == 1, "Every lesson offers a visible variation")
        }
        check(allPlies == 384 && allPoints == 96 && variationPlies == 128, "Content volume counts exclude origins and duplicate preview moves")
        check(blackLines == 8, "Include substantive black-side counterattack practice")
        if CommandLine.arguments.contains("--export-review") {
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys]))
            return
        }
        print("Opening repertoire PASS: \(checks) checks; 16 original courses, 32 distinct branches, 384 legal annotated plies, 96 decisions, 16 canvas variations (128 preview plies not counted as new content), 8 black-side branches.")
        #if REPERTOIRE_ENGINE_AUDIT
        if CommandLine.arguments.contains("--engine-audit") { try await audit() }
        #endif
    }

    #if REPERTOIRE_ENGINE_AUDIT
    @MainActor private static func audit() async throws {
        let paths = EngineConfiguration.resolve()
        guard paths.isConfigured else {
            throw StudyError.invalidContent("--engine-audit requires XQ_ENGINE_PATH and XQ_ENGINE_NETWORK")
        }
        let coach = TrainingCoach(binaryURL: paths.binary, networkURL: paths.network)
        defer { coach.shutdown() }
        let filter = Set(CommandLine.arguments.filter { $0.hasPrefix("--line=") }.map { String($0.dropFirst(7)) })
        let requestedBudget = CommandLine.arguments.first { $0.hasPrefix("--budget=") }.flatMap { Int($0.dropFirst(9)) } ?? 650
        let budget = min(3000, max(250, requestedBudget))
        var inspected = 0, inferior = 0, uncertain = 0
        for lesson in OpeningRepertoireCurriculum.lessons {
            for line in lesson.lines where filter.isEmpty || filter.contains(line.id) {
                let positions = try line.positions()
                for checkpoint in line.checkpoints ?? [] {
                    let move = Move(uci: line.moves[checkpoint.ply].uci)!
                    let result = try await coach.assess(position: positions[checkpoint.ply], move: move, movetime: budget)
                    inspected += 1
                    if result.verdict == .mistake || result.verdict == .inaccuracy { inferior += 1 }
                    if result.verdict == .uncertain { uncertain += 1 }
                    print("AUDIT \(line.id) ply=\(checkpoint.ply) \(move.uci) \(result.verdict.rawValue) \(result.detail)")
                    fflush(stdout)
                }
            }
        }
        print("ENGINE AUDIT: \(inspected) decisions; \(inferior) inferior; \(uncertain) uncertain. Limited-time evidence, not proof of optimality.")
        fflush(stdout)
        precondition(inferior == 0, "Reference decisions must not teach known inferior moves")
    }
    #endif
}
