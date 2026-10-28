import SwiftUI
import AppKit
import ImageIO
import NXLibraryCore

public struct LibraryRootView: View {
    @ObservedObject public var viewModel: AppViewModel
    @ObservedObject public var router: AppRouter
    @ObservedObject public var settings: AppSettingsStore
    @ObservedObject public var playSessions: PlaySessionStore
    @ObservedObject public var artwork: ArtworkStore

    @State private var metadata: NintendoStoreMetadata?
    @State private var heroImage: NSImage?
    @State private var railImages: [UUID: NSImage] = [:]
    @State private var railKeyArt: Set<UUID> = []
    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool
    @Environment(\.seleneReduceMotion) private var environmentReduceMotion

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
            let heroBottomInset = LibraryRailLayout.heroBottomInset(
                for: metrics,
                showsCommandBar: settings.settings.showButtonHints && !games.isEmpty
            )
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
                        focusArea: viewModel.librarySelection.focusArea,
                        actionIndex: viewModel.librarySelection.actionIndex,
                        readableText: settings.settings.readableText,
                        backgroundShade: settings.settings.backgroundShade.heroScrimOpacity,
                        bottomInset: heroBottomInset,
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
                            images: railImages,
                            metrics: metrics,
                            focusActive: viewModel.librarySelection.focusArea == .rail,
                            reduceMotion: environmentReduceMotion || settings.settings.reduceMotion,
                            onSelect: { id in
                                viewModel.librarySelection.selectedGameID = id
                                viewModel.librarySelection.focusArea = .rail
                            },
                            onOpen: { game in router.showDetail(game.id) }
                        )
                    }
                    if settings.settings.showButtonHints {
                        CommandBar(commandHints)
                    }
                }
            }
            .overlay(alignment: .top) {
                LibraryFilterBar(
                    selection: $viewModel.librarySelection,
                    searchVisible: $searchVisible,
                    searchFocused: $searchFocused,
                    showButtonHints: settings.settings.showButtonHints
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
            if let game = selectedGame {
                metadata = viewModel.storeMetadata[game.id]
                viewModel.loadStoreMetadata(for: game)
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: viewModel.handleLibraryGamepadAction(.navigateUp)
            case .down: viewModel.handleLibraryGamepadAction(.navigateDown)
            case .left: viewModel.handleLibraryGamepadAction(.navigateLeft)
            case .right: viewModel.handleLibraryGamepadAction(.navigateRight)
            default: break
            }
        }
        .seleneActivationKeys { viewModel.handleLibraryGamepadAction(.confirm) }
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
        .task(id: heroTaskKey) {
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
            if let url, let thumb = Self.railThumbnail(at: url) {
                railImages[game.id] = thumb
                railKeyArt.insert(game.id)
            }
        }
        .task(id: games.map(\.id)) {
            await loadRailImages()
        }
    }

    private var heroTaskKey: String {
        guard let game = selectedGame else { return "none" }
        let meta = viewModel.storeMetadata[game.id]
        let remote = meta?.headerImageURL ?? meta?.imageURL
        return game.id.uuidString + "|" + (remote?.absoluteString ?? "")
    }

    private var commandHints: [CommandHint] {
        guard selectedGame != nil else { return [CommandHint("≡", "Open menu")] }
        let state = viewModel.librarySelection
        var hints: [CommandHint] = []

        if state.focusArea != .filters {
            let label = state.focusArea == .actions && state.actionIndex == 1
                ? "Options"
                : "Play"
            hints.append(CommandHint("A", label))
        }
        if state.focusArea != .rail {
            hints.append(CommandHint("B", "Back"))
        }
        hints.append(CommandHint("X", "Details"))
        if !(state.focusArea == .actions && state.actionIndex == 1) {
            hints.append(CommandHint("Y", "Options"))
        }
        hints.append(CommandHint("≡", "Open menu"))
        return hints
    }

    private func loadRailImages() async {
        for game in games.prefix(12) {
            if Task.isCancelled { return }
            if railKeyArt.contains(game.id) { continue }

            let titleKey = game.titleId ?? game.uniqueKey
            if let cached = artwork.cachedURL(titleID: titleKey, kind: .hero),
               let image = Self.railThumbnail(at: cached) {
                railImages[game.id] = image
                railKeyArt.insert(game.id)
                continue
            }

            if railImages[game.id] != nil { continue }

            let meta = viewModel.storeMetadata[game.id]
            if let remote = meta?.headerImageURL,
               let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .hero),
               let image = Self.railThumbnail(at: url) {
                guard !Task.isCancelled else { return }
                railImages[game.id] = image
                railKeyArt.insert(game.id)
                continue
            }

            let coverRemote = meta?.imageURL ?? meta?.headerImageURL
            if let url = await artwork.fetch(titleID: titleKey, remoteURL: coverRemote, kind: .cover),
               let image = Self.railThumbnail(at: url) {
                guard !Task.isCancelled else { return }
                railImages[game.id] = image
            }
        }
    }

    private static func railThumbnail(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image,
                       size: NSSize(width: CGFloat(image.width),
                                    height: CGFloat(image.height)))
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
