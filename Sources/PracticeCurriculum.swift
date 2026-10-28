import Foundation

/// Original, deliberately small training positions. Sources inform topic coverage,
/// not the diagrams or move annotations. Lines marked as demonstrations do not claim
/// that every reply is forced or that the scripted first move is uniquely best.
enum PracticeCurriculum {
    static let sources: [LearningSource] = [
        LearningSource(id: "practice-cxa", title: "中国象棋协会：13–16级棋手技术等级评测标准（试行）",
                       url: "https://www.sport.gov.cn/qpzx/n27319064/n27319090/c27432106/content.html",
                       note: "用于核对入门知识与基本杀法覆盖；本课程不是协会等级认证，训练局面为原创。"),
        LearningSource(id: "practice-mates", title: "Xiangqi.com：教练署名的基本杀法讲解",
                       url: "https://www.xiangqi.com/articles/checkmate-strategies",
                       note: "David Kwan、Jason Chi、Jenny Yan 的主题讲解，用于核对车马炮和将帅配合概念；未复制原文棋图或题目。"),
        LearningSource(id: "practice-endings", title: "Johnny Chen：象棋残局的十项原则",
                       url: "https://www.xiangqi.com/articles/ten-most-important-chinese-chess-endgame-principles",
                       note: "用于讨论兵、将帅与炮架的作用；文中的一般规律不能替代具体局面计算，本课程不照搬绝对子力排序。")
    ]

    private static func fen(_ placement: String, side: Side = .red) -> String {
        var position = Position(board: Array(repeating: nil, count: 90), sideToMove: side)
        for token in placement.split(separator: " ") {
            let text = String(token)
            guard let symbol = text.first, let piece = Piece(fenCharacter: symbol),
                  let square = Square(coordinate: String(text.dropFirst())) else {
                preconditionFailure("Invalid original training placement: \(token)")
            }
            precondition(position[square] == nil, "Duplicate training square: \(token)")
            position[square] = piece
        }
        return position.fen
    }

    private static func line(_ id: String, _ title: String, _ placement: String,
                             intent: String, adapt: String, moves: [StudyMove]) -> StudyLine {
        StudyLine(id: "practice-" + id, title: title, intent: intent, adaptation: adapt,
                  startingFEN: fen(placement), studentSide: .red, moves: moves)
    }

    private static let prerequisites: [String: [String]] = [
        "practice-check-response": ["practice-protect"],
        "practice-capture-count": ["practice-protect", "practice-check-response"],
        "practice-cannon-screen": ["practice-capture-count"],
        "practice-horse-leg": ["practice-check-response"],
        "practice-check-gain": ["practice-capture-count", "practice-horse-leg"],
        "practice-double-attack": ["practice-check-gain"],
        "practice-pins": ["practice-cannon-screen", "practice-check-response"],
        "practice-rook-horse": ["practice-horse-leg", "practice-check-gain"],
        "practice-rook-cannon": ["practice-cannon-screen", "practice-pins"],
        "practice-single-rook": ["practice-check-response", "practice-rook-horse"],
        "practice-double-rook": ["practice-single-rook"],
        "practice-pawn-role": ["practice-single-rook"],
        "practice-exchange": ["practice-capture-count", "practice-pawn-role"],
        "practice-defense": ["practice-check-response", "practice-cannon-screen"],
        "practice-plan-activity": ["practice-protect", "practice-horse-leg", "practice-cannon-screen"],
        "practice-plan-priority": ["practice-check-response", "practice-plan-activity"],
        "practice-condition-change": ["practice-capture-count", "practice-plan-priority"],
        "practice-advanced-remove-guard": ["practice-check-gain", "practice-pins"],
        "practice-advanced-induction": ["practice-double-attack", "practice-condition-change"],
        "practice-advanced-turning": ["practice-plan-priority", "practice-defense"],
        "practice-advanced-transition": ["practice-exchange", "practice-pawn-role"],
        "practice-advanced-pawn-block": ["practice-pawn-role", "practice-single-rook"],
        "practice-advanced-coordination": ["practice-rook-cannon", "practice-advanced-transition"]
    ]

