import Foundation
import CryptoKit

/// An upstream index entry, not downloaded teaching material or a verified endorsement.
struct AwesomeResourceItem: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL
    /// Original English headings remain available for search and future upstream categories.
    let category: String
    let subcategory: String?
    /// Plain text from the complete resource line, with nested-list parent context if present.
    let context: String
    /// One-based physical line in the supplied Markdown, including any provenance comment.
    let sourceLine: Int

    var categoryTitle: String { Self.categoryNames[category.lowercased()] ?? category }
    var subcategoryTitle: String? { subcategory.map { Self.subcategoryNames[$0.lowercased()] ?? $0 } }
    var searchText: String {
        [title, context, category, subcategory ?? "", categoryTitle, subcategoryTitle ?? "", url.absoluteString]
            .joined(separator: " ")
    }
    func matches(_ query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy {
            searchText.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static let categoryNames = [
        "general websites": "综合网站", "websites to play": "对弈网站", "games databases": "棋谱数据库",
        "books": "书籍", "youtube channels": "视频频道", "engines": "引擎",
        "computer xiangqi": "计算机象棋", "other useful tools": "其他工具", "social": "社群"
    ]
    static let subcategoryNames = [
        "introductory books": "入门书籍", "opening": "布局", "tactics / puzzles": "战术与题集",
        "endgames": "残局", "ancient manuals": "古谱", "games collections": "对局集"
    ]

    /// Exact absolute URL + original category + subcategory; title, order and commit are excluded.
    /// NUL is forbidden in parsed input, so the separators cannot collide with field contents.
    static func stableID(url: URL, category: String, subcategory: String?) -> String {
        let bytes = Data([url.absoluteString, category, subcategory ?? ""].joined(separator: "\0").utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

enum AwesomeResourceIndexError: Error, LocalizedError, Equatable, Sendable {
    case invalidMetadata, inputTooLarge, malformedInput, noResources
    var errorDescription: String? {
        switch self {
        case .invalidMetadata: return "资源目录缺少有效的完整提交编号或抓取时间。"
        case .inputTooLarge: return "资源目录超过解析上限，请保留现有目录。"
        case .malformedInput: return "资源目录包含无效文本，未替换现有目录。"
        case .noResources: return "没有找到正文中的资源链接，未替换现有目录。"
        }
    }
}

/// A deterministic, network-free parser of the README's resource sections.
/// This is not a general CommonMark renderer. Supports inline/reference links and autolinks,
/// tables and nested lists, and ignores headings, TOC, images, comments and code blocks.
struct AwesomeResourceIndex: Codable, Sendable, Equatable {
    static let currentVersion = 1
    static let maximumMarkdownBytes = 1_048_576
    static let maximumItems = 5_000
    static let upstreamRepository = URL(string: "https://github.com/lucaferranti/awesome-xiangqi")!
    static let attribution = "Luca Ferranti 与 awesome-xiangqi 贡献者 · CC0-1.0；许可仅适用于资源索引，不延伸到链接作品。上游描述未经逐项背书。"

    let version: Int
    let commit: String
    let fetchedAt: Date
    let items: [AwesomeResourceItem]

    static func parse(markdown: String, commit: String, fetchedAt: Date) throws -> AwesomeResourceIndex {
        guard commit.count == 40, commit.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              fetchedAt.timeIntervalSince1970.isFinite else { throw AwesomeResourceIndexError.invalidMetadata }
        guard markdown.utf8.count <= maximumMarkdownBytes else { throw AwesomeResourceIndexError.inputTooLarge }
        guard !markdown.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 32 && ![9, 10, 13].contains($0.value)) })
        else { throw AwesomeResourceIndexError.malformedInput }
        let lines = try visibleLines(markdown)
        var references: [String: String] = [:]
        for line in lines {
            if let ref = referenceDefinition(line) { references[referenceKey(ref.0)] = ref.1 }
        }
        var category: String?, subcategory: String?
        var parents: [(indent: Int, title: String)] = []
        var items: [AwesomeResourceItem] = [], seen = Set<String>()
        let excludedSections: Set<String> = ["contents", "table of contents", "toc", "license", "licence", "contributing", "contributors", "acknowledgements", "acknowledgments", "about"]
        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = heading(trimmed) {
                parents = []
                if heading.level == 1 { category = nil; subcategory = nil }
                else if heading.level == 2 {
                    category = excludedSections.contains(heading.title.lowercased()) ? nil : heading.title
                    subcategory = nil
                } else if heading.level == 3 { subcategory = heading.title }
                continue
            }
            guard let category, !trimmed.isEmpty, referenceDefinition(trimmed) == nil else { continue }
            let bullet = bulletInfo(line)
            if let bullet { parents.removeAll { $0.indent >= bullet.indent } }
            let parent = parents.map(\.title).joined(separator: " · ")
            let tokens = links(in: maskInlineCode(line), references: references)
            let plain = plainText(line, tokens: tokens)
            if let bullet, !plain.isEmpty {
                let shortParent = plain.components(separatedBy: " - ").first ?? plain
                parents.append((bullet.indent, shortParent))
            }
            let context = parent.isEmpty ? plain : parent + " — " + plain
            let firstLabel = tokens.first(where: { !$0.image }).map { cleanText($0.label) } ?? ""
            let prefix = tokens.first.map { cleanText(String(Array(line)[0..<$0.range.lowerBound])) } ?? ""
            for token in tokens where !token.image {
                guard let url = permittedURL(token.destination) else { continue }
                let label = cleanText(token.label)
                guard !label.isEmpty else { continue }
                var title = label
                if ["here", "link", "video", "live demo"].contains(label.lowercased()), !firstLabel.isEmpty, firstLabel != label {
                    title = firstLabel + " · " + label + " · " + (url.host ?? "")
                } else if !prefix.isEmpty { title = prefix + " · " + label }
                if !parent.isEmpty { title = parent + " · " + title }
                let id = AwesomeResourceItem.stableID(url: url, category: category, subcategory: subcategory)
                // First occurrence wins only within an identical category/subcategory. Cross-category
                // occurrences are meaningful and remain separate; query strings/fragments are retained.
                guard seen.insert(id).inserted else { continue }
                items.append(.init(id: id, title: title, url: url, category: category, subcategory: subcategory,
                                   context: context, sourceLine: offset + 1))
                guard items.count <= maximumItems else { throw AwesomeResourceIndexError.inputTooLarge }
            }
        }
        guard !items.isEmpty else { throw AwesomeResourceIndexError.noResources }
        return .init(version: currentVersion, commit: commit.lowercased(), fetchedAt: fetchedAt, items: items)
    }

    static func permittedURL(_ raw: String) -> URL? {
        let value = decodeEntities(raw)
        guard !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private struct LinkToken {
        let range: Range<Int>
        let label: String
        let destination: String
        let image: Bool
    }

    /// Keeps every newline, so sourceLine points back to the supplied README.
    private static func visibleLines(_ markdown: String) throws -> [String] {
        var inComment = false, fence: Character?, fenceCount = 0
        return try markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { raw in
                guard raw.utf8.count <= 65_536 else { throw AwesomeResourceIndexError.inputTooLarge }
                let chars = Array(raw)
                var result = "", index = 0
                while index < chars.count {
                    if inComment {
                        if index + 2 < chars.count, String(chars[index...index + 2]) == "-->" { inComment = false; index += 3 }
                        else { index += 1 }
                    } else if index + 3 < chars.count, String(chars[index...index + 3]) == "<!--" { inComment = true; index += 4 }
                    else { result.append(chars[index]); index += 1 }
                }
                let text = result.trimmingCharacters(in: .whitespaces)
                if let marker = text.first, marker == "`" || marker == "~" {
                    let count = text.prefix(while: { $0 == marker }).count
                    if count >= 3 {
                        if fence == nil { fence = marker; fenceCount = count; return "" }
                        if fence == marker, count >= fenceCount, text.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                            fence = nil; return ""
                        }
                    }
                }
                return fence == nil ? result : ""
            }
    }

    private static func heading(_ text: String) -> (level: Int, title: String)? {
        let count = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), text.dropFirst(count).first?.isWhitespace == true else { return nil }
        let title = cleanText(text.dropFirst(count).trimmingCharacters(in: CharacterSet(charactersIn: " #\t")))
        return (count, title)
    }

    private static func bulletInfo(_ text: String) -> (indent: Int, body: String)? {
        let prefix = text.prefix(while: { $0 == " " || $0 == "\t" })
        let rest = text.dropFirst(prefix.count)
        guard let marker = rest.first, "-*+".contains(marker), rest.dropFirst().first?.isWhitespace == true else { return nil }
        return (prefix.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }, String(rest.dropFirst()))
    }

    private static func referenceKey(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() }
    private static func referenceDefinition(_ text: String) -> (String, String)? {
        let chars = Array(text.trimmingCharacters(in: .whitespaces))
        guard chars.first == "[", let end = pairedEnd(chars, at: 0, open: "[", close: "]"),
              end + 1 < chars.count, chars[end + 1] == ":" else { return nil }
        let tail = String(chars.dropFirst(end + 2)).trimmingCharacters(in: .whitespaces)
        guard let destination = destination(tail) else { return nil }
        return (String(chars[1..<end]), destination)
    }

    private static func links(in line: String, references: [String: String]) -> [LinkToken] {
        let chars = Array(line)
        var result: [LinkToken] = [], index = 0
        while index < chars.count {
            if chars[index] == "\\" { index += 2; continue }
            if chars[index] == "<", let end = chars[(index + 1)...].firstIndex(of: ">") {
                let candidate = String(chars[(index + 1)..<end])
                if permittedURL(candidate) != nil {
                    result.append(.init(range: index..<(end + 1), label: candidate, destination: candidate, image: false))
                }
                index = end + 1; continue
            }
            guard chars[index] == "[" else { index += 1; continue }
            // An unmatched outer bracket cannot contain a well-formed outer link; stop instead
            // of rescanning a long hostile line once for every opening bracket.
            guard let labelEnd = pairedEnd(chars, at: index, open: "[", close: "]") else { break }
            let label = String(chars[(index + 1)..<labelEnd])
            let isImage = (index > 0 && chars[index - 1] == "!") || label.contains("![") || label.lowercased().contains("<img")
            var end = labelEnd + 1, target: String?
            if end < chars.count, chars[end] == "(", let close = pairedEnd(chars, at: end, open: "(", close: ")") {
                target = destination(String(chars[(end + 1)..<close])); end = close + 1
            } else if end < chars.count, chars[end] == "[", let close = pairedEnd(chars, at: end, open: "[", close: "]") {
                let ref = String(chars[(end + 1)..<close])
                target = references[referenceKey(ref.isEmpty ? label : ref)]; end = close + 1
            } else { target = references[referenceKey(label)] }
            if let target { result.append(.init(range: index..<end, label: label, destination: target, image: isImage)) }
            index = end
        }
        return result
    }

    private static func pairedEnd(_ chars: [Character], at start: Int, open: Character, close: Character) -> Int? {
        var depth = 0, index = start
        while index < chars.count {
            if chars[index] == "\\" { index += 2; continue }
            if chars[index] == open { depth += 1 }
            if chars[index] == close { depth -= 1; if depth == 0 { return index } }
            index += 1
        }
        return nil
    }

    private static func destination(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("<"), let close = text.firstIndex(of: ">") { return String(text[text.index(after: text.startIndex)..<close]) }
        guard let token = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        return String(token).replacingOccurrences(of: "\\(", with: "(").replacingOccurrences(of: "\\)", with: ")")
    }

    private static func maskInlineCode(_ line: String) -> String {
        var chars = Array(line), index = 0
        while index < chars.count {
            guard chars[index] == "`" else { index += 1; continue }
            let start = index
            while index < chars.count, chars[index] == "`" { index += 1 }
            let count = index - start
            var scan = index, closing: Int?
            while scan < chars.count {
                if chars[scan] != "`" { scan += 1; continue }
                let candidate = scan
                while scan < chars.count, chars[scan] == "`" { scan += 1 }
                if scan - candidate == count { closing = scan; break }
            }
            if let closing { for offset in start..<closing { chars[offset] = " " }; index = closing }
        }
        return String(chars)
    }

    private static func plainText(_ line: String, tokens: [LinkToken]) -> String {
        var chars = Array(line)
        for token in tokens.reversed() { chars.replaceSubrange(token.range, with: Array(token.image ? "" : token.label)) }
        return cleanText(String(chars))
    }

    private static func cleanText(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "^\\s*(?:[-*+]\\s+|[0-9]+[.)]\\s+)", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "[\\*`]+", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\\\([\\[\\]()*_])", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "|", with: " · ").trimmingCharacters(in: CharacterSet(charactersIn: " ,·\t"))
        return decodeEntities(value).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func decodeEntities(_ text: String) -> String {
        var text = text
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
    }
}

