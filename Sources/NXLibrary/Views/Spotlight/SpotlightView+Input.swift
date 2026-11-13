import SwiftUI
import AppKit
import NXLibraryCore

/// Spotlight's controller, keyboard and pointer input.
extension SpotlightView {
    func handle(_ action: GamepadAction) {
        if viewer != nil { return handleViewer(action) }
        if viewModel.spotlight.isLifted { return handleLifted(action) }
        if cardMenu != nil { return handleCardMenu(action) }
        if modsHost.isPanelOpen { return modsHost.handlePanel(action) }
        if storeHost.isPanelOpen { return storeHost.panel.handlePanel(action) }
        if viewModel.spotlight.focus == .store {
            if handleStore(action) { return }
            // Y (the card's menu), X and the row's jumps belong to the row, not the store.
            if [.contextAction, .secondaryAction, .jumpToStart, .jumpToEnd].contains(action) { return }
        }
        let items = self.items
        let shots = screenshotCount
        let tops = topGameCount
        let page = currentPage
        let actions = page?.rows.count ?? 0
        let more = page?.more.count ?? 0
        let readMore = page.map { aboutExcerpt($0).truncated } ?? false
        let mods = selectedGame.flatMap { modsHost.game?.id == $0.id ? modsHost.tiles.count : nil } ?? 0
        var moved = false
        switch action {
        case .navigateLeft, .navigateRight:
            let delta = action == .navigateLeft ? -1 : 1
            mutate { state in
                moved = state.focus == .row
                    ? state.move(by: delta, in: items)
                    : state.moveSideways(by: delta, screenshotCount: shots, topGameCount: tops,
                                         actionCount: actions, moreCount: more, readMore: readMore, modsCount: mods)
            }
        case .navigateDown where selectedItem == .card(.mods) && viewModel.spotlight.focus == .row:
            enterStore()
        case .navigateDown:
            let isGame = selectedCatalogGame != nil
            let isActivity = selectedItem == .card(.activity)
            mutate {
                moved = $0.moveDown(selectedIsGame: isGame, screenshotCount: shots,
                                    selectedIsActivity: isActivity, topGameCount: tops,
                                    actionCount: actions, moreCount: more, modsCount: mods)
            }
        case .navigateUp:
            mutate { moved = $0.moveUp(screenshotCount: shots, actionCount: actions, modsCount: mods) }
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
            // X scrolls to the game's page (the pills), like Down from the row.
            if selectedGame != nil || selectedCatalogGame?.integration == .steam {
                mutate { if $0.focus == .row { moved = $0.showGameDetails() } }
            }
        case .contextAction:
            if selectedCatalogGame?.integration == .steam { router.openSettings(.sources); return }
            if let game = selectedGame {
                viewModel.openGameOptions(game, from: .spotlight)
            } else if case .card(let card) = selectedItem {
                cardMenu = CardMenuState(card: card)
                SoundEffectService.shared.play(.click)
            }
        case .view:
            if settings.settings.viewButtonSwitches { router.openCollection() }
        case .viewHold:
            router.isSearchPresented = true
        case .menu:
            router.isMenuPresented = true
        case .menuHold:
            router.openSettings(.startUp)
        case .rightStickPress:
            break
        }
        if moved { SoundEffectService.shared.play(.focus) }
    }

    func pressCatalogPill(_ index: Int, game: CatalogGame) {
        switch index {
        // The positions of Play, Options and favorite: Details and Hide until Steam Play and Options exist.
        case 0: router.showDetail(game.id)
        case 1: viewModel.setCatalogHidden(true, game: game)
        case 2: viewModel.setCatalogFavorite(game)
        default: break
        }
    }

