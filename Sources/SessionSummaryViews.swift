import SwiftUI

extension LearningCenterView {
    var studyShortcutsAllowed: Bool {
        model.page == .study && !model.busy && !model.libraryPreparing && (model.notice == nil || StudyNoticePresentation.isInformational(model.notice))
            && previewLesson == nil && readingSource == nil && variationPreview == nil
            && githubRequest == nil && positionLibraryRequest == nil && !showResourceCatalog
            && !showBranches && !showStudyDetails && !showGameSetup && !showGameHistory && !confirmNewGame
    }

    @ViewBuilder var studySessionProgress: some View {
        if model.isJourneyStudy, let plan = model.journeyPlan {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(plan.isFinished ? "这一组已结束" : "本组 \(min(plan.items.count, plan.cursor + 1)) / \(plan.items.count)")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if !plan.skippedIndices.isEmpty {
                        Text("跳过 \(plan.skippedIndices.count)").font(.system(size: 10)).foregroundColor(Studio.muted)
                    }
                }
                HStack(spacing: 5) {
                    ForEach(Array(plan.items.indices), id: \.self) { index in
                        Capsule().fill(plan.completedIndices.contains(index) ? Studio.accent :
                                        plan.skippedIndices.contains(index) ? Studio.muted.opacity(0.4) : Studio.line)
                            .frame(height: 4)
                            .overlay { if index == plan.cursor && !plan.isFinished { Capsule().strokeBorder(Studio.accent, lineWidth: 1) } }
                            .accessibilityLabel("第 \(index + 1) 项，\(plan.completedIndices.contains(index) ? "已完成" : plan.skippedIndices.contains(index) ? "已跳过" : index == plan.cursor ? "当前" : "未开始")")
                    }
                }
                if model.mode != .test, !model.completed, let item = plan.currentItem {
                    Text(item.reason.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(3)
                }
            }.padding(13).background(Studio.paper, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("study-session-progress")
        }
    }

    @ViewBuilder var studyCompletionCard: some View {
        if let summary = model.studyCompletionSummary {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 9) {
                    Image(systemName: summary.independent ? "checkmark.shield" : "checkmark.circle")
                        .font(.system(size: 23)).foregroundColor(summary.independent ? Studio.accent : Studio.muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.title.simplifiedForDisplay).font(.system(size: 17, weight: .semibold))
                        if summary.delayed { StudioTag(text: "隔日通过") }
                        else if summary.independent { StudioTag(text: "独立通过") }
                    }
                }
                Text(summary.detail.simplifiedForDisplay).font(.system(size: 12)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    completionMetric(summary.hints, "次提示")
                    completionMetric(summary.errors, "次关键偏差")
                }
                if let date = summary.nextReview {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                        Text("下次复习")
                        Text(date, style: .date)
                    }.font(.system(size: 10)).foregroundColor(Studio.muted)
                }
                Divider()
                Text(model.studyCompletionNextTitle.simplifiedForDisplay).font(.system(size: 13, weight: .semibold)).foregroundColor(Studio.accent)
                Text(model.studyCompletionNextDetail.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                if model.canStartSimilarLibraryEntry {
                    Button("另练一个相似局面") { model.startSimilarLibraryEntry() }
                        .buttonStyle(StudioButtonStyle(compact: true)).disabled(model.busy || model.libraryPreparing)
                        .accessibilityIdentifier("study-similar-position")
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Studio.paper, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("study-completion-summary")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.feedbackTitle.simplifiedForDisplay).font(.system(size: 17, weight: .semibold))
                Text(model.feedbackBody.simplifiedForDisplay).font(.system(size: 12)).lineSpacing(5)
                Text(model.studyCompletionNextDetail.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted)
            }.accessibilityIdentifier("study-completion-summary")
        }
    }

    private func completionMetric(_ count: Int, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(count)").font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 10)).foregroundColor(Studio.muted)
        }
    }
}

/// Only attached to visible navigation/retry actions. It is deliberately absent
/// while any learning modal is open, and never bound to an engine move or hint.
struct StudyKeyboardShortcut: ViewModifier {
    let enabled: Bool
    let key: KeyEquivalent
    var modifiers: EventModifiers = []
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.keyboardShortcut(key, modifiers: modifiers) }
        else { content }
    }
}
