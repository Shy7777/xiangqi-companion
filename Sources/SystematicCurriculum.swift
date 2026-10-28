import Foundation

/// Four public historical records, with original teaching questions.
/// A recorded move is evidence of what was played, never a certificate of best play.
/// Provenance: Docs/LICENSING.md; frozen source checks: Tests/SystematicContentTests.swift.
enum SystematicCurriculum {
    static let sources: [LearningSource] = [
        LearningSource(id: "systematic-game-1981-hu-yang",
            title: "实战棋谱：胡荣华—杨官璘 · 1981 首届五羊杯",
            url: "https://www.xqipu.com/qipu/5b21f642-0697-482d-8a91-d65e52a25bdf",
            note: "象棋谱公开全局记录，1981-01-17，红胜，77 半回合。提取走法与赛事事实；导读、问题和节点解释为本产品原创，并非棋手本人讲解。"),
        LearningSource(id: "systematic-game-2011-lv-xu",
            title: "实战棋谱：吕钦—许银川 · 2011 茅山碧桂园杯",
            url: "https://www.xqipu.com/qipu/89473f46-4d12-4fea-8153-bf9e7c00bad5",
            note: "象棋谱公开全局记录，2011-04-11，第 3 轮，和棋，75 半回合。保留全部公开续着；赛果来自资料标注，不把最后局面说成规则判和。"),
        LearningSource(id: "systematic-game-2010-xu-lv",
            title: "实战棋谱：许银川—吕钦 · 2010 亚运会选拔赛",
            url: "https://www.xqipu.com/qipu/8cf50da2-136c-4262-b1a1-1a633bd31947",
            note: "象棋谱公开全局记录，2010-03-10，第 1 轮，红胜，97 半回合。没有复制网页棋评；实战选择仍须接受当前局面的分析，不预设名手每步都正确。"),
        LearningSource(id: "systematic-game-1979-yang-hu",
            title: "实战棋谱：杨官璘—胡荣华 · 1979 全国个人赛",
            url: "https://www.xqipu.com/qipu/9907c6bd-4bf4-47f8-bc08-b9bd4bb4668c",
            note: "象棋谱公开全局记录，1979-09-13，北京，黑胜，172 半回合。资料库不是原始签字记谱单；已核验全部走法合法，未将历史真实性与规则验证混为一谈。")
    ]

    private static func line(id: String, title: String, intent: String, adaptation: String,
                             game: StudyGameMetadata, raw: String,
                             checkpoints: [StudyCheckpoint]) -> StudyLine {
        let byPly = Dictionary(uniqueKeysWithValues: checkpoints.map { ($0.ply, $0) })
        let moves = raw.split(whereSeparator: { $0.isWhitespace }).enumerated().map { index, uci in
            StudyMove(String(uci),
                byPly[index]?.explanation ?? "实战棋谱续着；此步未另附人工注解。",
                hint: byPly[index]?.focus ?? "")
        }
        var result = StudyLine(id: id, title: title, intent: intent, adaptation: adaptation, moves: moves)
        result.checkpoints = checkpoints
        result.game = game
        return result
    }

    static let lessons: [LearningLesson] = [
        openingTransition, positionBalance, forcingCalculation, endgameTransition
    ]

