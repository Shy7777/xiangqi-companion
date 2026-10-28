import Foundation

/// A book imported from a user-supplied file. Source text is never normalized in storage.
struct BookDocument: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let sourceFilename: String
    let sourceSHA256: String
    let sourceByteCount: Int
    let records: [BookRecord]
    let chapters: [BookChapter]
    let issues: [BookImportIssue]

    var moveCount: Int { records.reduce(0) { $0 + $1.moveCount } }
    var commentCount: Int { records.reduce(0) { $0 + $1.commentCount } }
    var variationCount: Int { records.reduce(0) { $0 + $1.variationCount } }
    var commentaryCharacterCount: Int {
        records.reduce(0) { total, record in total + record.nodes.reduce(0) { $0 + $1.comment.unicodeScalars.count } }
    }
}

struct BookChapter: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let number: Int
    let title: String
    let sections: [BookSection]

    var recordIDs: [String] { sections.flatMap(\.recordIDs) }
}

struct BookSection: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let recordIDs: [String]
}

struct BookImportIssue: Codable, Equatable, Sendable {
    let kind: String
    let message: String
    let recordID: String?
}

struct BookRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    /// Exact source title, including numbering errors, spelling and spacing.
    let title: String
    /// Presentation-only corrections. This must never replace `title` in an export.
    let displayTitle: String
    let chapterNumber: Int?
    let sectionID: String
    let sectionTitle: String
    let startingFEN: String
    let initialBoard: [UInt8]
    let sideToMove: String
    let nodes: [BookNode]
    let rootNodeID: Int
    let isSupplement: Bool
    let sourceOffset: Int
    let sourceByteCount: Int
    let issues: [BookImportIssue]

    var moveCount: Int { max(0, nodes.count - 1) }
    var commentCount: Int { nodes.reduce(0) { $0 + (($1.flags & 4) != 0 ? 1 : 0) } }
    var variationCount: Int { nodes.reduce(0) { $0 + max(0, $1.childIDs.count - 1) } }
    var isReadingOnly: Bool { moveCount == 0 }
    var rootComment: String { nodes.indices.contains(rootNodeID) ? nodes[rootNodeID].comment : "" }

    /// Source diagrams may violate today's position validator. Reading remains possible;
    /// callers must validate this position before engine analysis or interactive play.
    var rawPosition: Position {
        let board = initialBoard.count == 90 ? initialBoard : Array(repeating: UInt8(0), count: 90)
        return Position(board: board.map(Self.piece), sideToMove: sideToMove == "b" ? .black : .red)
    }

    static func piece(_ code: UInt8) -> Piece? {
        guard code != 0 else { return nil }
        let side: Side
        switch code >> 4 { case 1: side = .red; case 2: side = .black; default: return nil }
        let kind: PieceKind
        switch code & 15 {
        case 1: kind = .rook
        case 2: kind = .horse
        case 3: kind = .elephant
        case 4: kind = .advisor
        case 5: kind = .king
        case 6: kind = .cannon
        case 7: kind = .pawn
        default: return nil
        }
        return Piece(side: side, kind: kind)
    }
}

/// Flat preorder storage avoids recursive Codable depth limits. IDs index `record.nodes`.
struct BookNode: Codable, Equatable, Sendable, Identifiable {
    let id: Int
    let parentID: Int?
    var childIDs: [Int]
    let uci: String?
    /// Exact UTF-16 source text, including line endings and leading/trailing whitespace.
    let comment: String
    /// Absolute offset in the immutable source CBL, useful for text-integrity verification.
    let sourceOffset: Int
    let flags: UInt8
    let reservedByte: UInt8
}
