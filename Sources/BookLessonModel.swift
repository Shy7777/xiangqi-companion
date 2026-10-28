import Foundation
import Combine

enum BookLessonStage: String, Codable, CaseIterable, Sendable {
    case reading, decision, feedback, comparison, summary
    var title: String {
        switch self {
        case .reading: return "读懂问题"
        case .decision: return "自己判断"
        case .feedback: return "看清后果"
        case .comparison: return "比较条件"
        case .summary: return "回顾与下一步"
        }
    }
}

enum BookReferenceMatch: String, Sendable {
    case none, mainline, branch, offBook
    var title: String {
        switch self {
        case .none: return "尚未落子"
        case .mainline: return "与本题参考着一致"
        case .branch: return "书中收录的另一分支"
        case .offBook: return "原谱未收录；不等于错误"
        }
    }
}

/// A source-backed classroom, not another book tree or learning ledger. All
/// attempts, assistance, completions and reviews go to the shared LearningStore.
@MainActor
final class BookLessonModel: ObservableObject {
    typealias Assess = @MainActor (Position, Move, Int) async throws -> MoveAssessment
    typealias Evaluate = @MainActor (Position, Int) async throws -> [EngineLine]
    typealias Reply = @MainActor (Position, Int) async throws -> Move?

    @Published private(set) var catalog: BookCourseCatalog?
    @Published private(set) var selectedUnit: BookCourseUnit?
    @Published private(set) var checkpointIndex = 0
    @Published private(set) var stage: BookLessonStage = .reading
    @Published private(set) var position = Position.initial
    @Published var selected: Square?
    @Published private(set) var targets: [Square] = []
    @Published private(set) var studentSide = Side.red
    @Published private(set) var lastMove: Move?
    @Published private(set) var isThinking = false
    @Published private(set) var isLoading = false
    @Published var notice: String?
    @Published private(set) var feedback = "选择一课，从书中具体局面开始。"
    @Published private(set) var hintLevel = 0
    @Published private(set) var assessment: MoveAssessment?
    @Published private(set) var referenceMatch: BookReferenceMatch = .none
    @Published private(set) var engineLines: [EngineLine] = []
    @Published private(set) var completedCheckpointIDs = Set<String>()
    @Published private(set) var evidenceRevision = 0
    @Published private(set) var comparisonNodeID: Int?
    @Published private(set) var replyStepCount = 0

    let book: BookStudyModel
    let store: LearningStore
    private let coach: TrainingCoach
    private let assessMove: Assess
    private let evaluatePosition: Evaluate
    private let chooseReply: Reply
    private let now: @MainActor () -> Date
    private var document: BookDocument?
    private var anchorPosition = Position.initial
    private var attemptedMove: Move?
    private var pendingPV: [String] = []
    private var runID = UUID()
    private var started = Date()
    private var runHints = 0
    private var runErrors = 0
    private var wasRetry = false
    private var wasUnseen = false
    private var runFinished = false
    private var token = UUID()
    private var catalogToken = UUID()
    private var operation: Task<Void, Never>?
    private var activeReviewID: UUID?
    private var anchorReady = false
    private var storeSubscription: AnyCancellable?

