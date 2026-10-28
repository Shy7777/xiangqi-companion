import SwiftUI

extension LearningCenterView {
    var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(StudyMode.allCases) { mode in
                Button { if model.mode != mode { inspectorTab = 0; model.switchMode(mode) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode == .demonstration ? "play.circle" : mode == .practice ? "hand.draw" : "checkmark.shield")
                        Text(modeName(mode))
                    }.font(.system(size: 12, weight: model.mode == mode ? .semibold : .regular))
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .foregroundColor(model.mode == mode ? Studio.onAccent : Studio.muted)
                        .background(model.mode == mode ? Studio.green : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }.buttonStyle(StudioQuietButtonStyle()).accessibilityLabel(modeName(mode))
                    .accessibilityValue(model.mode == mode ? "已选择" : "未选择")
                    .help("\(mode.title)：从分支起点开始；本轮已有求助记录会保留")
                    .accessibilityIdentifier("study-mode-\(mode.rawValue)")
            }
        }.padding(3).background(Studio.paper, in: RoundedRectangle(cornerRadius: 6))
    }
    var branchChooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本课谱例 · \(model.lesson?.lines.count ?? 0) 条").font(.system(size: 18, weight: .semibold))
            Text("这里只列当前课程的谱例。点选后从起点开始，已有练习和辅助记录保留。")
                .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
            if let lesson = model.lesson {
                ForEach(lesson.lines) { line in
                    let progress = store.progress(lesson.id, line.id)
                    let current = model.lineID == line.id
                    let progressText = courseLineProgressText(progress)
                    Button {
                        showBranches = false; inspectorTab = 0; model.startLesson(lesson, line: line, mode: model.mode)
                    } label: {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: current ? "checkmark.circle.fill" : "circle").foregroundColor(Studio.green)
                            VStack(alignment: .leading, spacing: 7) {
                                Text((model.mode == .test ? neutralLineTitle(line) : line.title).simplifiedForDisplay).font(.system(size: 13, weight: .semibold))
                                HStack(spacing: 6) {
                                    if current { Text("当前谱例").foregroundColor(Studio.green) }
                                    Text(progressText).foregroundColor(Studio.muted)
                                }.font(.system(size: 10, weight: .medium))
                                Text((model.mode == .test ? lineScope(line) : line.intent).simplifiedForDisplay)
                                    .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(3)
                                if model.mode != .test, let game = line.game { gameProvenance(game) }
                            }
                        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                            .background(current ? Studio.green.opacity(0.06) : Studio.paper, in: RoundedRectangle(cornerRadius: 11))
                            .contentShape(Rectangle())
                    }.buttonStyle(StudioQuietButtonStyle())
                        .accessibilityIdentifier("study-course-line-\(line.id)")
                        .accessibilityValue((current ? "当前谱例，" : "") + progressText)
                }
            }
        }.padding(22).frame(width: 340).foregroundColor(Studio.ink).background(Studio.white)
    }
    private func courseLineProgressText(_ progress: LineProgress) -> String {
        if progress.delayedTests > 0 { return "隔日通过 · 已练 \(progress.completions) 次" }
        if progress.cleanTests > 0 { return "独立通过 · 已练 \(progress.completions) 次" }
        if progress.completions > 0 { return "已练 \(progress.completions) 次" }
        if progress.demonstrations > 0 { return "看过讲解 · 尚未练习" }
        return "尚未练习"
    }
    var studyBoardStatus: some View {
        HStack(spacing: 8) {
            Circle().fill(model.position.sideToMove == .red ? Studio.red : Studio.ink).frame(width: 7, height: 7)
            Text("\(model.position.sideToMove.label)行棋").font(.system(size: 12, weight: .semibold))
            Spacer()
            if model.isShowingReplyPreview { StudioTag(text: "反击预览", color: Studio.gold) }
            else if model.referenceContinuationNeeded { StudioTag(text: "本题已评估") }
            else if model.position.isInCheck(model.position.sideToMove) { StudioTag(text: "正在被将军", color: Studio.red) }
            else { Text(model.studyPhase.title).font(.system(size: 11)).foregroundColor(Studio.muted) }
        }.frame(height: 24)
    }
    func neutralLineTitle(_ line: StudyLine) -> String {
        "本课谱例 \((model.lesson?.lines.firstIndex(where: { $0.id == line.id }) ?? 0) + 1)"
    }
    var boardInstruction: String {
        if model.isShowingReplyPreview { return "正在预览对方回应，不是原来的作答局面。" }
        if model.studyPhase == .demonstration { return "教学箭头只代表这条线路，不是唯一好棋。" }
        if model.studyPhase == .studentTurn { return model.isCheckpointStudy ? "先确定计划，再在棋盘提交你的候选着法。" : "点一枚棋子，再点落点。圆点是合法位置。" }
        if model.referenceContinuationNeeded { return "这里显示你的选择；继续时会切回\(model.referenceLineName)，不是沿你的着法自动延续。" }
        if model.studyPhase == .awaitingOpponent { return "先读这一步的目的，再看对方怎样回应。" }
        if model.studyPhase == .analyzing { return "本地引擎正在核对走前与走后，暂不判分。" }
        return "随时可回到原局面，再作一次判断。"
    }

    func inspectorButton(_ title: String, tab: Int) -> some View {
        Button { inspectorTab = tab } label: {
            Text(title).font(.system(size: 12, weight: inspectorTab == tab ? .semibold : .regular))
                .foregroundColor(inspectorTab == tab ? Studio.green : Studio.muted).padding(.vertical, 15)
                .overlay(alignment: .bottom) { if inspectorTab == tab { Capsule().fill(Studio.green).frame(height: 2) } }
        }.buttonStyle(.plain).accessibilityIdentifier("inspector-tab-\(tab)")
    }
    var coachFeedbackPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: model.busy ? "sparkle.magnifyingglass" : model.feedbackKind == "mistake" ? "arrow.uturn.backward" : model.completed ? "checkmark" : "lightbulb")
                    .font(.system(size: 14, weight: .medium)).foregroundColor(feedbackColor)
                    .frame(width: 34, height: 34).background(feedbackColor.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("你的本地伴练").font(.system(size: 10, weight: .medium)).foregroundColor(Studio.muted)
                    Text(model.busy ? "正在核对局面" : model.feedbackKind == "mistake" ? "比较计划与计算" : model.isCheckpointStudy ? "参考线不是唯一答案" : "一次只看一个要点")
                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                }
            }
            Text(model.feedbackTitle.simplifiedForDisplay).font(.system(size: 19, weight: .semibold)).foregroundColor(feedbackColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(shortFeedback.simplifiedForDisplay).font(.system(size: 13)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("study-feedback")
            if shortFeedback != model.feedbackBody {
                DisclosureGroup(isExpanded: $showFullFeedback) {
                    Text(model.feedbackBody.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(5).padding(.top, 7)
                } label: { Text("完整解释与计算依据").font(.system(size: 11, weight: .medium)) }
            }
            if model.busy {
                HStack(spacing: 9) { ProgressView().controlSize(.small); Text(coach.status).font(.system(size: 11)).foregroundColor(Studio.muted) }
            }
            if model.page == .study, model.mode == .practice && !model.completed {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(1...3, id: \.self) { index in Capsule().fill(index <= model.hintLevel ? Studio.green : Studio.line.opacity(0.55)).frame(width: 22, height: 3) }
                        Text(["先自己判断", "方向提示", "关键棋子", "具体走法"][min(3, model.hintLevel)])
                            .font(.system(size: 10)).foregroundColor(Studio.muted).padding(.leading, 4)
                    }
                    if model.currentRunUsedHelp { Text("本轮用于练习，不算独立通过。").font(.system(size: 10)).foregroundColor(Studio.gold) }
                }.padding(.top, 3)
            }
            if model.mode == .test && model.page == .study {
                Label(model.currentRunUsedHelp ? "本轮含先前辅助记录" : "提示关闭 · 独立检验", systemImage: "eye.slash")
                    .font(.system(size: 10)).foregroundColor(Studio.muted)
            }
        }
    }
    var feedbackColor: Color { model.feedbackKind == "mistake" ? Studio.red : model.feedbackKind == "uncertain" ? Studio.gold : Studio.green }
    var shortFeedback: String {
        if model.isCheckpointStudy {
            if model.feedbackBody.count <= 200 { return model.feedbackBody }
            return String(model.feedbackBody.split(separator: "。").prefix(3).joined(separator: "。")) + "。"
        }
        if model.feedbackBody.count <= 100 { return model.feedbackBody }
        if model.feedbackKind == "alternative" { return "这步也成立，不需要照抄棋谱。你可以继续探索这条变化，或返回课程主线。" }
        if model.feedbackKind == "uncertain" { return "这次短时搜索还不足以确定对错，本轮不计错。你可以加深分析，或回到原局面再判断。" }
        if model.feedbackKind == "mistake" { return String(model.feedbackBody.split(separator: "。").prefix(2).joined(separator: "。")) + "。" }
        return String(model.feedbackBody.split(separator: "。").prefix(1).joined(separator: "。")) + "。"
    }
    var studyTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let line = model.line, model.studyPositions.count == line.moves.count + 1 {
                        let positions = model.studyPositions
                        Text(model.mode == .demonstration ? "点击任一步，回到对应棋面。" : "只显示已走过的步骤，不提前透露答案。")
                            .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4).padding(.bottom, 20)
                        if model.mode == .demonstration {
                            if let game = line.game { gameProvenance(game).padding(.bottom, 18) }
                            checkpointNavigator.padding(.bottom, 20)
                            Button("回到起点") { model.goToDemoPly(0) }.buttonStyle(StudioButtonStyle(compact: true)).padding(.bottom, 14)
                        }
                        ForEach(Array(line.moves.enumerated()).filter { model.mode == .demonstration || $0.offset < model.cursor }, id: \.offset) { index, step in
                            let current = index + 1 == model.cursor
                            Button { if model.mode == .demonstration { model.goToDemoPly(index + 1) } } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(spacing: 5) {
                                        Text("\(index + 1)").font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(current ? .white : Studio.muted).frame(width: 25, height: 25)
                                            .background(current ? Studio.green : Studio.paper, in: Circle())
                                        Rectangle().fill(Studio.line.opacity(0.55)).frame(width: 1).frame(minHeight: 18)
                                    }
                                    VStack(alignment: .leading, spacing: 7) {
                                        if let move = Move(uci: step.uci) { Text(positions[index].notation(for: move)).font(.system(size: 13, weight: .semibold)) }
                                        if model.mode == .demonstration { Text(step.explanation.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 18)
                                }.padding(8).background(current ? Studio.green.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(model.busy || model.mode != .demonstration).id(index + 1)
                                .accessibilityIdentifier("demo-ply-\(index + 1)")
                        }
                        if model.cursor == 0 && model.mode != .demonstration { Text("等你走出第一步。").font(.system(size: 13)).foregroundColor(Studio.muted) }
                    } else {
                        Text("错题练习只看当前局面。先自己走，反馈和反击路线会在落子后出现。")
                            .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(6)
                    }
                }.padding(20)
            }.onChange(of: model.cursor) { cursor in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(cursor, anchor: .center) } }
        }
    }

    @ViewBuilder var dockPrimary: some View {
        if model.busy {
            Button("取消本次判断") { model.stopCalculation() }.buttonStyle(StudioButtonStyle())
                .accessibilityIdentifier("study-cancel-assessment")
        } else if model.mode == .demonstration {
            if model.completed, model.isJourneyStudy {
                action(model.studyCompletionNextTitle, id: "demo-to-practice") { model.continueAfterStudy() }
            } else if model.completed, let lesson = model.lesson, let line = model.line {
                action("我来走一遍", id: "demo-to-practice") { model.startLesson(lesson, line: line, mode: .practice) }
            } else {
                action("下一步", id: "demo-next") { model.demoStep(1) }
                    .modifier(StudyKeyboardShortcut(enabled: studyShortcutsAllowed, key: .space))
            }
        } else if model.completed {
            action(model.studyCompletionNextTitle, id: model.isJourneyStudy ? "continue-daily" : model.isLibraryStudy ? "library-study-next" : model.activeReview != nil ? "review-done" : model.isCheckpointStudy ? "research-complete" : "next-variation") {
                model.continueAfterStudy()
            }.disabled(model.libraryPreparing)
        } else if model.referenceContinuationNeeded {
            action(model.nextDecisionActionTitle, id: "checkpoint-continue") { model.continueStudy() }
                .modifier(StudyKeyboardShortcut(enabled: studyShortcutsAllowed, key: .space))
        } else if model.hasPendingMove {
            if model.feedbackKind == "alternative", model.line != nil, !model.isShowingReplyPreview {
                action("继续这条变化", id: "continue-alternative") { model.continueBranchAsGame() }
            } else {
                action("悔棋重走", symbol: "arrow.uturn.backward", id: "retry-position") { model.rewindStudy() }
            }
        } else if model.awaitingContinue {
            action("看对手应招", id: "study-continue") { model.continueStudy() }
                .modifier(StudyKeyboardShortcut(enabled: studyShortcutsAllowed, key: .space))
        } else if model.mode == .practice {
            Label("轮到你走", systemImage: "hand.draw").font(.system(size: 13, weight: .medium)).foregroundColor(Studio.green).padding(8)
        } else { Label("在棋盘上作答", systemImage: "hand.draw").font(.system(size: 13, weight: .medium)).foregroundColor(Studio.green).padding(8) }
    }
    @ViewBuilder var dockSecondary: some View {
        if !model.busy {
            if model.isJourneyStudy, !model.completed {
                Menu {
                    Button("跳过本题，不记为完成") { model.skipJourneyItem() }
                    Button("先回学习路线") { model.openLearningRoadmap() }
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 15)) }
                    .menuStyle(.borderlessButton).fixedSize().help("这组训练的操作")
                    .accessibilityIdentifier("study-session-options")
            }
            if model.referenceContinuationNeeded {
                Button(model.referenceChoiceMatches ? "从这里实战" : "沿我的变招实战") { model.continueBranchAsGame() }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("checkpoint-explore")
            } else if model.mode == .demonstration {
                if model.isLibraryStudy, !model.isJourneyStudy, model.libraryCanContinue {
                    Button("下一局") { model.startNextLibraryEntry(mode: .demonstration) }
                        .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("library-demo-next")
                }
                if !model.completed, let lesson = model.lesson, let line = model.line {
                    Button("从这里练") { model.startLesson(lesson, line: line, mode: .practice, from: model.cursor) }.buttonStyle(StudioButtonStyle(compact: true))
                }
            } else if model.completed, model.activeReview == nil {
                Menu {
                    Button("无提示再测") { model.switchMode(.test) }
                    if model.isLibraryStudy {
                        Button("回到原位练习") { model.switchMode(.practice) }
                    } else if (model.lesson?.lines.count ?? 0) > 1 {
                        Button("下一条本课谱例") { model.nextVariation() }
                    }
                    if let line = model.line { Button("从此局面接着实战") { model.startGame(from: model.position, player: line.studentSide) } }
                    if model.isJourneyStudy { Button("返回学习路线") { model.openLearningRoadmap() } }
                } label: { Text("接下来…").font(.system(size: 12)) }.menuStyle(.borderlessButton).fixedSize()
            } else if model.hasPendingMove {
                Menu {
                    if !model.isShowingReplyPreview { Button("看对手反击") { model.showReply() } }
                    if model.feedbackKind == "uncertain" { Button("加深分析") { model.deepenStudyAssessment() } }
                    Button(model.studyUndoTitle) { model.rewindStudy() }
                } label: { Label("展开比较", systemImage: "ellipsis").font(.system(size: 12)) }.menuStyle(.borderlessButton).fixedSize()
            } else if model.mode == .test, model.lesson != nil, model.line != nil {
                Button("转练习，给提示") { model.enterGuidedPractice(); model.hint() }.buttonStyle(StudioButtonStyle(compact: true))
            } else if model.mode == .practice, !model.completed, model.hintLevel < 3 {
                Button(["给一点提示", "再具体一点", "显示这一步"][min(2, model.hintLevel)]) { model.hint() }
                    .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("study-hint")
            }
        }
    }
    func modeName(_ mode: StudyMode) -> String {
        switch mode { case .demonstration: return "看谱讲解"; case .practice: return "引导练习"; case .test: return "无提示检验" }
    }
    var studyModeDescription: String {
        switch model.mode {
        case .demonstration: return "看主线和变招，逐步理解思路。"
        case .practice: return "每步点评；可以提示、看谱、悔棋。"
        case .test: return model.currentRunUsedHelp ? "本轮已有辅助，只作练习，不计独立通过。" : "答前无提示，答后点评；看谱或悔棋会转练习。"
        }
    }
    var studyUndoButton: some View {
        Button { model.rewindStudy() } label: {
            Label(model.studyUndoTitle, systemImage: "arrow.uturn.backward")
        }.buttonStyle(StudioButtonStyle(compact: true))
            .disabled(!model.canRewindStudy)
            .help(model.mode == .test ? "悔棋后转为引导练习，不计独立通过；原记录保留。" : "回到自己上次落子前。记录保留，可反复重走。")
            .accessibilityIdentifier("study-undo")
            .modifier(StudyKeyboardShortcut(enabled: studyShortcutsAllowed && model.canRewindStudy && model.mode != .demonstration, key: "z", modifiers: .command))
    }
}
