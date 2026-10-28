import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

// Apple API references (checked 2026-09-07):
// https://developer.apple.com/documentation/vision/vnrecognizetextrequest
// https://developer.apple.com/documentation/coreimage/cifilter/3228380-perspectivecorrection
// https://developer.apple.com/documentation/imageio/kcgimagepropertypixelwidth

enum BoardImageImportError: Error, LocalizedError, Equatable {
    case invalidImage, imageTooLarge, invalidCorners, chineseUnavailable, unresolved(Int), missingTurn, missingReview
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取这张单帧图片。请选择 PNG、JPEG、HEIC 或 TIFF。"
        case .imageTooLarge: return "图片须不超过 16 MiB、2400 万像素，任一边不超过 8192 像素。"
        case .invalidCorners: return "四角需要顺时针围住完整棋盘，不能交叉、过小或超出图片。"
        case .chineseUnavailable: return "此系统没有可用的中文文字识别。仍可进入手工校正。"
        case .unresolved(let count): return "还有 \(count) 格没有核对；未识别不等于空格。"
        case .missingTurn: return "请明确选择红方或黑方先走。"
        case .missingReview: return "请先查看合法棋盘预览，再确认方向与全部棋子。"
        }
    }
}

/// Unit coordinates use the displayed image's top-left origin. Corners enclose the whole
/// 9-by-10 cell area, including half a cell outside the outermost board intersections.
struct BoardImageCorners: Equatable, Sendable {
    var topLeft = CGPoint(x: 0.04, y: 0.04)
    var topRight = CGPoint(x: 0.96, y: 0.04)
    var bottomRight = CGPoint(x: 0.96, y: 0.96)
    var bottomLeft = CGPoint(x: 0.04, y: 0.96)
    static let full = BoardImageCorners(topLeft: .zero, topRight: CGPoint(x: 1, y: 0),
                                       bottomRight: CGPoint(x: 1, y: 1), bottomLeft: CGPoint(x: 0, y: 1))
    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
    mutating func set(_ point: CGPoint, at index: Int) {
        guard point.x.isFinite, point.y.isFinite else { return }
        let point = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
        switch index { case 0: topLeft = point; case 1: topRight = point; case 2: bottomRight = point; case 3: bottomLeft = point; default: break }
    }
    func validate() throws {
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            throw BoardImageImportError.invalidCorners
        }
        var area: CGFloat = 0
        for index in 0..<4 {
            let a = points[index], b = points[(index + 1) % 4], c = points[(index + 2) % 4]
            guard (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) > 0.002,
                  hypot(b.x - a.x, b.y - a.y) > 0.05 else { throw BoardImageImportError.invalidCorners }
            area += a.x * b.y - b.x * a.y
        }
        guard area > 0.06, topLeft.y < bottomLeft.y, topRight.y < bottomRight.y,
              topLeft.x < topRight.x, bottomLeft.x < bottomRight.x else { throw BoardImageImportError.invalidCorners }
    }
    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        // Projective (not bilinear) guide points agree with CIPerspectiveCorrection even when
        // the photo's opposite edges converge. Invalid in-progress drags get a finite fallback.
        let dx1 = topRight.x - bottomRight.x, dx2 = bottomLeft.x - bottomRight.x
        let dy1 = topRight.y - bottomRight.y, dy2 = bottomLeft.y - bottomRight.y
        let dx3 = topLeft.x - topRight.x + bottomRight.x - bottomLeft.x
        let dy3 = topLeft.y - topRight.y + bottomRight.y - bottomLeft.y
        let determinant = dx1 * dy2 - dx2 * dy1
        guard abs(determinant) > 0.000001 else { return topLeft }
        let g = (dx3 * dy2 - dx2 * dy3) / determinant
        let h = (dx1 * dy3 - dx3 * dy1) / determinant
        let denominator = g * x + h * y + 1
        guard abs(denominator) > 0.000001 else { return topLeft }
        let px = ((topRight.x - topLeft.x + g * topRight.x) * x + (bottomLeft.x - topLeft.x + h * bottomLeft.x) * y + topLeft.x) / denominator
        let py = ((topRight.y - topLeft.y + g * topRight.y) * x + (bottomLeft.y - topLeft.y + h * bottomLeft.y) * y + topLeft.y) / denominator
        return px.isFinite && py.isFinite ? CGPoint(x: px, y: py) : topLeft
    }
}

