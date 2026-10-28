import SwiftUI

extension LearningCenterView {
    var guidedNextStep: (lesson: LearningLesson, line: StudyLine, mode: StudyMode)? {
        let catalog = model.lessons
        guard let recommendation = GuidedStudyRecommendation.next(chapters: GuidedCurriculum.chapters, lessons: catalog, archive: store.data),
              let lesson = catalog.first(where: { $0.id == recommendation.lessonID }),
              let line = lesson.lines.first(where: { $0.id == recommendation.lineID }) else { return nil }
        return (lesson, line, recommendation.mode)
    }

    var guidedStepTitle: String {
        guard let step = guidedNextStep else { return "选择下一次实战" }
        switch step.mode {
        case .demonstration: return "开始本课推演"
        case .practice: return "自己走一遍"
        case .test: return "检验这条线路"
        }
    }

    func beginGuidedStep() {
        guard let step = guidedNextStep else { model.navigate(.courses); return }
        if step.mode == .demonstration {
            previewBranchID = step.line.id; previewLesson = step.lesson
        } else { model.startLesson(step.lesson, line: step.line, mode: step.mode) }
    }

    private func nextChapterLine(_ lesson: LearningLesson) -> StudyLine? {
        let id = GuidedStudyRecommendation.preferredLineID(lesson: lesson, archive: store.data)
        return lesson.lines.first { $0.id == id }
    }

    func guidedRoute(compact: Bool) -> some View {
        VStack(spacing: 14) {
            if !compact && expandedChapterID != nil {
                HStack { Button("全部章节") { expandedChapterID = nil }.buttonStyle(StudioButtonStyle(compact: true)); Spacer() }
            }
            ForEach(GuidedCurriculum.chapters.filter { compact || expandedChapterID == nil || $0.id == expandedChapterID }) { chapter in
                guidedChapterCard(chapter, compact: compact)
            }
        }
    }

