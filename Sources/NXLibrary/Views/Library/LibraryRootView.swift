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
    @State private var heroCache: [UUID: NSImage] = [:]
    @State private var logoImage: NSImage?
    @State private var logoCache: [UUID: NSImage] = [:]
    @State private var heroKey = 0
    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool
    @State private var keyMonitor: Any?
    @Environment(\.seleneReduceMotion) private var environmentReduceMotion
    private let steamGridDB = SteamGridDBService()

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

    private var showsDetails: Bool {
        viewModel.librarySelection.focusArea == .actions
    }

    public var body: some View {
        GeometryReader { geo in
            let metrics = SeleneLayoutMetrics(width: geo.size.width)
            let contentTopInset = LibraryRailLayout.heroContentTopInset(
                for: metrics,
                expanded: showsDetails
            )
            ZStack(alignment: .top) {
                SeleneTheme.scrim.ignoresSafeArea()

                if let game = selectedGame, let presentation {
                    LibraryHeroView(
                        game: game,
                        presentation: presentation,
                        heroImage: heroImage,
                        logoImage: logoImage,
                        metrics: metrics,
                        size: geo.size,
                        showClock: settings.settings.showClock,
                        readiness: readiness,
                        focusArea: viewModel.librarySelection.focusArea,
                        actionIndex: viewModel.librarySelection.actionIndex,
                        readableText: settings.settings.readableText,
                        backgroundShade: settings.settings.backgroundShade.heroScrimOpacity,
                        contentTopInset: contentTopInset,
                        showsDetails: showsDetails,
                        reduceMotion: environmentReduceMotion || settings.settings.reduceMotion,
                        heroKey: "\(game.id.uuidString)-\(heroKey)",
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
                    LibraryFilterBar(
                        selection: $viewModel.librarySelection,
                        searchVisible: $searchVisible,
                        searchFocused: $searchFocused,
                        showButtonHints: settings.settings.showButtonHints
                    )
                    .padding(.top, LibraryRailLayout.filterTopPadding)

                    if !games.isEmpty {
                        CoverRailView(
                            games: games,
                            selectedID: viewModel.librarySelection.selectedGameID,
                            metrics: metrics,
                            expanded: showsDetails,
                            reduceMotion: environmentReduceMotion || settings.settings.reduceMotion,
                            onSelect: { id in
                                viewModel.librarySelection.selectedGameID = id
                                viewModel.librarySelection.actionIndex = 0
                                viewModel.librarySelection.focusArea = .rail
                            },
                            onOpen: { game in router.showDetail(game.id) }
                        )
                        .padding(.top, LibraryRailLayout.filterRailGap)
                    }

                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if settings.settings.showButtonHints {
                        SeleneHintsBar(left: menuHints, right: commandHints)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .animation(environmentReduceMotion || settings.settings.reduceMotion
                       ? nil : SeleneTheme.expand,
                       value: showsDetails)
        }
        .onAppear {
            installKeyMonitor()
            if settings.settings.restoreLastGame,
               let id = settings.settings.lastSelectedGameID,
               viewModel.libraryGames.contains(where: { $0.id == id }) {
                viewModel.librarySelection.selectedGameID = id
            }
            reconcile()
            viewModel.preloadCachedStoreMetadata()
            if let game = selectedGame {
                metadata = viewModel.storeMetadata[game.id]
                setHeroImage(heroCache[game.id])
                setLogoImage(logoCache[game.id])
                viewModel.loadStoreMetadata(for: game)
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: viewModel.libraryGames) { _ in
            reconcile()
            viewModel.preloadCachedStoreMetadata()
        }
        .onChange(of: viewModel.librarySelection.query) { _ in reconcile() }
        .onChange(of: viewModel.librarySelection.selectedGameID) { newValue in
            settings.settings.lastSelectedGameID = newValue
            guard let game = selectedGame else {
                metadata = nil
                setHeroImage(nil)
                setLogoImage(nil)
                return
            }
            metadata = viewModel.storeMetadata[game.id]
            setHeroImage(heroCache[game.id])
            setLogoImage(logoCache[game.id])
            viewModel.loadStoreMetadata(for: game)
        }
        .onChange(of: viewModel.storeMetadata) { _ in
            metadata = selectedGame.flatMap { viewModel.storeMetadata[$0.id] }
        }
        .task(id: heroTaskKey) {
            await loadHero()
            await loadLogo()
        }
        .task(id: games.map(\.id)) {
            viewModel.preloadCachedStoreMetadata()
            await preloadCachedHeroes()
            await preloadCachedLogos()
        }
    }

    private var heroTaskKey: String {
        guard let game = selectedGame else { return "none" }
        let meta = viewModel.storeMetadata[game.id]
        let remote = meta?.headerImageURL ?? meta?.imageURL
        let apiKey = settings.settings.steamGridDbApiKey
        return "\(game.id.uuidString)|\(remote?.absoluteString ?? "")|\(apiKey)"
    }

    private var menuHints: [HintItem] { [HintItem(.menu, "Open menu")] }

    private var commandHints: [HintItem] {
        guard selectedGame != nil else { return [] }
        let state = viewModel.librarySelection
        var hints: [HintItem] = []

        if state.focusArea != .filters {
            let label: String
            if state.focusArea == .actions {
                switch state.actionIndex {
                case 1: label = "Details"
                case 2: label = "Options"
                default: label = "Play"
                }
            } else {
                label = "Play"
            }
            hints.append(HintItem(.a, label))
        }
        if state.focusArea == .rail {
            hints.append(HintItem(nil, "↓ Details"))
        }
        if state.focusArea != .rail {
            hints.append(HintItem(.b, "Back"))
        }
        if !(state.focusArea == .actions && state.actionIndex == 1) {
            hints.append(HintItem(.x, "Game page"))
        }
        if !(state.focusArea == .actions && state.actionIndex == 2) {
            hints.append(HintItem(.y, "Options"))
        }
        return hints
    }

    @MainActor
    private func loadHero() async {
        guard let game = selectedGame else {
            setHeroImage(nil)
            return
        }
        if let cached = heroCache[game.id] {
            if let current = heroImage, current === cached { return }
            setHeroImage(cached)
            return
        }

        // 1. Check local custom artwork first (e.g. hero.jpg, hero.png, background.jpg, background.png, wallpaper.jpg)
        let candidates = ["hero.jpg", "hero.png", "background.jpg", "background.png", "wallpaper.jpg"]
        if let source = game.sources.first {
            let folder = source.url.deletingLastPathComponent()
            for name in candidates {
                let localURL = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: localURL.path),
                   let image = await Self.decodeHero(at: localURL) {
                    guard !Task.isCancelled, selectedGame?.id == game.id else { return }
                    heroCache[game.id] = image
                    setHeroImage(image)
                    return
                }
            }
        }
        let bundleResources = game.url.appendingPathComponent("Contents/Resources")
        for name in candidates {
            let localURL = bundleResources.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: localURL.path),
               let image = await Self.decodeHero(at: localURL) {
                guard !Task.isCancelled, selectedGame?.id == game.id else { return }
                heroCache[game.id] = image
                setHeroImage(image)
                return
            }
        }

        let titleKey = game.titleId ?? game.uniqueKey
        if let cachedURL = artwork.cachedURL(titleID: titleKey, kind: .hero),
           let image = await Self.decodeHero(at: cachedURL) {
            guard !Task.isCancelled, selectedGame?.id == game.id else { return }
            heroCache[game.id] = image
            setHeroImage(image)
            return
        }

        // 2. If SteamGridDB API key is provided, search clean hero wallpaper (without logo/text)
        let apiKey = settings.settings.steamGridDbApiKey
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let remoteHeroURL = await steamGridDB.fetchHeroURL(gameName: game.name, apiKey: apiKey) {
                guard !Task.isCancelled, selectedGame?.id == game.id else { return }
                if let url = await artwork.fetch(titleID: titleKey, remoteURL: remoteHeroURL, kind: .hero),
                   let image = await Self.decodeHero(at: url) {
                    guard !Task.isCancelled, selectedGame?.id == game.id else { return }
                    heroCache[game.id] = image
                    setHeroImage(image)
                    return
                }
            }
        }

        // 3. Fallback to clean community wallpaper
        if let fallbackWallpaperURL = Self.findCommunityWallpaperURL(gameName: game.name, titleId: game.titleId) {
            guard !Task.isCancelled, selectedGame?.id == game.id else { return }
            if let url = await artwork.fetch(titleID: titleKey, remoteURL: fallbackWallpaperURL, kind: .hero),
               let image = await Self.decodeHero(at: url) {
                guard !Task.isCancelled, selectedGame?.id == game.id else { return }
                heroCache[game.id] = image
                setHeroImage(image)
                return
            }
        }

        // 4. Fallback to store / TitleDB banner
        let meta = viewModel.storeMetadata[game.id]
        let remote = meta?.headerImageURL ?? meta?.imageURL ?? (game.titleId.flatMap { URL(string: "https://api.nlib.cc/nx/\($0)/banner") })
        guard let url = await artwork.fetch(titleID: titleKey,
                                            remoteURL: remote,
                                            kind: .hero) else { return }
        guard !Task.isCancelled, selectedGame?.id == game.id else { return }
        guard let image = await Self.decodeHero(at: url) else { return }
        guard !Task.isCancelled, selectedGame?.id == game.id else { return }
        heroCache[game.id] = image
        setHeroImage(image)
    }

    @MainActor
    private func loadLogo() async {
        guard let game = selectedGame else {
            setLogoImage(nil)
            return
        }
        if let cached = logoCache[game.id] {
            if let current = logoImage, current === cached { return }
            setLogoImage(cached)
            return
        }

        let titleKey = game.titleId ?? game.uniqueKey
        if let cachedURL = artwork.cachedURL(titleID: titleKey, kind: .logo),
           let image = NSImage(contentsOf: cachedURL) {
            guard !Task.isCancelled, selectedGame?.id == game.id else { return }
            logoCache[game.id] = image
            setLogoImage(image)
            return
        }

        if let source = game.sources.first {
            let folder = source.url.deletingLastPathComponent()
            let localLogoURL = folder.appendingPathComponent("logo.png")
            if FileManager.default.fileExists(atPath: localLogoURL.path),
               let image = NSImage(contentsOf: localLogoURL) {
                guard !Task.isCancelled, selectedGame?.id == game.id else { return }
                logoCache[game.id] = image
                setLogoImage(image)
                return
            }
        }
        let bundleLogoURL = game.url.appendingPathComponent("Contents/Resources/logo.png")
        if FileManager.default.fileExists(atPath: bundleLogoURL.path),
           let image = NSImage(contentsOf: bundleLogoURL) {
            guard !Task.isCancelled, selectedGame?.id == game.id else { return }
            logoCache[game.id] = image
            setLogoImage(image)
            return
        }

        let apiKey = settings.settings.steamGridDbApiKey
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let remoteLogoURL = await steamGridDB.fetchLogoURL(gameName: game.name, apiKey: apiKey) {
                guard !Task.isCancelled, selectedGame?.id == game.id else { return }
                if let url = await artwork.fetch(titleID: titleKey, remoteURL: remoteLogoURL, kind: .logo),
                   let image = NSImage(contentsOf: url) {
                    guard !Task.isCancelled, selectedGame?.id == game.id else { return }
                    logoCache[game.id] = image
                    setLogoImage(image)
                    return
                }
            }
        }

        let meta = viewModel.storeMetadata[game.id]
        if let remote = meta?.logoURL {
            guard let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .logo),
                  let image = NSImage(contentsOf: url) else { return }
            guard !Task.isCancelled, selectedGame?.id == game.id else { return }
            logoCache[game.id] = image
            setLogoImage(image)
            return
        }

        // Automatic fallback for official transparent logos
        if let fallbackLogoURL = Self.findCommunityLogoURL(gameName: game.name, titleId: game.titleId) {
            guard !Task.isCancelled, selectedGame?.id == game.id else { return }
            if let url = await artwork.fetch(titleID: titleKey, remoteURL: fallbackLogoURL, kind: .logo),
               let image = NSImage(contentsOf: url) {
                guard !Task.isCancelled, selectedGame?.id == game.id else { return }
                logoCache[game.id] = image
                setLogoImage(image)
                return
            }
        }
    }

    private static func findCommunityLogoURL(gameName: String, titleId: String?) -> URL? {
        let name = gameName.lowercased()
        if name.contains("wonder") || titleId == "010015100B514000" {
            return URL(string: "https://upload.wikimedia.org/wikipedia/commons/3/36/Super_Mario_Bros._Wonder_Logo.png")
        }
        if name.contains("odyssey") || titleId == "0100000000010000" {
            return URL(string: "https://upload.wikimedia.org/wikipedia/it/2/27/Super_Mario_Odyssey_logo.png")
        }
        if name.contains("breath of the wild") || titleId == "01007EF00011E000" {
            return URL(string: "https://cdn.wikimg.net/en/zeldawiki/images/0/06/BotW_English_Logo.png")
        }
        if name.contains("tears of the kingdom") || name.contains("totk") || titleId == "0100F2C0115B6000" {
            return URL(string: "https://cdn.wikimg.net/en/zeldawiki/images/4/4c/TotK_English_Logo.png")
        }
        return nil
    }

    private static func findCommunityWallpaperURL(gameName: String, titleId: String?) -> URL? {
        let name = gameName.lowercased()
        if name.contains("wonder") || titleId == "010015100B514000" {
            return URL(string: "https://catwithmonocle.com/wp-content/uploads/2023/11/smb-wonder-artwork-01-3840x2160-1.jpg")
        }
        if name.contains("odyssey") || titleId == "0100000000010000" {
            return URL(string: "https://catwithmonocle.com/wp-content/uploads/2017/12/smo-wallpaper-pc.jpg")
        }
        if name.contains("breath of the wild") || titleId == "01007EF00011E000" {
            return URL(string: "https://wallpapercat.com/w/full/a/e/e/904567-3840x2160-desktop-4k-legend-of-zelda-breath-of-the-wild-wallpaper.jpg")
        }
        if name.contains("tears of the kingdom") || name.contains("totk") || titleId == "0100F2C0115B6000" {
            return URL(string: "https://catwithmonocle.com/wp-content/uploads/2023/12/zelda-tearskingdom-artwork-02-3840x2160-1.jpg")
        }
        return nil
    }

    @MainActor
    private func preloadCachedHeroes() async {
        for game in games {
            if Task.isCancelled { return }
            if heroCache[game.id] != nil { continue }
            let titleKey = game.titleId ?? game.uniqueKey
            guard let url = artwork.cachedURL(titleID: titleKey, kind: .hero),
                  let image = await Self.decodeHero(at: url) else { continue }
            guard !Task.isCancelled else { return }
            heroCache[game.id] = image
            if selectedGame?.id == game.id, heroImage == nil {
                setHeroImage(image)
            }
        }
    }

    @MainActor
    private func preloadCachedLogos() async {
        for game in games {
            if Task.isCancelled { return }
            if logoCache[game.id] != nil { continue }
            let titleKey = game.titleId ?? game.uniqueKey
            guard let url = artwork.cachedURL(titleID: titleKey, kind: .logo),
                  let image = NSImage(contentsOf: url) else { continue }
            guard !Task.isCancelled else { return }
            logoCache[game.id] = image
            if selectedGame?.id == game.id, logoImage == nil {
                setLogoImage(image)
            }
        }
    }

    @MainActor
    private func setHeroImage(_ image: NSImage?) {
        heroImage = image
        heroKey += 1
    }

    @MainActor
    private func setLogoImage(_ image: NSImage?) {
        logoImage = image
    }

    private static func decodeHero(at url: URL) async -> NSImage? {
        let box = await Task.detached(priority: .utility) { () -> HeroImageBox? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else { return nil }
            return HeroImageBox(image: NSImage(cgImage: image,
                                               size: NSSize(width: CGFloat(image.width),
                                                            height: CGFloat(image.height))))
        }.value
        return box?.image
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

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if searchFocused { return event }
            guard !router.isMenuPresented,
                  router.route == .library,
                  viewModel.gameForSettingsSheet == nil,
                  !viewModel.showSetupSheet,
                  !viewModel.showInstallerSheet else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }

            switch event.keyCode {
            case 123:
                viewModel.handleLibraryGamepadAction(.navigateLeft)
                return nil
            case 124:
                viewModel.handleLibraryGamepadAction(.navigateRight)
                return nil
            case 125:
                viewModel.handleLibraryGamepadAction(.navigateDown)
                return nil
            case 126:
                viewModel.handleLibraryGamepadAction(.navigateUp)
                return nil
            case 36, 49:
                viewModel.handleLibraryGamepadAction(.confirm)
                return nil
            case 53:
                viewModel.handleLibraryGamepadAction(.cancel)
                return nil
            case 7:
                viewModel.handleLibraryGamepadAction(.secondaryAction)
                return nil
            case 16:
                viewModel.handleLibraryGamepadAction(.contextAction)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

private struct HeroImageBox: @unchecked Sendable {
    let image: NSImage
}
