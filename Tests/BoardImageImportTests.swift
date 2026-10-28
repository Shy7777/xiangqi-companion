#if BOARD_IMAGE_IMPORT_TESTS
import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main @MainActor struct BoardImageImportTests {
    static func main() async throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checks += 1 }
        func rejects(_ message: String, _ body: () throws -> Void) {
            do { try body(); preconditionFailure(message) } catch { checks += 1 }
        }
        try BoardImageCorners().validate(); checks += 1
        try BoardImageCorners.full.validate(); checks += 1
        let badCorners = [
            BoardImageCorners(topLeft: .zero, topRight: CGPoint(x: 1, y: 1), bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 1)),
            BoardImageCorners(topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero),
            BoardImageCorners(topLeft: CGPoint(x: -.infinity, y: 0), topRight: .zero, bottomRight: .zero, bottomLeft: .zero),
            BoardImageCorners(topLeft: CGPoint(x: -0.1, y: 0), topRight: CGPoint(x: 1, y: 0), bottomRight: CGPoint(x: 1, y: 1), bottomLeft: CGPoint(x: 0, y: 1))
        ]
        for value in badCorners { rejects("Invalid/crossed corners accepted") { try value.validate() } }
        var corners = BoardImageCorners()
        corners.set(CGPoint(x: -2, y: 3), at: 0)
        check(corners.topLeft == CGPoint(x: 0, y: 1), "Dragged corner must remain inside the displayed image")
        let saved = corners; corners.set(CGPoint(x: CGFloat.nan, y: 0), at: 1)
        check(saved == corners, "Non-finite drag must not poison the transform")
        check(BoardImageCorners.full.point(x: 0.5, y: 0.5) == CGPoint(x: 0.5, y: 0.5), "Guide grid coordinates changed")
        let skew = BoardImageCorners(topLeft: CGPoint(x: 0.2, y: 0.1), topRight: CGPoint(x: 0.8, y: 0.1),
                                    bottomRight: CGPoint(x: 1, y: 0.9), bottomLeft: CGPoint(x: 0, y: 0.9))
        try skew.validate(); checks += 1
        let midpoint = skew.point(x: 0.5, y: 0.5)
        check(abs(midpoint.x - 0.5) < 0.0001 && abs(midpoint.y - 0.4) < 0.0001, "Perspective guides must not use a bilinear midpoint")
        for (point, expected) in [(skew.point(x: 0, y: 0), skew.topLeft), (skew.point(x: 1, y: 0), skew.topRight),
                                  (skew.point(x: 1, y: 1), skew.bottomRight), (skew.point(x: 0, y: 1), skew.bottomLeft)] {
            check(hypot(point.x - expected.x, point.y - expected.y) < 0.0001, "Projective guide corner changed")
        }
        check(BoardImageDraft.imageCell(normalizedCenter: CGPoint(x: 0.5 / 9, y: 0.5 / 10)) == 0, "Top-left mapping wrong")
        check(BoardImageDraft.imageCell(normalizedCenter: CGPoint(x: 8.5 / 9, y: 9.5 / 10)) == 89, "Bottom-right mapping wrong")
        for point in [CGPoint(x: -0.1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: CGFloat.infinity, y: 0)] {
            check(BoardImageDraft.imageCell(normalizedCenter: point) == nil, "Off-board OCR was clamped into a real cell")
        }
        var draft = BoardImageDraft()
        check(draft.cells.count == 90 && draft.unresolvedCount == 90 && draft.sideToMove == nil, "Unknown cells and side cannot default to confirmed empty/red")
        rejects("Unselected turn accepted") { _ = try draft.position() }
        draft.sideToMove = .red
        rejects("Unrecognized cells silently became empty") { _ = try draft.position() }
        draft.cells[0] = .init(piece: Piece(side: .black, kind: .rook), confidence: 0.99, observedText: "車", confirmed: false)
        check(draft.unresolvedCount == 90, "High OCR confidence does not replace human review")
        draft.confirmRow(0)
        check(draft.unresolvedCount == 81 && draft.cells[0].piece?.kind == .rook && draft.cells[1].piece == nil, "Explicit row confirmation did not preserve proposals and confirm blanks")
        draft.confirmRow(-1); draft.confirmRow(10); draft.edit(-1, piece: nil); draft.edit(90, piece: nil)
        check(draft.unresolvedCount == 81, "Out-of-range edits changed cells")
        for index in 0..<90 { draft.edit(index, piece: Position.initial.board[index]) }
        let initial = try draft.position()
        check(initial == .initial, "Confirmed initial position failed legality/FEN validation")
        draft.sideToMove = .black
        let blackToMove = try draft.position()
        check(blackToMove.sideToMove == .black, "Selected side-to-move was ignored")
        draft.sideToMove = .red; draft.redAtBottom = false; draft.cells.reverse()
        let rotated = try draft.position()
        check(rotated == .initial, "180-degree image orientation must reverse both row and file")
        draft.cells[0].confirmed = false
        rejects("One unresolved cell accepted") { _ = try draft.position() }
        draft.cells[0].confirmed = true
        draft.edit(85, piece: nil)
        rejects("Missing black king accepted") { _ = try draft.position() }
        draft.cells = []
        rejects("Malformed editor cell count accepted") { _ = try draft.position() }
        for (text, kind, side) in [("帥", PieceKind.king, Side.red), ("將", .king, .black), ("仕", .advisor, .red), ("士", .advisor, .black),
                                    ("相", .elephant, .red), ("象", .elephant, .black), ("兵", .pawn, .red), ("卒", .pawn, .black), ("俥", .rook, .red), ("傌", .horse, .red)] {
            let value = BoardImageDraft.glyph(text)
            check(value?.kind == kind && value?.side == side, "Traditional/intrinsic-side glyph failed: \(text)")
        }
        for text in ["馬", "马", "車", "车", "炮", "砲"] {
            check(BoardImageDraft.glyph(text)?.side == nil, "Shared glyph must not invent a side")
        }
        for text in ["楚", "河", "汉", "界", "包", "5", "将帅", ""] { check(BoardImageDraft.glyph(text) == nil, "Unknown word falsely became a chessman") }
        try BoardImageLoader.validateDimensions(width: 900, height: 1000); checks += 1
        for (width, height) in [(0, 0), (89, 100), (8193, 1000), (8000, 8000), (Int.max, Int.max), (-1, 100)] {
            rejects("Invalid or oversized image dimensions accepted") { try BoardImageLoader.validateDimensions(width: width, height: height) }
        }
        rejects("Empty image accepted") { _ = try BoardImageLoader.decode(Data()) }
        rejects("Text is not an image") { _ = try BoardImageLoader.decode(Data("not an image".utf8)) }
        rejects("Oversized compressed bytes accepted") { _ = try BoardImageLoader.decode(Data(repeating: 0, count: BoardImageLoader.maximumBytes + 1)) }

        // Real system OCR evidence, not mocked observations. A crisp rendered initial board
        // tests the complete ImageIO -> perspective correction -> Vision -> 90-cell path.
        let rendered = try renderBoard()
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { fatalError("PNG encoder unavailable") }
        CGImageDestinationAddImage(destination, rendered, nil)
        check(CGImageDestinationFinalize(destination), "Render PNG encoding failed")
        let decoded = try BoardImageLoader.decode(bytes as Data)
        check(decoded.width == 900 && decoded.height == 1000, "Decoded orientation or image dimensions changed")
        if CommandLine.arguments.count > 1 {
            let file = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("board-image-ocr-fixture.png")
            try (bytes as Data).write(to: file, options: .atomic)
            let reopened = try BoardImageLoader.read(file)
            check(reopened.width == decoded.width && reopened.height == decoded.height, "Bounded file import must decode the same selected image")
        }
        let engine = BoardImageRecognizer()
        let result = try await engine.recognize(decoded, corners: .full)
        check(result.image.width == 900 && result.image.height == 1000, "Perspective correction must normalize to a bounded 9x10 canvas")
        check(result.draft.cells.count == 90 && result.draft.unresolvedCount == 90, "Real OCR silently approved unknown cells")
        check(result.draft.sideToMove == nil, "Real OCR guessed which side should move")
        check(result.recognizedGlyphs > 0 && result.draft.suggestedCount > 0, "System OCR did not recognize any piece on the clear fixture; report unavailable rather than claim success")
        let expected = Position.initial.board
        let correct = result.draft.cells.enumerated().filter { $0.element.piece != nil && $0.element.piece == expected[$0.offset] }.count
        let falsePositive = result.draft.cells.enumerated().filter { $0.element.piece != nil && $0.element.piece != expected[$0.offset] }.count
        check(correct >= 16, "Real OCR regressed below half the pieces on the clear fixture; investigate and report, do not call manual fallback recognition success")
        print("OCR EVIDENCE: \(result.observationCount) observations, \(result.recognizedGlyphs) recognized glyphs, \(result.draft.suggestedCount) piece suggestions; \(correct)/32 exact piece+side+cell matches, \(falsePositive) incorrect suggestions; all 90 cells remain unreviewed")
        print("PASS \(checks) board-image import / geometry / uncertainty / validation / ImageIO / real Vision checks; no network or user-state writes")
    }

    private static func renderBoard() throws -> CGImage {
        guard let context = CGContext(data: nil, width: 900, height: 1000, bitsPerComponent: 8, bytesPerRow: 3600,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw BoardImageImportError.invalidImage }
        context.setFillColor(CGColor(red: 0.96, green: 0.91, blue: 0.81, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1000))
        context.setStrokeColor(CGColor(red: 0.65, green: 0.5, blue: 0.3, alpha: 1)); context.setLineWidth(2)
        for col in 0..<9 { context.move(to: CGPoint(x: col * 100 + 50, y: 50)); context.addLine(to: CGPoint(x: col * 100 + 50, y: 950)) }
        for row in 0..<10 { context.move(to: CGPoint(x: 50, y: row * 100 + 50)); context.addLine(to: CGPoint(x: 850, y: row * 100 + 50)) }
        context.strokePath()
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for square in Square.all {
            guard let piece = Position.initial[square] else { continue }
            let center = CGPoint(x: square.col * 100 + 50, y: (9 - square.row) * 100 + 50)
            context.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.9, alpha: 1))
            context.fillEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
            let color: NSColor = piece.side == .red ? NSColor(calibratedRed: 0.7, green: 0.05, blue: 0.04, alpha: 1) : .black
            context.setStrokeColor(color.cgColor); context.strokeEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: "PingFangSC-Semibold", size: 61) ?? NSFont.systemFont(ofSize: 61), .foregroundColor: color]
            let text = piece.symbol as NSString, size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
        }
        guard let image = context.makeImage() else { throw BoardImageImportError.invalidImage }
        return image
    }
}
#endif
