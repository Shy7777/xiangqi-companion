import Foundation
import Combine

enum LearningPage: String, CaseIterable, Identifiable {
    case home, courses, study, review, sparring, progress, resources
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "今日学习"
        case .courses: return "课程与棋谱"
        case .study: return "学习棋盘"
        case .review: return "错题与复习"
        case .sparring: return "实战陪练"
        case .progress: return "能力与记录"
        case .resources: return "资料与使用"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "sun.max"
        case .courses: return "books.vertical"
        case .study: return "square.grid.3x3"
        case .review: return "arrow.counterclockwise"
        case .sparring: return "person.2"
        case .progress: return "chart.bar"
        case .resources: return "info.circle"
        }
    }
}

struct StudyTarget: Identifiable {
    var id: String { LearningStore.key(lesson.id, line.id) }
    let lesson: LearningLesson
    let line: StudyLine
}

enum StudyInteractionPhase: Equatable {
    case unavailable, demonstration, studentTurn, awaitingOpponent, analyzing, moveFeedback, completed

    var title: String {
        switch self {
        case .unavailable: return "请选择练习"
        case .demonstration: return "演示中"
        case .studentTurn: return "轮到你"
        case .awaitingOpponent: return "待看对方应招"
        case .analyzing: return "引擎计算中"
        case .moveFeedback: return "变招反馈"
        case .completed: return "本轮已完成"
        }
    }
}

@MainActor
final class LearningModel: ObservableObject {
    @Published var page: LearningPage = .home
    @Published var lessonID: String?
    @Published var lineID: String?
    @Published var mode: StudyMode = .demonstration
    @Published var position = Position.initial
    @Published var cursor = 0
    @Published var selected: Square?
    @Published var targets: [Square] = []
    @Published var flipped = false
    @Published var hintLevel = 0
    @Published var feedbackTitle = "先选择一课"
    @Published var feedbackBody = "从看懂威胁开始，每次只练一个明确目标。"
    @Published var feedbackKind = "info"
    @Published var completed = false
    @Published var awaitingContinue = false
    @Published var busy = false
    @Published var studySubmission: StudySubmission?
    @Published var lastAssessment: MoveAssessment?
    @Published var activeReview: ReviewItem?
    @Published var game: TrainingGame?
    @Published var gamePositions: [Position] = []
    @Published var gameReviewCursor: Int?
    @Published var playerSide: Side = .red
    @Published var opponentLevel = 1
    @Published var gameHints = false
    @Published var gameAnalysis: [EngineLine] = []
    @Published var notice: String?
    @Published var query = ""
    @Published var stageFilter: LearningStage?
    @Published var onlyBookmarks = false
    @Published var onlySupplements = false
    @Published var courseDisplay: LearningCourseDisplay = .roadmap
    var useAuthoredCourses: Bool {
        get { courseDisplay == .authored }
        set { courseDisplay = newValue ? .authored : .positions }
    }
    @Published var librarySelectedEntryID: String?
    @Published var libraryBrowserPage = 0
    @Published var routeExampleIDs: [String]? = nil
    @Published var studyRouteID: String?
    var requestedJourneyPlanID: UUID?
    @Published var libraryCatalog = LibraryCourseCatalog.empty {
        didSet { roadmapEntryCache = [:]; readingCache.resetCatalog() }
    }
    let readingCache = LearningReadingCache()
    var roadmapEntryCache: [String: [LibraryCourseEntry]] = [:]
    @Published var librarySection: LibraryCourseSection? = .opening
    @Published var libraryGroupID: String?
    @Published var libraryQuery = ""
    @Published var libraryFamily: String?
    @Published var libraryRouteFilterID: String?
    @Published var libraryStatusFilter = 0
    @Published var libraryPreparing = false
    @Published var libraryPreparationMessage = ""
    var libraryOperation: Task<Void, Never>?
    var libraryToken = 0
    var libraryPlanIDs: [String] = []
    var libraryPlanMode: StudyMode = .practice
    @Published var queue: [StudyTarget] = []
    @Published var queuedReviews: [ReviewItem] = []
    var remainingPlanCount: Int { queuedReviews.count + queue.count }
    let store: LearningStore
    let coach: TrainingCoach
    private var sequence: [Position] = []
    // Reuse the validated line rather than replaying every move on each redraw.
    var studyPositions: [Position] { sequence }
    private var runID = UUID()
    private var runStarted = Date()
    private var runHints = 0
    private var runErrors = 0
    private var runRetry = false
    private var wasUnseen = true
    private var retryPly: Int?
    private var token = 0
    private var operation: Task<Void, Never>?
    private var pendingMove: Move?
    private var previewingReply = false
    private var previewLastMove: Move?
    var isShowingReplyPreview: Bool { previewingReply }
    var currentRunUsedHelp: Bool { runHints > 0 || runErrors > 0 || runRetry || mode == .demonstration }
    var currentRunIdentity: UUID { runID }
    var currentRunStatistics: (hints: Int, errors: Int) { (runHints, runErrors) }
    var studyDecisionProgress: (completed: Int, total: Int) {
        if activeReview != nil { return (completed ? 1 : 0, 1) }
        return (completedCheckpointPlies.count, checkpointCount)
    }
    private var queuedMode: StudyMode = .practice
    private var completedCheckpointPlies = Set<Int>()
    private var checkpointAccepted = false
    private var checkpointHintMove: Move?

    init(store: LearningStore? = nil, coach: TrainingCoach? = nil) {
        self.store = store ?? LearningStore()
        self.coach = coach ?? TrainingCoach()
    }

