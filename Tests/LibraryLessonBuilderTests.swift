#if LIBRARY_LESSON_BUILDER_TESTS
import Foundation

@main
struct LibraryLessonBuilderTests {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @MainActor
    static func main() async throws {
        var assertions = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard value() else { throw Failure(message: message) }
        }
        func rejects(_ label: String, _ operation: () async throws -> Void) async throws {
            var failed = false
            do { try await operation() } catch { failed = true }
            try check(failed, "Expected rejection: \(label)")
        }
        func rejectsMetadata(_ label: String, _ study: LibraryGeneratedStudy,
                             edit: (inout [String: Any]) -> Void) throws {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(study)) as! [String: Any]
            edit(&object)
            var failed = false
            do {
                let changed = try JSONDecoder().decode(LibraryGeneratedStudy.self, from: JSONSerialization.data(withJSONObject: object))
                try changed.validate()
            } catch { failed = true }
            try check(failed, "Expected metadata rejection: \(label)")
        }
        func row(_ rank: Int = 1, _ pv: [String], depth: Int = 18, score: EngineScore = .cp(42)) -> EngineLine {
            EngineLine(rank: rank, depth: depth, score: score, pv: pv, timeMS: 700, nodes: nil, wdl: nil)
        }
        func verifyFixture(_ pv: [String], from initial: Position) throws {
            var position = initial
            for raw in pv {
                guard let move = Move(uci: raw) else { throw Failure(message: "Bad fixture UCI: \(raw)") }
                position = try position.applying(move: move)
                try position.validate()
            }
        }
        let commit = "3ff21f4502a03f30bb0df55db6f3814ceeb989f5"
        let primary = LibraryCourseMembership(groupID: "opening-repertoire.json", title: "测试布局局面", sourceIndex: 7,
                                              category: "开局定式", section: .opening)
        let secondary = LibraryCourseMembership(groupID: "Chess Patterns/测试定式.json", title: "同盘另一个出处", sourceIndex: 3,
                                                category: "测试定式", section: .patterns)
        func entry(_ position: Position = .initial, title: String = "测试局面",
                   memberships: [LibraryCourseMembership]? = nil) -> LibraryCourseEntry {
            LibraryCourseEntry(id: LibraryCourseEntry.identifier(fen: position.fen), fen: position.fen,
                               title: title, memberships: memberships ?? [primary, secondary])
        }
        let original = entry()
        let mainPV = ["b0c2", "b9c7", "h0g2", "h9g7", "a0b0", "a9b9"]
        let initialRows = [row(1, mainPV), row(2, ["h2e2", "h7e7", "b0c2", "b9c7"]),
                           row(3, ["b2e2", "b9c7", "b0c2", "h9g7"])]
        let replyRows = [row(1, ["b9c7", "h0g2", "h9g7"], depth: 15),
                         row(2, ["h7e7", "h2e2", "b9c7"], depth: 15),
                         row(3, ["h9g7", "h0g2", "b9c7"], depth: 15)]
        let afterFirst = try Position.initial.applying(move: Move(uci: mainPV[0])!)
        for candidate in initialRows { try verifyFixture(candidate.pv, from: .initial) }
        for candidate in replyRows { try verifyFixture(candidate.pv, from: afterFirst) }
        var calls: [(String, Int)] = []
        let started = Date()
        let study = try await LibraryLessonBuilder.build(entry: original, groupID: primary.groupID, commit: commit) { position, budget in
            calls.append((position.fen, budget))
            return position == .initial ? initialRows : replyRows
        }
        try study.validate()
        try check(calls.map(\.0) == [Position.initial.fen, afterFirst.fen], "Queries must use source position and position after the main first move")
        try check(calls.map(\.1) == [700, 700], "Each real search has a 700 ms budget")
        try check(study.version == 1 && study.entryID == original.id && study.groupID == primary.groupID && study.pwaCommit == commit, "Generated cache identity")
        try check(study.searchMilliseconds == 1_400 && study.depth == 18, "Record total search budget and main PV depth")
        try check(study.created >= started && study.created <= Date().addingTimeInterval(1), "Record actual generation time")
        try check(study.lesson.id == original.lessonID && study.lesson.lines.count == 1, "One stable lesson and one reference line")
        try check(study.source.url == primary.sourceURL(commit: commit)?.absoluteString, "Source citation points to the selected upstream file and commit")
        try check(study.lesson.sourceIDs == [study.source.id], "Lesson and source IDs match")
        let line = study.lesson.lines[0]
        try check(line.id == LibraryGeneratedStudy.lineID && line.id == "engine-study-v1", "Stable generated line ID")
        try check(line.startingFEN == original.fen && line.studentSide == .red, "Start exactly at the source position and side")
        try check(line.moves.map(\.uci) == mainPV, "Preserve the legal Top 1 PV")
        let states = try line.positions()
        let decisionPlies = line.moves.indices.filter { states[$0].sideToMove == line.studentSide }
        try check(line.checkpoints?.map(\.ply) == decisionPlies && decisionPlies.first == 0, "Every starting-side decision has a checkpoint, including ply zero")
        try check(line.game == nil, "A source FEN is not an invented historical game")
        let referenceText = [study.source.note, study.lesson.summary, line.title, line.intent, line.adaptation].joined(separator: " ")
        try check(referenceText.contains("引擎") && referenceText.contains("参考"), "Generated material is explicitly labeled as engine reference")
        try check(line.moves.allSatisfy { !$0.explanation.isEmpty && !$0.hint.isEmpty }, "Every move has fact-based text and a usable hint")
        for move in line.moves {
            let firstSentence = String(move.explanation.split(separator: "。").first ?? "")
            try check(!firstSentence.contains("→") && ["将军", "吃", "过河", "河界", "底线", "活动", "合法落点", "可走", "落点", "将死", "困毙", "无合法着"].contains(where: firstSentence.contains), "Lead with a verifiable board fact, not coordinate narration")
        }
        let variations = line.variations ?? []
        try check(!variations.isEmpty && variations.count <= 3, "Bound total alternative lines")
        try check(Set(variations.map(\.anchorPly)) == [0, 1], "Expose both first-move and nonreference opponent-reply decisions when available")
        for variation in variations {
            try check((1...8).contains(variation.moves.count), "Bound each variation to eight plies")
            try check(variation.moves[0].uci != line.moves[variation.anchorPly].uci, "Alternative first move differs from reference move at its anchor")
            let branch = try variation.positions(parent: line)
            try check(branch.first == states[variation.anchorPly], "Variation anchor is the position before the changed move")
        }
        try check(Set(variations.map { "\($0.anchorPly):\($0.moves[0].uci)" }).count == variations.count, "Do not duplicate the same anchored choice")
        let roundtrip = try JSONDecoder().decode(LibraryGeneratedStudy.self, from: JSONEncoder().encode(study))
        try roundtrip.validate()
        try check(roundtrip == study, "Generated cache Codable round trip")

        let repeated = try await LibraryLessonBuilder.build(entry: original, groupID: primary.groupID, commit: commit) { position, _ in
            position == .initial ? initialRows : replyRows
        }
        try check(repeated.entryID == study.entryID && repeated.lesson.id == study.lesson.id && repeated.source.id == study.source.id, "Repeat generation does not create new content identity")
        let otherGroup = try await LibraryLessonBuilder.build(entry: entry(title: "只改导航标题"), groupID: secondary.groupID, commit: commit) { position, _ in
            position == .initial ? [row(1, mainPV)] : []
        }
        try check(otherGroup.entryID == study.entryID && otherGroup.lesson.id == study.lesson.id, "FEN identity survives a different title or category")
        try check(otherGroup.groupID == secondary.groupID && otherGroup.source.url == secondary.sourceURL(commit: commit)?.absoluteString, "Selected membership controls citation, not lesson identity")
        try check(study.lesson.stage == .opening && otherGroup.lesson.stage == .endgame, "Source sections map to the matching study stage")
        try check(study.lesson.goal != otherGroup.lesson.goal && study.lesson.lines[0].checkpoints?.first?.focus != otherGroup.lesson.lines[0].checkpoints?.first?.focus, "Opening and endgame sections have distinct goals and checkpoint focus")
        let defaultGroup = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { position, _ in
            position == .initial ? [row(1, mainPV)] : []
        }
        try check(defaultGroup.groupID == primary.groupID, "Nil group defaults to the primary membership")
        let aliasFEN = original.fen.replacingOccurrences(of: "n", with: "h").replacingOccurrences(of: "N", with: "H")
            .replacingOccurrences(of: "b", with: "e").replacingOccurrences(of: "B", with: "E")
            .replacingOccurrences(of: " w ", with: " r ").replacingOccurrences(of: "0 1", with: "17 42")
        let aliasEntry = LibraryCourseEntry(id: original.id, fen: aliasFEN, title: original.title, memberships: original.memberships)
        let normalized = try await LibraryLessonBuilder.build(entry: aliasEntry, groupID: nil, commit: commit) { position, _ in
            position == .initial ? [row(1, mainPV)] : []
        }
        try check(normalized.entryID == study.entryID && normalized.lesson.lines[0].startingFEN == original.fen, "Piece aliases, red-side alias, and counters preserve canonical FEN identity")

        let cycle = ["b0c2", "b9c7", "c2b0", "c7b9"]
        let maximumPV = Array(repeating: cycle, count: 64).flatMap { $0 }
        let bounded = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { position, _ in
            position == .initial ? [row(1, maximumPV)] : []
        }
        try bounded.validate()
        try check(bounded.lesson.lines[0].moves.map(\.uci) == Array(maximumPV.prefix(10)), "Accept a legal 256-ply engine PV but retain only ten plies")
        let truncationText = bounded.lesson.summary + bounded.lesson.lines[0].adaptation + bounded.lesson.lines[0].intent
        try check(truncationText.contains("10") && (truncationText.contains("截") || truncationText.contains("前")), "Disclose reference-line truncation")
        var brokenTail = Array(repeating: cycle, count: 3).flatMap { $0 }
        brokenTail[11] = "a9a0"
        for (label, rows) in [
            ("no engine rows", [EngineLine]()), ("empty Top 1", [row(1, [])]),
            ("missing Top 1", [row(2, mainPV)]), ("malformed move", [row(1, ["not-a-move"])]),
            ("syntactically valid illegal move", [row(1, ["a0a9"])]),
            ("duplicate engine rank", [row(1, mainPV), row(1, mainPV)]),
            ("out-of-range engine rank", [row(1, mainPV), row(4, mainPV)]),
            ("invalid engine depth", [row(1, mainPV, depth: 0)]),
            ("illegal tail past retained ply ten", [row(1, brokenTail)]),
            ("engine PV beyond 256", [row(1, maximumPV + ["b0c2"])])
        ] {
            try await rejects(label) {
                _ = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { _, _ in rows }
            }
        }
        try await rejects("engine failure") {
            _ = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { _, _ in throw Failure(message: "mock engine failure") }
        }
        let longRootPV = ["h2e2", "h7e7"] + Array(repeating: cycle, count: 3).flatMap { $0 }
        let longReplyPV = ["h7e7", "h2e2"] + Array(repeating: ["b9c7", "h0g2", "c7b9", "g2h0"], count: 3).flatMap { $0 }
        try verifyFixture(longRootPV, from: .initial)
        try verifyFixture(longReplyPV, from: afterFirst)
        let longBranches = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { position, _ in
            position == .initial ? [row(1, mainPV), row(2, longRootPV)] : [row(1, longReplyPV)]
        }
        try longBranches.validate()
        try check(longBranches.lesson.lines[0].variations?.count == 2 && longBranches.lesson.lines[0].variations?.allSatisfy { $0.moves.count == 8 } == true, "Both branch roles are independently bounded to eight plies")
        var badAlternative = longRootPV; badAlternative[10] = "bad-tail"
        try await rejects("adopted alternative has an illegal tail beyond eight") {
            _ = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { position, _ in
                position == .initial ? [row(1, mainPV), row(2, badAlternative)] : []
            }
        }
        var badReply = longReplyPV; badReply[10] = "bad-tail"
        try await rejects("adopted reply has an illegal tail beyond eight") {
            _ = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { position, _ in
                position == .initial ? [row(1, mainPV)] : [row(1, badReply)]
            }
        }

        let sameFirst = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { position, _ in
            position == .initial ? [row(1, mainPV), row(2, ["b0c2", "h7e7"]), row(3, mainPV)]
                : [row(1, ["b9c7", "h0g2"]), row(2, ["b9c7", "h2e2"])]
        }
        try check(sameFirst.lesson.lines[0].variations?.isEmpty ?? true, "Do not invent a new decision when candidate first moves are identical")
        let short = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { position, _ in
            position == .initial ? [row(1, ["b0c2"])] : [row(1, ["b9c7"])]
        }
        try short.validate()
        try check(short.lesson.lines[0].moves.count == 1 && (short.lesson.lines[0].variations?.isEmpty ?? true), "A one-ply reference cannot have an out-of-range anchor-one variation")
        try check(short.searchMilliseconds == 700, "A one-ply reference has no usable reply anchor and needs only the initial search")

        let mateBefore = try Position(fen: "4k4/1N1R1R3/9/9/4P4/9/9/9/9/4K4 w - - 0 1")
        let mateAfter = try mateBefore.applying(move: Move(uci: "d8d9")!)
        try check(mateAfter.legalMoves().isEmpty, "Terminal fixture is independently verified")
        var terminalCalls = 0
        try await rejects("terminal source position") {
            _ = try await LibraryLessonBuilder.build(entry: entry(mateAfter), groupID: nil, commit: commit) { _, _ in
                terminalCalls += 1; return []
            }
        }
        try check(terminalCalls == 0, "Do not send a terminal source position to the engine")
        let mateStudy = try await LibraryLessonBuilder.build(entry: entry(mateBefore), groupID: nil, commit: commit) { _, budget in
            terminalCalls += 1
            try check(budget == 700, "Terminal-first-move search budget")
            return [row(1, ["d8d9"], score: .mate(1))]
        }
        try mateStudy.validate()
        try check(terminalCalls == 1 && mateStudy.searchMilliseconds == 700, "No reply search after an immediately terminal first move")
        try check(mateStudy.lesson.lines[0].checkpoints?.map(\.ply) == [0], "Immediate finish still gives the learner a first decision")

        let blackPosition = Position(board: Position.initial.board, sideToMove: .black)
        let blackPV = ["b9c7", "b0c2", "h9g7", "h0g2"]
        try verifyFixture(blackPV, from: blackPosition)
        let blackStudy = try await LibraryLessonBuilder.build(entry: entry(blackPosition), groupID: nil, commit: commit) { position, _ in
            position == blackPosition ? [row(1, blackPV)] : []
        }
        try blackStudy.validate()
        try check(blackStudy.lesson.lines[0].studentSide == .black && blackStudy.lesson.lines[0].checkpoints?.map(\.ply) == [0, 2], "Black-to-move source keeps black student decisions")
        let quietFirst = line.moves[0].explanation
        try check(!quietFirst.contains("吃掉了") && !quietFirst.contains("已将死") && !quietFirst.contains("必胜"), "Do not fabricate tactical or outcome facts for a quiet first move")
        let captureStart = try Position(fen: "3k5/9/9/9/9/9/p8/9/9/R3K4 w - - 0 1")
        let capturePV = ["a0a3", "d9d8"]
        try verifyFixture(capturePV, from: captureStart)
        let captureStudy = try await LibraryLessonBuilder.build(entry: entry(captureStart), groupID: nil, commit: commit) { position, _ in
            position == captureStart ? [row(1, capturePV)] : []
        }
        let captureFirst = String(captureStudy.lesson.lines[0].moves[0].explanation.split(separator: "。").first ?? "")
        try check(captureFirst.contains("吃") && captureFirst.contains("卒"), "A real capture leads with the captured piece fact")
        let matingFirst = String(mateStudy.lesson.lines[0].moves[0].explanation.split(separator: "。").first ?? "")
        try check(matingFirst.contains("将军") || matingFirst.contains("将死") || matingFirst.contains("无合法着"), "An immediate terminal checking move leads with a check or terminal fact")

        var rejectedEntryCalls = 0
        let badID = LibraryCourseEntry(id: String(repeating: "0", count: 64), fen: original.fen, title: original.title, memberships: original.memberships)
        let badFEN = LibraryCourseEntry(id: original.id, fen: "invalid", title: original.title, memberships: original.memberships)
        let rawAliasHash = LibraryCourseEntry(id: LibraryCourseEntry.identifier(fen: aliasFEN), fen: aliasFEN, title: original.title, memberships: original.memberships)
        for bad in [badID, badFEN, rawAliasHash, entry(memberships: [])] {
            try await rejects("invalid source identity or membership") {
                _ = try await LibraryLessonBuilder.build(entry: bad, groupID: nil, commit: commit) { _, _ in rejectedEntryCalls += 1; return [row(1, mainPV)] }
            }
        }
        try await rejects("group not among entry memberships") {
            _ = try await LibraryLessonBuilder.build(entry: original, groupID: "missing.json", commit: commit) { _, _ in rejectedEntryCalls += 1; return [row(1, mainPV)] }
        }
        try await rejects("invalid source commit") {
            _ = try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: "main") { _, _ in rejectedEntryCalls += 1; return [row(1, mainPV)] }
        }
        try check(rejectedEntryCalls == 0, "Reject bad metadata before requesting engine work")

        try rejectsMetadata("unsupported cache version", study) { $0["version"] = 2 }
        try rejectsMetadata("wrong entry hash", study) { $0["entryID"] = String(repeating: "0", count: 64) }
        try rejectsMetadata("wrong group citation", study) { $0["groupID"] = "other.json" }
        try rejectsMetadata("wrong commit citation", study) { $0["pwaCommit"] = String(repeating: "a", count: 40) }
        try rejectsMetadata("negative search budget", study) { $0["searchMilliseconds"] = -1 }
        try rejectsMetadata("negative engine depth", study) { $0["depth"] = -1 }
        try rejectsMetadata("lesson/source mismatch", study) {
            var lesson = $0["lesson"] as! [String: Any]; lesson["sourceIDs"] = ["unrelated-source"]; $0["lesson"] = lesson
        }
        try rejectsMetadata("lesson ID mismatch", study) {
            var lesson = $0["lesson"] as! [String: Any]; lesson["id"] = "unrelated-lesson"; $0["lesson"] = lesson
        }
        try rejectsMetadata("unsafe source URL", study) {
            var source = $0["source"] as! [String: Any]; source["url"] = "javascript:alert(1)"; $0["source"] = source
        }
        try rejectsMetadata("wrong generated line ID", study) {
            var lesson = $0["lesson"] as! [String: Any], lines = lesson["lines"] as! [[String: Any]]
            lines[0]["id"] = "original-source-game"; lesson["lines"] = lines; $0["lesson"] = lesson
        }
        try rejectsMetadata("missing engine-reference label", study) {
            var lesson = $0["lesson"] as! [String: Any]; lesson["title"] = "伪称上游完整解谱"; $0["lesson"] = lesson
        }
        try rejectsMetadata("invented historical game metadata", study) {
            var lesson = $0["lesson"] as! [String: Any], lines = lesson["lines"] as! [[String: Any]]
            lines[0]["game"] = ["red": "虚构红方", "black": "虚构黑方", "event": "虚构赛事", "date": "2026-01-01", "result": "1-0", "sourceURL": "https://example.test/game"]
            lesson["lines"] = lines; $0["lesson"] = lesson
        }
        try rejectsMetadata("too many main-line moves", study) {
            var lesson = $0["lesson"] as! [String: Any], lines = lesson["lines"] as! [[String: Any]]
            lines[0]["moves"] = Array(repeating: cycle, count: 3).flatMap { $0 }.map { ["uci": $0, "explanation": "引擎参考", "hint": "检查合法走法"] }
            lesson["lines"] = lines; $0["lesson"] = lesson
        }
        try rejectsMetadata("too many variations", study) {
            var lesson = $0["lesson"] as! [String: Any], lines = lesson["lines"] as! [[String: Any]]
            let sample = (lines[0]["variations"] as! [[String: Any]])[0]
            lines[0]["variations"] = (0..<4).map { index -> [String: Any] in var value = sample; value["id"] = "branch-\(index)"; return value }
            lesson["lines"] = lines; $0["lesson"] = lesson
        }
        try rejectsMetadata("out-of-range variation anchor", study) {
            var lesson = $0["lesson"] as! [String: Any], lines = lesson["lines"] as! [[String: Any]]
            var branches = lines[0]["variations"] as! [[String: Any]]; branches[0]["anchorPly"] = 99
            lines[0]["variations"] = branches; lesson["lines"] = lines; $0["lesson"] = lesson
        }
        try rejectsMetadata("nine legal plies exceed variation capacity", longBranches) {
            var lesson = $0["lesson"] as! [String: Any], lines = lesson["lines"] as! [[String: Any]]
            var branches = lines[0]["variations"] as! [[String: Any]]
            branches[0]["moves"] = longRootPV.prefix(9).map { ["uci": $0, "explanation": "引擎参考", "hint": "检查合法走法"] }
            lines[0]["variations"] = branches; lesson["lines"] = lines; $0["lesson"] = lesson
        }
        try rejectsMetadata("missing initial checkpoint", study) {
            var lesson = $0["lesson"] as! [String: Any], lines = lesson["lines"] as! [[String: Any]]
            let checkpoints = lines[0]["checkpoints"] as! [[String: Any]]; lines[0]["checkpoints"] = Array(checkpoints.dropFirst())
            lesson["lines"] = lines; $0["lesson"] = lesson
        }
        try rejectsMetadata("wrong student side", study) {
            var lesson = $0["lesson"] as! [String: Any], lines = lesson["lines"] as! [[String: Any]]
            lines[0]["studentSide"] = "black"; lesson["lines"] = lines; $0["lesson"] = lesson
        }
        try rejectsMetadata("text over per-field capacity", study) {
            var source = $0["source"] as! [String: Any]; source["note"] = (source["note"] as! String) + String(repeating: "x", count: 8_193); $0["source"] = source
        }
        try rejectsMetadata("NUL in source text", study) {
            var source = $0["source"] as! [String: Any]; source["note"] = (source["note"] as! String) + "\0"; $0["source"] = source
        }
        try rejectsMetadata("encoded cache over 200 KiB despite individually bounded strings", study) {
            var lesson = $0["lesson"] as! [String: Any], guide = lesson["guide"] as! [String: Any]
            let large = Array(repeating: String(repeating: "x", count: 8_192), count: 12)
            lesson["pitfalls"] = large; lesson["tags"] = large; guide["questions"] = large
            lesson["guide"] = guide; $0["lesson"] = lesson
        }

        var cancellationCalls = 0
        let cancelled = Task { @MainActor in
            try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { _, _ in
                cancellationCalls += 1; return [row(1, mainPV)]
            }
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; throw Failure(message: "Pre-cancelled generation unexpectedly succeeded") }
        catch is CancellationError { }
        try check(cancellationCalls == 0, "Cancellation prevents unused engine calls")
        let cancelledAfterEvaluation = Task { @MainActor in
            try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { _, _ in
                cancellationCalls += 1
                withUnsafeCurrentTask { $0?.cancel() }
                return [row(1, mainPV)]
            }
        }
        do { _ = try await cancelledAfterEvaluation.value; throw Failure(message: "Cancelled engine result was published") }
        catch is CancellationError { }
        try check(cancellationCalls == 1, "Check cancellation again when an evaluator returns without throwing")
        var replyCancellationCalls = 0
        let cancelledAfterReply = Task { @MainActor in
            try await LibraryLessonBuilder.build(entry: original, groupID: nil, commit: commit) { _, _ in
                replyCancellationCalls += 1
                if replyCancellationCalls == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                return replyCancellationCalls == 1 ? [row(1, mainPV)] : replyRows
            }
        }
        do { _ = try await cancelledAfterReply.value; throw Failure(message: "Cancelled reply result was published") }
        catch is CancellationError { }
        try check(replyCancellationCalls == 2, "Cancellation during the second search also prevents publication")

        print("PASS: LibraryLessonBuilder offline mocks; \(assertions) assertions; no network, engine process, or persisted writes")
    }
}
#endif