    private static var openingTransition: LearningLesson {
        var lesson = LearningLesson(
            id: "systematic-opening-transition", title: "出子之后，怎样接上中局计划",
            stage: .opening, order: 1000,
            summary: "沿胡荣华与杨官璘的一盘完整实战，追踪过河车、深入的马与另一辆车如何分工。",
            goal: "不用开局名称，也能说明活跃棋子在做什么、未出动的棋子怎样加入，以及何时先算交换。",
            principle: "出子只是把棋子带到能做事的位置；计划还必须说明目标、接应与对手的反击。",
            whenToAdapt: "深处的马出现可被炮吃的路线，或另一翼黑炮、黑卒逼近时，先重新算威胁，不能只按原来的进攻路线走。",
            pitfalls: ["把车过河本身当作优势，忽略它能否安全横向活动。", "只记红方进攻，没检查黑方马、炮与卒的反击。", "把兑掉深入的马解释成白丢子，没有继续算兵的回吃。"],
            sourceIDs: ["systematic-game-1981-hu-yang", "professional-png-opening-03", "professional-png-opening-04"],
            lines: [line(
                id: "systematic-1981-full", title: "胡荣华 对 杨官璘 · 全局 39 回合",
                intent: "从开局到车马炮协作，五次停下来检查目标与配合；其余着法保留完整实战顺序。",
                adaptation: "同一目标可能有别的合法实现方式。偏离实战后应在新局面核验，不把历史续着硬接到不同棋面。",
                game: StudyGameMetadata(red: "胡荣华", black: "杨官璘", event: "第 01 届五羊杯",
                    date: "1981-01-17", result: "红胜", sourceURL: sources[0].url),
                raw: openingMoves, checkpoints: [
                    StudyCheckpoint(ply: 10, title: "过河以后做什么",
                        prompt: "轮到红方。车已经过河；它当前的活动路线和红方尚未出动的棋子，哪一个需要优先处理？提出一手，并说出准备应付的回应。",
                        focus: "红车在 h6，黑车在 h9；黑炮刚离开 h7，黑 g 路卒在 g5。红方左马和左车还在底线。",
                        explanation: "实战车从 h6 横到 g6，离开与黑车同路的局面，同时为沿黑方卒线活动保留空间。随后左马才出动。这里学习的是活跃车与后续出子的衔接，不是‘车过河后必须平到这里’。"),
                    StudyCheckpoint(ply: 19, title: "换到对手这一侧看计划",
                        prompt: "轮到黑方。红马已深入、红车也在前线。你能只顾守住这一翼吗？选一个黑方能主动做事的棋子，检查它行动后红方的直接威胁。",
                        focus: "红马 c6、红车 f6；黑马 g7 与黑炮 g8 位于另一翼，黑方中央有士象，但两车尚未充分活动。",
                        explanation: "实战黑马从 g7 到 h5，向河边活动；后续黑炮下到 g3，g 路卒继续推进。可观察到黑方并非围着红马被动应付，而是在另一翼组织行动；这不是说该反击必然成立，仍需计算红方的推进。"),
                    StudyCheckpoint(ply: 26, title: "把闲子接入战局",
                        prompt: "轮到红方。当前没有将军，但黑炮和黑卒已经靠近。除处理前线外，你能怎样改善尚未参战的重子，同时不忽略本方安全？",
                        focus: "红车 f5 已活跃，另一辆车仍在 a0；黑炮 h3、黑卒 g4 正在红方一侧，红马 c6 深入。",
                        explanation: "实战把 a0 车移到 b0，利用已空出的马、炮原位所在路线出车。它后来参与 b 路兑车。该手的意义在于两车都有任务，而不是只让前线车反复移动；黑方随后炮进 b3，说明出子仍伴随对手反击。"),
                    StudyCheckpoint(ply: 35, title: "先算完一次交换",
                        prompt: "轮到黑方。红马深入，看起来有机会处理它。先数炮架，再把‘吃、回吃’算到底；你希望换掉什么，又会留下什么？",
                        focus: "黑炮 c3、红兵 c5、红马 c6 在同一列；红车 f8 已进入黑方腹地。不能只比较第一口吃到的棋子。",
                        explanation: "实战黑炮从 c3 隔着 c5 兵吃到 c6 马；红兵随即 c5 到 c6 回吃炮。这是炮换马并改变兵位置，不是黑方白得一马。接着还发生 b 路兑车，因此必须连着看子力与活动范围的改变。"),
                    StudyCheckpoint(ply: 58, title: "重新组织第二波",
                        prompt: "轮到红方。双方已各少一辆车，黑炮也侵入底线。红方哪枚轻子可以加入前线？先检查候选落点，再说明它与车、炮能否形成配合。",
                        focus: "红车 f6、红炮 e4 和 g1；红马还在 g2。黑车 d5、黑炮 a0，黑方两马分别在 c6 与 d8。",
                        explanation: "实战红马由 g2 到 f4，再走到 g6，与 f6 车及中路炮形成更靠前的配合。黑车同时沿 d 路深入，不能只看红方连续跳马。这一节点要求说清参战路线与对方反击，而不是背某种杀法名称。")
                ])],
            estimatedMinutes: 30, tags: ["系统研读", "完整实战", "开局转中局", "出子", "攻守分工"])
        lesson.guide = StudyGuide(
            level: "有实战基础 · 系统研究",
            reading: "先认识这盘棋的矛盾：红车很早过河，左马随后深入，但另一辆车还没有参战；黑方则用另一翼的马、炮和卒制造行动。阅读时不要把红胜倒推成红方每个决定都对。把每次停点当成一张新棋面：先说双方各在威胁什么，再确定自己最需要改善的棋子。第 18 回合附近尤其要算到红兵回吃黑炮，再看兑车后的新分工。完整后半盘保留供回看，不要求一次背下 77 个半回合。",
            questions: ["过河车的实际任务是什么？若它受赶，退或横移会不会比再进更好？", "红马深入之后由谁接应，黑炮利用哪个炮架能够处理它？", "另一辆车何时终于参与，交换后哪些棋子的价值和任务改变了？", "如果黑方不按实战反击，你的原计划还需要什么成立条件？"],
            workflow: ["先演示到第一个停点，口述双方威胁与尚未参战的棋子，不查开局名称。", "在五个停点各写或说出两手候选及对手一手最有力回应，再自己落子。", "对照实战解释与局面分析，区分目标相同的合理变招、计算错误和单纯不同选择。", "若判断失误，回到该停点重做，只保留一条提醒；不要从头重复整份谱。", "最后遮住续着，把同一停点换到另一方观察，复述对手怎样破坏计划。"],
            takeaway: "把‘出子’说成任务分工：活跃子有目标，后续子能接应，遇到交换与反击就重算。")
        return lesson
    }

