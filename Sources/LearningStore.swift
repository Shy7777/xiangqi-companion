import Foundation
import Combine

struct StudyPack: Codable, Sendable {
    var version = 1
    var title: String
    var sources: [LearningSource]
    var lessons: [LearningLesson]

    /// The initializer is file-scoped so callers cannot label an unchecked pack
    /// as validated. This immutable result can cross the background/UI boundary.
    struct Validated: Sendable {
        fileprivate let pack: StudyPack
        fileprivate let existingLessonIDs: Set<String>
        fileprivate init(pack: StudyPack, existingLessonIDs: Set<String>) {
            self.pack = pack; self.existingLessonIDs = existingLessonIDs
        }
        var lessonCount: Int { pack.lessons.count }
    }

    func preparedForImport(existingLessonIDs: Set<String>) throws -> Validated {
        try validate(existingLessonIDs: existingLessonIDs)
        return Validated(pack: self, existingLessonIDs: existingLessonIDs)
    }

    func validate(existingLessonIDs: Set<String> = []) throws {
        guard version == 1, !lessons.isEmpty, lessons.count <= 250 else {
            throw StudyError.invalidContent("需要版本 1 的课程包，每包 1–250 课。")
        }
        guard Set(lessons.map(\.id)).count == lessons.count,
              Set(sources.map(\.id)).count == sources.count else {
            throw StudyError.invalidContent("课程或来源编号重复。")
        }
        let sourceIDs = Set(sources.map(\.id))
        for source in sources {
            guard let url = URL(string: source.url), url.scheme == "https", url.host != nil else {
                throw StudyError.invalidContent("资料链接必须是 HTTPS 网页。")
            }
        }
        let allIDs = Set(lessons.map(\.id)).union(existingLessonIDs)
        for lesson in lessons {
            guard !lesson.id.isEmpty, !lesson.id.contains("/"), !lesson.title.isEmpty, !lesson.goal.isEmpty,
                  !lesson.principle.isEmpty, !lesson.whenToAdapt.isEmpty,
                  !existingLessonIDs.contains(lesson.id), !lesson.lines.isEmpty,
                  lesson.lines.count <= 80, Set(lesson.lines.map(\.id)).count == lesson.lines.count,
                  lesson.sourceIDs.allSatisfy({ sourceIDs.contains($0) }),
                  lesson.prerequisites.allSatisfy({ allIDs.contains($0) }) else {
                throw StudyError.invalidContent("\(lesson.title)：重复编号、缺失目标、来源或先修课。")
            }
            if let guide = lesson.guide {
                guard !lesson.sourceIDs.isEmpty, !guide.level.isEmpty, !guide.reading.isEmpty,
                      !guide.questions.isEmpty, guide.questions.allSatisfy({ !$0.isEmpty }),
                      !guide.workflow.isEmpty, guide.workflow.allSatisfy({ !$0.isEmpty }), !guide.takeaway.isEmpty else {
                    throw StudyError.invalidContent("\(lesson.title)：系统导读需要明确的阅读来源、问题、学习步骤与总结。")
                }
            }
            for line in lesson.lines {
                guard !line.id.isEmpty, !line.id.contains("/"), !line.moves.isEmpty, line.moves.count <= 400,
                      line.checkpoints != nil || line.moves.allSatisfy({ !$0.explanation.isEmpty && !$0.hint.isEmpty }) else {
                    throw StudyError.invalidContent("\(lesson.title) / \(line.title)：缺少走法或讲解。")
                }
                if let checkpoints = line.checkpoints {
                    let plies = checkpoints.map(\.ply)
                    guard Set(plies).count == plies.count, plies == plies.sorted(),
                          checkpoints.allSatisfy({ (0..<line.moves.count).contains($0.ply) && !$0.title.isEmpty &&
                              !$0.prompt.isEmpty && !$0.focus.isEmpty && !$0.explanation.isEmpty }) else {
                        throw StudyError.invalidContent("\(lesson.title)：关键点必须依次排列、不能重复，且题目与讲解完整。")
                    }
                }
                if let game = line.game {
                    guard [game.red, game.black, game.event, game.date, game.result].allSatisfy({ !$0.isEmpty }),
                          let url = URL(string: game.sourceURL), url.scheme == "https", url.host != nil else {
                        throw StudyError.invalidContent("\(lesson.title)：实战棋谱需要完整对局信息与 HTTPS 原始来源。")
                    }
                }
                do {
                    let positions = try line.positions()
                    guard line.checkpoints != nil || positions.dropLast().contains(where: { $0.sideToMove == line.studentSide }) else {
                        throw StudyError.invalidContent("路线至少需要一手由学生实际作答，不能只自动播放对手走法。")
                    }
                    if let variations = line.variations {
                        guard variations.count <= StudyVariation.maximumPerLine, Set(variations.map(\.id)).count == variations.count else {
                            throw StudyError.invalidContent("每条原谱最多 16 个变式，且变式编号不能重复。")
                        }
                        for variation in variations { _ = try variation.positions(parent: line, parentPositions: positions) }
                    }
                }
                catch { throw StudyError.invalidContent("\(lesson.title) / \(line.title)：\(error.localizedDescription)") }
            }
        }
        let prerequisites = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0.prerequisites) })
        var visiting = Set<String>(), visited = Set<String>()
        func visit(_ id: String) throws {
            guard !visited.contains(id), let parents = prerequisites[id] else { return }
            guard visiting.insert(id).inserted else {
                throw StudyError.invalidContent("先修课存在循环：\(id)。")
            }
            for parent in parents { try visit(parent) }
            visiting.remove(id); visited.insert(id)
        }
        for lesson in lessons { try visit(lesson.id) }
    }
}

