import SwiftUI

private struct BoardAppearanceKey: EnvironmentKey {
    static let defaultValue = BoardAppearance()
}
extension EnvironmentValues {
    var boardAppearance: BoardAppearance {
        get { self[BoardAppearanceKey.self] }
        set { self[BoardAppearanceKey.self] = newValue }
    }
}

struct BoardSurfaceColors {
    let upper: Color, fill: Color, lower: Color, edge: Color, grid: Color, coordinate: Color
    init(_ style: BoardColorway) {
        func color(_ hex: Int) -> Color {
            Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
        }
        let values: [Int]
        switch style {
        case .warmMaple: values = [0xF4D7A2, 0xE9C58E, 0xDFB675, 0xBA8A4C, 0x7E5E36, 0x5C3D1F]
        case .ricePaper: values = [0xFAF4E6, 0xEEE5D4, 0xE2D7C2, 0xAD9878, 0x79674C, 0x514230]
        case .paleJade: values = [0xE9F0DF, 0xDAE5CE, 0xC6D4B8, 0x90A080, 0x5A6B4E, 0x38452F]
        case .blueMist: values = [0xEAF0F2, 0xD9E3E7, 0xC8D5DD, 0x95A8B4, 0x5B6C79, 0x354551]
        case .roseClay: values = [0xF5E7DF, 0xEBD8CD, 0xDFC5B8, 0xB39889, 0x816052, 0x583C31]
        }
        upper = color(values[0]); fill = color(values[1]); lower = color(values[2])
        edge = color(values[3]); grid = color(values[4]); coordinate = color(values[5])
    }
}

struct PieceSurfaceColors {
    let face: Color, low: Color, base: Color
    init(_ style: PieceColorway) {
        func color(_ hex: Int) -> Color {
            Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
        }
        let values: [Int]
        switch style {
        case .ivory: values = [0xFFF5DB, 0xEFD3A0, 0xC59A5F]
        case .porcelain: values = [0xFFFCF7, 0xE8E0D5, 0xB5A697]
        case .honey: values = [0xFFEBC5, 0xEACE9B, 0xB28B51]
        case .jade: values = [0xF1F6E9, 0xD6E1C8, 0x97A984]
        case .slate: values = [0xF0F3F5, 0xD8DFE4, 0x98A4AF]
        }
        face = color(values[0]); low = color(values[1]); base = color(values[2])
    }
}

/// Native vector drawing shared by the interactive board and every thumbnail.
/// No image assets, random textures, cached bitmaps, or changes to chess rules.
enum WarmBoardPalette {
    static let maple = Color(red: 233 / 255, green: 197 / 255, blue: 142 / 255)
    static let mapleLight = Color(red: 244 / 255, green: 215 / 255, blue: 162 / 255)
    static let mapleLow = Color(red: 223 / 255, green: 182 / 255, blue: 117 / 255)
    static let edge = Color(red: 186 / 255, green: 138 / 255, blue: 76 / 255)
    static let grid = Color(red: 126 / 255, green: 94 / 255, blue: 54 / 255)
    static let coordinate = Color(red: 92 / 255, green: 61 / 255, blue: 31 / 255)
    static let pieceFace = Color(red: 255 / 255, green: 245 / 255, blue: 219 / 255)
    static let pieceLow = Color(red: 239 / 255, green: 211 / 255, blue: 160 / 255)
    static let pieceBase = Color(red: 197 / 255, green: 154 / 255, blue: 95 / 255)
    static let redInk = Color(red: 164 / 255, green: 44 / 255, blue: 32 / 255)
    static let blackInk = Color(red: 61 / 255, green: 43 / 255, blue: 30 / 255)
    static let selection = Studio.accent
    static let arrowOutline = Studio.onAccent

    static func ink(for side: Side) -> Color { side == .red ? redInk : blackInk }
}

