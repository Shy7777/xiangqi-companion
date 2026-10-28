import SwiftUI

extension LearningCenterView {
    var bookCoveragePanel: some View {
        let inventory = CurriculumInventory(lessons: model.lessons)
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "books.vertical").font(.system(size: 30)).foregroundColor(Studio.gold)
                    .frame(width: 62, height: 72).background(Studio.gold.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 9) {
                    StudioTag(text: "课程范围对照", color: Studio.gold)
                    Text(BookCoverage.title.simplifiedForDisplay).font(.system(size: 24, weight: .semibold))
                    Text("王嘉良 / 张志强 / 张弘 · 经济管理出版社 · 2016 第二版")
                        .font(.system(size: 11)).foregroundColor(Studio.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(BookCoverage.boundary.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.gold).lineSpacing(5)
            HStack(spacing: 0) {
                quietStat("\(inventory.courses)", "门主线课程")
                quietStat("\(inventory.lines)", "条可练线路")
                quietStat("\(inventory.checkpoints)", "个决策点")
                quietStat("\(inventory.variations)", "条研究变式")
            }
            Text("线路不是独立题目数：以上包含 \(inventory.uniqueStarts) 个不同起始局面、\(inventory.completeGames) 盘完整记录；专题截段可能引用同一名局。数字为当前本机课程，导入课程也会计入。")
                .font(.system(size: 10)).foregroundColor(Studio.muted).lineSpacing(4)
            ForEach(1...5, id: \.self) { chapter in
                DisclosureGroup(isExpanded: Binding(get: { expandedBookChapter == chapter }, set: { expandedBookChapter = $0 ? chapter : nil })) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(BookCoverage.themes.filter { $0.chapter == chapter }) { theme in bookThemeRow(theme) }
                    }.padding(.top, 18)
                } label: {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", chapter)).font(.system(size: 13, design: .monospaced)).foregroundColor(Studio.cyan)
                        Text(BookCoverage.chapterTitles[chapter - 1].simplifiedForDisplay).font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Text("\(BookCoverage.themes.filter { $0.chapter == chapter }.count) 个对照主题")
                            .font(.system(size: 10)).foregroundColor(Studio.muted)
                    }
                }.studioSurface(18).accessibilityIdentifier("book-theme-chapter-\(chapter)")
            }
            HStack(spacing: 12) {
                if let url = URL(string: BookCoverage.sourceURL) { Link("核对公开书目与目录 ↗", destination: url).font(.system(size: 12)) }
                Spacer()
                Text("主题有练习 ≠ 原书已读完 ≠ 已掌握").font(.system(size: 11)).foregroundColor(Studio.muted)
            }
        }.accessibilityIdentifier("book-coverage-panel")
    }

    private func bookThemeRow(_ theme: TextbookTheme) -> some View {
        let lessons = theme.lessons(in: model.lessons)
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(theme.id + "  " + theme.title.simplifiedForDisplay).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(lessons.count == theme.lessonIDs.count ? "有对应练习" : "部分课程缺失")
                    .font(.system(size: 10)).foregroundColor(lessons.count == theme.lessonIDs.count ? Studio.cyan : Studio.red)
            }
            Text(theme.target.simplifiedForDisplay).font(.system(size: 12)).lineSpacing(5)
            Text(theme.boundary.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
            ForEach(lessons) { lesson in
                Button {
                    previewBranchID = GuidedStudyRecommendation.preferredLineID(lesson: lesson, archive: store.data)
                    previewLesson = lesson
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "square.grid.3x3").foregroundColor(Studio.cyan)
                        Text(lesson.title.simplifiedForDisplay).font(.system(size: 12)).multilineTextAlignment(.leading)
                        Spacer(minLength: 5)
                        Text("\(lesson.lines.count) 线").font(.system(size: 10, design: .monospaced)).foregroundColor(Studio.muted)
                        Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundColor(Studio.muted)
                    }.padding(10).background(Studio.paper, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).accessibilityIdentifier("theme-\(theme.id)-\(lesson.id)")
            }
            if theme.id == "3.4" {
                Button("混合抽取 · 无提示检验") { model.startTopicCheck(lessonIDs: theme.lessonIDs) }
                    .buttonStyle(StudioButtonStyle(primary: true)).accessibilityIdentifier("book-mixed-check")
            }
            Divider().padding(.top, 5)
        }
    }
}