struct BoardImageCell: Equatable, Sendable {
    var piece: Piece? = nil
    var confidence: Float = 0
    var observedText = ""
    var confirmed = false
}

/// Every cell begins unreviewed, including high-confidence suggestions and apparently blank
/// cells. OCR absence is never silently converted into a confirmed empty square.
struct BoardImageDraft: Equatable, Sendable {
    var cells = Array(repeating: BoardImageCell(), count: 90)
    var sideToMove: Side?
    var redAtBottom = true
    var unresolvedCount: Int { cells.filter { !$0.confirmed }.count }
    var suggestedCount: Int { cells.filter { $0.piece != nil }.count }
    mutating func edit(_ index: Int, piece: Piece?) {
        guard cells.indices.contains(index) else { return }
        cells[index].piece = piece; cells[index].confirmed = true
    }
    /// UI labels this action explicitly: keep this row's proposed pieces; other cells are empty.
    mutating func confirmRow(_ row: Int) {
        guard (0..<10).contains(row), cells.count == 90 else { return }
        for index in (row * 9)..<(row * 9 + 9) { cells[index].confirmed = true }
    }
    func position() throws -> Position {
        guard cells.count == 90 else { throw XiangqiError.invalidPosition("图片校正需要完整 90 格") }
        guard let sideToMove else { throw BoardImageImportError.missingTurn }
        guard unresolvedCount == 0 else { throw BoardImageImportError.unresolved(unresolvedCount) }
        let pieces = cells.map(\.piece)
        let position = Position(board: redAtBottom ? pieces : Array(pieces.reversed()), sideToMove: sideToMove)
        try position.validate()
        return position
    }
    static func imageCell(normalizedCenter: CGPoint) -> Int? {
        guard normalizedCenter.x.isFinite, normalizedCenter.y.isFinite,
              (0..<1).contains(normalizedCenter.x), (0..<1).contains(normalizedCenter.y) else { return nil }
        return Int(normalizedCenter.y * 10) * 9 + Int(normalizedCenter.x * 9)
    }
    /// Returns the kind and a side only when the glyph itself distinguishes red/black.
    static func glyph(_ text: String) -> (kind: PieceKind, side: Side?)? {
        switch text {
        case "帅", "帥": return (.king, .red)
        case "将", "將": return (.king, .black)
        case "仕": return (.advisor, .red)
        case "士": return (.advisor, .black)
        case "相": return (.elephant, .red)
        case "象": return (.elephant, .black)
        case "兵": return (.pawn, .red)
        case "卒": return (.pawn, .black)
        case "俥": return (.rook, .red)
        case "傌": return (.horse, .red)
        case "车", "車": return (.rook, nil)
        case "马", "馬": return (.horse, nil)
        case "炮", "砲": return (.cannon, nil)
        default: return nil
        }
    }
}

