import SwiftUI

/// The chessroom presents tasks and positions; explanations are opt-in, not the navigation.
extension LearningCenterView {
    func chessroomSidebar(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.navigate(.home) } label: {
                HStack(spacing: 8) {
                    Text("棋").font(.system(size: 22, weight: .semibold, design: .serif))
                        .frame(width: 34, height: 34).overlay(Circle().strokeBorder(Studio.ink, lineWidth: 1.3))
                    if expanded { Text("象棋伴练").font(.system(size: 15, weight: .semibold)) }
                }.frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
                    .padding(.vertical, 18).contentShape(Rectangle()).foregroundColor(Studio.ink)
            }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("learn-nav-home")
            railItem("学习路线", symbol: "point.topleft.down.curvedto.point.bottomright.up", active: model.page == .courses && model.courseDisplay == .roadmap, expanded: expanded) {
                model.openLearningRoadmap()
            }.accessibilityIdentifier("learn-nav-roadmap")
            railItem("自由选局", symbol: "square.grid.2x2", active: model.page == .courses && model.courseDisplay == .positions, expanded: expanded) {
                model.openLibraryCourses(section: nil)
            }.accessibilityIdentifier("learn-nav-courses")
                .contextMenu {
                    ForEach(libraryVisibleSections) { section in
                        Button(section.title) { model.openLibraryCourses(section: section) }
                            .accessibilityIdentifier("rail-library-\(section.id)")
                    }
                }
            railItem("精讲谱例", symbol: "text.book.closed", active: model.page == .courses && model.useAuthoredCourses, expanded: expanded) {
                openAuthoredCourses()
            }.accessibilityIdentifier("open-authored-courses")
            Divider().padding(.vertical, 8)
            railItem("陪练", symbol: "person.2", active: model.page == .sparring, expanded: expanded) { model.navigate(.sparring) }
                .accessibilityIdentifier("learn-nav-sparring")
            railItem("错题", symbol: "arrow.counterclockwise", active: model.page == .review, expanded: expanded) { model.navigate(.review) }
                .accessibilityIdentifier("learn-nav-review")
            Spacer(minLength: 15)
            if (model.lesson != nil || model.activeReview != nil), model.page != .study {
                railItem("继续学习", symbol: "play.circle", active: false, expanded: expanded) { model.navigate(.study) }
                    .accessibilityIdentifier("return-study-board")
            }
            railItem("书架", symbol: "books.vertical", active: false, expanded: expanded) { githubRequest = GitHubLibraryRequest(section: .resources) }
                .accessibilityIdentifier("open-resource-catalog")
            railItem("记录", symbol: "chart.bar", active: model.page == .progress, expanded: expanded) { model.navigate(.progress) }
                .accessibilityIdentifier("learn-nav-progress")
            railItem("设置", symbol: "slider.horizontal.3", active: model.page == .resources, expanded: expanded) { model.navigate(.resources) }
                .accessibilityIdentifier("learn-nav-resources")
        }.padding(.horizontal, expanded ? 12 : 8).padding(.bottom, 16)
            .background(Studio.rail)
            .overlay(alignment: .trailing) { Rectangle().fill(Studio.line.opacity(0.45)).frame(width: 1) }
    }

    private func railItem(_ title: String, symbol: String, active: Bool, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 23)
                if expanded { Text(title).font(.system(size: 14, weight: active ? .semibold : .regular)).lineLimit(1); Spacer(minLength: 0) }
            }.frame(maxWidth: .infinity, minHeight: 43).padding(.horizontal, expanded ? 12 : 0)
                .contentShape(Rectangle())
                .foregroundColor(active ? Studio.onAccent : Studio.ink.opacity(0.85))
                .background(active ? Studio.accent : .clear, in: RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(ChessroomRailButtonStyle(active: active)).help(title).accessibilityLabel(title)
            .accessibilityValue(active ? "当前位置" : "")
    }

    func chapterShortName(_ number: Int) -> String { ["布局", "中局", "杀法", "残局", "实战"][min(4, max(0, number - 1))] }
    func openPositionLibrary() {
        positionLibraryRequest = PositionLibraryRequest(references: PositionLibraryCurriculumAdapter.references(from: model.lessons))
    }
    func chapterSymbol(_ number: Int) -> String { ["square.grid.2x2", "point.topleft.down.curvedto.point.bottomright.up", "scope", "flag", "checkerboard.rectangle"][min(4, max(0, number - 1))] }

    var libraryVisibleSections: [LibraryCourseSection] {
        LibraryCourseSection.allCases.filter { $0 != .other || model.libraryCatalog.groups.contains(where: { $0.section == .other }) }
    }
    func librarySectionSymbol(_ section: LibraryCourseSection) -> String {
        switch section {
        case .opening: return "square.grid.2x2"
        case .checkmates: return "scope"
        case .endgames: return "flag"
        case .patterns: return "square.stack.3d.up"
        case .classics: return "book.closed"
        case .other: return "square.grid.3x3"
        }
    }
    func openAuthoredCourses() {
        model.useAuthoredCourses = true; model.routeExampleIDs = nil; expandedChapterID = nil
        model.onlySupplements = false; model.query = ""; model.stageFilter = nil; model.onlyBookmarks = false
        model.navigate(.courses)
    }

    private var chessroomResume: StudyResume? {
        guard let resume = store.data.resume,
              model.lessons.contains(where: { $0.id == resume.lessonID && $0.lines.contains(where: { $0.id == resume.lineID }) }) else { return nil }
        return resume
    }
    private var chessroomHomePosition: Position? {
        if let resume = chessroomResume,
           let line = model.lessons.first(where: { $0.id == resume.lessonID })?.lines.first(where: { $0.id == resume.lineID }) {
            return model.readingCache.resumePosition(line: line, cursor: resume.cursor,
                acceptedMove: resume.acceptedCheckpoint == nil ? nil : resume.checkpointMove)
        }
        return nil
    }
    private var chessroomHomeTitle: String {
        if let resume = chessroomResume {
            return resume.mode == .test ? "继续你的无提示检验" : (model.lessons.first(where: { $0.id == resume.lessonID })?.title ?? "继续上次学习").simplifiedForDisplay
        }
        return model.todayRecommendationTitle
    }

    var chessroomHome: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今天练什么").font(.system(size: 28, weight: .semibold, design: .serif))
                    Text("从一盘、一种判断开始。").font(.system(size: 12)).foregroundColor(Studio.muted)
                }
                Spacer()
                Button("学习路线") { model.openLearningRoadmap() }.buttonStyle(StudioButtonStyle(compact: true))
                    .accessibilityIdentifier("home-open-roadmap")
            }
            libraryPreparationBanner
            if chessroomResume != nil, model.journeyPlan?.isFinished != false {
                HStack(spacing: 24) {
                    if let position = chessroomHomePosition {
                        BoardPreview(position: position, flipped: chessroomResume?.mode == .test ? position.sideToMove == .black : model.flipped, width: 220)
                            .accessibilityLabel("上次学习停下时的真实棋盘")
                    }
                    VStack(alignment: .leading, spacing: 17) {
                        StudioTag(text: "接着上次")
                        Text(chessroomHomeTitle).font(.system(size: 25, weight: .semibold, design: .serif)).lineLimit(3)
                        Text("已停在你上次思考的地方。").font(.system(size: 13)).foregroundColor(Studio.muted)
                        action("继续学习", symbol: "play.fill", id: "resume-study") { model.resumeStudy() }.disabled(model.libraryPreparing)
                        Menu("换个练法") {
                            Button("按路线开始一组") { model.startRecommendedSession() }
                            Button("无提示试一组") { model.startRecommendedSession(diagnostic: true) }
                        }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 12)).foregroundColor(Studio.muted)
                            .disabled(model.libraryPreparing || model.busy)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.studioSurface(24)
            } else {
                homeRecommendation
            }
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("自己选一局").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button("全部局面") { model.openLibraryCourses(section: nil) }.buttonStyle(.plain).foregroundColor(Studio.accent)
                        .accessibilityIdentifier("home-all-positions")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    ForEach(libraryVisibleSections) { section in
                        Button { model.openLibraryCourses(section: section) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: librarySectionSymbol(section)).foregroundColor(Studio.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(section.title.simplifiedForDisplay).font(.system(size: 13, weight: .medium))
                                    Text("\(model.librarySectionCount(section)) 局")
                                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                                }
                                Spacer(minLength: 0)
                            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Studio.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 13))
                        }.buttonStyle(ChessroomRailButtonStyle(active: false)).accessibilityIdentifier("home-library-\(section.id)")
                    }
                }
            }
            HStack(spacing: 8) {
                Text("Pikafish · 本地").font(.system(size: 11)).foregroundColor(Studio.muted)
                Spacer()
                Button("导入与局面收藏") { githubRequest = GitHubLibraryRequest(section: .positions) }
                    .accessibilityIdentifier("open-position-library")
                Button("资料与来源") { githubRequest = GitHubLibraryRequest(section: .resources) }
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Studio.muted)
        }
    }

    private var homeRecommendation: some View {
        let plan = model.journeyPlan
        let unfinished = plan.map { !$0.isFinished } ?? false
        return VStack(alignment: .leading, spacing: 17) {
            HStack {
                StudioTag(text: unfinished ? "继续这一组" : "今日建议")
                Spacer()
                if let plan, unfinished {
                    Text("已完成 \(plan.completedIndices.count) / \(plan.items.count)").font(.system(size: 11)).monospacedDigit().foregroundColor(Studio.muted)
                }
            }
            Text((unfinished ? plan?.title ?? model.todayRecommendationTitle : model.todayRecommendationTitle).simplifiedForDisplay)
                .font(.system(size: 25, weight: .semibold, design: .serif))
            Text((unfinished ? plan?.reason ?? model.todayRecommendationReason : model.todayRecommendationReason).simplifiedForDisplay)
                .font(.system(size: 13)).foregroundColor(Studio.muted).lineSpacing(4).lineLimit(3)
            if let plan, unfinished, let item = plan.currentItem {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.turn.down.right").foregroundColor(Studio.accent)
                    Text("接下来 · " + item.title.simplifiedForDisplay).font(.system(size: 12)).lineLimit(2)
                }.padding(.vertical, 5)
            } else {
                Text("自己判断  →  看懂回应  →  换局再练").font(.system(size: 12)).foregroundColor(Studio.muted)
            }
            HStack(spacing: 12) {
                if unfinished {
                    Button("继续这一组") { model.resumeJourneySession() }.buttonStyle(StudioButtonStyle(primary: true))
                        .accessibilityIdentifier("resume-journey-session")
                } else {
                    Button("开始一组练习") { model.startRecommendedSession() }.buttonStyle(StudioButtonStyle(primary: true))
                        .accessibilityIdentifier("start-daily-plan")
                }
                Menu("更多练法") {
                    Button("无提示试一组") { model.startRecommendedSession(diagnostic: true) }
                        .accessibilityIdentifier("start-diagnostic")
                    if let plan, unfinished {
                        Button("跳过当前项（不计完成）") { model.skipJourneyItem() }
                            .disabled(plan.completedIndices.contains(plan.cursor) || plan.skippedIndices.contains(plan.cursor))
                    }
                    if let resume = chessroomResume, resume.runID != plan?.activeRunID {
                        Button("回到上次的单课练习") { model.resumeStudy() }
                    }
                }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 12)).foregroundColor(Studio.muted)
                    .accessibilityIdentifier("home-journey-options")
            }.disabled(model.libraryPreparing || model.busy)
            if model.libraryCatalog.entries.isEmpty {
                HStack {
                    Text("精讲可直接开始；同步资料后会加入更多同类局面。").font(.system(size: 11)).foregroundColor(Studio.muted)
                    Spacer()
                    Button("载入资料") { githubRequest = GitHubLibraryRequest(section: .updates) }.buttonStyle(.plain).foregroundColor(Studio.accent)
                }
            }
        }.studioSurface(24)
    }
}

/// Hover and press state make passive-looking rows feel actionable, without
/// changing layout or introducing motion for users who reduce animations.
private struct ChessroomRailButtonStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        ChessroomRailButtonBody(label: configuration.label, active: active, pressed: configuration.isPressed)
    }
}
private struct ChessroomRailButtonBody<Label: View>: View {
    let label: Label
    let active: Bool
    let pressed: Bool
    @State private var hovering = false
    var body: some View {
        label.contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 12)
                .fill(Studio.accent.opacity(active ? 0 : pressed ? 0.12 : hovering ? 0.055 : 0))
                .allowsHitTesting(false))
            .opacity(pressed ? 0.82 : 1)
            .onHover { hovering = $0 }
    }
}