    private static var positionBalance: LearningLesson {
        var lesson = LearningLesson(
            id: "systematic-position-balance", title: "没有明显将吃时，怎样判断局面",
            stage: .strategy, order: 1010,
            summary: "从吕钦与许银川的一盘和棋，练习按活动范围、兵线、子力关系决定计划，而不是盯着胜负分数。",
            goal: "能用可见的棋面事实解释候选着法，并在兑车后重新比较马炮的活动能力。",
            principle: "局面判断是具体关系的比较，不是用‘先手、优势、主动’等词替代计算。",
            whenToAdapt: "重子兑完、兵线清空或炮架改变时，原先的压力线可能消失，需要重列双方的目标。",
            pitfalls: ["以为和棋就没有值得学的决策。", "只数兵的多少，不看为炮提供的炮架。", "兑车后继续按有车时的直线压力判断局面。"],
            sourceIDs: ["systematic-game-2011-lv-xu", "professional-png-middlegame", "professional-chen-position"],
            lines: [line(
                id: "systematic-2011-full", title: "吕钦 对 许银川 · 全局 38 回合",
                intent: "在一个没有早早决出胜负的完整对局里，比较出车、兵线争夺、兑车与马炮互换后的新关系。",
                adaptation: "和棋只是历史结果，不是中间任一局面的自动结论。若选择不同，应分别检查活动范围与具体威胁，而非要求复刻双方的交换。",
                game: StudyGameMetadata(red: "吕钦", black: "许银川",
                    event: "2011 年第 03 届句容茅山碧桂园杯全国象棋冠军邀请赛男子组 · 第 3 轮",
                    date: "2011-04-11", result: "和棋", sourceURL: sources[1].url),
                raw: positionMoves, checkpoints: [
                    StudyCheckpoint(ply: 14, title: "交换后重新找重点",
                        prompt: "轮到红方。一对车刚交换，双方轻子大多仍在本方。你想怎样安排剩下的车？先描述它当前为什么不方便做事。",
                        focus: "红车在 a0，黑车已到 a8；红方两马都已出动，但红车前方有 a3 兵，底线又有相、仕。",
                        explanation: "实战红车 a0 到 a1，随后横到 f1，再转向另一翼。升一格让它越过底线同伴横向活动。这里不是机械要求‘车一定走二线’，而是看哪些格线已经空出、能让这辆车获得实际路线。"),
                    StudyCheckpoint(ply: 23, title: "兵线与重子的联系",
                        prompt: "轮到黑方。你愿意在哪条兵线上制造接触？选择前先检查：兵线变化后，自己的车炮和对方的车分别会获得哪些格线？",
                        focus: "黑车 d5 已靠近河界，黑炮在 b7；g 路黑卒 g6 与红兵 g4 相对，红车仍在 f1。",
                        explanation: "实战推进 g6 卒，接着黑炮到 b5。随后 g 路发生兵卒交换，红车从 b4 吃到 g4。这个过程说明兵的接触会把重子引向新路线；不能只用‘争一个兵’概括整个计划。"),
                    StudyCheckpoint(ply: 29, title: "换车之前看炮架",
                        prompt: "轮到黑方。双方只剩各一辆车，红车刚吃卒。若把车带到接触位置，红方吃车后谁能回吃？把这条交换线完整说清。",
                        focus: "红车 g4；黑车 d5、黑炮 b5、黑卒 c5 同在第五横线附近。炮能否回吃取决于中间到底有几个棋子。",
                        explanation: "实战黑车 d5 到 g5，红车吃到 g5，黑炮 b5 再隔着 c5 卒回吃。两辆车一起离场。c5 卒在这条线上不仅是一个兵卒，更是使回吃成立的炮架；没有它，不能照搬这条换车线。"),
                    StudyCheckpoint(ply: 36, title: "无车局面怎样活动",
                        prompt: "轮到红方。车都已离场，你现在更应关注哪枚马、哪门炮的活动？选择一手，同时指出对方已经活跃起来的棋子。",
                        focus: "红马 c2、g2，红炮 c4、i2；黑马 d5 已在河边，黑炮 g5 也活跃。两方兵卒数量少了，线路更空。",
                        explanation: "实战红马 g2 到 h4，从本方后排向河边加入；黑炮随后转到 h5，红炮再到 c6。无车以后，马的跳跃路线与炮架更直接决定活动能力，不能继续套用重车压线的判断。"),
                    StudyCheckpoint(ply: 55, title: "一条线里有两种角色",
                        prompt: "轮到黑方。红马和红炮已经指向你的一翼。你能设计一个有回吃保障的应对吗？不要只数当前谁被攻击，还要看第一次交换怎样改变炮架。",
                        focus: "红马 g6、红炮 g2；黑马 g7、黑炮 i8。g 路上红马既是进攻子，也可能成为红炮吃马所需的炮架。",
                        explanation: "实战黑炮 i8 到 g8。红炮隔着 g6 红马吃掉 g7 黑马后，g7 红炮又成为黑炮吃回 g6 红马的炮架。双方各少一马。这个节点练习动态炮架：第一口吃子会改变第二口能否成立。")
                ])],
            estimatedMinutes: 30, tags: ["系统研读", "完整实战", "局面判断", "炮架", "和棋"])
        lesson.guide = StudyGuide(
            level: "有实战基础 · 系统研究",
            reading: "这盘棋不是用一串将军快速结束，而是逐步改变子力关系。双方先各交换一车，剩下的车围绕兵线活动；再利用炮架完成最后一对车的交换，进入马炮为主的局面。读谱时每次只描述三类事实：谁更容易活动，哪里存在接触，哪枚棋子承担保护或炮架职责。不要把‘最后和棋’解释成每步都同样好，也不要因为没有立即获子就判断一手没意义。",
            questions: ["红车升起一格之后具体多了什么路线，哪些路线仍被同伴堵住？", "黑卒在 c5 时怎样参与炮的回吃？如果拿掉它，原换车构想还成立吗？", "没有车以后，红黑两匹马的活动差异应该怎样比较？", "炮架会在第一次吃子后怎样变化，为什么‘看见有炮架’仍不够？"],
            workflow: ["演示到每个停点，先列活动子、受限子和接触线，不急着评谁优势。", "从这些事实提出两手候选，为每手补一句对方最直接的反驳。", "落子并检查即时反馈；对照实战时只保留能由棋面说明的理由。", "在兑车和换马两个节点倒退重走，分别说出交换前后炮架的变化。", "关闭提示复测停点；如果选择不同但关系判断正确，继续验证而不是为了对谱改手。"],
            takeaway: "把局面判断落在活动、接触线和动态保护关系上；分数与历史赛果都不能替你解释棋面。")
        return lesson
    }