struct StudyDecision: Identifiable, Codable {
    let id: UUID
    let date: Date
    let lessonID: String
    let lineID: String
    let ply: Int
    let mode: StudyMode
    let move: String
    let outcome: String
    let hintLevel: Int
    let wasRetry: Bool
}

struct StudyRun: Identifiable, Codable {
    let id: UUID
    let date: Date
    let lessonID: String
    let lineID: String
    let mode: StudyMode
    let hints: Int
    let errors: Int
    let wasRetry: Bool
    let independent: Bool
    let delayed: Bool
    let transfer: Bool
}

struct LineProgress: Codable {
    var demonstrations = 0
    var completions = 0
    var cleanTests = 0
    var delayedTests = 0
    var lastStudied: Date? = nil
    var nextReview: Date? = nil
}

struct ReviewItem: Identifiable, Codable {
    let id: UUID
    let created: Date
    var due: Date
    var lastReviewed: Date? = nil
    var lastAssisted: Date? = nil
    var successfulReviews = 0
    var occurrences = 1
    let lessonID: String?
    let lineID: String?
    let title: String
    let fen: String
    let attempted: String
    let suggested: String
    let detail: String
    let replyPV: [String]
    var resolved: Bool { successfulReviews >= 2 }
}

struct GameMoveReview: Identifiable, Codable {
    var id: Int { ply }
    let ply: Int
    let fen: String
    let move: String
    let bestMove: String?
    let verdict: String
    let detail: String
    let lossCP: Int?
    let bestPV: [String]
    let replyPV: [String]
}

struct TrainingGame: Identifiable, Codable {
    let id: UUID
    let started: Date
    let startFEN: String
    let player: Side
    let level: Int
    var moves: [String] = []
    var reviews: [GameMoveReview] = []
    var result: String? = nil

    func positions() throws -> [Position] {
        var p = try Position(fen: startFEN)
        var result = [p]
        for text in moves {
            guard let move = Move(uci: text) else { throw StudyError.invalidMove(text) }
            p = try p.applying(move: move); result.append(p)
        }
        return result
    }
}

struct StudyResume: Codable {
    let lessonID: String
    let lineID: String
    let mode: StudyMode
    let cursor: Int
    let hints: Int
    let errors: Int
    var wasRetry: Bool
    let runID: UUID
    let started: Date
    let wasUnseen: Bool
    var completedCheckpoints: [Int]? = nil
    var acceptedCheckpoint: Int? = nil
    var checkpointMove: String? = nil
    var contentFingerprint: String? = nil
    // Optional navigation context; older archives remain compatible. This is
    // never used as learning evidence or as a second completion counter.
    var routeID: String? = nil
}

/// A stable reference into a private book. No original text or copied tree is
/// placed in the shared learning archive; the source hash isolates editions.
struct BookStudySource: Codable, Equatable, Sendable {
    let bookSHA: String
    let recordID: String
    let nodeID: Int
    let title: String

    var lessonID: String { "book-" + bookSHA + "-" + recordID }
    var lineID: String { "node-\(nodeID)" }
    var key: String { lessonID + "/" + lineID }

    func validate() throws {
        guard bookSHA.count == 64,
              bookSHA.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              !recordID.isEmpty, recordID.utf8.count <= 128,
              recordID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }),
              (0..<500_000).contains(nodeID), !title.isEmpty, title.utf8.count <= 4096 else {
            throw StudyError.invalidContent("棋书学习的来源或节点编号无效。")
        }
    }
}

/// Navigation and unfinished work only. Evidence remains in StudyRun,
/// StudyDecision and ReviewItem, shared with the existing training system.
struct BookPracticeResume: Codable, Equatable, Sendable {
    let source: BookStudySource
    let unitID: String
    let checkpointIndex: Int
    let stage: String
    let positionFEN: String
    let studentSide: Side
    let attemptedMove: String?
    let hintLevel: Int
    let hints: Int
    let errors: Int
    let wasRetry: Bool
    let runID: UUID
    let started: Date
    let wasUnseen: Bool
    let lastMove: String?
    let completedCheckpointIDs: [String]

    func validate() throws {
        try source.validate()
        let timestamp = started.timeIntervalSince1970
        guard !unitID.isEmpty, unitID.utf8.count <= 512,
              (0..<500_000).contains(checkpointIndex),
              ["reading", "decision", "feedback", "comparison", "summary"].contains(stage),
              positionFEN.utf8.count <= 256, (0...3).contains(hintLevel), hints >= 0, errors >= 0,
              hints <= 1_000_000, errors <= 1_000_000,
              timestamp.isFinite, (-62_135_596_800...253_402_300_799).contains(timestamp),
              attemptedMove.map({ Move(uci: $0) != nil }) ?? true,
              lastMove.map({ Move(uci: $0) != nil }) ?? true,
              completedCheckpointIDs.count <= 500,
              Set(completedCheckpointIDs).count == completedCheckpointIDs.count,
              completedCheckpointIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }) else {
            throw StudyError.invalidContent("棋书课堂的续学位置或练习记录无效。")
        }
        let position = try Position(fen: positionFEN)
        try position.validate()
    }
}

