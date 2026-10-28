#if LEARNING_READING_BENCHMARK
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct ReadingBenchmark {
    static func time(_ action: () -> Int) -> (median: Double, p95: Double, checksum: Int) {
        var samples: [Double] = [], checksum = 0
        for _ in 0..<5 { checksum += action() }
        for _ in 0..<30 {
            let started = DispatchTime.now().uptimeNanoseconds
            checksum += action()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        }
        samples.sort()
        return (samples[15], samples[28], checksum)
    }
    static func main() throws {
        let path = CommandLine.arguments[1]
        let snapshot = try JSONDecoder().decode(GitHubLibrarySnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let catalog = try LibraryCourseCatalogAdapter.build(snapshot)
        let store = LearningStore(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
        let model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        model.libraryCatalog = catalog; model.librarySection = nil
        let archiveBefore = try store.exportData(), now = Date()
        for route in model.roadmapRoutes { _ = model.routeEntries(route) }
        func originalFilter() -> Int {
            catalog.entries(in: model.libraryGroupID, section: model.librarySection, query: model.libraryQuery).filter { entry in
                guard model.libraryFamily == nil || entry.openingFamily == model.libraryFamily else { return false }
                if let routeID = model.libraryRouteFilterID,
                   let route = model.roadmapRoutes.first(where: { $0.id == routeID }), !route.pool.includes(entry) { return false }
                let p = model.libraryProgress(entryID: entry.id)
                switch model.libraryStatusFilter {
                case 1: return p.completions == 0
                case 2: return p.nextReview.map { $0 <= Date() } ?? false
                case 3: return p.cleanTests > 0
                default: return true
                }
            }.count
        }
        func originalCoverage() -> Int {
            var result = 0
            for route in model.roadmapRoutes {
                let lookup = Dictionary(model.lessons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let targets = route.lessonIDs.flatMap { id -> [StudyTarget] in
                    guard let lesson = lookup[id] else { return [] }
                    return lesson.lines.filter { $0.checkpoints?.isEmpty != true }.map { StudyTarget(lesson: lesson, line: $0) }
                }
                let entries = model.routeEntries(route)
                let progress = entries.map { model.libraryProgress(entryID: $0.id) }
                result += targets.filter { store.progress($0.lesson.id, $0.line.id).completions > 0 }.count + targets.count + entries.count
                result += progress.filter { $0.completions > 0 }.count + progress.filter { $0.cleanTests > 0 }.count + progress.filter { $0.delayedTests > 0 }.count
            }
            return result
        }
        func cachedCoverage() -> Int {
            model.roadmapRoutes.reduce(0) { sum, route in
                let c = model.routeCoverage(route)
                return sum + c.coreCompleted + c.coreCount + c.positionCount + c.practicedPositions + c.independentPositions + c.delayedPositions
            }
        }
        let firstFilter = originalFilter(), newFilter = model.libraryFilteredEntries(now: now).count
        let firstCoverage = originalCoverage(), newCoverage = cachedCoverage()
        guard firstFilter == newFilter && firstCoverage == newCoverage else { fatalError("Projection mismatch") }
        let oldFilter = time(originalFilter), cachedFilter = time { model.libraryFilteredEntries(now: now).count }
        let oldCoverage = time(originalCoverage), newCoverageTime = time(cachedCoverage)
        print("catalog_count=\(catalog.totalCount) source_files=\(catalog.groups.count) routes=\(model.roadmapRoutes.count)")
        print("all_positions_old median_ms=\(oldFilter.median) p95_ms=\(oldFilter.p95) checksum=\(oldFilter.checksum)")
        print("all_positions_cached median_ms=\(cachedFilter.median) p95_ms=\(cachedFilter.p95) checksum=\(cachedFilter.checksum)")
        print("sixteen_routes_old median_ms=\(oldCoverage.median) p95_ms=\(oldCoverage.p95) checksum=\(oldCoverage.checksum)")
        print("sixteen_routes_cached median_ms=\(newCoverageTime.median) p95_ms=\(newCoverageTime.p95) checksum=\(newCoverageTime.checksum)")
        guard try store.exportData() == archiveBefore else { fatalError("Read path mutated learning state") }
        print("PASS equal projection checksums; read-only isolated store; 30 warm samples per path")
    }
}
#endif