    private static var forcingCalculation: LearningLesson {
        var lesson = LearningLesson(
            id: "systematic-forcing-calculation", title: "把将军、吃子与后续回应算成一条线",
            stage: .tactics, order: 1020,
            summary: "研读许银川与吕钦的激烈中局：深入的黑马、被将的红帅、炮的交换和车的防守需要连续判断。",
            goal: "在具体威胁下，至少算清自己的候选、对手回应和自己的下一手，并区分强制应将与可选交换。",
            principle: "先识别必须处理的将军，再计算吃子后的新攻击；有将可将、有子可吃都不是自动指令。",
            whenToAdapt: "一方改变回吃方式、离开炮架，或将帅位置改变时，要从当前棋面重算，不能沿旧分支继续背。",
            pitfalls: ["只见黑马吃兵，不检查它下一跳是否带将。", "被将军时继续执行进攻计划。", "看见炮能吃子就停算，漏掉对手另一翼的吃马。"],
            sourceIDs: ["systematic-game-2010-xu-lv", "professional-png-middlegame", "professional-cctv-2016-cheng-xie", "professional-cctv-2015-xu-hong"],
            lines: [line(
                id: "systematic-2010-full", title: "许银川 对 吕钦 · 全局 49 回合",
                intent: "五个节点既有真实应将，也有带回吃的交换与主动防守；保留双方全局，避免把几步战术与此前准备割裂。",
                adaptation: "候选不必与实战一致，但回应计算必须合法。改变局面后，先分析自己的分支；返回实战只是继续阅读参考对局，不等于对手被迫这样走。",
                game: StudyGameMetadata(red: "许银川", black: "吕钦",
                    event: "2010 年第 16 届亚洲运动会象棋选拔赛男子组 · 第 1 轮",
                    date: "2010-03-10", result: "红胜", sourceURL: sources[2].url),
                raw: calculationMoves, checkpoints: [
                    StudyCheckpoint(ply: 31, title: "吃子后还威胁什么",
                        prompt: "轮到黑方。你的马能接近红方中央，但吃到东西只是第一步。选一手并算出红方回应后，你还有没有带节奏的后续。",
                        focus: "黑马 d6，红兵 e4，红马 f4、红帅 e0；e 路红炮在 e2。计算时逐一检查马腿，不能把两个马步直接连起来。",
                        explanation: "实战黑马 d6 吃到 e4；红马随后吃 g6 卒，黑马再到 d2，向 e0 帅将军。这里观察到‘吃兵—对方行动—带将深入’的连续关系，但第一手并非因为有后续就自动最优，仍应比较红方其他回应。"),
                    StudyCheckpoint(ply: 34, title: "先把当前威胁读准",
                        prompt: "轮到红方。先判断帅是否受攻击。列出合法的处理方式，再选择一手；落子前重新检查新的帅位，而不是只看进攻能否继续。",
                        focus: "黑马已到 d2，红帅在 e0，d1 没有棋子阻挡这条马腿。红方还有车 f3、炮 e2 和 c1，但应将必须真正解除攻击。",
                        explanation: "黑马 d2 正在将军。实战红帅 e0 到 e1，新的帅位避开这次马的攻击。后续黑车转 d 路、黑马又吃到 c0，说明解除眼前将军并不等于所有威胁消失；应将后要立即重看局面。"),
                    StudyCheckpoint(ply: 52, title: "一次交换改变两条线",
                        prompt: "轮到红方。黑炮刚进入你的阵地。若打算吃它，先说出所用炮架，再找黑方可能的回吃；交换后自己的车还可以做什么？",
                        focus: "黑炮 c2、黑马 a1；红炮 g2 与目标之间有 e2 红相这个炮架，另一红炮在 g1，红车在 h3。",
                        explanation: "实战红炮 g2 隔相吃 c2 黑炮，黑马 a1 再到 c2 回吃。红车随即 h3 到 c3，沿新打开的 c 路压住这匹马。这是炮的交换连着车的活动变化，不是单步白得黑炮。"),
                    StudyCheckpoint(ply: 59, title: "对手能吃，不等于整条线结束",
                        prompt: "轮到黑方。红炮与黑炮在同一列，红马又在河边。你的一手行动可能让对方得到吃炮机会；请把双方连续交换后的子力变化算完整。",
                        focus: "红炮 g1、黑炮 g8 之间目前有 g4 红兵和 g7 黑马，尚非可直接吃炮的单炮架。红马 h4、红车 c3 也要纳入连续交换。",
                        explanation: "实战黑马 g7 到 f5，让 g 路只剩 g4 红兵这个炮架，红炮于是 g1 吃到 g8；黑马再吃 h4 红马，红车转 h3，黑马随后退到 g6。因此红方吃炮和黑方吃马发生在不同位置，不能在第一口吃子时结束计算，也不把该交换直接评作黑方最佳。"),
                    StudyCheckpoint(ply: 80, title: "进攻之前保留防守",
                        prompt: "轮到红方。你有深入的兵，但自己的帅附近也有黑马和黑车。选一手能够说明攻守作用的棋，先指出它准备应付哪个具体威胁。",
                        focus: "红帅 f0、红车 h2、红兵 d6；黑马 d3 与 c2，黑车 b2，黑卒 d4。d3 黑马具备接近红方底线的跳跃路线。",
                        explanation: "实战红车从 h2 横到 d2，看住附近 d3 黑马，同时占据这匹马通往底线的 d2 马腿；车在 d2 也受到 e1 仕保护。随后红兵由 d6 横到 e6，车又返回 h2。可以学习车的防守位置与兵的推进要一起考虑，但不能把往返本身当成通用好手。")
                ])],
            estimatedMinutes: 40, tags: ["系统研读", "完整实战", "计算", "应将", "攻守转换"])
        lesson.guide = StudyGuide(
            level: "计算专题 · 3–5 半回合连续核验",
            reading: "本局的战术并不只发生在一条直线上。黑马从河边吃中央兵，再深入带将；红方一面应将，一面用车炮寻找活动。后来一次炮的交换改变 c 路压力，另一段变化则是一翼吃炮、另一翼吃马。学习时要把‘我吃了什么’改写为‘这条线走完双方分别少了什么、谁仍受攻击’。遇到真实将军先做应将筛选，遇到并非强制的局面则保留至少两个候选，避免把实战当作强制变化。",
            questions: ["黑马吃 e4 兵以后，怎样在红方回应之后形成带将的后续？哪一格马腿必须保持畅通？", "红帅应将后还有哪些子受威胁，为什么‘已解除将军’不等于安全无事？", "红炮吃 c2 黑炮后，黑马回吃怎样改变红车的活动目标？", "红炮吃 g8 与黑马吃 h4 应合起来怎样记账，车又能否参与后续？"],
            workflow: ["每个停点先检查是否被将；把不解决将军的候选直接排除。", "对每个剩余候选至少算‘我一手—对方回应—我再一手’，遇到连续交换就算到暂时平息。", "自己落子后看反馈，明确错误来自漏看攻击、马腿炮架，还是计算深度不足。", "退回错误前重新说出完整变化，再执行；不要只记住正确落点。", "在无提示检验中同时练红黑双方，最后对照实战与分析的分歧，保留不确定性。"],
            takeaway: "将军先解决，交换算完整；每一步都从新棋面复核，绝不把名手的历史选择当作免检答案。")
        return lesson
    }

