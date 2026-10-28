#if STUDY_VARIATION_CATALOG_TESTS
import Foundation

@main struct StudyVariationCatalogTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ reason: String) {
            precondition(value(), reason); checks += 1
        }
        func variation(_ id: String, anchor: Int, moves: [String]) -> StudyVariation {
            StudyVariation(id: id, title: "变化 \(id)", anchorPly: anchor, condition: "条件 \(id)",
                           explanation: "思路 \(id)", moves: moves.map { StudyMove($0, "说明 \($0)") })
        }
        var first = StudyLine(id: "first", title: "第一谱例", intent: "比较", adaptation: "变化目的",
                              moves: ["h2e2", "h9g7", "h0g2", "i9h9"].map { StudyMove($0, "原谱") })
        first.variations = [
            variation("late", anchor: 3, moves: ["b9c7"]),
            variation("horse", anchor: 1, moves: ["b9c7", "b0c2"]),
            variation("pawn", anchor: 1, moves: ["a6a5"]),
            variation("central-pawn", anchor: 1, moves: ["e6e5"]),
            variation("bad", anchor: 99, moves: ["b9c7"])
        ]
        var second = StudyLine(id: "second", title: "第二谱例", intent: "比较", adaptation: "目的",
                               moves: [StudyMove("a3a4", "原谱")])
        second.variations = [variation("horse", anchor: 0, moves: ["h0g2"])]
        let third = StudyLine(id: "missing", title: "未附变化", intent: "比较", adaptation: "目的",
                              moves: [StudyMove("a3a4", "原谱")])
        let lesson = LearningLesson(id: "catalog", title: "目录测试", stage: .opening, order: 1,
                                    summary: "范围", goal: "完整列举", principle: "不猜测", whenToAdapt: "按条件",
                                    pitfalls: [], sourceIDs: [], lines: [first, second, third])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let originalBytes = try encoder.encode(lesson)
        let catalog = StudyVariationCatalog(lesson: lesson)
        check(catalog.routes.map(\.line.id) == ["first", "second", "missing"], "Every source route retains its source order")
        check(catalog.variationCount == 6 && catalog.forkCount == 4, "Counts cover every route and every anchor, not the nearest anchor")
        check(catalog.unannotatedRouteCount == 1, "Missing annotations are explicitly counted")
        check(catalog.routes[0].forks.map(\.anchorPly) == [1, 3, 99], "Forks are chronologically grouped without discarding malformed metadata")
        check(catalog.routes[0].forks[0].entries.map(\.variation.id) == ["horse", "pawn", "central-pawn"], "All three sibling variations remain visible in source order")
        check(catalog.routes[0].variationCount == 5 && catalog.routes[1].variationCount == 1, "Per-route coverage is not narrowed to the active line")
        check(catalog.routes[2].forks.isEmpty, "A source without variations receives no invented branch")
        check(catalog.routes[1].forks[0].label == "起始局面" && catalog.routes[0].forks[0].label == "已走 1 步时", "Anchors use explicit move counts")
        let rows = catalog.routes.flatMap(\.forks).flatMap(\.entries)
        check(Set(rows.map(\.id)).count == rows.count, "The same variation ID in different source routes has independent UI identity")
        for row in rows {
            check(row.variation.condition == "条件 \(row.variation.id)" && row.variation.explanation == "思路 \(row.variation.id)", "Source conditions and plans are preserved intact")
        }
        let bytesAfterReading = try encoder.encode(lesson)
        check(bytesAfterReading == originalBytes, "Reading the catalog must never rewrite the source or its provenance")

        let parentPositions = try first.positions()
        for candidate in first.variations!.dropLast() {
            let details = try StudyVariationStep.load(parent: first, variation: candidate)
            let positions = try candidate.positions(parent: first)
            check(details.count == candidate.moves.count, "Expanded explanations cover all variation moves, never the original remainder")
            for (index, detail) in details.enumerated() {
                let move = Move(uci: candidate.moves[index].uci)!
                check(detail.id == index + 1 && detail.number == index + 1, "Step identities retain route-local order")
                check(detail.notation == positions[index].notation(for: move), "Each notation is generated at its actual legal predecessor")
                check(detail.explanation == candidate.moves[index].explanation, "Each step exposes the source explanation")
            }
            check(positions.first == parentPositions[candidate.anchorPly], "Every route starts at its true source fork")
        }
        do {
            _ = try StudyVariationStep.load(parent: first, variation: first.variations!.last!)
            preconditionFailure("Invalid metadata must fail before showing playable step nodes")
        } catch { checks += 1 }
        do {
            _ = try StudyVariationStep.load(parent: first, variation: variation("illegal", anchor: 1, moves: ["a9a0"]))
            preconditionFailure("Illegal moves must not produce a guessed continuation")
        } catch { checks += 1 }

        var malformed = second
        malformed.startingFEN = "not a position"
        malformed.variations = [second.variations![0], second.variations![0]]
        let metadataOnly = LearningLesson(id: "metadata-only", title: "元数据", stage: .opening, order: 1,
                                         summary: "范围", goal: "列举", principle: "保持原文", whenToAdapt: "按条件",
                                         pitfalls: [], sourceIDs: [], lines: [malformed])
        let malformedCatalog = StudyVariationCatalog(lesson: metadataOnly)
        check(malformedCatalog.variationCount == 2, "Catalog creation reads metadata only and never eagerly replays even a malformed FEN")
        check(Set(malformedCatalog.routes[0].forks[0].entries.map(\.id)).count == 2, "Malformed duplicate IDs are not silently erased")
        do {
            _ = try StudyVariationStep.load(parent: malformed, variation: malformed.variations![0])
            preconditionFailure("A malformed source is rejected when actual playable steps are requested")
        } catch { checks += 1 }
        print("PASS \(checks) complete variation catalog / all anchors / source plans / lazy legal expansion checks")
    }
}
#endif
