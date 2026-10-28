import Foundation

enum ResourceCatalogKind: String, CaseIterable, Identifiable {
    case localCourses, originalSite, book, openSource
    var id: String { rawValue }
    var title: String {
        switch self {
        case .localCourses: return "本机课程"
        case .originalSite: return "免费原站"
        case .book: return "参考书目"
        case .openSource: return "开源工具"
        }
    }
    var symbol: String {
        switch self {
        case .localCourses: return "square.grid.2x2"
        case .originalSite: return "globe"
        case .book: return "books.vertical"
        case .openSource: return "wrench.and.screwdriver"
        }
    }
}

/// This is an index, not a downloadable textbook or a claim of rights to linked works.
struct ResourceCatalogEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let author: String
    let summary: String
    let kind: ResourceCatalogKind
    let stages: [LearningStage]
    let rights: String
    let scope: String
    var lessonIDs: [String] = []
    var sourceID: String? = nil
    var externalSource: LearningSource? = nil
    var externalURL: String? = nil

    var offlineLabel: String { kind == .localCourses ? "可离线练习" : "需访问原站" }
    var searchText: String {
        ([title, author, summary, kind.title] + stages.map(\.shortTitle)).joined(separator: " ")
    }
    var resolvedURL: URL? {
        guard let value = externalURL ?? externalSource?.url,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    func readingSource(in sources: [LearningSource]) -> LearningSource? {
        if let sourceID { return sources.first { $0.id == sourceID } }
        return externalSource
    }
    func lessons(in lessons: [LearningLesson]) -> [LearningLesson] {
        let byID = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return lessonIDs.compactMap { byID[$0] }
    }
}

struct ResourceDirectorySection: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    var url: URL? {
        URL(string: "https://github.com/lucaferranti/awesome-xiangqi/blob/8fff91f76b6569a191d8e7fc61295ae92d3bced2/README.md#" + id)
    }
}

@MainActor enum ResourceCatalog {
    static let upstreamCommit = "8fff91f76b6569a191d8e7fc61295ae92d3bced2"
    static let upstreamURL = "https://github.com/lucaferranti/awesome-xiangqi/blob/" + upstreamCommit + "/README.md"
    static let licenseURL = "https://github.com/lucaferranti/awesome-xiangqi/blob/" + upstreamCommit + "/LICENSE"
    static let attribution = "资源组织参考 Luca Ferranti 与贡献者的 awesome-xiangqi（CC0 1.0）。CC0 仅适用于该目录，不延伸到目录中的书籍、视频、网站或软件。"

    static let entries: [ResourceCatalogEntry] = localEntries + professionalEntries + referenceEntries
    /// Complete upstream taxonomy stays available without flooding the curated cards.
    static let directorySections: [ResourceDirectorySection] = [
        .init(id: "general-websites", title: "综合网站", detail: "世界象棋联合会、作者专题站"),
        .init(id: "websites-to-play", title: "对弈网站", detail: "在线对弈、观战与分析平台"),
        .init(id: "games-databases", title: "棋谱数据库", detail: "按棋手、赛事、开局查谱"),
        .init(id: "books", title: "书籍与古谱", detail: "入门、布局、战术、残局、古谱、对局集"),
        .init(id: "youtube-channels", title: "讲解视频", detail: "作者与棋手的教学频道"),
        .init(id: "engines", title: "象棋引擎", detail: "Pikafish、Fairy-Stockfish"),
        .init(id: "computer-xiangqi", title: "计算机象棋", detail: "编码、分类、规则与研究"),
        .init(id: "other-useful-tools", title: "制谱与辅助工具", detail: "棋面生成、编辑器与平台"),
        .init(id: "social", title: "棋友社群", detail: "社区讨论与开源协作")
    ]

    static func filtered(query: String, kind: ResourceCatalogKind?, stage: LearningStage?) -> [ResourceCatalogEntry] {
        let words = ChineseDisplayText.searchTerms(query)
        return entries.filter { entry in
            (kind == nil || entry.kind == kind) && (stage.map(entry.stages.contains) ?? true) &&
            (words.isEmpty || ChineseDisplayText.matches(normalizedText: ChineseDisplayText.searchKey(entry.searchText), terms: words))
        }
    }

