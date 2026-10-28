import Foundation

/// Topic alignment is not an edition, page, exercise, or learning-completion claim.
struct TextbookTheme: Identifiable, Equatable {
    let id: String
    let chapter: Int
    let title: String
    let target: String
    let boundary: String
    let lessonIDs: [String]

    func lessons(in catalog: [LearningLesson]) -> [LearningLesson] {
        let lookup = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return lessonIDs.compactMap { lookup[$0] }
    }
}

enum BookCoverage {
    static let title = "象棋中级教程（第二版）"
    static let sourceURL = "https://www.megbook.com.hk/mall/detail.jsp?proID=2782834"
    static let boundary = "目录主题对照 · 非原书全文或授权改编。已核验公开章节目，尚未取得原书完整正文；以下课程不能证明覆盖原书全部知识细节、原题与评注。"
    static let chapterTitles = ["布局研究", "中局研究", "残局研究和实践", "实战对局讲解", "大师经验"]

    static let themes: [TextbookTheme] = [
        .init(id: "1.1", chapter: 1, title: "布局理论概要", target: "比较出子效率、空间与反击；说出阵形通向什么中局，而不是报出布局名称。", boundary: "原创课程选取具体体系说明通则，不是原书本节逐页适配。", lessonIDs: ["repertoire-screen-high-rook", "repertoire-elephant-center"]),
        .init(id: "1.2", chapter: 1, title: "布局战术", target: "分析带威胁的展开和交换；每个先手都要核算对方能否反击或拒绝。", boundary: "只覆盖列出的练习机制，不能由几条主变推断掌握所有布局战术。", lessonIDs: ["repertoire-screen-exchange", "repertoire-sandwich-56", "repertoire-same-ranked"]),
        .init(id: "1.3", chapter: 1, title: "布局阶段易犯的错误", target: "在过早深入、重复调动与拥塞中找到代价；回到失误前改走，并在另一应招下重试。", boundary: "错误由局面和走前/走后引擎评价判断；不把历史谱外着法直接判错。", lessonIDs: ["repertoire-opposite-blockade", "atlas-review"]),
        .init(id: "1.4", chapter: 1, title: "布局陷阱", target: "先算诱饵背后的强制回应，再决定能否吃；对手不配合时停止沿旧套路走。", boundary: "陷阱研究以有限实例为边界，未取得原书全部陷阱例题。", lessonIDs: ["repertoire-opposite-tiger", "repertoire-pawn-thunder"]),
        .init(id: "1.5", chapter: 1, title: "流行布局变化详析", target: "从中炮、顺逆向炮、兵相马炮类起手中选择主干；对照不同应招与中局计划。", boundary: "所列具体布局是本项目的选材，不声称就是该书第二版收录的全部体系；也不宣称为当前比赛最新理论。", lessonIDs: ["repertoire-screen-59", "repertoire-screen-57", "repertoire-sandwich-rook", "repertoire-same-deferred", "repertoire-pawn-counter", "repertoire-horse-palcorner", "repertoire-palcorner-pawn", "repertoire-cross-wings"]),
        .init(id: "2.1", chapter: 2, title: "战略思想", target: "同时评估安全、材料、活动和弱点；比较主动进攻与改善局面两种计划。", boundary: "专题截段来自已有四盘实战，不另计为新增完整名局。原创点评不是棋手自述。", lessonIDs: ["atlas-activity", "atlas-race", "atlas-balance", "systematic-position-balance"]),
        .init(id: "2.2", chapter: 2, title: "战术技法", target: "在拆保护、炮架变化、近身马与攻守转换中算清回应；把威胁和实际得失分开。", boundary: "已配具体可演练机制，但未证明穷尽原书全部战术分类。", lessonIDs: ["atlas-exchange", "atlas-invasion", "atlas-counterinitiative"]),
        .init(id: "2.3", chapter: 2, title: "行棋方向", target: "兵线、将位或交换条件改变后，重新选择目标区域与要改善的棋子。", boundary: "通过多盘不同节点比较方向，不将一盘胜局中的每一步倒推成唯一正确计划。", lessonIDs: ["atlas-pawn-break", "atlas-king-safety", "atlas-cannon-routes", "atlas-conversion"]),
        .init(id: "3.1", chapter: 3, title: "常见实用残局胜和规律", target: "分辨将位、兵的深浅、护卫缺口和车马炮的活动条件；执攻与执守都要练。", boundary: "有限引擎主变不是例胜例和证明。本版未穷举各材料组合的全部理论定式。", lessonIDs: ["endgame-pawn-king-space", "endgame-pawn-depth", "endgame-rook-pawn-coordination", "endgame-rook-palace-defense", "endgame-rook-minor-activity", "endgame-horse-pawn-routes", "endgame-horse-pawn-support", "endgame-cannon-pawn-screen", "endgame-missing-advisor-defense", "endgame-missing-elephant-defense"]),
        .init(id: "3.2", chapter: 3, title: "多兵种杀法", target: "跟踪将军子、控逃路的子、炮架与马腿；对方换防守后重新计算分工。", boundary: "使用原创协同练习，不包含教材摘例；不用短时兵分标记已证强制杀法。", lessonIDs: ["endgame-rook-horse-team", "endgame-horse-cannon-team"]),
        .init(id: "3.3", chapter: 3, title: "实战研究", target: "交换前描述目标残局；检查交换是否拆掉炮架、失去活动或打开对方进攻路线。", boundary: "具体位置的转化研究，不推广为任何多子方都应兑子的规则。", lessonIDs: ["endgame-rook-pawn-exchange", "endgame-cannon-support-exchange", "endgame-winning-simplification", "endgame-active-defense"]),
        .init(id: "3.4", chapter: 3, title: "杀着自测", target: "隐藏题型与答案，独立选择关键着；含提示的练习与隔日独立通过分开记录。", boundary: "从本软件有限题库混合选题，不是原书杀着自测题库。", lessonIDs: ["endgame-rook-horse-team", "endgame-horse-cannon-team"]),
        .init(id: "4.0", chapter: 4, title: "实战对局讲解", target: "完整回放布局、中局与转化，在关键点提出自己的候选；原谱与引擎建议可不相同。", boundary: "四盘公开实战记录，非本书原谱；历史结果不证明中间每一手最优。", lessonIDs: ["systematic-opening-transition", "systematic-position-balance", "systematic-forcing-calculation", "systematic-endgame-transition"]),
        .init(id: "5.1", chapter: 5, title: "大师谈布局", target: "建立自己的准备流程：主干、偏离、反击、中局接续，利用每次复盘修订布局选择。", boundary: "仅对照方法主题。未读本节正文，不伪造大师观点、引语或教案。", lessonIDs: ["atlas-preparation", "repertoire-screen-exchange", "repertoire-pawn-counter"]),
        .init(id: "5.2", chapter: 5, title: "大师谈中局", target: "落实威胁→候选→最强回应→落子复核的思考流程；区分判断错误与计算漏步。", boundary: "这里的流程和问题为软件原创，不归给书中作者。", lessonIDs: ["atlas-review", "atlas-activity", "atlas-counterinitiative"]),
        .init(id: "5.3", chapter: 5, title: "大师谈残局", target: "先说明想进入哪种局面，再选交换对象；记录条件和反例，隔日从不同位置验证。", boundary: "这里的残局研究方法为软件原创，不代替原书经验文章。", lessonIDs: ["endgame-winning-simplification", "endgame-active-defense", "systematic-endgame-transition"]),
        .init(id: "5.4", chapter: 5, title: "大师谈备战", target: "围绕常错局面和常见偏离安排赛前练习；赛后先独立复盘，再开引擎找第一处判断偏差。", boundary: "不提供大师备战原文或未经核实的段位承诺；本软件不记录真实比赛用时。", lessonIDs: ["atlas-preparation", "atlas-review", "systematic-forcing-calculation"])
    ]

