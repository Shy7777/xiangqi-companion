import Foundation

/// On-demand only. No files, URLs, stores or learning counters are touched here.
/// The injected evaluator is normally the learning model's private local coach.
@MainActor enum LibraryLessonBuilder {
    private static let budget = 700
    private static let maximumInputPV = 256

    static func build(entry: LibraryCourseEntry, groupID: String?, commit: String,
                      evaluate: (Position, Int) async throws -> [EngineLine]) async throws -> LibraryGeneratedStudy {
        try Task.checkCancellation()
        let initial = try Position(fen: entry.fen)
        guard entry.id == LibraryCourseEntry.identifier(fen: initial.fen),
              LibraryCourseMembership.isValidCommit(commit), let membership = entry.membership(in: groupID),
              PWADataParser.isDataPath(membership.groupID), membership.groupID.utf8.count <= 1_024,
              (1...PWADataParser.maximumItems).contains(membership.sourceIndex),
              membership.section == LibraryCourseSection.section(for: membership.groupID),
              let sourceURL = membership.sourceURL(commit: commit),
              !membership.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !membership.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudyError.invalidContent("局面或选定来源与课程目录不匹配，未生成课程。")
        }
        guard !initial.legalMoves().isEmpty else { throw StudyError.invalidContent("此局面已无合法着，不能生成需要你作答的课程。") }
        let rows = try await evaluate(initial, budget)
        try Task.checkCancellation()
        let first = try checkedRows(rows, requireTop: true)
        guard let top = first.first(where: { $0.rank == 1 }) else { throw StudyError.invalidContent("引擎没有返回首选参考线。") }
        let main = try expand(top.pv, from: initial, limit: 10)
        let mainMoves = main.moves
        var rootAlternatives: [StudyVariation] = []
        var rootHeads = Set<String>()
        for row in first where row.rank != 1 && row.pv.first != top.pv.first {
            guard let head = row.pv.first, rootHeads.insert(head).inserted else { continue }
            let expansion = try expand(row.pv, from: initial, limit: 8)
            rootAlternatives.append(variation(expansion, anchor: 0, position: initial, role: "你的其他选择"))
        }

