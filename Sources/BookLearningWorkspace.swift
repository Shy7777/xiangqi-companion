import SwiftUI

/// One native desk owns the book, the decision and the route back from analysis.
/// Original text is resolved from BookDocument and is never rewritten here.
struct BookLearningWorkspace: View {
    @ObservedObject var book: BookStudyModel
    @ObservedObject var lesson: BookLessonModel
    let onAnalyze: (Position, Side) -> Void

    @State private var workspaceMode = WorkspaceMode.guided
    @State private var railTab = 0
    @State private var showsRail = false
    @State private var showsSources = false
    @State private var showsVariations = false
    @State private var showsOriginal = false
    @State private var showsEngine = false
    @State private var showsCoverage = false
    @State private var showsLearningPath = false
    @State private var showsPhases = false
    @AppStorage("book.learning.originalFontSize") private var originalFontSize = 15.0

    private enum WorkspaceMode: String, CaseIterable, Identifiable {
        case guided, reading, replay
        var id: String { rawValue }
        var title: String {
            switch self {
            case .guided: return "跟书学习"
            case .reading: return "自由阅读"
            case .replay: return "重走原谱"
            }
        }
    }

    private let sage = Color(red: 83 / 255, green: 109 / 255, blue: 87 / 255)
    private var guided: Bool { workspaceMode == .guided }
    private var decision: Bool { guided && lesson.stage == .decision }
    private var position: Position { guided ? lesson.position : book.position }
    private var originalNodeID: Int {
        guard guided else { return book.nodeID }
        if lesson.stage == .comparison, let nodeID = lesson.comparisonNodeID { return nodeID }
        return lesson.checkpoint?.annotationNodeID ?? book.nodeID
    }
    private var originalComment: String { book.node(originalNodeID)?.comment ?? "" }
    private var followingCheckpoint: BookCourseCheckpoint? {
        guard let unit = lesson.selectedUnit, unit.checkpoints.indices.contains(lesson.checkpointIndex + 1) else { return nil }
        return unit.checkpoints[lesson.checkpointIndex + 1]
    }
    private var canAnalyze: Bool {
        guided ? lesson.selectedUnit != nil && (try? lesson.analysisPosition.validate()) != nil : book.canAnalyze
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 1060
            VStack(spacing: 0) {
                header(wide: wide, compact: geometry.size.width < 700)
                if let message = lesson.store.error ?? lesson.notice ?? book.notice { notice(message) }
                if book.document == nil {
                    emptyLibrary
                } else {
                    HStack(spacing: 0) {
                        if wide {
                            rail.frame(width: 220)
                            Rectangle().fill(Studio.line).frame(width: 0.7)
                        }
                        desk(width: geometry.size.width - (wide ? 221 : 0))
                    }
                }
            }
        }
        .foregroundColor(Studio.ink).background(Studio.paper).tint(sage).preferredColorScheme(.light)
        .sheet(isPresented: $showsSources) {
            BookLearningSourceSheet(book: book, fontSize: $originalFontSize, onExpose: exposeWholeRecord,
                                    onChoose: openSourceNode)
        }
        .sheet(isPresented: $showsVariations) {
            BookLearningVariationSheet(book: book, onExpose: exposeWholeRecord, onChoose: openSourceNode)
        }
        .task(id: book.document?.sourceSHA256) { await lesson.reloadCatalog() }
        .onChange(of: lesson.stage) { stage in
            if stage == .decision { showsOriginal = false; showsEngine = false }
            else if stage == .reading { showsOriginal = false }
        }
        .onChange(of: lesson.selectedUnit?.id) { _ in
            resetReferencePanels(); workspaceMode = .guided
        }
        .onChange(of: lesson.checkpoint?.id) { _ in resetReferencePanels() }
    }

    private func header(wide: Bool, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                if !wide {
                    Button { showsRail.toggle() } label: { Label("本课 / 目录", systemImage: "sidebar.left") }
                        .buttonStyle(StudioButtonStyle(compact: true))
                        .accessibilityIdentifier("book-show-contents")
                        .sheet(isPresented: $showsRail) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("本课与全书目录").font(.headline)
                                    Spacer()
                                    Button("返回棋盘") { showsRail = false }
                                        .accessibilityIdentifier("book-close-contents")
                                }.padding(16)
                                Divider()
                                rail.frame(width: 420, height: 600)
                            }.background(Studio.paper)
                        }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.document?.title ?? "我的棋书")
                        .font(.system(size: 12)).foregroundColor(Studio.muted).lineLimit(1)
                    Text(lesson.selectedUnit?.title ?? book.record?.displayTitle ?? "把棋书变成连续的学习")
                        .font(.system(size: compact ? 18 : 21, weight: .semibold, design: .serif))
                        .lineLimit(2).help(book.record?.title ?? "")
                }.frame(maxWidth: .infinity, alignment: .leading)
                if book.record != nil {
                    StudioIconButton(symbol: book.status(for: book.selectedRecordID ?? "").bookmarked ? "bookmark.fill" : "bookmark",
                                     label: "收藏当前谱例") { book.toggleBookmark() }
                        .accessibilityIdentifier("book-bookmark")
                }
            }
            HStack(spacing: 12) {
                Picker("学习方式", selection: $workspaceMode) {
                    ForEach(WorkspaceMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 340)
                    .accessibilityIdentifier("book-workspace-mode")
                    .onChange(of: workspaceMode, perform: changeMode)
                Spacer(minLength: 0)
                if !compact {
                    Text("待复习 \(lesson.dueReviewCount)")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(sage)
                        .accessibilityIdentifier("book-due-review-count")
                }
            }
        }.padding(.horizontal, 20).padding(.vertical, 15).background(Studio.white)
            .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: 0.7) }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Picker("左侧内容", selection: $railTab) {
                Text("本课任务").tag(0)
                Text("全书目录").tag(1)
            }.pickerStyle(.segmented).labelsHidden().padding(14).accessibilityIdentifier("book-learning-rail-tabs")
            if railTab == 0 { lessonRail }
            else {
                BookContentsView(model: book, onChoose: {
                    resetReferencePanels()
                    if let id = book.selectedRecordID { lesson.selectRecord(id: id) }
                    workspaceMode = .guided; showsRail = false
                })
            }
        }.frame(maxHeight: .infinity).background(Studio.rail)
    }

    private var lessonRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    eyebrow("继续当前课")
                    Text(lesson.progressText).font(.system(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(book.record?.sectionTitle ?? "从当前谱例开始")
                        .font(.system(size: 12)).foregroundColor(Studio.muted)
                }
                if let unit = lesson.selectedUnit, !unit.checkpoints.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        eyebrow("本课关键点 · 可随时返回")
                        ForEach(Array(unit.checkpoints.enumerated()), id: \.element.id) { index, checkpoint in
                            checkpointButton(checkpoint, index: index)
                        }
                    }
                }
                DisclosureGroup("本课学习环节", isExpanded: $showsPhases) {
                    VStack(alignment: .leading, spacing: 4) {
                        phaseRow("01", title: "读懂这一处", detail: "目标与相关原注", active: lesson.stage == .reading)
                        phaseRow("02", title: "关键点练习", detail: "先判断，再核验后果", active: lesson.stage == .decision || lesson.stage == .feedback)
                        phaseRow("03", title: "比较变化", detail: "聚焦当前一个分歧", active: lesson.stage == .comparison)
                        phaseRow("04", title: "收束与复习", detail: "区分独立、辅助与隔日", active: lesson.stage == .summary)
                    }.padding(.top, 8)
                }.font(.system(size: 12))
                if let catalog = lesson.catalog, !catalog.firstRoundUnits.isEmpty {
                    DisclosureGroup("首轮学习路径 · \(catalog.firstRoundUnits.count) 课", isExpanded: $showsLearningPath) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(catalog.firstRoundUnits.enumerated()), id: \.element.id) { index, unit in
                                Button { selectUnit(unit.id) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(String(format: "%02d", index + 1)).font(.system(size: 11, design: .monospaced)).padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(unit.title).font(.system(size: 13, weight: lesson.selectedUnit?.id == unit.id ? .semibold : .regular))
                                            Text(unit.goal).font(.system(size: 11)).foregroundColor(Studio.muted)
                                        }
                                        Spacer(minLength: 0)
                                    }.foregroundColor(lesson.selectedUnit?.id == unit.id ? sage : Studio.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
                                }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-course-unit-\(unit.id)")
                            }
                            if let current = lesson.selectedUnit, !current.nextReason.isEmpty {
                                Text("本课之后：" + current.nextReason).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
                            }
                        }.padding(.top, 10)
                    }.font(.system(size: 12))
                }
                DisclosureGroup("本课目标与联系") {
                    VStack(alignment: .leading, spacing: 8) {
                        readingText(lesson.goal)
                        if !lesson.connection.isEmpty {
                            Text(lesson.connection).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.top, 8)
                }.font(.system(size: 12))
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    Text("待复习 \(lesson.dueReviewCount) 个关键点")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(sage)
                    ForEach(lesson.dueReviewItems) { item in
                        Button {
                            resetReferencePanels()
                            if lesson.startReview(item) { workspaceMode = .guided; showsRail = false }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).lineLimit(3)
                                HStack(spacing: 5) {
                                    Text("错题复习")
                                    Text(item.due, style: .date)
                                }.font(.system(size: 11)).foregroundColor(Studio.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }.font(.system(size: 12)).buttonStyle(StudioQuietButtonStyle())
                            .accessibilityIdentifier("book-review-\(item.id.uuidString)")
                    }
                    ForEach(lesson.dueBookSources, id: \.key) { source in
                        Button {
                            resetReferencePanels()
                            if lesson.startSourceReview(source) { workspaceMode = .guided; showsRail = false }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title).lineLimit(3)
                                Text("到期无提示复测 · 先不看答案").font(.system(size: 11)).foregroundColor(Studio.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }.font(.system(size: 12)).buttonStyle(StudioQuietButtonStyle())
                            .accessibilityIdentifier("book-source-review-\(source.key)")
                    }
                    if lesson.dueReviewCount == 0 {
                        Text("当前没有到期任务。").font(.system(size: 12)).foregroundColor(Studio.muted)
                    }
                    Text("阅读不等于掌握。只有实际练习记录进入独立、辅助与复习统计。")
                        .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
                }
                if let catalog = lesson.catalog {
                    DisclosureGroup("全书覆盖说明", isExpanded: $showsCoverage) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("可阅读 \(catalog.stats.readableRecordCount) 篇")
                            if catalog.stats.editedRecordCount > 0 {
                                Text("已编辑教案 \(catalog.stats.editedRecordCount) 篇")
                            }
                            Text("原注节点导学 \(catalog.stats.sourceGuidedRecordCount) 篇")
                            Text("可练习 \(catalog.stats.practiceRecordCount) 篇，不等于均已审校为独立检验题。")
                            if catalog.stats.excludedNodeCount > 0 {
                                Text("\(catalog.stats.excludedNodeCount) 个异常节点不用于练习，原文仍可查阅。")
                            }
                        }.font(.system(size: 12)).foregroundColor(Studio.muted).padding(.top, 8)
                    }.font(.system(size: 12))
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func phaseRow(_ number: String, title: String, detail: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.system(size: 11, weight: .medium, design: .monospaced)).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: active ? .semibold : .regular))
                Text(detail).font(.system(size: 11)).foregroundColor(Studio.muted)
            }
            Spacer(minLength: 0)
        }.foregroundColor(active ? sage : Studio.muted).padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? sage.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine).accessibilityValue(active ? "当前环节" : "学习环节")
    }

    private func checkpointButton(_ checkpoint: BookCourseCheckpoint, index: Int) -> some View {
        let current = lesson.checkpointIndex == index
        let completed = lesson.completedCheckpointIDs.contains(checkpoint.id)
        return Button {
            resetReferencePanels()
            lesson.selectCheckpoint(index: index); workspaceMode = .guided; showsRail = false
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: current ? "circle.inset.filled" : completed ? "checkmark.circle" : "circle")
                    .font(.system(size: 11)).padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(index + 1). \(checkpoint.title)").font(.system(size: 13, weight: current ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(current ? lesson.stage.title : completed ? "本轮已练过" : "可开始")
                        .font(.system(size: 11)).foregroundColor(Studio.muted)
                }
                Spacer(minLength: 0)
            }.foregroundColor(current ? sage : Studio.ink).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(current ? sage.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-checkpoint-\(index)")
            .accessibilityValue(current ? "当前关键点" : completed ? "本轮已练过" : "尚未完成")
    }

    @ViewBuilder private func desk(width: CGFloat) -> some View {
        if width < 660 {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        boardColumn(narrow: true).frame(height: max(340, min(520, width * 1.12)))
                        inspectorContent.padding(18).background(Studio.white, in: RoundedRectangle(cornerRadius: 10))
                    }.padding(16)
                }
                primaryFooter
            }
        } else {
            HStack(alignment: .top, spacing: 18) {
                boardColumn(narrow: false).frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 0) {
                    ScrollView { inspectorContent.padding(20) }
                    primaryFooter
                }.frame(width: width >= 950 ? 354 : 304, alignment: .top)
                    .background(Studio.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Studio.line.opacity(0.6), lineWidth: 0.7).allowsHitTesting(false))
            }.padding(18)
        }
    }

    private func boardColumn(narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(position.sideToMove == .red ? Studio.red : Studio.ink).frame(width: 7, height: 7)
                Text("\(position.sideToMove.label)行棋").font(.system(size: 12, weight: .medium))
                if guided { Text("你执\(lesson.studentSide.label)").font(.system(size: 12)).foregroundColor(Studio.muted) }
                Spacer(minLength: 0)
                StudioIconButton(symbol: "arrow.triangle.2.circlepath", label: "翻转棋盘") { book.flipped.toggle() }
                    .accessibilityIdentifier("book-flip-board")
            }
            GeometryReader { area in
                let boardWidth = max(0, min(area.size.width, area.size.height * BoardView.Layout.aspectRatio))
                BoardView(position: position, flipped: book.flipped,
                          selected: guided ? lesson.selected : book.selected,
                          targets: guided ? lesson.targets : book.targets,
                          lastMove: guided ? lesson.lastMove : book.lastMove,
                          arrows: guided ? lesson.arrows : book.arrows,
                          arrowContext: guided ? "提示" : "原谱",
                          onTap: { square in if guided { lesson.tap(square) } else { book.tap(square) } })
                    .frame(width: boardWidth, height: boardWidth / BoardView.Layout.aspectRatio)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            boardTools
            Text(guided ? "书外合理着法也可接受；是否复现原谱，另行记录。" : workspaceMode == .replay ? "这是原谱复现，不是引擎判分，也不计为关键点独立练习。" : "自由阅读保留全谱原注与变招；随时回到本课判断点。")
                .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var boardTools: some View {
        HStack(spacing: 8) {
            if guided {
                if lesson.stage == .reading {
                    Button("自由打谱") { workspaceMode = .reading }
                        .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("book-free-reading")
                } else {
                    Button("回到判断前") { lesson.returnToAnchor() }
                        .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("book-return-anchor")
                }
                Spacer(minLength: 0)
                if decision {
                    Button("给一点提示") { lesson.requestHint() }
                        .buttonStyle(StudioButtonStyle(compact: true)).disabled(lesson.isThinking)
                        .accessibilityIdentifier("book-lesson-hint")
                } else if lesson.stage == .feedback {
                    Button("从这里重试") { lesson.retry() }
                        .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("book-lesson-retry")
                }
            } else {
                Button { book.back() } label: { Label("上一步", systemImage: "chevron.left") }
                    .buttonStyle(StudioButtonStyle(compact: true)).disabled(!book.canGoBack)
                    .accessibilityIdentifier("book-step-back")
                Button("回分歧点") { book.backToBranch() }
                    .buttonStyle(StudioButtonStyle(compact: true)).disabled(book.currentPly == 0)
                    .accessibilityIdentifier("book-return-fork")
                Spacer(minLength: 0)
                if workspaceMode == .replay && !book.isAwaitingReply {
                    Button("提示") { book.hint() }.buttonStyle(StudioButtonStyle(compact: true))
                        .disabled(!book.canPractice).accessibilityIdentifier("book-hint")
                }
            }
        }
    }

    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if guided { guidedContent }
            else { readingContent }
            Divider()
            sourceTools
            if !decision { engineDetails }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var guidedContent: some View {
        eyebrow(stageTitle)
        if let unit = lesson.selectedUnit {
            Text(unit.tier.title).font(.system(size: 11, weight: .medium)).foregroundColor(sage)
            if unit.tier != .edited {
                Text(unit.availabilityNote).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
            }
        }
        switch lesson.stage {
        case .reading:
            Text(lesson.checkpoint?.title ?? "先读本篇材料").font(.system(size: 19, weight: .semibold, design: .serif))
            readingText(lesson.goal)
            if !lesson.connection.isEmpty {
                Text(lesson.connection).font(.system(size: 13)).foregroundColor(Studio.muted).lineSpacing(6)
            }
            if book.isTextOnly {
                ForEach(book.annotatedNodes) { note in
                    BookOriginalText(text: note.comment, fontSize: originalFontSize)
                        .onAppear { lesson.markReadingExposed() }
                }
            } else {
                readingText(lesson.prompt)
                DisclosureGroup(isExpanded: Binding(get: { showsOriginal }, set: { expanded in
                    if expanded { exposeReference() }
                    showsOriginal = expanded
                })) {
                    VStack(alignment: .leading, spacing: 16) {
                        if !lesson.explanation.isEmpty {
                            eyebrow("软件导学 · 非原书文字")
                            readingText(lesson.explanation)
                        }
                        if !originalComment.isEmpty { originalExcerpt }
                        else { Text("这一节点没有文件原注；整谱原注仍可从下方查阅。").font(.system(size: 14)).foregroundColor(Studio.muted) }
                    }.padding(.top, 12)
                } label: {
                    Text("先读相关原注与讲解").font(.system(size: 14, weight: .medium))
                }
                Text("可先读再练，也可直接判断。展开原注或讲解，本轮会记为辅助；单纯选课不会。")
                    .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
            }
        case .decision:
            Text("如果是你，下一步怎么走？").font(.system(size: 19, weight: .semibold, design: .serif))
            readingText(lesson.prompt)
            Text("在棋盘上选子、落子。先检查对方威胁，再选一个有明确任务的走法。")
                .font(.system(size: 14)).foregroundColor(Studio.muted).lineSpacing(6)
            if !lesson.displayedHint.isEmpty {
                Label("本轮提示", systemImage: "lightbulb").font(.system(size: 12, weight: .medium)).foregroundColor(sage)
                readingText(lesson.displayedHint)
            }
            if lesson.isThinking { thinkingStatus }
        case .feedback:
            Text(lesson.referenceMatch == .mainline ? "这一步与原谱一致" :
                 lesson.referenceMatch == .branch ? "走进书中另一条变招" :
                 lesson.assessment?.title ?? "看看这步的后果")
                .font(.system(size: 19, weight: .semibold, design: .serif))
            readingText(lesson.feedback)
            Text(lesson.referenceMatch.title).font(.system(size: 12, weight: .medium)).foregroundColor(sage)
                .accessibilityIdentifier("book-reference-match")
            if lesson.canPlayReply {
                Button { lesson.nextReply() } label: { Label("在棋盘看对方回应", systemImage: "play") }
                    .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("book-play-consequence")
            }
            if !lesson.canAdvance && !lesson.isThinking {
                Button("加深核验这一步") { lesson.reassess() }
                    .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("book-reassess")
            }
            if lesson.isThinking { thinkingStatus }
            comparisonChoices
        case .comparison:
            Text(lesson.checkpoint?.comparison?.title ?? "比较当前分歧").font(.system(size: 19, weight: .semibold, design: .serif))
            readingText(lesson.checkpoint?.comparison?.prompt ?? "从同一个分歧点切换线路，观察后续的不同。")
            comparisonChoices
            if lesson.canPlayReply {
                Button { lesson.nextReply() } label: { Label("看这条线的下一手", systemImage: "play") }
                    .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("book-comparison-next")
            }
            if lesson.isThinking { thinkingStatus }
            if let comparison = lesson.checkpoint?.comparison { readingText(comparison.explanation) }
            else if !lesson.feedback.isEmpty { readingText(lesson.feedback) }
            if !lesson.canPlayReply && !lesson.isThinking && lesson.comparisonNodeID != nil {
                Text("这条原谱变化已到可播放的末尾，可切换另一条或返回判断点。")
                    .font(.system(size: 12)).foregroundColor(Studio.muted)
            }
        case .summary:
            Text("把判断带到下一次").font(.system(size: 19, weight: .semibold, design: .serif))
            readingText(lesson.summary)
            VStack(spacing: 11) {
                evidenceRow("无提示通过", value: lesson.independentCount)
                evidenceRow("辅助练习", value: lesson.assistedCount)
                evidenceRow("隔日复习", value: lesson.delayedCount)
            }.padding(.vertical, 6)
            Text("这些是本课实际练习次数，不是棋力评级；读过或看过答案不算独立掌握。")
                .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
            if let next = followingCheckpoint {
                Divider()
                eyebrow("继续本课 · 下一个关键点")
                Text(next.title).font(.system(size: 15, weight: .semibold))
                readingText(next.prompt)
            } else if let next = lesson.nextUnitTitle {
                Divider()
                eyebrow("下一课怎样接上")
                Text(next).font(.system(size: 15, weight: .semibold))
                readingText(lesson.selectedUnit?.nextReason ?? lesson.connection)
                if let id = lesson.selectedUnit?.nextUnitID, let nextUnit = lesson.catalog?.unit(id: id) {
                    Text("下一课目标：" + nextUnit.goal).font(.system(size: 13)).foregroundColor(Studio.muted).lineSpacing(5)
                }
            }
            if followingCheckpoint == nil, let related = lesson.selectedUnit?.relatedUnits, !related.isEmpty {
                Divider()
                eyebrow("带着这个问题继续比较")
                ForEach(related) { relation in
                    if let unit = lesson.catalog?.unit(id: relation.unitID) {
                        Button { selectUnit(unit.id) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(unit.title).font(.system(size: 14, weight: .semibold)).foregroundColor(sage)
                                Text(relation.reason).font(.system(size: 13)).foregroundColor(Studio.muted).lineSpacing(5)
                                Text(relation.isVerifiedTransfer ? "已核验的换例材料" : "相关材料 · 尚不作为独立迁移检验")
                                    .font(.system(size: 11)).foregroundColor(Studio.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-related-unit-\(unit.id)")
                    }
                }
            }
        }
    }

    private var readingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            eyebrow(workspaceMode == .replay ? "重走原谱 · 非引擎判分" : "自由阅读 · 文件原注")
            Text(book.currentPly == 0 ? "本谱导读" : "第 \(book.currentPly) 手 · \(book.label(for: book.nodeID))")
                .font(.system(size: 18, weight: .semibold, design: .serif))
            if !book.feedback.isEmpty { readingText(book.feedback) }
            if let issue = book.positionIssue {
                Label(issue, systemImage: "exclamationmark.triangle").font(.system(size: 14)).foregroundColor(Studio.red)
            }
            if workspaceMode != .replay || book.referenceRevealed {
                if !originalComment.isEmpty { originalExcerpt }
                else { Text("文件未给这一位置附注。").font(.system(size: 14)).foregroundColor(Studio.muted) }
                if !book.choices.isEmpty {
                    eyebrow("从当前局面继续")
                    ForEach(book.choices) { choice in sourceChoice(choice) }
                }
            } else {
                Text("后续原注与着法先收起。需要时可查看参考，本轮会记为辅助。")
                    .font(.system(size: 14)).foregroundColor(Studio.muted).lineSpacing(6)
                Button("查看原谱参考 · 记为辅助") { book.revealReference(); exposeReference() }
                    .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("book-reveal-reference")
            }
            HStack {
                Button("回本谱起点") { book.setMode(.reading); book.restart(); if workspaceMode == .replay { book.setMode(.recall) } }
                    .accessibilityIdentifier("book-restart")
                Spacer()
                Button(book.status(for: book.selectedRecordID ?? "").read ? "取消已读" : "标为已读") { book.markRead() }
                    .help("只记录读过，不代表独立掌握").accessibilityIdentifier("book-mark-read")
            }.font(.system(size: 12)).buttonStyle(StudioQuietButtonStyle()).foregroundColor(Studio.muted)
        }
    }

    private var originalExcerpt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("文件原注 · \(book.label(for: originalNodeID))").font(.system(size: 11, weight: .medium)).foregroundColor(Studio.muted)
                Spacer(minLength: 0)
                Button { exposeWholeRecord(); showsSources = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(StudioQuietButtonStyle()).help("宽阅读 · 完整原注").accessibilityIdentifier("book-wide-reading")
            }
            BookOriginalText(text: originalComment, fontSize: originalFontSize)
                .accessibilityIdentifier("book-current-original-comment")
                .onAppear { exposeReference() }
        }
    }

    private var sourceTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            if guided && lesson.stage != .reading {
                Button {
                    if !showsOriginal { exposeReference(); if decision { lesson.revealAnswer() } }
                    showsOriginal.toggle()
                } label: {
                    HStack {
                        Label(decision ? "查看原注 · 记为辅助" : "相关原注与出处", systemImage: "text.book.closed")
                        Spacer(minLength: 0)
                        Image(systemName: showsOriginal ? "chevron.up" : "chevron.down")
                    }
                }.font(.system(size: 13, weight: .medium)).buttonStyle(StudioQuietButtonStyle())
                    .accessibilityIdentifier("book-toggle-original")
                if showsOriginal && !decision {
                    if !originalComment.isEmpty { originalExcerpt }
                    else { Text("这一节点没有文件原注。").font(.system(size: 13)).foregroundColor(Studio.muted) }
                }
            }
            HStack(spacing: 12) {
                Button("整谱原注") { exposeWholeRecord(); showsSources = true }
                    .accessibilityIdentifier("book-all-original-comments")
                Button("全部变招") { exposeWholeRecord(); showsVariations = true }
                    .accessibilityIdentifier("book-all-variations")
                Spacer(minLength: 0)
                fontControls
            }.font(.system(size: 12)).buttonStyle(StudioQuietButtonStyle()).foregroundColor(Studio.muted)
            Text("文件原文逐字保留；学习引导与引擎判断另行标明。")
                .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
        }
    }

    private var fontControls: some View {
        HStack(spacing: 4) {
            Button { originalFontSize = max(14, originalFontSize - 1) } label: { Text("A−").frame(width: 28, height: 28) }
                .accessibilityLabel("减小原注字号").accessibilityIdentifier("book-original-font-smaller")
            Button { originalFontSize = min(22, originalFontSize + 1) } label: { Text("A+").frame(width: 28, height: 28) }
                .accessibilityLabel("增大原注字号").accessibilityIdentifier("book-original-font-larger")
        }
    }

    @ViewBuilder private var comparisonChoices: some View {
        if !lesson.comparisonChoices.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                eyebrow("当前分歧 · 书中收录")
                ForEach(lesson.comparisonChoices) { choice in
                    Button { lesson.startComparison(nodeID: choice.id) } label: {
                        HStack {
                            Text(choice.isMainline ? "主线" : "变招").font(.system(size: 11)).foregroundColor(sage)
                            Text(choice.title).font(.system(size: 14, weight: .medium))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.turn.down.right").font(.system(size: 11))
                        }.padding(11).background(sage.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-compare-node-\(choice.id)")
                }
            }
        }
    }

    private var engineDetails: some View {
        DisclosureGroup("引擎对照 · 统一你方视角", isExpanded: $showsEngine) {
            VStack(alignment: .leading, spacing: 12) {
                if let assessment = lesson.assessment, guided {
                    if let before = assessment.beforeScore { scoreRow("走前首选评价", score: before) }
                    if let after = assessment.afterScore { scoreRow("你的走法之后", score: after) }
                    Text(assessment.detail).font(.system(size: 13)).foregroundColor(Studio.muted).lineSpacing(5)
                }
                if guided && !lesson.engineLines.isEmpty {
                    ForEach(lesson.engineLines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text("Top \(line.rank)").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.candidate(line.rank))
                            Text(line.pv.first.flatMap(Move.init(uci:)).map { (lesson.engineAnchorPosition ?? lesson.decisionPosition).notation(for: $0) } ?? "—")
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                            Text(scoreText(line.score)).font(.system(size: 12, design: .monospaced))
                        }
                    }
                    Text("候选来自本课走前局面；搜索深度 \(lesson.engineLines.map(\.depth).min() ?? 0)。")
                        .font(.system(size: 11)).foregroundColor(Studio.muted)
                } else if guided {
                    Button("计算本课 Top 3") { lesson.requestEngineCandidates() }
                        .buttonStyle(StudioButtonStyle(compact: true)).disabled(lesson.isThinking || !lesson.canStart)
                        .accessibilityIdentifier("book-engine-candidates")
                }
                if lesson.isThinking { thinkingStatus }
                Text("短时评价会随搜索加深变化；分数不是获胜概率。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                Button("带当前局面去分析") {
                    if guided { lesson.prepareForAnalysis(); onAnalyze(lesson.analysisPosition, lesson.studentSide) }
                    else {
                        exposeReference()
                        let side = lesson.selectedUnit?.recordID == book.selectedRecordID ? lesson.studentSide : book.position.sideToMove
                        onAnalyze(book.analysisPosition, side)
                    }
                }.buttonStyle(StudioButtonStyle(compact: true)).disabled(!canAnalyze)
                    .accessibilityIdentifier("book-analyze")
            }.padding(.top, 12)
        }.font(.system(size: 13, weight: .medium))
    }

    private var thinkingStatus: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在核验后果…").font(.system(size: 12)).foregroundColor(Studio.muted)
            Spacer(minLength: 0)
            Button("取消") { lesson.cancelEvaluation() }.font(.system(size: 12))
                .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-cancel-evaluation")
        }.padding(.vertical, 6)
    }

    private var primaryFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if guided {
                if decision {
                    Text(lesson.isThinking ? "可以取消分析，或回到判断前。" : "下一步：直接在棋盘落子")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(sage)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                        .accessibilityIdentifier("book-primary-action")
                } else {
                    Button {
                        if lesson.isThinking { lesson.cancelEvaluation() }
                        else { resetReferencePanels(); lesson.primaryAction() }
                    } label: {
                        HStack {
                            Text(lesson.isThinking ? "取消计算，保留局面" : lesson.primaryActionTitle).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.right")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(BookLearningPrimaryStyle())
                        .disabled(lesson.selectedUnit == nil)
                        .accessibilityIdentifier("book-primary-action")
                }
                Text(lesson.progressText).font(.system(size: 11)).foregroundColor(Studio.muted)
            } else {
                Button {
                    if book.canGoForward { book.forward() }
                    else { workspaceMode = .guided }
                } label: {
                    HStack {
                        Text(book.canGoForward ? (workspaceMode == .replay ? "看对方应招 / 下一手" : "读下一手") : "回到本课学习")
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(BookLearningPrimaryStyle())
                    .disabled(workspaceMode == .replay && book.canGoForward && !book.isAwaitingReply)
                    .accessibilityIdentifier("book-step-forward")
                if workspaceMode == .replay && book.canGoForward && !book.isAwaitingReply {
                    Text("轮到你，在棋盘重走原谱。").font(.system(size: 11)).foregroundColor(Studio.muted)
                }
            }
        }.padding(16).background(Studio.white)
            .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 0.7) }
    }

    private var stageTitle: String {
        switch lesson.stage {
        case .reading: return "01 / 阅读与目标"
        case .decision: return "02 / 关键点练习"
        case .feedback: return "02 / 你的选择与后果"
        case .comparison: return "03 / 比较变化"
        case .summary: return "04 / 本题小结"
        }
    }

    private func changeMode(_ mode: WorkspaceMode) {
        showsEngine = false
        if mode == .guided { book.setMode(.reading) }
        else {
            lesson.suspend()
            book.setMode(.reading)
            exposeWholeRecord()
            if mode == .replay { book.restart(); book.setMode(.recall) }
        }
    }

    private func resetReferencePanels() {
        showsOriginal = false; showsEngine = false; showsSources = false; showsVariations = false
    }

    private func selectUnit(_ id: String) {
        resetReferencePanels(); lesson.selectUnit(id: id); workspaceMode = .guided; showsRail = false
    }

    private func exposeReference() {
        lesson.markReadingExposed()
        if book.mode == .recall { book.revealReference() }
    }

    private func exposeWholeRecord() { lesson.markWholeRecordExposed() }

    private func openSourceNode(_ id: Int) {
        exposeReference(); lesson.suspend(); workspaceMode = .reading
        book.setMode(.reading); book.go(to: id)
        showsSources = false; showsVariations = false
    }

    private func sourceChoice(_ choice: BookMoveChoice) -> some View {
        Button { book.go(to: choice.id) } label: {
            HStack(spacing: 10) {
                Text(choice.isMainline ? "主线" : "变招").font(.system(size: 11)).foregroundColor(sage)
                Text(choice.title).font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11))
            }.padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-node-\(choice.id)")
    }

    private func evidenceRow(_ title: String, value: Int) -> some View {
        HStack { Text(title); Spacer(); Text("\(value) 次").monospacedDigit() }
            .font(.system(size: 14)).foregroundColor(Studio.muted)
    }
    private func scoreRow(_ title: String, score: EngineScore) -> some View {
        HStack { Text(title); Spacer(); Text(scoreText(score)).monospacedDigit() }.font(.system(size: 13))
    }
    private func scoreText(_ score: EngineScore) -> String {
        switch score {
        case .cp(let value): return String(format: "%+.2f", Double(value) / 100)
        case .mate(let value): return value > 0 ? "你方杀棋 \(abs(value))" : "你方被杀 \(abs(value))"
        }
    }
    private func eyebrow(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(sage)
    }
    private func readingText(_ text: String) -> some View {
        Text(text).font(.system(size: 15)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
    }
    private func notice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
            Text(message).font(.system(size: 12)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            Button { book.notice = nil; lesson.notice = nil } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                .buttonStyle(StudioQuietButtonStyle()).accessibilityLabel("关闭提示")
        }.foregroundColor(Studio.muted).padding(.horizontal, 20).padding(.vertical, 9).background(Studio.cream)
    }
    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            if book.isLoading { ProgressView("正在整理棋书与原注…") }
            else {
                StudioEmpty(symbol: "book.closed", title: "从一本棋书开始", detail: "导入 CBL，保留完整原注与变招；从当前内容继续读、练与复习。")
                Button("导入 CBL 棋书…") { book.importPanel() }.buttonStyle(StudioButtonStyle(primary: true))
                    .accessibilityIdentifier("book-import")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BookLearningPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 13)
            .foregroundColor(Studio.white)
            .background(Color(red: 83 / 255, green: 109 / 255, blue: 87 / 255), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle()).opacity(enabled ? configuration.isPressed ? 0.8 : 1 : 0.45)
    }
}

