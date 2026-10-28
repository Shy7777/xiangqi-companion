import SwiftUI
import AppKit

private struct AnalysisPanel: View {
    @ObservedObject var model: GameModel
    @ObservedObject var engine: PikafishEngine
    @Binding var viewMode: AnalysisViewMode
    @State private var preview: AnalysisVariation?

    private var currentRows: [EngineLine] {
        model.currentAnalysis
    }

    private func scoreText(_ score: EngineScore, redView: Bool = false) -> String {
        let multiplier = redView && model.position.sideToMove == .black ? -1 : 1
        switch score {
        case .cp(let value):
            return engine.usesNormalizedPawnScore ? String(format: "%+.2f", Double(value * multiplier) / 100) : String(format: "%+d", value * multiplier)
        case .mate(let value):
            let v = value * multiplier
            return v > 0 ? "胜势 · 杀\(abs(v))" : "败势 · 被杀\(abs(v))"
        }
    }

    private var evaluation: String {
        guard let first = currentRows.first else { return "—" }
        switch first.score {
        case .cp(let value):
            let red = value * (model.position.sideToMove == .red ? 1 : -1)
            if abs(red) < 45 { return "局面接近" }
            return red > 0 ? "红方较优" : "黑方较优"
        case .mate(let value):
            let winner: Side = value > 0 ? model.position.sideToMove : model.position.sideToMove.opponent
            return "\(winner.label)有杀棋"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("局面评价").font(.system(size: 12, weight: .medium)).foregroundColor(Palette.muted)
                    Spacer()
                    if engine.isThinking && model.analysisEnabled { ProgressView().controlSize(.small).scaleEffect(0.8) }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(evaluation).font(.system(size: 22, weight: .semibold))
                    Spacer(minLength: 2)
                    if let line = currentRows.first {
                        Text(scoreText(line.score, redView: true)).font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundColor(Palette.red)
                    }
                }
                Text(engine.usesNormalizedPawnScore ? "红方视角 · 标准化分数" : "红方视角 · 引擎分数").font(.system(size: 11)).foregroundColor(Palette.muted)
                    .help("引擎分数用于比较局面，不是个人胜率。")
            }.padding(16).background(Studio.white, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Studio.line, lineWidth: 1))

            HStack {
                Text("候选着法").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.position.sideToMove.label)的候选").font(.system(size: 11)).foregroundColor(Palette.muted)
            }
            Picker("候选显示方式", selection: $viewMode) {
                ForEach(AnalysisViewMode.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("analysis-view-mode")

            if !model.analysisEnabled {
                emptyState("分析已暂停", detail: "可以先自己想一想，准备好后再继续。", symbol: "pause.circle")
            } else if model.terminal {
                emptyState("本地棋局结束", detail: "当前一方没有合法走法，可悔棋或重开。", symbol: "flag.checkered")
            } else if let error = engine.error {
                emptyState("引擎暂不可用", detail: error, symbol: "exclamationmark.circle")
                Button("重新启动引擎") { engine.start(); model.scheduleAnalysis() }
                    .buttonStyle(.bordered)
            } else if currentRows.isEmpty {
                emptyState("正在计算候选", detail: "Pikafish 正在本机分析这张棋盘。", symbol: "sparkle.magnifyingglass")
            } else {
                ForEach(currentRows.prefix(viewMode.count)) { line in
                    if let value = line.pv.first, let move = Move(uci: value),
                       (try? model.position.applying(move: move)) != nil {
                        candidate(line, move: move)
                    }
                }
                if viewMode == .sequence, let first = currentRows.first {
                    Button("逐步看双方应对") { preview = AnalysisVariation(position: model.position, pv: first.pv, depth: first.depth) }
                        .buttonStyle(StudioButtonStyle(primary: true, compact: true)).accessibilityIdentifier("analysis-sequence-open")
                }
            }

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(engine.error == nil ? Studio.success : Palette.red).frame(width: 5, height: 5)
                    Text(engine.error == nil ? "Pikafish · 本地计算" : "请检查引擎").font(.system(size: 11, weight: .medium))
                }
                if let line = currentRows.first {
                    Text("深度 \(line.depth) · 搜索 \(line.timeMS ?? model.milliseconds) ms")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(Palette.muted)
                }
                Text("这里只分析你手动录入的棋盘。")
                    .font(.system(size: 11)).foregroundColor(Palette.muted)
            }
        }.foregroundColor(Palette.ink)
            .sheet(item: $preview) { AnalysisVariationView(line: $0) }
    }

    private func emptyState(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 25)).foregroundColor(Palette.green)
            Text(title).font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Studio.white, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Studio.line, lineWidth: 1))
    }

    private func candidate(_ line: EngineLine, move: Move) -> some View {
        let expectedRevision = model.revision
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text("\(line.rank)").font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundColor(Studio.onAccent)
                    .frame(width: 30, height: 34)
                    .background(Palette.candidate(line.rank), in: RoundedRectangle(cornerRadius: 4))
                Text(model.position.notation(for: move)).font(.system(size: line.rank == 1 ? 19 : 16, weight: .semibold))
                Spacer(minLength: 0)
                Text(scoreText(line.score)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Palette.muted)
            }
            if line.rank == 1 {
                Text(model.reason(for: move)).font(.system(size: 12)).foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("后续路线") {
                Text(model.variation(line.pv)).font(.system(size: 11)).foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.top, 3)
            }.font(.system(size: 11)).tint(Palette.muted)
            Button("录入这步") {
                guard model.revision == expectedRevision, engine.latestRevision == expectedRevision else { return }
                model.play(move)
            }
                .font(.system(size: 11, weight: .medium)).buttonStyle(StudioButtonStyle(compact: true))
                .help("把这个候选着法录入当前棋盘。")
                .accessibilityIdentifier("apply-candidate-\(line.rank)")
        }.padding(14)
            .background(line.rank == 1 ? Studio.surfaceRaised : Studio.white, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.candidate(line.rank).opacity(line.rank == 1 ? 0.55 : 0.28), lineWidth: 1))
    }
}

