import SwiftUI

extension LearningCenterView {
    func sparringWorkspace(width: CGFloat) -> some View {
        let inspectorWidth: CGFloat = width >= 950 ? 320 : width >= 790 ? 290 : 252
        return VStack(spacing: 0) {
            sparringToolbar
            HStack(spacing: 0) {
                sparringBoardStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Studio.line.opacity(0.6)).frame(width: 1)
                sparringInspector.frame(width: inspectorWidth)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            sparringActionBar
        }.background(Studio.paper)
    }

    private var sparringToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("实战练习").font(.system(size: 20, weight: .semibold))
                if let game = model.game {
                    Text("本盘你执\(game.player.label) · \(sparringLevelName(game.level))")
                        .font(.system(size: 11)).foregroundColor(Studio.muted)
                } else {
                    Text("你来判断，引擎来应招。").font(.system(size: 11)).foregroundColor(Studio.muted)
                }
            }
            Spacer(minLength: 8)
            StudioIconButton(symbol: "clock.arrow.circlepath", label: "打开全部对局历史") { showGameHistory = true }
                .accessibilityIdentifier("sparring-history")
            if model.game != nil {
                Button { sparringRequestNewGame() } label: { Label("新开一盘", systemImage: "plus") }
                    .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("start-sparring")
            }
        }.padding(.horizontal, 23).padding(.vertical, 15)
            .overlay(alignment: .bottom) { Rectangle().fill(Studio.line.opacity(0.45)).frame(height: 1) }
    }

    private var sparringBoardStage: some View {
        let p = model.game == nil ? Position.initial : model.displayedGamePosition
        return VStack(spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(p.sideToMove == .red ? Studio.red : Studio.ink).frame(width: 7, height: 7)
                Text(sparringBoardTitle).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                StudioIconButton(symbol: "arrow.triangle.2.circlepath", label: "翻转棋盘") { model.flipped.toggle() }
                    .accessibilityIdentifier("sparring-flip")
            }.padding(.horizontal, 5)
            GeometryReader { geo in
                let boardWidth = max(0, min(geo.size.width, geo.size.height * BoardView.Layout.aspectRatio))
                BoardView(position: p, flipped: model.flipped,
                          selected: model.gameReviewCursor == nil ? model.selected : nil,
                          targets: model.gameReviewCursor == nil ? model.targets : [],
                          lastMove: sparringLastMove, arrows: sparringArrows,
                          onTap: { square in if model.game != nil { model.tap(square) } })
                    .frame(width: boardWidth, height: boardWidth / BoardView.Layout.aspectRatio)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            HStack(spacing: 6) {
                Image(systemName: model.gameReviewCursor == nil ? "cursorarrow" : "clock")
                Text(sparringBoardCaption).lineLimit(2)
            }.font(.system(size: 10)).foregroundColor(Studio.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 5)
            if let game = model.game {
                HistoryRuleBanner(status: GameHistoryRules.inspect(positions: model.gamePositions,
                    moves: game.moves.compactMap(Move.init(uci:)), cursor: model.gameReviewCursor ?? game.moves.count))
            }
        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 15)
    }

    private var sparringBoardTitle: String {
        guard let game = model.game else { return "初始棋盘预览" }
        if let index = model.gameReviewCursor { return index == 0 ? "复盘 · 初始局面" : "复盘 · 第 \(index) 手之后" }
        if game.result != nil { return "本盘已结束" }
        return "\(model.position.sideToMove.label)行棋 · 第 \(game.moves.count + 1) 手"
    }
    private var sparringBoardCaption: String {
        guard let game = model.game else { return "设置颜色和搜索档位后，再开始落子。" }
        if model.gameReviewCursor != nil { return "正在查看历史棋面；这里不会改变实际对局。" }
        if game.result != nil { return "对局已经保存，可以逐步回看。" }
        if model.busy { return "棋盘保留当前局面，计算可随时暂停。" }
        return model.position.sideToMove == game.player ? "先选自己的棋子，再点合法落点。" : "轮到引擎，可继续应招或先复盘。"
    }

    private var sparringInspector: some View {
        VStack(spacing: 0) {
            Picker("对局检查栏", selection: $inspectorTab) {
                Text("教练").tag(0); Text("棋谱").tag(1); Text("回顾").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.game == nil { sparringWelcome }
                    else if inspectorTab == 1 { sparringMoveList }
                    else if inspectorTab == 2 { sparringReviewList }
                    else {
                        sparringFeedback
                        sparringAnalysis
                    }
                }.padding(.horizontal, 17).padding(.top, 3).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Studio.white.opacity(0.65))
    }

    private var sparringWelcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("选择起局，检验你的计划").font(.system(size: 21, weight: .medium)).lineSpacing(5)
            sparringWelcomeRow("cursorarrow", "先自己走", "没有自动落子，也不默认展示答案。")
            sparringWelcomeRow("bolt.horizontal", "本地引擎应招", "走后核对，再让皮卡鱼回应。")
            sparringWelcomeRow("arrow.counterclockwise", "回到关键一步", "随时悔棋、回看，或把这步带进重练。")
            Text("搜索档位不对应真人段位。即使使用短时搜索，引擎也可能很强。")
                .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
        }.padding(.vertical, 12)
    }
    private func sparringWelcomeRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol).foregroundColor(Studio.green).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(3)
            }
        }
    }

    private var sparringFeedback: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                if model.busy { ProgressView().controlSize(.small) }
                else { Image(systemName: "lightbulb").foregroundColor(Studio.gold) }
                Text(model.busy ? "本地引擎正在计算" : model.feedbackTitle).font(.system(size: 15, weight: .semibold))
            }
            Text(model.feedbackBody).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(4)
                .lineLimit(showFullFeedback ? nil : 5).accessibilityIdentifier("sparring-feedback")
            if model.feedbackBody.count > 100 {
                Button(showFullFeedback ? "收起说明" : "展开完整说明") { showFullFeedback.toggle() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Studio.green)
            }
            if model.busy {
                Text(coach.status).font(.system(size: 10)).foregroundColor(Studio.muted).lineLimit(3)
                Button("暂停本次计算") { model.stopCalculation() }.buttonStyle(StudioButtonStyle(compact: true))
            }
        }.studioSurface(15)
    }

    private var sparringAnalysis: some View {
        let p = model.displayedGamePosition
        return VStack(alignment: .leading, spacing: 12) {
            Text("当前局面的候选").font(.system(size: 13, weight: .semibold))
            if sparringMayAnalyze {
                Button { model.requestGameHint() } label: { Label("分析当前局面 / 求助", systemImage: "magnifyingglass") }
                    .buttonStyle(StudioButtonStyle(compact: true)).disabled(model.busy || p.legalMoves().isEmpty)
                    .accessibilityIdentifier("sparring-analyze")
            } else {
                Text("轮到引擎时先等待应招；回看历史局面也可以单独分析。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(3)
            }
            if !model.gameAnalysis.isEmpty {
                Text("\(p.sideToMove.label)视角 · 正分有利于该方")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(Studio.muted)
                ForEach(model.gameAnalysis) { row in sparringCandidate(row, position: p) }
                Button("隐藏候选与箭头") {
                    model.cancelOperation(); model.gameAnalysis = []; model.gameHints = false
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Studio.green)
                    .accessibilityIdentifier("sparring-clear-analysis")
            } else {
                Text(p.legalMoves().isEmpty ? "当前一方已无合法着，不再给候选。" : "默认隐藏答案。需要帮助时，再展开真实引擎候选。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
            }
            Text("限时评价不是胜率；本盘求助不计入课程无提示通过率。")
                .font(.system(size: 10)).foregroundColor(Studio.muted).lineSpacing(3)
        }
    }
    @ViewBuilder private func sparringCandidate(_ row: EngineLine, position: Position) -> some View {
        if let text = row.pv.first, let move = Move(uci: text), (try? position.applying(move: move)) != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Text("\(row.rank)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Studio.onAccent).frame(width: 23, height: 23)
                        .background(Palette.candidate(row.rank), in: RoundedRectangle(cornerRadius: 5))
                    Text(position.notation(for: move)).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                }
                Text(sparringScore(row.score)).font(.system(size: 17, weight: .medium, design: .rounded)).foregroundColor(sparringScoreColor(row.score))
                Text(variation(row.pv, from: position)).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                HStack {
                    Text("深度 \(row.depth)")
                    Spacer()
                    if let time = row.timeMS { Text(String(format: "%.2f 秒", Double(time) / 1000)) }
                }.font(.system(size: 9, design: .monospaced)).foregroundColor(Studio.muted)
            }.studioSurface(13)
        }
    }
    private var sparringMayAnalyze: Bool {
        guard let game = model.game else { return false }
        return model.gameReviewCursor != nil || game.result != nil || model.displayedGamePosition.sideToMove == game.player
    }
    private func sparringScore(_ score: EngineScore) -> String {
        switch score {
        case .cp(let value):
            return coach.usesNormalizedPawnScore ? String(format: "%+.2f 兵分", Double(value) / 100) : "\(value >= 0 ? "+" : "")\(value) 原始引擎分"
        case .mate(let value):
            return value > 0 ? "找到杀棋 · \(value)" : value < 0 ? "被杀路线 · \(value.magnitude)" : "杀棋结论"
        }
    }
    private func sparringScoreColor(_ score: EngineScore) -> Color {
        switch score {
        case .cp(let value): return value < 0 ? Studio.red : value > 0 ? Studio.green : Studio.muted
        case .mate(let value): return value > 0 ? Studio.green : Studio.red
        }
    }

    private var sparringMoveList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("整盘棋谱").font(.system(size: 16, weight: .semibold))
            Text("点击某一手，棋盘停在走后局面。实际对局仍然保留。")
                .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(3)
            Button { model.reviewGame(at: 0) } label: {
                HStack { Text("初始局面"); Spacer(); Image(systemName: "arrow.up.left") }
            }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("sparring-review-initial")
            if let game = model.game {
                if game.moves.isEmpty { Text("尚未落子。").font(.system(size: 12)).foregroundColor(Studio.muted).padding(.vertical, 14) }
                LazyVStack(spacing: 5) {
                    ForEach(Array(game.moves.enumerated()), id: \.offset) { index, text in
                        if let move = Move(uci: text), model.gamePositions.indices.contains(index) {
                            sparringMoveRow(index: index, move: move, position: model.gamePositions[index])
                        }
                    }
                }
            }
        }
    }
    private func sparringMoveRow(index: Int, move: Move, position: Position) -> some View {
        let active = model.gameReviewCursor == index + 1
        return Button { model.reviewGame(at: index + 1) } label: {
            HStack(spacing: 10) {
                Text("\(index + 1)").font(.system(size: 10, design: .monospaced)).frame(width: 23, alignment: .leading)
                Circle().fill(position.sideToMove == .red ? Studio.red : Studio.ink).frame(width: 5, height: 5)
                Text(position.notation(for: move)).font(.system(size: 12, weight: active ? .semibold : .regular))
                Spacer(minLength: 3)
                if active { Image(systemName: "eye").font(.system(size: 11)) }
            }.foregroundColor(active ? Studio.green : Studio.ink).padding(.horizontal, 10).padding(.vertical, 10)
                .background(active ? Studio.green.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("回看第 \(index + 1) 手，\(position.notation(for: move))")
    }

    private var sparringReviewList: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("你的走法回顾").font(.system(size: 16, weight: .semibold))
            Text("评价对应你当时的走法，不是眼前任意棋面的分数。")
                .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(3)
            if let game = model.game, !game.reviews.isEmpty {
                ForEach(game.reviews) { item in
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Text("第 \(item.ply) 手").font(.system(size: 11, weight: .medium))
                            Spacer()
                            StudioTag(text: sparringVerdict(item.verdict), color: item.verdict == "mistake" || item.verdict == "inaccuracy" ? Studio.red : Studio.green)
                        }
                        Text(item.detail).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(4)
                        HStack(spacing: 12) {
                            Button("棋盘定位") { model.reviewGame(at: item.ply - 1) }.buttonStyle(.plain)
                            if item.bestMove != nil {
                                Button("回到这步重练") { model.reviewGameMistake(item) }.buttonStyle(.plain)
                                    .accessibilityIdentifier("sparring-retry-\(item.ply)")
                            }
                        }.font(.system(size: 11, weight: .medium)).foregroundColor(Studio.green)
                    }.studioSurface(14)
                }
            } else {
                Text("走出自己的第一手后，这里会保留真实引擎评语。尚未完成的计算不会被记成失误。")
                    .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5).padding(.vertical, 15)
            }
        }
    }

    private var sparringActionBar: some View {
        HStack(spacing: 10) {
            if let game = model.game {
                if model.gameReviewCursor != nil || game.result != nil {
                    sparringHistoryControls(game)
                    Spacer(minLength: 8)
                    if model.busy {
                        Button("暂停计算") { model.stopCalculation() }.buttonStyle(StudioButtonStyle(compact: true))
                    }
                    if game.result == nil {
                        action("回到对局", symbol: "arrow.uturn.backward", id: "sparring-return-live") { model.returnToGame() }
                    } else {
                        Button("再练一盘") { sparringRequestNewGame() }.buttonStyle(StudioButtonStyle(compact: true))
                    }
                } else {
                    Button("悔棋重走") { model.undoGame() }.buttonStyle(StudioButtonStyle(compact: true))
                        .disabled(game.moves.isEmpty).accessibilityIdentifier("sparring-undo")
                    Button("结束并复盘") { model.finishGame(); inspectorTab = 2 }.buttonStyle(StudioButtonStyle(compact: true))
                        .accessibilityIdentifier("sparring-finish")
                    Spacer(minLength: 8)
                    if model.busy {
                        action("暂停计算", symbol: "pause.fill", id: "sparring-stop") { model.stopCalculation() }
                    } else if model.position.sideToMove != game.player {
                        action("继续引擎应招", symbol: "play.fill", id: "sparring-respond") { model.respondInGame() }
                    } else {
                        Label("轮到你来判断", systemImage: "cursorarrow").font(.system(size: 12, weight: .medium)).foregroundColor(Studio.green)
                    }
                }
            } else {
                if let saved = store.data.games.filter({ $0.result == nil }).max(by: { $0.started < $1.started }) {
                    Text("上次已走 \(saved.moves.count) 手，棋局已保存。")
                        .font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(2)
                    Spacer(minLength: 8)
                    Button("新开一盘") { showGameSetup = true }.buttonStyle(StudioButtonStyle(compact: true))
                    action("继续上次对局", symbol: "play.fill", id: "sparring-resume-latest") { model.resumeGame(saved); inspectorTab = 0 }
                } else {
                    Text("独立落子 · 本地应招 · 随时复盘").font(.system(size: 11)).foregroundColor(Studio.muted)
                    Spacer(minLength: 8)
                    action("设置并开局", symbol: "play.fill", id: "sparring-setup-primary") { showGameSetup = true }
                }
            }
        }.padding(.horizontal, 21).frame(height: 70).background(Studio.white)
            .overlay(alignment: .top) { Rectangle().fill(Studio.line.opacity(0.65)).frame(height: 1) }
    }
    private func sparringHistoryControls(_ game: TrainingGame) -> some View {
        let index = model.gameReviewCursor ?? game.moves.count
        return HStack(spacing: 3) {
            StudioIconButton(symbol: "backward.end", label: "回到初始局面") { model.reviewGame(at: 0) }.disabled(index == 0)
            StudioIconButton(symbol: "chevron.left", label: "回看上一手") { model.reviewGame(at: max(0, index - 1)) }.disabled(index == 0)
            Text("\(index) / \(game.moves.count)").font(.system(size: 11, design: .monospaced)).foregroundColor(Studio.muted).frame(minWidth: 60)
            StudioIconButton(symbol: "chevron.right", label: "回看下一手") { model.reviewGame(at: min(game.moves.count, index + 1)) }.disabled(index == game.moves.count)
            StudioIconButton(symbol: "forward.end", label: "回到棋谱末尾") { model.reviewGame(at: game.moves.count) }.disabled(index == game.moves.count)
        }
    }
    private var sparringLastMove: Move? {
        guard let game = model.game else { return nil }
        let count = model.gameReviewCursor ?? game.moves.count
        guard count > 0, game.moves.indices.contains(count - 1) else { return nil }
        return Move(uci: game.moves[count - 1])
    }
    private var sparringArrows: [RecommendationArrow] {
        guard model.game != nil, model.gameHints else { return [] }
        return model.gameAnalysis.compactMap { row in
            guard let first = row.pv.first, let move = Move(uci: first),
                  (try? model.displayedGamePosition.applying(move: move)) != nil else { return nil }
            return RecommendationArrow(rank: row.rank, move: move)
        }
    }
    private func sparringRequestNewGame() {
        if let game = model.game, game.result == nil, !game.moves.isEmpty { confirmNewGame = true }
        else { showGameSetup = true }
    }

    var gameSetupSheet: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .top) {
                sectionHeading("准备好下一盘。", detail: "下面的设置只用于新开的一盘，不修改当前对局。", large: true)
                Spacer()
                StudioIconButton(symbol: "xmark", label: "取消新盘设置") { showGameSetup = false }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("你执哪一方").font(.system(size: 13, weight: .semibold))
                Picker("新盘执棋颜色", selection: $model.playerSide) {
                    Text("红方 · 先走").tag(Side.red); Text("黑方 · 后走").tag(Side.black)
                }.pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("本地引擎搜索档位").font(.system(size: 13, weight: .semibold))
                Picker("新盘搜索档位", selection: $model.opponentLevel) {
                    Text("轻量").tag(0); Text("标准").tag(1); Text("认真").tag(2)
                    Text("深入").tag(3); Text("长考").tag(4)
                }.pickerStyle(.segmented).labelsHidden()
                Text(sparringLevelDetail(model.opponentLevel)).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(4)
            }
            Label("档位不是人类棋力等级；短时搜索仍然可能很强。", systemImage: "info.circle")
                .font(.system(size: 11)).foregroundColor(Studio.muted)
            Divider()
            HStack {
                Button("取消") { showGameSetup = false }.buttonStyle(StudioButtonStyle())
                Spacer()
                action("开始新的一盘", symbol: "play.fill", id: "sparring-confirm-start") {
                    showGameSetup = false; inspectorTab = 0; model.startGame()
                }
            }
        }.padding(28).frame(width: 510).background(Studio.paper).foregroundColor(Studio.ink)
    }

    var gameHistorySheet: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                sectionHeading("每一盘，都能再读一遍。", detail: "共 \(store.data.games.count) 盘；未结束的对局可以继续，也可以先复盘。")
                Spacer(minLength: 12)
                StudioIconButton(symbol: "xmark", label: "关闭对局历史") { showGameHistory = false }
            }.padding(24)
            Divider()
            ScrollView {
                LazyVStack(spacing: 11) {
                    if store.data.games.isEmpty {
                        StudioEmpty(symbol: "clock.arrow.circlepath", title: "第一盘，等你开始", detail: "开局后自动保存棋面和历史，不需要另外点保存。")
                    }
                    ForEach(store.data.games.sorted { $0.started > $1.started }) { game in
                        sparringSavedGame(game)
                    }
                }.padding(22)
            }
            HStack { Text("只保存在本机 · 不改动自由分析棋局").font(.system(size: 10)).foregroundColor(Studio.muted); Spacer() }
                .padding(20).background(Studio.white)
        }.frame(width: 630, height: 620).background(Studio.paper).foregroundColor(Studio.ink)
    }
    private func sparringSavedGame(_ game: TrainingGame) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(game.started.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13, weight: .semibold))
                Spacer()
                StudioTag(text: game.result == nil ? "未结束" : "已存档", color: game.result == nil ? Studio.green : Studio.muted)
            }
            Text("你执\(game.player.label) · \(sparringLevelName(game.level)) · \(game.moves.count) 手")
                .font(.system(size: 11)).foregroundColor(Studio.muted)
            if let result = game.result { Text(result).font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(2) }
            HStack {
                if model.game?.id == game.id { Text("当前打开的对局").font(.system(size: 10)).foregroundColor(Studio.green) }
                Spacer()
                Button("复盘") {
                    showGameHistory = false; model.resumeGame(game); model.reviewGame(at: game.moves.count); inspectorTab = 1
                }.buttonStyle(StudioButtonStyle(compact: true))
                if game.result == nil {
                    Button("继续对局") {
                        showGameHistory = false; model.resumeGame(game); inspectorTab = 0
                    }.buttonStyle(StudioButtonStyle(primary: true, compact: true))
                }
            }
        }.studioSurface(16)
    }
    private func sparringLevelName(_ level: Int) -> String {
        switch level { case 0: return "轻量搜索"; case 2: return "认真搜索"; case 3: return "深入搜索"; case 4: return "长考搜索"; default: return "标准搜索" }
    }
    private func sparringLevelDetail(_ level: Int) -> String {
        switch level {
        case 0: return "较短搜索，可能采用评价接近的其他合理候选。"
        case 2: return "给引擎更多思考时间，以本轮首选应招。"
        case 3: return "每次搜索 1.8 秒，以本轮首选应招；不是固定深度或 Elo。"
        case 4: return "每次搜索 3 秒，以本轮首选应招；复杂局面的结论仍可能变化。"
        default: return "适中的搜索时间，少量保留评价接近的合理变化。"
        }
    }
    private func sparringVerdict(_ value: String) -> String {
        switch value {
        case "exactBest": return "本轮首选"
        case "good": return "合理选择"
        case "inaccuracy": return "可以更稳"
        case "mistake": return "值得重练"
        default: return "仍待确认"
        }
    }
}
