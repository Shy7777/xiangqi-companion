import Foundation

struct PWASourceFile: Codable, Sendable {
    let path: String
    let total: Int
    let invalid: Int
    let issues: [String]
    let positions: [PWARawPosition]
}

/// Repository annotations are source metadata, not verified move answers.
struct PWARawPosition: Codable, Sendable, Equatable {
    let fen: String
    let index: Int
    let title: String
    let category: String
    let result: String?
    let bestMove: String?
}

struct PWAWebResource: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let url: String
    let sourceLine: Int
}

enum PWADataError: Error, LocalizedError {
    case invalidPath
    case tooLarge
    case tooManyItems
    case unknownStructure
    case resourceScopeChanged
    case noResources

    var errorDescription: String? {
        switch self {
        case .invalidPath: return "题库路径不受支持"
        case .tooLarge: return "单个题库文件超过 8 MiB 上限"
        case .tooManyItems: return "单个题库文件超过 20,000 条上限"
        case .unknownStructure: return "题库必须是条目数组或包含 fen 的单个对象"
        case .resourceScopeChanged: return "资源说明函数的源码范围已变化，无法安全提取链接"
        case .noResources: return "资源说明函数中没有可用的 HTTP/HTTPS 链接"
        }
    }
}

enum PWADataParser {
    static let maximumBytes = 8 * 1_024 * 1_024
    static let maximumItems = 20_000

