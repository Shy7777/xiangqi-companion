import SwiftUI

/// Route coverage is counted by StudyTarget (lesson + line), so the visible
/// directory uses exactly the same unit rather than merging lines into courses.
struct LearningRouteExampleList: View {
    @ObservedObject var model: LearningModel
    @ObservedObject var store: LearningStore
    let route: LearningRoute

    var body: some View {
        let targets = model.routeTargets(route)
        let completed = targets.filter { store.progress($0.lesson.id, $0.line.id).completions > 0 }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("谱例目录").font(.system(size: 14, weight: .semibold))
                    .accessibilityIdentifier("route-example-directory-\(route.id)")
                Spacer(minLength: 4)
                Text("已练 \(completed)/\(targets.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Studio.accent)
                    .accessibilityIdentifier("route-example-completion-count")
            }
            if targets.isEmpty {
                Text("这个目标暂未配置可练的精讲谱例。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted)
            } else {
                ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                    exampleRow(target, number: index + 1)
                }
            }
        }
    }

    private func exampleRow(_ target: StudyTarget, number: Int) -> some View {
        let progress = store.progress(target.lesson.id, target.line.id)
        let status = RouteExampleProgress(progress: progress)
        let resumable = model.routeStudyTargetIsResumable(target)
        let actionTitle = resumable ? "继续" : progress.completions > 0 ? "再练" : "练习"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Studio.accent).frame(width: 28, height: 28)
                    .background(Studio.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 5) {
                    Text(target.lesson.title.simplifiedForDisplay)
                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(target.line.title.simplifiedForDisplay)
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(Studio.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("route-example-row-\(target.id)")
                    HStack(spacing: 8) {
                        Label(status.title, systemImage: status.symbol)
                            .foregroundColor(status.isCompleted ? Studio.green : Studio.muted)
                        if resumable { Text("可继续").foregroundColor(Studio.accent) }
                    }.font(.system(size: 10, weight: .medium))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button {
                    open(target, mode: .practice, resumeExisting: resumable)
                } label: {
                    Label(actionTitle, systemImage: resumable ? "play.fill" : "hand.draw")
                        .frame(maxWidth: .infinity, minHeight: 18).contentShape(Rectangle())
                }
                .buttonStyle(StudioButtonStyle(primary: true, compact: true))
                .accessibilityLabel("\(actionTitle)谱例 \(number)：\(target.line.title.simplifiedForDisplay)")
                .accessibilityIdentifier("route-example-practice-\(target.id)")
                Button {
                    open(target, mode: .demonstration, resumeExisting: false)
                } label: {
                    Label("看谱", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 18).contentShape(Rectangle())
                }
                .buttonStyle(StudioButtonStyle(compact: true))
                .accessibilityLabel("看谱 \(number)：\(target.line.title.simplifiedForDisplay)")
                .accessibilityIdentifier("route-example-demonstration-\(target.id)")
                Menu {
                    Button("无提示检验") { open(target, mode: .test, resumeExisting: false) }
                    Button("从头练") { open(target, mode: .practice, resumeExisting: false) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 34).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("此谱例的其他练习方式")
                .accessibilityLabel("谱例 \(number) 的其他方式")
                .accessibilityIdentifier("route-example-options-\(target.id)")
            }
            .disabled(model.busy || model.libraryPreparing)
        }
        .padding(12)
        .background(Studio.paper.opacity(0.9), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Studio.line.opacity(0.75), lineWidth: 0.75))
    }

    private func open(_ target: StudyTarget, mode: StudyMode, resumeExisting: Bool) {
        model.openRouteStudyTarget(routeID: route.id, lessonID: target.lesson.id, lineID: target.line.id,
                                   mode: mode, resumeExisting: resumeExisting)
    }
}

/// Completion and independent success are different badges; a viewed example
/// is not counted as practiced merely because it has a reading timestamp.
private struct RouteExampleProgress {
    let title: String
    let symbol: String
    let isCompleted: Bool

    init(progress: LineProgress) {
        if progress.cleanTests > 0 {
            title = "独立通过"; symbol = "checkmark.shield.fill"; isCompleted = true
        } else if progress.completions > 0 {
            title = "已练"; symbol = "checkmark.circle"; isCompleted = true
        } else if progress.demonstrations > 0 {
            title = "看过"; symbol = "eye"; isCompleted = false
        } else {
            title = "未练"; symbol = "circle"; isCompleted = false
        }
    }
}
