import Foundation

@main struct MiddlegameAtlasTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("Middlegame atlas: \(message)") }
    }
    static func filled(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    static func rejects(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Middlegame atlas should reject: \(message)") }
        catch { checks += 1 }
    }

    @MainActor static func main() async throws {
        try contentTests()
        #if ATLAS_ENGINE_TESTS
        if CommandLine.arguments.contains("--engine") { try await engineTests() }
        #endif
    }

    static func contentTests() throws {
        let lessons = MiddlegameAtlasCurriculum.lessons
        let sources = MiddlegameAtlasCurriculum.sources
        let expectedIDs = ["atlas-activity","atlas-race","atlas-exchange","atlas-pawn-break",
                           "atlas-invasion","atlas-king-safety","atlas-cannon-routes","atlas-counterinitiative",
                           "atlas-conversion","atlas-balance","atlas-review","atlas-preparation"]
        expect(lessons.map(\.id) == expectedIDs, "12 distinct requested topics in their planned order")
        expect(lessons.map(\.order) == Array(stride(from: 500, through: 610, by: 10)), "before capstone full games, stable IDs and order")
        expect(sources == SystematicCurriculum.sources, "source reuse, not invented new authority")
        expect(Set(sources.map(\.id)).count == 4, "the corpus still consists of exactly four complete source games")
        let originalLines = SystematicCurriculum.lessons.map { $0.lines[0] }
        let originalStates = try originalLines.map { try $0.positions() }
        let sourceIDs = Set(sources.map(\.id))
        let originalFingerprints = originalLines.map(\.contentFingerprint)
        let oldExplanations = Set(originalLines.flatMap { ($0.checkpoints ?? []).map(\.explanation) })
        let oldNodes = Set(originalLines.enumerated().flatMap { index, line in
            (line.checkpoints ?? []).map { "\(index):\($0.ply)" }
        })
        var allLineIDs = Set<String>(), starts = Set<String>(), decisionExplanations = Set<String>()
        var decisionNodes = Set<String>(), newDecisionNodes = Set<String>(), branchStarts = Set<String>()
        var mainPlies = 0, branchPlies = 0, pointCount = 0, variationCount = 0

        for lesson in lessons {
            expect(lesson.lines.count == 2, "\(lesson.id) has two substantive comparative excerpts")
            expect(lesson.isSystematic, "structured guide participates in existing teaching workflow")
            expect([lesson.title,lesson.summary,lesson.goal,lesson.principle,lesson.whenToAdapt].allSatisfy(filled), "complete original teaching fields")
            expect(lesson.pitfalls.count >= 3 && Set(lesson.pitfalls).count == lesson.pitfalls.count, "specific failure modes")
            expect(!lesson.sourceIDs.isEmpty && Set(lesson.sourceIDs).isSubset(of: sourceIDs), "resolved actual historical source IDs")
            expect(lesson.summary.contains("专题截段") && lesson.tags.contains("非王嘉良原题"), "excerpt and authorship boundary visible")
            let guide = lesson.guide!
            expect(guide.reading.count >= 200, "substantive reading, not a placeholder subtitle")
            expect(guide.questions.count >= 3 && Set(guide.questions).count == guide.questions.count, "multiple concrete research questions")
            expect(guide.workflow.count >= 4 && guide.workflow.allSatisfy { $0.count >= 18 }, "actionable independent study workflow")
            expect(guide.takeaway.contains("完成标准") && guide.takeaway.contains("隔日"), "practice and delayed independent completion distinguished")
            expect(guide.reading.contains("不是王嘉良教材原题") && guide.reading.contains("历史着法仍须"), "no false textbook attribution or automatic historical correctness")

            for line in lesson.lines {
                guard let origin = MiddlegameAtlasCurriculum.origins[line.id] else { fatalError("missing excerpt origin") }
                expect(allLineIDs.insert(line.id).inserted, "globally unique line IDs")
                expect(starts.insert(line.startingFEN).inserted, "24 genuinely distinct starting boards, not duplicate fragments")
                expect(line.game == nil, "excerpts never have misleading full-game metadata")
                expect(line.moves.count == 10 && origin.length == 10, "ten continuous historical half-moves")
                expect(line.adaptation.contains("第 \(origin.startPly + 1)–\(origin.startPly + 10) 半步"), "exact location in original game is visible")
                expect(line.adaptation.contains("非新增完整对局"), "scope is explicit at individual line level")
                let parent = originalLines[origin.gameIndex]
                let parentStates = originalStates[origin.gameIndex]
                let states = try line.positions()
                expect(line.startingFEN == parentStates[origin.startPly].fen, "source starting board unchanged")
                expect(line.moves.map(\.uci) == Array(parent.moves[origin.startPly..<(origin.startPly + 10)]).map(\.uci), "every historical move matches verified complete record")
                expect(states.count == 11, "all source half-moves expand")
                for (offset, position) in states.enumerated() {
                    try position.validate()
                    expect(position.fen == parentStates[origin.startPly + offset].fen, "each intermediate board remains exactly the source board")
                    let reparsed = try Position(fen: position.fen)
                    expect(reparsed == position, "FEN round trip")
                    if offset < line.moves.count {
                        let item = line.moves[offset], move = Move(uci: line.moves[offset].uci)!
                        expect(position.legalMoves().contains(move), "independent legal move validation")
                        expect(item.explanation.contains(position.notation(for: move)), "factual annotation uses actual positional notation")
                        expect([item.explanation,item.hint].allSatisfy(filled), "every half-move has a nonempty useful description and hint")
                    }
                }
                let points = line.checkpoints!
                expect(points.count == 3, "three learner decisions, not a one-move exercise")
                expect(points.map(\.ply) == points.map(\.ply).sorted(), "ordered checkpoints")
                expect(Set(points.map(\.ply)).count == 3, "unique checkpoints")
                expect(points.contains { $0.ply >= 6 }, "decisions extend into the excerpt, not just its opening")
                for point in points {
                    expect((0..<10).contains(point.ply), "valid before-move anchor")
                    expect(states[point.ply].sideToMove == line.studentSide && line.studentSide == .red, "assigned study side matches actual decision side")
                    expect(!states[point.ply].legalMoves().isEmpty, "not a terminal/nondecision position")
                    expect([point.title,point.prompt,point.focus,point.explanation].allSatisfy(filled), "complete authored checkpoint")
                    expect(point.prompt.count >= 18 && point.focus.count >= 18 && point.explanation.count >= 70, "\(line.id)@\(point.ply) substantive authored content (lengths \(point.prompt.count)/\(point.focus.count)/\(point.explanation.count))")
                    expect(point.explanation == line.moves[point.ply].explanation, "feedback and timeline commentary agree")
                    expect(!oldExplanations.contains(point.explanation), "no old checkpoint explanation simply copied")
                    expect(decisionExplanations.insert(point.explanation).inserted, "72 separately authored explanations, not a repeated template")
                    let node = "\(origin.gameIndex):\(origin.startPly + point.ply)"
                    decisionNodes.insert(node)
                    if !oldNodes.contains(node) { newDecisionNodes.insert(node) }
                    pointCount += 1
                }
                for branch in line.variations ?? [] {
                    expect((0..<line.moves.count).contains(branch.anchorPly), "branch before-move anchor")
                    expect(branch.moves.count == 8, "eight real PV half-moves, no one-step padding")
                    expect(branch.moves[0].uci != line.moves[branch.anchorPly].uci, "a genuinely different root move")
                    let branchStates = try branch.positions(parent: line)
                    expect(branchStates.first == states[branch.anchorPly], "fork derives from its own actual anchor")
                    expect(branchStarts.insert(branchStates[0].fen).inserted, "all research alternatives have distinct starting boards")
                    expect(branchStates[1] != states[branch.anchorPly + 1], "not relabelled original continuation")
                    for (offset, item) in branch.moves.enumerated() {
                        let move = Move(uci: item.uci)!
                        expect(branchStates[offset].legalMoves().contains(move), "each research PV move independently legal")
                        try branchStates[offset + 1].validate()
                        expect(item.explanation.contains(branchStates[offset].notation(for: move)), "branch facts use branch board, never original notation context")
                    }
                    expect(branch.explanation.contains("600 毫秒") && branch.explanation.contains("非强制变化或理论定论"), "finite-search budget and claim boundary preserved")
                    expect(branch.explanation.contains("不是当前局面评分"), "snapshot score cannot masquerade as live analysis")
                    let derived = try branch.studyLine(parent: line)
                    expect(derived.startingFEN == states[branch.anchorPly].fen && derived.moves == branch.moves, "optional pure practice bridge stays in branch")
                    expect(derived.game == nil && derived.variations == nil, "branch bridge not a new complete historical game")
                    variationCount += 1; branchPlies += branch.moves.count
                }
                mainPlies += line.moves.count
            }
        }
        expect(mainPlies == 240 && pointCount == 72, "240 source plies, 72 authored decisions")
        expect(allLineIDs.count == 24 && starts.count == 24, "24 source-derived, distinct training starts")
        expect(variationCount == 12 && branchPlies == 96, "twelve genuine research alternatives, 96 branch plies")
        expect(newDecisionNodes.count >= 55, "substantial new decision coverage rather than old stops renamed")
        expect(SystematicCurriculum.lessons.map { $0.lines[0].contentFingerprint } == originalFingerprints, "source records are not mutated by deriving study or branch data")
        expect(MiddlegameAtlasCurriculum.lessons == lessons, "cached curriculum stable across repeated access")
        try annotationTests(lessons)
        try packTests(lessons, sources)
        print("PASS \(checks) atlas content checks · 12 topics / 24 excerpts / 240 historical plies / 72 checkpoints (\(decisionNodes.count) distinct source nodes, \(newDecisionNodes.count) new versus original stops) / 12 research branches / 96 PV plies")
    }

    static func annotationTests(_ lessons: [LearningLesson]) throws {
        let lines = Dictionary(uniqueKeysWithValues: lessons.flatMap(\.lines).map { ($0.id, $0) })
        func position(_ id: String, _ ply: Int) throws -> Position { try lines[id]!.positions()[ply] }
        func piece(_ p: Position, _ coordinate: String, _ side: Side, _ kind: PieceKind) {
            expect(p[Square(coordinate: coordinate)!] == Piece(side: side, kind: kind), "authored factual claim: \(side.label) \(kind) at \(coordinate)")
        }
        func screen(_ p: Position, _ from: String, _ to: String, _ expected: [String]) {
            let a = Square(coordinate: from)!, b = Square(coordinate: to)!
            expect(a.row == b.row || a.col == b.col, "straight cannon ray")
            let between = Square.all.filter { q in
                if a.row == b.row { return q.row == a.row && q.col > min(a.col,b.col) && q.col < max(a.col,b.col) }
                return q.col == a.col && q.row > min(a.row,b.row) && q.row < max(a.row,b.row)
            }.filter { p[$0] != nil }.map(\.coordinate)
            expect(Set(between) == Set(expected), "exact cannon screen(s) for \(from)→\(to)")
        }
        let activity = try position("atlas-activity-excerpt-1", 2)
        piece(activity, "g3", .black, .pawn); screen(activity, "c3", "g3", ["e3"])
        let exchange = try position("atlas-exchange-excerpt-1", 7)
        piece(exchange, "g5", .red, .rook); screen(exchange, "b5", "g5", ["c5"])
        let secondExchange = try position("atlas-exchange-excerpt-2", 5)
        piece(secondExchange, "i3", .red, .horse); screen(secondExchange, "i7", "i3", ["i6"])
        let pawn = try position("atlas-pawn-break-excerpt-1", 2)
        piece(pawn, "c4", .black, .pawn); screen(pawn, "c0", "c4", ["c2"])
        let elephant = try position("atlas-pawn-break-excerpt-2", 4)
        piece(elephant, "g5", .black, .elephant); screen(elephant, "g8", "g5", ["g6"])
        let cannons = try position("atlas-cannon-routes-excerpt-2", 4)
        piece(cannons, "a4", .black, .pawn); screen(cannons, "i4", "a4", ["h4"])
        let twoExchanges = try position("atlas-cannon-routes-excerpt-2", 8)
        screen(twoExchanges, "g2", "g7", ["g6"])
        let nextExchange = try position("atlas-cannon-routes-excerpt-2", 9)
        piece(nextExchange, "g7", .red, .cannon); screen(nextExchange, "g8", "g6", ["g7"])
        let recovery = try position("atlas-review-excerpt-1", 8)
        piece(recovery, "c5", .red, .pawn); piece(recovery, "c6", .black, .cannon)
        let checkedKing = try position("atlas-king-safety-excerpt-2", 0)
        expect(checkedKing.isInCheck(.red), "king-safety explanation correctly identifies an actual cannon check")
        screen(checkedKing, "e4", "e0", ["e2"])
        let blockedCheck = try position("atlas-king-safety-excerpt-2", 1)
        expect(!blockedCheck.isInCheck(.red), "advisor supplies a second obstruction and resolves check")
        screen(blockedCheck, "e4", "e0", ["e2","e1"])
        let blocker = try position("atlas-conversion-excerpt-1", 9)
        piece(blocker, "d2", .red, .rook); piece(blocker, "d3", .black, .horse); piece(blocker, "e1", .red, .advisor)
        expect(blocker[Square(coordinate: "d2")!] != nil, "d2 blocks the nearby horse's straight leg toward the bottom")
    }

    static func packTests(_ lessons: [LearningLesson], _ sources: [LearningSource]) throws {
        let pack = StudyPack(title: "实战专题截段", sources: sources, lessons: lessons)
        try pack.validate()
        checks += 1
        let encoded = try JSONEncoder().encode(pack)
        let decoded = try JSONDecoder().decode(StudyPack.self, from: encoded)
        try decoded.validate()
        expect(decoded.lessons == lessons, "complete content and research provenance survive JSON import round trip")
        var duplicate = pack; duplicate.lessons.append(lessons[0])
        rejects("duplicate courses") { try duplicate.validate() }
        var unresolved = pack; unresolved.sources = []
        rejects("unresolved source references") { try unresolved.validate() }
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var courseObjects = object["lessons"] as! [[String: Any]]
        var lineObjects = courseObjects[0]["lines"] as! [[String: Any]]
        var variationObjects = lineObjects[0]["variations"] as! [[String: Any]]
        variationObjects[0]["anchorPly"] = 10
        lineObjects[0]["variations"] = variationObjects; courseObjects[0]["lines"] = lineObjects; object["lessons"] = courseObjects
        let invalid = try JSONDecoder().decode(StudyPack.self, from: JSONSerialization.data(withJSONObject: object))
        rejects("a fork at the after-end position") { try invalid.validate() }
        variationObjects[0]["anchorPly"] = 0
        var branchMoves = variationObjects[0]["moves"] as! [[String: Any]]
        branchMoves[0]["uci"] = "a0a9"
        variationObjects[0]["moves"] = branchMoves
        lineObjects[0]["variations"] = variationObjects; courseObjects[0]["lines"] = lineObjects; object["lessons"] = courseObjects
        let illegal = try JSONDecoder().decode(StudyPack.self, from: JSONSerialization.data(withJSONObject: object))
        rejects("an illegal research root move") { try illegal.validate() }
    }

    #if ATLAS_ENGINE_TESTS
    @MainActor static func engineTests() async throws {
        let coach = TrainingCoach()
        defer { coach.shutdown() }
        var results: [String: Int] = [:]
        for lesson in MiddlegameAtlasCurriculum.lessons {
            for line in lesson.lines {
                let states = try line.positions()
                for branch in line.variations ?? [] {
                    let move = Move(uci: branch.moves[0].uci)!
                    let assessment = try await coach.assess(position: states[branch.anchorPly], move: move, movetime: 900)
                    expect(assessment.move == move && assessment.beforeScore != nil && assessment.afterScore != nil, "actual before/after engine evaluation returned for each alternative")
                    expect(coach.usesNormalizedPawnScore, "engine confirms normalized scoring before numeric commentary is used")
                    results[assessment.verdict.rawValue, default: 0] += 1
                    print("ENGINE \(line.id) anchor=\(branch.anchorPly) \(move.uci) \(assessment.verdict.rawValue) before=\(String(describing: assessment.beforeScore)) after=\(String(describing: assessment.afterScore))")
                }
            }
        }
        expect(results.values.reduce(0,+) == 12, "12 alternatives each receive real independent engine analysis")
        print("PASS 12 real engine before/after checks at 900 ms per search; finite-time verdicts (not fixed theoretical truth): \(results)")
    }
    #endif
}