struct CompanionView: View {
    @ObservedObject var model: GameModel
    @ObservedObject var engine: PikafishEngine
    @State private var showBoardImageImport = false
    @State private var analysisViewMode = AnalysisViewMode.three
    @State private var historyRule: HistoryRuleStatus?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "square.grid.3x3").font(.system(size: 20, weight: .medium)).foregroundColor(Studio.cyan)
                    .frame(width: 40, height: 40).background(Studio.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isLocalTwoPlayer ? "本机双人" : "分析棋盘").font(.system(size: 22, weight: .semibold, design: .serif))
                }
                Spacer()
                Menu {
                    Button("本机棋谱与历史") { model.openRecordLibrary() }
                    Button("导入棋谱文件") { model.importRecordUI() }
                    Button("粘贴棋谱或 PWA 局面") { model.importRecordClipboardUI() }
                    Button("从图片导入局面") { model.pauseClock(); showBoardImageImport = true }
                    Button("保存当前棋谱") { _ = model.saveRecordToLibrary() }
                    Button("导出棋谱") { model.exportRecordUI() }
                    Divider()
                    if model.isLocalTwoPlayer { Button("切回引擎分析") { model.startManualAnalysis() } }
                    else { Button("从当前局面双人下棋") { model.startLocalTwoPlayer() } }
                } label: { Label("棋谱", systemImage: "doc.text").font(.system(size: 12)) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityIdentifier("manual-record-menu")
                Button { model.openPlayUtilities() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless).help("棋钟、声音、配色与棋盘图片")
                    .accessibilityLabel("棋盘工具").accessibilityIdentifier("play-utilities")
                Button { model.isPinned.toggle(); WindowPlacement.pin(model.isPinned) } label: {
                    Image(systemName: model.isPinned ? "pin.fill" : "pin")
                }.buttonStyle(.borderless).help(model.isPinned ? "取消置顶" : "窗口置顶")
                Button { WindowPlacement.placeRight() } label: { Image(systemName: "rectangle.righthalf.inset.filled") }
                    .buttonStyle(.borderless).help("放到屏幕右侧")
            }.padding(.horizontal, 23).padding(.vertical, 12)
            Rectangle().fill(Studio.line).frame(height: 1)
            GeometryReader { workspace in
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(model.position.sideToMove == .red ? Palette.red : Palette.ink).frame(width: 7, height: 7)
                            Text(model.stateLabel).font(.system(size: 12, weight: .medium))
                        }
                        Spacer()
                        Text("第 \(model.cursor) 步").font(.system(size: 11, design: .monospaced)).foregroundColor(Palette.muted)
                    }
                    GeometryReader { boardArea in
                        let width = max(0, min(boardArea.size.width, boardArea.size.height * BoardView.Layout.aspectRatio))
                        BoardView(position: model.position, flipped: model.flipped, selected: model.selected,
                                  targets: model.legalTargets, lastMove: model.lastMove,
                                  arrows: Array(model.recommendationArrows.prefix(analysisViewMode.count)), appearance: model.playPreferences.appearance, onTap: model.tap)
                            .frame(width: width, height: width / BoardView.Layout.aspectRatio)
                            .position(x: boardArea.size.width / 2, y: boardArea.size.height / 2)
                    }
                    HStack(spacing: 8) {
                        Button { model.navigate(to: model.cursor - 1) } label: { Label("悔棋", systemImage: "arrow.uturn.backward") }
                            .disabled(model.cursor == 0).keyboardShortcut("z", modifiers: .command)
                        Button { model.navigate(to: model.cursor + 1) } label: { Image(systemName: "arrow.uturn.forward") }
                            .disabled(model.isAtEnd).help("前进一步").keyboardShortcut("z", modifiers: [.command,.shift])
                        Spacer(minLength: 0)
                        Button("翻转") { model.flip() }
                        Button("摆局") { model.showSetup = true }.accessibilityIdentifier("setup-board")
                        Button("重开") { model.showNewGame = true }
                    }.buttonStyle(StudioButtonStyle(compact: true)).controlSize(.small)
                    Text(model.message).font(.system(size: 11)).foregroundColor(Palette.muted)
                        .lineLimit(2).frame(maxWidth: .infinity, minHeight: 26, alignment: .topLeading)
                    HistoryRuleBanner(status: historyRule)
                    history
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    if model.isLocalTwoPlayer { localTwoPlayerPanel }
                    else {
                        AnalysisPanel(model: model, engine: engine, viewMode: $analysisViewMode)
                            .frame(maxWidth: .infinity, minHeight: max(0, workspace.size.height - 40), alignment: .top)
                    }
                }.frame(width: 268)
            }.padding(20).frame(width: workspace.size.width, height: workspace.size.height)
            }
            Rectangle().fill(Studio.line).frame(height: 1)
            HStack(spacing: 13) {
                if model.isLocalTwoPlayer {
                    Label("双方交替落子 · 提示关闭", systemImage: "person.2").font(.system(size: 11)).foregroundColor(Palette.muted)
                    Spacer()
                    Button("切回分析") { model.startManualAnalysis() }.buttonStyle(StudioButtonStyle(compact: true))
                        .accessibilityIdentifier("local-game-to-analysis")
                } else {
                Button { model.toggleAnalysis() } label: {
                    Label(model.analysisEnabled ? "暂停分析" : "继续分析", systemImage: model.analysisEnabled ? "pause.fill" : "play.fill")
                }.buttonStyle(.borderless).font(.system(size: 11)).accessibilityIdentifier("toggle-analysis")
                Button { model.toggleArrows() } label: {
                    Label(model.showArrows ? "隐藏箭头" : "显示箭头", systemImage: "arrow.up.right")
                }.buttonStyle(.borderless).font(.system(size: 11))
                    .help("只控制棋盘上的 Top 1、2、3 箭头，不影响候选分析。")
                    .accessibilityIdentifier("toggle-arrows")
                Spacer()
                Text("计算时间").font(.system(size: 11)).foregroundColor(Palette.muted)
                Picker("计算时间", selection: Binding(get: { model.milliseconds }, set: model.setBudget)) {
                    Text("快 · 0.25 秒").tag(250)
                    Text("标准 · 0.35 秒").tag(350)
                    Text("深入 · 1 秒").tag(1000)
                }.labelsHidden().frame(width: 140).controlSize(.small)
                Button("复制局面") { model.copyFEN() }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }.padding(.horizontal, 22).padding(.vertical, 12).background(Studio.rail)
        }
        .foregroundColor(Palette.ink).background(Palette.paper).preferredColorScheme(.light)
        .frame(minWidth: 735, idealWidth: 820, maxHeight: .infinity)
        .sheet(isPresented: $model.showSetup) { SetupView(model: model) }
        .sheet(isPresented: $model.showRecordLibrary) { ManualRecordBrowser(model: model) }
        .sheet(isPresented: $model.showPlayUtilities) { PlayUtilitiesView(model: model) }
        .sheet(isPresented: $showBoardImageImport) {
            BoardImageImportView(onApply: { model.analyzePosition($0) })
        }
        .alert("开始新棋局？", isPresented: $model.showNewGame) {
            Button("取消", role: .cancel) { }
            Button("重开") { model.newGame() }
        } message: { Text("当前棋谱会保存在本机历史目录。") }
        .onAppear { model.start(); WindowPlacement.install() }
        .onChange(of: model.revision) { _ in historyRule = GameHistoryRules.inspect(positions: model.positions, moves: model.moves, cursor: model.cursor) }
        .onDisappear { model.pauseClock() }
        .onChange(of: model.showSetup) { if $0 { model.pauseClock() } }
        .onChange(of: model.showRecordLibrary) { if $0 { model.pauseClock() } }
        .onChange(of: model.showNewGame) { if $0 { model.pauseClock() } }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in model.tickClock() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in model.pauseClock() }
    }

    private var localTwoPlayerPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "person.2").font(.system(size: 32)).foregroundColor(Studio.accent)
            Text(model.stateLabel).font(.system(size: 25, weight: .semibold, design: .serif))
            Text("在同一台电脑上轮流走棋。").font(.system(size: 13)).foregroundColor(Studio.muted)
            if model.playPreferences.clockEnabled {
                LocalChessClockView(model: model)
            } else {
                Button("添加棋钟") { model.openPlayUtilities() }.buttonStyle(StudioButtonStyle(compact: true))
                    .accessibilityIdentifier("add-chess-clock")
            }
            Divider()
            Label("引擎与候选已关闭", systemImage: "eye.slash").font(.system(size: 12)).foregroundColor(Studio.muted)
            Button("保存这盘棋") { _ = model.saveRecordToLibrary() }.buttonStyle(StudioButtonStyle(primary: true))
            Button("打开棋谱") { model.openRecordLibrary() }.buttonStyle(StudioButtonStyle(compact: true))
            DisclosureGroup("棋规范围") {
                Text("检查合法走子、将军和无合法走法；长将、长捉等比赛争议仍需裁判规则核定。").font(.system(size: 11)).foregroundColor(Studio.muted).padding(.top, 8)
            }.font(.system(size: 11))
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Studio.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本地棋谱").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.muted)
                Spacer()
                if !model.isAtEnd {
                    Button("回到最新") { model.navigate(to: model.moves.count) }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if model.moveNames.isEmpty {
                            Text("点击棋子，再点击目标位置。双方走子都由你录入。")
                                .font(.system(size: 11)).foregroundColor(Palette.muted).padding(.vertical, 7)
                        }
                        ForEach(Array(model.moveNames.enumerated()), id: \.offset) { index, name in
                            Button { model.navigate(to: index + 1) } label: {
                                Text("\(index + 1). \(name)").font(.system(size: 11))
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                    .foregroundColor(model.cursor == index + 1 ? Studio.cyan : Studio.ink)
                                    .background(model.cursor == index + 1 ? Palette.green.opacity(0.12) : Studio.white, in: RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(model.cursor == index + 1 ? Studio.cyan.opacity(0.45) : Studio.line, lineWidth: 0.8))
                            }.buttonStyle(.plain).id(index + 1)
                        }
                    }
                }.onChange(of: model.cursor) { value in proxy.scrollTo(value, anchor: .trailing) }
            }.frame(height: 32)
        }
    }
}