// Cached JSON receives the same URL/identity boundary as a newly parsed README. Decoding is
// still network-free; callers own persistence, sync scheduling and explicit link activation.
extension AwesomeResourceItem {
    private enum CodingKeys: String, CodingKey { case id, title, url, category, subcategory, context, sourceLine }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        url = try values.decode(URL.self, forKey: .url)
        category = try values.decode(String.self, forKey: .category)
        subcategory = try values.decodeIfPresent(String.self, forKey: .subcategory)
        context = try values.decode(String.self, forKey: .context)
        sourceLine = try values.decode(Int.self, forKey: .sourceLine)
        guard AwesomeResourceIndex.permittedURL(url.absoluteString) == url,
              !title.isEmpty, !category.isEmpty, !context.isEmpty, sourceLine > 0,
              [title, category, subcategory ?? "", context].allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 131_072 }),
              id == Self.stableID(url: url, category: category, subcategory: subcategory) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid resource URL, identity or text"))
        }
    }
}

extension AwesomeResourceIndex {
    private enum CodingKeys: String, CodingKey { case version, commit, fetchedAt, items }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        commit = try values.decode(String.self, forKey: .commit)
        fetchedAt = try values.decode(Date.self, forKey: .fetchedAt)
        items = try values.decode([AwesomeResourceItem].self, forKey: .items)
        guard version == Self.currentVersion, commit.count == 40,
              commit.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              fetchedAt.timeIntervalSince1970.isFinite, !items.isEmpty, items.count <= Self.maximumItems,
              Set(items.map(\.id)).count == items.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid resource index version, provenance or duplicates"))
        }
    }
}
