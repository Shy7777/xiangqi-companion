import Foundation
import SwiftUI
import AppKit

@main @MainActor struct WarmStyleTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func components(_ color: Color) -> [Double] {
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            return [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)]
        }
        func luminance(_ color: Color) -> Double {
            zip(components(color), [0.2126, 0.7152, 0.0722]).reduce(0) { sum, item in
                let value = item.0 <= 0.04045 ? item.0 / 12.92 : pow((item.0 + 0.055) / 1.055, 2.4)
                return sum + value * item.1
            }
        }
        func contrast(_ a: Color, _ b: Color) -> Double {
            let first = luminance(a), second = luminance(b)
            return (max(first, second) + 0.05) / (min(first, second) + 0.05)
        }
        for background in [Studio.paper, Studio.white, Studio.cream, Studio.surfaceRaised, Studio.rail] {
            check(contrast(Studio.ink, background) >= 7, "Main text must retain AAA-level contrast on warm surfaces")
            check(contrast(Studio.muted, background) >= 4.5, "Secondary text is not decorative low-contrast gray")
        }
        for foreground in [Studio.accent, Studio.red, Studio.success, Studio.gold, Studio.cyan, Studio.purple] {
            check(contrast(foreground, Studio.white) >= 4.5, "Semantic labels remain readable on a paper panel")
        }
        check(contrast(Studio.accent, Studio.onAccent) >= 4.5, "Primary controls retain readable light labels")
        for rank in 1...3 {
            check(contrast(Palette.candidate(rank), Studio.onAccent) >= 4.5, "Every Top badge has readable numerals")
            check(contrast(Palette.candidate(rank), WarmBoardPalette.mapleLow) >= 3, "Each arrow is distinguishable from the darkest maple tone")
        }
        let rankComponents = (1...3).map { components(Palette.candidate($0)) }
        for i in 0..<3 {
            for j in (i + 1)..<3 {
                let distance = zip(rankComponents[i], rankComponents[j]).map { pow($0 - $1, 2) }.reduce(0, +).squareRoot()
                check(distance >= 0.20, "Top ranks must not collapse to near-identical colors")
            }
        }
        for side in Side.allCases {
            check(contrast(WarmBoardPalette.ink(for: side), WarmBoardPalette.pieceFace) >= 4.5, "Piece text is readable on ivory")
            check(contrast(WarmBoardPalette.ink(for: side), WarmBoardPalette.pieceLow) >= 4.5, "Piece text remains readable across the full face gradient")
        }
        check(contrast(WarmBoardPalette.coordinate, WarmBoardPalette.mapleLow) >= 4.5, "Coordinate labels remain readable at the lower rim")
        check(contrast(WarmBoardPalette.grid, WarmBoardPalette.mapleLow) >= 3, "Thin board lines still contrast with maple")
        check(components(Palette.redPiece) == components(Palette.blackPiece), "Both sides use the same ivory face, not a leftover dark disk")
        check(contrast(Palette.red, Palette.board) >= 4.5 && contrast(Palette.ink, Palette.board) >= 4.5,
              "The existing public Palette contrast contract remains intact")

        for width: CGFloat in [78, 120, 350, 480, 620] {
            let size = CGSize(width: width, height: width / WarmBoardLayout.aspectRatio)
            let layout = BoardView.Layout(size: size)
            let previewLayout = WarmBoardLayout(size: size)
            check(layout.cell == previewLayout.cell && layout.origin == previewLayout.origin,
                  "Main and preview board must share one geometry")
            if width >= 350 {
                check(layout.pieceFontSize >= 19, "Interactive board piece text keeps its minimum size")
                check(layout.coordinateY - layout.coordinateFontSize * 0.65 > layout.origin.y + layout.cell * 9 + layout.pieceDiameter / 2,
                      "Footer coordinates cannot overlap the last rank")
                check(layout.coordinateY + layout.coordinateFontSize * 0.7 < size.height - 3.5,
                      "Footer labels fit inside the board")
            }
            check(layout.hitDiameter > layout.pieceDiameter && layout.hitDiameter < layout.cell,
                  "A comfortable tap target may not reach a neighboring intersection")
            for flipped in [false, true] {
                var points = Set<String>()
                for square in Square.all {
                    let point = layout.point(square, flipped: flipped)
                    points.insert("\(point.x),\(point.y)")
                    check(point == BoardArrowGeometry.point(square, flipped: flipped, cell: layout.cell, origin: layout.origin),
                          "Moving geometry to the shared drawing must not shift arrow endpoints")
                    check(point == previewLayout.point(square, flipped: flipped), "Thumbnail pieces must match the main board exactly")
                    let radius = layout.hitDiameter / 2
                    check(point.x - radius >= 0 && point.x + radius <= size.width && point.y - radius >= 0 && point.y + radius <= size.height,
                          "Every target fits the surface, including flipped corner pieces")
                }
                check(points.count == 90, "Each intersection stays unique")
            }
        }
        let moves = ["h2e2", "b2e2", "h0g2"].enumerated().map {
            RecommendationArrow(rank: $0.offset + 1, move: Move(uci: $0.element)!)
        }
        for flipped in [false, true] {
            let layout = WarmBoardLayout(size: CGSize(width: 620, height: 620 / WarmBoardLayout.aspectRatio))
            let geometries = moves.map { BoardArrowGeometry(arrow: $0, all: moves, flipped: flipped, cell: layout.cell, origin: layout.origin) }
            check(Set(geometries.map { "\($0.badge.x),\($0.badge.y)" }).count == 3, "Shared-endpoint candidates retain separate rank labels")
            check(geometries.allSatisfy { $0.start.x.isFinite && $0.start.y.isFinite && $0.tip.x.isFinite && $0.tip.y.isFinite },
                  "Arrow geometry remains finite")
        }
        print("PASS \(checks) warm palette / board geometry / candidate readability checks")
        print(String(format: "Contrast: text %.2f; muted %.2f; primary %.2f; Top 1/2/3 %.2f / %.2f / %.2f; red/black pieces %.2f / %.2f",
                     contrast(Studio.ink, Studio.paper), contrast(Studio.muted, Studio.cream), contrast(Studio.accent, Studio.onAccent),
                     contrast(Studio.gold, Studio.onAccent), contrast(Studio.cyan, Studio.onAccent), contrast(Studio.purple, Studio.onAccent),
                     contrast(WarmBoardPalette.redInk, WarmBoardPalette.pieceLow), contrast(WarmBoardPalette.blackInk, WarmBoardPalette.pieceLow)))

        // Explicit, test-owned preview output only. Normal verification creates
        // no snapshots and does not launch the installed application.
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--render=") }) {
            let path = String(argument.dropFirst("--render=".count))
            guard (path as NSString).isAbsolutePath, path.contains("xiangqi-warm-style.") else {
                throw NSError(domain: "WarmStyleTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Snapshot target must be inside the test-owned temporary directory"])
            }
            let view = HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 16) {
                    BoardView(position: .initial, flipped: false, arrows: moves, onTap: { _ in })
                        .frame(width: 560, height: 560 / WarmBoardLayout.aspectRatio)
                    HStack {
                        Button("看一遍") {}.buttonStyle(StudioButtonStyle(primary: true))
                        Button("自己走") {}.buttonStyle(StudioButtonStyle())
                        Button("检验") {}.buttonStyle(StudioButtonStyle())
                        Spacer()
                        StudioIconButton(symbol: "chevron.left", label: "上一步") {}
                        StudioIconButton(symbol: "chevron.right", label: "下一步") {}
                    }.studioSurface(12)
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text("暖木棋室").font(.system(size: 25, weight: .semibold, design: .serif))
                    Label("先看对手的威胁", systemImage: "lightbulb").font(.system(size: 15))
                    HStack { StudioTag(text: "红方行棋", color: Studio.red); Spacer(); Text("第 1 步").font(.system(size: 12)).foregroundColor(Studio.muted) }
                    ForEach([false, true], id: \.self) { flipped in
                        HStack {
                            Text(flipped ? "变招" : "原谱").font(.system(size: 14, weight: .medium))
                            Spacer()
                            BoardPreview(position: .initial, flipped: flipped, width: 136)
                        }.studioSurface(12)
                    }
                    ForEach(1...3, id: \.self) { rank in
                        HStack(spacing: 10) {
                            Text("\(rank)").font(.system(size: 14, weight: .bold)).foregroundColor(Studio.onAccent)
                                .frame(width: 28, height: 28).background(Palette.candidate(rank), in: RoundedRectangle(cornerRadius: 6))
                            Text("候选着法").font(.system(size: 13)).foregroundColor(Studio.ink)
                        }
                    }
                    Button("从当前分支局面陪练") {}.buttonStyle(StudioButtonStyle(primary: true))
                }.frame(width: 255).studioSurface(20)
            }.padding(24).foregroundColor(Studio.ink).background(Studio.paper).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let rendered = renderer.cgImage,
                  let bytes = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "WarmStyleTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to render native warm board preview"])
            }
            try bytes.write(to: URL(fileURLWithPath: path))
            print("Native warm preview: \(path)")
        }
    }
}
