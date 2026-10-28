import Foundation

enum BoardColorway: String, CaseIterable, Codable {
    case warmMaple, ricePaper, paleJade, blueMist, roseClay
    var title: String {
        switch self {
        case .warmMaple: return "暖枫木"
        case .ricePaper: return "米纸"
        case .paleJade: return "浅青玉"
        case .blueMist: return "雾蓝"
        case .roseClay: return "浅陶土"
        }
    }
}

enum PieceColorway: String, CaseIterable, Codable {
    case ivory, porcelain, honey, jade, slate
    var title: String {
        switch self {
        case .ivory: return "象牙白"
        case .porcelain: return "白瓷"
        case .honey: return "浅蜜木"
        case .jade: return "青瓷"
        case .slate: return "灰石"
        }
    }
}

struct BoardAppearance: Codable, Equatable {
    var board: BoardColorway = .warmMaple
    var pieces: PieceColorway = .ivory
}

struct PlayPreferences: Codable, Equatable {
    var version = 1
    var appearance = BoardAppearance()
    var soundEnabled = false
    var captureSoundEnabled = false
    var soundVolume = 0.35
    var clockEnabled = false
    var clockMinutes = 10
    var clockIncrementSeconds = 0
    static let supportedMinutes = Array(1...120)
    static let supportedIncrementSeconds = 0...60

    init() { }
    private enum CodingKeys: String, CodingKey {
        case version, appearance, soundEnabled, captureSoundEnabled, soundVolume, clockEnabled, clockMinutes, clockIncrementSeconds
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        appearance = try values.decode(BoardAppearance.self, forKey: .appearance)
        soundEnabled = try values.decode(Bool.self, forKey: .soundEnabled)
        captureSoundEnabled = try values.decodeIfPresent(Bool.self, forKey: .captureSoundEnabled) ?? false
        soundVolume = try values.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.35
        clockEnabled = try values.decode(Bool.self, forKey: .clockEnabled)
        clockMinutes = try values.decode(Int.self, forKey: .clockMinutes)
        clockIncrementSeconds = try values.decodeIfPresent(Int.self, forKey: .clockIncrementSeconds) ?? 0
    }

    func validate() throws {
        guard version == 1, Self.supportedMinutes.contains(clockMinutes), Self.supportedIncrementSeconds.contains(clockIncrementSeconds),
              soundVolume.isFinite, (0...1).contains(soundVolume) else {
            throw PlayUtilityError.invalid("棋盘工具设置版本或时间无效。")
        }
    }
}

enum MoveSoundEvent: String, Equatable { case move, capture }

enum PlayUtilityError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

/// Small, separate preferences. Never touches session/history or global defaults.
enum PlayPreferencesStore {
    static let maximumBytes = 2_048
    static func read(from url: URL) throws -> PlayPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return PlayPreferences() }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let count = values.fileSize, count <= maximumBytes else {
            throw PlayUtilityError.invalid("工具设置不是有效的小型文件；原文件已保留。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw PlayUtilityError.invalid("工具设置过大。") }
        let preferences = try JSONDecoder().decode(PlayPreferences.self, from: data)
        try preferences.validate()
        return preferences
    }

    static func write(_ preferences: PlayPreferences, to url: URL) throws {
        try preferences.validate()
        let data = try JSONEncoder().encode(preferences)
        guard data.count <= maximumBytes else { throw PlayUtilityError.invalid("工具设置过大。") }
        // Do not follow a user-created link or overwrite a corrupt existing file.
        if FileManager.default.fileExists(atPath: url.path) { _ = try read(from: url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// An injected monotonic timestamp makes elapsed time, pauses and flag fall
/// deterministic. There is no timer, wall-clock dependency, or engine here.
struct LocalChessClock: Equatable {
    private(set) var redRemaining: TimeInterval
    private(set) var blackRemaining: TimeInterval
    private(set) var runningSide: Side?
    private(set) var timedOut: Side?
    let incrementSeconds: TimeInterval
    static let maximumRemaining: TimeInterval = 86_400
    private var lastTick: TimeInterval?

    init(seconds: TimeInterval = 600, increment: TimeInterval = 0) {
        let valid = seconds.isFinite ? max(1, min(7_200, seconds)) : 600
        incrementSeconds = increment.isFinite ? max(0, min(60, increment)) : 0
        redRemaining = valid; blackRemaining = valid
    }

    func remaining(_ side: Side) -> TimeInterval { side == .red ? redRemaining : blackRemaining }
    func isLow(_ side: Side) -> Bool { remaining(side) > 0 && remaining(side) < 60 }

    mutating func start(turn: Side, now: TimeInterval) {
        guard timedOut == nil, now.isFinite else { return }
        if runningSide != nil { pause(now: now) }
        guard timedOut == nil else { return }
        runningSide = turn; lastTick = now
    }

    mutating func advance(now: TimeInterval) {
        guard let side = runningSide, let last = lastTick, now.isFinite, now >= last else { return }
        let remaining = max(0, remaining(side) - (now - last))
        if side == .red { redRemaining = remaining } else { blackRemaining = remaining }
        lastTick = now
        if remaining <= 0 { timedOut = side; runningSide = nil; lastTick = nil }
    }

    mutating func pause(now: TimeInterval) {
        advance(now: now); runningSide = nil; lastTick = nil
    }

    /// Call only after a legal move was committed; a paused clock stays paused.
    mutating func completedMove(nextTurn: Side, now: TimeInterval, terminal: Bool = false) {
        guard let mover = runningSide, nextTurn == mover.opponent,
              let last = lastTick, now.isFinite, now >= last else { return }
        pause(now: now)
        guard timedOut == nil else { return }
        if mover == .red { redRemaining = min(Self.maximumRemaining, redRemaining + incrementSeconds) }
        else { blackRemaining = min(Self.maximumRemaining, blackRemaining + incrementSeconds) }
        if !terminal { start(turn: nextTurn, now: now) }
    }

    static func text(_ seconds: TimeInterval) -> String {
        let value = seconds.isFinite ? Int(max(0, min(Self.maximumRemaining, seconds)).rounded(.up)) : 0
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
