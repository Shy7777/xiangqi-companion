import SwiftUI

extension LearningCenterView {
    var libraryCourses: some View {
        LibraryCourseBrowser(model: model, store: store) {
            githubRequest = GitHubLibraryRequest(section: .updates)
        }
    }

    @ViewBuilder var libraryPreparationBanner: some View {
        if model.libraryPreparing {
            LibraryPreparationStatus(message: model.libraryPreparationMessage) { model.cancelCurrentOperation() }
        }
    }
}

/// An indeterminate state, not an invented time estimate or percent. Cancellation
/// stays enabled while other start actions are locked to the same operation.
struct LibraryPreparationStatus: View {
    let message: String
    let cancel: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text("正在准备这局练习").font(.system(size: 12, weight: .medium))
                Text(message.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("取消") { cancel() }.buttonStyle(StudioButtonStyle(compact: true))
                .accessibilityIdentifier("library-cancel-preparation")
        }.padding(13).background(Studio.cream, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("library-preparing")
    }
}

/// Selection and paging are passive. Paging keeps the selected position pinned;
/// only a mode button prepares a lesson. Original names remain source metadata.
private struct LibraryCourseBrowser: View {
    @ObservedObject var model: LearningModel
    @ObservedObject var store: LearningStore
    let openSources: () -> Void
    @State private var searchText = ""
    @State private var submittedSearch = ""
    @State private var showObjective = false
    @State private var objective: String?
    @State private var showSource = false
    @FocusState private var searchFocused: Bool
    private let pageSize = 50
    private var searchPending: Bool { searchText != model.libraryQuery }

