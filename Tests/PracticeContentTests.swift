import Foundation

@main
struct PracticeContentTests {
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw StudyError.invalidContent(message) }
    }

    private struct ProbeResult {
        let bestMove: String
        let score: String
        let output: String
    }

    /// A bounded real-engine check. The engine gets time to finish its search before quit.
    private static func probe(_ position: Position, binary: String, firstMove: String? = nil,
                              movetime: Int = 350) throws -> ProbeResult {
        guard let network = ProcessInfo.processInfo.environment["XQ_ENGINE_NETWORK"],
              (network as NSString).isAbsolutePath, !network.contains("\n"), !network.contains("\r"),
              FileManager.default.isReadableFile(atPath: network) else {
            throw StudyError.invalidContent("--placement requires XQ_ENGINE_NETWORK")
        }
        let process = Process()
        let input = Pipe(), output = Pipe()
        let lock = NSLock()
        let finished = DispatchSemaphore(value: 0)
        var captured = ""
        var signaled = false
        process.executableURL = URL(fileURLWithPath: binary)
        process.currentDirectoryURL = URL(fileURLWithPath: binary).deletingLastPathComponent()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock()
            captured += String(decoding: data, as: UTF8.self)
            if !signaled && captured.contains("bestmove ") {
                signaled = true
                finished.signal()
            }
            lock.unlock()
        }
        try process.run()
        let search = firstMove.map { " searchmoves \($0)" } ?? ""
        let commands = "uci\nsetoption name Threads value 1\nsetoption name Hash value 32\nsetoption name EvalFile value \(network)\nsetoption name ScoreType value PawnValueNormalized\nisready\nposition fen \(position.fen)\ngo movetime \(movetime)\(search)\n"
        input.fileHandleForWriting.write(Data(commands.utf8))
        let completed = finished.wait(timeout: .now() + 8) == .success
        input.fileHandleForWriting.write(Data("quit\n".utf8))
        try? input.fileHandleForWriting.close()
        if !completed { process.terminate() }
        process.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        lock.lock(); let text = captured; lock.unlock()
        try require(completed && process.terminationStatus == 0, "引擎核查超时或失败")
        let lines = text.split(separator: "\n").map(String.init)
        let best = lines.last { $0.hasPrefix("bestmove ") }?.split(separator: " ").dropFirst().first.map(String.init) ?? "missing"
        let scoreLine = lines.last { $0.hasPrefix("info ") && $0.contains(" score ") } ?? ""
        let tokens = scoreLine.split(separator: " ").map(String.init)
        var score = "unavailable"
        if let index = tokens.firstIndex(of: "score"), index + 2 < tokens.count {
            score = tokens[index + 1] + " " + tokens[index + 2]
        }
        return ProbeResult(bestMove: best, score: score, output: text)
    }

    static func main() throws {
        if let index = CommandLine.arguments.firstIndex(of: "--placement"), CommandLine.arguments.indices.contains(index + 1) {
            var position = Position(board: Array(repeating: nil, count: 90), sideToMove: .red)
            for item in CommandLine.arguments[index + 1].split(separator: " ") {
                let token = String(item)
                guard let character = token.first, let piece = Piece(fenCharacter: character),
                      let square = Square(coordinate: String(token.dropFirst())) else { throw StudyError.invalidContent(token) }
                position[square] = piece
            }
            try position.validate()
            let firstIndex = CommandLine.arguments.firstIndex(of: "--first")
            let firstMove = firstIndex.flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
            guard let binary = ProcessInfo.processInfo.environment["XQ_ENGINE_PATH"],
                  (binary as NSString).isAbsolutePath, FileManager.default.isExecutableFile(atPath: binary) else {
                throw StudyError.invalidContent("--placement requires XQ_ENGINE_PATH")
            }
            let result = try probe(position, binary: binary, firstMove: firstMove, movetime: 1500)
            print(position.fen)
            print(result.output.split(separator: "\n").last { $0.hasPrefix("info ") && $0.contains(" score ") } ?? "missing")
            print(result.output.split(separator: "\n").last { $0.contains(" pv ") && ($0.components(separatedBy: " pv ").last?.split(separator: " ").count ?? 0) >= 7 } ?? "no long PV")
            print("BEST \(result.bestMove) \(result.score)")
            return
        }
        let lessons = PracticeCurriculum.lessons
        let sources = PracticeCurriculum.sources
        try require(lessons.count >= 24, "基础/战术/残局/实战与进阶至少24课")
        try require(lessons.filter { $0.tags.contains("进阶") }.count >= 6, "至少六个进阶主题")
        try require(Set(lessons.map(\.id)).count == lessons.count, "课程ID重复")
        let lessonIDs = Set(lessons.map(\.id))
        let sourceIDs = Set(sources.map(\.id))
        try require(sources.allSatisfy { $0.id.hasPrefix("practice-") && URL(string: $0.url)?.scheme == "https" }, "来源ID或网址错误")
        for stage in [LearningStage.foundation, .tactics, .endgame, .strategy] {
            try require(lessons.contains { $0.stage == stage }, "缺少阶段 \(stage)")
        }

        var lineIDs = Set<String>()
        var lineCount = 0, moveCount = 0
        var positionsByID: [String: [Position]] = [:]
        var errors: [String] = []
        for lesson in lessons {
            try require(lesson.lines.count >= 2, "每课至少两个实质练习：\(lesson.id)")
            try require(lesson.prerequisites.allSatisfy { lessonIDs.contains($0) && $0 != lesson.id }, "先修课程ID错误：\(lesson.id)")
            try require(!lesson.goal.isEmpty && !lesson.principle.isEmpty && !lesson.whenToAdapt.isEmpty && lesson.pitfalls.count >= 2,
                        "课程缺少目标/原则/变通/坑点：\(lesson.id)")
            try require(lesson.sourceIDs.allSatisfy { sourceIDs.contains($0) }, "课程来源不存在：\(lesson.id)")
            try require(Set(lesson.lines.map { $0.startingFEN + " " + $0.moves.map(\.uci).joined(separator: " ") }).count == lesson.lines.count,
                        "同课局面与线路同时重复：\(lesson.id)")
            for line in lesson.lines {
                lineCount += 1
                try require(lineIDs.insert(line.id).inserted, "线路ID重复：\(line.id)")
                try require(!line.intent.isEmpty && !line.adaptation.isEmpty && !line.moves.isEmpty, "线路缺少内容：\(line.id)")
                try require(line.moves.allSatisfy { !$0.explanation.isEmpty && !$0.hint.isEmpty }, "走法缺少说明或提示：\(line.id)")
                if lesson.tags.contains("进阶") {
                    try require((3...7).contains(line.moves.count), "进阶线路需有3至7半步：\(line.id)")
                    try require((line.moves.count + 1) / 2 >= 2, "进阶线路需有至少两次学生决策：\(line.id)")
                }
                do {
                    let positions = try line.positions()
                    for position in positions { try position.validate() }
                    positionsByID[line.id] = positions
                    moveCount += line.moves.count
                } catch {
                    errors.append("\(line.id): \(error.localizedDescription)\n  \(line.startingFEN)\n  \(line.moves.map(\.uci).joined(separator: " "))")
                }
            }
        }
        if !errors.isEmpty {
            FileHandle.standardError.write(Data((errors.joined(separator: "\n") + "\n").utf8))
            throw StudyError.invalidContent("\(errors.count) 条线路未通过合法性核查")
        }

        let mates = ["practice-mate-rook-horse", "practice-mate-horse-rook", "practice-mate-discovered-cannon",
                     "practice-mate-rook-cannon", "practice-mate-single-rook", "practice-mate-king-first",
                     "practice-mate-double-rook", "practice-mate-double-rook-setup", "practice-mate-pawn-stalemate",
                     "practice-advanced-guard-horse", "practice-advanced-counter-capture", "practice-advanced-pawn-after-trade",
                     "practice-advanced-pawn-wait", "practice-advanced-two-pawns", "practice-advanced-king-rook-plan",
                     "practice-advanced-horse-cannon-plan"]
        let stalemates: Set<String> = ["practice-mate-pawn-stalemate", "practice-advanced-guard-horse",
                                      "practice-advanced-pawn-after-trade", "practice-advanced-pawn-wait", "practice-advanced-two-pawns"]
        for id in mates {
            let terminal = positionsByID[id]!.last!
            try require(terminal.sideToMove == .black && terminal.legalMoves().isEmpty, "所称收尾未成立：\(id)")
            try require(terminal.isInCheck(.black) == !stalemates.contains(id), "将死/困毙分类错误：\(id)")
        }

        // Verify concrete captures without turning illustrative opponent replies into forced claims.
        let horseFork = positionsByID["practice-checkgain-fork"]!.last!
        try require(!horseFork.board.contains(Piece(side: .black, kind: .rook)), "马将抽车没有吃到车")
        let discovered = positionsByID["practice-checkgain-discovered"]![1]
        try require(discovered.isInCheck(.black) && !discovered.board.contains(Piece(side: .black, kind: .rook)), "抽将吃车条件未成立")
        let cannonSafe = positionsByID["practice-condition-screen-absent"]![1]
        try require(!cannonSafe.legalMoves(from: Square(coordinate: "c8")!).contains(Move(uci: "c8c2")!), "无炮架时却可回吃")
        let cannonTrap = positionsByID["practice-condition-screen-present"]![0]
        let greedy = try cannonTrap.applying(move: Move(uci: "a2c2")!)
        try require(greedy.legalMoves(from: Square(coordinate: "c8")!).contains(Move(uci: "c8c2")!), "贪吃对比例缺少炮回吃")

        if let flag = CommandLine.arguments.firstIndex(of: "--engine"), CommandLine.arguments.indices.contains(flag + 1) {
            let binary = CommandLine.arguments[flag + 1]
            let onlyIndex = CommandLine.arguments.firstIndex(of: "--only")
            let selectedIDs: Set<String>? = onlyIndex.flatMap { index in
                guard CommandLine.arguments.indices.contains(index + 1) else { return nil }
                return Set(CommandLine.arguments[index + 1].split(separator: ",").map(String.init))
            }
            for lesson in lessons {
                for line in lesson.lines {
                    if let selectedIDs, !selectedIDs.contains(line.id) { continue }
                    let initial = positionsByID[line.id]![0]
                    let best = try probe(initial, binary: binary)
                    let chosen = try probe(initial, binary: binary, firstMove: line.moves[0].uci)
                    print("ENGINE \(line.id): best=\(best.bestMove) \(best.score); lesson=\(chosen.bestMove) \(chosen.score)")
                    try require(chosen.bestMove == line.moves[0].uci, "引擎未接受课程首着：\(line.id)")
                }
            }
            for id in mates {
                let terminal = positionsByID[id]!.last!
                let result = try probe(terminal, binary: binary, movetime: 100)
                try require(result.bestMove == "(none)" || result.bestMove == "0000", "引擎仍发现合法回应：\(id)")
                print("TERMINAL \(id): \(result.bestMove) \(result.score)")
            }
        }
        let startingCount = Set(lessons.flatMap(\.lines).map(\.startingFEN)).count
        print("PASS: \(lessons.count) lessons, \(lineCount) distinct lines, \(startingCount) starting positions, \(moveCount) legal plies; \(mates.count) terminal claims verified")
    }
}
