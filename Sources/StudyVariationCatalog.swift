import Foundation

/// A metadata-only index. Opening a catalogue must not replay every course or
/// run the engine. Legality is checked only when a concrete route is opened.
struct StudyVariationCatalog {
    struct Entry: Identifiable {
        let id: String
        let variation: StudyVariation
    }

    struct Fork: Identifiable {
        var id: Int { anchorPly }
        let anchorPly: Int
        let entries: [Entry]
        var label: String {
            anchorPly == 0 ? "起始局面" : "已走 \(anchorPly) 步时"
        }
    }

    struct Route: Identifiable {
        let id: String
        let line: StudyLine
        let forks: [Fork]
        var variationCount: Int { forks.reduce(0) { $0 + $1.entries.count } }
    }

    let routes: [Route]
    let variationCount: Int
    let forkCount: Int
    let unannotatedRouteCount: Int

    init(lesson: LearningLesson) {
        routes = lesson.lines.enumerated().map { lineIndex, line in
            let entries = (line.variations ?? []).enumerated().map { variationIndex, variation in
                // Use source order as well as the source ID: a malformed
                // duplicate must stay visible rather than silently disappear.
                Entry(id: "\(lesson.id)/\(lineIndex)/\(variationIndex)/\(variation.id)", variation: variation)
            }
            let grouped = Dictionary(grouping: entries) { $0.variation.anchorPly }
            let forks = grouped.keys.sorted().map { Fork(anchorPly: $0, entries: grouped[$0] ?? []) }
            return Route(id: "\(lesson.id)/\(lineIndex)/\(line.id)", line: line, forks: forks)
        }
        variationCount = routes.reduce(0) { $0 + $1.variationCount }
        forkCount = routes.reduce(0) { $0 + $1.forks.count }
        unannotatedRouteCount = routes.filter { $0.forks.isEmpty }.count
    }
}

/// Expanded only after an explicit request for step-by-step explanations.
/// It never joins a variation to an unrelated remainder of the original game.
struct StudyVariationStep: Identifiable, Equatable {
    var id: Int { number }
    let number: Int
    let notation: String
    let explanation: String

    static func load(parent: StudyLine, variation: StudyVariation) throws -> [Self] {
        let positions = try variation.positions(parent: parent)
        return try variation.moves.enumerated().map { index, item in
            guard let move = Move(uci: item.uci) else { throw StudyError.invalidMove(item.uci) }
            return Self(number: index + 1, notation: positions[index].notation(for: move), explanation: item.explanation)
        }
    }
}
