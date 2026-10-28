import Foundation

/// A topic's progress, directory, and next/previous navigation all refer to the
/// same StudyTarget (lesson + line). There is no parallel progress store.
extension LearningModel {
    func routeContainingTarget(routeID: String?, lessonID: String, lineID: String) -> LearningRoute? {
        guard let routeID, let route = roadmapRoutes.first(where: { $0.id == routeID }),
              routeTargets(route).contains(where: { $0.lesson.id == lessonID && $0.line.id == lineID }) else { return nil }
        return route
    }
    var currentStudyRoute: LearningRoute? {
        guard activeReview == nil, !isLibraryStudy, let lessonID, let lineID else { return nil }
        return routeContainingTarget(routeID: studyRouteID, lessonID: lessonID, lineID: lineID)
    }
    var currentRouteStudyIndex: Int? {
        guard let route = currentStudyRoute else { return nil }
        return routeTargets(route).firstIndex { $0.lesson.id == lessonID && $0.line.id == lineID }
    }
    var nextRouteStudyTarget: StudyTarget? {
        guard let route = currentStudyRoute, let index = currentRouteStudyIndex else { return nil }
        let targets = routeTargets(route)
        return targets.indices.contains(index + 1) ? targets[index + 1] : nil
    }
    func routeStudyTargetIsResumable(_ target: StudyTarget) -> Bool {
        if activeReview == nil, !completed, lessonID == target.lesson.id, lineID == target.line.id { return true }
        guard let saved = store.data.resume, saved.lessonID == target.lesson.id, saved.lineID == target.line.id else { return false }
        return !store.data.runs.contains { $0.id == saved.runID }
    }
    func openRouteStudyTarget(routeID: String, lessonID targetLessonID: String, lineID targetLineID: String,
                              mode: StudyMode, resumeExisting: Bool = true) {
        guard let route = routeContainingTarget(routeID: routeID, lessonID: targetLessonID, lineID: targetLineID),
              let target = routeTargets(route).first(where: { $0.lesson.id == targetLessonID && $0.line.id == targetLineID }) else {
            notice = "这条谱例不在当前主题目录中，原学习位置已保留。"; return
        }
        selectLearningRoute(id: route.id)
        // Explicit directory navigation is not a request to consume a leftover
        // ad-hoc queue. A persistent training plan itself is retained untouched.
        queue = []; queuedReviews = []; libraryPlanIDs = []; requestedJourneyPlanID = nil
        if resumeExisting, activeReview == nil, !completed, lessonID == targetLessonID, lineID == targetLineID {
            studyRouteID = route.id
            navigate(.study)
            return
        }
        if resumeExisting, let saved = store.data.resume, saved.lessonID == targetLessonID,
           saved.lineID == targetLineID, !store.data.runs.contains(where: { $0.id == saved.runID }) {
            startLesson(target.lesson, line: target.line, mode: saved.mode, from: saved.cursor,
                        restoring: saved, routeID: route.id, detachedFromJourney: true)
            return
        }
        startLesson(target.lesson, line: target.line, mode: mode, routeID: route.id, detachedFromJourney: true)
    }
    func openCurrentStudyCatalog() {
        guard let route = currentStudyRoute else { openLearningRoadmap(); return }
        openRouteExamples(routeID: route.id)
    }
}
