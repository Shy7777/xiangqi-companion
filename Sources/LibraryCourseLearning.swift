import Foundation

/// The catalog schedules real source positions; the existing learning model owns
/// demonstration, assessment, retry, help tracking and saved progress. No second
/// board, score system or persistent copy of the entire catalog is introduced.
extension LearningModel {
    var isLibraryStudy: Bool { activeReview == nil && lessonID?.hasPrefix("library-") == true }
    var referenceLineName: String { isLibraryStudy ? "引擎参考线" : "实战原谱" }
    var currentLibraryEntry: LibraryCourseEntry? {
        guard isLibraryStudy, let saved = store.data.libraryStudy else { return nil }
        return libraryCatalog.entry(id: saved.entryID)
    }
    var libraryFilteredEntries: [LibraryCourseEntry] {
        libraryFilteredEntries(now: Date())
    }
    /// An explicit clock makes due-date boundaries deterministic in regression
    /// tests. A cached due filter expires at the next actual due date, not a poll.
    func libraryFilteredEntries(now: Date) -> [LibraryCourseEntry] {
        let key = LearningReadingCache.Query(groupID: libraryGroupID, section: librarySection,
            text: String(libraryQuery.prefix(512)), family: libraryFamily, routeID: libraryRouteFilterID,
            status: libraryStatusFilter, progressRevision: (1...3).contains(libraryStatusFilter) ? store.readingRevision : nil)
        return readingCache.filteredEntries(query: key, now: now) {
            let route = roadmapRoutes.first { $0.id == libraryRouteFilterID }
            var nextDue = Date.distantFuture
            let entries = libraryCatalog.entries(in: key.groupID, section: key.section, query: key.text).filter { entry in
                guard libraryFamily == nil || entry.openingFamily == libraryFamily else { return false }
                if let route, !route.pool.includes(entry) { return false }
                // The ordinary browser needs no progress lookups at all.
                guard (1...3).contains(libraryStatusFilter) else { return true }
                let p = libraryProgress(entryID: entry.id)
                switch libraryStatusFilter {
                case 1: return p.completions == 0
                case 2:
                    guard let due = p.nextReview else { return false }
                    if due > now { nextDue = min(nextDue, due) }
                    return due <= now
                default: return p.cleanTests > 0
                }
            }
            return .init(entries: entries, validUntil: nextDue)
        }
    }
    var libraryNavigation: LearningReadingCache.Navigation {
        readingCache.catalogNavigation {
            var counts: [LibraryCourseSection: Int] = [:], families = Set<String>()
            for entry in libraryCatalog.entries {
                for section in Set(entry.memberships.map(\.section)) { counts[section, default: 0] += 1 }
                if let family = entry.openingFamily { families.insert(family) }
            }
            return .init(sectionCounts: counts, openingFamilies: families.sorted())
        }
    }
    var libraryOpeningFamilies: [String] { libraryNavigation.openingFamilies }
    func librarySectionCount(_ section: LibraryCourseSection) -> Int { libraryNavigation.sectionCounts[section, default: 0] }
    var libraryCanContinue: Bool {
        if isJourneyStudy { return journeyPlan?.isFinished == false }
        if libraryPlanIDs.contains(where: { libraryCatalog.entry(id: $0) != nil }) { return true }
        return libraryFilteredEntries.contains { $0.id != currentLibraryEntry?.id }
    }
    func libraryProgress(entryID: String) -> LineProgress { store.libraryProgress(entryID: entryID) }
    func libraryEntryStatus(entryID: String) -> String {
        let value = libraryProgress(entryID: entryID)
        if value.nextReview.map({ $0 <= Date() }) == true { return "待复习" }
        if value.delayedTests > 0 { return "隔日通过" }
        if value.cleanTests > 0 { return "独立通过" }
        if value.completions > 0 { return "练习过" }
        if value.demonstrations > 0 { return "看过演示" }
        return "未练习"
    }
    func libraryGroupProgress(groupID: String) -> (practiced: Int, independent: Int) {
        readingCache.groupProgress(id: groupID, revision: store.readingRevision) {
            var practiced = 0, independent = 0
            for entry in libraryCatalog.entries(in: groupID, section: nil, query: "") {
                let progress = libraryProgress(entryID: entry.id)
                if progress.completions > 0 { practiced += 1 }
                if progress.cleanTests > 0 { independent += 1 }
            }
            return (practiced, independent)
        }
    }
    func openLibraryCourses(section: LibraryCourseSection? = nil) {
        useAuthoredCourses = false; librarySection = section; libraryGroupID = nil
        libraryQuery = ""; libraryFamily = nil; libraryStatusFilter = 0
        libraryRouteFilterID = nil; librarySelectedEntryID = nil; libraryBrowserPage = 0
        navigate(.courses)
    }
    func cancelCurrentOperation() { stopCalculation(); libraryPreparationMessage = "已取消，原学习记录保留。" }

