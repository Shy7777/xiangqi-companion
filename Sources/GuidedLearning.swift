import Foundation

/// Bibliographic references only. They never claim that local progress proves a book was read.
struct TextbookChapterReference: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let locator: String
    let note: String
}

struct StudyTextbook: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let author: String
    let edition: String
    let sourceURL: String
    let coverage: String
    let rightsNote: String
    let chapters: [TextbookChapterReference]
}

/// A chapter groups existing lesson IDs; it owns no alternate completion record.
struct GuidedChapter: Identifiable, Codable, Equatable {
    let id: String
    let number: Int
    let title: String
    let subtitle: String
    let goal: String
    let lessonIDs: [String]
    /// IDs of StudyTextbook values, not independent read-completion flags.
    let readingIDs: [String]
    let completionStandard: String
}

struct GuidedLessonStatus: Equatable {
    let lessonID: String
    let totalLineCount: Int
    let practiceLineCount: Int
    let studiedLineCount: Int
    let practicedLineCount: Int
    let testedLineCount: Int
    let delayedLineCount: Int

    init(lesson: LearningLesson, archive: LearningArchive) {
        lessonID = lesson.id
        totalLineCount = lesson.lines.count
        let playable = lesson.lines.filter { !$0.moves.isEmpty && $0.checkpoints?.isEmpty != true }
        practiceLineCount = playable.count
        func progress(_ line: StudyLine) -> LineProgress {
            archive.progress[LearningStore.key(lesson.id, line.id)] ?? LineProgress()
        }
        studiedLineCount = lesson.lines.filter { progress($0).demonstrations > 0 }.count
        practicedLineCount = playable.filter { progress($0).completions > 0 }.count
        testedLineCount = playable.filter { progress($0).cleanTests > 0 }.count
        delayedLineCount = playable.filter { progress($0).delayedTests > 0 }.count
    }

    var isStudied: Bool { totalLineCount > 0 && studiedLineCount == totalLineCount }
    var isPracticed: Bool { practiceLineCount > 0 && practicedLineCount == practiceLineCount }
    var isTested: Bool { practiceLineCount > 0 && testedLineCount == practiceLineCount }
    var isConsolidated: Bool { practiceLineCount > 0 && delayedLineCount == practiceLineCount }
    /// A suggestion only; callers may still let the learner choose another mode.
    var nextMode: StudyMode { isPracticed || isTested || isConsolidated ? .test : isStudied ? .practice : .demonstration }
}

/// The home and chapter views share one tested recommendation policy. Finishing
/// a test never creates an obligation to watch the corresponding demonstration.
struct GuidedStudyRecommendation: Equatable {
    let lessonID: String
    let lineID: String
    let mode: StudyMode

    static func next(chapters: [GuidedChapter], lessons: [LearningLesson], archive: LearningArchive) -> Self? {
        for chapter in chapters {
            for id in chapter.lessonIDs {
                guard let lesson = lessons.first(where: { $0.id == id }) else { continue }
                for line in lesson.lines where line.checkpoints?.isEmpty != true {
                    let progress = archive.progress[LearningStore.key(id, line.id)] ?? LineProgress()
                    guard progress.cleanTests == 0 else { continue }
                    let mode: StudyMode = progress.completions > 0 ? .test : progress.demonstrations > 0 ? .practice : .demonstration
                    return Self(lessonID: id, lineID: line.id, mode: mode)
                }
            }
        }
        return nil
    }

    static func preferredLineID(lesson: LearningLesson, archive: LearningArchive) -> String? {
        let playable = lesson.lines.filter { $0.checkpoints?.isEmpty != true }
        func progress(_ line: StudyLine) -> LineProgress { archive.progress[LearningStore.key(lesson.id, line.id)] ?? LineProgress() }
        return playable.first { progress($0).cleanTests == 0 }?.id
            ?? playable.first { progress($0).delayedTests == 0 }?.id
            ?? lesson.lines.first?.id
    }
}

struct GuidedChapterStatus: Equatable {
    let totalCount: Int
    let studiedCount: Int
    let practicedCount: Int
    let testedCount: Int
    let delayedCount: Int
    let nextLessonID: String?
    let missingLessonIDs: [String]

    init(chapter: GuidedChapter, lessons: [LearningLesson], archive: LearningArchive) {
        var seen = Set<String>()
        let ids = chapter.lessonIDs.filter { seen.insert($0).inserted }
        var lookup: [String: LearningLesson] = [:]
        for lesson in lessons where lookup[lesson.id] == nil { lookup[lesson.id] = lesson }
        let statuses = ids.compactMap { lookup[$0].map { GuidedLessonStatus(lesson: $0, archive: archive) } }
        totalCount = ids.count
        missingLessonIDs = ids.filter { lookup[$0] == nil }
        studiedCount = statuses.filter(\.isStudied).count
        practicedCount = statuses.filter(\.isPracticed).count
        testedCount = statuses.filter(\.isTested).count
        delayedCount = statuses.filter(\.isConsolidated).count
        // Stay with one chapter lesson until its independent test is done. A
        // later interval test is a separate stage, never inferred from rereading.
        nextLessonID = statuses.first { !$0.isTested }?.lessonID ?? statuses.first { !$0.isConsolidated }?.lessonID
    }

    var isStudied: Bool { totalCount > 0 && studiedCount == totalCount && missingLessonIDs.isEmpty }
    var isPracticed: Bool { totalCount > 0 && practicedCount == totalCount && missingLessonIDs.isEmpty }
    var isTested: Bool { totalCount > 0 && testedCount == totalCount && missingLessonIDs.isEmpty }
    var isConsolidated: Bool { totalCount > 0 && delayedCount == totalCount && missingLessonIDs.isEmpty }
}

enum GuidedCatalogValidator {
    static func validate(textbooks: [StudyTextbook], chapters: [GuidedChapter], lessons: [LearningLesson]) throws {
        func filled(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        func identifier(_ value: String) -> Bool { filled(value) && !value.contains("/") }
        guard Set(textbooks.map(\.id)).count == textbooks.count,
              Set(chapters.map(\.id)).count == chapters.count,
              Set(chapters.map(\.number)).count == chapters.count else {
            throw StudyError.invalidContent("教材或章节编号重复。")
        }
        for book in textbooks {
            guard identifier(book.id), [book.title, book.author, book.edition, book.coverage, book.rightsNote].allSatisfy(filled),
                  let url = URL(string: book.sourceURL), url.scheme == "https", url.host != nil,
                  Set(book.chapters.map(\.id)).count == book.chapters.count,
                  book.chapters.allSatisfy({ identifier($0.id) && [$0.title, $0.locator, $0.note].allSatisfy(filled) }) else {
                throw StudyError.invalidContent("教材书目信息、章次定位或正版来源链接不完整。")
            }
        }
        let knownLessons = Set(lessons.map(\.id)), knownBooks = Set(textbooks.map(\.id))
        for chapter in chapters {
            guard identifier(chapter.id), chapter.number > 0,
                  [chapter.title, chapter.subtitle, chapter.goal, chapter.completionStandard].allSatisfy(filled),
                  !chapter.lessonIDs.isEmpty, Set(chapter.lessonIDs).count == chapter.lessonIDs.count,
                  Set(chapter.readingIDs).count == chapter.readingIDs.count,
                  chapter.lessonIDs.allSatisfy({ knownLessons.contains($0) }), chapter.readingIDs.allSatisfy({ knownBooks.contains($0) }) else {
                throw StudyError.invalidContent("章节缺少教学内容，或引用了重复、不存在的课程/教材。")
            }
        }
    }
}