    static func validate(lessons: [LearningLesson], sources: [LearningSource]) throws {
        guard Set(entries.map(\.id)).count == entries.count else { throw StudyError.invalidContent("书架条目编号重复。") }
        guard directorySections.count == 9, Set(directorySections.map(\.id)).count == 9,
              directorySections.allSatisfy({ $0.url?.scheme == "https" && $0.url?.fragment == $0.id }) else {
            throw StudyError.invalidContent("完整资源目录的分类或链接不完整。")
        }
        let lessonIDs = Set(lessons.map(\.id)), sourceIDs = Set(sources.map(\.id))
        for entry in entries {
            guard !entry.title.isEmpty, !entry.author.isEmpty, !entry.summary.isEmpty,
                  !entry.rights.isEmpty, !entry.scope.isEmpty, !entry.stages.isEmpty else {
                throw StudyError.invalidContent("书架条目缺少出处或范围：" + entry.id)
            }
            if entry.kind == .localCourses {
                guard !entry.lessonIDs.isEmpty, Set(entry.lessonIDs).count == entry.lessonIDs.count,
                      entry.lessonIDs.allSatisfy(lessonIDs.contains), entry.sourceID == nil,
                      entry.externalSource == nil, entry.externalURL == nil else {
                    throw StudyError.invalidContent("本机书架含失效课程：" + entry.id)
                }
            } else if let sourceID = entry.sourceID {
                guard sourceIDs.contains(sourceID), entry.lessonIDs.isEmpty,
                      entry.externalURL == nil, entry.externalSource == nil else {
                    throw StudyError.invalidContent("原站书架含失效或冲突来源：" + entry.id)
                }
            } else {
                guard entry.resolvedURL != nil, entry.lessonIDs.isEmpty,
                      (entry.externalSource == nil) != (entry.externalURL == nil) else {
                    throw StudyError.invalidContent("书架外链需要单一 HTTPS 目标：" + entry.id)
                }
            }
        }
    }

    private static let localRights = "这些入口只打开本机课程。公开版保留项目原创教学与客观实战记录，不包含外部教材例题或原注，也不声称参考书已获授权改编。"
    private static let localEntries: [ResourceCatalogEntry] = [
        .init(id: "local-opening", title: "布局与变招", author: "本机研究课程", summary: "中炮、屏风马及不同起手；从主干比较计划与偏离。", kind: .localCourses,
              stages: [.opening], rights: localRights, scope: "精选入口；不是新增课程，也不是完整开局百科。",
              lessonIDs: ["repertoire-screen-exchange", "repertoire-sandwich-rook", "repertoire-pawn-counter", "repertoire-elephant-center"]),
        .init(id: "local-middlegame", title: "中局判断与计算", author: "本机研究课程", summary: "先评估活动和安全，再计算交换、侵入与反击。", kind: .localCourses,
              stages: [.tactics, .strategy], rights: localRights, scope: "含既有完整实战的专题截段；截段不计作新的一盘名局。",
              lessonIDs: ["atlas-activity", "atlas-exchange", "atlas-king-safety", "atlas-counterinitiative"]),
        .init(id: "local-mates", title: "杀法配合", author: "本机研究课程", summary: "车马炮分工、炮架与逃路；换一种防守重新计算。", kind: .localCourses,
              stages: [.tactics, .endgame], rights: localRights, scope: "有限可演练局面；课程名字不等于任何摆局都成立的杀法定理。",
              lessonIDs: ["endgame-rook-horse-team", "endgame-horse-cannon-team"]),
        .init(id: "local-endgames", title: "残局兑现与防守", author: "本机研究课程", summary: "兵的位置、将位与交换条件；争胜和守和都要练。", kind: .localCourses,
              stages: [.endgame], rights: localRights, scope: "有限引擎搜索不构成全部材料组合的例胜例和证明。",
              lessonIDs: ["endgame-pawn-king-space", "endgame-rook-pawn-coordination", "endgame-horse-pawn-routes", "endgame-cannon-pawn-screen", "endgame-active-defense"]),
        .init(id: "local-games", title: "完整实战与复盘", author: "本机研究课程", summary: "沿四盘公开对局看布局、中局、转化与关键决策。", kind: .localCourses,
              stages: [.opening, .tactics, .endgame, .strategy], rights: localRights, scope: "四盘既有完整记录；历史胜者的每一步不一定是引擎最优着。",
              lessonIDs: ["systematic-opening-transition", "systematic-position-balance", "systematic-forcing-calculation", "systematic-endgame-transition"])
    ]

    private static let professionalEntries: [ResourceCatalogEntry] = ProfessionalResources.sources.map { source in
        let stage: [LearningStage]
        let author: String
        let summary: String
        if source.id.contains("png-opening") {
            stage = [.opening]; author = "Jim Png · 作者原站"
            summary = "开局理论导读：从走子次序、空间与先手理解计划。"
        } else if source.id.contains("chen-endgame") {
            stage = [.endgame]; author = "陈俊彦 · 相弈象棋"
            summary = "实用残局原则与胜和条件的中文专题。"
        } else if source.id.contains("cctv") {
            stage = [.opening, .tactics, .endgame, .strategy]; author = "央视 · 对局节目"
            summary = "在原站观看对局节目；停在关键位置先作自己的判断。"
        } else if source.id.contains("cxa") {
            stage = [.tactics]; author = "中国象棋协会 · WXF 提供"
            summary = "三十六计系列短例；用于局部战术识别，非进阶主线。"
        } else {
            stage = [.tactics, .strategy]
            author = source.id.contains("chen") ? "陈俊彦 · 相弈象棋" : "Jim Png · 相弈象棋"
            summary = "比较局面判断、战略计划与需要算清的具体变化。"
        }
        return .init(id: "catalog-" + source.id, title: source.title, author: author, summary: summary,
                     kind: .originalSite, stages: stage,
                     rights: "公开可访问不等于允许复制改编。原作品保留在作者或提供方网站；本机仅保存目录与原创阅读任务，不收录完整正文、视频或讲稿。",
                     scope: source.note, sourceID: source.id)
    }