private struct BookLearningSourceSheet: View {
    @ObservedObject var book: BookStudyModel
    @Binding var fontSize: Double
    let onExpose: () -> Void
    let onChoose: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("整谱原注 · 宽阅读").font(.system(size: 21, weight: .semibold, design: .serif))
                    Text(book.record?.displayTitle ?? "原注").font(.system(size: 12)).foregroundColor(Studio.muted)
                }
                Spacer()
                Button("A−") { fontSize = max(14, fontSize - 1) }.accessibilityIdentifier("book-wide-font-smaller")
                Button("A+") { fontSize = min(22, fontSize + 1) }.accessibilityIdentifier("book-wide-font-larger")
                StudioIconButton(symbol: "xmark", label: "关闭宽阅读") { dismiss() }
                    .accessibilityIdentifier("book-close-wide-reading")
            }.buttonStyle(StudioQuietButtonStyle()).padding(22)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Text("按文件节点完整列出；原文中的繁体、标点、空白均不改写。点击节点标题可在棋盘定位。")
                        .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
                    ForEach(book.annotatedNodes) { note in
                        VStack(alignment: .leading, spacing: 11) {
                            Button { onChoose(note.id) } label: {
                                Label(note.title, systemImage: "scope").font(.system(size: 13, weight: .medium))
                            }.buttonStyle(StudioQuietButtonStyle()).foregroundColor(Studio.success)
                                .accessibilityIdentifier("book-original-node-\(note.id)")
                            BookOriginalText(text: note.comment, fontSize: fontSize)
                        }
                        Divider()
                    }
                    if book.annotatedNodes.isEmpty { Text("这份谱例没有文件原注。").foregroundColor(Studio.muted) }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(minWidth: 580, idealWidth: 740, maxWidth: 840, minHeight: 480, idealHeight: 650)
            .background(Studio.white).foregroundColor(Studio.ink).onAppear(perform: onExpose)
    }
}

