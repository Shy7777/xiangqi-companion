import SwiftUI
import AppKit

enum GitHubLibrarySection: String, CaseIterable, Identifiable {
    case positions, resources, updates
    var id: String { rawValue }
    var title: String { switch self { case .positions: return "局面全集"; case .resources: return "资料全集"; case .updates: return "同步记录" } }
}

struct GitHubLibraryRequest: Identifiable {
    let id = UUID()
    let section: GitHubLibrarySection
}

/// One local viewer for both synchronized sources. It never executes repository
/// HTML/JavaScript, opens external pages automatically, or writes study scores.
struct GitHubLibraryView: View {
    @ObservedObject var store: GitHubLibraryStore
    let catalog: LibraryCourseCatalog
    let initialSection: GitHubLibrarySection
    let onStudy: (String) -> Void
    let onAnalyze: (Position) -> Void
    let onPractice: (Position) -> Void
    let onRead: (LearningSource) -> Void
    let onPersonal: () -> Void
    let onCurated: () -> Void
    let onExposure: () -> Void
    let onPositionExposure: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var section = GitHubLibrarySection.positions
    @State private var query = ""
    @State private var fileFilter = ""
    @State private var categoryFilter = ""
    @State private var selectedID: String?
    @State private var selectedResourceID: String?
    @State private var page = 0
    @State private var message: String?
    @State private var showConverter = false
    @State private var visited = Set<String>()
    private let pageSize = 50

