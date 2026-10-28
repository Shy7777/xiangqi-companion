import Foundation

enum LearningRoutePhase: String, CaseIterable, Identifiable {
    case opening, middlegame, endgame, practice
    var id: String { rawValue }
    var title: String {
        switch self { case .opening: return "前期"; case .middlegame: return "中期"; case .endgame: return "后期"; case .practice: return "实战迁移" }
    }
}
enum LearningMaterialFocus { case any, pawnOnly, rookPawn, minorPieces }
struct LearningRoutePool {
    let sections: [LibraryCourseSection]
    var sourcePaths: [String] = []
    var openingFamilies: [String] = []
    var material: LearningMaterialFocus = .any

    func includes(_ entry: LibraryCourseEntry) -> Bool {
        guard entry.memberships.contains(where: { sections.contains($0.section) && (sourcePaths.isEmpty || sourcePaths.contains($0.groupID)) }),
              openingFamilies.isEmpty || entry.openingFamily.map(openingFamilies.contains) == true else { return false }
        switch material {
        case .any: return true
        case .pawnOnly:
            let shape = LibraryPositionShape(fen: entry.fen)
            return shape.rooks == 0 && shape.horses == 0 && shape.cannons == 0 && shape.pawns > 0
        case .rookPawn:
            let shape = LibraryPositionShape(fen: entry.fen)
            return shape.rooks > 0 && shape.pawns > 0 && shape.horses == 0 && shape.cannons == 0
        case .minorPieces:
            let shape = LibraryPositionShape(fen: entry.fen)
            return shape.rooks == 0 && shape.horses + shape.cannons > 0
        }
    }
}
struct LearningRoute: Identifiable {
    let id: String
    let title: String
    let phase: LearningRoutePhase
    let goal: String
    let principles: [String]
    let pitfalls: [String]
    let adaptation: String
    let lessonIDs: [String]
    let pool: LearningRoutePool
    let sourceIDs: [String]
}
struct LearningRouteCoverage {
    let coreCompleted: Int
    let coreCount: Int
    let positionCount: Int
    let practicedPositions: Int
    let independentPositions: Int
    let delayedPositions: Int
}
/// Cheap structural indexing, not a rules engine, difficulty estimate or answer.
struct LibraryPositionShape {
    let counts: [Character: Int]
    init(fen: String) {
        var result: [Character: Int] = [:]
        for character in fen.split(separator: " ").first ?? "" where character.isLetter { result[character, default: 0] += 1 }
        counts = result
    }
    func count(_ names: String) -> Int { names.reduce(0) { $0 + counts[$1, default: 0] } }
    var rooks: Int { count("Rr") }
    var horses: Int { count("NnHh") }
    var cannons: Int { count("Cc") }
    var pawns: Int { count("Pp") }
    func distance(to other: Self) -> Int {
        Set(counts.keys).union(other.counts.keys).reduce(0) { $0 + abs(counts[$1, default: 0] - other.counts[$1, default: 0]) }
    }
}

enum LearningCourseDisplay { case roadmap, positions, authored }

/// Bounded identifiers only: no second copy of positions, examples or scores.
struct LearningPracticeItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case library, lesson, review }
    let kind: Kind
    let targetID: String
    var lineID: String? = nil
    let title: String
    let reason: String
    let mode: StudyMode
    var id: String { kind.rawValue + ":" + targetID + ":" + (lineID ?? "") }
}
struct LearningPracticePlan: Codable, Equatable {
    let id: UUID
    let created: Date
    let routeID: String?
    let title: String
    let reason: String
    let items: [LearningPracticeItem]
    var cursor = 0
    var completedIndices: Set<Int> = []
    var skippedIndices: Set<Int> = []
    var activeRunID: UUID? = nil
    var isFinished: Bool { completedIndices.union(skippedIndices).count == items.count }
    var currentItem: LearningPracticeItem? { items.indices.contains(cursor) ? items[cursor] : nil }
    func validate() throws {
        func bounded(_ text: String, _ limit: Int) -> Bool { !text.isEmpty && text.utf8.count <= limit && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
        guard (1...8).contains(items.count), Set(items.map(\.id)).count == items.count,
              (0..<items.count).contains(cursor), created.timeIntervalSince1970.isFinite,
              routeID.map({ bounded($0, 128) }) ?? true, bounded(title, 512), bounded(reason, 1024),
              completedIndices.isDisjoint(with: skippedIndices),
              completedIndices.union(skippedIndices).allSatisfy({ items.indices.contains($0) && $0 <= cursor }),
              Set(0..<cursor).isSubset(of: completedIndices.union(skippedIndices)) else {
            throw StudyError.invalidContent("训练组的编号、位置或完成状态无效。")
        }
        for item in items {
            guard bounded(item.targetID, 200), !item.targetID.contains("/"), bounded(item.title, 512), bounded(item.reason, 1024) else {
                throw StudyError.invalidContent("训练项目不完整或过长。")
            }
            switch item.kind {
            case .library:
                guard item.targetID.utf8.count == 64, item.targetID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }), item.lineID == nil else {
                    throw StudyError.invalidContent("训练局面编号无效。")
                }
            case .lesson:
                guard let line = item.lineID, bounded(line, 200), !line.contains("/"), !item.targetID.hasPrefix("library-") else {
                    throw StudyError.invalidContent("训练精讲分支无效。")
                }
            case .review:
                guard UUID(uuidString: item.targetID) != nil, item.lineID == nil else { throw StudyError.invalidContent("训练错题编号无效。") }
            }
        }
    }
}

struct LearningJourneyState: Codable, Equatable {
    var selectedRouteID: String?
    var plan: LearningPracticePlan?
    func validate() throws {
        if let selectedRouteID, selectedRouteID.isEmpty || selectedRouteID.utf8.count > 128 || selectedRouteID.contains("/") {
            throw StudyError.invalidContent("学习路线编号无效。")
        }
        try plan?.validate()
    }
}

struct StudyCompletionSummary {
    let title: String
    let detail: String
    let hints: Int
    let errors: Int
    let independent: Bool
    let delayed: Bool
    let nextReview: Date?
}
