import Foundation

/// Software-authored study prompts. These never replace, normalize, or append to
/// an annotation imported from the user's book file.
struct BookLearningGuidance: Equatable, Sendable {
    let title: String
    let goal: String
    let connection: String
    let practicePrompt: String
    let transferPrompt: String
}

enum BookLearningGuide {
    /// A suggested route for someone who already plays, not the book's order or
    /// a prerequisite/completion gate. Every available chapter remains accessible.
    static let recommendedChapterOrder = [4, 5, 6, 8, 2, 3, 7]
    static let sourceLabel = "软件学习引导"
    static let sourceNote = "以下是软件编写的学习建议，与文件原注分开展示；谱例编号不代表难度。"

    static func guide(chapter: Int, sectionTitle: String) -> BookLearningGuidance {
        let title = matchingTitle(sectionTitle)
        let sections: [SectionGuide]
        switch chapter {
        case 4: sections = openingSections
        case 5: sections = middlegameSections
        default: sections = []
        }
        if let section = sections.first(where: { item in
            item.aliases.contains { title.contains($0) }
        }) {
            return section.guidance
        }
        return chapterGuide(chapter)
    }

    private static func matchingTitle(_ title: String) -> String {
        // Matching only: the imported title and commentary remain untouched.
        let simplified = title.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? title
        return simplified.precomposedStringWithCompatibilityMapping
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private static func chapterGuide(_ chapter: Int) -> BookLearningGuidance {
        switch chapter {
        case 2:
            return .init(title: "基础知识 · 按需补缺",
                goal: "只补当前实战卡住的判断：子力配合、攻杀、守和或交换，不必从头重学走法。",
                connection: "在布局、中局或残局遇到说不清的地方，再回到这里找对应基础。",
                practicePrompt: "先读相关原注，自己摆出成立条件；仍说不清就重看一例，能说明再独立重走。",
                transferPrompt: "回到刚才卡住的棋谱，说明这条基础知识如何改变你的选择。")
        case 3:
            return .init(title: "让子研究 · 拓展专题",
                goal: "在让子的特殊条件下，练习用出子效率、威胁和配合补偿子力差距。",
                connection: "这是布局与攻守判断的拓展，不是进入后续章节前必须通过的关卡。",
                practicePrompt: "先核对让子条件与起始局面，再读一例；对方换应招时，重新检查原计划是否成立。",
                transferPrompt: "选另一让子谱，比较补偿条件；不要把特殊摆法中的结论直接套到正常对局。")
        case 4:
            return .init(title: "布局研究 · 建立自己的主线",
                goal: "选一种常遇到的布局，说明每个主要棋子的任务，以及准备进入什么中局。",
                connection: "从实战熟悉的局面开始；后面的中局研究会继续检查这些子力安排能做什么。",
                practicePrompt: "先读一例原注；能说清双方计划，再回到分歧前自己落子。说不清就先比较原谱已有变招。",
                transferPrompt: "本节有参考局就选一局，没有则换一例；先判断对方改变的条件，再决定是否沿用主线。")
        case 5:
            return .init(title: "中局研究 · 把布局计划落实",
                goal: "先找对手威胁，再比较将军、吃子和改善子力的候选；算清对方回应后才下结论。",
                connection: "承接布局的子力分工：棋子已经出来，现在判断能否进攻、需要防守还是准备交换。",
                practicePrompt: "先找出本例真正的攻守转折，再读原注；回到转折前自己选择，并比较已有分支中的不同回应。",
                transferPrompt: "换同节另一例，检查原来的战术条件还在不在；若不成立，就重新制定计划。")
        case 6:
            return .init(title: "残局研究 · 学会收束与抵抗",
                goal: "分清胜负取决于哪些条件：将位、兵的位置、护卫和子力活动，而不只看多了几个子。",
                connection: "承接中局的交换决定：先知道想进入哪种残局，才有依据选择兑什么、保留什么。",
                practicePrompt: "先读一例的胜和条件，再自己走；走不通就回到失误前重试，并检查谱中其他防守。",
                transferPrompt: "换另一例比较关键条件；领先时检查简化是否保住优势，落后时寻找主动抵抗的机会。")
        case 7:
            return .init(title: "古局新编 · 比较解法",
                goal: "练习逐步验证攻守：不因题名、旧解或某条漂亮变化，就假定对手只能如此应对。",
                connection: "把中局计算和残局条件判断放到专题局面里检验；这是拓展，不必先做完才学完整对局。",
                practicePrompt: "先核对起始局面并自己找候选；文件若有旧解、新解或不同版本，回到各自分歧处比较。",
                transferPrompt: "说出一种解法成立或失效的具体条件；换题时重新计算，不照搬上一题的走法。")
        case 8:
            return .init(title: "对局评注 · 串起前中后期",
                goal: "沿一盘完整对局追踪计划：布局怎样进入中局，哪次决策改变方向，如何进入最后阶段。",
                connection: "把前面分开练的布局计划、中局攻守和残局目标接起来，不把每个节点当成孤立题目。",
                practicePrompt: "先选一局读原注；在阶段转换处停下来自己判断，再比较续线。历史胜负不能证明每步都是最优。",
                transferPrompt: "再选一局，先独立标出三个阶段的计划与转折，最后用原注检查遗漏了哪些条件。")
        default:
            return .init(title: "阅读与对照",
                goal: "先确认这份材料讲什么，再决定需要阅读、打谱还是比较不同解法。",
                connection: "未识别的小节不自动套用其他章节结论，也不作为必须完成的新关卡。",
                practicePrompt: "有棋谱就核对起点后读原注、自己重走；纯文字条目先阅读，不把阅读算成独立解题。",
                transferPrompt: "找到与当前问题相关的谱例再练；缺少的正文或变招不能由软件猜补成原书内容。")
        }
    }

    private struct SectionGuide: Sendable {
        let aliases: [String]
        let guidance: BookLearningGuidance

        init(_ title: String, aliases: [String] = [], goal: String, connection: String,
             practice: String, transfer: String) {
            self.aliases = [title] + aliases
            self.guidance = .init(title: title, goal: goal, connection: connection,
                practicePrompt: practice, transferPrompt: transfer)
        }
    }

    // The book's section labels provide topic routing only. These prompts do not
    // claim which numbered example is easier, optimal, or representative.
    private static let openingSections: [SectionGuide] = [
        .init("中炮巡河炮对屏风马", goal: "看清巡河炮的任务，以及其他棋子如何跟上；每次调动都要检查帅将安全和出子代价。",
            connection: "用本节建立布局学习的基本问题：我在争什么，对手准备怎样应对。",
            practice: "先读一例说明双方计划；再选谱中一处分歧，自己判断炮位或对方应招改变后是否还应照走。",
            transfer: "有参考局就挑一局，先找巡河炮实际发挥作用的条件；没有则换一例比较，不只记它走到哪里。"),
        .init("中炮过河车对屏风马平炮兑车", goal: "在决定是否兑车之前，比较交换后双方的出子、压力和下一步任务。",
            connection: "在巡河炮一节的子力任务判断上，加入交换选择：同样主动出子，后续计划可能不同。",
            practice: "先读一例原注；在兑车相关分歧处暂停，自己考虑接受交换和其他谱内应对，再比较后续。",
            transfer: "换一例或参考局，检查支援与退路是否相同；条件变了，就重新评价过河车和兑车计划。"),
        .init("当头炮巡河车对屏风马", aliases: ["中炮巡河车对屏风马"],
            goal: "比较车在巡河位置能做什么，以及继续前进、横移或支援是否值得。",
            connection: "与过河车一节对照：只改变车的活动位置，也可能改变出子次序和进攻时机。",
            practice: "读一例后，选择原谱一处车的调动自己判断；若要多走一手，说明得到什么以及让出了什么。",
            transfer: "在另一例中先找车的任务，再看原谱；不要因为车位相似就默认采用同一续线。"),
        .init("当头炮对单提马", aliases: ["中炮对单提马"],
            goal: "对手换了防守结构后，重新找弱点、反击与自己的出子路线。",
            connection: "从前几节的屏风马转到另一种应对；沿用判断问题，不沿用未经检查的固定走法。",
            practice: "先读一例指出防守结构的不同；自己落子前，再问原来的进攻目标是否仍然存在。",
            transfer: "选另一例或参考局，比较对手最有力的反击条件；若条件不同，就调整自己的展开顺序。"),
        .init("五六炮对屏风马", goal: "检查两炮和车马怎样分工，哪些调动能互相支持，哪些只是重复走子。",
            connection: "承接不同防守结构的比较，回到熟悉的屏风马，重点改看己方炮位与配合。",
            practice: "先读一例，再在炮位变化处自己选择；说明这步帮助了哪个棋子，也检查是否留下反击。",
            transfer: "换一例比较配合条件；若支援子尚未到位，就不能只因炮位相同而照搬进攻。"),
        .init("五七炮对屏风马", goal: "看清不同炮位改变了哪些线路、支援和攻守选择，不把两种阵形当成一套走法。",
            connection: "与五六炮一节对照：保留对子力分工的提问，逐项检查炮位改变后的条件。",
            practice: "读一例原注后，在真实分歧处自己判断；有不同应招就逐一比较，不能只演对方配合的一条线。",
            transfer: "在参考局或另一例中说明何时需要改变计划；以后读五七炮弃车专题时，仍须重新算清具体条件。"),
        .init("进兵局", goal: "把进兵看成局面选择：它打开或限制了什么，后续车马炮准备怎样展开。",
            connection: "离开先架中炮的起手，用同样的出子、安全和对手反击框架检查新的选择。",
            practice: "先读一例辨认双方计划，再自己比较谱内不同应招；若对方改变中心或侧翼安排，重新选择出子方向。",
            transfer: "换一例或参考局，先说进兵带来的实际变化，再选后续；不把第一步相同当成整盘计划相同。"),
        .init("顺炮直车对横车", goal: "比较直车和横车的活动路线，判断哪方正在制造威胁，哪一步仍在准备。",
            connection: "从进兵起手转回炮局，把前面学的出子效率用在双方不同的车路安排上。",
            practice: "读一例后选原谱一处分歧自己处理；决定抢攻前，先核对对方将军、吃子和反击的机会。",
            transfer: "有参考局就换一局，比较车路需要的手数与支援；不能只凭谁先出车断定主动。"),
        .init("顺炮横车对直车", goal: "换到另一种车路安排，重新判断进攻目标、支援和对方最直接的威胁。",
            connection: "与上一节的直车对横车互相对照；更换观察角度，不能把双方身份简单交换后照抄结论。",
            practice: "先读一例，再在横车调动处自己选择；若路线被限制，就检查原计划还剩哪些可用条件。",
            transfer: "选另一例或参考局，说明车路相似之外的关键差异，再决定是否继续进攻或先补协调。"),
        .init("列手炮", goal: "面对不同炮位，先分清双方的威胁方向，再决定抢攻、补防或改善子力。",
            connection: "把前面车路、炮位与出子效率的判断放在另一类布局里对照，之后带着计划进入中局。",
            practice: "读一例后，在谱内攻守分歧处自己落子；若对方威胁更急，先解决具体问题再考虑原定进攻。",
            transfer: "在参考局或另一例中写下一句中局计划：主要目标、参与棋子，以及什么变化会让你改计划。")
    ]

    private static let middlegameSections: [SectionGuide] = [
        .init("弃马陷车", goal: "在考虑弃马之前，核实对方是否必须接受、车是否真无退路，以及自己能否承受反击。",
            connection: "从布局的子力位置进入具体计算：位置安排只有在对手的回应也算清后，才可能转成收益。",
            practice: "先读一例原注，再回到弃马前自己算；谱中若有拒吃、逃车或反击分支，逐一与主线对照。",
            transfer: "换同节另一例，找出陷车成立的必要条件；若条件缺一项，就不能把弃马当成固定答案。"),
        .init("弃炮陷车", goal: "核实弃炮之后车的可走格、保护关系和对方的中间手，不只看表面能追回多少子。",
            connection: "沿用弃马陷车的检查流程，改看炮的线路和炮架条件；相同目的不代表相同手段。",
            practice: "读一例后自己处理弃炮前的选择；比较已有变招时，逐步确认对方车为什么能走或不能走。",
            transfer: "与另一例或前节对照，说明是哪项具体限制构成陷车，哪些只是局面的表面相似。"),
        .init("五七炮弃车", goal: "把弃车后的强制威胁、可持续进攻和材料代价分开核算，不能只看一条漂亮续线。",
            connection: "回到布局中学过的炮位配合，同时把前两节的弃子条件检查用在更大的材料投入上。",
            practice: "先读本例原注；回到弃车前自己找对方最强回应，再与文件已有分支逐一核对。",
            transfer: "本节谱例较少，先比较真实分支；再去相关布局参考局找条件，不把另一种起点硬接成本题变招。"),
        .init("车换马炮", goal: "比较交换后车与马炮的活动、配合、帅将安全及后续目标，不只做静态子值加减。",
            connection: "从短期弃子计算转向交换后的持续局面判断，也为之后研究残局转换做准备。",
            practice: "先读一例，再在交换前自己选择；说明换完后双方最有作用的棋子和最需要解决的问题。",
            transfer: "换另一例比较活动条件；同样是车换马炮，结论也必须依据交换后的实际局面。"),
        .init("高左炮", goal: "观察高左炮的具体任务，比较炮架、车马支援和对手反击是否允许继续原计划。",
            connection: "承接交换后的子力活动判断，转到一类具体炮位，练习从布局安排识别中局机会。",
            practice: "读一例找到攻守转折，再自己落子；若炮架或支援改变，就回到变化处重新评估。",
            transfer: "选同节另一例，先判断炮实际能做什么，再看原注；不要把阵形名称当作进攻成立的依据。"),
        .init("屏风马过河炮", goal: "判断炮越河后的目标、支援与退路，并同时检查对手能否利用后方空隙反击。",
            connection: "与高左炮的任务判断对照：炮的位置变了，进攻距离、配合和安全条件也要重新检查。",
            practice: "先读一例，再回到炮行动前自己决定；有不同防守分支，就比较哪项条件让原计划需要变化。",
            transfer: "换同节另一例，说明越河带来的是实际威胁还是新的负担，再决定继续深入或调整。"),
        .init("中局攻守", goal: "综合选择：先解急迫威胁，再比较进攻、防守、交换和改善最不活跃的棋子。",
            connection: "把前面几节的战术条件、材料取舍与子力任务合起来，练习在多个合理计划之间做判断。",
            practice: "读一例后回到转折前自己列候选；如果计算中出现对方更强回应，就撤回旧判断再算。",
            transfer: "在另一例中先说明选择计划的理由，再看原注；涉及简化时，带着想要的局面去接续残局学习。")
    ]
}
