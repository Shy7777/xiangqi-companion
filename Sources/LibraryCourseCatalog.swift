import Foundation
import CryptoKit

/// Source-file sections are navigation, not claims about a learner's level.
enum LibraryCourseSection: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case opening, checkmates, endgames, patterns, classics, other
    var id: String { rawValue }
    var order: Int {
        switch self {
        case .opening: return 0
        case .checkmates: return 1
        case .endgames: return 2
        case .patterns: return 3
        case .classics: return 4
        case .other: return 5
        }
    }
    var title: String {
        switch self {
        case .opening: return "布局局面"
        case .checkmates: return "杀法训练"
        case .endgames: return "残局研究"
        case .patterns: return "实用定式"
        case .classics: return "古谱选局"
        case .other: return "其他局面"
        }
    }
    var note: String {
        switch self {
        case .opening: return "这些局面已有前序，用来判断后续选择，不是从初始盘面开始的完整棋谱。"
        case .checkmates: return "从当前局面练习寻找杀棋；原始建议需经本地引擎核验。"
        case .endgames: return "练习当前子力结构下的攻守和胜和判断。"
        case .patterns: return "按上游文件保留实用残局定式，不把文件名中的胜和当作已证明结论。"
        case .classics: return "保留古谱局面出处，不冒充书籍全文或原著讲解。"
        case .other: return "未归入固定主题的原始局面，完整保留并可研究。"
        }
    }
    static func section(for path: String) -> Self {
        switch path {
        case "opening-repertoire.json": return .opening
        case "basic-checkmates.json", "advanced-checkmates.json": return .checkmates
        case "endgames_all.json", "extremely-challenging-endgames.json", "jianghu-endgames.json": return .endgames
        case "meng-ru-shen-ji.json", "shi-qing-ya-qu.json": return .classics
        default: return path.hasPrefix("Chess Patterns/") ? .patterns : .other
        }
    }
}

struct LibraryCourseMembership: Codable, Identifiable, Equatable, Sendable {
    /// A relative upstream path used only as a category ID, never a local path.
    let groupID: String
    let title: String
    let sourceIndex: Int
    let category: String
    let section: LibraryCourseSection
    var id: String { groupID + "#" + String(sourceIndex) }
    var displayTitle: String { title.simplifiedForDisplay }
    var displayCategory: String { category.simplifiedForDisplay }

