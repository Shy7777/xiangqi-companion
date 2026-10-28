import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class GameModel: ObservableObject {
    @Published var position = Position.initial
    @Published var selected: Square?
    @Published var legalTargets: [Square] = []
    @Published var positions: [Position] = [.initial]
    @Published var moves: [Move] = []
    @Published var moveNames: [String] = []
    @Published var cursor = 0
    @Published var flipped = false
    @Published var analysisEnabled = true
    @Published var showArrows = true
    @Published var milliseconds = 350
    @Published var message = "可自由录入双方走子，或从开源棋库选择局面。"
    @Published var revision = 0
    @Published var showSetup = false
    @Published var showNewGame = false
    @Published var isPinned = false
    @Published private(set) var isLocalTwoPlayer = false
    @Published private(set) var isSessionProtected = false
    @Published var sessionRecoveryNotice: String?
    @Published var showRecordLibrary = false
    @Published private(set) var recordEntries: [ManualRecordEntry] = []
    @Published private(set) var recordLibraryNotice: String?
    @Published private(set) var recordPreview: ManualRecordPreview?
    @Published private(set) var recordPreviewError: String?
    @Published private(set) var recordEntryErrors: [String: String] = [:]
    @Published private(set) var playPreferences = PlayPreferences()
    @Published private(set) var chessClock = LocalChessClock()
    @Published var showPlayUtilities = false
    @Published private(set) var utilitiesNotice: String?
    let engine: PikafishEngine
    private var initialFEN = Position.initial.fen
    private let dataDirectory: URL
    private var hasStarted = false
    private var recordID = UUID()
    private var recordMetadata: GameRecord.Metadata?
    private var recordAnnotations: [GameRecord.Annotation]?
    private var lastArchived: Data?
    private let monotonicNow: () -> TimeInterval
    private let playMoveSound: (MoveSoundEvent, Double) -> Void
    static let maximumHistoryCount = 200
    static let maximumHistoryBytes = 16 * 1_024 * 1_024

    init(directory: URL? = nil, clockNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         moveSound: (() -> Void)? = nil, engine suppliedEngine: PikafishEngine? = nil,
         soundPlayer: ((MoveSoundEvent, Double) -> Void)? = nil) {
        monotonicNow = clockNow
        if let soundPlayer { playMoveSound = soundPlayer }
        else if let moveSound { playMoveSound = { _, _ in moveSound() } }
        else {
            playMoveSound = { event, volume in
                let sound = NSSound(named: NSSound.Name(event == .capture ? "Tink" : "Pop"))
                sound?.volume = Float(volume); _ = sound?.play()
            }
        }
        let enginePaths = EngineConfiguration.resolve()
        engine = suppliedEngine ?? PikafishEngine(binaryURL: enginePaths.binary, networkURL: enginePaths.network)
        if let directory {
            dataDirectory = directory
        } else if let override = ProcessInfo.processInfo.environment["XQ_COMPANION_STATE_DIR"] {
            dataDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("XiangqiCompanionOpenSource", isDirectory: true)
        }
        restore()
        do { playPreferences = try PlayPreferencesStore.read(from: preferencesURL) }
        catch { utilitiesNotice = "工具设置未读取，暂用默认外观；原文件未覆盖。" }
        chessClock = LocalChessClock(seconds: Double(playPreferences.clockMinutes * 60), increment: Double(playPreferences.clockIncrementSeconds))
    }

    var lastMove: Move? { cursor > 0 ? moves[cursor - 1] : nil }
    var isAtEnd: Bool { cursor == moves.count }
    var terminal: Bool { position.legalMoves().isEmpty }
    var currentAnalysis: [EngineLine] {
        CandidateDisplay.lines(engine.rows, position: position, revision: revision,
                               resultRevision: engine.latestRevision, enabled: analysisEnabled && !isLocalTwoPlayer && !isSessionProtected)
    }
    var recommendationArrows: [RecommendationArrow] {
        guard showArrows else { return [] }
        return currentAnalysis.compactMap { line in
            guard let value = line.pv.first, let move = Move(uci: value) else { return nil }
            return RecommendationArrow(rank: line.rank, move: move)
        }
    }
    var stateLabel: String {
        if isLocalTwoPlayer, playPreferences.clockEnabled, let side = chessClock.timedOut { return "\(side.label)超时 · 棋钟已停止" }
        if terminal { return "\(position.sideToMove.label)无合法走法" }
        if position.isInCheck(position.sideToMove) { return "\(position.sideToMove.label)被将军" }
        return "轮到\(position.sideToMove.label)"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if analysisEnabled && !isLocalTwoPlayer && !isSessionProtected { engine.start() }
        scheduleAnalysis()
    }

    func tap(_ square: Square) {
        guard !isSessionProtected else { message = "损坏记录已保护。请先新建棋局，保留副本后再走棋。"; return }
        if let from = selected, legalTargets.contains(square) {
            play(Move(from: from, to: square))
            return
        }
        if square == selected {
            clearSelection()
        } else if let piece = position[square], piece.side == position.sideToMove {
            selected = square
            legalTargets = position.legalMoves(from: square).map(\.to)
            message = legalTargets.isEmpty ? "这枚棋子当前没有合法走法。" : "再点目标位置，录入这一步。"
        } else if position[square] != nil {
            message = "现在轮到\(position.sideToMove.label)。若两边局面不同，可用「摆局」调整。"
        } else {
            clearSelection()
        }
    }

    func play(_ move: Move) {
        guard !isSessionProtected else { message = "损坏记录已保护，请先明确新建棋局。"; return }
        guard cursor < GameRecord.maximumMoves else { message = "已到 1,024 半步上限，请先导出棋谱再新建。"; return }
        let moveTimestamp = monotonicNow()
        updateClock(at: moveTimestamp)
        guard !isLocalTwoPlayer || !playPreferences.clockEnabled || chessClock.timedOut == nil else {
            message = "棋钟已超时；请重置计时或关闭棋钟后继续研究。"; return
        }
        do {
            let next = try position.applying(move: move)
            let name = position.notation(for: move)
            let soundEvent: MoveSoundEvent = position[move.to] == nil ? .move : .capture
            if cursor < moves.count {
                guard archive() else { return }
                moves = Array(moves.prefix(cursor))
                moveNames = Array(moveNames.prefix(cursor))
                positions = Array(positions.prefix(cursor + 1))
                recordAnnotations = recordAnnotations?.filter { $0.ply <= cursor }
                recordID = UUID()
            }
            moves.append(move)
            moveNames.append(name)
            positions.append(next)
            cursor += 1
            position = next
            if isLocalTwoPlayer && playPreferences.clockEnabled {
                chessClock.completedMove(nextTurn: next.sideToMove, now: moveTimestamp, terminal: next.legalMoves().isEmpty)
            }
            if soundEvent == .capture ? playPreferences.captureSoundEnabled : playPreferences.soundEnabled {
                emitSound(soundEvent)
            }
            message = "已录入 \(name) · \(stateLabel)"
            changed()
        } catch {
            message = "这一步不符合当前局面的走棋规则。"
        }
    }

    func navigate(to index: Int) {
        guard positions.indices.contains(index) else { return }
        pauseClock()
        cursor = index
        position = positions[index]
        message = index == moves.count ? "已回到最新局面。" : "正在看第 \(index) 步；在这里落子可重新尝试。"
        changed()
    }

    func newGame() {
        if replace(with: .initial) { message = isLocalTwoPlayer ? "本机双人新局 · 红方先走。" : "新棋局已就绪，红方先走。" }
    }

    @discardableResult
    func replace(with newPosition: Position) -> Bool {
        do { try newPosition.validate() }
        catch { message = "未替换：\(error.localizedDescription)"; return false }
        guard prepareReplacement() else { return false }
        resetClock()
        initialFEN = newPosition.fen
        recordID = UUID(); recordMetadata = nil; recordAnnotations = nil
        position = newPosition
        positions = [newPosition]
        moves = []
        moveNames = []
        cursor = 0
        showSetup = false
        message = "局面已更新 · \(stateLabel)"
        changed()
        return true
    }

    func flip() { flipped.toggle(); save() }
    func toggleArrows() {
        guard !isLocalTwoPlayer else { message = "本机双人棋盘不显示引擎提示。"; return }
        showArrows.toggle(); save()
    }
    func toggleAnalysis() {
        guard !isLocalTwoPlayer else { message = "本机双人棋盘已关闭引擎；可切回手动分析。"; return }
        analysisEnabled.toggle(); scheduleAnalysis(); save()
    }
    func setBudget(_ value: Int) { milliseconds = value; scheduleAnalysis(); save() }
    func clearSelection() { selected = nil; legalTargets = [] }
    func copyFEN() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(position.fen, forType: .string)
        message = "当前局面已复制，可在「摆局」里再次导入。"
    }

    /// Both sides remain human-operated through the same legal-move model.
    func startLocalTwoPlayer() {
        guard !isSessionProtected else { message = "请先明确新建棋局并保留损坏原记录。"; return }
        pauseClock()
        isLocalTwoPlayer = true; analysisEnabled = false; showArrows = false
        clearSelection(); revision += 1; engine.shutdown(); save()
        message = "本机双人 · \(stateLabel) · 引擎与提示已关闭。"
    }

    func startManualAnalysis() {
        guard !isSessionProtected else { message = "损坏记录已保护，请先新建或载入棋谱。"; return }
        pauseClock()
        isLocalTwoPlayer = false; analysisEnabled = true; showArrows = true
        changed(); message = "已切回手动分析。"
    }

    /// An explicit "analyze this position" action must not inherit the previous
    /// local-two-player mode and silently hide the requested engine analysis.
    @discardableResult
    func analyzePosition(_ newPosition: Position) -> Bool {
        guard replace(with: newPosition) else { return false }
        startManualAnalysis()
        return true
    }

    private func changed() {
        clearSelection()
        scheduleAnalysis()
        save()
    }

    func scheduleAnalysis() {
        revision += 1
        let legalCount = position.legalMoves().count
        guard analysisEnabled, !isLocalTwoPlayer, !isSessionProtected, legalCount > 0 else { engine.stop(); return }
        engine.analyze(fen: initialFEN, moves: moves.prefix(cursor).map(\.uci),
                       revision: revision, movetime: milliseconds, expectedPVCount: min(3, legalCount))
    }

    func shutdown() { pauseClock(); save(); engine.shutdown() }

    private func save() {
        let saved = SavedSession(initialFEN: initialFEN, moves: moves.map(\.uci), cursor: cursor,
                                 flipped: flipped, analysisEnabled: analysisEnabled, milliseconds: milliseconds, showArrows: showArrows,
                                 localTwoPlayer: isLocalTwoPlayer, recordID: recordID, metadata: recordMetadata, annotations: recordAnnotations)
        guard !isSessionProtected else { return }
        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(saved)
            guard bytes.count <= GameRecord.maximumBytes else { throw GameRecordError.invalid("当前棋谱超过保存上限，请导出精简记录。") }
            try bytes.write(to: dataDirectory.appendingPathComponent("session.json"), options: .atomic)
        } catch { message = "局面仍可使用，但保存失败：\(error.localizedDescription)" }
    }

    @discardableResult
    private func archive(force: Bool = false) -> Bool {
        guard !isSessionProtected else { return true }
        guard force || !moves.isEmpty || initialFEN != Position.initial.fen || recordMetadata != nil else { return true }
        do {
            let bytes = try currentRecord.encoded()
            if bytes == lastArchived { return true }
            let directory = dataDirectory.appendingPathComponent("history", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let inventory = try historyInventory()
            guard !inventory.limited, inventory.entries.count < Self.maximumHistoryCount,
                  inventory.bytes + bytes.count <= Self.maximumHistoryBytes else {
                throw GameRecordError.invalid("本机历史已达 200 份或 16 MiB 上限；请先导出并整理历史，当前棋盘未替换。")
            }
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            try bytes.write(to: directory.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8)).json"), options: .atomic)
            lastArchived = bytes
            return true
        } catch { message = "未能保留当前棋谱：\(error.localizedDescription)"; return false }
    }

    private func restore() {
        let url = dataDirectory.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let bytes = try GameRecordCodec.read(url)
            try GameRecordCodec.checkJSONDepth(bytes)
            let saved = try JSONDecoder().decode(SavedSession.self, from: bytes)
            let replay = try saved.record.validate()
            initialFEN = replay.positions[0].fen
            moves = replay.moves; moveNames = replay.names; positions = replay.positions
            cursor = saved.cursor; position = positions[cursor]
            recordID = saved.recordID ?? UUID(); recordMetadata = saved.metadata; recordAnnotations = saved.annotations
            flipped = saved.flipped; analysisEnabled = saved.analysisEnabled
            showArrows = saved.showArrows ?? true
            isLocalTwoPlayer = saved.localTwoPlayer ?? false
            if isLocalTwoPlayer { analysisEnabled = false; showArrows = false }
            milliseconds = [250,350,1000].contains(saved.milliseconds) ? saved.milliseconds : 350
            message = "已恢复上次局面 · 第 \(cursor) 步"
        } catch {
            isSessionProtected = true
            sessionRecoveryNotice = "上次 session.json 无法完整读取，原文件已保留。明确新建时会先备份，自动保存不会覆盖它。"
            message = "上次记录损坏，当前只读；原文件未覆盖。"
        }
    }

    var currentRecord: GameRecord {
        GameRecord(id: recordID, initialFEN: initialFEN, moves: moves.map(\.uci), currentPly: cursor,
                   metadata: recordMetadata, annotations: recordAnnotations)
    }

    /// A corrupt session must survive even explicit replacement. Large/non-file
    /// targets are not copied recursively or automatically rewritten.
    private func prepareReplacement() -> Bool {
        if isSessionProtected {
            let source = dataDirectory.appendingPathComponent("session.json")
            do {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size <= 8 * 1_024 * 1_024 else {
                    throw GameRecordError.invalid("原记录不是普通文件或超过 8 MiB；请先在访达中移出它，再重新打开软件。")
                }
                let copy = dataDirectory.appendingPathComponent("session-recovery-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: source, to: copy)
                isSessionProtected = false
                sessionRecoveryNotice = "损坏原记录副本已保留：\(copy.lastPathComponent)"
            } catch { message = "未新建：原记录备份失败。\(error.localizedDescription)"; return false }
        }
        return archive()
    }

    private func historyInventory() throws -> (entries: [ManualRecordEntry], bytes: Int, limited: Bool) {
        let directory = dataDirectory.appendingPathComponent("history", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], 0, false) }
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants], errorHandler: { _, error in enumerationError = error; return false }) else {
            throw GameRecordError.invalid("无法读取本机历史目录。")
        }
        var entries: [ManualRecordEntry] = [], total = 0, inspected = 0, limited = false
        for case let url as URL in enumerator {
            inspected += 1
            if inspected > 1_000 { limited = true; break }
            guard url.pathExtension.lowercased() == "json" else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            if entries.count >= Self.maximumHistoryCount { limited = true; break }
            let size = max(0, values.fileSize ?? 0)
            total += min(size, Self.maximumHistoryBytes + 1)
            entries.append(ManualRecordEntry(id: url.lastPathComponent, url: url,
                                            date: values.contentModificationDate ?? .distantPast, bytes: size))
        }
        if let enumerationError { throw enumerationError }
        return (entries.sorted { $0.date > $1.date }, total, limited)
    }

    func openRecordLibrary() { pauseClock(); refreshRecordLibrary(); previewCurrentRecord(); showRecordLibrary = true }
    func refreshRecordLibrary() {
        do {
            let inventory = try historyInventory(); recordEntries = inventory.entries
            recordLibraryNotice = inventory.limited ? "只显示前 200 份记录；文件均未删除，可在访达整理后刷新。" : nil
        } catch { recordLibraryNotice = "历史目录无法读取：\(error.localizedDescription)"; recordEntries = [] }
    }
    func previewCurrentRecord() {
        do {
            recordPreview = ManualRecordPreview(imported: try GameRecordCodec.validated(currentRecord), title: "当前棋盘")
            recordPreviewError = nil
        } catch { recordPreview = nil; recordPreviewError = error.localizedDescription }
    }
    func previewRecordEntry(_ entry: ManualRecordEntry) {
        do {
            let expected = dataDirectory.appendingPathComponent("history", isDirectory: true).standardizedFileURL
            guard entry.url.deletingLastPathComponent().standardizedFileURL == expected else { throw GameRecordError.invalid("历史路径不匹配。") }
            let imported = try GameRecordCodec.decode(GameRecordCodec.read(entry.url))
            recordPreview = ManualRecordPreview(imported: imported, title: imported.record.metadata?.title ?? entry.title)
            recordPreviewError = nil; recordEntryErrors[entry.id] = nil
        } catch {
            recordPreview = nil
            recordPreviewError = "这份记录无法完整重放，未载入；原文件仍保留。\(error.localizedDescription)"
            recordEntryErrors[entry.id] = recordPreviewError
        }
    }
    @discardableResult
    func previewRecordData(_ data: Data, title: String = "待导入棋谱") -> Bool {
        pauseClock()
        do {
            let imported = try GameRecordCodec.decode(data)
            recordPreview = ManualRecordPreview(imported: imported, title: title)
            recordPreviewError = nil; refreshRecordLibrary(); showRecordLibrary = true
            return true
        } catch { recordPreview = nil; recordPreviewError = error.localizedDescription; message = "未导入：\(error.localizedDescription)"; return false }
    }
    @discardableResult
    func acceptRecordPreview(at ply: Int? = nil) -> Bool {
        guard let preview = recordPreview else { return false }
        do {
            var requested = preview.imported.record
            if let ply { requested.currentPly = ply }
            let imported = try GameRecordCodec.validated(requested, notice: preview.imported.notice)
            guard prepareReplacement() else { return false }
            resetClock()
            let record = imported.record
            initialFEN = record.initialFEN; recordID = record.id
            recordMetadata = record.metadata; recordAnnotations = record.annotations
            moves = imported.replay.moves; moveNames = imported.replay.names; positions = imported.replay.positions
            cursor = record.currentPly ?? moves.count; position = positions[cursor]
            changed(); showRecordLibrary = false
            message = imported.notice ?? "完整棋谱已载入 · 第 \(cursor) / \(moves.count) 半步。"
            return true
        } catch { recordPreviewError = error.localizedDescription; return false }
    }
    @discardableResult
    func saveRecordToLibrary() -> Bool {
        guard !isSessionProtected else { message = "当前仅是只读占位棋盘，损坏原记录未作为新棋谱保存。"; return false }
        guard archive(force: true) else { return false }
        refreshRecordLibrary(); message = "完整棋谱已存入本机历史。"; return true
    }
    func revealRecordLibrary() {
        do {
            let directory = dataDirectory.appendingPathComponent("history", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        } catch { recordLibraryNotice = error.localizedDescription }
    }
    func importRecordUI() {
        pauseClock()
        let panel = NSOpenPanel(); panel.title = "导入棋谱或局面"
        panel.allowedContentTypes = [.json, .plainText,
                                     UTType(filenameExtension: "fen", conformingTo: .plainText) ?? .plainText,
                                     UTType(filenameExtension: "uci", conformingTo: .plainText) ?? .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { _ = previewRecordData(try GameRecordCodec.read(url), title: url.lastPathComponent) }
        catch { message = "未导入：\(error.localizedDescription)" }
    }
    func importRecordClipboardUI() {
        guard let text = NSPasteboard.general.string(forType: .string), text.utf8.count <= GameRecord.maximumBytes else {
            message = "剪贴板需要 256 KiB 内的棋谱文本。"; return
        }
        _ = previewRecordData(Data(text.utf8), title: "剪贴板棋谱")
    }
    func exportRecordUI(format: ManualRecordExportFormat = .json) {
        pauseClock()
        do {
            guard !isSessionProtected else { throw GameRecordError.invalid("这是只读占位棋盘，不是已恢复的原记录。") }
            let bytes: Data
            switch format {
            case .json: bytes = try currentRecord.encoded()
            case .uci: bytes = Data(try currentRecord.uciText().utf8)
            case .fen: bytes = Data(position.fen.utf8)
            }
            let panel = NSSavePanel(); panel.title = "导出棋谱"
            panel.nameFieldStringValue = "象棋棋谱." + format.fileExtension
            panel.allowedContentTypes = [format == .json ? .json : UTType(filenameExtension: format.fileExtension, conformingTo: .plainText) ?? .plainText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try bytes.write(to: url, options: .atomic)
            message = format == .fen ? "当前局面已导出（不含历史）。" : "完整着序已导出。"
        } catch { message = "未导出：\(error.localizedDescription)" }
    }

    func variation(_ pv: [String], limit: Int = 6) -> String {
        var p = position
        var text: [String] = []
        for value in pv.prefix(limit) {
            guard let move = Move(uci: value), let next = try? p.applying(move: move) else { break }
            text.append(p.notation(for: move))
            p = next
        }
        return text.joined(separator: "  ")
    }

    func reason(for move: Move) -> String {
        if position.isInCheck(position.sideToMove) { return "先解除将军，保证帅将安全。" }
        if let target = position[move.to] { return "可吃掉对方的\(target.symbol)，继续留意对方应手。" }
        if let next = try? position.applying(move: move), next.isInCheck(next.sideToMove) { return "这步形成将军，迫使对方先应对。" }
        if let piece = position[move.from], piece.kind == .horse || piece.kind == .rook || piece.kind == .cannon {
            return "当前搜索推荐这一步，后续应手见下方路线。"
        }
        return "当前搜索的优先候选，可展开查看后续应手。"
    }

    private var preferencesURL: URL { dataDirectory.appendingPathComponent("play-preferences.json") }

    private func savePlayPreferences() {
        do { try PlayPreferencesStore.write(playPreferences, to: preferencesURL); utilitiesNotice = nil }
        catch { utilitiesNotice = "本次工具设置仅在当前窗口生效，未覆盖原文件：\(error.localizedDescription)" }
    }
    func setBoardColorway(_ value: BoardColorway) {
        playPreferences.appearance.board = value; savePlayPreferences()
    }
    func setPieceColorway(_ value: PieceColorway) {
        playPreferences.appearance.pieces = value; savePlayPreferences()
    }
    func setMoveSound(_ enabled: Bool) {
        playPreferences.soundEnabled = enabled; savePlayPreferences()
    }
    func setCaptureSound(_ enabled: Bool) {
        playPreferences.captureSoundEnabled = enabled; savePlayPreferences()
    }
    func setSoundVolume(_ volume: Double) {
        guard volume.isFinite else { return }
        playPreferences.soundVolume = min(1, max(0, volume)); savePlayPreferences()
    }
    /// An explicit preview can be heard without enabling automatic move sounds.
    func previewSound(_ event: MoveSoundEvent) { emitSound(event) }
    private func emitSound(_ event: MoveSoundEvent) {
        guard playPreferences.soundVolume > 0 else { return }
        playMoveSound(event, playPreferences.soundVolume)
    }
    func setClockEnabled(_ enabled: Bool) {
        pauseClock(); playPreferences.clockEnabled = enabled; resetClock(); savePlayPreferences()
    }
    func setClockMinutes(_ minutes: Int) {
        guard PlayPreferences.supportedMinutes.contains(minutes) else { utilitiesNotice = "每方用时请输入 1–120 分钟。"; return }
        pauseClock(); playPreferences.clockMinutes = minutes; resetClock(); savePlayPreferences()
    }
    func setClockIncrement(_ seconds: Int) {
        guard PlayPreferences.supportedIncrementSeconds.contains(seconds) else { utilitiesNotice = "每步加秒请输入 0–60 秒。"; return }
        pauseClock(); playPreferences.clockIncrementSeconds = seconds; resetClock(); savePlayPreferences()
    }
    func openPlayUtilities() { pauseClock(); showPlayUtilities = true }
    func resetClock() {
        chessClock = LocalChessClock(seconds: Double(playPreferences.clockMinutes * 60), increment: Double(playPreferences.clockIncrementSeconds))
    }
    func pauseClock() {
        guard chessClock.runningSide != nil else { return }
        chessClock.pause(now: monotonicNow())
    }
    func startClock() {
        guard isLocalTwoPlayer, playPreferences.clockEnabled, isAtEnd, !terminal, !isSessionProtected,
              !showSetup, !showRecordLibrary, !showPlayUtilities else { return }
        chessClock.start(turn: position.sideToMove, now: monotonicNow())
    }
    func tickClock() { updateClock(at: monotonicNow()) }
    private func updateClock(at timestamp: TimeInterval) {
        guard chessClock.runningSide != nil else { return }
        guard isLocalTwoPlayer, playPreferences.clockEnabled, isAtEnd, !terminal, !isSessionProtected,
              !showSetup, !showRecordLibrary, !showPlayUtilities else { pauseClock(); return }
        chessClock.advance(now: timestamp)
        if let side = chessClock.timedOut {
            clearSelection(); message = "\(side.label)用时已到，棋钟已停止。可重置或关闭计时后继续研究。"
        }
    }

    func exportBoardPNG() {
        pauseClock()
        guard !isSessionProtected else { message = "当前为损坏记录的占位棋盘，未导出。"; return }
        do {
            let data = try BoardPNGExporter.png(position: position, flipped: flipped, appearance: playPreferences.appearance)
            let panel = NSSavePanel(); panel.title = "导出当前棋盘"
            panel.nameFieldStringValue = "象棋局面.png"; panel.allowedContentTypes = [.png]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            message = "已导出当前朝向的纯棋盘图片，不含提示与屏幕内容。"
        } catch { message = "棋盘图片未导出：\(error.localizedDescription)" }
    }
}
