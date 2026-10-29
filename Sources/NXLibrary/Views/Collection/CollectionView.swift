import SwiftUI
import AppKit
import NXLibraryCore

/// Collection (spec §5.3, Selene Main.xaml SeleneLibrary, `library.png`): the
/// whole library as one row of portrait covers over the selected game's art.
/// Rows on the 1920 × 1080 stage: top bar 0–100, the centered logo / stats /
/// genres column over 100–576, the cover band 576–976 (400 high), hints below.
/// The art and the row reach the window edges.
public struct CollectionView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var playSessions: PlaySessionStore
    @ObservedObject var artwork: ArtworkStore

    @Environment(\.seleneCanvas) var canvas

    @StateObject var art = SeleneHeroArt()
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

    var games: [PortedGame] {
        viewModel.librarySelection.query.apply(to: viewModel.libraryGames, history: playSessions)
    }

    var hasAnyGame: Bool { viewModel.libraryGames.contains { !$0.isHidden } }

    func selectedGame(in games: [PortedGame]) -> PortedGame? {
        guard let id = viewModel.librarySelection.selectedGameID else { return nil }
        return games.first { $0.id == id }
    }

    var selectedGame: PortedGame? { selectedGame(in: games) }

    // MARK: - Body

    public var body: some View {
        let games = self.games
        let game = selectedGame(in: games)
        ZStack(alignment: .topLeading) {
            SeleneArtBackground(image: art.image, imageKey: art.key,
                                shade: settings.settings.backgroundShade)
            stage(games: games, game: game)
                .frame(width: canvas.stageSize.width, height: canvas.stageSize.height, alignment: .topLeading)
                .offset(x: canvas.stageOrigin.x, y: canvas.stageOrigin.y)
        }
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .clipped()
        .onAppear(perform: appear)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: viewModel.libraryGames) { _ in
            viewModel.preloadCachedStoreMetadata()
            reconcile()
        }
        .onChange(of: filter) { _ in reconcile() }
        .onChange(of: viewModel.librarySelection.selectedGameID) { _ in selectionChanged() }
        .onReceive(NotificationCenter.default.publisher(for: .nxCollectionGamepadAction)) { note in
            guard viewModel.alertMessage == nil else { return }
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
        .task(id: art.heroTaskKey(game, metadata: game.flatMap { viewModel.storeMetadata[$0.id] },
                                  apiKey: settings.settings.steamGridDbApiKey)) { await loadHero(game) }
        .task(id: art.logoTaskKey(game, metadata: game.flatMap { viewModel.storeMetadata[$0.id] },
                                  apiKey: settings.settings.steamGridDbApiKey)) { await loadLogo(game) }
    }

    private func stage(games: [PortedGame], game: PortedGame?) -> some View {
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
                    // Row 1 (100 … 576): the column sits at x 100, 840 wide, centered in the row.
                    .frame(width: canvas.u(840), height: canvas.u(476))
                    .offset(x: canvas.u(100), y: canvas.u(100))
            }

            if games.isEmpty {
                emptyState
                    .frame(width: canvas.stageSize.width, height: canvas.u(980), alignment: .center)
            } else {
                CollectionCoverRow(
                    games: games,
                    selectedID: viewModel.librarySelection.selectedGameID,
                    steamGridDbApiKey: settings.settings.steamGridDbApiKey,
                    artwork: artwork,
                    steamGridDB: viewModel.steamGridDB,
                    coverURL: { viewModel.storeMetadata[$0.id]?.imageURL },
                    onSelect: { select($0.id) },
                    onActivate: { select($0.id); play($0) })
                    .offset(y: canvas.u(576))
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: globalHints, right: contextHints(game), bottom: 40, leftInset: 18)
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
            Text("No games in \(filter.rawValue)")
                .seleneFont(34)
                .foregroundColor(SeleneTheme.ink)
                .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
                .allowsHitTesting(false)
        } else {
            VStack(spacing: canvas.u(14)) {
                Text("No games yet").seleneFont(34).foregroundColor(SeleneTheme.ink)
                Text("Add a game to start your collection.")
                    .seleneFont(19).foregroundColor(SeleneTheme.ink60)
                HStack(spacing: canvas.u(14)) {
                    SelenePillButton(title: "Add game", focused: true) { router.openAddGame() }
                    SelenePillButton(title: "Import existing builds", minWidth: 0, focused: false) {
                        viewModel.importExistingBuilds()
                    }
                }
                .padding(.top, canvas.u(18))
            }
            .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
        }
    }

    // MARK: - Hints

    private var globalHints: [HintItem] {
        [HintItem(nil, "Spotlight", glyph: .spotlight, hold: "Hold: Search"),
         HintItem(nil, "Menu", glyph: .menu, hold: "Hold: Settings")]
    }

    private func contextHints(_ game: PortedGame?) -> [HintItem] {
        guard let game else {
            if viewModel.isScanningLibrary { return [] }
            return hasAnyGame ? [HintItem(.rs, "Filter")] : [HintItem(.a, "Add game")]
        }
        let filterHint = HintItem(.rs, "Filter")
        if game.isPlayableLocally {
            return [HintItem(.a, "Play"), HintItem(.x, "Details"), HintItem(.y, "Game options"), filterHint]
        }
        return [HintItem(.a, "Details"), HintItem(.y, "Game options"), filterHint]
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
        state.reconcile(with: viewModel.libraryGames, history: playSessions,
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
        guard let game = selectedGame else { return }
        if settings.settings.lastSelectedGameID != game.id { settings.settings.lastSelectedGameID = game.id }
        viewModel.loadStoreMetadata(for: game)
    }

    // MARK: - Art

    private func loadHero(_ game: PortedGame?) async {
        await art.loadHero(game: game, current: { selectedGame?.id },
                           metadata: game.flatMap { viewModel.storeMetadata[$0.id] }, artwork: artwork,
                           steamGridDB: viewModel.steamGridDB, apiKey: settings.settings.steamGridDbApiKey)
    }

    private func loadLogo(_ game: PortedGame?) async {
        await art.loadLogo(game: game, metadata: game.flatMap { viewModel.storeMetadata[$0.id] },
                           artwork: artwork, steamGridDB: viewModel.steamGridDB,
                           apiKey: settings.settings.steamGridDbApiKey)
    }
}

