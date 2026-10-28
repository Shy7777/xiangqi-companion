import SwiftUI
import AppKit

/// Every route owns its complete sequence from its actual fork position. An
/// original continuation is never appended to a different variation position.
struct VariationCanvasBranch: Identifiable {
    let id: String
    let variationID: String?
    let anchorPly: Int
    let title: String
    let condition: String
    let explanation: String
    let moves: [StudyMove]
    let positions: [Position]
    let ordinal: Int
    var isOriginal: Bool { variationID == nil }
    var accent: Color { isOriginal ? Studio.gold : ordinal.isMultiple(of: 2) ? Studio.color(.strategy) : Studio.green }
    func move(at ply: Int) -> Move? { moves.indices.contains(ply - 1) ? Move(uci: moves[ply - 1].uci) : nil }
    func notation(at ply: Int) -> String {
        guard positions.indices.contains(ply - 1), let move = move(at: ply) else { return "分歧点" }
        return positions[ply - 1].notation(for: move)
    }
}

struct VariationCanvasGroup: Identifiable {
    var id: Int { anchorPly }
    let anchorPly: Int
    let branches: [VariationCanvasBranch]
}

struct VariationCanvasGraph {
    let groups: [VariationCanvasGroup]
    let unavailableCount: Int
    var branches: [VariationCanvasBranch] { groups.flatMap(\.branches) }

    init(parent: StudyLine) {
        guard let original = try? parent.positions() else {
            groups = []; unavailableCount = parent.variations?.count ?? 0; return
        }
        var valid: [(StudyVariation, [Position])] = []
        var unavailable = 0, seen = Set<String>()
        for variation in parent.variations ?? [] {
            guard seen.insert(variation.id).inserted,
                  let positions = try? variation.positions(parent: parent, parentPositions: original) else {
                unavailable += 1; continue
            }
            valid.append((variation, positions))
        }
        groups = Set(valid.map { $0.0.anchorPly }).sorted().map { anchor in
            let reference = parent.id == LibraryGeneratedStudy.lineID ? "引擎参考线" : "原谱"
            var branches = [VariationCanvasBranch(
                id: "original-\(anchor)", variationID: nil, anchorPly: anchor,
                title: reference + "继续", condition: "从\(reference)已走 \(anchor) 半回合的位置继续。",
                explanation: parent.adaptation, moves: Array(parent.moves.dropFirst(anchor)),
                positions: Array(original.dropFirst(anchor)), ordinal: 0)]
            for (index, item) in valid.filter({ $0.0.anchorPly == anchor }).enumerated() {
                let variation = item.0
                branches.append(VariationCanvasBranch(
                    id: "variation-\(variation.id)", variationID: variation.id, anchorPly: anchor,
                    title: variation.title, condition: variation.condition, explanation: variation.explanation,
                    moves: variation.moves, positions: item.1, ordinal: index + 1))
            }
            return VariationCanvasGroup(anchorPly: anchor, branches: branches)
        }
        unavailableCount = unavailable
    }
}

enum VariationCanvasCursor {
    static func restore(saved: Int?, aligning current: Int, moveCount: Int) -> Int {
        min(max(0, moveCount), max(0, saved ?? current))
    }
}

/// The sheet only changes its own route/cursor. Answer exposure is recorded
/// before any board or move nodes become visible, including during a test.
struct VariationStudyView: View {
    let request: VariationPreviewRequest
    @ObservedObject var model: LearningModel
    private var referenceLabel: String { request.lessonID.hasPrefix("library-") ? "引擎参考线" : "原谱" }
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBranchID: String
    @State private var cursors: [String: Int]
    @State private var flipped: Bool
    @State private var exposureRecorded = false
    @State private var showCoordinates = false
    @State private var lastVariationByAnchor: [Int: String] = [:]
    // Build the legal-position graph once when the sheet actually opens, not
    // while its presenting view is being recomputed after every board tap.
    @State private var graph: VariationCanvasGraph?
    private let preferredSize: CGSize

