import SwiftUI
import AppKit

enum Palette {
    static let paper = Studio.paper
    static let ink = Studio.ink
    static let muted = Studio.muted
    static let red = Studio.red
    static let green = Studio.accent
    static let board = WarmBoardPalette.maple
    static let line = WarmBoardPalette.coordinate
    static let ivory = WarmBoardPalette.pieceFace
    static let boardEdge = WarmBoardPalette.edge
    static let redPiece = WarmBoardPalette.pieceFace
    static let blackPiece = WarmBoardPalette.pieceFace
    static let redPieceInk = WarmBoardPalette.redInk
    static let blackPieceInk = WarmBoardPalette.blackInk

    static func candidate(_ rank: Int) -> Color {
        switch rank {
        case 1: return Studio.gold
        case 2: return Studio.cyan
        default: return Studio.purple
        }
    }
}

/// Cards and arrows consume exactly the same current, legal candidate set.
enum CandidateDisplay {
    static func lines(_ rows: [EngineLine], position: Position, revision: Int,
                      resultRevision: Int?, enabled: Bool) -> [EngineLine] {
        guard enabled, resultRevision == revision else { return [] }
        var moves = Set<Move>()
        var ranks = Set<Int>()
        return rows.sorted { $0.rank < $1.rank }.filter { line in
            guard (1...3).contains(line.rank), let value = line.pv.first,
                  let move = Move(uci: value), (try? position.applying(move: move)) != nil,
                  !moves.contains(move), !ranks.contains(line.rank) else { return false }
            moves.insert(move); ranks.insert(line.rank)
            return true
        }
    }
}

struct RecommendationArrow: Identifiable, Equatable {
    var id: Int { rank }
    let rank: Int
    let move: Move
}

struct BoardArrowGeometry {
    let start: CGPoint
    let control: CGPoint
    let tip: CGPoint
    let headLeft: CGPoint
    let headRight: CGPoint
    let badge: CGPoint

    static func point(_ square: Square, flipped: Bool, cell: CGFloat, origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(flipped ? 8 - square.col : square.col) * cell,
                y: origin.y + CGFloat(flipped ? 9 - square.row : square.row) * cell)
    }

    init(arrow: RecommendationArrow, all: [RecommendationArrow], flipped: Bool,
         cell: CGFloat, origin: CGPoint) {
        let from = Self.point(arrow.move.from, flipped: flipped, cell: cell, origin: origin)
        let to = Self.point(arrow.move.to, flipped: flipped, cell: cell, origin: origin)
        let dx = to.x - from.x, dy = to.y - from.y
        let distance = max(1, hypot(dx, dy))
        let ux = dx / distance, uy = dy / distance
        // Split shared endpoints and collinear routes, keeping Top 1 straight.
        let sharedRoute = all.contains { other in
            guard other.rank != arrow.rank else { return false }
            if other.move.from == arrow.move.from || other.move.to == arrow.move.to { return true }
            let a = Self.point(other.move.from, flipped: flipped, cell: cell, origin: origin)
            let b = Self.point(other.move.to, flipped: flipped, cell: cell, origin: origin)
            return abs((a.x - from.x) * uy - (a.y - from.y) * ux) < cell * 0.05
                && abs((b.x - from.x) * uy - (b.y - from.y) * ux) < cell * 0.05
        }
        let bend: CGFloat = sharedRoute ? (arrow.rank == 2 ? 0.65 : arrow.rank == 3 ? -0.65 : 0) * cell : 0
        start = CGPoint(x: from.x + ux * cell * 0.31, y: from.y + uy * cell * 0.31)
        tip = CGPoint(x: to.x - ux * cell * 0.19, y: to.y - uy * cell * 0.19)
        control = CGPoint(x: (start.x + tip.x) / 2 - uy * bend,
                          y: (start.y + tip.y) / 2 + ux * bend)
        let hx = tip.x - control.x, hy = tip.y - control.y
        let headDistance = max(1, hypot(hx, hy))
        let vx = hx / headDistance, vy = hy / headDistance
        let headLength = cell * 0.23, headWidth = cell * 0.115
        headLeft = CGPoint(x: tip.x - vx * headLength - vy * headWidth,
                           y: tip.y - vy * headLength + vx * headWidth)
        headRight = CGPoint(x: tip.x - vx * headLength + vy * headWidth,
                            y: tip.y - vy * headLength - vx * headWidth)
        let t: CGFloat = arrow.rank == 1 ? 0.61 : arrow.rank == 2 ? 0.40 : 0.76
        let u = 1 - t
        let badgeSide: CGFloat = bend < 0 ? -1 : 1
        let raw = CGPoint(x: u*u*start.x + 2*u*t*control.x + t*t*tip.x - uy * cell * 0.25 * badgeSide,
                          y: u*u*start.y + 2*u*t*control.y + t*t*tip.y + ux * cell * 0.25 * badgeSide)
        // Keep labels inside the board, including moves on an outer file/rank.
        badge = CGPoint(x: min(origin.x + cell * 8.16, max(origin.x - cell * 0.16, raw.x)),
                        y: min(origin.y + cell * 9.16, max(origin.y - cell * 0.16, raw.y)))
    }
}

