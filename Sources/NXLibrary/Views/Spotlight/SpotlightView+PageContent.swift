import SwiftUI
import AppKit
import NXLibraryCore

/// What the page below the row holds for a Switch or Steam game: About, Details, screenshots and related games.
extension SpotlightView {
    struct SteamRelatedRequest: Equatable {
        let appIDs: Set<UInt32>
        let language: String
    }

    func loadCachedSteamRelated(_ request: SteamRelatedRequest) async {
        guard cachedSteamRelated?.request != request else { return }
        let traits = await SteamMetadataService.shared.cachedRelatedTraits(appIDs: request.appIDs, language: request.language)
        guard !Task.isCancelled else { return }
        cachedSteamRelated = (request, traits)
    }

    private func relatedTraits(for game: CatalogGame, language: String) -> MoreLikeThis.Traits? {
        if let native = game.nxnativeGame {
            return store.storeMetadata[native.id].map {
                MoreLikeThis.Traits(developers: $0.developers, publishers: $0.publishers, genres: GameGenre.list($0.genres))
            }
        }
        guard let appID = game.steamGame?.appID else { return nil }
        let key = game.personalizationReference.key
        let loaded = steamFacts.metadata(for: game).flatMap { $0.language == language ? MoreLikeThis.Traits(steam: $0) : nil }
        let cached = cachedSteamRelated.flatMap { $0.request.language == language ? $0.traits[appID] : nil }
        let traits = loaded ?? cached
        let developer = steamFields.value(titleID: key, field: .developer)
        let publisher = steamFields.value(titleID: key, field: .publisher)
        let genres = steamFields.value(titleID: key, field: .genres)
        guard traits != nil || developer != nil || publisher != nil || genres != nil else { return nil }
        return MoreLikeThis.Traits(developers: developer.map { [$0] } ?? traits?.developers ?? [],
                                   publishers: publisher.map { [$0] } ?? traits?.publishers ?? [],
                                   genres: GameGenre.list(genres.map { $0.split(separator: ",").map(String.init) } ?? traits?.genres ?? []))
    }

    func steamPage(for game: CatalogGame) -> SpotlightPageModel {
        let visible = viewModel.visibleCatalogGames
        let playtimes = Dictionary(visible.map { ($0.id, playSessions.totalDuration(for: $0.id)) },
                                   uniquingKeysWith: { first, _ in first })
        let key = game.personalizationReference.key
        var overrides: [MetadataField: String] = [:]
        for field in MetadataField.allCases { overrides[field] = steamFields.value(titleID: key, field: field) }
        let presentation = GameDetailPresentation(
            steamRecord: game, metadata: steamFacts.metadata(for: game), overrides: overrides,
            totalPlaytime: playSessions.totalDuration(for: game.id),
            lastPlayed: playSessions.lastPlayed(for: game.id),
            sessions: playSessions.sessions, libraryGames: visible, playtimeByGame: playtimes)
        let facts = DetailsFacts.steamGame(game, metadata: steamFacts.metadata(for: game), overrides: overrides,
                                           volumeName: DetailsLink.volumeName(of: game))
        let app = presentation.appPath.isEmpty ? nil : URL(fileURLWithPath: presentation.appPath)
        let language = SteamMetadata.language(localization.language)
        let ids = belowShown ? MoreLikeThis.pick(for: game, in: visible, fallbackToOtherSources: true,
                                                traits: { relatedTraits(for: $0, language: language) }) : []
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return SpotlightPageModel(presentation: presentation, facts: facts,
                                  links: DetailsLink.links(app: app, store: presentation.storeURL,
                                                           hltb: presentation.hltbURL, viewModel: viewModel),
                                  more: ids.compactMap { byID[$0] }, buildBlocked: false)
    }

