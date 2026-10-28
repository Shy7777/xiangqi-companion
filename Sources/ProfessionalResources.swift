import Foundation

/// Original reading assignments. The linked works remain on their authors' or providers' sites.
struct ProfessionalReadingPath: Identifiable {
    let id: String
    let title: String
    let aim: String
    let assignment: String
    let sourceIDs: [String]
}

enum ProfessionalResources {
    static let sources: [LearningSource] = [
        LearningSource(
            id: "professional-cxa-stratagems",
            title: "中国象棋协会 · 象棋三十六计（短例·选看）",
            url: "https://www.wxf-xiangqi.org/index.php?Itemid=328&id=231&lang=cn&option=com_content&view=article",
            note: "中国象棋协会制作、世界象棋联合会提供的目录，仅作短例选看。本轮实测第 15 集为 58 秒、7 子短例，不适合作为本用户进阶主线；未逐集观看，不推定各集长度相同，未收录视频或讲稿。"
        ),
        LearningSource(
            id: "professional-cxa-lin-15",
            title: "林延秋 · 第15计：调虎离山（短例·选看）",
            url: "https://www.wxf-xiangqi.org/index.php?id=308&lang=cn&option=com_sppagebuilder&view=page",
            note: "协会系列官方单集，讲者林延秋。本轮原站播放实测总长 58 秒，画面为 7 子短例；适合短时识别一个战术关系，不当作完整实战或进阶课程。未逐集观看该系列，也未逐招审定讲解。"
        ),
        LearningSource(
            id: "professional-cxa-tang-28",
            title: "唐丹 · 第28计：上屋抽梯（短例·选看）",
            url: "https://www.wxf-xiangqi.org/index.php?id=321&lang=cn&option=com_sppagebuilder&view=page",
            note: "协会系列官方单集页，讲者唐丹。目录与页面已核实，未完整观看，也未独立确认本集时长；仅作短例选看，不由作品名或讲者身份推定它具有系统进阶深度。"
        ),
        LearningSource(
            id: "professional-chen-position",
            title: "陈俊彦 · 形势评估：活动、威胁与子力协同（中文）",
            url: "https://www.zh.xiangqi.com/articles/5-xiangqi-situation-analysis-indicators.html",
            note: "相弈象棋陈俊彦署名原创专题，以配图讨论子力、控制范围、威胁、牵制与协同。中文正文已核读，适合作为中局判断的短读；文中子力数值只是教学近似，不是引擎评分或任意局面的固定结论。"
        ),
        LearningSource(
            id: "professional-png-opening-03",
            title: "Jim Png · 开局理论 03：子力、节奏与要点（英文）",
            url: "https://www.xqinenglish.com/index.php?Itemid=511&catid=226&id=451&lang=en&option=com_content&view=article",
            note: "Jim Png 作者原站的英文导读，参考刘殿中《象棋布局精要》，讨论恋兵、贪子失先、拥塞和要点。正文提纲已核读；实例依赖网页嵌入内容，不是教材全文。"
        ),
        LearningSource(
            id: "professional-png-opening-04",
            title: "Jim Png · 开局理论 04：中心、次序与进攻时机（英文）",
            url: "https://www.xqinenglish.com/index.php?Itemid=511&catid=226&id=452&lang=en&option=com_content&view=article",
            note: "Jim Png 作者原站的英文导读，参考刘殿中《象棋布局精要》，涵盖中心、空间、走子次序、进攻时机与弃兵争先。正文为提纲，案例需原站加载；不声称已搬入完整变化。"
        ),
        LearningSource(
            id: "professional-png-middlegame",
            title: "Jim Png · 中局：判断局面、选择计划、实施战术（英文）",
            url: "https://www.xiangqi.com/articles/defining-and-learning-the-xiangqi-chinese-chess-middle-game",
            note: "Jim Png 署名文章，参考刘殿中《象棋中局战法》，说明中局判断、战略与计算的关系，以及实战和复盘的用途。英文正文可读；这是专业导读，不是刘殿中教材全文或官方认证课程。"
        ),
        LearningSource(
            id: "professional-cctv-2016-cheng-xie",
            title: "央视对局节目 · 程鸣—谢靖（29分12秒）",
            url: "https://tv.cctv.com/2016/09/03/VIDEzaFhZUE0wwHJikaMK1mv160903.shtml",
            note: "央视 2016-09-03 节目页确认讲述华阳体育杯全国团体赛程鸣—谢靖一局，并标为完整版。由页面播放器标识对应的官方接口核实时长 29分12秒；供原站观摩，未全片观看或审定每手讲解，未导入为本地训练谱。"
        ),
        LearningSource(
            id: "professional-cctv-2015-xu-hong",
            title: "央视《象棋世界》· 许银川—洪智（29分24秒）",
            url: "https://tv.cctv.com/2015/12/26/VIDEPr6JPK6JHH8lIlAA0TGK151226.shtml",
            note: "央视 2015-12-26 节目页确认讲述决战名山天堂寨站许银川—洪智一局。由页面播放器标识对应的官方接口核实时长 29分24秒；供原站观摩，未全片观看，不保证逐步覆盖全局，未收录视频或完整讲稿。"
        ),
        LearningSource(
            id: "professional-chen-endgame",
            title: "陈俊彦 · 实用残局原则与胜和定式",
            url: "https://www.zh.xiangqi.com/articles/10-xiangqi-endgame-principles.html",
            note: "相弈象棋陈俊彦署名中文原创文章，讨论兵的位置、将帅控线、停着与残局转换。正文可读，但胜和定式仅作概览，没有逐局完整解法；应用不把概括结论用于任意摆局的判胜。"
        )
    ]

