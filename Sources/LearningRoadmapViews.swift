import SwiftUI

extension LearningCenterView {
    var learningRoadmap: some View {
        LearningRoadmapBrowser(model: model, store: store, openSource: openStudyReference)
    }
}

/// A compact chooser over the existing curriculum. Expansion is local UI state;
/// every count and continuation still comes from the original learning records.
private struct LearningRoadmapBrowser: View {
    @ObservedObject var model: LearningModel
    @ObservedObject var store: LearningStore
    let openSource: (URL) -> Void
    @State private var phase: LearningRoutePhase = .opening
    @State private var phaseSelections: [LearningRoutePhase: String] = [:]
    @State private var requestedReplacement: String?

    private var routes: [LearningRoute] { model.roadmapRoutes.filter { $0.phase == phase } }
    private var selected: LearningRoute? {
        routes.first { $0.id == model.selectedLearningRoute.id } ?? routes.first
    }
    private var hasUnfinishedPlan: Bool { model.journeyPlan.map { !$0.isFinished } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("学习路线").font(.system(size: 28, weight: .semibold, design: .serif))
                    Text("选一个目标，在不同局面里练会它。")
                        .font(.system(size: 12)).foregroundColor(Studio.muted)
                }
                Spacer()
                Button("自由选局") { model.openLibraryCourses(section: nil) }
                    .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("roadmap-open-library")
            }
            sessionStatus
            preparationStatus
            phasePicker
            if let route = selected {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        routeList.frame(width: 248)
                        routeDetail(route).frame(minWidth: 340, maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        compactRoutePicker
                        routeDetail(route)
                    }
                }
            } else {
                StudioEmpty(symbol: "point.topleft.down.curvedto.point.bottomright.up", title: "这个阶段尚无路线", detail: "可以先选其他阶段，或从自由选局开始。")
            }
        }
        .onAppear {
            phase = model.selectedLearningRoute.phase
            phaseSelections[phase] = model.selectedLearningRoute.id
        }
        .onChange(of: model.selectedLearningRoute.id) { _ in
            phase = model.selectedLearningRoute.phase
            phaseSelections[phase] = model.selectedLearningRoute.id
        }
        .confirmationDialog("改练这个目标？", isPresented: Binding(get: { requestedReplacement != nil }, set: { if !$0 { requestedReplacement = nil } }), titleVisibility: .visible) {
            Button("开始新的一组") {
                if let id = requestedReplacement { model.startRecommendedSession(routeID: id) }
                requestedReplacement = nil
            }
            Button("继续原来的一组") { requestedReplacement = nil; model.resumeJourneySession() }
            Button("取消", role: .cancel) { requestedReplacement = nil }
        } message: {
            Text("已经完成的练习记录会保留，未完成的训练安排将被替换。")
        }
    }

    @ViewBuilder private var sessionStatus: some View {
        if let plan = model.journeyPlan {
            HStack(spacing: 12) {
                Image(systemName: plan.isFinished ? "flag.checkered" : "play.circle.fill")
                    .font(.system(size: 19)).foregroundColor(Studio.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.isFinished ? "训练组 · 已结束" : "训练组 · " + plan.title.simplifiedForDisplay)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("本组完成 \(plan.completedIndices.count) 项" + (plan.skippedIndices.isEmpty ? "" : " · 跳过 \(plan.skippedIndices.count) 项") + (plan.isFinished ? "" : " · 共 \(plan.items.count) 项"))
                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                }
                Spacer(minLength: 10)
                if !plan.isFinished {
                    Button("继续训练组") { model.resumeJourneySession() }.buttonStyle(StudioButtonStyle(compact: true))
                        .accessibilityIdentifier("roadmap-resume-session")
                    Menu {
                        Button("跳过当前项（不计完成）") { model.skipJourneyItem() }
                            .disabled(plan.completedIndices.contains(plan.cursor) || plan.skippedIndices.contains(plan.cursor))
                    } label: { Image(systemName: "ellipsis").frame(width: 22, height: 24) }
                        .menuStyle(.borderlessButton).fixedSize().help("训练安排")
                        .accessibilityLabel("训练安排").accessibilityIdentifier("roadmap-journey-options")
                }
            }.padding(13).background(Studio.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .disabled(model.busy || model.libraryPreparing)
                .accessibilityIdentifier(plan.isFinished ? "roadmap-session-finished" : "roadmap-session-active")
        }
    }

    @ViewBuilder private var preparationStatus: some View {
        if model.libraryPreparing {
            LibraryPreparationStatus(message: model.libraryPreparationMessage) { model.cancelCurrentOperation() }
        }
    }

    private var phasePicker: some View {
        HStack(spacing: 4) {
            ForEach(LearningRoutePhase.allCases) { option in
                Button { selectPhase(option) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: phaseSymbol(option)).font(.system(size: 13))
                        Text(option.title).font(.system(size: 13, weight: phase == option ? .semibold : .medium))
                    }.frame(maxWidth: .infinity, minHeight: 42)
                        .contentShape(Rectangle())
                        .foregroundColor(phase == option ? Studio.onAccent : Studio.muted)
                        .background(phase == option ? Studio.accent : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("roadmap-phase-\(option.id)")
                    .accessibilityValue(phase == option ? "已选择" : "未选择")
                    .help(phasePurpose(option))
            }
        }.padding(4).background(Studio.cream.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private var routeList: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("选择练习目标").font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(routes.count) 个").font(.system(size: 10))
            }.foregroundColor(Studio.muted).padding(.horizontal, 12).padding(.vertical, 10)
            ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                let coverage = model.routeCoverage(route)
                let active = selected?.id == route.id
                Button { chooseRoute(route) } label: {
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(active ? Studio.accent : Studio.muted.opacity(0.7))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(route.title.simplifiedForDisplay).font(.system(size: 13, weight: active ? .semibold : .medium))
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Text(coverage.coreCount > 0 ? "谱例已练 \(coverage.coreCompleted)/\(coverage.coreCount)" : "局面专项")
                                .font(.system(size: 10)).foregroundColor(Studio.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if active { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(Studio.accent) }
                    }.padding(.horizontal, 12).padding(.vertical, 12)
                        .background(active ? Studio.white : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .leading) {
                            if active { RoundedRectangle(cornerRadius: 2).fill(Studio.accent).frame(width: 3).padding(.vertical, 12) }
                        }.contentShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("roadmap-route-\(route.id)")
                    .accessibilityValue(active ? "当前目标" : "")
            }
        }
    }

    private var compactRoutePicker: some View {
        Picker("练习目标", selection: Binding(get: { selected?.id ?? "" }, set: { id in
            if let route = routes.first(where: { $0.id == id }) { chooseRoute(route) }
        })) {
            ForEach(routes) { Text($0.title.simplifiedForDisplay).tag($0.id) }
        }.accessibilityIdentifier("roadmap-compact-route-picker")
    }

    private func routeDetail(_ route: LearningRoute) -> some View {
        let coverage = model.routeCoverage(route)
        let continuing = hasUnfinishedPlan && model.journeyPlan?.routeID == route.id
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(route.title.simplifiedForDisplay).font(.system(size: 23, weight: .semibold, design: .serif))
                Text(route.goal.simplifiedForDisplay).font(.system(size: 14)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LearningRouteExampleList(model: model, store: store, route: route)
            Divider().overlay(Studio.line.opacity(0.4))
            HStack(spacing: 12) {
                Button(continuing ? "继续这组练习" : "安排一组练习") {
                    if continuing { model.resumeJourneySession() }
                    else if hasUnfinishedPlan { requestedReplacement = route.id }
                    else { model.startRecommendedSession(routeID: route.id) }
                }.buttonStyle(StudioButtonStyle(primary: true)).accessibilityIdentifier("roadmap-start-session")
                Menu("其他方式") {
                    Button("先看一个精讲谱例") { model.startRouteExample(routeID: route.id) }.disabled(coverage.coreCount == 0)
                    Button("直接无提示检验") { model.startRecommendedSession(routeID: route.id, diagnostic: true) }
                }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 12))
            }.disabled(model.libraryPreparing || model.busy)
            HStack(spacing: 6) {
                Text("理解思路"); Image(systemName: "chevron.right").font(.system(size: 8))
                Text("自己走"); Image(systemName: "chevron.right").font(.system(size: 8)); Text("换局检验")
            }.font(.system(size: 11)).foregroundColor(Studio.muted).accessibilityElement(children: .combine)
            Divider().overlay(Studio.line.opacity(0.4))
            DisclosureGroup("先看判断方法与变通") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(route.principles.enumerated()), id: \.offset) { index, principle in
                        HStack(alignment: .top, spacing: 9) {
                            Text("\(index + 1)").font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.accent)
                                .frame(width: 19, height: 19).background(Studio.paper, in: Circle())
                            Text(principle.simplifiedForDisplay).font(.system(size: 12)).lineSpacing(4)
                        }
                    }
                    Text("对手变招时").font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.accent)
                    Text(route.adaptation.simplifiedForDisplay).font(.system(size: 12)).lineSpacing(4)
                    Text("留意这些误区").font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.muted)
                    ForEach(Array(route.pitfalls.enumerated()), id: \.offset) { _, pitfall in
                        Label { Text(pitfall.simplifiedForDisplay).font(.system(size: 12)).lineSpacing(4) } icon: {
                            Image(systemName: "minus").font(.system(size: 8)).foregroundColor(Studio.muted)
                        }
                    }
                }.padding(.top, 12).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 12, weight: .medium)).accessibilityIdentifier("roadmap-methods")
            if coverage.positionCount > 0 {
                VStack(alignment: .leading, spacing: 11) {
                    Button { model.openRoutePositions(routeID: route.id) } label: {
                        Label("局面练习 · \(coverage.positionCount) 局", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(StudioButtonStyle(compact: true))
                        .accessibilityIdentifier("roadmap-route-positions")
                    Text("局面已练 \(coverage.practicedPositions) · 独立通过 \(coverage.independentPositions) · 隔日通过 \(coverage.delayedPositions)")
                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                }
            }
            DisclosureGroup("资料来源") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(LearningRoadmapContent.sources.filter { route.sourceIDs.contains($0.id) }) { source in
                        VStack(alignment: .leading, spacing: 5) {
                            if let url = URL(string: source.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                                Button { openSource(url) } label: { Label(source.title.simplifiedForDisplay, systemImage: "arrow.up.right") }
                                    .buttonStyle(.plain).foregroundColor(Studio.accent)
                            } else { Text(source.title.simplifiedForDisplay).fontWeight(.medium) }
                            Text(source.note.simplifiedForDisplay).foregroundColor(Studio.muted).lineSpacing(4)
                        }.font(.system(size: 11))
                    }
                    Text("练过、独立通过和隔日通过分别记录；资料数量不代表掌握程度。")
                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                }.padding(.top, 12)
            }.font(.system(size: 11)).foregroundColor(Studio.muted)
        }.studioSurface(22).id(route.id)
    }

    private func selectPhase(_ option: LearningRoutePhase) {
        guard option != phase else { return }
        phaseSelections[phase] = selected?.id
        let id = phaseSelections[option] ?? model.roadmapRoutes.first(where: { $0.phase == option })?.id
        // Swapping an entire route is navigation, not a geometry animation.
        // Commit the destination immediately rather than animating both layouts.
        phase = option
        if let id { model.selectLearningRoute(id: id) }
    }
    private func chooseRoute(_ route: LearningRoute) {
        guard route.id != selected?.id else { return }
        model.selectLearningRoute(id: route.id)
        phaseSelections[route.phase] = route.id
    }
    private func phasePurpose(_ phase: LearningRoutePhase) -> String {
        switch phase {
        case .opening: return "出动、协调、安将"
        case .middlegame: return "识别威胁，选择计划"
        case .endgame: return "抓住胜和条件"
        case .practice: return "换个局面，仍能判断"
        }
    }
    private func phaseSymbol(_ phase: LearningRoutePhase) -> String {
        switch phase {
        case .opening: return "arrow.triangle.branch"
        case .middlegame: return "scope"
        case .endgame: return "flag"
        case .practice: return "arrow.triangle.2.circlepath"
        }
    }
}
