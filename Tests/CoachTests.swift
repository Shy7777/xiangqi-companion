#if COACH_TESTS
import Foundation

@main
struct CoachTests {
    struct Failure: Error { let message: String }
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw Failure(message: message) }
    }

    static func testPolicy() throws {
        let equivalent = MoveAssessmentPolicy.compare(before: .cp(90), after: .cp(40), chosenIsBest: false)
        try require(equivalent.verdict == .good && equivalent.lossCP == 50, "Non-top equivalent move was incorrectly penalized")
        let horizon = MoveAssessmentPolicy.compare(before: .cp(90), after: .cp(-200), chosenIsBest: true)
        try require(horizon.verdict == .uncertain, "Own-best horizon contradiction was called a mistake")
        try require(MoveAssessmentPolicy.compare(before: .cp(90), after: .cp(-200), chosenIsBest: false).verdict == .mistake,
                    "Large measured loss was not identified")
        let maintainedMate = MoveAssessmentPolicy.compare(before: .mate(3), after: .mate(8), chosenIsBest: false)
        try require(maintainedMate.verdict == .good && maintainedMate.lossCP == nil, "Maintained mate was converted to CP loss")
        let losing = MoveAssessmentPolicy.compare(before: .mate(-3), after: .mate(-1), chosenIsBest: false)
        try require(losing.verdict == .uncertain && losing.lossCP == nil, "Previously lost position falsely penalized the move")
        let mateHorizon = MoveAssessmentPolicy.compare(before: .mate(3), after: .cp(500), chosenIsBest: false)
        try require(mateHorizon.verdict == .uncertain && mateHorizon.lossCP == nil, "Mate-to-CP difference was treated as a measured loss")
        try require(MoveAssessmentPolicy.negated(.cp(-120)) == .cp(120) &&
                    MoveAssessmentPolicy.negated(.mate(3)) == .mate(-3), "Mover perspective conversion failed")
        print("PASS: conservative equality, score direction, horizon uncertainty, mate separation")
    }

    @MainActor
    static func main() async {
        let configured = EngineConfiguration.resolve()
        let binary = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : configured.binary
        let network = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : configured.network
        let coach = TrainingCoach(binaryURL: binary, networkURL: network)
        do {
            try testPolicy()
            try await testFailureHandling()
            guard ProcessInfo.processInfo.environment["XQ_RUN_ENGINE_TESTS"] == "1" || CommandLine.arguments.count > 2 else {
                print("SKIP: actual Pikafish coaching assessments (use verify.sh --with-engine)")
                return
            }
            let initial = try await coach.evaluate(position: .initial, movetime: 350)
            try require(initial.count == 3 && Set(initial.compactMap { $0.pv.first }).count == 3, "Coach did not return actual three PVs")
            try require(!coach.isBusy && coach.error == nil, "Successful evaluation left UI busy/error")

            let draw = try Position(fen: "4k4/9/9/9/9/9/9/9/4A4/3K5 w - - 0 1")
            let top = try await coach.evaluate(position: draw, movetime: 700)
            let listed = Set(top.compactMap { $0.pv.first })
            guard let unlisted = draw.legalMoves().first(where: { !listed.contains($0.uci) }) else {
                throw Failure(message: "Equivalent-move fixture did not have a non-top candidate")
            }
            let assessment = try await coach.assess(position: draw, move: unlisted, movetime: 700)
            try require(assessment.verdict == .good || assessment.verdict == .exactBest,
                        "Real engine rejected the non-top equivalent draw: \(assessment.detail)")
            try require(assessment.beforeScore != nil && assessment.afterScore != nil && !assessment.replyPV.isEmpty,
                        "Assessment did not analyze both the original and resulting position")
            print("PASS: actual original/resulting search; a move absent from previous Top 3 is accepted as equivalent")

            let mate = try Position(fen: "4k4/1N1R1R3/9/9/4P4/9/9/9/9/4K4 w - - 0 1")
            let winningMove = Move(uci: "d8d9")!
            let finished = try mate.applying(move: winningMove)
            try require(finished.legalMoves().isEmpty, "Immediate-win fixture is not terminal")
            let terminalAssessment = try await coach.assess(position: mate, move: winningMove, movetime: 350)
            try require(terminalAssessment.verdict == .exactBest && terminalAssessment.replyPV.isEmpty && terminalAssessment.lossCP == nil,
                        "Terminal win was not handled directly")
            let endedEvaluation = try await coach.evaluate(position: finished, movetime: 350)
            let endedReply = try await coach.chooseReply(position: finished, level: 0)
            try require(endedEvaluation.isEmpty && endedReply == nil, "Terminal loser was asked to play again")
            let mateLines = try await coach.evaluate(position: mate, movetime: 500)
            guard case .mate(let mateDistance) = mateLines.first?.score, mateDistance > 0 else {
                throw Failure(message: "Actual engine failed to report fixture's winning mate")
            }
            print("PASS: actual mate analysis, immediate win, terminal no-reply behavior")

            for level in 0...4 {
                let reply = try await coach.chooseReply(position: .initial, level: level)
                try require(reply.map { Position.initial.legalMoves().contains($0) } == true, "Companion level returned an illegal move")
            }
            print("PASS: all five local companion levels return actual legal engine candidates")

            let slow = Task { try await coach.evaluate(position: .initial, movetime: 3000) }
            try await Task.sleep(nanoseconds: 150_000_000)
            let cancelledAt = Date()
            coach.cancel()
            do { _ = try await slow.value; throw Failure(message: "Explicit cancel did not cancel the awaiting caller") }
            catch is CancellationError { }
            try require(Date().timeIntervalSince(cancelledAt) < 0.3 && !coach.isBusy && coach.error == nil,
                        "Explicit cancellation was slow or left busy/error state")

            let taskCancelled = Task { try await coach.evaluate(position: .initial, movetime: 3000) }
            try await Task.sleep(nanoseconds: 150_000_000)
            taskCancelled.cancel()
            do { _ = try await taskCancelled.value; throw Failure(message: "Task cancellation did not propagate") }
            catch is CancellationError { }

            let superseded = Task { try await coach.assess(position: .initial, move: Move(uci: "h2e2")!, movetime: 2000) }
            try await Task.sleep(nanoseconds: 200_000_000)
            let fresh = try await coach.evaluate(position: draw, movetime: 350)
            do { _ = try await superseded.value; throw Failure(message: "Old assessment survived a new session") }
            catch is CancellationError { }
            try require(fresh.allSatisfy { line in line.pv.first.flatMap(Move.init(uci:)).map { draw.legalMoves().contains($0) } == true },
                        "Superseded assessment contaminated new evaluation")
            try require(!coach.isBusy && coach.error == nil, "Old cancellation overwrote the new successful session")
            print("PASS: immediate explicit cancel, Task cancel, new-session ticket protection, no stuck UI")

            coach.shutdown()
            try await Task.sleep(nanoseconds: 300_000_000)
            print("PASS: live coaching service shutdown completes")
        } catch {
            coach.shutdown()
            print("FAIL: \(error)")
            exit(1)
        }
    }

    @MainActor
    static func testFailureHandling() async throws {
            // No downloaded files are needed to exercise these process failures.
            let fixture = URL(fileURLWithPath: "/dev/null")
            let missing = TrainingCoach(binaryURL: URL(fileURLWithPath: "/nonexistent/coach-engine"), networkURL: fixture)
            do { _ = try await missing.evaluate(position: .initial); throw Failure(message: "Missing engine did not throw") }
            catch is TrainingCoachError { }
            try require(!missing.isBusy && missing.error != nil, "Missing resource left coach busy")
            missing.shutdown()
            let missingNetwork = TrainingCoach(binaryURL: URL(fileURLWithPath: "/bin/cat"), networkURL: URL(fileURLWithPath: "/nonexistent/coach.nnue"))
            do { _ = try await missingNetwork.evaluate(position: .initial); throw Failure(message: "Missing network did not throw") }
            catch is TrainingCoachError { }
            try require(!missingNetwork.isBusy && missingNetwork.error != nil, "Missing network left coach busy")
            missingNetwork.shutdown()

            // cat accepts input but never speaks UCI: exercise the actual
            // startup deadline through the coach instead of faking a timeout.
            let unresponsive = TrainingCoach(binaryURL: URL(fileURLWithPath: "/bin/cat"), networkURL: fixture)
            defer { unresponsive.shutdown() }
            let timeoutStarted = Date()
            do { _ = try await unresponsive.evaluate(position: .initial, movetime: 250); throw Failure(message: "Non-UCI process did not time out") }
            catch is TrainingCoachError { }
            try require(!unresponsive.isBusy && unresponsive.error?.contains("超时") == true &&
                        Date().timeIntervalSince(timeoutStarted) < 14,
                        "Unresponsive process did not release the coach within its deadline")
            unresponsive.shutdown()
            print("PASS: real unresponsive UCI-process timeout releases the awaiting UI")
            print("PASS: missing resources fail promptly and service shutdown completes")
    }
}
#endif
