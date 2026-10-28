import SwiftUI
import AppKit

/// Re-renders only the chess position, never captures a window or screen.
@MainActor enum BoardPNGExporter {
    static func png(position: Position, flipped: Bool, appearance: BoardAppearance = .init(), width: Int = 1_098) throws -> Data {
        try position.validate()
        guard (256...2_048).contains(width) else { throw PlayUtilityError.invalid("导出宽度需在 256–2,048 像素内。") }
        let content = PureBoardImage(position: position, flipped: flipped)
            .environment(\.boardAppearance, appearance).environment(\.colorScheme, .light)
            .frame(width: CGFloat(width), height: CGFloat(width) / WarmBoardLayout.aspectRatio)
            .background(Studio.paper)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1; renderer.isOpaque = true
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw PlayUtilityError.invalid("系统未能绘制棋盘图片，请重试。")
        }
        return data
    }
}

private struct PureBoardImage: View {
    let position: Position
    let flipped: Bool
    @Environment(\.boardAppearance) private var appearance
    var body: some View {
        GeometryReader { geometry in
            let layout = WarmBoardLayout(size: geometry.size)
            ZStack {
                WarmBoardSurface()
                WarmBoardGrid(cell: layout.cell, origin: layout.origin)
                ForEach(0..<90, id: \.self) { index in
                    let square = Square(row: index / 9, col: index % 9)
                    if let piece = position[square] {
                        WarmPieceFace(piece: piece, diameter: layout.pieceDiameter, fontSize: layout.pieceFontSize)
                            .position(layout.point(square, flipped: flipped))
                    }
                }
                ForEach(0..<9, id: \.self) { index in
                    Text(flipped ? String(index + 1) : ["九","八","七","六","五","四","三","二","一"][index])
                        .font(.system(size: layout.coordinateFontSize, weight: .medium, design: .serif))
                        .foregroundColor(BoardSurfaceColors(appearance.board).coordinate)
                        .position(x: layout.origin.x + CGFloat(index) * layout.cell, y: layout.coordinateY)
                }
            }
        }
    }
}

struct LocalChessClockView: View {
    @ObservedObject var model: GameModel
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                clock(.red); clock(.black)
            }
            HStack(spacing: 10) {
                if model.chessClock.runningSide != nil {
                    Button("暂停") { model.pauseClock() }.accessibilityIdentifier("clock-pause")
                } else {
                    Button("开始计时") { model.startClock() }
                        .disabled(!model.isAtEnd || model.terminal || model.chessClock.timedOut != nil)
                        .accessibilityIdentifier("clock-start")
                }
                Button("重置") { model.resetClock() }.accessibilityIdentifier("clock-reset")
                Spacer(minLength: 0)
                Text(model.chessClock.timedOut != nil ? "超时" : model.chessClock.runningSide == nil ? "已暂停" : "计时中")
                    .font(.system(size: 10)).foregroundColor(Studio.muted)
            }.buttonStyle(StudioButtonStyle(compact: true))
        }.accessibilityElement(children: .contain)
    }
    private func clock(_ side: Side) -> some View {
        let active = model.chessClock.runningSide == side
        let expired = model.chessClock.timedOut == side
        let low = model.chessClock.isLow(side)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(side.label).font(.system(size: 11, weight: .medium))
                Spacer()
                if active { Image(systemName: "timer").font(.system(size: 11)) }
                if expired { Image(systemName: "flag.fill").font(.system(size: 11)) }
            }
            Text(LocalChessClock.text(model.chessClock.remaining(side)))
                .font(.system(size: 22, weight: .medium, design: .monospaced)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            if low { Text("不足 1 分钟").font(.system(size: 10)).foregroundColor(Studio.accent) }
        }.foregroundColor(side == .red ? Studio.red : Studio.ink)
            .padding(11).frame(maxWidth: .infinity)
            .background(active ? Studio.surfaceRaised : Studio.cream, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(expired ? Studio.red : active || low ? Studio.accent : Studio.line, lineWidth: active || expired ? 1.5 : 0.8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(side.label)剩余时间")
            .accessibilityValue(LocalChessClock.text(model.chessClock.remaining(side)) + (expired ? "，超时" : active ? "，计时中" : "，暂停") + (low ? "，不足一分钟" : ""))
            .accessibilityIdentifier("clock-\(side.rawValue)")
    }
}

