import SwiftUI
import AppKit
import NXLibraryCore

/// Collection (spec §5.3, Selene Main.xaml SeleneLibrary, `library.png`): the
/// whole library as one row of portrait covers over the selected game's art.
/// It shares Spotlight's frame (`SeleneHomeChrome`): the top bar, the 80 margin
/// and the hints sit where Spotlight has them. On the stage: top bar 0–100, the
/// logo / stats / genres at x 80 from y 110, the cover band 576–976 (400 high).
/// The art and the row reach the window edges.
public struct CollectionView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var playSessions: PlaySessionStore
    @ObservedObject var artwork: ArtworkStore

    @Environment(\.seleneCanvas) var canvas

    @StateObject var art = SeleneHeroArt()
    /// Art the player picks redraws the hero and logo (their task keys carry its revision).
    @ObservedObject var picks = ArtworkPicks.shared
    /// Steam Play phases drive the A hint.
    @ObservedObject var steamPlayer = SteamPlayCoordinator.shared
    @State var keyMonitor: Any?

    public init(viewModel: AppViewModel, router: AppRouter, settings: AppSettingsStore,
                playSessions: PlaySessionStore, artwork: ArtworkStore) {
        self.viewModel = viewModel
        self.router = router
        self.settings = settings
        self.playSessions = playSessions
        self.artwork = artwork
    }

    // MARK: - Model

    /// The filter is shared with Spotlight.
    var filter: LibraryFilter { viewModel.librarySelection.query.filter }

    var games: [CatalogGame] {
        viewModel.librarySelection.query.applyCatalog(to: viewModel.visibleCatalogGames, history: playSessions)
    }

    var hasAnyGame: Bool { !viewModel.visibleCatalogGames.isEmpty }

    func selectedGame(in games: [CatalogGame]) -> PortedGame? {
        guard let id = viewModel.librarySelection.selectedGameID else { return nil }
        return games.first { $0.id == id }?.nxnativeGame
    }

    var selectedGame: PortedGame? { selectedGame(in: games) }
    var selectedCatalogGame: CatalogGame? { games.first { $0.id == viewModel.librarySelection.selectedGameID } }

    // MARK: - Body

    public var body: some View {
        let games = self.games
        let game = selectedGame(in: games)
        SeleneHomeChrome(
            leftHints: HintItem.homeGlobals(other: "Spotlight",
                                            onOther: { if settings.settings.viewButtonSwitches { router.showLibrary() } },
                                            onMenu: { router.isMenuPresented = true }),
            rightHints: contextHints(game),
            hintsHidden: router.overlayHasHints(viewModel),
            backdrop: {
                SeleneArtBackground(image: art.image, imageKey: art.key,
                                    shade: settings.settings.backgroundShade,
                                    showsArt: !settings.settings.keepWallpaperOnGames)
            },
            stage: { stage(games: games, game: game) })
        .onAppear(perform: appear)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: viewModel.catalogGames) { _ in
            viewModel.preloadCachedStoreMetadata()
            reconcile()
        }
        .onChange(of: viewModel.catalogSourceConfigurations) { _ in reconcile() }
        .onChange(of: filter) { _ in reconcile() }
        .onChange(of: viewModel.librarySelection.selectedGameID) { _ in selectionChanged() }
        .onReceive(NotificationCenter.default.publisher(for: .nxCollectionGamepadAction)) { note in
            guard viewModel.alertMessage == nil, viewModel.settingsNotice == nil else { return }
            if let action = note.object as? GamepadAction { handle(action) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxFindGameSelect)) { note in
            guard let id = note.object as? UUID else { return }
            // Find a game lands on Collection; a tab without the game gives way to All games.
            if !games.contains(where: { $0.id == id }) { setFilter(.all) }
            select(id)
        }
        .onChange(of: playSessions.sessions.count) { _ in reconcile() }
        .onChange(of: viewModel.isScanningLibrary) { _ in reconcile() }
        .task(id: art.heroTaskKey(game, metadata: game.flatMap { viewModel.storeMetadata[$0.id] })) { await loadHero(game) }
        .task(id: art.steamHeroTaskKey(selectedCatalogGame)) { await art.loadSteamHero(game: selectedCatalogGame, current: { selectedCatalogGame?.id }, artwork: artwork) }
        .task(id: art.logoTaskKey(game, metadata: game.flatMap { viewModel.storeMetadata[$0.id] })) { await loadLogo(game) }
    }

    private func stage(games: [CatalogGame], game: PortedGame?) -> some View {
        ZStack(alignment: .topLeading) {
            SpotlightTopBar(filter: filter, showClock: settings.settings.showClock,
                            onSelect: { setFilter($0) })

            if let game {
                CollectionInfoView(game: game, logo: art.logo(for: game),
                                   presentation: LibraryPresentation(
                                       game: game, metadata: viewModel.storeMetadata[game.id],
                                       totalPlaytime: playSessions.totalDuration(for: game.id),
                                       lastPlayed: playSessions.lastPlayed(for: game.id)))
                    .id(game.id)
                    // Spotlight's left margin; the logo starts just under the top bar.
                    .frame(width: canvas.u(1100), alignment: .topLeading)
                    .offset(x: canvas.u(80), y: canvas.u(110))
            } else if let record = selectedCatalogGame, record.integration == .steam {
                CatalogSteamInfo(game: record, totalPlaytime: playSessions.totalDuration(for: record.id),
                                 lastPlayed: playSessions.lastPlayed(for: record.id), collection: true)
                    .id(record.id)
                    .frame(width: canvas.u(1100), alignment: .topLeading)
                    .offset(x: canvas.u(80), y: canvas.u(110))
            }

            if games.isEmpty {
                emptyState
                    .frame(width: canvas.stageSize.width, height: canvas.u(980), alignment: .center)
            } else {
                CollectionCoverRow(
                    games: games,
                    selectedID: viewModel.librarySelection.selectedGameID,
                    artwork: artwork,
                    boxArt: viewModel.boxArt,
                    boxArtIndexVersion: viewModel.boxArtIndexVersion,
                    officialName: { viewModel.storeMetadata[$0.id]?.name },
                    needsMetadata: { viewModel.loadStoreMetadata(for: $0) },
                    tileLook: viewModel.portingTileLook,
                    onSelect: { select($0.id) },
                    onActivate: { record in select(record.id); activateCatalog(record) })
                    .offset(y: canvas.u(576))
            }
        }
    }

    // MARK: - Empty state

    /// No games at all: the Add game prompt. A filter with no games: its name.
    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isScanningLibrary {
            EmptyView()
        } else if hasAnyGame {
            Text(L10n.format("No games in %@", [L10n.text(filter.rawValue)]))
                .seleneFont(34)
                .foregroundColor(SeleneTheme.ink)
                .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
                .allowsHitTesting(false)
        } else {
            VStack(spacing: canvas.u(14)) {
                Text(L10n.text("Add your first game")).seleneFont(34).foregroundColor(SeleneTheme.ink)
                Text(L10n.text("Choose game files or find your existing apps."))
                    .seleneFont(19).foregroundColor(SeleneTheme.ink60)
                HStack(spacing: canvas.u(14)) {
                    SelenePillButton(title: L10n.text("Add game"), focused: true) { router.openAddGame() }
                    SelenePillButton(title: L10n.text("Import existing builds"), minWidth: 0, focused: false) {
                        viewModel.importExistingBuilds()
                    }
                }
                .padding(.top, canvas.u(18))
            }
            .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
        }
    }

    // MARK: - Hints

    private func contextHints(_ game: PortedGame?) -> [HintItem] {
        if let steam = selectedCatalogGame, steam.integration == .steam {
            return SteamPlayCoordinator.shared.hint(for: steam)
                + [HintItem(.y, L10n.text("Game options")), HintItem(.rs, L10n.text("Filter"))]
        }
        guard let game else {
            if viewModel.isScanningLibrary { return [] }
            return hasAnyGame ? [HintItem(.rs, L10n.text("Filter"))] : [HintItem(.a, L10n.text("Add game"))]
        }
        let filterHint = HintItem(.rs, L10n.text("Filter"))
        if game.isPlayableLocally {
            return [HintItem(.a, L10n.text("Play")), HintItem(.x, L10n.text("Details")), HintItem(.y, L10n.text("Game options")), filterHint]
        }
        return [HintItem(.a, L10n.text("Details")), HintItem(.y, L10n.text("Game options")), filterHint]
    }

    // MARK: - Selection

    func appear() {
        installKeyMonitor()
        router.isSearchPresented = false
        viewModel.preloadCachedStoreMetadata()
        // The starting tab is applied once per session, on the first visit to either screen.
        if !viewModel.spotlight.startingTabApplied {
            viewModel.spotlight.startingTabApplied = true
            viewModel.librarySelection.query.filter = LibraryFilter(startingTab: settings.settings.startingTab)
        }
        reconcile()
        selectionChanged()
    }

    /// Keeps the selection inside the filtered list, in the same frame as any change to it.
    func reconcile() {
        var state = viewModel.librarySelection
        state.reconcileCatalog(with: viewModel.visibleCatalogGames, history: playSessions,
                        preferredGameID: settings.settings.restoreLastGame ? settings.settings.lastSelectedGameID : nil)
        if state != viewModel.librarySelection { viewModel.librarySelection = state }
    }

    func setFilter(_ next: LibraryFilter) {
        guard next != filter else { return }
        viewModel.librarySelection.query.filter = next
        reconcile()
        SoundEffectService.shared.play(.tabSwitch)
    }

    func select(_ id: UUID) {
        if viewModel.librarySelection.selectedGameID != id { viewModel.librarySelection.selectedGameID = id }
    }

    private func selectionChanged() {
        if let id = selectedCatalogGame?.id, settings.settings.lastSelectedGameID != id { settings.settings.lastSelectedGameID = id }
        guard let game = selectedGame else { return }
        if settings.settings.lastSelectedGameID != game.id { settings.settings.lastSelectedGameID = game.id }
        viewModel.loadStoreMetadata(for: game)
    }

    // MARK: - Art

    private func loadHero(_ game: PortedGame?) async {
        // On a Steam game the nxnative art stays until the Steam hero replaces it, so the change is one crossfade.
        await art.loadHero(game: game, current: { selectedGame?.id },
                           metadata: game.flatMap { viewModel.storeMetadata[$0.id] }, artwork: artwork, personalizations: viewModel.personalizations,
                           keepsWithoutGame: selectedCatalogGame?.integration == .steam)
    }

    private func loadLogo(_ game: PortedGame?) async {
        await art.loadLogo(game: game, metadata: game.flatMap { viewModel.storeMetadata[$0.id] },
                           artwork: artwork, personalizations: viewModel.personalizations)
    }
}

