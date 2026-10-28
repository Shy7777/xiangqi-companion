import Foundation

/// Navigation and bibliography only. The playable curriculum remains LearningLesson/StudyLine.
enum GuidedCurriculum {
    static let books: [StudyTextbook] = [BookCoverage.textbook] + [
        StudyTextbook(
            id: "png-opening", title: "选择自己的布局体系 · 英文署名专题", author: "Jim Png",
            edition: "Xiangqi.com 作者署名文章，非刘殿中著作全文",
            sourceURL: "https://www.xiangqi.com/articles/choosing-your-xiangqi-chinese-chess-opening",
            coverage: "布局主题的延伸阅读入口；文章的谱例和正文不随软件提供。",
            rightsNote: "作者署名文章保留在原站；仅按需打开，不打包正文或嵌入视频。文中参考刘殿中著作，不等于提供该书全文。",
            chapters: [
                TextbookChapterReference(id: "selection", title: "选择布局与研究思路", locator: "Choosing your Xiangqi (Chinese Chess) Opening", note: "将布局选择落实为能理解的分支。先看子力效率与反击，再在课程中比较不同着序。"),
                TextbookChapterReference(id: "example", title: "具体谱例与不同应对", locator: "请在作者原站阅读", note: "软件的原创课程与该文章独立，不构成文章谱例的完整适配。")
            ]),
        StudyTextbook(
            id: "png-sacrifice", title: "弃子：争先、攻杀与求和 · 英文署名专题", author: "Jim Png",
            edition: "Xiangqi.com · Basic Midgame Tactics 05",
            sourceURL: "https://www.xiangqi.com/articles/basic-xiangqi-chinese-chess-midgame-tactics-05-sacrificing-material",
            coverage: "弃子主题的延伸阅读入口；文章中的棋谱摘例不包含在公开课程中。",
            rightsNote: "原文和谱例留在原站，版权归原权利人；阅读链接不构成再分发或改编授权。",
            chapters: [
                TextbookChapterReference(id: "attack", title: "弃子攻击与防守改进", locator: "请在作者原站阅读", note: "阅读后可以用自己有权使用的棋谱在分析棋盘上研究。"),
                TextbookChapterReference(id: "draw", title: "为求和而弃子", locator: "Sacrificing Material for a Draw", note: "本条只提供阅读导航，不包含文章例题、原注或改写课程。")
            ]),
        StudyTextbook(
            id: "qian-midgame", title: "Checkmate Methods in Xiangqi Mid-Games", author: "钱俊（Qian Jun）",
            edition: "WXF 公开英文电子版 · 序言署 1985 年 4 月",
            sourceURL: "https://www.wxf-xiangqi.org/images/free_download_books/Checkmate_methods_in_Xiangqi_Midgames.pdf",
            coverage: "中局攻防与强制手段的外部阅读入口；书内排拟局、例题和原注不包含在软件中。",
            rightsNote: "公开阅读不等于获得再分发或改编许可。本软件仅提供书目及原站链接。",
            chapters: [
                TextbookChapterReference(id: "preface", title: "结构与使用方法", locator: "PDF 第 2–4 页：序言、目录", note: "区分排拟中局与赛事实例；阅读例题前先列威胁、候选和对手抵抗。"),
                TextbookChapterReference(id: "applications", title: "中局计算谱例", locator: "请在原书中阅读", note: "外部阅读与本项目原创训练分开；引擎评价不是数学证明。")
            ]),
        StudyTextbook(
            id: "zhu-checkmates", title: "Basic Xiangqi Checkmate Methods", author: "朱宝位（Zhu Baowei）",
            edition: "WXF 公开英文电子版 · 具体出版年未核明",
            sourceURL: "https://www.wxf-xiangqi.org/images/free_download_books/BasicXqCheckmate.pdf",
            coverage: "杀法主题的外部阅读入口；原书例题、应招分支和作者讲解不随软件分发。",
            rightsNote: "仅链接 WXF 原站，不下载或打包正文；版权归原权利人，公开可读不等于可以复制或改编。",
            chapters: [
                TextbookChapterReference(id: "piece-role", title: "棋子在杀法中的作用", locator: "第 I 章；PDF 第 6 页起", note: "不是重教棋子怎么走，而是观察将帅控线和弱子如何影响进攻条件。"),
                TextbookChapterReference(id: "combined", title: "车马、马炮与炮架协作", locator: "请在原书目录中选择阅读", note: "本软件原创协同练习不等于该书例题的数字化版本。"),
                TextbookChapterReference(id: "conversion", title: "从控线到残局兑现", locator: "第 I 章中的将帅与辅助子作用", note: "同样的剩余兵种不等于同样胜和；比较具体位置、轮次和等待着，不能仅凭子力表下结论。")
            ]),
        StudyTextbook(
            id: "liu-endgame", title: "象棋残局基础 · 推荐阅读", author: "刘殿中",
            edition: "北京体育大学出版社 · 书目记录 2002-06-01 · ISBN 7-81051-485-7",
            sourceURL: "https://www.sinobook.com.cn/B2C/SCRP/bookdetail.cfm?iBookNo=32252",
            coverage: "仅核验正规书目，未取得正文；不计为本软件已适配教材。残局训练使用项目原创局面与完整实战记录。",
            rightsNote: "这是书目入口，不是免费电子书。未虚构目录、原著习题或作者注解；需要正版正文才能做逐章适配。",
            chapters: [TextbookChapterReference(id: "scope", title: "补充残局胜和体系", locator: "本轮只核实书目，未读取目录与正文", note: "可配合自己持有的正版教材阅读；本软件不会声称做完当前课程就掌握了该书全部残局。")]),
        StudyTextbook(
            id: "wang-intermediate", title: "象棋中级教程 · 推荐阅读", author: "王嘉良",
            edition: "经济管理出版社 · 2006 年 6 月第 1 版（高校课纲所列版本）",
            sourceURL: "https://www.shou.edu.cn/_upload/article/files/ba/b5/67140eef420b9509dfca4c3340f1/3eaf5aba-834e-466d-a706-2ec3495ffb8a.pdf#page=201",
            coverage: "上海海洋大学《象棋》课程所列参考书。用于说明系统进阶的书目方向；本轮未取得正版全文。",
            rightsNote: "链接是高校教学大纲的参考书页，不是该书正文。完整实战为独立公开棋谱来源，不宣称出自本书。",
            chapters: [TextbookChapterReference(id: "syllabus", title: "布局—中局—残局—讲评", locator: "高校课纲 PDF 物理第 195–201 页；书目在第 201 页", note: "借鉴分阶段学习与对局讲评相连的课程组织，不挪用或虚构书内章节。")])
    ]

