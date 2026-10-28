import Foundation
import CryptoKit

enum LearningStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case foundation, opening, tactics, endgame, strategy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .foundation: return "01 · 不丢子，先看懂威胁"
        case .opening: return "02 · 常见开局与变招"
        case .tactics: return "03 · 中局配合与计算"
        case .endgame: return "04 · 残局兑现与防守"
        case .strategy: return "05 · 计划、实战与复盘"
        }
    }
    var shortTitle: String {
        switch self {
        case .foundation: return "基本功"
        case .opening: return "开局"
        case .tactics: return "中局"
        case .endgame: return "残局"
        case .strategy: return "实战思路"
        }
    }
}

struct LearningSource: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let url: String
    let note: String
}

struct StudyMove: Codable, Equatable, Sendable {
    let uci: String
    let explanation: String
    let hint: String
    init(_ uci: String, _ explanation: String, hint: String = "先看对手威胁，再检查这步能改善什么。") {
        self.uci = uci; self.explanation = explanation; self.hint = hint
    }
}

struct StudyCheckpoint: Codable, Equatable, Sendable {
    /// Zero-based ply before the learner's decision, not the position after that move.
    let ply: Int
    let title: String
    let prompt: String
    let focus: String
    let explanation: String
}

struct StudyGameMetadata: Codable, Equatable, Sendable {
    let red: String
    let black: String
    let event: String
    let date: String
    let result: String
    let sourceURL: String
}

struct StudyGuide: Codable, Equatable, Sendable {
    let level: String
    let reading: String
    let questions: [String]
    let workflow: [String]
    let takeaway: String
}

struct StudyVariation: Identifiable, Codable, Equatable, Sendable {
    static let maximumPerLine = 16
    static let maximumMoves = 80
    let id: String
    let title: String
    /// Zero-based parent position BEFORE its move at this index.
    let anchorPly: Int
    let condition: String
    let explanation: String
    let moves: [StudyMove]

    func positions(parent: StudyLine) throws -> [Position] {
        try positions(parent: parent, parentPositions: parent.positions())
    }

    /// Pure expansion. No course progress, hint counters, or resume state is touched.
    func studyLine(parent: StudyLine) throws -> StudyLine {
        let states = try positions(parent: parent)
        let student = states[0].sideToMove
        var derived = StudyLine(id: parent.id + "--variation--" + id, title: title, intent: condition,
                                adaptation: explanation, startingFEN: states[0].fen, studentSide: student, moves: moves)
        derived.checkpoints = moves.indices.filter { states[$0].sideToMove == student }.map {
            StudyCheckpoint(ply: $0, title: "变式第 \($0 + 1) 步", prompt: "根据当前变式局面独立选择走法。",
                            focus: moves[$0].hint, explanation: moves[$0].explanation)
        }
        return derived
    }

    func positions(parent: StudyLine, parentPositions: [Position]) throws -> [Position] {
        func filled(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard filled(id), !id.contains("/"), filled(title), filled(condition), filled(explanation),
              (0..<parent.moves.count).contains(anchorPly), parentPositions.count == parent.moves.count + 1,
              (1...Self.maximumMoves).contains(moves.count),
              moves.allSatisfy({ filled($0.explanation) && filled($0.hint) }) else {
            throw StudyError.invalidContent("变式需要完整编号、触发条件、讲解及 1–80 步续着；起点必须位于原谱走子之前。")
        }
        var position = parentPositions[anchorPly]
        var states = [position]
        for item in moves {
            guard let move = Move(uci: item.uci) else { throw StudyError.invalidMove(item.uci) }
            position = try position.applying(move: move); states.append(position)
        }
        return states
    }
}

struct StudyLine: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let intent: String
    let adaptation: String
    var startingFEN: String = Position.initial.fen
    var studentSide: Side = .red
    let moves: [StudyMove]
    /// nil preserves legacy every-turn rehearsal; [] is reading-only.
    var checkpoints: [StudyCheckpoint]? = nil
    var game: StudyGameMetadata? = nil
    var variations: [StudyVariation]? = nil

    var contentFingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(self) else { return "" }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func positions() throws -> [Position] {
        var position = try Position(fen: startingFEN)
        try position.validate()
        var result = [position]
        for item in moves {
            guard let move = Move(uci: item.uci) else { throw StudyError.invalidMove(item.uci) }
            position = try position.applying(move: move)
            result.append(position)
        }
        return result
    }
}

struct LearningLesson: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let stage: LearningStage
    let order: Int
    let summary: String
    let goal: String
    let principle: String
    let whenToAdapt: String
    let pitfalls: [String]
    var prerequisites: [String] = []
    let sourceIDs: [String]
    let lines: [StudyLine]
    var estimatedMinutes: Int = 12
    var tags: [String] = []
    var guide: StudyGuide? = nil
    var isSystematic: Bool { guide != nil }
}

enum StudyError: LocalizedError {
    case invalidMove(String)
    case invalidContent(String)
    var errorDescription: String? {
        switch self {
        case .invalidMove(let move): return "棋谱包含无法识别的走法：\(move)"
        case .invalidContent(let detail): return "课程数据有问题：\(detail)"
        }
    }
}

enum StudyMode: String, Codable, CaseIterable, Identifiable {
    case demonstration, practice, test
    var id: String { rawValue }
    var title: String {
        switch self {
        case .demonstration: return "讲解演示"
        case .practice: return "引导练习"
        case .test: return "无提示检验"
        }
    }
}
