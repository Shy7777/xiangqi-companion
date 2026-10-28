import SwiftUI

/// Selection is a passive preview. Only the confirmed replacement changes the
/// manual board; damaged legacy entries remain visible and are never deleted.
struct ManualRecordBrowser: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var previewPly = 0
    @State private var selectedID = "current"
    @State private var confirmReplace = false
    @State private var confirmRecovery = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("本机棋谱").font(.system(size: 21, weight: .semibold, design: .serif))
                Spacer()
                Button("导入文件") { model.importRecordUI() }.buttonStyle(StudioButtonStyle(compact: true))
                Button("粘贴棋谱") { model.importRecordClipboardUI() }.buttonStyle(StudioButtonStyle(compact: true))
                StudioIconButton(symbol: "xmark", label: "关闭棋谱库") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider().overlay(Studio.line)
            HStack(alignment: .top, spacing: 0) {
                libraryList.frame(width: 220)
                Divider().overlay(Studio.line)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().overlay(Studio.line)
            HStack {
                Button("保存当前棋谱") { _ = model.saveRecordToLibrary() }
                    .buttonStyle(StudioButtonStyle(compact: true)).disabled(model.isSessionProtected)
                Menu("导出当前") {
                    Button("棋谱 JSON（含注释）") { model.exportRecordUI() }
                    Button("标准 UCI 着序") { model.exportRecordUI(format: .uci) }
                    Button("当前 FEN（无历史）") { model.exportRecordUI(format: .fen) }
                }.disabled(model.isSessionProtected)
                Spacer()
                Button("用此棋谱替换") { confirmReplace = true }
                    .buttonStyle(StudioButtonStyle(primary: true, compact: true))
                    .disabled(model.recordPreview == nil || (model.isSessionProtected && selectedID == "current"))
                    .accessibilityIdentifier("record-confirm-replace")
            }.padding(.horizontal, 16).padding(.top, 12)
            Text(model.message).font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
        }.frame(width: 820, height: 700).background(Studio.paper).foregroundColor(Studio.ink).preferredColorScheme(.light)
            .onAppear {
                model.refreshRecordLibrary()
                if model.recordPreview == nil && model.recordPreviewError == nil { model.previewCurrentRecord() }
                synchronizePreview()
            }
            .onChange(of: model.recordPreview?.id) { _ in synchronizePreview() }
            .confirmationDialog("替换当前棋谱？", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("保留当前棋谱并替换") { _ = model.acceptRecordPreview(at: previewPly) }
                Button("取消", role: .cancel) {}
            } message: {
                Text(model.isSessionProtected ? "先保留损坏原文件的副本，再载入所选棋谱。" : "当前完整着序先存入本机历史；所选棋谱从预览位置打开。")
            }
            .alert("保留原文件后新建？", isPresented: $confirmRecovery) {
                Button("保留副本并新建") { model.newGame(); model.previewCurrentRecord() }
                Button("取消", role: .cancel) {}
            } message: { Text("原 session.json 会先复制为 recovery 文件；无法备份时不新建。") }
    }

    private var libraryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                selectedID = "current"; model.previewCurrentRecord()
            } label: {
                Label("当前棋盘", systemImage: "square.grid.3x3")
                    .font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(11)
                    .background(selectedID == "current" ? Studio.accent.opacity(0.10) : Studio.white, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            HStack {
                Text("历史 · \(model.recordEntries.count)").font(.system(size: 11)).foregroundColor(Studio.muted)
                Spacer()
                Button { model.refreshRecordLibrary() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("刷新历史")
            }
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.recordEntries) { entry in
                        Button {
                            selectedID = entry.id; model.previewRecordEntry(entry)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: model.recordEntryErrors[entry.id] == nil ? "doc.text" : "exclamationmark.triangle")
                                    .foregroundColor(model.recordEntryErrors[entry.id] == nil ? Studio.muted : Studio.red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.date, style: .date).font(.system(size: 12, weight: .medium))
                                    Text(entry.title.simplifiedForDisplay).font(.system(size: 10, design: .monospaced)).lineLimit(1).foregroundColor(Studio.muted)
                                    if model.recordEntryErrors[entry.id] != nil { Text("损坏 · 原文件保留").font(.system(size: 10)).foregroundColor(Studio.red) }
                                }
                                Spacer(minLength: 0)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedID == entry.id ? Studio.accent.opacity(0.10) : Studio.white, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).accessibilityIdentifier("record-entry-\(entry.id)")
                    }
                    if model.recordEntries.isEmpty { Text("还没有保存的棋谱").font(.system(size: 12)).foregroundColor(Studio.muted).padding(.vertical, 20) }
                }
            }
            if let notice = model.recordLibraryNotice { Text(notice).font(.system(size: 11)).foregroundColor(Studio.red).fixedSize(horizontal: false, vertical: true) }
            Button("在访达中查看") { model.revealRecordLibrary() }.font(.system(size: 11)).buttonStyle(.plain).foregroundColor(Studio.accent)
        }.padding(15)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isSessionProtected {
                HStack {
                    Label("损坏原记录已保护", systemImage: "lock.shield").font(.system(size: 12)).foregroundColor(Studio.red)
                    Spacer()
                    Button("保留副本并新建") { confirmRecovery = true }.font(.system(size: 11))
                }
            }
            if let failure = model.recordPreviewError {
                StudioEmpty(symbol: "doc.badge.ellipsis", title: "未载入这份棋谱", detail: failure)
            } else if let preview = model.recordPreview {
                Text(preview.title.simplifiedForDisplay).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                if let notice = preview.imported.notice {
                    Text(notice).font(.system(size: 11)).foregroundColor(Studio.accent).fixedSize(horizontal: false, vertical: true)
                }
                GeometryReader { geometry in
                    let width = max(0, min(geometry.size.width, geometry.size.height * WarmBoardLayout.aspectRatio))
                    if preview.imported.replay.positions.indices.contains(previewPly) {
                        BoardPreview(position: preview.imported.replay.positions[previewPly], flipped: model.flipped,
                                     lastMove: previewPly > 0 ? preview.imported.replay.moves[previewPly - 1] : nil, width: width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                HStack {
                    StudioIconButton(symbol: "backward.end", label: "棋谱起点") { previewPly = 0 }
                    StudioIconButton(symbol: "chevron.left", label: "棋谱上一步") { previewPly = max(0, previewPly - 1) }.disabled(previewPly == 0)
                    Spacer()
                    Text("\(previewPly) / \(preview.imported.record.moves.count) 半步").font(.system(size: 12, design: .monospaced)).foregroundColor(Studio.muted)
                    Spacer()
                    StudioIconButton(symbol: "chevron.right", label: "棋谱下一步") { previewPly = min(preview.imported.record.moves.count, previewPly + 1) }
                        .disabled(previewPly == preview.imported.record.moves.count)
                    StudioIconButton(symbol: "forward.end", label: "棋谱终点") { previewPly = preview.imported.record.moves.count }
                }
                if let note = preview.imported.record.annotations?.first(where: { $0.ply == previewPly }) {
                    DisclosureGroup("此步注释") { Text(note.text.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted) }
                }
            } else {
                Spacer(); Text("选择一份棋谱预览").foregroundColor(Studio.muted); Spacer()
            }
            DisclosureGroup("格式与限制") {
                Text("JSON 保存完整着序和注释；UCI 文本保存起局与着序；FEN 只保存当前局面。PWA 只转换当前棋盘，不还原未核验历史。本机最多 200 份、16 MiB，不自动删除旧文件。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 11))
        }.padding(18)
    }

    private func synchronizePreview() {
        previewPly = model.recordPreview?.cursor ?? 0
        if model.recordPreview?.title != "当前棋盘", selectedID == "current" { selectedID = "import" }
    }
}
