import SwiftUI
import AppKit

@MainActor
enum WindowPlacement {
    private static var installed = false
    static func install() {
        guard !installed else { return }; installed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.windows.first { $0.canBecomeMain }?.title = "象棋伴练 开源版"
            placeStudy()
        }
    }
    static func placeStudy() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }), let screen = window.screen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let width = min(1280, frame.width - 32)
        let height = min(900, frame.height - 24)
        window.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height), display: true, animate: false)
    }
    static func placeRight() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }), let screen = window.screen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let width = min(880, max(760, frame.width * 0.49))
        let height = min(860, frame.height - 20)
        window.setFrame(NSRect(x: frame.maxX - width - 12, y: frame.maxY - height - 8, width: width, height: height), display: true, animate: false)
    }
    static func pin(_ enabled: Bool) {
        NSApp.windows.first { $0.canBecomeMain }?.level = enabled ? .floating : .normal
    }
}

@MainActor
final class CompanionDelegate: NSObject, NSApplicationDelegate {
    var game: GameModel?
    var learning: LearningModel?
    var bookLesson: BookLessonModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.activate(ignoringOtherApps: true)
        let icon = NSImage(size: NSSize(width: 128, height: 128))
        icon.lockFocus()
        NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.89, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 120, height: 120), xRadius: 27, yRadius: 27).fill()
        let accent = NSColor(calibratedRed: 0.62, green: 0.22, blue: 0.11, alpha: 1)
        accent.setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: 20, y: 20, width: 88, height: 88)); circle.lineWidth = 3; circle.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 59, weight: .medium), .foregroundColor: accent]
        let title = NSString(string: "棋")
        let size = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: (128-size.width)/2, y: (128-size.height)/2 + 2), withAttributes: attrs)
        icon.unlockFocus(); NSApp.applicationIconImage = icon
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { bookLesson?.suspend(); game?.shutdown(); learning?.shutdown() }
}

#if !APP_TESTS
@main
struct XiangqiCompanionApp: App {
    @NSApplicationDelegateAdaptor(CompanionDelegate.self) var delegate
    @StateObject private var model = GameModel()
    @StateObject private var learning: LearningModel
    @StateObject private var book: BookStudyModel
    @StateObject private var bookLesson: BookLessonModel
    @State private var studying = true
    @State private var readingBook = true
    init() {
        let learningModel = LearningModel()
        let bookModel = BookStudyModel()
        _learning = StateObject(wrappedValue: learningModel)
        _book = StateObject(wrappedValue: bookModel)
        _bookLesson = StateObject(wrappedValue: BookLessonModel(book: bookModel, store: learningModel.store, coach: learningModel.coach))
    }
    var body: some Scene {
        WindowGroup("象棋伴练 开源版") {
            CompanionRootView(model: model, learning: learning, book: book, bookLesson: bookLesson, studying: $studying, readingBook: $readingBook)
                .onAppear { delegate.game = model; delegate.learning = learning; delegate.bookLesson = bookLesson }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("分析棋盘：新棋局") { model.showNewGame = true }.keyboardShortcut("n", modifiers: .command).disabled(studying)
                Button("分析棋盘：摆局 / 导入") { model.showSetup = true }.keyboardShortcut("o", modifiers: .command).disabled(studying)
            }
            CommandMenu("棋盘") {
                Button("分析棋盘：悔棋") { model.navigate(to: model.cursor - 1) }.disabled(studying || model.cursor == 0)
                Button("分析棋盘：前进") { model.navigate(to: model.cursor + 1) }.disabled(studying || model.isAtEnd)
                Button("翻转棋盘") { if readingBook { book.flipped.toggle() } else if studying { learning.flipped.toggle() } else { model.flip() } }.keyboardShortcut("f", modifiers: .command)
                Button(model.showArrows ? "隐藏候选箭头" : "显示候选箭头") { model.toggleArrows() }.disabled(studying)
                Button("复制分析局面") { model.copyFEN() }.keyboardShortcut("c", modifiers: [.command,.shift]).disabled(studying)
                Divider()
                Button(model.analysisEnabled ? "暂停分析" : "继续分析") { model.toggleAnalysis() }.disabled(studying)
                Button("放到屏幕右侧") { WindowPlacement.placeRight() }
                Button("展开学习工作台") { WindowPlacement.placeStudy() }
            }
            CommandMenu("引擎") {
                Button("配置本地引擎与权重…") { EngineConfigurationUI.configure() }
                Button("清除保存的引擎配置…") { EngineConfigurationUI.clear() }
            }
        }
    }
}
#endif