    static let builtInLessons: [LearningLesson] = TextbookCurriculum.lessons + SystematicCurriculum.lessons
        + OpeningRepertoireCurriculum.lessons + MiddlegameAtlasCurriculum.lessons + EndgameSchoolCurriculum.lessons
        + PracticeCurriculum.lessons + OpeningCurriculum.lessons
    static let builtInSources: [LearningSource] = TextbookCurriculum.sources + ProfessionalResources.sources
        + SystematicCurriculum.sources + OpeningRepertoireCurriculum.sources + EndgameSchoolCurriculum.sources
        + PracticeCurriculum.sources + OpeningCurriculum.sources
    private static let guidedLessonOrder: [String: Int] = {
        var order: [String: Int] = [:]
        for (index, id) in GuidedCurriculum.chapters.flatMap(\.lessonIDs).enumerated() where order[id] == nil {
            order[id] = index
        }
        return order
    }()
    private var curriculumPresentation: LearningReadingCache.Curriculum {
        readingCache.curriculum(revision: store.readingRevision) {
        let lessons = (Self.builtInLessons + store.data.importedLessons + (store.data.libraryStudy.map { [$0.lesson] } ?? [])).sorted {
            let a = LearningStage.allCases.firstIndex(of: $0.stage)!, b = LearningStage.allCases.firstIndex(of: $1.stage)!
            return a == b ? $0.order < $1.order : a < b
        }
        var seen = Set<String>()
        let sources = (Self.builtInSources + store.data.importedSources + (store.data.libraryStudy.map { [$0.source] } ?? [])).filter { seen.insert($0.id).inserted }
        let catalog = lessons.filter { !$0.id.hasPrefix("library-") }, systematic = catalog.filter(\.isSystematic)
        // The chapter route also governs nextTarget and daily plans. Numeric content
        // order remains a stable fallback for imported/unmapped systematic courses.
        let recommended = systematic.isEmpty ? catalog : systematic.sorted {
            let left = Self.guidedLessonOrder[$0.id] ?? Int.max
            let right = Self.guidedLessonOrder[$1.id] ?? Int.max
            if left != right { return left < right }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
        return .init(lessons: lessons, sources: sources, recommended: recommended)
        }
    }
    var lessons: [LearningLesson] { curriculumPresentation.lessons }
    var sources: [LearningSource] { curriculumPresentation.sources }
    var recommendedLessons: [LearningLesson] { curriculumPresentation.recommended }
    var lesson: LearningLesson? { lessonID.flatMap { curriculumPresentation.lessonByID[$0] } }
    var line: StudyLine? { lesson?.lines.first { $0.id == lineID } }
    var filteredLessons: [LearningLesson] {
        let terms = ChineseDisplayText.searchTerms(query)
        return (onlySupplements ? lessons.filter { !$0.isSystematic } : recommendedLessons).filter { item in
            (routeExampleIDs == nil || routeExampleIDs!.contains(item.id)) &&
            (stageFilter == nil || item.stage == stageFilter)
            && (!onlyBookmarks || store.data.bookmarks.contains(item.id))
            && (terms.isEmpty || ChineseDisplayText.matches(normalizedText: ChineseDisplayText.searchKey(([item.title,item.summary,item.principle] + item.tags).joined(separator: " ")), terms: terms))
        }
    }
    var dueTargets: [StudyTarget] {
        recommendedLessons.flatMap { lesson in lesson.lines.compactMap { line in
            guard line.checkpoints?.isEmpty != true, let due = store.progress(lesson.id, line.id).nextReview, due <= Date() else { return nil }
            return StudyTarget(lesson: lesson, line: line)
        } }
    }
    var nextTarget: StudyTarget? {
        for lesson in recommendedLessons {
            if let line = lesson.lines.first(where: { $0.checkpoints?.isEmpty != true && store.progress(lesson.id, $0.id).completions == 0 }) {
                return StudyTarget(lesson: lesson, line: line)
            }
        }
        return recommendedLessons.lazy.compactMap { lesson in lesson.lines.first(where: { $0.checkpoints?.isEmpty != true }).map { StudyTarget(lesson: lesson, line: $0) } }.first
    }
    var dueReviews: [ReviewItem] { store.data.reviews.filter { !$0.resolved && $0.due <= Date() }.sorted { $0.due < $1.due } }
    var expectedMove: Move? {
        if let activeReview { return Move(uci: activeReview.suggested) }
        guard let line, line.moves.indices.contains(cursor) else { return nil }
        return Move(uci: line.moves[cursor].uci)
    }
    var isCheckpointStudy: Bool { activeReview == nil && line?.checkpoints != nil }
    var currentCheckpoint: StudyCheckpoint? { line?.checkpoints?.first { $0.ply == cursor } }
    var checkpointIndex: Int? { line?.checkpoints?.firstIndex { $0.ply == cursor } }
    var checkpointCount: Int { line?.checkpoints?.count ?? 0 }
    var referenceContinuationNeeded: Bool { isCheckpointStudy && checkpointAccepted && !completed }
    var studyPhase: StudyInteractionPhase {
        guard page == .study, activeReview != nil || line != nil else { return .unavailable }
        if busy { return .analyzing }
        if completed { return .completed }
        if mode == .demonstration { return .demonstration }
        if pendingMove != nil { return .moveFeedback }
        if awaitingContinue { return .awaitingOpponent }
        if activeReview != nil || (isCheckpointStudy && currentCheckpoint != nil) || position.sideToMove == line?.studentSide { return .studentTurn }
        return .awaitingOpponent
    }
    /// A keyboard or single-button shortcut may advance presentation, never choose the student's move.
    @discardableResult
    func performPrimaryStudyAction() -> Bool {
        if referenceContinuationNeeded && !busy { continueStudy(); return true }
        switch studyPhase {
        case .demonstration: demoStep(1)
        case .awaitingOpponent: continueStudy()
        case .moveFeedback: retryStudy()
        case .unavailable, .studentTurn, .analyzing, .completed: return false
        }
        return true
    }
    var studyArrows: [RecommendationArrow] {
        guard !busy, !completed, pendingMove == nil, activeReview == nil || hintLevel >= 3,
              mode == .demonstration || hintLevel >= 3, let move = expectedMove else { return [] }
        if isCheckpointStudy && mode != .demonstration {
            return checkpointHintMove.map { [RecommendationArrow(rank: 1, move: $0)] } ?? []
        }
        return [RecommendationArrow(rank: 1, move: move)]
    }
    var lastMove: Move? {
        if previewingReply { return previewLastMove }
        if let pendingMove { return pendingMove }
        guard let line, cursor > 0, line.moves.indices.contains(cursor - 1) else { return nil }
        return Move(uci: line.moves[cursor - 1].uci)
    }
    var submittedStudyMove: Move? { pendingMove }
    var studyPrompt: String {
        if activeReview != nil { return "先独立处理这个曾经出错的局面。" }
        guard let line else { return "选择一课开始。" }
        if completed { return "分支已完成。换一个应对，检查你是否真的能变通。" }
        if mode == .demonstration { return "看每一步的目的；点击下一步观察局面怎样变化。" }
        if let checkpoint = currentCheckpoint { return checkpoint.prompt }
        return position.sideToMove == line.studentSide ? "轮到你（\(line.studentSide.label)）。先看威胁，再选走法。" : "观察对手的回应，再调整你的计划。"
    }

    private func markPendingStudyRetry() {
        guard !completed, pendingMove != nil, !referenceContinuationNeeded else { return }
        // Returning to the course after evaluated feedback is another attempt,
        // even when the alternative was reasonable rather than a mistake.
        runRetry = true
        retryPly = cursor
        persistLibraryAssistance()
    }

    func navigate(_ destination: LearningPage) {
        if [.home, .courses, .resources, .review, .progress].contains(destination) {
            let currentCleanCheck = !completed && !currentRunUsedHelp && (mode == .test || activeReview != nil)
            let savedCleanCheck = store.data.resume.map { saved in
                saved.mode == .test && !saved.wasRetry && saved.hints == 0 && saved.errors == 0
                    && !store.data.runs.contains(where: { $0.id == saved.runID })
            } ?? false
            if recordMaterialExposure(), currentCleanCheck || savedCleanCheck {
                notice = "检验期间查看课程、复习记录或资料可能透露题型与思路，本轮已记为含辅助；返回后仍可继续练习，但不计独立通过。"
            }
        }
        if page == .study {
            markPendingStudyRetry()
            saveResume()
        }
        cancelOperation()
        selected = nil; targets = []
        if destination == .study {
            markPendingStudyRetry()
            if let activeReview { position = (try? Position(fen: activeReview.fen)) ?? position }
            else if sequence.indices.contains(cursor) {
                position = sequence[cursor]
                if referenceContinuationNeeded, let move = pendingMove { position = (try? position.applying(move: move)) ?? position }
            }
            if !referenceContinuationNeeded { pendingMove = nil; lastAssessment = nil }
            previewingReply = false; checkpointHintMove = nil
            feedbackTitle = completed ? "本轮已经完成" : activeReview == nil ? mode.title : "继续错题练习"
            feedbackBody = referenceContinuationNeeded ? "这道关键点已经作答并记录。继续时会明确切回\(referenceLineName)，再到下一关键点。" : completed ? "可以换一个应对继续练习，或到期后再做无提示检验。" : "已恢复学习棋面，本轮提示、错误与重试记录继续保留。"
            feedbackKind = completed ? "complete" : "info"
        } else if destination == .sparring, let last = gamePositions.last {
            position = last
            feedbackTitle = gameReviewCursor == nil ? "继续练习对局" : "对局复盘"
            feedbackBody = gameReviewCursor == nil ? "已恢复对局末尾。重新检查当前威胁；需要时可分析当前局面。" : "正在回看历史棋面；点击分析可获得这个局面的候选，不沿用课程评语。"
            feedbackKind = "info"
        }
        page = destination
        if destination == .study { saveResume() }
    }
    func cancelOperation() {
        studySubmission = nil
        libraryToken += 1; libraryOperation?.cancel(); libraryOperation = nil; libraryPreparing = false
        token += 1; operation?.cancel(); operation = nil; coach.cancel(); busy = false
    }
    func stopCalculation() {
        cancelOperation()
        feedbackTitle = "已停止本次计算"
        feedbackBody = page == .sparring ? "已经录入的走子保留；轮到引擎时可点击继续应招。" : "本次未完成的评价不计对错。你可以重新尝试。"
        feedbackKind = "info"
    }
    func suspend() { saveResume(); cancelOperation(); store.save() }
    func shutdown() { suspend(); coach.shutdown() }

    func startLesson(_ lesson: LearningLesson, line chosen: StudyLine? = nil, mode: StudyMode = .demonstration,
                     from ply: Int = 0, restoring: StudyResume? = nil, routeID: String? = nil,
                     detachedFromJourney: Bool = false) {
        let requestedPlan = requestedJourneyPlanID
        requestedJourneyPlanID = nil
        let previousJourney = !detachedFromJourney && isJourneyStudy
        guard let chosen = chosen ?? lesson.lines.first else { return }
        guard lesson.lines.contains(chosen) else {
            notice = "独立变式不能注册为原课分支；请使用变式预览，或从该局面开启陪练。"
            return
        }
        let contextID = routeID ?? restoring?.routeID
            ?? ((requestedPlan != nil || previousJourney) ? journeyPlan?.routeID : nil)
            ?? ((lessonID == lesson.id) ? studyRouteID : nil)
        let resolvedRoute = routeContainingTarget(routeID: contextID, lessonID: lesson.id, lineID: chosen.id)
        let sameUnfinished = !completed && lessonID == lesson.id && lineID == chosen.id
        let carryAssistance = sameUnfinished && (self.mode == .demonstration || runHints > 0 || runErrors > 0 || runRetry || pendingMove != nil)
        let saved = store.data.resume
        let carrySaved = saved?.lessonID == lesson.id && saved?.lineID == chosen.id
            && (saved?.mode == .demonstration || (saved?.hints ?? 0) > 0 || (saved?.errors ?? 0) > 0 || saved?.wasRetry == true)
        do {
            let positions = try chosen.positions()
            // Empty checkpoints mean a reading-only game, never an empty successful test.
            let effectiveMode: StudyMode = chosen.checkpoints?.isEmpty == true ? .demonstration : mode
            var validResume = restoring
            if let saved = restoring, chosen.checkpoints != nil {
                let declared = Set(chosen.checkpoints!.map(\.ply))
                let answered = Set(saved.completedCheckpoints ?? [])
                let prior = Set(declared.filter { $0 < saved.cursor })
                let accepted = saved.acceptedCheckpoint
                let acceptedMove = saved.checkpointMove.flatMap(Move.init(uci:))
                let valid = saved.contentFingerprint == chosen.contentFingerprint
                    && answered.count == (saved.completedCheckpoints ?? []).count
                    && answered.isSubset(of: declared) && (saved.mode == .demonstration || saved.wasRetry || prior.isSubset(of: answered))
                    && answered.allSatisfy { $0 < saved.cursor || $0 == accepted }
                    && (accepted == nil ? saved.checkpointMove == nil :
                        accepted == saved.cursor && answered.contains(saved.cursor) && acceptedMove != nil &&
                        positions.indices.contains(saved.cursor) && (try? positions[saved.cursor].applying(move: acceptedMove!)) != nil)
                if !valid {
                    validResume = nil
                    notice = "课程内容或恢复信息已变化，已从起点重新开始；不会把未核验的关键点计为独立完成。"
                }
            }
            cancelOperation()
            self.lessonID = lesson.id; self.lineID = chosen.id; self.mode = effectiveMode
            studyRouteID = resolvedRoute?.id
            sequence = positions; cursor = restoring != nil && validResume == nil ? 0 : min(max(0, ply), chosen.moves.count)
            position = positions[cursor]; selected = nil; targets = []
            activeReview = nil; pendingMove = nil; lastAssessment = nil; previewingReply = false
            completedCheckpointPlies = []; checkpointAccepted = false; checkpointHintMove = nil
            completed = false; awaitingContinue = false; hintLevel = 0
            runID = UUID(); runStarted = Date(); runHints = 0; runErrors = 0
            let recentlyAssisted = store.recentlyAssisted(lessonID: lesson.id, lineID: chosen.id)
            runRetry = ply > 0 || carryAssistance || carrySaved || recentlyAssisted || (restoring != nil && validResume == nil); retryPly = nil
            wasUnseen = !store.data.exposedLines.contains(LearningStore.key(lesson.id, chosen.id))
            if let saved = validResume {
                runID = saved.runID; runStarted = saved.started; runHints = saved.hints; runErrors = saved.errors
                runRetry = saved.wasRetry || recentlyAssisted; wasUnseen = saved.wasUnseen
                completedCheckpointPlies = Set(saved.completedCheckpoints ?? [])
                if let accepted = saved.acceptedCheckpoint, accepted == cursor,
                   let move = saved.checkpointMove.flatMap(Move.init(uci:)), let after = try? position.applying(move: move) {
                    checkpointAccepted = true; awaitingContinue = true; pendingMove = move; position = after
                }
            } else { store.markExposed(lesson.id, chosen.id, assisted: effectiveMode == .demonstration) }
            feedbackKind = "info"; feedbackTitle = effectiveMode.title
            feedbackBody = effectiveMode == .test
                ? (chosen.checkpoints == nil ? "请独立作答；按谱匹配与变招的引擎评价会分开说明。" : "请独立作答；参考走法不是唯一答案，各关键点会由本地引擎核验。")
                : chosen.intent
            flipped = chosen.studentSide == .black; page = .study
            if effectiveMode != .demonstration && !checkpointAccepted { advanceOpponent() }
            if checkpointAccepted { flipped = positions[cursor].sideToMove == .black }
            bindJourneyRun(requested: requestedPlan, continuing: previousJourney || (restoring.map { $0.runID == journeyPlan?.activeRunID } ?? false))
            saveResume()
        } catch { notice = error.localizedDescription }
    }
    func resumeStudy() {
        guard let saved = store.data.resume, let lesson = lessons.first(where: { $0.id == saved.lessonID }),
              let line = lesson.lines.first(where: { $0.id == saved.lineID }) else { return }
        if let cached = store.data.libraryStudy, lesson.id == cached.lesson.id {
            libraryGroupID = cached.groupID; librarySection = .section(for: cached.groupID)
            libraryQuery = ""; libraryFamily = nil; libraryStatusFilter = 0; useAuthoredCourses = false
        }
        startLesson(lesson, line: line, mode: saved.mode, from: saved.cursor, restoring: saved)
        if !completed, referenceContinuationNeeded {
            feedbackTitle = "这题已作答"
            feedbackBody = "继续\(referenceLineName)会前往下一关键点；也可以沿自己的变招陪练。"
        } else if !completed, mode == .demonstration, line.moves.indices.contains(cursor - 1) {
            feedbackBody = line.moves[cursor - 1].explanation
        }
        saveResume()
    }
    func saveResume() {
        guard page == .study, activeReview == nil, !completed, let lessonID, let lineID else { return }
        store.setResume(StudyResume(lessonID: lessonID, lineID: lineID, mode: mode, cursor: cursor,
                                   hints: runHints, errors: runErrors, wasRetry: runRetry || (pendingMove != nil && !referenceContinuationNeeded), runID: runID,
                                   started: runStarted, wasUnseen: wasUnseen,
                                   completedCheckpoints: isCheckpointStudy ? completedCheckpointPlies.sorted() : nil,
                                   acceptedCheckpoint: referenceContinuationNeeded ? cursor : nil,
                                   checkpointMove: referenceContinuationNeeded ? pendingMove?.uci : nil,
                                   contentFingerprint: isCheckpointStudy ? line?.contentFingerprint : nil,
                                   routeID: currentStudyRoute?.id))
    }
    func switchMode(_ newMode: StudyMode) {
        guard let lesson, let line else { return }
        startLesson(lesson, line: line, mode: newMode)
    }
    func nextVariation() {
        guard let lesson, let line, let index = lesson.lines.firstIndex(where: { $0.id == line.id }) else { return }
        startLesson(lesson, line: lesson.lines[(index + 1) % lesson.lines.count], mode: mode == .demonstration ? .practice : mode)
    }
    /// Uses existing per-line progress and assessment, never a separate book-completion flag.
    func startTopicCheck(lessonIDs: [String]) {
        let included = Set(lessonIDs)
        let candidates = lessons.filter { included.contains($0.id) }.flatMap { lesson in
            lesson.lines.filter { !$0.moves.isEmpty && $0.checkpoints?.isEmpty == false }
                .map { StudyTarget(lesson: lesson, line: $0) }
        }
        guard !candidates.isEmpty else { notice = "这个主题暂时没有可检验的线路。"; return }
        var seenPositions = Set<String>()
        queue = Array(candidates.shuffled().filter {
            let identity = (try? Position(fen: $0.line.startingFEN).fen) ?? $0.line.startingFEN
            return seenPositions.insert(identity).inserted
        }.prefix(5))
        queuedMode = .test; queuedReviews = []
        nextQueued()
    }
    func startDailyPlan(diagnostic: Bool = false) {
        var list: [StudyTarget] = []
        queuedMode = diagnostic ? .test : .practice
        var seenReviews = Set<String>()
        queuedReviews = diagnostic ? [] : Array(dueReviews.filter {
            seenReviews.insert($0.fen + " " + $0.suggested).inserted
        }.prefix(2))
        if diagnostic {
            var seenStages = Set<LearningStage>()
            for lesson in recommendedLessons {
                guard !seenStages.contains(lesson.stage), let line = lesson.lines.last(where: { $0.checkpoints?.isEmpty != true }) else { continue }
                seenStages.insert(lesson.stage)
                list.append(StudyTarget(lesson: lesson, line: line))
            }
        } else {
            list += dueTargets.prefix(2)
            if let next = nextTarget, !list.contains(where: { $0.id == next.id }) { list.append(next) }
            if store.data.dailyMinutes >= 20, let next = nextTarget, let variant = next.lesson.lines.last,
               !list.contains(where: { $0.line.id == variant.id && $0.lesson.id == next.lesson.id }) {
                list.append(StudyTarget(lesson: next.lesson, line: variant))
            }
            if store.data.dailyMinutes >= 30 {
                list += recommendedLessons.filter { $0.stage == .tactics || $0.stage == .endgame }.prefix(2).compactMap { lesson in
                    lesson.lines.first.map { StudyTarget(lesson: lesson, line: $0) }
                }
            }
        }
        var seenCourses = Set<String>()
        queue = list.filter { seenCourses.insert($0.id).inserted }
        nextQueued()
    }
    func nextQueued(mode: StudyMode? = nil) {
        if let mode { queuedMode = mode }
        if !queuedReviews.isEmpty {
            let item = queuedReviews.removeFirst()
            startReview(item)
            return
        }
        guard !queue.isEmpty else { return }
        let target = queue.removeFirst()
        startLesson(target.lesson, line: target.line, mode: queuedMode)
    }

    func demoStep(_ delta: Int) {
        let (target, overflow) = cursor.addingReportingOverflow(delta)
        goToDemoPly(overflow ? (delta >= 0 ? Int.max : Int.min) : target)
    }
    func goToDemoPly(_ ply: Int) {
        guard page == .study, mode == .demonstration, !busy, activeReview == nil, let line,
              sequence.count == line.moves.count + 1 else { return }
        cursor = min(max(0, ply), line.moves.count); position = sequence[cursor]
        selected = nil; targets = []; pendingMove = nil; checkpointAccepted = false; checkpointHintMove = nil
        if let lessonID, let lineID { store.markExposed(lessonID, lineID, assisted: true) }
        feedbackTitle = cursor == 0 ? "先看目标，再看走法" : "第 \(cursor) 步 · \(sequence[cursor - 1].notation(for: Move(uci: line.moves[cursor - 1].uci)!))"
        feedbackBody = cursor == 0 ? line.intent : line.moves[cursor - 1].explanation.isEmpty ? "这一步来自\(referenceLineName)。到关键局面时，再暂停比较不同走法。" : line.moves[cursor - 1].explanation
        feedbackKind = "info"
        if cursor == line.moves.count { finishStudy() } else { completed = false; saveResume() }
    }
    func hint() {
        guard page == .study, mode != .test, !busy, !completed, pendingMove == nil else { return }
        hintLevel = min(3, hintLevel + 1); runHints += 1
        if let activeReview { store.markReviewAssisted(activeReview.id) }
        if let lessonID, let lineID { store.markExposed(lessonID, lineID, assisted: true) }
        feedbackTitle = "提示 \(hintLevel) / 3"
        if isCheckpointStudy, let checkpoint = currentCheckpoint {
            feedbackKind = "hint"
            if hintLevel == 1 { feedbackBody = checkpoint.focus }
            else if hintLevel == 2 { feedbackBody = "先选两个合法候选，分别算对方最直接的将军、吃子或反击，再比较走后局面。参考着法不一定最好。" }
            else {
                let before = position, currentToken = token
                busy = true; feedbackBody = "正在计算这个局面的候选，不把参考着法直接当作答案。"
                operation = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let rows = try await self.coach.evaluate(position: before, movetime: 900)
                        guard self.token == currentToken, !Task.isCancelled, self.position == before else { return }
                        self.busy = false
                        self.checkpointHintMove = rows.first?.pv.first.flatMap(Move.init(uci:))
                        self.feedbackBody = self.checkpointHintMove.map { "本次限时分析可以考虑 \(before.notation(for: $0))。这是引擎候选，不是唯一答案；本轮已经记为使用帮助。" } ?? "本次没有得到可用候选，可以稍后重试。"
                    } catch {
                        guard self.token == currentToken else { return }
                        self.busy = false; self.feedbackBody = error.localizedDescription
                    }
                }
            }
            saveResume(); return
        }
        if hintLevel == 1 {
            feedbackBody = activeReview != nil ? "先看有没有必须处理的将军、吃子或直接威胁。" : (line?.moves.indices.contains(cursor) == true ? line!.moves[cursor].hint : "先看当前目标。")
        } else if hintLevel == 2, let move = expectedMove, let piece = position[move.from] {
            feedbackBody = "重点考虑\(piece.side.label)的\(piece.symbol)。它怎样走，能同时处理威胁并推进目标？"
        } else if let move = expectedMove {
            feedbackBody = "可以尝试 \(position.notation(for: move))。看过答案后，请回到这里再无提示重走。"
        }
        feedbackKind = "hint"; saveResume()
    }
    func tap(_ square: Square) {
        guard !busy else { return }
        if page == .sparring {
            guard gameReviewCursor == nil, let game, game.result == nil, position.sideToMove == game.player else { return }
        } else {
            guard page == .study, mode != .demonstration, !completed, !awaitingContinue, pendingMove == nil else { return }
            if activeReview == nil {
                if isCheckpointStudy { guard currentCheckpoint != nil else { return } }
                else if position.sideToMove != line?.studentSide { return }
            }
        }
        if let from = selected, targets.contains(square) {
            let move = Move(from: from, to: square); selected = nil; targets = []
            if page == .sparring { playHuman(move) } else { attempt(move) }
        } else if square == selected { selected = nil; targets = [] }
        else if let piece = position[square], piece.side == position.sideToMove {
            selected = square; targets = position.legalMoves(from: square).map(\.to)
        } else if let from = selected {
            do { _ = try position.applying(move: Move(from: from, to: square)) }
            catch {
                feedbackTitle = "这个位置不能落子"
                feedbackBody = "\(error.localizedDescription)。棋盘上的小圆点是这枚子的合法落点；这次不记为战术错误。"
                feedbackKind = "info"
            }
        } else { selected = nil; targets = [] }
    }
    func attempt(_ move: Move) {
        guard page == .study, mode != .demonstration, !busy, !completed, !awaitingContinue, pendingMove == nil,
              (try? position.applying(move: move)) != nil else { return }
        if isCheckpointStudy {
            guard currentCheckpoint != nil else { return }
            assessStudyMove(move); return
        }
        if activeReview == nil, let current = line, let lesson {
            if current.moves.indices.contains(cursor), current.moves[cursor].uci == move.uci { acceptCourseMove(move); return }
            // A learned branch may transpose only when its entire observed prefix matches.
            if let other = lesson.lines.first(where: {
                $0.startingFEN == current.startingFEN && $0.studentSide == current.studentSide
                && $0.moves.count > cursor && Array($0.moves.prefix(cursor).map(\.uci)) == Array(current.moves.prefix(cursor).map(\.uci))
                && $0.moves[cursor].uci == move.uci
            }), let positions = try? other.positions() {
                wasUnseen = wasUnseen && !store.data.exposedLines.contains(LearningStore.key(lesson.id, other.id))
                // Transposing into a recently assisted branch cannot reset the
                // no-help contract of the destination line.
                runRetry = runRetry || store.recentlyAssisted(lessonID: lesson.id, lineID: other.id)
                store.markExposed(lesson.id, other.id, assisted: false)
                lineID = other.id; sequence = positions; acceptCourseMove(move)
                feedbackTitle = "走进另一条合理分支"; return
            }
        }
        assessStudyMove(move)
    }
    private func record(_ move: Move, outcome: String) {
        store.recordDecision(StudyDecision(id: UUID(), date: Date(), lessonID: lessonID ?? "review",
                                           lineID: lineID ?? activeReview?.id.uuidString ?? "custom", ply: cursor,
                                           mode: mode, move: move.uci, outcome: outcome,
                                           hintLevel: hintLevel, wasRetry: retryPly == cursor))
    }
    private func acceptCourseMove(_ move: Move) {
        guard let line, line.moves.indices.contains(cursor), sequence.indices.contains(cursor + 1) else { return }
        record(move, outcome: "course")
        let explanation = line.moves[cursor].explanation
        cursor += 1; position = sequence[cursor]; hintLevel = 0; pendingMove = nil; selected = nil; targets = []
        feedbackTitle = "与参考谱一致"
        feedbackBody = mode == .test ? "已记录。继续观察对手下一步，不提前展示讲解。" : explanation
        feedbackKind = "correct"; awaitingContinue = true
        if cursor == line.moves.count { finishStudy() }
        saveResume()
    }
    func continueStudy() {
        guard page == .study, !busy, !completed else { return }
        if isCheckpointStudy {
            guard referenceContinuationNeeded, mode != .demonstration else { return }
            cursor += 1
            pendingMove = nil; lastAssessment = nil; checkpointAccepted = false; checkpointHintMove = nil
            previewingReply = false; selected = nil; targets = []; hintLevel = 0; awaitingContinue = false
            advanceToCheckpoint(); saveResume(); return
        }
        guard pendingMove == nil else { return }
        advanceOpponent(); awaitingContinue = false; saveResume()
    }
    private func advanceOpponent() {
        guard let line else { return }
        if isCheckpointStudy { advanceToCheckpoint(); return }
        if cursor < line.moves.count, position.sideToMove != line.studentSide {
            let index = cursor; cursor += 1; position = sequence[cursor]
            feedbackTitle = "对手已回应"
            feedbackBody = mode == .test ? "轮到你。重新检查对手刚才改变了什么。" : line.moves[index].explanation
            feedbackKind = "opponent"
        }
        if cursor >= line.moves.count { finishStudy() }
    }
    private func advanceToCheckpoint() {
        guard let line, let checkpoints = line.checkpoints, mode != .demonstration else { return }
        if let next = checkpoints.first(where: { $0.ply >= cursor && !completedCheckpointPlies.contains($0.ply) }) {
            cursor = next.ply; position = sequence[cursor]; flipped = position.sideToMove == .black
            // Keep assessment prompts neutral at the source: tooltips, detail
            // panels and accessibility read the same fields as the main card.
            feedbackTitle = mode == .test ? "独立检验" : next.title
            feedbackBody = mode == .test ? "请独立判断当前局面，并在棋盘上提交你的选择。" : next.prompt
            feedbackKind = "info"
            awaitingContinue = false
        } else {
            cursor = line.moves.count; position = sequence[cursor]
            if !Set(checkpoints.map(\.ply)).isSubset(of: completedCheckpointPlies) { runRetry = true }
            finishStudy()
        }
    }
    private func finishStudy() {
        guard let lessonID, let lineID else { return }
        completed = true; awaitingContinue = false
        store.finishRun(id: runID, lessonID: lessonID, lineID: lineID, mode: mode,
                        hints: runHints, errors: runErrors, wasRetry: runRetry, wasUnseen: wasUnseen)
        completeJourneyItem(runID: runID)
        feedbackTitle = mode == .demonstration ? "这一分支看完了" : "这一分支练完了"
        feedbackBody = mode == .demonstration ? "下一步先隐藏答案，自己走；演示完成不算独立掌握。" :
            "本轮提示 \(runHints) 次、关键偏差 \(runErrors) 次。\(mode == .test && runHints == 0 && runErrors == 0 && !runRetry ? "已记为无提示通过；隔日再测稳定性。" : "可以换应手再练，再安排无提示检验。")"
        feedbackKind = "complete"
    }
    private func assessStudyMove(_ move: Move, movetime: Int = 900) {
        let before = position; let currentToken = token; let originalPly = cursor
        studySubmission = StudySubmission(position: before, move: move)
        busy = true; feedbackTitle = isCheckpointStudy ? "正在核验关键点选择" : "正在检验你的变招"
        feedbackBody = "分别分析走前与走后局面，不按是否命中 Top 1 或参考着法判错。"
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let assessment = try await self.coach.assess(position: before, move: move, movetime: movetime)
                guard self.token == currentToken, !Task.isCancelled else { return }
                defer { self.studySubmission = nil }
                self.busy = false; self.lastAssessment = assessment
                let good = assessment.verdict == .exactBest || assessment.verdict == .good
                self.record(move, outcome: good ? "alternative" : assessment.verdict == .uncertain ? "uncertain" : "mistake")
                if let review = self.activeReview {
                    if good {
                        self.position = try before.applying(move: move); self.pendingMove = move
                        self.completed = true; self.feedbackKind = "complete"; self.feedbackTitle = "这次处理合理"
                        self.feedbackBody = assessment.detail + " 下次到期再独立处理，才会逐步移出错题。"
                        self.store.reviewCompleted(review.id, clean: self.runErrors == 0,
                                                   assisted: self.runHints > 0 || self.runRetry)
                        self.completeJourneyItem(runID: self.runID)
                        return
                    }
                }
                self.pendingMove = move; self.position = try before.applying(move: move)
                let matchesReference = self.activeReview == nil && self.line?.moves.indices.contains(originalPly) == true
                    && self.line?.moves[originalPly].uci == move.uci
                self.feedbackTitle = StudyReferenceFeedback.title(for: assessment, matchesReference: matchesReference)
                self.feedbackBody = matchesReference ? "你走的就是参考谱这一手。\n引擎复核：" + assessment.detail : assessment.detail
                if self.isCheckpointStudy, let checkpoint = self.currentCheckpoint, good {
                    self.completedCheckpointPlies.insert(originalPly); self.checkpointAccepted = true; self.awaitingContinue = true
                    let matches = self.line?.moves[originalPly].uci == move.uci
                    self.feedbackKind = matches ? "correct" : "alternative"
                    self.feedbackBody += matches ? " 你的选择与参考着法相同。" : " 你的选择与参考着法不同，但本次分析认为可以成立。"
                    self.feedbackBody += " 这道关键点已经记录。继续时会明确切回\(self.referenceLineName)，再到下一关键点。 " + checkpoint.explanation
                    self.saveResume(); return
                }
                if good {
                    self.feedbackKind = "alternative"
                    self.feedbackBody += " 这步不在当前教学路线内，不等于错。可从这里让引擎应招，也可回到课程主线。"
                } else if assessment.verdict == .uncertain {
                    self.feedbackKind = "uncertain"
                    self.feedbackBody += " 本次不计错；可以加深分析或回到原局面。"
                    if let review = self.activeReview { self.store.markReviewAssisted(review.id) }
                } else {
                    self.feedbackKind = "mistake"; self.runErrors += 1; self.retryPly = originalPly
                    self.runRetry = true
                    if let best = assessment.bestMove {
                        self.store.addReview(lessonID: self.lessonID, lineID: self.lineID,
                                             title: self.activeReview?.title ?? self.lesson?.title ?? "局面练习",
                                             fen: before.fen, attempted: move.uci, suggested: best.uci,
                                             detail: assessment.detail, replyPV: assessment.replyPV)
                    }
                    if let review = self.activeReview { self.store.reviewCompleted(review.id, clean: false) }
                    if let lessonID = self.lessonID, let lineID = self.lineID { self.store.markExposed(lessonID, lineID, assisted: true) }
                }
                self.saveResume()
            } catch {
                guard self.token == currentToken else { return }
                self.studySubmission = nil
                self.busy = false; self.feedbackKind = "uncertain"; self.feedbackTitle = "本次没有判分"
                self.feedbackBody = error.localizedDescription + " 可以重试，不会计为错误。"
            }
        }
    }
    private var studyRewindPly: Int? {
        guard let line, sequence.count == line.moves.count + 1 else { return nil }
        if mode == .demonstration { return cursor > 0 ? cursor - 1 : nil }
        if pendingMove != nil { return cursor }
        if let checkpoints = line.checkpoints {
            return checkpoints.map(\.ply).filter { $0 < cursor }.max()
        }
        return sequence.indices.reversed().first { $0 < cursor && sequence[$0].sideToMove == line.studentSide }
    }
    var canRewindStudy: Bool {
        page == .study && !busy && !libraryPreparing &&
            (activeReview != nil ? (hasPendingMove || completed) : studyRewindPly != nil)
    }
    var studyUndoTitle: String {
        if mode == .demonstration { return "上一步" }
        if mode == .test && !completed { return "悔棋并转练习" }
        if completed { return "重走最后一题" }
        if hasPendingMove || awaitingContinue { return "悔棋 · 重走此题" }
        return isCheckpointStudy ? "返回上一题" : "悔棋 · 返回上一步"
    }
    func rewindStudy() {
        guard canRewindStudy else { return }
        if mode == .demonstration { demoStep(-1); return }
        if let review = activeReview {
            if completed { startReview(review) }
            store.markReviewAssisted(review.id)
            mode = .practice
            retryStudy(); return
        }
        guard let target = studyRewindPly, let lesson, let line else { return }
        store.markExposed(lesson.id, line.id, assisted: true)
        if completed {
            // A completed score is immutable. Replay starts a separate assisted
            // run instead of reopening and awarding the old run twice.
            startLesson(lesson, line: line, mode: .practice, from: target)
            feedbackTitle = "重新练这一题"
            feedbackBody = "之前的完成记录保留。这次从上一处决策重新练，不计为新的独立通过。"
            return
        }
        cancelOperation()
        mode = .practice; cursor = target; position = sequence[target]
        pendingMove = nil; lastAssessment = nil; previewingReply = false
        selected = nil; targets = []; hintLevel = 0; checkpointHintMove = nil
        completedCheckpointPlies = completedCheckpointPlies.filter { $0 < target }
        checkpointAccepted = false; awaitingContinue = false; completed = false
        runRetry = true; retryPly = target
        flipped = isCheckpointStudy ? position.sideToMove == .black : line.studentSide == .black
        persistLibraryAssistance()
        feedbackTitle = "已悔棋，重新判断"
        feedbackBody = "已回到你落子前；现在是引导练习。原有评价和错误记录保留，重走不计独立通过。"
        feedbackKind = "info"; saveResume()
    }
    /// Explicitly asking for a teaching aid leaves no-hint mode at the same
    /// board, without resetting the run or discarding already recorded mistakes.
    func enterGuidedPractice() {
        guard page == .study else { return }
        cancelOperation()
        _ = recordMaterialExposure(lessonID: lessonID)
        runRetry = true; mode = .practice
        persistLibraryAssistance()
        if let activeReview { store.markReviewAssisted(activeReview.id) }
        if !completed && !hasPendingMove {
            feedbackTitle = "已转为引导练习"
            feedbackBody = "棋面和已有记录保留。现在可以看思路、请求提示或悔棋，本轮不计独立通过。"
            feedbackKind = "info"
        }
        saveResume()
    }
    func retryStudy() {
        let wasMistake = lastAssessment?.verdict == .mistake || lastAssessment?.verdict == .inaccuracy || feedbackKind == "mistake"
        cancelOperation()
        if let activeReview { position = (try? Position(fen: activeReview.fen)) ?? position }
        else if sequence.indices.contains(cursor) { position = sequence[cursor] }
        pendingMove = nil; selected = nil; targets = []; hintLevel = 0; previewingReply = false
        completedCheckpointPlies.remove(cursor); checkpointAccepted = false; checkpointHintMove = nil
        completed = false; awaitingContinue = false; lastAssessment = nil
        runRetry = true; retryPly = cursor
        persistLibraryAssistance()
        feedbackTitle = wasMistake ? "回到错误前，自己重走" : "回到原局面，再作判断"
        feedbackBody = wasMistake ? "这次已撤掉箭头。重试用于巩固，不会冲高独立通过率。" : "已撤掉箭头。可以重新判断，或沿课程继续；本轮重试不计为新的独立通过。"
        feedbackKind = "info"
        saveResume()
    }
    func showReply() {
        guard !previewingReply, let assessment = lastAssessment, pendingMove != nil else { return }
        var p = position
        previewLastMove = pendingMove
        for uci in assessment.replyPV.prefix(2) {
            guard let move = Move(uci: uci), let next = try? p.applying(move: move) else { break }
            p = next; previewLastMove = move
        }
        position = p; previewingReply = true; runHints += 1
        persistLibraryAssistance()
        if let activeReview { store.markReviewAssisted(activeReview.id) }
        feedbackTitle = "反击路线预览"
        feedbackBody = "这里只预览引擎给出的前两步回应。点击「回到原局面」再自己处理。"
        saveResume()
    }
    func deepenStudyAssessment() {
        guard !referenceContinuationNeeded, let move = pendingMove else { return }
        // This repeats a move after feedback was visible. Preserve that exposure
        // even if the deeper search is cancelled before a second verdict.
        markPendingStudyRetry()
        if let activeReview { store.markReviewAssisted(activeReview.id) }
        if let activeReview { position = (try? Position(fen: activeReview.fen)) ?? position }
        else if sequence.indices.contains(cursor) { position = sequence[cursor] }
        pendingMove = nil; previewingReply = false; assessStudyMove(move, movetime: 2500)
        saveResume()
    }
    var hasPendingMove: Bool { pendingMove != nil }

    func startReview(_ item: ReviewItem) {
        guard let p = try? Position(fen: item.fen) else { notice = "这条错题的棋局无法恢复。"; return }
        saveResume()
        cancelOperation(); page = .study; activeReview = item; lessonID = nil; lineID = nil
        mode = .practice; position = p; cursor = 0; hintLevel = 0; completed = false
        selected = nil; targets = []; pendingMove = nil; lastAssessment = nil; awaitingContinue = false; previewingReply = false
        runID = UUID(); runStarted = Date()
        runHints = 0; runErrors = 0
        let assisted = store.data.reviews.first(where: { $0.id == item.id })?.lastAssisted
        runRetry = assisted.map { Date().timeIntervalSince($0) < 20 * 3600 || Calendar.current.isDateInToday($0) } ?? false
        retryPly = nil; flipped = p.sideToMove == .black
        feedbackTitle = "\(item.title) · 错题重练"
        feedbackBody = "答案暂时隐藏。先处理原局面，再核对你是否改变了之前的判断。"; feedbackKind = "info"
    }

    func startGame(from start: Position = .initial, player: Side? = nil) {
        if page == .study { markPendingStudyRetry() }
        saveResume(); cancelOperation()
        if var prior = game, prior.result == nil, !prior.moves.isEmpty {
            prior.result = "开始另一盘前存档"; store.saveGame(prior)
        }
        let player = player ?? playerSide
        game = TrainingGame(id: UUID(), started: Date(), startFEN: start.fen, player: player, level: opponentLevel)
        position = start; gamePositions = [start]; gameReviewCursor = nil; playerSide = player
        flipped = player == .black; selected = nil; targets = []; lastAssessment = nil; gameAnalysis = []
        page = .sparring; feedbackTitle = "练习对局已开始"; feedbackKind = "info"
        feedbackBody = "你执\(player.label)。计算档位不是人类等级；对局可随时结束后复盘。"
        store.saveGame(game!)
        if start.legalMoves().isEmpty { finishGame("\(start.sideToMove.opponent.label)胜：对方无合法走法") }
        else if start.sideToMove != player { respondInGame() }
    }
    /// A read-only variation sheet owns its own positions and cursor. Opening it
    /// may mark exposure, but never changes the active board or manufactures a run.
    @discardableResult
    func recordVariationExposure(lessonID: String, lineID: String) -> Bool {
        guard let parent = lessons.first(where: { $0.id == lessonID })?.lines.first(where: { $0.id == lineID }),
              parent.variations?.isEmpty == false else { return false }
        store.markVariationExposed(lessonID, lineID)
        if self.lessonID == lessonID && self.lineID == lineID && !completed {
            runRetry = true
            saveResume()
        }
        return true
    }

    /// Called when course guidance or an original-source reader actually opens.
    /// Unknown course IDs fail before touching any current or saved session.
    @discardableResult
    func recordMaterialExposure(lessonID materialID: String? = nil) -> Bool {
        let material: LearningLesson?
        if let materialID {
            guard let found = lessons.first(where: { $0.id == materialID }) else { return false }
            material = found
        } else { material = nil }
        let currentLineExists = lesson != nil && line != nil
        let affectsCurrent = !completed && (activeReview != nil ||
            (currentLineExists && (mode == .test || (materialID != nil && self.lessonID == materialID))))
        var activeLine: (lessonID: String, lineID: String)?
        if affectsCurrent {
            objectWillChange.send()
            runRetry = true
            if let lessonID = self.lessonID, let lineID = self.lineID {
                activeLine = (lessonID, lineID)
            }
        }
        return store.markMaterialExposed(material, activeLine: activeLine,
                                         activeReviewID: affectsCurrent ? activeReview?.id : nil)
    }

    /// Explicitly starts a separate game from the displayed branch position.
    /// The original course remains resumable and receives no branch completion.
    @discardableResult
    func startVariationGame(lessonID: String, lineID: String, variationID: String, ply: Int = 0, player: Side? = nil) -> Bool {
        guard let parent = lessons.first(where: { $0.id == lessonID })?.lines.first(where: { $0.id == lineID }),
              let variation = parent.variations?.first(where: { $0.id == variationID }) else { return false }
        do {
            let positions = try variation.positions(parent: parent)
            guard positions.indices.contains(ply) else { throw StudyError.invalidContent("变式预览位置越界。") }
            _ = recordVariationExposure(lessonID: lessonID, lineID: lineID)
            let start = positions[ply]
            startGame(from: start, player: player ?? start.sideToMove)
            if game?.result == nil {
                feedbackBody = "从已经展示的教材变式开始独立陪练；不把这次练习计为原谱完成或无提示成绩。你执\(game!.player.label)。"
            }
            return true
        } catch { notice = error.localizedDescription; return false }
    }
    func continueBranchAsGame() {
        guard let line else { return }
        startGame(from: position, player: isCheckpointStudy && sequence.indices.contains(cursor) ? sequence[cursor].sideToMove : line.studentSide)
    }
    func resumeGame(_ saved: TrainingGame) {
        do {
            let positions = try saved.positions()
            cancelOperation(); game = saved; gamePositions = positions; position = positions.last!
            gameReviewCursor = saved.result == nil ? nil : saved.moves.count
            playerSide = saved.player; flipped = saved.player == .black; page = .sparring
            selected = nil; targets = []; lastAssessment = nil; gameAnalysis = []
            feedbackTitle = saved.result == nil ? "已恢复练习对局" : "对局复盘"
            feedbackBody = saved.result ?? "局面和走子历史已恢复。"; feedbackKind = "info"
            if saved.result == nil && position.legalMoves().isEmpty { finishGame("\(position.sideToMove.opponent.label)胜：对方无合法走法") }
            else if saved.result == nil && position.sideToMove != saved.player { respondInGame() }
        } catch { notice = error.localizedDescription }
    }
    private func playHuman(_ move: Move) {
        guard var current = game, current.result == nil, position.sideToMove == current.player,
              let after = try? position.applying(move: move) else { return }
        let before = position
        current.moves.append(move.uci); game = current; position = after; gamePositions.append(after)
        gameAnalysis = []; store.saveGame(current)
        busy = true; let currentToken = token; let ply = current.moves.count
        feedbackTitle = "已走 \(before.notation(for: move))"; feedbackBody = "正在核对这一步，然后由本地引擎应招。"
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let assessment = try await self.coach.assess(position: before, move: move, movetime: 700)
                guard self.token == currentToken, !Task.isCancelled else { return }
                self.lastAssessment = assessment
                let record = GameMoveReview(ply: ply, fen: before.fen, move: move.uci,
                                            bestMove: assessment.bestMove?.uci, verdict: assessment.verdict.rawValue,
                                            detail: assessment.detail, lossCP: assessment.lossCP,
                                            bestPV: assessment.bestPV, replyPV: assessment.replyPV)
                self.game?.reviews.append(record)
                if assessment.verdict == .mistake || assessment.verdict == .inaccuracy, let best = assessment.bestMove {
                    self.store.addReview(lessonID: nil, lineID: nil, title: "实战第 \(ply) 步",
                                         fen: before.fen, attempted: move.uci, suggested: best.uci,
                                         detail: assessment.detail, replyPV: assessment.replyPV)
                }
                if let game = self.game { self.store.saveGame(game) }
                self.feedbackTitle = assessment.title; self.feedbackBody = assessment.detail
                try await self.performReply(token: currentToken)
            } catch {
                guard self.token == currentToken else { return }
                self.busy = false; self.feedbackTitle = "引擎暂时没有完成应招"
                self.feedbackBody = error.localizedDescription + " 走子已保存，可点击「继续应招」。"
            }
        }
    }
    func respondInGame() {
        guard let game, game.result == nil, position.sideToMove != game.player else { return }
        cancelOperation(); busy = true; let currentToken = token
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await self.performReply(token: currentToken) }
            catch {
                guard self.token == currentToken else { return }
                self.busy = false; self.feedbackTitle = "应招暂不可用"; self.feedbackBody = error.localizedDescription
            }
        }
    }
    private func performReply(token currentToken: Int) async throws {
        guard token == currentToken, !Task.isCancelled else { return }
        guard let current = game else { busy = false; return }
        if position.legalMoves().isEmpty { finishGame("\(position.sideToMove.opponent.label)胜：对方无合法走法"); return }
        let move = try await coach.chooseReply(position: position, level: current.level)
        guard token == currentToken, !Task.isCancelled else { return }
        guard let move else { busy = false; return }
        let next = try position.applying(move: move)
        game?.moves.append(move.uci); position = next; gamePositions.append(next); busy = false
        if next.legalMoves().isEmpty { finishGame("\(next.sideToMove.opponent.label)胜：对方无合法走法"); return }
        if let game { store.saveGame(game) }
        if gamePositions.filter({ $0 == next }).count >= 3 {
            feedbackTitle = "出现重复局面"
            feedbackBody = "本练习不作完整长将长捉裁决。可以换计划，或结束本盘复盘。"
        }
    }
    func finishGame(_ result: String = "主动结束练习") {
        cancelOperation(); game?.result = result
        if let game { store.saveGame(game); gameReviewCursor = game.moves.count }
        feedbackTitle = "进入复盘"; feedbackBody = result + "。逐步回看或直接重练下面标出的关键局面。"
    }
    func undoGame() {
        guard var game, game.result == nil, !game.moves.isEmpty else { return }
        cancelOperation()
        repeat {
            game.moves.removeLast()
            if game.moves.isEmpty { break }
        } while (gamePositions[game.moves.count].sideToMove != game.player)
        game.reviews.removeAll { $0.ply > game.moves.count }
        gamePositions = Array(gamePositions.prefix(game.moves.count + 1)); position = gamePositions.last!
        self.game = game; selected = nil; targets = []; lastAssessment = nil; gameAnalysis = []
        feedbackTitle = "已回到你上一步之前"; feedbackBody = "这次自己改变判断，再试一个走法。"
        store.saveGame(game)
        if position.sideToMove != game.player { respondInGame() }
    }
    func reviewGame(at index: Int) {
        guard gamePositions.indices.contains(index) else { return }
        cancelOperation(); gameReviewCursor = index; selected = nil; targets = []; gameAnalysis = []
        gameHints = false; lastAssessment = nil; feedbackKind = "info"
        if let review = game?.reviews.first(where: { $0.ply == index }) {
            feedbackTitle = "第 \(index) 步 · 你的走法回顾"
            feedbackBody = "以下评价针对你刚走的第 \(index) 步；棋盘显示走后局面。" + review.detail
        } else {
            feedbackTitle = index == 0 ? "复盘 · 初始局面" : "复盘第 \(index) 步"
            feedbackBody = "轮到\(gamePositions[index].sideToMove.label)行棋。" + (index == 0 ? "这里还没有走子评语。" : "这一步没有保存走法评语。")
        }
        feedbackBody += " “分析当前局面”给出的是眼前局面的候选。"
    }
    func returnToGame() {
        cancelOperation()
        gameReviewCursor = nil; selected = nil; targets = []; gameAnalysis = []
        gameHints = false; lastAssessment = nil; feedbackKind = "info"
        feedbackTitle = "已回到当前对局"
        feedbackBody = "棋盘已回到最新的第 \(game?.moves.count ?? 0) 步，轮到\(position.sideToMove.label)行棋。历史局面的分析已清除。"
        if let game, game.result == nil, position.sideToMove != game.player { respondInGame() }
    }
    var displayedGamePosition: Position {
        if let index = gameReviewCursor, gamePositions.indices.contains(index) { return gamePositions[index] }
        return position
    }
    func requestGameHint() {
        let p = displayedGamePosition; cancelOperation(); busy = true; let currentToken = token
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rows = try await self.coach.evaluate(position: p, movetime: 1200)
                guard self.token == currentToken, !Task.isCancelled, self.page == .sparring,
                      self.displayedGamePosition == p else { return }
                self.gameAnalysis = rows; self.gameHints = true; self.busy = false
            } catch {
                guard self.token == currentToken else { return }
                self.busy = false; self.notice = error.localizedDescription
            }
        }
    }
    func reviewGameMistake(_ item: GameMoveReview) {
        guard let best = item.bestMove else { return }
        if !store.data.reviews.contains(where: { $0.fen == item.fen && $0.suggested == best }) {
            store.addReview(lessonID: nil, lineID: nil, title: "实战第 \(item.ply) 步", fen: item.fen,
                            attempted: item.move, suggested: best, detail: item.detail, replyPV: item.replyPV)
        }
        if let review = store.data.reviews.first(where: { $0.fen == item.fen && $0.suggested == best }) { startReview(review) }
    }
    /// The UI chooses a file; this transition validates and commits before resetting any live state.
    @discardableResult
    func restoreLearningArchive(_ bytes: Data) throws -> URL? {
        guard bytes.count <= 8_000_000 else { throw StudyError.invalidContent("学习记录请控制在 8 MB 内。") }
        let backup = try store.restoreBackup(bytes, builtInIDs: Set(Self.builtInLessons.map(\.id)), builtInSources: Self.builtInSources)
        cancelOperation()
        lessonID = nil; lineID = nil; activeReview = nil; game = nil; gamePositions = []; gameReviewCursor = nil
        completedCheckpointPlies = []; checkpointAccepted = false; checkpointHintMove = nil
        sequence = []; queue = []; queuedReviews = []; queuedMode = .practice
        libraryPlanIDs = []; libraryPlanMode = .practice
        requestedJourneyPlanID = nil; routeExampleIDs = nil; studyRouteID = nil
        position = .initial; cursor = 0; selected = nil; targets = []
        completed = false; awaitingContinue = false; pendingMove = nil; lastAssessment = nil
        previewingReply = false; gameAnalysis = []; gameHints = false; page = .home
        return backup
    }
}