    init(book: BookStudyModel, store: LearningStore, coach: TrainingCoach,
         assess: Assess? = nil, evaluate: Evaluate? = nil, reply: Reply? = nil,
         now: @escaping @MainActor () -> Date = Date.init) {
        self.book = book; self.store = store; self.coach = coach; self.now = now
        assessMove = assess ?? { try await coach.assess(position: $0, move: $1, movetime: $2) }
        evaluatePosition = evaluate ?? { try await coach.evaluate(position: $0, movetime: $1) }
        chooseReply = reply ?? { try await coach.chooseReply(position: $0, level: $1) }
        storeSubscription = store.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.evidenceRevision &+= 1 }
        }
    }

    var checkpoint: BookCourseCheckpoint? {
        guard let unit = selectedUnit, unit.checkpoints.indices.contains(checkpointIndex) else { return nil }
        return unit.checkpoints[checkpointIndex]
    }
    var currentSource: BookStudySource? {
        guard let unit = selectedUnit, let checkpoint else { return nil }
        return BookStudySource(bookSHA: unit.sourceHash, recordID: unit.recordID,
                               nodeID: checkpoint.anchorNodeID, title: unit.title + " · " + checkpoint.title)
    }
    var analysisPosition: Position { position }
    var decisionPosition: Position { anchorPosition }
    var goal: String { selectedUnit?.goal ?? "先选择本课材料" }
    var connection: String { selectedUnit?.connection ?? "" }
    var prompt: String { checkpoint?.prompt ?? selectedUnit?.availabilityNote ?? "" }
    var explanation: String { checkpoint?.explanation ?? "" }
    var canStart: Bool { checkpoint != nil && anchorReady && decisionPly <= 400 }
    var canSubmit: Bool { stage == .decision && !isThinking && position.sideToMove == studentSide && !runFinished }
    var canAdvance: Bool { runFinished }
    var canCompare: Bool { checkpoint?.comparison != nil && !isThinking }
    var canPlayReply: Bool {
        guard !isThinking, stage == .feedback || stage == .comparison else { return false }
        // A source route ends where the source ends. It must never silently
        // become engine play under an "original next move" presentation.
        if comparisonNodeID != nil { return sourceReplyStep != nil }
        return !position.legalMoves().isEmpty
    }
    var completedCount: Int { completedCheckpointIDs.count }
    var progressText: String { "本课关键点 \(min(checkpointIndex + 1, selectedUnit?.checkpoints.count ?? 0))/\(selectedUnit?.checkpoints.count ?? 0) · 本轮完成 \(completedCount)" }
    var nextUnitTitle: String? { selectedUnit?.nextUnitID.flatMap { catalog?.unit(id: $0)?.title } }
    var nextReason: String { selectedUnit?.nextReason ?? "可返回目录，自主选择下一篇。" }
    var engineAnchorPosition: Position? { engineLines.isEmpty ? nil : anchorPosition }
    var currentReviewItems: [ReviewItem] {
        guard let hash = selectedUnit?.sourceHash else { return [] }
        return store.data.reviews.filter {
            guard let lessonID = $0.lessonID, let lineID = $0.lineID else { return false }
            return store.bookSource(lessonID: lessonID, lineID: lineID)?.bookSHA == hash
        }
    }
    var dueReviewItems: [ReviewItem] {
        currentReviewItems.filter { !$0.resolved && $0.due <= now() }.sorted { $0.due < $1.due }
    }
    var dueBookSources: [BookStudySource] {
        guard let catalog else { return [] }
        let wrongAnswerKeys = Set(currentReviewItems.filter { !$0.resolved }.compactMap { item -> String? in
            guard let lessonID = item.lessonID, let lineID = item.lineID else { return nil }
            return LearningStore.key(lessonID, lineID)
        })
        return Array((store.data.bookSources ?? [:]).values).filter { source in
            guard source.bookSHA == catalog.sourceHash, !wrongAnswerKeys.contains(source.key),
                  let unit = catalog.unit(recordID: source.recordID),
                  unit.checkpoints.contains(where: { $0.anchorNodeID == source.nodeID }),
                  let due = store.progress(source.lessonID, source.lineID).nextReview else { return false }
            return due <= now()
        }.sorted { first, second in
            let firstDue = store.progress(first.lessonID, first.lineID).nextReview ?? .distantFuture
            let secondDue = store.progress(second.lessonID, second.lineID).nextReview ?? .distantFuture
            return firstDue == secondDue ? first.key < second.key : firstDue < secondDue
        }
    }
    var dueReviewCount: Int { dueReviewItems.count + dueBookSources.count }
    private var unitProgress: [LineProgress] {
        guard let unit = selectedUnit else { return [] }
        return Set(unit.checkpoints.map(\.anchorNodeID)).map { nodeID in
            let source = BookStudySource(bookSHA: unit.sourceHash, recordID: unit.recordID, nodeID: nodeID, title: unit.title)
            return store.progress(source.lessonID, source.lineID)
        }
    }
    var independentCount: Int { unitProgress.reduce(0) { $0 + $1.cleanTests } }
    var assistedCount: Int { unitProgress.reduce(0) { $0 + max(0, $1.completions - $1.cleanTests) } }
    var delayedCount: Int { unitProgress.reduce(0) { $0 + $1.delayedTests } }
    var summary: String {
        guard runFinished else { return "本题尚未获得确定的合理着法评价；取消、失败与不确定结果都不算通过。" }
        let run = store.data.runs.first { $0.id == runID }
        let evidence = run?.delayed == true ? "本题已记录为延迟独立通过。" :
            run?.independent == true ? "本题已记录为无提示通过，仍需隔日复测。" : "本题已记录为辅助练习完成，不代表独立掌握。"
        return evidence + "本轮提示 \(runHints) 次，明确偏差 \(runErrors) 次。"
    }
    var displayedHint: String {
        guard hintLevel > 0 else { return "" }
        if hintLevel == 1 { return "先检查：" + (checkpoint?.focus ?? "对方的直接威胁和你的应对条件。") }
        guard let move = referenceMove else { return "引擎候选仅供比较，不代表原著唯一答案。" }
        return "原谱候选：\(anchorPosition.notation(for: move))。这是书中走法，是否合理仍由局面核验。"
    }
    var arrows: [RecommendationArrow] {
        guard stage == .decision, hintLevel >= 2, position == anchorPosition else { return [] }
        let candidates: [RecommendationArrow] = engineLines.prefix(3).compactMap { line in
            guard let move = line.pv.first.flatMap(Move.init(uci:)),
                  (try? anchorPosition.applying(move: move)) != nil else { return nil }
            return .init(rank: line.rank, move: move)
        }
        if !candidates.isEmpty { return candidates }
        return referenceMove.map { [.init(rank: 1, move: $0)] } ?? []
    }
    var comparisonChoices: [BookMoveChoice] {
        guard let checkpoint, let record = sourceRecord else { return [] }
        let ids = checkpoint.comparison?.nodeIDs ?? []
        let parent = checkpoint.comparison?.branchNodeID ?? checkpoint.anchorNodeID
        guard let before = try? replay(record: record, to: parent) else { return [] }
        return ids.compactMap { id in
            guard record.nodes.indices.contains(id), let move = record.nodes[id].uci.flatMap(Move.init(uci:)),
                  (try? before.applying(move: move)) != nil else { return nil }
            return BookMoveChoice(id: id, title: before.notation(for: move), comment: record.nodes[id].comment,
                                  isMainline: record.nodes[parent].childIDs.first == id)
        }
    }
    var primaryActionTitle: String {
        switch stage {
        case .reading: return canStart ? "从这一处自己判断" : "继续下一篇"
        case .decision: return isThinking ? "取消计算" : "请在棋盘上落子"
        case .feedback: return runFinished ? "完成本题，回顾收获" : isThinking ? "取消计算" : "回到落子前再试"
        case .comparison: return runFinished ? "结束比较，回顾本题" : "回到决策点"
        case .summary: return hasNextCheckpoint ? "进入下一关键点" : "进入下一课"
        }
    }
    private var hasNextCheckpoint: Bool { checkpointIndex + 1 < (selectedUnit?.checkpoints.count ?? 0) }
    private var sourceRecord: BookRecord? { document?.records.first { $0.id == selectedUnit?.recordID } }
    private var referenceMove: Move? {
        guard let checkpoint, let record = sourceRecord, record.nodes.indices.contains(checkpoint.referenceNodeID) else { return nil }
        return record.nodes[checkpoint.referenceNodeID].uci.flatMap(Move.init(uci:))
    }
    private var sourceReplyStep: (nodeID: Int, move: Move, position: Position)? {
        guard let nodeID = comparisonNodeID, let record = sourceRecord,
              record.nodes.indices.contains(nodeID), let child = record.nodes[nodeID].childIDs.first,
              record.nodes.indices.contains(child), record.nodes[child].parentID == nodeID,
              let move = record.nodes[child].uci.flatMap(Move.init(uci:)),
              let next = try? position.applying(move: move) else { return nil }
        return (child, move, next)
    }
    private var decisionPly: Int {
        guard let checkpoint, let record = sourceRecord else { return 0 }
        var cursor = checkpoint.anchorNodeID, count = 0, visited = Set<Int>()
        while record.nodes.indices.contains(cursor), let parent = record.nodes[cursor].parentID,
              visited.insert(cursor).inserted {
            count += 1; cursor = parent
        }
        return count
    }

    func reloadCatalog() async {
        guard let source = book.document else { return }
        if catalog?.sourceHash == source.sourceSHA256 { return }
        invalidateOperation(); let revision = UUID(); catalogToken = revision; isLoading = true
        let built = await Task.detached(priority: .userInitiated) { BookCourseCatalog.build(document: source) }.value
        guard catalogToken == revision, !Task.isCancelled, book.document?.sourceSHA256 == source.sourceSHA256 else { return }
        install(document: source, catalog: built)
        isLoading = false
    }

    /// Also provides a deterministic seam for source/session regression tests.
    func install(document source: BookDocument, catalog newCatalog: BookCourseCatalog) {
        guard source.sourceSHA256 == newCatalog.sourceHash else { return }
        preserveAbandonedAttempt()
        invalidateOperation(); document = source; catalog = newCatalog
        let saved = store.data.bookResume
        if let saved, saved.source.bookSHA == source.sourceSHA256,
           let unit = newCatalog.unit(id: saved.unitID), unit.recordID == saved.source.recordID,
           unit.checkpoints.indices.contains(saved.checkpointIndex),
           unit.checkpoints[saved.checkpointIndex].anchorNodeID == saved.source.nodeID {
            selectUnit(id: unit.id, checkpoint: saved.checkpointIndex, persist: false)
            completedCheckpointIDs = Set(saved.completedCheckpointIDs).intersection(Set(unit.checkpoints.map(\.id)))
            runID = saved.runID; started = saved.started; runHints = saved.hints; runErrors = saved.errors
            wasUnseen = saved.wasUnseen; hintLevel = saved.hintLevel; wasRetry = saved.wasRetry
            runFinished = store.data.runs.contains { $0.id == saved.runID }
            if runFinished { stage = .summary; feedback = summary }
            else if saved.stage == BookLessonStage.reading.rawValue { stage = .reading }
            else if saved.stage == BookLessonStage.decision.rawValue && saved.attemptedMove == nil {
                stage = .decision
            } else {
                // Search results are not persisted as evidence. Never restore an
                // ungraded attempt as an accepted move or silently award a pass.
                stage = .decision; wasRetry = true
                markAssisted(); feedback = "已回到上次决策点。中断的计算没有判分；本次重走保留辅助记录。"
            }
            saveResume(); return
        }
        let id = book.selectedRecordID.flatMap { newCatalog.unit(recordID: $0)?.id }
            ?? newCatalog.firstRoundUnitIDs.first ?? newCatalog.units.first?.id
        if let id { selectUnit(id: id) }
    }

    func selectUnit(id: String) { selectUnit(id: id, checkpoint: 0, persist: true) }
    func selectRecord(id: String) {
        guard let unit = catalog?.unit(recordID: id) else { return }
        if selectedUnit?.id != unit.id { selectUnit(id: unit.id) }
    }
    func selectCheckpoint(index: Int) {
        guard let unit = selectedUnit, unit.checkpoints.indices.contains(index), index != checkpointIndex else { return }
        preserveAbandonedAttempt()
        checkpointIndex = index; activeReviewID = nil; prepareCheckpoint()
    }
    private func selectUnit(id: String, checkpoint index: Int, persist: Bool) {
        guard let unit = catalog?.unit(id: id) else { return }
        preserveAbandonedAttempt()
        invalidateOperation(); selectedUnit = unit; checkpointIndex = index
        completedCheckpointIDs = []; activeReviewID = nil
        book.chooseRecord(id: unit.recordID, resume: false, markVisited: false)
        prepareCheckpoint(persist: persist)
    }

    private func prepareCheckpoint(persist: Bool = true) {
        invalidateOperation(); clearBoardSelection(); attemptedMove = nil; assessment = nil; referenceMatch = .none
        engineLines = []; pendingPV = []; hintLevel = 0; runHints = 0; runErrors = 0; replyStepCount = 0; anchorReady = false
        runID = UUID(); started = now(); runFinished = false; comparisonNodeID = nil; stage = .reading
        guard let record = sourceRecord else { return }
        do {
            anchorPosition = try replay(record: record, to: checkpoint?.anchorNodeID ?? record.rootNodeID)
            position = anchorPosition; studentSide = anchorPosition.sideToMove; lastMove = nil
            anchorReady = referenceMove.flatMap { try? anchorPosition.applying(move: $0) } != nil
            if let checkpoint { book.go(to: checkpoint.anchorNodeID) }
            if let source = currentSource {
                store.registerBookSource(source)
                wasUnseen = !store.data.exposedLines.contains(source.key)
                wasRetry = recentlyExposed(source)
            }
            feedback = checkpoint?.prompt ?? selectedUnit?.availabilityNote ?? "此篇保留阅读，尚未配备可判分关键点。"
            notice = nil
        } catch { notice = error.localizedDescription; feedback = "此处源局面待核验，原文仍可阅读。" }
        if persist { saveResume() }
    }

    func startDecision() {
        guard canStart else { return }
        if runFinished { retry(); return }
        if stage == .feedback || stage == .comparison { retry(); return }
        invalidateOperation(); stage = .decision; position = anchorPosition; lastMove = nil
        clearBoardSelection(); attemptedMove = nil; assessment = nil; referenceMatch = .none; pendingPV = []
        if let source = currentSource { wasRetry = wasRetry || recentlyExposed(source) }
        feedback = "你执\(studentSide.label)。请选择任意合法着；不按是否背出原谱判分。"; saveResume()
    }

    func tap(_ square: Square) {
        guard canSubmit else { return }
        if let selected, targets.contains(square) { submit(Move(from: selected, to: square)); return }
        if position[square]?.side == studentSide {
            selected = square; targets = position.legalMoves(from: square).map(\.to)
        } else { clearBoardSelection() }
    }

    func submit(_ move: Move, movetime: Int = 900) {
        guard canSubmit, let source = currentSource,
              let after = try? anchorPosition.applying(move: move) else { return }
        invalidateOperation(); let revision = token; let before = anchorPosition
        attemptedMove = move; position = after; lastMove = move; stage = .feedback
        clearBoardSelection(); assessment = nil; isThinking = true; pendingPV = []; replyStepCount = 0
        referenceMatch = sourceMatch(move); feedback = "已落子，正在核验走前与走后局面。你仍执\(studentSide.label)。"
        saveResume()
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await assessMove(before, move, movetime)
                guard token == revision, !Task.isCancelled else { return }
                isThinking = false; assessment = result; pendingPV = result.replyPV
                let good = result.verdict == .exactBest || result.verdict == .good
                let wrong = result.verdict == .inaccuracy || result.verdict == .mistake
                store.recordDecision(StudyDecision(id: UUID(), date: now(), lessonID: source.lessonID,
                    lineID: source.lineID, ply: decisionPly, mode: .test, move: move.uci,
                    outcome: good ? (referenceMatch == .mainline ? "course" : "alternative") : wrong ? "mistake" : "uncertain",
                    hintLevel: hintLevel, wasRetry: wasRetry))
                feedback = referenceMatch.title + "。\n引擎核验：" + result.detail
                if wrong {
                    runErrors += 1; wasRetry = true; markAssisted()
                    if let best = result.bestMove {
                        store.addReview(lessonID: source.lessonID, lineID: source.lineID, title: source.title,
                            fen: before.fen, attempted: move.uci, suggested: best.uci, detail: result.detail,
                            replyPV: result.replyPV, now: now())
                    }
                    if let id = activeReviewID { store.reviewCompleted(id, clean: false, now: now()) }
                    feedback += " 可以逐步看对方应招，然后回到落子前重试。"
                } else if good {
                    finishCheckpoint()
                    feedback += " 本题局面判断已通过；这不等于复现全部原谱。"
                } else {
                    feedback += " 本次评价不确定，不计错误，也不算通过。可加深复核或重走。"
                }
                saveResume()
            } catch {
                guard token == revision, !Task.isCancelled else { return }
                isThinking = false; assessment = nil
                feedback = "本次未判分：\(error.localizedDescription) 可重新核验；不会按错误或通过记录。"
                saveResume()
            }
        }
    }

    /// Retry the SAME pending move after an engine failure/uncertain result.
    /// A new user decision must instead use retry(), which records assistance.
    func reassess(movetime: Int = 2500) {
        guard !runFinished, let move = attemptedMove else { return }
        invalidateOperation(); position = anchorPosition; stage = .decision
        submit(move, movetime: movetime)
    }

    func requestHint() {
        guard stage == .decision, !runFinished else { return }
        runHints += 1; hintLevel = min(2, hintLevel + 1); markAssisted(); saveResume()
        guard hintLevel == 2 else { return }
        requestEngineCandidates()
    }

    /// Candidates are explicitly for the original decision, in the learner's
    /// perspective, even if the board currently shows a later response ply.
    func requestEngineCandidates() {
        guard canStart else { return }
        if stage == .decision { hintLevel = max(2, hintLevel) }
        markAssisted(); saveResume()
        invalidateOperation(); let revision = token; let before = anchorPosition; isThinking = true
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rows = try await evaluatePosition(before, 900)
                guard token == revision, !Task.isCancelled else { return }
                engineLines = rows; isThinking = false; saveResume()
            } catch {
                guard token == revision, !Task.isCancelled else { return }
                isThinking = false; notice = "候选计算未完成：\(error.localizedDescription)。原谱候选不是引擎结论。"
            }
        }
    }

    func revealAnswer() {
        guard let move = referenceMove else { return }
        invalidateOperation(); markAssisted(); hintLevel = 2; runHints += 1
        position = (try? anchorPosition.applying(move: move)) ?? anchorPosition; lastMove = move
        stage = .comparison; comparisonNodeID = checkpoint?.referenceNodeID
        if let nodeID = comparisonNodeID { markDisplayedSourceMove(nodeID: nodeID) }
        pendingPV = []; clearBoardSelection(); feedback = "原谱在这里走\(anchorPosition.notation(for: move))。这是看答案，未记通过。" + explanation
        saveResume()
    }

    func markReadingExposed() {
        guard currentSource != nil else { return }
        markAssisted(); saveResume()
    }

    func markWholeRecordExposed() {
        guard let unit = selectedUnit else { return }
        let sources = unit.checkpoints.map {
            BookStudySource(bookSHA: unit.sourceHash, recordID: unit.recordID,
                nodeID: $0.anchorNodeID, title: unit.title + " · " + $0.title)
        }
        store.markBookSourcesExposed(sources, now: now())
        markAssisted(); saveResume()
    }

    func prepareForAnalysis() { markAssisted(); suspend(); saveResume() }
    func suspend() { invalidateOperation(); saveResume() }
    func cancelEvaluation() {
        invalidateOperation(); feedback = "计算已取消；本次没有新增判分。可以重新核验或回到决策点。"; saveResume()
    }

    func retry() {
        guard canStart else { return }
        invalidateOperation()
        if runFinished {
            runID = UUID(); started = now(); runFinished = false; runHints = 0; runErrors = 0; wasUnseen = false
            if let checkpoint { completedCheckpointIDs.remove(checkpoint.id) }
        }
        markAssisted(); wasRetry = true; stage = .decision; position = anchorPosition
        attemptedMove = nil; assessment = nil; lastMove = nil; referenceMatch = .none
        pendingPV = []; engineLines = []; hintLevel = 0; comparisonNodeID = nil; replyStepCount = 0
        clearBoardSelection(); feedback = "已回到你落子前，仍执\(studentSide.label)。这是重走；之前提示和错误不会被抹去。"; saveResume()
    }

    func returnToAnchor() {
        invalidateOperation(); position = anchorPosition; lastMove = nil; comparisonNodeID = nil
        pendingPV = []; replyStepCount = 0; clearBoardSelection()
        if runFinished { stage = .feedback; feedback = "已回到同一决策点；本题结果保留，可比较另一条变化。"; saveResume() }
        else { retry() }
    }

    func startComparison(nodeID: Int) {
        guard let checkpoint, let comparison = checkpoint.comparison,
              comparison.nodeIDs.contains(nodeID), let record = sourceRecord,
              let next = try? replay(record: record, to: nodeID) else { return }
        invalidateOperation(); markAssisted(); stage = .comparison; position = next
        markDisplayedSourceMove(nodeID: nodeID)
        comparisonNodeID = nodeID; lastMove = record.nodes[nodeID].uci.flatMap(Move.init(uci:))
        pendingPV = []; replyStepCount = 0; clearBoardSelection()
        feedback = comparison.prompt + "\n" + comparison.explanation; saveResume()
    }

    /// One visible ply at a time. The learner identity never follows sideToMove.
    func nextReply() {
        guard canPlayReply else { return }
        markAssisted()
        if comparisonNodeID != nil {
            guard let step = sourceReplyStep else { return }
            markDisplayedSourceMove(nodeID: step.nodeID)
            position = step.position; lastMove = step.move; comparisonNodeID = step.nodeID
            replyStepCount += 1; saveResume(); return
        }
        if let text = pendingPV.first, let move = Move(uci: text), let next = try? position.applying(move: move) {
            markDisplayedEngineMove(from: position)
            pendingPV.removeFirst(); position = next; lastMove = move; replyStepCount += 1; saveResume(); return
        }
        pendingPV = []
        invalidateOperation(); let revision = token; let before = position; isThinking = true
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let move = try await chooseReply(before, 2)
                guard token == revision, !Task.isCancelled else { return }
                isThinking = false
                if let move, let next = try? before.applying(move: move) {
                    markDisplayedEngineMove(from: before)
                    position = next; lastMove = move; replyStepCount += 1
                } else { feedback = "当前路线已无可播放的合法着。" }
                saveResume()
            } catch {
                guard token == revision, !Task.isCancelled else { return }
                isThinking = false; notice = "应招尚未计算完成：" + error.localizedDescription
            }
        }
    }

    func completeCheckpoint() {
        guard runFinished else { return }
        invalidateOperation(); stage = .summary; feedback = summary; saveResume()
    }
    func nextCheckpoint() {
        guard runFinished else { return }
        if hasNextCheckpoint { checkpointIndex += 1; activeReviewID = nil; prepareCheckpoint() }
        else { nextUnit() }
    }
    func nextUnit() {
        guard let id = selectedUnit?.nextUnitID else { notice = "已到当前路径末尾；可以回目录选学或复习。"; return }
        selectUnit(id: id)
    }
    func primaryAction() {
        switch stage {
        case .reading: if canStart { startDecision() } else { nextUnit() }
        case .decision: if isThinking { cancelEvaluation() }
        case .feedback: if isThinking { cancelEvaluation() } else if runFinished { completeCheckpoint() } else { retry() }
        case .comparison: if runFinished { completeCheckpoint() } else { returnToAnchor() }
        case .summary: nextCheckpoint()
        }
    }

    @discardableResult
    func startReview(_ item: ReviewItem) -> Bool {
        guard let lessonID = item.lessonID, let lineID = item.lineID,
              let source = store.bookSource(lessonID: lessonID, lineID: lineID),
              catalog?.sourceHash == source.bookSHA, let unit = catalog?.unit(recordID: source.recordID),
              let index = unit.checkpoints.firstIndex(where: { $0.anchorNodeID == source.nodeID }) else { return false }
        selectUnit(id: unit.id, checkpoint: index, persist: false); activeReviewID = item.id
        guard canStart else { return false }
        startDecision(); return true
    }

    @discardableResult
    func startSourceReview(_ source: BookStudySource) -> Bool {
        guard catalog?.sourceHash == source.bookSHA,
              store.bookSource(lessonID: source.lessonID, lineID: source.lineID)?.key == source.key,
              let unit = catalog?.unit(recordID: source.recordID),
              let index = unit.checkpoints.firstIndex(where: { $0.anchorNodeID == source.nodeID }) else { return false }
        selectUnit(id: unit.id, checkpoint: index, persist: false)
        guard canStart else { return false }
        // No reading stage is rendered between these synchronous transitions.
        // The user chooses whether to reveal help after the prompt is shown.
        startDecision(); return true
    }

    private func finishCheckpoint() {
        guard !runFinished, let source = currentSource, let checkpoint else { return }
        // An unseen book position is not automatically a reviewed transfer
        // exercise. Related source units remain ordinary judgments until a
        // distinct, validated transfer workflow supplies that evidence.
        store.finishRun(id: runID, lessonID: source.lessonID, lineID: source.lineID, mode: .test,
                        hints: runHints, errors: runErrors, wasRetry: wasRetry, wasUnseen: false, now: now())
        if let id = activeReviewID {
            store.reviewCompleted(id, clean: runErrors == 0, assisted: wasRetry || runHints > 0, now: now())
        }
        store.markExposed(source.lessonID, source.lineID, assisted: false, now: now())
        completedCheckpointIDs.insert(checkpoint.id); runFinished = true
    }

    private func recentlyExposed(_ source: BookStudySource) -> Bool {
        if store.recentlyAssisted(lessonID: source.lessonID, lineID: source.lineID, now: now()) { return true }
        if let date = store.progress(source.lessonID, source.lineID).lastStudied {
            return now().timeIntervalSince(date) < 20 * 3600 || Calendar.current.isDate(date, inSameDayAs: now())
        }
        return false
    }
    private func markDisplayedSourceMove(nodeID: Int) {
        guard let record = sourceRecord, record.nodes.indices.contains(nodeID),
              let parent = record.nodes[nodeID].parentID else { return }
        markDisplayedCheckpoints { $0.anchorNodeID == parent }
    }
    private func markDisplayedEngineMove(from before: Position) {
        guard let record = sourceRecord else { return }
        let fen = before.fen
        markDisplayedCheckpoints { checkpoint in
            (try? replay(record: record, to: checkpoint.anchorNodeID).fen) == fen
        }
    }
    /// Only questions whose answer has actually been demonstrated are exposed.
    /// A source step uses its parent node; an engine step uses its before-FEN.
    /// Other, unvisited branches and other records retain their own evidence.
    private func markDisplayedCheckpoints(_ includes: (BookCourseCheckpoint) -> Bool) {
        guard let selectedUnit, let catalog else { return }
        var sources: [String: BookStudySource] = [:]
        for unit in catalog.units where unit.sourceHash == selectedUnit.sourceHash && unit.recordID == selectedUnit.recordID {
            for checkpoint in unit.checkpoints where includes(checkpoint) {
                let source = BookStudySource(bookSHA: unit.sourceHash, recordID: unit.recordID,
                    nodeID: checkpoint.anchorNodeID, title: unit.title + " · " + checkpoint.title)
                sources[source.key] = source
            }
        }
        if !sources.isEmpty { store.markBookSourcesExposed(Array(sources.values), now: now()) }
    }
    private func markAssisted() {
        guard let source = currentSource else { return }
        store.markExposed(source.lessonID, source.lineID, assisted: true, now: now())
        if !runFinished { wasRetry = true; wasUnseen = false }
        if let id = activeReviewID { store.markReviewAssisted(id, now: now()) }
    }
    private func sourceMatch(_ move: Move) -> BookReferenceMatch {
        if referenceMove == move { return .mainline }
        guard let checkpoint, let record = sourceRecord, record.nodes.indices.contains(checkpoint.anchorNodeID) else { return .offBook }
        return record.nodes[checkpoint.anchorNodeID].childIDs.contains {
            record.nodes.indices.contains($0) && record.nodes[$0].uci == move.uci
        } ? .branch : .offBook
    }
    private func clearBoardSelection() { selected = nil; targets = [] }
    private func preserveAbandonedAttempt() {
        // Navigating away and reopening must not erase a submitted attempt.
        // A same-move reassessment is distinct and does not use this path.
        if !runFinished, attemptedMove != nil { markAssisted() }
    }
    private func invalidateOperation() {
        token = UUID(); operation?.cancel(); operation = nil
        if isThinking { coach.cancel() }; isThinking = false
    }
    private func saveResume() {
        guard let source = currentSource, let unit = selectedUnit else { return }
        store.setBookResume(BookPracticeResume(source: source, unitID: unit.id, checkpointIndex: checkpointIndex,
            stage: stage.rawValue, positionFEN: position.fen, studentSide: studentSide,
            attemptedMove: attemptedMove?.uci, hintLevel: hintLevel, hints: runHints, errors: runErrors,
            wasRetry: wasRetry, runID: runID, started: started, wasUnseen: wasUnseen, lastMove: lastMove?.uci,
            completedCheckpointIDs: completedCheckpointIDs.sorted()))
    }
    private func replay(record: BookRecord, to nodeID: Int) throws -> Position {
        guard record.nodes.indices.contains(nodeID) else { throw StudyError.invalidContent("原谱节点已不存在。") }
        var path: [Int] = []; var cursor: Int? = nodeID; var visited = Set<Int>()
        while let current = cursor {
            guard record.nodes.indices.contains(current), visited.insert(current).inserted else {
                throw StudyError.invalidContent("原谱节点路径不完整。")
            }
            path.append(current); cursor = record.nodes[current].parentID
        }
        guard path.last == record.rootNodeID else { throw StudyError.invalidContent("原谱节点不属于此篇起点。") }
        var result = record.rawPosition; try result.validate()
        for id in path.reversed().dropFirst() {
            guard let move = record.nodes[id].uci.flatMap(Move.init(uci:)) else { throw StudyError.invalidContent("原谱着法无法识别。") }
            result = try result.applying(move: move)
        }
        return result
    }
}
