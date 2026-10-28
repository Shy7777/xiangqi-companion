#if LIBRARY_COURSE_CATALOG_TESTS
import Foundation

@main struct LibraryCourseCatalogTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try value() else { throw Failure(description: message) }; checks += 1
        }
        func rejects(_ snapshot: GitHubLibrarySnapshot, _ message: String) throws {
            do { _ = try LibraryCourseCatalogAdapter.build(snapshot); throw Failure(description: message) }
            catch is LibraryCourseCatalogError { checks += 1 }
        }
        let commit = String(repeating: "a", count: 40)
        let awesome = try AwesomeResourceIndex.parse(markdown: "# Index\n## Books\n- [Book](https://example.test/book)", commit: commit, fetchedAt: Date(timeIntervalSince1970: 0))
        let first = Position.initial.fen
        let second = try Position.initial.applying(move: Move(uci: "a3a4")!).fen
        let third = try Position.initial.applying(move: Move(uci: "c3c4")!).fen
        func report(_ path: String, _ total: Int, _ invalid: Int = 0) -> SyncedFileReport {
            SyncedFileReport(file: GitHubDataFile(path: path, sha: String(repeating: "b", count: 40), size: 20), total: total, invalid: invalid, issues: [])
        }
        func origin(_ path: String, _ index: Int, _ title: String, _ fen: String) -> SyncedPositionOrigin {
            SyncedPositionOrigin(file: path, item: PWARawPosition(fen: fen, index: index, title: title,
                category: PWADataParser.category(for: path), result: nil, bestMove: nil))
        }
        func position(_ fen: String, _ origins: [SyncedPositionOrigin]) -> SyncedPosition {
            SyncedPosition(id: LibraryCourseEntry.identifier(fen: fen), fen: fen, origins: origins)
        }
        func snapshot(_ files: [SyncedFileReport], _ positions: [SyncedPosition], version: String? = nil) -> GitHubLibrarySnapshot {
            GitHubLibrarySnapshot(awesome: awesome, pwaCommit: version ?? commit,
                pwaIndexFile: GitHubDataFile(path: "index.html", sha: String(repeating: "c", count: 40), size: 1),
                pwaResources: [.init(id: "https://example.test", title: "Fixture", url: "https://example.test", sourceLine: 1)],
                syncedAt: Date(timeIntervalSince1970: 0), files: files, positions: positions, downloadedBytes: 0, reusedFiles: 0)
        }
        let opening = "opening-repertoire.json", basic = "basic-checkmates.json", pattern = "Chess Patterns/單車定式.json", future = "future-course.json"
        let files = [report(pattern, 0), report("shi-qing-ya-qu.json", 1, 1), report(future, 1), report(basic, 1), report(opening, 3)]
        let entries = [
            position(second, [origin(opening, 3, "飛相對中炮－另一来源", second), origin(basic, 1, "同一局面杀法", second)]),
            position(third, [origin(future, 1, "未知新题", third)]),
            position(first, [origin(opening, 1, "列炮對屏風馬", first)]),
            position(second, [origin(opening, 2, "飛相對中炮", second)])
        ]
        let value = try LibraryCourseCatalogAdapter.build(snapshot: snapshot(files, entries))
        try check(LibraryCourseSection.allCases.map(\.order) == Array(0...5), "Section ordering is explicit and stable")
        try check(LibraryCourseSection.allCases.map(\.title).allSatisfy { !$0.isEmpty }, "Every section has a Chinese title")
        for path in ["opening-repertoire.json"] { try check(LibraryCourseSection.section(for: path) == .opening, "Opening classification") }
        for path in ["basic-checkmates.json", "advanced-checkmates.json"] { try check(LibraryCourseSection.section(for: path) == .checkmates, "Checkmate classification") }
        for path in ["endgames_all.json", "extremely-challenging-endgames.json", "jianghu-endgames.json"] { try check(LibraryCourseSection.section(for: path) == .endgames, "Endgame classification") }
        for path in ["meng-ru-shen-ji.json", "shi-qing-ya-qu.json"] { try check(LibraryCourseSection.section(for: path) == .classics, "Classic classification") }
        try check(LibraryCourseSection.section(for: pattern) == .patterns && LibraryCourseSection.section(for: future) == .other, "Unknown source files are kept in other, not discarded")
        try check(value.totalCount == 3 && value.entries.count == Set(value.entries.map(\.fen)).count, "Canonical FEN entries are unique across repeated source positions")
        try check(value.groups.count == 5 && value.group(id: pattern)?.entryIDs.isEmpty == true,
                  "Empty source files still have a group")
        try check(value.group(id: "shi-qing-ya-qu.json")?.rawCount == 1 && value.group(id: "shi-qing-ya-qu.json")?.invalidCount == 1,
                  "All-invalid source files remain visible with honest counts")
        try check(value.group(id: opening)?.entryIDs == [LibraryCourseEntry.identifier(fen: first), LibraryCourseEntry.identifier(fen: second)],
                  "Group order follows original source index and removes only duplicate FEN IDs")
        let shared = value.entry(id: LibraryCourseEntry.identifier(fen: second))!
        try check(shared.memberships.count == 3 && shared.primaryMembership?.sourceIndex == 2,
                  "All aliases remain; primary membership is deterministic by section/file/source index")
        try check(shared.membership(in: basic)?.title == "同一局面杀法" && shared.membership(in: nil) == shared.primaryMembership,
                  "UI can show the selected group's real title rather than an unrelated alias")
        try check(shared.lessonID == "library-" + shared.id && shared.id.count == 64, "Lesson identity excludes mutable titles, order and commit")
        try check(shared.openingFamily == "顺相／列相／飞相" && shared.openingTitleStem == "飛相" && value.entry(id: LibraryCourseEntry.identifier(fen: third))?.openingFamily == nil,
                  "Opening navigation uses source-backed broad families while retaining the fine-grained original prefix")
        let simplified = LibraryCourseEntry(id: "x", fen: first, title: "中炮对屏风马", memberships: [.init(groupID: opening, title: "中炮对屏风马", sourceIndex: 1, category: "布局", section: .opening)])
        try check(simplified.openingFamily == "中炮及“五×炮”" && simplified.openingTitleStem == "中炮", "Both source-script variants work without altering the original title")
        let familyFixtures: [(String, String)] = [
            ("順相局", "顺相／列相／飞相"), ("列相局", "顺相／列相／飞相"), ("飞相对中炮", "顺相／列相／飞相"),
            ("起馬對進７卒", "起马"), ("仕角炮轉反宮馬對右中炮", "仕角炮"), ("過宮炮直車對左中炮", "过宫炮"),
            ("中炮過河車對屏風馬", "中炮及“五×炮”"), ("五七炮對反宮馬", "中炮及“五×炮”"),
            ("五九炮對屏風馬", "中炮及“五×炮”"), ("五八炮對屏風馬", "中炮及“五×炮”"),
            ("五六炮對屏風馬", "中炮及“五×炮”"), ("五炮左邊馬對屏風馬", "中炮及“五×炮”"),
            ("順炮直車對緩開", "顺炮"), ("仙人指路轉左中炮卒底砲", "仙人指路"),
            ("兩頭蛇對進右馬", "两头蛇"), ("對兵轉兵底炮", "对兵"),
            ("上仕局-冷門開局", "原标冷门"), ("中炮-冷門開局", "原标冷门"),
            ("寶炮車-極冷門開局", "原标极冷门"), ("起马-极冷门开局", "原标极冷门"),
            ("创新防线對未知", "创新防线"), ("對角新名称", "對角新名称"), ("五卒對中炮", "五卒"), ("五卒對炮局", "五卒")
        ]
        for (title, expected) in familyFixtures {
            let entry = LibraryCourseEntry(id: "fixture", fen: first, title: title,
                memberships: [.init(groupID: opening, title: title, sourceIndex: 1, category: "布局", section: .opening)])
            try check(entry.openingFamily == expected && entry.title == title && entry.memberships[0].title == title,
                      "Family grouping must preserve literal names and unknown future prefixes: \(title)")
        }
        try check(value.entries(in: opening).map(\.id) == value.group(id: opening)?.entryIDs, "Group lookup preserves source order")
        try check(value.entries(section: .opening).count == 2 && value.entries(section: .checkmates).count == 1,
                  "Cross-section FENs remain reachable from each source section")
        try check(value.entries(in: opening, section: .checkmates).isEmpty && value.entries(in: "missing").isEmpty,
                  "Contradictory or missing group filters never fall back to unrelated entries")
        try check(value.entries(query: "飛相 中炮").map(\.id) == [shared.id] && value.entries(query: "同一局面").map(\.id) == [shared.id],
                  "Search covers all source aliases and combines multiple terms")
        try check(value.entries(section: .other, query: "未知").count == 1 && value.entries().count == 3, "Unknown root data and default all-data queries are complete")
        try check(value.entry(id: "missing") == nil && value.group(id: "missing") == nil && LibraryCourseCatalog.empty.entries().isEmpty,
                  "Empty and missing selections are safe")
        try check(shared.sourceURL(commit: commit)?.host == "github.com" && shared.sourceURL(commit: commit)?.path.contains("/blob/\(commit)/opening-repertoire.json") == true,
                  "Source links are pinned to the requested upstream commit")
        let patternMember = LibraryCourseMembership(groupID: pattern, title: "定式", sourceIndex: 1, category: "定式", section: .patterns)
        try check(patternMember.sourceURL(commit: commit)?.path.hasSuffix(pattern) == true, "Source links preserve slash-separated paths and Unicode")
        for bad in ["../secret.json", "/absolute.json", "Chess Patterns/../secret.json", "foo\\bar.json", "foo//bar.json", "foo\nbar.json"] {
            let member = LibraryCourseMembership(groupID: bad, title: "x", sourceIndex: 1, category: "x", section: .other)
            try check(member.sourceURL(commit: commit) == nil, "Unsafe source path must not become a source link")
        }
        try check(shared.sourceURL(commit: "main") == nil, "Source links never silently switch to mutable main")
        let bytes = try JSONEncoder().encode(value)
        let roundTrip = try JSONDecoder().decode(LibraryCourseCatalog.self, from: bytes)
        try check(roundTrip == value && roundTrip.entry(id: shared.id) == shared, "Codable round-trip rebuilds derived lookup indices")
        let reordered = try LibraryCourseCatalogAdapter.build(snapshot(Array(files.reversed()), Array(entries.reversed())))
        try check(reordered == value, "Unstable upstream completion order must not reorder courses or aliases")
        let newer = try LibraryCourseCatalogAdapter.build(snapshot(files, entries, version: String(repeating: "d", count: 40)))
        try check(newer.entries.map(\.lessonID) == value.entries.map(\.lessonID), "Upstream version changes preserve FEN-based lesson identities")
        try rejects(snapshot([report(opening, 1)], []), "Missing valid origins may not produce a partial successful catalog")
        try rejects(snapshot([report(opening, 0)], [position(first, [origin(opening, 1, "x", first)])]), "Origin cannot reference a zero-item file")
        try rejects(snapshot([report(opening, 1), report(opening, 1)], []), "Duplicate file IDs are rejected without dictionary traps")
        try rejects(snapshot([report(opening, Int.max)], []), "Untrusted counters are bounded before arithmetic")
        try rejects(snapshot([report(opening, 1)], [position(first, [origin(opening, 2, "x", first)])]), "Out-of-range source index is rejected")
        try rejects(snapshot([report(opening, 2)], [position(first, [origin(opening, 1, "x", first), origin(opening, 1, "x", first)])]), "Duplicate source indices are not hidden by FEN deduplication")
        let badIdentity = SyncedPosition(id: "not-a-sha", fen: first, origins: [origin(opening, 1, "x", first)])
        try rejects(snapshot([report(opening, 1)], [badIdentity]), "Wrong stable identity is rejected")
        try rejects(snapshot([report("../escape.json", 0)], []), "Adapter refuses unsafe source paths")

        // Explicit read-only audit of the already-synchronized formal snapshot.
        // No store.load(), network, writes, engine, or all-position validation.
        if let index = CommandLine.arguments.firstIndex(of: "--audit") {
            guard CommandLine.arguments.indices.contains(index + 1) else { throw Failure(description: "--audit requires the existing library.json path") }
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let data = try GitHubLibraryStore.readBounded(url, maximum: GitHubLibraryRemote.maximumArchiveBytes)
            let upstream = try JSONDecoder().decode(GitHubLibrarySnapshot.self, from: data)
            let started = Date()
            let catalog = try LibraryCourseCatalogAdapter.build(upstream)
            let duration = Date().timeIntervalSince(started)
            let reachable = Set(catalog.groups.flatMap(\.entryIDs))
            try check(catalog.groups.count == upstream.files.count && Set(catalog.groups.map(\.id)) == Set(upstream.files.map { $0.file.path }), "Formal audit omitted source files")
            try check(catalog.entries.count == upstream.positions.count && reachable == Set(catalog.entries.map(\.id)), "Formal audit left valid FENs unreachable")
            try check(catalog.entries.reduce(0, { $0 + $1.memberships.count }) == upstream.rawCount - upstream.invalidCount, "Formal audit lost source aliases")
            for group in catalog.groups {
                let actual = catalog.entries(in: group.id)
                try check(actual.map(\.id) == group.entryIDs && Set(actual.map(\.id)).count == actual.count, "Formal group not fully reachable: \(group.id)")
                let indices = actual.compactMap { $0.membership(in: group.id)?.sourceIndex }
                try check(indices == indices.sorted(), "Formal group source ordering changed: \(group.id)")
            }
            if upstream.pwaCommit == "3ff21f4502a03f30bb0df55db6f3814ceeb989f5" {
                try check(catalog.groups.count == 207 && catalog.entries.count == 10_280 && catalog.entries(in: opening).count == 264,
                          "Pinned upstream complete-library counts changed")
                let families = Dictionary(grouping: catalog.entries(in: opening), by: { $0.openingFamily ?? "missing" }).mapValues(\.count)
                let expected = ["顺相／列相／飞相": 26, "起马": 6, "仕角炮": 5, "过宫炮": 6, "中炮及“五×炮”": 137,
                                "顺炮": 22, "仙人指路": 34, "两头蛇": 2, "对兵": 9, "原标冷门": 13, "原标极冷门": 4]
                try check(families == expected && families.values.reduce(0, +) == 264,
                          "Pinned opening titles must form exactly the 11 audited source-backed groups")
                for family in families.keys.sorted() { print("OPENING_FAMILY \(family): \(families[family]!)") }
            }
            let unchanged = try GitHubLibraryStore.readBounded(url, maximum: GitHubLibraryRemote.maximumArchiveBytes)
            try check(unchanged == data, "Read-only audit must not modify the formal snapshot")
            print(String(format: "AUDIT groups=%d entries=%d reachable=%d memberships=%d opening=%d emptyGroups=%d buildSeconds=%.3f", catalog.groups.count, catalog.entries.count, reachable.count, catalog.entries.reduce(0, { $0 + $1.memberships.count }), catalog.entries(in: opening).count, catalog.groups.filter { $0.entryIDs.isEmpty }.count, duration))
            for section in LibraryCourseSection.allCases {
                print("SECTION \(section.rawValue): groups=\(catalog.groups.filter { $0.section == section }.count) distinctEntries=\(catalog.entries(section: section).count)")
            }
        }
        print("PASS: \(checks) library-course catalog checks; no engine, network, or user-data writes")
    }
}
#endif
