#if CBL_PARSER_TESTS
import Foundation

@main struct CBLParserTests {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try value() else { throw Failure(description: message) }
            checks += 1
        }
        func rejects(_ data: Data, _ message: String) throws {
            do { _ = try CBLParser.parse(data: data); throw Failure(description: message) }
            catch is CBLImportError { checks += 1 }
        }

        let source = fixture()
        let book = try CBLParser.parse(data: source, sourceFilename: "test.CBL")
        try check(book.title == "弈林新编 测试", "Library title decoded")
        try check(book.records.count == 1 && book.chapters.map(\.number) == [4], "Record and chapter structure")
        let record = book.records[0]
        try check(record.title == "4.1.01中炮巡河炮对屏风马(一)", "Exact original title")
        try check(record.rootComment == "  原注\r\n繁體字　\n末尾 \t🀄", "Original spaces, CRLF, script and surrogate pair preserved")
        try check(record.startingFEN == Position.initialFEN, "Source board decoded correctly")
        try check(record.rawPosition == Position.initial, "Raw source diagram matches board")
        try check(record.nodes.count == 6 && record.moveCount == 5, "All variation nodes read")
        try check(record.nodes[0].childIDs == [1], "Root continuation")
        try check(record.nodes[1].childIDs == [2, 5], "Sibling move restored to correct parent")
        try check(record.nodes[2].childIDs == [3, 4], "Nested variation retains two child moves")
        try check(record.nodes.map(\.parentID) == [nil, 0, 1, 2, 2, 1], "Flat tree parent links")
        try check(record.nodes[1].uci == "h2e2" && record.nodes[2].uci == "h9g7", "Coordinate conversion")
        try check(record.variationCount == 2, "Additional branch entry count")
        try check(record.nodes[4].reservedByte == 1 && record.issues.contains { $0.kind == "reserved-node-byte" }, "Reserved metadata retained")
        try check(record.nodes[5].comment == "  分支原注\r\n", "Branch commentary retains trailing whitespace")
        try check(book.sourceByteCount == source.count && book.sourceSHA256.count == 64, "Source integrity metadata")
        try check(book.issues.contains { $0.kind == "missing-chapter" }, "Missing first chapter is explicit")
        try check(book.chapters[0].sections[0].recordIDs == [record.id], "Chapter directory includes stable ID")
        let again = try CBLParser.parse(data: source, sourceFilename: "renamed.CBL")
        try check(again.id == book.id && again.records[0].id == record.id, "File renaming does not reset stable progress identity")
        let encoded = try JSONEncoder().encode(book)
        try check(try JSONDecoder().decode(BookDocument.self, from: encoded) == book, "Codable preserves source and complete flat tree")
        try compareComments(book: book, source: source) { try check($0, $1) }
        var otherBook = source
        otherBook.replaceSubrange(64..<(64 + 512), with: repeatElement(UInt8(0), count: 512))
        putText(&otherBook, at: 64, text: "另一部棋书")
        let generic = try CBLParser.parse(data: otherBook)
        try check(generic.chapters[0].title == "第 4 章" && generic.chapters[0].sections[0].title == "第 1 节",
                  "Unrelated books are not mislabeled with Yilin chapter names")
        try check(!generic.issues.contains { $0.kind == "missing-chapter" }, "Yilin completeness note is not applied to unrelated books")

        for count in [0, 1, 15, 79, 80, 95, 96, 255, 256, 2_470] {
            try rejects(Data(source.prefix(count)), "Truncated fixture must fail safely at \(count)")
        }
        var malformed = source; malformed[16] = 2
        try rejects(malformed, "Unsupported library version rejected")
        malformed = source; malformed[1024 + 19] = 1
        try rejects(malformed, "Unsupported record version rejected")
        malformed = source; malformed[1024 + 2214] = 0x80
        try rejects(malformed, "Unknown flags rejected")
        malformed = source; malformed[1024 + 2214 + 4] = 255
        try rejects(malformed, "Odd UTF16 byte length rejected")
        malformed = source; put32(&malformed, at: 1024 + 2214 + 4, value: UInt32.max)
        try rejects(malformed, "Oversized comment rejected without allocation")
        malformed = source; malformed[1024 + 2214 + 8] = 0; malformed[1024 + 2214 + 9] = 0xd8
        try rejects(malformed, "Unpaired UTF16 high surrogate rejected without replacement")
        malformed = source; malformed[1024 + 2214 + 8] = 0; malformed[1024 + 2214 + 9] = 0xdc
        try rejects(malformed, "Unpaired UTF16 low surrogate rejected")
        malformed = source; malformed[1024 + 2120] = 0xff
        try rejects(malformed, "Unknown piece encoding rejected")
        malformed = source; malformed[1024 + 2112] = 3
        try rejects(malformed, "Unknown side rejected")
        malformed = source; malformed[malformed.count - 1] = 1
        try rejects(malformed, "Unrecognized trailing data is not silently dropped")
        malformed = source; malformed[1024 + 2120 + 4] = 0
        let invalidPosition = try CBLParser.parse(data: malformed).records[0]
        try check(invalidPosition.issues.contains { $0.kind == "source-position" }, "Invalid original position is retained with a warning")
        try check(invalidPosition.rootComment == record.rootComment && invalidPosition.rawPosition.board.count == 90, "Invalid diagram still supports reading without changing text")

        // The private user book is optional, never copied into repository fixtures.
        if let path = CommandLine.arguments.dropFirst().first ?? ProcessInfo.processInfo.environment["XQ_CBL_FIXTURE"] {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let imported = try CBLParser.parse(url: url)
            try check(imported.sourceSHA256.count == 64, "Imported source has a SHA256 identity")
            try check(imported.sourceByteCount == data.count, "Imported byte count matches the supplied source")
            try check(!imported.records.isEmpty, "The optional source contains records")
            let ids = imported.chapters.flatMap(\.recordIDs)
            try check(Set(ids).count == imported.records.count && ids.count == imported.records.count, "Every source record reachable exactly once from book directory")
            for entry in imported.records {
                try check(entry.nodes[0].parentID == nil && entry.nodes[0].uci == nil, "Root invariant")
                for node in entry.nodes {
                    try check(node.id < entry.nodes.count, "Node ID is a safe array index")
                    for child in node.childIDs {
                        try check(child > node.id && entry.nodes[child].parentID == node.id, "Every branch has an acyclic matching parent")
                    }
                }
            }
            try compareComments(book: imported, source: data) { try check($0, $1) }
            print("CBL actual source: \(imported.records.count) records, \(imported.moveCount) moves, \(imported.commentCount) comments, \(imported.variationCount) branches, \(imported.commentaryCharacterCount) characters")
            if CommandLine.arguments.contains("--audit") { try auditLegality(book: imported) }
        }
        print("CBL parser tests passed (\(checks) checks)")
    }

    /// Diagnostic only: source positions, moves, commentary and side markers are not repaired.
    private static func auditLegality(book: BookDocument) throws {
        var invalidRoots: [[String: Any]] = []
        var firstFailures: [[String: Any]] = []
        var sideMismatches: [[String: Any]] = []
        var legalMoves = 0, skippedDescendants = 0, invalidRootMoves = 0, completeRecords = 0
        for (recordIndex, record) in book.records.enumerated() {
            var base: [String: Any] = ["recordIndex": recordIndex + 1, "id": record.id, "title": record.title]
            let root = record.rawPosition
            for child in record.nodes[record.rootNodeID].childIDs {
                guard let uci = record.nodes[child].uci, let move = Move(uci: uci), let piece = root[move.from], piece.side != root.sideToMove else { continue }
                var mismatch = base
                mismatch["node"] = child; mismatch["uci"] = uci
                mismatch["sourceSide"] = root.sideToMove.rawValue; mismatch["movingPieceSide"] = piece.side.rawValue
                sideMismatches.append(mismatch)
            }
            do { try root.validate() } catch {
                base["reason"] = error.localizedDescription; base["fen"] = root.fen
                invalidRoots.append(base); invalidRootMoves += record.moveCount
                continue
            }
            var mainline = Set<Int>()
            var cursor = record.rootNodeID
            while let child = record.nodes[cursor].childIDs.first { mainline.insert(child); cursor = child }
            var positions = Array<Position?>(repeating: nil, count: record.nodes.count)
            positions[record.rootNodeID] = root
            var hasFailure = false
            for node in record.nodes.dropFirst() {
                guard let parentID = node.parentID, let parent = positions[parentID] else { skippedDescendants += 1; continue }
                do {
                    guard let uci = node.uci, let move = Move(uci: uci) else { throw Failure(description: "无效的 UCI 着法") }
                    positions[node.id] = try parent.applying(move: move)
                    legalMoves += 1
                } catch {
                    hasFailure = true
                    var failure = base
                    failure["node"] = node.id; failure["uci"] = node.uci ?? ""
                    failure["parent"] = parentID; failure["mainline"] = mainline.contains(node.id)
                    failure["reason"] = error.localizedDescription; failure["parentFEN"] = parent.fen
                    firstFailures.append(failure)
                }
            }
            if !hasFailure { completeRecords += 1 }
        }
        let summary: [String: Any] = ["validRoots": book.records.count - invalidRoots.count,
                                     "invalidRoots": invalidRoots.count, "fullyLegalRecordsIncludingText": completeRecords,
                                     "legalMoves": legalMoves, "firstFailingMoves": firstFailures.count,
                                     "mainlineFailures": firstFailures.filter { $0["mainline"] as? Bool == true }.count,
                                     "branchFailures": firstFailures.filter { $0["mainline"] as? Bool == false }.count,
                                     "skippedDescendantsOfMoveFailures": skippedDescendants,
                                     "movesInInvalidRootRecords": invalidRootMoves,
                                     "firstMoveSideMismatches": sideMismatches.count]
        for (kind, entries) in [("summary", [summary]), ("invalidRoot", invalidRoots), ("firstFailingMove", firstFailures), ("firstMoveSideMismatch", sideMismatches)] {
            for var entry in entries {
                entry["kind"] = kind
                let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys, .withoutEscapingSlashes])
                print(String(decoding: data, as: UTF8.self))
            }
        }
    }

    private static func compareComments(book: BookDocument, source: Data,
                                         check: (Bool, String) throws -> Void) throws {
        for record in book.records {
            for node in record.nodes where node.flags & 4 != 0 {
                let offset = node.sourceOffset + 4
                let length = Int(source[offset]) | Int(source[offset + 1]) << 8 | Int(source[offset + 2]) << 16 | Int(source[offset + 3]) << 24
                var bytes: [UInt8] = []
                for unit in node.comment.utf16 { bytes.append(UInt8(unit & 255)); bytes.append(UInt8(unit >> 8)) }
                try check(bytes == Array(source[(offset + 4)..<(offset + 4 + length)]), "Every source comment round-trips byte-for-byte")
            }
        }
    }

    private static func put32(_ data: inout Data, at offset: Int, value: UInt32) {
        for byte in 0..<4 { data[offset + byte] = UInt8((value >> (8 * byte)) & 255) }
    }

    private static func putText(_ data: inout Data, at offset: Int, text: String) {
        for (index, unit) in text.utf16.enumerated() {
            data[offset + index * 2] = UInt8(unit & 255)
            data[offset + index * 2 + 1] = UInt8(unit >> 8)
        }
    }

    private static func fixture() -> Data {
        let start = 1024
        var data = Data(repeating: 0, count: start + 4096)
        data.replaceSubrange(0..<16, with: "CCBridgeLibrary\0".utf8)
        put32(&data, at: 16, value: 3)
        for index in 20..<36 { data[index] = UInt8(index) }
        putText(&data, at: 64, text: "弈林新编 测试")
        data.replaceSubrange(start..<(start + 16), with: "CCBridge Record\0".utf8)
        data[start + 19] = 2
        for index in 20..<36 { data[start + index] = UInt8(index + 20) }
        putText(&data, at: start + 180, text: "4.1.01中炮巡河炮对屏风马(一)")
        put32(&data, at: start + 2112, value: 1)
        put32(&data, at: start + 2116, value: 1)
        let codes: [PieceKind: UInt8] = [.rook: 1, .horse: 2, .elephant: 3, .advisor: 4, .king: 5, .cannon: 6, .pawn: 7]
        for (index, piece) in Position.initial.board.enumerated() {
            if let piece { data[start + 2120 + index] = (piece.side == .red ? 0x10 : 0x20) | codes[piece.kind]! }
        }
        var cursor = start + 2214
        func node(flags: UInt8, reserved: UInt8 = 0, from: UInt8, to: UInt8, comment: String? = nil) {
            data.replaceSubrange(cursor..<(cursor + 4), with: [flags, reserved, from, to]); cursor += 4
            if let comment {
                let length = comment.utf16.count * 2
                put32(&data, at: cursor, value: UInt32(length)); cursor += 4
                putText(&data, at: cursor, text: comment); cursor += length
            }
        }
        node(flags: 4, from: 0, to: 0, comment: "  原注\r\n繁體字　\n末尾 \t🀄")
        node(flags: 0, from: 70, to: 67)
        node(flags: 2, from: 7, to: 24)
        node(flags: 3, from: 88, to: 69)
        node(flags: 1, reserved: 1, from: 82, to: 65)
        node(flags: 5, from: 1, to: 20, comment: "  分支原注\r\n")
        return data
    }
}
#endif
