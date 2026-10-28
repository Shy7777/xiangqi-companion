import SwiftUI

extension LearningCenterView {
    var reviewPage: some View {
        let visible = libraryVisibleReviews
        let dueCourses = model.dueTargets
        return VStack(alignment: .leading, spacing: 25) {
            sectionHeading("复习工作台", detail: "回到错误前重新判断，再用间隔检验确认是否稳定。", large: true)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 0) {
                        quietStat("\(model.dueReviews.count)", "个错题到期")
                        quietStat("\(dueCourses.count)", "个分支待复习")
                    }
                    Text("已巩固 \(store.data.reviews.filter(\.resolved).count) / \(store.data.reviews.count) 个错题")
                        .font(.system(size: 11)).foregroundColor(Studio.muted)
                }
                Spacer(minLength: 0)
                if let item = model.dueReviews.first {
                    action("先复习一个", id: "review-next") { model.startReview(item) }
                } else if let target = dueCourses.first {
                    action("检验一个分支", id: "review-next") {
                        model.startLesson(target.lesson, line: target.line, mode: .test)
                    }
                }
            }.padding(.vertical, 4)
            HStack(spacing: 8) {
                filterPill("待复习", active: reviewFilter == 0) { reviewFilter = 0 }
                    .accessibilityIdentifier("review-filter-due")
                filterPill("全部", active: reviewFilter == 1) { reviewFilter = 1 }
                    .accessibilityIdentifier("review-filter-all")
                filterPill("已巩固", active: reviewFilter == 2) { reviewFilter = 2 }
                    .accessibilityIdentifier("review-filter-consolidated")
            }
            if visible.isEmpty && (reviewFilter == 2 || dueCourses.isEmpty) {
                StudioEmpty(symbol: reviewFilter == 2 ? "leaf" : "checkmark.circle",
                            title: libraryReviewEmptyTitle, detail: libraryReviewEmptyDetail)
                if reviewFilter == 0 && !store.data.reviews.isEmpty {
                    Button("查看全部错题") { reviewFilter = 1 }.buttonStyle(StudioButtonStyle())
                } else if store.data.reviews.isEmpty {
                    Button("去练一个主题") { model.navigate(.courses) }.buttonStyle(StudioButtonStyle())
                }
            }
            if !visible.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    libraryListHeader(reviewFilter == 2 ? "已经巩固的错题" : "从错误前再来一次",
                                      trailing: "\(visible.count) 个局面")
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { item in
                            libraryReviewRow(item)
                            if item.id != visible.last?.id { Divider().padding(.leading, 36) }
                        }
                    }
                }
            }
            if reviewFilter != 2 && !dueCourses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    libraryListHeader("到期课程 · 撤掉提示再走", trailing: "\(dueCourses.count) 个分支")
                    LazyVStack(spacing: 0) {
                        ForEach(dueCourses) { target in
                            libraryDueCourseRow(target)
                            if target.id != dueCourses.last?.id { Divider().padding(.leading, 36) }
                        }
                    }
                }
            }
            DisclosureGroup("怎样才算巩固，而不只是记住答案？") {
                Text("错题需要两次间隔成功；后一次与上次接触需跨日且至少间隔 20 小时。看提示、看反击或刚重试过，仍然是有用的练习，但不会额外累计独立成功。课程复习与错题分别记录。")
                    .font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5).padding(.top, 9)
            }.font(.system(size: 12)).padding(.top, 4)
        }
    }

    private var libraryVisibleReviews: [ReviewItem] {
        let now = Date()
        return store.data.reviews.filter { item in
            switch reviewFilter {
            case 0: return !item.resolved && item.due <= now
            case 2: return item.resolved
            default: return true
            }
        }.sorted { a, b in
            if a.resolved != b.resolved { return !a.resolved }
            if a.due != b.due { return a.due < b.due }
            return a.created < b.created
        }
    }
    private var libraryReviewEmptyTitle: String {
        if reviewFilter == 2 { return "巩固，需要一点间隔。" }
        return store.data.reviews.isEmpty ? "还没有需要重练的错误。" : "今天的到期复习已处理。"
    }
    private var libraryReviewEmptyDetail: String {
        if reviewFilter == 2 { return "独立处理同一错误，再隔日回来验证。达到两次间隔成功后，它会出现在这里。" }
        if store.data.reviews.isEmpty { return "先正常练习。课程或实战里值得回看的偏差，会自动留在这里，不需要你手动抄题。" }
        return "未到期的错题仍保留在「全部」中。可以提前练，但不必靠当天反复重刷追求通过数。"
    }
    private func libraryReviewRow(_ item: ReviewItem) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: item.resolved ? "checkmark.circle" : "arrow.counterclockwise")
                .font(.system(size: 16, weight: .medium)).foregroundColor(item.resolved ? Studio.green : Studio.gold)
                .frame(width: 23).padding(.top, 3)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title.simplifiedForDisplay).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text("\(item.lessonID == nil ? "实战局面" : "课程错题") · 出现 \(item.occurrences) 次 · \(libraryDueLabel(item))")
                    .font(.system(size: 11)).foregroundColor(Studio.muted)
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        ForEach(0..<2, id: \.self) { index in
                            Capsule().fill(index < item.successfulReviews ? Studio.green : Studio.line.opacity(0.7))
                                .frame(width: 24, height: 4)
                        }
                    }.accessibilityHidden(true)
                    Text("间隔成功 \(min(2, item.successfulReviews))/2")
                        .font(.system(size: 10)).foregroundColor(Studio.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(item.resolved ? "再练一次" : item.due <= Date() ? "独立重练" : "提前练习") { model.startReview(item) }
                .buttonStyle(StudioButtonStyle(compact: true))
                .help("回到错误前，先隐藏答案。提前练习不一定增加间隔成功次数。")
                .accessibilityIdentifier("review-item-\(item.id.uuidString)")
        }.padding(.vertical, 18)
    }
    private func libraryDueLabel(_ item: ReviewItem) -> String {
        if item.resolved { return "已巩固" }
        if item.due <= Date() { return "现在可复习" }
        return "下次 " + item.due.formatted(date: .abbreviated, time: .omitted)
    }
    private func libraryDueCourseRow(_ target: StudyTarget) -> some View {
        let progress = store.progress(target.lesson.id, target.line.id)
        return HStack(alignment: .top, spacing: 13) {
            Image(systemName: Studio.symbol(target.lesson.stage)).font(.system(size: 16))
                .foregroundColor(Studio.color(target.lesson.stage)).frame(width: 23).padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                Text(target.lesson.title.simplifiedForDisplay).font(.system(size: 14, weight: .semibold))
                Text("分支 \((target.lesson.lines.firstIndex(where: { $0.id == target.line.id }) ?? 0) + 1) · 不提前显示应对")
                    .font(.system(size: 12)).foregroundColor(Studio.muted)
                Text("执\(target.line.studentSide.label) · 已练 \(progress.completions) 轮 · 隔日通过 \(progress.delayedTests) 次")
                    .font(.system(size: 10)).foregroundColor(Studio.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("无提示检验") { model.startLesson(target.lesson, line: target.line, mode: .test) }
                .buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("review-course-\(target.id)")
        }.padding(.vertical, 17)
    }

    var progressPage: some View {
        let tests = store.data.runs.filter { $0.mode == .test }
        return VStack(alignment: .leading, spacing: 28) {
            sectionHeading("能力与训练记录", detail: "记录来自真实完成的练习，不用引擎辅助胜局换算段位。", large: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 22)], alignment: .leading, spacing: 18) {
                libraryProgressMetric(tests.isEmpty ? "—" : "\(tests.filter(\.independent).count) / \(tests.count)", title: "无提示通过", detail: "通过轮次 / 已完成检验")
                libraryProgressMetric("\(tests.filter(\.delayed).count)", title: "隔日通过", detail: "跨日且距上次接触 ≥ 20 小时")
                libraryProgressMetric("\(tests.filter(\.transfer).count)", title: "首次分支通过", detail: "未在本软件接触过该分支")
            }.padding(.vertical, 5)
            libraryPracticeRhythm
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("练过什么，哪些能独立处理", detail: "布局、中局、残局与实战思路统计系统主线，基本功单列旧补漏题；完整历史仍保留在下方。进度不是掌握度。")
                VStack(spacing: 0) {
                    ForEach(LearningStage.allCases) { stage in
                        libraryStageProgress(stage)
                        if stage != .strategy { Divider().padding(.leading, 35) }
                    }
                }
            }
            DisclosureGroup("这些数字能说明什么？") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("看过答案、用过提示、发生错误后重试，本轮都不会记成无提示通过。只统计已经完成的检验；未完成或主动退出的测验不进入分母。")
                    Text("首次分支通过只表示未在本软件看过该分支，不等于掌握所有相似局面。隔日通过看稳定性，不能替代长期无辅助实战。")
                    Text("记录的是完成轮次与日期，没有推算你真实花费的分钟数，也没有把演示观看当作无提示练习。")
                }.font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5).padding(.top, 10)
            }.font(.system(size: 12))
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    libraryListHeader("全部学习记录", trailing: "\(store.data.runs.count) 轮")
                    Menu {
                        Button("导出学习记录") { model.exportProgress() }
                        Button("恢复学习备份") { model.restoreProgress() }
                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 17)) }
                        .menuStyle(.borderlessButton).fixedSize().help("学习记录导出与恢复")
                }
                if store.data.runs.isEmpty {
                    StudioEmpty(symbol: "chart.bar.xaxis", title: "从第一次完成开始。", detail: "看完一个演示、练完一个分支或完成一次检验后，真实记录会出现在这里。")
                    Button("去选一课") { model.navigate(.courses) }.buttonStyle(StudioButtonStyle())
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(store.data.runs.sorted { $0.date > $1.date }) { run in
                            libraryRunRow(run)
                            Divider().padding(.leading, 35)
                        }
                    }
                }
            }
        }
    }
    private func libraryProgressMetric(_ value: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.simplifiedForDisplay).font(.system(size: 12, weight: .medium)).foregroundColor(Studio.muted)
            Text(value).font(.system(size: 29, weight: .medium, design: .rounded)).foregroundColor(Studio.green)
            Text(detail.simplifiedForDisplay).font(.system(size: 10)).foregroundColor(Studio.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var libraryPracticeDays: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let counts = store.data.runs.filter { $0.mode != .demonstration }.reduce(into: [Date: Int]()) { result, run in
            result[calendar.startOfDay(for: run.date), default: 0] += 1
        }
        return (0..<14).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 13, to: today) else { return nil }
            return (day, counts[day, default: 0])
        }
    }
    private var libraryPracticeRhythm: some View {
        let days = libraryPracticeDays
        return VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近 14 天的练习节奏").font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(days.filter { $0.count > 0 }.count) 天练过 · 完成 \(days.reduce(0) { $0 + $1.count }) 轮")
                    .font(.system(size: 11)).foregroundColor(Studio.muted)
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                    VStack(spacing: 7) {
                        Text(day.count == 0 ? "·" : "\(day.count)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .foregroundColor(day.count >= 3 ? Studio.white : Studio.green)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(libraryHeatColor(day.count), in: RoundedRectangle(cornerRadius: 7))
                        Text(index == days.count - 1 ? "今天" : day.date.formatted(.dateTime.day()))
                            .font(.system(size: 9)).foregroundColor(Studio.muted)
                    }.frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted))，完成练习与检验 \(day.count) 轮")
                        .help("\(day.date.formatted(date: .abbreviated, time: .omitted)) · 完成 \(day.count) 轮")
                }
            }
            Text("每格显示当天完成的引导练习与检验轮次；不含演示、未完成练习或对局时长。")
                .font(.system(size: 10)).foregroundColor(Studio.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 19)
            .overlay(alignment: .top) { Divider() }.overlay(alignment: .bottom) { Divider() }
    }
    private func libraryHeatColor(_ count: Int) -> Color {
        count == 0 ? Studio.line.opacity(0.35) : Studio.green.opacity(min(0.92, 0.16 + Double(count) * 0.19))
    }
    private func libraryStageProgress(_ stage: LearningStage) -> some View {
        let supplements = stage == .foundation
        let lessons = model.lessons.filter { $0.stage == stage && (supplements ? !$0.isSystematic : $0.isSystematic) }
        let total = lessons.reduce(0) { $0 + $1.lines.count }
        let practiced = lessons.reduce(0) { n, lesson in n + lesson.lines.filter { store.progress(lesson.id, $0.id).completions > 0 }.count }
        let independent = lessons.reduce(0) { n, lesson in n + lesson.lines.filter { store.progress(lesson.id, $0.id).cleanTests > 0 }.count }
        return Button {
            model.query = ""; model.onlyBookmarks = false; model.onlySupplements = supplements
            model.stageFilter = stage; model.navigate(.courses)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: Studio.symbol(stage)).font(.system(size: 16)).foregroundColor(Studio.color(stage)).frame(width: 22)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(Studio.stageName(stage)).font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 8)
                        Text("练过 \(practiced)/\(total) · 独立通过 \(independent) 个分支")
                            .font(.system(size: 10)).foregroundColor(Studio.muted)
                    }
                    StudioProgress(value: Double(practiced) / Double(max(1, total)), color: Studio.color(stage))
                }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(Studio.muted)
            }.padding(.vertical, 17).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("progress-stage-\(stage.rawValue)")
    }
    private func libraryRunRow(_ run: StudyRun) -> some View {
        let lesson = model.lessons.first { $0.id == run.lessonID }
        let branch = lesson?.lines.first { $0.id == run.lineID }
        return HStack(alignment: .top, spacing: 13) {
            Image(systemName: run.mode == .demonstration ? "play.rectangle" : run.independent ? "checkmark.circle" : "pencil")
                .font(.system(size: 15)).foregroundColor(run.independent ? Studio.green : Studio.muted).frame(width: 22).padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(lesson?.title.simplifiedForDisplay ?? run.lessonID).font(.system(size: 13, weight: .medium))
                Text(branch?.title.simplifiedForDisplay ?? run.lineID).font(.system(size: 11)).foregroundColor(Studio.muted)
                Text("\(run.mode.title) · 提示 \(run.hints) 次 · 偏差 \(run.errors) 次\(run.wasRetry ? " · 含重试" : "")")
                    .font(.system(size: 10)).foregroundColor(Studio.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 7) {
                Text(run.delayed ? "隔日通过" : run.independent ? "无提示通过" : run.mode == .demonstration ? "看过演示" : "练习完成")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(run.independent ? Studio.green : Studio.muted)
                if run.transfer { Text("首次分支").font(.system(size: 9)).foregroundColor(Studio.gold) }
                Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundColor(Studio.muted)
            }
        }.padding(.vertical, 16)
    }

    var resourcesPage: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Text("设置").font(.system(size: 28, weight: .semibold, design: .serif)); Spacer()
                Button("打开书架") { showResourceCatalog = true }.buttonStyle(StudioButtonStyle(compact: true))
            }
            DisclosureGroup("教材主题对照") { bookCoveragePanel.padding(.top, 18) }.font(.system(size: 14, weight: .medium))
            DisclosureGroup("参考书架与原站阅读") { textbookLibrary.padding(.top, 18) }
                .font(.system(size: 14, weight: .medium)).accessibilityIdentifier("reference-bookshelf")
            DisclosureGroup("拓展阅读与完整讲棋节目") {
                professionalReading.padding(.top, 20)
            }.font(.system(size: 14, weight: .medium))
            Divider().padding(.vertical, 8)
            sectionHeading("数据与备份", detail: "保存在本机")
            VStack(alignment: .leading, spacing: 0) {
                librarySettingsRow("课程资料", detail: "导入时核对编号、来源、棋局和每一步合法性。", symbol: "books.vertical") {
                    Button("导入课程包") { model.importCourses() }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("import-courses")
                    Button("导出全部课程") { model.exportCourses() }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("export-courses")
                }
                Divider().padding(.leading, 35)
                librarySettingsRow("学习记录与备份", detail: "恢复前先校验，并保留被替换的原记录副本。", symbol: "externaldrive") {
                    Button("导出学习记录") { model.exportProgress() }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("export-learning")
                    Button("恢复学习备份") { model.restoreProgress() }.buttonStyle(StudioButtonStyle(compact: true)).accessibilityIdentifier("restore-learning")
                }
                Divider().padding(.leading, 35)
                HStack(spacing: 13) {
                    Image(systemName: "clock").font(.system(size: 17)).foregroundColor(Studio.green).frame(width: 22)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("每天留一点时间").font(.system(size: 14, weight: .medium))
                        Text("只用于安排计划，不是倒计时，也不是实际用时统计。")
                            .font(.system(size: 11)).foregroundColor(Studio.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Picker("每日计划时长", selection: Binding(get: { store.data.dailyMinutes }, set: { store.setDailyMinutes($0) })) {
                        ForEach([10, 20, 30, 45], id: \.self) { Text("\($0) 分钟").tag($0) }
                    }.labelsHidden().frame(width: 118).accessibilityIdentifier("daily-minutes")
                }.padding(.vertical, 21)
            }
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading("研究方法与评价边界", detail: "先评估形势，再提出计划；候选着法必须经过对方最强抵抗的检验。")
                DisclosureGroup("系统进阶，怎样练才有迁移？") {
                    VStack(alignment: .leading, spacing: 14) {
                        libraryContractRow(.opening, "给选定布局建立分支地图：对手怎样争先、兑子、换阵形？按中局计划分类，而不是只背着序。")
                        libraryContractRow(.strategy, "每个节点先比较子力质量、弱点、空间与主动权；提出两种计划，说明取舍。")
                        libraryContractRow(.tactics, "每个候选都算对手最强回应，再算自己的后续；不要只沿着希望对方配合的线路计算。")
                        libraryContractRow(.endgame, "交换前先看剩余组合、兵的位置和将帅活动；用实战验证能否兑现或守和。")
                        Text("关键点逐题由引擎评估；回到原谱是另一个研究动作，不代表你的变招自然接到了原谱。基础短谱单独作为补漏资料。")
                            .font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                    }.padding(.top, 13)
                }
                Divider()
                DisclosureGroup("遇到这些词，随手查一下") {
                    VStack(alignment: .leading, spacing: 12) {
                        libraryGlossary("出子", "让车、马、炮真正能参与攻防，而不只是离开原来的格子。")
                        libraryGlossary("先手", "你的威胁迫使对方先回应；无意义的将军不一定赚先手。")
                        libraryGlossary("有根 / 无根", "有没有己子保护。有人保护也未必不能吃，还要算交换。")
                        libraryGlossary("炮架", "炮吃子时隔着的那一枚棋子；它一移开，攻击关系就变了。")
                        libraryGlossary("马腿", "马前进方向上的相邻直格；被堵住时，相应的跳法走不了。")
                        libraryGlossary("变招", "对手或局面改变以后，调整走法，而不是继续照抄原谱。")
                    }.padding(.top, 13)
                }
                Divider()
                DisclosureGroup("分数、候选与教学走法，应该怎样看？") {
                    libraryExplanation([
                        "兵分是引擎评价，不是你的获胜概率。分析区顶部采用红方视角；候选与陪练分析标出当前行棋方视角，比较前先看清标注。",
                        "Top 1 是本次限时搜索的首选，不是证明了唯一最佳。青色教学箭头来自课程编排；走出另一种合法好棋，也可以成立。",
                        "谱外着法比较走前与走后，统一为你方视角。搜索不稳定时不计错，可以加深；明显偏差可以看反击、回到原位重练。",
                        "陪练档位调节搜索，并不对应真人段位。皮卡鱼负责计算，课程的目标与解释来自资料核对及原创编排。"
                    ])
                }
                Divider()
                DisclosureGroup("离线使用、棋规与能力边界") {
                    libraryExplanation([
                        "本版不捕获屏幕、不自动同步天天象棋、不对外自动落子，也不上传棋局与学习记录。主动点击资料链接时，才会打开外部网页。",
                        "课程和陪练记录与原手动分析棋局分别保存。导出课程是导出全部课程，不是空白模板；新增课程需使用自己的编号，不能原样重复导入。",
                        "本机检查基础走法、将军与无合法走法，但不完整裁决比赛中的长将、长捉及重复局面争议，不能代替赛事裁判。",
                        "有限题库不保证练成大师。课程完成不是棋力认证；真正的提升，要在长期无辅助实战里检验。"
                    ])
                }
            }.font(.system(size: 13))
            VStack(alignment: .leading, spacing: 13) {
                sectionHeading("来源与内容分层", detail: "原站专业教程 / 公开实战记录 / 软件补充导读 / 旧版原创补漏题，分别标明。")
                DisclosureGroup("查看 \(model.sources.count) 项资料来源") {
                    VStack(alignment: .leading, spacing: 17) { sourceRows(model.sources) }.padding(.top, 14)
                }.font(.system(size: 12)).accessibilityIdentifier("learning-sources")
                Text("公开可读不等于允许整本复制。课程可扩展，但不复制付费题库、整篇网页或整本教材。")
                    .font(.system(size: 10)).foregroundColor(Studio.muted).lineSpacing(4)
            }
        }
    }
    private func librarySettingsRow<Controls: View>(_ title: String, detail: String, symbol: String,
                                                  @ViewBuilder controls: () -> Controls) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: symbol).font(.system(size: 17)).foregroundColor(Studio.green).frame(width: 22).padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.simplifiedForDisplay).font(.system(size: 14, weight: .medium))
                    Text(detail.simplifiedForDisplay).font(.system(size: 11)).foregroundColor(Studio.muted).lineSpacing(4)
                }
            }
            HStack(spacing: 9) { controls() }.padding(.leading, 35)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
    }
    private func libraryContractRow(_ stage: LearningStage, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(stage.shortTitle).font(.system(size: 12, weight: .semibold)).foregroundColor(Studio.color(stage)).frame(width: 65, alignment: .leading)
            Text(detail.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func libraryGlossary(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title.simplifiedForDisplay).font(.system(size: 12, weight: .medium)).frame(width: 78, alignment: .leading)
            Text(detail.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func libraryExplanation(_ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(paragraphs, id: \.self) { Text($0.simplifiedForDisplay).font(.system(size: 12)).foregroundColor(Studio.muted).lineSpacing(5) }
        }.padding(.top, 13)
    }
    private func libraryListHeader(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.simplifiedForDisplay).font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 8)
            Text(trailing.simplifiedForDisplay).font(.system(size: 10)).foregroundColor(Studio.muted)
        }.padding(.bottom, 7).overlay(alignment: .bottom) { Divider() }
    }
}
