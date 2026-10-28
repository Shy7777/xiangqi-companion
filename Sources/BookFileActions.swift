import AppKit
import UniformTypeIdentifiers

extension BookStudyModel {
    func importPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cbl") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "选择本地 CBL 棋书。原件完整保留，评注不作摘要或改写。"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.importBook(url: url) }
        }
    }
}
