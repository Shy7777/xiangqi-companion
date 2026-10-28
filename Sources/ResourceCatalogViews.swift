import SwiftUI
import AppKit

/// A local, searchable index. Loading this view never requests or downloads a URL.
@MainActor struct ResourceCatalogView: View {
    @ObservedObject var model: LearningModel
    let onSelectSource: (LearningSource) -> Void
    var onSelectLesson: ((LearningLesson) -> Void)? = nil
    var onSelectStage: ((LearningStage) -> Void)? = nil
    @State private var query = ""
    @State private var kind: ResourceCatalogKind? = nil
    @State private var stage: LearningStage? = nil
    @State private var selectedEntry: ResourceCatalogEntry?
    @State private var pendingAction: CatalogAction?
    @State private var openError: String?

    private enum CatalogAction {
        case source(LearningSource), lesson(LearningLesson), stage(LearningStage)
    }
    private var visibleEntries: [ResourceCatalogEntry] {
        ResourceCatalog.filtered(query: query, kind: kind, stage: stage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("研究书架").font(.system(size: 28, weight: .semibold))
                    Text("课程、原站与参考书，分开看清。").font(.system(size: 13)).foregroundColor(Studio.muted)
                }
                Spacer()
                Label("不自动下载", systemImage: "internaldrive")
                    .font(.system(size: 11)).foregroundColor(Studio.muted).padding(.top, 10)
            }
            filters
            directoryIndex
            HStack {
                Text("\(visibleEntries.count) 项资源").font(.system(size: 11, weight: .medium))
                Spacer()
                Text("“免费原站”不表示正文已获改编授权").font(.system(size: 10)).foregroundColor(Studio.muted)
            }
            if visibleEntries.isEmpty {
                VStack(spacing: 12) {
                    Text("没有匹配的资源").font(.system(size: 16, weight: .medium))
                    Button("清除筛选") { query = ""; kind = nil; stage = nil }
                        .buttonStyle(StudioButtonStyle(compact: true))
                }.frame(maxWidth: .infinity).padding(.vertical, 35)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 225, maximum: 360), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(visibleEntries) { entry in card(entry) }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "link").padding(.top, 2)
                Text(ResourceCatalog.attribution).lineSpacing(4)
            }.font(.system(size: 10)).foregroundColor(Studio.muted).padding(.top, 3)
            if let openError { Text(openError).font(.system(size: 12)).foregroundColor(Studio.red) }
        }
        .foregroundColor(Studio.ink)
        .onAppear { _ = model.recordMaterialExposure() }
        .sheet(item: $selectedEntry, onDismiss: performPendingAction) { entry in detail(entry) }
    }

    private var directoryIndex: some View {
        DisclosureGroup("开放资源总目录 · 全部 9 类") {
            VStack(alignment: .leading, spacing: 12) {
                Text("完整保留上游各类别入口。目录内含商业书目、外站与社群，并非本机课程；其中每个外链的可用性与许可需要单独核对。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(ResourceCatalog.directorySections) { section in
                        Button {
                            guard let url = section.url else { return }
                            openError = nil
                            if !NSWorkspace.shared.open(url) { openError = "无法打开资源目录，请检查默认浏览器后重试。" }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(section.title).font(.system(size: 12, weight: .medium)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 9)) }
                                Text(section.detail).font(.system(size: 10)).foregroundColor(Studio.muted).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                                .background(Studio.white, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).accessibilityIdentifier("resource-directory-" + section.id)
                    }
                }
            }.padding(.top, 12)
        }.font(.system(size: 12, weight: .medium))
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(Studio.muted)
                TextField("搜索书名、作者、布局或残局", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .accessibilityIdentifier("resource-search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundColor(Studio.muted).accessibilityLabel("清除搜索")
                }
            }.padding(12).background(Studio.white, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Studio.line))
            HStack(spacing: 7) {
                filterButton("全部", selected: kind == nil) { kind = nil }
                ForEach(ResourceCatalogKind.allCases) { value in
                    filterButton(value.title, selected: kind == value) { kind = value }
                }
                Spacer(minLength: 5)
                Picker("阶段", selection: $stage) {
                    Text("全部阶段").tag(Optional<LearningStage>.none)
                    ForEach(LearningStage.allCases) { value in Text(value.shortTitle).tag(Optional(value)) }
                }.labelsHidden().frame(width: 112).accessibilityIdentifier("resource-stage-filter")
            }
        }
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .foregroundColor(selected ? Studio.onAccent : Studio.muted)
                .background(selected ? Studio.accent : Studio.white, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func card(_ entry: ResourceCatalogEntry) -> some View {
        Button {
            _ = model.recordMaterialExposure()
            openError = nil; selectedEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: entry.kind.symbol).font(.system(size: 15)).foregroundColor(accent(entry))
                    Spacer()
                    Text(entry.kind.title).font(.system(size: 10)).foregroundColor(Studio.muted)
                }
                Text(entry.title.simplifiedForDisplay).font(.system(size: 16, weight: .semibold)).lineLimit(2).frame(height: 43, alignment: .topLeading)
                Text(entry.author.simplifiedForDisplay).font(.system(size: 10)).foregroundColor(Studio.muted).lineLimit(1)
                Text(entry.summary.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(3).lineLimit(2)
                    .frame(height: 39, alignment: .topLeading)
                HStack {
                    Label(entry.offlineLabel, systemImage: entry.kind == .localCourses ? "checkmark.circle" : "network")
                        .font(.system(size: 10)).foregroundColor(accent(entry))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundColor(Studio.muted)
                }.padding(.top, 5)
            }.frame(maxWidth: .infinity, alignment: .leading).studioSurface(16)
        }.buttonStyle(.plain).accessibilityIdentifier("resource-card-" + entry.id)
    }

    private func detail(_ entry: ResourceCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StudioTag(text: entry.kind.title, color: accent(entry))
                Spacer()
                StudioIconButton(symbol: "xmark", label: "关闭资源详情") { selectedEntry = nil }
                    .keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 24).padding(.top, 17)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(entry.title.simplifiedForDisplay).font(.system(size: 25, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(entry.author.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted)
                        Text(entry.summary.simplifiedForDisplay).font(.system(size: 14)).lineSpacing(5)
                    }
                    if entry.kind == .localCourses { localCourses(entry) }
                    detailSection("内容与范围", text: entry.scope)
                    DisclosureGroup("来源与使用权限") {
                        Text(entry.rights).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5).padding(.top, 9)
                    }.font(.system(size: 12, weight: .medium))
                    if let source = entry.readingSource(in: model.sources), let url = URL(string: source.url) {
                        Text(url.host ?? "原作者网站").font(.system(size: 10)).foregroundColor(Studio.muted)
                    } else if let url = entry.resolvedURL {
                        Text(url.host ?? "来源网站").font(.system(size: 10)).foregroundColor(Studio.muted)
                    }
                    if let openError { Text(openError).font(.system(size: 12)).foregroundColor(Studio.red) }
                }.padding(24)
            }
            HStack {
                Text(entry.kind == .localCourses ? "只打开已有课程，不新增完成记录。" : "点击后访问原站；本机不下载或打包正文。")
                    .font(.system(size: 10)).foregroundColor(Studio.muted).lineLimit(2)
                Spacer(minLength: 12)
                if let source = entry.readingSource(in: model.sources) {
                    Button("阅读原站") { schedule(.source(source)) }.buttonStyle(StudioButtonStyle(primary: true))
                        .accessibilityIdentifier("resource-read-source")
                } else if let url = entry.resolvedURL {
                    Button(entry.kind == .book ? "查看书目" : "打开来源") {
                        if !NSWorkspace.shared.open(url) { openError = "无法打开浏览器。请检查系统默认浏览器后重试。" }
                    }.buttonStyle(StudioButtonStyle(primary: true)).accessibilityIdentifier("resource-open-external")
                } else if entry.kind == .localCourses, let stage = entry.stages.first {
                    Button("查看本阶段课程") { schedule(.stage(stage)) }.buttonStyle(StudioButtonStyle(primary: true))
                }
            }.padding(20).background(Studio.white)
        }.frame(minWidth: 570, idealWidth: 660, maxWidth: 760, minHeight: 460, idealHeight: 610, maxHeight: 720)
            .background(Studio.paper).foregroundColor(Studio.ink).preferredColorScheme(.light)
    }

    private func localCourses(_ entry: ResourceCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("进入本机课程").font(.system(size: 12, weight: .semibold))
            ForEach(entry.lessons(in: model.lessons)) { lesson in
                Button { schedule(.lesson(lesson)) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: Studio.symbol(lesson.stage)).foregroundColor(Studio.color(lesson.stage))
                        Text(lesson.title.simplifiedForDisplay).font(.system(size: 12)).lineLimit(2)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(Studio.muted)
                    }.padding(11).background(Studio.white, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).accessibilityIdentifier("resource-lesson-" + lesson.id)
            }
        }
    }

    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
        }
    }
    private func accent(_ entry: ResourceCatalogEntry) -> Color {
        switch entry.kind {
        case .localCourses: return Studio.cyan
        case .originalSite: return Studio.success
        case .book: return Studio.gold
        case .openSource: return Studio.purple
        }
    }
    private func schedule(_ action: CatalogAction) { pendingAction = action; selectedEntry = nil }
    private func performPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .source(let source):
            _ = model.recordMaterialExposure(); onSelectSource(source)
        case .lesson(let lesson):
            if let onSelectLesson { onSelectLesson(lesson) } else { model.startLesson(lesson) }
        case .stage(let stage):
            if let onSelectStage { onSelectStage(stage) } else {
                model.onlySupplements = false; model.onlyBookmarks = false; model.query = ""
                model.stageFilter = stage; model.navigate(.courses)
            }
        }
    }
}
