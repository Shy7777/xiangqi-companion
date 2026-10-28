import SwiftUI
import WebKit
import AppKit

extension LearningCenterView {
    func lessonScope(_ lesson: LearningLesson) -> String {
        if lesson.isSystematic {
            let lines = lesson.lines
            let fullGames = lines.filter { $0.game != nil }.count
            let scope = fullGames == lines.count ? "\(fullGames) 盘完整实战" : "\(lines.count) 个研究谱例"
            return "\(scope) · \(lines.reduce(0) { $0 + ($1.checkpoints?.count ?? 0) }) 个决策点 · 约 \(lesson.estimatedMinutes) 分钟"
        }
        return "\(lesson.lines.count) 个短谱练习 · 约 \(lesson.estimatedMinutes) 分钟"
    }
    func lineScope(_ line: StudyLine) -> String {
        if let points = line.checkpoints {
            return "\(line.moves.count) 半回合\(line.game == nil ? "谱例" : "完整记录") · \(points.count) 个关键决策"
        }
        return "执\(line.studentSide.label) · \(line.moves.count) 半回合"
    }
    func gameProvenance(_ game: StudyGameMetadata) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("红方 \(game.red)  —  黑方 \(game.black)").font(.system(size: 12, weight: .medium))
            Text("\(game.event) · \(game.date) · \(game.result)").font(.system(size: 10)).foregroundColor(Studio.muted)
            if let url = URL(string: game.sourceURL) {
                Button("核对原始棋谱 ↗") { openStudyReference(url) }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(Studio.accent)
            }
        }
    }
    func studyGuide(_ guide: StudyGuide, lesson: LearningLesson) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            StudioTag(text: guide.level)
            Text("带着问题读谱").font(.system(size: 17, weight: .semibold))
            Text(guide.reading.simplifiedForDisplay).font(.system(size: 13)).foregroundColor(Studio.muted).lineSpacing(6)
            ForEach(Array(guide.questions.enumerated()), id: \.offset) { index, question in
                HStack(alignment: .top, spacing: 11) {
                    Text("\(index + 1)").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(Studio.green)
                    Text(question.simplifiedForDisplay).font(.system(size: 13)).lineSpacing(5)
                }
            }
            DisclosureGroup("研究顺序与完成标准") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(guide.workflow.enumerated()), id: \.offset) { index, item in
                        Text("\(index + 1). \(item)").font(.system(size: 12)).lineSpacing(5)
                    }
                    Text(guide.takeaway.simplifiedForDisplay).font(.system(size: 12, weight: .medium)).foregroundColor(Studio.green).lineSpacing(5)
                }.padding(.top, 12)
            }.font(.system(size: 12, weight: .medium))
            sourceRows(model.sources.filter { lesson.sourceIDs.contains($0.id) })
        }
    }
    var professionalReading: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeading("有出处的专业教程", detail: "署名专题与完整对局节目，配合本地棋谱研究；短例只作选看补充。", large: true)
            Text("阅读任务为本软件补充导读。原站保留完整内容与署名；视频标明节目范围及已核实时长，不冒称全片审定。")
                .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
            ForEach(ProfessionalResources.paths) { path in
                VStack(alignment: .leading, spacing: 13) {
                    Text(path.title.simplifiedForDisplay).font(.system(size: 19, weight: .semibold))
                    Text(path.aim.simplifiedForDisplay).font(.system(size: 13)).lineSpacing(5)
                    sourceRows(ProfessionalResources.sources.filter { path.sourceIDs.contains($0.id) }, embedded: true)
                    Divider()
                    Label("读完回棋盘验证", systemImage: "square.grid.3x3").font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.green)
                    Text(path.assignment.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
                }.studioSurface(20)
            }
            DisclosureGroup("协会短例 · 可选补充") {
                VStack(alignment: .leading, spacing: 15) {
                    Text("这些是短小案例，不是系统进阶课程。只在需要补一个局部手段时选看，不计入主线完成度。")
                        .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
                    sourceRows(ProfessionalResources.sources.filter { $0.id.hasPrefix("professional-cxa-") }, embedded: true)
                }.padding(.top, 14)
            }.font(.system(size: 13, weight: .medium)).accessibilityIdentifier("optional-short-videos")
            Button("到实战研究选择一盘") { model.onlySupplements = false; model.stageFilter = nil; model.navigate(.courses) }
                .buttonStyle(StudioButtonStyle(primary: true))
        }
    }
    @ViewBuilder var checkpointNavigator: some View {
        if let points = model.line?.checkpoints, !points.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("关键决策导航", systemImage: "scope").font(.system(size: 11, weight: .semibold)).foregroundColor(Studio.green)
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Button { model.goToDemoPly(point.ply) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(format: "%02d", index + 1)).font(.system(size: 11, design: .monospaced)).foregroundColor(Studio.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(point.title.simplifiedForDisplay).font(.system(size: 12, weight: .medium))
                                let startSide = (try? Position(fen: model.line?.startingFEN ?? Position.initial.fen))?.sideToMove ?? .red
                                Text("第 \(point.ply / 2 + 1) 回合 · \((point.ply % 2 == 0 ? startSide : startSide.opponent).label)决策").font(.system(size: 10)).foregroundColor(Studio.muted)
                            }
                            Spacer(minLength: 0)
                        }.padding(10).background(model.cursor == point.ply ? Studio.green.opacity(0.07) : Studio.paper, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).disabled(model.busy).accessibilityIdentifier("checkpoint-jump-\(index)")
                }
            }
        }
    }
    @ViewBuilder var decisionContext: some View {
        if let point = model.currentCheckpoint {
            VStack(alignment: .leading, spacing: 12) {
                StudioTag(text: "决策 \((model.checkpointIndex ?? 0) + 1) / \(model.checkpointCount)")
                Text(model.mode == .test ? "独立评估当前局面" : point.title).font(.system(size: 17, weight: .semibold))
                Text(model.mode == .test ? "请自行判断双方威胁，比较候选并算清回应，再在棋盘提交一手。这里不提前给出题型或研究方向。" : point.prompt).font(.system(size: 13)).lineSpacing(6)
                if model.mode == .demonstration || model.mode == .practice && model.hintLevel > 0 {
                    Text(point.focus.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
                }
                if model.mode == .demonstration {
                    DisclosureGroup("原谱选择与研究说明") {
                        Text(point.explanation.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5).padding(.top, 10)
                    }.font(.system(size: 12, weight: .medium))
                }
                if model.mode == .test {
                    Label(model.currentRunUsedHelp ? "本轮含辅助或重试记录" : "无提示检验", systemImage: "eye.slash")
                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                } else if model.currentRunUsedHelp && model.mode == .practice {
                    Text("本轮用于练习，不计为独立通过。").font(.system(size: 10)).foregroundColor(Studio.gold)
                }
            }
        }
    }
}

