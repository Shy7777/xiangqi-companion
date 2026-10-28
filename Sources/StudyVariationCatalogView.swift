import SwiftUI

/// The caller records material exposure before inserting this view. In a test,
/// it must first offer an explicit return to guided study instead of leaking
/// the catalogue's conditions, explanations, or continuation moves.
struct StudyVariationCatalogView: View {
    let lesson: LearningLesson
    let currentLine: StudyLine
    let currentPly: Int
    let onOpen: (StudyLine, StudyVariation) -> Void
    private let catalog: StudyVariationCatalog

    init(lesson: LearningLesson, currentLine: StudyLine, currentPly: Int,
         onOpen: @escaping (StudyLine, StudyVariation) -> Void) {
        self.lesson = lesson
        self.currentLine = currentLine
        self.currentPly = currentPly
        self.onOpen = onOpen
        catalog = StudyVariationCatalog(lesson: lesson)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("本课全部变招", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(Studio.green)
                Spacer(minLength: 4)
                Text("\(catalog.variationCount) 条 · \(catalog.forkCount) 个分歧点")
                    .font(.system(size: 10)).foregroundColor(Studio.muted)
            }
            Text(coverageNote).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(3)
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(catalog.routes) { route in routeSection(route) }
            }
        }
        .accessibilityIdentifier("study-variation-catalog")
    }

    private var coverageNote: String {
        if catalog.variationCount == 0 { return "本课还没有收录变招讲解；不会用引擎候选着冒充完整谱例。" }
        if lesson.id.hasPrefix("library-") {
            return "以下是本局面已生成的参考变化，不代表棋理上所有可行应招。"
        }
        return "按谱例与分歧点列出所有已收录变化。点开即可逐步推演，并与原谱比较。"
    }

    private func routeSection(_ route: StudyVariationCatalog.Route) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(route.line.title.simplifiedForDisplay).font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                if route.line.id == currentLine.id { StudioTag(text: "当前谱例") }
            }
            if route.forks.isEmpty {
                Text("这条谱例暂未收录变招。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted)
            } else {
                ForEach(route.forks) { fork in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            Text(fork.label)
                            if route.line.id == currentLine.id && fork.anchorPly == currentPly {
                                Text("· 当前局面").foregroundColor(Studio.green)
                            }
                        }.font(.system(size: 10, weight: .medium)).foregroundColor(Studio.muted)
                        ForEach(fork.entries) { entry in
                            StudyVariationCatalogCard(parent: route.line, variation: entry.variation) {
                                onOpen(route.line, entry.variation)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
        .accessibilityIdentifier("study-variation-route-\(route.line.id)")
    }
}

private struct StudyVariationCatalogCard: View {
    let parent: StudyLine
    let variation: StudyVariation
    let open: () -> Void
    @State private var showSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 9) {
                    Text(variation.title.simplifiedForDisplay).font(.system(size: 12, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 3)
                    Label("推演", systemImage: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(Studio.green)
                }
                .foregroundColor(Studio.ink)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("study-catalog-open-\(parent.id)-\(variation.id)")
            .accessibilityLabel("推演变招：\(variation.title.simplifiedForDisplay)")
            explanation("何时变", text: variation.condition, missing: "来源尚未附触发条件。")
            explanation("思路", text: variation.explanation, missing: "来源尚未附思路说明。")
            DisclosureGroup("逐步讲解 · \(variation.moves.count) 步", isExpanded: $showSteps) {
                if showSteps {
                    StudyVariationStepList(parent: parent, variation: variation).padding(.top, 9)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Studio.green)
            .accessibilityIdentifier("study-catalog-steps-\(parent.id)-\(variation.id)")
        }
        .padding(12)
        .background(Studio.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Studio.line.opacity(0.7), lineWidth: 0.75))
    }

    private func explanation(_ label: String, text: String, missing: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(Studio.green)
            Text((text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? missing : text).simplifiedForDisplay)
                .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StudyVariationStepList: View {
    let parent: StudyLine
    let variation: StudyVariation
    @State private var steps: [StudyVariationStep] = []
    @State private var unavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if unavailable {
                Text("这条续着未通过棋规校验，暂不能推演；上方保留来源原有说明。")
                    .font(.system(size: 11)).foregroundColor(Studio.red)
            } else {
                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(step.number). \(step.notation.simplifiedForDisplay)")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.ink)
                        Text(step.explanation.simplifiedForDisplay)
                            .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear(perform: loadSteps)
        .onChange(of: parent) { _ in loadSteps() }
        .onChange(of: variation) { _ in loadSteps() }
    }

    private func loadSteps() {
        do { steps = try StudyVariationStep.load(parent: parent, variation: variation); unavailable = false }
        catch { steps = []; unavailable = true }
    }
}