    private static let referenceEntries: [ResourceCatalogEntry] = [
        .init(id: "book-intermediate-2016", title: "象棋中级教程（第二版）", author: "王嘉良、张志强、张弘 · 2016", summary: "布局、中局、残局、实战与大师经验的参考书目。", kind: .book,
              stages: [.opening, .tactics, .endgame, .strategy],
              rights: "商业书籍；未取得完整正文或改编授权。书目页不是可免费阅读的整本教材。",
              scope: "经济管理出版社；ISBN 9787509641002。现有 5 章、17 个公开目录主题对照不能证明原书全部例题、变化与深度已内置。",
              externalURL: "https://www.megbook.com.hk/mall/detail.jsp?proID=2782834"),
        .init(id: "wxf-open-guide", title: "WXF 象棋导读", author: "WXF 网站提供 · 2015 v3.0 英文稿", summary: "公开 PDF：规则、战术、残局及相关参考资料。", kind: .originalSite,
              stages: [.foundation, .opening, .tactics, .endgame],
              rights: "混合许可，必须按章处理：除第 8、12、13、15–20 章外为 CC BY-SA 3.0；第 8 章注明含 WXF/CXA 公版材料；第 12、15–20 章为非商业 CC BY-NC-SA；第 13 章另有字典来源。不是整本统一开放许可。",
              scope: "这里只提供官方 PDF 阅读入口。它偏入门，不能替代适合已有实战能力者的完整中级教材；本次未下载、打包或新增改编其全文。",
              externalSource: LearningSource(id: "catalog-wxf-open-guide", title: "WXF 象棋导读 · 原站 PDF",
                  url: "https://www.wxf-xiangqi.org/images/free_download_books/xiangqi_introduction_chessplayers_20150323.pdf",
                  note: "98 页公开导读，版权说明位于第 96 页。分章许可不同，原站免费阅读不代表可统一内置或商用。")),
        .init(id: "archive-orange-manual", title: "橘中秘（二）· 古籍影像", author: "朱晋桢辑 · CADAL / Wikimedia Commons", summary: "查看古谱原貌，用于史料核对与经典局面研究。", kind: .originalSite,
              stages: [.opening, .endgame],
              rights: "Commons 文件页标注 Public Domain；此标记针对该古籍影像，不覆盖现代译注、整理版本或网站上的其他内容。公开发布仍应核对目标地区与具体版本权利。",
              scope: "文件页登记 83 页、约 1.41 MB。本机只保存入口，未下载影像，未把它包装成已逐题审校的现代进阶课程。",
              externalSource: LearningSource(id: "catalog-orange-manual", title: "橘中秘（二）· 古籍来源与影像",
                  url: "https://commons.wikimedia.org/wiki/File:CADAL02095145_%E6%A9%98%E4%B8%AD%E7%A7%98%EF%BC%88%E4%BA%8C%EF%BC%89.djvu",
                  note: "CADAL 编号 02095145；古籍文件页含来源、许可与逐页预览。未内置全文或现代评注。")),
        .init(id: "tool-awesome", title: "Awesome Xiangqi", author: "Luca Ferranti 与贡献者", summary: "网站、棋谱库、书籍、视频与软件的开源资源索引。", kind: .openSource,
              stages: [.opening, .tactics, .endgame, .strategy], rights: attribution,
              scope: "核验版本 " + upstreamCommit + "。仓库只有 README、LICENSE、contributing 三个文件，不是教材或题库。原目录中未核实与失效的链接未自动导入本书架。",
              externalURL: upstreamURL),
        .init(id: "tool-pikafish", title: "Pikafish", author: "Pikafish 开源贡献者", summary: "本软件所用象棋分析引擎的官方源码与文档。", kind: .openSource,
              stages: [.opening, .tactics, .endgame, .strategy],
              rights: "引擎按其 GNU GPL v3 许可分发；不是 MIT，也不提供参考书正文的改编授权。查看仓库不安装或更新引擎。",
              scope: "引擎给出有限搜索的着法与评价；评分不是你的个人胜率，主变也不是自动生成的权威教学解释。",
              externalURL: "https://github.com/official-pikafish/Pikafish"),
        .init(id: "tool-xiangqi-pwa", title: "棋弈江湖 · Xiangqi PWA", author: "dffge552", summary: "离线象棋平台；参考其局面分类、摆局与分析工具。", kind: .openSource,
              stages: [.opening, .tactics, .endgame],
              rights: "仓库根许可为 MIT，版权人 dffge552，2026。题目另致谢从宽象棋，未找到逐题来源授权清单；根许可证不证明第三方题库、模型训练素材及 Pikafish 均可改用 MIT。",
              scope: "核验版本 3ff21f4502a03f30bb0df55db6f3814ceeb989f5。题库主要是 FEN 局面，已检查的 7 个专题文件没有解序或评注；199 个残局类别中发现 7 对文件内容重复。未内置这些题库或下载模型。",
              externalURL: "https://github.com/dffge552/xiangqi-pwa-offline/tree/3ff21f4502a03f30bb0df55db6f3814ceeb989f5")
    ]
}