    private static var endgameTransition: LearningLesson {
        var lesson = LearningLesson(
            id: "systematic-endgame-transition", title: "兑换不是终点：进入什么残局更重要",
            stage: .endgame, order: 1030,
            summary: "沿杨官璘与胡荣华的 86 回合实战，经历一对车、最后一对车、双方炮依次交换后的计划重建。",
            goal: "能够在交换之前描述交换后的子力、兵卒位置和将帅安全，并为新的残局制定连续计划。",
            principle: "是否兑换要看换完谁更容易做事；兵卒的作用取决于位置、同伴与将帅周围的关系，而不只取决于数量。",
            whenToAdapt: "重子减少、护卫被吃、卒进入九宫附近或马腿被打开时，重新检查防守任务；领先方与落后方都不能机械求简化。",
            pitfalls: ["把少子直接等同于简单，忽略马腿和将帅安全。", "认为兵多的一方必然更好，不看过河卒离帅的距离。", "黑胜就把每个早期兑换都倒推成必胜方案。", "看见谱的终点就说已将死；此局资料记录结束时仍有合法走法。"],
            sourceIDs: ["systematic-game-1979-yang-hu", "professional-chen-endgame"],
            lines: [line(
                id: "systematic-1979-full", title: "杨官璘 对 胡荣华 · 全局 86 回合",
                intent: "六次停点贯穿有车中局、无车马炮局和马兵卒残局；重点比较兑换前后的任务，不要求背下长谱。",
                adaptation: "历史黑胜不是所有早期简化都正确的证明。不同兑换方案要看新的子力与兵线；若对方不接受交换，计划也必须还能继续。",
                game: StudyGameMetadata(red: "杨官璘", black: "胡荣华", event: "1979 年全国象棋个人赛 · 北京",
                    date: "1979-09-13", result: "黑胜", sourceURL: sources[3].url),
                raw: endgameMoves, checkpoints: [
                    StudyCheckpoint(ply: 12, title: "第一次兑换要付出什么",
                        prompt: "轮到红方。你的车与黑车在同一路。若考虑交换，谁会回吃，双方接下来还能用哪些子继续行动？也提出一个暂不交换的想法。",
                        focus: "红车 h6、黑车 h9，黑马 g7 可以接近 h9；红方另一匹马 c2 还在后方。",
                        explanation: "实战红车 h6 吃 h9 黑车，黑马 g7 到 h9 回吃；红方接着 c2 马到 d4。少一对车同时改变了黑马的位置与红方出马节奏。这里只记录两者的联系，并不把早换车概括为天然稳健或天然吃亏。"),
                    StudyCheckpoint(ply: 72, title: "最后一对车要不要换",
                        prompt: "轮到红方。若继续简化，不能只说‘把车换了’。请先描述换完双方的轻子、兵卒与将帅护卫，再决定让车承担什么任务。",
                        focus: "红车 a9、红马 b8；黑车 d6、黑马 d4。红兵在 a5、c4、g4，黑卒在 e4、i4，黑炮仍在 f8。",
                        explanation: "实战红车 a9 到 a6，黑车 d6 吃到 a6，红马 b8 回吃。双方从各有一车进入马炮兵卒局；黑马仍在红方附近，不能因车被兑光就忽略近身威胁。是否接受这种简化需要看完整新局面，不能只看交换价值相等。"),
                    StudyCheckpoint(ply: 75, title: "刚换完，马上重看威胁",
                        prompt: "轮到黑方。车已全部离场。哪枚子现在最有条件继续行动？检查它能否吃到目标，以及吃完会给对方什么回应。",
                        focus: "黑马 d4 靠近红相 e2；红炮 d1、两仕 d2 与 e1，红马则在 a6。黑马和红帅附近的关系比远处兵的推进更紧迫。",
                        explanation: "实战黑马 d4 到 e2 吃相，红炮随后从 d1 转到 b1，黑马再到 g3。兑车没有让攻击关系归零：黑马在近处的活动立刻影响红方护卫，而红方也重新安排炮的路线。"),
                    StudyCheckpoint(ply: 105, title: "第二次简化的准备",
                        prompt: "轮到黑方。双方各剩一炮。能否用一个带威胁的调动改善它的位置，并让未来的交换有接应？至少算到红方防守后自己的下一手。",
                        focus: "黑炮 e3、黑卒 c4 与 h4；红帅 d0，红仕 d2，红炮 b1。炮一旦进入 d 路，必须重新数它到帅之间的棋子。",
                        explanation: "实战黑炮 e3 到 d3，隔着 d2 红仕将军。红炮 b1 到 d1 挡住，黑卒 c4 到 c3；红炮再隔仕吃 d3 黑炮时，黑卒能 c3 到 d3 回吃。双方炮退出后进入马兵卒残局。先有将军与兵的接应，才出现这个交换过程，并非所有应法都被强制成同一条线。"),
                    StudyCheckpoint(ply: 113, title: "兵卒往哪里走才有任务",
                        prompt: "轮到黑方。双方都在调动兵卒，不能只比较推进速度。你想让哪个卒与现有马、卒形成联系？说明选择的目标区域，而不是只说向前走。",
                        focus: "黑卒 h4、d3，黑马 f3；红帅 d0、两仕 d2 与 e1。红兵虽有三个，但在 b5、f6、g7，离双方将帅的作用不同。",
                        explanation: "实战黑卒 h4 横到 g4，后来经 f4 到 e4，再向 e3、e2 前进；这让原本远侧的卒逐渐靠近中路和另一卒。它与直接向底线推进是不同计划。红方同期也推进 b 路兵，所以仍要比较两边行动的实际效果，不能把兵数当作结论。"),
                    StudyCheckpoint(ply: 145, title: "两卒怎样分工",
                        prompt: "轮到黑方。两卒已经接近红帅，但彼此也可能挡住马腿。选一手调整它们的分工，逐项检查对红仕、帅位和马路线的影响。",
                        focus: "黑卒 d2、d1，黑马 d3；红帅 e0、红仕 e1 与 f0。d2 正好也在黑马向红方底线跳跃所需的一条马腿上。",
                        explanation: "实战后卒 d2 横到 e2，开始压住 e1 仕，同时腾开 d2 马腿；前卒随后有机会从 d1 横入 e1。这里能直接核对‘卒的攻击＋马腿变化＋九宫内空间’三件事。完整记录后来黑胜，但这一手不被标成已证的强制杀法。")
                ])],
            estimatedMinutes: 45, tags: ["系统研读", "完整实战", "残局转化", "兑换", "马兵残局"])
        lesson.guide = StudyGuide(
            level: "转换专题 · 比较交换后的局面",
            reading: "这盘长棋谱最值得观察的不是某个神奇残局招式，而是三次变化：开局各少一车，中局最后一对车退出，后期两炮又交换。每一次，双方棋子的任务都会重写。进入无车局面后黑马仍贴近红方，进入马兵卒残局后红兵虽然多，黑卒却更接近红帅并逐渐与马发生联系。请把历史黑胜仅当作资料记载，不要反过来给所有黑方选择贴上最优标签；训练应围绕每个节点的真实攻守关系。",
            questions: ["换车后黑马的位置与红方护卫发生了什么变化，是否需要先处理近身威胁？", "两炮交换之前，黑方怎样同时利用将军与卒的接应？如果红方不按实战挡将，还能硬套同一变化吗？", "红方兵多、黑卒靠近帅，这两种特点各有什么实际意义，还需要哪些信息才能判断好坏？", "d2 卒离开时，除了卒自身的攻击范围，还改变了哪匹马的路线？"],
            workflow: ["先快速浏览完整对局，记下第一次兑车、最后一次兑车、兑炮三个分界，不背走法。", "在每个分界停住，列交换后双方剩子与最紧迫的任务，再选择自己的候选。", "完成六个决策节点；计算交换必须包括回吃，兵卒调动必须说出同伴和目标区域。", "把错误节点倒退重做，并口述如果对手拒绝交换，自己的计划还怎样继续。", "最后在无提示模式重复关键节点，从实际独立判断评价进步，而不是以记住 86 回合为目标。"],
            takeaway: "先问‘换完进入什么局面’，再决定换不换；残局计划来自兵卒位置、护卫和马腿等具体联系。")
        return lesson
    }