struct BoardView: View {
    let position: Position
    let flipped: Bool
    var selected: Square? = nil
    var targets: [Square] = []
    var lastMove: Move? = nil
    var arrows: [RecommendationArrow] = []
    var arrowContext: String = "Top"
    var studyCoordinates = false
    var appearance = BoardAppearance()
    let onTap: (Square) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredSquare: Square?
    @State private var motionScene: BoardMotionScene?

    // Every visual and hit target shares this layout, including arrow overlays.
    typealias Layout = WarmBoardLayout

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(size: geo.size)
            ZStack {
                WarmBoardSurface()
                WarmBoardGrid(cell: layout.cell, origin: layout.origin)
                ForEach(0..<90, id: \.self) { index in
                    let square = Square(row: index / 9, col: index % 9)
                    squareButton(square, layout: layout)
                        .position(layout.point(square, flipped: flipped))
                }
                ForEach((motionScene ?? BoardMotionScene(position: position)).tokens) { token in
                    WarmPieceFace(piece: token.piece, diameter: layout.pieceDiameter, fontSize: layout.pieceFontSize)
                        .scaleEffect(hoveredSquare == token.square && !reduceMotion ? 1.025 : 1)
                        .position(layout.point(token.square, flipped: flipped))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                ForEach(0..<9, id: \.self) { index in
                    Text(studyCoordinates ? String(Array("abcdefghi")[flipped ? 8 - index : index]) : flipped ? String(index + 1) : ["九","八","七","六","五","四","三","二","一"][index])
                        .font(.system(size: layout.coordinateFontSize, weight: .medium, design: .serif))
                        .foregroundColor(BoardSurfaceColors(appearance.board).coordinate)
                        .position(x: layout.origin.x + CGFloat(index) * layout.cell,
                                  y: layout.coordinateY)
                        .accessibilityHidden(true)
                }
                if studyCoordinates {
                    ForEach(0..<10, id: \.self) { index in
                        Text(String(flipped ? index : 9 - index))
                            .font(.system(size: max(9, layout.cell * 0.20), design: .monospaced))
                            .foregroundColor(BoardSurfaceColors(appearance.board).coordinate)
                            .position(x: layout.origin.x - layout.cell * 0.48, y: layout.origin.y + CGFloat(index) * layout.cell)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                candidateOverlay(layout: layout)
            }
        }
        .aspectRatio(Layout.aspectRatio, contentMode: .fit)
        .environment(\.boardAppearance, appearance)
        .onAppear { motionScene = BoardMotionScene(position: position) }
        .onChange(of: position) { next in
            let scene = (motionScene ?? BoardMotionScene(position: next)).advancing(to: next, move: lastMove)
            withAnimation(!reduceMotion && scene.isSingleMove ? .easeOut(duration: 0.16) : nil) { motionScene = scene }
        }
    }

    private func squareButton(_ square: Square, layout: Layout) -> some View {
        let piece = position[square]
        let isSelected = selected == square
        let isTarget = targets.contains(square)
        let isHovered = hoveredSquare == square
        let isLastFrom = lastMove?.from == square
        let isLastTo = lastMove?.to == square
        let cell = layout.cell
        return Button { onTap(square) } label: {
            ZStack {
                if isLastFrom || isLastTo {
                    RoundedRectangle(cornerRadius: cell * 0.15, style: .continuous)
                        .fill(Palette.green.opacity(isLastTo ? 0.16 : 0.07))
                        .overlay(RoundedRectangle(cornerRadius: cell * 0.15, style: .continuous)
                            .strokeBorder(Palette.green.opacity(isLastTo ? 0.50 : 0.22), lineWidth: 0.8))
                        .frame(width: cell * 0.91, height: cell * 0.91)
                }
                if isHovered && !isSelected {
                    Circle().fill(Palette.green.opacity(0.14))
                        .frame(width: cell * 0.92, height: cell * 0.92)
                }
                if isSelected {
                    Circle().strokeBorder(Palette.ivory, lineWidth: 4)
                        .frame(width: cell * 0.94, height: cell * 0.94)
                    Circle().strokeBorder(Palette.green, lineWidth: max(2, cell * 0.043))
                        .frame(width: cell * 0.94, height: cell * 0.94)
                }
                if isTarget {
                    if piece != nil {
                        // Capture targets leave the character unobscured.
                        ForEach(0..<4, id: \.self) { quadrant in
                            Circle().trim(from: 0.04, to: 0.21)
                                .stroke(Palette.green, style: StrokeStyle(lineWidth: max(2.3, cell * 0.055), lineCap: .round))
                                .rotationEffect(.degrees(Double(quadrant) * 90))
                                .frame(width: cell * 0.91, height: cell * 0.91)
                        }
                    } else {
                        Circle().fill(Palette.ivory.opacity(0.95)).frame(width: cell * 0.30, height: cell * 0.30)
                        Circle().fill(Palette.green.opacity(isHovered ? 1 : 0.85))
                            .frame(width: cell * 0.17, height: cell * 0.17)
                    }
                }
                if isLastTo && !isSelected && !isTarget {
                    Circle().fill(Palette.green).overlay(Circle().stroke(Palette.ivory, lineWidth: 1))
                        .frame(width: max(5, cell * 0.11), height: max(5, cell * 0.11))
                        .offset(x: cell * 0.32, y: cell * 0.32)
                }
            }
            .frame(width: layout.hitDiameter, height: layout.hitDiameter)
            .contentShape(Rectangle())
        }
        .buttonStyle(CellButtonStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            if hovering { hoveredSquare = square }
            else if hoveredSquare == square { hoveredSquare = nil }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel("\(square.col + 1)列\(square.row + 1)行 \(piece.map { $0.side.label + $0.symbol } ?? "空位")")
        .accessibilityValue(isSelected ? "已选中" : isTarget ? "合法落点" : isLastTo ? "上一步落点" : isLastFrom ? "上一步起点" : "")
        .accessibilityIdentifier("square-\(square.row)-\(square.col)")
    }

    private struct CellButtonStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.82 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
        }
    }

