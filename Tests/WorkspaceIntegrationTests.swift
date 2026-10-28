#if WORKSPACE_INTEGRATION_TESTS
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

/// Model-level seams used by the new workspace, without file panels, UI or engine searches.
@main @MainActor struct WorkspaceIntegrationTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw Failure(message: message) }; checks += 1
    }
    static func rejects(_ action: () throws -> Void) throws {
        do { try action() } catch { checks += 1; return }
        throw Failure(message: "Expected the operation to reject before mutation")
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    struct LiveSnapshot: Equatable {
        let archive: Data
        let position: Position
        let page: LearningPage
        let mode: StudyMode
        let lessonID: String?
        let lineID: String?
        let cursor: Int
        let busy: Bool
        let selected: Square?
        let targets: [Square]
        let hintLevel: Int
        let assistance: Bool
        let title: String
        let body: String
        let kind: String
        let completed: Bool
        let awaitingContinue: Bool
        let game: Data
        let queue: [String]
        let storeError: String?
        @MainActor init(_ model: LearningModel) throws {
            archive = try encode(model.store.data); position = model.position; page = model.page; mode = model.mode
            lessonID = model.lessonID; lineID = model.lineID; cursor = model.cursor; busy = model.busy
            selected = model.selected; targets = model.targets; hintLevel = model.hintLevel; assistance = model.currentRunUsedHelp
            title = model.feedbackTitle; body = model.feedbackBody; kind = model.feedbackKind
            completed = model.completed; awaitingContinue = model.awaitingContinue; game = try encode(model.game)
            queue = model.queue.map(\.id); storeError = model.store.error
        }
    }
    static let fixture = LearningLesson(id: "workspace-fixture", title: "工作区测试课", stage: .foundation, order: 1,
        summary: "独立检验与恢复测试", goal: "比较兵的推进", principle: "观察回应", whenToAdapt: "条件变化后再判断",
        pitfalls: ["把看过答案当成独立"], sourceIDs: [], lines: [
            StudyLine(id: "one", title: "推进边兵", intent: "练习导读", adaptation: "重新看对手",
                      moves: [StudyMove("a3a4", "兵向前一步")]),
            StudyLine(id: "two", title: "推进另一兵", intent: "另一练习导读", adaptation: "重新看威胁",
                      moves: [StudyMove("c3c4", "另一兵向前一步")])])
    static func make(_ directory: URL) throws -> (LearningStore, LearningModel) {
        let store = LearningStore(directory: directory)
        try store.importPack(StudyPack(title: "工作区测试", sources: [], lessons: [fixture]),
                             builtInIDs: Set(LearningModel.builtInLessons.map(\.id)), builtInSources: LearningModel.builtInSources)
        return (store, LearningModel(store: store, coach: TrainingCoach()))
    }
    static func main() throws {
        let configured = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"]
        if let configured { precondition((configured as NSString).isAbsolutePath) }
        let base = configured.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("xiangqi-workspace-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try restorationTests(directory)
        try exposureTests(directory)
        try neutralPromptTests(directory)
        try chapterUnitsTests()
        print("PASS \(checks) workspace integration checks; invalid restores preserve live state, material exposure survives transitions, test prompts stay neutral")
    }

    static func restorationTests(_ base: URL) throws {
        let (store, model) = try make(base.appendingPathComponent("restore"))
        defer { model.shutdown() }
        model.startLesson(fixture, mode: .practice)
        model.hint(); model.queue = [StudyTarget(lesson: fixture, line: fixture.lines[1])]
        if let move = model.position.legalMoves().first { model.tap(move.from) }
        // A deterministic cancellation sentinel: cancelOperation() would clear busy.
        // No real background engine process is launched by this test.
        model.busy = true
        let original = try LiveSnapshot(model)
        let diskURL = store.directory.appendingPathComponent("learning.json")
        let originalDisk = try Data(contentsOf: diskURL)
        let originalFiles = try FileManager.default.contentsOfDirectory(atPath: store.directory.path).sorted()
        var wrongVersion = LearningArchive(); wrongVersion.version = 99
        for bytes in [Data("{not json}".utf8), try encode(wrongVersion), Data(repeating: 32, count: 8_000_001)] {
            try rejects { _ = try model.restoreLearningArchive(bytes) }
            try check(try LiveSnapshot(model) == original, "Rejected restore cancelled or changed the active session")
            try check(try Data(contentsOf: diskURL) == originalDisk, "Rejected restore changed persisted history")
            try check(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).sorted() == originalFiles,
                      "Invalid data created a backup or partial replacement")
        }
        let (donorStore, donor) = try make(base.appendingPathComponent("donor"))
        defer { donor.shutdown() }
        donor.startLesson(fixture, line: fixture.lines[1], mode: .test)
        donorStore.setDailyMinutes(45); donorStore.bookmark(fixture.id)
        let replacement = try donorStore.exportData(), expectedRun = donorStore.data.resume?.runID
        let backup = try model.restoreLearningArchive(replacement)
        try check(backup != nil && backup?.deletingLastPathComponent().standardizedFileURL.path == store.directory.standardizedFileURL.path,
                  "Successful replacement did not return its local recovery backup")
        try check(try Data(contentsOf: backup!) == originalDisk, "Pre-restore backup failed byte preservation")
        try check(store.data.dailyMinutes == 45 && store.data.resume?.runID == expectedRun && store.data.bookmarks.contains(fixture.id),
                  "Validated archive was not committed intact")
        try check(!model.busy && model.lessonID == nil && model.lineID == nil && model.page == .home && model.position == .initial,
                  "Successful commit did not clear live study state")
        try check(model.queue.isEmpty && model.queuedReviews.isEmpty && model.game == nil && model.gamePositions.isEmpty && model.targets.isEmpty,
                  "Old workspace queues or game state survived replacement")
        let persisted = try JSONDecoder().decode(LearningArchive.self, from: Data(contentsOf: diskURL))
        try check(persisted.dailyMinutes == 45 && persisted.resume?.runID == expectedRun, "Old live resume overwrote the new archive")
        model.resumeStudy()
        try check(model.lineID == fixture.lines[1].id && store.data.resume?.runID == expectedRun, "Restored archive cannot resume its actual line")

        let blocked = base.appendingPathComponent("not-a-directory")
        try Data("test-owned obstruction".utf8).write(to: blocked)
        let blockedModel = LearningModel(store: LearningStore(directory: blocked), coach: TrainingCoach())
        defer { blockedModel.shutdown() }
        blockedModel.position = try Position.initial.applying(move: Move(uci: "a3a4")!)
        blockedModel.page = .sparring; blockedModel.busy = true
        let beforeFailure = try LiveSnapshot(blockedModel)
        try rejects { _ = try blockedModel.restoreLearningArchive(replacement) }
        try check(try LiveSnapshot(blockedModel) == beforeFailure, "Disk commit failure reset the still-active workspace")
        try check(try Data(contentsOf: blocked) == Data("test-owned obstruction".utf8), "Failed restore overwrote its obstruction")
    }

    static func exposureTests(_ base: URL) throws {
        for route in ["book", "positions", "manual"] {
            let (store, model) = try make(base.appendingPathComponent("exposure-" + route))
            model.startLesson(fixture, line: fixture.lines[0], mode: .test)
            let initial = model.position, run = store.data.resume!.runID
            try check(!model.currentRunUsedHelp, "Fresh test unexpectedly starts assisted")
            try check(model.recordMaterialExposure(), "Workspace source/analysis opening failed to record help")
            // App.swift's manual transition invokes these in this order.
            if route == "manual" { model.suspend() }
            try check(model.position == initial && store.data.resume?.runID == run && store.data.resume?.wasRetry == true,
                      "Opening assistance changed the board or lost its saved assistance")
            try check(model.hintLevel == 0 && store.data.runs.isEmpty && store.data.decisions.isEmpty,
                      "Reading invented a numbered hint, attempt or completion")
            model.switchMode(.practice); model.switchMode(.test)
            try check(model.currentRunUsedHelp && store.data.resume?.wasRetry == true, "Changing modes cleared material exposure")
            model.shutdown()
            let restored = LearningModel(store: LearningStore(directory: store.directory), coach: TrainingCoach())
            restored.resumeStudy(); restored.attempt(Move(uci: fixture.lines[0].moves[0].uci)!)
            try check(restored.completed && restored.store.data.runs.last?.independent == false && restored.store.data.runs.last?.hints == 0,
                      "A completed test after assistance earned independent credit or fabricated hints")
            restored.shutdown()
        }
        let (store, model) = try make(base.appendingPathComponent("practice-course-source"))
        defer { model.shutdown() }
        model.startLesson(fixture, line: fixture.lines[0], mode: .practice)
        try check(!model.currentRunUsedHelp, "Unassisted practice was unexpectedly tainted")
        try check(model.recordMaterialExposure(lessonID: fixture.id), "Current-course source reading was not recorded")
        model.switchMode(.test)
        try check(model.currentRunUsedHelp && store.data.resume?.wasRetry == true,
                  "Reading the current course in practice then switching to test cleared assistance")
        model.attempt(Move(uci: fixture.lines[0].moves[0].uci)!)
        try check(model.completed && store.data.runs.last?.independent == false && store.data.runs.last?.hints == 0,
                  "Current-course source reading became an independent pass or fake numbered hint")
    }

    static func neutralPromptTests(_ base: URL) throws {
        var line = StudyLine(id: "checkpoints", title: "题型秘密", intent: "导读秘密", adaptation: "变招秘密",
            moves: [StudyMove("a3a4", "解释秘密"), StudyMove("a6a5", "回应秘密"), StudyMove("c3c4", "后续秘密")])
        line.checkpoints = [
            StudyCheckpoint(ply: 0, title: "暴露标题一", prompt: "暴露提示一：先走边兵", focus: "暴露方向一", explanation: "暴露说明一"),
            StudyCheckpoint(ply: 2, title: "暴露标题二", prompt: "暴露提示二：再走另一兵", focus: "暴露方向二", explanation: "暴露说明二")]
        let lesson = LearningLesson(id: "neutral-fixture", title: fixture.title, stage: .foundation, order: 2, summary: fixture.summary,
            goal: fixture.goal, principle: fixture.principle, whenToAdapt: fixture.whenToAdapt, pitfalls: fixture.pitfalls, sourceIDs: [], lines: [line])
        let store = LearningStore(directory: base.appendingPathComponent("neutral"))
        try store.importPack(StudyPack(title: "中性提示测试", sources: [], lessons: [lesson]), builtInIDs: Set(LearningModel.builtInLessons.map(\.id)))
        let model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        for ply in [0, 1, 2] {
            model.startLesson(lesson, line: line, mode: .test, from: ply)
            try check(model.cursor == (ply == 0 ? 0 : 2), "Test did not advance to the next real checkpoint")
            try check(!model.feedbackTitle.contains("暴露") && !model.feedbackBody.contains("暴露") && !model.feedbackBody.contains("秘密"),
                      "Tooltip/detail fields leak checkpoint direction in test mode")
            try check(model.studyArrows.isEmpty, "Independent test leaked an answer arrow")
            let expectedCursor = model.cursor
            model.resumeStudy()
            try check(model.cursor == expectedCursor && !model.feedbackTitle.contains("暴露") && !model.feedbackBody.contains("暴露"),
                      "Resume revealed checkpoint labels or changed checkpoint")
            model.startLesson(lesson, line: line, mode: .practice, from: ply)
            let point = line.checkpoints!.first { $0.ply >= ply }!
            try check(model.feedbackTitle == point.title && model.feedbackBody == point.prompt,
                      "Hiding test answers removed useful practice guidance")
        }
    }

    static func chapterUnitsTests() throws {
        let chapter = GuidedChapter(id: "unit-fixture", number: 1, title: "测试", subtitle: "测试", goal: "测试", lessonIDs: [fixture.id], readingIDs: [], completionStandard: "全部谱例")
        var archive = LearningArchive()
        var progress = LineProgress(); progress.cleanTests = 1
        archive.progress[LearningStore.key(fixture.id, fixture.lines[0].id)] = progress
        var status = GuidedChapterStatus(chapter: chapter, lessons: [fixture], archive: archive)
        try check(status.totalCount == 1 && status.testedCount == 0, "Chapter count is per lesson, not a count of passed lines")
        archive.progress[LearningStore.key(fixture.id, fixture.lines[1].id)] = progress
        status = GuidedChapterStatus(chapter: chapter, lessons: [fixture], archive: archive)
        try check(status.totalCount == 1 && status.testedCount == 1, "A topic counts only when all playable lines pass")
    }
}
#endif