private struct BookLearningVariationSheet: View {
    @ObservedObject var book: BookStudyModel
    let onExpose: () -> Void
    let onChoose: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var expanded = Set<Int>()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("全谱变招目录").font(.system(size: 21, weight: .semibold, design: .serif))
                Spacer()
                StudioIconButton(symbol: "xmark", label: "关闭变招目录") { dismiss() }
                    .accessibilityIdentifier("book-close-variations")
            }.padding(22)
            Text("\(book.branchPoints.count) 处分歧全部保留。主线与变招只表示文件结构，不代表引擎优劣。")
                .font(.system(size: 13)).foregroundColor(Studio.muted).padding(.horizontal, 22).padding(.bottom, 18)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(book.branchPoints) { branch in
                        DisclosureGroup(isExpanded: Binding(get: { expanded.contains(branch.id) }, set: { value in
                            if value { expanded.insert(branch.id) } else { expanded.remove(branch.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 14) {
                                Button("在棋盘定位这个分歧") { onChoose(branch.nodeID) }
                                    .font(.system(size: 13)).foregroundColor(Studio.success)
                                ForEach(branch.choices) { choice in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Button { onChoose(choice.id) } label: {
                                            Label("\(choice.isMainline ? "主线" : "变招") · \(choice.title)", systemImage: "arrow.turn.down.right")
                                                .font(.system(size: 14, weight: .medium))
                                        }.accessibilityIdentifier("book-node-\(choice.id)")
                                        if !choice.comment.isEmpty { BookOriginalText(text: choice.comment) }
                                    }
                                }
                            }.buttonStyle(StudioQuietButtonStyle()).padding(.top, 14)
                        } label: {
                            Text("\(branch.title) · \(branch.choices.count) 路").font(.system(size: 14, weight: .medium))
                        }
                        Divider()
                    }
                    if book.branchPoints.isEmpty {
                        Text("这份谱例没有收录其他分支。未收录不代表不存在其他合理走法。")
                            .font(.system(size: 15)).foregroundColor(Studio.muted)
                    }
                }.padding(24)
            }
        }.frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 650)
            .background(Studio.white).foregroundColor(Studio.ink).onAppear(perform: onExpose)
    }
}
