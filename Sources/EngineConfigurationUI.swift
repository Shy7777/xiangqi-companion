import AppKit

@MainActor
enum EngineConfigurationUI {
    static func configure() {
        let binaryPanel = NSOpenPanel()
        binaryPanel.title = "选择本地象棋引擎"
        binaryPanel.message = "请选择你自行取得、确认可信的 Pikafish 可执行文件。本软件不下载或提供引擎与权重。"
        binaryPanel.canChooseDirectories = false
        binaryPanel.allowsMultipleSelection = false
        guard binaryPanel.runModal() == .OK, let binary = binaryPanel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: binary.path),
              (try? binary.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            notify("无法使用这个文件", "请选择普通的可执行文件；本软件不会更改文件权限或绕过系统安全保护。")
            return
        }
        let networkPanel = NSOpenPanel()
        networkPanel.title = "选择引擎权重"
        networkPanel.message = "请选择与引擎兼容、你有权使用的 NNUE 权重。引擎与权重可能采用不同许可，请自行核对。"
        networkPanel.canChooseDirectories = false
        networkPanel.allowsMultipleSelection = false
        networkPanel.directoryURL = binary.deletingLastPathComponent()
        guard networkPanel.runModal() == .OK, let network = networkPanel.url else { return }
        guard FileManager.default.isReadableFile(atPath: network.path),
              (try? network.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            notify("无法读取权重", "请选择可读取的普通权重文件。")
            return
        }
        guard EngineConfiguration.resolve(environment: [
            "XQ_ENGINE_PATH": binary.path, "XQ_ENGINE_NETWORK": network.path
        ]).isConfigured else {
            notify("无法使用这个路径", "引擎与权重的文件路径不能包含换行或其他控制字符。请更改文件名后重新选择。")
            return
        }
        let confirm = NSAlert()
        confirm.messageText = "保存这组引擎配置？"
        confirm.informativeText = "下次启动本软件并使用分析功能时，会以你的本机权限运行以下程序。请只使用可信来源的引擎。现在仅保存路径，不运行或复制文件。\n\n引擎：\(binary.path)\n权重：\(network.path)"
        confirm.addButton(withTitle: "保存配置")
        confirm.addButton(withTitle: "取消")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        EngineConfiguration.save(binary: binary, network: network)
        let overridden = ["XQ_ENGINE_PATH", "XQ_ENGINE_NETWORK", "XQ_ENGINE_DIR"].contains { ProcessInfo.processInfo.environment[$0] != nil }
        notify("配置已保存", "请正常退出并重新打开本软件后使用分析功能。当前棋局不会被打断。" + (overridden ? "\n当前进程设置了引擎环境变量；环境变量的优先级高于此配置。" : ""))
    }

    static func clear() {
        let confirm = NSAlert()
        confirm.messageText = "清除保存的引擎路径？"
        confirm.informativeText = "不会删除引擎或权重文件。重启后生效；显式设置的环境变量仍优先使用。"
        confirm.addButton(withTitle: "清除配置")
        confirm.addButton(withTitle: "取消")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        EngineConfiguration.clear()
        notify("配置已清除", "重启软件后生效，文件和当前棋局均未删除。")
    }

    private static func notify(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
