import Foundation

/// One route over authored examples, the full position index and existing review
/// records. Progress is read from LearningStore, never copied into route badges.
extension LearningModel {
    var roadmapRoutes: [LearningRoute] { LearningRoadmapContent.routes }
    var selectedLearningRoute: LearningRoute {
        roadmapRoutes.first { $0.id == store.data.learningJourney?.selectedRouteID } ?? roadmapRoutes[0]
    }
    var journeyPlan: LearningPracticePlan? { store.data.learningJourney?.plan }
    var todayRecommendationTitle: String {
        if let plan = journeyPlan, !plan.isFinished { return "继续这组 · " + plan.title }
        return selectedLearningRoute.title
    }
    var todayRecommendationReason: String {
        if let plan = journeyPlan, !plan.isFinished { return "已完成 \(plan.completedIndices.count) / \(plan.items.count) 项，上次的安排和学习位置已保留。" }
        if !dueReviews.isEmpty { return "先复查一处到期错题，再练当前主题。" }
        return selectedLearningRoute.goal
    }
    var currentRouteGoal: String? {
        guard mode != .test || completed else { return nil }
        return isJourneyStudy ? roadmapRoutes.first { $0.id == journeyPlan?.routeID }?.goal : currentStudyRoute?.goal
    }
    private func itemMatchesCurrent(_ item: LearningPracticeItem) -> Bool {
        switch item.kind {
        case .library: return activeReview == nil && lessonID == "library-" + item.targetID && lineID == LibraryGeneratedStudy.lineID
        case .lesson: return activeReview == nil && lessonID == item.targetID && lineID == item.lineID
        case .review: return activeReview?.id.uuidString == item.targetID
        }
    }
    var isJourneyStudy: Bool {
        guard let plan = journeyPlan, let item = plan.currentItem else { return false }
        return !plan.skippedIndices.contains(plan.cursor) && plan.activeRunID == currentRunIdentity && itemMatchesCurrent(item)
    }
    func openLearningRoadmap() { courseDisplay = .roadmap; navigate(.courses) }
    func selectLearningRoute(id: String) {
        guard roadmapRoutes.contains(where: { $0.id == id }) else { return }
        guard selectedLearningRoute.id != id else { return }
        var state = store.data.learningJourney ?? LearningJourneyState()
        state.selectedRouteID = id
        commitJourney(state)
    }
    private func commitJourney(_ state: LearningJourneyState) {
        do { try store.setLearningJourney(state) }
        catch { notice = "训练安排未保存：" + error.localizedDescription }
    }
    func routeEntries(_ route: LearningRoute) -> [LibraryCourseEntry] {
        if let cached = roadmapEntryCache[route.id] { return cached }
        let entries = libraryCatalog.entries.filter(route.pool.includes)
        roadmapEntryCache[route.id] = entries
        return entries
    }
    func routeTargets(_ route: LearningRoute) -> [StudyTarget] {
        readingCache.routeTargets(id: route.id, revision: store.readingRevision) {
            let lookup = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return route.lessonIDs.flatMap { id -> [StudyTarget] in
                guard let lesson = lookup[id] else { return [] }
                return lesson.lines.filter { $0.checkpoints?.isEmpty != true }.map { StudyTarget(lesson: lesson, line: $0) }
            }
        }
    }
    func routeCoverage(_ route: LearningRoute) -> LearningRouteCoverage {
        readingCache.routeCoverage(id: route.id, revision: store.readingRevision) {
            let targets = routeTargets(route), entries = routeEntries(route)
            var practiced = 0, independent = 0, delayed = 0
            for entry in entries {
                let p = libraryProgress(entryID: entry.id)
                if p.completions > 0 { practiced += 1 }
                if p.cleanTests > 0 { independent += 1 }
                if p.delayedTests > 0 { delayed += 1 }
            }
            return LearningRouteCoverage(coreCompleted: targets.filter { store.progress($0.lesson.id, $0.line.id).completions > 0 }.count,
                coreCount: targets.count, positionCount: entries.count, practicedPositions: practiced,
                independentPositions: independent, delayedPositions: delayed)
        }
    }
    func openRouteExamples(routeID: String) {
        guard let route = roadmapRoutes.first(where: { $0.id == routeID }) else { return }
        selectLearningRoute(id: route.id)
        routeExampleIDs = nil
        openLearningRoadmap()
    }
    func openRoutePositions(routeID: String) {
        guard let route = roadmapRoutes.first(where: { $0.id == routeID }) else { return }
        selectLearningRoute(id: routeID)
        guard !route.pool.sections.isEmpty else { openRouteExamples(routeID: routeID); return }
        openLibraryCourses(section: route.pool.sections.count == 1 ? route.pool.sections[0] : nil)
        libraryRouteFilterID = routeID
    }
    func startRouteExample(routeID: String) {
        guard let route = roadmapRoutes.first(where: { $0.id == routeID }), let target = routeTargets(route).first else { return }
        openRouteStudyTarget(routeID: routeID, lessonID: target.lesson.id, lineID: target.line.id,
                             mode: .demonstration, resumeExisting: false)
    }
    /// Scheduling uses the explicit route, never a hidden free-browser search.
    func recommendedPracticeItems(route: LearningRoute, diagnostic: Bool = false, now: Date = Date()) -> [LearningPracticeItem] {
        let size = min(6, max(3, store.data.dailyMinutes / 5))
        var result: [LearningPracticeItem] = [], seen = Set<String>()
        func append(_ item: LearningPracticeItem) {
            if result.count < size && seen.insert(item.id).inserted { result.append(item) }
        }
        if !diagnostic, let review = store.data.reviews.filter({ !$0.resolved && $0.due <= now }).sorted(by: { $0.due < $1.due }).first {
            append(.init(kind: .review, targetID: review.id.uuidString, title: "回到曾经漏算的局面", reason: "这道错题已到复习时间。先不看答案，重新判断。", mode: .test))
        }
        let targets = routeTargets(route)
        let dueTargets = targets.filter { store.progress($0.lesson.id, $0.line.id).nextReview.map { $0 <= now } ?? false }
        for target in dueTargets.prefix(1) {
            append(.init(kind: .lesson, targetID: target.lesson.id, lineID: target.line.id, title: "精讲例题 · 隔日再试", reason: "这条线路到期复习；不提前展示参考走法。", mode: .test))
        }
        if !diagnostic, let target = targets.first(where: { store.progress($0.lesson.id, $0.line.id).completions == 0 }) ?? targets.first {
            append(.init(kind: .lesson, targetID: target.lesson.id, lineID: target.line.id, title: "把思路用在实战例子里", reason: "先自己走，需要时再打开提示和原谱讲解。", mode: .practice))
        }
        let entries = routeEntries(route)
        // Keep source order inside equal scheduling priorities. No random re-roll
        // on redraw, and no automatic difficulty labels from upstream filenames.
        var prioritized: [(offset: Int, entry: LibraryCourseEntry, rank: Int)] = []
        for (offset, entry) in entries.enumerated() {
            let p = libraryProgress(entryID: entry.id)
            let rank: Int
            if let due = p.nextReview, due <= now { rank = 0 }
            else if p.completions == 0 && p.demonstrations == 0 { rank = 1 }
            else { rank = p.cleanTests == 0 ? 2 : 3 }
            prioritized.append((offset, entry, rank))
        }
        prioritized.sort { $0.rank == $1.rank ? $0.offset < $1.offset : $0.rank < $1.rank }
        let ranked = prioritized.map { $0.entry }
        for entry in ranked {
            let p = libraryProgress(entryID: entry.id), due = p.nextReview.map { $0 <= now } ?? false
            let mode: StudyMode = diagnostic || due || result.count == size - 1 ? .test : .practice
            append(.init(kind: .library, targetID: entry.id,
                title: mode == .test ? "局面检验 · 先不看题型" : entry.title,
                reason: due ? "上次学习已到复习时间。" : mode == .test ? "换一个实际局面，检查能否独立判断。" : "用这一主题的判断方法处理新的局面。", mode: mode))
            if result.count == size { break }
        }
        for target in targets {
            append(.init(kind: .lesson, targetID: target.lesson.id, lineID: target.line.id,
                title: diagnostic || result.count == size - 1 ? "实战关键点 · 独立检验" : "另一种实战应对",
                reason: "使用已核验实战谱例；不同于原谱的合理选择也会实际评估。",
                mode: diagnostic || result.count == size - 1 ? .test : .practice))
            if result.count == size { break }
        }
        return result
    }
    func startRecommendedSession(routeID: String? = nil, diagnostic: Bool = false) {
        if routeID == nil, !diagnostic, let plan = journeyPlan, !plan.isFinished { resumeJourneySession(); return }
        let route = roadmapRoutes.first { $0.id == routeID } ?? selectedLearningRoute
        let items = recommendedPracticeItems(route: route, diagnostic: diagnostic)
        guard !items.isEmpty else { notice = "这个主题暂时没有可练习的内容，请先载入资料。"; return }
        let plan = LearningPracticePlan(id: UUID(), created: Date(), routeID: route.id,
            title: route.title, reason: diagnostic ? "隐藏参考讲解，检查当前主题的独立判断。" : route.goal, items: items)
        do {
            try store.setLearningJourney(.init(selectedRouteID: route.id, plan: plan))
            libraryPlanIDs = []; queue = []; queuedReviews = []
            beginJourneyItem()
        } catch { notice = "训练安排未保存：" + error.localizedDescription }
    }
    func bindJourneyRun(requested: UUID?, continuing: Bool) {
        guard var state = store.data.learningJourney, var plan = state.plan, let item = plan.currentItem,
              itemMatchesCurrent(item), !plan.completedIndices.contains(plan.cursor), !plan.skippedIndices.contains(plan.cursor),
              requested == plan.id || continuing else { return }
        plan.activeRunID = currentRunIdentity; state.plan = plan; commitJourney(state)
    }
    private func beginJourneyItem() {
        guard let plan = journeyPlan, let item = plan.currentItem else { return }
        switch item.kind {
        case .library:
            guard let entry = libraryCatalog.entry(id: item.targetID) else {
                notice = "这一局尚未载入或已不在同步库中。可先载入资料，或跳过这一项；不计完成。"; return
            }
            libraryQuery = ""; libraryFamily = nil; libraryStatusFilter = 0; libraryRouteFilterID = nil
            startLibraryEntry(entry, mode: item.mode, journeyPlanID: plan.id)
        case .lesson:
            guard let lesson = lessons.first(where: { $0.id == item.targetID }), let line = lesson.lines.first(where: { $0.id == item.lineID }) else {
                notice = "这条精讲线路暂不可用，可跳过此项；不会计入完成。"; return
            }
            requestedJourneyPlanID = plan.id; startLesson(lesson, line: line, mode: item.mode)
        case .review:
            guard let review = store.data.reviews.first(where: { $0.id.uuidString == item.targetID }) else {
                notice = "这道错题已不在当前记录，可跳过此项。"; return
            }
            startReview(review); bindJourneyRun(requested: plan.id, continuing: false)
        }
    }
    func resumeJourneySession() {
        guard let plan = journeyPlan else { startRecommendedSession(); return }
        if plan.isFinished { openLearningRoadmap(); return }
        if plan.completedIndices.contains(plan.cursor) || plan.skippedIndices.contains(plan.cursor) { continueJourneySession(); return }
        if isJourneyStudy { navigate(.study); return }
        if let saved = store.data.resume, saved.runID == plan.activeRunID, let item = plan.currentItem,
           item.kind != .review,
           saved.lessonID == (item.kind == .library ? "library-" + item.targetID : item.targetID),
           saved.lineID == (item.kind == .library ? LibraryGeneratedStudy.lineID : item.lineID) { resumeStudy(); return }
        beginJourneyItem()
    }
    func completeJourneyItem(runID: UUID) {
        guard var state = store.data.learningJourney, var plan = state.plan, plan.activeRunID == runID,
              completed, !plan.skippedIndices.contains(plan.cursor), !plan.completedIndices.contains(plan.cursor),
              let item = plan.currentItem, itemMatchesCurrent(item) else { return }
        if item.kind != .review && !store.data.runs.contains(where: { $0.id == runID }) { return }
        // Looking at the answer is useful but cannot consume an item that asks
        // for an actual learner decision. The visible next action restarts it.
        if item.mode != .demonstration && mode == .demonstration { return }
        plan.completedIndices.insert(plan.cursor); state.plan = plan; commitJourney(state)
    }
    func continueJourneySession() {
        guard var state = store.data.learningJourney, var plan = state.plan else { return }
        guard plan.completedIndices.contains(plan.cursor) || plan.skippedIndices.contains(plan.cursor) else {
            if isJourneyStudy && completed { beginJourneyItem() }
            else { resumeJourneySession() }
            return
        }
        if plan.isFinished { openLearningRoadmap(); return }
        guard plan.cursor + 1 < plan.items.count else { return }
        plan.cursor += 1; plan.activeRunID = nil; state.plan = plan
        do { try store.setLearningJourney(state); beginJourneyItem() }
        catch { notice = "下一项尚未开始：" + error.localizedDescription }
    }
    func skipJourneyItem() {
        guard var state = store.data.learningJourney, var plan = state.plan, !plan.isFinished else { return }
        guard !plan.completedIndices.contains(plan.cursor) else { continueJourneySession(); return }
        let skipsCurrentStudy = isJourneyStudy && !completed
        // Skipping never submits a move or produces a StudyRun/clean-test score.
        saveResume(); cancelCurrentOperation()
        plan.skippedIndices.insert(plan.cursor); plan.activeRunID = nil; state.plan = plan
        do {
            try store.setLearningJourney(state)
            if plan.isFinished && skipsCurrentStudy {
                // The retained attempt still needs the normal reading-exposure
                // protection when returning to the route. Record it here, in
                // the explicit skip transition, so navigate does not announce
                // this abandoned item as an ongoing independent test.
                _ = recordMaterialExposure()
                saveResume()
            }
            continueJourneySession()
        }
        catch { notice = "跳过操作未保存：" + error.localizedDescription }
    }
    var studyCompletionSummary: StudyCompletionSummary? {
        guard completed else { return nil }
        if let review = activeReview {
            let latest = store.data.reviews.first { $0.id == review.id }
            return .init(title: currentRunUsedHelp ? "错题重练 · 使用过辅助" : "错题重新判断完成",
                detail: "错题是否移出，仍依据间隔复习的实际结果。", hints: currentRunStatistics.hints,
                errors: currentRunStatistics.errors, independent: !currentRunUsedHelp, delayed: false, nextReview: latest?.due)
        }
        guard let run = store.data.runs.first(where: { $0.id == currentRunIdentity }) else { return nil }
        let title = run.mode == .demonstration ? "看懂了，再自己走" : run.delayed ? "隔日检验通过" : run.independent ? "独立检验通过" : "练习完成 · 尚非独立检验"
        return .init(title: title, detail: run.mode == .demonstration ? "演示只记录看过，不计独立掌握。" : run.independent ? "这次没有提示或重走；换局面和隔日再测，才能看出稳定性。" : "提示、重走和有效练习都会保留，之后再检验独立判断。",
            hints: run.hints, errors: run.errors, independent: run.independent, delayed: run.delayed,
            nextReview: store.progress(run.lessonID, run.lineID).nextReview)
    }
    var studyCompletionNextTitle: String {
        if isJourneyStudy, let plan = journeyPlan {
            if completed && !plan.completedIndices.contains(plan.cursor) { return "回到本题，自己走" }
            return plan.isFinished ? "本组完成 · 回学习路线" : "继续本组下一项"
        }
        if currentStudyRoute != nil { return nextRouteStudyTarget == nil ? "回到谱例目录" : "下一篇谱例" }
        return isLibraryStudy ? "换一道相似局面" : remainingPlanCount > 0 ? "继续今日计划" : "回到学习路线"
    }
    var studyCompletionNextDetail: String {
        if isJourneyStudy, let plan = journeyPlan {
            if completed && !plan.completedIndices.contains(plan.cursor) { return "刚才只完成了演示。本题仍等你实际作答；已经看过的提示记录会保留。" }
            if plan.isFinished { return "完成 \(plan.completedIndices.count) 项，跳过 \(plan.skippedIndices.count) 项。到期复习已在原学习记录中安排。" }
            if plan.items.indices.contains(plan.cursor + 1) { return plan.items[plan.cursor + 1].reason }
        }
        if let route = currentStudyRoute {
            if let next = nextRouteStudyTarget { return "接下来：" + next.line.title + "。也可以回到目录重看前面的谱例。" }
            return "已到「" + route.title + "」目录末篇，可回看任意谱例；到末篇不代表全部独立通过。"
        }
        return "用另一种局面检查思路，不把熟记这一条参考线当成掌握。"
    }
    func continueAfterStudy() {
        if isJourneyStudy { continueJourneySession() }
        else if let route = currentStudyRoute {
            if let next = nextRouteStudyTarget {
                openRouteStudyTarget(routeID: route.id, lessonID: next.lesson.id, lineID: next.line.id,
                                     mode: .practice, resumeExisting: false)
            } else { openCurrentStudyCatalog() }
        }
        else if remainingPlanCount > 0 { nextQueued() }
        else if isLibraryStudy, canStartSimilarLibraryEntry { startSimilarLibraryEntry() }
        else { openLearningRoadmap() }
    }
    var similarLibraryEntries: [LibraryCourseEntry] {
        guard let current = currentLibraryEntry else { return [] }
        let shape = LibraryPositionShape(fen: current.fen), family = current.openingFamily
        let sections = Set(current.memberships.map(\.section))
        return libraryCatalog.entries.filter { other in
            guard other.id != current.id, other.memberships.contains(where: { sections.contains($0.section) }) else { return false }
            if let family { return other.openingFamily == family }
            return shape.distance(to: LibraryPositionShape(fen: other.fen)) <= 2
        }.sorted {
            let left = libraryProgress(entryID: $0.id).completions, right = libraryProgress(entryID: $1.id).completions
            return left == right ? $0.id < $1.id : left < right
        }
    }
    var canStartSimilarLibraryEntry: Bool { !similarLibraryEntries.isEmpty }
    func startSimilarLibraryEntry() {
        guard let entry = similarLibraryEntries.first else { returnToLibraryBrowser(); return }
        libraryQuery = ""; libraryFamily = currentLibraryEntry?.openingFamily; libraryStatusFilter = 0
        libraryRouteFilterID = nil
        startLibraryEntry(entry, mode: .practice)
    }
    func returnToLibraryBrowser() {
        courseDisplay = .positions
        if let entry = currentLibraryEntry {
            librarySelectedEntryID = entry.id
            if let index = libraryFilteredEntries.firstIndex(where: { $0.id == entry.id }) { libraryBrowserPage = index / 50 }
        }
        navigate(.courses)
    }
}