private struct CompanionRootView: View {
    @StateObject private var githubLibrary = GitHubLibraryStore()
    @State private var recordLegacyExposureOnAnalysis = false
    @State private var bookAnalysisSource: BookStudySource?
    @State private var bookAnalysisSide: Side?
    @ObservedObject var model: GameModel
    @ObservedObject var learning: LearningModel
    @ObservedObject var book: BookStudyModel
    @ObservedObject var bookLesson: BookLessonModel
    @Binding var studying: Bool
    @Binding var readingBook: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { EngineConfigurationUI.configure() } label: { Label("引擎设置", systemImage: "gearshape") }
                    .buttonStyle(StudioButtonStyle(compact: true))
                    .help("选择自行取得的可信引擎与权重；重启生效")
                    .accessibilityIdentifier("external-engine-settings")
                if let source = bookAnalysisSource, !readingBook {
                    Button {
                        learning.suspend(); model.engine.stop()
                        readingBook = true; studying = true
                    } label: { Label("回到本课", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(StudioButtonStyle(compact: true))
                        .help(source.title).accessibilityIdentifier("book-return-from-analysis")
                }
                Spacer()
                if !studying {
                    Button("从此局面练习") {
                        bookLesson.suspend()
                        learning.startGame(from: model.position, player: bookAnalysisSide ?? model.position.sideToMove)
                        readingBook = false; studying = true
                    }.buttonStyle(StudioButtonStyle(compact: true)).help(bookAnalysisSource == nil ? "保留分析棋局，在学习区开启独立陪练" : "沿用本课执子方；对弈练习不代替本课关键点检验，练完可回本课")
                }
                HStack(spacing: 3) {
                    Button { learning.suspend(); readingBook = true; studying = true } label: { Label("跟书学习", systemImage: "book.pages").font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 13).padding(.vertical, 7).foregroundColor(readingBook ? Studio.green : Studio.muted)
                        .background(readingBook ? Studio.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle()) }
                        .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("workspace-books")
                    Button { bookLesson.suspend(); readingBook = false; studying = true } label: { Label("更多练法", systemImage: "book.closed").font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 13).padding(.vertical, 7).foregroundColor(studying && !readingBook ? Studio.green : Studio.muted)
                        .background(studying && !readingBook ? Studio.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle()) }
                        .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("workspace-learning")
                    Button {
                        bookLesson.suspend(); bookAnalysisSource = nil; bookAnalysisSide = nil
                        recordLegacyExposureOnAnalysis = studying && !readingBook
                        readingBook = false; studying = false
                    } label: { Label("自由研究", systemImage: "square.grid.3x3").font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 13).padding(.vertical, 7).foregroundColor(!studying ? Studio.green : Studio.muted)
                        .background(!studying ? Studio.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle()) }
                        .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("workspace-analysis")
                }.padding(3).background(Studio.paper, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Studio.line.opacity(0.7), lineWidth: 0.8).allowsHitTesting(false))
            }.padding(.horizontal, 20).frame(height: 43).background(Studio.rail)
            Rectangle().fill(Studio.line).frame(height: 1)
            if readingBook {
                BookLearningWorkspace(book: book, lesson: bookLesson, onAnalyze: { position, side in
                    if model.analyzePosition(position) {
                        bookLesson.prepareForAnalysis()
                        bookAnalysisSource = bookLesson.currentSource; bookAnalysisSide = side
                        recordLegacyExposureOnAnalysis = false
                        learning.suspend(); readingBook = false; studying = false
                    }
                    else { book.notice = model.message }
                })
            } else if studying {
                LearningCenterView(model: learning, store: learning.store, coach: learning.coach, githubLibrary: githubLibrary, onAnalyzePosition: { position in
                    if model.analyzePosition(position) {
                        bookAnalysisSource = nil; bookAnalysisSide = nil
                        recordLegacyExposureOnAnalysis = true
                        learning.suspend(); studying = false
                    }
                    else { learning.notice = model.message }
                })
            }
            else { CompanionView(model: model, engine: model.engine) }
        }
        .background(Studio.paper).foregroundColor(Studio.ink).tint(Studio.accent).preferredColorScheme(.light)
        .onChange(of: studying) { value in
            if value { model.engine.stop() }
            else {
                if recordLegacyExposureOnAnalysis {
                    _ = learning.recordMaterialExposure(lessonID: learning.lessonID)
                    let id = SyncedPosition.identifier(model.position.fen)
                    if learning.libraryCatalog.entry(id: id) != nil { learning.recordLibraryExposure(entryID: id) }
                }
                recordLegacyExposureOnAnalysis = false
                bookLesson.suspend(); learning.suspend(); model.scheduleAnalysis()
            }
        }
        .onChange(of: readingBook) { value in
            if value { learning.suspend(); model.engine.stop() }
        }
        .task { await book.bootstrap() }
        .onAppear { WindowPlacement.install() }
        .frame(minWidth: 780, minHeight: 780)
    }
}