    static let chapters: [GuidedChapter] = [
        GuidedChapter(id: "opening", number: 1, title: "布局：建立你的应对体系",
                      subtitle: "把出子次序连接到中局计划，知道对手变了什么。",
                      goal: "比较出子效率与反击机会。走谱不是记住唯一顺序，而是认出什么条件还在、什么条件已经改变。",
                      lessonIDs: OpeningRepertoireCurriculum.lessons.map(\.id), readingIDs: ["wang-intermediate-2016", "png-opening", "png-sacrifice"],
                      completionStandard: "能解释主线与不同应招的目的，并在隐藏提示后完成两种局面判断。"),
        GuidedChapter(id: "middlegame", number: 2, title: "中局：从判断到可计算的计划",
                      subtitle: "找出防守负担和先手来源，候选必须经得起对方反击。",
                      goal: "先判断谁在威胁谁，再算改变防守关系的手段。攻杀是计划的结果，不是见将就将。",
                      lessonIDs: MiddlegameAtlasCurriculum.lessons.filter { !["atlas-review", "atlas-preparation"].contains($0.id) }.map(\.id), readingIDs: ["wang-intermediate-2016", "qian-midgame"],
                      completionStandard: "提出候选、算清对方回应，能说明为什么另一个看似主动的选择不成立。"),
        GuidedChapter(id: "checkmates", number: 3, title: "杀法：把子力协作算到底",
                      subtitle: "将帅控线、车马配合、马炮协同与炮架变化。",
                      goal: "识别逃路由谁控制、将军由谁完成、对手能否拆掉炮架或解除封锁，再推演连续应招。",
                      lessonIDs: ["endgame-rook-horse-team", "endgame-horse-cannon-team"],
                      readingIDs: ["wang-intermediate-2016", "zhu-checkmates"],
                      completionStandard: "在多个组合中独立完成关键着，能解释必要条件，而不是只说出杀法名称。"),
        GuidedChapter(id: "endgame", number: 4, title: "残局：判断能赢、能守的条件",
                      subtitle: "交换只是入口，兵位、将位、控线与行棋权决定计划。",
                      goal: "比较变化后的具体局面，练习兑现与防守；从原图的胜法过渡到条件改变后的重新判断。",
                      lessonIDs: EndgameSchoolCurriculum.lessons.filter { !["endgame-rook-horse-team", "endgame-horse-cannon-team"].contains($0.id) }.map(\.id), readingIDs: ["wang-intermediate-2016", "zhu-checkmates", "png-sacrifice", "liu-endgame"],
                      completionStandard: "说明目标残局依赖什么位置条件，完成谱例后从变式局面与引擎继续验证。"),
        GuidedChapter(id: "integration", number: 5, title: "实战：把各阶段连成一盘棋",
                      subtitle: "四盘完整名局，结合布局准备与赛后复盘方法。",
                      goal: "在真实完整对局的关键点独立选择，再比较棋手走法与本地引擎；合理变招沿自己的棋面继续实战。",
                      lessonIDs: ["atlas-preparation", "atlas-review", "systematic-opening-transition", "systematic-position-balance", "systematic-forcing-calculation", "systematic-endgame-transition"],
                      readingIDs: ["wang-intermediate-2016", "wang-intermediate"],
                      completionStandard: "完成各关键点的无提示检验，并隔日复查；研究过名局不等于获得真人段位或大师棋力。")
    ]
}
