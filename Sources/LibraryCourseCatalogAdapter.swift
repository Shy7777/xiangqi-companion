import Foundation

/// Translates an already-validated synchronization snapshot without revalidating
/// ten thousand chess positions. Only the selected lesson should invoke rules.
enum LibraryCourseCatalogAdapter {
    static func build(snapshot: GitHubLibrarySnapshot) throws -> LibraryCourseCatalog { try build(snapshot) }

    static func build(_ snapshot: GitHubLibrarySnapshot) throws -> LibraryCourseCatalog {
        guard LibraryCourseMembership.isValidCommit(snapshot.pwaCommit),
              snapshot.files.count <= 1_000, snapshot.positions.count <= 50_000,
              Set(snapshot.files.map { $0.file.path }).count == snapshot.files.count else {
            throw LibraryCourseCatalogError.invalid("课程目录的版本或文件列表异常。")
        }
        let reports = snapshot.files.sorted {
            let left = LibraryCourseSection.section(for: $0.file.path).order
            let right = LibraryCourseSection.section(for: $1.file.path).order
            return left != right ? left < right : $0.file.path < $1.file.path
        }
        for report in reports {
            guard LibraryCourseMembership.isSafeSourcePath(report.file.path),
                  (0...20_000).contains(report.total), (0...report.total).contains(report.invalid) else {
                throw LibraryCourseCatalogError.invalid("课程来源文件的计数或路径异常。")
            }
        }
        let fileReports = Dictionary(uniqueKeysWithValues: reports.map { ($0.file.path, $0) })
        let groupOrder = Dictionary(uniqueKeysWithValues: reports.enumerated().map { ($0.element.file.path, $0.offset) })
        var memberships: [String: [LibraryCourseMembership]] = [:]
        var fens: [String: String] = [:]
        var groupItems: [String: [(index: Int, id: String)]] = [:]
        var seenOrigins = Set<String>(), totalOrigins = 0
        for (offset, position) in snapshot.positions.enumerated() {
            if offset.isMultiple(of: 128) { try Task.checkCancellation() }
            guard position.fen.utf8.count <= 512, !position.fen.isEmpty,
                  position.id == LibraryCourseEntry.identifier(fen: position.fen),
                  !position.origins.isEmpty else { throw LibraryCourseCatalogError.invalid("课程局面缺少稳定身份或出处。") }
            if let existing = fens[position.id], existing != position.fen {
                throw LibraryCourseCatalogError.invalid("课程局面身份冲突。")
            }
            fens[position.id] = position.fen
            for origin in position.origins {
                totalOrigins += 1
                guard totalOrigins <= 100_000, let report = fileReports[origin.file],
                      origin.item.fen == position.fen, (1...max(1, report.total)).contains(origin.item.index), report.total > 0,
                      !origin.item.title.isEmpty, origin.item.title.count <= 256, origin.item.category.count <= 256,
                      seenOrigins.insert(origin.file + "\0" + String(origin.item.index)).inserted else {
                    throw LibraryCourseCatalogError.invalid("课程条目出处重复、缺失或超出来源文件范围。")
                }
                let membership = LibraryCourseMembership(groupID: origin.file, title: origin.item.title,
                    sourceIndex: origin.item.index, category: origin.item.category,
                    section: LibraryCourseSection.section(for: origin.file))
                memberships[position.id, default: []].append(membership)
                groupItems[origin.file, default: []].append((origin.item.index, position.id))
            }
        }
        var groups: [LibraryCourseGroup] = [], orderedIDs: [String] = [], seenEntries = Set<String>()
        for report in reports {
            let candidates = (groupItems[report.file.path] ?? []).sorted { $0.index < $1.index }
            guard candidates.count == report.total - report.invalid else { throw LibraryCourseCatalogError.invalid("课程文件的有效条目未完整映射。") }
            var groupSeen = Set<String>()
            let entryIDs = candidates.compactMap { candidate -> String? in
                if seenEntries.insert(candidate.id).inserted { orderedIDs.append(candidate.id) }
                return groupSeen.insert(candidate.id).inserted ? candidate.id : nil
            }
            groups.append(LibraryCourseGroup(id: report.file.path, title: PWADataParser.category(for: report.file.path),
                section: LibraryCourseSection.section(for: report.file.path), entryIDs: entryIDs,
                rawCount: report.total, invalidCount: report.invalid))
        }
        let entries = try orderedIDs.map { id -> LibraryCourseEntry in
            guard let fen = fens[id], let values = memberships[id], !values.isEmpty else {
                throw LibraryCourseCatalogError.invalid("课程目录存在不可达条目。")
            }
            let sorted = values.sorted {
                let left = groupOrder[$0.groupID] ?? Int.max, right = groupOrder[$1.groupID] ?? Int.max
                return left != right ? left < right : $0.sourceIndex < $1.sourceIndex
            }
            return LibraryCourseEntry(id: id, fen: fen, title: sorted[0].title, memberships: sorted)
        }
        guard entries.count == fens.count else { throw LibraryCourseCatalogError.invalid("课程目录未覆盖全部有效局面。") }
        return LibraryCourseCatalog(pwaCommit: snapshot.pwaCommit, entries: entries, groups: groups)
    }
}
