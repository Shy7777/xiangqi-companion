import Foundation

/// A submitted legal move can be visible immediately without pretending the
/// asynchronous evaluation has accepted it or committing a learning result.
struct StudySubmission: Equatable {
    let before: Position
    let after: Position
    let move: Move

    init?(position: Position, move: Move) {
        guard let after = try? position.applying(move: move) else { return nil }
        self.before = position; self.after = after; self.move = move
    }
}

enum StudyNoticePresentation {
    // Only this known informational notice is nonmodal. File, import, engine,
    // corruption and persistence errors retain the existing explicit alert.
    static func isInformational(_ message: String?) -> Bool {
        message == "检验期间查看课程、复习记录或资料可能透露题型与思路，本轮已记为含辅助；返回后仍可继续练习，但不计独立通过。"
    }
}

/// Reference identity and engine quality are separate facts. A historical or
/// generated reference can still require verification; matching it is not a
/// reason to silently turn an uncertain/poor engine assessment into a pass.
enum StudyReferenceFeedback {
    static func title(for assessment: MoveAssessment, matchesReference: Bool) -> String {
        guard matchesReference else { return assessment.title }
        switch assessment.verdict {
        case .exactBest, .good: return "与参考谱一致"
        case .uncertain, .inaccuracy, .mistake: return "与参考谱一致 · 需要复核"
        }
    }
    static func summary(for assessment: MoveAssessment, matchesReference: Bool, purpose: String = "") -> String {
        if matchesReference {
            switch assessment.verdict {
            case .exactBest, .good:
                let first = purpose.components(separatedBy: CharacterSet(charactersIn: "。\n")).first ?? ""
                return "你走中了参考谱的这一手。" + (first.isEmpty ? "" : "思路：" + String(first.prefix(100)) + "。")
            case .uncertain: return "这步与参考谱相同，但本轮分析还不能稳妥判定，不计错。"
            case .inaccuracy, .mistake: return "这步确实按谱走了，但本轮引擎发现风险；展开解释核对依据。"
            }
        }
        switch assessment.verdict {
        case .exactBest: return "这是不同于参考谱的选择，与本轮引擎首选一致。"
        case .good: return "这是合理变招，不必照抄参考谱。"
        case .inaccuracy: return "这步有所让步，看看对手怎样利用。"
        case .mistake: return "这步有明显遗漏，可以悔棋后再判断。"
        case .uncertain: return "目前还不能稳妥判定，本次不计错。"
        }
    }
}

extension LearningModel {
    var studyBoardPosition: Position { studySubmission?.after ?? position }
    var studyBoardLastMove: Move? { studySubmission?.move ?? lastMove }
    var isAssessingSubmission: Bool { busy && studySubmission != nil }
    var referenceChoiceMatches: Bool {
        guard hasPendingMove, let line, line.moves.indices.contains(cursor), let move = submittedStudyMove else { return false }
        return line.moves[cursor].uci == move.uci
    }
    var nextDecisionActionTitle: String {
        guard let line else { return "继续练习" }
        let hasNext = line.checkpoints?.contains { $0.ply > cursor } ?? false
        return hasNext ? "继续下一题" : "查看本题小结"
    }
    var submissionSummary: String? {
        guard hasPendingMove, let assessment = lastAssessment else { return nil }
        // Reviews have no reference line: do not invent a deviation from one.
        if activeReview != nil { return assessment.detail.components(separatedBy: "。").first }
        let purpose = mode != .test && line?.moves.indices.contains(cursor) == true ? line!.moves[cursor].explanation : ""
        return StudyReferenceFeedback.summary(for: assessment, matchesReference: referenceChoiceMatches, purpose: purpose)
    }
}
