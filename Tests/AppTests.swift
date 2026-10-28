import Foundation
import SwiftUI
import AppKit

@main
struct AppTests {
    @MainActor
    static func main() async throws {
        let configuredBase = ProcessInfo.processInfo.environment["XQ_TEST_TEMP_DIR"]
        if let configuredBase {
            precondition((configuredBase as NSString).isAbsolutePath, "XQ_TEST_TEMP_DIR must be an absolute test-owned directory")
        }
        let base = configuredBase.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("xiangqi-app-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let configuredBase {
            let expected = URL(fileURLWithPath: configuredBase, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
            precondition(directory.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == expected,
                         "App test data escaped XQ_TEST_TEMP_DIR")
        }
        setenv("XQ_COMPANION_STATE_DIR", directory.path, 1)
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }

        // The smallest supported board must keep all 90 targets and piece glyphs legible.
        for width: CGFloat in [350, 480, 620] {
            let size = CGSize(width: width, height: width / BoardView.Layout.aspectRatio)
            let layout = BoardView.Layout(size: size)
            check(layout.pieceFontSize >= 19, "piece characters stay readable at the minimum board width")
            check(layout.hitDiameter > layout.pieceDiameter && layout.hitDiameter < layout.cell,
                  "piece hit targets are generous without overlapping adjacent intersections")
            check(layout.coordinateY - layout.coordinateFontSize * 0.65
                  > layout.origin.y + layout.cell * 9 + layout.pieceDiameter / 2,
                  "coordinate footer has clear space below the final piece row")
            check(layout.coordinateY + layout.coordinateFontSize * 0.7 < size.height - 3.5,
                  "coordinate labels stay inside the board rim at \(width) px")
            for flipped in [false, true] {
                let points = (0..<90).map { layout.point(Square(row: $0 / 9, col: $0 % 9), flipped: flipped) }
                let radius = layout.hitDiameter / 2
                check(points.allSatisfy {
                    $0.x - radius >= 0 && $0.x + radius <= size.width
                    && $0.y - radius >= 0 && $0.y + radius <= size.height
                }, "all 90 target bounds fit the board at \(width) px, flipped=\(flipped)")
                check(Set(points.map { "\($0.x),\($0.y)" }).count == 90, "each intersection has a unique hit target")
                for square in [Square(row: 0, col: 0), Square(row: 9, col: 8), Square(row: 4, col: 3)] {
                    check(layout.point(square, flipped: flipped) == BoardArrowGeometry.point(square,
                          flipped: flipped, cell: layout.cell, origin: layout.origin),
                          "arrows and visual intersections share the same layout at every size")
                }
            }
        }
        let tallLayout = BoardView.Layout(size: CGSize(width: 350, height: 600))
        check(tallLayout.origin.y > tallLayout.cell * 0.55, "letterboxed boards center the grid vertically")
        func luminance(_ color: Color) -> Double {
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            func linear(_ channel: CGFloat) -> Double {
                let value = Double(channel)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return linear(rgb.redComponent) * 0.2126 + linear(rgb.greenComponent) * 0.7152
                + linear(rgb.blueComponent) * 0.0722
        }
        func contrast(_ first: Color, _ second: Color) -> Double {
            let a = luminance(first), b = luminance(second)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        check(contrast(Palette.red, Palette.board) >= 4.5 && contrast(Palette.ink, Palette.board) >= 4.5,
              "both piece colors remain legible against the board")
        check((1...3).allSatisfy { contrast(Palette.candidate($0), Studio.onAccent) >= 4.5 },
              "Top 1/2/3 badge numbers retain readable contrast against light text")
        check(contrast(Studio.ink, Studio.paper) >= 7 && contrast(Studio.muted, Studio.white) >= 4.5,
              "warm chessroom primary and secondary copy retain readable contrast")

        // Exercise the actual canvas model, not a view-only replacement fixture.
        var graphParent = StudyLine(id: "graph", title: "reference", intent: "compare", adaptation: "conditions",
            moves: ["h2e2", "h9g7", "h0g2", "i9h9"].map { StudyMove($0, "reference") })
        graphParent.variations = [
            StudyVariation(id: "left", title: "left", anchorPly: 1, condition: "different horse", explanation: "two-ply route", moves: ["b9c7", "b0c2"].map { StudyMove($0, "alternative") }),
            StudyVariation(id: "pawn", title: "pawn", anchorPly: 1, condition: "different pawn", explanation: "one-ply route", moves: [StudyMove("a6a5", "alternative")]),
            StudyVariation(id: "late", title: "late", anchorPly: 3, condition: "later fork", explanation: "different point", moves: [StudyMove("b9c7", "alternative")]),
            StudyVariation(id: "bad", title: "bad", anchorPly: 99, condition: "invalid", explanation: "reject", moves: [StudyMove("b9c7", "invalid")])
        ]
        let graph = VariationCanvasGraph(parent: graphParent)
        let graphStates = try graphParent.positions()
        check(graph.groups.map(\.anchorPly) == [1, 3] && graph.unavailableCount == 1 && graph.branches.count == 5,
              "canvas groups real forks, preserves sibling alternatives and rejects invalid anchors")
        for branch in graph.branches {
            check(branch.positions.first == graphStates[branch.anchorPly] && branch.positions.count == branch.moves.count + 1,
                  "every branch begins at its own true anchor and has its own sequence length")
            for ply in 1...branch.moves.count {
                let next = try branch.positions[ply - 1].applying(move: Move(uci: branch.moves[ply - 1].uci)!)
                check(next == branch.positions[ply],
                      "every clickable canvas node matches a legal move on its displayed predecessor")
            }
        }
        check(graph.branches.first { $0.variationID == "left" }?.moves.count == 2 &&
              graph.branches.first { $0.id == "original-1" }?.moves.count == 3,
              "short variation does not append the unrelated historical continuation")
        let shortReferenceCursor = VariationCanvasCursor.restore(saved: nil, aligning: 8, moveCount: 3)
        check(shortReferenceCursor == 3 && VariationCanvasCursor.restore(saved: 8, aligning: shortReferenceCursor, moveCount: 8) == 8,
              "switching through a shorter reference does not erase the longer branch's saved cursor")
        check(VariationCanvasCursor.restore(saved: -10, aligning: 2, moveCount: 8) == 0 &&
              VariationCanvasCursor.restore(saved: 500, aligning: 2, moveCount: 8) == 8,
              "canvas restored cursors stay within the selected route")

        // Optional real SwiftUI snapshots: ./build/app-tests --render-board
        // Kept out of normal tests to avoid writing images on routine verification.
        if CommandLine.arguments.contains("--render-board") {
            let previews = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("build/board-previews", isDirectory: true)
            try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
            let samples: [(String, CGFloat, Bool, Bool)] = [
                ("board-350-candidates", 350, false, true),
                ("board-620-clean", 620, false, false),
                ("board-350-flipped", 350, true, true)
            ]
            for (name, width, flipped, showGuides) in samples {
                var position = Position.initial
                if showGuides {
                    position = try position.applying(move: Move(uci: "a3a4")!)
                    position = try position.applying(move: Move(uci: "a6a5")!)
                }
                let selected = Square(coordinate: "b2")!
                let moves = ["b2e2", "h2e2", "h0g2"].enumerated().map {
                    RecommendationArrow(rank: $0.offset + 1, move: Move(uci: $0.element)!)
                }
                let preview = BoardView(position: position, flipped: flipped,
                    selected: showGuides ? selected : nil,
                    targets: showGuides ? position.legalMoves(from: selected).map(\.to) : [],
                    lastMove: showGuides ? Move(uci: "a6a5") : nil,
                    arrows: showGuides ? moves : [], onTap: { _ in })
                    .frame(width: width, height: width / BoardView.Layout.aspectRatio)
                    .padding(16).background(Palette.paper)
                let renderer = ImageRenderer(content: preview)
                renderer.scale = 2
                guard let cgImage = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                    preconditionFailure("SwiftUI board preview could not render")
                }
                try png.write(to: previews.appendingPathComponent("\(name).png"))
            }
            print("Board previews: \(previews.path)")
        }

        let cell: CGFloat = 50
        let origin = CGPoint(x: 30, y: 40)
        func point(_ coordinate: String, flipped: Bool = false) -> CGPoint {
            BoardArrowGeometry.point(Square(coordinate: coordinate)!, flipped: flipped, cell: cell, origin: origin)
        }
        func close(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
            hypot(lhs.x - rhs.x, lhs.y - rhs.y) < 0.0001
        }
        func arrow(_ rank: Int, _ uci: String) -> RecommendationArrow {
            RecommendationArrow(rank: rank, move: Move(uci: uci)!)
        }
        func geometry(_ value: RecommendationArrow, all: [RecommendationArrow]? = nil,
                      flipped: Bool = false) -> BoardArrowGeometry {
            BoardArrowGeometry(arrow: value, all: all ?? [value], flipped: flipped, cell: cell, origin: origin)
        }
        func checkGeometry(_ value: RecommendationArrow, all: [RecommendationArrow]? = nil,
                           flipped: Bool = false) {
            let g = geometry(value, all: all, flipped: flipped)
            let from = BoardArrowGeometry.point(value.move.from, flipped: flipped, cell: cell, origin: origin)
            let to = BoardArrowGeometry.point(value.move.to, flipped: flipped, cell: cell, origin: origin)
            let dx = to.x - from.x, dy = to.y - from.y
            let lengthSquared = dx * dx + dy * dy
            let startProgress = (g.start.x - from.x) * dx + (g.start.y - from.y) * dy
            let tipProgress = (g.tip.x - from.x) * dx + (g.tip.y - from.y) * dy
            check(startProgress > 0 && tipProgress > startProgress && tipProgress < lengthSquared,
                  "arrow runs toward its destination, with both piece centers left clear: \(value.move.uci)")
            check([g.start, g.control, g.tip, g.headLeft, g.headRight, g.badge].allSatisfy { $0.x.isFinite && $0.y.isFinite },
                  "finite arrow geometry")
            let tangent = CGPoint(x: g.tip.x - g.control.x, y: g.tip.y - g.control.y)
            check([g.headLeft, g.headRight].allSatisfy {
                ($0.x - g.tip.x) * tangent.x + ($0.y - g.tip.y) * tangent.y < 0
            }, "arrowhead points along the final curve tangent")
            check(g.badge.x >= origin.x - cell * 0.16 && g.badge.x <= origin.x + cell * 8.16
                  && g.badge.y >= origin.y - cell * 0.16 && g.badge.y <= origin.y + cell * 9.16,
                  "rank label remains inside board margins")
        }
        check(point("a0") == CGPoint(x: 30, y: 490), "red corner maps to board bottom left")
        check(point("i9") == CGPoint(x: 430, y: 40), "black corner maps to board top right")
        check(point("a0", flipped: true) == point("i9") && point("i9", flipped: true) == point("a0"),
              "flipping rotates both ranks and files")
        let redStep = geometry(arrow(1, "e3e4"))
        let blackStep = geometry(arrow(1, "e6e5"))
        check(redStep.tip.y < redStep.start.y && blackStep.tip.y > blackStep.start.y,
              "red and black forward arrows point in opposite screen directions")
        for uci in ["e3e4", "e6e5", "b2e2", "h0g2", "e4f6", "a0a1"] {
            checkGeometry(arrow(1, uci))
            checkGeometry(arrow(1, uci), flipped: true)
        }
        let diagonal = arrow(2, "e4f6")
        let normal = geometry(diagonal)
        let rotated = geometry(diagonal, flipped: true)
        let reflection = CGPoint(x: origin.x * 2 + cell * 8, y: origin.y * 2 + cell * 9)
        for (before, after) in zip([normal.start, normal.control, normal.tip, normal.headLeft, normal.headRight, normal.badge],
                                   [rotated.start, rotated.control, rotated.tip, rotated.headLeft, rotated.headRight, rotated.badge]) {
            check(close(after, CGPoint(x: reflection.x - before.x, y: reflection.y - before.y)),
                  "flipped horse arrow and label preserve board-relative geometry")
        }
        let shared = [arrow(1, "a0a1"), arrow(2, "a0a2"), arrow(3, "a0a3")]
        let sharedGeometry = shared.map { geometry($0, all: shared) }
        check(close(sharedGeometry[0].control, CGPoint(x: (sharedGeometry[0].start.x + sharedGeometry[0].tip.x) / 2,
                                                       y: (sharedGeometry[0].start.y + sharedGeometry[0].tip.y) / 2)),
              "Top 1 stays straight on an overlapping route")
        check(sharedGeometry[1].control.x > sharedGeometry[1].start.x
              && sharedGeometry[2].control.x < sharedGeometry[2].start.x,
              "Top 2 and Top 3 separate onto opposite sides of a shared route")
        check(!close(sharedGeometry[0].badge, sharedGeometry[1].badge)
              && !close(sharedGeometry[1].badge, sharedGeometry[2].badge), "overlapping candidate numbers stay distinct")
        for value in shared { checkGeometry(value, all: shared); checkGeometry(value, all: shared, flipped: true) }
        let collinear = [arrow(1, "c3c4"), arrow(2, "c5c6")]
        let collinearSecond = geometry(collinear[1], all: collinear)
        check(collinearSecond.control.x != collinearSecond.start.x, "collinear routes separate even with distinct endpoints")

        func line(_ rank: Int, _ pv: [String]) -> EngineLine {
            EngineLine(rank: rank, depth: 12, score: .cp(30), pv: pv, timeMS: 250, nodes: 100, wdl: nil)
        }
        let candidateRows = [line(3, ["a3a4"]), line(1, ["b2e2"]), line(2, ["h2e2"])]
        func filtered(_ rows: [EngineLine], resultRevision: Int? = 7, enabled: Bool = true,
                      position: Position = .initial) -> [EngineLine] {
            CandidateDisplay.lines(rows, position: position, revision: 7, resultRevision: resultRevision, enabled: enabled)
        }
        check(filtered(candidateRows).map(\.rank) == [1, 2, 3], "candidate display orders Top 1 through Top 3")
        check(filtered(candidateRows, resultRevision: 6).isEmpty && filtered(candidateRows, resultRevision: nil).isEmpty,
              "old or missing revision never displays candidates")
        check(filtered(candidateRows, enabled: false).isEmpty, "paused analysis hides all candidates")
        let rejected = [line(0, ["b2e2"]), line(4, ["h2e2"]), line(1, []), line(2, ["bad"]),
                        line(2, ["b2b0"]), line(3, ["b9c7"])]
        check(filtered(rejected).isEmpty, "invalid rank, empty PV, malformed, illegal and wrong-side moves are hidden")
        let deduplicated = filtered([line(1, ["b2e2"]), line(2, ["b2e2"]), line(2, ["h2e2"]),
                                     line(3, ["a3a4"]), line(3, ["c3c4"])])
        check(deduplicated.count == 3 && Set(deduplicated.map(\.rank)).count == 3
              && Set(deduplicated.compactMap { $0.pv.first }).count == 3,
              "candidate set has unique ranks and first moves")
        var blackToMove = Position.initial
        blackToMove.sideToMove = .black
        check(filtered([line(1, ["b9c7"]), line(2, ["b2e2"])], position: blackToMove).map(\.pv) == [["b9c7"]],
              "candidate legality follows the current side to move")

        let model = GameModel()
        check(model.position == .initial, "initial board")
        check(model.showArrows && model.recommendationArrows.isEmpty, "arrows default on but no fabricated initial suggestions")
        // Verify real board click handling, not just model rules.
        model.tap(Square(row: 7, col: 1))
        check(model.legalTargets.contains(Square(row: 7, col: 4)), "cannon target")
        model.tap(Square(row: 7, col: 4))
        check(model.cursor == 1 && model.position.sideToMove == .black, "red manual move")
        check(model.moveNames == ["炮八平五"], "notation")
        model.play(Move(uci: "b9c7")!)
        check(model.cursor == 2 && model.position.sideToMove == .red, "black manual move")
        let afterTwo = model.position
        model.navigate(to: 1)
        check(model.cursor == 1 && model.moves.count == 2, "undo preserves redo")
        model.navigate(to: 2)
        check(model.position == afterTwo, "redo board exact")
        model.navigate(to: 1)
        model.play(Move(uci: "h9g7")!)
        check(model.moves.map(\.uci) == ["b2e2", "h9g7"], "new variation truncates only future")
        model.flip()
        model.setBudget(250)
        model.toggleArrows()
        let restored = GameModel()
        check(restored.position == model.position, "restored board")
        check(restored.moves == model.moves && restored.cursor == model.cursor, "restored history")
        check(restored.flipped && restored.milliseconds == 250, "restored preferences")
        check(!restored.showArrows, "hidden-arrow preference survives restart")
        restored.shutdown()
        model.toggleArrows()
        let restoredShown = GameModel()
        check(restoredShown.showArrows, "visible-arrow preference survives restart")
        restoredShown.shutdown()

        // Older sessions have no arrow preference; exercise the real restore path.
        let sessionURL = directory.appendingPathComponent("session.json")
        var legacyJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: sessionURL)) as! [String: Any]
        legacyJSON.removeValue(forKey: "showArrows")
        try JSONSerialization.data(withJSONObject: legacyJSON).write(to: sessionURL, options: .atomic)
        let legacy = GameModel()
        check(legacy.showArrows && legacy.position == model.position && legacy.moves == model.moves,
              "legacy session restores board and defaults arrow preference to visible")
        legacy.shutdown()

