#if AWESOME_RESOURCE_INDEX_TESTS
import Foundation

@main struct AwesomeResourceIndexTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func rejects(_ message: String, _ body: () throws -> Void) {
            do { try body(); preconditionFailure(message) } catch { checks += 1 }
        }
        let commit = "8fff91f76b6569a191d8e7fc61295ae92d3bced2"
        let fetchedAt = Date(timeIntervalSince1970: 1_788_768_000)
        let fixturePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/Fixtures/awesome-xiangqi.md"
        let fixture = try String(contentsOfFile: fixturePath, encoding: .utf8)
        let index = try AwesomeResourceIndex.parse(markdown: fixture, commit: commit, fetchedAt: fetchedAt)
        check(index.items.count == 90, "Complete pinned README must produce all 90 actual body links, not a curated subset")
        check(index.version == 1 && index.commit == commit && index.fetchedAt == fetchedAt, "Index provenance changed")
        check(fixture.hasPrefix("<!-- Upstream") && fixture.contains("CC0-1.0"), "Fixture must retain source/license notice")
        let counts = Dictionary(grouping: index.items, by: \.category).mapValues(\.count)
        check(counts == ["General websites": 3, "Websites to play": 7, "Games databases": 3, "Books": 49,
                         "YouTube channels": 8, "Engines": 2, "Computer xiangqi": 6, "Other useful tools": 5, "Social": 7], "A full upstream category is missing")
        let books = index.items.filter { $0.category == "Books" }
        check(Dictionary(grouping: books, by: { $0.subcategory ?? "" }).mapValues(\.count)
              == ["Introductory books": 9, "Opening": 13, "Tactics / puzzles": 5, "Endgames": 5, "Ancient manuals": 15, "Games collections": 2],
              "Book subcategories, volume links or secondary reading links were lost")
        let lines = fixture.components(separatedBy: "\n")
        // Independent simple extraction of the pinned fixture (all of its body links use this
        // syntax), so a parser regression cannot silently redefine what 'all resources' means.
        let regex = try NSRegularExpression(pattern: #"\[[^\]]+\]\((https?://[^\s)]+)\)"#)
        var expected: [(line: Int, url: String)] = [], inBody = false
        for (offset, line) in lines.enumerated() {
            if line == "## General websites" { inBody = true }
            guard inBody else { continue }
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let range = Range(match.range(at: 1), in: line) { expected.append((offset + 1, String(line[range]))) }
            }
        }
        check(expected.count == 90, "Pinned fixture changed: independently audit its complete link set")
        check(index.items.map(\.url.absoluteString) == expected.map(\.url), "Parser did not retain every link in original reading order")
        check(index.items.map(\.sourceLine) == expected.map(\.line), "Source lines do not point to the exact supplied Markdown")
        for item in index.items {
            check(item.id.count == 64 && item.id.allSatisfy(\.isHexDigit), "Identity must be SHA-256, not Swift's randomized Hasher")
            check(item.categoryTitle != item.category, "Known main category needs a Chinese display title")
            check(item.matches(item.category) && item.matches(item.categoryTitle), "Chinese and original English search must both work")
            check(!item.context.contains("]("), "Plain text context must not expose Markdown link syntax")
        }
        check(Set(index.items.map(\.id)).count == 90, "Distinct upstream entries collided")
        check(books.allSatisfy { $0.subcategoryTitle != $0.subcategory }, "Known book subcategories need Chinese labels")
        check(index.items.filter { $0.title.contains("Understanding the elephant series · Part") }.count == 4, "Nested volumes lost their series identity")
        check(index.items.filter { $0.title.hasPrefix("Secret in the Tangerine · volume") }.count == 4, "Four volume links must be individually searchable")
        check(index.items.filter { $0.title.hasPrefix("Elegant pastime manual · volumes") }.count == 3, "All three multi-volume links must survive")
        check(index.items.contains { $0.url.lastPathComponent == "Deceptive_Play.pdf" && $0.context.contains("partial English translation") }, "WXF partial-translation secondary link disappeared")
        check(index.items.contains { $0.title.contains("Lexicon of xiangqi · here") && $0.url.host == "www.xqinenglish.com" }, "Free extract must remain separate from commercial book")
        check(index.items.contains { $0.title.contains("Live demo") && $0.url.host == "android-xiangqi-offline.netlify.app" }, "PWA secondary live-demo link disappeared")
        check(index.items.contains { $0.url.absoluteString == "http://www.01xq.z/" }, "Index parsing must not silently rewrite or hide an unverified upstream HTTP URL")
        check(index.items.contains { $0.url.host == "sci-hub.se" }, "A full source index is not the curated reviewed subset; inclusion is not an endorsement")
        check(!index.items.contains { ["awesome.re", "upload.wikimedia.org", "en.wikipedia.org"].contains($0.url.host ?? "") }, "Badge, decoration or introductory header was counted as a resource")
        check(index.items.filter { $0.category == "Books" && $0.subcategory == "Opening" && $0.url.host == "www.youtube.com" }.count == 4, "All four opening secondary video playlists are required")
        check(AwesomeResourceIndex.attribution.contains("CC0") && AwesomeResourceIndex.attribution.contains("不延伸"), "Index reuse must not relicense linked books")

        let sample = """
        # Repository [Header](https://header.example)
        [Intro](https://intro.example)
        ## Contents
        - [TOC](#books) [external decoration](https://toc.example)
        ## Books
        ### Opening
        - **Parent series**
          - [Part 1](https://book.example/a_(b)?q=1&x=2) — **Complete** line with [here](https://video.example/list "Video title").
          - [Same URL different title](https://book.example/a_(b)?q=1&x=2)
          - [Fragment](https://book.example/a_(b)?q=1&x=2#chapter)
        - [Reference][read] and [short][] and [shortcut]
        - <http://plain.example/info>
        - [![Badge](https://badge.example/a.svg)](https://badge.example)
        - ![Image](https://image.example/a.png)
        - [Anchor](#opening) [Relative](book.md) [Mail](mailto:editor@example.com) [Script](javascript:alert(1)) [File](file:///tmp/book)
        - [Credentials](https://user:secret@example.com/book) [Protocol-relative](//example.com/book)
        - `[Inline fake](https://code.example)` [Real](https://real.example)
        <!-- [Comment](https://comment.example)
        ## Invisible
        [More comment](https://comment.example/2) -->
        ```md
        ## Hidden
        [Fenced fake](https://fenced.example)
        ```
        ### Endgames
        | [Second classification](https://book.example/a_(b)?q=1&x=2) | [Rules](<https://rules.example/guide>) |
        ## Engines
        - [Engine][engine]
        ## New resources
        - [Future item](https://future.example)
        ## License
        [Do not index](https://license.example)
        [read]: https://ref.example/book
        [short]: <https://ref.example/short> "Title"
        [shortcut]: https://ref.example/shortcut
        [engine]: https://engine.example
        """
        let parsed = try AwesomeResourceIndex.parse(markdown: sample, commit: commit, fetchedAt: fetchedAt)
        check(parsed.items.count == 12, "Markdown filtering, reference links or exact-context de-duplication failed")
        check(parsed.items.first?.title == "Parent series · Part 1", "Nested list parent title was lost")
        check(parsed.items.first?.context == "Parent series — Part 1 — Complete line with here.", "Keep the complete original line as concise plain text")
        check(parsed.items.contains { $0.url.absoluteString.contains("a_(b)?q=1&x=2#chapter") }, "Balanced URL parentheses, query or fragment changed")
        check(parsed.items.filter { $0.url.absoluteString == "https://book.example/a_(b)?q=1&x=2" }.count == 2, "Keep cross-subcategory entries but deduplicate identical context")
        check(parsed.items.contains { $0.title == "Reference" && $0.url.host == "ref.example" }, "Named reference link failed")
        check(parsed.items.contains { $0.title == "short" } && parsed.items.contains { $0.title == "shortcut" }, "Collapsed or shortcut reference failed")
        check(parsed.items.last?.categoryTitle == "New resources", "New upstream categories must remain available without an app update")
        check(parsed.items.contains { $0.category == "Engines" && $0.subcategory == nil }, "A new main category must reset the old book subcategory")
        check(!parsed.items.contains { ["badge.example", "image.example", "code.example", "comment.example", "fenced.example", "license.example"].contains($0.url.host ?? "") }, "Non-resource markup entered the index")
        let reordered = try AwesomeResourceIndex.parse(markdown: "\n\n" + sample.replacingOccurrences(of: "Part 1", with: "Renamed volume"), commit: String(repeating: "a", count: 40), fetchedAt: .distantPast)
        check(reordered.items.map(\.id) == parsed.items.map(\.id), "Identity must survive title, line-number, date and commit updates")
        check(reordered.items.first?.sourceLine == (parsed.items.first?.sourceLine ?? 0) + 2, "Line offsets must still be accurate after comments/newlines")
        let crlf = try AwesomeResourceIndex.parse(markdown: sample.replacingOccurrences(of: "\n", with: "\r\n"), commit: commit.uppercased(), fetchedAt: fetchedAt)
        check(crlf == parsed, "CRLF normalization or uppercase commit normalization failed")
        let encoded = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(AwesomeResourceIndex.self, from: encoded)
        check(decoded == index, "Offline cache Codable round-trip lost index content or provenance")
        func decodeMutating(_ key: String, value: Any) throws {
            var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            json[key] = value
            _ = try JSONDecoder().decode(AwesomeResourceIndex.self, from: JSONSerialization.data(withJSONObject: json))
        }
        rejects("Cache must reject a future format version") { try decodeMutating("version", value: 2) }
        rejects("Cache must reject invalid source provenance") { try decodeMutating("commit", value: "main") }
        rejects("Cache must reject duplicate identities") {
            var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            var entries = json["items"] as! [[String: Any]]; entries.append(entries[0]); json["items"] = entries
            _ = try JSONDecoder().decode(AwesomeResourceIndex.self, from: JSONSerialization.data(withJSONObject: json))
        }
        rejects("Cache must not bypass URL validation") {
            var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            var entries = json["items"] as! [[String: Any]]; entries[0]["url"] = "file:///tmp/unsafe"; json["items"] = entries
            _ = try JSONDecoder().decode(AwesomeResourceIndex.self, from: JSONSerialization.data(withJSONObject: json))
        }
        for unsafe in ["file:///tmp/a", "javascript:alert(1)", "data:text/html,test", "//example.com", "https:///", "https://a b.example", "https://user:pass@example.com", "https://example.com/\nfile"] {
            check(AwesomeResourceIndex.permittedURL(unsafe) == nil, "Unsafe URL accepted: \(unsafe)")
        }
        check(AwesomeResourceIndex.permittedURL("https://example.com?a=1&amp;b=2")?.query == "a=1&b=2", "HTML-escaped URL query should retain both parameters")
        check(AwesomeResourceIndex.permittedURL("http://example.com")?.scheme == "http", "Valid HTTP entries must not be silently dropped")
        check(index.items[0].matches(" \n ") && !index.items[0].matches("不存在的关键词"), "Empty or unmatched search is incorrect")
        rejects("Empty README should not erase a cached index") { _ = try AwesomeResourceIndex.parse(markdown: "", commit: commit, fetchedAt: fetchedAt) }
        rejects("HTML error body is not a resource index") { _ = try AwesomeResourceIndex.parse(markdown: "<html>404 <a href='https://example.com'>fail</a></html>", commit: commit, fetchedAt: fetchedAt) }
        rejects("Branch name is not immutable provenance") { _ = try AwesomeResourceIndex.parse(markdown: sample, commit: "main", fetchedAt: fetchedAt) }
        rejects("Invalid date must not be cached") { _ = try AwesomeResourceIndex.parse(markdown: sample, commit: commit, fetchedAt: Date(timeIntervalSince1970: .infinity)) }
        rejects("Oversized text must fail before parsing") { _ = try AwesomeResourceIndex.parse(markdown: String(repeating: "a", count: AwesomeResourceIndex.maximumMarkdownBytes + 1), commit: commit, fetchedAt: fetchedAt) }
        rejects("Oversized line must fail before expensive parsing") { _ = try AwesomeResourceIndex.parse(markdown: "## Books\n" + String(repeating: "[", count: 65_537), commit: commit, fetchedAt: fetchedAt) }
        rejects("Control bytes must not enter ID fields") { _ = try AwesomeResourceIndex.parse(markdown: sample + "\0", commit: commit, fetchedAt: fetchedAt) }
        let tooMany = "## Books\n" + (0...AwesomeResourceIndex.maximumItems).map { "- [Item \($0)](https://example.com/\($0))" }.joined(separator: "\n")
        rejects("Too many entries must not partially publish") { _ = try AwesomeResourceIndex.parse(markdown: tooMany, commit: commit, fetchedAt: fetchedAt) }
        print("PASS \(checks) awesome full-index / secondary links / stable IDs / safety / cache checks; 90 resource links, 9 categories, 6 book subcategories; no network or state writes")
    }
}
#endif