/// Preserves BoardView's established board / target / coordinate geometry.
/// The passive thumbnail uses the very same points without creating buttons.
struct WarmBoardLayout {
    static let aspectRatio: CGFloat = 9.15 / 10.25
    private static let heightUnits: CGFloat = 10.6
    let cell: CGFloat
    let origin: CGPoint
    let size: CGSize
    var pieceDiameter: CGFloat { cell * 0.82 }
    var hitDiameter: CGFloat { cell * 0.94 }
    var pieceFontSize: CGFloat { cell * 0.52 }
    var coordinateFontSize: CGFloat { max(10, cell * 0.22) }
    var coordinateY: CGFloat { origin.y + 9.65 * cell }

    init(size: CGSize) {
        self.size = size
        cell = max(0, min(size.width / 9.15, size.height / Self.heightUnits))
        origin = CGPoint(x: (size.width - cell * 8) / 2,
                         y: (size.height - cell * Self.heightUnits) / 2 + cell * 0.60)
    }

    func point(_ square: Square, flipped: Bool) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(flipped ? 8 - square.col : square.col) * cell,
                y: origin.y + CGFloat(flipped ? 9 - square.row : square.row) * cell)
    }
}

struct WarmBoardSurface: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.boardAppearance) private var appearance

    var body: some View {
        let colors = BoardSurfaceColors(appearance.board)
        GeometryReader { geometry in
            let corner = min(12, max(4, geometry.size.width * 0.02))
            ZStack {
                RoundedRectangle(cornerRadius: corner).fill(colors.edge)
                RoundedRectangle(cornerRadius: max(2, corner - 1))
                    .fill(LinearGradient(colors: [colors.upper, colors.fill, colors.lower],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(2)
                if contrast != .increased && appearance.board == .warmMaple {
                    // A few quiet, deterministic grain lines suggest maple; they
                    // cannot obscure a grid point or allocate a texture resource.
                    Canvas { context, size in
                        var grain = Path()
                        for index in 0..<18 {
                            let x = size.width * (CGFloat(index) + 0.45) / 18
                            let bend = size.width * (index.isMultiple(of: 2) ? 0.012 : -0.009)
                            grain.move(to: CGPoint(x: x, y: 0))
                            grain.addCurve(to: CGPoint(x: x + bend, y: size.height),
                                           control1: CGPoint(x: x - bend, y: size.height * 0.33),
                                           control2: CGPoint(x: x + bend * 1.5, y: size.height * 0.67))
                        }
                        context.stroke(grain, with: .color(colors.edge.opacity(0.09)), lineWidth: 0.7)
                    }.clipShape(RoundedRectangle(cornerRadius: max(2, corner - 2))).padding(3)
                }
                RoundedRectangle(cornerRadius: max(2, corner - 1))
                    .strokeBorder(WarmBoardPalette.pieceFace.opacity(0.62), lineWidth: 0.8).padding(3)
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(colors.edge.opacity(contrast == .increased ? 1 : 0.75), lineWidth: 1)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct WarmBoardGrid: View {
    let cell: CGFloat
    let origin: CGPoint
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.boardAppearance) private var appearance

    var body: some View {
        let colors = BoardSurfaceColors(appearance.board)
        Canvas { context, _ in
            guard cell > 0 else { return }
            let river = CGRect(x: origin.x, y: origin.y + cell * 4, width: cell * 8, height: cell)
            context.fill(Path(river), with: .color(WarmBoardPalette.pieceFace.opacity(0.16)))
            var lines = Path()
            for row in 0..<10 {
                let y = origin.y + CGFloat(row) * cell
                lines.move(to: CGPoint(x: origin.x, y: y))
                lines.addLine(to: CGPoint(x: origin.x + 8 * cell, y: y))
            }
            for col in 0..<9 {
                let x = origin.x + CGFloat(col) * cell
                lines.move(to: CGPoint(x: x, y: origin.y))
                lines.addLine(to: CGPoint(x: x, y: origin.y + (col == 0 || col == 8 ? 9 : 4) * cell))
                if col != 0 && col != 8 {
                    lines.move(to: CGPoint(x: x, y: origin.y + 5 * cell))
                    lines.addLine(to: CGPoint(x: x, y: origin.y + 9 * cell))
                }
            }
            for row in [0, 7] {
                lines.move(to: CGPoint(x: origin.x + 3 * cell, y: origin.y + CGFloat(row) * cell))
                lines.addLine(to: CGPoint(x: origin.x + 5 * cell, y: origin.y + CGFloat(row + 2) * cell))
                lines.move(to: CGPoint(x: origin.x + 5 * cell, y: origin.y + CGFloat(row) * cell))
                lines.addLine(to: CGPoint(x: origin.x + 3 * cell, y: origin.y + CGFloat(row + 2) * cell))
            }
            context.stroke(lines, with: .color(contrast == .increased ? colors.coordinate : colors.grid),
                           lineWidth: max(0.7, cell * (contrast == .increased ? 0.022 : 0.015)))
            let border = CGRect(x: origin.x - cell * 0.075, y: origin.y - cell * 0.075,
                                width: cell * 8.15, height: cell * 9.15)
            context.stroke(Path(border), with: .color(colors.grid), lineWidth: max(0.55, cell * 0.012))

            var marks = Path()
            let anchors = [2, 7].flatMap { row in [1, 7].map { Square(row: row, col: $0) } }
                + [3, 6].flatMap { row in [0, 2, 4, 6, 8].map { Square(row: row, col: $0) } }
            for square in anchors {
                let point = CGPoint(x: origin.x + CGFloat(square.col) * cell, y: origin.y + CGFloat(square.row) * cell)
                for xSign in [-1.0, 1.0] where !(square.col == 0 && xSign < 0) && !(square.col == 8 && xSign > 0) {
                    for ySign in [-1.0, 1.0] {
                        let x = point.x + xSign * cell * 0.09, y = point.y + ySign * cell * 0.09
                        marks.move(to: CGPoint(x: x + xSign * cell * 0.10, y: y))
                        marks.addLine(to: CGPoint(x: x, y: y))
                        marks.addLine(to: CGPoint(x: x, y: y + ySign * cell * 0.10))
                    }
                }
            }
            context.stroke(marks, with: .color(colors.grid.opacity(0.85)), lineWidth: max(0.5, cell * 0.013))
            for (text, file) in [("楚 河", 1.8), ("汉 界", 6.2)] {
                context.draw(Text(text).font(.system(size: cell * 0.35, weight: .regular, design: .serif))
                    .tracking(cell * 0.07).foregroundColor(colors.coordinate),
                             at: CGPoint(x: origin.x + file * cell, y: origin.y + cell * 4.5))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct WarmPieceFace: View {
    let piece: Piece
    let diameter: CGFloat
    let fontSize: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.boardAppearance) private var appearance

    var body: some View {
        let ink = WarmBoardPalette.ink(for: piece.side)
        let colors = PieceSurfaceColors(appearance.pieces)
        ZStack {
            Circle().fill(colors.base)
                .offset(y: max(0.7, diameter * 0.035))
                .shadow(color: Studio.shadow.opacity(0.23), radius: diameter * 0.045, y: diameter * 0.045)
            Circle().fill(LinearGradient(colors: [colors.face, colors.face, colors.low],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(colors.base, lineWidth: max(0.65, diameter * 0.018))
            Circle().strokeBorder(colors.face, lineWidth: max(0.7, diameter * 0.022))
                .padding(diameter * 0.035)
            Circle().strokeBorder(contrast == .increased ? ink : colors.base.opacity(0.82),
                                  lineWidth: max(0.65, diameter * 0.017))
                .padding(diameter * 0.085)
            Text(piece.symbol)
                .font(.system(size: fontSize, weight: .medium, design: .serif))
                .foregroundColor(ink).offset(y: -diameter * 0.012)
        }.frame(width: diameter, height: diameter)
    }
}
