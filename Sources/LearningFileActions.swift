import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
private enum LearningFileTask {
    // A single file operation at a time prevents a slower import from racing
    // a later restore. Export and ordinary chess interaction remain available.
    static var isLoading = false
}

/// File panels belong to the macOS adapter, not the learning state machine.
extension LearningModel {
    func importCourses() {
        guard !LearningFileTask.isLoading else { notice = "正在处理已选择的文件，请稍候。"; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "选择课程包 JSON；全部局面和走法通过校验后才会加入。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let builtInIDs = Set(Self.builtInLessons.map(\.id))
        let existingIDs = builtInIDs.union(store.data.importedLessons.map(\.id))
        LearningFileTask.isLoading = true
        notice = "正在读取并校验课程…"
        Task { @MainActor in
            defer { LearningFileTask.isLoading = false }
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let bytes = try SafeLocalFile.read(url, maximumBytes: 8_000_000)
                    let pack = try JSONDecoder().decode(StudyPack.self, from: bytes)
                    return try pack.preparedForImport(existingLessonIDs: existingIDs)
                }.value
                try store.importPreparedPack(prepared, builtInIDs: builtInIDs, builtInSources: Self.builtInSources)
                notice = "已导入并保存 \(prepared.lessonCount) 课。所有局面和走法均通过规则校验。"
            } catch { notice = "未导入，原课程保持不变：\(error.localizedDescription)" }
        }
    }
    func exportCourses() {
        let pack = StudyPack(title: "象棋伴练课程包", sources: sources, lessons: lessons)
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try export(encoder.encode(pack), name: "象棋伴练-课程包.json")
        } catch { notice = error.localizedDescription }
    }
    func exportProgress() {
        do { try export(store.exportData(), name: "象棋伴练-学习记录.json") }
        catch { notice = error.localizedDescription }
    }
    func restoreProgress() {
        guard !LearningFileTask.isLoading else { notice = "正在处理已选择的文件，请稍候。"; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "选择此前导出的完整学习记录。恢复只影响学习区，不改变伴练分析棋局。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert(); alert.messageText = "恢复这份学习记录？"
        alert.informativeText = "当前学习记录会先另存一份备份，再由所选记录替换。课程、错题、练习历史和学习进度一起恢复；伴练分析棋局保持不变。"
        alert.addButton(withTitle: "备份当前记录并恢复"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        LearningFileTask.isLoading = true
        notice = "正在读取学习记录…"
        Task { @MainActor in
            defer { LearningFileTask.isLoading = false }
            do {
                let bytes = try await Task.detached(priority: .userInitiated) {
                    try SafeLocalFile.read(url, maximumBytes: 8_000_000)
                }.value
                let backup = try restoreLearningArchive(bytes)
                notice = "学习记录已恢复。" + (backup.map { "恢复前的原记录保留在：\($0.path)" } ?? "")
            } catch { notice = "未恢复，原记录保持不变：\(error.localizedDescription)" }
        }
    }
    private func export(_ data: Data, name: String) throws {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic); notice = "已保存 \(url.lastPathComponent)。"
    }
}
