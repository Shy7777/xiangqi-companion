import Foundation
import CryptoKit

/// Existing curriculum references are derived once by the caller; never persisted
/// into the user's independent library or credited as newly completed lessons.
enum PositionLibraryCurriculumAdapter {
    static func references(from lessons: [LearningLesson]) -> [LibraryPosition] {
        var seen = Set<String>()
        return lessons.flatMap { lesson in
            lesson.lines.compactMap { line -> LibraryPosition? in
                guard let position = try? Position(fen: line.startingFEN), seen.insert(position.fen).inserted else { return nil }
                let digest = Array(SHA256.hash(data: Data(position.fen.utf8)).prefix(16))
                let id = UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                                     digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
                return LibraryPosition(id: id, fen: position.fen,
                    title: String((lesson.title + " · " + line.title).prefix(200)),
                    category: lesson.isSystematic ? "本机系统课程" : "本机补漏短练",
                    sourceFile: "本机课程引用：\(lesson.id)", importedAt: Date(timeIntervalSince1970: 0),
                    originalResult: nil, originalBestMove: nil, originalTimestamp: nil,
                    originalSource: "课程编号 \(lesson.id) / \(line.id)；教学来源在原课程中列出。此处只引用起始局面。")
            }
        }
    }
}
