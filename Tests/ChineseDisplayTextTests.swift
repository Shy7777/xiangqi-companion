#if CHINESE_DISPLAY_TEXT_TESTS
import Foundation

@main struct ChineseDisplayTextTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try value() else { throw Failure(description: message) }
            checks += 1
        }
        let fixtures = [
            ("飛相對屏風馬", "飞相对屏风马"),
            ("順炮直車對緩開", "顺炮直车对缓开"),
            ("過宮砲對反宮馬", "过宫炮对反宫马"),
            ("單車士相全勝雙卒", "单车士相全胜双卒"),
            ("將帥安全與殘局練習", "将帅安全与残局练习"),
            ("兩頭蛇轉中砲", "两头蛇转中炮"),
            ("適情雅趣 · 第 12 局", "适情雅趣 · 第 12 局"),
            ("起馬對進７卒", "起马对进７卒"),
            ("先看威胁，再改善子力。", "先看威胁，再改善子力。"),
            ("Pikafish 2026", "Pikafish 2026"),
            ("♟️ 象棋 1/4", "♟️ 象棋 1/4"),
            ("", "")
        ]
        for (original, expected) in fixtures {
            try check(ChineseDisplayText.simplified(original) == expected, "Simplified display: \(original)")
            try check(original.simplifiedForDisplay == expected, "String presentation adapter: \(original)")
            try check(ChineseDisplayText.simplified(expected) == expected, "Conversion is idempotent: \(expected)")
        }
        let fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1"
        try check(fen.simplifiedForDisplay == fen, "ASCII FEN is not rewritten")
        try check(ChineseDisplayText.searchKey("飛相對進７卒") == ChineseDisplayText.searchKey("飞相对进7卒"),
                  "Search normalizes script and full-width digits")
        try check(ChineseDisplayText.searchKey("PÍKAFISH") == ChineseDisplayText.searchKey("pikafish"),
                  "Search normalizes Latin case and accents")
        try check(ChineseDisplayText.searchKey("\u{1100}\u{1161}") == ChineseDisplayText.searchKey("\u{AC00}"),
                  "Literal search keys preserve Unicode canonical equivalence")
        try check(ChineseDisplayText.searchTerms("  飛相\n對進７卒\t") == ["飞相", "对进7卒"],
                  "Multiple terms use whitespace and the same normalization")
        try check(ChineseDisplayText.searchTerms(String(repeating: "馬", count: 600)).first?.count == 512,
                  "Query normalization keeps the existing length limit")
        try check(ChineseDisplayText.matches(normalizedText: "飞相对进7卒", terms: ["飞相", "7卒"]),
                  "All query terms can match separately")
        try check(!ChineseDisplayText.matches(normalizedText: "飞相对进7卒", terms: ["飞相", "中炮"]),
                  "All query terms must match")

        let originalTitle = "飛相對進７卒"
        let path = "Chess Patterns/單車定式.json"
        let member = LibraryCourseMembership(groupID: path, title: originalTitle, sourceIndex: 3,
                                             category: "單車殘局", section: .patterns)
        let identifier = LibraryCourseEntry.identifier(fen: fen)
        let traditional = LibraryCourseEntry(id: identifier, fen: fen, title: originalTitle, memberships: [member])
        let alternate = LibraryCourseEntry(id: "second", fen: fen + " ", title: "顺炮对屏风马",
            memberships: [.init(groupID: "opening-repertoire.json", title: "顺炮对屏风马", sourceIndex: 1,
                                 category: "布局", section: .opening)])
        let group = LibraryCourseGroup(id: path, title: "單車定式", section: .patterns,
                                       entryIDs: [identifier], rawCount: 1, invalidCount: 0)
        let catalog = LibraryCourseCatalog(pwaCommit: String(repeating: "a", count: 40), entries: [traditional, alternate], groups: [group])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let originalBytes = try encoder.encode(catalog)
        try check(traditional.displayTitle == "飞相对进７卒" && member.displayTitle == "飞相对进７卒"
                  && member.displayCategory == "单车残局" && group.displayTitle == "单车定式", "Display adapters cover source labels")
        for query in ["飞相", "飛相", "飛相 7卒", "飞相 ７卒", "单车 残局", "單車 殘局", "Chess Patterns/单车"] {
            try check(catalog.entries(query: query).map(\.id) == [identifier], "Search original or simplified aliases: \(query)")
        }
        for query in ["顺炮", "順炮", "屏風馬", "屏风马"] {
            try check(catalog.entries(query: query).map(\.id) == ["second"], "Traditional query finds a simplified source: \(query)")
        }
        try check(catalog.entries(in: path, query: "单车 飞相").map(\.id) == [identifier], "Group filtering uses the normalized index")
        try check(catalog.entries(section: .opening, query: "飛相").isEmpty, "Script normalization cannot bypass section filters")
        try check(catalog.entries(query: "").map(\.id) == [identifier, "second"], "Blank query preserves canonical source order")
        try check(catalog.entries(query: "a0a1").isEmpty, "Unmatched ASCII query stays unmatched")
        try check(catalog.entries(in: "missing", query: "飞相").isEmpty, "Missing group never falls back to unrelated data")
        try check(traditional.title == originalTitle && member.title == originalTitle && member.category == "單車殘局",
                  "Presentation does not mutate source metadata")
        try check(traditional.id == identifier && traditional.lessonID == "library-" + identifier && traditional.fen == fen,
                  "Presentation does not change IDs, lesson identity or FEN")
        try check(member.groupID == path && member.sourceURL(commit: catalog.pwaCommit)?.lastPathComponent == "單車定式.json",
                  "Source URLs continue to refer to the original upstream path")
        try check(try encoder.encode(catalog) == originalBytes, "Display and search are not written into persisted source data")
        let decoded = try JSONDecoder().decode(LibraryCourseCatalog.self, from: originalBytes)
        try check(decoded == catalog && decoded.entries(query: "飛相 7卒").map(\.id) == [identifier],
                  "Decode rebuilds a working search index without a schema migration")
        let serialized = String(decoding: originalBytes, as: UTF8.self)
        try check(!serialized.contains("normalizedSearch") && !serialized.contains("displayTitle"),
                  "Derived display and index fields are never encoded")

        let countCache = ChineseDisplayTextCache(maximumEntries: 3, maximumUTF8Bytes: 200)
        for index in 0..<50 { _ = countCache.simplified("馬\(index)") }
        try check(countCache.metrics.count == 3 && countCache.metrics.utf8Bytes <= 200,
                  "Cache count is strictly bounded after many distinct titles")
        for _ in 0..<10 { try check(countCache.simplified("馬49") == "马49", "Warm cache returns the same conversion") }
        let byteCache = ChineseDisplayTextCache(maximumEntries: 20, maximumUTF8Bytes: 20)
        for index in 0..<50 { _ = byteCache.simplified("馬\(index)") }
        try check(byteCache.metrics.count <= 2 && byteCache.metrics.utf8Bytes <= 20,
                  "Cache byte budget evicts even before the entry limit")
        let oversized = String(repeating: "馬", count: 20)
        let beforeOversized = byteCache.metrics
        try check(byteCache.simplified(oversized) == String(repeating: "马", count: 20), "Oversized input still displays correctly")
        try check(byteCache.metrics == beforeOversized, "Oversized labels never displace the visible-label cache")
        let cappedInputCache = ChineseDisplayTextCache(maximumEntries: 10, maximumUTF8Bytes: 100, maximumCachedInputBytes: 5)
        _ = cappedInputCache.simplified("雙馬")
        try check(cappedInputCache.metrics.count == 0, "Input-size cap is enforced separately from total storage")
        let asciiCache = ChineseDisplayTextCache()
        for _ in 0..<20 { _ = asciiCache.simplified(fen) }
        try check(asciiCache.metrics.count == 0 && asciiCache.metrics.utf8Bytes == 0, "ASCII-only text bypasses the conversion cache")
        let disabledCache = ChineseDisplayTextCache(maximumEntries: 0, maximumUTF8Bytes: 0)
        try check(disabledCache.simplified("飛相") == "飞相" && disabledCache.metrics.count == 0, "Zero byte budget safely disables retention")
        let clampedCache = ChineseDisplayTextCache(maximumEntries: Int.max, maximumUTF8Bytes: Int.max, maximumCachedInputBytes: Int.max)
        try check(clampedCache.metrics.maximumEntries == 4_096 && clampedCache.metrics.maximumUTF8Bytes == 2_097_152,
                  "Constructor cannot accidentally create an unbounded cache")
        let concurrentCache = ChineseDisplayTextCache(maximumEntries: 8, maximumUTF8Bytes: 128)
        DispatchQueue.concurrentPerform(iterations: 300) { index in
            _ = concurrentCache.simplified("飛相對馬\(index % 12)")
        }
        try check(concurrentCache.metrics.count <= 8 && concurrentCache.metrics.utf8Bytes <= 128,
                  "Concurrent rendering requests preserve both cache limits")
        try check(concurrentCache.simplified("飛相對馬") == "飞相对马", "Concurrent eviction leaves the cache usable")
        print("PASS \(checks) simplified display/search/cache checks")
    }
}
#endif
