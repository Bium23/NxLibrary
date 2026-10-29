import SwiftUI
import AppKit
import NXLibraryCore

/// Spotlight's controller, keyboard and pointer input.
extension SpotlightView {
    func handle(_ action: GamepadAction) {
        if viewer != nil { return handleViewer(action) }
        if viewModel.spotlight.isLifted { return handleLifted(action) }
        if cardMenu != nil { return handleCardMenu(action) }
        let items = self.items
        let shots = screenshotCount
        let tops = topGameCount
        var moved = false
        switch action {
        case .navigateLeft, .navigateRight:
            let delta = action == .navigateLeft ? -1 : 1
            mutate { state in
                moved = state.focus == .row
                    ? state.move(by: delta, in: items)
                    : state.moveSideways(by: delta, screenshotCount: shots, topGameCount: tops)
            }
        case .navigateDown:
            let isGame = selectedGame != nil
            let isActivity = selectedItem == .card(.activity)
            mutate {
                moved = $0.moveDown(selectedIsGame: isGame, screenshotCount: shots,
                                    selectedIsActivity: isActivity, topGameCount: tops)
            }
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
            if router.isSearchPresented { router.isSearchPresented = false }
            mutate { if $0.focus != .row { $0.focus = .row; moved = true } }
        case .secondaryAction:
            if let game = selectedGame { router.showDetail(game.id) }
        case .contextAction:
            if let game = selectedGame {
                viewModel.gameForSettingsSheet = game
            } else if case .card(let card) = selectedItem {
                cardMenu = CardMenuState(card: card)
                SoundEffectService.shared.play(.click)
            }
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
            openViewer(at: state.stripIndex)
        case .topGames:
            let ids = visibleTopGameIDs
            if state.topGameIndex < ids.count { selectGame(ids[state.topGameIndex]) }
        }
    }

    // MARK: - Screenshot viewer

    func openViewer(at index: Int) {
        guard let game = selectedGame else { return }
        let urls = Array((viewModel.storeMetadata[game.id]?.screenshotURLs ?? [])
            .prefix(SpotlightScreenshotStrip.maxCount))
        guard !urls.isEmpty else { return }
        viewer = ViewerContext(titleID: game.titleId ?? game.uniqueKey, urls: urls,
                               state: ScreenshotViewerState(count: urls.count, start: index))
        SoundEffectService.shared.play(.click)
    }

    /// Closing returns Spotlight's focus to the strip tile last viewed.
    func closeViewer() {
        guard let context = viewer else { return }
        viewer = nil
        let last = context.state.index
        mutate { $0.focus = .strip; $0.stripIndex = last }
        SoundEffectService.shared.play(.focus)
    }

    private func handleViewer(_ action: GamepadAction) {
        guard var context = viewer else { return }
        switch ScreenshotViewer.handle(action, state: &context.state) {
        case .moved:
            viewer = context
            SoundEffectService.shared.play(.focus)
        case .close:
            closeViewer()
        case .ignored:
            break
        }
    }

    // MARK: - Moving a tile

    /// While a tile is lifted only Left/Right, A and B do anything.
    private func handleLifted(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let delta = action == .navigateLeft ? -1 : 1
            let items = self.items
            var moved = false
            mutate { moved = $0.moveLifted(by: delta, in: items) }
            if moved { SoundEffectService.shared.play(.focus) }
        case .confirm:
            var order: [String]?
            mutate { order = $0.drop() }
            if let order {
                // Under a filter, fold the visible order into the full one.
                let full = SpotlightRow.build(
                    games: LibraryQuery(filter: .all).apply(to: viewModel.libraryGames, history: playSessions),
                    enabledCards: settings.settings.spotlightCards,
                    order: settings.settings.spotlightOrder).map(\.key)
                settings.settings.spotlightOrder = SpotlightRow.merging(visibleOrder: order, into: full)
            }
            SoundEffectService.shared.play(.click)
        case .cancel:
            mutate { $0.cancelLift() }
            SoundEffectService.shared.play(.focus)
        default:
            break
        }
    }

    // MARK: - Card menu

    private func handleCardMenu(_ action: GamepadAction) {
        guard let menu = cardMenu else { return }
        let last = SpotlightCardMenu.rows.count - 1
        switch action {
        case .navigateUp: cardMenu?.index = max(0, menu.index - 1)
        case .navigateDown: cardMenu?.index = min(last, menu.index + 1)
        case .confirm: chooseCardMenu(menu.index)
        case .cancel, .contextAction:
            cardMenu = nil
            SoundEffectService.shared.play(.focus)
        default: break
        }
    }

    func chooseCardMenu(_ index: Int) {
        guard let menu = cardMenu else { return }
        cardMenu = nil
        SoundEffectService.shared.play(.click)
        switch index {
        case 0:
            router.requestSpotlightMove(SpotlightItem.card(menu.card).key)
        default:
            hideCard(menu.card)
        }
    }

    /// Removes the card from the row; the selection moves to its neighbour.
    private func hideCard(_ card: SpotlightCard) {
        let before = items
        let key = SpotlightItem.card(card).key
        let neighbour: SpotlightItem? = before.firstIndex { $0.key == key }.flatMap { index in
            index + 1 < before.count ? before[index + 1] : (index > 0 ? before[index - 1] : nil)
        }
        settings.settings.spotlightCards.removeAll { $0 == card }
        if let neighbour, viewModel.spotlight.selectedKey == key { mutate { $0.select(neighbour) } }
        reconcile()
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
            break // Down enters its top games; the full screen comes later.
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
        selectGame(id)
        SoundEffectService.shared.play(.click)
    }

    /// Details asked Spotlight to select a game (More like this): the same path as Surprise.
    func consumePendingSelect() {
        guard let id = router.pendingSpotlightSelect else { return }
        router.pendingSpotlightSelect = nil
        selectGame(id)
    }

    /// Selects a game in the row, switching to All games when the current
    /// filter hides it.
    func selectGame(_ id: UUID) {
        if !items.contains(.game(id)) {
            viewModel.librarySelection.query.filter = .all
        }
        mutate { $0.select(.game(id)) }
        reconcile() // In case the pick is hidden from the row after all.
    }

    // MARK: - Keyboard

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // An alert or sheet owns Return and Esc; consuming them here would
            // replay the action that raised the alert.
            guard !router.isMenuPresented,
                  router.route == .library,
                  viewModel.alertMessage == nil,
                  viewModel.gameForSettingsSheet == nil,
                  !viewModel.showSetupSheet,
                  !viewModel.showInstallerSheet,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText) else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            if viewer != nil {
                // The viewer owns the keyboard: arrows page, Esc closes, the rest is swallowed.
                switch event.keyCode {
                case 123: handle(.navigateLeft)
                case 124: handle(.navigateRight)
                case 53: handle(.cancel)
                case 12: handle(.tabPrevious)
                case 14: handle(.tabNext)
                case 36, 49, 125, 126, 7, 16, 48: break
                default: return event
                }
                return nil
            }
            let action: GamepadAction
            switch event.keyCode {
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 125: action = .navigateDown
            case 126: action = .navigateUp
            case 36, 49: action = .confirm
            case 53:
                // On the row Esc falls through to the shell, which opens the Menu.
                guard viewModel.spotlight.focus != .row || viewModel.spotlight.isLifted
                        || cardMenu != nil else { return event }
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