    func sourceURL(commit: String) -> URL? {
        guard Self.isValidCommit(commit), Self.isSafeSourcePath(groupID) else { return nil }
        return URL(string: "https://github.com/dffge552/xiangqi-pwa-offline/blob/\(commit)/")?.appendingPathComponent(groupID)
    }
    static func isSafeSourcePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && path.utf8.count <= 1_024 && !path.contains("\\")
            && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
    static func isValidCommit(_ commit: String) -> Bool {
        commit.utf8.count == 40 && commit.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct LibraryCourseEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let fen: String
    let title: String
    let memberships: [LibraryCourseMembership]
    var displayTitle: String { title.simplifiedForDisplay }
    var primaryMembership: LibraryCourseMembership? { memberships.first }
    var lessonID: String { "library-" + id }
    /// Coarse navigation from literal upstream names; never inferred from FEN.
    /// Explicit cold-opening tags take precedence over ordinary name prefixes.
    var openingFamily: String? {
        guard let original = memberships.first(where: { $0.section == .opening })?.title else { return nil }
        let replacements = ["飛": "飞", "順": "顺", "馬": "马", "過": "过", "宮": "宫", "對": "对",
                            "兩": "两", "頭": "头", "門": "门", "極": "极", "砲": "炮"]
        let name = original.map { replacements[String($0)] ?? String($0) }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if name.contains("极冷门") { return "原标极冷门" }
        if name.contains("冷门") { return "原标冷门" }
        if ["顺相", "列相", "飞相"].contains(where: name.hasPrefix) { return "顺相／列相／飞相" }
        if name.hasPrefix("起马") { return "起马" }
        if name.hasPrefix("仕角炮") { return "仕角炮" }
        if name.hasPrefix("过宫炮") { return "过宫炮" }
        let ownPrefix = name.split(separator: "对", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        if name.hasPrefix("中炮") || (ownPrefix.hasPrefix("五") && ownPrefix.prefix(4).contains("炮")) { return "中炮及“五×炮”" }
        if name.hasPrefix("顺炮") { return "顺炮" }
        if name.hasPrefix("仙人指路") { return "仙人指路" }
        if name.hasPrefix("两头蛇") { return "两头蛇" }
        if name.hasPrefix("对兵") { return "对兵" }
        return openingTitleStem
    }
    /// The unmodified fine-grained prefix remains available for search/details.
    /// An unknown future title is retained, rather than assigned a guessed family.
    var openingTitleStem: String? {
        guard let original = memberships.first(where: { $0.section == .opening })?.title else { return nil }
        let split = [original.range(of: "對")?.lowerBound, original.range(of: "对")?.lowerBound].compactMap { $0 }.min()
        let name = (split.map { String(original[..<$0]) } ?? original).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? original.trimmingCharacters(in: .whitespacesAndNewlines) : name
    }
    var sections: [LibraryCourseSection] { Array(Set(memberships.map(\.section))).sorted { $0.order < $1.order } }
    func membership(in groupID: String?) -> LibraryCourseMembership? {
        guard let groupID else { return primaryMembership }
        return memberships.first { $0.groupID == groupID }
    }
    func sourceURL(commit: String) -> URL? { primaryMembership?.sourceURL(commit: commit) }
    static func identifier(fen: String) -> String {
        SHA256.hash(data: Data(fen.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    fileprivate var normalizedSearchText: String {
        let fields = [title, fen] + memberships.flatMap { [$0.title, $0.category, $0.section.title, $0.groupID] }
        return ChineseDisplayText.searchKey(fields.joined(separator: "\u{1F}"))
    }
}

struct LibraryCourseGroup: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let section: LibraryCourseSection
    /// Unique canonical FEN IDs, ordered by their first index in this file.
    let entryIDs: [String]
    let rawCount: Int
    let invalidCount: Int
    var displayTitle: String { title.simplifiedForDisplay }
    var validCount: Int {
        guard rawCount >= 0, invalidCount >= 0, invalidCount <= rawCount else { return 0 }
        return rawCount - invalidCount
    }
    var uniqueCount: Int { entryIDs.count }
}

/// Lightweight navigation only: no Position parsing, move replay, engine, store,
/// network, or disk access. Canonical FENs arrive from the validated source layer.
struct LibraryCourseCatalog: Codable, Equatable, Sendable {
    let pwaCommit: String
    let entries: [LibraryCourseEntry]
    let groups: [LibraryCourseGroup]
    private let entryOffsets: [String: Int]
    private let groupOffsets: [String: Int]
    /// Built once per catalog, never persisted or repeatedly transformed by a
    /// SwiftUI body while a user types or flips pages.
    private let normalizedSearchTexts: [String]
    static let empty = LibraryCourseCatalog(pwaCommit: "", entries: [], groups: [])
    var totalCount: Int { entries.count }

    init(pwaCommit: String, entries: [LibraryCourseEntry], groups: [LibraryCourseGroup]) {
        self.pwaCommit = pwaCommit; self.entries = entries; self.groups = groups
        // Avoid trapping when an unvalidated decoded value contains duplicate IDs.
        // The adapter rejects duplicates; raw Codable values are not trusted stores.
        entryOffsets = entries.enumerated().reduce(into: [:]) { if $0[$1.element.id] == nil { $0[$1.element.id] = $1.offset } }
        groupOffsets = groups.enumerated().reduce(into: [:]) { if $0[$1.element.id] == nil { $0[$1.element.id] = $1.offset } }
        normalizedSearchTexts = entries.map(\.normalizedSearchText)
    }
    private enum CodingKeys: String, CodingKey { case pwaCommit, entries, groups }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(pwaCommit: try values.decode(String.self, forKey: .pwaCommit),
                  entries: try values.decode([LibraryCourseEntry].self, forKey: .entries),
                  groups: try values.decode([LibraryCourseGroup].self, forKey: .groups))
    }
    func entry(id: String) -> LibraryCourseEntry? { entryOffsets[id].map { entries[$0] } }
    func group(id: String) -> LibraryCourseGroup? { groupOffsets[id].map { groups[$0] } }
    func entries(in groupID: String? = nil, section: LibraryCourseSection? = nil, query: String = "") -> [LibraryCourseEntry] {
        let terms = ChineseDisplayText.searchTerms(query)
        func matches(at offset: Int) -> Bool {
            ChineseDisplayText.matches(normalizedText: normalizedSearchTexts[offset], terms: terms)
        }
        if let groupID {
            guard let group = group(id: groupID), section.map({ $0 == group.section }) ?? true else { return [] }
            return group.entryIDs.compactMap { id in
                guard let offset = entryOffsets[id], matches(at: offset) else { return nil }
                return entries[offset]
            }
        }
        return entries.enumerated().compactMap { offset, entry in
            guard (section.map { wanted in entry.memberships.contains { $0.section == wanted } } ?? true), matches(at: offset) else { return nil }
            return entry
        }
    }
}

enum LibraryCourseCatalogError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