    private func confirm() {
        let state = viewModel.spotlight
        switch state.focus {
        case .row:
            if let item = selectedItem { activate(item) }
        case .pills:
            if let game = selectedGame { pressPill(state.pillIndex, game: game) }
            else if let game = selectedCatalogGame { pressCatalogPill(state.pillIndex, game: game) }
        case .strip:
            openViewer(at: state.stripIndex)
        case .about:
            aboutExpanded.toggle()
            SoundEffectService.shared.play(.click)
        case .actions:
            let rows = currentPage?.rows ?? []
            guard state.actionIndex < rows.count else { return }
            rows[state.actionIndex].action()
        case .more:
            let more = currentPage?.more ?? []
            guard state.moreIndex < more.count else { return }
            SoundEffectService.shared.play(.click)
            selectGame(more[state.moreIndex].id)
        case .mods:
            modsHost.activate(state.modsIndex, viewModel: viewModel, openMods: openMods)
        case .topGames:
            let ids = visibleTopGameIDs
            if state.topGameIndex < ids.count { selectGame(ids[state.topGameIndex]) }
        case .store:
            break // The store takes A itself (`handleStore`).
        }
    }

    // MARK: - Screenshot viewer

    func openViewer(at index: Int) {
        let titleID: String, all: [URL]
        if let game = selectedGame {
            titleID = viewModel.personalizationKey(for: game); all = viewModel.storeMetadata[game.id]?.screenshotURLs ?? []
        } else if let game = selectedCatalogGame, game.integration == .steam {
            titleID = game.personalizationReference.key; all = steamFacts.metadata(for: game)?.screenshots ?? []
        } else { return }
        let urls = Array(all.prefix(SpotlightScreenshotStrip.maxCount))
        guard !urls.isEmpty else { return }
        viewer = ViewerContext(titleID: titleID, urls: urls,
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
                settings.settings.spotlightOrder = SpotlightRow.saving(
                    visibleOrder: order, gameIDs: viewModel.catalogGames.map(\.id),
                    previousOrder: settings.settings.spotlightOrder)
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
        settings.settings.visibleSpotlightCards.removeAll { $0 == card }
        if let neighbour, viewModel.spotlight.selectedKey == key { mutate { $0.select(neighbour) } }
        reconcile()
    }

    /// A on a row item: a game plays (or opens Details when it is not built);
    /// a card does its one obvious thing until the cards get their own screens.
    func activate(_ item: SpotlightItem) {
        switch item {
        case .game(let id):
            if viewModel.visibleCatalogGames.first(where: { $0.id == id })?.integration == .steam {
                SoundEffectService.shared.play(.click); router.showDetail(id); return
            }
            guard let game = viewModel.libraryGames.first(where: { $0.id == id }) else { return }
            if viewModel.portingPills(game) == .porting {
                SoundEffectService.shared.play(.click)
                router.openAddGame()
                return
            }
            play(game)
        case .card(.collection):
            SoundEffectService.shared.play(.click)
            router.openCollection()
        case .card(.surprise):
            surprise()
        case .card(.activity):
            break // Down enters its top games; the full screen comes later.
        case .card(.mods):
            enterStore()
        case .card(.addGame):
            SoundEffectService.shared.play(.click)
            NotificationCenter.default.post(name: .nxLibraryOpenAddGame, object: nil)
        }
    }

    func pressPill(_ index: Int, game: PortedGame) {
        SoundEffectService.shared.play(.click)
        switch viewModel.portingPills(game) {
        case .porting:
            // The porting pill shows the porting.
            router.openAddGame()
            return
        case .failed:
            switch index {
            case 0: viewModel.startBuild(for: game)
            case 1: viewModel.revealLog(for: game)
            default: viewModel.askRemoveGame(game)
            }
            return
        case .unavailable:
            if index == 0, !runningGames.isRunning(game) {
                SoundEffectService.shared.play(.error)
                return
            }
        case .normal, .normalAfterFailure:
            break
        }
        switch index {
        case 0:
            // Resume while the game runs; otherwise Play.
            if runningGames.isRunning(game) {
                runningGames.resume(game)
            } else {
                play(game)
            }
        case 1:
            // Close Game while the game runs (asks first); otherwise Options.
            if runningGames.isRunning(game) {
                viewModel.askCloseGame(game)
            } else {
                viewModel.openGameOptions(game, from: .spotlight)
            }
        default:
            viewModel.toggleFavorite(game)
        }
    }

    private func play(_ game: PortedGame) {
        guard GameResourceState.unavailableReason(for: game) == nil else {
            SoundEffectService.shared.play(.error)
            return
        }
        if game.isPlayableLocally {
            viewModel.launchGame(game)
        } else {
            // Not built yet: scroll down to Build & Sources.
            let canBuild = GameResourceState.sourcesAvailable(for: game)
            mutate { $0.focus = .actions; $0.actionIndex = canBuild ? 1 : 0 }
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { event in
            // An alert or sheet owns Return and Esc; consuming them here would
            // replay the action that raised the alert.
            guard !router.isMenuPresented,
                  !NativeMenuCommands.shared.isTracking,
                  !router.isSearchPresented,
                  !router.isIntroShowing,
                  router.route == .library,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  viewModel.gameForSettingsSheet == nil,
                  viewModel.gameToClose == nil,
                  viewModel.gameToRemove == nil,
                  !viewModel.isUpdateOfferOpen,
                  !viewModel.showSetupCheck,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText) else { return event }
            if event.type == .scrollWheel {
                // An open mod panel takes the wheel: its description scrolls, the page beneath stays.
                if let panel = [modsHost, storeHost.panel].first(where: \.isPanelOpen) {
                    let dy = event.scrollingDeltaY
                    if abs(dy) >= abs(event.scrollingDeltaX) {
                        panel.scrollDetail(by: event.hasPreciseScrollingDeltas ? dy : dy * canvas.u(48),
                                           precise: event.hasPreciseScrollingDeltas)
                    }
                    return nil
                }
                return selectedItem == .card(.mods) ? scrollStore(with: event) : scrollPage(with: event)
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            if modsHost.isPanelOpen || storeHost.isPanelOpen {
                // The mod detail or Find the game panel owns the arrows, Return and Esc.
                guard let action = ModsBandHost.panelAction(keyCode: event.keyCode) else { return event }
                handle(action)
                return nil
            }
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

    // MARK: - Wheel and trackpad

    /// The wheel or trackpad. Between the row and the page it never stops
    /// halfway: the first scroll down from the row runs the same glide as Down,
    /// and scrolling above the pills runs the glide back to the row; the rest of
    /// that gesture is ignored. Inside the page it moves freely, following the
    /// fingers (with the trackpad's momentum) down to the bottom. When it stops,
    /// the focus moves to the nearest section without moving the page.
    func scrollPage(with event: NSEvent) -> NSEvent? {
        guard selectedGame != nil, viewer == nil, cardMenu == nil,
              !viewModel.spotlight.isLifted else { return event }
        let dy = event.scrollingDeltaY
        guard abs(dy) >= abs(event.scrollingDeltaX) else { return event }
        if wheelLocked {
            // A new touch, or a mouse wheel click once the glide is over, starts afresh.
            let fresh = event.phase == .began || (!event.hasPreciseScrollingDeltas && !isGliding)
            guard fresh else { return nil }
            wheelLocked = false
        }
        guard !isGliding else { return nil }
        let focus = viewModel.spotlight.focus
        let onRow = focus == .row || focus == .topGames
        let first = offset(for: .pills)
        let step = event.hasPreciseScrollingDeltas ? dy : dy * canvas.u(48)

        if onRow {
            // Content moving up (scrolling down) leaves the row with the full glide.
            guard focus == .row, step < -2 else { return nil }
            wheelLocked = true
            wheelSettle?.cancel()
            mutate { $0.focus = .pills; $0.pillIndex = 0 }
            SoundEffectService.shared.play(.focus)
            return nil
        }

        let next = scroll + step
        if next > first + 2 {
            // Above the pills: glide back to the row.
            wheelLocked = true
            wheelSettle?.cancel()
            mutate { $0.focus = .row }
            SoundEffectService.shared.play(.focus)
            return nil
        }
        let page = currentPage
        // An open description can run past More like this's resting place.
        let last: (SpotlightPageModel) -> SpotlightFocusArea = {
            !$0.more.isEmpty ? .more : modsHost.localMods != nil ? .mods : .actions
        }
        let bottom = page.map { min(offset(for: last($0)), offset(for: .about)) }
            ?? offset(for: .pills)
        let clamped = min(first, max(bottom, next))
        if event.hasPreciseScrollingDeltas || reduceMotion {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { scroll = clamped }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { scroll = clamped }
        }
        setPageFades(onRow: false,
                     deep: clamped < (offset(for: .strip) + offset(for: .actions)) / 2)
        wheelSettle?.cancel()
        wheelSettle = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            settleFocusOnScroll()
        }
        return nil
    }

    /// Focuses the section whose resting place is nearest the current scroll.
    private func settleFocusOnScroll() {
        guard let page = currentPage else { return }
        // The row is reached only by the glide, never by settling.
        var areas: [SpotlightFocusArea] = [.pills]
        if screenshotCount > 0 { areas.append(.strip) }
        if !page.rows.isEmpty { areas.append(.actions) }
        if modsHost.localMods != nil { areas.append(.mods) }
        if !page.more.isEmpty { areas.append(.more) }
        let current = scroll
        guard let nearest = areas.min(by: { abs(offset(for: $0) - current) < abs(offset(for: $1) - current) }),
              nearest != viewModel.spotlight.focus else { return }
        holdScroll = true
        mutate { state in
            state.focus = nearest
            state.pillIndex = 0
            state.actionIndex = 0
            state.moreIndex = 0
        }
        SoundEffectService.shared.play(.focus)
    }

    func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

// MARK: - Store

extension SpotlightView {
    /// Down (or A) on the Mods card: the store rises below it.
    func enterStore() {
        guard selectedItem == .card(.mods), viewModel.spotlight.focus == .row else { return }
        mutate { $0.focus = .store }
        SoundEffectService.shared.play(.focus)
    }

    /// The store's arrows, A and B; true when it took the action. Up from its top and B give the focus back to
    /// the row.
    func handleStore(_ action: GamepadAction) -> Bool {
        switch action {
        case .navigateUp, .navigateDown, .navigateLeft, .navigateRight, .confirm, .cancel: break
        default: return false
        }
        switch storeHost.handle(action) {
        case .moved:
            SoundEffectService.shared.play(.focus)
        case .leave:
            mutate { $0.focus = .row }
            SoundEffectService.shared.play(.focus)
        case .stayed:
            break
        }
        return true
    }

    /// The wheel or trackpad in the store moves section by section: one notch, or a swipe's worth of travel, is
    /// one section; the first scroll down from the card enters the store with the page's glide.
    func scrollStore(with event: NSEvent) -> NSEvent? {
        guard viewer == nil, cardMenu == nil, !viewModel.spotlight.isLifted else { return event }
        let dy = event.scrollingDeltaY
        guard abs(dy) >= abs(event.scrollingDeltaX) else { return event }
        if event.phase == .began { storeWheel = 0 }
        if wheelLocked {
            // One section per gesture: the rest of a swipe (its momentum too) is ignored.
            let fresh = event.phase == .began || (!event.hasPreciseScrollingDeltas && !isGliding)
            guard fresh else { return nil }
            wheelLocked = false
        }
        guard !isGliding else { return nil }
        let step = event.hasPreciseScrollingDeltas ? dy : dy * canvas.u(48)
        if viewModel.spotlight.focus == .row {
            guard step < -2 else { return nil }
            storeWheel = 0
            wheelLocked = true
            enterStore()
            return nil
        }
        storeWheel += step
        let threshold = canvas.u(90)
        if storeWheel <= -threshold {
            storeWheel = 0
            wheelLocked = true
            _ = handleStore(.navigateDown)
        } else if storeWheel >= threshold {
            storeWheel = 0
            wheelLocked = true
            _ = handleStore(.navigateUp)
        }
        return nil
    }
}
