import SwiftUI

/// A private-book reader. Original commentary and the app's practice guidance
/// intentionally have separate surfaces and never share a text transform.
struct BookStudyWorkspace: View {
    @ObservedObject var model: BookStudyModel
    let onAnalyze: (Position) -> Void
    @State private var showContents = false
    @State private var inspectorTab = 0
    @State private var showAllNotes = false
    @State private var showIntroduction = false
    @State private var showGuidance = false
    @State private var expandedBranches = Set<Int>()

    var body: some View {
        GeometryReader { geometry in
            let showsContents = geometry.size.width >= 1120
            VStack(spacing: 0) {
                header(showsContents: showsContents)
                if let notice = model.notice { noticeBanner(notice) }
                HStack(spacing: 0) {
                    if showsContents {
                        BookContentsView(model: model).frame(width: 240)
                        Rectangle().fill(Studio.line).frame(width: 0.7)
                    }
                    if model.record != nil {
                        readingDesk(width: geometry.size.width - (showsContents ? 240 : 0))
                    } else {
                        VStack(spacing: 18) {
                            StudioEmpty(symbol: "book.closed", title: "把棋书放到棋盘上", detail: "导入 CBL，按章节看原注、走主线、试变招。")
                            Button("导入 CBL 棋书…") { model.importPanel() }
                                .buttonStyle(StudioButtonStyle(primary: true))
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .foregroundColor(Studio.ink).background(Studio.paper).tint(Studio.accent).preferredColorScheme(.light)
        .overlay {
            if model.isLoading {
                ZStack {
                    Studio.paper.opacity(0.72)
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("正在整理棋书与原注…").font(.system(size: 13))
                    }.padding(28).background(Studio.white, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onChange(of: model.selectedRecordID) { _ in resetInspector() }
        .onChange(of: model.mode) { _ in resetInspector() }
    }

    private var maySeeReference: Bool { model.mode == .reading || model.referenceRevealed }

    private func header(showsContents: Bool) -> some View {
        HStack(spacing: 14) {
            if !showsContents {
                Button { showContents.toggle() } label: {
                    Label("目录", systemImage: "sidebar.left")
                }.buttonStyle(StudioButtonStyle(compact: true))
                    .accessibilityIdentifier("book-show-contents")
                    .popover(isPresented: $showContents, arrowEdge: .bottom) {
                        BookContentsView(model: model, onChoose: { showContents = false })
                            .frame(width: 320, height: 620)
                    }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.record?.sectionTitle ?? "棋书学习")
                    .font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(1)
                Text(model.record?.displayTitle ?? model.document?.title ?? "我的棋书")
                    .font(.system(size: 20, weight: .semibold, design: .serif)).lineLimit(2)
                    .help(model.record?.title ?? "")
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let record = model.record {
                let progress = model.status(for: record.id)
                recordControls
                StudioIconButton(symbol: progress.bookmarked ? "bookmark.fill" : "bookmark", label: "收藏当前谱例", active: progress.bookmarked) {
                    model.toggleBookmark()
                }.accessibilityIdentifier("book-bookmark")
                Button { model.markRead() } label: {
                    Label(progress.read ? "已读" : "标为已读", systemImage: progress.read ? "checkmark.circle.fill" : "checkmark.circle")
                }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("book-mark-read")
                    .help("只记录读过，不代表已掌握这篇内容")
            }
        }.padding(.horizontal, 20).padding(.vertical, 15).background(Studio.white)
            .overlay(alignment: .bottom) { Rectangle().fill(Studio.line).frame(height: 0.7) }
    }

    private func readingDesk(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                if !model.isTextOnly { modePicker }
                if model.isTextOnly { textOnlyPage }
                else {
                    boardStatus
                    GeometryReader { area in
                        let boardWidth = max(0, min(area.size.width, area.size.height * BoardView.Layout.aspectRatio))
                        BoardView(position: model.position, flipped: model.flipped, selected: model.selected,
                                  targets: model.targets, lastMove: model.lastMove, arrows: model.arrows,
                                  arrowContext: "原谱", onTap: model.tap)
                            .frame(width: boardWidth, height: boardWidth / BoardView.Layout.aspectRatio)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    moveControls
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            inspector.frame(width: width >= 1160 ? 350 : 306)
        }.padding(18)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                modeButton("读谱", symbol: "book", mode: .reading)
                modeButton("自己走", symbol: "hand.draw", mode: .recall)
                Spacer(minLength: 0)
                if model.mode == .recall {
                    Button("退出练习") { model.setMode(.reading) }
                        .font(.system(size: 11)).buttonStyle(StudioQuietButtonStyle())
                        .accessibilityIdentifier("book-exit-recall")
                }
            }
            Text(model.mode == .reading ? "读谱：逐步看原注，随时进入书里的变化。" : "自己走：你在棋盘落子，再与原谱核对；不是引擎判分。")
                .font(.system(size: 11)).foregroundColor(Studio.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeButton(_ title: String, symbol: String, mode: BookStudyMode) -> some View {
        Button { model.setMode(mode) } label: {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .foregroundColor(model.mode == mode ? Studio.onAccent : Studio.muted)
                .background(model.mode == mode ? Studio.accent : Studio.white, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(StudioQuietButtonStyle()).disabled(mode == .recall && !model.canPractice)
            .accessibilityIdentifier(mode == .reading ? "book-mode-reading" : "book-mode-recall")
            .accessibilityValue(model.mode == mode ? "已选择" : "未选择")
    }

    private var boardStatus: some View {
        HStack(spacing: 8) {
            Circle().fill(model.position.sideToMove == .red ? Studio.red : Studio.ink).frame(width: 7, height: 7)
            Text("\(model.position.sideToMove.label)行棋").font(.system(size: 12, weight: .semibold))
            Spacer()
            if model.currentPly > 0 && !model.canGoForward && model.positionIssue == nil {
                StudioTag(text: "线路末尾", color: Studio.success)
            }
            Text(model.currentPly == 0 ? "起始局面" : "第 \(model.currentPly) 手")
                .font(.system(size: 11)).foregroundColor(Studio.muted).monospacedDigit()
            StudioIconButton(symbol: "arrow.triangle.2.circlepath", label: "翻转棋盘") { model.flipped.toggle() }
        }.frame(height: 30)
    }

    @ViewBuilder private var feedback: some View {
        if let issue = model.positionIssue {
            Label(issue, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12)).foregroundColor(Studio.red)
                .fixedSize(horizontal: false, vertical: true).padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Studio.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        } else if !model.feedback.isEmpty {
            Text(model.feedback).font(.system(size: 12)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Studio.white, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("book-move-feedback")
        }
    }

    private var moveControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Button { model.back() } label: {
                    Label(model.mode == .recall ? "悔棋" : "上一步", systemImage: "chevron.left")
                }.buttonStyle(StudioButtonStyle(compact: true)).disabled(!model.canGoBack)
                    .accessibilityIdentifier("book-step-back")
                Spacer(minLength: 0)
                if model.mode == .recall && !model.isAwaitingReply {
                    Button { model.hint() } label: { Label("提示", systemImage: "lightbulb") }
                        .buttonStyle(StudioButtonStyle(compact: true)).disabled(!model.canPractice)
                        .accessibilityIdentifier("book-hint")
                } else {
                    Button { model.forward() } label: {
                        Label(model.mode == .recall ? "看对方应招" : "下一步", systemImage: "chevron.right")
                    }.buttonStyle(StudioButtonStyle(primary: true, compact: true)).disabled(!model.canGoForward)
                        .accessibilityIdentifier("book-step-forward")
                }
            }
            HStack(spacing: 14) {
                Button("回本谱起点") { returnToBookStart(thenPractice: model.mode == .recall) }
                    .accessibilityIdentifier("book-restart")
                Button("回分歧点") { model.backToBranch() }
                    .disabled(model.currentPly == 0).accessibilityIdentifier("book-return-fork")
                Spacer(minLength: 0)
                Button(model.mode == .recall ? "重走本谱" : "我来重走") {
                    returnToBookStart(thenPractice: true)
                }.disabled(model.record?.isReadingOnly != false).accessibilityIdentifier("book-replay")
            }.font(.system(size: 11)).buttonStyle(StudioQuietButtonStyle())
                .padding(.vertical, 4)
        }.padding(12).background(Studio.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private var recordControls: some View {
        HStack(spacing: 5) {
            Button { model.previousRecord() } label: { Label("上一篇", systemImage: "chevron.left") }
                .buttonStyle(StudioButtonStyle(compact: true)).fixedSize()
                .disabled(!model.canGoPreviousRecord).accessibilityIdentifier("book-previous-record")
            Button { model.nextRecord() } label: { Label("下一篇", systemImage: "chevron.right") }
                .buttonStyle(StudioButtonStyle(compact: true)).fixedSize()
                .disabled(model.nextRecordTitle == nil)
                .help(model.nextRecordTitle ?? "已到本书最后一篇")
                .accessibilityIdentifier("book-next-record")
        }
    }

    private var textOnlyPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("文件原文 · 导读", systemImage: "text.book.closed")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.muted)
                if let record = model.record {
                    ForEach(record.nodes.filter { !$0.comment.isEmpty }, id: \.id) { node in
                        BookOriginalText(text: node.comment)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }.background(Studio.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                inspectorButton("文件原注", tab: 0)
                inspectorButton("变招目录", tab: 1)
                Spacer(minLength: 0)
                if model.guide != nil {
                    StudioIconButton(symbol: "signpost.right", label: "本节目标与前后衔接", active: showGuidance) {
                        showGuidance.toggle()
                    }.accessibilityIdentifier("book-learning-guidance")
                }
            }.padding(.horizontal, 16).padding(.top, 5)
            Rectangle().fill(Studio.line.opacity(0.65)).frame(height: 0.7)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("book-inspector-top")
                        LazyVStack(alignment: .leading, spacing: 18) {
                            practiceContext
                            if showGuidance && !model.isTextOnly { guidance }
                            if inspectorTab == 0 { originalNotes }
                            else { variationDirectory }
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.id("\(model.selectedRecordID ?? "")-\(inspectorTab)")
                    .onChange(of: model.nodeID) { _ in
                        if inspectorTab == 0 && !showAllNotes { proxy.scrollTo("book-inspector-top", anchor: .top) }
                    }
            }
            Divider().overlay(Studio.line)
            HStack {
                Text("皮卡鱼分析与原书观点分开显示")
                    .font(.system(size: 10)).foregroundColor(Studio.muted)
                Spacer(minLength: 0)
                Button("分析局面") {
                    if model.mode == .recall { model.revealReference() }
                    onAnalyze(model.analysisPosition)
                }
                    .font(.system(size: 11, weight: .medium)).buttonStyle(StudioQuietButtonStyle())
                    .disabled(!model.canAnalyze).accessibilityIdentifier("book-analyze")
            }.padding(14)
        }.frame(maxHeight: .infinity).background(Studio.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Studio.line.opacity(0.6), lineWidth: 0.7).allowsHitTesting(false))
    }

    @ViewBuilder private var practiceContext: some View {
        if model.guide != nil || !model.feedback.isEmpty || model.positionIssue != nil {
            VStack(alignment: .leading, spacing: 11) {
                if let guide = model.guide, !model.isTextOnly {
                    Button { showGuidance.toggle() } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Label("本节目标", systemImage: "signpost.right")
                                    .font(.system(size: 10, weight: .semibold)).foregroundColor(Studio.accent)
                                Spacer()
                                Image(systemName: showGuidance ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9)).foregroundColor(Studio.muted)
                            }
                            Text(guide.goal).font(.system(size: 12)).foregroundColor(Studio.ink).lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }.buttonStyle(StudioQuietButtonStyle()).help("展开完整目标、前后联系与迁移练习")
                }
                if !model.feedback.isEmpty || model.positionIssue != nil {
                    Text("伴练反馈 · 非原书文字").font(.system(size: 10, weight: .medium)).foregroundColor(Studio.muted)
                    feedback
                }
            }.padding(12).background(Studio.paper, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func inspectorButton(_ title: String, tab: Int) -> some View {
        Button { inspectorTab = tab } label: {
            Text(title).font(.system(size: 12, weight: inspectorTab == tab ? .semibold : .regular))
                .foregroundColor(inspectorTab == tab ? Studio.accent : Studio.muted)
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    if inspectorTab == tab { Capsule().fill(Studio.accent).frame(height: 2) }
                }.contentShape(Rectangle())
        }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-inspector-\(tab)")
    }

    @ViewBuilder private var originalNotes: some View {
        if let record = model.record {
            if record.isSupplement {
                Label("补充资料：不与原书正文混称", systemImage: "doc.badge.plus")
                    .font(.system(size: 11)).foregroundColor(Studio.gold)
            }
            if model.isTextOnly {
                Text("本篇是文字导读，完整原文在左侧。")
                    .font(.system(size: 13)).foregroundColor(Studio.muted)
                guidance
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.currentPly == 0 ? "本谱导读" : "当前着法原注")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.muted)
                    if !maySeeReference {
                        Text("原注可能包含后续答案，自己走时先收起。")
                            .font(.system(size: 12)).foregroundColor(Studio.muted)
                        revealButton
                    } else if let node = model.currentNode, !node.comment.isEmpty {
                        BookOriginalText(text: node.comment).accessibilityIdentifier("book-current-original-comment")
                    } else {
                        Text("文件未给这一位置附注。")
                            .font(.system(size: 12)).foregroundColor(Studio.muted)
                    }
                }
                if model.currentPly > 0, let root = record.nodes.first(where: { $0.id == record.rootNodeID }), !root.comment.isEmpty {
                    DisclosureGroup("本谱导读", isExpanded: $showIntroduction) {
                        if maySeeReference {
                            BookOriginalText(text: root.comment).padding(.top, 10)
                        } else { revealButton.padding(.top, 10) }
                    }.font(.system(size: 12, weight: .medium))
                }
                if maySeeReference { nextChoices }
                else if model.isAwaitingReply { nextChoices }
                Divider()
                Button {
                    if !maySeeReference { model.revealReference() }
                    showAllNotes.toggle()
                } label: {
                    HStack {
                        Label(showAllNotes ? "收起整谱原注" : "整谱原注 · \(record.nodes.lazy.filter { !$0.comment.isEmpty }.count) 段", systemImage: "text.alignleft")
                        Spacer(minLength: 0)
                        Image(systemName: showAllNotes ? "chevron.up" : "chevron.down").font(.system(size: 10))
                    }.font(.system(size: 12, weight: .medium)).padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-all-original-comments")
                if showAllNotes && maySeeReference {
                    Text("按文件树顺序列出；点位置可回到对应棋面。")
                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                    ForEach(model.annotatedNodes, id: \.id) { note in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { model.go(to: note.id) } label: {
                                Label(note.title, systemImage: "arrow.up.left.square")
                                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.accent)
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(StudioQuietButtonStyle())
                            BookOriginalText(text: note.comment)
                        }.padding(.vertical, 9)
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder private var nextChoices: some View {
        if !model.choices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.isAwaitingReply ? "书中收录的对方应招" : "从这里继续")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.muted)
                ForEach(model.choices, id: \.id) { choice in
                    choiceButton(choice, showsComment: false)
                }
            }
        } else if model.currentPly > 0 {
            Text("已到这条变化的末尾，可回分歧点比较另一条。")
                .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(4)
        }
    }

    @ViewBuilder private var variationDirectory: some View {
        if !maySeeReference {
            Text("自己走时先隐藏后续着法。主动打开后，本轮会记为看过参考。")
                .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
            revealButton
        } else {
            let branches = model.branchPoints
            if !model.breadcrumb.isEmpty {
                DisclosureGroup("当前路线 · \(model.breadcrumb.count) 手") {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(model.breadcrumb, id: \.id) { choice in choiceButton(choice, showsComment: false) }
                    }.padding(.top, 8)
                }.font(.system(size: 12, weight: .medium))
            }
            Text("全谱分歧点 · \(branches.count) 处")
                .font(.system(size: 12, weight: .semibold))
            if branches.isEmpty {
                Text("这份谱例没有录入其他分支。未收录不代表没有其他好走法。")
                    .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
            }
            ForEach(branches, id: \.id) { branch in
                VStack(alignment: .leading, spacing: 9) {
                    Button {
                        if expandedBranches.contains(branch.id) { expandedBranches.remove(branch.id) }
                        else { expandedBranches.insert(branch.id) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: expandedBranches.contains(branch.id) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                            Text(branch.title).font(.system(size: 12, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Text("\(branch.choices.count) 路").font(.system(size: 10)).foregroundColor(Studio.muted)
                        }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-fork-\(branch.id)")
                    Text(branchContext(branch.nodeID)).font(.system(size: 10)).foregroundColor(Studio.muted)
                    if expandedBranches.contains(branch.id) {
                        Button("回到这个分歧点") { model.go(to: branch.nodeID) }
                            .font(.system(size: 11)).buttonStyle(StudioQuietButtonStyle()).foregroundColor(Studio.accent)
                        ForEach(branch.choices, id: \.id) { choice in choiceButton(choice, showsComment: true) }
                    }
                }.padding(12).background(Studio.paper, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func choiceButton(_ choice: BookMoveChoice, showsComment: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.go(to: choice.id) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(choice.isMainline ? "主" : "变").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(choice.isMainline ? Studio.accent : Studio.cyan)
                        .frame(width: 23, height: 23)
                        .background((choice.isMainline ? Studio.accent : Studio.cyan).opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    Text(choice.title).font(.system(size: 12, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(Studio.muted)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Studio.cream.opacity(0.35), in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
            }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("book-node-\(choice.id)")
            if showsComment && !choice.comment.isEmpty {
                BookOriginalText(text: choice.comment).padding(.horizontal, 3)
            }
        }
    }

    private var revealButton: some View {
        Button("查看完整参考 · 记录为辅助") { model.revealReference() }
            .buttonStyle(StudioButtonStyle(compact: true))
            .accessibilityIdentifier("book-reveal-reference")
    }

    @ViewBuilder private var guidance: some View {
        if let guide = model.guide {
            VStack(alignment: .leading, spacing: 12) {
                Label("伴练衔接 · 非原书文字", systemImage: "signpost.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(Studio.accent)
                Text(guide.title).font(.system(size: 15, weight: .semibold))
                guidanceLine("这一节", text: guide.goal)
                guidanceLine("前后联系", text: guide.connection)
                guidanceLine("落子前", text: guide.practicePrompt)
                guidanceLine("换个局面", text: guide.transferPrompt)
            }.padding(14).background(Studio.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func guidanceLine(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(Studio.muted)
            Text(text).font(.system(size: 12)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundColor(Studio.accent)
            Text(notice).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.notice = nil } label: {
                Image(systemName: "xmark").frame(width: 24, height: 24).contentShape(Rectangle())
            }.buttonStyle(StudioQuietButtonStyle()).help("关闭提示")
        }.padding(.horizontal, 20).padding(.vertical, 10).background(Studio.cream)
    }

    private func resetInspector() {
        inspectorTab = 0; showAllNotes = false; showIntroduction = false; expandedBranches.removeAll()
    }

    private func branchContext(_ id: Int) -> String {
        guard let record = model.record else { return "" }
        let depth = model.path(to: id).dropFirst().reduce(0) { count, nodeID in
            guard record.nodes.indices.contains(nodeID), let parent = record.nodes[nodeID].parentID,
                  record.nodes.indices.contains(parent) else { return count }
            return count + (record.nodes[parent].childIDs.first == nodeID ? 0 : 1)
        }
        return depth == 0 ? "主线中的分歧" : "变招内的分歧 · 嵌套 \(depth) 层"
    }

    private func returnToBookStart(thenPractice: Bool) {
        // restart() deliberately means the current practice anchor in recall
        // mode. These controls explicitly promise the book record's root.
        model.setMode(.reading)
        model.restart()
        if thenPractice { model.setMode(.recall) }
        resetInspector()
    }
}

/// Text(verbatim:) prevents accidental Markdown interpretation. In particular,
/// do not apply simplifiedForDisplay, trimming, summary, or lineLimit here.
struct BookOriginalText: View {
    let text: String
    var fontSize: CGFloat = 15
    var body: some View {
        Text(verbatim: text).font(.system(size: fontSize)).lineSpacing(7)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
