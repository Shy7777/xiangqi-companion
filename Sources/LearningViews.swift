import SwiftUI
import AppKit

struct PositionLibraryRequest: Identifiable {
    let id = UUID()
    let references: [LibraryPosition]
}

struct LearningCenterView: View {
    @ObservedObject var model: LearningModel
    @ObservedObject var store: LearningStore
    @ObservedObject var coach: TrainingCoach
    @ObservedObject var githubLibrary: GitHubLibraryStore
    var onAnalyzePosition: ((Position) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var focusMode = false
    @State var inspectorTab = 0
    @State var previewLesson: LearningLesson?
    @State var previewBranchID: String?
    @State var showBranches = false
    @State var showFullFeedback = false
    @State var reviewFilter = 0
    @State var showGameSetup = false
    @State var confirmNewGame = false
    @State var showGameHistory = false
    @State var readingSource: LearningSource?
    @State var showStudyCoordinates = false
    @State var expandedChapterID: String?
    @State var variationPreview: VariationPreviewRequest?
    @State var expandedBookChapter: Int?
    @State var showStudyDetails = false
    @State var positionLibraryRequest: PositionLibraryRequest?
    @State var showResourceCatalog = false
    @State var catalogSource: LearningSource?
    @State var catalogLesson: LearningLesson?
    @State var githubRequest: GitHubLibraryRequest?
    @State var githubNextAction: GitHubLibraryAction?

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 1040
            let rail: CGFloat = focusMode && model.page == .study ? 0 : wide ? 176 : 64
            HStack(spacing: 0) {
                if rail > 0 { chessroomSidebar(expanded: wide).frame(width: rail) }
                VStack(spacing: 0) {
                    if model.page != .study { workspaceHeader }
                    if StudyNoticePresentation.isInformational(model.notice) { studyInformationBanner }
                    if let error = store.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundColor(Studio.red)
                            .padding(12).frame(maxWidth: .infinity).background(Studio.red.opacity(0.07))
                    }
                    if model.page == .study { chessroomStudyWorkspace(width: geo.size.width - rail) }
                    else if model.page == .sparring { sparringWorkspace(width: geo.size.width - rail) }
                    else {
                        ScrollView { pageContent.frame(maxWidth: 1160).padding(24).frame(maxWidth: .infinity, alignment: .top) }
                            .id(model.page).background(Studio.paper)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.foregroundColor(Studio.ink).background(Studio.paper).preferredColorScheme(.light).tint(Studio.green)
            .sheet(item: $previewLesson) { lesson in lessonPreview(lesson) }
            .sheet(item: $readingSource) { source in
                ProfessionalReader(source: source).onAppear { model.recordMaterialExposure(lessonID: model.lessonID) }
            }
            .sheet(item: $variationPreview) { request in
                VariationStudyView(request: request, model: model)
            }
            .sheet(item: $githubRequest, onDismiss: finishGitHubAction) { request in
                GitHubLibraryView(store: githubLibrary, catalog: model.libraryCatalog, initialSection: request.section,
                    onStudy: { queueGitHubAction(.study($0)) },
                    onAnalyze: { queueGitHubAction(.analyze($0)) },
                    onPractice: { queueGitHubAction(.practice($0)) },
                    onRead: { queueGitHubAction(.read($0)) },
                    onPersonal: { queueGitHubAction(.personal) },
                    onCurated: { queueGitHubAction(.curated) },
                    onExposure: { _ = model.recordMaterialExposure() },
                    onPositionExposure: { model.recordLibraryExposure(entryID: $0) })
            }
            .sheet(item: $positionLibraryRequest) { request in
                PositionLibraryView(builtIn: request.references, onAnalyze: { position in
                    positionLibraryRequest = nil
                    if let onAnalyzePosition { onAnalyzePosition(position) }
                    else { model.startGame(from: position, player: position.sideToMove) }
                }, onPractice: { position in
                    positionLibraryRequest = nil; model.startGame(from: position, player: position.sideToMove)
                }, onExposure: { _ = model.recordMaterialExposure() })
            }
            .sheet(isPresented: $showResourceCatalog, onDismiss: {
                if let source = catalogSource { catalogSource = nil; readingSource = source }
                if let lesson = catalogLesson { catalogLesson = nil; previewBranchID = nil; previewLesson = lesson }
            }) {
                VStack(spacing: 0) {
                    HStack { Spacer(); StudioIconButton(symbol: "xmark", label: "关闭书架") { showResourceCatalog = false } }.padding(16)
                    ScrollView {
                        ResourceCatalogView(model: model, onSelectSource: { source in
                            catalogSource = source; showResourceCatalog = false
                        }, onSelectLesson: { lesson in
                            catalogLesson = lesson; showResourceCatalog = false
                        }, onSelectStage: { stage in
                            showResourceCatalog = false; model.useAuthoredCourses = true; model.onlySupplements = false; model.query = ""; model.onlyBookmarks = false
                            model.stageFilter = stage; model.navigate(.courses)
                        }).padding(24)
                    }
                }.frame(width: 920, height: 700).background(Studio.paper)
            }
            .sheet(isPresented: $showGameSetup) { gameSetupSheet }
            .sheet(isPresented: $showGameHistory) { gameHistorySheet }
            .confirmationDialog("开始新的一盘？", isPresented: $confirmNewGame, titleVisibility: .visible) {
                Button("结束当前练习并新开") { showGameSetup = true }
                Button("取消", role: .cancel) {}
            } message: { Text("当前对局将结束并存入历史，仍可复盘。颜色和搜索档位只对新的一盘生效。") }
            .alert("象棋伴练", isPresented: Binding(get: { model.notice != nil && !StudyNoticePresentation.isInformational(model.notice) }, set: { if !$0 && !StudyNoticePresentation.isInformational(model.notice) { model.notice = nil } })) {
                Button("知道了") { model.notice = nil }
            } message: { Text(model.notice ?? "") }
            .onChange(of: model.lessonID) { _ in inspectorTab = 0; showFullFeedback = false }
            .onChange(of: model.lineID) { _ in inspectorTab = 0; showFullFeedback = false }
            .onChange(of: model.mode) { mode in if mode == .test { inspectorTab = 0 }; showFullFeedback = false }
            .onChange(of: model.page) { _ in inspectorTab = 0; showFullFeedback = false }
            .onChange(of: model.feedbackBody) { _ in showFullFeedback = false }
            .task { await githubLibrary.load() }
            .task(id: githubLibrary.snapshot?.pwaCommit) {
                guard let snapshot = githubLibrary.snapshot else { return }
                do {
                    let catalog = try await Task.detached(priority: .userInitiated) {
                        try LibraryCourseCatalogAdapter.build(snapshot: snapshot)
                    }.value
                    guard !Task.isCancelled else { return }
                    model.libraryCatalog = catalog
                } catch { if !Task.isCancelled { model.notice = "教程目录未载入：" + error.localizedDescription } }
            }
    }
    private var studyInformationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle").foregroundColor(Studio.accent)
            Text("已保留本轮辅助记录，仍可继续练习。")
                .font(.system(size: 12)).foregroundColor(Studio.ink)
            Spacer(minLength: 8)
            Text("不计独立通过").font(.system(size: 11)).foregroundColor(Studio.muted)
            Button { model.notice = nil } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                .buttonStyle(.plain).help("收起提醒").accessibilityLabel("收起提醒")
        }.padding(.horizontal, 20).padding(.vertical, 8).background(Studio.cream)
            .accessibilityIdentifier("study-information-banner")
    }
    @ViewBuilder var pageContent: some View {
        switch model.page {
        case .home: chessroomHome
        case .courses: courses
        case .review: reviewPage
        case .progress: progressPage
        case .resources: resourcesPage
        default: EmptyView()
        }
    }
    var workspaceHeader: some View {
        HStack(spacing: 9) {
            Text(model.page == .study ? model.activeReview == nil ? "课程 / 学习棋盘" : "复习 / 重新判断" : navTitle(model.page))
                .font(.system(size: 12, weight: .medium)).foregroundColor(Studio.muted)
            Spacer(); Circle().fill(Studio.green.opacity(0.65)).frame(width: 5, height: 5)
            Text("本地练习").font(.system(size: 11)).foregroundColor(Studio.muted)
            if model.page == .study {
                StudioIconButton(symbol: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                 label: focusMode ? "退出专注模式" : "专注模式 · 扩大棋盘", active: focusMode) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { focusMode.toggle() }
                }.accessibilityIdentifier("study-focus")
            }
        }.padding(.horizontal, 25).frame(height: 48).background(Studio.paper)
            .overlay(alignment: .bottom) { Rectangle().fill(Studio.line.opacity(0.45)).frame(height: 1) }
    }
    var systematicLessons: [LearningLesson] { model.lessons.filter { $0.isSystematic && !$0.id.hasPrefix("library-") } }
    var courseStages: [LearningStage] { [.opening, .strategy, .tactics, .endgame, .foundation] }
    var activeResearchResume: StudyResume? {
        guard let resume = store.data.resume, systematicLessons.contains(where: { $0.id == resume.lessonID }) else { return nil }
        return resume
    }
    var homeStudyPosition: Position? {
        if let resume = activeResearchResume,
           let lesson = model.lessons.first(where: { $0.id == resume.lessonID }),
           let line = lesson.lines.first(where: { $0.id == resume.lineID }),
           let positions = try? line.positions(), positions.indices.contains(resume.cursor) { return positions[resume.cursor] }
        return guidedNextStep.flatMap { try? Position(fen: $0.line.startingFEN) }
    }
    var todayTitle: String {
        if activeResearchResume?.mode == .test { return "继续你的无提示检验" }
        if let resume = activeResearchResume, let lesson = model.lessons.first(where: { $0.id == resume.lessonID }) { return lesson.title }
        if let review = model.dueReviews.first { return "重新判断：" + review.title }
        if let target = model.dueTargets.first { return "隔日再试：" + target.lesson.title }
        return guidedNextStep?.lesson.title ?? model.nextTarget?.lesson.title ?? "从一盘练习开始"
    }
    var todayDetail: String {
        if let resume = activeResearchResume { return "上次研究到第 \(resume.cursor / 2 + 1) 回合。落子、提示与重试记录保留，可以从这里继续。" }
        if !model.dueReviews.isEmpty { return "先回到曾经出错的局面，答案暂时隐藏。完成到期复习，再练一个新的目标。" }
        if !model.dueTargets.isEmpty { return "再给自己一次不看答案的机会，看看上次的思路是否还用得上。" }
        if let step = guidedNextStep {
            return "\(step.mode.title) · \(step.lesson.goal)"
        }
        return model.nextTarget?.lesson.goal ?? "选好颜色，让本地引擎陪你练习。"
    }
    func stageRow(_ stage: LearningStage) -> some View {
        let lessons = systematicLessons.filter { $0.stage == stage }
        let count = lessons.filter { lesson in lesson.lines.contains { store.progress(lesson.id, $0.id).completions > 0 } }.count
        return Button { model.useAuthoredCourses = true; model.query = ""; model.onlyBookmarks = false; model.onlySupplements = false; model.stageFilter = stage; model.navigate(.courses) } label: {
            HStack(spacing: 16) {
                Image(systemName: Studio.symbol(stage)).font(.system(size: 19, weight: .medium)).foregroundColor(Studio.color(stage))
                    .frame(width: 48, height: 48).background(Studio.color(stage).opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(Studio.stageName(stage)).font(.system(size: 14, weight: .semibold))
                    Text(stageDescription(stage)).font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(1)
                }
                Spacer(minLength: 15)
                VStack(alignment: .trailing, spacing: 7) {
                    Text("\(count) / \(lessons.count) 课练过").font(.system(size: 10, design: .monospaced)).foregroundColor(Studio.muted)
                    StudioProgress(value: Double(count) / Double(max(1, lessons.count)), color: Studio.color(stage)).frame(width: 84)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(Studio.muted)
            }.padding(.vertical, 13).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("stage-\(stage.rawValue)")
    }
    @ViewBuilder var courses: some View {
        switch model.courseDisplay {
        case .roadmap: learningRoadmap
        case .authored: authoredCourses
        case .positions: libraryCourses
        }
    }
    var authoredCourses: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                sectionHeading("精讲补充", detail: "原有逐步评注与中局专题，学习记录保留。", large: true)
                Spacer()
                Button("局面教程全集") { model.openLibraryCourses(section: nil) }.buttonStyle(StudioButtonStyle(compact: true))
            }
            HStack(spacing: 8) {
                filterPill("教材学习路线", active: !model.onlySupplements) { model.onlySupplements = false; model.stageFilter = nil; model.query = ""; model.onlyBookmarks = false }
                    .accessibilityIdentifier("curriculum-systematic")
                filterPill("基础补漏与短谱", active: model.onlySupplements) { model.onlySupplements = true; model.stageFilter = nil }
                    .accessibilityIdentifier("curriculum-supplements")
                Spacer()
                Button("教材书架") { model.navigate(.resources) }.buttonStyle(StudioButtonStyle(compact: true))
            }
            if model.onlySupplements {
                Text("旧版短谱与基础练习保留在这里，仅作局部补漏，不再作为系统进阶主线。已有记录与收藏仍然保留。")
                    .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
                if store.data.resume != nil && activeResearchResume == nil {
                    Button("继续之前的短谱练习") { model.resumeStudy() }.buttonStyle(StudioButtonStyle(compact: true))
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundColor(Studio.muted)
                    TextField("找课程、开局或一个难题…", text: $model.query).textFieldStyle(.plain).font(.system(size: 13)).accessibilityIdentifier("course-search")
                    if !model.query.isEmpty { StudioIconButton(symbol: "xmark", label: "清除搜索") { model.query = "" } }
                }.padding(.horizontal, 13).frame(height: 42).background(Studio.white, in: RoundedRectangle(cornerRadius: 11))
                StudioIconButton(symbol: model.onlyBookmarks ? "bookmark.fill" : "bookmark", label: "只看收藏", active: model.onlyBookmarks) { model.onlyBookmarks.toggle() }
                    .accessibilityIdentifier("filter-bookmarks")
                Menu { Button("导入课程包") { model.importCourses() }; Button("导出全部课程") { model.exportCourses() } }
                label: { Image(systemName: "ellipsis.circle").font(.system(size: 18)) }.menuStyle(.borderlessButton).fixedSize().help("课程导入与导出")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterPill("全部", active: model.stageFilter == nil) { model.stageFilter = nil }
                    ForEach(courseStages) { stage in filterPill(stage.shortTitle, active: model.stageFilter == stage) { model.stageFilter = stage } }
                }
            }
            if !model.onlySupplements && model.query.isEmpty && model.stageFilter == nil && !model.onlyBookmarks {
                guidedRoute(compact: false)
                let mapped = Set(GuidedCurriculum.chapters.flatMap(\.lessonIDs))
                let extra = model.recommendedLessons.filter { !mapped.contains($0.id) }
                if !extra.isEmpty {
                    sectionHeading("扩展课程", detail: "导入或补充的系统课程，保留独立入口。")
                    ForEach(Array(extra.enumerated()), id: \.element.id) { index, lesson in lessonRow(lesson, index: index) }
                }
            } else if model.filteredLessons.isEmpty {
                StudioEmpty(symbol: "magnifyingglass", title: "换个方向找找", detail: "没有符合当前条件的课程。你可以换一个关键词，或清除筛选。")
                Button("清除全部筛选") { model.query = ""; model.stageFilter = nil; model.onlyBookmarks = false }.buttonStyle(StudioButtonStyle())
            } else {
                ForEach(courseStages.filter { stage in model.filteredLessons.contains { $0.stage == stage } }) { stage in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Studio.stageName(stage)).font(.system(size: 12, weight: .semibold)).foregroundColor(Studio.color(stage))
                        LazyVStack(spacing: 0) {
                            let items = model.filteredLessons.filter { $0.stage == stage }
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, lesson in
                                lessonRow(lesson, index: index)
                                if index < items.count - 1 { Divider().padding(.leading, 63) }
                            }
                        }.studioSurface(16)
                    }
                }
            }
        }
    }
    func lessonRow(_ lesson: LearningLesson, index: Int) -> some View {
        let done = lesson.lines.filter { store.progress(lesson.id, $0.id).completions > 0 }.count
        return HStack(spacing: 12) {
            Button { previewBranchID = lesson.lines.first?.id; previewLesson = lesson } label: {
                HStack(spacing: 15) {
                    Text(String(format: "%02d", index + 1)).font(.system(size: 20, weight: .light, design: .monospaced)).foregroundColor(Studio.color(lesson.stage).opacity(0.6)).frame(width: 34)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(lesson.title.simplifiedForDisplay).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(lesson.goal.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineLimit(2).lineSpacing(3)
                        Text(lessonScope(lesson) + (done > 0 ? " · 已练 \(done)/\(lesson.lines.count)" : ""))
                            .font(.system(size: 10)).foregroundColor(Studio.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundColor(Studio.muted)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("lesson-\(lesson.id)")
            StudioIconButton(symbol: store.data.bookmarks.contains(lesson.id) ? "bookmark.fill" : "bookmark", label: "收藏：\(lesson.title)", active: store.data.bookmarks.contains(lesson.id)) { store.bookmark(lesson.id) }
        }.padding(.vertical, 16)
    }
    func lessonPreview(_ lesson: LearningLesson) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StudioTag(text: Studio.stageName(lesson.stage), color: Studio.color(lesson.stage)); Spacer()
                StudioIconButton(symbol: "xmark", label: "关闭课程预览") { previewLesson = nil }
            }.padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(lesson.title.simplifiedForDisplay).font(.system(size: 25, weight: .semibold))
                    Text(lesson.summary.simplifiedForDisplay).font(.system(size: 14)).foregroundColor(Studio.muted).lineSpacing(6)
                    if model.mode == .test && !model.completed && model.line != nil {
                        Label("检验期间查看课程导读，本轮会保留辅助记录。", systemImage: "eye")
                            .font(.system(size: 11)).foregroundColor(Studio.gold)
                    }
                    DisclosureGroup("阅读路线与教材对应") {
                        VStack(alignment: .leading, spacing: 16) { lessonLearningJourney(lesson); lessonTextbookContext(lesson) }.padding(.top, 14)
                    }.font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 9) {
                        Text(lesson.isSystematic ? "研究任务" : "补漏目标").font(.system(size: 11, weight: .medium)).foregroundColor(Studio.green)
                        Text(lesson.goal.simplifiedForDisplay).font(.system(size: 17, weight: .medium)).lineSpacing(5)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Studio.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                    if let guide = lesson.guide {
                        DisclosureGroup("完整导读") { studyGuide(guide, lesson: lesson).padding(.top, 12) }.font(.system(size: 12))
                    }
                    Text(lesson.isSystematic ? "选择谱例或应对分支" : "选择一个应对开始").font(.system(size: 13, weight: .semibold))
                    ForEach(lesson.lines) { line in
                        Button { previewBranchID = line.id } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: selectedPreviewLine(lesson) == line.id ? "checkmark.circle.fill" : "circle").foregroundColor(Studio.green)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(line.title.simplifiedForDisplay).font(.system(size: 14, weight: .medium))
                                    Text(line.intent.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineLimit(2)
                                    Text(lineScope(line)).font(.system(size: 10)).foregroundColor(Studio.muted)
                                    if let game = line.game { gameProvenance(game) }
                                }; Spacer(minLength: 0)
                            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedPreviewLine(lesson) == line.id ? Studio.green.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                    DisclosureGroup("适用条件、常见误区与来源") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(lesson.whenToAdapt.simplifiedForDisplay)
                            ForEach(lesson.pitfalls, id: \.self) { Text("· " + $0) }
                            sourceRows(model.sources.filter { lesson.sourceIDs.contains($0.id) })
                        }.font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(4).padding(.top, 10)
                    }.font(.system(size: 12))
                }.padding(.horizontal, 26).padding(.bottom, 25)
            }
            HStack(spacing: 12) {
                action(lesson.isSystematic ? "进入谱例推演" : "看一遍讲解", symbol: "play.fill", id: "preview-demo") { beginPreview(lesson, mode: .demonstration) }
                Button(lesson.isSystematic ? "练关键决策" : "自己走一遍") { beginPreview(lesson, mode: .practice) }.buttonStyle(StudioButtonStyle()).accessibilityIdentifier("preview-practice")
                Spacer()
                Button("直接检验") { beginPreview(lesson, mode: .test) }.buttonStyle(.plain).font(.system(size: 12)).foregroundColor(Studio.muted)
            }.padding(24).background(Studio.white)
        }.frame(width: 680, height: 700).background(Studio.paper).foregroundColor(Studio.ink)
            .onAppear { model.recordMaterialExposure(lessonID: lesson.id) }
    }
    func beginPreview(_ lesson: LearningLesson, mode: StudyMode) {
        let line = lesson.lines.first { $0.id == previewBranchID } ?? lesson.lines.first
        previewLesson = nil; model.startLesson(lesson, line: line, mode: mode)
    }
    func selectedPreviewLine(_ lesson: LearningLesson) -> String? {
        lesson.lines.first(where: { $0.id == previewBranchID })?.id ?? lesson.lines.first?.id
    }
    func navTitle(_ page: LearningPage) -> String {
        switch page {
        case .home: return "研究工作台"
        case .courses: return "课程与棋谱"
        case .study: return "学习棋盘"
        case .review: return "复习与错题"
        case .sparring: return "实战练习"
        case .progress: return "训练记录"
        case .resources: return "教材与设置"
        }
    }
    func stageDescription(_ stage: LearningStage) -> String {
        switch stage {
        case .foundation: return "应将、保护、吃子与回吃。"
        case .opening: return "从布局阵形进入中局，比较先后手与子力效率。"
        case .tactics: return "候选着法、强制变化与对手的最强抵抗。"
        case .endgame: return "分析交换后的胜和条件，而非机械地兑子。"
        case .strategy: return "权衡子力、空间、结构与主动权，选择计划。"
        }
    }
    func action(_ title: String, symbol: String = "arrow.right", id: String = "", perform: @escaping () -> Void) -> some View {
        Button(action: perform) { HStack(spacing: 10) { Text(title.simplifiedForDisplay); Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) } }
            .buttonStyle(StudioButtonStyle(primary: true)).accessibilityIdentifier(id.isEmpty ? "action-\(title)" : id)
    }
    func sectionHeading(_ title: String, detail: String, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.simplifiedForDisplay).font(.system(size: large ? 25 : 18, weight: .semibold))
            Text(detail.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(4)
        }
    }
    func filterPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title.simplifiedForDisplay).font(.system(size: 12, weight: active ? .semibold : .regular))
            .padding(.horizontal, 14).padding(.vertical, 9).foregroundColor(active ? Studio.green : Studio.muted)
            .background(active ? Studio.green.opacity(0.1) : Studio.white, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(active ? Studio.green.opacity(0.5) : Studio.line, lineWidth: 1)) }.buttonStyle(.plain)
    }
    func quietStat(_ value: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: 18, weight: .medium, design: .rounded))
            Text(title.simplifiedForDisplay).font(.system(size: 10)).foregroundColor(Studio.muted)
        }.padding(.trailing, 22)
    }
    func sourceRows(_ sources: [LearningSource], embedded: Bool = false) -> some View {
        ForEach(sources) { source in
            VStack(alignment: .leading, spacing: 6) {
                if embedded {
                    Button { model.recordMaterialExposure(lessonID: model.lessonID); readingSource = source } label: { Label(source.title, systemImage: "book") }.buttonStyle(.plain).font(.system(size: 12)).foregroundColor(Studio.green).accessibilityIdentifier("read-source-\(source.id)")
                } else if let url = URL(string: source.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    Button { openStudyReference(url) } label: { Label(source.title, systemImage: "arrow.up.right") }.buttonStyle(.plain).font(.system(size: 12)).foregroundColor(Studio.accent)
                }
                Text(source.note).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(3)
            }
        }
    }
    func openStudyReference(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        _ = model.recordMaterialExposure(lessonID: model.lessonID)
        NSWorkspace.shared.open(url)
    }
    func variation(_ pv: [String], from start: Position) -> String {
        var p = start; var names: [String] = []
        for text in pv.prefix(8) {
            guard let move = Move(uci: text), let next = try? p.applying(move: move) else { break }
            names.append(p.notation(for: move)); p = next
        }
        return names.joined(separator: " → ")
    }
}
