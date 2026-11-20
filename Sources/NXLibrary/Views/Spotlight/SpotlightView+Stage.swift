import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// Spotlight's stage: the row, the game's info, the overlays over them and the hero art behind.
extension SpotlightView {
    @ViewBuilder
    func storeOverlay(_ model: Snapshot) -> some View {
        if model.selectedItem == .card(.mods), let game = storeHost.panel.game {
            ModsBandOverlay(host: storeHost.panel, find: storeHost.panel.find, game: game)
        }
    }

    @ViewBuilder
    var viewerOverlay: some View {
        if let viewer {
            ScreenshotViewer(titleID: viewer.titleID, urls: viewer.urls, state: viewer.state,
                             artwork: artwork, onClose: closeViewer)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    func achievementsOverlay(_ model: Snapshot) -> some View {
        if let screen = achievementsScreen, let game = model.selectedCatalogGame, let summary = selectedAchievements {
            AchievementsScreen(model: screen, game: game, summary: summary, art: shownArt(model),
                               onFilter: { filter in
                                   guard filter != screen.state.filter else { return }
                                   screen.setFilter(filter, summary: summary)
                                   SoundEffectService.shared.play(.tabSwitch)
                               },
                               onShiftFilter: { delta in
                                   screen.shiftFilter(by: delta, summary: summary)
                                   SoundEffectService.shared.play(.tabSwitch)
                               },
                               onCycleOrder: {
                                   screen.cycleOrder(summary: summary)
                                   SoundEffectService.shared.play(.tabSwitch)
                               },
                               onFocus: { index in
                                   // A click on the focused row opens it, as A does.
                                   guard index != screen.state.index else {
                                       if screen.openDetail() { SoundEffectService.shared.play(.click) }
                                       return
                                   }
                                   screen.focus(index)
                                   SoundEffectService.shared.play(.focus)
                               },
                               onOpen: { if screen.openDetail() { SoundEffectService.shared.play(.click) } },
                               onCloseDetail: {
                                   screen.closeDetail()
                                   SoundEffectService.shared.play(.focus)
                               },
                               onClose: closeAchievements)
                .transition(.opacity)
        }
    }

    func stage(_ model: Snapshot, state: SpotlightState) -> some View {
        let items = model.items
        return ZStack(alignment: .topLeading) {
            SpotlightTopBar(filter: filter, showClock: settings.settings.showClock,
                            onSelect: { if !state.isLifted { setFilter($0) } })
                // Comes in last with the hints (`finishEntrance`).
                .opacity(rowShown && controlsShown ? 1 : 0)
                .allowsHitTesting(rowShown && entrance.takesInput)

            ZStack(alignment: .topLeading) {
                SpotlightRowView(
                    items: items,
                    gamesByID: model.gamesByID,
                    catalogGamesByID: model.catalogGamesByID,
                    selectedKey: state.selectedKey,
                    liftedKey: state.lift?.key,
                    isEmptyFilter: LibraryEmptyState.showsMessage(
                        hasGames: items.contains { if case .game = $0 { return true } else { return false } },
                        isReadingLibrary: viewModel.isScanningLibrary) ? filter : nil,
                    artwork: artwork,
                    tileLook: viewModel.portingTileLook,
                    modsCover: storeHost.cover,
                    entrance: entrance,
                    onEntranceEnd: { finishEntrance() },
                    onSelect: { item in
                        guard !state.isLifted else { return }
                        mutate { $0.select(item) }
                    },
                    onActivate: { item in
                        guard !state.isLifted else { return }
                        mutate { $0.select(item) }
                        activate(item)
                    }
                )
                .offset(y: canvas.u(130))
                // The icons give way as the page rises (and stop taking the pointer).
                .opacity(rowOpacity)
                .allowsHitTesting(rowShown && entrance.takesInput)
                .onPreferenceChange(TileArtPendingKey.self, perform: tileArtPending)

                SpotlightFilterPill(filter: pillFilter, count: model.rowGameCount)
                    .offset(x: canvas.u(80), y: canvas.u(88))
                    // Opacity fades always run, reduce motion or not.
                    .opacity(pillVisible && !entrance.holdsHidden ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: pillVisible)
                    .animation(entranceRise, value: entrance.holdsHidden)

                info(model, state: state)
                    .offset(x: canvas.u(80), y: canvas.u(420))
                    .entrance(entrance == .landed ? nil : SpotlightEntrance.info, launched: entranceLaunched,
                              unit: canvas.u(1))
                    .allowsHitTesting(entrance.takesInput)
            }
            .onPreferenceChange(SpotlightBlockKey.self) { heights in
                if !Self.sameLayout(heights, blocks) { blocks = heights }
            }
            .onPreferenceChange(SpotlightReadMoreKey.self) { shown in
                if shown != aboutReadMore { aboutReadMore = shown }
            }
            // Every block rides the glide as one: the fades that run beside it (`setPageFades`) re-timed leaves
            // of their own and they slid at their own pace (`GlideGroup`).
            .modifier(GlideGroup())
            // One page: the focus scrolls it; the glide is movement, so reduce motion jumps.
            .offset(y: scroll)
            // The page fades out short of the window's edges, top and bottom.
            .frame(width: canvas.stageSize.width, height: canvas.size.height, alignment: .topLeading)
            .mask(pageMask)
            .contentShape(Path(CGRect(x: 0, y: 0, width: canvas.stageSize.width,
                                      height: max(0, canvas.size.height - canvas.u(SeleneBottomScrim.contentClearance)))))

            // Off the row, the page has risen: there is more above (More like this is the end).
            SpotlightUpHint()
                .frame(width: canvas.stageSize.width)
                .padding(.top, canvas.u(24))
                .opacity([.pills, .strip, .about, .actions, .store].contains(state.focus) ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: state.focus)
                .allowsHitTesting(false)

            if let menu = cardMenu {
                ZStack {
                    Color.black.opacity(0.45)
                        .contentShape(Rectangle())
                        .onTapGesture { cardMenu = nil }
                    SpotlightCardMenu(card: menu.card, focusedIndex: menu.index,
                                      onFocus: { cardMenu?.index = $0 },
                                      onChoose: { chooseCardMenu($0) })
                }
                .frame(width: canvas.stageSize.width, height: canvas.size.height)
                .transition(.opacity)
                .zIndex(5)
            }
        }
    }

    @ViewBuilder
    private func info(_ model: Snapshot, state: SpotlightState) -> some View {
        if let game = model.selectedGame {
            let metadata = store.storeMetadata[game.id]
            let genres = GameGenre.list(metadata?.genres ?? [])
            VStack(alignment: .leading, spacing: 0) {
                SpotlightGameInfoView(
                    game: game,
                    logo: logo(for: game),
                    presentation: LibraryPresentation(
                        game: game, metadata: metadata,
                        totalPlaytime: playSessions.totalDuration(for: game.id),
                        lastPlayed: playSessions.lastPlayed(for: game.id)),
                    isRunning: runningGames.isRunning(game),
                    focusedPill: state.focus == .pills ? state.pillIndex : nil,
                    onPill: { index in
                        guard !state.isLifted else { return }
                        mutate { $0.focus = .pills; $0.pillIndex = index }
                        pressPill(index, game: game)
                    },
                    onHoverPill: { index in
                        // Hover moves along the pills only once they have focus, and never
                        // mid-glide: the page moving under a still pointer is not a hover.
                        guard !state.isLifted, state.focus == .pills, !isGliding else { return }
                        mutate { $0.pillIndex = index }
                    },
                    pillSet: viewModel.portingPills(game),
                    etaText: viewModel.portingETAText,
                    onOpenLog: { viewModel.revealLog(for: game) }
                )
                .id(game.id)
                .spotlightBlock(.head)

                if !genres.isEmpty {
                    SpotlightGenreChips(genres: genres)
                        // They leave and come back with the pills, not stay while the rest changes.
                        .modifier(SpotlightInfoFollow())
                        .id(game.id)
                        .padding(.top, canvas.u(20))
                        .spotlightBlock(.genres)
                }

                screenshotStrip(id: game.id, titleID: viewModel.personalizationKey(for: game),
                                urls: metadata?.screenshotURLs ?? [],
                                known: screenshotsKnown(game, metadata: metadata), state: state)

                // The lower page is offscreen on the row. Build it only as the page rises.
                if belowShown { pageBelow(game, page: page(for: game), state: state).transition(.opacity) }
            }
        } else if let game = model.selectedCatalogGame, game.integration == .steam {
            let metadata = steamFacts.metadata(for: game)
            let genres = GameDetailPresentation.steamGenres(
                for: game, metadata: metadata,
                override: steamFields.value(titleID: game.personalizationReference.key, field: .genres))
            VStack(alignment: .leading, spacing: 0) {
                CatalogSteamInfo(game: game, totalPlaytime: playSessions.totalDuration(for: game.id),
                                 lastPlayed: playSessions.lastPlayed(for: game.id),
                                 focused: state.focus == .pills ? state.pillIndex : nil,
                                 onAction: { index in
                                     guard !state.isLifted else { return }
                                     mutate { $0.focus = .pills; $0.pillIndex = index }
                                     pressCatalogPill(index, game: game)
                                 },
                                 onHover: { index in
                                     guard !state.isLifted, state.focus == .pills, !isGliding else { return }
                                     mutate { $0.pillIndex = index }
                                 })
                    .id(game.id)
                    .spotlightBlock(.head)

                if !genres.isEmpty {
                    SpotlightGenreChips(genres: genres)
                        .modifier(SpotlightInfoFollow())
                        .id(game.id)
                        .padding(.top, canvas.u(20))
                        .spotlightBlock(.genres)
                }

                screenshotStrip(id: game.id, titleID: game.personalizationReference.key,
                                urls: metadata?.screenshots ?? [],
                                known: steamFacts.isKnown(game), state: state)

                if belowShown {
                    let request = SteamRelatedRequest(
                        appIDs: Set(model.catalogGamesByID.values.compactMap { $0.isHidden ? nil : $0.steamGame?.appID }),
                        language: SteamMetadata.language(localization.language))
                    steamPageBelow(steamPage(for: game), state: state)
                        .task(id: request) { await loadCachedSteamRelated(request) }
                        .transition(.opacity)
                }
            }
        } else if model.selectedItem == .card(.mods) {
            VStack(alignment: .leading, spacing: 0) {
                SpotlightCardInfoView(
                    card: .mods, gameCount: 0, installedCount: 0, poolLabel: "", activity: ActivitySummary(),
                    topGames: [], focusedTop: nil, artwork: artwork, onTopGame: { _ in },
                    modCounts: storeHost.counts)
                    .padding(.top, canvas.u(10))
                    .spotlightBlock(.head)
                ModStorePage(host: storeHost, catalog: storeHost.catalog, active: state.focus == .store)
                    .padding(.top, canvas.u(Self.storeGap))
                    // Hidden while the row has focus: it rises in with the page.
                    .opacity(belowShown ? 1 : 0)
            }
        } else if case .card(let card) = model.selectedItem {
            let summary = card == .activity ? activitySummary : ActivitySummary()
            let top = summary.topGames.compactMap { model.gamesByID[$0] }.filter { !$0.isHidden }
            let visible = viewModel.visibleCatalogGames
            // Selene's card panels sit 40 under the row, 10 lower than a game's.
            SpotlightCardInfoView(
                card: card,
                gameCount: visible.count,
                installedCount: LibraryQuery(filter: .installed).applyCatalog(to: visible, history: playSessions).count,
                poolLabel: Self.poolLabel(settings.settings.surprisePool),
                activity: summary,
                topGames: top,
                focusedTop: state.focus == .topGames ? state.topGameIndex : nil,
                artwork: artwork,
                onTopGame: { index in
                    guard !state.isLifted, index < top.count else { return }
                    selectGame(top[index].id)
                }
            )
            .padding(.top, canvas.u(10))
        }
    }

    static func poolLabel(_ pool: SurprisePool) -> String {
        switch pool {
        case .installed: return L10n.text("Installed games")
        case .notPlayed: return L10n.text("Games not played yet")
        case .all: return "All games"
        }
    }

    /// This week's play time. The week is Monday-first (see `Activity.summary`).
    var activitySummary: ActivitySummary {
        Activity.summary(sessions: playSessions.sessions, now: Date(), calendar: Calendar.current)
    }

    /// Top-game ids that still exist as visible games, in order.
    var topGameCount: Int {
        guard selectedItem == .card(.activity) else { return 0 }
        return visibleTopGameIDs.count
    }

    /// Top-game ids that exist and are not hidden, in order.
    var visibleTopGameIDs: [UUID] {
        let known = Set(viewModel.libraryGames.filter { !$0.isHidden }.map(\.id))
        return activitySummary.topGames.filter(known.contains)
    }

    /// "No screenshots" only once the answer is final: not before the first
    /// request starts, nor while a stale empty cache entry is being refetched.
    private func screenshotsKnown(_ game: PortedGame, metadata: NintendoStoreMetadata?) -> Bool {
        if store.storeMetadataLoading.contains(game.id) || store.screenshotLookups.contains(game.id) { return false }
        guard let titleId = game.titleId, !titleId.isEmpty else { return true }
        return metadata != nil || store.storeMetadataErrors[game.id] != nil
    }

    private func logo(for game: PortedGame) -> NSImage? {
        art.logo(for: game)
    }
    // MARK: - Art

    func loadHero(_ game: PortedGame?) async {
        await art.loadHero(game: game, current: { selectedGame?.id },
                           metadata: game.flatMap { store.storeMetadata[$0.id] }, artwork: artwork, personalizations: viewModel.personalizations,
                           // The logo leads (0.3 s); the art turns after it.
                           settle: 420_000_000, keepsWithoutGame: true)
        // The game's art is in (or it has none): the gold gives way under it.
        if let game, !Task.isCancelled, selectedGame?.id == game.id { modsBackdrop = false }
    }

    /// The art behind the page: none on a card; on a game its own art, or the previous game's while the next
    /// loads when browsing from game to game (never another game's art right after a card). The rule answers for
    /// the selection this render sees, so the art never drops out for the render before `onChange` runs.
    func shownArt(_ model: Snapshot) -> NSImage? {
        let id = model.selectedGame?.id ?? model.selectedCatalogGame.flatMap { $0.integration == .steam ? $0.id : nil }
        guard let id, let image = art.image else { return nil }
        return art.key.hasPrefix(id.uuidString)
            || artRule.keepsOtherArt(selection: viewModel.spotlight.selectedKey, isGame: true) ? image : nil
    }

    /// Gold on the Mods card; another card turns it off at once, a game once its art has arrived.
    func updateModsBackdrop() {
        if selectedItem == .card(.mods) {
            modsBackdrop = true
        } else if let game = selectedGame {
            if art.key.hasPrefix(game.id.uuidString) { modsBackdrop = false }
        } else {
            modsBackdrop = false
        }
    }
}
