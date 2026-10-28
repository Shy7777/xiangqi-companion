import Foundation

/// Reading links only. Third-party textbook examples and article excerpts are
/// excluded from the source release; linked works keep their own terms.
enum TextbookCurriculum {
    static let sources: [LearningSource] = [
        LearningSource(id: "textbook-zhu-basic", title: "朱宝位 · Basic Xiangqi Checkmate Methods", url: "https://www.wxf-xiangqi.org/images/free_download_books/BasicXqCheckmate.pdf", note: "WXF 官方阅读入口。原书例题、原图与原注不随本软件分发；阅读不代表取得再分发许可。"),
        LearningSource(id: "textbook-qian-midgames", title: "钱俊 · Checkmate Methods in Xiangqi Mid-Games", url: "https://www.wxf-xiangqi.org/images/free_download_books/Checkmate_methods_in_Xiangqi_Midgames.pdf", note: "WXF 官方阅读入口；本软件不内置该书例题或作者原注。"),
        LearningSource(id: "textbook-png-openings", title: "Jim Png · Choosing your Xiangqi Opening", url: "https://www.xiangqi.com/articles/choosing-your-xiangqi-chinese-chess-opening", note: "作者署名文章的原站链接；文章及摘例不随软件分发，请遵守原站条款。"),
        LearningSource(id: "textbook-png-sacrifice", title: "Jim Png · Midgame Tactics 05: Sacrificing Material", url: "https://www.xiangqi.com/articles/basic-xiangqi-chinese-chess-midgame-tactics-05-sacrificing-material", note: "作者署名文章的原站链接；不提供文章镜像或摘例课程。")
    ]

    // Explicit boundary for callers and imported-course compatibility.
    static let lessons: [LearningLesson] = []
}
