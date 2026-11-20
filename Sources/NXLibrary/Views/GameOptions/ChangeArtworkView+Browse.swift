import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import NXLibraryCore

/// Browsing a source: opening it, its search, closing it and opening its page.
extension ChangeArtworkView {
    // MARK: - Browsing a source

    func openBrowse(_ source: ArtworkBrowseSource) {
        browsing = source
        browseDraft = subject.name
        browseQuery = subject.name
        startBrowseSearch()
    }

    func submitSearch() {
        let text = browseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { browseDraft = subject.name }
        fieldFocused = false
        SoundEffectService.shared.play(.click)
        let query = text.isEmpty ? subject.name : text
        guard query != browseQuery || browseResult?.page == nil else {
            focus = tiles.isEmpty ? -1 : 0
            return
        }
        browseQuery = query
        startBrowseSearch()
    }

    private func startBrowseSearch() {
        browseResult = nil
        browseItems = [:]
        browseLoading = []
        message = nil
        focus = 0
        browseRound += 1
    }

    func closeBrowse() {
        browsing = nil
        browseResult = nil
        browseItems = [:]
        browseLoading = []
        downloading = false
        fieldFocused = false
        message = nil
        browseRound += 1
        focus = mainFocus
    }

    func openPage() {
        guard browsing != nil, let page = browseResult?.page else { return }
        SoundEffectService.shared.play(.click)
        NSWorkspace.shared.open(page)
    }
}