    /// Injectable evaluator supports deterministic cancellation and failure tests;
    /// production uses exactly the shared, local TrainingCoach instance.
    func startLibraryEntry(_ entry: LibraryCourseEntry, mode: StudyMode = .practice, groupID: String? = nil,
                           evaluate supplied: ((Position, Int) async throws -> [EngineLine])? = nil, continuingPlan: Bool = false,
                           journeyPlanID: UUID? = nil) {
        guard let canonical = libraryCatalog.entry(id: entry.id), canonical.fen == entry.fen else {
            notice = "这个局面不在当前题库，请刷新目录后再试。"; return
        }
        let membership = entry.memberships.first(where: { $0.groupID == groupID }) ?? entry.primaryMembership
        guard let membership else { notice = "局面缺少来源，尚未开始教程。"; return }
        if !continuingPlan { libraryPlanIDs = [] }
        saveResume(); cancelOperation()
        if let cached = store.data.libraryStudy, cached.entryID == entry.id {
            libraryGroupID = membership.groupID; librarySection = membership.section
            useAuthoredCourses = false
            requestedJourneyPlanID = journeyPlanID
            startLesson(cached.lesson, mode: mode)
            return
        }
        // No selected lesson, current board or saved resume changes before a full,
        // validated result exists. Cancellation cannot replace an unfinished lesson.
        libraryPreparing = true
        libraryPreparationMessage = "正在为当前局面准备参考续着…"
        let request = libraryToken, commit = libraryCatalog.pwaCommit
        libraryOperation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let generated = try await LibraryLessonBuilder.build(entry: canonical, groupID: membership.groupID,
                    commit: commit, evaluate: { position, budget in
                        if let supplied { return try await supplied(position, budget) }
                        return try await self.coach.evaluate(position: position, movetime: budget)
                    })
                guard self.libraryToken == request, !Task.isCancelled else { return }
                try generated.validate()
                try self.store.installLibraryStudy(generated)
                self.libraryGroupID = membership.groupID; self.librarySection = membership.section
                self.useAuthoredCourses = false
                self.libraryOperation = nil; self.libraryPreparing = false
                self.requestedJourneyPlanID = journeyPlanID
                self.startLesson(generated.lesson, mode: mode)
            } catch {
                guard self.libraryToken == request, !Task.isCancelled else { return }
                self.libraryPreparing = false; self.libraryOperation = nil
                self.libraryPreparationMessage = error.localizedDescription
                self.notice = "这局教程尚未准备成功：\(error.localizedDescription) 原记录保留，也没有计入完成。"
            }
        }
    }
    func startNextLibraryEntry(mode: StudyMode? = nil) {
        if isJourneyStudy { continueJourneySession(); return }
        let nextMode = mode ?? (isLibraryStudy ? self.mode : .practice)
        if !libraryPlanIDs.isEmpty {
            while !libraryPlanIDs.isEmpty {
                let id = libraryPlanIDs.removeFirst()
                if let entry = libraryCatalog.entry(id: id) {
                    startLibraryEntry(entry, mode: libraryPlanMode, groupID: libraryGroupID, continuingPlan: true); return
                }
            }
        }
        let entries = libraryFilteredEntries
        guard !entries.isEmpty else { openLibraryCourses(section: librarySection); return }
        let next: LibraryCourseEntry
        if let current = currentLibraryEntry, let index = entries.firstIndex(where: { $0.id == current.id }) {
            guard entries.count > 1 else { notice = "当前筛选只有这一局。可重新检验，或返回目录选其他局面。"; return }
            next = entries[(index + 1) % entries.count]
        } else {
            next = entries.first(where: { libraryProgress(entryID: $0.id).completions == 0 }) ?? entries[0]
        }
        startLibraryEntry(next, mode: nextMode, groupID: libraryGroupID)
    }
    func startLibraryPlan(diagnostic: Bool = false) {
        startRecommendedSession(diagnostic: diagnostic)
    }
    func recordLibraryExposure(entryID: String) {
        store.markLibraryExposed(entryID: entryID)
        if store.data.libraryStudy?.entryID == entryID, isLibraryStudy {
            _ = recordMaterialExposure(lessonID: lessonID)
        }
    }
    func persistLibraryAssistance() {
        guard isLibraryStudy, let id = store.data.libraryStudy?.entryID else { return }
        store.markLibraryExposed(entryID: id)
    }
}