    private static let openingMoves = """
    h2e2 h9g7 h0g2 i9h9 i0h0 g6g5 h0h6 b9c7 c3c4 h7i7 h6g6 i7i8
    b0c2 d9e8 c2d4 i8g8 g6f6 c9e7 d4c6 g7h5 b2c2 g8g3 g0i2 g5g4
    f6f5 g3h3 a0b0 b7b3 c4c5 b3c3 d0e1 g4g3 g2h0 h5g7 f5f8 c3c6
    c5c6 a9b9 b0b9 c7b9 c2c3 h9h5 c3g3 g7f5 g3g1 f5d4 h0g2 g9i7
    f8f4 d4c6 e2e6 b9d8 e6e4 h3a3 f4f6 a3a0 c0e2 h5d5 g2f4 d5d4
    f4g6 e9d9 e4h4 d8e6 e1d2 d4d2 f6e6 c6b4 e6b6 b4c2 b6b9 d9d8
    h4h8 e8f7 b9b8 d8d9 g6e7
    """

    private static let positionMoves = """
    b0c2 c6c5 g3g4 b9c7 h0g2 a9a8 h2i2 h9g7 i0h0 i9h9 h0h6 h7i7
    h6h9 g7h9 a0a1 a8d8 c0e2 h9g7 a1f1 g9e7 b2b0 d8d5 b0c0 g6g5
    f1b1 b7b5 b1b4 g5g4 b4g4 d5g5 g4g5 b5g5 c3c4 c5c4 c0c4 c7d5
    g2h4 g5h5 c4c6 i7i3 c6i6 d5f4 d0e1 a6a5 i6i4 f4h3 e0d0 f9e8
    i2g2 h5d5 a3a4 a5a4 i4a4 i3i8 h4g6 i8g8 g2g7 g8g6 a4a1 e6e5
    d0e0 h3f4 g7h7 g6h6 c2b4 d5d4 h7g7 d4d6 a1a4 f4h3 a4a1 h6e6
    b4c2 h3g5 a1a5
    """

