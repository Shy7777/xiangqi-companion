import SwiftUI

/// The book's own chapter/section order is kept intact. Only expanded sections
/// instantiate record rows, so the reading desk never builds the entire tree.
struct BookContentsView: View {
    @ObservedObject var model: BookStudyModel
    var onChoose: () -> Void = {}
    @State private var expandedChapters = Set<String>()
    @State private var expandedSections = Set<String>()
    @State private var bookmarksOnly = false
    @State private var showSourceDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundColor(Studio.muted)
                TextField("搜索章节、谱例", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .accessibilityIdentifier("book-contents-search")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Studio.muted)
                    }.buttonStyle(.plain).help("清空搜索")
                }
            }.padding(10).background(Studio.white, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
            HStack {
                Text("章节目录").font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.muted)
                Spacer()
                Button { bookmarksOnly.toggle() } label: {
                    Label("收藏", systemImage: bookmarksOnly ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 11)).foregroundColor(bookmarksOnly ? Studio.accent : Studio.muted)
                        .padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(StudioQuietButtonStyle()).accessibilityValue(bookmarksOnly ? "只看收藏" : "查看全部")
            }.padding(.horizontal, 16)
            Rectangle().fill(Studio.line).frame(height: 0.7)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if let document = model.document {
                            ForEach(document.chapters.filter(chapterMatches), id: \.id) { chapter in
                                chapterRow(chapter)
                                if expandedChapters.contains(chapter.id) || isFiltering {
                                    ForEach(chapter.sections.filter(sectionMatches), id: \.id) { section in
                                        sectionRow(section)
                                        if expandedSections.contains(section.id) || isFiltering {
                                            ForEach(records(in: section), id: \.id) { record in
                                                recordRow(record).id(record.id)
                                            }
                                        }
                                    }
                                }
                            }
                            if !document.chapters.contains(where: chapterMatches) {
                                Text(bookmarksOnly ? "还没有匹配的收藏。" : "没有找到匹配的谱例。")
                                    .font(.system(size: 12)).foregroundColor(Studio.muted).padding(18)
                            }
                        }
                    }.padding(.vertical, 10).padding(.horizontal, 8)
                }
                .onAppear { revealSelection(); scrollToSelection(proxy) }
                .onChange(of: model.selectedRecordID) { _ in
                    revealSelection()
                    // No animated layout transition: a selected row remains a
                    // stable click target, including rapid chapter navigation.
                    scrollToSelection(proxy)
                }
                .onChange(of: model.document?.id) { _ in revealSelection() }
            }
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                Text("原注保存在本机 · 已读不代表掌握")
            }.font(.system(size: 10)).foregroundColor(Studio.muted)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Studio.cream.opacity(0.5))
        }.background(Studio.rail).foregroundColor(Studio.ink)
            .sheet(isPresented: $showSourceDetails) {
                if let document = model.document { BookSourceDetailsView(document: document) }
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("棋书", systemImage: "books.vertical").font(.system(size: 12, weight: .semibold))
                Spacer()
                Menu {
                    Button("导入 CBL 棋书…") { model.importPanel() }
                    Button("这份资料的完整性…") { showSourceDetails = true }.disabled(model.document == nil)
                    if !model.shelf.isEmpty {
                        Divider()
                        ForEach(model.shelf, id: \.id) { book in
                            Button(book.title) { Task { await model.openBook(id: book.id) } }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 17)).frame(width: 28, height: 28)
                }.menuStyle(.borderlessButton).fixedSize().help("切换或导入棋书")
            }
            Text(model.document?.title ?? "我的棋书")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isFiltering: Bool { !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bookmarksOnly }
    private func records(in section: BookSection) -> [BookRecord] {
        guard let document = model.document else { return [] }
        let term = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sectionHit = section.title.localizedCaseInsensitiveContains(term)
        let chapterHit = document.chapters.first(where: { $0.sections.contains(where: { $0.id == section.id }) })?
            .title.localizedCaseInsensitiveContains(term) ?? false
        return section.recordIDs.compactMap { model.record(id: $0) }.filter { record in
            (!bookmarksOnly || model.status(for: record.id).bookmarked)
                && (term.isEmpty || sectionHit || chapterHit || record.title.localizedCaseInsensitiveContains(term)
                    || record.displayTitle.localizedCaseInsensitiveContains(term))
        }
    }
    private func sectionMatches(_ section: BookSection) -> Bool { !isFiltering || !records(in: section).isEmpty }
    private func chapterMatches(_ chapter: BookChapter) -> Bool { !isFiltering || chapter.sections.contains(where: sectionMatches) }

    private func chapterRow(_ chapter: BookChapter) -> some View {
        let expanded = expandedChapters.contains(chapter.id) || isFiltering
        return Button {
            if expandedChapters.contains(chapter.id) { expandedChapters.remove(chapter.id) }
            else { expandedChapters.insert(chapter.id) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).frame(width: 10)
                Text(chapter.title).font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
                .background(Studio.cream.opacity(0.55), in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-chapter-\(chapter.id)")
            .accessibilityValue(expanded ? "已展开" : "已折叠")
    }

    private func sectionRow(_ section: BookSection) -> some View {
        let expanded = expandedSections.contains(section.id) || isFiltering
        return Button {
            if expandedSections.contains(section.id) { expandedSections.remove(section.id) }
            else { expandedSections.insert(section.id) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9)).frame(width: 10)
                Text(section.title).font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                Text("\(records(in: section).count)").font(.system(size: 10)).monospacedDigit().foregroundColor(Studio.muted)
            }.padding(.leading, 22).padding(.trailing, 10).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-section-\(section.id)")
    }

    private func recordRow(_ record: BookRecord) -> some View {
        let current = model.selectedRecordID == record.id
        let progress = model.status(for: record.id)
        return Button {
            model.chooseRecord(id: record.id); onChoose()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: current ? "circle.inset.filled" : progress.read ? "checkmark.circle" : "circle")
                    .font(.system(size: 11)).foregroundColor(current ? Studio.accent : progress.read ? Studio.success : Studio.line)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.displayTitle).font(.system(size: 12, weight: current ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if record.isSupplement { Text("补充资料").foregroundColor(Studio.gold) }
                        if progress.read { Text("已读").foregroundColor(Studio.success) }
                        else if progress.nodeID != record.rootNodeID { Text("有上次位置").foregroundColor(Studio.muted) }
                        if progress.bookmarked { Image(systemName: "bookmark.fill").foregroundColor(Studio.accent) }
                    }.font(.system(size: 10))
                }
                Spacer(minLength: 0)
            }.padding(.leading, 30).padding(.trailing, 9).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(current ? Studio.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-record-\(record.id)")
            .accessibilityValue(current ? "当前谱例" : progress.read ? "已读" : "尚未标记已读")
    }

    private func revealSelection() {
        guard let document = model.document, let record = model.record else { return }
        if let chapter = document.chapters.first(where: { $0.sections.contains(where: { $0.id == record.sectionID }) }) {
            expandedChapters.insert(chapter.id); expandedSections.insert(record.sectionID)
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let id = model.selectedRecordID else { return }
        // Expanded rows enter the hierarchy on the next layout pass. An early
        // scroll would otherwise silently target a row that does not exist yet.
        DispatchQueue.main.async {
            guard model.selectedRecordID == id else { return }
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct BookSourceDetailsView: View {
    let document: BookDocument
    @Environment(\.dismiss) private var dismiss
    @State private var showIntegrity = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("资料与完整性").font(.system(size: 20, weight: .semibold, design: .serif))
                Spacer()
                StudioIconButton(symbol: "xmark", label: "关闭资料说明") { dismiss() }
            }.padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(document.title).font(.system(size: 16, weight: .semibold))
                    Text("\(document.records.count) 条记录 · \(document.commentCount) 条文件评注 · \(document.variationCount) 个额外分支入口")
                        .font(.system(size: 12)).foregroundColor(Studio.muted)
                    Text("这里保留的是导入文件的原文，不代表已与纸书逐字校对。显示标题中的校订不会改写原件或评注；软件学习引导和引擎分析另行标明。")
                        .font(.system(size: 13)).lineSpacing(5)
                    if !document.issues.isEmpty {
                        Text("需要留意").font(.system(size: 13, weight: .semibold))
                        ForEach(Array(document.issues.enumerated()), id: \.offset) { _, issue in
                            Label(issue.message, systemImage: "info.circle")
                                .font(.system(size: 12)).foregroundColor(Studio.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    DisclosureGroup("文件校验信息", isExpanded: $showIntegrity) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(verbatim: document.sourceFilename)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(document.sourceByteCount), countStyle: .file))
                            Text("SHA-256").fontWeight(.semibold)
                            Text(verbatim: document.sourceSHA256).font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                        }.font(.system(size: 11)).foregroundColor(Studio.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }.font(.system(size: 12))
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(width: 560, height: 500).background(Studio.white).foregroundColor(Studio.ink)
    }
}
