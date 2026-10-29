import Foundation
import AppKit
import NXLibraryCore

extension AppViewModel {
    public func handleLibraryGamepadAction(_ action: GamepadAction) {
        let games = librarySelection.query.apply(to: libraryGames, history: playSessionStore ?? NoPlayHistory())
        switch action {
        case .navigateLeft:
            switch librarySelection.focusArea {
            case .rail:
                librarySelection.move(by: -1, in: libraryGames, history: playSessionStore ?? NoPlayHistory())
                librarySelection.actionIndex = 0
                SoundEffectService.shared.play(.focus)
            case .filters:
                librarySelection.filterIndex = max(0, librarySelection.filterIndex - 1)
                librarySelection.query.filter = LibraryFilter.allCases[librarySelection.filterIndex]
            case .actions:
                librarySelection.actionIndex = max(0, librarySelection.actionIndex - 1)
            }
        case .navigateRight:
            switch librarySelection.focusArea {
            case .rail:
                librarySelection.move(by: 1, in: libraryGames, history: playSessionStore ?? NoPlayHistory())
                librarySelection.actionIndex = 0
                SoundEffectService.shared.play(.focus)
            case .filters:
                librarySelection.filterIndex = min(LibraryFilter.allCases.count - 1,
                                                   librarySelection.filterIndex + 1)
                librarySelection.query.filter = LibraryFilter.allCases[librarySelection.filterIndex]
            case .actions:
                librarySelection.actionIndex = min(2, librarySelection.actionIndex + 1)
            }
        case .navigateUp:
            switch librarySelection.focusArea {
            case .actions: librarySelection.focusArea = .rail
            case .rail: librarySelection.focusArea = .filters
            case .filters: break
            }
            SoundEffectService.shared.play(.focus)
        case .navigateDown:
            switch librarySelection.focusArea {
            case .filters:
                librarySelection.focusArea = .rail
            case .rail:
                librarySelection.focusArea = .actions
                librarySelection.actionIndex = 0
            case .actions:
                break
            }
            SoundEffectService.shared.play(.focus)
        case .confirm:
            guard let game = games.first(where: { $0.id == librarySelection.selectedGameID }) ?? games.first else { return }
            switch librarySelection.focusArea {
            case .rail:
                launchGame(game)
            case .actions:
                switch librarySelection.actionIndex {
                case 0: launchGame(game)
                case 1: router?.showDetail(game.id)
                default: gameForSettingsSheet = game
                }
            case .filters:
                break
            }
            SoundEffectService.shared.play(.click)
        case .secondaryAction:
            if let game = games.first(where: { $0.id == librarySelection.selectedGameID }) ?? games.first {
                router?.showDetail(game.id)
            }
        case .contextAction:
            if let game = games.first(where: { $0.id == librarySelection.selectedGameID }) ?? games.first {
                gameForSettingsSheet = game
            }
        case .cancel:
            if librarySelection.focusArea != .rail {
                librarySelection.focusArea = .rail
            }
        case .menu:
            NotificationCenter.default.post(name: .nxLibraryOpenMenu, object: nil)
        case .menuHold, .view, .viewHold, .jumpToStart, .jumpToEnd, .rightStickPress:
            break // Not used by the library screen yet.
        case .tabPrevious:
            librarySelection.filterIndex = max(0, librarySelection.filterIndex - 1)
            librarySelection.query.filter = LibraryFilter.allCases[librarySelection.filterIndex]
        case .tabNext:
            librarySelection.filterIndex = min(LibraryFilter.allCases.count - 1,
                                               librarySelection.filterIndex + 1)
            librarySelection.query.filter = LibraryFilter.allCases[librarySelection.filterIndex]
        }
    }

    /// The game the menu-bar Play / Details / Options commands act on. On
    /// Spotlight that is the selected tile, and nothing while a card is selected.
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