    private func candidateOverlay(layout: Layout) -> some View {
        Canvas { context, _ in
            let cell = layout.cell, origin = layout.origin
            let ordered = arrows.sorted { $0.rank > $1.rank }
            for arrow in ordered {
                let g = BoardArrowGeometry(arrow: arrow, all: arrows, flipped: flipped, cell: cell, origin: origin)
                var shaft = Path()
                shaft.move(to: g.start)
                shaft.addQuadCurve(to: g.tip, control: g.control)
                let width = max(2.4, cell * (arrow.rank == 1 ? 0.095 : 0.067))
                context.stroke(shaft, with: .color(WarmBoardPalette.arrowOutline.opacity(0.95)),
                               style: StrokeStyle(lineWidth: width + 2.2, lineCap: .round))
                context.stroke(shaft, with: .color(Palette.candidate(arrow.rank)),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
                var head = Path()
                head.move(to: g.tip); head.addLine(to: g.headLeft); head.addLine(to: g.headRight); head.closeSubpath()
                context.stroke(head, with: .color(WarmBoardPalette.arrowOutline.opacity(0.95)), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                context.fill(head, with: .color(Palette.candidate(arrow.rank)))
            }
            // Draw every rank badge last so crossing arrows cannot hide numbers.
            for arrow in ordered {
                let g = BoardArrowGeometry(arrow: arrow, all: arrows, flipped: flipped, cell: cell, origin: origin)
                let diameter = max(17, cell * 0.40)
                let circle = Path(ellipseIn: CGRect(x: g.badge.x - diameter/2, y: g.badge.y - diameter/2,
                                                  width: diameter, height: diameter))
                context.fill(circle, with: .color(Palette.candidate(arrow.rank)))
                context.stroke(circle, with: .color(WarmBoardPalette.arrowOutline), lineWidth: 1.5)
                context.draw(Text("\(arrow.rank)").font(.system(size: diameter * 0.61, weight: .bold, design: .rounded))
                    .foregroundColor(Studio.onAccent), at: g.badge)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(arrows.isEmpty ? "无候选箭头" : arrows.sorted { $0.rank < $1.rank }.map {
            "\(arrowContext) \($0.rank) 箭头：\(position.notation(for: $0.move))"
        }.joined(separator: "；"))
        .accessibilityIdentifier("candidate-arrows")
    }
}
