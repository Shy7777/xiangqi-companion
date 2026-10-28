import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FENBatchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var result: FENBatchResult?
    @State private var notice: String?
    @State private var busy = false
    @State private var ticket = UUID()
    @State private var conversionTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("局面批量转换").font(.system(size: 23, weight: .semibold, design: .serif)); Spacer()
                StudioIconButton(symbol: "xmark", label: "关闭转换") { dismiss() }
            }
            Text("粘贴 FEN 或 JSON；题名可放同一行或下一行。").font(.system(size: 12)).foregroundColor(Studio.muted)
            TextEditor(text: $input).font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 240).accessibilityIdentifier("fen-batch-input")
            HStack {
                Button("读取文件") { readFile() }.buttonStyle(StudioButtonStyle(compact: true))
                Button("转换并核验") { convert() }.buttonStyle(StudioButtonStyle(primary: true, compact: true)).disabled(busy)
                    .accessibilityIdentifier("fen-batch-convert")
                if busy { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let result {
                Text("\(result.accepted) 个不同合法局面 · \(result.duplicates) 重复 · \(result.invalid) 未通过").font(.system(size: 13, weight: .medium))
                if !result.issues.isEmpty { ScrollView { Text(result.issues.joined(separator: "\n")).font(.system(size: 11)).foregroundColor(Studio.red).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 75) }
                HStack {
                    Button("复制 JSON") { copy(String(data: result.jsonData, encoding: .utf8) ?? "") }
                    Button("复制 FEN + 题名") { copy(result.namedFENText) }
                    Button("保存 JSON") { save(result.jsonData) }
                }.buttonStyle(StudioButtonStyle(compact: true)).disabled(result.accepted == 0)
                Text("可在“我的局面”导入 JSON；先预览再确认，不会自动改动题库。").font(.system(size: 11)).foregroundColor(Studio.muted)
            }
            if let notice { Text(notice).font(.system(size: 11)).foregroundColor(Studio.muted) }
        }.padding(25).frame(width: 740, height: 580).background(Studio.paper)
            .onChange(of: input) { _ in ticket = UUID(); conversionTask?.cancel(); busy = false; result = nil; notice = nil }
            .onDisappear { conversionTask?.cancel(); ticket = UUID() }
    }
    private func convert() {
        let text = input, request = UUID(); ticket = request; busy = true; result = nil; notice = nil
        conversionTask = Task {
            do {
                let task = Task.detached { try FENBatchCodec.convert(text: text) }
                let value = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                guard ticket == request, !Task.isCancelled else { return }
                result = value; busy = false
            } catch { guard ticket == request else { return }; notice = error.localizedDescription; busy = false }
        }
    }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string); notice = "已复制" }
    private func readFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json, .plainText]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try GitHubLibraryStore.readBounded(url, maximum: FENBatchCodec.maximumBytes)
            guard let text = String(data: data, encoding: .utf8) else { throw FENBatchError.invalid("文件不是 UTF-8 文本。") }
            input = text
        } catch { notice = error.localizedDescription }
    }
    private func save(_ data: Data) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "转换后的局面.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic); notice = "已保存；尚未加入个人题库" }
        catch { notice = error.localizedDescription }
    }
}
