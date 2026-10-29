import Foundation
import AppKit
import NXLibraryCore

extension AppViewModel {
    /// The game the menu-bar Play / Details / Options commands act on. On
    /// Spotlight that is the selected tile, and nothing while a card is
    /// selected; on Collection, the selected cover (nothing when the filter is empty).
    public var currentFocusedGame: PortedGame? {
        if router?.route == .library {
            guard let id = spotlight.selectedGameID else { return nil }
            return libraryGames.first { $0.id == id && !$0.isHidden }
        }
        let games = librarySelection.query.apply(to: libraryGames, history: playSessionStore ?? NoPlayHistory())
        guard !games.isEmpty else { return nil }
        return games.first { $0.id == librarySelection.selectedGameID } ?? games.first
    }

    public func revealSaveFolder(_ url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
