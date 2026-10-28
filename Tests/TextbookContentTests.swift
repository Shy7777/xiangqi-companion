import Foundation

@main struct TextbookContentTests {
    static func main() {
        precondition(TextbookCurriculum.lessons.isEmpty,
                     "Third-party textbook excerpts must not ship in the public source release")
        let sources = TextbookCurriculum.sources
        precondition(sources.count == 4 && Set(sources.map(\.id)).count == sources.count,
                     "Reading links retain distinct source identities")
        for source in sources {
            precondition(source.id.hasPrefix("textbook-"), "Reading source namespace")
            precondition([source.title, source.url, source.note].allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }, "Each reading link needs attribution and a distribution boundary")
            precondition(URL(string: source.url)?.scheme == "https", "Reading links use HTTPS")
            precondition(source.note.contains("不"), "Each source states what is not redistributed")
        }
        print("PASS textbook release boundary: 4 attributed reading links; no bundled textbook excerpts")
    }
}