    init(request: VariationPreviewRequest, model: LearningModel) {
        self.request = request; self._model = ObservedObject(wrappedValue: model)
        let variationID = "variation-\(request.variation.id)"
        let initial = request.preferOriginal ? "original-\(request.variation.anchorPly)" : variationID
        _selectedBranchID = State(initialValue: initial)
        let length = request.preferOriginal ? max(0, request.parent.moves.count - request.variation.anchorPly) : request.variation.moves.count
        _cursors = State(initialValue: [initial: min(length, max(0, request.initialPly))])
        _lastVariationByAnchor = State(initialValue: [request.variation.anchorPly: variationID])
        _flipped = State(initialValue: request.parent.studentSide == .black)
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 850)
        let window = NSApp.keyWindow?.contentLayoutRect.size ?? screen
        preferredSize = CGSize(width: min(1140, max(620, min(window.width - 30, screen.width - 60))),
                               height: min(790, max(450, min(window.height - 45, screen.height - 110))))
    }

    private var selectedBranch: VariationCanvasBranch? { graph?.branches.first { $0.id == selectedBranchID } }
    private var cursor: Int { selectedBranch.map { cursor(for: $0) } ?? 0 }
    private var shownPosition: Position? {
        guard let branch = selectedBranch, branch.positions.indices.contains(cursor) else { return nil }
        return branch.positions[cursor]
    }
    private var compareBinding: Binding<Bool> {
        Binding(get: { selectedBranch?.isOriginal == true }, set: { original in compare(original: original) })
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                heading(compact: geometry.size.width < 800)
                Divider().overlay(Studio.line.opacity(0.5))
                if exposureRecorded, selectedBranch != nil {
                    HStack(spacing: 0) {
                        boardWorkspace.padding(geometry.size.width < 800 ? 12 : 20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Rectangle().fill(Studio.line.opacity(0.6)).frame(width: 1)
                        branchCanvas.frame(width: min(370, max(285, geometry.size.width * 0.34)))
                    }.frame(maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 30)).foregroundColor(Studio.muted)
                        Text("当前课程的变式暂不可用").font(.system(size: 16, weight: .medium))
                        Text("只有通过规则校验、且能记录学习辅助的真实分支才会显示。请关闭后重新进入课程。")
                            .font(.system(size: 12)).foregroundColor(Studio.muted).multilineTextAlignment(.center).frame(maxWidth: 360)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
                }
                Divider().overlay(Studio.line.opacity(0.5))
                actionDock(compact: geometry.size.width < 800)
            }.background(Studio.paper).foregroundColor(Studio.ink)
        }
        .frame(minWidth: 620, idealWidth: preferredSize.width, maxWidth: preferredSize.width,
               minHeight: 450, idealHeight: preferredSize.height, maxHeight: preferredSize.height)
        .onAppear {
            exposureRecorded = model.recordVariationExposure(lessonID: request.lessonID, lineID: request.parent.id)
            if exposureRecorded && graph == nil { graph = VariationCanvasGraph(parent: request.parent) }
        }
        .onChange(of: model.store.data.resume?.runID) { _ in
            if exposureRecorded { exposureRecorded = model.recordVariationExposure(lessonID: request.lessonID, lineID: request.parent.id) }
        }
    }

    private func heading(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Text("变招推演").font(.system(size: compact ? 18 : 21, weight: .semibold, design: .serif))
            Text(request.parent.title.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineLimit(1)
            Spacer(minLength: 6)
            StudioIconButton(symbol: "xmark", label: "关闭变招推演") { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(.horizontal, 20).padding(.vertical, 9).background(Studio.white)
    }

    private var boardWorkspace: some View {
        VStack(spacing: 10) {
            if let branch = selectedBranch {
                HStack(alignment: .top, spacing: 8) {
                    Text(branch.isOriginal ? referenceLabel : "变招").font(.system(size: 12, weight: .semibold)).foregroundColor(branch.accent)
                    Spacer(minLength: 4)
                    if let position = shownPosition { StudioTag(text: "\(position.sideToMove.label)行棋", color: position.sideToMove == .red ? Studio.red : Studio.muted) }
                }
                GeometryReader { geometry in
                    let width = max(0, min(geometry.size.width, geometry.size.height * 9.15 / 10.25))
                    if let position = shownPosition {
                        BoardView(position: position, flipped: flipped, lastMove: branch.move(at: cursor),
                                  studyCoordinates: showCoordinates, onTap: { _ in })
                            .frame(width: width, height: width * 10.25 / 9.15)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 7) {
                    Text(cursor == 0 ? "分歧前 · \(referenceLabel)已走 \(branch.anchorPly) 半回合" : "\(cursor). \(branch.notation(at: cursor))")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1).accessibilityIdentifier("variation-current-move")
                    Spacer(minLength: 2)
                    Text("\(cursor) / \(branch.moves.count)").font(.system(size: 11, design: .monospaced)).foregroundColor(Studio.muted)
                        .accessibilityLabel(branch.isOriginal ? referenceLabel + "剩余部分进度" : "独立变式进度")
                        .accessibilityValue("\(cursor) / \(branch.moves.count) 半回合")
                }
                transport
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            StudioIconButton(symbol: "backward.end", label: "回到分歧点") { setCursor(0) }
                .accessibilityIdentifier("variation-anchor")
            StudioIconButton(symbol: "chevron.left", label: "变式上一步") { setCursor(cursor - 1) }
                .disabled(cursor == 0).keyboardShortcut(.leftArrow, modifiers: [])
            StudioProgress(value: Double(cursor) / Double(max(1, selectedBranch?.moves.count ?? 1)), color: selectedBranch?.accent ?? Studio.green)
            StudioIconButton(symbol: "chevron.right", label: "变式下一步") { setCursor(cursor + 1) }
                .disabled(cursor >= (selectedBranch?.moves.count ?? 0)).keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityIdentifier("variation-next")
            StudioIconButton(symbol: "arrow.triangle.2.circlepath", label: "翻转变式棋盘") { flipped.toggle() }
            StudioIconButton(symbol: "number", label: "研究坐标", active: showCoordinates) { showCoordinates.toggle() }
        }.frame(height: 36)
    }

    private var branchCanvas: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("应招比较").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(graph?.groups.count ?? 0) 个分歧点").font(.system(size: 10)).foregroundColor(Studio.muted)
            }.padding(.horizontal, 17).padding(.top, 17).padding(.bottom, 8)
            Picker("对比路线", selection: compareBinding) {
                Text("变招").tag(false)
                Text(referenceLabel).tag(true)
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("variation-compare")
                .padding(.horizontal, 17).padding(.bottom, 15).help("每条路线保留各自的浏览位置。")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(graph?.groups ?? []) { group in canvasGroup(group).id("fork-\(group.id)") }
                        if let graph, graph.unavailableCount > 0 {
                            Text("\(graph.unavailableCount) 条未通过验证的分支未展示。")
                                .font(.system(size: 11)).foregroundColor(Studio.red)
                        }
                    }.padding(.horizontal, 15).padding(.bottom, 20)
                }
                .onAppear {
                    if let anchor = selectedBranch?.anchorPly { proxy.scrollTo("fork-\(anchor)", anchor: .top) }
                }
            }
        }.background(Studio.white.opacity(0.5))
    }

    private func canvasGroup(_ group: VariationCanvasGroup) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Button {
                if let branch = group.branches.first { select(branch, at: 0) }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 11)).frame(width: 23, height: 23)
                        .background(Studio.gold.opacity(0.12), in: Circle())
                    Text("\(referenceLabel)第 \(group.anchorPly) 半回合后分歧")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                }.foregroundColor(Studio.gold)
            }.buttonStyle(.plain).accessibilityIdentifier("variation-fork-\(group.anchorPly)")
            VStack(spacing: 11) {
                ForEach(group.branches) { branch in
                    HStack(spacing: 0) {
                        Rectangle().fill(branch.accent.opacity(0.5)).frame(width: 17, height: 1)
                        VariationCanvasCard(branch: branch, cursor: cursor(for: branch), selected: branch.id == selectedBranchID, flipped: flipped,
                                            selectBranch: { select(branch, at: cursors[branch.id] ?? min(1, branch.moves.count)) },
                                            selectNode: { select(branch, at: $0) })
                    }.id(branch.id)
                }
            }.padding(.leading, 11)
                .overlay(alignment: .leading) { Rectangle().fill(Studio.line).frame(width: 1).padding(.leading, 11) }
        }
    }

    private func actionDock(compact: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(exposureRecorded ? "辅助已记录" : "尚未开始推演", systemImage: "eye")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(exposureRecorded ? Studio.gold : Studio.muted)
                Text("关闭回原位").font(.system(size: 10)).foregroundColor(Studio.muted)
            }
            Spacer(minLength: 4)
            Button(compact ? "从这里陪练" : "从当前分支局面陪练") { beginGame() }
                .buttonStyle(StudioButtonStyle(primary: true))
                .disabled(!exposureRecorded || shownPosition == nil || model.busy)
                .accessibilityIdentifier("variation-play")
        }.padding(.horizontal, 20).padding(.vertical, 14).background(Studio.white)
    }

    private func cursor(for branch: VariationCanvasBranch) -> Int { min(branch.moves.count, max(0, cursors[branch.id] ?? min(1, branch.moves.count))) }
    private func setCursor(_ ply: Int) {
        guard let branch = selectedBranch else { return }
        cursors[branch.id] = min(branch.moves.count, max(0, ply))
    }
    private func select(_ branch: VariationCanvasBranch, at ply: Int) {
        guard exposureRecorded else { return }
        selectedBranchID = branch.id; cursors[branch.id] = min(branch.moves.count, max(0, ply))
        if !branch.isOriginal { lastVariationByAnchor[branch.anchorPly] = branch.id }
    }
    private func compare(original: Bool) {
        guard let current = selectedBranch, let group = graph?.groups.first(where: { $0.anchorPly == current.anchorPly }) else { return }
        let route = original ? group.branches.first(where: \.isOriginal) :
            group.branches.first(where: { $0.id == lastVariationByAnchor[current.anchorPly] }) ?? group.branches.first(where: { !$0.isOriginal })
        if let route {
            select(route, at: VariationCanvasCursor.restore(saved: cursors[route.id], aligning: cursor, moveCount: route.moves.count))
        }
    }
    private func beginGame() {
        guard exposureRecorded, let branch = selectedBranch, let position = shownPosition,
              model.recordVariationExposure(lessonID: request.lessonID, lineID: request.parent.id) else { return }
        if let variationID = branch.variationID {
            if model.startVariationGame(lessonID: request.lessonID, lineID: request.parent.id, variationID: variationID,
                                        ply: cursor, player: position.sideToMove) { dismiss() }
        } else {
            model.startGame(from: position, player: position.sideToMove)
            dismiss()
        }
    }
}

