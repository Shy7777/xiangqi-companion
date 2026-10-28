import SwiftUI

enum GitHubLibraryAction {
    case analyze(Position), practice(Position), study(String), read(LearningSource), personal, curated
}

extension LearningCenterView {
    func queueGitHubAction(_ action: GitHubLibraryAction) {
        githubNextAction = action
        githubRequest = nil
    }
    /// Finish the current sheet before presenting another. The request is the
    /// single source of truth for both presentation and content payload.
    func finishGitHubAction() {
        guard let next = githubNextAction else { return }
        githubNextAction = nil
        switch next {
        case .study(let id):
            guard let entry = model.libraryCatalog.entry(id: id) else {
                model.notice = "教程目录仍在载入，请稍后再试。"; return
            }
            // External entry starts a new source scope; do not carry an opening
            // family or search filter into an unrelated endgame tutorial.
            model.libraryQuery = ""; model.libraryFamily = nil; model.libraryStatusFilter = 0
            model.libraryRouteFilterID = nil
            model.startLibraryEntry(entry)
        case .analyze(let position):
            if let onAnalyzePosition { onAnalyzePosition(position) }
            else { model.startGame(from: position, player: position.sideToMove) }
        case .practice(let position): model.startGame(from: position, player: position.sideToMove)
        case .read(let source): readingSource = source
        case .personal: openPositionLibrary()
        case .curated: showResourceCatalog = true
        }
    }
}