/// Shows the original publisher's site only after the reader explicitly opens it.
/// No scraped copies, injected scripts, logins, or remote lesson text enter the local engine.
struct ProfessionalReader: View {
    let source: LearningSource
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var failure: String?
    @State private var reloadID = UUID()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(source.title.simplifiedForDisplay).font(.system(size: 15, weight: .semibold))
                    Text(URL(string: source.url)?.host ?? "原站资料").font(.system(size: 11)).foregroundColor(Studio.muted)
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button("刷新") { failure = nil; loading = true; reloadID = UUID() }.buttonStyle(StudioButtonStyle(compact: true))
                if let url = URL(string: source.url) { Link("浏览器打开 ↗", destination: url).font(.system(size: 12)) }
                StudioIconButton(symbol: "xmark", label: "关闭原站阅读") { dismiss() }
            }.padding(18).background(Studio.white)
            Text(source.note + "  ·  此页需要联网，由来源网站提供；棋盘与本地引擎不依赖它。")
                .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            if let failure {
                VStack(spacing: 14) {
                    Spacer()
                    StudioEmpty(symbol: "wifi.exclamationmark", title: "原站暂时未能加载", detail: failure + " 可重试，或用上方浏览器入口打开；本地棋谱仍然可用。")
                    Spacer()
                }
            } else if let url = URL(string: source.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                OriginalSourceWebView(url: url, loading: $loading, failure: $failure).id(reloadID)
            }
        }.frame(width: 860, height: 700).background(Studio.paper).foregroundColor(Studio.ink)
    }
}

private struct OriginalSourceWebView: NSViewRepresentable {
    let url: URL
    @Binding var loading: Bool
    @Binding var failure: String?
    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading, failure: $failure) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url, timeoutInterval: 30))
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) { nsView.stopLoading(); nsView.navigationDelegate = nil; nsView.uiDelegate = nil }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loading: Binding<Bool>
        var failure: Binding<String?>
        init(loading: Binding<Bool>, failure: Binding<String?>) { self.loading = loading; self.failure = failure }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading.wrappedValue = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading.wrappedValue = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func fail(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            loading.wrappedValue = false; failure.wrappedValue = error.localizedDescription
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
            decisionHandler(["http", "https", "about"].contains(scheme) ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}
