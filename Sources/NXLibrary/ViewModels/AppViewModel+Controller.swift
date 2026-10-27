import Foundation
import SwiftUI
import AppKit
import NXLibraryCore

extension AppViewModel {
    public func setupControllerNavigation() {
        GameControllerService.shared.onAction = { [weak self] action in
            self?.handleGamepadAction(action)
        }
    }
    
    public func handleGamepadAction(_ action: GamepadAction) {
        switch action {
        case .tabPrevious:
            SoundEffectService.shared.play(.tabSwitch)
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = (selectedTab - 1 + 5) % 5
            }
            
        case .tabNext:
            SoundEffectService.shared.play(.tabSwitch)
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = (selectedTab + 1) % 5
            }
            
        case .navigateLeft:
            if selectedTab == 0 && !isFocusOnDeck { // Library Tab Carousel
                if focusedGameIndex > 0 {
                    focusedGameIndex -= 1
                    SoundEffectService.shared.play(.focus)
                }
            }
            
        case .navigateRight:
            if selectedTab == 0 && !isFocusOnDeck { // Library Tab Carousel
                if focusedGameIndex < filteredLibraryGames.count - 1 {
                    focusedGameIndex += 1
                    SoundEffectService.shared.play(.focus)
                }
            }
            
        case .navigateDown:
            if selectedTab == 0 && !isFocusOnDeck {
                isFocusOnDeck = true
                SoundEffectService.shared.play(.focus)
            }
            
        case .navigateUp:
            if selectedTab == 0 && isFocusOnDeck {
                isFocusOnDeck = false
                SoundEffectService.shared.play(.focus)
            }
            
        case .confirm:
            SoundEffectService.shared.play(.click)
            if selectedTab == 0 {
                if let game = currentFocusedGame {
                    launchGame(game)
                }
            }
            
        case .cancel:
            if selectedTab == 0 && isFocusOnDeck {
                isFocusOnDeck = false
                SoundEffectService.shared.play(.focus)
            } else if gameForSettingsSheet != nil {
                gameForSettingsSheet = nil
                SoundEffectService.shared.play(.click)
            }
            
        case .secondaryAction: // X: Open Settings
            if selectedTab == 0, let game = currentFocusedGame {
                SoundEffectService.shared.play(.click)
                gameForSettingsSheet = game
            }
            
        case .contextAction: // Y: Reveal Save Folder
            if selectedTab == 0, let game = currentFocusedGame {
                SoundEffectService.shared.play(.click)
                let profile = GameDetailsProfile.inspect(for: game)
                revealSaveFolder(profile.saveDirectory)
            }
            
        case .menu:
            SoundEffectService.shared.play(.click)
            selectedTab = 3 // Settings
        }
    }
    
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
