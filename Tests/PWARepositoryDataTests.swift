#if PWA_REPOSITORY_DATA_TESTS
import Foundation

@main
struct PWARepositoryDataTests {
    static func main() throws {
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
        }
        func encode(_ object: Any) throws -> Data {
            try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
        }
        func rejects(_ data: Data, path: String = "endgames_all.json") {
            do { _ = try PWADataParser.parse(data: data, path: path); preconditionFailure("Expected rejection: \(path)") }
            catch { }
        }
        let fen = Position.initialFEN
        let input: [[String: Any]] = [
            ["fen": fen, "name": "基础", "bestMove": " a0a1\0 \n", "result": "egtb:a0a1\0"],
            ["fen": fen, "typeFull": "炮兵 vs 单士", "classification": ["type": "分类"], "bestMove": "需要查詢"],
            ["fen": fen, "classification": ["typeFull": "分类全名"], "bestMove": "需要查询"],
            ["fen": "9/9/9/9/9/9/9/9/9/9 w - - 0 1"],
            ["title": "缺少 FEN"]
        ]
        let parsed = try PWADataParser.parse(data: Data([0xEF, 0xBB, 0xBF]) + encode(input), path: "endgames_all.json")
        check(parsed.total == 5 && parsed.invalid == 2 && parsed.positions.count == 3, "Mixed valid and invalid")
        check(parsed.positions.map(\.index) == [1, 2, 3], "Keep one-based source indexes")
        check(parsed.positions[0].bestMove == "a0a1" && parsed.positions[0].result == "egtb:a0a1", "Remove trailing NUL")
        check(parsed.positions[1].bestMove == nil && parsed.positions[2].bestMove == nil, "Placeholder is not an answer")
        check(parsed.positions[2].title == "分类全名", "Nested classification title")
        check(Set(parsed.positions.map(\.fen)).count == 1 && parsed.positions.count == 3, "Do not deduplicate origins")
        check(parsed.issues.count == 2, "Issue count")

