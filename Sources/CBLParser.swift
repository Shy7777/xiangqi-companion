import Foundation
import CryptoKit

enum CBLImportError: Error, LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return "棋书文件无法导入：" + message }
    }
}

/// Independently implemented reader for the inspected CCBridge Library 3 / Record 2
/// representation. No third-party parser code or dependencies are incorporated.
enum CBLParser {
    static let maximumFileBytes = 32 * 1_024 * 1_024
    static let maximumRecords = 10_000
    static let maximumNodes = 500_000
    static let maximumCommentBytes = 4 * 1_024 * 1_024

    static func parse(url: URL) throws -> BookDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              (80...maximumFileBytes).contains(size) else {
            throw CBLImportError.invalid("请选择不超过 32 MB 的普通 CBL 文件。")
        }
        return try parse(data: Data(contentsOf: url), sourceFilename: url.lastPathComponent)
    }

    static func parse(data: Data, sourceFilename: String = "棋书.CBL") throws -> BookDocument {
        guard (96...maximumFileBytes).contains(data.count) else {
            throw CBLImportError.invalid("文件为空、过短或超过 32 MB 上限。")
        }
        let bytes = Array(data)
        let reader = Reader(bytes: bytes)
        guard bytes.starts(with: Array("CCBridgeLibrary\0".utf8)),
              try reader.uint32(16, end: bytes.count) == 3 else {
            throw CBLImportError.invalid("当前支持象棋桥 CBL 3 棋库中的 CBR 2 棋谱。")
        }
        let signature = Array("CCBridge Record\0".utf8)
        var starts: [Int] = []
        // Match the entire record marker. Arbitrary ASCII substrings are not accepted.
        for offset in 80...(bytes.count - signature.count) where bytes[offset] == signature[0] {
            if bytes[offset..<(offset + signature.count)].elementsEqual(signature) {
                starts.append(offset)
                guard starts.count <= maximumRecords else { throw CBLImportError.invalid("棋谱数量超过安全上限。") }
            }
        }
        guard !starts.isEmpty else { throw CBLImportError.invalid("没有找到可读取的 CBR 2 棋谱记录。") }
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sourceTitle = try reader.fixedText(64, byteCount: 512, end: starts[0])
        let title = sourceTitle.isEmpty ? URL(fileURLWithPath: sourceFilename).deletingPathExtension().lastPathComponent : sourceTitle
        let isYilin = title.contains("弈林新编") || title.contains("弈林新編")
        let identifier = "cbl-" + bytes[20..<36].map { String(format: "%02x", $0) }.joined()
        var records: [BookRecord] = []
        var seenIDs = Set<String>()
        var nodeCount = 0
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : bytes.count
            let record = try parseRecord(reader: reader, start: start, end: end, documentID: identifier,
                                         remainingNodeBudget: maximumNodes - nodeCount, isYilin: isYilin)
            guard seenIDs.insert(record.id).inserted else {
                throw CBLImportError.invalid("发现重复棋谱标识；为避免覆盖学习进度，已停止导入。")
            }
            nodeCount += record.nodes.count
            records.append(record)
        }
        var issues = records.flatMap(\.issues)
        if isYilin && !records.contains(where: { $0.chapterNumber == 1 }) {
            issues.append(.init(kind: "missing-chapter", message: "当前文件从第二章开始，未包含第一章；文件内容不等同于纸书全文。", recordID: nil))
        }
        let chapters = makeChapters(records: records, isYilin: isYilin)
        return BookDocument(id: identifier, title: title, sourceFilename: sourceFilename, sourceSHA256: sha,
                            sourceByteCount: bytes.count, records: records, chapters: chapters, issues: issues)
    }

    private static func parseRecord(reader: Reader, start: Int, end: Int, documentID: String,
                                    remainingNodeBudget: Int, isYilin: Bool) throws -> BookRecord {
        try reader.require(start, count: 2_218, end: end)
        guard reader.bytes[(start + 16)..<(start + 20)].elementsEqual([0, 0, 0, 2]) else {
            throw CBLImportError.invalid("含有不支持的 CBR 版本（位置 \(start)）。")
        }
        let uuid = reader.bytes[(start + 20)..<(start + 36)].map { String(format: "%02x", $0) }.joined()
        let id = documentID + "-" + uuid
        let title = try reader.fixedText(start + 180, byteCount: 128, end: end)
        let category = classify(title, isYilin: isYilin)
        var issues: [BookImportIssue] = []
        if title != category.displayTitle {
            issues.append(.init(kind: "source-title-correction", message: "目录显示已校订编号或明显错字，原始标题仍完整保留：" + title, recordID: id))
        }
        if category.supplement {
            issues.append(.init(kind: "supplement", message: "本条标题注明来自《象棋残局新论》，单独列为补充，不冒充《弈林新编》原注。", recordID: id))
        }
        let sideValue = try reader.uint32(start + 2112, end: end)
        guard sideValue == 1 || sideValue == 2 else { throw CBLImportError.invalid("棋谱行棋方编码无法识别（\(title)）。") }
        let side = sideValue == 2 ? "b" : "w"
        let fullmove = max(1, try reader.uint32(start + 2116, end: end))
        let board = Array(reader.bytes[(start + 2120)..<(start + 2210)])
        guard board.allSatisfy({ $0 == 0 || BookRecord.piece($0) != nil }) else {
            throw CBLImportError.invalid("棋谱包含无法识别的棋子编码（\(title)）。")
        }
        let position = Position(board: board.map(BookRecord.piece), sideToMove: side == "b" ? .black : .red)
        var fenFields = position.fen.split(separator: " ").map(String.init)
        fenFields[5] = String(fullmove)
        let fen = fenFields.joined(separator: " ")
        do { _ = try Position(fen: fen) } catch {
            issues.append(.init(kind: "source-position", message: "原始局面未通过现行棋规检查；保留图与原注，练习及引擎分析需先确认局面。" + error.localizedDescription, recordID: id))
        }
        var cursor = start + 2214
        var nodes: [BookNode] = []
        var nextParent: Int?
        var pendingSiblingParents: [Int] = []
        while true {
            guard nodes.count < remainingNodeBudget else { throw CBLImportError.invalid("棋谱节点超过安全上限。") }
            try reader.require(cursor, count: 4, end: end)
            let nodeOffset = cursor
            let flags = reader.bytes[cursor]
            let reserved = reader.bytes[cursor + 1]
            let from = Int(reader.bytes[cursor + 2]), to = Int(reader.bytes[cursor + 3])
            guard flags & 0xf8 == 0 else { throw CBLImportError.invalid("存在未知节点标记（\(title)，位置 \(cursor)）。") }
            let nodeID = nodes.count
            if nodeID == 0 {
                guard from == 0, to == 0, flags & 2 == 0 else { throw CBLImportError.invalid("棋谱根节点结构无效（\(title)）。") }
            } else {
                guard from < 90, to < 90, nextParent != nil else { throw CBLImportError.invalid("着法坐标或分支结构无效（\(title)）。") }
            }
            cursor += 4
            var comment = ""
            if flags & 4 != 0 {
                let length = try reader.uint32(cursor, end: end)
                cursor += 4
                guard length <= maximumCommentBytes else { throw CBLImportError.invalid("单段评注超过安全上限。") }
                comment = try reader.text(cursor, byteCount: length, end: end)
                cursor += length
            }
            let uci = nodeID == 0 ? nil : Square(row: from / 9, col: from % 9).coordinate + Square(row: to / 9, col: to % 9).coordinate
            let node = BookNode(id: nodeID, parentID: nextParent, childIDs: [], uci: uci, comment: comment,
                                sourceOffset: nodeOffset, flags: flags, reservedByte: reserved)
            nodes.append(node)
            if let parent = nextParent { nodes[parent].childIDs.append(nodeID) }
            if flags & 2 != 0, let parent = nextParent { pendingSiblingParents.append(parent) }
            if flags & 1 == 0 { nextParent = nodeID }
            else if let siblingParent = pendingSiblingParents.popLast() { nextParent = siblingParent }
            else { break }
        }
        if nodes.contains(where: { $0.reservedByte != 0 }) {
            issues.append(.init(kind: "reserved-node-byte", message: "原文件含非零保留字节，已逐节点保留，未据此改写原谱。", recordID: id))
        }
        let tail = reader.bytes[cursor..<end]
        if tail.contains(where: { $0 != 0 }) {
            // This inspected record repeats its immediately preceding 76-byte suffix.
            // Require exact bytes and all-zero padding; never discard an unknown tail.
            let duplicateLength = 76
            if cursor - start == 5266, cursor + duplicateLength <= end,
               reader.bytes[cursor..<(cursor + duplicateLength)].elementsEqual(reader.bytes[(cursor - duplicateLength)..<cursor]),
               reader.bytes[(cursor + duplicateLength)..<end].allSatisfy({ $0 == 0 }) {
                issues.append(.init(kind: "duplicate-tail", message: "有效棋谱树后有 76 字节完全重复尾段；原文件保留，学习树不重复计入。", recordID: id))
            } else {
                throw CBLImportError.invalid("有效棋谱树后存在未识别的数据（\(title)，位置 \(cursor)），未静默丢弃。")
            }
        }
        return BookRecord(id: id, title: title, displayTitle: category.displayTitle, chapterNumber: category.chapter,
                          sectionID: category.sectionID, sectionTitle: category.sectionTitle, startingFEN: fen,
                          initialBoard: board, sideToMove: side, nodes: nodes, rootNodeID: 0,
                          isSupplement: category.supplement, sourceOffset: start, sourceByteCount: end - start, issues: issues)
    }

    private struct Category {
        var chapter: Int?
        var sectionID: String
        var sectionTitle: String
        var displayTitle: String
        var supplement: Bool
    }

    private static func classify(_ title: String, isYilin: Bool) -> Category {
        let prefix = String(title.prefix { $0.isASCII && ($0.isNumber || $0 == ".") })
        let numbers = prefix.split(separator: ".").compactMap { Int($0) }
        let chapter = numbers.first
        if !isYilin {
            let chapterID = chapter.map { "chapter-\($0)" } ?? "unclassified"
            let sectionNumber = numbers.count >= 3 ? numbers[1] : nil
            return Category(chapter: chapter, sectionID: sectionNumber.map { chapterID + "-section-\($0)" } ?? chapterID + "-main",
                            sectionTitle: sectionNumber.map { "第 \($0) 节" } ?? "正文棋谱", displayTitle: title, supplement: false)
        }
        var display = title
        if title.hasPrefix("6.17第十六局") { display = title.replacingOccurrences(of: "6.17", with: "6.16", options: .anchored) }
        if title.hasPrefix("6.40第四十一局") { display = title.replacingOccurrences(of: "6.40", with: "6.41", options: .anchored) }
        display = display.replacingOccurrences(of: "炮辗丹沙", with: "炮碾丹砂")
        let supplement = title.contains("象棋残局新论")
        let chapterID = chapter.map { "chapter-\($0)" } ?? "unclassified"
        var sectionID = chapterID + "-main"
        var sectionTitle = "正文棋谱"
        let chapterIntroductions = [2: "第二章", 3: "第三章", 4: "第四章", 5: "第五章", 6: "第六章", 7: "第七章", 8: "第八章"]
        if let number = chapter, let marker = chapterIntroductions[number], title.contains(marker) {
            sectionID = chapterID + "-intro"; sectionTitle = "章节导读"
        } else if supplement {
            sectionID = chapterID + "-supplement"; sectionTitle = "补充 · 象棋残局新论"
        } else if let number = chapter, [3, 4, 5].contains(number), numbers.count >= 3 {
            let sub = numbers[1]
            sectionID = chapterID + "-section-\(sub)"
            let titles: [Int: [String]] = [
                3: ["让单马", "让双马"],
                4: ["中炮巡河炮对屏风马", "中炮过河车对屏风马平炮兑车", "当头炮巡河车对屏风马", "当头炮对单提马", "五六炮对屏风马", "五七炮对屏风马", "进兵局", "顺炮直车对横车", "顺炮横车对直车", "列手炮"],
                5: ["弃马陷车局", "弃炮陷车局", "五七炮弃车局", "车换马炮局", "高左炮局", "屏风马过河炮局", "中局攻守法"]
            ]
            if let values = titles[number], (1...values.count).contains(sub) { sectionTitle = values[sub - 1] }
            else { sectionTitle = "第 \(sub) 节" }
        } else if chapter == 2 {
            let groups = ["杀法初阶", "例和残局", "兑子与度数", "布局入门", "全局浅释", "谈谈怎样掌握先手", "实战布局琐谈"]
            if let group = groups.firstIndex(where: { title.contains($0) }) {
                sectionID = chapterID + "-section-\(group + 2)"; sectionTitle = groups[group]
            } else { sectionID = chapterID + "-section-1"; sectionTitle = "线位与子力运用" }
        } else if title.contains("参考局") {
            sectionID = chapterID + "-reference"; sectionTitle = "参考对局"
        } else if chapter == 7, numbers.count >= 2 {
            let number = numbers[1]
            sectionID = chapterID + "-section-\(number)"
            let titles = ["短棹轻舟", "双马饮泉", "阳春白雪", "雪拥蓝关"]
            sectionTitle = (1...titles.count).contains(number) ? titles[number - 1] : "第 \(number) 局"
        } else if chapter == 8 { sectionTitle = "全局评注" }
        else if chapter == 6 { sectionTitle = "残局研究五十局" }
        return Category(chapter: chapter, sectionID: sectionID, sectionTitle: sectionTitle, displayTitle: display, supplement: supplement)
    }

    private static func makeChapters(records: [BookRecord], isYilin: Bool) -> [BookChapter] {
        let names = isYilin ? [2: "象棋基本知识", 3: "让子棋的研究", 4: "布局研究", 5: "中局研究", 6: "残局研究", 7: "古局新编", 8: "对局评注"] : [:]
        let numbers = Set(records.map { $0.chapterNumber ?? 0 }).sorted()
        return numbers.map { number in
            let members = records.filter { ($0.chapterNumber ?? 0) == number }
            let sectionIDs = Set(members.map(\.sectionID)).sorted { lhs, rhs in
                func rank(_ value: String) -> Int {
                    if value.hasSuffix("-intro") { return -1 }
                    if value.hasSuffix("-main") { return 0 }
                    if value.hasSuffix("-reference") { return 1_001 }
                    if value.hasSuffix("-supplement") { return 1_002 }
                    return Int(value.split(separator: "-").last ?? "") ?? 1_000
                }
                let left = rank(lhs), right = rank(rhs)
                return left == right ? lhs < rhs : left < right
            }
            let sections = sectionIDs.map { id in
                let sectionRecords = members.filter { $0.sectionID == id }.sorted {
                    $0.displayTitle.compare($1.displayTitle, options: .numeric) == .orderedAscending
                }
                return BookSection(id: id, title: sectionRecords.first?.sectionTitle ?? "正文棋谱", recordIDs: sectionRecords.map(\.id))
            }
            return BookChapter(id: "chapter-\(number)", number: number, title: names[number] ?? (number == 0 ? "未分类" : "第 \(number) 章"), sections: sections)
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        func require(_ offset: Int, count: Int, end: Int) throws {
            guard offset >= 0, count >= 0, end <= bytes.count, offset <= end, count <= end - offset else {
                throw CBLImportError.invalid("数据被截断或长度越界（位置 \(offset)）。")
            }
        }
        func uint32(_ offset: Int, end: Int) throws -> Int {
            try require(offset, count: 4, end: end)
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        func fixedText(_ offset: Int, byteCount: Int, end: Int) throws -> String {
            try require(offset, count: byteCount, end: end)
            var length = 0
            while length + 1 < byteCount, bytes[offset + length] != 0 || bytes[offset + length + 1] != 0 { length += 2 }
            return try text(offset, byteCount: length, end: end)
        }
        func text(_ offset: Int, byteCount: Int, end: Int) throws -> String {
            try require(offset, count: byteCount, end: end)
            guard byteCount % 2 == 0 else { throw CBLImportError.invalid("评注 UTF-16 字节长度为奇数，未替换或丢弃原文。") }
            var units: [UInt16] = []
            units.reserveCapacity(byteCount / 2)
            for index in stride(from: offset, to: offset + byteCount, by: 2) {
                units.append(UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
            }
            var index = 0
            while index < units.count {
                let value = units[index]
                if (0xd800...0xdbff).contains(value) {
                    guard index + 1 < units.count, (0xdc00...0xdfff).contains(units[index + 1]) else {
                        throw CBLImportError.invalid("评注含未配对 UTF-16 字符，未用替代字符修改原文。")
                    }
                    index += 2
                } else {
                    guard !(0xdc00...0xdfff).contains(value) else { throw CBLImportError.invalid("评注含未配对 UTF-16 字符。") }
                    index += 1
                }
            }
            let text = String(decoding: units, as: UTF16.self)
            guard Array(text.utf16) == units else { throw CBLImportError.invalid("评注回编码校验失败，导入已停止。") }
            return text
        }
    }
}