    static var textbook: StudyTextbook {
        StudyTextbook(id: "wang-intermediate-2016", title: title + " · 目录主题对照", author: "王嘉良、张志强、张弘",
            edition: "经济管理出版社 · 2016 · ISBN 9787509641002 · 书目登记 288 页",
            sourceURL: sourceURL, coverage: boundary,
            rightsNote: "高校课纲所列参考书是 2006 年第一版，不能视作对第二版或本软件的认证。第二版章节目据公开书目核对，原书正文与改编授权尚未取得。公开版仅含原创教学与客观实战记录；不含本书正文或题库。",
            chapters: themes.map { .init(id: $0.id, title: $0.title, locator: "公开目录 " + $0.id, note: $0.target + " " + $0.boundary) })
    }

    static func validate(lessons: [LearningLesson]) throws {
        guard themes.count == 17, Set(themes.map(\.id)).count == themes.count,
              Set(themes.map(\.chapter)) == Set(1...5) else { throw StudyError.invalidContent("教材主题目录不完整或编号重复。") }
        let known = Set(lessons.map(\.id))
        for theme in themes {
            guard !theme.target.isEmpty, !theme.boundary.isEmpty, !theme.lessonIDs.isEmpty,
                  Set(theme.lessonIDs).count == theme.lessonIDs.count,
                  theme.lessonIDs.allSatisfy(known.contains),
                  theme.lessons(in: lessons).allSatisfy({ $0.isSystematic && $0.lines.contains { $0.checkpoints?.isEmpty == false } })
            else { throw StudyError.invalidContent("教材主题 \(theme.id) 含缺失、重复或不可练的课程。") }
        }
    }
}

struct CurriculumInventory: Equatable {
    let courses: Int
    let lines: Int
    let uniqueStarts: Int
    let checkpoints: Int
    let variations: Int
    let completeGames: Int
    init(lessons: [LearningLesson]) {
        let core = lessons.filter(\.isSystematic)
        let all = core.flatMap(\.lines)
        courses = core.count; lines = all.count
        uniqueStarts = Set(all.map { (try? Position(fen: $0.startingFEN).fen) ?? $0.startingFEN }).count
        checkpoints = all.reduce(0) { $0 + ($1.checkpoints?.count ?? 0) }
        variations = all.reduce(0) { $0 + ($1.variations?.count ?? 0) }
        completeGames = all.filter { $0.game != nil }.count
    }
}