/// The selected game's logo, stats and genres, left aligned like Spotlight's
/// info: a 250 high logo area (logo up to 700 × 240, Spotlight's size, bottom
/// left; else the name at 56), stats 28 below, Spotlight's genre chips 20 below.
/// The column arrives together on each game change: hold 0.12 s, fade in to
/// 0.42 s while sliding from x −24 (0.3 s cubic out).
struct CollectionInfoView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    let game: PortedGame
    let logo: NSImage?
    let presentation: LibraryPresentation

    @State private var shown = true
    @State private var slid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logoArea
            if let reason = GameResourceState.unavailableReason(for: game) {
                Text(reason.title)
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink75)
                    .padding(.top, canvas.u(20))
                Text(reason.detail)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.top, canvas.u(6))
            } else if !game.isPlayableLocally, game.status != .building, game.portingFailure == nil {
                Text(L10n.text("Not built yet"))
                    .seleneFont(17)
                    .foregroundColor(SeleneTheme.ink75)
                    .padding(.top, canvas.u(20))
            }
            SeleneStatsRow(presentation: presentation)
                .padding(.top, canvas.u(28))
            if !presentation.genres.isEmpty {
                SpotlightGenreChips(genres: presentation.genres)
                    .padding(.top, canvas.u(20))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .opacity(shown ? 1 : 0)
        .offset(x: slid ? 0 : canvas.u(Self.slideDistance))
        .onAppear { reveal() }
    }

    private var logoArea: some View {
        GameLogoArea(title: game.name, logo: logo, collection: true)
    }

    /// The whole column's fade and slide after a change. A Steam game's column uses the same.
    static let fade = Animation.linear(duration: 0.3).delay(0.12)
    static let slide = SeleneTheme.cubicOut(0.3).delay(0.12)
    static let slideDistance: CGFloat = -24

    /// The fade always runs; the slide is movement and drops under reduce motion.
    private func reveal() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            shown = false
            slid = reduceMotion
        }
        DispatchQueue.main.async {
            withAnimation(Self.fade) { shown = true }
            if !reduceMotion {
                withAnimation(Self.slide) { slid = true }
            }
        }
    }
}