struct PlayUtilitiesView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Text("棋盘工具").font(.system(size: 23, weight: .semibold, design: .serif))
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(StudioButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 20) {
                PureBoardImage(position: model.position, flipped: model.flipped)
                    .environment(\.boardAppearance, model.playPreferences.appearance)
                    .frame(width: 160, height: 160 / WarmBoardLayout.aspectRatio)
                VStack(alignment: .leading, spacing: 15) {
                    Picker("棋盘", selection: Binding(get: { model.playPreferences.appearance.board }, set: model.setBoardColorway)) {
                        ForEach(BoardColorway.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("board-colorway")
                    Picker("棋子", selection: Binding(get: { model.playPreferences.appearance.pieces }, set: model.setPieceColorway)) {
                        ForEach(PieceColorway.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("piece-colorway")
                    Button("导出棋盘 PNG") { model.exportBoardPNG() }
                        .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("export-board-png")
                }
            }
            Divider()
            HStack {
                Toggle("落子音", isOn: Binding(get: { model.playPreferences.soundEnabled }, set: model.setMoveSound))
                    .accessibilityIdentifier("move-sound-toggle")
                Button("试听") { model.previewSound(.move) }.buttonStyle(StudioButtonStyle(compact: true))
                    .accessibilityLabel("试听落子音").accessibilityIdentifier("preview-move-sound")
                Spacer()
                Toggle("吃子音", isOn: Binding(get: { model.playPreferences.captureSoundEnabled }, set: model.setCaptureSound))
                    .accessibilityIdentifier("capture-sound-toggle")
                Button("试听") { model.previewSound(.capture) }.buttonStyle(StudioButtonStyle(compact: true))
                    .accessibilityLabel("试听吃子音").accessibilityIdentifier("preview-capture-sound")
            }
            HStack(spacing: 12) {
                Text("音量").font(.system(size: 12))
                Slider(value: Binding(get: { model.playPreferences.soundVolume }, set: model.setSoundVolume), in: 0...1)
                    .accessibilityLabel("音效音量").accessibilityIdentifier("sound-volume")
                Text("\(Int((model.playPreferences.soundVolume * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced)).frame(width: 38, alignment: .trailing)
            }
            Divider()
            Toggle("双人棋钟", isOn: Binding(get: { model.playPreferences.clockEnabled }, set: model.setClockEnabled))
                .accessibilityIdentifier("chess-clock-toggle")
            if model.playPreferences.clockEnabled {
                HStack {
                    Text("每方用时"); Spacer()
                    TextField("分钟", value: Binding(get: { model.playPreferences.clockMinutes }, set: model.setClockMinutes), format: .number)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 56)
                        .accessibilityLabel("每方分钟数，1 至 120").accessibilityIdentifier("clock-duration")
                    Text("分钟")
                    Stepper("每方用时", value: Binding(get: { model.playPreferences.clockMinutes }, set: model.setClockMinutes), in: 1...120)
                        .labelsHidden().fixedSize()
                }.font(.system(size: 12))
                HStack {
                    Text("每步加秒"); Spacer()
                    TextField("秒", value: Binding(get: { model.playPreferences.clockIncrementSeconds }, set: model.setClockIncrement), format: .number)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 56)
                        .accessibilityLabel("每步加秒，0 至 60").accessibilityIdentifier("clock-increment")
                    Text("秒")
                    Stepper("每步加秒", value: Binding(get: { model.playPreferences.clockIncrementSeconds }, set: model.setClockIncrement), in: 0...60)
                        .labelsHidden().fixedSize()
                }.font(.system(size: 12))
                Text("1–120 分钟 · 每步 0–60 秒 · 更改会重置双方用时")
                    .font(.system(size: 10)).foregroundColor(Studio.muted)
                Text(model.isLocalTwoPlayer ? "关闭工具后，在棋盘旁开始计时。" : "仅本机双人模式启用；分析棋盘不计时。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted)
            }
            DisclosureGroup("使用说明") {
                Text("默认暖枫木与象牙白。图片由局面重新绘制，不读取屏幕。两类音效使用系统短音，默认均关闭；试听不改变开关。计时中的合法落子给刚走方加秒，默认加 0 秒；本机安全上限每步 60 秒、剩余累计 24 小时。暂停、回看、非法走子和超时不加秒。不足一分钟只作文字提醒。回看、切模式、离开棋盘或切换应用会暂停，不自动恢复；重启只恢复设置，不恢复旧钟。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4).padding(.top, 7)
            }.font(.system(size: 11))
            if let notice = model.utilitiesNotice { Text(notice).font(.system(size: 11)).foregroundColor(Studio.red).fixedSize(horizontal: false, vertical: true) }
        }.padding(24).frame(width: 485).foregroundColor(Studio.ink).background(Studio.paper).preferredColorScheme(.light)
    }
}
