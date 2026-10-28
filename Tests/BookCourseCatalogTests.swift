import Foundation

#if BOOK_COURSE_TESTS
@main @MainActor
struct BookCourseCatalogTests {
    static var checks = 0

    static func main() throws {
        let record = fixtureRecord(id: "example")
        let text = fixtureRecord(id: "reading", nodes: [node(0, nil, [], nil, "本节阅读材料。")])
        let book = fixtureDocument(records: [record, text])
        let catalog = BookCourseCatalog.build(document: book)
        check(catalog == BookCourseCatalog.build(document: book), "Index and identifiers must be deterministic")
        check(catalog.units.count == 2 && catalog.stats.readableRecordCount == 2, "Text remains in the index")
        check(catalog.stats.practiceRecordCount == 1 && catalog.stats.readingOnlyRecordCount == 1,
              "Reading must not become an independent exercise")
        let unit = catalog.unit(recordID: "example")!
        check(unit.tier == .sourceGuided && unit.checkpoints.count == 2,
              "Generic source annotations are guided, not edited teaching")
        check(unit.excludedNodeIDs == [4, 5], "Illegal move and its descendant are both removed from entry points")
        check(record.nodes.count == 6 && record.nodes[4].comment == "错误分支原注仍可读。",
              "Indexing must not mutate imported branches or commentary")
        check(catalog.unit(recordID: "reading")?.nextUnitID == unit.id,
              "A section introduction can lead to its first practice example")
        check(unit.checkpoints.first?.annotationNodeID == 1 && unit.checkpoints.first?.anchorNodeID == 0,
              "A concrete first-move annotation takes priority over a duplicate root overview")
        check(unit.checkpoints.contains { $0.anchorNodeID == 0 && $0.annotationNodeID == 1 && $0.referenceNodeID == 1 },
              "A move annotation belongs to the before-move decision")
        check(unit.checkpoints.contains { $0.comparison?.nodeIDs == [1, 3] },
              "Comparison must name actual legal siblings at the same branch")
        try validate(catalog, against: book)

        var siblingNodes = record.nodes
        siblingNodes[3] = node(3, 0, [], "c3c4", "另一着也有原注，不应把同一走前局面重复算题。")
        let siblings = BookCourseCatalog.build(document: fixtureDocument(records: [fixtureRecord(id: "siblings", nodes: siblingNodes)]))
        check(siblings.units[0].checkpoints.filter { $0.anchorNodeID == 0 }.count == 1,
              "Annotated siblings share one decision entry; alternate moves belong in comparison")
        check(siblings.units[0].checkpoints.first?.comparison?.nodeIDs == [1, 3],
              "Deduplicating the decision keeps the actual alternative available")

        var correctedNodes = record.nodes
        correctedNodes[3] = node(3, 0, [], "c3c4", "原谱被录错了——测试标记")
        let flagged = fixtureDocument(records: [fixtureRecord(id: "erratum", nodes: correctedNodes)])
        let flaggedUnit = BookCourseCatalog.build(document: flagged).units[0]
        check(flaggedUnit.excludedNodeIDs == [3, 4, 5], "Explicit transcription warning is not taught as reliable material")
        check(flaggedUnit.checkpoints.allSatisfy { $0.comparison == nil }, "Invalid sibling never enters branch comparison")

        let invalid = fixtureRecord(id: "invalid-position", board: Array(repeating: 0, count: 90))
        let invalidIndex = BookCourseCatalog.build(document: fixtureDocument(records: [invalid]))
        check(invalidIndex.stats.practiceRecordCount == 0 && invalidIndex.units[0].tier == .readingOnly,
              "An illegal starting diagram remains readable but cannot launch practice")
        check(invalidIndex.units[0].excludedNodeIDs.count == invalid.nodes.count,
              "All descendants of an invalid starting diagram are excluded")

        let changedHash = fixtureDocument(records: [record, text], hash: "another-file-version")
        let changed = BookCourseCatalog.build(document: changedHash)
        check(Set(catalog.units.map(\.id)).isDisjoint(with: changed.units.map(\.id)),
              "Identifiers bind to source bytes, preventing progress leakage across editions")
        check(catalog.firstRoundUnitIDs.isEmpty, "A lookalike title cannot inherit private-edition authored lessons")
        let roundTrip = try JSONDecoder().decode(BookCourseCatalog.self, from: JSONEncoder().encode(catalog))
        check(roundTrip == catalog, "The Foundation domain is Codable without model or UI state")

        let another = fixtureRecord(id: "another-example")
        let related = BookCourseCatalog.build(document: fixtureDocument(records: [record, another]))
        check(related.units[0].nextUnitID == related.units[1].id, "Same-section next example stays connected")
        check(related.units[0].relatedUnits.allSatisfy { !$0.isVerifiedTransfer },
              "Section membership alone is not a verified same-goal transfer exercise")
        check(Set(related.units.map(\.id)).count == 2, "Different records have separate stable identities")

        let privatePath = ProcessInfo.processInfo.environment["XQ_BOOK_COURSE_TEST_FILE"]
            ?? CommandLine.arguments.dropFirst().first
        if let privatePath {
            let url = URL(fileURLWithPath: privatePath)
            let bytesBefore = try Data(contentsOf: url)
            let imported = try CBLParser.parse(data: bytesBefore, sourceFilename: url.lastPathComponent)
            let started = Date()
            let full = BookCourseCatalog.build(document: imported)
            let elapsed = Date().timeIntervalSince(started)
            try validate(full, against: imported)
            check(full == BookCourseCatalog.build(document: imported), "Full-book index remains stable on rebuild")
            check(try Data(contentsOf: url) == bytesBefore, "Private original is byte-identical after catalog validation")
            check(full.stats.readableRecordCount == imported.records.count, "Every imported entry remains readable")
            check(full.stats.editedRecordCount == 0 && full.stats.editedCheckpointCount == 0 && full.firstRoundUnitIDs.isEmpty,
                  "Public catalog never injects private-edition authored content")
            print("FULL BOOK: \(full.stats.readableRecordCount) readable, \(full.stats.practiceRecordCount) practice, \(full.stats.editedRecordCount) edited units / \(full.stats.editedCheckpointCount) edited points, \(full.stats.checkpointCount) unique decisions, \(full.stats.comparisonCount) branch comparisons, \(full.stats.excludedNodeCount) excluded nodes; build \(String(format: "%.3f", elapsed)) s")
        } else {
            print("Private source not supplied: synthetic coverage only (set XQ_BOOK_COURSE_TEST_FILE for full-book audit).")
        }
        print("PASS \(checks) book course checks")
    }

    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
    }

    static func validate(_ catalog: BookCourseCatalog, against document: BookDocument) throws {
        let recordByID = Dictionary(uniqueKeysWithValues: document.records.map { ($0.id, $0) })
        check(Set(catalog.units.map(\.id)).count == catalog.units.count, "No duplicate unit identifiers")
        let all = catalog.units.flatMap(\.checkpoints)
        check(Set(all.map(\.id)).count == all.count, "No duplicate checkpoint identifiers")
        for unit in catalog.units {
            let record = recordByID[unit.recordID]!
            var positions = [record.rootNodeID: record.rawPosition]
            for node in record.nodes where node.parentID != nil {
                guard let parent = node.parentID, let before = positions[parent],
                      let move = node.uci.flatMap(Move.init(uci:)),
                      let after = try? before.applying(move: move) else { continue }
                positions[node.id] = after
            }
            check(unit.sourceHash == document.sourceSHA256, "Unit keeps exact source identity")
            check(Set(unit.checkpoints.map(\.anchorNodeID)).count == unit.checkpoints.count,
                  "One record and one before-move anchor identify exactly one decision, including edited units")
            check(unit.nextUnitID == nil || catalog.unit(id: unit.nextUnitID!) != nil, "Continuation target exists")
            check(unit.relatedUnits.allSatisfy { $0.unitID != unit.id && catalog.unit(id: $0.unitID) != nil },
                  "Related records exist and never point to the same unit")
            for checkpoint in unit.checkpoints {
                check(catalog.checkpoint(id: checkpoint.id) == checkpoint, "Stable checkpoint lookup resolves exact metadata")
                check(record.nodes.indices.contains(checkpoint.annotationNodeID), "Referenced commentary node exists")
                check(!record.nodes[checkpoint.annotationNodeID].comment.isEmpty, "No invented source annotation")
                check(!unit.excludedNodeIDs.contains(checkpoint.anchorNodeID)
                      && !unit.excludedNodeIDs.contains(checkpoint.annotationNodeID)
                      && !unit.excludedNodeIDs.contains(checkpoint.referenceNodeID), "Quarantined nodes cannot teach")
                let before = positions[checkpoint.anchorNodeID]!
                try before.validate()
                check(record.nodes[checkpoint.referenceNodeID].parentID == checkpoint.anchorNodeID,
                      "Reference is a direct child of the before-move position")
                let move = Move(uci: record.nodes[checkpoint.referenceNodeID].uci!)!
                check((try? before.applying(move: move)) != nil, "Every reference move is actually legal")
                check(!checkpoint.prompt.isEmpty && !checkpoint.explanation.isEmpty && !checkpoint.focus.isEmpty,
                      "Every entry states a question, evidence boundary and focus")
                if let comparison = checkpoint.comparison {
                    check(comparison.firstNodeID != comparison.secondNodeID, "Comparison cannot replay the same branch twice")
                    let branchPosition = positions[comparison.branchNodeID]!
                    for id in comparison.nodeIDs {
                        check(record.nodes[id].parentID == comparison.branchNodeID && !unit.excludedNodeIDs.contains(id),
                              "Both comparison lines originate at one valid source branch")
                        check((try? branchPosition.applying(move: Move(uci: record.nodes[id].uci!)!)) != nil,
                              "Comparison entry moves are legal")
                    }
                }
            }
        }
        for (index, section) in catalog.sections.enumerated() {
            check(section.order == index, "Section order is explicit and stable")
            check(section.previousSectionID == (index == 0 ? nil : catalog.sections[index - 1].id), "Previous section is connected")
            check(section.nextSectionID == (index + 1 == catalog.sections.count ? nil : catalog.sections[index + 1].id), "Next section is connected")
            check(!section.goal.isEmpty && !section.connection.isEmpty, "Every section has a learning purpose and continuity")
            check(section.unitIDs.allSatisfy { catalog.unit(id: $0)?.sectionID == section.id }, "Directory and curriculum refer to the same records")
        }
    }

    static func node(_ id: Int, _ parent: Int?, _ children: [Int], _ uci: String?, _ comment: String) -> BookNode {
        .init(id: id, parentID: parent, childIDs: children, uci: uci, comment: comment,
              sourceOffset: 100 + id * 20, flags: comment.isEmpty ? 0 : 4, reservedByte: 0)
    }
    static func fixtureRecord(id: String, nodes: [BookNode]? = nil, board: [UInt8]? = nil) -> BookRecord {
        let code: [PieceKind: UInt8] = [.rook: 1, .horse: 2, .elephant: 3, .advisor: 4, .king: 5, .cannon: 6, .pawn: 7]
        let initial = Position.initial.board.map { piece -> UInt8 in
            guard let piece else { return 0 }; return (piece.side == .red ? 16 : 32) + code[piece.kind]!
        }
        return .init(id: id, title: "4.1.01例 \(id)", displayTitle: "例 \(id)", chapterNumber: 4,
            sectionID: "chapter-4-section-1", sectionTitle: "中炮巡河炮对屏风马",
            startingFEN: Position.initial.fen, initialBoard: board ?? initial, sideToMove: "w",
            nodes: nodes ?? [node(0, nil, [1, 3, 4], nil, "本例原注：先观察双方出子。"),
                node(1, 0, [2], "a3a4", "红方进兵。"), node(2, 1, [], "a6a5", "黑方回应。"),
                node(3, 0, [], "c3c4", ""), node(4, 0, [5], "a3a5", "错误分支原注仍可读。"),
                node(5, 4, [], "a6a5", "非法分支的后续。")],
            rootNodeID: 0, isSupplement: false, sourceOffset: 0, sourceByteCount: 1_000, issues: [])
    }
    static func fixtureDocument(records: [BookRecord], hash: String = "fixture-source-hash") -> BookDocument {
        .init(id: "fixture", title: "弈林新编（测试合成材料）", sourceFilename: "fixture.cbl",
              sourceSHA256: hash, sourceByteCount: 2_000, records: records,
              chapters: [.init(id: "chapter-4", number: 4, title: "布局研究",
                sections: [.init(id: "chapter-4-section-1", title: "中炮巡河炮对屏风马", recordIDs: records.map(\.id))])], issues: [])
    }
}
#endif