    func guidedChapterCard(_ chapter: GuidedChapter, compact: Bool) -> some View {
        let lessons = chapter.lessonIDs.compactMap { id in model.lessons.first { $0.id == id } }
        let expanded = !compact && expandedChapterID == chapter.id
        let status = GuidedChapterStatus(chapter: chapter, lessons: model.lessons, archive: store.data)
        return VStack(alignment: .leading, spacing: 17) {
            Button {
                if compact {
                    expandedChapterID = chapter.id; model.onlySupplements = false
                    model.query = ""; model.stageFilter = nil; model.onlyBookmarks = false; model.navigate(.courses)
                } else { expandedChapterID = expanded ? nil : chapter.id }
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: chapterSymbol(chapter.number)).font(.system(size: 23)).foregroundColor(Studio.accent)
                        .frame(width: 46, height: 46).background(Studio.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(chapter.title.simplifiedForDisplay).font(.system(size: 18, weight: .semibold, design: .serif))
                        Text("\(lessons.count) 个主题 · \(status.testedCount)/\(status.totalCount) 主题独立通过").font(.system(size: 11)).foregroundColor(Studio.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.right").foregroundColor(Studio.muted)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                LazyVStack(spacing: 0) {
                    ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                        lessonRow(lesson, index: index)
                        if index < lessons.count - 1 { Divider().padding(.leading, 48) }
                    }
                }
                DisclosureGroup("本章目标、参考与记录") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(chapter.subtitle.simplifiedForDisplay).font(.system(size: 13)).lineSpacing(4)
                        HStack(spacing: 18) {
                            chapterMetric("已研究", count: status.studiedCount, total: status.totalCount)
                            chapterMetric("已练习", count: status.practicedCount, total: status.totalCount)
                            chapterMetric("独立检验", count: status.testedCount, total: status.totalCount)
                        }
                        Text("仅该主题全部谱例达标才计入；研究记录不代表读完原书。").font(.system(size: 10)).foregroundColor(Studio.muted)
                        ForEach(GuidedCurriculum.books.filter { chapter.readingIDs.contains($0.id) }) { book in
                            Button { openTextbook(book) } label: { Label(book.title.simplifiedForDisplay, systemImage: "book.closed").font(.system(size: 12)) }
                                .buttonStyle(.plain).foregroundColor(Studio.accent).help(book.coverage.simplifiedForDisplay)
                        }
                        Text(chapter.completionStandard.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted)
                    }.padding(.top, 14)
                }.font(.system(size: 12))
            }
        }.studioSurface(22)
    }

    func chapterMetric(_ title: String, count: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.simplifiedForDisplay).font(.system(size: 10)).foregroundColor(Studio.muted)
            Text("\(count) / \(total)").font(.system(size: 16, weight: .medium, design: .monospaced))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    func lessonLearningJourney(_ lesson: LearningLesson) -> some View {
        HStack(alignment: .top, spacing: 8) {
            journeyStep("01", "读懂条件", "本课导读", symbol: "book")
            journeyStep("02", "推演与变招", "在棋盘比较", symbol: "arrow.triangle.branch")
            journeyStep("03", "自己判断", "引擎核对", symbol: "hand.draw")
            journeyStep("04", "独立检验", "隔日再试", symbol: "checkmark.shield")
        }.padding(14).background(Studio.cream.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func journeyStep(_ number: String, _ title: String, _ detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(number).font(.system(size: 10, design: .monospaced))
                Image(systemName: symbol).font(.system(size: 12))
            }.foregroundColor(Studio.green)
            Text(title.simplifiedForDisplay).font(.system(size: 12, weight: .medium))
            Text(detail.simplifiedForDisplay).font(.system(size: 10)).foregroundColor(Studio.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder func lessonTextbookContext(_ lesson: LearningLesson) -> some View {
        if let chapter = GuidedCurriculum.chapters.first(where: { $0.lessonIDs.contains(lesson.id) }) {
            VStack(alignment: .leading, spacing: 8) {
                Label("第 \(chapter.number) 章 · \(chapter.title.simplifiedForDisplay)", systemImage: "books.vertical")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(Studio.green)
                Text(chapter.completionStandard.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                if !lesson.prerequisites.isEmpty {
                    let titles = lesson.prerequisites.compactMap { id in model.lessons.first { $0.id == id }?.title }
                    Text("建议先学：" + titles.joined(separator: "、").simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted)
                }
            }
        }
    }

    var textbookLibrary: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeading("参考书架", detail: "书目、公开选例与原创课程分开标明。未取得正文的教材不标为全文适配。", large: true)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "internaldrive").foregroundColor(Studio.green)
                Text("轻量离线课程 · 原站按需阅读。不会后台下载整本书或视频；原站阅读使用非持久网页缓存。软件讲解是原创编排，不冒充作者原注。")
                    .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5)
            }.studioSurface(16)
            ForEach(GuidedCurriculum.books) { book in
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "book.closed").font(.system(size: 23, weight: .light)).foregroundColor(Studio.green)
                            .frame(width: 45, height: 62).background(Studio.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(book.title.simplifiedForDisplay).font(.system(size: 18, weight: .semibold))
                            Text((book.author + " · " + book.edition).simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted)
                            Text(book.coverage.simplifiedForDisplay).font(.system(size: 12)).lineSpacing(5)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button("打开来源") { openTextbook(book) }.buttonStyle(StudioButtonStyle(compact: true))
                            .accessibilityIdentifier("textbook-open-\(book.id)")
                    }
                    DisclosureGroup("阅读定位与适配范围") {
                        VStack(alignment: .leading, spacing: 13) {
                            ForEach(book.chapters) { reference in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text((reference.title + " · " + reference.locator).simplifiedForDisplay).font(.system(size: 12, weight: .medium))
                                    Text(reference.note.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                                }
                            }
                            Text(book.rightsNote.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.gold).lineSpacing(5)
                        }.padding(.top, 12)
                    }.font(.system(size: 12, weight: .medium))
                    let related = GuidedCurriculum.chapters.filter { $0.readingIDs.contains(book.id) }
                    if !related.isEmpty {
                        HStack(spacing: 8) {
                            Text("回到学习").font(.system(size: 10)).foregroundColor(Studio.muted)
                            ForEach(related) { chapter in
                                Button("第 \(chapter.number) 章") {
                                    expandedChapterID = chapter.id
                                    model.onlySupplements = false; model.query = ""; model.stageFilter = nil; model.onlyBookmarks = false
                                    model.navigate(.courses)
                                }.buttonStyle(StudioButtonStyle(compact: true))
                            }
                        }
                    }
                }.studioSurface(21)
            }
        }
    }

    private func openTextbook(_ book: StudyTextbook) {
        _ = model.recordMaterialExposure(lessonID: model.lessonID)
        readingSource = LearningSource(id: "book-" + book.id, title: book.title, url: book.sourceURL,
                                      note: book.coverage + " " + book.rightsNote)
    }

    @ViewBuilder var studyVariationEntry: some View {
        if let lesson = model.lesson, let line = model.line, let variations = line.variations, !variations.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                Label("变招与应对", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Studio.green)
                Text("从同一分歧点比较目的与应招；查看后，本轮保留辅助记录。")
                    .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                ForEach(variations) { variation in
                    Button {
                        variationPreview = VariationPreviewRequest(lessonID: lesson.id, parent: line, variation: variation)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                            VStack(alignment: .leading, spacing: 5) {
                                Text(variation.title.simplifiedForDisplay).font(.system(size: 12, weight: .medium))
                                Text("分歧前已走 \(variation.anchorPly) 半回合").font(.system(size: 10)).foregroundColor(Studio.muted)
                            }
                            Spacer(minLength: 0)
                        }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Studio.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).disabled(model.busy).accessibilityIdentifier("study-variation-\(variation.id)")
                }
            }
        }
    }
}

struct VariationPreviewRequest: Identifiable {
    var id: String { parent.id + "/" + variation.id }
    let lessonID: String
    let parent: StudyLine
    let variation: StudyVariation
    var preferOriginal = false
    var initialPly = 0
}
