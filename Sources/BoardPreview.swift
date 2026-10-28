import SwiftUI

/// Passive vector previews share the real board's geometry and warm drawing,
/// without allocating 90 buttons, hover handlers, or interactive hit targets.
struct BoardPreview: View {
    let position: Position
    var flipped = false
    var lastMove: Move? = nil
    let width: CGFloat
    var body: some View {
        let safeWidth = width.isFinite ? max(0, width) : 0
        let size = CGSize(width: safeWidth, height: safeWidth / WarmBoardLayout.aspectRatio)
        let layout = WarmBoardLayout(size: size)
        ZStack {
            WarmBoardSurface()
            WarmBoardGrid(cell: layout.cell, origin: layout.origin)
            if let lastMove {
                ForEach([lastMove.from, lastMove.to], id: \.self) { square in
                    RoundedRectangle(cornerRadius: layout.cell * 0.12)
                        .fill(WarmBoardPalette.selection.opacity(square == lastMove.to ? 0.20 : 0.09))
                        .frame(width: layout.cell * 0.91, height: layout.cell * 0.91)
                        .position(layout.point(square, flipped: flipped))
                }
            }
            ForEach(Square.all, id: \.self) { square in
                if let piece = position[square] {
                    WarmPieceFace(piece: piece, diameter: layout.pieceDiameter, fontSize: layout.pieceFontSize)
                        .position(layout.point(square, flipped: flipped))
                }
            }
        }.frame(width: size.width, height: size.height)
            .clipped().allowsHitTesting(false).accessibilityElement(children: .ignore)
    }
}
