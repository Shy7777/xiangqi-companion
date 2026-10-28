import Foundation
import Combine

enum EngineScore: Equatable, Sendable {
    case cp(Int)
    case mate(Int)
}

struct EngineWDL: Equatable, Sendable {
    let wins: Int
    let draws: Int
    let losses: Int
}

struct EngineLine: Identifiable, Equatable, Sendable {
    var id: Int { rank }
    let rank: Int
    let depth: Int
    /// UCI scores refer to the side to move in the analyzed position.
    let score: EngineScore
    let pv: [String]
    let timeMS: Int?
    let nodes: UInt64?
    /// Present only if the engine actually supplies WDL, in thousandths.
    let wdl: EngineWDL?
}

/// UCI emits MultiPV lines individually, and an interrupted iteration may mix
/// depths or reorder moves. Only complete, distinct candidate sets are visible.
struct EngineLineGroupAssembler: Sendable {
    let expectedPVCount: Int
    private var groups: [Int: [Int: EngineLine]] = [:]
    private(set) var latestComplete: [EngineLine] = []

    init(expectedPVCount: Int) {
        self.expectedPVCount = min(3, max(1, expectedPVCount))
    }

    mutating func append(_ line: EngineLine) -> [EngineLine]? {
        guard (1...expectedPVCount).contains(line.rank), !line.pv.isEmpty,
              line.depth >= (latestComplete.first?.depth ?? 0) else { return nil }
        // A rank-one update starts a new report at this depth; the remaining
        // ranks must arrive again before replacing the previous complete set.
        if line.rank == 1 { groups[line.depth] = [:] }
        groups[line.depth, default: [:]][line.rank] = line
        let group = groups[line.depth] ?? [:]
        let complete = (1...expectedPVCount).compactMap { group[$0] }
        guard complete.count == expectedPVCount,
              Set(complete.compactMap { $0.pv.first }).count == expectedPVCount else {
            trimPendingGroups()
            return nil
        }
        latestComplete = complete
        groups = groups.filter { $0.key >= line.depth }
        trimPendingGroups()
        return complete
    }

    private mutating func trimPendingGroups() {
        if groups.count > 8 {
            let keep = Set(groups.keys.sorted().suffix(8))
            groups = groups.filter { keep.contains($0.key) }
        }
    }
}

/// A serial UCI connection. A new position invalidates old output immediately;
/// its search starts only after the previous search acknowledges `stop`.
@MainActor
final class PikafishEngine: ObservableObject {
    @Published private(set) var status = "尚未启动"
    @Published private(set) var error: String?
    @Published private(set) var isReady = false
    @Published private(set) var isThinking = false
    @Published private(set) var rows: [EngineLine] = []
    @Published private(set) var supportsWDL = false
    @Published private(set) var usesNormalizedPawnScore = false
    @Published private(set) var latestRevision: Int?
    @Published private(set) var engineName = "Pikafish"
    var isRunning: Bool { process?.isRunning == true }
    /// The boolean is true only when the requested search reaches bestmove.
    var onResults: ((Int, [EngineLine], Bool) -> Void)?

    private struct Request {
        let fen: String
        let moves: [String]
        let revision: Int
        let ticket: Int
        let movetime: Int
        let expectedPVCount: Int
    }

    private let binaryURL: URL
    private let networkURL: URL
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var stderrTail = ""
    private var options: [String: String] = [:]
    private var handshake: String?
    private var shutdownRequested = false
    private var running: Request?
    private var pending: Request?
    private var lineAssembler: EngineLineGroupAssembler?
    private var stopRequested = false
    private var ticket = 0
    private var generation = 0
    private var debounceTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(binaryURL: URL, networkURL: URL) {
        self.binaryURL = binaryURL
        self.networkURL = networkURL
    }

