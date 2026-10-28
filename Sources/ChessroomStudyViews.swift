import SwiftUI

extension LearningCenterView {
    func chessroomStudyWorkspace(width: CGFloat) -> some View {
        VStack(spacing: 14) {
            libraryPreparationBanner
            if model.studyPhase == .unavailable {
                Spacer()
                StudioEmpty(symbol: "book.closed", title: "选一课，开始落子", detail: "")
                action("打开学习路线") { model.openLearningRoadmap() }
                Spacer()
            } else {
                if let route = model.currentStudyRoute, let index = model.currentRouteStudyIndex {
                    HStack(spacing: 12) {
                        Button { model.openCurrentStudyCatalog() } label: {
                            Label(model.mode == .test ? "返回谱例目录" : "谱例目录 · " + route.title.simplifiedForDisplay,
                                  systemImage: "chevron.left")
                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                                .frame(minHeight: 32, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("study-route-directory")
                        Spacer(minLength: 0)
                        Text("第 \(index + 1) / \(model.routeTargets(route).count) 篇")
                            .font(.system(size: 11)).foregroundColor(Studio.muted)
                            .accessibilityIdentifier("study-route-position")
                    }
                }
                HStack(spacing: 14) {
                    if model.line != nil { modeSwitcher }
                    Text(studyModeDescription).font(.system(size: 11)).foregroundColor(Studio.muted)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("study-mode-description")
                }
                HStack(alignment: .top, spacing: 20) {
                    GeometryReader { area in
                        let boardWidth = min(area.size.width, area.size.height * BoardView.Layout.aspectRatio)
                        BoardView(position: model.studyBoardPosition, flipped: model.flipped, selected: model.selected,
                                  targets: model.targets, lastMove: model.studyBoardLastMove, arrows: model.studyArrows,
                                  arrowContext: model.mode == .demonstration ? model.isLibraryStudy ? "引擎参考" : "原谱" : "候选",
                                  studyCoordinates: showStudyCoordinates, onTap: model.tap)
                            .frame(width: boardWidth, height: boardWidth / BoardView.Layout.aspectRatio)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    chessroomInspector.frame(width: width < 850 ? 284 : 334)
                }.frame(maxHeight: .infinity).disabled(model.libraryPreparing)
                HStack(spacing: 12) {
                    studyUndoButton
                    Spacer(minLength: 0)
                    dockSecondary
                    dockPrimary
                }.padding(12).background(Studio.white, in: RoundedRectangle(cornerRadius: 17)).disabled(model.libraryPreparing)
                    .shadow(color: Studio.ink.opacity(0.07), radius: 9, y: 4)
            }
        }.padding(width < 850 ? 14 : 22).background(Studio.paper)
    }

    private var chessroomInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Text((model.mode == .test ? model.currentRunUsedHelp ? "检验 · 本轮含辅助" : "无提示检验" : model.activeReview?.title ?? model.lesson?.title ?? "局面练习").simplifiedForDisplay)
                    .font(.system(size: 22, weight: .semibold, design: .serif)).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let lesson = model.lesson {
                    StudioIconButton(symbol: store.data.bookmarks.contains(lesson.id) ? "bookmark.fill" : "bookmark", label: "收藏课程") { store.bookmark(lesson.id) }
                }
            }
            studySessionProgress
            HStack {
                Text(model.isAssessingSubmission ? "已落子 · 正在核对" : "\(model.position.sideToMove.label)行棋")
                    .foregroundColor(model.position.sideToMove == .red ? Studio.red : Studio.ink)
                Spacer()
                if model.isCheckpointStudy, model.mode != .demonstration {
                    let progress = model.studyDecisionProgress
                    Text("决策 \(progress.completed) / \(progress.total)").monospacedDigit()
                } else if let line = model.line { Text("\(model.cursor) / \(line.moves.count)").monospacedDigit() }
                else { Text(model.studyPhase.title) }
            }.font(.system(size: 12, weight: .medium)).padding(12)
                .background(Studio.paper, in: RoundedRectangle(cornerRadius: 12))
            if model.mode == .demonstration {
                HStack(spacing: 8) {
                    StudioIconButton(symbol: "chevron.left", label: "上一步 · ←") { model.demoStep(-1) }.disabled(model.cursor == 0 || model.busy)
                        .modifier(StudyKeyboardShortcut(enabled: studyShortcutsAllowed, key: .leftArrow))
                    StudioIconButton(symbol: "chevron.right", label: "下一步 · →") { model.demoStep(1) }.disabled(model.completed || model.busy)
                        .modifier(StudyKeyboardShortcut(enabled: studyShortcutsAllowed, key: .rightArrow))
                    Text("逐步看谱").font(.system(size: 11)).foregroundColor(Studio.muted)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                StudioIconButton(symbol: "arrow.triangle.2.circlepath", label: "翻转棋盘") { model.flipped.toggle() }
                StudioIconButton(symbol: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                 label: focusMode ? "退出专注模式" : "专注模式 · 扩大棋盘", active: focusMode) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { focusMode.toggle() }
                }.accessibilityIdentifier("study-focus")
                Spacer(minLength: 0)
                StudioIconButton(symbol: "list.bullet", label: "逐步棋谱", active: inspectorTab == 1) { inspectorTab = inspectorTab == 1 ? 0 : 1 }
                    .accessibilityIdentifier("inspector-tab-1")
                StudioIconButton(symbol: "info.circle", label: "讲解与来源", active: showStudyDetails) { showStudyDetails = true }
                    .popover(isPresented: $showStudyDetails) { chessroomStudyDetails }
                    .accessibilityIdentifier("study-details")
            }
            if let lesson = model.lesson {
                let count = lesson.lines.reduce(0) { $0 + ($1.variations?.count ?? 0) }
                Button {
                    if inspectorTab == 2 { inspectorTab = 0 }
                    else {
                        if model.mode == .test { model.enterGuidedPractice() }
                        guard model.recordMaterialExposure(lessonID: lesson.id) else { return }
                        inspectorTab = 2
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: inspectorTab == 2 ? "arrow.left" : "arrow.triangle.branch")
                        Text(inspectorTab == 2 ? "返回当前点评" : model.mode == .test ? "转练习，看变招思路" : "变招与思路 · \(count) 条")
                        Spacer(minLength: 0)
                        if inspectorTab != 2 { Image(systemName: "chevron.right").font(.system(size: 10)) }
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(StudioButtonStyle(compact: true)).disabled(model.busy)
                    .accessibilityIdentifier("study-all-variations")
            }
            if inspectorTab == 2, model.mode != .test, let lesson = model.lesson, let line = model.line {
                ScrollView {
                    StudyVariationCatalogView(lesson: lesson, currentLine: line, currentPly: model.cursor) { parent, variation in
                        variationPreview = VariationPreviewRequest(lessonID: lesson.id, parent: parent, variation: variation)
                    }
                }
            } else if inspectorTab == 1 { studyTimeline }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.completed, model.mode != .demonstration { studyCompletionCard }
                        else {
                            chessroomFeedback
                            if model.mode != .test, let goal = model.currentRouteGoal, !goal.isEmpty {
                                DisclosureGroup("这次练什么") {
                                    Text(goal.simplifiedForDisplay).font(.system(size: 12)).lineSpacing(5).padding(.top, 8)
                                }.font(.system(size: 11)).foregroundColor(Studio.muted)
                            }
                            if model.hasPendingMove, !model.completed {
                                if model.referenceContinuationNeeded {
                                    Label(model.referenceChoiceMatches ? "继续沿参考线练习" : "下一题会回到参考线；你的选择已记录", systemImage: "arrow.triangle.branch")
                                        .font(.system(size: 11)).foregroundColor(Studio.muted).fixedSize(horizontal: false, vertical: true)
                                }
                                HStack(spacing: 8) {
                                    if !model.isShowingReplyPreview {
                                        Button("看对手回应") { model.showReply() }.buttonStyle(StudioButtonStyle(compact: true)).disabled(model.busy)
                                    }
                                    if model.feedbackKind == "uncertain" {
                                        Button("再算深一点") { model.deepenStudyAssessment() }.buttonStyle(StudioButtonStyle(compact: true)).disabled(model.busy)
                                    }
                                }
                            }
                        }
                        if model.mode == .practice && !model.completed {
                            HStack(spacing: 5) {
                                ForEach(1...3, id: \.self) { index in Capsule().fill(index <= model.hintLevel ? Studio.accent : Studio.line).frame(width: 23, height: 3) }
                                Text(model.hintLevel == 0 ? "先自己走" : "提示 \(model.hintLevel) / 3").font(.system(size: 10)).foregroundColor(Studio.muted)
                            }.padding(.top, 7)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            if model.mode == .demonstration, !model.completed {
                Button { model.startGame(from: model.position, player: model.position.sideToMove) } label: {
                    Text("从当前局面陪练").frame(maxWidth: .infinity)
                }.buttonStyle(StudioButtonStyle(primary: true)).disabled(model.busy)
                    .accessibilityIdentifier("study-position-to-game")
            }
            HStack {
                Text(model.currentRunUsedHelp ? "辅助练习" : model.mode == .test ? "无提示检验" : "本地学习").font(.system(size: 10)).foregroundColor(Studio.muted)
                Spacer()
                if model.currentStudyRoute != nil {
                    Button("返回谱例目录") { model.openCurrentStudyCatalog() }
                        .buttonStyle(StudioQuietButtonStyle()).font(.system(size: 11)).foregroundColor(Studio.accent)
                        .accessibilityIdentifier("study-back-directory")
                } else if model.isJourneyStudy {
                    Button("学习路线") { model.openLearningRoadmap() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Studio.accent).disabled(model.busy)
                        .accessibilityIdentifier("study-back-roadmap")
                } else if model.isLibraryStudy {
                    Button("返回题库") { model.returnToLibraryBrowser() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Studio.accent).disabled(model.busy)
                        .accessibilityIdentifier("library-study-catalog")
                } else if model.line != nil {
                    Button("本课谱例") { showBranches = true }.buttonStyle(StudioQuietButtonStyle()).font(.system(size: 11)).foregroundColor(Studio.accent)
                        .popover(isPresented: $showBranches) { branchChooser }.disabled(model.busy)
                        .accessibilityIdentifier("study-branches")
                }
            }
        }.padding(20).frame(maxHeight: .infinity).background(Studio.white, in: RoundedRectangle(cornerRadius: 23))
            .shadow(color: Studio.ink.opacity(0.08), radius: 16, y: 6)
    }

    private var chessroomFeedback: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.hasPendingMove && !model.isShowingReplyPreview && !model.busy {
                Text(model.feedbackTitle.simplifiedForDisplay).font(.system(size: 18, weight: .semibold)).foregroundColor(feedbackColor)
            }
            HStack(alignment: .top, spacing: 10) {
                if model.busy { ProgressView().controlSize(.small) }
                else { Image(systemName: model.mode == .test ? "eye.slash" : "lightbulb").foregroundColor(feedbackColor) }
                Text(chessroomHint.simplifiedForDisplay).font(.system(size: 14, weight: .medium)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("study-feedback")
            }
            // Test prompts remain neutral until a move has been submitted. Never
            // disclose the reference-line body through hover or an early expander.
            if !model.busy, model.mode != .test || model.hasPendingMove || model.completed {
                if model.feedbackBody.count > chessroomHint.count {
                    DisclosureGroup(isExpanded: $showFullFeedback) {
                        Text(model.feedbackBody.simplifiedForDisplay).font(.system(size: 12)).lineSpacing(5).padding(.top, 8)
                    } label: { Text("展开解释").font(.system(size: 11)) }
                }
            }
        }.padding(15).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Studio.cream.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }

    private var chessroomHint: String {
        if model.busy { return model.isAssessingSubmission ? "已收到这一步，正在比较对手的回应…" : "正在核对局面…" }
        if model.mode == .test && !model.completed && !model.hasPendingMove { return "请在棋盘上提交你的选择。" }
        if model.isShowingReplyPreview { return "这是对方的回应。看清后回原位重走。" }
        if let summary = model.submissionSummary { return summary }
        let body = model.feedbackBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = body.components(separatedBy: CharacterSet(charactersIn: "。\n")).first ?? body
        if first.isEmpty { return "先在棋盘上走一步。" }
        if first.count > 66 { return String(first.prefix(65)) + "…" }
        return first + ("！？?!…".contains(String(first.suffix(1))) ? "" : "。")
    }

    private var chessroomStudyDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("讲解与来源").font(.system(size: 20, weight: .semibold)); Spacer(); StudioIconButton(symbol: "xmark", label: "收起讲解") { showStudyDetails = false } }
                coachFeedbackPanel
                if model.isCheckpointStudy { decisionContext }
                if model.mode != .test, let lesson = model.lesson {
                    if let guide = lesson.guide { DisclosureGroup("本课导读") { studyGuide(guide, lesson: lesson).padding(.top, 12) } }
                    DisclosureGroup("通法与变招条件") {
                        VStack(alignment: .leading, spacing: 10) { Text(lesson.principle.simplifiedForDisplay); Text((model.line?.adaptation ?? lesson.whenToAdapt).simplifiedForDisplay) }.font(.system(size: 13)).lineSpacing(5).padding(.top, 12)
                    }
                    if model.mode == .demonstration { checkpointNavigator; studyVariationEntry }
                    sourceRows(model.sources.filter { lesson.sourceIDs.contains($0.id) })
                }
                Text(boardInstruction).font(.system(size: 11)).foregroundColor(Studio.muted)
                Toggle("显示 a–i / 0–9 坐标", isOn: $showStudyCoordinates).font(.system(size: 12))
            }.padding(24)
        }.frame(width: 470, height: 570).background(Studio.white).foregroundColor(Studio.ink)
    }

}
