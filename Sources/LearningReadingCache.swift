import Foundation

/// Ephemeral UI projections only. Nothing here is encoded or used to award a
/// result. Keep one search result, small route/group summaries and shared arrays
/// so typing/hovering cannot accumulate a second copy of the position library.
@MainActor
final class LearningReadingCache {
    struct Query: Equatable {
        let groupID: String?
        let section: LibraryCourseSection?
        let text: String
        let family: String?
        let routeID: String?
        let status: Int
        let progressRevision: UInt64?
    }
    struct FilteredResult {
        let entries: [LibraryCourseEntry]
        var validUntil: Date = .distantFuture
    }
    struct Navigation {
        let sectionCounts: [LibraryCourseSection: Int]
        let openingFamilies: [String]
    }
    struct Curriculum {
        let lessons: [LearningLesson]
        let sources: [LearningSource]
        let recommended: [LearningLesson]
        let lessonByID: [String: LearningLesson]

        init(lessons: [LearningLesson], sources: [LearningSource], recommended: [LearningLesson]) {
            self.lessons = lessons; self.sources = sources; self.recommended = recommended
            lessonByID = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
    private struct ResumeBoardKey: Equatable {
        let line: StudyLine
        let cursor: Int
        let acceptedMove: String?
    }
    private struct Revisioned<Value> {
        let revision: UInt64
        let value: Value
    }
    private var filtered: (query: Query, value: FilteredResult, validFrom: Date)?
    private var coverage: [String: Revisioned<LearningRouteCoverage>] = [:]
    private var targets: [String: Revisioned<[StudyTarget]>] = [:]
    private var groups: [String: Revisioned<(practiced: Int, independent: Int)>] = [:]
    private var navigation: Navigation?
    private var curriculumValue: Revisioned<Curriculum>?
    private var resumeBoardValue: (key: ResumeBoardKey, position: Position?)?

    func resetCatalog() {
        filtered = nil; coverage.removeAll(keepingCapacity: true)
        targets.removeAll(keepingCapacity: true); groups.removeAll(keepingCapacity: true)
        navigation = nil
    }
    func filteredEntries(query: Query, now: Date, build: () -> FilteredResult) -> [LibraryCourseEntry] {
        if let cached = filtered, cached.query == query,
           now >= cached.validFrom, now < cached.value.validUntil { return cached.value.entries }
        let value = build()
        filtered = (query, value, now)
        return value.entries
    }
    func routeCoverage(id: String, revision: UInt64, build: () -> LearningRouteCoverage) -> LearningRouteCoverage {
        if let cached = coverage[id], cached.revision == revision { return cached.value }
        let value = build()
        if coverage.count >= 32 { coverage.removeAll(keepingCapacity: true) }
        coverage[id] = .init(revision: revision, value: value)
        return value
    }
    func routeTargets(id: String, revision: UInt64, build: () -> [StudyTarget]) -> [StudyTarget] {
        if let cached = targets[id], cached.revision == revision { return cached.value }
        let value = build()
        if targets.count >= 32 { targets.removeAll(keepingCapacity: true) }
        targets[id] = .init(revision: revision, value: value)
        return value
    }
    func groupProgress(id: String, revision: UInt64, build: () -> (practiced: Int, independent: Int)) -> (practiced: Int, independent: Int) {
        if let cached = groups[id], cached.revision == revision { return cached.value }
        let value = build()
        if groups.count >= 256 { groups.removeAll(keepingCapacity: true) }
        groups[id] = .init(revision: revision, value: value)
        return value
    }
    func catalogNavigation(build: () -> Navigation) -> Navigation {
        if let navigation { return navigation }
        let value = build(); navigation = value
        return value
    }
    /// One shared catalog per archive revision replaces sorting and de-duplicating
    /// the same lessons in every computed property of one SwiftUI redraw.
    func curriculum(revision: UInt64, build: () -> Curriculum) -> Curriculum {
        if let cached = curriculumValue, cached.revision == revision { return cached.value }
        let value = build(); curriculumValue = .init(revision: revision, value: value)
        return value
    }
    /// Home only needs one resume thumbnail. Replaying a complete game for each
    /// title, count, or hover update is unnecessary; never retain a second game tree.
    func resumePosition(line: StudyLine, cursor: Int, acceptedMove: String?) -> Position? {
        let key = ResumeBoardKey(line: line, cursor: cursor, acceptedMove: acceptedMove)
        if let cached = resumeBoardValue, cached.key == key { return cached.position }
        let value: Position?
        if let positions = try? line.positions(), positions.indices.contains(cursor) {
            let before = positions[cursor]
            value = acceptedMove.flatMap(Move.init(uci:)).flatMap { try? before.applying(move: $0) } ?? before
        } else { value = nil }
        resumeBoardValue = (key, value)
        return value
    }
}