    func start() {
        guard process == nil else { return }
        error = nil
        shutdownRequested = false
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            fail(binaryURL.lastPathComponent == "xiangqi-engine-not-configured"
                 ? "尚未配置本地引擎。请点击“引擎设置”，选择可信引擎与权重后重启。"
                 : "找不到可运行的皮卡鱼引擎：\(binaryURL.path)")
            return
        }
        guard FileManager.default.isReadableFile(atPath: networkURL.path) else {
            fail("找不到引擎权重：\(networkURL.path)")
            return
        }
        generation += 1
        let connection = generation
        options = [:]
        outputBuffer.removeAll(keepingCapacity: true)
        stderrTail = ""
        supportsWDL = false
        usesNormalizedPawnScore = false
        isReady = false
        status = "正在启动引擎…"
        handshake = "uci"
        let child = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        child.executableURL = binaryURL
        child.currentDirectoryURL = binaryURL.deletingLastPathComponent()
        child.standardInput = input
        child.standardOutput = output
        child.standardError = errors
        inputPipe = input
        outputPipe = output
        errorPipe = errors
        process = child
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == connection else { return }
                self.receive(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == connection else { return }
                self.stderrTail += String(decoding: data, as: UTF8.self)
                self.stderrTail = String(self.stderrTail.suffix(8192))
            }
        }
        child.terminationHandler = { [weak self] child in
            let exitCode = child.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == connection else { return }
                self.didExit(exitCode)
            }
        }
        do {
            try child.run()
            send("uci")
            armTimeout(seconds: 12, message: "引擎启动超时，请重新启动分析器。")
        } catch {
            fail("引擎无法启动：\(error.localizedDescription)")
            releasePipes()
            process = nil
        }
    }

    func analyze(fen: String, moves: [String] = [], revision: Int, movetime: Int = 350,
                 expectedPVCount: Int = 3) {
        ticket += 1
        let requestTicket = ticket
        latestRevision = revision
        debounceTask?.cancel()
        pending = nil
        lineAssembler = nil
        rows = []
        error = nil
        guard !fen.isEmpty, !fen.contains("\n"), !fen.contains("\r"),
              moves.allSatisfy({ $0.range(of: "^[a-i][0-9][a-i][0-9]$", options: .regularExpression) != nil }) else {
            stop()
            error = "棋局格式无效，请重新摆盘。"
            status = "无法分析"
            return
        }
        let request = Request(fen: fen, moves: moves, revision: revision,
                              ticket: requestTicket, movetime: min(10_000, max(100, movetime)),
                              expectedPVCount: min(3, max(1, expectedPVCount)))
        isThinking = true
        status = isReady ? "等待棋面稳定…" : "正在启动引擎…"
        if process == nil { start() }
        guard process != nil else { isThinking = false; return }
        requestStopIfSearching()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, let self, self.ticket == requestTicket else { return }
            self.pending = request
            self.dispatchIfReady()
        }
    }

    func stop() {
        ticket += 1
        latestRevision = nil
        rows = []
        lineAssembler = nil
        debounceTask?.cancel()
        debounceTask = nil
        pending = nil
        isThinking = false
        requestStopIfSearching()
        if isReady { status = "分析已暂停" }
    }

    func shutdown() {
        stop()
        shutdownRequested = true
        timeoutTask?.cancel()
        isReady = false
        status = "已停止"
        guard let process else { return }
        if process.isRunning {
            send("quit")
            let connection = generation
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self, self.generation == connection else { return }
                if self.process?.isRunning == true { self.process?.terminate() }
            }
        }
    }

    private func requestStopIfSearching() {
        guard running != nil, !stopRequested else { return }
        stopRequested = true
        send("stop")
        armTimeout(seconds: 5, message: "引擎未能结束上一个局面的分析，请重新启动。")
    }

    private func dispatchIfReady() {
        guard isReady, !shutdownRequested, running == nil, let request = pending,
              request.ticket == ticket else { return }
        pending = nil
        running = request
        lineAssembler = EngineLineGroupAssembler(expectedPVCount: request.expectedPVCount)
        stopRequested = false
        isThinking = true
        status = "正在分析…"
        let history = request.moves.isEmpty ? "" : " moves " + request.moves.joined(separator: " ")
        send("position fen \(request.fen)\(history)")
        send("go movetime \(request.movetime)")
        armTimeout(seconds: Double(request.movetime) / 1000 + 12,
                   message: "引擎分析超时，请重新启动分析器。")
    }

    private func receive(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = String(decoding: outputBuffer[..<newline], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            outputBuffer.removeSubrange(...newline)
            handle(line)
        }
        if outputBuffer.count > 262_144 { outputBuffer.removeAll() }
    }

    private func handle(_ line: String) {
        guard !shutdownRequested else { return }
        if line.hasPrefix("id name ") {
            engineName = String(line.dropFirst(8))
        } else if line.hasPrefix("option name "), let boundary = line.range(of: " type ") {
            let name = String(line[line.index(line.startIndex, offsetBy: 12)..<boundary.lowerBound])
            options[name] = line
        } else if line == "uciok", handshake == "uci" {
            handshake = "ready"
            setOption("Threads", "4")
            setOption("Hash", "128")
            setOption("MultiPV", "3")
            setOption("Ponder", "false")
            setOption("EvalFile", networkURL.path)
            if options["ScoreType"]?.contains("var PawnValueNormalized") == true {
                setOption("ScoreType", "PawnValueNormalized")
                usesNormalizedPawnScore = true
            }
            if options["UCI_ShowWDL"] != nil {
                setOption("UCI_ShowWDL", "true")
                supportsWDL = true
            }
            send("isready")
        } else if line == "readyok", handshake == "ready" {
            handshake = nil
            timeoutTask?.cancel()
            isReady = true
            status = "就绪"
            dispatchIfReady()
        } else if line.hasPrefix("info ") {
            guard let request = running, request.ticket == ticket, !stopRequested,
                  let result = Self.parseInfo(line) else { return }
            guard let complete = lineAssembler?.append(result) else { return }
            rows = complete
            onResults?(request.revision, rows, false)
        } else if line.hasPrefix("bestmove") {
            guard let request = running else { return }
            timeoutTask?.cancel()
            let publish = request.ticket == ticket && !stopRequested
            running = nil
            stopRequested = false
            if publish {
                rows = lineAssembler?.latestComplete ?? []
                isThinking = false
                status = rows.isEmpty ? "当前局面没有可用着法" : "分析完成"
                onResults?(request.revision, rows, true)
            }
            lineAssembler = nil
            dispatchIfReady()
        }
    }

    private func setOption(_ name: String, _ value: String) {
        guard options[name] != nil else { return }
        send("setoption name \(name) value \(value)")
    }

    private func send(_ command: String) {
        guard let process, process.isRunning, let inputPipe else { return }
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8))
        } catch {
            fail("无法与引擎通信：\(error.localizedDescription)")
        }
    }

    private func armTimeout(seconds: Double, message: String) {
        timeoutTask?.cancel()
        let connection = generation
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.generation == connection else { return }
            self.fail(message)
            if self.process?.isRunning == true { self.process?.terminate() }
        }
    }

    private func fail(_ message: String) {
        ticket += 1
        debounceTask?.cancel()
        timeoutTask?.cancel()
        pending = nil
        lineAssembler = nil
        rows = []
        isReady = false
        isThinking = false
        error = message
        status = "引擎异常"
        if process?.isRunning == true { process?.terminate() }
    }

    private func didExit(_ exitCode: Int32) {
        timeoutTask?.cancel()
        running = nil
        lineAssembler = nil
        stopRequested = false
        handshake = nil
        isReady = false
        isThinking = false
        releasePipes()
        process = nil
        if shutdownRequested {
            status = "已停止"
        } else if error == nil {
            let detail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            fail("引擎已退出（\(exitCode)）" + (detail.isEmpty ? "" : "：\(detail)"))
        }
    }

    private func releasePipes() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? inputPipe?.fileHandleForWriting.close()
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
    }

    /// This parser intentionally does not turn evaluation into a made-up win rate.
    nonisolated static func parseInfo(_ text: String) -> EngineLine? {
        let tokens = text.split(separator: " ").map(String.init)
        guard tokens.first == "info", !tokens.contains("lowerbound"), !tokens.contains("upperbound"),
              let scoreIndex = tokens.firstIndex(of: "score"), scoreIndex + 2 < tokens.count,
              let value = Int(tokens[scoreIndex + 2]), let pvIndex = tokens.firstIndex(of: "pv"),
              pvIndex + 1 < tokens.count else { return nil }
        let score: EngineScore
        switch tokens[scoreIndex + 1] {
        case "cp": score = .cp(value)
        case "mate": score = .mate(value)
        default: return nil
        }
        func integer(_ key: String) -> Int? {
            guard let index = tokens.firstIndex(of: key), index + 1 < tokens.count else { return nil }
            return Int(tokens[index + 1])
        }
        let rank = integer("multipv") ?? 1
        guard (1...3).contains(rank) else { return nil }
        var wdl: EngineWDL?
        if let index = tokens.firstIndex(of: "wdl"), index + 3 < tokens.count,
           let wins = Int(tokens[index + 1]), let draws = Int(tokens[index + 2]),
           let losses = Int(tokens[index + 3]), wins >= 0, draws >= 0, losses >= 0,
           wins + draws + losses == 1000 {
            wdl = EngineWDL(wins: wins, draws: draws, losses: losses)
        }
        return EngineLine(rank: rank, depth: integer("depth") ?? 0, score: score,
                          pv: Array(tokens[(pvIndex + 1)...]), timeMS: integer("time"),
                          nodes: integer("nodes").flatMap { $0 >= 0 ? UInt64($0) : nil }, wdl: wdl)
    }
}
