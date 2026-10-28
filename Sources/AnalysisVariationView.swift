import SwiftUI

struct AnalysisVariationView: View {
    let line: AnalysisVariation
    @Environment(\.dismiss) private var dismiss
    @State private var cursor = 0
    var body: some View {
        VStack(spacing: 18) {
            HStack { Text("双方连续五步").font(.system(size: 22, weight: .semibold, design: .serif)); Spacer()
                StudioIconButton(symbol: "xmark", label: "关闭五步预览") { dismiss() }
            }
            BoardPreview(position: line.positions[cursor], width: 370)
            HStack {
                Button("上一步") { cursor = max(0, cursor - 1) }.disabled(cursor == 0)
                Spacer(); Text(cursor == 0 ? "当前局面" : "\(cursor). \(line.names[cursor - 1])").font(.system(size: 15, weight: .medium)); Spacer()
                Button("下一步") { cursor = min(line.moves.count, cursor + 1) }.disabled(cursor == line.moves.count)
                    .accessibilityIdentifier("analysis-sequence-next")
            }.buttonStyle(StudioButtonStyle(compact: true))
            Text("第 \(cursor) / \(line.moves.count) 半步 · 搜索深度 \(line.depth) · 预览不改主棋盘").font(.system(size: 11)).foregroundColor(Studio.muted)
            if line.truncated { Text("后续着法未通过合法性检查，已停止预览。").font(.system(size: 11)).foregroundColor(Studio.red) }
            else if line.moves.count < 5 { Text("引擎本轮只提供 \(line.moves.count) 个可回放半步。").font(.system(size: 11)).foregroundColor(Studio.muted) }
        }.padding(25).frame(width: 510).background(Studio.paper)
    }
}
