import Foundation

@main
struct BookLearningGuideTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }

        check(BookLearningGuide.recommendedChapterOrder == [4, 5, 6, 8, 2, 3, 7],
              "Main route should suit an existing player without hiding optional chapters")
        check(Set(BookLearningGuide.recommendedChapterOrder) == Set(2...8),
              "Every available chapter must be represented once")
        check(BookLearningGuide.sourceLabel == "软件学习引导"
              && BookLearningGuide.sourceNote.contains("与文件原注分开展示"),
              "Software-authored prompts need an explicit provenance boundary")

        let opening = ["中炮巡河炮对屏风马", "中炮过河车对屏风马平炮兑车", "当头炮巡河车对屏风马",
                       "当头炮对单提马", "五六炮对屏风马", "五七炮对屏风马", "进兵局",
                       "顺炮直车对横车", "顺炮横车对直车", "列手炮"]
        let middlegame = ["弃马陷车", "弃炮陷车", "五七炮弃车", "车换马炮", "高左炮", "屏风马过河炮", "中局攻守"]
        for (chapter, titles) in [(4, opening), (5, middlegame)] {
            var signatures = Set<String>()
            for title in titles {
                let guide = BookLearningGuide.guide(chapter: chapter, sectionTitle: title)
                check(guide.title == title, "Missing section guide: \(title)")
                check(signatures.insert(guide.goal).inserted, "Distinct sections need concrete distinct objectives")
                check(BookLearningGuide.guide(chapter: chapter,
                    sectionTitle: "弈林新编 第\(chapter)章 \(title)（十一）参考局") == guide,
                    "Metadata prefixes and example numbering must not invent a new guide or difficulty")
                for field in [guide.title, guide.goal, guide.connection, guide.practicePrompt, guide.transferPrompt] {
                    check(!field.isEmpty && field.count <= 90, "Prompts must be complete and compact")
                }
                check(guide.practicePrompt.contains("读") && guide.practicePrompt.contains("自己"),
                      "Study flow should join source reading to an independent decision: \(title)")
                check(guide.transferPrompt.count >= 20 && (guide.transferPrompt.contains("一例")
                      || guide.transferPrompt.contains("参考局") || guide.transferPrompt.contains("谱例较少")),
                      "Transfer needs a material-selection instruction without inventing more examples: \(title)")
            }
        }

        for chapter in 2...8 {
            let fallback = BookLearningGuide.guide(chapter: chapter, sectionTitle: "未核验的小节")
            check(fallback == BookLearningGuide.guide(chapter: chapter, sectionTitle: ""),
                  "Unknown title must use chapter guidance, not guessed record content")
            check(!fallback.connection.isEmpty && !fallback.transferPrompt.isEmpty,
                  "Each chapter needs continuity and an application goal")
        }
        check(BookLearningGuide.guide(chapter: 5, sectionTitle: "五七炮对屏风马")
              == BookLearningGuide.guide(chapter: 5, sectionTitle: ""),
              "Similar title must not pull an opening prompt into a middlegame record")
        check(BookLearningGuide.guide(chapter: 4, sectionTitle: "中炮巡河车对屏风马").title == "当头炮巡河车对屏风马",
              "Known middle-cannon naming alias should retain the right rook topic")
        check(BookLearningGuide.guide(chapter: 4, sectionTitle: "第四章 順炮橫車對直車（參考局）")
              == BookLearningGuide.guide(chapter: 4, sectionTitle: "顺炮横车对直车"),
              "Traditional source titles may be matched without rewriting imported text")
        let original = "  第四章\n中炮巡河炮對屏風馬（十一）\n原注：變招不能刪。  "
        let preserved = original
        _ = BookLearningGuide.guide(chapter: 4, sectionTitle: original)
        check(original == preserved, "Matching cannot mutate caller-owned original text")
        check(BookLearningGuide.guide(chapter: 1, sectionTitle: "目录")
              == BookLearningGuide.guide(chapter: -1, sectionTitle: "其他材料"),
              "Unavailable chapters need a neutral fallback rather than invented book content")
        check(BookLearningGuide.guide(chapter: 5, sectionTitle: "五七炮弃车").transferPrompt.contains("谱例较少"),
              "One-example section must not claim to have extra independent examples")
        check(BookLearningGuide.guide(chapter: 2, sectionTitle: "").goal.contains("不必从头重学"),
              "Foundation is a reference for this player, not mandatory beginner repetition")
        print("PASS \(checks) book learning guidance checks")
    }
}