private struct SetupView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Position
    @State private var chosen: Piece? = Piece(side: .red, kind: .rook)
    @State private var fenText = ""
    @State private var error = ""

    init(model: GameModel) {
        self.model = model
        _draft = State(initialValue: model.position)
        _fenText = State(initialValue: model.position.fen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("摆出当前局面").font(.system(size: 20, weight: .semibold))
                    Text("选右侧棋子，再点棋盘；选择橡皮可移除棋子。")
                        .font(.system(size: 12)).foregroundColor(Palette.muted)
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 20) {
                BoardView(position: draft, flipped: model.flipped) { square in
                    draft[square] = chosen; error = ""
                }.frame(width: 370)
                VStack(alignment: .leading, spacing: 12) {
                    Text("要放置的棋子").font(.system(size: 12, weight: .medium))
                    ForEach([Side.red, Side.black], id: \.self) { side in
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(38)), count: 4), spacing: 8) {
                            ForEach([PieceKind.king, .advisor, .elephant, .horse, .rook, .cannon, .pawn], id: \.self) { kind in
                                let piece = Piece(side: side, kind: kind)
                                Button { chosen = piece } label: {
                                    Text(piece.symbol).font(.system(size: 21, weight: .medium, design: .serif))
                                        .foregroundColor(side == .red ? Palette.red : Palette.ink)
                                        .frame(width: 34, height: 34)
                                        .background(chosen == piece ? Palette.green.opacity(0.15) : Studio.surfaceRaised, in: Circle())
                                        .overlay(Circle().stroke(chosen == piece ? Palette.green : Studio.line))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Button { chosen = nil } label: { Label("橡皮 / 移除棋子", systemImage: "eraser") }
                        .buttonStyle(.bordered).tint(chosen == nil ? Palette.green : nil)
                    Divider().padding(.vertical, 4)
                    Text("轮到哪方走？").font(.system(size: 12, weight: .medium))
                    Picker("行棋方", selection: $draft.sideToMove) {
                        Text("红方").tag(Side.red)
                        Text("黑方").tag(Side.black)
                    }.pickerStyle(.segmented).labelsHidden()
                    Button("恢复初始摆法") { draft = .initial; error = "" }
                    Button("清空棋盘") { draft = Position(board: Array(repeating: nil, count: 90), sideToMove: .red); error = "" }
                    Text("局面会先检查规则，再交给引擎。")
                        .font(.system(size: 11)).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 180)
            }
            DisclosureGroup("粘贴局面代码（FEN）") {
                HStack {
                    TextField("局面代码", text: $fenText).font(.system(size: 11, design: .monospaced)).textFieldStyle(.roundedBorder)
                    Button("导入") {
                        do { draft = try Position(fen: fenText); error = "" }
                        catch { self.error = "无法导入：\(error.localizedDescription)" }
                    }
                }.padding(.top, 7)
            }.font(.system(size: 12))
            HStack {
                Text(error).font(.system(size: 11)).foregroundColor(Palette.red).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("用这个局面分析") {
                    do {
                        try draft.validate()
                        if model.replace(with: draft) { dismiss() } else { self.error = model.message }
                    }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(StudioButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 620).background(Palette.paper).foregroundColor(Palette.ink).preferredColorScheme(.light)
    }
}