    private static let calculationMoves = """
    h2e2 h9g7 h0g2 i9h9 i0h0 b9c7 g3g4 c6c5 b0a2 a6a5 b2c2 c7b5
    a0a1 c9e7 h0h6 a9a6 a1d1 h7i7 h6h9 g7h9 c2c1 h9g7 e3e4 f9e8
    d1d3 b7d7 g2f4 c5c4 c3c4 b5d6 d3f3 d6e4 f4g6 e4d2 e0e1 a6d6
    c4c5 i7h7 f3h3 d2c0 e2b2 d6b6 b2g2 h7i7 g0e2 c0a1 e1e0 i7i8
    c1g1 d7c7 c5d5 c7c2 g2c2 a1c2 h3c3 b6b2 e2c0 i8g8 g6h4 g7f5
    g1g8 f5h4 c3h3 h4g6 h3h2 e6e5 f0e1 e5e4 g4g5 e7g5 g8g5 g9e7
    g5a5 e4d4 a3a4 g6f4 d5d6 f4d3 e0f0 e8f9 h2d2 f9e8 d6e6 e7c9
    d2h2 d3f4 a5e5 e9f9 a4a5 b2b6 h2c2 b6e6 c2f2 d4e4 e5b5 f9e9
    a2c3
    """

    private static let endgameMoves = """
    h2e2 h9g7 h0g2 i9h9 i0h0 g6g5 h0h6 b9c7 c3c4 d9e8 b0c2 h7i7
    h6h9 g7h9 c2d4 h9g7 d4c6 b7b3 e3e4 c9e7 a3a4 b3c3 c6b4 c3i3
    g2i3 i7i3 a0b0 c7d5 b4c6 a9c9 b2c2 d5c3 c6b8 i3i4 c0a2 g5g4
    g3g4 i4e4 f0e1 g7f5 e0f0 c3e2 g0e2 c9a9 a2c0 f5d4 c2a2 e4f4
    f0e0 f4f8 b8a6 a9d9 b0b3 e8f7 a2a3 f9e8 a4a5 d9d7 e1d2 i6i5
    d0e1 i5i4 a3a1 e6e5 a1d1 e5e4 b3b9 e8d9 a6b8 d7d6 b9a9 f7e8
    a9a6 d6a6 b8a6 d4e2 d1b1 e2g3 g4g5 e4d4 c4c5 i4h4 c5d5 f8i8
    g5g6 i8i0 d5d6 i0c0 a6c5 d4c4 b1b9 e7c9 c5b7 e9f9 d6e6 c0c3
    g6g7 c3e3 e0d0 g3e2 e6f6 g9e7 b7d6 e2g1 b9b1 e3d3 b1d1 c4c3
    d1d3 c3d3 d6c4 g1f3 a5b5 h4g4 d0d1 g4f4 b5b6 f4e4 b6c6 e4e3
    e1f0 e3e2 d2e1 f3d4 c6d6 d3c3 d6e6 c3c2 d1d0 c2c1 c4a3 e7c5
    g7g8 c9e7 g8h8 d4f3 a3c2 f3e5 h8g8 e5d3 e6d6 e2d2 c2a1 c1d1
    d0e0 d2e2 a1c2 d3c1 c2d4 d1e1 e0d0 e1f1 d0d1 c1d3 d6e6 d3b2
    d4c2 b2c4 c2a1 e2d2 d1d0 c4e3 d0e0 d2d1 a1c0 e3g2 f0e1 f1e1
    c0e1 d1e1 e0d0 g2e3
    """

}