/// The selected game's logo, stats and genres, centered in their column
/// (Main.xaml SeleneLibrary row 1): a 250 high logo area (logo up to 600 × 240
/// bottom aligned, else the name at 56), stats 28 below, genres 16 below that.
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
        VStack(spacing: 0) {
            logoArea
            SeleneStatsRow(presentation: presentation)
                .padding(.top, canvas.u(28))
            if !presentation.genres.isEmpty {
                HStack(spacing: 0) {
                    ForEach(presentation.genres, id: \.self) { genre in
                        Text(genre).seleneFont(16).foregroundColor(SeleneTheme.ink60)
                            .padding(.horizontal, canvas.u(10))
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: canvas.u(4))
                .padding(.top, canvas.u(16))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(shown ? 1 : 0)
        .offset(x: slid ? 0 : canvas.u(-24))
        .onAppear { reveal() }
    }

    private var logoArea: some View {
        ZStack(alignment: .bottom) {
            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: canvas.u(600), maxHeight: canvas.u(240))
                    .shadow(color: .black.opacity(0.35), radius: canvas.u(8))
            } else {
                Text(game.name)
                    .seleneFont(56)
                    .foregroundColor(SeleneTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxHeight: canvas.u(220))
                    .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: canvas.u(250), alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.name)
        .accessibilityAddTraits(.isHeader)
    }

    /// The fade always runs; the slide is movement and drops under reduce motion.
    private func reveal() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            shown = false
            slid = reduceMotion
        }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 0.3).delay(0.12)) { shown = true }
            if !reduceMotion {
                withAnimation(SeleneTheme.cubicOut(0.3).delay(0.12)) { slid = true }
            }
        }
    }
}
