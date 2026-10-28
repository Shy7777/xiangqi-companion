import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor struct PositionLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: PositionLibraryStore
    let builtIn: [LibraryPosition]
    let onAnalyze: (Position) -> Void
    let onPractice: (Position) -> Void
    let onExposure: () -> Void
    @State private var query = ""
    @State private var category = ""
    @State private var page = 0
    @State private var selectedID: UUID?
    @State private var choosingFile = false
    @State private var preview: PositionLibraryImportPreview?
    @State private var message: String?
    @State private var importTask: Task<Void, Never>?
    @State private var importToken = UUID()
    @State private var removal: LibraryPosition?
    private let pageSize = 40

    init(store: PositionLibraryStore? = nil, builtIn: [LibraryPosition] = [], onAnalyze: @escaping (Position) -> Void,
         onPractice: @escaping (Position) -> Void, onExposure: @escaping () -> Void = {}) {
        _store = StateObject(wrappedValue: store ?? PositionLibraryStore())
        self.builtIn = builtIn
        self.onAnalyze = onAnalyze; self.onPractice = onPractice; self.onExposure = onExposure
    }
    private var allEntries: [LibraryPosition] {
        var seen = Set<String>()
        return (store.entries + builtIn).filter { seen.insert($0.fen).inserted }
    }
    private var matches: [LibraryPosition] {
        let terms = ChineseDisplayText.searchTerms(query)
        return terms.isEmpty ? allEntries : allEntries.filter {
            ChineseDisplayText.matches(normalizedText: ChineseDisplayText.searchKey([$0.title, $0.category, $0.sourceFile, $0.fen].joined(separator: " ")), terms: terms)
        }
    }
    private var visible: [LibraryPosition] { Array(matches.dropFirst(page * pageSize).prefix(pageSize)) }
    private var selected: LibraryPosition? { allEntries.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("局面库").font(.system(size: 24, weight: .semibold))
                    Text("选一个局面，直接分析或陪练。")
                        .font(.system(size: 12)).foregroundColor(Studio.muted)
                }
                Spacer()
                Link("打开上游来源 ↗", destination: URL(string: "https://github.com/dffge552/xiangqi-pwa-offline")!)
                    .accessibilityIdentifier("position-library-source")
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(StudioButtonStyle(compact: true)).accessibilityLabel("关闭局面库")
                    .accessibilityIdentifier("position-library-close")
            }
            HStack {
                TextField("导入分类（留空使用文件名）", text: $category).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("position-library-import-label")
                Button("导入本地 JSON / FEN") { choosingFile = true }.buttonStyle(StudioButtonStyle(primary: true))
                    .disabled(store.isBusy || !store.isLoaded).accessibilityIdentifier("position-library-import")
                Button("导出我的局面") { exportPersonal() }.buttonStyle(StudioButtonStyle())
                    .disabled(store.isBusy || store.entries.isEmpty).accessibilityIdentifier("position-library-export")
            }
            if store.isBusy { ProgressView("正在读取和核验局面…").font(.system(size: 12)) }
            if let error = store.error { Text(error).font(.system(size: 12)).foregroundColor(Studio.red) }
            if let message { Text(message).font(.system(size: 12)).foregroundColor(Studio.muted).textSelection(.enabled) }
            if !builtIn.isEmpty {
                Text("本机课程 \(builtIn.count) · 我的局面 \(store.entries.count)")
                    .font(.system(size: 11)).foregroundColor(Studio.muted)
            }
            if allEntries.isEmpty && !store.isBusy {
                StudioEmpty(symbol: "square.and.arrow.down", title: "从你选择的局面开始",
                    detail: "当前没有导入数据。支持 PWA 的 fen/name JSON 数组，也支持每行一个 FEN 的文本文件。先预览，再确认保存；不会自动下载上千题。")
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("搜索名称、分类、来源文件或 FEN", text: $query).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("position-library-search")
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(visible) { entry in
                                    Button { selectedID = entry.id; onExposure() } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(verbatim: entry.title.simplifiedForDisplay).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                            Text(verbatim: entry.category.simplifiedForDisplay).font(.system(size: 10)).foregroundColor(Studio.muted).lineLimit(1)
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                            .background(selectedID == entry.id ? Studio.accent.opacity(0.15) : Studio.white,
                                                        in: RoundedRectangle(cornerRadius: 6))
                                    }.buttonStyle(.plain).accessibilityIdentifier("position-library-row-\(entry.id.uuidString)")
                                }
                            }
                        }
                        HStack {
                            Button("上一页") { page = max(0, page - 1) }.disabled(page == 0)
                            Spacer()
                            Text("\(matches.count) 局面 · 第 \(page + 1) 页").font(.system(size: 11)).foregroundColor(Studio.muted)
                            Spacer()
                            Button("下一页") { page += 1 }.disabled((page + 1) * pageSize >= matches.count)
                        }.buttonStyle(StudioButtonStyle(compact: true))
                    }.frame(maxWidth: .infinity)
                    ScrollView { selectionPanel }.frame(minWidth: 230, idealWidth: 310, maxWidth: 350)
                }.frame(maxHeight: .infinity)
            }
        }.padding(24).frame(width: 920, height: 700).foregroundColor(Studio.ink).background(Studio.paper)
            .task { onExposure(); selectedID = allEntries.first?.id; await store.loadIfNeeded(); if selectedID == nil { selectedID = allEntries.first?.id } }
            .onChange(of: query) { _ in page = 0; selectedID = matches.first?.id }
            .onDisappear { importToken = UUID(); importTask?.cancel(); store.cancelPreview(); preview = nil }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json, .plainText, UTType(filenameExtension: "fen") ?? .plainText]) { result in
                do { readFile(try result.get()) } catch { message = error.localizedDescription }
            }
            .sheet(item: $preview) { value in importConfirmation(value) }
            .alert("移出个人局面库？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
                Button("取消", role: .cancel) { removal = nil }
                Button("移出", role: .destructive) {
                    guard let target = removal else { return }
                    do {
                        try store.remove(id: target.id); selectedID = matches.first?.id
                        page = min(page, max(0, (matches.count - 1) / pageSize))
                        message = "已移出个人局面。原导入文件和课程未改动；移除前的局面库保留在 positions.previous.json。"
                    } catch { message = error.localizedDescription }
                    removal = nil
                }
            } message: {
                Text("只移出这一个个人局面。原始文件与本机课程不删除；本次操作前的局面库会保留一份备份。")
            }
    }

    @ViewBuilder private var selectionPanel: some View {
        if let entry = selected, let position = entry.position {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: entry.title.simplifiedForDisplay).font(.system(size: 17, weight: .semibold)).lineLimit(3)
                Text("\(position.sideToMove.label)行棋").font(.system(size: 12, weight: .medium))
                BoardPreview(position: position, width: 260).frame(maxWidth: .infinity)
                    .accessibilityLabel("所选局面，\(position.sideToMove.label)行棋")
                Button("在本地分析") { onExposure(); onAnalyze(position) }.buttonStyle(StudioButtonStyle(primary: true))
                    .accessibilityIdentifier("position-library-analyze")
                Button("从这里开始陪练") { onExposure(); onPractice(position) }.buttonStyle(StudioButtonStyle())
                    .accessibilityIdentifier("position-library-practice")
                DisclosureGroup("来源与原始标记") {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(verbatim: "分类：\(entry.category)\n来源文件：\(entry.sourceFile)")
                        Text(verbatim: entry.fen).font(.system(size: 10, design: .monospaced))
                        if let result = entry.originalResult { Text(verbatim: "原始结果（未核验）：\(result)") }
                        if let best = entry.originalBestMove { Text(verbatim: "原始建议（不是答案）：\(best)") }
                        if let source = entry.originalSource { Text(verbatim: "附带来源文字：\(source)") }
                        Text("仅核验棋盘规则与行棋方；未证明题名、胜和或最佳着法。不计课程掌握度。")
                        if store.entries.contains(where: { $0.id == entry.id }) {
                            Button("移出个人局面库…") { removal = entry }.buttonStyle(StudioButtonStyle(destructive: true))
                                .accessibilityIdentifier("position-library-remove")
                        }
                    }.font(.system(size: 11)).foregroundColor(Studio.muted).textSelection(.enabled).padding(.top, 8)
                }
                .font(.system(size: 12))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Studio.white, in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text("选择一个局面，核对来源后分析或陪练。")
                .font(.system(size: 13)).foregroundColor(Studio.muted).padding(16)
        }
    }

    private func readFile(_ url: URL) {
        importTask?.cancel(); message = nil
        let token = UUID(); importToken = token
        let label = category
        importTask = Task { @MainActor in
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do {
                let bytes = try await Task.detached(priority: .userInitiated) {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= PositionLibraryImporter.maximumBytes else { throw PositionLibraryError.invalid("文件超过 8 MB。") }
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    let bytes = try handle.read(upToCount: PositionLibraryImporter.maximumBytes + 1) ?? Data()
                    guard bytes.count <= PositionLibraryImporter.maximumBytes else { throw PositionLibraryError.invalid("文件超过 8 MB。") }
                    return bytes
                }.value
                try Task.checkCancellation()
                let value = try await store.preview(data: bytes, fileName: url.lastPathComponent, label: label,
                    existingReferences: Set(builtIn.map(\.fen)))
                try Task.checkCancellation()
                guard importToken == token else { return }
                preview = value
            } catch is CancellationError { }
            catch { if importToken == token && !Task.isCancelled { message = error.localizedDescription } }
        }
    }

    private func exportPersonal() {
        do {
            let batches = try store.exportBatches()
            guard !batches.isEmpty else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false; panel.prompt = "导出到此文件夹"
            panel.message = "仅导出 \(store.entries.count) 个个人局面，共 \(batches.count) 个 JSON 文件；每个文件都可再次导入。本机课程引用不导出。"
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            let granted = folder.startAccessingSecurityScopedResource()
            defer { if granted { folder.stopAccessingSecurityScopedResource() } }
            let prefix = "xiangqi-positions-" + UUID().uuidString
            var written = 0
            do {
                for (index, batch) in batches.enumerated() {
                    let url = folder.appendingPathComponent("\(prefix)-\(index + 1).json")
                    guard !FileManager.default.fileExists(atPath: url.path) else { throw PositionLibraryError.invalid("导出文件已存在，未覆盖。") }
                    try batch.data.write(to: url, options: .withoutOverwriting); written += 1
                }
                message = "已导出 \(store.entries.count) 个个人局面到 \(folder.path)，共 \(written) 个 JSON 文件。"
            } catch { message = "已写出 \(written) 个文件，后续导出失败：\(error.localizedDescription)" }
        } catch { message = error.localizedDescription }
    }

    private func importConfirmation(_ value: PositionLibraryImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认导入局面").font(.system(size: 22, weight: .semibold))
            Text(verbatim: value.sourceFile).foregroundColor(Studio.muted)
            Text("总计 \(value.total) · 新增 \(value.accepted) · 重复 \(value.duplicates) · 无效 \(value.invalid)")
                .font(.system(size: 14, weight: .medium)).accessibilityIdentifier("position-library-preview-counts")
            Text("只保存通过规则检查的新局面。重复和无效条目会跳过；结果标签与 bestMove 不作为已验证答案。此操作不改变学习或分析存档。")
                .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(4)
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(value.issues, id: \.self) { Text(verbatim: $0).font(.system(size: 11)).foregroundColor(Studio.red) }
                    ForEach(value.entries.prefix(5)) { Text(verbatim: "＋ \($0.title) · \($0.category)").font(.system(size: 12)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 180)
            HStack {
                Button("取消") { preview = nil }.buttonStyle(StudioButtonStyle())
                Spacer()
                Button("确认保存 \(value.accepted) 个局面") {
                    do {
                        try store.commit(value); selectedID = value.entries.first?.id; page = 0
                        message = "已保存 \(value.accepted) 个局面；未计入课程掌握度。"; preview = nil
                    } catch { message = error.localizedDescription; preview = nil }
                }.disabled(value.accepted == 0).buttonStyle(StudioButtonStyle(primary: true))
                    .accessibilityIdentifier("position-library-confirm")
            }
        }.padding(28).frame(width: 550).foregroundColor(Studio.ink).background(Studio.paper)
    }
}