    static func isDataPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              let file = parts.last, file.hasSuffix(".json"), file.count > 5 else { return false }
        if parts.count == 1 { return file != "manifest.json" && file != "patterns_index.json" }
        return parts.count == 2 && parts[0] == "Chess Patterns"
    }

    static func category(for path: String) -> String {
        let known = [
            "advanced-checkmates.json": "进阶杀法",
            "basic-checkmates.json": "基础杀法",
            "endgames_all.json": "综合残局",
            "extremely-challenging-endgames.json": "极难残局",
            "jianghu-endgames.json": "江湖残局",
            "meng-ru-shen-ji.json": "梦入神机",
            "opening-repertoire.json": "开局定式",
            "shi-qing-ya-qu.json": "适情雅趣"
        ]
        if let name = known[path] { return name }
        let file = path.split(separator: "/").last.map(String.init) ?? path
        return label(file.hasSuffix(".json") ? String(file.dropLast(5)) : file)
    }

    static func parse(data: Data, path: String) throws -> PWASourceFile {
        guard isDataPath(path) else { throw PWADataError.invalidPath }
        guard data.count <= maximumBytes else { throw PWADataError.tooLarge }
        let payload = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        let object = try JSONSerialization.jsonObject(with: payload)
        let entries: [Any]
        if let array = object as? [Any] {
            entries = array
        } else if let single = object as? [String: Any], single["fen"] is String {
            entries = [single]
        } else {
            throw PWADataError.unknownStructure
        }
        guard entries.count <= maximumItems else { throw PWADataError.tooManyItems }

        var positions: [PWARawPosition] = []
        var invalid = 0
        var issues: [String] = []
        let category = category(for: path)
        func reject(_ index: Int, _ message: String) {
            invalid += 1
            if issues.count < 12 { issues.append("第 \(index) 条：\(String(message.prefix(256)))") }
        }
        for (offset, entry) in entries.enumerated() {
            let index = offset + 1
            guard let item = entry as? [String: Any], let fen = item["fen"] as? String, !fen.isEmpty else {
                reject(index, "缺少字符串 fen")
                continue
            }
            guard fen.utf8.count <= 512 else {
                reject(index, "FEN 过长")
                continue
            }
            do {
                let position = try Position(fen: fen)
                let classification = item["classification"] as? [String: Any]
                let candidates = [item["title"], item["name"], item["typeFull"], item["type"],
                                  classification?["typeFull"], classification?["type"]]
                let name = candidates.compactMap { $0 as? String }.map(label).first { !$0.isEmpty }
                let sourceBest = annotation(item["bestMove"])
                let bestMove = sourceBest.flatMap {
                    $0.contains("需要查询") || $0.contains("需要查詢") ? nil : $0
                }
                positions.append(PWARawPosition(
                    fen: position.fen, index: index, title: name ?? label("\(category) · 第 \(index) 题"),
                    category: category, result: annotation(item["result"]), bestMove: bestMove
                ))
            } catch {
                reject(index, error.localizedDescription)
            }
        }
        return PWASourceFile(path: path, total: entries.count, invalid: invalid, issues: issues, positions: positions)
    }

    /// Reads source text only. No HTML, JavaScript, or linked page is executed or fetched.
    static func parseResources(html: String) throws -> [PWAWebResource] {
        guard html.utf8.count <= maximumBytes else { throw PWADataError.resourceScopeChanged }
        let source = html as NSString
        let declaration = try NSRegularExpression(pattern: #"(?m)^[\t ]*function[\t ]+showGameInstructionsDialog[\t ]*\([\t ]*\)[\t ]*\{"#)
        let declarations = declaration.matches(in: html, range: NSRange(location: 0, length: source.length))
        guard declarations.count == 1, let match = declarations.first else { throw PWADataError.resourceScopeChanged }
        let opening = NSMaxRange(match.range) - 1
        let units = Array(html.utf16)
        var commentRanges: [NSRange] = []
        var cursor = opening
        let bound = min(units.count, opening + 512 * 1_024)

        func quoted(_ quote: UInt16, _ index: inout Int) throws {
            index += 1
            while index < bound {
                if units[index] == 92 { index += 2; continue }
                if units[index] == quote { index += 1; return }
                if units[index] == 10 || units[index] == 13 { throw PWADataError.resourceScopeChanged }
                index += 1
            }
            throw PWADataError.resourceScopeChanged
        }
        func template(_ index: inout Int, depth: Int) throws {
            index += 1
            while index < bound {
                if units[index] == 92 { index += 2; continue }
                if units[index] == 96 { index += 1; return }
                if units[index] == 36, index + 1 < bound, units[index + 1] == 123 {
                    index += 1
                    try block(&index, depth: depth + 1)
                    continue
                }
                index += 1
            }
            throw PWADataError.resourceScopeChanged
        }
        func block(_ index: inout Int, depth: Int) throws {
            guard depth <= 128, index < bound, units[index] == 123 else { throw PWADataError.resourceScopeChanged }
            index += 1
            while index < bound {
                switch units[index] {
                case 39, 34: try quoted(units[index], &index)
                case 96: try template(&index, depth: depth)
                case 123: try block(&index, depth: depth + 1)
                case 125: index += 1; return
                case 47:
                    let start = index
                    guard index + 1 < bound else { throw PWADataError.resourceScopeChanged }
                    if units[index + 1] == 47 {
                        index += 2
                        while index < bound, units[index] != 10, units[index] != 13 { index += 1 }
                    } else if units[index + 1] == 42 {
                        index += 2
                        while index + 1 < bound, !(units[index] == 42 && units[index + 1] == 47) { index += 1 }
                        guard index + 1 < bound else { throw PWADataError.resourceScopeChanged }
                        index += 2
                    } else {
                        // This source function has no regex/division expressions. Fail closed on a changed grammar.
                        throw PWADataError.resourceScopeChanged
                    }
                    commentRanges.append(NSRange(location: start, length: index - start))
                default: index += 1
                }
            }
            throw PWADataError.resourceScopeChanged
        }
        try block(&cursor, depth: 0)
        let closing = cursor - 1
        let suffix = source.substring(from: cursor)
        let successor = try NSRegularExpression(pattern: #"\A(?:\s|//[^\r\n]*(?:\r?\n|$)|/\*[\s\S]*?\*/)*function\s+closeGameInstructionsDialog\s*\("#)
        guard successor.firstMatch(in: suffix, range: NSRange(location: 0, length: (suffix as NSString).length)) != nil else {
            throw PWADataError.resourceScopeChanged
        }
        let bodyRange = NSRange(location: opening + 1, length: closing - opening - 1)
        var bodyUnits = Array(units[(opening + 1)..<closing])
        func mask(_ range: NSRange) {
            for i in range.location..<NSMaxRange(range) where bodyUnits.indices.contains(i) {
                if bodyUnits[i] != 10 && bodyUnits[i] != 13 { bodyUnits[i] = 32 }
            }
        }
        for range in commentRanges { mask(NSRange(location: range.location - bodyRange.location, length: range.length)) }
        let body = String(decoding: bodyUnits, as: UTF16.self)
        let htmlComments = try NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#)
        for range in htmlComments.matches(in: body, range: NSRange(location: 0, length: bodyUnits.count)).map(\.range) { mask(range) }
        let safeBody = String(decoding: bodyUnits, as: UTF16.self)
        let safeSource = safeBody as NSString
        let anchors = try NSRegularExpression(pattern: #"<a\b((?:[^\"'<>]|\"[^\"]*\"|'[^']*')*)>([\s\S]*?)</a\s*>"#, options: [.caseInsensitive])
        let href = try NSRegularExpression(pattern: #"(?:^|\s)href\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+))"#, options: [.caseInsensitive])
        let tags = try NSRegularExpression(pattern: #"<(?:[^\"'<>]|\"[^\"]*\"|'[^']*')*>"#)
        var resources: [PWAWebResource] = []
        var seen = Set<String>()
        for anchor in anchors.matches(in: safeBody, range: NSRange(location: 0, length: safeSource.length)) {
            let attributes = safeSource.substring(with: anchor.range(at: 1))
            let attributesSource = attributes as NSString
            guard let attribute = href.firstMatch(in: attributes, range: NSRange(location: 0, length: attributesSource.length)),
                  let valueRange = (1...3).map({ attribute.range(at: $0) }).first(where: { $0.location != NSNotFound }) else { continue }
            let address = decodeEntities(attributesSource.substring(with: valueRange)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard address.utf8.count <= 8_192, !address.contains("\\"),
                  !address.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
                  let components = URLComponents(string: address),
                  let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
                  let host = components.host, !host.isEmpty, !host.contains("@"),
                  components.user == nil, components.password == nil, components.url != nil,
                  seen.insert(address).inserted else { continue }
            let rawTitle = safeSource.substring(with: anchor.range(at: 2))
            let plain = tags.stringByReplacingMatches(in: rawTitle, range: NSRange(location: 0, length: (rawTitle as NSString).length), withTemplate: "")
            let title = label(decodeEntities(plain).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
            let line = units[..<(bodyRange.location + anchor.range.location)].reduce(1) { $1 == 10 ? $0 + 1 : $0 }
            resources.append(PWAWebResource(id: address, title: title.isEmpty ? label(host) : title, url: address, sourceLine: line))
        }
        guard !resources.isEmpty else { throw PWADataError.noResources }
        return resources
    }

    private static func decodeEntities(_ value: String) -> String {
        let named = ["amp": "&", "AMP": "&", "lt": "<", "LT": "<", "gt": ">", "GT": ">", "quot": "\"", "QUOT": "\"", "apos": "'",
                     "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ", "ndash": "–", "mdash": "—", "hellip": "…", "middot": "·", "bull": "•",
                     "copy": "©", "reg": "®", "trade": "™", "colon": ":", "sol": "/", "bsol": "\\", "Tab": "\t", "NewLine": "\n"]
        let regex = try! NSRegularExpression(pattern: #"&(#(?:[xX][0-9A-Fa-f]+|[0-9]+)|[A-Za-z][A-Za-z0-9]+);"#)
        let result = NSMutableString(string: value)
        for match in regex.matches(in: value, range: NSRange(location: 0, length: (value as NSString).length)).reversed() {
            let key = (value as NSString).substring(with: match.range(at: 1))
            var replacement = named[key]
            if key.hasPrefix("#") {
                let hex = key.hasPrefix("#x") || key.hasPrefix("#X")
                if let number = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) { replacement = String(scalar) }
            }
            if let replacement { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }

    private static func label(_ value: String) -> String {
        let clean = value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        return String(clean.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
    }

    private static func annotation(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return clean.isEmpty ? nil : String(clean.prefix(2_000))
    }
}
