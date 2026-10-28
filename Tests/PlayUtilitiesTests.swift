import Foundation
import SwiftUI
import AppKit

@main @MainActor struct PlayUtilitiesTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
        var clock = LocalChessClock(seconds: 60)
        check(clock.runningSide == nil && clock.timedOut == nil, "Clock starts paused")
        clock.advance(now: 500)
        check(clock.redRemaining == 60 && clock.blackRemaining == 60, "Paused clock never burns time")
        clock.start(turn: .red, now: 100)
        clock.advance(now: 102.5)
        check(near(clock.redRemaining, 57.5) && clock.blackRemaining == 60, "Only the running side loses elapsed time")
        clock.advance(now: 101); clock.advance(now: .nan)
        check(near(clock.redRemaining, 57.5), "Backward and nonfinite timestamps are ignored without rebasing")
        clock.completedMove(nextTurn: .black, now: 104)
        check(clock.redRemaining == 56 && clock.runningSide == .black, "A committed move switches exactly once")
        clock.pause(now: 107)
        check(clock.blackRemaining == 57 && clock.runningSide == nil, "Pause accounts for time through the pause instant")
        clock.completedMove(nextTurn: .red, now: 800)
        check(clock.runningSide == nil && clock.blackRemaining == 57, "Paused moves do not secretly restart time")
        clock.start(turn: .black, now: 1_000); clock.advance(now: 1_057)
        check(clock.blackRemaining == 0 && clock.timedOut == .black && clock.runningSide == nil, "Exact zero stops and flags the correct side")
        clock.start(turn: .red, now: 1_058)
        check(clock.runningSide == nil, "Timeout cannot be bypassed by restarting")
        clock = LocalChessClock(seconds: 20)
        clock.start(turn: .black, now: 10); clock.completedMove(nextTurn: .red, now: 15, terminal: true)
        check(clock.blackRemaining == 15 && clock.runningSide == nil, "Winning move pauses instead of charging the loser")
        clock.start(turn: .red, now: 20); clock.advance(now: 1_000)
        check(clock.redRemaining == 0 && clock.blackRemaining == 15, "Long update gaps charge only the actual active side")
        check(LocalChessClock(seconds: .nan).redRemaining == 600, "NaN configuration uses a safe default")
        check(LocalChessClock(seconds: -1).redRemaining == 1 && LocalChessClock(seconds: 9_999).redRemaining == 7_200, "Clock inputs are bounded")
        check(LocalChessClock.text(60) == "01:00" && LocalChessClock.text(0.1) == "00:01" && LocalChessClock.text(.infinity) == "00:00", "Time rendering rounds up and handles invalid values")
        check(BoardColorway.allCases.count == 5 && PieceColorway.allCases.count == 5, "Exactly five optional board and piece palettes")
        check(PlayPreferences().appearance == BoardAppearance() && !PlayPreferences().soundEnabled && !PlayPreferences().captureSoundEnabled && !PlayPreferences().clockEnabled,
              "Warm C and quiet untimed play remain the defaults")
        check(PlayPreferences().clockIncrementSeconds == 0 && LocalChessClock().incrementSeconds == 0, "Increment is opt-in and defaults to zero")
        check(LocalChessClock.text(7_200) == "120:00", "Two-hour clocks must not be truncated to one hour")
        for minute in 1...120 {
            var preferences = PlayPreferences(); preferences.clockMinutes = minute
            try preferences.validate()
            check(LocalChessClock(seconds: Double(minute * 60)).redRemaining == Double(minute * 60), "Every minute from 1 through 120 is supported, not only presets")
        }
        for increment in 0...60 {
            var preferences = PlayPreferences(); preferences.clockIncrementSeconds = increment
            try preferences.validate()
            check(LocalChessClock(increment: Double(increment)).incrementSeconds == Double(increment), "Every increment from 0 through 60 is supported")
        }
        var incrementClock = LocalChessClock(seconds: 60, increment: 10)
        check(!incrementClock.isLow(.red), "Exactly one minute is not below one minute")
        incrementClock.start(turn: .red, now: 0); incrementClock.advance(now: 1)
        check(incrementClock.isLow(.red), "Only strictly below 60 seconds shows gentle low-time status")
        incrementClock.completedMove(nextTurn: .black, now: 5)
        check(incrementClock.redRemaining == 65 && incrementClock.blackRemaining == 60 && incrementClock.runningSide == .black,
              "Increment rewards the mover after subtracting elapsed time, then switches sides")
        check(!incrementClock.isLow(.red), "An increment back above a minute clears the low-time status")
        incrementClock.completedMove(nextTurn: .black, now: 5)
        check(incrementClock.redRemaining == 65 && incrementClock.blackRemaining == 60, "Duplicate or same-side completion cannot add seconds twice")
        incrementClock.pause(now: 7); incrementClock.completedMove(nextTurn: .red, now: 9)
        check(incrementClock.blackRemaining == 58 && incrementClock.runningSide == nil, "Paused completion does not award an increment")
        incrementClock = LocalChessClock(seconds: 1, increment: 60)
        incrementClock.start(turn: .red, now: 0); incrementClock.completedMove(nextTurn: .black, now: 1)
        check(incrementClock.redRemaining == 0 && incrementClock.timedOut == .red && !incrementClock.isLow(.red), "Flag fall is final; increment cannot rescue a timed-out player")
        incrementClock = LocalChessClock(seconds: 20, increment: 4)
        incrementClock.start(turn: .black, now: 0); incrementClock.completedMove(nextTurn: .red, now: 5, terminal: true)
        check(incrementClock.blackRemaining == 19 && incrementClock.runningSide == nil, "A legal winning move receives its increment without starting the losing clock")
        incrementClock = LocalChessClock(seconds: 7_200, increment: 60)
        incrementClock.start(turn: .red, now: 0)
        for turn in 0..<3_000 { incrementClock.completedMove(nextTurn: turn.isMultiple(of: 2) ? .black : .red, now: 0) }
        check(incrementClock.redRemaining == LocalChessClock.maximumRemaining && incrementClock.blackRemaining == LocalChessClock.maximumRemaining,
              "Accumulated clock values remain safely bounded")
        check(LocalChessClock(increment: .nan).incrementSeconds == 0 && LocalChessClock(increment: -1).incrementSeconds == 0 && LocalChessClock(increment: 61).incrementSeconds == 60,
              "Nonfinite and out-of-range increments cannot reach arithmetic")

        let base = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("xiangqi-play-utilities-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefsURL = directory.appendingPathComponent("preferences.json")
        let missing = try PlayPreferencesStore.read(from: prefsURL)
        check(missing == PlayPreferences() && !FileManager.default.fileExists(atPath: prefsURL.path), "Reading absent settings does not write anything")
        for board in BoardColorway.allCases {
            for pieces in PieceColorway.allCases {
                var prefs = PlayPreferences(); prefs.appearance = BoardAppearance(board: board, pieces: pieces)
                try PlayPreferencesStore.write(prefs, to: prefsURL)
                let read = try PlayPreferencesStore.read(from: prefsURL)
                check(read == prefs, "All 25 combinations round-trip without global defaults")
            }
        }
        let corruptURL = directory.appendingPathComponent("corrupt.json")
        let corrupt = Data("{broken".utf8); try corrupt.write(to: corruptURL)
        do { try PlayPreferencesStore.write(PlayPreferences(), to: corruptURL); preconditionFailure("Corrupt preferences must not be overwritten") }
        catch { checks += 1 }
        let retained = try Data(contentsOf: corruptURL)
        check(retained == corrupt, "Original corrupt preferences remain byte-identical")
        let oversized = directory.appendingPathComponent("oversized.json")
        try Data(repeating: 32, count: PlayPreferencesStore.maximumBytes + 1).write(to: oversized)
        do { _ = try PlayPreferencesStore.read(from: oversized); preconditionFailure("Oversized preferences must be rejected") }
        catch { checks += 1 }
        let link = directory.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: prefsURL)
        do { try PlayPreferencesStore.write(PlayPreferences(), to: link); preconditionFailure("Settings must not follow links") }
        catch { checks += 1 }
        var invalidPrefs = PlayPreferences(); invalidPrefs.version = 2
        do { try invalidPrefs.validate(); preconditionFailure("Future schema is not silently accepted") } catch { checks += 1 }
        invalidPrefs.version = 1; invalidPrefs.clockMinutes = 0
        do { try invalidPrefs.validate(); preconditionFailure("Invalid duration is rejected") } catch { checks += 1 }
        invalidPrefs.clockMinutes = 10; invalidPrefs.soundVolume = 1.5
        do { try invalidPrefs.validate(); preconditionFailure("Invalid sound volume is rejected") } catch { checks += 1 }
        let originalPreferences = Data("{\"version\":1,\"appearance\":{\"board\":\"warmMaple\",\"pieces\":\"ivory\"},\"soundEnabled\":true,\"clockEnabled\":false,\"clockMinutes\":10}".utf8)
        let migratedPreferences = try JSONDecoder().decode(PlayPreferences.self, from: originalPreferences)
        check(migratedPreferences.soundEnabled && !migratedPreferences.captureSoundEnabled && migratedPreferences.soundVolume == 0.35 && migratedPreferences.clockIncrementSeconds == 0,
              "Earlier preferences retain move toggle without silently enabling new capture sounds")

        var now: TimeInterval = 100, sounds = 0
        let modelDirectory = directory.appendingPathComponent("model", isDirectory: true)
        let testEngine = PikafishEngine(binaryURL: directory.appendingPathComponent("no-engine"), networkURL: directory.appendingPathComponent("no-network"))
        let model = GameModel(directory: modelDirectory, clockNow: { now }, moveSound: { sounds += 1 }, engine: testEngine)
        model.setClockMinutes(3); model.setClockEnabled(true)
        model.startClock()
        check(model.chessClock.runningSide == nil, "Analysis mode cannot start a clock")
        model.startLocalTwoPlayer(); model.startClock(); now = 105
        model.play(Move(uci: "a0a9")!)
        check(model.moves.isEmpty && model.chessClock.runningSide == .red && model.chessClock.redRemaining == 175,
              "Illegal move consumes real elapsed time but cannot switch sides")
        model.play(Move(uci: "a3a4")!)
        check(model.moves.count == 1 && model.chessClock.runningSide == .black && model.chessClock.redRemaining == 175,
              "Actual legal move advances board and clock together")
        check(sounds == 0, "Sound remains off by default")
        model.setMoveSound(true); now = 110
        model.play(Move(uci: "a6a5")!)
        check(sounds == 1 && model.chessClock.runningSide == .red && model.chessClock.blackRemaining == 175, "One legal move produces one opt-in short sound")
        model.play(Move(uci: "a0a9")!)
        check(sounds == 1, "Illegal moves produce no move sound")
        now = 115; model.navigate(to: 1)
        check(model.chessClock.runningSide == nil && model.chessClock.redRemaining == 170, "Browsing pauses immediately")
        now = 300; model.startClock(); model.tickClock()
        check(model.chessClock.runningSide == nil && model.chessClock.redRemaining == 170, "Historical boards cannot tick or resume clocks")
        model.navigate(to: 2)
        check(model.chessClock.runningSide == nil, "Returning to latest does not automatically restart")
        model.startClock(); now = 310; model.openPlayUtilities()
        check(model.chessClock.runningSide == nil && model.chessClock.redRemaining == 160, "Opening utilities pauses")
        model.startClock()
        check(model.chessClock.runningSide == nil, "A modal cannot start an invisible clock")
        model.showPlayUtilities = false; model.startClock(); now = 320; model.startManualAnalysis()
        check(model.chessClock.runningSide == nil && model.chessClock.redRemaining == 150, "Mode switch pauses without resetting elapsed time")
        model.startLocalTwoPlayer(); model.resetClock(); model.startClock(); now = 500; model.tickClock()
        check(model.chessClock.timedOut == .red && model.stateLabel.contains("超时"), "Model surfaces flag fall")
        let count = model.moves.count
        model.play(Move(uci: "c3c4")!)
        check(model.moves.count == count && sounds == 1, "Timed-out boards reject further local timed play")
        model.resetClock()
        check(model.chessClock.timedOut == nil && model.chessClock.redRemaining == 180 && model.chessClock.runningSide == nil, "Explicit reset clears flag fall and stays paused")
        model.startClock(); now = 501; model.setClockEnabled(false)
        check(model.chessClock.runningSide == nil, "Disabling clock immediately pauses")
        model.setBoardColorway(.blueMist); model.setPieceColorway(.porcelain)
        let savedRecord = try model.currentRecord.encoded()
        model.setMoveSound(false)
        let afterRecord = try model.currentRecord.encoded()
        check(savedRecord == afterRecord, "Preferences never change record ID, moves, metadata, or annotations")
        let restored = GameModel(directory: modelDirectory, clockNow: { now }, moveSound: { sounds += 1 })
        check(restored.playPreferences == model.playPreferences && restored.chessClock.runningSide == nil,
              "Only preferences survive restart; timers are explicitly paused")
        check(!restored.engine.isRunning && !model.engine.isRunning, "Utility tests never start an engine")
        model.shutdown(); restored.shutdown()

        var incrementNow: TimeInterval = 0
        let incrementDirectory = directory.appendingPathComponent("increment", isDirectory: true)
        let incrementEngine = PikafishEngine(binaryURL: directory.appendingPathComponent("no-engine"), networkURL: directory.appendingPathComponent("no-network"))
        let timedModel = GameModel(directory: incrementDirectory, clockNow: { incrementNow }, engine: incrementEngine)
        timedModel.startLocalTwoPlayer(); timedModel.setClockMinutes(1); timedModel.setClockIncrement(5); timedModel.setClockEnabled(true)
        timedModel.startClock(); incrementNow = 2; timedModel.play(Move(uci: "a0a9")!)
        check(timedModel.chessClock.redRemaining == 58 && timedModel.chessClock.blackRemaining == 60, "Illegal moves cannot mint increment seconds")
        timedModel.play(Move(uci: "a3a4")!)
        check(timedModel.chessClock.redRemaining == 63 && timedModel.chessClock.runningSide == .black, "Legal model move awards exactly the configured increment")
        incrementNow = 3; timedModel.pauseClock(); timedModel.play(Move(uci: "a6a5")!)
        check(timedModel.chessClock.blackRemaining == 59 && timedModel.chessClock.runningSide == nil, "Untimed moves while paused receive no increment")
        timedModel.navigate(to: 0); timedModel.play(Move(uci: "c3c4")!)
        check(timedModel.chessClock.redRemaining == 63 && timedModel.chessClock.blackRemaining == 59, "Trying an earlier variation cannot farm clock increment")
        timedModel.setClockMinutes(120); timedModel.setClockIncrement(60)
        check(timedModel.chessClock.redRemaining == 7_200 && timedModel.chessClock.incrementSeconds == 60 && timedModel.chessClock.runningSide == nil,
              "Updating parameters resets both clocks and does not auto-start")
        timedModel.setClockMinutes(121); timedModel.setClockIncrement(61)
        check(timedModel.playPreferences.clockMinutes == 120 && timedModel.playPreferences.clockIncrementSeconds == 60, "Invalid parameter edits preserve last valid settings")
        let timedRestored = GameModel(directory: incrementDirectory)
        check(timedRestored.playPreferences.clockMinutes == 120 && timedRestored.playPreferences.clockIncrementSeconds == 60 && timedRestored.chessClock.incrementSeconds == 60,
              "Increment and arbitrary supported duration persist in isolated preferences")
        timedModel.shutdown(); timedRestored.shutdown()

        var events: [(MoveSoundEvent, Double)] = []
        let audioDirectory = directory.appendingPathComponent("audio", isDirectory: true)
        let audioEngine = PikafishEngine(binaryURL: directory.appendingPathComponent("no-engine"), networkURL: directory.appendingPathComponent("no-network"))
        let audioModel = GameModel(directory: audioDirectory, engine: audioEngine, soundPlayer: { events.append(($0, $1)) })
        audioModel.startLocalTwoPlayer(); audioModel.setMoveSound(true)
        for text in ["a3a4", "a6a5", "a4a5"] { audioModel.play(Move(uci: text)!) }
        check(events.map(\.0) == [.move, .move], "Capture does not play the move sound when capture sound is disabled")
        audioModel.setMoveSound(false); audioModel.setCaptureSound(true); audioModel.newGame()
        for text in ["a3a4", "a6a5", "a4a5"] { audioModel.play(Move(uci: text)!) }
        check(events.map(\.0) == [.move, .move, .capture], "Capture toggle works independently without duplicate move sound")
        audioModel.setSoundVolume(0.7); audioModel.previewSound(.move); audioModel.previewSound(.capture)
        check(events.suffix(2).map(\.0) == [.move, .capture] && events.suffix(2).allSatisfy { $0.1 == 0.7 }, "Both explicit previews use the selected volume")
        check(!audioModel.playPreferences.soundEnabled && audioModel.playPreferences.captureSoundEnabled, "Preview does not modify automatic sound switches")
        let eventCount = events.count
        audioModel.setSoundVolume(0); audioModel.previewSound(.move); audioModel.previewSound(.capture)
        check(events.count == eventCount, "Zero volume is silent, including previews")
        audioModel.setSoundVolume(9)
        check(audioModel.playPreferences.soundVolume == 1, "Volume is upper bounded")
        audioModel.setSoundVolume(.nan)
        check(audioModel.playPreferences.soundVolume == 1, "NaN volume cannot reach the system player")
        audioModel.setSoundVolume(-1)
        check(audioModel.playPreferences.soundVolume == 0, "Volume is lower bounded")
        let audioRestored = GameModel(directory: audioDirectory)
        check(!audioRestored.playPreferences.soundEnabled && audioRestored.playPreferences.captureSoundEnabled && audioRestored.playPreferences.soundVolume == 0,
              "Both toggles and volume persist only in the isolated preference file")
        audioModel.shutdown(); audioRestored.shutdown()

        func luminance(_ color: Color) -> Double {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            func linear(_ x: CGFloat) -> Double { let value = Double(x); return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
        }
        func contrast(_ a: Color, _ b: Color) -> Double { let x = luminance(a), y = luminance(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }
        for style in BoardColorway.allCases {
            let colors = BoardSurfaceColors(style)
            for background in [colors.upper, colors.fill, colors.lower] {
                check(contrast(colors.coordinate, background) >= 4.5, "Board coordinates remain readable in all palettes")
                for rank in 1...3 { check(contrast(Palette.candidate(rank), background) >= 3, "All Top 3 arrows contrast against each board palette") }
            }
        }
        for style in PieceColorway.allCases {
            let colors = PieceSurfaceColors(style)
            for background in [colors.face, colors.low] {
                check(contrast(WarmBoardPalette.redInk, background) >= 4.5, "Red glyphs remain legible")
                check(contrast(WarmBoardPalette.blackInk, background) >= 4.5, "Black glyphs remain legible")
            }
        }
        let position = try Position.initial.applying(move: Move(uci: "a3a4")!)
        let normal = try BoardPNGExporter.png(position: position, flipped: false, width: 366)
        let flipped = try BoardPNGExporter.png(position: position, flipped: true, width: 366)
        let recolored = try BoardPNGExporter.png(position: position, flipped: false, appearance: .init(board: .blueMist, pieces: .porcelain), width: 366)
        check(normal.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]), "Export is an actual PNG, not screen content or a mislabeled file")
        let bitmap = NSBitmapImageRep(data: normal)!
        check(bitmap.pixelsWide == 366 && abs(bitmap.pixelsHigh - 410) <= 1, "PNG uses fixed, bounded board geometry")
        check(normal != flipped && normal != recolored, "Orientation and chosen palettes affect exported chess content")
        check(normal.count < 1_024 * 1_024, "Small vector board export stays lightweight")
        for badWidth in [0, 255, 2_049, Int.max] {
            do { _ = try BoardPNGExporter.png(position: position, flipped: false, width: badWidth); preconditionFailure("Unsafe raster size") }
            catch { checks += 1 }
        }
        if let output = ProcessInfo.processInfo.environment["XQ_UTILITY_PREVIEW_DIR"] {
            let preview = URL(fileURLWithPath: output, isDirectory: true)
            try normal.write(to: preview.appendingPathComponent("normal.png"))
            try flipped.write(to: preview.appendingPathComponent("flipped.png"))
            try recolored.write(to: preview.appendingPathComponent("blue.png"))
            let utilityRenderer = ImageRenderer(content: PlayUtilitiesView(model: model))
            if let image = utilityRenderer.cgImage,
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try data.write(to: preview.appendingPathComponent("tools.png"))
            }
            let clockRenderer = ImageRenderer(content: LocalChessClockView(model: model).padding(16).frame(width: 280).background(Studio.paper))
            if let image = clockRenderer.cgImage,
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try data.write(to: preview.appendingPathComponent("clock.png"))
            }
        }
        print("PASS: \(checks) play-utility checks; clock uses injected time; no engine/audio/user-store access")
    }
}
