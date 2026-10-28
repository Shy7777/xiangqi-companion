#if ENGINE_TESTS
import Foundation

@main
struct EngineTests {
    static let startFEN = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1"

    @MainActor
    static func wait(_ message: String, timeout: Double = 15,
                     until predicate: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() > deadline { throw Failure(message: message) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    struct Failure: Error { let message: String }
    static func require(_ expression: @autoclosure () -> Bool, _ message: String) throws {
        if !expression() { throw Failure(message: message) }
    }

    static func testCandidateGrouping() throws {
        func line(_ depth: Int, _ rank: Int, _ move: String) -> EngineLine {
            PikafishEngine.parseInfo("info depth \(depth) multipv \(rank) score cp 10 time 250 nodes 100 pv \(move)")!
        }
        var assembler = EngineLineGroupAssembler(expectedPVCount: 3)
        try require(assembler.append(line(10, 1, "h2e2")) == nil, "Published an incomplete rank-one group")
        try require(assembler.append(line(10, 2, "b2e2")) == nil, "Published an incomplete two-line group")
        try require(assembler.append(line(10, 3, "b0c2"))?.count == 3, "Complete group was not published")
        let previous = assembler.latestComplete
        try require(assembler.append(line(11, 1, "h2e2")) == nil, "Mixed new rank one with old depth")
        try require(assembler.append(line(11, 2, "b0c2")) == nil, "Mixed candidate reordering across depths")
        try require(assembler.latestComplete == previous, "Incomplete depth replaced last complete iteration")
        try require(assembler.append(line(11, 3, "b0c2")) == nil, "Duplicate first moves were published")
        let repaired = assembler.append(line(11, 3, "b2e2"))
        try require(repaired?.count == 3 && Set(repaired!.map(\.depth)) == [11], "Did not recover complete distinct same-depth group")
        try require(assembler.append(line(12, 2, "b2e2")) == nil, "Published a group without rank one")
        try require(assembler.append(line(11, 1, "b0c2")) == nil, "Repeated rank one reused stale ranks at the same depth")
        try require(assembler.append(line(11, 2, "h2e2")) == nil, "Same-depth report completed prematurely")
        try require(assembler.append(line(11, 3, "b2e2"))?.count == 3, "Same-depth replacement could not complete")
        let last = assembler.latestComplete
        try require(assembler.append(line(10, 1, "h2e2")) == nil && assembler.latestComplete == last,
                    "Late lower-depth output regressed the published candidates")
        var one = EngineLineGroupAssembler(expectedPVCount: 1)
        try require(one.append(line(1, 1, "e9f9"))?.count == 1, "Single-legal-move group did not publish")
        var two = EngineLineGroupAssembler(expectedPVCount: 2)
        try require(two.append(line(1, 1, "e9f9")) == nil, "Two-move group published too early")
        try require(two.append(line(1, 2, "e9d9"))?.count == 2, "Two-legal-move group did not publish")
        print("PASS: deterministic partial-depth/reordered/duplicate MultiPV regression; 1/2/3 candidate groups")
    }

    @MainActor
    static func main() async {
        let configured = EngineConfiguration.resolve()
        let binary = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : configured.binary
        let network = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : configured.network
        let engine = PikafishEngine(binaryURL: binary, networkURL: network)
        do {
            try testCandidateGrouping()
            let missing = PikafishEngine(binaryURL: URL(fileURLWithPath: "/nonexistent/xiangqi-engine"), networkURL: network)
            missing.start()
            try require(missing.error != nil && !missing.isReady, "Missing binary did not produce an error")
            let noNetwork = PikafishEngine(binaryURL: URL(fileURLWithPath: "/bin/cat"), networkURL: URL(fileURLWithPath: "/nonexistent/xiangqi.nnue"))
            noNetwork.start()
            try require(noNetwork.error != nil && !noNetwork.isReady, "Missing network did not produce an error")

            let parsed = PikafishEngine.parseInfo("info depth 20 multipv 2 score mate -3 nodes 1234 time 251 wdl 100 200 700 pv a0a1 b9c7")
            try require(parsed?.score == .mate(-3) && parsed?.rank == 2 && parsed?.wdl?.losses == 700,
                        "Mate/WDL parser failed")
            try require(PikafishEngine.parseInfo("info depth 1 score cp 10 lowerbound pv a0a1") == nil,
                        "Bound score was presented as exact")

            guard ProcessInfo.processInfo.environment["XQ_RUN_ENGINE_TESTS"] == "1" || CommandLine.arguments.count > 2 else {
                print("PASS: offline UCI parsing, candidate grouping and missing-resource errors")
                print("SKIP: actual Pikafish process tests (run verify.sh --with-engine with explicit engine/network paths)")
                return
            }

            var completions: [Int: [EngineLine]] = [:]
            var deliveredRevisions: [Int] = []
            var invalidGroups: [Int] = []
            var expectedCounts: [Int: Int] = [:]
            engine.onResults = { revision, rows, completed in
                deliveredRevisions.append(revision)
                if rows.count != (expectedCounts[revision] ?? 3) || Set(rows.map(\.depth)).count != 1 ||
                    Set(rows.compactMap { $0.pv.first }).count != rows.count {
                    invalidGroups.append(revision)
                }
                if completed { completions[revision] = rows }
            }
            engine.start()
            try await wait("UCI handshake timed out") { engine.isReady || engine.error != nil }
            try require(engine.isReady, "Startup failed: \(engine.error ?? "unknown")")
            try require(engine.usesNormalizedPawnScore, "Normalized pawn scoring option was not configured")
            engine.analyze(fen: startFEN, revision: 1, movetime: 350)
            try await wait("Initial search did not complete") { completions[1] != nil || engine.error != nil }
            let initial = completions[1] ?? []
            try require(initial.count == 3 && initial.allSatisfy { !$0.pv.isEmpty && $0.depth > 0 },
                        "Actual search did not return three complete PVs")
            try require(initial.allSatisfy { $0.timeMS != nil && $0.nodes != nil }, "Search timing/nodes are missing")
            print("PASS: actual engine handshake, normalized score, 3 PVs, search completion")

            engine.analyze(fen: startFEN, revision: 2, movetime: 2000)
            try await wait("Long search did not begin") { deliveredRevisions.contains(2) || engine.error != nil }
            let cutover = deliveredRevisions.count
            engine.analyze(fen: startFEN, moves: ["h2e2"], revision: 3, movetime: 300)
            engine.analyze(fen: startFEN, moves: ["h2e2", "h9g7"], revision: 4, movetime: 350)
            try await wait("Replacement search did not complete") { completions[4] != nil || engine.error != nil }
            try require(engine.error == nil, "Replacement error: \(engine.error ?? "")")
            try require(completions[2] == nil && completions[3] == nil, "Cancelled search reported completion")
            try require(deliveredRevisions.dropFirst(cutover).allSatisfy { $0 == 4 }, "Stale search contaminated new results")
            try require(completions[4]?.count == 3, "Replacement search did not return three PVs")
            try require(engine.latestRevision == 4 && !engine.isThinking, "Latest revision/completion state incorrect")
            print("PASS: serial stop/bestmove, debounce, history input, stale result rejection")

            expectedCounts[5] = 2
            engine.analyze(fen: "4k4/4R4/9/9/9/9/9/9/9/4K4 b - - 0 1", revision: 5, movetime: 250, expectedPVCount: 2)
            try await wait("Two-legal-move position did not complete") { completions[5] != nil || engine.error != nil }
            try require(completions[5]?.count == 2, "Two-legal-move position returned an incomplete group")
            expectedCounts[6] = 1
            engine.analyze(fen: "4k4/3RR4/9/9/9/9/9/9/9/4K4 b - - 0 1", revision: 6, movetime: 250, expectedPVCount: 1)
            try await wait("One-legal-move position did not complete") { completions[6] != nil || engine.error != nil }
            try require(completions[6]?.count == 1, "One-legal-move position returned an incomplete group")
            try require(invalidGroups.isEmpty, "Real engine published mixed/duplicate/incomplete groups: \(invalidGroups)")
            print("PASS: actual 1/2-legal-move endings; every intermediate and final group has distinct moves at a single depth")

            engine.shutdown()
            try await wait("Engine process did not exit after quit", timeout: 5) { !engine.isRunning }
            try require(!engine.isReady && !engine.isThinking && engine.error == nil, "Clean shutdown failed")
            print("PASS: missing resource errors, parser, shutdown; WDL support = \(engine.supportsWDL)")
        } catch {
            engine.shutdown()
            print("FAIL: \(error)")
            exit(1)
        }
    }
}
#endif