    static let paths: [ProfessionalReadingPath] = [
        ProfessionalReadingPath(
            id: "professional-opening-understanding",
            title: "布局理解：走完熟悉的几步之后",
            aim: "已经会出子，进一步判断哪条线值得争、什么时机值得换计划。",
            assignment: "选自己常下的一套开局，在双方开始接触时停住。先不看建议，写下两种计划：各自准备改善哪枚棋子、争哪条线、允许对方获得什么。读完开局 03/04 后，任选一个计划继续五个回合；对方换应手时，只解释哪项条件改变，再决定是否改计划。",
            sourceIDs: ["professional-png-opening-03", "professional-png-opening-04"]
        ),
        ProfessionalReadingPath(
            id: "professional-position-assessment",
            title: "形势判断：多一个兵，不一定更好下",
            aim: "把子力数量、活动空间、将帅安全和先手放到同一个局面里比较。",
            assignment: "从自己的对局取一个没有直接将杀的中局，先用一句话判断谁更好下，并指出决定判断的两项条件。分别提出一个改善局面的走法和一个主动进攻的走法，算出对方最强回应。最后再看引擎与导读：如果结论不同，改的是判断依据，不只记住 Top 1。",
            sourceIDs: ["professional-chen-position", "professional-png-middlegame", "professional-png-opening-03"]
        ),
        ProfessionalReadingPath(
            id: "professional-calculation-defense",
            title: "计算攻防：把对方最强回应算进去",
            aim: "以完整实战的中局决策为主，区分局面判断、候选计划与需要算到底的强制变化。",
            assignment: "先读中局专题，明确判断与计算的分工；回「实战研究」选一个关键点，列两手候选，对每手计算对手最强回应和自己的后续，交换未平息就继续算。先落子、再看反馈，回错误前重算，必要时沿自己的变招实战。央视对局节目用于额外观摩：在一个决策前暂停先算，再与讲解比较；节目加载失败不影响本地训练。协会短例仅作选看，不代替这条主线。",
            sourceIDs: ["professional-chen-position", "professional-png-middlegame", "professional-cctv-2016-cheng-xie", "professional-cctv-2015-xu-hong"]
        ),
        ProfessionalReadingPath(
            id: "professional-endgame-transition",
            title: "残局转化：先看换完以后能否赢或守",
            aim: "把胜和知识用于实战的交换决策，而非只会照着少子谱走。",
            assignment: "找一个可选择兑子的简化局面。先列出兑与不兑后剩余的兵种、兵的位置和士象保护，再给出自己的争胜或守和计划。分别继续对练，检查计划能否兑现；随后只改变一枚兵的位置或一枚防守子，重新判断。遇到复杂胜和结论，保留不确定，不用一条口诀代替完整分析。",
            sourceIDs: ["professional-chen-endgame", "professional-png-middlegame"]
        )
    ]
}
