import Foundation

/// Diagnostic evidence only: limits are not proofs and historical moves need not be optimal.
@main
struct SystematicEngineProbe {
    @MainActor static func main() async throws {
        let paths = EngineConfiguration.resolve()
        guard paths.isConfigured else {
            throw StudyError.invalidContent("Configure XQ_ENGINE_PATH and XQ_ENGINE_NETWORK before running this explicit engine probe")
        }
        let coach = TrainingCoach(binaryURL: paths.binary, networkURL: paths.network)
        defer { coach.shutdown() }
        for lesson in SystematicCurriculum.lessons {
            for line in lesson.lines {
                let positions = try line.positions()
                for checkpoint in line.checkpoints ?? [] {
                    let position = positions[checkpoint.ply]
                    let historical = Move(uci: line.moves[checkpoint.ply].uci)!
                    let reference = try await coach.assess(position: position, move: historical, movetime: 900)
                    let candidate = reference.bestMove ?? historical
                    let candidateCheck = candidate == historical ? reference : try await coach.assess(position: position, move: candidate, movetime: 1300)
                    print("\(line.id) ply=\(checkpoint.ply) side=\(position.sideToMove.rawValue) reference=\(historical.uci):\(reference.verdict.rawValue) candidate=\(candidate.uci):\(candidateCheck.verdict.rawValue) \(candidateCheck.detail)")
                    fflush(stdout)
                }
            }
        }
    }
}