    private var selectedID: String? {
        get { model.librarySelectedEntryID }
        nonmutating set { model.librarySelectedEntryID = newValue }
    }
    private var page: Int {
        get { model.libraryBrowserPage }
        nonmutating set { model.libraryBrowserPage = newValue }
    }
    private var groups: [LibraryCourseGroup] {
        model.libraryCatalog.groups.filter { model.librarySection == nil || $0.section == model.librarySection }
    }
    private var matches: [LibraryCourseEntry] { model.libraryFilteredEntries }
    private var safePage: Int { min(max(0, page), max(0, (matches.count - 1) / pageSize)) }
    private var pageEntries: [LibraryCourseEntry] { Array(matches.dropFirst(safePage * pageSize).prefix(pageSize)) }
    private var selected: LibraryCourseEntry? {
        if let selectedID, let entry = matches.first(where: { $0.id == selectedID }) { return entry }
        return pageEntries.first
    }
    private var hasFilters: Bool {
        !model.libraryQuery.isEmpty || model.libraryGroupID != nil || model.libraryFamily != nil || model.libraryStatusFilter != 0
    }
    private func title(_ entry: LibraryCourseEntry) -> String { membership(entry)?.displayTitle ?? entry.displayTitle }
    private func membership(_ entry: LibraryCourseEntry) -> LibraryCourseMembership? {
        if let groupID = model.libraryGroupID { return entry.membership(in: groupID) }
        return entry.memberships.first(where: { $0.section == model.librarySection }) ?? entry.primaryMembership
    }
    private func status(_ entry: LibraryCourseEntry) -> String { model.libraryEntryStatus(entryID: entry.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("自由选局").font(.system(size: 28, weight: .semibold, design: .serif))
                    Text("选中看棋盘，开始才进入练习。").font(.system(size: 12)).foregroundColor(Studio.muted)
                }
                Spacer()
                Button("资料同步") { openSources() }.buttonStyle(StudioButtonStyle(compact: true))
                    .accessibilityIdentifier("library-open-sources")
            }
            filters.disabled(model.libraryPreparing)
            if model.libraryPreparing {
                LibraryPreparationStatus(message: model.libraryPreparationMessage) { model.cancelCurrentOperation() }
            }
            if model.libraryCatalog.entries.isEmpty {
                StudioEmpty(symbol: "square.grid.2x2", title: "局面目录还未载入", detail: "载入已有资料，或同步开源棋库后开始。")
                Button("载入棋库") { openSources() }.buttonStyle(StudioButtonStyle(primary: true)).frame(maxWidth: .infinity)
            } else if matches.isEmpty {
                StudioEmpty(symbol: "magnifyingglass", title: "没找到符合条件的局面",
                            detail: hasFilters ? "可以换个关键词，或清除题库与状态筛选。" : "这个分类或主题暂时没有局面，可以返回完整棋库。")
                Button(hasFilters ? "清除筛选" : "显示全部局面") {
                    if hasFilters { clearFilters() }
                    else {
                        searchText = ""; submittedSearch = ""
                        model.openLibraryCourses(section: nil)
                    }
                }.buttonStyle(StudioButtonStyle(compact: true))
                    .accessibilityIdentifier("library-clear-filters")
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        entryList.frame(minWidth: 300).disabled(model.libraryPreparing)
                        preview.frame(width: 294)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        preview
                        entryList.disabled(model.libraryPreparing)
                    }
                }
            }
            Text("全库 \(model.libraryCatalog.entries.count) 个去重局面 · \(model.libraryCatalog.groups.count) 个题库")
                .font(.system(size: 10)).foregroundColor(Studio.muted)
        }
        .onAppear {
            searchText = model.libraryQuery
            submittedSearch = model.libraryQuery
            if selectedID == nil { selectedID = pageEntries.first?.id }
        }
        .onChange(of: model.librarySection) { _ in reconcileSelection() }
        .onChange(of: model.libraryGroupID) { _ in reconcileSelection() }
        .onChange(of: model.libraryQuery) { value in
            // A result published by our own debounce must not overwrite newer
            // keystrokes. Only an external query/reset replaces the local draft.
            if value != submittedSearch {
                submittedSearch = value
                searchText = value
            }
            reconcileSelection()
        }
        .onChange(of: model.libraryFamily) { _ in reconcileSelection() }
        .onChange(of: model.libraryStatusFilter) { _ in reconcileSelection() }
        .onChange(of: model.libraryRouteFilterID) { _ in reconcileSelection() }
        .onChange(of: model.libraryCatalog.pwaCommit) { _ in reconcileSelection() }
        .onChange(of: selected?.id) { _ in showObjective = false; objective = nil; showSource = false }
        .task(id: searchText) {
            let draft = searchText
            guard draft != model.libraryQuery else { return }
            do { try await Task.sleep(nanoseconds: 160_000_000) } catch { return }
            guard !Task.isCancelled, searchText == draft else { return }
            submitSearch(draft)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let id = model.libraryRouteFilterID, let route = model.roadmapRoutes.first(where: { $0.id == id }) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle").foregroundColor(Studio.accent)
                    Text(route.title.simplifiedForDisplay).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    Button("显示全部主题") { model.libraryRouteFilterID = nil }.buttonStyle(.plain).foregroundColor(Studio.accent)
                        .font(.system(size: 11)).accessibilityIdentifier("library-clear-route-filter")
                }.padding(11).background(Studio.cream, in: RoundedRectangle(cornerRadius: 9))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    sectionButton("全部", section: nil)
                    ForEach(LibraryCourseSection.allCases.filter { $0 != .other || model.libraryCatalog.groups.contains(where: { $0.section == .other }) }) {
                        sectionButton($0.title.simplifiedForDisplay, section: $0)
                    }
                }
            }
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(Studio.muted)
                    TextField("搜索题名、子力、古谱", text: $searchText).textFieldStyle(.plain)
                        .font(.system(size: 12)).focused($searchFocused)
                        .onSubmit { submitSearch(searchText) }
                        .accessibilityIdentifier("library-course-search")
                    if !searchText.isEmpty {
                        Button { searchText = ""; submitSearch(""); searchFocused = true } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Studio.muted).font(.system(size: 12))
                        }.buttonStyle(.plain).help("清空搜索").accessibilityLabel("清空搜索")
                            .accessibilityIdentifier("library-clear-search")
                    }
                }.padding(.horizontal, 12).frame(height: 36)
                    .background(Studio.white, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(searchFocused ? Studio.accent.opacity(0.55) : Studio.line, lineWidth: 0.8))
                Picker("题库", selection: Binding(get: { model.libraryGroupID ?? "" }, set: { model.libraryGroupID = $0.isEmpty ? nil : $0 })) {
                    Text("全部题库").tag("")
                    ForEach(groups) { Text($0.displayTitle).tag($0.id) }
                }.labelsHidden().frame(width: 176).accessibilityIdentifier("library-course-group")
            }
            HStack(spacing: 10) {
                Picker("练习状态", selection: $model.libraryStatusFilter) {
                    Text("全部").tag(0); Text("未练").tag(1); Text("待复习").tag(2); Text("独立通过").tag(3)
                }.pickerStyle(.segmented).frame(maxWidth: 300).accessibilityIdentifier("library-course-status")
                if model.librarySection == .opening {
                    Picker("开局类型", selection: Binding(get: { model.libraryFamily ?? "" }, set: { model.libraryFamily = $0.isEmpty ? nil : $0 })) {
                        Text("全部开局类型").tag("")
                        ForEach(model.libraryOpeningFamilies, id: \.self) { Text($0.simplifiedForDisplay).tag($0) }
                    }.labelsHidden().frame(maxWidth: 172).accessibilityIdentifier("library-opening-family")
                }
                Spacer(minLength: 0)
                if hasFilters {
                    Button("重置") { clearFilters() }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Studio.accent)
                        .help("清除关键词、题库与状态筛选").accessibilityIdentifier("library-reset-filters")
                }
            }
        }
    }

    private func sectionButton(_ title: String, section: LibraryCourseSection?) -> some View {
        let active = model.librarySection == section
        return Button {
            guard model.librarySection != section else { return }
            model.librarySection = section
            model.libraryGroupID = nil
            if section != .opening { model.libraryFamily = nil }
            model.libraryRouteFilterID = nil
        } label: {
            Text(title).font(.system(size: 12, weight: active ? .semibold : .medium)).padding(.horizontal, 13).padding(.vertical, 8)
                .foregroundColor(active ? Studio.onAccent : Studio.muted)
                .background(active ? Studio.accent : Studio.cream.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityIdentifier("library-section-\(section?.id ?? "all")")
            .accessibilityValue(active ? "当前分类" : "")
    }

    private var entryList: some View {
        let entries = matches
        let visible = pageEntries
        let chosenID = selected?.id
        return VStack(spacing: 8) {
            HStack {
                Text("\(entries.count) 个局面").font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(safePage * pageSize + 1)–\(min((safePage + 1) * pageSize, entries.count))")
                    .font(.system(size: 10)).monospacedDigit()
            }.foregroundColor(Studio.muted).padding(.horizontal, 8).padding(.vertical, 3)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visible) { entry in
                            LibraryPositionRow(title: title(entry), category: membership(entry)?.displayCategory ?? "局面练习",
                                               status: status(entry), selected: chosenID == entry.id) {
                                selectedID = entry.id
                            }.id(entry.id).accessibilityIdentifier("library-course-entry-\(entry.id)")
                        }
                    }
                }.frame(height: 420)
                    .onChange(of: safePage) { _ in if let first = pageEntries.first { proxy.scrollTo(first.id, anchor: .top) } }
            }
            HStack(spacing: 10) {
                Button { movePage(safePage - 1) } label: { Label("上一页", systemImage: "chevron.left") }
                    .disabled(safePage == 0).accessibilityIdentifier("library-page-previous")
                Spacer()
                Text("\(safePage + 1) / \(max(1, (entries.count + pageSize - 1) / pageSize))")
                    .font(.system(size: 11)).monospacedDigit().foregroundColor(Studio.muted)
                Spacer()
                Button { movePage(safePage + 1) } label: { Label("下一页", systemImage: "chevron.right") }
                    .disabled((safePage + 1) * pageSize >= entries.count).accessibilityIdentifier("library-page-next")
            }.buttonStyle(StudioButtonStyle(compact: true))
        }
    }

    @ViewBuilder private var preview: some View {
        if let entry = selected, let position = try? Position(fen: entry.fen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("已选局面").font(.system(size: 11, weight: .medium)).foregroundColor(Studio.muted)
                    Spacer()
                    if !pageEntries.contains(where: { $0.id == entry.id }) {
                        Button("定位列表") { locateSelected() }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Studio.accent)
                            .accessibilityIdentifier("library-locate-selection")
                    }
                }
                Text(title(entry)).font(.system(size: 17, weight: .semibold, design: .serif)).lineLimit(3)
                Button { start(entry, mode: .practice) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: model.libraryPreparing ? "hourglass" : "play.fill").font(.system(size: 11))
                        Text(model.libraryPreparing ? "正在准备…" : searchPending ? "筛选更新中…" : "开始引导练习")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(StudioButtonStyle(primary: true)).disabled(model.libraryPreparing || searchPending)
                    .accessibilityIdentifier("library-course-practice")
                BoardPreview(position: position, flipped: position.sideToMove == .black, width: 260)
                    .frame(maxWidth: .infinity).accessibilityLabel("所选局面的真实棋盘")
                HStack {
                    StudioTag(text: status(entry))
                    Spacer()
                    Text("\(position.sideToMove.label)先行").font(.system(size: 11)).foregroundColor(Studio.muted)
                }
                DisclosureGroup("这局先看什么", isExpanded: Binding(get: { showObjective }, set: { expanded in
                    showObjective = expanded
                    if expanded {
                        model.recordLibraryExposure(entryID: entry.id)
                        if objective == nil { objective = try? PositionLearningInsights.read(position).objective }
                    }
                })) {
                    Text((objective ?? "进入练习后看具体判断。").simplifiedForDisplay).font(.system(size: 12))
                        .foregroundColor(Studio.muted).lineSpacing(3).padding(.top, 6)
                }.font(.system(size: 11)).disabled(model.libraryPreparing).accessibilityIdentifier("library-position-objective")
                HStack(spacing: 8) {
                    Button("看演示") { start(entry, mode: .demonstration) }.accessibilityIdentifier("library-course-demonstration")
                    Spacer(minLength: 0)
                    Button("无提示检验") { start(entry, mode: .test) }.accessibilityIdentifier("library-course-test")
                }.buttonStyle(StudioButtonStyle(compact: true)).disabled(model.libraryPreparing || searchPending)
                DisclosureGroup("题目来源", isExpanded: $showSource) {
                    VStack(alignment: .leading, spacing: 8) {
                        let originalTitle = membership(entry)?.title ?? entry.title
                        if originalTitle != title(entry) {
                            Text("原题名：" + originalTitle)
                        }
                        Text((membership(entry)?.category ?? "局面练习").simplifiedForDisplay)
                        Text(membership(entry)?.section == .opening
                             ? "从当前局面往后学；原始资料没有此前的走子记录。"
                             : "由本地引擎核验续着；原题名与胜和标记不直接作为答案。")
                        Text("看过提示后立即检验，不计无提示独立通过。")
                    }.font(.system(size: 10)).foregroundColor(Studio.muted).lineSpacing(3).padding(.top, 7)
                }.font(.system(size: 10)).foregroundColor(Studio.muted)
            }.studioSurface(17)
        }
    }

    private func start(_ entry: LibraryCourseEntry, mode: StudyMode) {
        guard !searchPending, !model.libraryPreparing else { return }
        searchFocused = false
        selectedID = entry.id
        model.startLibraryEntry(entry, mode: mode, groupID: membership(entry)?.groupID)
    }
    private func clearFilters() {
        searchText = ""; submitSearch(""); model.libraryGroupID = nil
        model.libraryFamily = nil; model.libraryStatusFilter = 0
        // Keep the explicit category/topic. Clearing a search should not lose
        // the user's curriculum context or silently open an unrelated pool.
        reconcileSelection()
    }
    private func submitSearch(_ value: String) {
        submittedSearch = value
        model.libraryQuery = value
    }
    private func reconcileSelection() {
        page = 0
        if let selectedID, matches.contains(where: { $0.id == selectedID }) { return }
        selectedID = matches.first?.id
    }
    private func movePage(_ target: Int) {
        if selectedID == nil { selectedID = selected?.id }
        page = min(max(0, target), max(0, (matches.count - 1) / pageSize))
    }
    private func locateSelected() {
        guard let id = selected?.id, let index = matches.firstIndex(where: { $0.id == id }) else { return }
        page = index / pageSize
    }
}

private struct LibraryPositionRow: View {
    let title: String
    let category: String
    let status: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(selected ? Studio.accent : .clear).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium)).lineLimit(2)
                    Text(category).font(.system(size: 10)).foregroundColor(Studio.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(status).font(.system(size: 10)).foregroundColor(Studio.muted).lineLimit(1)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12)).foregroundColor(selected ? Studio.accent : Studio.line)
            }.padding(.vertical, 10).padding(.leading, 5).padding(.trailing, 12)
                .background(selected ? Studio.white : hovering ? Studio.white.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
            .accessibilityValue(selected ? "已选择，右侧显示棋盘" : status)
    }
}
