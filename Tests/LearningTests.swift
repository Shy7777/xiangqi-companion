#if LEARNING_TESTS
import Foundation

#if LEARNING_MODEL_TESTS && !APP_TESTS
// LearningModel only needs this value type from the UI to express hints.
struct RecommendationArrow { let rank: Int; let move: Move }
#endif

@main
@MainActor
struct LearningTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw Failure(message: message) }
        checks += 1
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        do { try body() }
        catch { checks += 1; return }
        throw Failure(message: message)
    }
    static let source = LearningSource(id: "test-source", title: "规则", url: "https://www.xiangqi.com/how-to-play-xiangqi", note: "测试资料")
    static func lesson(_ id: String = "test-lesson", lineID: String = "test-line", side: Side = .red,
                       moves: [String] = ["b2e2", "b9c7"], prerequisites: [String] = []) -> LearningLesson {
        LearningLesson(id: id, title: "测试课程", stage: .foundation, order: 1, summary: "测试摘要",
                       goal: "活动棋子", principle: "先看威胁", whenToAdapt: "对手改变应对时",
                       pitfalls: ["忽略威胁"], prerequisites: prerequisites, sourceIDs: [source.id],
                       lines: [StudyLine(id: lineID, title: "测试变化", intent: "明确目的", adaptation: "按威胁调整",
                                         studentSide: side, moves: moves.map { StudyMove($0, "这一步的说明") })])
    }
    static func pack(_ lessons: [LearningLesson]) -> StudyPack {
        StudyPack(title: "测试课程包", sources: [source], lessons: lessons)
    }
    static func temporaryDirectory(_ label: String) throws -> URL {
        let configuredBase = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"]
        if let configuredBase {
            precondition((configuredBase as NSString).isAbsolutePath, "XQ_TEST_TEMP_DIR must be an absolute test-owned directory")
        }
        let base = configuredBase.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("xiangqi-learning-tests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let configuredBase {
            let expected = URL(fileURLWithPath: configuredBase, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
            precondition(directory.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == expected,
                         "Learning test data escaped XQ_TEST_TEMP_DIR")
        }
        return directory
    }

    @MainActor
    static func storeTests() throws {
        let valid = pack([lesson()])
        try valid.validate(); checks += 1
        try rejects("Duplicate lesson IDs were accepted") { try pack([lesson(), lesson()]).validate() }
        try rejects("An existing lesson could be overwritten") { try valid.validate(existingLessonIDs: ["test-lesson"]) }
        try rejects("An illegal move was accepted") { try pack([lesson(moves: ["b2b0"])]).validate() }
        try rejects("Malformed move was accepted") { try pack([lesson(moves: ["not-a-move"])]).validate() }
        try rejects("An empty route was accepted") { try pack([lesson(moves: [])]).validate() }
        try rejects("Progress namespace collision lesson ID was accepted") { try pack([lesson("a/b")]).validate() }
        try rejects("Progress namespace collision line ID was accepted") { try pack([lesson(lineID: "b/c")]).validate() }
        try rejects("An opponent-only route could award independent completion") { try pack([lesson(side: .black, moves: ["b2e2"])]).validate() }
        try rejects("Self prerequisite was accepted") { try pack([lesson(prerequisites: ["test-lesson"])]).validate() }
        try rejects("Cyclic prerequisite was accepted") {
            try pack([lesson("a", prerequisites: ["b"]), lesson("b", prerequisites: ["a"])]).validate()
        }
        try rejects("Missing prerequisite was accepted") { try pack([lesson(prerequisites: ["missing"])]).validate() }
        var badSource = valid
        badSource.sources = [LearningSource(id: source.id, title: source.title, url: "javascript:alert(1)", note: source.note)]
        try rejects("Non-HTTPS source was accepted") { try badSource.validate() }

        let directory = try temporaryDirectory("store")
        let store = LearningStore(directory: directory)
        try store.importPack(valid, builtInIDs: [])
        try require(store.data.importedLessons.count == 1, "Valid course pack was not imported")
        try rejects("Repeated import overwrote an existing course") { try store.importPack(valid, builtInIDs: []) }
        try require(store.data.importedLessons.count == 1, "Rejected import partially changed lessons")
        let second = pack([lesson("second")])
        try store.importPack(second, builtInIDs: [])
        try require(store.data.importedSources.count == 1 && store.data.importedLessons.count == 2, "Identical source wasn't deduplicated")
        var conflicting = pack([lesson("third")])
        conflicting.sources = [LearningSource(id: source.id, title: "冲突", url: "https://example.com", note: "不同内容")]
        try rejects("Conflicting source replaced original attribution") { try store.importPack(conflicting, builtInIDs: []) }
        try require(store.data.importedLessons.count == 2 && store.data.importedSources.first == source, "Failed source import changed stored data")
        let builtInConflictStore = LearningStore(directory: try temporaryDirectory("builtin-sources"))
        try rejects("An imported source silently replaced the meaning of a bundled source ID") {
            try builtInConflictStore.importPack(conflicting, builtInIDs: [], builtInSources: [source])
        }
        try require(builtInConflictStore.data.importedLessons.isEmpty, "Builtin source rejection left a partial course")

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let run = UUID()
        let resume = StudyResume(lessonID: "test-lesson", lineID: "test-line", mode: .test, cursor: 1,
                                 hints: 2, errors: 1, wasRetry: true, runID: run, started: date, wasUnseen: false)
        store.setResume(resume)
        store.setDailyMinutes(30)
        store.bookmark("test-lesson")
        let restored = LearningStore(directory: directory)
        try require(restored.data.resume?.runID == run && restored.data.resume?.hints == 2 && restored.data.resume?.errors == 1,
                    "Restart lost resume identity or assistance counters")
        try require(restored.data.dailyMinutes == 30 && restored.data.bookmarks.contains("test-lesson"), "Settings did not survive restart")
        store.finishRun(id: run, lessonID: "test-lesson", lineID: "test-line", mode: .test,
                        hints: 2, errors: 1, wasRetry: true, wasUnseen: false, now: date)
        try require(store.data.runs.last?.independent == false, "Hinted/retried test counted as independent")
        store.finishRun(id: run, lessonID: "test-lesson", lineID: "test-line", mode: .test,
                        hints: 0, errors: 0, wasRetry: false, wasUnseen: true, now: date)
        try require(store.data.runs.count == 1 && store.progress("test-lesson", "test-line").completions == 1,
                    "One run was accounted more than once")
        for (index, values) in [(0, (1, 0, false)), (1, (0, 1, false)), (2, (0, 0, true))] {
            store.finishRun(id: UUID(), lessonID: "assisted", lineID: "line\(index)", mode: .test,
                            hints: values.0, errors: values.1, wasRetry: values.2, wasUnseen: false, now: date)
            try require(store.data.runs.last?.independent == false, "An assisted attempt counted as independent")
        }
        store.finishRun(id: UUID(), lessonID: "demo", lineID: "line", mode: .demonstration,
                        hints: 0, errors: 0, wasRetry: false, wasUnseen: true, now: date)
        try require(store.progress("demo", "line").demonstrations == 1 && store.progress("demo", "line").cleanTests == 0,
                    "Watching a demonstration counted as independent skill")

        for offset in 0..<5 {
            store.finishRun(id: UUID(), lessonID: "spacing", lineID: "line", mode: .test,
                            hints: 0, errors: 0, wasRetry: false, wasUnseen: offset == 0,
                            now: date.addingTimeInterval(Double(offset * 60)))
        }
        let sameDay = store.progress("spacing", "line")
        try require(sameDay.cleanTests == 5 && sameDay.delayedTests == 0, "Same-session successes were confused with delayed tests")
        try require(abs(sameDay.nextReview!.timeIntervalSince(sameDay.lastStudied!) - 86400) < 1,
                    "Same-day repetition improperly advanced spaced review to several weeks")
        let calendarDay = Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 1, hour: 0, minute: 1))!
        for moment in [calendarDay, calendarDay.addingTimeInterval(21 * 3600)] {
            store.finishRun(id: UUID(), lessonID: "same-calendar-day", lineID: "line", mode: .test,
                            hints: 0, errors: 0, wasRetry: false, wasUnseen: false, now: moment)
        }
        try require(store.progress("same-calendar-day", "line").delayedTests == 0,
                    "Two tests on the same calendar day counted as an overnight retention test")
        let nextDay = date.addingTimeInterval(25 * 3600)
        store.finishRun(id: UUID(), lessonID: "spacing", lineID: "line", mode: .test,
                        hints: 0, errors: 0, wasRetry: false, wasUnseen: false, now: nextDay)
        let delayed = store.progress("spacing", "line")
        try require(delayed.delayedTests == 1 && abs(delayed.nextReview!.timeIntervalSince(nextDay) - 3 * 86400) < 1,
                    "A genuinely delayed independent success failed to advance spacing")
        store.markExposed("spacing", "line", assisted: true, now: nextDay.addingTimeInterval(25 * 3600))
        store.finishRun(id: UUID(), lessonID: "spacing", lineID: "line", mode: .test,
                        hints: 0, errors: 0, wasRetry: false, wasUnseen: false, now: nextDay.addingTimeInterval(25 * 3600 + 60))
        try require(store.progress("spacing", "line").delayedTests == 1, "Looking at assistance just before testing counted as spaced retrieval")

        store.addReview(lessonID: nil, lineID: nil, title: "错题", fen: Position.initial.fen,
                        attempted: "a3a4", suggested: "b2e2", detail: "比较走法", replyPV: ["b9c7"], now: date)
        store.addReview(lessonID: nil, lineID: nil, title: "错题", fen: Position.initial.fen,
                        attempted: "c3c4", suggested: "b2e2", detail: "重复出现", replyPV: ["b9c7"], now: date)
        try require(store.data.reviews.count == 1 && store.data.reviews[0].occurrences == 2, "Repeated same-position mistake was duplicated")
        let reviewID = store.data.reviews[0].id
        store.reviewCompleted(reviewID, clean: true, now: date)
        store.reviewCompleted(reviewID, clean: true, now: date.addingTimeInterval(60))
        try require(store.data.reviews[0].successfulReviews == 1 && !store.data.reviews[0].resolved,
                    "Immediate repetitions incorrectly resolved an error")
        store.reviewCompleted(reviewID, clean: true, now: nextDay)
        try require(store.data.reviews[0].successfulReviews == 2 && store.data.reviews[0].resolved,
                    "Spaced error review was not credited")
        store.addReview(lessonID: nil, lineID: nil, title: "又错了", fen: Position.initial.fen,
                        attempted: "a3a4", suggested: "b2e2", detail: "需要重练", replyPV: [], now: nextDay)
        try require(!store.data.reviews[0].resolved && store.data.reviews[0].occurrences == 3, "New error occurrence failed to reopen a mastered item")

        let assistedStore = LearningStore(directory: try temporaryDirectory("review-assistance"))
        assistedStore.addReview(lessonID: nil, lineID: nil, title: "提示记忆", fen: Position.initial.fen,
                                attempted: "a3a4", suggested: "b2e2", detail: "独立回忆", replyPV: [], now: date)
        let assistedID = assistedStore.data.reviews[0].id
        assistedStore.reviewCompleted(assistedID, clean: true, now: date)
        assistedStore.markReviewAssisted(assistedID, now: nextDay)
        try require(assistedStore.data.reviews[0].successfulReviews == 1,
                    "Viewing help erased a previously valid spaced success")
        let assistedReload = LearningStore(directory: assistedStore.directory)
        try require(assistedReload.data.reviews[0].lastAssisted == nextDay, "Review assistance was not persisted")
        assistedReload.reviewCompleted(assistedID, clean: true, now: nextDay.addingTimeInterval(60))
        try require(assistedReload.data.reviews[0].successfulReviews == 1 && !assistedReload.data.reviews[0].resolved,
                    "Restarting immediately after seeing a review answer counted as spaced mastery")
        assistedReload.reviewCompleted(assistedID, clean: false, assisted: true, now: nextDay.addingTimeInterval(120))
        try require(assistedReload.data.reviews[0].successfulReviews == 1,
                    "An assisted correct answer was treated as a tactical failure")
        assistedReload.reviewCompleted(assistedID, clean: true, now: nextDay.addingTimeInterval(25 * 3600))
        try require(assistedReload.data.reviews[0].resolved, "A later independent review after assistance could not be credited")
        var oldReviewJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(assistedReload.data.reviews[0])) as! [String: Any]
        oldReviewJSON.removeValue(forKey: "lastAssisted")
        let oldReview = try JSONDecoder().decode(ReviewItem.self, from: JSONSerialization.data(withJSONObject: oldReviewJSON))
        try require(oldReview.lastAssisted == nil, "Older review archives without assistance metadata no longer decode")

        store.setResume(resume)
        store.finishRun(id: run, lessonID: "test-lesson", lineID: "test-line", mode: .test,
                        hints: 0, errors: 0, wasRetry: false, wasUnseen: true, now: date)
        try require(store.data.resume == nil, "Re-finishing an existing run left a completed resume behind")
        let export = try store.exportData()
        let decoded = try JSONDecoder().decode(LearningArchive.self, from: export)
        try require(decoded.runs.count == store.data.runs.count && decoded.reviews.count == 1, "Export did not round-trip learning history")

        let corruptDir = try temporaryDirectory("corrupt")
        let corruptURL = corruptDir.appendingPathComponent("learning.json")
        let originalBytes = Data("{broken学习存档".utf8)
        try originalBytes.write(to: corruptURL)
        let corrupt = LearningStore(directory: corruptDir)
        corrupt.setDailyMinutes(45)
        corrupt.bookmark("must-not-write")
        let preserved = try Data(contentsOf: corruptURL)
        try require(corrupt.error != nil && preserved == originalBytes,
                    "Opening a corrupt archive silently overwrote the original")
        let backupURL = directory.appendingPathComponent("learning.previous.json")
        try require(FileManager.default.fileExists(atPath: backupURL.path) &&
                    (try? JSONDecoder().decode(LearningArchive.self, from: Data(contentsOf: backupURL))) != nil,
                    "No recoverable preceding valid archive was preserved")
        print("PASS: \(checks) learning storage, pack validation, independent scoring, spaced-review and corruption checks")
    }

    @MainActor
    static func main() async {
        do {
            #if LEARNING_MODEL_TESTS
            if CommandLine.arguments.contains("--checkpoints-only") {
                guard ProcessInfo.processInfo.environment["XQ_RUN_ENGINE_TESTS"] == "1" else {
                    throw Failure(message: "--checkpoints-only requires the explicit live-engine lane")
                }
                try await checkpointTests(); return
            }
            #endif
            try storeTests()
            try backupTests()
            #if LEARNING_MODEL_TESTS
            if ProcessInfo.processInfo.environment["XQ_RUN_ENGINE_TESTS"] == "1" {
                try await modelTests()
                try await interactionTests()
                try await checkpointTests()
            } else {
                print("SKIP: live-engine learning sessions, interaction and checkpoint assessments (use verify.sh --with-engine)")
            }
            #endif
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    @MainActor
    static func backupTests() throws {
        let now = Date()
        var incoming = LearningArchive()
        incoming.importedLessons = [lesson()]
        incoming.importedSources = [source]
        incoming.dailyMinutes = 30
        incoming.bookmarks = ["test-lesson"]
        incoming.exposedLines = ["test-lesson/test-line"]
        incoming.lastAssisted = ["test-lesson/test-line": now]
        incoming.progress = ["test-lesson/test-line": LineProgress(completions: 1, cleanTests: 1,
                                                                  lastStudied: now, nextReview: now.addingTimeInterval(86400))]
        incoming.runs = [StudyRun(id: UUID(), date: now, lessonID: "test-lesson", lineID: "test-line", mode: .test,
                                  hints: 0, errors: 0, wasRetry: false, independent: true, delayed: false, transfer: true)]
        incoming.decisions = [StudyDecision(id: UUID(), date: now, lessonID: "test-lesson", lineID: "test-line", ply: 0,
                                           mode: .test, move: "b2e2", outcome: "course", hintLevel: 0, wasRetry: false)]
        incoming.reviews = [ReviewItem(id: UUID(), created: now, due: now, lessonID: "test-lesson", lineID: "test-line",
                                       title: "测试错题", fen: Position.initial.fen, attempted: "a3a4", suggested: "b2e2",
                                       detail: "比较选择", replyPV: ["b9c7"])]
        incoming.reviews[0].lastAssisted = now
        let gameReview = GameMoveReview(ply: 1, fen: Position.initial.fen, move: "b2e2", bestMove: "b2e2",
                                        verdict: "good", detail: "测试复盘", lossCP: 0,
                                        bestPV: ["b2e2", "b9c7"], replyPV: ["b9c7"])
        incoming.games = [TrainingGame(id: UUID(), started: now, startFEN: Position.initial.fen, player: .red, level: 1,
                                      moves: ["b2e2", "b9c7"], reviews: [gameReview])]
        incoming.resume = StudyResume(lessonID: "test-lesson", lineID: "test-line", mode: .practice, cursor: 1,
                                     hints: 2, errors: 1, wasRetry: true, runID: UUID(), started: now, wasUnseen: false)
        let bytes = try JSONEncoder().encode(incoming)

        let directory = try temporaryDirectory("restore")
        let target = LearningStore(directory: directory)
        target.bookmark("previous-state")
        let learningURL = directory.appendingPathComponent("learning.json")
        let original = try Data(contentsOf: learningURL)
        let sessionURL = directory.appendingPathComponent("session.json")
        let sessionBytes = Data("{\"manual-board\":\"keep byte for byte\"}\n".utf8)
        try sessionBytes.write(to: sessionURL)
        let preservedURL = try target.restoreBackup(bytes, builtInIDs: [], builtInSources: [source])
        try require(preservedURL != nil && preservedURL!.lastPathComponent.hasPrefix("learning.before-restore-"),
                    "Restore did not return a named, unique previous-state backup")
        let preserved = try Data(contentsOf: preservedURL!)
        try require(preserved == original, "Pre-restore backup did not preserve the original bytes exactly")
        try require(target.data.runs.first?.id == incoming.runs.first?.id &&
                    target.data.importedLessons.map(\.id) == ["test-lesson"] && target.data.games.first?.id == incoming.games.first?.id,
                    "Restore did not replace records, courses and games together")
        try require(target.data.resume?.hints == 2 && target.data.resume?.errors == 1 && target.data.resume?.wasRetry == true,
                    "Restore cleared an in-progress session's assistance counters")
        let restored = LearningStore(directory: directory)
        try require(restored.data.dailyMinutes == 30 && restored.data.games.first?.moves == ["b2e2", "b9c7"] && restored.error == nil,
                    "Restored learning data did not survive a real reload")
        try require(restored.data.reviews.first?.lastAssisted == now,
                    "Backup restoration discarded review assistance exposure")
        let unchangedSession = try Data(contentsOf: sessionURL)
        try require(unchangedSession == sessionBytes, "Restoring learning history modified the manual-analysis session")

        let acceptedBytes = try Data(contentsOf: learningURL)
        let acceptedFiles = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        func rejectsWithoutWriting(_ candidate: LearningArchive, _ message: String) throws {
            let badBytes = try JSONEncoder().encode(candidate)
            try rejects(message) { _ = try target.restoreBackup(badBytes, builtInIDs: [], builtInSources: [source]) }
            let currentBytes = try Data(contentsOf: learningURL)
            let currentFiles = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
            try require(currentBytes == acceptedBytes && currentFiles == acceptedFiles &&
                        target.data.runs.first?.id == incoming.runs.first?.id && target.data.games.first?.moves == incoming.games.first?.moves,
                        "Rejected backup partially changed data or wrote a backup file: \(message)")
        }
        var bad = incoming
        bad.version = 2
        try rejectsWithoutWriting(bad, "Unsupported backup version was accepted")
        bad = incoming; bad.runs.append(bad.runs[0])
        try rejectsWithoutWriting(bad, "Repeated run UUID was accepted")
        bad = incoming; bad.decisions.append(bad.decisions[0])
        try rejectsWithoutWriting(bad, "Repeated decision UUID was accepted")
        bad = incoming; bad.reviews.append(bad.reviews[0])
        try rejectsWithoutWriting(bad, "Repeated review UUID was accepted")
        bad = incoming; bad.reviews[0].lastAssisted = Date(timeIntervalSince1970: 999_999_999_999)
        try rejectsWithoutWriting(bad, "An invalid review assistance timestamp was accepted")
        bad = incoming; bad.games.append(bad.games[0])
        try rejectsWithoutWriting(bad, "Repeated game UUID was accepted")
        bad = incoming; bad.games[0].moves = ["a0a9"]
        try rejectsWithoutWriting(bad, "An illegal game history was accepted")
        bad = incoming; bad.games[0].reviews.append(gameReview)
        try rejectsWithoutWriting(bad, "Repeated per-ply game review was accepted")
        bad = incoming
        bad.games[0].reviews = [GameMoveReview(ply: 2, fen: Position.initial.fen, move: "b9c7", bestMove: nil,
                                              verdict: "good", detail: "错配局面", lossCP: nil, bestPV: [], replyPV: [])]
        try rejectsWithoutWriting(bad, "Game review was allowed to reference the wrong prior position")
        bad = incoming; bad.importedLessons.append(bad.importedLessons[0])
        try rejectsWithoutWriting(bad, "Duplicate imported lesson IDs were accepted")
        bad = incoming; bad.importedLessons = [lesson(moves: ["b2b0"])]
        try rejectsWithoutWriting(bad, "An illegal imported course was accepted")
        bad = incoming
        bad.importedSources = [LearningSource(id: source.id, title: "不同归属", url: "https://example.com", note: "冲突")]
        try rejectsWithoutWriting(bad, "Restored source silently changed a built-in source identity")
        bad = incoming; bad.progress["test-lesson/test-line"] = LineProgress(completions: -1)
        try rejectsWithoutWriting(bad, "Negative progress counters were accepted")
        bad = incoming
        bad.runs = [StudyRun(id: UUID(), date: now, lessonID: "test-lesson", lineID: "test-line", mode: .test,
                             hints: 2, errors: 0, wasRetry: true, independent: true, delayed: true, transfer: false)]
        try rejectsWithoutWriting(bad, "Hinted retry could be restored as independent success")
        bad = incoming
        bad.resume = StudyResume(lessonID: "test-lesson", lineID: "test-line", mode: .test, cursor: 100,
                                 hints: 0, errors: 0, wasRetry: false, runID: UUID(), started: now, wasUnseen: false)
        try rejectsWithoutWriting(bad, "An out-of-range imported-course resume was accepted")
        try rejects("Oversized backup was accepted") {
            _ = try target.restoreBackup(Data(count: 8_000_001), builtInIDs: [], builtInSources: [])
        }
        let postFailuresSession = try Data(contentsOf: sessionURL)
        try require(postFailuresSession == sessionBytes, "Invalid restore attempts touched the analysis session")

        let damagedDirectory = try temporaryDirectory("restore-damaged")
        let damagedURL = damagedDirectory.appendingPathComponent("learning.json")
        let damagedBytes = Data("damaged original 学习记录\n".utf8)
        try damagedBytes.write(to: damagedURL)
        let damaged = LearningStore(directory: damagedDirectory)
        try require(damaged.error != nil, "Damaged original was not recognized")
        let damagedBackup = try damaged.restoreBackup(bytes, builtInIDs: [], builtInSources: [source])
        let rescuedOriginal = try Data(contentsOf: damagedBackup!)
        try require(rescuedOriginal == damagedBytes && damaged.error == nil,
                    "Explicit restore did not preserve the damaged original before replacing it")
        damaged.setDailyMinutes(45)
        let rescued = LearningStore(directory: damagedDirectory)
        try require(rescued.data.dailyMinutes == 45 && rescued.error == nil && rescued.data.games.count == 1,
                    "Explicit successful recovery did not release corruption read-only mode")

        let empty = LearningStore(directory: try temporaryDirectory("restore-new"))
        let noPredecessor = try empty.restoreBackup(bytes, builtInIDs: [], builtInSources: [source])
        try require(noPredecessor == nil && empty.data.runs.count == 1,
                    "Restoring without an old file fabricated a previous-state backup")
        print("PASS: \(checks) cumulative learning storage and transactional backup restoration checks")
    }

    #if LEARNING_MODEL_TESTS
    @MainActor
    static func modelTests() async throws {
        let all = LearningModel.builtInLessons
        let builtInPack = StudyPack(title: "内置课程", sources: LearningModel.builtInSources, lessons: all)
        let directory = try temporaryDirectory("model")
        let store = LearningStore(directory: directory)
        let fixture = lesson("model-course", moves: ["b2e2", "b9c7", "h0g2", "h9g7"])
        try store.importPack(pack([fixture]), builtInIDs: Set(all.map(\.id)))
        let coach = TrainingCoach()
        let model = LearningModel(store: store, coach: coach)
        defer { model.shutdown() }
        let line = fixture.lines[0]
        model.startLesson(fixture, line: line, mode: .test)
        let selectedCannon = Square(coordinate: "b2")!
        model.tap(selectedCannon)
        let legalDots = model.targets
        model.tap(Square(coordinate: "e5")!)
        try require(model.selected == selectedCannon && model.targets == legalDots && model.position == .initial,
                    "Illegal destination cleared the selected piece or changed the board")
        try require(store.data.decisions.isEmpty && store.data.runs.isEmpty && store.data.resume?.errors == 0 &&
                    model.feedbackTitle == "这个位置不能落子",
                    "An illegal UI click was recorded as a tactical mistake or completed attempt")
        model.attempt(Move(uci: "b2e2")!)
        try require(model.cursor == 1 && model.position.sideToMove == .black && model.awaitingContinue,
                    "Student move did not wait for the course opponent's response")
        model.continueStudy()
        try require(model.cursor == 2 && model.position.sideToMove == .red, "Course opponent response did not return the student's turn")
        model.attempt(Move(uci: "h0g2")!); model.continueStudy()
        try require(model.completed && store.data.runs.last?.independent == true, "Clean full test was not credited")
        let runCount = store.data.runs.count
        model.continueStudy()
        try require(store.data.runs.count == runCount, "A completed route was accounted twice")

        let blackLesson = lesson("black-student", side: .black, moves: ["b2e2", "b9c7"])
        try store.importPack(pack([blackLesson]), builtInIDs: Set(all.map(\.id)))
        model.startLesson(blackLesson, mode: .test)
        try require(model.cursor == 1 && model.position.sideToMove == .black && !model.completed,
                    "A black-side course did not play Red's opening before the student's answer")
        model.attempt(Move(uci: "b9c7")!)
        try require(model.completed && store.data.runs.last?.independent == true,
                    "Black-side student response failed to complete its independent test")

        let unfamiliarLine = StudyLine(id: "unfamiliar", title: "新线路", intent: "比较选择", adaptation: "按局面调整",
                                      moves: [StudyMove("b2e2", "出炮")])
        let familiarLine = StudyLine(id: "familiar", title: "已学线路", intent: "比较选择", adaptation: "按局面调整",
                                    moves: [StudyMove("h2e2", "出炮")])
        let branches = LearningLesson(id: "branch-exposure", title: "变招曝光测试", stage: .foundation, order: 3,
                                      summary: "测试", goal: "理解变招", principle: "同样合理", whenToAdapt: "对手变化",
                                      pitfalls: [], sourceIDs: [source.id], lines: [unfamiliarLine, familiarLine])
        try store.importPack(pack([branches]), builtInIDs: Set(all.map(\.id)))
        store.markExposed(branches.id, familiarLine.id, assisted: true)
        model.startLesson(branches, line: unfamiliarLine, mode: .test)
        model.attempt(Move(uci: "h2e2")!)
        try require(model.completed && model.lineID == familiarLine.id && store.data.runs.last?.transfer == false,
                    "Transposing into a known branch was incorrectly credited as unfamiliar transfer")
        try require(store.data.runs.last?.wasRetry == true && store.data.runs.last?.independent == false,
                    "Transposing into a recently assisted branch bypassed the target line's assistance record")
        try require(store.data.exposedLines.contains(LearningStore.key(branches.id, unfamiliarLine.id)) &&
                    store.data.exposedLines.contains(LearningStore.key(branches.id, familiarLine.id)),
                    "A branch switch failed to mark both encountered lines as exposed")

        model.startLesson(fixture, line: line, mode: .demonstration)
        model.demoStep(4)
        model.switchMode(.practice)
        try require(model.cursor == 0 && model.position == .initial && !model.completed && model.studyArrows.isEmpty,
                    "Switching demonstration to practice did not hide the answer and reset the board")
        model.hint(); model.retryStudy()
        model.attempt(Move(uci: "b2e2")!); model.continueStudy()
        model.attempt(Move(uci: "h0g2")!); model.continueStudy()
        try require(store.data.runs.last?.independent == false, "Hint/retry completion counted as independent")

        model.startLesson(fixture, line: line, mode: .practice)
        model.hint()
        model.switchMode(.test)
        try require(store.data.resume?.wasRetry == true, "Switching an unfinished hinted practice to test erased assistance contamination")
        model.attempt(Move(uci: "b2e2")!); model.continueStudy()
        model.attempt(Move(uci: "h0g2")!); model.continueStudy()
        try require(store.data.runs.last?.independent == false,
                    "Same-session mode switch awarded independent credit for a previously hinted route")
        model.startLesson(fixture, line: line, mode: .test)
        try require(store.data.resume?.wasRetry == true, "An immediate new test erased recently viewed answers")
        model.attempt(Move(uci: "b2e2")!); model.continueStudy()
        model.attempt(Move(uci: "h0g2")!); model.continueStudy()
        try require(store.data.runs.last?.independent == false, "Completing an assisted run allowed instant answer memorization to count as independent")
        store.markExposed(fixture.id, line.id, assisted: true, now: Date().addingTimeInterval(-2 * 86400))
        model.startLesson(fixture, line: line, mode: .test)
        try require(store.data.resume?.wasRetry == false, "Help remained permanent after the genuine spacing interval")
        model.attempt(Move(uci: "b2e2")!); model.continueStudy()
        model.attempt(Move(uci: "h0g2")!); model.continueStudy()
        try require(store.data.runs.last?.independent == true, "A later separate unassisted test could never be credited")

        // A separate fixture represents an actually old study session: both the
        // answer exposure and last completed practice precede this test by two
        // days. This checks real delayed credit, not merely expiry of the hint.
        let spacedCourse = lesson("model-delayed-assistance", moves: ["b2e2", "b9c7"])
        try store.importPack(pack([spacedCourse]), builtInIDs: Set(all.map(\.id)))
        let pastStudy = Date().addingTimeInterval(-2 * 86400)
        store.markExposed(spacedCourse.id, spacedCourse.lines[0].id, assisted: true, now: pastStudy)
        store.finishRun(id: UUID(), lessonID: spacedCourse.id, lineID: spacedCourse.lines[0].id, mode: .practice,
                        hints: 1, errors: 0, wasRetry: true, wasUnseen: false, now: pastStudy)
        model.startLesson(spacedCourse, mode: .test)
        try require(!model.currentRunUsedHelp && store.data.resume?.wasRetry == false,
                    "A genuinely spaced model test inherited expired answer exposure")
        model.attempt(Move(uci: "b2e2")!); model.continueStudy()
        try require(model.completed && store.data.runs.last?.independent == true && store.data.runs.last?.delayed == true &&
                    store.progress(spacedCourse.id, spacedCourse.lines[0].id).cleanTests == 1 &&
                    store.progress(spacedCourse.id, spacedCourse.lines[0].id).delayedTests == 1,
                    "A complete model test after both study and assistance intervals failed to earn delayed independent credit")

        let finalReply = lesson("resume-final-reply", moves: ["b2e2", "b9c7"])
        try store.importPack(pack([finalReply]), builtInIDs: Set(all.map(\.id)))
        let originalRun = UUID()
        store.setResume(StudyResume(lessonID: finalReply.id, lineID: finalReply.lines[0].id, mode: .test,
                                    cursor: 1, hints: 2, errors: 1, wasRetry: true, runID: originalRun,
                                    started: Date(), wasUnseen: false))
        let beforeRestoreCount = store.data.runs.count
        model.resumeStudy()
        if !model.completed { model.continueStudy() }
        try require(model.completed && store.data.runs.count == beforeRestoreCount + 1,
                    "Restoring before a final opponent move did not complete exactly one run")
        try require(store.data.runs.last?.id == originalRun && store.data.runs.last?.hints == 2 &&
                    store.data.runs.last?.errors == 1 && store.data.runs.last?.independent == false,
                    "Resume awarded a fresh clean run before restoring original assistance counters")

        let custom = try Position(fen: "4k4/9/9/9/9/9/9/9/4A4/3K5 w - - 0 1")
        model.startGame(from: custom, player: .red)
        let gameID = model.game!.id
        model.startLesson(fixture, line: line, mode: .demonstration)
        model.demoStep(2)
        let coursePosition = model.position
        model.navigate(.sparring)
        try require(model.position == custom && model.game?.id == gameID && model.game?.moves.isEmpty == true,
                    "Switching from course to game reused the course board as a game position")
        model.navigate(.study)
        try require(model.position == coursePosition, "Switching back to study did not restore the course board")

        let alternativeLine = StudyLine(id: "alternative-line", title: "等价着测试", intent: "自己判断合法选择",
                                        adaptation: "接受近似等价", startingFEN: custom.fen,
                                        moves: [StudyMove("e1f2", "仕向另一侧活动")])
        let alternativeLesson = LearningLesson(id: "alternative-lesson", title: "等价选择", stage: .foundation,
                                               order: 2, summary: "测试", goal: "正确走仕", principle: "不唯一路线",
                                               whenToAdapt: "棋盘变化时", pitfalls: [], sourceIDs: [source.id], lines: [alternativeLine])
        try store.importPack(pack([alternativeLesson]), builtInIDs: Set(all.map(\.id)))
        model.startLesson(alternativeLesson, mode: .test)
        model.attempt(Move(uci: "e1d2")!)
        let alternativeDeadline = Date().addingTimeInterval(8)
        while model.busy && Date() < alternativeDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(!model.busy && model.hasPendingMove && model.lastAssessment != nil,
                    "Alternative-draw fixture did not finish real before/after assessment")
        try require(store.data.resume?.wasRetry == true,
                    "A pending alternative with AI feedback could be restarted as a fresh independent attempt")
        model.navigate(.home); model.navigate(.study)
        try require(model.position == custom && !model.hasPendingMove, "Route return did not restore the original course position")
        model.attempt(Move(uci: "e1f2")!)
        try require(model.completed && store.data.runs.last?.wasRetry == true && store.data.runs.last?.independent == false,
                    "Sidebar navigation erased assistance contamination and awarded independent success")

        // Completing an assisted run does not erase the recent exposure when
        // starting another test of the same authored line immediately.
        model.startLesson(alternativeLesson, mode: .test)
        try require(model.currentRunUsedHelp && store.data.resume?.wasRetry == true,
                    "An immediate handoff-fixture test erased the preceding run's recent assistance")
        model.attempt(Move(uci: "e1f2")!)
        try require(model.completed && store.data.runs.last?.wasRetry == true && store.data.runs.last?.independent == false,
                    "An immediate repeated authored test earned independent credit after reading feedback")

        // Isolate the handoff's own effect after earlier answer exposure has
        // genuinely expired. The same retry status must survive in memory and
        // in the persisted resume, without requiring an app restart.
        for directGameStart in [false, true] {
            store.markExposed(alternativeLesson.id, alternativeLine.id, assisted: true,
                              now: Date().addingTimeInterval(-2 * 86400))
            model.startLesson(alternativeLesson, mode: .test)
            let handoffRunID = store.data.resume?.runID
            try require(!model.currentRunUsedHelp && store.data.resume?.wasRetry == false,
                        "A handoff test still inherited assistance after the answer-exposure interval elapsed")
            model.attempt(Move(uci: "e1d2")!)
            let handoffDeadline = Date().addingTimeInterval(8)
            while model.busy && Date() < handoffDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
            try require(model.feedbackKind == "alternative" && model.hasPendingMove && !model.currentRunUsedHelp,
                        "Real-engine handoff fixture did not produce a clean, reasonable alternative")
            let alternativePosition = model.position
            if directGameStart { model.startGame(from: alternativePosition, player: .red) }
            else { model.continueBranchAsGame() }
            try require(model.page == .sparring && model.currentRunUsedHelp && store.data.resume?.wasRetry == true
                        && store.data.resume?.runID == handoffRunID,
                        "Course-to-game handoff persisted a retry but failed to mark the same live run")
            model.navigate(.study)
            try require(model.position == custom && !model.hasPendingMove && model.currentRunUsedHelp
                        && store.data.resume?.wasRetry == true,
                        "Returning from an evaluated alternative erased retry status before the course was resumed")
            model.attempt(Move(uci: "e1f2")!)
            try require(model.completed && store.data.runs.last?.id == handoffRunID
                        && store.data.runs.last?.hints == 0 && store.data.runs.last?.errors == 0
                        && store.data.runs.last?.wasRetry == true && store.data.runs.last?.independent == false
                        && store.data.decisions.last?.wasRetry == true,
                        "A reasonable alternative explored in sparring falsely became a fresh independent course success")
            try await Task.sleep(nanoseconds: 150_000_000)
            try require(model.page == .study && model.completed && !model.busy,
                        "The cancelled sparring reply changed the completed course after handoff")
        }
        // With no recent exposure and no evaluated pending move, ordinary
        // game/course navigation must not itself manufacture assistance.
        store.markExposed(alternativeLesson.id, alternativeLine.id, assisted: true,
                          now: Date().addingTimeInterval(-2 * 86400))
        model.startLesson(alternativeLesson, mode: .test)
        model.navigate(.sparring); model.navigate(.study)
        model.attempt(Move(uci: "e1f2")!)
        try require(model.completed && store.data.runs.last?.wasRetry == false && store.data.runs.last?.independent == true,
                    "The pending-move fix incorrectly marked all game/course navigation as assisted")

        model.startLesson(alternativeLesson, mode: .test)
        model.attempt(Move(uci: "e1d2")!)
        let restartDeadline = Date().addingTimeInterval(8)
        while model.busy && Date() < restartDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(model.hasPendingMove && store.data.resume?.wasRetry == true, "Pending state wasn't saved before restart")
        let pendingRunID = store.data.resume?.runID
        model.suspend()
        let restartStore = LearningStore(directory: directory)
        let restarted = LearningModel(store: restartStore, coach: TrainingCoach())
        restarted.resumeStudy()
        restarted.attempt(Move(uci: "e1f2")!)
        try require(restarted.completed && restartStore.data.runs.last?.id == pendingRunID &&
                    restartStore.data.runs.last?.wasRetry == true && restartStore.data.runs.last?.independent == false,
                    "Restart erased the pending attempt's original identity and assistance contamination")
        restarted.shutdown()

        let existingReviewCount = store.data.reviews.count
        let review = GameMoveReview(ply: 1, fen: Position.initial.fen, move: "a3a4", bestMove: "b2e2",
                                    verdict: "mistake", detail: "测试实战错题", lossCP: 300,
                                    bestPV: ["b2e2"], replyPV: ["b9c7"])
        model.reviewGameMistake(review)
        try require(store.data.reviews.count == existingReviewCount + 1 &&
                    store.data.reviews.contains(where: { $0.id == model.activeReview?.id }),
                    "Starting a game mistake created a review UUID that is absent from the store")
        let activeID = model.activeReview!.id
        model.reviewGameMistake(review)
        try require(model.activeReview?.id == activeID && store.data.reviews.count == existingReviewCount + 1,
                    "Reopening the same game mistake duplicated its review item")

        model.startLesson(fixture, line: line, mode: .practice)
        model.attempt(Move(uci: "a3a4")!)
        try require(model.busy, "Alternative move did not start actual assessment")
        model.navigate(.home)
        try await Task.sleep(nanoseconds: 200_000_000)
        try require(model.page == .home && !model.busy && model.lastAssessment == nil,
                    "Cancelled assessment wrote late UI results after route change")

        model.startGame(player: .black)
        model.startLesson(fixture, line: line, mode: .demonstration)
        try await Task.sleep(nanoseconds: 250_000_000)
        try require(model.page == .study && model.position == .initial && !model.busy && model.game?.moves.isEmpty == true,
                    "A cancelled opponent-start task mutated the newly opened course")

        let mateBefore = try Position(fen: "4k4/1N1R1R3/9/9/4P4/9/9/9/9/4K4 w - - 0 1")
        let terminal = try mateBefore.applying(move: Move(uci: "d8d9")!)
        model.startGame(from: terminal, player: .black)
        try require(model.game?.result != nil && !model.busy && model.game?.moves.isEmpty == true,
                    "Starting on a terminal student's turn did not settle the completed game")
        let unfinishedTerminal = TrainingGame(id: UUID(), started: Date(), startFEN: terminal.fen,
                                             player: .black, level: 1)
        model.resumeGame(unfinishedTerminal)
        try require(model.game?.result != nil && !model.busy,
                    "Resuming on a terminal student's turn left an unplayable active game")

        var historicalGame = TrainingGame(id: UUID(), started: Date(), startFEN: Position.initial.fen,
                                          player: .red, level: 1)
        historicalGame.moves = ["b2e2", "b9c7"]
        historicalGame.reviews = [GameMoveReview(ply: 1, fen: Position.initial.fen, move: "b2e2", bestMove: "b2e2",
                                                verdict: "good", detail: "只有第一步的评语", lossCP: 0,
                                                bestPV: ["b2e2"], replyPV: ["b9c7"])]
        model.resumeGame(historicalGame)
        let currentGamePosition = model.position
        model.reviewGame(at: 1)
        try require(model.feedbackBody.contains("只有第一步的评语") && model.feedbackTitle.contains("第 1 步"),
                    "Historical move review did not select the matching saved assessment")
        model.reviewGame(at: 2)
        try require(!model.feedbackBody.contains("只有第一步的评语") && model.feedbackBody.contains("没有保存走法评语"),
                    "An unassessed historical ply displayed another move's assessment")
        model.reviewGame(at: 0)
        model.requestGameHint()
        try await Task.sleep(nanoseconds: 200_000_000)
        try require(model.busy, "Historical hint finished before the cancellation regression exercised its pending state")
        model.returnToGame()
        try require(!model.busy && model.gameReviewCursor == nil && model.displayedGamePosition == currentGamePosition,
                    "Returning to the live player turn failed to cancel the historical search immediately")
        try await Task.sleep(nanoseconds: 1_600_000_000)
        try require(model.gameAnalysis.isEmpty && !model.gameHints && model.lastAssessment == nil &&
                    !model.feedbackBody.contains("只有第一步的评语"),
                    "A stale historical search or assessment appeared on the current game board")
        model.requestGameHint()
        let liveHintDeadline = Date().addingTimeInterval(5)
        while model.busy && Date() < liveHintDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(!model.gameAnalysis.isEmpty && coach.usesNormalizedPawnScore,
                    "The current-position search did not recover after cancelling history, or score units were unavailable")

        let assistedDate = Date().addingTimeInterval(-2 * 86400)
        store.addReview(lessonID: nil, lineID: nil, title: "重进提示污染", fen: custom.fen,
                        attempted: "e1d2", suggested: "e1f2", detail: "独立处理", replyPV: [], now: assistedDate)
        let reentryReview = store.data.reviews.first { $0.fen == custom.fen && $0.suggested == "e1f2" }!
        store.reviewCompleted(reentryReview.id, clean: true, now: assistedDate)
        model.startReview(reentryReview); model.hint(); model.hint(); model.hint()
        model.navigate(.review); model.startReview(reentryReview)
        model.attempt(Move(uci: "e1f2")!)
        let reviewReentryDeadline = Date().addingTimeInterval(7)
        while model.busy && Date() < reviewReentryDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(model.completed && store.data.reviews.first { $0.id == reentryReview.id }?.successfulReviews == 1,
                    "Reopening a review after viewing its answer falsely awarded the second spaced success")

        store.addReview(lessonID: nil, lineID: nil, title: "重启提示污染", fen: custom.fen,
                        attempted: "e1f2", suggested: "e1d2", detail: "独立处理", replyPV: [], now: assistedDate)
        let rebootReview = store.data.reviews.first { $0.fen == custom.fen && $0.suggested == "e1d2" }!
        store.reviewCompleted(rebootReview.id, clean: true, now: assistedDate)
        model.startReview(rebootReview); model.hint(); model.hint(); model.hint(); model.suspend()
        let reviewRestartStore = LearningStore(directory: directory)
        let reviewRestartModel = LearningModel(store: reviewRestartStore, coach: TrainingCoach())
        reviewRestartModel.startReview(reviewRestartStore.data.reviews.first { $0.id == rebootReview.id }!)
        reviewRestartModel.attempt(Move(uci: "e1d2")!)
        let reviewRebootDeadline = Date().addingTimeInterval(7)
        while reviewRestartModel.busy && Date() < reviewRebootDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(reviewRestartModel.completed && reviewRestartStore.data.reviews.first { $0.id == rebootReview.id }?.successfulReviews == 1,
                    "Restarting after viewing a review answer falsely marked that item mastered")
        reviewRestartModel.shutdown()

        let planStore = LearningStore(directory: try temporaryDirectory("daily-plan"))
        let planModel = LearningModel(store: planStore, coach: TrainingCoach())
        defer { planModel.shutdown() }
        planStore.setDailyMinutes(30)
        planStore.addReview(lessonID: nil, lineID: nil, title: "最早到期错题", fen: custom.fen,
                            attempted: "e1d2", suggested: "e1f2", detail: "先复习", replyPV: [], now: assistedDate)
        planStore.addReview(lessonID: nil, lineID: nil, title: "同一错题重复出现", fen: custom.fen,
                            attempted: "e1d2", suggested: "e1f2", detail: "不要重复排入", replyPV: [], now: assistedDate)
        planStore.addReview(lessonID: nil, lineID: nil, title: "第二条错题", fen: custom.fen,
                            attempted: "e1f2", suggested: "e1d2", detail: "再复习", replyPV: [], now: assistedDate.addingTimeInterval(10))
        planStore.addReview(lessonID: nil, lineID: nil, title: "留给下次的第三条", fen: Position.initial.fen,
                            attempted: "a3a4", suggested: "b2e2", detail: "本次最多两条", replyPV: [], now: assistedDate.addingTimeInterval(20))
        let planDueIDs = planModel.dueReviews.map(\.id)
        let tacticalTarget = planModel.recommendedLessons.first { $0.stage == .tactics }!
        planStore.finishRun(id: UUID(), lessonID: tacticalTarget.id, lineID: tacticalTarget.lines[0].id, mode: .practice,
                            hints: 0, errors: 0, wasRetry: false, wasUnseen: true, now: assistedDate)
        planModel.startDailyPlan()
        try require(planModel.activeReview?.id == planDueIDs[0] && planModel.queuedReviews.map(\.id) == [planDueIDs[1]],
                    "Daily plan did not prioritize the two distinct earliest due mistakes")
        try require(planModel.remainingPlanCount == planModel.queue.count + 1 && !planModel.queue.isEmpty,
                    "Plan remaining count omitted pending mistakes or courses")
        try require(Set(planModel.queue.map(\.id)).count == planModel.queue.count &&
                    planModel.queue.filter { $0.lesson.id == tacticalTarget.id && $0.line.id == tacticalTarget.lines[0].id }.count == 1,
                    "Thirty-minute extras duplicated a course branch already due for review")
        for expectedID in planDueIDs.prefix(2) {
            try require(planModel.activeReview?.id == expectedID, "Daily plan changed mistake order")
            planModel.attempt(Move(uci: planModel.activeReview!.suggested)!)
            let planReviewDeadline = Date().addingTimeInterval(7)
            while planModel.busy && Date() < planReviewDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
            try require(planModel.completed && planModel.activeReview?.id == expectedID,
                        "A queued mistake did not complete through real engine assessment")
            let remaining = planModel.remainingPlanCount
            planModel.nextQueued()
            try require(planModel.remainingPlanCount == remaining - 1, "Advancing the mixed daily plan skipped or double-counted an item")
        }
        try require(planModel.activeReview == nil && planModel.lesson != nil && planModel.mode == .practice,
                    "After due mistakes, the daily plan failed to continue into a practice course")

        let beforeDiagnosticRuns = planStore.data.runs.count
        planModel.startDailyPlan(diagnostic: true)
        try require(planModel.queuedReviews.isEmpty && planModel.activeReview == nil && planModel.mode == .test,
                    "Starting diagnostic mixed due mistakes into the unassisted test plan")
        var diagnosticCourses = 0
        repeat {
            try require(planModel.mode == .test && planModel.activeReview == nil,
                        "A later diagnostic item reverted to practice or opened a mistake")
            try require(planModel.lesson?.isSystematic == true && planModel.isCheckpointStudy &&
                        planModel.currentCheckpoint != nil && planModel.studyArrows.isEmpty,
                        "A diagnostic opened a supplement or exposed the historical answer before a key question")
            diagnosticCourses += 1
            if planModel.remainingPlanCount == 0 { break }
            planModel.nextQueued()
        } while diagnosticCourses < 10
        let diagnosticStages = Set(planModel.recommendedLessons.map(\.stage)).count
        try require(diagnosticCourses == diagnosticStages && planModel.remainingPlanCount == 0 &&
                    planStore.data.runs.dropFirst(beforeDiagnosticRuns).allSatisfy { $0.mode == .test },
                    "The available systematic-stage diagnostic did not remain entirely in test mode")

        let unavailableStore = LearningStore(directory: try temporaryDirectory("unresponsive-model"))
        try unavailableStore.importPack(pack([fixture]), builtInIDs: Set(all.map(\.id)))
        let unresponsiveCoach = TrainingCoach(binaryURL: URL(fileURLWithPath: "/bin/cat"),
                                             networkURL: URL(fileURLWithPath: "/dev/null"))
        let unavailableModel = LearningModel(store: unavailableStore, coach: unresponsiveCoach)
        unavailableModel.startLesson(fixture, line: line, mode: .practice)
        unavailableModel.attempt(Move(uci: "a3a4")!)
        let unavailableDeadline = Date().addingTimeInterval(15)
        while unavailableModel.busy && Date() < unavailableDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(!unavailableModel.busy && unavailableModel.feedbackKind == "uncertain",
                    "Unresponsive engine left the training UI blocked")
        try require(unavailableStore.data.runs.isEmpty && unavailableStore.data.decisions.isEmpty &&
                    unavailableStore.data.reviews.isEmpty && unavailableStore.data.resume?.errors == 0,
                    "Engine timeout was falsely recorded as a student mistake or completed attempt")
        unavailableModel.shutdown()
        let actualExport = try store.exportData()
        let actualRestored = LearningStore(directory: try temporaryDirectory("model-export-roundtrip"))
        try actualRestored.restoreBackup(actualExport, builtInIDs: Set(all.map(\.id)), builtInSources: LearningModel.builtInSources)
        try require(actualRestored.data.runs.count == store.data.runs.count &&
                    actualRestored.data.games.count == store.data.games.count &&
                    actualRestored.data.importedLessons.count == store.data.importedLessons.count,
                    "The restore validator rejected or changed an archive produced by the actual learning model")
        try builtInPack.validate(); checks += 1
        print("PASS: \(checks) total storage/curriculum/session checks, including real coach cancellation")
    }

    @MainActor
    static func interactionTests() async throws {
        let store = LearningStore(directory: try temporaryDirectory("interaction-safety"))
        let course = lesson("interaction-course", moves: ["b2e2", "b9c7", "h0g2", "h9g7"])
        try store.importPack(pack([course]), builtInIDs: Set(LearningModel.builtInLessons.map(\.id)))
        let model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        try require(model.studyPhase == .unavailable && !model.performPrimaryStudyAction(),
                    "A study shortcut ran outside an active learning board")
        model.startLesson(course, mode: .test)
        let testFeedback = model.feedbackBody
        model.goToDemoPly(Int.max); model.demoStep(Int.max)
        try require(model.studyPhase == .studentTurn && model.cursor == 0 && model.position == .initial &&
                    model.studyArrows.isEmpty && model.feedbackBody == testFeedback && store.data.runs.isEmpty,
                    "Timeline or demo shortcuts revealed answers, moved pieces or completed an unassisted test")
        try require(!model.performPrimaryStudyAction() && model.cursor == 0 && store.data.decisions.isEmpty,
                    "The primary shortcut chose the student's test move")
        model.attempt(Move(uci: "b2e2")!)
        try require(model.studyPhase == .awaitingOpponent && model.performPrimaryStudyAction(),
                    "After an explicit student move, the primary shortcut failed to show the prescribed reply")
        try require(model.studyPhase == .studentTurn && model.cursor == 2 && !model.performPrimaryStudyAction(),
                    "One primary action advanced beyond the opponent reply into the student's next choice")
        model.attempt(Move(uci: "h0g2")!); model.performPrimaryStudyAction()
        try require(model.studyPhase == .completed && !model.performPrimaryStudyAction() && store.data.runs.count == 1,
                    "A completed test shortcut replayed or accounted the run again")

        model.startLesson(course, mode: .demonstration)
        store.markExposed(course.id, course.lines[0].id, assisted: true, now: Date().addingTimeInterval(-3 * 86400))
        let jumpStarted = Date()
        model.goToDemoPly(2)
        let positions = try course.lines[0].positions()
        try require(model.studyPhase == .demonstration && model.cursor == 2 && model.position == positions[2],
                    "The demonstration timeline did not restore the exact selected position")
        try require(store.data.lastAssisted[LearningStore.key(course.id, course.lines[0].id)]! >= jumpStarted,
                    "Viewing an old demonstration timeline did not refresh answer exposure")
        let beforeDemo = store.data.runs.count
        model.goToDemoPly(Int.max)
        try require(model.studyPhase == .completed && model.cursor == course.lines[0].moves.count &&
                    store.data.runs.count == beforeDemo + 1 && store.data.runs.last?.mode == .demonstration &&
                    store.data.runs.last?.independent == false,
                    "Jumping to the end did not clamp safely or was credited as an independent test")
        model.goToDemoPly(Int.min)
        try require(model.studyPhase == .demonstration && model.cursor == 0 && model.position == .initial &&
                    model.performPrimaryStudyAction() && model.cursor == 1,
                    "Jumping to the beginning did not safely resume manual demonstration stepping")
        model.goToDemoPly(Int.max); model.goToDemoPly(0); model.goToDemoPly(Int.max)
        try require(store.data.runs.count == beforeDemo + 1 && store.data.resume == nil,
                    "Scrubbing an already-completed demonstration repeatedly counted the same run")
        model.switchMode(.test)
        model.attempt(Move(uci: "b2e2")!); model.performPrimaryStudyAction()
        model.attempt(Move(uci: "h0g2")!); model.performPrimaryStudyAction()
        try require(store.data.runs.last?.mode == .test && store.data.runs.last?.wasRetry == true &&
                    store.data.runs.last?.independent == false && store.data.runs.last?.delayed == false &&
                    store.data.runs.last?.transfer == false,
                    "Looking at the timeline and immediately testing was credited as independent, delayed or unseen retrieval")

        let custom = try Position(fen: "4k4/9/9/9/9/9/9/9/4A4/3K5 w - - 0 1")
        model.startLesson(course, mode: .demonstration)
        model.startGame(from: custom, player: .red)
        model.goToDemoPly(0); model.demoStep(1)
        try require(model.studyPhase == .unavailable && !model.performPrimaryStudyAction() && model.position == custom &&
                    model.game?.moves.isEmpty == true,
                    "A stale demonstration timeline callback overwrote the current sparring board")

        model.startGame(player: .black)
        let cancelledGameID = model.game!.id
        model.startGame(player: .red)
        let freshGameID = model.game!.id
        try await Task.sleep(nanoseconds: 400_000_000)
        try require(cancelledGameID != freshGameID && model.game?.id == freshGameID && model.position == .initial &&
                    model.game?.moves.isEmpty == true && !model.busy,
                    "Opening a new player-first game received a late reply from the previous game")
        model.tap(Square(coordinate: "b2")!); model.tap(Square(coordinate: "e2")!)
        try require(model.busy, "The game-to-course cancellation fixture did not begin real assessment")
        model.startLesson(course, mode: .test)
        try await Task.sleep(nanoseconds: 400_000_000)
        try require(model.studyPhase == .studentTurn && model.position == .initial && !model.busy &&
                    model.lastAssessment == nil && model.game?.moves.count == 1 && model.game?.reviews.isEmpty == true,
                    "A late game assessment or reply changed the newly selected test course")

        let alternativeLine = StudyLine(id: "alternative", title: "等价选择", intent: "自己判断", adaptation: "合法变招",
                                        startingFEN: custom.fen, moves: [StudyMove("e1f2", "活动仕")])
        let alternativeCourse = LearningLesson(id: "interaction-alternative", title: "变招反馈测试", stage: .foundation,
                                               order: 2, summary: "测试", goal: "活动棋子", principle: "合理即可",
                                               whenToAdapt: "按局面判断", pitfalls: [], sourceIDs: [source.id], lines: [alternativeLine])
        try store.importPack(pack([alternativeCourse]), builtInIDs: Set(LearningModel.builtInLessons.map(\.id)))
        model.startLesson(alternativeCourse, mode: .practice)
        model.attempt(Move(uci: "e1d2")!)
        try require(model.studyPhase == .analyzing && !model.performPrimaryStudyAction(),
                    "A primary action changed a pending engine assessment")
        let feedbackDeadline = Date().addingTimeInterval(7)
        while model.busy && Date() < feedbackDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(model.studyPhase == .moveFeedback &&
                    (model.lastAssessment?.verdict == .good || model.lastAssessment?.verdict == .exactBest),
                    "An equivalent real-engine move did not enter its distinct feedback phase")
        var previewPosition = model.position
        var previewLastMove = Move(uci: "e1d2")!
        for text in model.lastAssessment!.replyPV.prefix(2) {
            guard let move = Move(uci: text), let next = try? previewPosition.applying(move: move) else { break }
            previewPosition = next; previewLastMove = move
        }
        model.showReply()
        try require(model.isShowingReplyPreview && model.currentRunUsedHelp && model.position == previewPosition &&
                    model.lastMove == previewLastMove && model.studyArrows.isEmpty,
                    "Reply preview failed to mark assistance or highlighted the student's old move instead of the actual preview last move")
        model.showReply()
        try require(model.position == previewPosition && model.lastMove == previewLastMove,
                    "Clicking reply preview twice applied the same PV a second time")
        try require(model.performPrimaryStudyAction() && model.studyPhase == .studentTurn && model.position == custom &&
                    model.feedbackTitle == "回到原局面，再作判断" && store.data.resume?.wasRetry == true &&
                    !model.isShowingReplyPreview && model.lastMove == nil,
                    "Returning from a reasonable move mislabeled it an error or erased retry contamination")
        model.suspend()
        let previewReloadStore = LearningStore(directory: store.directory)
        let previewReloadModel = LearningModel(store: previewReloadStore, coach: TrainingCoach())
        previewReloadModel.resumeStudy()
        try require(previewReloadModel.currentRunUsedHelp && !previewReloadModel.isShowingReplyPreview &&
                    previewReloadModel.position == custom && previewReloadModel.lastMove == nil,
                    "Resuming after a reply preview restored a stale marker or lost assistance contamination")
        previewReloadModel.shutdown()
        model.feedbackKind = "mistake"; model.retryStudy()
        try require(model.feedbackTitle == "回到错误前，自己重走",
                    "A genuine mistake lost its explicit error-retry explanation")
        model.feedbackKind = "uncertain"; model.retryStudy()
        try require(model.feedbackTitle == "回到原局面，再作判断",
                    "An inconclusive assessment was described as a confirmed error")
        print("PASS: \(checks) cumulative checks including safe interaction phases, timeline and task handoff")
    }
    static func waitForAssessment(_ model: LearningModel) async throws {
        let deadline = Date().addingTimeInterval(8)
        while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(!model.busy, "Checkpoint assessment did not complete within the bounded wait")
    }

    static func checkpointTests() async throws {
        let custom = try Position(fen: "4k4/9/9/9/9/9/9/9/4A4/3K5 w - - 0 1")
        func point(_ ply: Int) -> StudyCheckpoint {
            StudyCheckpoint(ply: ply, title: "关键点 \(ply)", prompt: "独立选择合法走法", focus: "先检查规则与威胁", explanation: "作答后才显示的讲解 \(ply)")
        }
        var line = StudyLine(id: "key-game", title: "完整上下文", intent: "只在指定步作答", adaptation: "不强制原谱", startingFEN: custom.fen,
                             moves: ["e1f2", "e9f9", "f2e1", "f9e9"].map { StudyMove($0, "", hint: "") })
        line.checkpoints = [point(1), point(2)]
        line.game = StudyGameMetadata(red: "测试红方", black: "测试黑方", event: "规则测试", date: "2026-01-01", result: "未完", sourceURL: source.url)
        func course(_ id: String, _ selected: StudyLine) -> LearningLesson {
            var value = LearningLesson(id: id, title: "系统课测试", stage: .foundation, order: 1, summary: "全局背景", goal: "计算关键点",
                                       principle: "不以原谱为唯一答案", whenToAdapt: "候选不同也可合理", pitfalls: [], sourceIDs: [source.id], lines: [selected])
            value.guide = StudyGuide(level: "有实战基础", reading: "原站导读", questions: ["你如何选择"], workflow: ["看谱", "计算", "比较"], takeaway: "独立计算")
            return value
        }
        let fixture = course("checkpoint-fixture", line)
        try pack([fixture]).validate(); checks += 1
        for invalid in [[point(-1)], [point(1), point(1)], [point(2), point(1)], [point(4)]] {
            var bad = line; bad.checkpoints = invalid
            try rejects("Invalid checkpoint indices passed course validation") { try pack([course("bad-checkpoint", bad)]).validate() }
        }
        var badMetadata = line
        badMetadata.game = StudyGameMetadata(red: "R", black: "B", event: "E", date: "D", result: "R", sourceURL: "javascript:alert(1)")
        try rejects("Non-HTTPS game provenance passed validation") { try pack([course("bad-source", badMetadata)]).validate() }
        let old = try JSONDecoder().decode(LearningLesson.self, from: JSONEncoder().encode(lesson()))
        try require(old.guide == nil && old.lines[0].checkpoints == nil && old.lines[0].game == nil,
                    "Legacy course JSON stopped decoding without optional systematic metadata")
        let oldResume = StudyResume(lessonID: old.id, lineID: old.lines[0].id, mode: .test, cursor: 0,
                                    hints: 0, errors: 0, wasRetry: false, runID: UUID(), started: Date(), wasUnseen: true)
        let decodedOldResume = try JSONDecoder().decode(StudyResume.self, from: JSONEncoder().encode(oldResume))
        try require(decodedOldResume.completedCheckpoints == nil,
                    "Legacy resume stopped decoding without checkpoint progress")

        let directory = try temporaryDirectory("checkpoints")
        let store = LearningStore(directory: directory)
        try store.importPack(pack([fixture]), builtInIDs: Set(LearningModel.builtInLessons.map(\.id)))
        let model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        try require(model.filteredLessons.allSatisfy(\.isSystematic) && model.recommendedLessons.allSatisfy(\.isSystematic),
                    "Default recommendations or catalog still prioritize shallow legacy supplements")
        model.onlySupplements = true
        try require(!model.filteredLessons.isEmpty && model.filteredLessons.allSatisfy { !$0.isSystematic },
                    "Legacy supplement courses became inaccessible")
        model.startLesson(fixture, mode: .test)
        let positions = try line.positions()
        try require(model.cursor == 1 && model.position == positions[1] && model.position.sideToMove == .black && model.flipped &&
                    model.currentCheckpoint == line.checkpoints![0] && model.checkpointIndex == 0 && model.checkpointCount == 2,
                    "Non-key context failed to advance to a black-side checkpoint")
        try require(store.data.decisions.isEmpty && model.studyArrows.isEmpty && !model.feedbackBody.contains("作答后才"),
                    "Context playback recorded an answer or exposed the explanation")
        model.hint(); model.goToDemoPly(4); model.continueStudy()
        try require(model.cursor == 1 && model.hintLevel == 0 && !model.completed,
                    "A test could auto-play, seek, or reveal a checkpoint answer")
        model.tap(Square(coordinate: "e9")!)
        try require(model.selected == Square(coordinate: "e9") && model.targets.contains(Square(coordinate: "e8")!),
                    "A black checkpoint was incorrectly blocked by the legacy red studentSide")
        model.tap(Square(coordinate: "e8")!)
        try require(model.busy && store.data.decisions.isEmpty, "Checkpoint answers bypassed real engine assessment")
        try await waitForAssessment(model)
        try require(model.referenceContinuationNeeded && model.cursor == 1 && model.hasPendingMove && model.awaitingContinue &&
                    model.position == (try? positions[1].applying(move: Move(uci: "e9e8")!)) &&
                    model.lastAssessment != nil && model.feedbackBody.contains("与参考着法不同") && model.feedbackBody.contains("实战原谱") && model.feedbackBody.contains("作答后才"),
                    "An equivalent off-record answer was not accepted with an explicit original-game continuation")
        try require(store.data.decisions.count == 1 && store.data.runs.isEmpty && store.data.resume?.wasRetry == false &&
                    store.data.resume?.acceptedCheckpoint == 1 && store.data.resume?.completedCheckpoints == [1],
                    "Accepted checkpoint was overcounted, lost, or mislabeled a retry")
        let acceptedRunID = store.data.resume!.runID
        let acceptedPosition = model.position
        // Suspending alone does not reveal material or turn an accepted choice into a retry.
        model.suspend(); model.resumeStudy()
        try require(model.referenceContinuationNeeded && model.position == acceptedPosition && model.cursor == 1 &&
                    !model.currentRunUsedHelp && store.data.resume?.runID == acceptedRunID &&
                    store.data.resume?.acceptedCheckpoint == 1 && store.data.resume?.checkpointMove == "e9e8" &&
                    store.data.resume?.completedCheckpoints == [1] && store.data.resume?.wasRetry == false,
                    "A plain suspension lost the accepted checkpoint or incorrectly added assistance")
        // Home exposes course titles and learning goals. Preserve the accepted answer, but
        // the new material-reading contract marks this unfinished test as assisted.
        model.navigate(.home); model.navigate(.study)
        try require(model.referenceContinuationNeeded && model.position == acceptedPosition && model.cursor == 1 &&
                    model.currentRunUsedHelp && model.notice?.contains("含辅助") == true &&
                    store.data.resume?.runID == acceptedRunID && store.data.resume?.acceptedCheckpoint == 1 &&
                    store.data.resume?.checkpointMove == "e9e8" && store.data.resume?.completedCheckpoints == [1] &&
                    store.data.resume?.wasRetry == true && store.data.resume?.hints == 0 && store.data.resume?.errors == 0 &&
                    store.data.decisions.count == 1 && store.data.runs.isEmpty,
                    "Reading navigation lost an accepted checkpoint, failed to mark assistance, or fabricated hint/completion records")
        model.suspend()
        let restoredStore = LearningStore(directory: directory)
        let restored = LearningModel(store: restoredStore, coach: TrainingCoach())
        defer { restored.shutdown() }
        restored.resumeStudy()
        try require(restored.referenceContinuationNeeded && restored.position == acceptedPosition && restored.cursor == 1 &&
                    restoredStore.data.resume?.runID == acceptedRunID && restored.currentRunUsedHelp &&
                    restoredStore.data.resume?.acceptedCheckpoint == 1 && restoredStore.data.resume?.checkpointMove == "e9e8" &&
                    restoredStore.data.resume?.completedCheckpoints == [1] && restoredStore.data.resume?.wasRetry == true &&
                    restoredStore.data.resume?.hints == 0 && restoredStore.data.resume?.errors == 0,
                    "Restart lost the accepted choice, changed run identity, or erased material-reading assistance")
        restored.continueStudy()
        try require(restored.cursor == 2 && restored.position == positions[2] && restored.position != acceptedPosition &&
                    restored.checkpointIndex == 1 && !restored.referenceContinuationNeeded && !restored.hasPendingMove &&
                    restoredStore.data.decisions.count == 1, "Continue appended historical moves to a different branch or recorded context as answers")
        restored.attempt(Move(uci: "f2e1")!)
        try require(restored.busy && restoredStore.data.decisions.count == 1,
                    "Matching the recorded move was accepted without a real before/after assessment")
        try await waitForAssessment(restored)
        try require(restored.referenceContinuationNeeded && !restored.completed && restoredStore.data.runs.isEmpty,
                    "The final accepted checkpoint completed before explicit original-game continuation")
        restored.continueStudy(); restored.continueStudy()
        try require(restored.completed && restored.position == positions.last && restoredStore.data.runs.count == 1 &&
                    restoredStore.data.runs[0].id == acceptedRunID && !restoredStore.data.runs[0].independent &&
                    restoredStore.data.runs[0].wasRetry && restoredStore.data.runs[0].hints == 0 && restoredStore.data.runs[0].errors == 0 &&
                    restoredStore.progress(fixture.id, line.id).completions == 1 && restoredStore.progress(fixture.id, line.id).cleanTests == 0 &&
                    restoredStore.data.decisions.count == 2 && restoredStore.data.resume == nil,
                    "An assisted checkpoint test lost correct answers, completed twice, or falsely earned an independent pass")

        // Read-only lines still retain the full score without manufacturing successful tests.
        var readingLine = line; readingLine.checkpoints = []
        let readingCourse = course("reading-only", readingLine)
        try store.importPack(pack([readingCourse]), builtInIDs: [])
        model.startLesson(readingCourse, mode: .test)
        try require(model.mode == .demonstration && model.checkpointCount == 0, "An empty checkpoint list opened an answerless test")
        model.goToDemoPly(4); model.goToDemoPly(0); model.goToDemoPly(4)
        try require(store.data.runs.filter { $0.lessonID == readingCourse.id }.count == 1 &&
                    store.data.runs.filter { $0.lessonID == readingCourse.id }.allSatisfy { !$0.independent && $0.mode == .demonstration },
                    "Read-only demo seeking awarded or duplicated an independent pass")

        model.startLesson(fixture, mode: .practice); model.hint(); model.switchMode(.test)
        try require(model.currentRunUsedHelp && store.data.resume?.wasRetry == true,
                    "Changing hinted checkpoint practice to test erased assistance")
        model.startLesson(fixture, mode: .demonstration); model.goToDemoPly(2); model.suspend()
        let demoResume = LearningModel(store: LearningStore(directory: directory), coach: TrainingCoach())
        demoResume.resumeStudy()
        try require(demoResume.mode == .demonstration && demoResume.cursor == 2 && !demoResume.referenceContinuationNeeded,
                    "Demonstration resume required completed checkpoints or leaked into a test")
        demoResume.shutdown()

        // Archive restore rejects forged or mismatched checkpoint metadata atomically.
        var archive = restoredStore.data
        archive.resume = StudyResume(lessonID: fixture.id, lineID: line.id, mode: .test, cursor: 1,
                                    hints: 0, errors: 0, wasRetry: false, runID: UUID(), started: Date(), wasUnseen: true,
                                    completedCheckpoints: [1], acceptedCheckpoint: 1, checkpointMove: "e9e8", contentFingerprint: line.contentFingerprint)
        let backupStore = LearningStore(directory: try temporaryDirectory("checkpoint-backup"))
        _ = try backupStore.restoreBackup(JSONEncoder().encode(archive), builtInIDs: Set(LearningModel.builtInLessons.map(\.id)), builtInSources: LearningModel.builtInSources)
        try require(backupStore.data.resume?.acceptedCheckpoint == 1, "Valid accepted-point backup failed to restore")
        let baseline = try backupStore.exportData()
        for fault in 0..<4 {
            var bad = archive
            if fault == 0 { bad.resume?.completedCheckpoints = [1, 1] }
            if fault == 1 { bad.resume?.checkpointMove = "e9e0" }
            if fault == 2 { bad.resume?.contentFingerprint = String(repeating: "0", count: 64) }
            if fault == 3 { bad.resume?.acceptedCheckpoint = 2 }
            try rejects("Corrupted checkpoint resume passed backup validation") {
                _ = try backupStore.restoreBackup(JSONEncoder().encode(bad), builtInIDs: Set(LearningModel.builtInLessons.map(\.id)), builtInSources: LearningModel.builtInSources)
            }
            let afterRejected = try backupStore.exportData()
            try require(afterRejected == baseline, "Rejected checkpoint backup partly changed the archive")
        }
        var changed = archive.resume!
        changed.contentFingerprint = String(repeating: "f", count: 64)
        model.startLesson(fixture, mode: .test, from: 1, restoring: changed)
        try require(model.cursor == 1 && !model.referenceContinuationNeeded && model.currentRunUsedHelp &&
                    store.data.resume?.runID != changed.runID && store.data.resume?.completedCheckpoints == [],
                    "Changed content replayed stale accepted points as independent work")
        let badPosition = try Position(fen: "4k4/9/9/9/3r5/9/9/9/3R5/3K5 w - - 0 1")
        var badOriginal = StudyLine(id: "bad-recorded-move", title: "原谱也可能失误", intent: "核验原着", adaptation: "引擎不盲从棋谱",
                                    startingFEN: badPosition.fen, moves: [StudyMove("d1d4", "故意收录一手会被将死的合法原着")])
        badOriginal.checkpoints = [point(0)]
        let badCourse = course("bad-recorded-course", badOriginal)
        try store.importPack(pack([badCourse]), builtInIDs: [])
        model.startLesson(badCourse, mode: .test); model.attempt(Move(uci: "d1d4")!)
        try require(model.busy && !model.completed, "A losing recorded move was instantly marked correct")
        try await waitForAssessment(model)
        try require(model.lastAssessment?.verdict == .mistake && !model.referenceContinuationNeeded && !model.completed &&
                    store.data.resume?.errors == 1 && store.data.runs.allSatisfy { $0.lessonID != badCourse.id },
                    "Real engine failed to reject a historical move allowing immediate mate: \(model.feedbackBody)")
        let authoredIDs = GuidedCurriculum.chapters.flatMap(\.lessonIDs)
        let authoredSet = Set(authoredIDs)
        let unmapped = model.lessons.filter { $0.isSystematic && !authoredSet.contains($0.id) }.sorted {
            $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order
        }
        try require(model.recommendedLessons.map(\.id) == authoredIDs + unmapped.map(\.id),
                    "Recommendations diverged from chapter order or dropped/reordered imported systematic courses")

        // Every authored key question enters the same real two-position analysis path.
        // The historical move may be good, uncertain, or a mistake; matching it never bypasses evaluation.
        var actualQuestions = 0
        for systematic in SystematicCurriculum.lessons {
            for fullLine in systematic.lines {
                for checkpoint in fullLine.checkpoints ?? [] {
                    model.startLesson(systematic, line: fullLine, mode: .test, from: checkpoint.ply)
                    let decisions = store.data.decisions.count
                    model.attempt(Move(uci: fullLine.moves[checkpoint.ply].uci)!)
                    try require(model.busy && store.data.decisions.count == decisions && !model.completed,
                                "Systematic key point \(systematic.id):\(checkpoint.ply) bypassed engine evaluation")
                    try await waitForAssessment(model)
                    try require(model.lastAssessment != nil && store.data.decisions.count == decisions + 1 &&
                                model.lastAssessment?.move.uci == fullLine.moves[checkpoint.ply].uci,
                                "Systematic key point \(systematic.id):\(checkpoint.ply) did not receive a real completed assessment")
                    actualQuestions += 1
                }
            }
        }
        try require(actualQuestions >= 20, "Systematic curriculum lost its expected complete-game key questions")
        print("PASS: \(checks) cumulative checks including actual-engine checkpoint answers, both sides, original-game continuation, resume and legacy compatibility")
    }
    #endif
}
#endif
