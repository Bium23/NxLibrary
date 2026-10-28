import Foundation
import AppKit
import NXLibraryCore

extension AppViewModel {
    public func handleLibraryGamepadAction(_ action: GamepadAction) {
        let games = librarySelection.query.apply(to: libraryGames)
        switch action {
        case .navigateLeft:
            switch librarySelection.focusArea {
            case .rail:
                librarySelection.move(by: -1, in: libraryGames)
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
                librarySelection.move(by: 1, in: libraryGames)
                SoundEffectService.shared.play(.focus)
            case .filters:
                librarySelection.filterIndex = min(LibraryFilter.allCases.count - 1,
                                                   librarySelection.filterIndex + 1)
                librarySelection.query.filter = LibraryFilter.allCases[librarySelection.filterIndex]
            case .actions:
                librarySelection.actionIndex = min(1, librarySelection.actionIndex + 1)
            }
        case .navigateUp:
            switch librarySelection.focusArea {
            case .rail: librarySelection.focusArea = .actions
            case .actions: librarySelection.focusArea = .filters
            case .filters: break
            }
            SoundEffectService.shared.play(.focus)
        case .navigateDown:
            switch librarySelection.focusArea {
            case .filters: librarySelection.focusArea = .actions
            case .actions: librarySelection.focusArea = .rail
            case .rail: break
            }
            SoundEffectService.shared.play(.focus)
        case .confirm:
            guard let game = games.first(where: { $0.id == librarySelection.selectedGameID }) ?? games.first else { return }
            switch librarySelection.focusArea {
            case .rail:
                launchGame(game)
            case .actions:
                if librarySelection.actionIndex == 0 {
                    launchGame(game)
                } else {
                    gameForSettingsSheet = game
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
        case .tabPrevious:
            librarySelection.filterIndex = max(0, librarySelection.filterIndex - 1)
            librarySelection.query.filter = LibraryFilter.allCases[librarySelection.filterIndex]
        case .tabNext:
            librarySelection.filterIndex = min(LibraryFilter.allCases.count - 1,
                                               librarySelection.filterIndex + 1)
            librarySelection.query.filter = LibraryFilter.allCases[librarySelection.filterIndex]
        }
    }

    public var currentFocusedGame: PortedGame? {
        let games = librarySelection.query.apply(to: libraryGames)
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
