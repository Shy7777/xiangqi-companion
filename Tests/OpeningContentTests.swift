import Foundation

@main
struct OpeningContentTests {
    static func main() throws {
        let lessons = OpeningCurriculum.lessons
        let sources = OpeningCurriculum.sources
        precondition(lessons.count >= 12, "Expected at least twelve substantive opening lessons")
        precondition(Set(lessons.map(\.id)).count == lessons.count, "Lesson ids must be unique")
        precondition(Set(sources.map(\.id)).count == sources.count, "Source ids must be unique")
        let sourceIDs = Set(sources.map(\.id))
        var lineIDs = Set<String>()
        var exactLines = Set<String>()
        var branchCount = 0
        var plyCount = 0
        var blackBranches = 0
        var studentDecisions = 0
        var review: [[String: Any]] = []
        let exportAll = CommandLine.arguments.contains("--export-all-review")

        for source in sources {
            precondition(source.id.hasPrefix("opening-"))
            precondition(URL(string: source.url)?.scheme == "https")
            precondition(!source.note.isEmpty)
        }
        for lesson in lessons {
            precondition(lesson.stage == .opening)
            precondition(lesson.id.hasPrefix("opening-"))
            precondition(lesson.lines.count >= 3, "Missing variations: \(lesson.id)")
            precondition([lesson.summary, lesson.goal, lesson.principle, lesson.whenToAdapt].allSatisfy { $0.count >= 15 })
            precondition(lesson.pitfalls.count >= 3 && lesson.pitfalls.allSatisfy { !$0.isEmpty })
            precondition(!lesson.sourceIDs.isEmpty && Set(lesson.sourceIDs).isSubset(of: sourceIDs))
            precondition(lesson.prerequisites.allSatisfy { id in lessons.contains { $0.id == id } })
            var finalPositions = Set<String>()
            for line in lesson.lines {
                precondition(lineIDs.insert(line.id).inserted, "Duplicate line id: \(line.id)")
                precondition((8...16).contains(line.moves.count), "Line outside 8–16 plies: \(line.id)")
                precondition(!line.intent.isEmpty && !line.adaptation.isEmpty)
                let signature = line.startingFEN + " " + line.moves.map(\.uci).joined(separator: " ")
                precondition(exactLines.insert(signature).inserted, "Duplicate full sequence: \(line.id)")
                var position = try Position(fen: line.startingFEN)
                var lastStudentCheckpoint: [String: Any]?
                for (index, item) in line.moves.enumerated() {
                    precondition(item.explanation.count >= 5 && item.hint.count >= 7
                                 && item.explanation.count + item.hint.count >= 14,
                                 "Insufficient teaching content: \(line.id), ply \(index + 1)")
                    guard let move = Move(uci: item.uci) else {
                        throw StudyError.invalidContent("\(line.id), ply \(index + 1): malformed \(item.uci)")
                    }
                    if position.sideToMove == line.studentSide {
                        studentDecisions += 1
                        lastStudentCheckpoint = ["lineID": line.id, "title": line.title,
                            "ply": index + 1, "fen": position.fen, "move": item.uci,
                            "side": line.studentSide.rawValue]
                    }
                    if exportAll {
                        review.append(["lineID": line.id, "title": line.title,
                            "ply": index + 1, "fen": position.fen, "move": item.uci,
                            "side": position.sideToMove.rawValue])
                    }
                    do {
                        position = try position.applying(move: move)
                        try position.validate()
                    } catch {
                        throw StudyError.invalidContent("\(line.id), ply \(index + 1), \(item.uci): \(error.localizedDescription)")
                    }
                }
                let replay = try line.positions()
                precondition(replay.count == line.moves.count + 1 && replay.last == position)
                finalPositions.insert(position.fen)
                if !exportAll, let checkpoint = lastStudentCheckpoint { review.append(checkpoint) }
                branchCount += 1
                plyCount += line.moves.count
                if line.studentSide == .black { blackBranches += 1 }
            }
            precondition(finalPositions.count == lesson.lines.count,
                         "Variations must end in distinct teaching positions: \(lesson.id)")
        }
        precondition(blackBranches >= 6 && blackBranches < branchCount, "Include substantive practice for both sides")
        if CommandLine.arguments.contains("--export-review") || exportAll {
            let data = try JSONSerialization.data(withJSONObject: review, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            return
        }
        print("Opening content PASS: \(lessons.count) lessons, \(branchCount) branches, \(plyCount) legal annotated plies, \(blackBranches) black-side branches, \(sources.count) sources.")
        print("Student decision points: \(studentDecisions).")
        print("All intermediate positions validate; unique line ids and full sequences; 8–16 plies per line; every move has an explanation and a hint.")
    }
}
