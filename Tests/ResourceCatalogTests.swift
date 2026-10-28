#if RESOURCE_CATALOG_TESTS
import Foundation
struct RecommendationArrow { let rank: Int; let move: Move }

@main @MainActor struct ResourceCatalogTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let lessons = LearningModel.builtInLessons, sources = LearningModel.builtInSources
        try ResourceCatalog.validate(lessons: lessons, sources: sources)
        let entries = ResourceCatalog.entries
        check(entries.count == 21, "The reviewed compact catalog changed without a content audit")
        check(entries.filter { $0.kind == .localCourses }.count == 5, "Keep the five real local entry groups")
        check(Set(entries.map(\.kind)) == Set(ResourceCatalogKind.allCases), "Catalog categories disappeared")
        check(ResourceCatalog.directorySections.count == 9, "The complete awesome directory must remain accessible")
        check(Set(ResourceCatalog.directorySections.map(\.id)) == Set(["general-websites", "websites-to-play", "games-databases", "books", "youtube-channels", "engines", "computer-xiangqi", "other-useful-tools", "social"]), "Upstream taxonomy is incomplete")
        for section in ResourceCatalog.directorySections {
            check(section.url?.host == "github.com" && section.url?.fragment == section.id, "Directory shortcuts must link to the pinned, exact upstream section")
        }
        check(ResourceCatalog.filtered(query: "  \n ", kind: nil, stage: nil) == entries, "Whitespace should not hide entries")
        check(ResourceCatalog.filtered(query: "pIkAfIsH", kind: .openSource, stage: nil).map(\.id) == ["tool-pikafish"], "Case-insensitive author/title search failed")
        check(ResourceCatalog.filtered(query: "不存在的书名", kind: nil, stage: nil).isEmpty, "Search fabricated a matching resource")
        check(ResourceCatalog.filtered(query: "王嘉良 2016", kind: .book, stage: .opening).map(\.id) == ["book-intermediate-2016"], "Multi-word book search failed")
        check(ResourceCatalog.filtered(query: "王嘉良", kind: .localCourses, stage: nil).isEmpty, "A book search must not imply its text is a local course")
        for kind in ResourceCatalogKind.allCases {
            let filtered = ResourceCatalog.filtered(query: "", kind: kind, stage: nil)
            check(!filtered.isEmpty && filtered.allSatisfy { $0.kind == kind }, "Category filter leaked another kind")
        }
        for stage in LearningStage.allCases {
            let filtered = ResourceCatalog.filtered(query: "", kind: nil, stage: stage)
            check(!filtered.isEmpty && filtered.allSatisfy { $0.stages.contains(stage) }, "Stage filter leaked another stage")
        }
        for entry in entries {
            check(!entry.rights.isEmpty && !entry.scope.isEmpty, "Every card needs reviewable rights and scope")
            if entry.kind == .localCourses {
                check(entry.lessons(in: lessons).map(\.id) == entry.lessonIDs, "A local entry must resolve real ordered lessons")
                check(entry.offlineLabel == "可离线练习" && entry.resolvedURL == nil && entry.readingSource(in: sources) == nil,
                      "Local course entries must not load remote content")
            } else {
                check(entry.offlineLabel == "需访问原站", "External text was falsely advertised as offline")
                if let source = entry.readingSource(in: sources) {
                    check(URL(string: source.url)?.scheme == "https", "Embedded reader needs an explicit HTTPS origin")
                } else { check(entry.resolvedURL?.scheme == "https", "External button needs a safe target") }
            }
        }
        let references = Set(entries.compactMap(\.sourceID))
        check(references == Set(ProfessionalResources.sources.map(\.id)), "Do not duplicate or silently lose the existing verified reading sources")
        check(ResourceCatalog.attribution.contains("CC0") && ResourceCatalog.attribution.contains("不延伸"), "CC0 index permission must not relicense linked books")
        let pwa = entries.first { $0.id == "tool-xiangqi-pwa" }!
        check(pwa.rights.contains("第三方") && pwa.scope.contains("没有解序"), "The PWA index must not overclaim solved or cleared content")
        let book = entries.first { $0.id == "book-intermediate-2016" }!
        check(book.kind == .book && book.rights.contains("未取得") && book.lessonIDs.isEmpty, "Book bibliography is not a local textbook")
        let wxf = entries.first { $0.id == "wxf-open-guide" }!
        check(wxf.rights.contains("BY-NC-SA") && wxf.rights.contains("第 13"), "Mixed PDF licenses cannot be flattened into a blanket license")
        var unsafe = book
        unsafe.externalURL = "file:///private/example/book.pdf"
        check(unsafe.resolvedURL == nil, "An index link must not open arbitrary local files")
        unsafe.externalURL = "javascript:alert(1)"
        check(unsafe.resolvedURL == nil, "Executable URL scheme must be rejected")
        do {
            try ResourceCatalog.validate(lessons: lessons.filter { $0.id != "atlas-activity" }, sources: sources)
            preconditionFailure("Missing local course was accepted")
        } catch { checks += 1 }
        do {
            try ResourceCatalog.validate(lessons: lessons, sources: sources.filter { $0.id != "professional-chen-position" })
            preconditionFailure("Missing existing reader source was accepted")
        } catch { checks += 1 }
        print("PASS \(checks) resource catalog / filtering / source / rights-boundary checks; \(entries.count) entries, no network or user-state writes")
    }
}
#endif