struct LearningArchive: Codable {
    var version = 1
    var progress: [String: LineProgress] = [:]
    var decisions: [StudyDecision] = []
    var runs: [StudyRun] = []
    var reviews: [ReviewItem] = []
    var games: [TrainingGame] = []
    var importedLessons: [LearningLesson] = []
    var importedSources: [LearningSource] = []
    var bookmarks: Set<String> = []
    var exposedLines: Set<String> = []
    var lastAssisted: [String: Date] = [:]
    var resume: StudyResume? = nil
    var dailyMinutes = 20
    /// One generated reference line, not a second copy of the source library.
    /// Optional for compatibility with every existing version-1 archive.
    var libraryStudy: LibraryGeneratedStudy? = nil
    var learningJourney: LearningJourneyState? = nil
    var bookResume: BookPracticeResume? = nil
    var bookSources: [String: BookStudySource]? = nil
}

@MainActor
final class LearningStore: ObservableObject {
    @Published private(set) var data = LearningArchive() {
        didSet { readingRevision &+= 1 }
    }
    /// Invalidates ephemeral reading projections after every archive mutation,
    /// including restore/import. Not persisted; archive writes remain unchanged.
    private(set) var readingRevision: UInt64 = 0
    @Published private(set) var error: String?
    let directory: URL
    private var readOnlyAfterCorruption = false

    init(directory: URL? = nil) {
        let override = ProcessInfo.processInfo.environment["XQ_COMPANION_STATE_DIR"]
        self.directory = directory ?? override.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("XiangqiCompanionOpenSource", isDirectory: true)
        let url = self.directory.appendingPathComponent("learning.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            data = try JSONDecoder().decode(LearningArchive.self, from: Data(contentsOf: url))
            guard data.version == 1 else { throw StudyError.invalidContent("学习记录版本暂不支持。") }
            try data.libraryStudy?.validate()
            try data.learningJourney?.validate()
            try Self.validateBookState(data)
        } catch {
            self.error = "学习记录无法读取，原文件已保留。请先导出或检查备份；本次不会覆盖它。"
            readOnlyAfterCorruption = true
            data = LearningArchive()
        }
    }

    nonisolated static func key(_ lessonID: String, _ lineID: String) -> String { lessonID + "/" + lineID }
    private nonisolated static func isDelayed(since prior: Date, now: Date) -> Bool {
        now.timeIntervalSince(prior) >= 20 * 3600 && !Calendar.current.isDate(prior, inSameDayAs: now)
    }
    func progress(_ lessonID: String, _ lineID: String) -> LineProgress {
        data.progress[Self.key(lessonID, lineID)] ?? LineProgress()
    }
    func setResume(_ value: StudyResume?) { data.resume = value; save() }

    func bookSource(lessonID: String, lineID: String) -> BookStudySource? {
        data.bookSources?[Self.key(lessonID, lineID)]
    }

    @discardableResult
    func registerBookSource(_ source: BookStudySource) -> Bool {
        do { try source.validate() }
        catch { self.error = error.localizedDescription; return false }
        guard data.bookSources?[source.key] != source else { return true }
        var replacement = data
        var sources = replacement.bookSources ?? [:]
        sources[source.key] = source; replacement.bookSources = sources
        return commitBookState(replacement)
    }

    /// Opening a complete record exposes more than the current question. Batch
    /// the small source index in one write, without storing original book text.
    @discardableResult
    func markBookSourcesExposed(_ values: [BookStudySource], now: Date = Date()) -> Bool {
        var replacement = data
        var sources = replacement.bookSources ?? [:]
        for source in values {
            do { try source.validate() }
            catch { self.error = error.localizedDescription; return false }
            sources[source.key] = source
            replacement.exposedLines.insert(source.key)
            replacement.lastAssisted[source.key] = now
        }
        replacement.bookSources = sources
        return commitBookState(replacement)
    }

    @discardableResult
    func setBookResume(_ value: BookPracticeResume?) -> Bool {
        if data.bookResume == value && error == nil { return true }
        var replacement = data
        replacement.bookResume = value
        if let value {
            var sources = replacement.bookSources ?? [:]
            sources[value.source.key] = value.source; replacement.bookSources = sources
        }
        return commitBookState(replacement)
    }

    private static func validateBookState(_ archive: LearningArchive) throws {
        try archive.bookResume?.validate()
        let sources = archive.bookSources ?? [:]
        guard sources.count <= 5_000 else { throw StudyError.invalidContent("棋书学习索引过大，原记录已保留。") }
        for (key, source) in sources {
            try source.validate()
            guard key == source.key else { throw StudyError.invalidContent("棋书来源与学习编号不匹配。") }
        }
        if let resume = archive.bookResume, sources[resume.source.key] == nil {
            throw StudyError.invalidContent("棋书续学记录缺少对应来源。")
        }
    }