    func page(for game: PortedGame) -> SpotlightPageModel {
        let library = viewModel.libraryGames
        let playtimes = Dictionary(library.map { ($0.id, playSessions.totalDuration(for: $0.id)) },
                                   uniquingKeysWith: { first, _ in first })
        let presentation = GameDetailPresentation(
            game: game, metadata: store.storeMetadata[game.id],
            totalPlaytime: playSessions.totalDuration(for: game.id),
            lastPlayed: playSessions.lastPlayed(for: game.id),
            sessions: playSessions.sessions, libraryGames: library, playtimeByGame: playtimes)
        let blocked = setup.compatibilityReport != nil && !setup.canPassToolchainGate
        let facts = DetailsFacts.switchGame(game, metadata: store.storeMetadata[game.id],
                                            folderName: DetailsLink.folderName(of: game.url))
        let links = DetailsLink.links(app: game.url, store: presentation.storeURL, hltb: presentation.hltbURL,
                                      viewModel: viewModel)
        let ids = MoreLikeThis.pick(for: game, in: library,
                                    metadata: { store.storeMetadata[$0] }, limit: 6)
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return SpotlightPageModel(presentation: presentation, facts: facts, links: links,
                                  more: ids.compactMap { byID[$0].map(CatalogGame.init(nxnative:)) }, buildBlocked: blocked)
    }

