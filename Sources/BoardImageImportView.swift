import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor struct BoardImageImportView: View {
    @Environment(\.dismiss) private var dismiss
    let onApply: (Position) -> Bool
    @State private var image: CGImage?
    @State private var correctedImage: CGImage?
    @State private var corners = BoardImageCorners()
    @State private var draft = BoardImageDraft()
    @State private var stage = 0
    @State private var selected = 0
    @State private var message = "选择你自己的棋盘图片。图片不会上传，也不会读取其他窗口。"
    @State private var busy = false
    @State private var operation: Task<Void, Never>?
    @State private var token = UUID()
    @State private var recognizer = BoardImageRecognizer()
    @State private var validated: Position?
    @State private var approved = false
    @State private var confirmRow: Int?

    init(onApply: @escaping (Position) -> Bool) { self.onApply = onApply }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("从图片导入局面").font(.system(size: 24, weight: .semibold, design: .serif))
                    Text(["1 · 定位棋盘", "2 · 核对 90 格", "3 · 验证与应用"][stage])
                        .font(.system(size: 12)).foregroundColor(Studio.muted)
                }
                Spacer()
                Button("选择图片") { chooseImage() }.buttonStyle(StudioButtonStyle(compact: true)).disabled(busy)
                    .accessibilityIdentifier("board-image-file")
                Button("粘贴图片") { pasteImage() }.buttonStyle(StudioButtonStyle(compact: true)).disabled(busy)
                    .accessibilityIdentifier("board-image-paste")
                StudioIconButton(symbol: "xmark", label: "关闭图片导入") { cancel(); dismiss() }
            }
            if busy {
                HStack { ProgressView().controlSize(.small); Text("正在本机处理图片…").font(.system(size: 12)); Button("取消") { cancel() } }
            }
            Text(message).font(.system(size: 12)).foregroundColor(Studio.muted).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("board-image-status")
            Group {
                if stage == 0 { locationStage }
                else if stage == 1 { ScrollView { correctionStage.padding(.bottom, 4) } }
                else { reviewStage }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack {
                Text("Apple Vision 中文 OCR · 本机不同实现，非 PWA 专用棋子模型。识别只是建议，空格也需核对。")
                    .font(.system(size: 10)).foregroundColor(Studio.muted)
                Spacer()
                if stage == 1 {
                    Button("重定四角") { stage = 0; validated = nil; approved = false }.disabled(busy)
                        .buttonStyle(StudioButtonStyle(compact: true))
                    Button("验证并预览") { validate() }.buttonStyle(StudioButtonStyle(primary: true))
                        .disabled(busy || draft.unresolvedCount > 0 || draft.sideToMove == nil)
                        .accessibilityIdentifier("board-image-validate")
                } else if stage == 2 {
                    Button("继续校正") { stage = 1; validated = nil; approved = false }.buttonStyle(StudioButtonStyle(compact: true))
                    Button("复制 FEN") { copyFEN() }.buttonStyle(StudioButtonStyle(compact: true)).disabled(!approved)
                        .accessibilityIdentifier("board-image-copy")
                    Button("应用到分析棋盘") { apply() }.buttonStyle(StudioButtonStyle(primary: true)).disabled(!approved)
                        .accessibilityIdentifier("board-image-apply")
                }
            }
        }.padding(24).frame(width: 1060, height: 760).background(Studio.paper).foregroundColor(Studio.ink)
            .preferredColorScheme(.light).onDisappear { cancel() }
            .confirmationDialog("确认这一整行？", isPresented: Binding(get: { confirmRow != nil }, set: { if !$0 { confirmRow = nil } }), titleVisibility: .visible) {
                if let row = confirmRow {
                    Button("第 \(row + 1) 行已核对：保留显示的棋子，其余格为空") {
                        draft.confirmRow(row); selected = min(89, (row + 1) * 9); confirmRow = nil
                    }
                }
                Button("继续逐格检查", role: .cancel) { confirmRow = nil }
            } message: { Text("未识别的棋子也可能显示为空。请对照左侧图片看完这一行；有漏认或颜色错误，请先补正。") }
    }

    private var locationStage: some View {
        HStack(alignment: .top, spacing: 24) {
            if let image {
                BoardImageCornerEditor(image: image, corners: $corners).frame(width: 650, height: 510).disabled(busy)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 48)).foregroundColor(Studio.accent)
                    Text("打开图片，再把四角拖到棋盘边缘").font(.system(size: 16))
                    Text("16 MiB 内 · 最多 2400 万像素 · 单帧图片").font(.system(size: 12)).foregroundColor(Studio.muted)
                }.frame(width: 650, height: 510).background(Studio.white, in: RoundedRectangle(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 18) {
                Text("让 90 个参考点对准棋子中心").font(.system(size: 17, weight: .semibold))
                Text("四角围住完整棋子区域，外侧留半格边距。不要只框住棋盘最外面的交叉线。四角依次为左上、右上、右下、左下。")
                    .font(.system(size: 13)).foregroundColor(Studio.muted).lineSpacing(5)
                Button("四角恢复默认") { corners = BoardImageCorners() }.buttonStyle(StudioButtonStyle(compact: true)).disabled(busy || image == nil)
                Button("整张图就是棋盘") { corners = .full }.buttonStyle(StudioButtonStyle(compact: true)).disabled(busy || image == nil)
                Button("本机识别棋子") { beginRecognition(manual: false) }.buttonStyle(StudioButtonStyle(primary: true)).disabled(busy || image == nil)
                    .accessibilityIdentifier("board-image-recognize")
                Button("直接手工校正") { beginRecognition(manual: true) }.buttonStyle(StudioButtonStyle(compact: true)).disabled(busy || image == nil)
                Text("字体、颜色、遮挡会影响识别。失败后仍可手工补齐，不会假报成功。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var correctionStage: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("对照图片").font(.system(size: 15, weight: .semibold))
                if let correctedImage { imagePreview(correctedImage, width: 310) }
                Text("点右侧任一格，用下方棋子修改。问号表示未确认，不表示空格。")
                    .font(.system(size: 12)).foregroundColor(Studio.muted).fixedSize(horizontal: false, vertical: true)
            }.frame(width: 310)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("校正棋盘").font(.system(size: 15, weight: .semibold)); Spacer()
                    Text("待核对 \(draft.unresolvedCount) 格").font(.system(size: 12)).foregroundColor(Studio.accent)
                }
                cellEditor
                HStack {
                    Text("第 \(selected / 9 + 1) 行，第 \(selected % 9 + 1) 列").font(.system(size: 11))
                    Spacer()
                    Button("核对这一行…") { confirmRow = selected / 9 }.buttonStyle(StudioButtonStyle(compact: true))
                }
            }.frame(width: 360)
            VStack(alignment: .leading, spacing: 13) {
                Text("这一格放什么？").font(.system(size: 15, weight: .semibold))
                ForEach(Side.allCases, id: \.self) { side in
                    Text(side.label).font(.system(size: 12, weight: .semibold)).foregroundColor(side == .red ? Studio.red : Studio.ink)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(43), spacing: 7), count: 4), spacing: 7) {
                        ForEach(PieceKind.allCases, id: \.self) { kind in
                            let piece = Piece(side: side, kind: kind)
                            Button { draft.edit(selected, piece: piece); nextUnconfirmed() } label: {
                                WarmPieceFace(piece: piece, diameter: 36, fontSize: 24).frame(width: 43, height: 43)
                            }.buttonStyle(.plain).accessibilityLabel("设为\(side.label)\(piece.symbol)")
                        }
                    }
                }
                HStack {
                    Button("确认为空格") { draft.edit(selected, piece: nil); nextUnconfirmed() }.buttonStyle(StudioButtonStyle(compact: true))
                    Button("保留此格") { draft.edit(selected, piece: draft.cells[selected].piece); nextUnconfirmed() }
                        .buttonStyle(StudioButtonStyle(compact: true))
                }
                if !draft.cells[selected].observedText.isEmpty {
                    Text("识别原字：\(draft.cells[selected].observedText) · \(Int(draft.cells[selected].confidence * 100))% 文字置信度")
                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                }
                Divider()
                Toggle("图片中红方在下方", isOn: $draft.redAtBottom).font(.system(size: 12))
                Text("轮到哪方走？").font(.system(size: 12, weight: .semibold))
                Picker("行棋方", selection: $draft.sideToMove) {
                    Text("请选择").tag(Optional<Side>.none)
                    Text("红方先走").tag(Optional(Side.red))
                    Text("黑方先走").tag(Optional(Side.black))
                }.labelsHidden().accessibilityIdentifier("board-image-turn")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cellEditor: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 3), count: 9), spacing: 3) {
            ForEach(0..<90, id: \.self) { index in
                let cell = draft.cells[index]
                Button { selected = index } label: {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 5).fill(index == selected ? Studio.accent.opacity(0.18) : Studio.white)
                        if let piece = cell.piece {
                            WarmPieceFace(piece: piece, diameter: 30, fontSize: 21).frame(width: 36, height: 36)
                        } else { Text(cell.confirmed ? "·" : "?").font(.system(size: 16)).frame(width: 36, height: 36).foregroundColor(Studio.muted) }
                        Circle().fill(cell.confirmed ? Studio.success : Studio.gold).frame(width: 5, height: 5).padding(2)
                    }.frame(width: 36, height: 36).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(index == selected ? Studio.accent : .clear, lineWidth: 2))
                }.buttonStyle(.plain)
                    .accessibilityLabel("第\(index / 9 + 1)行第\(index % 9 + 1)列，\(cell.piece.map { $0.side.label + $0.symbol } ?? "未显示棋子")，\(cell.confirmed ? "已确认" : "待核对")")
            }
        }.padding(5).background(Studio.cream, in: RoundedRectangle(cornerRadius: 10))
    }

    private var reviewStage: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text("原图对照").font(.system(size: 15, weight: .semibold))
                if let correctedImage { imagePreview(correctedImage, width: 330) }
            }
            if let validated {
                VStack(alignment: .leading, spacing: 10) {
                    Text("合法局面预览 · \(validated.sideToMove.label)先走").font(.system(size: 15, weight: .semibold))
                    BoardPreview(position: validated, width: 330)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("最后核对一次").font(.system(size: 18, weight: .semibold))
                    Text("右侧预览统一红方在下。请检查棋子颜色、漏子、朝向与行棋方。合法性通过不代表识别完全正确。")
                        .font(.system(size: 13)).foregroundColor(Studio.muted).lineSpacing(4)
                    Toggle("我已核对 90 格、方向与行棋方", isOn: $approved).font(.system(size: 13))
                        .accessibilityIdentifier("board-image-approve")
                    Text(validated.fen).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    Text("只导入当前局面，不推测此前着序。应用前仍会经过现有分析棋局的替换保护。")
                        .font(.system(size: 11)).foregroundColor(Studio.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func imagePreview(_ image: CGImage, width: CGFloat) -> some View {
        Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
            .frame(width: width, height: width * 10 / 9).background(Studio.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "仅打开你选择的图片，在本机识别，不上传。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { install(try BoardImageLoader.read(url)) } catch { message = error.localizedDescription }
    }
    private func pasteImage() {
        let board = NSPasteboard.general
        guard let data = board.data(forType: .png) ?? board.data(forType: .tiff) else { message = "剪贴板中没有 PNG 或 TIFF 图片。"; return }
        do { install(try BoardImageLoader.decode(data)) } catch { message = error.localizedDescription }
    }
    private func install(_ value: CGImage) {
        cancel(); image = value; correctedImage = nil; corners = BoardImageCorners(); draft = BoardImageDraft()
        stage = 0; validated = nil; approved = false
        message = "图片已载入。拖动四角，让参考点对准九列十行的棋子中心。"
    }
    private func beginRecognition(manual: Bool) {
        guard let image else { return }
        do { try corners.validate() } catch { message = error.localizedDescription; return }
        cancel(); busy = true; validated = nil; approved = false
        let current = UUID(); token = current; let selectedCorners = corners
        operation = Task {
            do {
                if manual {
                    let corrected = try await recognizer.corrected(image, corners: selectedCorners)
                    guard !Task.isCancelled, token == current else { return }
                    correctedImage = corrected; draft = BoardImageDraft()
                    message = "手工校正：尚未识别任何棋子。请对照原图补齐并确认 90 格。"
                } else {
                    let result = try await recognizer.recognize(image, corners: selectedCorners)
                    guard !Task.isCancelled, token == current else { return }
                    correctedImage = result.image; draft = result.draft
                    message = result.draft.suggestedCount == 0
                        ? "没有认出可用棋子；现在是手工校正，不是识别成功。请逐行补齐。"
                        : "得到 \(result.draft.suggestedCount) 枚棋子建议；颜色与字体可能误判，全部 90 格仍需核对。"
                }
                selected = 0; stage = 1; busy = false
            } catch {
                guard !Task.isCancelled, token == current else { return }
                busy = false; message = "未完成识别：\(error.localizedDescription) 可点击「直接手工校正」。"
            }
        }
    }
    private func cancel() { token = UUID(); operation?.cancel(); operation = nil; busy = false }
    private func nextUnconfirmed() {
        let indices = Array((selected + 1)..<90) + Array(0..<min(90, selected + 1))
        if let next = indices.first(where: { !draft.cells[$0].confirmed }) { selected = next }
    }
    private func validate() {
        do { validated = try draft.position(); approved = false; stage = 2; message = "已通过棋局合法性检查。请对照原图看完最终预览，再明确应用。" }
        catch { validated = nil; approved = false; message = error.localizedDescription }
    }
    private func checkedPosition() throws -> Position {
        let position = try draft.position()
        guard stage == 2, approved, validated == position else { throw BoardImageImportError.missingReview }
        return position
    }
    private func copyFEN() {
        do { let value = try checkedPosition(); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value.fen, forType: .string); message = "已复制当前 FEN，不包含历史着序。" }
        catch { message = error.localizedDescription }
    }
    private func apply() {
        do { if onApply(try checkedPosition()) { dismiss() } else { message = "未替换分析棋盘。校正结果保留，请查看原棋局的保存或保护提示。" } }
        catch { message = error.localizedDescription }
    }
}

private struct BoardImageCornerEditor: View {
    let image: CGImage
    @Binding var corners: BoardImageCorners
    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / CGFloat(image.width), geo.size.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            ZStack {
                Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                Path { path in
                    let points = corners.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                    path.addLines(points); path.closeSubpath()
                }.stroke(Studio.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                ForEach(0..<90, id: \.self) { index in
                    let point = corners.point(x: (CGFloat(index % 9) + 0.5) / 9, y: (CGFloat(index / 9) + 0.5) / 10)
                    Circle().fill(Studio.onAccent).frame(width: 4, height: 4).overlay(Circle().stroke(Studio.accent, lineWidth: 1))
                        .position(x: point.x * size.width, y: point.y * size.height).allowsHitTesting(false)
                }
                ForEach(0..<4, id: \.self) { index in
                    let point = corners.points[index]
                    Text(["左上", "右上", "右下", "左下"][index]).font(.system(size: 10, weight: .bold))
                        .foregroundColor(Studio.onAccent).frame(width: 40, height: 32).background(Studio.accent, in: Capsule())
                        .position(x: point.x * size.width, y: point.y * size.height)
                        .gesture(DragGesture(coordinateSpace: .named("board-image-corners")).onChanged { value in
                            corners.set(CGPoint(x: value.location.x / size.width, y: value.location.y / size.height), at: index)
                        }).accessibilityLabel("拖动\(["左上", "右上", "右下", "左下"][index])定位点")
                }
            }.frame(width: size.width, height: size.height).coordinateSpace(name: "board-image-corners")
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Studio.white)
        }
    }
}