    static let lessons: [LearningLesson] = [
        LearningLesson(id: "practice-protect", title: "先找没保护的棋子", stage: .foundation, order: 10,
            summary: "同样遇到攻击，可以撤离，也可以补保护。", goal: "落子前说清哪枚子正被攻击、有没有可靠保护。",
            principle: "看攻击线，再比较撤、护、吃掉来攻子；保护是否有效要算对手硬吃后的结果。",
            whenToAdapt: "对手改打另一枚子，或保护子被牵制时，重新数一遍攻守关系。",
            pitfalls: ["只盯着自己想走的子。", "看到有保护就不算对手接着吃什么。"], sourceIDs: ["practice-cxa"], lines: [
                line("protect-retreat", "没有接应，先把马移开", "Ke0 kd9 Nc3 ra3",
                     intent: "黑车正在横向攻击红马；练识别当下威胁，不把保住马解释成整盘获胜。",
                     adapt: "如果落点仍受攻击，就重新找安全落点；本题不要求记住固定马步。",
                     moves: [StudyMove("c3d5", "马离开黑车的横线，先保住这枚子。", hint: "看黑车所在横线；马能离开这条线吗？")]),
                line("protect-support", "补上保护，再看硬吃的后果", "Ke0 kd9 Nc3 ra3 Rb1 ae8 af9 bc9 bg9",
                     intent: "演示加保护后，对手仍硬吃的交换结果；黑方硬吃是教学示例，不是最佳应手。",
                     adapt: "对手不吃马时，不要替对手假定交换已经发生；继续改善马的位置。",
                     moves: [StudyMove("b1c1", "车转到马的后方，沿直线接应它。", hint: "哪一条直线能让车保护马？"),
                             StudyMove("a3c3", "示例：黑车仍吃马，红方应兑现刚建立的保护。", hint: "检查马被吃后，谁能接着吃车。"),
                             StudyMove("c1c3", "红车回吃黑车，交换的是马与车，而不是白丢一马。", hint: "沿刚建立的保护线回吃。")])
            ], tags: ["护子", "逃子", "攻守关系"]),

        LearningLesson(id: "practice-check-response", title: "被将军时先解决将军", stage: .foundation, order: 20,
            summary: "分别练吃掉将军子和用有保护的棋子挡住攻击线。", goal: "应将后再次确认帅不受攻击。",
            principle: "应将可以移帅、吃子或挡线；选择后仍要检查新棋面。",
            whenToAdapt: "马将不能像车将那样随便塞一枚子；双将时尤其要检查全部攻击。",
            pitfalls: ["被将时继续走原定计划。", "挡住将军，却把挡子白送给对手。"], sourceIDs: ["practice-cxa"], lines: [
                line("check-capture", "将军子没有保护，可以直接吃", "Ke0 kd9 re1",
                     intent: "红帅已被黑车将军；黑车没有保护，红帅可直接吃掉。",
                     adapt: "若黑车后方另有保护，先验证帅吃过去是否仍安全。",
                     moves: [StudyMove("e0e1", "帅吃掉近处的车，新的帅位没有受到攻击。", hint: "先问这辆将军的车有没有保护。")]),
                line("check-block", "有保护的挡车可以换掉进攻车", "Ke0 kd9 re7 Ra1",
                     intent: "用车挡将，并演示黑车换车时红帅能回吃。",
                     adapt: "黑车撤退时，挡将目标已经完成，不必继续追着它换。",
                     moves: [StudyMove("a1e1", "车挡在攻击线上，而且受到帅的保护。", hint: "找一个既能挡线、又靠近帅的位置。"),
                             StudyMove("e7e1", "示例：黑车选择交换挡将的红车。", hint: "交换后检查红帅能否回吃。"),
                             StudyMove("e0e1", "帅回吃，双方的车一起退出棋盘，危机解除。", hint: "用保护子完成回吃。")])
            ], tags: ["应将", "挡将", "回吃"]),

        LearningLesson(id: "practice-capture-count", title: "吃子前多算一次回吃", stage: .foundation, order: 30,
            summary: "区别直接获子和包含回吃的交换。", goal: "至少算到对手回应与自己的下一次回吃。",
            principle: "被保护不等于不能吃；关键是完整交换后双方各少了什么。",
            whenToAdapt: "出现将军、牵制或炮架变化时，静态数子不够，要重新验证走法。",
            pitfalls: ["能吃就吃。", "只算第一步赚了什么，不算自己下一步损失。"], sourceIDs: ["practice-cxa"], lines: [
                line("capture-free", "先认出真正无保护的目标", "Ke0 kd9 Ra2 nc2",
                     intent: "在没有其他干扰的简化棋面中，确认黑马没有回吃保护。",
                     adapt: "多一枚车或炮就可能改变答案；不要把这张图的走法套到所有图。",
                     moves: [StudyMove("a2c2", "车吃马后，没有黑子能立即回吃红车。", hint: "沿车的横线看目标，再找目标背后的保护。")]),
                line("capture-recapture", "对方有回吃，自己也有接应", "Ke0 kd9 Ra2 nc2 rc7 Ne3",
                     intent: "示范一条三手交换线：先吃马，黑车回吃后红马再吃车。",
                     adapt: "黑车不回吃时，红方已吃到马；接着按新局面思考，不强行走第三手。",
                     moves: [StudyMove("a2c2", "先吃马，并已确认红马能够接着回吃黑车。", hint: "别停在黑车回吃这一层，再看红马。"),
                             StudyMove("c7c2", "示例：黑车沿直线回吃红车。", hint: "红马到目标格的马腿是否畅通？"),
                             StudyMove("e3c2", "马回吃黑车，这条变化走完后红方仍保留一马。", hint: "把交换的双方棋子逐一划掉，再比较。")])
            ], tags: ["将吃判断", "交换计算"]),

        LearningLesson(id: "practice-cannon-screen", title: "炮的关键是中间那枚子", stage: .foundation, order: 40,
            summary: "练建立炮架与移走炮架，理解炮的攻防会随一枚子的移动改变。", goal: "每次炮吃子前准确数中间的棋子。",
            principle: "炮吃目标时中间恰好隔一枚子；挡子属于哪一方并不重要。",
            whenToAdapt: "炮架移动、被吃或多了一枚挡子时，重新计算整条线。",
            pitfalls: ["把炮当车使用。", "移动自己的子后，忘记它原来是对方的炮架。"], sourceIDs: ["practice-cxa"], lines: [
                line("cannon-build", "建立炮架，也要保护炮架", "Ke0 ke9 Cc2 Ra4 Ne3 rc7 ad9 af9 bc9 bg9 pe6",
                     intent: "马进入炮线形成炮架，而且有车保护；炮架被吃后，回吃由车完成，不是无架的炮。",
                     adapt: "黑车离开这条线时，炮的目标也消失，需要重新选择目标。",
                     moves: [StudyMove("e3c4", "马成为炮架，使炮威胁黑车；红车同时保护这枚炮架。", hint: "建立炮架之后，再问炮架自己有没有保护。"),
                             StudyMove("c7c4", "示例：黑车吃掉炮架，红炮已不能无架回吃。", hint: "黑车与红炮之间现在还有多少枚子？"),
                             StudyMove("a4c4", "车回吃黑车，这条示例变化用马换到了车；炮与炮架的保护者分工不同。", hint: "炮架消失后，换哪枚保护子完成回吃？")]),
                line("cannon-remove", "被炮将军，移走它的炮架", "Ke0 kd9 ce7 Ne3",
                     intent: "红马是黑炮唯一的炮架，移走后黑炮无法直接攻击帅。",
                     adapt: "马落点若另成炮架或暴露车将，就要换一个应将办法。",
                     moves: [StudyMove("e3c4", "马离开中线，黑炮与帅之间变成零枚挡子，将军解除。", hint: "谁在替黑炮当炮架？")])
            ], tags: ["炮架", "应将", "条件变化"]),

        LearningLesson(id: "practice-horse-leg", title: "让自己的马能走，让对方的马受限", stage: .foundation, order: 50,
            summary: "从疏通马腿和挡住马腿两个方向认识马的活动。", goal: "说出目标马步对应哪一格马腿。",
            principle: "马的跳跃取决于第一步直行格是否被占；同一匹马的不同方向可能分别受限。",
            whenToAdapt: "挡腿子一移动，要重新检查此前不能走的马步和此前不存在的马将。",
            pitfalls: ["以为马能随便跳过中间的子。", "为了出马乱动保护帅的关键棋子。"], sourceIDs: ["practice-cxa"], lines: [
                line("horse-free", "先疏通自己的马腿", "Ke0 kd9 Nb0 Rb1 ae8 af9 bc9 bg9",
                     intent: "用一次车的调动同时给马让路，随后练习出马。",
                     adapt: "若对方制造直接威胁，先处理威胁，不保证必须按三手顺序出马。",
                     moves: [StudyMove("b1e1", "车离开马前方，给马让出直行的第一格。", hint: "马去河口前，第一格被谁占着？"),
                             StudyMove("d9d8", "黑将向前移动，红方继续检查原计划是否成立。", hint: "黑方这步有没有新威胁？"),
                             StudyMove("b0c2", "马腿畅通后再跳出，活动范围扩大。", hint: "刚刚腾出的格子让哪一步马能走了？")]),
                line("horse-block", "挡马腿也能解除马将", "Ke0 kd9 nd2 Ra1 ae8 af9 bc9 bg9",
                     intent: "红帅被马将军；车进入马腿格，令这次攻击失效。",
                     adapt: "挡在马的目标格附近未必有效，必须找到那次跳跃的直行第一格。",
                     moves: [StudyMove("a1d1", "车塞住黑马向下的马腿，黑马不能再跳到帅的位置。", hint: "从黑马到帅，先直走哪一格？")])
            ], tags: ["马腿", "子力活动"]),

        LearningLesson(id: "practice-check-gain", title: "用将军争取吃子的时间", stage: .tactics, order: 10,
            summary: "练移开挡子形成将军，以及马同时攻击将和车。", goal: "先确认将军真实成立，再看额外攻击能否兑现。",
            principle: "将军要求对方先应将，因此第二个攻击目标可能来不及逃。",
            whenToAdapt: "对手能吃掉将军子、挡住马腿或用一次应将保护目标时，不能机械宣称获子。",
            pitfalls: ["只看到吃子，忽略将军来自另一枚子。", "认为所有带将军的走法都好。"], sourceIDs: ["practice-mates"], lines: [
                line("checkgain-discovered", "马吃车，同时让开车的将军线", "Kf0 ke9 Re2 Ne5 rc6",
                     intent: "红马吃车的同时离开中线，红车开始将军。",
                     adapt: "原攻击线上若还有另一枚挡子，移马未必形成将军。",
                     moves: [StudyMove("e5c6", "马吃黑车并让开中线，身后的红车同时将军。", hint: "哪枚红子挡住了自己车的攻击？"),
                             StudyMove("e9d9", "黑将必须先离开车线，无法处理刚到位的红马。", hint: "只列出能解除车将的回应。")]),
                line("checkgain-fork", "马将军，另一头瞄住车", "Kd0 ke9 Ne5 rg9",
                     intent: "同一马步同时攻击黑将与黑车，练算应将后的兑现。",
                     adapt: "若对手能够吃马或堵住马腿，应先处理这种回应；本图没有那样的救援子。",
                     moves: [StudyMove("e5f7", "马同时攻击黑将和黑车，黑方先应将。", hint: "找一格能同时跳到将与车的马位。"),
                             StudyMove("e9e8", "黑将避开马将，黑车仍在马的攻击范围内。", hint: "回应后重新看车的位置。"),
                             StudyMove("f7g9", "马吃车，把双重攻击转化为实际获子。", hint: "将军已经结束，现在兑现另一个目标。")])
            ], tags: ["抽将", "将军获子", "双攻"]),

        LearningLesson(id: "practice-double-attack", title: "一步制造两个要处理的目标", stage: .tactics, order: 20,
            summary: "双攻不一定带将军，必须观察对手能否同时解救。", goal: "识别两个目标，并算至少一种防守回应。",
            principle: "真正的双攻需要对手难以一手同时撤离、保护或反击两个目标。",
            whenToAdapt: "对手能反将、吃掉攻击子或把两个目标连成保护关系时，重新计算净收益。",
            pitfalls: ["攻击两个子就立刻宣称赢棋。", "忽略以小换大后仍可能处于劣势。"], sourceIDs: ["practice-cxa"], lines: [
                line("fork-rook", "车进入两枚子之间的横线", "Ke0 kd9 Rb1 na4 ch4 ae8 af9 bc9 bg9",
                     intent: "车横向同时威胁马和炮，演示对手移马后吃炮。",
                     adapt: "对手若移炮，应重新检查吃马；不是照着固定第三手走。",
                     moves: [StudyMove("b1b4", "车上到同一横线，同时看住黑马和黑炮。", hint: "两枚黑子是否在同一横线上？"),
                             StudyMove("a4b6", "示例：黑方先移开马，另一头的炮还留在原处。", hint: "对手保护了哪个目标，留下了哪个？"),
                             StudyMove("b4h4", "车吃掉仍在横线上的炮。", hint: "重新确认这段横线中间没有挡子。")]),
                line("fork-horse", "用马同时攻击两辆车", "Kf0 kd9 Nc4 rc6 rg6",
                     intent: "演示黑车互相接应后的交换；红方可用马换车，但不代表原本劣势已经变成赢棋。",
                     adapt: "两车能互保时，要按车与马的实际交换评估，不能说两辆车都能吃到。",
                     moves: [StudyMove("c4e5", "马来到同时攻击两辆车的位置。", hint: "找一个到两辆车都能走马步的交点。"),
                             StudyMove("c6e6", "黑方把一辆车移开并保护另一辆，限制红方获利。", hint: "对手不仅逃子，还建立了什么保护？"),
                             StudyMove("e5g6", "红马吃车，接受用马换一辆车的结果。", hint: "别忘了计算随后可能的回吃。"),
                             StudyMove("e6g6", "黑车回吃马；这条变化是车换马，不能称为整盘必胜。", hint: "把双方损失写出来再评价。")])
            ], tags: ["双攻", "交换收益"]),

        LearningLesson(id: "practice-pins", title: "被挡住的攻击线也能产生约束", stage: .tactics, order: 30,
            summary: "认识车线和炮线背后的将帅安全。", goal: "说出某枚防守子为什么不能随便离开。",
            principle: "一枚子看似可以走，但离开后若暴露自己的将，就失去自由。",
            whenToAdapt: "将已离线、炮架数量改变或进攻子被换掉，原来的约束就可能失效。",
            pitfalls: ["把牵制当作永久状态。", "忘记炮线需要数挡子，而不是只看直线。"], sourceIDs: ["practice-mates"], lines: [
                line("pin-rook", "车线上的马不能随便逃", "Kf0 ke9 Re2 ne7",
                     intent: "马夹在车与将之间，红车可以沿线吃马并将军。",
                     adapt: "若马受到别的子保护，仍要算车吃过去能否被回吃。",
                     moves: [StudyMove("e2e7", "车沿线吃马，继续保持对黑将的攻击。", hint: "马身后的棋子是谁？"),
                             StudyMove("e9d9", "黑将避开车线；红方已把约束转化为获子。", hint: "将离开之后，原来的牵制关系已改变。")]),
                line("pin-cannon", "两枚挡子使炮线上的子互相受限", "Kf0 ke9 Ce2 ne6 ae8 bc9 Ra4",
                     intent: "炮前有马和士两枚挡子，任意一枚单独离线都会留下一个炮架。",
                     adapt: "黑将先离开中线即可解除约束；因此进攻要看回应，不把牵制视为永远存在。",
                     moves: [StudyMove("a4a6", "车对准被炮线约束的马，制造具体压力。", hint: "马若跳开，炮与将之间还剩几枚子？"),
                             StudyMove("e9d9", "黑将离开炮线，让原先被约束的子恢复活动。", hint: "哪一类王的移动会解除整条线的约束？"),
                             StudyMove("a6e6", "趁目标仍在原处吃马；之后不能再假定中线仍有牵制。", hint: "按新棋面确认横线畅通与目标保护。")])
            ], tags: ["牵制", "炮线", "条件变化"]),

        LearningLesson(id: "practice-rook-horse", title: "车和马分工：一个将军，一个封路", stage: .tactics, order: 40,
            summary: "用两种不同分工完成已经形成的短杀局面。", goal: "逐格解释黑将为什么不能逃、不能吃进攻子。",
            principle: "配合的价值在于覆盖不同逃路与保护关键落点。",
            whenToAdapt: "马腿被挡、保护子被换或将的位置改变时，原来的杀法就要重算。",
            pitfalls: ["只看到将军，没检查将能否吃掉进攻子。", "背一个马位，却不看它控制的格子。"], sourceIDs: ["practice-mates"], lines: [
                line("mate-rook-horse", "马保护车的落点并封住一侧", "Kd0 ke9 Ra8 Ng7",
                     intent: "红车进入受马保护的位置，配合红帅封线完成一步将死。",
                     adapt: "移走马或挡住马腿后，车贴近将可能被吃；先核对保护条件。",
                     moves: [StudyMove("a8e8", "车将军，马保护车并控制侧逃格，红帅限制另一侧，黑将无合法回应。", hint: "找一个马能保护、又能直接将军的车位。")]),
                line("mate-horse-rook", "马负责将军，车与帅封住出口", "Ke0 kf9 Rh8 Nc6",
                     intent: "车封住向前的出口，帅限制侧逃，马的一跳完成最后的将军。",
                     adapt: "车一旦离开横线或直线，黑将就可能从原来被封的格子逃走。",
                     moves: [StudyMove("c6d8", "马在马腿畅通的位置将军，车与帅封住其余出口，形成将死。", hint: "先找车封住的格子，再检查将军马步的马腿。")])
            ], tags: ["车马配合", "一步杀"]),

        LearningLesson(id: "practice-rook-cannon", title: "车炮配合要数炮架与逃路", stage: .tactics, order: 50,
            summary: "分别练发现炮将和车将时炮封逃路。", goal: "把将军来源、炮架和控制格分别讲清。",
            principle: "车能直接控制直线，炮借一个炮架控制另一条线。",
            whenToAdapt: "炮架能被对手移走或吃掉时，不能只凭图形宣布将死。",
            pitfalls: ["用错炮架数量。", "看见车炮靠近将就认定有杀。"], sourceIDs: ["practice-mates"], lines: [
                line("mate-discovered-cannon", "移车后留下唯一炮架", "Kd0 ke9 Ce2 Ne6 Re5",
                     intent: "车移开后炮借红马将军，车与帅分别限制侧逃。",
                     adapt: "多一枚可用的黑防守子，可能挡线或吃炮架；本题结论仅对当前局面成立。",
                     moves: [StudyMove("e5f5", "车让开炮线又封住侧路，炮借马将军，黑将无处可走。", hint: "移车后，中线要恰好剩一枚炮架。")]),
                line("mate-rook-cannon", "车封底线，炮控制向前的出口", "Kf0 ke9 Ca8 Pc8 Rh7",
                     intent: "兵提供炮架，炮控制将向前的格子，车负责横向将军。",
                     adapt: "炮架不在原位时，要重新检查向前的出口是否还被控制。",
                     moves: [StudyMove("h7h9", "车在底线将军，炮借兵控制向前的出口，形成将死。", hint: "黑将向前的格子由谁控制？")])
            ], tags: ["车炮配合", "炮架", "一步杀"]),

        LearningLesson(id: "practice-single-rook", title: "单车收尾：帅封一线，车封另一线", stage: .endgame, order: 10,
            summary: "不仅移动车，也让帅参与限制对方将的活动。", goal: "在简化局面中说明将帅照面规则如何帮助进攻。",
            principle: "安全条件允许时，用帅限制相邻路线，车控制将所在的直线。",
            whenToAdapt: "加入其他攻击子后，主动露帅可能不安全；先排除对手将军和反击。",
            pitfalls: ["始终让帅停在原地。", "车贴将却没有保护，反被吃掉。"], sourceIDs: ["practice-endings", "practice-mates"], lines: [
                line("mate-single-rook", "帅已占好位置，车直接封线", "Ke0 kd9 Ra7",
                     intent: "红帅限制将向中路逃，车从远处控制黑将所在直线。",
                     adapt: "将若不在边侧宫线，先建立限制，不能无条件重复这一车步。",
                     moves: [StudyMove("a7d7", "车远距离将军并控制前进格，红帅限制侧逃，形成将死。", hint: "黑将的两个出口，哪一个已经被帅限制？")]),
                line("mate-king-first", "先调帅，等将选择后再落车", "Kf0 kd8 Ra6",
                     intent: "先建立帅的限制；示范黑将退回后如何完成收尾。",
                     adapt: "黑将若向前走，按新的将位重新检查车要控制哪一条线。",
                     moves: [StudyMove("f0e0", "帅进入能限制对方横向移动的直线。", hint: "哪条空直线能让帅参与封路？"),
                             StudyMove("d8d9", "示例：黑将退回底线，红方重新确认出口。", hint: "将的位置变了，哪些逃路仍受限制？"),
                             StudyMove("a6d6", "车控制将所在直线，帅封住侧路，完成将死。", hint: "车不必贴将，远处也能封整条线。")])
            ], tags: ["单车", "将帅协作", "收尾"]),

        LearningLesson(id: "practice-double-rook", title: "双车收尾：分层封锁，不挤在一起", stage: .endgame, order: 20,
            summary: "一辆车限制前进，另一辆车将军；也练先建立封锁再收尾。", goal: "给两辆车分别指派任务。",
            principle: "两辆车控制相邻层次时，能够把对方将的活动压缩到很小。",
            whenToAdapt: "两车挤在同一条线上，或其中一辆被攻击时，要先保持相互配合。",
            pitfalls: ["两辆车都追着将走。", "没数出口就急着将军。"], sourceIDs: ["practice-mates"], lines: [
                line("mate-double-rook", "第一辆车封路，第二辆车将军", "Ke0 kf9 Ra8 Rb7",
                     intent: "先看已有的封锁，再找另一辆车的将军位置。",
                     adapt: "控制前进格的车不能随意移开，否则最后一格逃路会重新出现。",
                     moves: [StudyMove("b7b9", "一车控制底线，另一车控制下一横线，黑将无合法回应。", hint: "负责封路的那辆车已经到位，动另一辆。")]),
                line("mate-double-rook-setup", "先建立下一横线的封锁", "Kd0 ke9 Ra7 Rb6",
                     intent: "先用一辆车压缩活动范围，等将移动后由另一辆收尾。",
                     adapt: "对方若有其他子可挡或可吃车，需要重新计算；这是裸将简化练习。",
                     moves: [StudyMove("a7a8", "先封住将向前的整条横线。", hint: "现在最该封的是哪条逃跑横线？"),
                             StudyMove("e9f9", "黑将在剩余合法格间移动，红方保持封锁。", hint: "不要为了追将把封锁车移开。"),
                             StudyMove("b6b9", "另一辆车进入底线将军，与封锁车配合完成将死。", hint: "让第二辆车完成最后一层封锁。")])
            ], tags: ["双车", "分工", "收尾"]),

        LearningLesson(id: "practice-pawn-role", title: "兵的作用是控制格子，不只是向前冲", stage: .endgame, order: 30,
            summary: "比较宫心附近的兵和已经到底的兵，观察选择为何不同。", goal: "说明一个兵控制哪些格子，以及推进后会失去哪些选择。",
            principle: "过河兵能横走，但不能后退也不会升变；兵的价值取决于位置和配合。",
            whenToAdapt: "将或保护子位置变化时，要重新决定前进还是横移。",
            pitfalls: ["把兵冲到底当成必然进步。", "误以为没有将军就不可能获胜。"], sourceIDs: ["practice-endings"], lines: [
                line("mate-pawn-stalemate", "兵占关键格，形成无棋可走", "Ke0 kd9 Pe7",
                     intent: "兵与帅限制全部出口，黑方虽未被将军，也因无合法走法而负。",
                     adapt: "加上一枚能移动的黑子，困毙条件就可能消失；必须检查对方全部棋子。",
                     moves: [StudyMove("e7e8", "兵控制宫内关键格，黑方没有合法走法；这是困毙，不是将军。", hint: "把兵推进后，逐格检查黑将还能走哪里。")]),
                line("pawn-bottom", "到底的兵改用横向控制", "Ke0 kd8 Pd9",
                     intent: "训练底兵的活动方式与限制，不宣称这张残局必胜。",
                     adapt: "底兵不能回头；如果需要控制身后格子，只能考虑将或其他子配合。",
                     moves: [StudyMove("d9e9", "兵已不能再前进，横移以改变底线控制。", hint: "到边界后还有哪一种合法移动？"),
                             StudyMove("d8d7", "黑将避开底线控制，位置变化后需要重做计划。", hint: "对手现在离开了哪条受控横线？"),
                             StudyMove("e0e1", "帅保持中线限制并调整位置；这一练习不把局面标为已赢。", hint: "兵不能后退，哪枚子还能调整？")])
            ], tags: ["兵", "困毙", "不可逆选择"]),

        LearningLesson(id: "practice-exchange", title: "交换前先看换完留下什么", stage: .endgame, order: 40,
            summary: "既练简化，也练保留和推进有保护的兵。", goal: "用一句话描述交换后的棋盘目标。",
            principle: "领先时也不能无条件换子；要检查剩余兵、将的位置和对手反击。",
            whenToAdapt: "交换会丢掉关键兵或进入自己不会处理的残局时，先保留选择。",
            pitfalls: ["领先就见子必换。", "只比较子数，不看兵能否继续发挥作用。"], sourceIDs: ["practice-endings"], lines: [
                line("exchange-rooks", "换掉对方车后，重新规划兵", "Kd0 ke8 Ra7 re7 Pc6",
                     intent: "示例中车交换后留下兵，接着从剩余局面重新选择计划；不以演示线路代替完整残局证明。",
                     adapt: "黑将不回吃时，先解决当前将军和车的安全，不能直接跳到兵残局。",
                     moves: [StudyMove("a7e7", "车换掉对方车，并先观察黑将怎样回应。", hint: "换车后自己会剩下什么进攻子？"),
                             StudyMove("e8e7", "黑将回吃，局面进入兵与将的简化阶段。", hint: "现在将的位置与交换前不同了。"),
                             StudyMove("c6d6", "兵横向调整到更接近将活动区的位置，开始下一阶段计划。", hint: "用新棋面定目标，不继续执行旧车的计划。")]),
                line("exchange-keep-pawn", "先保住有保护的兵，不急着兑掉", "Ke0 kd9 Ra5 Pa6 ra9 ae8 af9 bc9 bg9",
                     intent: "兵在车的接应下推进；示范黑车离线后，红车跟进保持联系。",
                     adapt: "黑车继续压兵时，先算它吃兵会不会被回吃；不能机械沿演示继续。",
                     moves: [StudyMove("a6a7", "兵在车的保护下向前，保留有用的进攻力量。", hint: "兵前进后，保护线会不会断？"),
                             StudyMove("a9b9", "示例：黑车离开兵线，原来的正面压力减轻。", hint: "对手离线后，哪枚红子能进一步改善位置？"),
                             StudyMove("a5a6", "车跟进支持兵，保持两子协作。", hint: "别让兵与车分离得太远。")])
            ], tags: ["兑换", "兵", "局面转换"]),

        LearningLesson(id: "practice-defense", title: "防守要针对攻击方式", stage: .endgame, order: 50,
            summary: "同样把仕放进中线，对车和对炮解除将军的原因不同。", goal: "用规则解释这步为什么有效，而非只记仕的落点。",
            principle: "防车可以挡住直线；防炮可以改变炮架数量；保护子要能承受对手吃入。",
            whenToAdapt: "来攻子变化后，重新判断挡子是消除攻击还是替对方搭炮架。",
            pitfalls: ["套用同一个挡将动作。", "没区分一枚挡子和两枚挡子对炮的影响。"], sourceIDs: ["practice-cxa", "practice-endings"], lines: [
                line("defend-rook-advisor", "对车：加一枚有保护的挡子", "Ke0 kd9 re7 Ad0",
                     intent: "仕受帅保护，挡住黑车直接攻击帅的直线；练习解除当前将军，不宣称整体和棋。",
                     adapt: "若帅不能回吃，仕可能只是临时挡住一次攻击，需要继续找防守。",
                     moves: [StudyMove("d0e1", "仕挡住车线，又有帅接应，当前将军解除。", hint: "仕能否进入中线，同时仍被帅保护？")]),
                line("defend-cannon-second-screen", "对炮：增加第二枚挡子", "Ke0 kd9 ce7 Pe3 Ad0",
                     intent: "兵原先是唯一炮架；仕加入后变为两枚挡子，黑炮不能再直接将军。",
                     adapt: "兵或仕之后移动时要重新数炮架，不能把暂时安全当成永久安全。",
                     moves: [StudyMove("d0e1", "中线从一枚挡子变成两枚，炮对帅的攻击因此失效。", hint: "黑炮到帅之间目前有几枚子，走后又有几枚？")])
            ], tags: ["防守", "仕", "炮架"]),

        LearningLesson(id: "practice-plan-activity", title: "没有急事时，改善最妨碍目标的地方", stage: .strategy, order: 10,
            summary: "改善活动不是盲目出最闲的子，而是解决一项具体障碍。", goal: "走之前说明这步要解决哪一个问题。",
            principle: "先定一个小目标，再让相关棋子获得路线、接应或目标。",
            whenToAdapt: "对手制造强制威胁时暂停原计划；目标移动后，重新考虑调子价值。",
            pitfalls: ["把不断走子当作有计划。", "为了改善闲子而忽略将帅安全。"], sourceIDs: ["practice-endings"], lines: [
                line("plan-open-file", "本列受阻，先换到通畅线路", "Ke0 kd9 Ra0 Na2 Pa3 ae8 af9 bc9 bg9",
                     intent: "车所在直线被己方马兵限制，横移为车寻找活动通道。",
                     adapt: "对手若控制新线路的落点，不必强行把车冲出去；先建立保护。",
                     moves: [StudyMove("a0b0", "车横移到通畅直线，为下一步活动做准备。", hint: "哪条相邻直线没有己方棋子挡路？"),
                             StudyMove("d9d8", "黑将移动后，红方确认车的路线仍安全。", hint: "对手这步是否改变了新线路的安全性？"),
                             StudyMove("b0b4", "车沿已经打开的直线进入更有活动空间的位置。", hint: "执行目标前，再检查整段路线。")]),
                line("plan-cannon-home", "炮没有目标时，回到能借子的区域", "Kd1 ke9 Ch6 Af0 nc0",
                     intent: "炮回到底线后可借己方仕形成攻击；此为调子思路示例，不是普遍的炮必退规则。",
                     adapt: "目标移走或仕的位置改变时，炮架的用途就不同，需要另找计划。",
                     moves: [StudyMove("h6h0", "炮回到仕旁，借仕瞄住底线上的黑马。", hint: "己方哪里已有一枚可以利用的炮架？")])
            ], tags: ["制定计划", "子力活动", "炮的回调"]),

        LearningLesson(id: "practice-plan-priority", title: "对手一变，调整自己的行动顺序", stage: .strategy, order: 20,
            summary: "发展和进攻都有前提：先处理真正紧迫的威胁。", goal: "每次对手走完后，重新指出最重要的一件事。",
            principle: "先应对将军和直接损失，再把安全与发展结合起来。",
            whenToAdapt: "威胁消失就恢复主动计划；不把防守变成无休止的被动跟随。",
            pitfalls: ["背好三步就连续执行。", "每次被攻击都只会后退，不找兼顾发展的办法。"], sourceIDs: ["practice-cxa"], lines: [
                line("priority-check-first", "想出车，也得先解除马将", "Ke0 kd9 nd2 Ra0 ae8 af9 bc9 bg9",
                     intent: "先完成强制的应将，再在对手回应后恢复车的活动。",
                     adapt: "若对手继续将军，需要继续应将，不能按示例自动出车。",
                     moves: [StudyMove("e0f0", "帅先避开马的攻击，暂缓出车计划。", hint: "当前有没有不处理就不能走别子的威胁？"),
                             StudyMove("d2f3", "示例：黑马移位，当前不再将军。", hint: "检查新马位是否产生了新的强制威胁。"),
                             StudyMove("a0a2", "安全条件恢复后，再让车走出原位。", hint: "最紧迫的问题已解决，现在回到活动目标。")]),
                line("priority-protect-and-develop", "调整车的落点，同时照顾受攻的马", "Ke0 kd9 Rh0 Nc3 rb3 ae8 af9 bc9 bg9",
                     intent: "车发展到能保护马的横线，把解决威胁与改善活动合成一步。",
                     adapt: "黑方若继续增加对马的攻击，应重新比较攻守数量，而非立刻转去进攻。",
                     moves: [StudyMove("h0h3", "车进入马所在横线，发展时顺便补上保护。", hint: "车能到哪个位置，既活动又保护马？"),
                             StudyMove("b3b4", "示例：黑车离开原来的攻击横线。", hint: "旧威胁还存在吗？"),
                             StudyMove("c3d5", "马在压力减轻后选择更活跃的落点。", hint: "不要只照计划走，先确认马的新格子安全。")])
            ], tags: ["计划变通", "优先级"]),

        LearningLesson(id: "practice-condition-change", title: "同一招能不能用，要看条件是否改变", stage: .strategy, order: 30,
            summary: "比较只差一个炮架的两张棋面，练真正的迁移而非记答案。", goal: "在走同一吃子前指出决定答案的那枚棋子。",
            principle: "按目标、成立条件和对手回应理解招法；棋面相似不代表答案相同。",
            whenToAdapt: "保护、炮架、马腿或将的位置任一改变，都应重新验证原来的招。",
            pitfalls: ["见过相似图就直接走记忆中的吃子。", "只看第一候选，不解释为什么此处成立。"], sourceIDs: ["practice-cxa"], lines: [
                line("condition-screen-present", "有炮架时，先别让车贪吃马", "Ke0 kd9 Ra2 nc2 cc8 pc5 ae8 af9 bc9 bg9",
                     intent: "红车若直接吃马，黑炮可借卒回吃；先考虑直接向负责回吃的黑炮施压。",
                     adapt: "黑炮移动后，重新判断马是否仍有保护；不必机械追炮，也不宣称一定能吃到炮。",
                     moves: [StudyMove("a2a8", "车先直接威胁黑炮，避开吃马后被炮回吃的陷阱。", hint: "假设先吃马会被回吃，能否先给负责保护的炮制造麻烦？")]),
                line("condition-screen-absent", "炮架消失后，同一吃子可以成立", "Ke0 kd9 Ra2 nc2 cc8 ae8 af9 bc9 bg9",
                     intent: "这里没有卒作炮架，红车吃马后黑炮不能像车一样回吃。",
                     adapt: "黑方若下一步补上炮架，红车仍需应对新的攻击，不能把一次安全视为永久安全。",
                     moves: [StudyMove("a2c2", "车吃马后，黑炮与车之间没有炮架，无法直接回吃。", hint: "与上一张图相比，决定吃子条件的棋子还在吗？"),
                             StudyMove("c8b8", "示例：黑炮改换线路，红方重新判断计划。", hint: "黑炮的新线是否已经有炮架？"),
                             StudyMove("c2c5", "车在吃子后继续改善活动，并保留观察对手回应的习惯。", hint: "先排除新威胁，再选择有用的活动位置。")])
            ], tags: ["变通", "对比练习", "复盘迁移"]),

        LearningLesson(id: "practice-advanced-remove-guard", title: "进阶 · 先拆保护，再连续兑现", stage: .tactics, order: 60,
            summary: "从吃掉保护子开始，算到获子后的第二个任务。", goal: "在连续三到四次决策中，把保护关系变化转化为实际结果。",
            principle: "带将军地消除保护，可争取处理另一个目标的时间；获子后仍要重新组织配合。",
            whenToAdapt: "对手能用一次应将恢复保护，或转移第二个目标时，必须重算，不能按固定顺序吃。",
            pitfalls: ["只发现保护子，却不检查拿掉它是否带将军。", "吃到大子就停止思考，忽略剩下的防守与逃路。"],
            sourceIDs: ["practice-mates", "practice-cxa"], lines: [
                line("advanced-guard-horse", "马先吃保护马，再吃车并完成封锁", "Kd0 kf9 Ra6 Nf5 ne7 rc6",
                     intent: "这条引擎核实的七半步分支依次完成拆保护、获车和车马封路；终局是困毙。",
                     adapt: "黑将若走不同逃路，重新检查马与车的分工；不要假定第七手仍落在同一格。",
                     moves: [StudyMove("f5e7", "马先吃掉保护黑车的马，同时将军，迫使黑方先应将。", hint: "哪枚黑子在保护车，吃它能否同时将军？"),
                             StudyMove("f9e9", "黑将离开原位，红方获得兑现另一目标的时间。", hint: "应将后，原先那辆车还有保护吗？"),
                             StudyMove("e7c6", "马继续吃掉已经失去保护的黑车。", hint: "确认下一次跳马的马腿仍畅通。"),
                             StudyMove("e9f9", "这一分支里黑将向侧面移动，接下来要重新布置封锁。", hint: "获子之后，黑将还剩哪些活动格？"),
                             StudyMove("a6a8", "车控制向前的整条横线，为马的下一次封路做准备。", hint: "先让车承担横线封锁，不急着连续将军。"),
                             StudyMove("f9e9", "黑将回到中路，红方检查最后一格侧逃路。", hint: "侧逃格由马控制，前进格由车控制。"),
                             StudyMove("c6e7", "马限制两侧出口，配合车与帅使黑方无合法走法；这是困毙。", hint: "这里不必将军，逐格检查能否封住全部出口。")]),
                line("advanced-guard-pawn", "用兵拆仕，引开将，再处理车与象", "Kd0 ke9 Ra7 Pd8 ae8 rf7 bc9",
                     intent: "兵吃仕带将军，黑将回吃后红车拿到目标车；获子后继续处理剩余象。",
                     adapt: "黑将不回吃时，也要重新检查目标车的保护；不要把献兵理解为必须有人接。",
                     moves: [StudyMove("d8e8", "兵吃掉保护车的仕并将军，先改变对方的保护关系。", hint: "哪枚小子既能拆仕，又能逼将回应？"),
                             StudyMove("e9e8", "黑将回吃兵，但它的新位置已经不能直接保护原来的车。", hint: "将只能直走一步，检查它现在能保护哪里。"),
                             StudyMove("a7f7", "红车吃掉失去原保护的黑车。", hint: "沿横线确认没有新的挡子。"),
                             StudyMove("e8e9", "黑将退回，红方需要处理还留在棋盘上的象。", hint: "获子后把注意力转到剩余防守。"),
                             StudyMove("f7c7", "车转向象所在直线，开始下一阶段，而不是把吃车当作终点。", hint: "哪枚防守子仍影响后续收尾？")])
            ], estimatedMinutes: 20, tags: ["进阶", "拆保护", "连续计算", "阶段转换"]),

        LearningLesson(id: "practice-advanced-induction", title: "进阶 · 诱饵被拒绝时，计划怎样变", stage: .tactics, order: 70,
            summary: "同一起点练两种真实条件：对手贪吃，或者正确拒绝。", goal: "先提出一个有条件的想法，再依据对手回应选择第二个目标。",
            principle: "诱饵不是强制命令；对手不配合时，继续找可验证的攻击与交换。",
            whenToAdapt: "对手把车移开而不吃兵，就放弃抽车设想，检查马对炮的攻击及新的炮架。",
            pitfalls: ["把对手贪吃写成最佳或被迫回应。", "诱饵没成功仍机械走抽将，把马送掉。"], sourceIDs: ["practice-cxa", "practice-mates"], lines: [
                line("advanced-bait-accepted", "对手若贪吃：移马抽将并吃车", "Kf0 ke9 Re2 Ne5 Pc5 rc8 ad9 af9 bc9 bg9 cd8 cf8",
                     intent: "这是明确标注的对手失误分支：黑车若吃进，红马能吃车并让开车的将军线；不宣称可强制赢棋。",
                     adapt: "黑车不吃兵时，本分支立即失效，切换到下一条拒绝诱饵的变化。",
                     moves: [StudyMove("c5c6", "兵向前提出一个带条件的接触：车若吃兵，红马有回应。", hint: "先算对手吃兵后的两步，不假定他一定会吃。"),
                             StudyMove("c8c6", "失误示例：黑车贪吃兵，进入红马能跳到的位置。", hint: "这枚车的新位置与中线挡子有什么关系？"),
                             StudyMove("e5c6", "马吃车，同时让开中线形成车将军；只对刚才的贪吃分支成立。", hint: "让开自己车的攻击线，并检查能否同时吃到目标。")]),
                line("advanced-bait-declined", "对手正确拒绝：转而处理马炮交换", "Kf0 ke9 Re2 Ne5 Pc5 rc8 ad9 af9 bc9 bg9 cd8 cf8",
                     intent: "黑方不吃兵，按实际引擎变化训练另找炮目标；这张图总体仍难下，目标是正确变通而非承诺翻盘。",
                     adapt: "对方挡将的位置改变后，炮架也会改变；每次吃炮前都重新数中间的子。",
                     moves: [StudyMove("c5c6", "仍从同一接触开始，但准备观察对手是否接受。", hint: "同时保留‘他不吃’这一分支。"),
                             StudyMove("c8a8", "黑车离开，拒绝让红马抽车；原目标消失。", hint: "车没上钩，就停止执行上一条答案。"),
                             StudyMove("e5g6", "马转向炮，同时让开中线形成将军，改变攻击目标。", hint: "除了车，马的新落点还能攻击什么？"),
                             StudyMove("f9e8", "黑仕挡将，并成为两门炮之间的新炮架。", hint: "这枚仕落下后，哪两枚子之间多了炮架？"),
                             StudyMove("g6f8", "马吃一门炮前，已算到另一门炮可以回吃。", hint: "这次是交换，不是白拿一炮。"),
                             StudyMove("d8f8", "黑炮借刚落下的仕回吃马，兑现新的炮架关系。", hint: "确认回吃时中间恰好只有一枚仕。"),
                             StudyMove("e2e6", "车向前施压，按交换后的力量重新组织局面。", hint: "原来的抽车计划已结束，现在谁能承担主动任务？")])
            ], estimatedMinutes: 22, tags: ["进阶", "诱导", "拒绝诱饵", "炮架变化", "分支比较"]),

        LearningLesson(id: "practice-advanced-turning", title: "进阶 · 先完整应将，再抓反击窗口", stage: .strategy, order: 40,
            summary: "一条先吃掉来攻子再封锁，另一条必须连续应将后才轮到反击。", goal: "不跳过对手的强制回应，识别攻守转换真正发生的那一刻。",
            principle: "每一轮都重新判断是否仍在被将；安全后再把局部收益转成主动。",
            whenToAdapt: "对手继续将军就继续应将；对手停止将军时也先检查其他直接威胁，再展开进攻。",
            pitfalls: ["第一次躲将后以为已经安全。", "只想着反击，省掉对手的一次强制将军。"], sourceIDs: ["practice-cxa", "practice-mates"], lines: [
                line("advanced-counter-capture", "吃掉将军炮，再逐步限制将", "Ke0 kd9 Re1 ce7 Ca2",
                     intent: "红车原来是黑炮的炮架，直接吃掉黑炮解除危机，然后通过两次车的安排收尾。",
                     adapt: "黑将若换一条逃路，车的封锁位置要随之改变；不把最后一手当成固定公式。",
                     moves: [StudyMove("e1e7", "车吃掉正在将军的炮，先消除强制威胁。", hint: "炮借谁将军？这枚炮架能否直接吃掉炮？"),
                             StudyMove("d9d8", "黑将前移，红方开始考虑怎样限制它的活动。", hint: "安全问题已解决，现在列出将的出口。"),
                             StudyMove("e7b7", "车控制将继续向前的横线，迫使它返回。", hint: "先封前进方向，不必每一步都将军。"),
                             StudyMove("d8d9", "黑将退回，侧路仍受到红帅限制。", hint: "哪条侧路始终不能走？"),
                             StudyMove("b7d7", "车转入将所在直线，配合帅完成将死。", hint: "把刚才的封锁转换成最后的将军。")]),
                line("advanced-counter-after-checks", "连续两次应将后，车才获得反击时间", "Ke0 kf9 ra0 Ne2 cf1 Rh3 ae8",
                     intent: "采用实际引擎给出的七半步分支，训练先应将、再应将、最后车连续施压的节奏。",
                     adapt: "第三手后对手若继续将军，不能提前执行进车；本分支在黑车不再将军时才转攻。",
                     moves: [StudyMove("e0e1", "帅先离开被车控制的底线，不急着出动攻击车。", hint: "先把帅移出当前攻击横线。"),
                             StudyMove("a0a1", "黑车跟进，再次横向将军；上一手的安全已经改变。", hint: "对手的新横线是否又穿过帅？"),
                             StudyMove("e1e0", "帅再次避开将军，不能省略这一轮应将。", hint: "先完成必须做的事，再看自己的进攻。"),
                             StudyMove("a1a4", "本分支中黑车改换位置，暂时不再将军。", hint: "这是攻守转换前的检查点。"),
                             StudyMove("h3h9", "红车抓住时间进入底线将军，开始主动施压。", hint: "确认帅安全后，检查哪辆车能迅速将军。"),
                             StudyMove("f9f8", "黑将向前避开底线，红方重新定位目标。", hint: "将的位置变了，下一次车将应在哪条线？"),
                             StudyMove("h9h8", "车换到新的横线继续将军；这只是攻势的延续，不宣称已将死。", hint: "继续计算对方下一次合法回应。")])
            ], estimatedMinutes: 22, tags: ["进阶", "攻守转换", "连续应将", "反击窗口"]),

        LearningLesson(id: "practice-advanced-transition", title: "进阶 · 简化之后，重新安排剩余力量", stage: .endgame, order: 60,
            summary: "换完不是结束：分别练兵残局的连续目标与换炮后的车兵协作。", goal: "跨过交换节点后，主动重设下一阶段的目标。",
            principle: "用剩余棋子的控制范围制定计划，而不是把交换前的路线继续套下去。",
            whenToAdapt: "对方不同的回吃方式改变将位、兵位或开放线时，从那个新局面重新判断。",
            pitfalls: ["只计算交换过程，没想换完怎样走。", "把引擎一时接近零的分数当成已经证明理论和棋。"], sourceIDs: ["practice-endings"], lines: [
                line("advanced-pawn-after-trade", "车已换完：兵连续改变控制格", "Kd0 ke7 Pc6",
                     intent: "从换车后的真实阶段开始，经过四次兵的选择，配合帅形成困毙。",
                     adapt: "将选择别的路径时，重新检查兵该直进还是横移；兵不能退回重选。",
                     moves: [StudyMove("c6c7", "兵先前进一步，为横向接近将的活动区创造位置。", hint: "推进后，兵能横向控制哪一条线？"),
                             StudyMove("e7e8", "黑将后退，红方要再次选择接近方向。", hint: "将不在原格，兵的下一目标也应更新。"),
                             StudyMove("c7d7", "兵横移，控制对方的一侧入口并保持继续调动的余地。", hint: "横移能否比继续到底保留更多选择？"),
                             StudyMove("e8f8", "黑将向另一侧避让，原来的控制需要跟进。", hint: "找新将位附近尚未控制的格子。"),
                             StudyMove("d7e7", "兵再次横移，控制将向前和向侧面移动的关键格。", hint: "一个兵现在同时负责哪些出口？"),
                             StudyMove("f8f9", "黑将退到底线，红方核对最后两个出口。", hint: "最后一手应让哪两个格子同时受控？"),
                             StudyMove("e7e8", "兵前进后封住两个出口，黑方无合法走法，形成困毙。", hint: "检查全部合法走法，而不只检查是否将军。")]),
                line("advanced-cannon-trade-plan", "换炮后，用车开线、让兵跟上", "Ke0 kd9 Rc1 Cc2 Pc5 cc7 rc8 ae8 af9 bc9 bg9",
                     intent: "炮的交换只是阶段转换；随后车、兵分别改善位置。这条七半步线不宣称必胜或理论和棋。",
                     adapt: "黑方不回吃炮时，应按实际局面处理；黑车换线路后也要重新注意将军与兵的安全。",
                     moves: [StudyMove("c2c7", "炮借兵换掉对方炮，并预先算到黑车回吃。", hint: "这次交换结束后，自己还有哪些子能发挥作用？"),
                             StudyMove("c8c7", "黑车回吃，车兵与车的阶段开始，旧炮线已不存在。", hint: "先重新认识剩下的棋子。"),
                             StudyMove("c1d1", "车切入新的直线将军，主动改善线路。", hint: "旧线路被兵占着，车有没有相邻的可用线路？"),
                             StudyMove("d9e9", "黑将避开车线，红方继续处理兵与车的配合。", hint: "将换线后，兵应靠近哪一辆车？"),
                             StudyMove("c5d5", "兵横移到车能接应的直线，保持保护关系。", hint: "兵横移后，自己的车还能沿线保护它吗？"),
                             StudyMove("c7i7", "黑车转移，未来的侧向将军和袭兵需要重新检查。", hint: "对手换线不是无关的一步。"),
                             StudyMove("d1d2", "车在保持护兵的同时调整活动位置，进入下一轮计划。", hint: "这步既要改善车，也不能切断护兵线。")])
            ], estimatedMinutes: 24, tags: ["进阶", "简化利弊", "阶段转换", "车兵协作"]),

        LearningLesson(id: "practice-advanced-pawn-block", title: "进阶 · 兵的控制与行棋顺序一起算", stage: .endgame, order: 70,
            summary: "练受限局面中的等待步，以及两兵轮流限制对方将的路线。", goal: "知道为什么此时轮到哪一方走，也会改变结果。",
            principle: "封锁不仅是占格子，还要让对方在合适时刻面对无路可走；等待步必须保持关键控制。",
            whenToAdapt: "对方多了一枚可自由移动的子，就不能再用‘将没路’直接判困毙。",
            pitfalls: ["只会不断将军，不会保持封锁。", "把等待步当成随便走一步，破坏了原有控制。"], sourceIDs: ["practice-endings", "practice-mates"], lines: [
                line("advanced-pawn-wait", "先把将赶进受限区，再用兵保持局面", "Ke0 kd9 Ra5 Pc6 ae8 af9",
                     intent: "车将军后将被迫换线，仕因将帅关系受限；一手不破坏控制的兵步让黑方面对困毙。",
                     adapt: "若对手的仕能够合法移动，等待步就未必结束棋局，必须把所有黑子都列入检查。",
                     moves: [StudyMove("a5d5", "车先将军并限制这一条直线，让黑将改变位置。", hint: "先把将逼到会被自己防守子挤住的位置。"),
                             StudyMove("d9e9", "黑将进入中路；中线仕又不能随意离开，否则会将帅照面。", hint: "检查仕的每一步是否会暴露自己的将。"),
                             StudyMove("c6b6", "兵横移保持全部关键控制，轮到黑方后无合法走法，形成困毙。", hint: "不必再将军，找一手不破坏封锁的合法等待步。")]),
                line("advanced-two-pawns", "两兵轮流推进，按将的回应封口", "Ke0 kd9 Pc6 Pf6",
                     intent: "先动一侧兵，再用另一侧兵跟随将的路线，五半步后形成困毙。",
                     adapt: "每次移动前确认另一枚兵和帅的限制仍在；不要把两兵都无条件冲到底。",
                     moves: [StudyMove("f6f7", "先安排右侧兵的控制，并把回合交给受限的黑将。", hint: "哪枚兵可以改善位置，又不破坏另一侧的计划？"),
                             StudyMove("d9d8", "黑将向前移动，红方根据它的新位置选择另一枚兵。", hint: "现在该由哪一侧的兵收紧空间？"),
                             StudyMove("c6c7", "左兵向前，限制将继续前进的路线。", hint: "这步要控制的不是将本身，而是它的下一个出口。"),
                             StudyMove("d8d9", "黑将只能退回，红方重新检查底线的出口。", hint: "对手退回后，是否还需要再将军？"),
                             StudyMove("c7d7", "兵横移封住前进格，配合帅的限制使黑方无合法走法。", hint: "确认这是困毙，而不是看到兵接近将就猜测获胜。")])
            ], estimatedMinutes: 20, tags: ["进阶", "兵的配合", "等待步", "封锁", "困毙"]),

        LearningLesson(id: "practice-advanced-coordination", title: "进阶 · 连续计划中的分工与换线", stage: .strategy, order: 50,
            summary: "从赶将、调帅到换车线，或从调马、转炮到最后建立炮架。", goal: "每次自己走前都能说出这一手在整段计划中的职责。",
            principle: "连续计划由多个可检查的小目标构成，对手的位置变化决定下一步负责封路的棋子。",
            whenToAdapt: "对手改走另一条合法路线，重新分配封锁任务；允许更快或等价的收尾，不以逐字背谱为标准。",
            pitfalls: ["记住一串走法，却不知道哪一步负责封哪条路。", "把炮摆到将的直线上就误以为已经将军。"], sourceIDs: ["practice-endings", "practice-mates"], lines: [
                line("advanced-king-rook-plan", "先赶将，再调帅，最后车换线", "Kf0 ke8 Ra4",
                     intent: "一条五半步收尾分支：车先驱赶，帅建立限制，车最后转到新直线；不要求这条线是唯一最快。",
                     adapt: "黑将若选择向前而不是向后，按它的新格子重新验证最后车步。",
                     moves: [StudyMove("a4e4", "车先将军，让黑将离开中路直线。", hint: "先让将移动，才能判断帅该参与哪条封锁线。"),
                             StudyMove("e8d8", "黑将向侧面避让，红方获得调整帅位置的条件。", hint: "将已换线，红帅能否安全进入中线？"),
                             StudyMove("f0e0", "帅调整到中线，为车下一次换线后保留侧面限制。", hint: "这一步不直接攻击将，却负责哪条未来逃路？"),
                             StudyMove("d8d9", "示例：黑将退回底线，红方检查计划条件仍成立。", hint: "重新数黑将的出口，不自动执行旧答案。"),
                             StudyMove("e4d4", "车换入将所在直线，帅接管中线限制，完成将死。", hint: "车移开后，中线由谁继续控制？")]),
                line("advanced-horse-cannon-plan", "马先压住关键点，炮再跟着将换线", "Ke0 ke9 Ca2 Nd5 ae8",
                     intent: "七半步的马炮协作：先调马，再两次转炮，最后用马建立炮架完成将死。",
                     adapt: "黑仕选择不同应对时，重新检查炮架与将帅照面限制；不能只照着炮的列号走。",
                     moves: [StudyMove("d5f6", "马先控制将附近的关键点，并给后续炮的线路创造配合。", hint: "先检查马能限制哪枚防守子与哪些宫内格。"),
                             StudyMove("e9d9", "黑将离开中路，红方需要让炮与它的新线路发生联系。", hint: "将已经换线，原来的炮位还够用吗？"),
                             StudyMove("a2e2", "炮先进入中线，利用仕与将的位置关系限制防守。", hint: "这一步是建立线路，不必立刻形成将军。"),
                             StudyMove("d9d8", "黑将继续向前，炮的最终线路再次改变。", hint: "把对手新落点当作新的计算起点。"),
                             StudyMove("e2d2", "炮转到将所在直线，等待马进入合适的炮架格。", hint: "炮线上现在还缺什么条件？"),
                             StudyMove("e8d9", "黑仕离开中线，改变了将帅之间的空线关系。", hint: "仕一移动，黑将横向逃跑还合法吗？"),
                             StudyMove("f6d5", "马进入炮线作架，炮将军；马、帅和仕的位置共同封住出口，形成将死。", hint: "最后同时检查炮架、马控制格和将帅照面。")])
            ], estimatedMinutes: 24, tags: ["进阶", "连续计划", "将帅协作", "马炮协作", "换线"])
    ].map { original in
        var lesson = original
        lesson.prerequisites = prerequisites[lesson.id] ?? []
        return lesson
    }
}