    /// About this game with the column beside it (a Steam game's achievements, then the source's panel):
    /// the same geometry, focus blocks and excerpt for every source.
    private func aboutAndColumn<Panel: View>(_ page: SpotlightPageModel, state: SpotlightState,
                                             @ViewBuilder panel: () -> Panel) -> some View {
        HStack(alignment: .top, spacing: 0) {
            let excerpt = aboutExcerpt(page)
            let wikipedia = aboutWikipedia(page)
            SpotlightDescription(text: wikipedia?.text ?? page.presentation.description,
                                 languageNote: wikipedia == nil ? page.presentation.descriptionLanguageNote : nil,
                                 wikipediaPage: wikipedia?.pageURL, excerpt: excerpt,
                                 expanded: aboutExpanded, focused: state.focus == .about,
                                 onToggle: { aboutExpanded.toggle() })
                .spotlightBlock(.about)
                .preference(key: SpotlightReadMoreKey.self, value: excerpt.truncated)
                .task(id: aboutLookup(page)) {
                    guard let lookup = aboutLookup(page) else { return }
                    guard let found = await lookup.load() else { return }
                    wikipediaAbout = WikipediaAbout(lookup: lookup, description: found)
                }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: canvas.u(40)) {
                if let summary = selectedAchievements, let appID = selectedCatalogGame?.steamGame?.appID {
                    DetailsAchievementsCard(summary: summary, appID: appID, focused: state.focus == .achievements,
                                            onOpen: {
                                                guard !state.isLifted else { return }
                                                mutate { $0.focus = .achievements }
                                                openAchievements()
                                            })
                }
                panel()
            }
            .spotlightBlock(.column)
        }
        .frame(width: canvas.u(1700), alignment: .topLeading)
        .padding(.top, canvas.u(44))
        .spotlightBlock(.description)
    }

    /// The selected Steam game's achievements, when it has some and Steam's files read.
    var selectedAchievements: AchievementSummary? {
        guard let appID = selectedCatalogGame?.steamGame?.appID,
              let summary = achievementsStore.summaries[appID], summary.total > 0 else { return nil }
        return summary
    }

    /// The Details panel in the column beside About this game, the same for every source.
    private func detailsPanel(_ page: SpotlightPageModel, state: SpotlightState) -> some View {
        DetailsPanel(
            facts: page.facts, links: page.links,
            focusedLink: state.focus == .actions ? state.actionIndex : nil,
            onHoverLink: { index in
                guard state.focus == .actions, !isGliding else { return }
                mutate { $0.actionIndex = index }
            },
            onPressLink: { index in
                mutate { $0.focus = .actions; $0.actionIndex = index }
                if index < page.links.count { page.links[index].action() }
            },
            ratingQuery: selectedRatingQuery)
    }

    var selectedRatingQuery: CriticRatingQuery? {
        if let game = selectedGame {
            return CriticRatingQuery(game: game, name: store.storeMetadata[game.id]?.name)
        }
        guard let game = selectedCatalogGame, let steam = game.steamGame else { return nil }
        return CriticRatingQuery(name: steam.name, platform: .mac, steamAppID: steam.appID)
    }

    /// A Steam game's page under the head: About, its achievements, Details, then related games.
    func steamPageBelow(_ page: SpotlightPageModel, state: SpotlightState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            aboutAndColumn(page, state: state) { detailsPanel(page, state: state) }
            relatedBand(page, state: state)
        }
    }

    /// The screenshot strip under the head, for any source: the same tiles, fade and arrival.
    func screenshotStrip(id: UUID, titleID: String, urls: [URL], known: Bool, state: SpotlightState) -> some View {
        SpotlightScreenshotStrip(
            titleID: titleID,
            urls: urls,
            known: known,
            focusedIndex: state.focus == .strip ? state.stripIndex : nil,
            scrollIndex: state.stripIndex,
            artwork: artwork,
            onSelect: { index in
                guard !state.isLifted else { return }
                mutate { $0.focus = .strip; $0.stripIndex = index }
                openViewer(at: index)
            }
        )
        // On the row the screenshots dissolve downwards (Selene's home): the
        // hints sit on the dark below them, and the fade says there is more below.
        // Gradient stops do not animate, so the fade lifts by a solid layer
        // fading in over it, along with the glide. The mask reaches past the
        // strip's edges so the focus ring outside a tile shows.
        .mask(ZStack {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.3),
                .init(color: .black.opacity(0.35), location: 0.62),
                .init(color: .black.opacity(0), location: 0.86)
            ], startPoint: .top, endPoint: .bottom)
            Color.black.opacity(stripFull ? 1 : 0)
        }
        .padding(-canvas.u(16)))
        // They arrive after the logo, not before it.
        .seleneReveal(delay: 0.6)
        .id(id)
        .padding(.top, canvas.u(30))
        .spotlightBlock(.strip)
    }

    /// Below the screenshots: About this game, with Details in a column on its right
    /// (beside it however long it is), then More like this.
    func pageBelow(_ game: PortedGame, page: SpotlightPageModel, state: SpotlightState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            aboutAndColumn(page, state: state) {
                detailsPanel(page, state: state)
            }

            if let mods = modsHost.localMods, modsHost.game?.id == game.id {
                DetailsModsBand(
                    mods: mods,
                    records: modsHost.records,
                    gameBanana: modsHost.gameBanana,
                    focusedIndex: state.focus == .mods ? state.modsIndex : nil,
                    onFocus: { index in
                        guard !isGliding else { return }
                        mutate { $0.focus = .mods; $0.modsIndex = index }
                    },
                    onOpen: { index in
                        mutate { $0.focus = .mods; $0.modsIndex = index }
                        modsHost.activate(index, viewModel: viewModel, openMods: openMods)
                    })
                    .padding(.top, canvas.u(Self.moreGap))
                    .spotlightBlock(.mods)
            }

            relatedBand(page, state: state)
        }
    }

    @ViewBuilder
    private func relatedBand(_ page: SpotlightPageModel, state: SpotlightState) -> some View {
        if !page.more.isEmpty {
            DetailsMoreBand(
                games: page.more,
                focusedIndex: state.focus == .more ? state.moreIndex : nil,
                artwork: artwork,
                boxArt: viewModel.boxArt,
                boxArtIndexVersion: viewModel.boxArtIndexVersion,
                officialName: { store.storeMetadata[$0.id]?.name },
                onFocus: { index in mutate { $0.focus = .more; $0.moreIndex = index } },
                onOpen: { index in
                    SoundEffectService.shared.play(.click)
                    selectGame(page.more[index].id)
                })
                .padding(.top, canvas.u(Self.moreGap))
                .spotlightBlock(.more)
        }
    }

    func loadLogo(_ game: PortedGame?) async {
        await art.loadLogo(game: game, metadata: game.flatMap { store.storeMetadata[$0.id]},
                           artwork: artwork, personalizations: viewModel.personalizations)
    }
}
