import SwiftUI
import AppKit
import NXLibraryCore

/// Collection's controller, keyboard and pointer input.
extension CollectionView {
    func handle(_ action: GamepadAction) {
        var moved = false
        let all = viewModel.visibleCatalogGames
        switch action {
        case .navigateLeft, .navigateRight:
            let before = viewModel.librarySelection.selectedGameID
            viewModel.librarySelection.moveCatalog(by: action == .navigateLeft ? -1 : 1,
                                            in: all, history: playSessions)
            moved = viewModel.librarySelection.selectedGameID != before
        case .navigateUp, .navigateDown:
            break
        case .jumpToStart, .jumpToEnd:
            let before = viewModel.librarySelection.selectedGameID
            viewModel.librarySelection.jumpCatalog(toEnd: action == .jumpToEnd, in: all, history: playSessions)
            moved = viewModel.librarySelection.selectedGameID != before
        case .tabPrevious:
            setFilter(filter.shifted(by: -1))
        case .tabNext:
            setFilter(filter.shifted(by: 1))
        case .rightStickPress:
            setFilter(filter.cycled())
        case .confirm:
            if let record = selectedCatalogGame {
                activateCatalog(record)
            } else if !hasAnyGame, !viewModel.isScanningLibrary {
                SoundEffectService.shared.play(.click)
                router.openAddGame()
            }
        case .secondaryAction:
            // A Steam game's details are its Spotlight page; Collection has no Details screen for it.
            if let game = selectedCatalogGame, game.integration != .steam { router.showDetail(game.id) }
        case .contextAction:
            if let steam = selectedCatalogGame, steam.integration == .steam {
                SoundEffectService.shared.play(.click)
                viewModel.openSteamOptions(steam, from: .collection)
                return
            }
            if let game = selectedGame { viewModel.openGameOptions(game, from: .collection) }
        case .cancel:
            router.showLibrary() // B goes home, like Selene's library.
        case .view:
            if settings.settings.viewButtonSwitches { router.showLibrary() }
        case .viewHold:
            router.isSearchPresented = true
        case .menu:
            router.isMenuPresented = true
        case .menuHold:
            router.openSettings(.startUp)
        }
        if moved { SoundEffectService.shared.play(.focus) }
    }

    func activateCatalog(_ record: CatalogGame) {
        if let native = record.nxnativeGame { play(native) }
        else if record.integration == .steam { SoundEffectService.shared.play(.click); SteamPlayCoordinator.shared.press(record) }
        else { SoundEffectService.shared.play(.click); router.showDetail(record.id) }
    }

    /// A on a cover: plays, or opens Details when the game is not built (Spotlight's rule).
    func play(_ game: PortedGame) {
        SoundEffectService.shared.play(.click)
        if game.isPlayableLocally {
            viewModel.launchGame(game)
        } else {
            router.showDetail(game.id)
        }
    }

    // MARK: - Keyboard

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // An alert or sheet owns Return and Esc; consuming them here would
            // replay the action that raised the alert.
            guard !router.isMenuPresented,
                  !NativeMenuCommands.shared.isTracking,
                  !router.isSearchPresented,
                  !router.isIntroShowing,
                  router.route == .collection,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  !viewModel.isGameOptionsOpen,
                  viewModel.gameToClose == nil,
                  viewModel.gameToRemove == nil,
                  !viewModel.isUpdateOfferOpen,
                  !viewModel.showSetupCheck,
                  !router.isScreenshotViewerOpen,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText) else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 36, 49: action = .confirm
            case 7: action = .secondaryAction   // X
            case 16: action = .contextAction    // Y
            case 12: action = .tabPrevious      // Q
            case 14: action = .tabNext          // E
            default: return event               // Esc falls through to the shell, which opens the Menu.
            }
            handle(action)
            return nil
        }
    }

    func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