private struct VariationCanvasCard: View {
    let branch: VariationCanvasBranch
    let cursor: Int
    let selected: Bool
    let flipped: Bool
    let selectBranch: () -> Void
    let selectNode: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: selectBranch) {
                HStack(alignment: .top, spacing: 11) {
                    if branch.positions.indices.contains(cursor) {
                        BoardPreview(position: branch.positions[cursor], flipped: flipped, lastMove: branch.move(at: cursor), width: 78)
                            .accessibilityHidden(true)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(branch.isOriginal ? "参考主线" : "分支 \(branch.ordinal)").font(.system(size: 9, weight: .semibold)).foregroundColor(branch.accent)
                        Text(branch.title.simplifiedForDisplay).font(.system(size: 12, weight: .semibold)).foregroundColor(Studio.ink).lineLimit(2)
                        Text(branch.condition.simplifiedForDisplay).font(.system(size: 10)).foregroundColor(Studio.muted).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundColor(selected ? branch.accent : Studio.line)
                        .font(.system(size: 13))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("variation-branch-\(branch.id)")
                .accessibilityLabel("\(branch.title.simplifiedForDisplay)，\(branch.moves.count) 半回合，\(selected ? "已选择" : "切换路线")")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 5) {
                        ForEach(0...branch.moves.count, id: \.self) { ply in
                            Button { selectNode(ply) } label: {
                                Text(ply == 0 ? "分歧点" : "\(ply) \(branch.notation(at: ply))")
                                    .font(.system(size: 10, weight: selected && cursor == ply ? .semibold : .regular))
                                    .foregroundColor(selected && cursor == ply ? branch.accent : Studio.muted)
                                    .padding(.horizontal, 8).padding(.vertical, 7)
                                    .background(selected && cursor == ply ? branch.accent.opacity(0.13) : Studio.paper, in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected && cursor == ply ? branch.accent.opacity(0.6) : Studio.line.opacity(0.4), lineWidth: 1))
                            }.buttonStyle(.plain).id(ply).accessibilityIdentifier("variation-node-\(branch.id)-\(ply)")
                        }
                    }.padding(.vertical, 2)
                }.onChange(of: cursor) { ply in if selected { proxy.scrollTo(ply, anchor: .center) } }
            }.frame(height: 39)
            if selected {
                Text(cursor == 0 ? "同一分歧前位置" : "当前：\(branch.notation(at: cursor)) · \(cursor) / \(branch.moves.count) 半回合")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(branch.accent)
                VStack(alignment: .leading, spacing: 9) {
                    Text(branch.condition.simplifiedForDisplay)
                    if branch.moves.indices.contains(cursor - 1), !branch.moves[cursor - 1].explanation.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("这一步").font(.system(size: 9, weight: .semibold)).foregroundColor(branch.accent)
                            Text(branch.moves[cursor - 1].explanation.simplifiedForDisplay)
                                .accessibilityIdentifier("variation-selected-step-explanation")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("变化思路").font(.system(size: 9, weight: .semibold)).foregroundColor(branch.accent)
                        Text(branch.explanation.simplifiedForDisplay)
                    }
                }.font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(11).background(selected ? branch.accent.opacity(0.035) : Studio.paper.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? branch.accent.opacity(0.75) : Studio.line.opacity(0.65), lineWidth: selected ? 1.5 : 1))
    }
}
