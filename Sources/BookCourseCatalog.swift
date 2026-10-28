import Foundation

/// Software-authored learning metadata. Imported text remains in BookDocument;
/// this index contains references, never a second copy of the user's book.
enum BookCourseTier: String, Codable, Equatable, Sendable {
    case edited, sourceGuided, readingOnly
    var title: String {
        switch self {
        case .edited: return "已编辑节点教案"
        case .sourceGuided: return "原注节点导学"
        case .readingOnly: return "阅读材料"
        }
    }
}


struct BookCourseComparison: Codable, Equatable, Sendable {
    let branchNodeID: Int
    let firstNodeID: Int
    let secondNodeID: Int
    let title: String
    let prompt: String
    let explanation: String
    var nodeIDs: [Int] { [firstNodeID, secondNodeID] }
}

struct BookCourseCheckpoint: Codable, Equatable, Sendable, Identifiable {
    let id: String
    /// The learner chooses a move in this BEFORE-move position.
    let anchorNodeID: Int
    /// Original commentary is resolved from the imported record at runtime.
    let annotationNodeID: Int
    /// A legal source child of anchorNodeID, not an engine-best-move assertion.
    let referenceNodeID: Int
    let title: String
    let prompt: String
    let explanation: String
    let focus: String
    let tier: BookCourseTier
    let comparison: BookCourseComparison?
}

struct BookCourseRelatedUnit: Codable, Equatable, Sendable, Identifiable {
    var id: String { unitID }
    let unitID: String
    let reason: String
    /// Content pairing was individually checked for a shared goal and changed
    /// conditions. This never means the learner has demonstrated transfer.
    /// A same-section suggestion alone is not a verified content pairing.
    let isVerifiedTransfer: Bool
}

struct BookCourseUnit: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let recordID: String
    let sourceHash: String
    let sectionID: String
    let title: String
    let tier: BookCourseTier
    let goal: String
    let connection: String
    let checkpoints: [BookCourseCheckpoint]
    let nextUnitID: String?
    let nextReason: String
    let relatedUnits: [BookCourseRelatedUnit]
    let excludedNodeIDs: [Int]
    let availabilityNote: String
    var canPractice: Bool { !checkpoints.isEmpty }
}

struct BookCourseSection: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let chapterNumber: Int
    let chapterTitle: String
    let title: String
    let order: Int
    let goal: String
    let connection: String
    let previousSectionID: String?
    let nextSectionID: String?
    let unitIDs: [String]
}

struct BookCourseStats: Codable, Equatable, Sendable {
    let readableRecordCount: Int
    let practiceRecordCount: Int
    let editedRecordCount: Int
    let sourceGuidedRecordCount: Int
    let readingOnlyRecordCount: Int
    let checkpointCount: Int
    let editedCheckpointCount: Int
    let comparisonCount: Int
    let excludedNodeCount: Int
    let recordsWithExcludedNodes: Int
}

struct BookCourseCatalog: Codable, Equatable, Sendable {
    let sourceHash: String
    let sections: [BookCourseSection]
    let units: [BookCourseUnit]
    let firstRoundUnitIDs: [String]
    let stats: BookCourseStats
    var firstRoundUnits: [BookCourseUnit] { firstRoundUnitIDs.compactMap { unit(id: $0) } }
    func unit(id: String) -> BookCourseUnit? { units.first { $0.id == id } }
    func unit(recordID: String) -> BookCourseUnit? { units.first { $0.recordID == recordID } }
    func checkpoint(id: String) -> BookCourseCheckpoint? {
        units.lazy.flatMap(\.checkpoints).first { $0.id == id }
    }

