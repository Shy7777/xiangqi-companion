import Foundation
import CryptoKit

struct LibraryGeneratedStudy: Codable, Equatable {
    static let lineID = "engine-study-v1"
    static let maximumEncodedBytes = 200 * 1_024
    var version = 1
    let entryID: String
    let groupID: String
    let pwaCommit: String
    let source: LearningSource
    let lesson: LearningLesson
    let created: Date
    /// Sum of requested local search budgets, not wall time or a strength rating.
    let searchMilliseconds: Int
    /// Initial-position Top1 search depth; later replies may have another depth.
    let depth: Int

    func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw StudyError.invalidContent(message) }
        }
        try require(version == 1 && entryID.utf8.count == 64
                    && entryID.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }, "局面课程版本或编号无效。")
        try require(LibraryCourseMembership.isValidCommit(pwaCommit) && PWADataParser.isDataPath(groupID)
                    && groupID.utf8.count <= 1_024, "局面课程来源版本或路径无效。")
        let expectedURL = URL(string: "https://github.com/dffge552/xiangqi-pwa-offline/blob/\(pwaCommit)/")!.appendingPathComponent(groupID).absoluteString
        let expectedLessonID = "library-" + entryID
        try require(lesson.id == expectedLessonID && source.id == expectedLessonID + "-source"
                    && lesson.sourceIDs == [source.id] && source.url == expectedURL,
                    "局面课程编号、来源和仓库路径不匹配。")
        try require(created.timeIntervalSince1970.isFinite && [700, 1_400].contains(searchMilliseconds)
                    && (1...512).contains(depth), "局面课程搜索或时间信息无效。")
        try require(lesson.lines.count == 1 && lesson.lines[0].id == Self.lineID
                    && lesson.prerequisites.isEmpty && (1...30).contains(lesson.estimatedMinutes), "局面课程必须保留唯一固定学习线路。")
        let line = lesson.lines[0]
        try require((1...10).contains(line.moves.count) && line.game == nil && (line.variations?.count ?? 0) <= 3,
                    "引擎参考线最多 10 半步、3 条变式，不能标成完整实战。")
        let initial = try Position(fen: line.startingFEN)
        try require(initial.fen == line.startingFEN && LibraryCourseEntry.identifier(fen: initial.fen) == entryID
                    && initial.sideToMove == line.studentSide, "起始局面与课程编号或学生行棋方不匹配。")
        let positions = try line.positions()
        let expectedPlies = line.moves.indices.filter { positions[$0].sideToMove == line.studentSide }
        try require(line.checkpoints?.map(\.ply) == expectedPlies && expectedPlies.first == 0,
                    "每个学生回合都需要判断点，且必须包含起始局面。")
        try require(lesson.title.contains("引擎参考") && line.title.contains("引擎参考")
                    && source.note.contains("无前序") && source.note.contains("引擎")
                    && lesson.guide?.reading.contains("不是原谱") == true,
                    "缺少引擎参考线及原始来源范围说明。")
        var strings = [source.title, source.note, lesson.title, lesson.summary, lesson.goal, lesson.principle,
                       lesson.whenToAdapt, line.title, line.intent, line.adaptation] + lesson.pitfalls + lesson.tags
        try require(lesson.pitfalls.count <= 12 && lesson.tags.count <= 12, "局面课程标签或提示过多。")
        if let guide = lesson.guide {
            try require(guide.questions.count <= 12 && guide.workflow.count <= 12, "引擎课程导读过长。")
            strings += [guide.level, guide.reading, guide.takeaway] + guide.questions + guide.workflow
        }
        strings += line.moves.flatMap { [$0.uci, $0.explanation, $0.hint] }
        strings += (line.checkpoints ?? []).flatMap { [$0.title, $0.prompt, $0.focus, $0.explanation] }
        var alternateHeads = Set<String>()
        for variation in line.variations ?? [] {
            try require([0, 1].contains(variation.anchorPly) && variation.anchorPly < line.moves.count
                        && (1...8).contains(variation.moves.count), "局面变式起点或长度无效。")
            try require(variation.moves[0].uci != line.moves[variation.anchorPly].uci
                        && alternateHeads.insert("\(variation.anchorPly):\(variation.moves[0].uci)").inserted,
                        "变式必须是不同于参考线的独立首着，不能重复充数。")
            strings += [variation.id, variation.title, variation.condition, variation.explanation]
                + variation.moves.flatMap { [$0.uci, $0.explanation, $0.hint] }
        }
        try require(strings.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 8_192
                    && !$0.unicodeScalars.contains(where: { $0.value == 0 }) }, "局面课程文本为空或超过容量。")
        let pack = StudyPack(title: "局面库引擎参考", sources: [source], lessons: [lesson])
        try pack.validate()
        try require(try JSONEncoder().encode(self).count <= Self.maximumEncodedBytes, "单个局面课程超过 200 KiB。")
    }
}
