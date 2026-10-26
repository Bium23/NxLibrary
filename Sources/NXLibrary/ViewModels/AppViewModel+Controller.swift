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
                if focusedGameIndex < libraryGames.count - 1 {
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
    
    public var currentFocusedGame: PortedGame? {
        guard !libraryGames.isEmpty else { return nil }
        let clamped = max(0, min(focusedGameIndex, libraryGames.count - 1))
        return libraryGames[clamped]
    }
    
    public func revealSaveFolder(_ url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