        func awaitCurrentAnalysis() async throws {
            let expected = model.revision
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline && (model.engine.isThinking || model.currentAnalysis.count < 3 || model.engine.latestRevision != expected) {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            check(model.engine.error == nil, "live engine initialization")
            check(model.engine.latestRevision == expected && model.currentAnalysis.count == 3, "live UI revision gets top three")
        }
        if ProcessInfo.processInfo.environment["XQ_RUN_ENGINE_TESTS"] == "1" {
        try await awaitCurrentAnalysis()
        for row in model.engine.rows {
            let move = Move(uci: row.pv.first!)!
            check((try? model.position.applying(move: move)) != nil, "recommended move is legal")
        }
        func checkArrowSource() {
            let fromCards = model.currentAnalysis.map { RecommendationArrow(rank: $0.rank, move: Move(uci: $0.pv.first!)!) }
            check(fromCards.count == 3 && model.recommendationArrows == fromCards,
                  "real engine arrows and candidate cards use exactly the same moves and ranks")
        }
        checkArrowSource()
        let shownArrows = model.recommendationArrows
        let shownCards = model.currentAnalysis
        let shownRevision = model.revision
        model.toggleArrows()
        check(model.recommendationArrows.isEmpty && model.currentAnalysis == shownCards && model.revision == shownRevision,
              "hiding arrows retains cards and does not restart analysis")
        model.toggleArrows()
        check(model.recommendationArrows == shownArrows, "showing arrows reuses the current candidate set")
        model.flip()
        check(model.recommendationArrows == shownArrows && model.revision == shownRevision,
              "board flip changes orientation without changing candidate moves")
        model.flip()

        let previousCursor = model.cursor
        let previousPosition = model.position
        model.play(shownArrows[0].move)
        check(model.cursor == previousCursor + 1 && model.revision > shownRevision, "candidate move records a new position")
        check(model.recommendationArrows.isEmpty && model.currentAnalysis.isEmpty,
              "manual move synchronously removes old arrows and cards before new engine output")
        try await awaitCurrentAnalysis()
        checkArrowSource()
        let beforeUndoRevision = model.revision
        model.navigate(to: previousCursor)
        check(model.position == previousPosition && model.revision > beforeUndoRevision, "undo returns exact prior position with new revision")
        check(model.recommendationArrows.isEmpty && model.currentAnalysis.isEmpty,
              "undo synchronously removes arrows from the abandoned position")
        try await awaitCurrentAnalysis()
        checkArrowSource()
        model.toggleAnalysis()
        check(!model.analysisEnabled, "pause")
        check(model.engine.rows.isEmpty, "pause clears stale rows")
        check(model.currentAnalysis.isEmpty && model.recommendationArrows.isEmpty, "pause clears cards and arrows together")
        model.toggleArrows()
        model.toggleArrows()
        check(model.recommendationArrows.isEmpty, "arrow toggle cannot resurrect suggestions while paused")
        } else {
            model.engine.stop()
            if model.analysisEnabled { model.toggleAnalysis() }
            check(model.recommendationArrows.isEmpty, "unconfigured offline board never fabricates engine arrows")
            print("SKIP: live engine board/candidate integration (use verify.sh --with-engine)")
        }
        var blackFirst = Position.initial
        blackFirst.sideToMove = .black
        model.replace(with: blackFirst)
        check(model.position.sideToMove == .black && model.moves.isEmpty, "editor side to move")
        let restoreSetup = GameModel()
        check(restoreSetup.position == blackFirst, "editor root survives restart")
        restoreSetup.shutdown()
        model.newGame()
        check(model.position == .initial && model.moves.isEmpty, "new game")
        model.shutdown()
        try await Task.sleep(nanoseconds: 300_000_000)
        check(!model.engine.isRunning, "engine exits cleanly")
        print("PASS \(checks) app/session/integration checks")
        print("Test-only session files: \(directory.path)")
    }
}
