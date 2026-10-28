#if GUIDED_TESTS
import Foundation

#if GUIDED_MODEL_TESTS && !APP_TESTS
struct RecommendationArrow { let rank: Int; let move: Move }
#endif

@main
@MainActor
struct GuidedLearningTests {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw Failure(message: message) }; checks += 1
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { checks += 1; return }
        throw Failure(message: message)
    }
    static func directory(_ label: String) throws -> URL {
        let configuredBase = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"]
        if let configuredBase {
            precondition((configuredBase as NSString).isAbsolutePath, "XQ_TEST_TEMP_DIR must be an absolute test-owned directory")
        }
        let base = configuredBase.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("guided-learning-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let configuredBase {
            let expected = URL(fileURLWithPath: configuredBase, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
            precondition(url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == expected,
                         "Guided test data escaped XQ_TEST_TEMP_DIR")
        }
        return url
    }
    static let source = LearningSource(id: "guided-test-source", title: "测试资料", url: "https://example.com/book.pdf#page=3", note: "规则与状态测试")
    static func variation(id: String = "black-response", anchor: Int = 1, moves: [String] = ["h9g7", "a3a4", "b9c7"],
                          title: String = "另一种应招", condition: String = "黑方先走另一侧马", explanation: String = "在相同起点比较不同应对") -> StudyVariation {
        StudyVariation(id: id, title: title, anchorPly: anchor, condition: condition, explanation: explanation,
                       moves: moves.map { StudyMove($0, "变式走法说明", hint: "先看直接威胁") })
    }
    static func line(id: String = "guided-test-line") -> StudyLine {
        var value = StudyLine(id: id, title: "主线", intent: "检查局面", adaptation: "依据应手调整",
                              moves: ["b2e2", "b9c7", "h0g2", "h9g7"].map { StudyMove($0, "原谱说明") })
        value.variations = [variation()]; return value
    }
    static func lesson(id: String = "guided-test-lesson", lines: [StudyLine]? = nil) -> LearningLesson {
        LearningLesson(id: id, title: "教材课程", stage: .opening, order: 100, summary: "从章节到练习", goal: "能够比较候选",
                       principle: "先独立判断", whenToAdapt: "应对变化时", pitfalls: [], sourceIDs: [source.id], lines: lines ?? [line()])
    }
    static func pack(_ lessons: [LearningLesson]) -> StudyPack { StudyPack(title: "变式测试", sources: [source], lessons: lessons) }
    static let book = StudyTextbook(id: "book", title: "教材", author: "作者", edition: "公开版", sourceURL: source.url,
                                    coverage: "用于章节结构与谱例研读", rightsNote: "仅链接原站，不声称重制全书",
                                    chapters: [TextbookChapterReference(id: "chapter-reference", title: "章节", locator: "第 1 章，第 3 页", note: "原站定位说明")])
    static func chapter(_ ids: [String], readingIDs: [String] = ["book"]) -> GuidedChapter {
        GuidedChapter(id: "chapter", number: 1, title: "第一章", subtitle: "研究并练习", goal: "学会比较", lessonIDs: ids,
                      readingIDs: readingIDs, completionStandard: "所有谱例练习、无提示检验与隔日巩固")
    }

    static func dataTests() throws {
        let parent = line(), branch = variation()
        let original = try parent.positions(), expanded = try branch.positions(parent: parent)
        try require(expanded[0] == original[1] && expanded.count == branch.moves.count + 1,
                    "Variation used the wrong parent anchor or appended the original continuation")
        try require(expanded[1] != original[2] && expanded.last != original.last,
                    "Variation was silently reattached to the original game")
        let derived = try branch.studyLine(parent: parent)
        try require(derived.startingFEN == original[1].fen && derived.studentSide == .black && derived.moves == branch.moves &&
                    derived.checkpoints?.map(\.ply) == [0, 2] && derived.variations == nil && derived.game == nil,
                    "Derived branch invented historical identity or failed to isolate all learner decisions")
        try require(tryPositions(derived) == expanded, "Derived independent line changed the actual variation")
        try pack([lesson()]).validate(); checks += 1
        var legacy = parent; legacy.variations = nil
        let legacyData = try JSONEncoder().encode(legacy)
        let decodedLegacy = try JSONDecoder().decode(StudyLine.self, from: legacyData)
        try require(decodedLegacy.variations == nil && !String(decoding: legacyData, as: UTF8.self).contains("variations"),
                    "Legacy JSON requires or serializes an absent variation field")
        try require(decodedLegacy.contentFingerprint == legacy.contentFingerprint, "Adding nil variations changed legacy content identity")
        let roundtrip = try JSONDecoder().decode(StudyPack.self, from: JSONEncoder().encode(pack([lesson()])))
        try require(roundtrip.lessons[0].lines[0].variations == [branch], "Course JSON lost variation metadata")
        for invalid in [variation(id: ""), variation(id: "bad/id"), variation(anchor: -1), variation(anchor: parent.moves.count),
                        variation(moves: []), variation(moves: Array(repeating: "h9g7", count: 81)), variation(moves: ["b2e2"]),
                        variation(moves: ["not-a-move"]), variation(title: "  "), variation(condition: ""), variation(explanation: "")] {
            var malformed = parent; malformed.variations = [invalid]
            try rejects("Invalid variation passed full course-pack validation") { try pack([lesson(lines: [malformed])]).validate() }
        }
        var duplicate = parent; duplicate.variations = [branch, branch]
        try rejects("Duplicate variation IDs passed validation") { try pack([lesson(lines: [duplicate])]).validate() }
        var tooMany = parent; tooMany.variations = (0..<17).map { variation(id: "v\($0)") }
        try rejects("Excessive variation count passed validation") { try pack([lesson(lines: [tooMany])]).validate() }
        var missingAnnotation = parent
        missingAnnotation.variations = [StudyVariation(id: "missing", title: "标题", anchorPly: 1, condition: "条件", explanation: "解释",
                                                     moves: [StudyMove("h9g7", "", hint: "")])]
        try rejects("Variation with incomplete per-move annotations passed validation") { try pack([lesson(lines: [missingAnnotation])]).validate() }

        let store = LearningStore(directory: try directory("variation-store"))
        try store.importPack(pack([lesson()]), builtInIDs: [])
        let beforePreview = try store.exportData()
        _ = try branch.positions(parent: parent); _ = try branch.studyLine(parent: parent)
        let afterPreview = try store.exportData()
        try require(beforePreview == afterPreview && store.data.runs.isEmpty && store.data.decisions.isEmpty,
                    "Pure preview mutated learning or scored a viewed answer")
        let resume = StudyResume(lessonID: "guided-test-lesson", lineID: parent.id, mode: .test, cursor: 0,
                                 hints: 0, errors: 0, wasRetry: false, runID: UUID(), started: Date(), wasUnseen: true)
        store.setResume(resume); store.markVariationExposed(resume.lessonID, resume.lineID)
        try require(store.data.resume?.wasRetry == true && store.data.resume?.hints == 0 && store.data.resume?.errors == 0 &&
                    store.data.resume?.cursor == 0 && store.data.resume?.runID == resume.runID && store.data.runs.isEmpty,
                    "Viewing a variation either erased help evidence or changed hint/completion accounting")
        let restarted = LearningStore(directory: store.directory)
        try require(restarted.data.resume?.wasRetry == true && restarted.progress(resume.lessonID, resume.lineID).completions == 0,
                    "Restart erased branch assistance or manufactured course completion")
        store.finishRun(id: resume.runID, lessonID: resume.lessonID, lineID: resume.lineID, mode: .test,
                        hints: 0, errors: 0, wasRetry: store.data.resume!.wasRetry, wasUnseen: false)
        try require(store.data.runs[0].independent == false && store.data.runs[0].hints == 0,
                    "A branch answer viewed during the run was credited as independent")
        let snapshot = try store.exportData()
        var badBackup = store.data; badBackup.importedLessons = [lesson(lines: [duplicate])]
        try rejects("Invalid variations in a backup bypassed complete pack validation") {
            _ = try store.restoreBackup(JSONEncoder().encode(badBackup), builtInIDs: [], builtInSources: [])
        }
        let afterRejection = try store.exportData()
        try require(snapshot == afterRejection, "Rejected variation backup partly wrote learning state")
    }
    static func tryPositions(_ line: StudyLine) -> [Position]? { try? line.positions() }

    static func chapterTests() throws {
        let first = lesson(lines: [line(id: "a"), line(id: "b")]), second = lesson(id: "second", lines: [line(id: "c")])
        let catalog = [first, second], section = chapter(catalog.map(\.id))
        try GuidedCatalogValidator.validate(textbooks: [book], chapters: [section], lessons: catalog); checks += 1
        var archive = LearningArchive()
        var status = GuidedChapterStatus(chapter: section, lessons: catalog, archive: archive)
        try require(status.totalCount == 2 && status.studiedCount == 0 && status.practicedCount == 0 && status.testedCount == 0 &&
                    status.nextLessonID == first.id && !status.isConsolidated, "Unstudied chapter invented progress")
        var progress = LineProgress(); progress.demonstrations = 1
        archive.progress[LearningStore.key(first.id, "a")] = progress
        status = GuidedChapterStatus(chapter: section, lessons: catalog, archive: archive)
        try require(status.studiedCount == 0, "One branch demonstration falsely completed the whole lesson")
        archive.progress[LearningStore.key(first.id, "b")] = progress
        status = GuidedChapterStatus(chapter: section, lessons: catalog, archive: archive)
        try require(status.studiedCount == 1 && status.practicedCount == 0 && status.testedCount == 0,
                    "Demonstration was conflated with practice or an independent test")
        try require(GuidedLessonStatus(lesson: first, archive: archive).nextMode == .practice,
                    "Guided next step ignored demonstrated examples")
        var directlyTested = LearningArchive(), directProgress = LineProgress()
        directProgress.completions = 1; directProgress.cleanTests = 1
        for item in first.lines { directlyTested.progress[LearningStore.key(first.id, item.id)] = directProgress }
        let directStatus = GuidedLessonStatus(lesson: first, archive: directlyTested)
        try require(directStatus.isTested && !directStatus.isStudied && directStatus.nextMode == .test,
                    "An independently passed lesson was sent back to mandatory demonstration or mislabeled already read")
        progress.completions = 1
        for item in first.lines { archive.progress[LearningStore.key(first.id, item.id)] = progress }
        status = GuidedChapterStatus(chapter: section, lessons: catalog, archive: archive)
        try require(status.practicedCount == 1 && status.testedCount == 0 && status.delayedCount == 0,
                    "Assisted practice was counted as independent or delayed mastery")
        progress.cleanTests = 1
        for item in first.lines { archive.progress[LearningStore.key(first.id, item.id)] = progress }
        status = GuidedChapterStatus(chapter: section, lessons: catalog, archive: archive)
        try require(status.testedCount == 1 && status.delayedCount == 0 && status.nextLessonID == second.id,
                    "A same-day test was mislabeled consolidated or blocked the next lesson")
        archive.progress[LearningStore.key(second.id, "c")] = progress
        status = GuidedChapterStatus(chapter: section, lessons: catalog, archive: archive)
        try require(status.isTested && !status.isConsolidated && status.nextLessonID == first.id,
                    "Delayed review was inferred from clean tests without delayedTests evidence")
        progress.delayedTests = 1
        for course in catalog { for item in course.lines { archive.progress[LearningStore.key(course.id, item.id)] = progress } }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(archive)
        status = GuidedChapterStatus(chapter: section, lessons: catalog, archive: archive)
        let after = try encoder.encode(archive)
        try require(status.isConsolidated && status.nextLessonID == nil && status.delayedCount == 2 && before == after,
                    "Pure chapter status persisted a second progress system or failed to use the existing records")
        let missing = GuidedChapterStatus(chapter: chapter([first.id, "missing"]), lessons: catalog, archive: archive)
        try require(missing.totalCount == 2 && missing.missingLessonIDs == ["missing"] && !missing.isTested,
                    "Missing lesson references silently reduced the completion denominator")
        let empty = GuidedChapterStatus(chapter: chapter([]), lessons: catalog, archive: archive)
        try require(!empty.isStudied && !empty.isTested && !empty.isConsolidated, "An empty chapter counted as complete")
        var readOnly = line(); readOnly.checkpoints = []
        let reading = lesson(id: "reading-only", lines: [readOnly])
        archive.progress[LearningStore.key(reading.id, readOnly.id)] = progress
        let readingStatus = GuidedLessonStatus(lesson: reading, archive: archive)
        try require(readingStatus.isStudied && !readingStatus.isPracticed && !readingStatus.isTested,
                    "A reading-only line manufactured a practice or test requirement already marked passed")
        for invalid in [chapter([first.id, first.id]), chapter(["missing"]), chapter([first.id], readingIDs: ["missing"])] {
            try rejects("Invalid guided chapter references passed validation") {
                try GuidedCatalogValidator.validate(textbooks: [book], chapters: [invalid], lessons: catalog)
            }
        }
        try rejects("Duplicate chapter metadata passed validation") {
            try GuidedCatalogValidator.validate(textbooks: [book], chapters: [section, section], lessons: catalog)
        }
    }

    #if GUIDED_MODEL_TESTS
    /// Optional content-audit mode; normal verification does not depend on a
    /// research JSON file or turn short-search scores into content assertions.
    static func probeExamples(path: String) async throws {
        struct Example: Decodable { let id: String; let startingFEN: String; let moves: [String] }
        func argument(_ name: String) -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: name), CommandLine.arguments.indices.contains(index + 1) else { return nil }
            return CommandLine.arguments[index + 1]
        }
        let selectedID = argument("--probe-id"), selectedPly = argument("--probe-ply").flatMap(Int.init)
        let selectedSide: Side = argument("--probe-side") == "black" ? .black : .red
        let movetime = min(5000, max(250, argument("--probe-ms").flatMap(Int.init) ?? 700))
        let examples = try JSONDecoder().decode([Example].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let coach = TrainingCoach(); defer { coach.shutdown() }
        for example in examples where selectedID == nil || selectedID == example.id {
            var position = try Position(fen: example.startingFEN)
            for (ply, text) in example.moves.enumerated() {
                guard let move = Move(uci: text) else { throw StudyError.invalidMove(text) }
                let next = try position.applying(move: move)
                if position.sideToMove == selectedSide && (selectedPly == nil || selectedPly == ply) {
                    let result = try await coach.assess(position: position, move: move, movetime: movetime)
                    print("PROBE \(example.id) ply=\(ply) move=\(text) verdict=\(result.verdict.rawValue) before=\(String(describing: result.beforeScore)) after=\(String(describing: result.afterScore)) best=\(result.bestMove?.uci ?? "-") pv=\(result.replyPV.prefix(4).joined(separator: " "))")
                }
                position = next
            }
        }
    }

    static func modelTests(exerciseCatalog: Bool = true) throws {
        let store = LearningStore(directory: try directory("model")), course = lesson()
        try store.importPack(pack([course]), builtInIDs: Set(LearningModel.builtInLessons.map(\.id)))
        let model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        model.startLesson(course, mode: .test)
        model.tap(Square(coordinate: "b2")!)
        let originalPosition = model.position, originalCursor = model.cursor, originalSelection = model.selected,
            originalTargets = model.targets, originalRun = store.data.resume?.runID, originalHint = model.hintLevel
        let derived = try course.lines[0].variations![0].studyLine(parent: course.lines[0])
        model.startLesson(course, line: derived, mode: .test)
        try require(model.lineID == course.lines[0].id && model.position == originalPosition && store.data.resume?.runID == originalRun,
                    "An unregistered preview line replaced the original course or its scoring identity")
        try require(model.recordVariationExposure(lessonID: course.id, lineID: course.lines[0].id), "A valid branch exposure was not recorded")
        _ = try course.lines[0].variations![0].positions(parent: course.lines[0])
        try require(model.position == originalPosition && model.cursor == originalCursor && model.selected == originalSelection &&
                    model.targets == originalTargets && model.hintLevel == originalHint && !model.busy && !model.hasPendingMove &&
                    store.data.resume?.runID == originalRun && store.data.resume?.hints == 0 && store.data.resume?.wasRetry == true &&
                    store.data.decisions.isEmpty && store.data.runs.isEmpty,
                    "A preview changed the active board/hints or created an independent result")
        model.navigate(.home); model.resumeStudy()
        try require(model.currentRunUsedHelp && model.hintLevel == 0 && model.position == originalPosition,
                    "Reopening the original test erased branch exposure or leaked an arrow")
        model.attempt(Move(uci: "b2e2")!); model.continueStudy()
        model.attempt(Move(uci: "h0g2")!); model.continueStudy()
        try require(model.completed && store.data.runs.last?.independent == false && store.data.runs.last?.hints == 0,
                    "Returning from a viewed variation awarded an independent original-course pass")
        model.startLesson(course, mode: .test)
        let newRun = store.data.resume!.runID
        let gameStart = try course.lines[0].variations![0].positions(parent: course.lines[0])[1]
        try require(model.startVariationGame(lessonID: course.id, lineID: course.lines[0].id, variationID: "black-response", ply: 1),
                    "Explicit variation-to-game handoff failed")
        try require(model.page == .sparring && model.position == gameStart && model.game?.startFEN == gameStart.fen &&
                    model.game?.moves.isEmpty == true && store.data.resume?.runID == newRun && store.data.resume?.wasRetry == true,
                    "Variation practice overwrote original course resume or pasted parent moves into the independent game")
        model.navigate(.study)
        try require(model.position == originalPosition && model.lineID == course.lines[0].id && model.currentRunUsedHelp && model.studyArrows.isEmpty,
                    "Returning from variation practice restored the branch as original-game training")
        let boardBeforeInvalid = model.position, gameID = model.game?.id, runsBeforeInvalid = store.data.runs.count
        try require(!model.startVariationGame(lessonID: course.id, lineID: course.lines[0].id, variationID: "missing") &&
                    !model.startVariationGame(lessonID: course.id, lineID: course.lines[0].id, variationID: "black-response", ply: 999) &&
                    model.position == boardBeforeInvalid && model.game?.id == gameID && store.data.runs.count == runsBeforeInvalid,
                    "An invalid variation request partially changed games or course records")
        let unrelated = lesson(id: "unrelated")
        try store.importPack(pack([unrelated]), builtInIDs: [])
        model.startLesson(unrelated, mode: .test)
        _ = model.recordVariationExposure(lessonID: course.id, lineID: course.lines[0].id)
        try require(!model.currentRunUsedHelp && store.data.resume?.wasRetry == false && model.hintLevel == 0,
                    "Viewing another lesson's variation polluted this unrelated run's hint or test counters")
        guard exerciseCatalog else { return }
        // The public route includes only distributable authored families; external
        // reading links are not playable courses or additional complete games.
        try require(TextbookCurriculum.lessons.isEmpty, "Unlicensed textbook excerpts entered the public route")
        let mainlineFamilies = [OpeningRepertoireCurriculum.lessons,
                                MiddlegameAtlasCurriculum.lessons, EndgameSchoolCurriculum.lessons]
        let mainline = mainlineFamilies.flatMap { $0 }, capstones = SystematicCurriculum.lessons
        let mainlineIDs = Set(mainline.map(\.id)), capstoneIDs = Set(capstones.map(\.id))
        let core = LearningModel.builtInLessons.filter(\.isSystematic)
        let coreIDs = Set(core.map(\.id)), recommendations = model.recommendedLessons
        let routeIDs = GuidedCurriculum.chapters.flatMap(\.lessonIDs)
        try require(mainlineFamilies.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isSystematic) } &&
                    mainlineIDs.count == mainline.count && mainlineIDs.isDisjoint(with: capstoneIDs) &&
                    coreIDs == mainlineIDs.union(capstoneIDs) && core.count == coreIDs.count,
                    "An authored mainline family was omitted, duplicated, or relabeled as a capstone")
        // Recommendations, nextTarget and daily plans share the actual chapter route,
        // rather than inferring placement from numeric content-family order ranges.
        try require(Set(recommendations.map(\.id)) == coreIDs && recommendations.count == coreIDs.count &&
                    recommendations.map(\.id) == routeIDs,
                    "Expanded recommendations omitted/duplicated a core course or diverged from the chapter route")
        let fullGames = core.flatMap(\.lines).filter { $0.game != nil }
        try require(capstones.count == 4 && capstoneIDs.count == 4 && fullGames.count == 4 &&
                    capstones.allSatisfy { $0.lines.count == 1 && $0.lines[0].game != nil } &&
                    mainline.flatMap(\.lines).allSatisfy { $0.game == nil } &&
                    fullGames.allSatisfy { $0.startingFEN == Position.initialFEN && !$0.moves.isEmpty } &&
                    Set(fullGames.compactMap { $0.game?.sourceURL }).count == 4,
                    "Thematic excerpts became extra complete games, or the four distinct original full-game records were lost")
        let knownSources = Set(LearningModel.builtInSources.map(\.id))
        try require(core.allSatisfy { !$0.sourceIDs.isEmpty && $0.sourceIDs.allSatisfy { knownSources.contains($0) } } &&
                    capstones.allSatisfy { course in
                        guard let url = course.lines.first?.game?.sourceURL else { return false }
                        return LearningModel.builtInSources.contains { course.sourceIDs.contains($0.id) && $0.url == url }
                    }, "An expanded course or preserved full-game record lost its actual source reference")
        try StudyPack(title: "Expanded guided mainline", sources: LearningModel.builtInSources, lessons: core).validate()
        checks += 1
        try GuidedCatalogValidator.validate(textbooks: GuidedCurriculum.books, chapters: GuidedCurriculum.chapters, lessons: LearningModel.builtInLessons)
        checks += 1
        try require(Set(routeIDs) == coreIDs &&
                    routeIDs.count == Set(routeIDs).count,
                    "The actual guided route omitted or duplicated an expanded mainline lesson or preserved capstone")
        let integration = GuidedCurriculum.chapters.first { $0.id == "integration" }
        try require(GuidedCurriculum.chapters.last?.id == "integration" &&
                    Set(routeIDs.dropLast(capstones.count)) == mainlineIDs &&
                    integration?.lessonIDs == ["atlas-preparation", "atlas-review"] + capstones.sorted { $0.order < $1.order }.map(\.id),
                    "The final integration chapter lost preparation/review methods or changed the four full-game capstones")
        try require(GuidedCurriculum.books.allSatisfy { !$0.chapters.isEmpty && $0.chapters.allSatisfy { !$0.locator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } },
                    "An actual textbook reference has no chapter/page locator")
    }

    static func planningOrderTests() throws {
        func imported(_ id: String, order: Int) -> LearningLesson {
            var value = LearningLesson(id: id, title: "导入系统课", stage: .opening, order: order,
                summary: "排序回归", goal: "保留章节外的学习内容", principle: "导入不抢占既有章节",
                whenToAdapt: "既有章节学完后继续导入内容", pitfalls: [], sourceIDs: [source.id], lines: [line()])
            value.guide = StudyGuide(level: "测试", reading: "引用测试来源", questions: ["还有哪一课未练过？"],
                workflow: ["完成当前章节后继续下一课"], takeaway: "章节与导入记录共存")
            return value
        }
        // Reverse insertion order and low numeric orders must neither preempt the
        // authored chapters nor destabilize the same-order imported-course suffix.
        let extras = [imported("import-z", order: 1), imported("import-last", order: 2), imported("import-a", order: 1)]
        let store = LearningStore(directory: try directory("planning-order"))
        try store.importPack(pack(extras), builtInIDs: Set(LearningModel.builtInLessons.map(\.id)))
        store.setDailyMinutes(10)
        let model = LearningModel(store: store, coach: TrainingCoach())
        defer { model.shutdown() }
        let routeIDs = GuidedCurriculum.chapters.flatMap(\.lessonIDs)
        let expectedIDs = routeIDs + ["import-a", "import-z", "import-last"]
        try require(model.recommendedLessons.map(\.id) == expectedIDs &&
                    Set(store.data.importedLessons.map(\.id)) == Set(extras.map(\.id)),
                    "Imported systematic lessons disappeared, preempted the chapter route, or lacked stable order/id sorting")
        let restored = LearningModel(store: LearningStore(directory: store.directory), coach: TrainingCoach())
        try require(restored.recommendedLessons.map(\.id) == expectedIDs,
                    "Restart changed the chapter route or imported-course suffix")
        restored.shutdown()
        let catalog = Dictionary(uniqueKeysWithValues: model.lessons.map { ($0.id, $0) })
        for id in expectedIDs {
            guard let course = catalog[id], let first = course.lines.first(where: { $0.checkpoints?.isEmpty != true }) else {
                throw Failure(message: "A planned course has no real practice line: \(id)")
            }
            try require(model.nextTarget?.lesson.id == id && model.nextTarget?.line.id == first.id,
                        "Actual nextTarget skipped the chapter route at \(id)")
            let runs = store.data.runs.count, decisions = store.data.decisions.count
            model.startDailyPlan()
            try require(model.lessonID == id && model.lineID == first.id && model.mode == .practice &&
                        model.page == .study && model.activeReview == nil && !model.busy && model.remainingPlanCount == 0,
                        "Actual ten-minute daily plan did not start the next chapter course at \(id)")
            try require(store.data.runs.count == runs && store.data.decisions.count == decisions,
                        "Planning fabricated completion or answer records at \(id)")
            // Seed completed-practice records, not simulated student answers, to
            // inspect every next-course transition without running 100 engine lessons.
            for branch in course.lines where branch.checkpoints?.isEmpty != true {
                store.finishRun(id: UUID(), lessonID: id, lineID: branch.id, mode: .practice,
                    hints: 0, errors: 0, wasRetry: false, wasUnseen: false)
            }
        }
        try require(store.data.importedLessons.count == extras.count && store.data.decisions.isEmpty &&
                    model.recommendedLessons.map(\.id) == expectedIDs,
                    "Advancing the actual plan changed imported content or manufactured student decisions")
    }
    #endif

    static func recommendationTests() throws {
        let course = lesson(lines: [line(id: "one"), line(id: "two")])
        let route = [chapter([course.id])]
        var archive = LearningArchive()
        func next() -> GuidedStudyRecommendation? {
            GuidedStudyRecommendation.next(chapters: route, lessons: [course], archive: archive)
        }
        try require(next()?.lineID == "one" && next()?.mode == .demonstration, "A new line should begin with its guide")
        let key = LearningStore.key(course.id, "one")
        archive.progress[key] = LineProgress(demonstrations: 1)
        try require(next()?.mode == .practice, "A studied line should offer actual practice")
        archive.progress[key] = LineProgress(completions: 1)
        try require(next()?.mode == .test, "Already practiced material must not force an unwatched demonstration")
        archive.progress[key] = LineProgress(completions: 1, cleanTests: 1)
        try require(next()?.lineID == "two" && next()?.mode == .demonstration, "A direct clean test should advance to the untested branch")
        try require(GuidedStudyRecommendation.preferredLineID(lesson: course, archive: archive) == "two", "Continue chapter returned to its completed first branch")
        archive.progress[LearningStore.key(course.id, "two")] = LineProgress(completions: 1, cleanTests: 1)
        try require(next() == nil, "All independent tests must finish the initial route despite zero demonstrations")
        try require(GuidedStudyRecommendation.preferredLineID(lesson: course, archive: archive) == "one", "Delayed review no longer has a resumable line")
        var readingOnly = line(id: "reading"); readingOnly.checkpoints = []
        let reading = lesson(lines: [readingOnly])
        try require(GuidedStudyRecommendation.next(chapters: route, lessons: [reading], archive: LearningArchive()) == nil,
                    "Reading-only material was presented as a scored independent exercise")
    }

    static func main() async {
        do {
            #if GUIDED_MODEL_TESTS
            if let index = CommandLine.arguments.firstIndex(of: "--probe-json"), CommandLine.arguments.indices.contains(index + 1) {
                try await probeExamples(path: CommandLine.arguments[index + 1]); return
            }
            #endif
            try dataTests(); try chapterTests(); try recommendationTests()
            #if GUIDED_MODEL_TESTS
            try modelTests(exerciseCatalog: !CommandLine.arguments.contains("--bridge-only"))
            if !CommandLine.arguments.contains("--bridge-only") { try planningOrderTests() }
            #endif
            print("PASS: \(checks) guided chapter, legal variation, legacy JSON, isolated preview and existing-progress checks")
        } catch { print("FAIL: \(error)"); exit(1) }
    }
}
#endif
