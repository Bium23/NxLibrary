import SwiftUI
import AppKit
import NXLibraryCore

public struct LibraryRootView: View {
    @ObservedObject public var viewModel: AppViewModel
    @ObservedObject public var router: AppRouter
    @ObservedObject public var settings: AppSettingsStore
    @ObservedObject public var playSessions: PlaySessionStore
    @ObservedObject public var artwork: ArtworkStore

    @State private var metadata: NintendoStoreMetadata?
    @State private var heroImage: NSImage?
    @State private var coverImages: [UUID: NSImage] = [:]
    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool

    public init(viewModel: AppViewModel,
                router: AppRouter,
                settings: AppSettingsStore,
                playSessions: PlaySessionStore,
                artwork: ArtworkStore) {
        self.viewModel = viewModel
        self.router = router
        self.settings = settings
        self.playSessions = playSessions
        self.artwork = artwork
    }

    private var games: [PortedGame] {
        viewModel.librarySelection.query.apply(to: viewModel.libraryGames)
    }

    private var selectedGame: PortedGame? {
        guard let id = viewModel.librarySelection.selectedGameID else { return games.first }
        return games.first { $0.id == id } ?? games.first
    }

    private var readiness: Bool {
        viewModel.isProdKeysValid
            && viewModel.isNxnativeValid
            && viewModel.environmentStatus?.canBuild == true
            && viewModel.canPassToolchainGate
    }

    public var body: some View {
        GeometryReader { geo in
            let metrics = SeleneLayoutMetrics(width: geo.size.width)
            ZStack(alignment: .bottom) {
                SeleneTheme.canvas.ignoresSafeArea()

                if let game = selectedGame, let presentation {
                    LibraryHeroView(
                        game: game,
                        presentation: presentation,
                        heroImage: heroImage,
                        metrics: metrics,
                        size: geo.size,
                        showClock: settings.settings.showClock,
                        readiness: readiness,
                        onPlay: { viewModel.launchGame(game) },
                        onDetails: { router.showDetail(game.id) },
                        onOptions: { viewModel.gameForSettingsSheet = game }
                    )
                } else {
                    LibraryEmptyStateView(
                        onAdd: { router.openAddGame() },
                        onImport: { viewModel.importExistingBuilds() }
                    )
                }

                VStack(spacing: 0) {
                    if !games.isEmpty {
                        CoverRailView(
                            games: games,
                            selectedID: viewModel.librarySelection.selectedGameID,
                            coverImages: coverImages,
                            metrics: metrics,
                            onSelect: { id in
                                viewModel.librarySelection.selectedGameID = id
                                viewModel.librarySelection.focusArea = .rail
                            },
                            onOpen: { game in router.showDetail(game.id) }
                        )
                    }
                    if settings.settings.showButtonHints {
                        CommandBar([
                            .init("B", "Menu"),
                            .init("Y", "Game options"),
                            .init("A", "Play"),
                            .init("X", "Details")
                        ])
                    }
                }
            }
            .overlay(alignment: .top) {
                LibraryFilterBar(
                    selection: $viewModel.librarySelection,
                    searchVisible: $searchVisible,
                    searchFocused: $searchFocused
                )
                .padding(.top, 22)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .onAppear {
            if settings.settings.restoreLastGame,
               let id = settings.settings.lastSelectedGameID,
               viewModel.libraryGames.contains(where: { $0.id == id }) {
                viewModel.librarySelection.selectedGameID = id
            }
            reconcile()
            if let first = games.first {
                viewModel.loadStoreMetadata(for: first)
            }
        }
        .onChange(of: viewModel.libraryGames) { _ in reconcile() }
        .onChange(of: viewModel.librarySelection.query) { _ in reconcile() }
        .onChange(of: viewModel.librarySelection.selectedGameID) { newValue in
            settings.settings.lastSelectedGameID = newValue
            if let game = selectedGame {
                viewModel.loadStoreMetadata(for: game)
                metadata = viewModel.storeMetadata[game.id]
            }
        }
        .onChange(of: viewModel.storeMetadata) { _ in
            metadata = selectedGame.flatMap { viewModel.storeMetadata[$0.id] }
        }
        .task(id: selectedGame?.id) {
            guard let game = selectedGame else {
                heroImage = nil
                return
            }
            let meta = viewModel.storeMetadata[game.id]
            let remote = meta?.headerImageURL ?? meta?.imageURL
            let titleKey = game.titleId ?? game.uniqueKey
            let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .hero)
            guard !Task.isCancelled, selectedGame?.id == game.id else { return }
            heroImage = url.flatMap(NSImage.init(contentsOf:))
        }
        .task(id: games.map(\.id)) {
            for game in games.prefix(12) {
                if coverImages[game.id] != nil { continue }
                let meta = viewModel.storeMetadata[game.id]
                let remote = meta?.imageURL ?? meta?.headerImageURL
                let titleKey = game.titleId ?? game.uniqueKey
                let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .cover)
                guard !Task.isCancelled else { return }
                if let url, let image = NSImage(contentsOf: url) {
                    coverImages[game.id] = image
                }
            }
        }
    }

    private var presentation: LibraryPresentation? {
        guard let game = selectedGame else { return nil }
        return LibraryPresentation(
            game: game,
            metadata: metadata,
            totalPlaytime: playSessions.totalDuration(for: game.id),
            lastPlayed: playSessions.lastPlayed(for: game.id)
        )
    }

    private func reconcile() {
        var state = viewModel.librarySelection
        _ = state.reconcile(with: viewModel.libraryGames)
        viewModel.librarySelection = state
    }
}
