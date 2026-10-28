import Foundation
import Combine

struct MoveAssessment: Sendable {
    enum Verdict: String, Codable, Sendable {
        case exactBest, good, inaccuracy, mistake, uncertain
    }
    let move: Move
    let bestMove: Move?
    let verdict: Verdict
    let title: String
    let detail: String
    let lossCP: Int?
    /// Both scores use the learner/mover's perspective, never the opponent's.
    let beforeScore: EngineScore?
    let afterScore: EngineScore?
    let replyPV: [String]
    let bestPV: [String]
}

enum TrainingCoachError: Error, LocalizedError, Equatable {
    case engine(String)
    case timeout
    case noEvaluation
    case invalidEngineMove

    var errorDescription: String? {
        switch self {
        case .engine(let message): return message
        case .timeout: return "本轮教练分析超时，请重试。"
        case .noEvaluation: return "本次限时搜索没有形成完整评价，请增加计算时间后重试。"
        case .invalidEngineMove: return "引擎返回的候选与当前棋盘不一致，请重新分析。"
        }
    }
}

/// Scoring policy is separate from search so horizon effects and mate scores
/// can be regression-tested without pretending a short search is a proof.
enum MoveAssessmentPolicy {
    struct Comparison {
        let verdict: MoveAssessment.Verdict
        let title: String
        let explanation: String
        let lossCP: Int?
    }

    static func negated(_ score: EngineScore) -> EngineScore {
        switch score {
        case .cp(let value): return .cp(-value)
        case .mate(let value): return .mate(-value)
        }
    }

    static func compare(before: EngineScore, after: EngineScore, chosenIsBest: Bool,
                        normalizedPawnScore: Bool = true) -> Comparison {
        func answer(_ verdict: MoveAssessment.Verdict, _ title: String, _ explanation: String,
                    _ loss: Int? = nil) -> Comparison {
            Comparison(verdict: verdict, title: title, explanation: explanation, lossCP: loss)
        }
        switch (before, after) {
        case (.cp(let original), .cp(let resulting)):
            guard normalizedPawnScore else {
                return answer(.uncertain, "暂不做误差分级", "引擎未确认标准化兵分，不能用当前分数差套用教学阈值。")
            }
            let difference = original - resulting
            let loss = max(0, difference)
            let scores = String(format: "走前 %+.2f，走后 %+.2f（均为你方视角）。", Double(original) / 100, Double(resulting) / 100)
            if difference < -150 || (chosenIsBest && loss > 100) {
                return answer(.uncertain, "限时评价还不稳定", scores + "两次搜索的判断变化较大，本轮不把它记作失误。", loss)
            }
            if chosenIsBest {
                return answer(.exactBest, "与本轮首选一致", scores + "你走的是这次搜索的第一候选。", loss)
            }
            if loss <= 70 {
                return answer(.good, "这步也可以", scores + "评价差距较小；即使没有出现在前三候选，也不按错误处理。", loss)
            }
            if loss < 120 {
                return answer(.uncertain, "这步值得再看看", scores + "差距接近判断边界，先不作明确判错。", loss)
            }
            let lossText = String(format: "相对走前首选，约损失 %.2f 标准化兵分。", Double(loss) / 100)
            if loss < 250 {
                return answer(.inaccuracy, "可以走得更稳", scores + lossText + "可回到这步前比较另一种选择。", loss)
            }
            return answer(.mistake, "这步需要重练", scores + lossText + "先看对方的最佳应对，再回到原局面重走。", loss)

        case (.mate(let first), .mate(let second)) where first > 0 && second > 0:
            return answer(chosenIsBest ? .exactBest : .good,
                          chosenIsBest ? "与本轮首选一致" : "仍然保持杀棋",
                          "走前和走后的搜索都找到你方杀棋；不因杀棋步数不同直接扣分。")

        case (.mate(let first), .mate(let second)) where first <= 0 && second <= 0:
            return answer(chosenIsBest ? .exactBest : .uncertain,
                          chosenIsBest ? "与本轮防守首选一致" : "原局面已被搜索判为败势",
                          "两次搜索都报告你方会被杀。不能仅凭走后败势，把已经存在的困难算成这一步造成的。")

        case (_, .mate(let resulting)) where resulting > 0:
            return answer(chosenIsBest ? .exactBest : .good,
                          chosenIsBest ? "与本轮首选一致" : "走后找到你方杀棋",
                          "走后搜索找到你方杀棋。杀棋分数与普通兵分分开处理。")

        case (_, .mate(let resulting)) where resulting <= 0:
            return answer(chosenIsBest ? .uncertain : .mistake,
                          chosenIsBest ? "需要加深确认" : "走后出现被杀路线",
                          chosenIsBest
                          ? "你采用了本轮首选，但走后搜索又报告被杀，说明两次限时评价不一致，本轮不直接判错。"
                          : "走后搜索找到对方杀棋，走前首选未报告相同结果。请查看对方应手并重走；杀棋不折算成兵分损失。")

        default:
            return answer(.uncertain, "杀棋结论需要再确认",
                          "走前与走后的杀棋结论不同。当前搜索不足以把这个变化换算成确定的兵分损失。")
        }
    }
}