        let alias = fen.replacingOccurrences(of: "n", with: "h").replacingOccurrences(of: "N", with: "H")
            .replacingOccurrences(of: "b", with: "e").replacingOccurrences(of: "B", with: "E")
            .replacingOccurrences(of: " w ", with: " r ").replacingOccurrences(of: "0 1", with: "8 20")
        let single = try PWADataParser.parse(data: encode(["fen": alias]), path: "Chess Patterns/测试.json")
        check(single.positions.first?.fen == fen, "Normalize piece aliases, side, and counters")
        check(single.positions.first?.category == "测试", "Pattern category")
        for path in ["/a.json", "../a.json", "Chess Patterns/../a.json", "a\\b.json", "Chess Patterns/x/y.json", "a\n.json", "manifest.json", "patterns_index.json", "Chess Patterns//a.json", ".json", "a.JSON"] {
            check(!PWADataParser.isDataPath(path), "Rejected path: \(path)")
            rejects(try encode([]), path: path)
        }
        check(PWADataParser.isDataPath("new-data.json"), "Future root libraries supported")
        rejects(Data("broken".utf8))
        rejects(try encode(["files": []]))
        rejects(try encode("not a library"))
        rejects(Data(repeating: 32, count: PWADataParser.maximumBytes + 1))
        rejects(try encode(Array(repeating: NSNull(), count: PWADataParser.maximumItems + 1)))
        let byteBoundary = Data("[]".utf8) + Data(repeating: 32, count: PWADataParser.maximumBytes - 2)
        let empty = try PWADataParser.parse(data: byteBoundary, path: "empty.json")
        check(empty.total == 0 && empty.invalid == 0, "Accept exactly 8 MiB and an empty library")
        let itemBoundary = try PWADataParser.parse(data: encode(Array(repeating: NSNull(), count: PWADataParser.maximumItems)), path: "boundary.json")
        check(itemBoundary.total == 20_000 && itemBoundary.invalid == 20_000 && itemBoundary.issues.count == 12, "Accept exactly 20,000 entries with bounded issues")
        let invalid = try PWADataParser.parse(data: encode(Array(repeating: ["fen": "bad"], count: 30)), path: "basic-checkmates.json")
        check(invalid.invalid == 30 && invalid.issues.count == 12, "Bound diagnostic samples")
        let long = String(repeating: "长", count: 3_000)
        let bounded = try PWADataParser.parse(data: encode([["fen": fen, "title": long, "result": long, "bestMove": long]]), path: "x.json").positions[0]
        check(bounded.title.count == 256 && bounded.result?.count == 2_000 && bounded.bestMove?.count == 2_000, "Bound annotations")
        let longCategory = try PWADataParser.parse(data: encode([["fen": fen, "bestMove": " \0 \n"]]), path: "Chess Patterns/\(long).json").positions[0]
        check(longCategory.title.count <= 256 && longCategory.category.count == 256 && longCategory.bestMove == nil, "Bound fallback titles and remove empty annotations")
        let roundtrip = try JSONDecoder().decode(PWASourceFile.self, from: JSONEncoder().encode(parsed))
        check(roundtrip.positions.count == 3, "Codable round trip")
        let resourceFixture = #"""
        <a href="https://outside-before.test/">Outside before</a>
        function showGameInstructionsDialog() {
            const braces = "}"; const other = '{';
            const nested = `literal { } ${(() => `nested ${ {a: "}"}.a }`)()}`;
            // <a href="https://comment.test/">Ignored code comment</a> }
            /* a closing brace } and opening { in a comment */
            const content = `
            <A title="contains >" HREF="https://example.test/?a=1&amp;b=2"><b>A &amp; B</b> &#x4E2D;&#25991; &quot;资源&quot;</A>
            <a href='https://example.test/?a=1&b=2'>Duplicate</a>
            <a href=http://plain.test/path>HTTP is retained</a>
            <a href="https&colon;&sol;&sol;entities.test/">实体网址</a>
            <a href="https://empty-title.test/"><img alt="not text"></a>
            <a data-href="https://not-href.test/">Not an href attribute</a>
            <!-- <a href="https://html-comment.test/">Ignored HTML comment</a> -->
            <a href="javascript:alert(1)">Bad</a><a href="&#106;avascript&colon;alert(1)">Bad</a>
            <a href="file:///tmp/local">Bad</a><a href="data:text/html,x">Bad</a>
            <a href="/relative">Bad</a><a href="//relative.test/">Bad</a>
            <a href="https://user:secret@credentials.test/">Bad</a>
            <a href="https://line.test/&#10;break">Bad</a>
            <a href="https://backslash.test/\path">Bad</a>
            `;
            if (true) { throw new Error('source is never executed'); }
        }
        // Exact next-function scope sentinel.
        function closeGameInstructionsDialog() {
            const outside = `<a href="https://outside-after.test/">Outside after</a>`;
        }
        """#
        let resources = try PWADataParser.parseResources(html: resourceFixture)
        check(resources.count == 4, "Resource filtering, comments, outside scope, and exact-URL deduplication")
        check(resources[0].url == "https://example.test/?a=1&b=2" && resources[0].title == "A & B 中文 \"资源\"", "Decode entities and strip tags")
        let firstLine = resourceFixture.components(separatedBy: "\n").firstIndex { $0.contains("<A title=") }! + 1
        check(resources[0].sourceLine == firstLine, "One-based original source line")
        check(resources[0].id == resources[0].url && resources[1].url.hasPrefix("http:"), "Stable URL identity and HTTP support")
        check(resources[3].title == "empty-title.test", "Blank title has readable host fallback")
        let resourceRoundtrip = try JSONDecoder().decode([PWAWebResource].self, from: JSONEncoder().encode(resources))
        check(resourceRoundtrip == resources, "Resource Codable round trip")
        func rejectsResources(_ source: String) {
            do { _ = try PWADataParser.parseResources(html: source); preconditionFailure("Expected resource rejection") }
            catch { }
        }
        rejectsResources("<a href=\"https://outside.test/\">No scoped function</a>")
        rejectsResources(resourceFixture + resourceFixture)
        rejectsResources(resourceFixture.replacingOccurrences(of: "closeGameInstructionsDialog()", with: "renamedSuccessor()"))
        rejectsResources("function showGameInstructionsDialog() { const x = `unterminated }")
        rejectsResources("function showGameInstructionsDialog() { const x = /}/; }\nfunction closeGameInstructionsDialog() {}")
        rejectsResources("function showGameInstructionsDialog() { const x = `no links`; }\nfunction closeGameInstructionsDialog() {}")
        rejectsResources("function showGameInstructionsDialog() { const x = `<a href='javascript:bad'>Bad</a>`; }\nfunction closeGameInstructionsDialog() {}")
        print("PWA parser unit tests passed")

        if let source = ProcessInfo.processInfo.environment["PWA_SOURCE_HTML"] {
            let resources = try PWADataParser.parseResources(html: String(contentsOfFile: source, encoding: .utf8))
            check(resources.count == 18, "Pinned real source contains 18 unique resource links")
            for resource in resources { print("RESOURCE line=\(resource.sourceLine) title=\(resource.title) url=\(resource.url)") }
            print("PWA full resource source: uniqueLinks=\(resources.count)")
        }

        if let root = ProcessInfo.processInfo.environment["PWA_SOURCE_DIR"] {
            let base = URL(fileURLWithPath: root, isDirectory: true)
            let enumerator = FileManager.default.enumerator(atPath: root)!
            var files = 0, total = 0, invalid = 0
            var unique = Set<String>()
            for case let path as String in enumerator {
                guard PWADataParser.isDataPath(path) else { continue }
                let url = base.appendingPathComponent(path)
                let parsed = try PWADataParser.parse(data: Data(contentsOf: url), path: path)
                files += 1; total += parsed.total; invalid += parsed.invalid
                unique.formUnion(parsed.positions.map(\.fen))
                print("SOURCE \(path) total=\(parsed.total) valid=\(parsed.positions.count) invalid=\(parsed.invalid)")
                if parsed.invalid > 0 { print("ISSUES \(path): \(parsed.issues.joined(separator: " | "))") }
            }
            check(files > 0, "Source directory must contain at least one data file")
            print("PWA full corpus: files=\(files) total=\(total) valid=\(total - invalid) invalid=\(invalid) uniqueValidatedFEN=\(unique.count)")
        }
    }
}
#endif
