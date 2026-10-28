import Foundation
import Combine

enum BookStudyMode: String, CaseIterable, Identifiable {
    case reading, recall
    var id: String { rawValue }
    var title: String { self == .reading ? "读谱" : "自己走" }
}

struct BookMoveChoice: Identifiable {
    let id: Int
    let title: String
    let comment: String
    let isMainline: Bool
}

struct BookBranchPoint: Identifiable {
    var id: Int { nodeID }
    let nodeID: Int
    let ply: Int
    let title: String
    let choices: [BookMoveChoice]
}

struct BookAnnotatedNode: Identifiable {
    let id: Int
    let title: String
    let comment: String
}

@MainActor
final class BookStudyModel: ObservableObject {
    @Published private(set) var document: BookDocument?
    @Published private(set) var shelf: [BookShelfEntry] = []
    @Published private(set) var selectedRecordID: String?
    @Published private(set) var nodeID = 0
    @Published private(set) var position = Position.initial
    @Published var selected: Square?
    @Published private(set) var targets: [Square] = []
    @Published var flipped = false
    @Published private(set) var mode: BookStudyMode = .reading
    @Published private(set) var isLoading = false
    @Published var notice: String?
    @Published private(set) var feedback = "导入棋书后，按章节读谱。"
    @Published private(set) var positionIssue: String?
    @Published var query = ""
    @Published private(set) var hintLevel = 0
    @Published private(set) var referenceRevealed = false
    @Published private(set) var revision = 0

    private let storage: BookLibraryStorage
    private var state = BookShelfState()
    private var loaded = false
    private var storageWritable = true
    private var operationID = UUID()
    private var recordIndices: [String: Int] = [:]
    private var readingOrder: [String] = []
    private var positionCache: [Int: Position] = [:]
    private var nodeLabels: [Int: String] = [:]
    private var studentSide = Side.red
    private var practiceAnchor = 0
    private var deviation: Position?
    private var bookmarkedPath: [Int: Int] = [:]

    init(directory: URL? = nil) { storage = BookLibraryStorage(directory: directory) }

    var record: BookRecord? { selectedRecordID.flatMap { record(id: $0) } }
    func record(id: String) -> BookRecord? {
        guard let document, let index = recordIndices[id], document.records.indices.contains(index) else { return nil }
        return document.records[index]
    }
    var currentNode: BookNode? { node(nodeID) }
    var currentPly: Int { max(0, path(to: nodeID).count - 1) }
    var isTextOnly: Bool { record?.nodes.count == 1 }
    var canGoBack: Bool { currentNode?.parentID != nil }
    var canGoForward: Bool { !(currentNode?.childIDs.isEmpty ?? true) && positionIssue == nil }
    var canAnalyze: Bool { record != nil && positionIssue == nil && (try? analysisPosition.validate()) != nil }
    var canPractice: Bool { referenceChoiceID != nil && !isTextOnly }
    private var referenceChoiceID: Int? {
        guard positionIssue == nil else { return nil }
        return currentNode?.childIDs.first { id in
            guard let uci = node(id)?.uci, let move = Move(uci: uci) else { return false }
            return (try? position.applying(move: move)) != nil
        }
    }
    var isAwaitingReply: Bool { mode == .recall && position.sideToMove != studentSide && canGoForward }
    var analysisPosition: Position { deviation ?? position }
    var lastMove: Move? { currentNode?.uci.flatMap(Move.init(uci:)) }
    var guide: BookLearningGuidance? {
        guard let record, let chapter = record.chapterNumber else { return nil }
        return BookLearningGuide.guide(chapter: document?.title.contains("弈林新编") == true ? chapter : 0,
                                       sectionTitle: record.sectionTitle)
    }
    var choices: [BookMoveChoice] { choices(at: nodeID) }
    var breadcrumb: [BookMoveChoice] {
        path(to: nodeID).dropFirst().compactMap { id in
            guard let n = node(id) else { return nil }
            return BookMoveChoice(id: id, title: label(for: id), comment: n.comment,
                                  isMainline: n.parentID.flatMap(node)?.childIDs.first == id)
        }
    }
    var branchPoints: [BookBranchPoint] {
        guard let record else { return [] }
        return record.nodes.filter { $0.childIDs.count > 1 }.map {
            let ply = path(to: $0.id).count - 1
            return BookBranchPoint(nodeID: $0.id, ply: ply,
                                   title: ply == 0 ? "起始局面" : "第 \(ply) 手后 · \(label(for: $0.id))",
                                   choices: choices(at: $0.id))
        }
    }
    var annotatedNodes: [BookAnnotatedNode] {
        guard let record else { return [] }
        return record.nodes.filter { !$0.comment.isEmpty }.map {
            BookAnnotatedNode(id: $0.id, title: $0.id == record.rootNodeID ? "本谱导读" : "第 \(path(to: $0.id).count - 1) 手 · \(label(for: $0.id))",
                              comment: $0.comment)
        }
    }
    var arrows: [RecommendationArrow] {
        guard mode == .recall, hintLevel >= 2, let uci = referenceChoiceID.flatMap(node)?.uci,
              let move = Move(uci: uci), (try? position.applying(move: move)) != nil else { return [] }
        return [RecommendationArrow(rank: 1, move: move)]
    }
    var nextRecordTitle: String? {
        guard let id = selectedRecordID, let index = readingOrder.firstIndex(of: id), index + 1 < readingOrder.count else { return nil }
        return record(id: readingOrder[index + 1])?.displayTitle
    }
    var canGoPreviousRecord: Bool { selectedRecordID.flatMap { readingOrder.firstIndex(of: $0) }.map { $0 > 0 } ?? false }