/// Owns an independent engine process. A newer call cancels the previous
/// operation, including an assessment's second search; callers never share
/// a mutable engine callback with the free-analysis board.
@MainActor
final class TrainingCoach: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var status = "教练已就绪"
    @Published private(set) var error: String?
    var usesNormalizedPawnScore: Bool { engine.usesNormalizedPawnScore }

    private let engine: PikafishEngine
    private var operation = 0
    private var searchRevision = 0
    private var waitingRevision: Int?
    private var completedRows: [EngineLine]?

    init(binaryURL: URL? = nil, networkURL: URL? = nil) {
        let configured = EngineConfiguration.resolve()
        let selectedBinary = binaryURL ?? configured.binary
        let selectedNetwork = networkURL ?? configured.network
        engine = PikafishEngine(binaryURL: selectedBinary, networkURL: selectedNetwork)
        engine.onResults = { [weak self] revision, rows, complete in
            guard complete, let self, self.waitingRevision == revision else { return }
            self.completedRows = rows
        }
    }

    func cancel() {
        operation += 1
        waitingRevision = nil
        completedRows = nil
        engine.stop()
        isBusy = false
        error = nil
        status = "本轮分析已取消"
    }

    func shutdown() {
        cancel()
        engine.shutdown()
        status = "教练已停止"
    }

    func evaluate(position: Position, movetime: Int = 900) async throws -> [EngineLine] {
        let token = begin("正在看当前局面…")
        return try await perform(token) {
            try position.validate()
            let result = try await self.search(position, token: token, movetime: movetime)
            self.finish(token, status: result.isEmpty ? "当前一方无合法走法" : "局面评价完成")
            return result
        }
    }

    func assess(position: Position, move: Move, movetime: Int = 900) async throws -> MoveAssessment {
        let token = begin("正在比较你的选择…")
        return try await perform(token) {
            try position.validate()
            let next = try position.applying(move: move)
            if next.legalMoves().isEmpty {
                self.finish(token, status: "这步已经获胜")
                return MoveAssessment(move: move, bestMove: move, verdict: .exactBest,
                                      title: "这步已经获胜",
                                      detail: "对方已经没有合法走法，按象棋规则本地判负。这个结论来自走法检查，不依赖限时分数。",
                                      lossCP: nil, beforeScore: nil, afterScore: nil,
                                      replyPV: [], bestPV: [move.uci])
            }
            let before = try await self.search(position, token: token, movetime: movetime)
            guard let best = before.first, let bestMove = best.pv.first.flatMap(Move.init(uci:)) else {
                throw TrainingCoachError.noEvaluation
            }
            self.status = "正在检查对方的最佳应对…"
            let after = try await self.search(next, token: token, movetime: movetime)
            guard let reply = after.first else { throw TrainingCoachError.noEvaluation }
            let afterScore = MoveAssessmentPolicy.negated(reply.score)
            let comparison = MoveAssessmentPolicy.compare(before: best.score, after: afterScore,
                                                           chosenIsBest: bestMove == move,
                                                           normalizedPawnScore: self.engine.usesNormalizedPawnScore)
            var facts: [String] = []
            if position.isInCheck(position.sideToMove) { facts.append("这步解除了将军。") }
            if let captured = position[move.to] { facts.append("这步吃掉了对方的\(captured.symbol)。") }
            if next.isInCheck(next.sideToMove) { facts.append("这步形成将军。") }
            let budget = min(10_000, max(100, movetime))
            let detail = facts.joined() + comparison.explanation + "本次前后局面各限时 \(budget) 毫秒，评价可能随搜索加深变化。"
            self.finish(token, status: "这步已完成复盘")
            return MoveAssessment(move: move, bestMove: bestMove, verdict: comparison.verdict,
                                  title: comparison.title, detail: detail, lossCP: comparison.lossCP,
                                  beforeScore: best.score, afterScore: afterScore,
                                  replyPV: reply.pv, bestPV: best.pv)
        }
    }

    /// Levels are local search settings, not an Elo or a claim of human skill.
    /// Lower levels select a lower-ranked but close candidate deterministically.
    func chooseReply(position: Position, level: Int) async throws -> Move? {
        let token = begin("陪练正在思考…")
        return try await perform(token) {
            try position.validate()
            let boundedLevel = min(4, max(0, level))
            let rows = try await self.search(position, token: token, movetime: [250, 500, 1000, 1800, 3000][boundedLevel])
            guard let best = rows.first else {
                self.finish(token, status: "当前一方无合法走法")
                return nil
            }
            let tolerance = boundedLevel == 0 ? 90 : 35
            let choices = rows.filter { candidate in
                switch (best.score, candidate.score) {
                case (.cp(let first), .cp(let other)):
                    return self.engine.usesNormalizedPawnScore && first - other <= tolerance
                case (.mate(let first), .mate(let other)):
                    return first > 0 && other > 0
                default: return candidate.rank == 1
                }
            }
            let pick = boundedLevel >= 2 ? best : (choices.dropFirst(boundedLevel == 0 ? 2 : 1).first ?? choices.last ?? best)
            guard let move = pick.pv.first.flatMap(Move.init(uci:)),
                  position.legalMoves(from: move.from).contains(move) else { throw TrainingCoachError.invalidEngineMove }
            self.finish(token, status: "陪练已选择应手")
            return move
        }
    }

    private func begin(_ message: String) -> Int {
        cancel()
        isBusy = true
        status = message
        return operation
    }

    private func finish(_ token: Int, status message: String) {
        guard token == operation else { return }
        waitingRevision = nil
        completedRows = nil
        isBusy = false
        status = message
    }

    private func check(_ token: Int) throws {
        try Task.checkCancellation()
        guard token == operation else { throw CancellationError() }
    }

    private func perform<T>(_ token: Int, body: @MainActor () async throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            do {
                try check(token)
                return try await body()
            } catch {
                if token == operation {
                    engine.stop()
                    waitingRevision = nil
                    completedRows = nil
                    isBusy = false
                    if error is CancellationError {
                        self.error = nil
                        status = "本轮分析已取消"
                    } else {
                        self.error = error.localizedDescription
                        status = "教练暂时无法分析"
                    }
                }
                throw error
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.operation == token else { return }
                self.cancel()
            }
        }
    }

    private func search(_ position: Position, token: Int, movetime: Int) async throws -> [EngineLine] {
        try check(token)
        let legal = position.legalMoves()
        if legal.isEmpty { return [] }
        searchRevision += 1
        let revision = searchRevision
        waitingRevision = revision
        completedRows = nil
        engine.analyze(fen: position.fen, revision: revision, movetime: movetime,
                       expectedPVCount: min(3, legal.count))
        let deadline = Date().addingTimeInterval(Double(min(10_000, max(100, movetime))) / 1000 + 15)
        while true {
            try check(token)
            if let engineError = engine.error { throw TrainingCoachError.engine(engineError) }
            if let results = completedRows {
                waitingRevision = nil
                completedRows = nil
                guard !results.isEmpty else { throw TrainingCoachError.noEvaluation }
                guard results.allSatisfy({ line in
                    guard let move = line.pv.first.flatMap(Move.init(uci:)) else { return false }
                    return legal.contains(move)
                }) else { throw TrainingCoachError.invalidEngineMove }
                return results
            }
            if Date() >= deadline { throw TrainingCoachError.timeout }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