    private func commitBookState(_ replacement: LearningArchive) -> Bool {
        guard !readOnlyAfterCorruption else {
            error = "学习记录已保护，未覆盖原来的棋书进度。"; return false
        }
        do {
            try Self.validateBookState(replacement)
            let bytes = try JSONEncoder().encode(replacement)
            guard bytes.count <= 8_000_000 else { throw StudyError.invalidContent("学习记录已到容量上限，请先导出备份。") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("learning.json")
            if let previous = try? Data(contentsOf: url) {
                try previous.write(to: directory.appendingPathComponent("learning.previous.json"), options: .atomic)
            }
            try bytes.write(to: url, options: .atomic)
            data = replacement; error = nil; return true
        } catch { self.error = "棋书进度未保存，原记录保持不变：\(error.localizedDescription)"; return false }
    }
    func setLearningJourney(_ value: LearningJourneyState) throws {
        guard !readOnlyAfterCorruption else { throw StudyError.invalidContent("学习记录已保护，尚未更改训练安排。") }
        try value.validate()
        var replacement = data; replacement.learningJourney = value
        let bytes = try JSONEncoder().encode(replacement)
        guard bytes.count <= 8_000_000 else { throw StudyError.invalidContent("学习记录容量不足，原训练安排保留。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("learning.json")
        if let previous = try? Data(contentsOf: url) {
            try previous.write(to: directory.appendingPathComponent("learning.previous.json"), options: .atomic)
        }
        try bytes.write(to: url, options: .atomic)
        data = replacement; error = nil
    }
    /// Publish the generated lesson and remove only its obsolete resume in one
    /// archive write. Never leave a resume pointing at an evicted generated line.
    func installLibraryStudy(_ value: LibraryGeneratedStudy) throws {
        guard !readOnlyAfterCorruption else { throw StudyError.invalidContent("学习记录已保护，请先处理损坏的记录；本次未替换教程。") }
        try value.validate()
        var replacement = data
        if let prior = replacement.libraryStudy, replacement.resume?.lessonID == prior.lesson.id,
           prior.lesson != value.lesson { replacement.resume = nil }
        replacement.libraryStudy = value
        let bytes = try JSONEncoder().encode(replacement)
        // Reserve more than a complete bounded StudyResume and its next decision
        // so installing the reference cannot consume the space needed to resume it.
        guard bytes.count <= 8_000_000 - 16_384 else { throw StudyError.invalidContent("学习记录接近 8 MB 上限，请先导出备份；本次未替换当前教程。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("learning.json")
        if FileManager.default.fileExists(atPath: target.path) {
            let prior = try Data(contentsOf: target)
            try prior.write(to: directory.appendingPathComponent("learning.previous.json"), options: .atomic)
        }
        try bytes.write(to: target, options: .atomic)
        data = replacement
        error = nil
    }

    func libraryProgress(entryID: String) -> LineProgress {
        progress("library-" + entryID, LibraryGeneratedStudy.lineID)
    }

    /// Exposure is tied to the canonical position, including before its first
    /// generated lesson. Source aliases cannot turn a seen answer into a new test.
    func markLibraryExposed(entryID: String, now: Date = Date()) {
        guard entryID.count == 64, entryID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return }
        let lessonID = "library-" + entryID
        let key = Self.key(lessonID, LibraryGeneratedStudy.lineID)
        data.exposedLines.insert(key); data.lastAssisted[key] = now
        if data.resume?.lessonID == lessonID { data.resume?.wasRetry = true }
        save()
    }

    func libraryWasRecentlyAssisted(entryID: String, now: Date = Date()) -> Bool {
        recentlyAssisted(lessonID: "library-" + entryID, lineID: LibraryGeneratedStudy.lineID, now: now)
    }
    func recentlyAssisted(lessonID: String, lineID: String, now: Date = Date()) -> Bool {
        guard let prior = data.lastAssisted[Self.key(lessonID, lineID)] else { return false }
        return !Self.isDelayed(since: prior, now: now)
    }
    func setDailyMinutes(_ value: Int) { data.dailyMinutes = [10,20,30,45].contains(value) ? value : 20; save() }
    func bookmark(_ id: String) {
        if data.bookmarks.contains(id) { data.bookmarks.remove(id) } else { data.bookmarks.insert(id) }
        save()
    }
    func recordDecision(_ value: StudyDecision) {
        guard !data.decisions.contains(where: { $0.id == value.id }) else { return }
        data.decisions.append(value)
        pruneLibraryDetails()
        save()
    }
    func markExposed(_ lesson: String, _ line: String, assisted: Bool, now: Date = Date()) {
        let key = Self.key(lesson, line)
        data.exposedLines.insert(key)
        if assisted { data.lastAssisted[key] = now }
        save()
    }
    /// Viewing a branch is exposure, not a completed lesson or a numbered hint.
    func markVariationExposed(_ lesson: String, _ line: String, now: Date = Date()) {
        let key = Self.key(lesson, line)
        data.exposedLines.insert(key); data.lastAssisted[key] = now
        if data.resume?.lessonID == lesson && data.resume?.lineID == line { data.resume?.wasRetry = true }
        save()
    }
    /// Reading is assistance, not a numbered hint or a completed exercise.
    /// Batch all material lines and any unfinished saved test into one write;
    /// saved resumes may still be active while another page is on screen.
    @discardableResult
    func markMaterialExposed(_ material: LearningLesson?,
                             activeLine: (lessonID: String, lineID: String)? = nil,
                             activeReviewID: UUID? = nil, now: Date = Date()) -> Bool {
        var keys = Set<String>()
        if let material { keys.formUnion(material.lines.map { Self.key(material.id, $0.id) }) }
        if let activeLine { keys.insert(Self.key(activeLine.lessonID, activeLine.lineID)) }
        if let saved = data.resume, !data.runs.contains(where: { $0.id == saved.runID }),
           saved.mode == .test || saved.lessonID == material?.id {
            keys.insert(Self.key(saved.lessonID, saved.lineID))
            data.resume?.wasRetry = true
        }
        var reviewChanged = false
        if let activeReviewID, let index = data.reviews.firstIndex(where: { $0.id == activeReviewID }) {
            data.reviews[index].lastAssisted = now
            reviewChanged = true
        }
        guard !keys.isEmpty || reviewChanged else { return false }
        for key in keys { data.exposedLines.insert(key); data.lastAssisted[key] = now }
        save()
        return true
    }
    func finishRun(id: UUID, lessonID: String, lineID: String, mode: StudyMode,
                   hints: Int, errors: Int, wasRetry: Bool, wasUnseen: Bool, now: Date = Date()) {
        guard !data.runs.contains(where: { $0.id == id }) else {
            if data.resume?.runID == id { data.resume = nil; save() }
            return
        }
        let key = Self.key(lessonID, lineID)
        var p = data.progress[key] ?? LineProgress()
        let recentlyHelpedBook = data.bookSources?[key] != nil && recentlyAssisted(lessonID: lessonID, lineID: lineID, now: now)
        let independent = mode == .test && hints == 0 && errors == 0 && !wasRetry && !recentlyHelpedBook
        let priorExposure = [p.lastStudied, data.lastAssisted[key]].compactMap { $0 }.max()
        let delayed = independent && (priorExposure.map { Self.isDelayed(since: $0, now: now) } ?? false)
        let run = StudyRun(id: id, date: now, lessonID: lessonID, lineID: lineID, mode: mode,
                           hints: hints, errors: errors, wasRetry: wasRetry,
                           independent: independent, delayed: delayed, transfer: independent && wasUnseen)
        data.runs.append(run)
        pruneLibraryDetails()
        if mode == .demonstration { p.demonstrations += 1 } else { p.completions += 1 }
        if independent { p.cleanTests += 1 }
        if delayed { p.delayedTests += 1 }
        let intervals = [1, 3, 7, 14, 30]
        // Repeated tests in one session do not move the spacing ladder.
        // Only a genuinely delayed success advances beyond tomorrow.
        let days = independent ? intervals[min(max(0, p.delayedTests), intervals.count - 1)] : 1
        p.nextReview = now.addingTimeInterval(Double(days) * 86400)
        p.lastStudied = now
        data.progress[key] = p
        if data.resume?.runID == id { data.resume = nil }
        save()
    }

    func addReview(lessonID: String?, lineID: String?, title: String, fen: String,
                   attempted: String, suggested: String, detail: String, replyPV: [String], now: Date = Date()) {
        if let index = data.reviews.firstIndex(where: {
            guard $0.fen == fen && $0.suggested == suggested else { return false }
            // A book error must retain its original lesson/node. Do not merge it
            // with an unrelated course merely because both contain this FEN.
            if lessonID?.hasPrefix("book-") == true || $0.lessonID?.hasPrefix("book-") == true {
                return $0.lessonID == lessonID && $0.lineID == lineID
            }
            return true
        }) {
            data.reviews[index].occurrences += 1
            data.reviews[index].successfulReviews = 0
            data.reviews[index].due = now
        } else {
            data.reviews.append(ReviewItem(id: UUID(), created: now, due: now, lessonID: lessonID,
                                          lineID: lineID, title: title, fen: fen, attempted: attempted,
                                          suggested: suggested, detail: detail, replyPV: replyPV))
        }
        save()
    }
    func markReviewAssisted(_ id: UUID, now: Date = Date()) {
        guard let index = data.reviews.firstIndex(where: { $0.id == id }) else { return }
        data.reviews[index].lastAssisted = now
        save()
    }
    func reviewCompleted(_ id: UUID, clean: Bool, assisted: Bool = false, now: Date = Date()) {
        guard let index = data.reviews.firstIndex(where: { $0.id == id }) else { return }
        var item = data.reviews[index]
        if assisted {
            // Seeing help is a learning exposure, not a new independent success or a tactical failure.
            item.lastAssisted = now
            item.due = now.addingTimeInterval(86400)
        } else if clean {
            // Same-session repetitions are useful practice, not spaced mastery.
            let priorExposure = [item.lastReviewed, item.lastAssisted].compactMap { $0 }.max()
            if priorExposure == nil || Self.isDelayed(since: priorExposure!, now: now) {
                item.successfulReviews += 1
            }
            item.due = now.addingTimeInterval(item.successfulReviews >= 2 ? 7 * 86400 : 86400)
        } else {
            item.successfulReviews = 0; item.due = now.addingTimeInterval(10 * 60)
        }
        item.lastReviewed = now; data.reviews[index] = item; save()
    }
    func saveGame(_ game: TrainingGame) {
        if let index = data.games.firstIndex(where: { $0.id == game.id }) { data.games[index] = game }
        else { data.games.append(game) }
        save()
    }
    func importPack(_ pack: StudyPack, builtInIDs: Set<String>, builtInSources: [LearningSource] = []) throws {
        let existingIDs = builtInIDs.union(data.importedLessons.map(\.id))
        try importPreparedPack(pack.preparedForImport(existingLessonIDs: existingIDs),
                               builtInIDs: builtInIDs, builtInSources: builtInSources)
    }

    func importPreparedPack(_ prepared: StudyPack.Validated, builtInIDs: Set<String>,
                            builtInSources: [LearningSource] = []) throws {
        guard !readOnlyAfterCorruption else {
            throw StudyError.invalidContent("学习记录已保护，请先恢复有效备份；本次未导入课程。")
        }
        let pack = prepared.pack
        guard pack.lessons.allSatisfy({ !$0.id.hasPrefix("library-") && !$0.id.hasPrefix("book-") }) else {
            throw StudyError.invalidContent("library- 和 book- 编号留给局面库与私人棋书，请为导入课程使用不同编号。")
        }
        // Normal UI imports were fully checked off the main actor. If another
        // operation changed available courses in the meantime, validate again.
        let existingIDs = builtInIDs.union(data.importedLessons.map(\.id))
        if prepared.existingLessonIDs != existingIDs {
            try pack.validate(existingLessonIDs: existingIDs)
        }
        let currentSources = Dictionary((builtInSources + data.importedSources).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for source in pack.sources {
            if let existing = currentSources[source.id], existing != source {
                throw StudyError.invalidContent("来源编号 \(source.id) 与已有内容冲突。")
            }
        }
        var replacement = data
        replacement.importedLessons += pack.lessons
        // Retain an identical source locally too, so the imported lessons remain
        // a self-contained archive independent of bundled curriculum revisions.
        let importedIDs = Set(data.importedSources.map(\.id))
        replacement.importedSources += pack.sources.filter { !importedIDs.contains($0.id) }
        // Persistence must succeed before observers see the imported course.
        // Do not use save(), whose best-effort policy is for ongoing practice.
        let bytes = try JSONEncoder().encode(replacement)
        guard bytes.count <= 8_000_000 else {
            throw StudyError.invalidContent("导入后学习记录会超过 8 MB，原课程和记录保持不变。")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("learning.json")
        if FileManager.default.fileExists(atPath: target.path) {
            let previous = try Data(contentsOf: target)
            try previous.write(to: directory.appendingPathComponent("learning.previous.json"), options: .atomic)
        }
        try bytes.write(to: target, options: .atomic)
        data = replacement
        error = nil
    }
    func exportData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let pretty = try encoder.encode(data)
        if pretty.count <= 8_000_000 { return pretty }
        encoder.outputFormatting = [.sortedKeys]
        let compact = try encoder.encode(data)
        guard compact.count <= 8_000_000 else { throw StudyError.invalidContent("当前学习记录超过可恢复的 8 MB 上限，尚未导出；磁盘原记录仍保留。") }
        return compact
    }

    /// The caller obtains explicit user confirmation before replacing learning
    /// history. Validation finishes before any disk or published-state changes.
    @discardableResult
    func restoreBackup(_ bytes: Data, builtInIDs: Set<String>, builtInSources: [LearningSource]) throws -> URL? {
        guard bytes.count <= 8_000_000 else { throw StudyError.invalidContent("学习备份请控制在 8 MB 内。") }
        let restored = try JSONDecoder().decode(LearningArchive.self, from: bytes)
        try Self.validateBackup(restored, builtInIDs: builtInIDs, builtInSources: builtInSources)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let replacement = try encoder.encode(restored)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("learning.json")
        var preservedURL: URL?
        if FileManager.default.fileExists(atPath: target.path) {
            // Preserve bytes even when the old file is corrupt: its recovery
            // must not depend on our ability to decode it.
            let preceding = try Data(contentsOf: target)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
            let backup = directory.appendingPathComponent("learning.before-restore-\(stamp)-\(UUID().uuidString).json")
            try preceding.write(to: backup, options: .atomic)
            guard try Data(contentsOf: backup) == preceding else {
                throw StudyError.invalidContent("恢复前备份未能完整保存，原学习记录未替换。")
            }
            preservedURL = backup
        }
        try replacement.write(to: target, options: .atomic)
        data = restored
        readOnlyAfterCorruption = false
        error = nil
        return preservedURL
    }

    private static func validateBackup(_ archive: LearningArchive, builtInIDs: Set<String>,
                                       builtInSources: [LearningSource]) throws {
        func check(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw StudyError.invalidContent("学习备份：" + detail) }
        }
        func identifier(_ value: String) -> Bool {
            !value.isEmpty && value.count <= 256 && !value.contains("/") &&
                !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
        func progressKey(_ value: String) -> Bool {
            let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            return parts.count == 2 && parts.allSatisfy(identifier)
        }
        func date(_ value: Date?) -> Bool {
            guard let value else { return true }
            let seconds = value.timeIntervalSince1970
            return seconds.isFinite && (-62_135_596_800...253_402_300_799).contains(seconds)
        }
        func play(_ text: String, from position: Position) throws -> Position {
            guard let move = Move(uci: text) else { throw StudyError.invalidMove(text) }
            return try position.applying(move: move)
        }
        func variation(_ moves: [String], from position: Position) throws {
            try check(moves.count <= 1000, "分析路线过长。")
            var current = position
            for move in moves { current = try play(move, from: current) }
        }

        try check(archive.version == 1, "暂不支持这个记录版本。")
        try archive.libraryStudy?.validate()
        try archive.learningJourney?.validate()
        try Self.validateBookState(archive)
        try check(archive.importedLessons.allSatisfy { !$0.id.hasPrefix("library-") }, "导入课程占用了局面库教程编号。")
        try check([10, 20, 30, 45].contains(archive.dailyMinutes), "每日学习时间无效。")
        try check(Set(archive.decisions.map(\.id)).count == archive.decisions.count &&
                  Set(archive.runs.map(\.id)).count == archive.runs.count &&
                  Set(archive.reviews.map(\.id)).count == archive.reviews.count &&
                  Set(archive.games.map(\.id)).count == archive.games.count,
                  "作答、练习、错题或对局编号重复。")
        try check(Set(archive.importedSources.map(\.id)).count == archive.importedSources.count,
                  "导入资料编号重复。")
        let builtInSourceMap = Dictionary(builtInSources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for source in archive.importedSources {
            try check(identifier(source.id) && !source.title.isEmpty, "资料编号或标题为空。")
            guard let url = URL(string: source.url), url.scheme == "https", url.host != nil else {
                throw StudyError.invalidContent("学习备份的资料链接必须是 HTTPS 网页。")
            }
            if let existing = builtInSourceMap[source.id] {
                try check(existing == source, "资料编号 \(source.id) 与内置来源冲突。")
            }
        }
        let incomingSourceIDs = Set(archive.importedSources.map(\.id))
        let allSources = archive.importedSources + builtInSources.filter { !incomingSourceIDs.contains($0.id) }
        if !archive.importedLessons.isEmpty {
            try StudyPack(title: "恢复的课程", sources: allSources, lessons: archive.importedLessons)
                .validate(existingLessonIDs: builtInIDs)
        }
        let restorable = archive.importedLessons + (archive.libraryStudy.map { [$0.lesson] } ?? [])
        let importedLessons = Dictionary(uniqueKeysWithValues: restorable.map { ($0.id, $0) })
        let knownLessons = builtInIDs.union(importedLessons.keys)

        // Historical counters may outlive a removed bundled lesson, but their
        // identifiers and numerical relationships still need to be coherent.
        for (key, progress) in archive.progress {
            try check(progressKey(key) && progress.demonstrations >= 0 && progress.completions >= 0 &&
                      progress.cleanTests >= 0 && progress.delayedTests >= 0 &&
                      progress.cleanTests <= progress.completions && progress.delayedTests <= progress.cleanTests &&
                      date(progress.lastStudied) && date(progress.nextReview), "线路进度或计数无效。")
        }
        try check(archive.bookmarks.allSatisfy(identifier) && archive.exposedLines.allSatisfy(progressKey),
                  "收藏或已接触线路编号无效。")
        for (key, timestamp) in archive.lastAssisted {
            try check(progressKey(key) && date(timestamp), "提示使用记录无效。")
        }
        for decision in archive.decisions {
            try check(identifier(decision.lessonID) && identifier(decision.lineID) && decision.ply >= 0 &&
                      decision.ply <= 400 && (0...3).contains(decision.hintLevel) && date(decision.date) &&
                      Move(uci: decision.move) != nil && ["course", "alternative", "uncertain", "mistake"].contains(decision.outcome),
                      "作答记录无效。")
        }
        for run in archive.runs {
            let canBeIndependent = run.mode == .test && run.hints == 0 && run.errors == 0 && !run.wasRetry
            try check(identifier(run.lessonID) && identifier(run.lineID) && date(run.date) &&
                      run.hints >= 0 && run.errors >= 0 && (!run.independent || canBeIndependent) &&
                      (!run.delayed || run.independent) && (!run.transfer || run.independent),
                      "练习计数或独立通过标记相互矛盾。")
        }
        if let resume = archive.resume {
            try check(resume.routeID.map { identifier($0) && $0.utf8.count <= 128 } ?? true,
                      "待恢复谱例的主题编号无效。")
            try check(identifier(resume.lessonID) && identifier(resume.lineID) && knownLessons.contains(resume.lessonID) &&
                      (0...400).contains(resume.cursor) && resume.hints >= 0 && resume.errors >= 0 && date(resume.started),
                      "待恢复课程或学习位置无效。")
            let answered = resume.completedCheckpoints ?? []
            try check(Set(answered).count == answered.count && answered.allSatisfy { (0..<400).contains($0) && $0 <= resume.cursor },
                      "关键点恢复记录重复或越界。")
            try check(resume.contentFingerprint.map { $0.count == 64 && $0.allSatisfy { $0.isHexDigit } } ?? true,
                      "课程内容校验编号无效。")
            if let accepted = resume.acceptedCheckpoint {
                try check(accepted == resume.cursor && answered.contains(accepted) && resume.mode != .demonstration &&
                          resume.checkpointMove.flatMap(Move.init(uci:)) != nil, "已答关键点缺少对应的合法走法记录。")
            } else { try check(resume.checkpointMove == nil, "尚未接受的关键点不能带已答走法。") }
            if let lesson = importedLessons[resume.lessonID] {
                guard let line = lesson.lines.first(where: { $0.id == resume.lineID }), resume.cursor <= line.moves.count else {
                    throw StudyError.invalidContent("学习备份的恢复点超出对应课程线路。")
                }
                if let checkpoints = line.checkpoints {
                    let declared = Set(checkpoints.map(\.ply))
                    try check(resume.contentFingerprint == line.contentFingerprint && Set(answered).isSubset(of: declared) &&
                              (resume.mode == .demonstration || resume.wasRetry || Set(declared.filter { $0 < resume.cursor }).isSubset(of: Set(answered))) &&
                              answered.allSatisfy { $0 < resume.cursor || $0 == resume.acceptedCheckpoint },
                              "关键点恢复记录与课程内容不一致。")
                    if let move = resume.checkpointMove {
                        let positions = try line.positions()
                        _ = try play(move, from: positions[resume.cursor])
                    }
                } else {
                    try check(resume.completedCheckpoints == nil && resume.acceptedCheckpoint == nil && resume.contentFingerprint == nil,
                              "非关键点课程不能包含关键点恢复信息。")
                }
            }
        }
        var seenReviews = Set<String>()
        for item in archive.reviews {
            try check(date(item.created) && date(item.due) && date(item.lastReviewed) && date(item.lastAssisted) && item.successfulReviews >= 0 &&
                      item.occurrences > 0 && item.lessonID.map(identifier) != false && item.lineID.map(identifier) != false,
                      "错题日期、编号或复习计数无效。")
            let before = try Position(fen: item.fen)
            let after = try play(item.attempted, from: before)
            _ = try play(item.suggested, from: before)
            try variation(item.replyPV, from: after)
            let sourceSuffix = item.lessonID?.hasPrefix("book-") == true
                ? " " + (item.lessonID ?? "") + "/" + (item.lineID ?? "") : ""
            try check(seenReviews.insert(before.fen + " " + item.suggested + sourceSuffix).inserted,
                      "同一来源、局面和建议重复出现在错题中。")
        }
        for game in archive.games {
            try check(date(game.started) && (0...4).contains(game.level) && game.moves.count <= 10_000,
                      "对局时间、陪练档位或棋谱长度无效。")
            let positions = try game.positions()
            try check(Set(game.reviews.map(\.ply)).count == game.reviews.count, "同一对局半回合被重复复盘。")
            for review in game.reviews {
                try check((1...max(1, game.moves.count)).contains(review.ply) && review.ply <= game.moves.count &&
                          ["exactBest", "good", "inaccuracy", "mistake", "uncertain"].contains(review.verdict) &&
                          (review.lossCP ?? 0) >= 0, "对局复盘的步数、结论或损失分无效。")
                let before = try Position(fen: review.fen)
                try check(before == positions[review.ply - 1] && review.move == game.moves[review.ply - 1],
                          "对局复盘记录与实际走子历史不对应。")
                if let best = review.bestMove {
                    _ = try play(best, from: before)
                    try check(review.bestPV.isEmpty || review.bestPV.first == best, "最佳着法与路线首着不同。")
                }
                try variation(review.bestPV, from: before)
                try variation(review.replyPV, from: positions[review.ply])
            }
        }
    }

    /// Only new library detail logs are rolling; cumulative per-position progress,
    /// unresolved mistakes, authored courses and pre-existing records are retained.
    private func pruneLibraryDetails() {
        var decisions = 0
        data.decisions = data.decisions.reversed().filter {
            guard $0.lessonID.hasPrefix("library-") else { return true }
            decisions += 1; return decisions <= 2_000
        }.reversed()
        var runs = 0
        data.runs = data.runs.reversed().filter {
            guard $0.lessonID.hasPrefix("library-") else { return true }
            runs += 1; return runs <= 1_000
        }.reversed()
        var bookDecisions = 0
        data.decisions = data.decisions.reversed().filter {
            guard $0.lessonID.hasPrefix("book-") else { return true }
            bookDecisions += 1; return bookDecisions <= 4_000
        }.reversed()
        var bookRuns = 0
        data.runs = data.runs.reversed().filter {
            guard $0.lessonID.hasPrefix("book-") else { return true }
            bookRuns += 1; return bookRuns <= 2_000
        }.reversed()
    }

    func save() {
        guard !readOnlyAfterCorruption else { return }
        do {
            let encoded = try JSONEncoder().encode(data)
            guard encoded.count <= 8_000_000 else {
                throw StudyError.invalidContent("学习记录超过 8 MB，尚未保存；请先导出备份，磁盘原记录仍保留。")
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("learning.json")
            // Keep the preceding valid state as a recoverable backup.
            if let previous = try? Data(contentsOf: url) {
                try previous.write(to: directory.appendingPathComponent("learning.previous.json"), options: .atomic)
            }
            try encoded.write(to: url, options: .atomic)
            error = nil
        } catch { self.error = "学习仍可继续，但记录保存失败：\(error.localizedDescription)" }
    }
}