    func bootstrap() async {
        guard !loaded else { return }
        loaded = true
        do { state = try storage.load(); shelf = state.entries }
        catch { storageWritable = false; notice = "书架读取失败，未覆盖原记录：\(error.localizedDescription)"; return }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--import-book"), arguments.indices.contains(index + 1) {
            await importBook(url: URL(fileURLWithPath: arguments[index + 1]))
        } else if let id = state.lastBookID ?? shelf.last?.id { await openBook(id: id) }
    }

    func importBook(url: URL) async {
        guard storageWritable else { return }
        let token = UUID(); operationID = token; isLoading = true
        defer { if operationID == token { isLoading = false } }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let data = try BookLibraryStorage.readBounded(url)
                return (data, try CBLParser.parse(data: data, sourceFilename: url.lastPathComponent))
            }.value
            guard operationID == token, !Task.isCancelled else { return }
            state = try storage.install(data: result.0, document: result.1, state: state)
            shelf = state.entries; install(result.1)
            notice = "已导入 \(result.1.records.count) 条记录。原件与原评注完整保留；不代表已与纸书逐字校对。"
        } catch { if operationID == token { notice = "未导入，原书架保持不变：\(error.localizedDescription)" } }
    }

    func openBook(id: String) async {
        guard let entry = shelf.first(where: { $0.id == id }) else { return }
        let token = UUID(); operationID = token; isLoading = true
        defer { if operationID == token { isLoading = false } }
        do {
            let url = try storage.url(for: entry)
            let book = try await Task.detached(priority: .userInitiated) {
                try CBLParser.parse(data: BookLibraryStorage.readBounded(url), sourceFilename: entry.originalFilename ?? entry.filename)
            }.value
            guard operationID == token, !Task.isCancelled else { return }
            guard book.sourceSHA256 == entry.id else { throw BookLibraryError.message("棋书原件校验值改变，请重新导入另存版本。") }
            state.lastBookID = id; install(book); persist()
        } catch { if operationID == token { notice = "棋书未打开：\(error.localizedDescription)" } }
    }

    private func install(_ book: BookDocument) {
        document = book
        recordIndices = Dictionary(uniqueKeysWithValues: book.records.enumerated().map { ($0.element.id, $0.offset) })
        readingOrder = book.chapters.flatMap(\.recordIDs)
        let first = state.lastRecordByBook[book.sourceSHA256].flatMap { recordIndices[$0] == nil ? nil : $0 }
            ?? (book.title.contains("弈林新编") ? book.records.first(where: { $0.chapterNumber == 4 && $0.nodes.count > 1 })?.id : nil)
            ?? book.records.first?.id
        if let first { chooseRecord(id: first, markVisited: false) }
        persist()
    }

    func chooseRecord(id: String, resume: Bool = true, markVisited: Bool = true) {
        guard !isLoading || document != nil, let target = record(id: id) else { return }
        selectedRecordID = id; mode = .reading; referenceRevealed = false; hintLevel = 0
        positionCache = [:]; nodeLabels = [:]; bookmarkedPath = [:]; deviation = nil
        let initial = target.rawPosition
        positionCache[target.rootNodeID] = initial
        position = initial; nodeID = target.rootNodeID
        if let book = document { state.lastRecordByBook[book.sourceSHA256] = id }
        let saved = resume ? status(for: id).nodeID : target.rootNodeID
        go(to: target.nodes.indices.contains(saved) ? saved : target.rootNodeID, recordsHelp: false, recordVisit: markVisited)
        feedback = target.nodes.count == 1 ? "这是文字导读；阅读后可以标记已读。" : "先看原注，再逐步打谱；想练习时切到「自己走」。"
    }

    func node(_ id: Int) -> BookNode? {
        guard let record, record.nodes.indices.contains(id) else { return nil }
        return record.nodes[id]
    }

    func path(to id: Int) -> [Int] {
        guard let record, record.nodes.indices.contains(id) else { return [] }
        var ids: [Int] = []; var current: Int? = id
        while let value = current, record.nodes.indices.contains(value), ids.count <= record.nodes.count {
            ids.append(value); current = record.nodes[value].parentID
        }
        return ids.reversed()
    }

    private func replay(to id: Int) -> (Position, String?) {
        guard let record else { return (.initial, "请选择棋谱。") }
        var current = record.rawPosition
        do { try current.validate() }
        catch { return (current, "源棋盘待核对：\(error.localizedDescription)。原注仍可阅读。") }
        for step in path(to: id).dropFirst() {
            if let cached = positionCache[step] { current = cached; continue }
            guard let uci = node(step)?.uci, let move = Move(uci: uci) else { return (current, "源着法无法识别，棋盘停在前一局面。") }
            nodeLabels[step] = current.notation(for: move)
            do { current = try current.applying(move: move); positionCache[step] = current }
            catch { return (current, "本谱第 \(path(to: step).count - 1) 手 \(nodeLabels[step] ?? uci) 待核对；棋盘停在前一合法局面，未自动改谱。") }
        }
        return (current, nil)
    }

    func go(to id: Int) { go(to: id, recordsHelp: true) }
    private func go(to id: Int, recordsHelp: Bool, recordVisit: Bool = true) {
        guard let target = node(id) else { return }
        if recordsHelp && mode == .recall { revealReference() }
        let result = replay(to: id)
        position = result.0; positionIssue = result.1; nodeID = id
        selected = nil; targets = []; deviation = nil; hintLevel = 0
        if let parent = target.parentID { bookmarkedPath[parent] = id }
        if recordVisit { updateProgress { $0.nodeID = id; $0.lastVisited = Date() } }
    }

    func back() {
        guard let parent = currentNode?.parentID else { return }
        go(to: parent, recordsHelp: false)
        feedback = "已返回上一步。原来的练习记录仍保留。"
    }

    func forward() {
        guard canGoForward, let child = bookmarkedPath[nodeID].flatMap({ currentNode?.childIDs.contains($0) == true ? $0 : nil })
                ?? currentNode?.childIDs.first else { return }
        let assisted = mode == .recall && !isAwaitingReply
        go(to: child, recordsHelp: assisted)
        if !canGoForward && positionIssue == nil {
            feedback = "这条线路已走完。可以回到分歧点比较其他变化，或选择下一篇。"
        } else {
            feedback = mode == .recall ? (isAwaitingReply ? "已查看本谱走法，接着看对方应招。" : "轮到你，判断下一步。") : ""
        }
    }

    func restart() {
        guard let record else { return }
        go(to: mode == .recall ? practiceAnchor : record.rootNodeID, recordsHelp: false)
        referenceRevealed = false
        feedback = mode == .recall ? "回到本轮起点，再自己判断一次。" : "回到本谱起点。"
    }

    func backToBranch() {
        guard let branch = path(to: nodeID).dropLast().reversed().first(where: { (node($0)?.childIDs.count ?? 0) > 1 }) else {
            feedback = "前面没有分歧点，可用上一步或回到起点。"; return
        }
        go(to: branch, recordsHelp: mode == .recall)
        feedback = "已回到分歧点，可以比较另一种应招。"
    }

    func setMode(_ next: BookStudyMode) {
        guard next != mode else { return }
        if next == .recall && !canPractice { feedback = "先回到一处有后续着法的合法局面。"; return }
        mode = next; selected = nil; targets = []; deviation = nil
        referenceRevealed = false; hintLevel = 0
        if next == .recall { studentSide = position.sideToMove; practiceAnchor = nodeID }
        feedback = next == .recall ? "你执\(studentSide.label)。后续走法已收起；这是复现本谱练习，不是棋力评级。" : "已返回读谱，原注与变招都可查看。"
    }

    func tap(_ square: Square) {
        guard mode == .recall, positionIssue == nil, canGoForward else { return }
        guard !isAwaitingReply else { feedback = "现在轮到对方，点击「看对方应招」。"; return }
        if selected == square { selected = nil; targets = []; return }
        if let from = selected, targets.contains(square) { attempt(Move(from: from, to: square)); return }
        if position[square]?.side == position.sideToMove {
            selected = square; targets = position.legalMoves(from: square).map(\.to)
        } else { selected = nil; targets = [] }
    }

    func attempt(_ move: Move) {
        guard mode == .recall, canGoForward, !isAwaitingReply,
              let next = try? position.applying(move: move) else { feedback = "这步不符合当前棋规，请重新选子。"; return }
        updateProgress(save: false) { $0.attempts += 1 }
        selected = nil; targets = []
        if let matched = currentNode?.childIDs.first(where: { node($0)?.uci == move.uci }) {
            let main = currentNode?.childIDs.first == matched
            updateProgress(save: false) { $0.matched += 1 }
            go(to: matched, recordsHelp: false)
            feedback = main ? "与本谱主线一致。" : "这是本谱收录的变招。"
            if !canGoForward { feedback += "这条线路已走完；可回到分歧点比较其他变化。" }
        } else {
            deviation = next
            updateProgress { $0.offBook += 1 }
            feedback = "这步未被本谱收录，不等于错误。棋盘保留在落子前；可重新判断，或用「分析局面」检验你的变招。"
        }
    }

    func hint() {
        guard mode == .recall, let id = referenceChoiceID, let uci = node(id)?.uci,
              let move = Move(uci: uci) else {
            feedback = "此处没有已通过棋规检查的参考着法，请在读谱中核对原注。"; return
        }
        hintLevel = min(2, hintLevel + 1); updateProgress { $0.hints += 1 }
        feedback = hintLevel == 1 ? "本谱从 \(move.from.coordinate) 的\(position[move.from]?.symbol ?? "棋子")入手。先自己找落点。"
            : "已标出\(currentNode?.childIDs.first == id ? "本谱主线" : "本谱一条变招")走法。这是读谱提示，不是引擎最优解。"
    }

    func revealReference() {
        guard mode == .recall, !referenceRevealed else { return }
        referenceRevealed = true; updateProgress { $0.hints += 1 }
    }

    func status(for recordID: String) -> BookRecordProgress { state.progress[progressKey(recordID)] ?? BookRecordProgress() }
    func markRead() { updateProgress { $0.read.toggle() } }
    func toggleBookmark() { updateProgress { $0.bookmarked.toggle() } }

    func nextRecord() {
        guard let id = selectedRecordID, let index = readingOrder.firstIndex(of: id), index + 1 < readingOrder.count else { return }
        chooseRecord(id: readingOrder[index+1])
    }
    func previousRecord() {
        guard let id = selectedRecordID, let index = readingOrder.firstIndex(of: id), index > 0 else { return }
        chooseRecord(id: readingOrder[index-1])
    }

    private func choices(at id: Int) -> [BookMoveChoice] {
        guard let n = node(id) else { return [] }
        return n.childIDs.enumerated().compactMap { index, child in
            guard let value = node(child) else { return nil }
            return BookMoveChoice(id: child, title: label(for: child), comment: value.comment, isMainline: index == 0)
        }
    }

    func label(for id: Int) -> String {
        if let text = nodeLabels[id] { return text }
        guard let value = node(id), let uci = value.uci, let move = Move(uci: uci) else { return "起始局面" }
        if let parent = value.parentID {
            let replayed = positionCache[parent].map { ($0, Optional<String>.none) } ?? replay(to: parent)
            if replayed.1 == nil {
                let text = replayed.0.notation(for: move); nodeLabels[id] = text; return text
            }
        }
        // Only the selected record is cached. Invalid source lines retain their
        // coordinates rather than receiving invented Chinese move names.
        return "\(move.from.coordinate) → \(move.to.coordinate)"
    }

    private func progressKey(_ id: String) -> String { (document?.sourceSHA256 ?? "") + ":" + id }
    private func updateProgress(save: Bool = true, _ edit: (inout BookRecordProgress) -> Void) {
        guard let id = selectedRecordID else { return }
        let key = progressKey(id); var value = state.progress[key] ?? BookRecordProgress()
        edit(&value); state.progress[key] = value; revision += 1
        if save { persist() }
    }
    private func persist() {
        guard storageWritable else { return }
        do { try storage.save(state) }
        catch { notice = "棋书进度暂未保存：\(error.localizedDescription)" }
    }
}
