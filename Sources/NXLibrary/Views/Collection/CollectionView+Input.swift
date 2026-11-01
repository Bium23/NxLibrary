import SwiftUI
import AppKit
import NXLibraryCore

/// Collection's controller, keyboard and pointer input.
extension CollectionView {
    func handle(_ action: GamepadAction) {
        var moved = false
        let all = viewModel.libraryGames
        switch action {
        case .navigateLeft, .navigateRight:
            let before = viewModel.librarySelection.selectedGameID
            viewModel.librarySelection.move(by: action == .navigateLeft ? -1 : 1,
                                            in: all, history: playSessions)
            moved = viewModel.librarySelection.selectedGameID != before
        case .navigateUp, .navigateDown:
            break
        case .jumpToStart, .jumpToEnd:
            let before = viewModel.librarySelection.selectedGameID
            viewModel.librarySelection.jump(toEnd: action == .jumpToEnd, in: all, history: playSessions)
            moved = viewModel.librarySelection.selectedGameID != before
        case .tabPrevious:
            setFilter(filter.shifted(by: -1))
        case .tabNext:
            setFilter(filter.shifted(by: 1))
        case .rightStickPress:
            setFilter(filter.cycled())
        case .confirm:
            if let game = selectedGame {
                play(game)
            } else if !hasAnyGame, !viewModel.isScanningLibrary {
                SoundEffectService.shared.play(.click)
                router.openAddGame()
            }
        case .secondaryAction:
            if let game = selectedGame { router.showDetail(game.id) }
        case .contextAction:
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
                  !router.isSearchPresented,
                  !router.isIntroShowing,
                  router.route == .collection,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  viewModel.gameForSettingsSheet == nil,
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
