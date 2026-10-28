import Foundation
import CryptoKit

struct SyncedResourceOrigin: Identifiable, Sendable {
    let repository: String
    let commit: String
    let path: String
    let line: Int
    let title: String
    let category: String
    let context: String
    var id: String { repository + ":" + path + ":" + String(line) }
    var sourceURL: URL? { URL(string: "https://github.com/\(repository)/blob/\(commit)/\(path)#L\(line)") }
}

struct SyncedWebResource: Identifiable, Sendable {
    let id: String
    let url: URL
    var origins: [SyncedResourceOrigin]
    var title: String { origins.first?.title ?? url.host ?? "资料" }
    var categories: [String] { Array(Set(origins.map(\.category))).sorted() }
    var categoryTitle: String { categories.joined(separator: " · ") }
    var context: String { Array(Set(origins.map(\.context))).sorted().joined(separator: "\n\n") }
    func matches(_ query: String) -> Bool {
        let content = origins.map { $0.title + " " + $0.category + " " + $0.context }.joined(separator: " ") + " " + url.absoluteString
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { content.localizedStandardContains(String($0)) }
    }
    /// Exact destination URLs are deduplicated; all category/source occurrences
    /// remain inspectable. HTTP and HTTPS are not assumed to be interchangeable.
    static func merge(awesome: AwesomeResourceIndex, pwa: [PWAWebResource], pwaCommit: String) -> [SyncedWebResource] {
        var entries: [SyncedWebResource] = [], indices: [String: Int] = [:]
        func append(_ url: URL, _ origin: SyncedResourceOrigin) {
            let key = url.absoluteString
            if let index = indices[key] { entries[index].origins.append(origin) }
            else {
                indices[key] = entries.count
                let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                entries.append(SyncedWebResource(id: id, url: url, origins: [origin]))
            }
        }
        for item in awesome.items {
            append(item.url, SyncedResourceOrigin(repository: GitHubLibraryRemote.awesomeRepo, commit: awesome.commit,
                path: "README.md", line: item.sourceLine, title: item.title,
                category: [item.categoryTitle, item.subcategoryTitle].compactMap { $0 }.joined(separator: " · "), context: item.context))
        }
        for item in pwa {
            guard let url = URL(string: item.url) else { continue }
            let category = url.host?.contains("youtube.com") == true ? "视频频道" : url.host?.contains("google.com") == true ? "上游反馈" : "PWA 学习资源"
            append(url, SyncedResourceOrigin(repository: GitHubLibraryRemote.pwaRepo, commit: pwaCommit,
                path: "index.html", line: item.sourceLine, title: item.title, category: category,
                context: "PWA 原版说明中的资源。江湖残局与疑难题原页注明取材于从寬象棋频道；具体题目没有独立视频对应关系。"))
        }
        return entries
    }
}