    private var positions: [SyncedPosition] {
        let terms = ChineseDisplayText.searchTerms(query)
        let matchingIDs: Set<String>? = terms.isEmpty ? nil : Set(catalog.entries(query: query).map(\.id))
        return (store.snapshot?.positions ?? []).filter { entry in
            (fileFilter.isEmpty || entry.origins.contains { fileFilter == "patterns" ? $0.file.hasPrefix("Chess Patterns/") : $0.file == fileFilter })
                && (matchingIDs?.contains(entry.id) ?? true)
        }
    }
    private var selected: SyncedPosition? { store.snapshot?.positions.first { $0.id == selectedID } }
    private var resources: [SyncedWebResource] {
        let terms = ChineseDisplayText.searchTerms(query)
        return (store.snapshot?.resources ?? []).filter { entry in
            (categoryFilter.isEmpty || entry.categories.contains(categoryFilter)) &&
            (terms.isEmpty || ChineseDisplayText.matches(normalizedText: ChineseDisplayText.searchKey(entry.title + " " + entry.context + " " + entry.categoryTitle + " " + entry.url.absoluteString), terms: terms))
        }
    }
    private var resource: SyncedWebResource? { store.snapshot?.resources.first { $0.id == selectedResourceID } }
    private var rootFiles: [String] { store.snapshot?.files.map { $0.file.path }.filter { !$0.contains("/") } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Text("开源棋库").font(.system(size: 25, weight: .semibold, design: .serif))
                Picker("内容", selection: $section) { ForEach(GitHubLibrarySection.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 340).accessibilityIdentifier("github-section")
                Spacer()
                Button(store.isBusy ? "取消同步" : "同步 GitHub") { if store.isBusy { store.cancel() } else { store.startSync() } }
                    .buttonStyle(StudioButtonStyle(primary: true, compact: true)).accessibilityIdentifier("github-sync")
                StudioIconButton(symbol: "xmark", label: "关闭开源棋库") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if store.isBusy {
                HStack { ProgressView().controlSize(.small); Text(store.status).font(.system(size: 12)); Spacer()
                    if store.totalFiles > 0 { Text("\(store.completedFiles) / \(store.totalFiles)").monospacedDigit().font(.system(size: 11)) }
                }
            }
            if let error = store.error { Text(error).font(.system(size: 12)).foregroundColor(Studio.red).textSelection(.enabled) }
            if store.snapshot == nil {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 36)).foregroundColor(Studio.accent)
                    Text("两个仓库，一处研究").font(.system(size: 24, weight: .semibold, design: .serif))
                    Text("完整资料目录与全部局面包，首次同步后离线使用。").font(.system(size: 13)).foregroundColor(Studio.muted)
                    Button("同步全部资料") { store.startSync() }.disabled(store.isBusy)
                        .buttonStyle(StudioButtonStyle(primary: true)).accessibilityIdentifier("github-first-sync")
                }.frame(maxWidth: .infinity)
                Spacer()
            } else if section == .updates { updates }
            else {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(Studio.muted)
                    TextField(section == .positions ? "搜题名、子力、古谱或分类" : "搜书名、作者、视频或工具", text: $query)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("github-search")
                    if section == .positions {
                        Picker("题库", selection: $fileFilter) {
                            Text("全部题库").tag("")
                            ForEach(rootFiles, id: \.self) { Text(PWADataParser.category(for: $0)).tag($0) }
                            Text("实用残局定式").tag("patterns")
                        }.labelsHidden().frame(width: 170).accessibilityIdentifier("github-position-category")
                        Button { chooseRandom() } label: { Image(systemName: "shuffle") }.buttonStyle(StudioButtonStyle(compact: true))
                            .disabled(positions.isEmpty).help("在当前筛选内随机选题").accessibilityIdentifier("github-random")
                    } else {
                        Picker("类别", selection: $categoryFilter) {
                            Text("全部类别").tag("")
                            ForEach(resourceCategories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }.labelsHidden().frame(width: 170).accessibilityIdentifier("github-resource-category")
                    }
                }
                HStack(alignment: .top, spacing: 20) {
                    if section == .positions { positionList } else { resourceList }
                    ScrollView { if section == .positions { positionDetail } else { resourceDetail } }
                        .frame(width: 344)
                }.frame(maxHeight: .infinity)
            }
            HStack {
                Text(store.isBusy ? "只更新资料，不更新软件或学习记录" : store.status).font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(1)
                Spacer()
                Button("批量转换") { showConverter = true }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("github-converter")
                Button("我的局面") { onPersonal() }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("github-personal")
                Button("教学书架") { onCurated() }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("github-curated")
            }
            if let message { Text(message).font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(2) }
        }.padding(24).frame(width: 1020, height: 740).background(Studio.paper).foregroundColor(Studio.ink)
            .task { section = initialSection; onExposure(); await store.load(); selectFirst() }
            .onChange(of: section) { _ in query = ""; page = 0; selectFirst() }
            .onChange(of: query) { _ in page = 0; visited = []; selectFirst() }
            .onChange(of: fileFilter) { _ in page = 0; visited = []; selectFirst() }
            .onChange(of: categoryFilter) { _ in selectFirst() }
            .onChange(of: store.snapshot?.syncedAt) { _ in page = 0; selectFirst() }
            .sheet(isPresented: $showConverter) { FENBatchView() }
    }
    private var resourceCategories: [String] {
        var seen = Set<String>()
        return (store.snapshot?.resources ?? []).flatMap(\.categories).filter { seen.insert($0).inserted }
    }
    private var positionList: some View {
        let matches = positions
        return VStack(spacing: 12) {
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(matches.dropFirst(page * pageSize).prefix(pageSize))) { item in
                        listRow(title: item.title, subtitle: item.categories.joined(separator: " · "), active: item.id == selectedID) { selectedID = item.id }
                            .accessibilityIdentifier("github-position-" + item.id)
                    }
                    if matches.isEmpty { Text("没有匹配的局面").foregroundColor(Studio.muted).padding(30) }
                }
            }
            HStack {
                Button("上一页") { page = max(0, page - 1) }.disabled(page == 0)
                Spacer(); Text("\(matches.count) 局面 · 第 \(page + 1) 页").font(.system(size: 11)).monospacedDigit(); Spacer()
                Button("下一页") { page += 1 }.disabled((page + 1) * pageSize >= matches.count)
            }.buttonStyle(StudioButtonStyle(compact: true))
        }.frame(maxWidth: .infinity)
    }
    private var resourceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(resources.count) 项资源").font(.system(size: 11)).foregroundColor(Studio.muted)
            ScrollView { LazyVStack(spacing: 5) { ForEach(resources) { item in
                listRow(title: item.title, subtitle: item.categoryTitle, active: item.id == selectedResourceID) { selectedResourceID = item.id }
                    .accessibilityIdentifier("github-resource-" + item.id)
            } } }
        }.frame(maxWidth: .infinity)
    }
    private func listRow(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title.simplifiedForDisplay).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text(verbatim: subtitle.simplifiedForDisplay).font(.system(size: 10)).foregroundColor(Studio.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
                .background(active ? Studio.accent.opacity(0.13) : Studio.white, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var positionDetail: some View {
        if let selected, let position = selected.position {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: selected.title.simplifiedForDisplay).font(.system(size: 18, weight: .semibold, design: .serif)).lineLimit(3)
                Text("\(position.sideToMove.label)行棋").font(.system(size: 12)).foregroundColor(Studio.accent)
                BoardPreview(position: position, width: 300).accessibilityLabel("当前同步局面")
                Button { onStudy(selected.id) } label: { Text("开始教程").frame(maxWidth: .infinity) }
                    .buttonStyle(StudioButtonStyle(primary: true)).accessibilityIdentifier("github-study")
                HStack {
                    Button("自由陪练") { onExposure(); onPositionExposure(selected.id); onPractice(position) }.accessibilityIdentifier("github-practice")
                    Button("引擎分析") { onExposure(); onPositionExposure(selected.id); onAnalyze(position) }.accessibilityIdentifier("github-analyze")
                    Button("复制 FEN") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(selected.fen, forType: .string); message = "已复制当前局面" }
                }.buttonStyle(StudioButtonStyle(compact: true))
                DisclosureGroup("出处与原始建议 · \(selected.origins.count)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("原始胜和与建议不是已验证答案；用本地引擎核验。").foregroundColor(Studio.muted)
                        ForEach(Array(selected.origins.enumerated()), id: \.offset) { _, origin in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: "\(origin.item.category) · 第 \(origin.item.index) 项").fontWeight(.medium)
                                Text(verbatim: origin.item.title)
                                if let result = origin.item.result { Text(verbatim: "原始标记：" + String(result.prefix(120))) }
                                if let best = origin.item.bestMove { Text(verbatim: "原始建议：" + String(best.prefix(120))) }
                                if let commit = store.snapshot?.pwaCommit,
                                   let url = URL(string: "https://github.com/\(GitHubLibraryRemote.pwaRepo)/blob/\(commit)/")?.appendingPathComponent(origin.file) {
                                    Link("核对来源文件 ↗", destination: url)
                                }
                            }.padding(.vertical, 5)
                        }
                    }.font(.system(size: 11)).padding(.top, 10).textSelection(.enabled)
                        .onAppear { onPositionExposure(selected.id) }
                }.font(.system(size: 12))
            }.padding(16).background(Studio.white, in: RoundedRectangle(cornerRadius: 13))
        }
    }
    @ViewBuilder private var resourceDetail: some View {
        if let item = resource {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: item.categories.contains(where: { $0.hasPrefix("书籍") }) ? "books.vertical" : "link").font(.system(size: 34)).foregroundColor(Studio.accent)
                Text(verbatim: item.title.simplifiedForDisplay).font(.system(size: 22, weight: .semibold, design: .serif))
                Text(verbatim: item.context.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
                Button("打开资料") {
                    onExposure()
                    onRead(LearningSource(id: "github-" + item.id, title: item.title, url: item.url.absoluteString,
                        note: "上游资源索引；目录可离线检索，正文由原站提供。书籍、视频和工具各有自己的使用条款。"))
                }.buttonStyle(StudioButtonStyle(primary: true)).accessibilityIdentifier("github-open-resource")
                Text(item.url.host ?? "原站").font(.system(size: 11)).foregroundColor(Studio.muted)
                DisclosureGroup("索引来源") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("awesome-xiangqi 为 CC0 索引，PWA 仓库为 MIT；外链作品有各自条款。")
                        ForEach(item.origins) { origin in
                            Text(verbatim: origin.repository + " · " + origin.category)
                            if let url = origin.sourceURL { Link("查看原始条目 ↗", destination: url) }
                        }
                    }.font(.system(size: 11)).padding(.top, 8)
                }.font(.system(size: 12))
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Studio.white, in: RoundedRectangle(cornerRadius: 13))
        }
    }
    private var updates: some View {
        ScrollView {
            if let value = store.snapshot {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 36) {
                        metric("资源目录", value: "\(value.resources.count)")
                        metric("题库文件", value: "\(value.files.count)")
                        metric("不同局面", value: "\(value.positions.count)")
                        metric("待核验条目", value: "\(value.invalidCount)")
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Studio.white, in: RoundedRectangle(cornerRadius: 12))
                    Text("最后同步：\(value.syncedAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 12))
                    Text("awesome \(value.awesome.items.count) 项 + PWA \(value.pwaResources.count) 项；同一链接合并，全部出处保留。").font(.system(size: 12)).foregroundColor(Studio.muted)
                    Text("原始 \(value.rawCount) 条 · 重复 \(value.duplicateCount) 条 · 不合法 \(value.invalidCount) 条；重复局面仍保留所有分类与出处。").font(.system(size: 12)).foregroundColor(Studio.muted)
                    Text("资料下载 \(ByteCountFormatter.string(fromByteCount: Int64(value.downloadedBytes), countStyle: .file)) · 复用 \(value.reusedFiles) 个文件（不含版本与许可请求）").font(.system(size: 12))
                    DisclosureGroup("版本与同步范围") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("awesome：\(value.awesome.commit)\nPWA：\(value.pwaCommit)").font(.system(size: 11, design: .monospaced))
                            Text("只同步公开目录和全量局面 JSON；代码、引擎、模型不会自动执行或更新。书籍全文和视频仍按原站权限阅读。失败或取消不替换上次成功的资料；个人局面、棋谱与学习记录独立保存。")
                        }.font(.system(size: 12)).foregroundColor(Studio.muted).padding(.top, 10).textSelection(.enabled)
                    }
                    DisclosureGroup("全部文件与未通过条目") {
                        LazyVStack(alignment: .leading, spacing: 10) { ForEach(value.files, id: \.file.path) { report in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: "\(report.file.path) · \(report.total) 条 / \(report.invalid) 未通过").font(.system(size: 11, weight: .medium))
                                ForEach(report.issues, id: \.self) { Text(verbatim: $0).font(.system(size: 10)).foregroundColor(Studio.red) }
                            }
                        } }.padding(.top, 10)
                    }
                }.padding(8)
            }
        }.frame(maxHeight: .infinity)
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)); Text(title).font(.system(size: 11)).foregroundColor(Studio.muted) }
    }
    private func selectFirst() { selectedID = positions.first?.id; selectedResourceID = resources.first?.id }
    private func chooseRandom() {
        let pool = positions
        if let selectedID { visited.insert(selectedID) }
        var remaining = pool.filter { !visited.contains($0.id) }
        if remaining.isEmpty { visited = []; remaining = pool; message = "本次筛选已浏览一轮，重新洗牌；浏览不记为练会" }
        else { message = "本轮还有 \(remaining.count) 个未抽取局面；关闭棋库后重新开始" }
        if let item = remaining.randomElement() {
            visited.insert(item.id); selectedID = item.id
            if let index = pool.firstIndex(where: { $0.id == item.id }) { page = index / pageSize }
        }
    }
}