        var replyAlternatives: [StudyVariation] = []
        var replyHeads = Set<String>()
        var searchMilliseconds = budget
        // With only one main move there is no valid anchor 1 in StudyLine's
        // contract. Never invent a parent move just to attach a variation.
        if mainMoves.count > 1 {
            let afterFirst = main.positions[1]
            if !afterFirst.legalMoves().isEmpty {
                searchMilliseconds += budget
                let replies = try await evaluate(afterFirst, budget)
                try Task.checkCancellation()
                for row in try checkedRows(replies, requireTop: false) where row.pv.first != mainMoves[1].uci {
                    guard let head = row.pv.first, replyHeads.insert(head).inserted else { continue }
                    let expansion = try expand(row.pv, from: afterFirst, limit: 8)
                    replyAlternatives.append(variation(expansion, anchor: 1, position: afterFirst, role: "对手的不同应招"))
                    if replyAlternatives.count == 2 { break }
                }
            }
        }
        // Prefer actual opponent branching, while retaining one initial choice.
        let variations: [StudyVariation]
        if replyAlternatives.isEmpty { variations = Array(rootAlternatives.prefix(3)) }
        else { variations = Array(rootAlternatives.prefix(1)) + Array(replyAlternatives.prefix(2)) }
        let sourceTitle = safeText(membership.title, maximum: 256)
        let category = safeText(membership.category, maximum: 256)
        let notice = "原始数据只提供当前 FEN 和题名标签，无前序走法、解序或评注。以下是本机限时搜索的引擎参考线，不是原谱或权威讲解。"
        let ending = main.description
        let source = LearningSource(id: entry.lessonID + "-source", title: "局面出处：" + sourceTitle,
                                    url: sourceURL.absoluteString,
                                    note: "原文件第 \(membership.sourceIndex) 条（1-based）。" + notice)
        var line = StudyLine(id: LibraryGeneratedStudy.lineID, title: "引擎参考线", intent: "从这个现成局面开始，由\(initial.sideToMove.label)独立判断后续选择。",
                             adaptation: ending + "合理走法不必等于参考线；实际尝试仍由教练重新分析。",
                             startingFEN: initial.fen, studentSide: initial.sideToMove, moves: mainMoves)
        line.checkpoints = try mainMoves.indices.filter { main.positions[$0].sideToMove == initial.sideToMove }.enumerated().map { ordinal, ply in
            let reading = try PositionLearningInsights.read(main.positions[ply])
            return StudyCheckpoint(ply: ply, title: "第 \(ordinal + 1) 次局面判断",
                                   prompt: reading.isInCheck ? "你正在被将军。请先选择一着合法应对。" : "请根据当前局面，独立选择你准备走的一着。",
                                   focus: reading.objective + focus(for: membership.section),
                                   explanation: mainMoves[ply].explanation + "这是本轮引擎的参考选择，不是唯一正确着法的证明。")
        }
        line.variations = variations.isEmpty ? nil : variations
        var lesson = LearningLesson(id: entry.lessonID, title: sourceTitle + " · 引擎参考", stage: stage(for: membership.section), order: 0,
                                    summary: "从局面库的这个起点练习判断，不要求背诵原题名。",
                                    goal: goal(for: membership.section),
                                    principle: "引擎参考线用于比较，不把原始题名、单个建议或本轮搜索当作唯一答案。",
                                    whenToAdapt: ending + "每个变式从标明的分歧点独立展开，不拼接回原线。",
                                    pitfalls: ["不要把课程终点当作对局已经结束。", "原文件的必胜、和棋等名称未经本轮证明。", "看过提示或参考线后，要另择时间进行无提示检验。"],
                                    sourceIDs: [source.id], lines: [line])
        lesson.estimatedMinutes = 5
        lesson.tags = ["局面库", "引擎参考线", category]
        lesson.guide = StudyGuide(level: "局面练习，不代表等级或 Elo", reading: notice + " " + ending,
                                  questions: ["对手现在威胁什么？", "所选走法合法吗，是否漏掉将军或吃子？", "对手换一种应招后，你的判断还成立吗？"],
                                  workflow: ["从当前局面独立走一步。", "核对有限搜索反馈与棋盘事实。", "必要时回到分歧点比较其他选择。", "之后再做无提示检验。"],
                                  takeaway: "依据局面作判断；本轮参考线不能替代独立计算，也不补写缺失的原谱。")
        let result = LibraryGeneratedStudy(entryID: entry.id, groupID: membership.groupID, pwaCommit: commit,
                                           source: source, lesson: lesson, created: Date(), searchMilliseconds: searchMilliseconds, depth: top.depth)
        try Task.checkCancellation()
        try result.validate()
        return result
    }

    private struct Expansion {
        let moves: [StudyMove]
        let positions: [Position]
        let description: String
    }

    private static func checkedRows(_ rows: [EngineLine], requireTop: Bool) throws -> [EngineLine] {
        guard rows.count <= 3, Set(rows.map(\.rank)).count == rows.count,
              rows.allSatisfy({ (1...3).contains($0.rank) && (1...512).contains($0.depth) && !$0.pv.isEmpty && $0.pv.count <= maximumInputPV }),
              !requireTop || rows.contains(where: { $0.rank == 1 }) else {
            throw StudyError.invalidContent("引擎没有提供有效的有限参考线，未生成课程。")
        }
        return rows.sorted { $0.rank < $1.rank }
    }

    private static func expand(_ pv: [String], from initial: Position, limit: Int) throws -> Expansion {
        guard !pv.isEmpty, pv.count <= maximumInputPV else { throw StudyError.invalidContent("引擎参考线为空或超出长度上限。") }
        var position = initial
        var moves: [StudyMove] = [], positions = [initial]
        for (index, raw) in pv.enumerated() {
            try Task.checkCancellation()
            guard let move = Move(uci: raw), move.uci == raw else { throw StudyError.invalidContent("引擎参考线第 \(index + 1) 半步格式不合法，未生成课程。") }
            let next: Position
            do { next = try position.applying(move: move) }
            catch { throw StudyError.invalidContent("引擎参考线第 \(index + 1) 半步不合法，未生成课程；不会隐藏坏尾部。") }
            if index < limit {
                let reading = try PositionLearningInsights.read(position)
                let explanation = try PositionLearningInsights.explain(move: move, in: position)
                moves.append(StudyMove(raw, explanation.expandedText, hint: reading.shortHint))
                positions.append(next)
            }
            position = next
        }
        let end = positions.last!
        let description: String
        if pv.count > limit { description = "本轮引擎参考线仅展示前 \(limit) 半步，长度已截断；这不是完整对局。" }
        else if end.legalMoves().isEmpty { description = "本段参考线末端对方已无合法着；这是棋规可核对的局面，不是原书解序。" }
        else { description = "本轮仅取得 \(moves.count) 半步引擎参考，末端仍可继续行棋；后续需要重新分析，不表示已经获胜。" }
        return Expansion(moves: moves, positions: positions, description: description)
    }

    private static func variation(_ value: Expansion, anchor: Int, position: Position, role: String) -> StudyVariation {
        let move = Move(uci: value.moves[0].uci)!
        return StudyVariation(id: "engine-\(anchor)-" + move.uci, title: role + " · " + position.notation(for: move), anchorPly: anchor,
                              condition: "在第 \(anchor) 半步后的局面，\(position.sideToMove.label)若改走 " + move.uci + "。",
                              explanation: "这是对该分歧局面实际搜索得到的引擎参考线，非必然应招。" + value.description,
                              moves: value.moves)
    }

    private static func safeText(_ value: String, maximum: Int) -> String {
        String(value.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximum))
    }
    private static func stage(for section: LibraryCourseSection) -> LearningStage {
        switch section {
        case .opening: return .opening
        case .checkmates, .classics: return .tactics
        case .endgames, .patterns: return .endgame
        case .other: return .strategy
        }
    }

    private static func focus(for section: LibraryCourseSection) -> String {
        switch section {
        case .opening: return "检查车马炮是否能活动、将帅是否安全，以及对手眼前的威胁。"
        case .checkmates: return "逐一检查将军着法、对方合法应将和逃路；没有算清前不假定杀棋。"
        case .endgames, .patterns: return "先核对子力与将帅安全，再比较攻守选择；不按原题名预设胜和。"
        case .classics: return "依据实际棋面计算将军、吃子和对方应招，不按古谱题名猜结论。"
        case .other: return "先看对手威胁，核对将军、吃子与合法活动的选择。"
        }
    }

    private static func goal(for section: LibraryCourseSection) -> String {
        switch section {
        case .opening: return "从当前布局局面判断子力活动与将帅安全，不依赖开局名称背答案。"
        case .checkmates: return "独立检查将军与逃路，再用实际应招核对自己的计算。"
        case .endgames, .patterns: return "根据当前子力与攻守条件独立选择，不把上游胜和题名当答案。"
        case .classics: return "从古谱现成局面独立计算应招，而不是补写缺失的原著评注。"
        case .other: return "先独立作答，再核对对手应招和自己漏看的棋盘事实。"
        }
    }
}
