import Foundation
import AppKit
import NXLibraryCore

extension AppViewModel {
    /// The game the menu-bar Play / Details / Options commands act on. On
    /// Spotlight that is the selected tile, and nothing while a card is
    /// selected; on Collection, the selected cover (nothing when the filter is empty).
    public var currentFocusedGame: PortedGame? {
        if case .detail(let id) = router?.route { return libraryGames.first { $0.id == id } }
        if router?.route == .library {
            guard let id = spotlight.selectedGameID else { return nil }
            return libraryGames.first { $0.id == id && !$0.isHidden }
        }
        guard router?.route == .collection else { return nil }
        let games = librarySelection.query.applyCatalog(to: visibleCatalogGames, history: playSessionStore ?? NoPlayHistory())
        guard !games.isEmpty else { return nil }
        let selected = games.first { $0.id == librarySelection.selectedGameID } ?? games.first
        return selected?.nxnativeGame
    }

    public func revealSaveFolder(_ url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