enum BoardImageLoader {
    static let maximumBytes = 16 * 1024 * 1024
    static let maximumPixels = 24_000_000
    static let maximumDimension = 8192
    static let workingDimension = 1800
    static func read(_ url: URL) throws -> CGImage {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize else { throw BoardImageImportError.invalidImage }
        guard size > 0, size <= maximumBytes else { throw BoardImageImportError.imageTooLarge }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        return try decode(handle.read(upToCount: maximumBytes + 1) ?? Data())
    }
    static func decode(_ data: Data) throws -> CGImage {
        guard !data.isEmpty else { throw BoardImageImportError.invalidImage }
        guard data.count <= maximumBytes else { throw BoardImageImportError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int else {
            throw BoardImageImportError.invalidImage
        }
        try validateDimensions(width: width, height: height)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0,
            [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: workingDimension,
             kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw BoardImageImportError.invalidImage
        }
        return image
    }
    static func validateDimensions(width: Int, height: Int) throws {
        guard width >= 90, height >= 100, width <= maximumDimension, height <= maximumDimension,
              width <= maximumPixels / max(1, height) else { throw BoardImageImportError.imageTooLarge }
    }
}

struct BoardImageRecognition: Sendable {
    let image: CGImage
    let draft: BoardImageDraft
    let recognizedGlyphs: Int
    let observationCount: Int
}

/// Framework calls run on this actor, not on the UI actor. No URLSession, uploads, screen
/// permissions or model downloads. Results are suggestions; the draft still needs 90 reviews.
actor BoardImageRecognizer {
    func corrected(_ image: CGImage, corners: BoardImageCorners) throws -> CGImage {
        try Self.correct(image, corners: corners)
    }
    static func correct(_ image: CGImage, corners: BoardImageCorners) throws -> CGImage {
        try corners.validate()
        try Task.checkCancellation()
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        func convert(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * CGFloat(image.width), y: (1 - point.y) * CGFloat(image.height)) }
        filter.topLeft = convert(corners.topLeft); filter.topRight = convert(corners.topRight)
        filter.bottomLeft = convert(corners.bottomLeft); filter.bottomRight = convert(corners.bottomRight)
        guard let output = filter.outputImage, !output.extent.isEmpty, !output.extent.isInfinite else { throw BoardImageImportError.invalidCorners }
        let normalized = output.transformed(by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: 900 / output.extent.width, y: 1000 / output.extent.height))
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let result = context.createCGImage(normalized, from: CGRect(x: 0, y: 0, width: 900, height: 1000)) else {
            throw BoardImageImportError.invalidImage
        }
        return result
    }
    func recognize(_ image: CGImage, corners: BoardImageCorners) throws -> BoardImageRecognition {
        let corrected = try Self.correct(image, corners: corners)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012
        let languages = try request.supportedRecognitionLanguages()
        let chinese = ["zh-Hans", "zh-Hant"].filter { languages.contains($0) }
        guard !chinese.isEmpty else { throw BoardImageImportError.chineseUnavailable }
        request.recognitionLanguages = chinese
        request.customWords = ["帅", "将", "車", "馬", "炮", "兵", "卒", "士", "仕", "相", "象"]
        try VNImageRequestHandler(cgImage: corrected, options: [:]).perform([request])
        try Task.checkCancellation()
        var draft = BoardImageDraft(), glyphs = 0
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first else { continue }
            for range in text.string.indices.map({ $0..<text.string.index(after: $0) }) {
                let symbol = String(text.string[range])
                guard let glyph = BoardImageDraft.glyph(symbol),
                      let bounds = try? text.boundingBox(for: range),
                      let index = BoardImageDraft.imageCell(normalizedCenter: CGPoint(x: bounds.boundingBox.midX, y: 1 - bounds.boundingBox.midY)) else { continue }
                let ink = Self.inkSide(image: corrected, boundingBox: bounds.boundingBox)
                let side = glyph.side ?? ink
                let disagreement = glyph.side != nil && ink != nil && glyph.side != ink
                let confidence = disagreement ? min(text.confidence, 0.4) : text.confidence
                let piece = side.map { Piece(side: $0, kind: glyph.kind) }
                // Two detections in one cell are not silently merged into a confident answer.
                if !draft.cells[index].observedText.isEmpty {
                    draft.cells[index].confidence = 0
                    draft.cells[index].observedText += "/" + symbol
                } else {
                    draft.cells[index] = BoardImageCell(piece: piece, confidence: piece == nil ? 0 : confidence,
                                                       observedText: symbol, confirmed: false)
                }
                glyphs += 1
            }
        }
        return .init(image: corrected, draft: draft, recognizedGlyphs: glyphs, observationCount: request.results?.count ?? 0)
    }
    /// Only red/black ink pixels are considered. A shared glyph with ambiguous ink keeps
    /// no piece suggestion; the user chooses its side explicitly during correction.
    static func inkSide(image: CGImage, boundingBox: CGRect) -> Side? {
        let box = CGRect(x: boundingBox.minX * CGFloat(image.width), y: (1 - boundingBox.maxY) * CGFloat(image.height),
                         width: boundingBox.width * CGFloat(image.width), height: boundingBox.height * CGFloat(image.height)).integral
        guard let crop = image.cropping(to: box), let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = context.data else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var red = 0, black = 0
        for index in stride(from: 0, to: 64 * 64 * 4, by: 4) {
            let r = Int(bytes[index]), g = Int(bytes[index + 1]), b = Int(bytes[index + 2])
            guard bytes[index + 3] > 128 else { continue }
            if r > 65, r > g * 3 / 2 + 15, r > b * 3 / 2 + 15 { red += 1 }
            else if max(r, g, b) < 115, max(r, g, b) - min(r, g, b) < 50 { black += 1 }
        }
        if red >= 25 && red > black / 2 { return .red }
        if black >= 35 && red < 12 { return .black }
        return nil
    }
}