    /// Pure, deterministic and deliberately non-MainActor. Call on a background
    /// task: every source branch is replayed before it can become an exercise.
    static func build(document: BookDocument) -> BookCourseCatalog {
        let isYilin = document.title.contains("弈林新编") || document.title.contains("弈林新編")
        let chapterOrder = isYilin ? BookLearningGuide.recommendedChapterOrder : document.chapters.map(\.number)
        let chapters = document.chapters.sorted {
            let a = chapterOrder.firstIndex(of: $0.number) ?? Int.max
            let b = chapterOrder.firstIndex(of: $1.number) ?? Int.max
            return a == b ? $0.number < $1.number : a < b
        }
        let sourceSections = chapters.flatMap { chapter in chapter.sections.map { (chapter, $0) } }
        let records = Dictionary(document.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let orderedRecordIDs = sourceSections.flatMap { $0.1.recordIDs }
        // Parser output normally covers all records. Keep imported material visible
        // even when a caller constructs a partial directory by hand.
        let orderedRecords = (orderedRecordIDs + document.records.map(\.id).filter { !orderedRecordIDs.contains($0) })
            .compactMap { records[$0] }
        // No private-edition bindings or third-party lesson text are distributed.
        var drafts: [Draft] = []
        var seen = Set<String>()
        for record in orderedRecords where seen.insert(record.id).inserted {
            let uid = "book-course:\(document.sourceSHA256):\(record.id)"
            let replay = Replay(record: record)
            let checkpoints = sourceCheckpoints(record: record, unitID: uid, replay: replay)
            let guidance = sectionGuidance(chapter: isYilin ? record.chapterNumber ?? 0 : 0,
                                           title: record.sectionTitle)
            let tier: BookCourseTier = checkpoints.isEmpty ? .readingOnly : .sourceGuided
            var notes: [String] = []
            if record.isReadingOnly { notes.append("纯文字材料：可阅读，不计独立练习。") }
            else if checkpoints.isEmpty { notes.append("未找到有原注可定位的合法练习节点；原图、原注和变招仍可阅读。") }
            else { notes.append("按合法原注节点自动建立入口，尚未逐谱编辑教案；不把通用提问当成精讲。") }
            if !replay.excluded.isEmpty { notes.append("\(replay.excluded.count) 个异常或受其影响的节点已退出教学入口，原文件未改写。") }
            if record.isSupplement { notes.append("此篇为文件所附补充资料，不冒充《弈林新编》正文。") }
            drafts.append(.init(id: uid, record: record, tier: tier,
                goal: guidance.goal,
                connection: guidance.connection,
                checkpoints: checkpoints, excluded: replay.excluded, note: notes.joined(separator: " ")))
        }
        let firstRound: [String] = []
        let units = drafts.map { draft -> BookCourseUnit in
            let siblings = drafts.filter { $0.record.sectionID == draft.record.sectionID && !$0.checkpoints.isEmpty }
            let siblingIndex = siblings.firstIndex { $0.id == draft.id }
            let nextSibling = siblingIndex.flatMap { $0 + 1 < siblings.count ? siblings[$0 + 1] : nil }
                ?? (draft.checkpoints.isEmpty ? siblings.first : nil)
            var related: [BookCourseRelatedUnit] = []
            if let candidate = nextSibling, !related.contains(where: { $0.unitID == candidate.id }) {
                related.append(.init(unitID: candidate.id,
                    reason: "同属「\(draft.record.sectionTitle)」：换一例先找成立条件，再读原注核对；尚未审校为同难度迁移题。",
                    isVerifiedTransfer: false))
            }
            let nextID: String?
            let nextReason: String
            if let nextSibling {
                nextID = nextSibling.id
                nextReason = "继续本节另一例，检查相同主题下哪些条件改变；这只是同节续学，不自动计作迁移成功。"
            } else {
                let sectionIndex = sourceSections.firstIndex { $0.1.id == draft.record.sectionID }
                let laterIDs = sectionIndex.map { sourceSections.dropFirst($0 + 1).flatMap { $0.1.recordIDs } } ?? []
                nextID = laterIDs.lazy.compactMap { id in drafts.first { $0.record.id == id && !$0.checkpoints.isEmpty }?.id }.first
                nextReason = nextID == nil ? "本路径已到末项；回看尚需无提示重试的节点，或自由选读其他小节。" : "本节告一段落，按小节前后联系进入下一主题；章节始终开放，不设强制通关。"
            }
            return BookCourseUnit(id: draft.id, recordID: draft.record.id, sourceHash: document.sourceSHA256,
                sectionID: draft.record.sectionID, title: draft.record.displayTitle, tier: draft.tier,
                goal: draft.goal, connection: draft.connection, checkpoints: draft.checkpoints,
                nextUnitID: nextID, nextReason: nextReason, relatedUnits: related,
                excludedNodeIDs: draft.excluded, availabilityNote: draft.note)
        }
        let sections = sourceSections.enumerated().map { index, pair -> BookCourseSection in
            let (chapter, source) = pair
            let guide = sectionGuidance(chapter: isYilin ? chapter.number : 0, title: source.title)
            return .init(id: source.id, chapterNumber: chapter.number, chapterTitle: chapter.title,
                title: source.title, order: index, goal: guide.goal, connection: guide.connection,
                previousSectionID: index > 0 ? sourceSections[index - 1].1.id : nil,
                nextSectionID: index + 1 < sourceSections.count ? sourceSections[index + 1].1.id : nil,
                unitIDs: source.recordIDs.compactMap { rid in units.first { $0.recordID == rid }?.id })
        }
        let checkpoints = units.flatMap(\.checkpoints)
        return .init(sourceHash: document.sourceSHA256, sections: sections, units: units,
            firstRoundUnitIDs: firstRound, stats: .init(readableRecordCount: units.count,
                practiceRecordCount: units.filter(\.canPractice).count,
                editedRecordCount: units.filter { $0.tier == .edited }.count,
                sourceGuidedRecordCount: units.filter { $0.tier == .sourceGuided }.count,
                readingOnlyRecordCount: units.filter { $0.tier == .readingOnly }.count,
                checkpointCount: checkpoints.count, editedCheckpointCount: checkpoints.filter { $0.tier == .edited }.count,
                comparisonCount: checkpoints.filter { $0.comparison != nil }.count,
                excludedNodeCount: units.reduce(0) { $0 + $1.excludedNodeIDs.count },
                recordsWithExcludedNodes: units.filter { !$0.excludedNodeIDs.isEmpty }.count))
    }

    private struct Draft {
        let id: String
        let record: BookRecord
        let tier: BookCourseTier
        let goal: String
        let connection: String
        let checkpoints: [BookCourseCheckpoint]
        let excluded: [Int]
        let note: String
    }

    private struct Replay {
        var positions: [Int: Position] = [:]
        var excluded: [Int] = []
        init(record: BookRecord) {
            guard record.nodes.indices.contains(record.rootNodeID),
                  record.nodes[record.rootNodeID].id == record.rootNodeID,
                  record.nodes[record.rootNodeID].parentID == nil,
                  !Self.hasSourceErratum(record.nodes[record.rootNodeID].comment),
                  (try? record.rawPosition.validate()) != nil else {
                excluded = record.nodes.map(\.id); return
            }
            positions[record.rootNodeID] = record.rawPosition
            for node in record.nodes where node.id != record.rootNodeID {
                guard record.nodes.indices.contains(node.id), record.nodes[node.id] == node,
                      let parentID = node.parentID, parentID < node.id,
                      record.nodes.indices.contains(parentID), record.nodes[parentID].childIDs.contains(node.id),
                      let before = positions[parentID], !Self.hasSourceErratum(node.comment),
                      let uci = node.uci, let move = Move(uci: uci),
                      let after = try? before.applying(move: move) else { excluded.append(node.id); continue }
                positions[node.id] = after
            }
        }
        private static func hasSourceErratum(_ text: String) -> Bool {
            // Explicit transcription notices, not ordinary discussions of bad moves.
            ["原谱被录错", "录入错误", "录谱错误", "此处棋谱有误"].contains { text.contains($0) }
        }
        func children(of id: Int, record: BookRecord) -> [Int] {
            guard record.nodes.indices.contains(id), positions[id] != nil else { return [] }
            var seen = Set<Int>()
            return record.nodes[id].childIDs.filter {
                record.nodes.indices.contains($0) && record.nodes[$0].parentID == id
                    && positions[$0] != nil && seen.insert($0).inserted
            }
        }
    }

    private static func sourceCheckpoints(record: BookRecord, unitID: String, replay: Replay) -> [BookCourseCheckpoint] {
        guard !record.isReadingOnly else { return [] }
        let candidates: [BookCourseCheckpoint] = record.nodes.compactMap { annotation in
            guard replay.positions[annotation.id] != nil,
                  !annotation.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let anchor: Int
            let reference: Int
            if let parent = annotation.parentID {
                anchor = parent; reference = annotation.id
            } else {
                anchor = annotation.id
                guard let child = replay.children(of: anchor, record: record).first else { return nil }
                reference = child
            }
            guard replay.positions[anchor] != nil else { return nil }
            let children = replay.children(of: anchor, record: record)
            let comparison = children.first(where: { $0 != reference }).map { second in
                BookCourseComparison(branchNodeID: anchor, firstNodeID: reference, secondNodeID: second,
                    title: "同一局面的两条原谱变化",
                    prompt: "分别走两条收录的变化，指出对方回应、保护关系或活动线路改变在哪里。",
                    explanation: "两条变化都从节点 \(anchor) 出发；顺序不表示优劣。按各自原注核对，不把局部评语扩展为所有着法的结论。")
            }
            return BookCourseCheckpoint(id: "\(unitID):source:\(annotation.id):\(anchor)",
                anchorNodeID: anchor, annotationNodeID: annotation.id, referenceNodeID: reference,
                title: annotation.parentID == nil ? "从本谱起点判断" : "原注 \(annotation.id) · 走前先判断",
                prompt: "在当前局面先选一着，并说出要处理的威胁或要改善的棋子；再展开节点 \(annotation.id) 的原注核对。",
                explanation: "此入口依据本谱节点 \(annotation.id) 的原注与对应合法谱线自动生成，未补写作者未讲的理由。简短胜负评语或署名不能替代完整棋理；合理异着仍需单独核验。",
                focus: record.sectionTitle, tier: .sourceGuided, comparison: comparison)
        }
        // An exercise is a decision position, not each annotation attached to
        // its outgoing moves. Keep one entry per anchor, prefer a concrete move
        // annotation to a root overview, and expose siblings through comparison.
        // Other annotations remain untouched in the source reader.
        var result: [BookCourseCheckpoint] = []
        var indexByAnchor: [Int: Int] = [:]
        for candidate in candidates {
            if let index = indexByAnchor[candidate.anchorNodeID] {
                if result[index].annotationNodeID == record.rootNodeID
                    && candidate.annotationNodeID != record.rootNodeID {
                    result[index] = candidate
                }
            } else {
                indexByAnchor[candidate.anchorNodeID] = result.count
                result.append(candidate)
            }
        }
        return result
    }


    private static func sectionGuidance(chapter: Int, title: String) -> BookLearningGuidance {
        let base = BookLearningGuide.guide(chapter: chapter, sectionTitle: title)
        let topic: (String, String)?
        switch (chapter, title) {
        case (2, "线位与子力运用"):
            topic = ("看一条线是否畅通、一个棋子是否受限；用活动与保护解释子力作用，不只背静态子值。", "回补布局和交换判断中的薄弱环节，再回到原先卡住的节点。")
        case (2, "杀法初阶"):
            topic = ("确认限制将帅逃路与连续威胁的配合；只有算清对方回应才称为杀势。", "承接线路与子力配合；遇到中局计算缺口时选对应杀法，不要求背杀法名称。")
        case (2, "例和残局"):
            topic = ("指出守和所需的将位、护卫与活动条件，区分一种摆法成立与同类材料必和。", "与残局研究互相对照；这类条件会反过来影响中局是否应该交换。")
        case (2, "兑子与度数"):
            topic = ("交换前数清实际失去和得到的行动机会，并检查换完谁能先制造威胁。", "把子力作用与行棋节奏接起来，再用于布局展开和中局简化。")
        case (2, "布局入门"):
            topic = ("逐手解释出子的任务、中心控制和将帅安全，不以记住起手名称作为完成。", "为第四章主线补出子逻辑；已经会的部分可以跳过，直接回课内节点。")
        case (2, "全局浅释"):
            topic = ("跟踪同一盘棋的计划如何从出子变成攻守，再变成收束目标。", "用较少注释串联阶段，然后进入第八章完整对局检查判断能否保持一致。")
        case (2, "谈谈怎样掌握先手"):
            topic = ("区分眼前将吃与可持续威胁，计算对方最直接的反击后再决定抢攻。", "承接出子和行动机会，回到第五章攻守选择核对每次争先的条件。")
        case (2, "实战布局琐谈"):
            topic = ("在不同布局实例中检验出子、牵制与反击条件；同一起手并不保证相同中局。", "与第四章同主题小节互查，带着具体问题读实例，不把十篇当成十套必背定式。")
        case (3, "让单马"):
            topic = ("在少一马的起始条件下检查出子、威胁和补偿，先核对谁让子、谁先走。", "属于可选拓展；从正常布局带来判断方法，不把让子结论直接套回正常对局。")
        case (3, "让双马"):
            topic = ("少两马后重新核算可持续进攻与防守缺口；更多弃材需要更具体的补偿。", "与让单马比较补偿条件的变化，不能按谱例编号推断难度。")
        case (6, "残局研究五十局"):
            topic = ("逐例找胜和依赖的保护链、将位和活动空间；领先时保住获胜条件，落后时寻找抵抗。", "承接中局的交换选择。首轮先比较第一、二局的保护结构，再按实际问题选其他残局。")
        case (6, "参考对局"):
            topic = ("在较长续线中跟踪残局条件何时改变，不能只用最后的胜负评语解释前面每步。", "与前面的研究局互查；参考局是运用材料，并非材料相似就自动成为迁移题。")
        case (6, "补充 · 象棋残局新论"):
            topic = ("把补充版本作为对照，检查分歧起点和不同续线各自的成立条件。", "这是文件另附资料；回到正文对应局比较，不混淆来源，也不覆盖正文。")
        case (7, "短棹轻舟"):
            topic = ("从同一古局起点逐一检查强制回应，区分源谱列出的变化与尚未穷尽的防守。", "用中局计算与残局条件作专题检验；不把古局结论直接当实战通则。")
        case (7, "双马饮泉"):
            topic = ("在实际节点核对马路、限制与将帅逃路，确认配合是否经得住换应招。", "继续逐分支验证方法；先看棋面成立条件，再学习题名。")
        case (7, "阳春白雪"):
            topic = ("拆开长变化中的攻守转折，每次转换目标都重查对手的可用回应。", "把前两例的局部核验延伸到长线，不以连续跟谱代替独立计算。")
        case (7, "雪拥蓝关"):
            topic = ("对照同题古谱与新编的真实版本，先找到分歧位置再比较结论。", "汇合前面逐分支核验；不同起点不能硬接成同一分支，版本差异保留可读。")
        case (8, "全局评注"):
            topic = ("把出子任务、攻守转折与残局取舍串成完整计划；原局胜负不能证明每步最优。", "首轮先读第十九、二十局，承接巡河炮与车换马炮；之后按熟悉布局拓展，不必顺序读完四十局。")
        default: topic = nil
        }
        guard let topic else { return base }
        return .init(title: title, goal: topic.0, connection: topic.1,
                     practicePrompt: base.practicePrompt, transferPrompt: base.transferPrompt)
    }
}
