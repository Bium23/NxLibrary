import SwiftUI
import AppKit
import NXLibraryCore

/// Spotlight's controller, keyboard and pointer input.
extension SpotlightView {
    func handle(_ action: GamepadAction) {
        let items = self.items
        let shots = screenshotCount
        var moved = false
        switch action {
        case .navigateLeft, .navigateRight:
            let delta = action == .navigateLeft ? -1 : 1
            mutate { state in
                moved = state.focus == .row
                    ? state.move(by: delta, in: items)
                    : state.moveSideways(by: delta, screenshotCount: shots)
            }
        case .navigateDown:
            let isGame = selectedGame != nil
            mutate { moved = $0.moveDown(selectedIsGame: isGame, screenshotCount: shots) }
        case .navigateUp:
            mutate { moved = $0.moveUp() }
        case .tabPrevious:
            setFilter(filter.shifted(by: -1))
        case .tabNext:
            setFilter(filter.shifted(by: 1))
        case .jumpToStart, .jumpToEnd:
            mutate { moved = $0.jump(toEnd: action == .jumpToEnd, in: items) }
        case .confirm:
            confirm()
        case .cancel:
            mutate { if $0.focus != .row { $0.focus = .row; moved = true } }
        case .secondaryAction:
            if let game = selectedGame { router.showDetail(game.id) }
        case .contextAction:
            if let game = selectedGame { viewModel.gameForSettingsSheet = game }
        case .view:
            router.openCollection()
        case .viewHold:
            router.isSearchPresented = true
        case .menu:
            router.isMenuPresented = true
        case .menuHold:
            router.openSettings(.general)
        case .rightStickPress:
            break
        }
        if moved { SoundEffectService.shared.play(.focus) }
    }

    private func confirm() {
        let state = viewModel.spotlight
        switch state.focus {
        case .row:
            if let item = selectedItem { activate(item) }
        case .pills:
            if let game = selectedGame { pressPill(state.pillIndex, game: game) }
        case .strip:
            break // The screenshot viewer (spec §6.4) comes with a later task.
        }
    }

    /// A on a row item: a game plays (or opens Details when it is not built);
    /// a card does its one obvious thing until the cards get their own screens.
    func activate(_ item: SpotlightItem) {
        switch item {
        case .game(let id):
            guard let game = viewModel.libraryGames.first(where: { $0.id == id }) else { return }
            play(game)
        case .card(.collection):
            SoundEffectService.shared.play(.click)
            router.openCollection()
        case .card(.surprise):
            surprise()
        case .card(.activity):
            break // Activity arrives with its own screen.
        case .card(.addGame):
            SoundEffectService.shared.play(.click)
            NotificationCenter.default.post(name: .nxLibraryOpenAddGame, object: nil)
        }
    }

    func pressPill(_ index: Int, game: PortedGame) {
        SoundEffectService.shared.play(.click)
        switch index {
        case 0:
            play(game)
        case 1:
            if playSessions.isRunning(gameID: game.id) {
                viewModel.closeGame(game)
            } else {
                router.showDetail(game.id)
            }
        default:
            viewModel.toggleFavorite(game)
        }
    }

    private func play(_ game: PortedGame) {
        if game.isPlayableLocally {
            viewModel.launchGame(game)
        } else {
            router.showDetail(game.id)
        }
    }

    /// Surprise me: picks from the configured pool and selects that game on Spotlight.
    private func surprise() {
        var random = SystemRandomNumberGenerator()
        guard let id = Surprise.pick(from: viewModel.libraryGames,
                                     pool: settings.settings.surprisePool,
                                     history: playSessions,
                                     excluding: selectedGame?.id,
                                     random: &random) else {
            SoundEffectService.shared.play(.error)
            return
        }
        if !items.contains(.game(id)) {
            viewModel.librarySelection.query.filter = .all
        }
        mutate { $0.select(.game(id)) }
        SoundEffectService.shared.play(.click)
    }

    // MARK: - Keyboard

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !router.isMenuPresented,
                  router.route == .library,
                  viewModel.gameForSettingsSheet == nil,
                  !viewModel.showSetupSheet,
                  !viewModel.showInstallerSheet,
                  !(event.window?.firstResponder is NSText) else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 125: action = .navigateDown
            case 126: action = .navigateUp
            case 36, 49: action = .confirm
            case 53:
                // On the row Esc falls through to the shell, which opens the Menu.
                guard viewModel.spotlight.focus != .row else { return event }
                action = .cancel
            case 7: action = .secondaryAction   // X
            case 16: action = .contextAction    // Y
            case 12: action = .tabPrevious      // Q
            case 14: action = .tabNext          // E
            default: return event
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
