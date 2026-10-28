import Foundation

/// Presentation and search only. Source titles, source paths, FENs and saved
/// lesson fingerprints must continue to use the original, unmodified strings.
enum ChineseDisplayText {
    private static let displayCache = ChineseDisplayTextCache()
    private static let searchLocale = Locale(identifier: "en_US_POSIX")

    static func simplified(_ original: String) -> String {
        displayCache.simplified(original)
    }

    /// Both the query and the searchable text use the same canonical form. This
    /// also keeps Latin titles and full-width move numbers searchable.
    static func searchKey(_ original: String) -> String {
        simplified(original).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: searchLocale)
            .precomposedStringWithCanonicalMapping
    }

    static func searchTerms(_ query: String) -> [String] {
        searchKey(String(query.prefix(512))).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func matches(normalizedText: String, terms: [String]) -> Bool {
        // Script, case, width and Unicode composition have already been folded.
        // Literal search avoids repeating costly locale/canonical comparisons for
        // every one of the library's thousands of titles on each keystroke.
        terms.allSatisfy { normalizedText.range(of: $0, options: .literal) != nil }
    }
}

extension String {
    var simplifiedForDisplay: String { ChineseDisplayText.simplified(self) }
}

/// A small, process-local FIFO cache for visible text. Unlike an unbounded
/// memoization table, browsing the whole library cannot retain every label.
/// Foundation conversion runs outside the lock; duplicate concurrent requests
/// are harmless. Stored byte cost includes the original and converted strings.
final class ChineseDisplayTextCache: @unchecked Sendable {
    struct Metrics: Equatable {
        let count: Int
        let utf8Bytes: Int
        let maximumEntries: Int
        let maximumUTF8Bytes: Int
    }
    private struct Entry {
        let value: String
        let bytes: Int
    }
    private let lock = NSLock()
    private let maximumEntries: Int
    private let maximumUTF8Bytes: Int
    private let maximumCachedInputBytes: Int
    private var entries: [String: Entry] = [:]
    private var order: [String?]
    private var head = 0
    private var tail = 0
    private var storedBytes = 0

    init(maximumEntries: Int = 2_048, maximumUTF8Bytes: Int = 1_048_576,
         maximumCachedInputBytes: Int = 16_384) {
        self.maximumEntries = max(1, min(maximumEntries, 4_096))
        self.maximumUTF8Bytes = max(0, min(maximumUTF8Bytes, 2_097_152))
        self.maximumCachedInputBytes = max(0, min(maximumCachedInputBytes, 16_384))
        self.order = Array(repeating: nil, count: self.maximumEntries)
    }

    func simplified(_ original: String) -> String {
        // FENs, URLs and engine output do not need conversion or cache entries.
        guard !original.utf8.allSatisfy({ $0 < 128 }) else { return original }
        let inputBytes = original.utf8.count
        let mayCache = inputBytes <= maximumCachedInputBytes && inputBytes <= maximumUTF8Bytes
        if mayCache {
            lock.lock()
            let cached = entries[original]?.value
            lock.unlock()
            if let cached { return cached }
        }
        let converted = original.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? original
        let bytes = inputBytes + converted.utf8.count
        guard mayCache, bytes <= maximumUTF8Bytes else { return converted }

        lock.lock()
        defer { lock.unlock() }
        if let cached = entries[original] { return cached.value }
        while !entries.isEmpty && (entries.count >= maximumEntries || storedBytes + bytes > maximumUTF8Bytes) {
            if let oldest = order[head], let removed = entries.removeValue(forKey: oldest) {
                storedBytes -= removed.bytes
            }
            order[head] = nil
            head = (head + 1) % maximumEntries
        }
        entries[original] = Entry(value: converted, bytes: bytes)
        order[tail] = original
        tail = (tail + 1) % maximumEntries
        storedBytes += bytes
        return converted
    }

    var metrics: Metrics {
        lock.lock()
        defer { lock.unlock() }
        return Metrics(count: entries.count, utf8Bytes: storedBytes,
                       maximumEntries: maximumEntries, maximumUTF8Bytes: maximumUTF8Bytes)
    }
}
