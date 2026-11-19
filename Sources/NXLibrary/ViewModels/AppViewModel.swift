import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var retry: (() -> Void)?
    var onDismiss: (() -> Void)? = nil
    var actionTitle = "Retry"
    var cancelTitle = "Back"
}

final class AppViewModel: ObservableObject {
    /// The automatic Icon's online lookup, shared by Switch and Steam games' Change artwork.
    static let automaticIconArtwork = ArtworkStore()
    let saveGate = SaveOperationGate()
    let saveQueue = DispatchQueue(label: "local.nxlibrary.saves", qos: .userInitiated)
    @Published var settingsNotice: SettingsNotice? {
        didSet {
            if let waitingGame = appIcon.iconLaunchWait.gameID, settingsNotice?.id != appIcon.iconLaunchWait.noticeID {
                appIcon.iconLaunchWait.cancel()
                if launchingGameId == waitingGame { launchingGameId = nil }
            }
        }
    }
    @Published var settingsNoticeFocus = 0
    /// A SteamGridDB API key is saved (Settings → Online services → SteamGridDB), so Change artwork searches it.
    @Published var hasSteamGridDBKey = SteamGridDBKey().load() != nil
    @Published var isEditingSteamGridDBKey = false
    @Published var isUpdatingApp = false
    @Published private(set) var hasActiveSaveOperations = false
    @Published var runningGameCount = 0

    func showSettingsNotice(title: String, message: String, actionTitle: String = "Retry",
                            cancelTitle: String = "Back", retry: (() -> Void)? = nil) {
        settingsNoticeFocus = 0
        settingsNotice = SettingsNotice(title: title, message: message, retry: retry,
                                       actionTitle: actionTitle, cancelTitle: cancelTitle)
    }

    // MARK: - Storage Keys for Persistence
    enum StorageKeys {
        static let savedGameFolder = "NXNative_SavedGameFolder"
        static let lastPortingFinishSeconds = "NXLibrary.lastPortingFinishSeconds"
        static let savedLibraryFolder = "NXNative_SavedLibraryFolder"
        static let savedProdKeysPath = "NXNative_SavedProdKeysPath"
        static let savedIconAppearanceMode = "NXNative_SavedIconAppearanceMode"
        static let allowUntestedToolchain = "NXLibrary_AllowUntestedToolchain"
        static let setupCompleted = "NXLibrary_SetupCompleted"
        static let setupPage = "NXLibrary_SetupPage"
        static let setupSteamChoice = "NXLibrary_SetupSteamChoice"
        /// A chosen engine folder other than ~/nxnative.
        static let savedEngineFolder = "NXLibrary_EngineFolder"
        static let newestEngineChoice = "NXLibrary_NewestEngineChoice"
    }

    // MARK: - Workspace & Paths
    @Published var defaultInstallPath: String = ""

    /// The update dialog is up (set by the shell); screens leave input to it.
    var isUpdateOfferOpen = false
    /// "Welcome to Arcane" is on screen, until its fade has ended: screens' own keyboard monitors let Return and
    /// the arrows go to it, and Spotlight holds its entrance until it has gone.
    @Published var isWelcomeOpen = false
    /// The window is still taking its launch mode (Start in fullscreen): Spotlight's entrance waits for it, so the
    /// fullscreen transition never cuts the flight (`StartupWindowObserver`, at most 4 s from attachment).
    @Published var isWindowSettling = true
    /// A home screen (Spotlight or Collection) has shown since launch: Spotlight's entrance plays only on the first.
    var homeSeen = false

    var gameAppsFolder: URL {
        libraryFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    }

    // MARK: - Drag & Drop & ZIP
    @Published var dropErrorMessage: String? = nil

    // MARK: - Library
    @Published private(set) var libraryGames: [PortedGame] = []
    @Published private(set) var catalogGames: [CatalogGame] = []
    @Published private(set) var catalogSourceConfigurations: [CatalogSourceConfiguration] = []
    @Published private(set) var personalizations = CatalogPersonalizations.empty
    /// Finished file operations whose catalog save must still be retried.
    @Published var catalogBuildRecoveries = CatalogBuildRecoveries()
    @Published var libraryFolder: URL? {
        didSet {
            if let folder = libraryFolder {
                AppData.preferences.set(folder.path, forKey: StorageKeys.savedLibraryFolder)
            }
        }
    }
    /// First use asks where to find existing games and install new ones; later visits keep that choice.
    var requiresGameAppsFolderChoice: Bool {
        !setupCompleted && AppData.preferences.string(forKey: StorageKeys.savedLibraryFolder) == nil
    }
    @Published var isScanningLibrary: Bool = false
    /// Non-blocking scan details shown beside Library refresh, never an automatic launch dialog.
    @Published var libraryScanWarnings: [String] = []
    @Published var gameForSettingsSheet: PortedGame? = nil
    /// The Steam game whose Options are open (`SteamOptionsView`); never open with `gameForSettingsSheet`.
    @Published var steamOptionsGame: CatalogGame? = nil
    /// Any game's Options are open: the screens underneath stop reading input.
    var isGameOptionsOpen: Bool { gameForSettingsSheet != nil || steamOptionsGame != nil }
    /// The game whose Options are open, for the panels' own key monitors.
    var optionsGameID: UUID? { gameForSettingsSheet?.id ?? steamOptionsGame?.id }
    /// Where the open Game options came from; decides its rows (Move is Spotlight-only).
    @Published var gameOptionsOrigin: GameOptionsOrigin = .collection
    /// Game options opens straight on its Mods panel (the Details page's Mods band).
    @Published var gameOptionsOpensMods = false
    /// The running game whose Close Game confirmation is open. The shell draws the dialog.
    @Published var gameToClose: PortedGame? = nil
    @Published var closeGameFocus: SeleneConfirmButton = .cancel
    @Published var storageSnapshot: StorageSnapshot? = nil
    var storageUsage: StorageUsage? { storageSnapshot?.total }
    @Published var isCalculatingStorage: Bool = false
    @Published private(set) var isCleaningStorage = false
    @Published private(set) var storageCleanupMessage: String?
    private var storageRefreshRequested = false

    var canCleanStorage: Bool { !isBuilding && !isCleaningStorage && !isCalculatingStorage && !isUpdatingApp }
    @Published var showSetupCheck: Bool = false
    /// The Setup check's state and installs; lives with the app so an install survives closing the screen.
    lazy var setupCheck = SetupCheckModel(viewModel: self)
    @Published private(set) var firstRunSetup = FirstRunSetup() {
        didSet {
            AppData.preferences.set(firstRunSetup.isCompleted, forKey: StorageKeys.setupCompleted)
            if let page = firstRunSetup.pageToRemember {
                AppData.preferences.set(page, forKey: StorageKeys.setupPage)
            } else {
                AppData.preferences.removeObject(forKey: StorageKeys.setupPage)
            }
            if let choice = firstRunSetup.steamChoiceToRemember {
                AppData.preferences.set(choice, forKey: StorageKeys.setupSteamChoice)
            } else {
                AppData.preferences.removeObject(forKey: StorageKeys.setupSteamChoice)
            }
        }
    }
    var setupCompleted: Bool { firstRunSetup.isCompleted }
    @Published var lastError: String? = nil
    @Published var alertMessage: String? = nil
    @Published var buildLogURL: URL? = nil
    @Published var currentBuildGameID: UUID? = nil
    @Published var lastBuildGameID: UUID? = nil

    // MARK: - Build State
    /// What Add Game and its Porting step show of a build; the home reads only the three values here.
    private(set) lazy var porting = PortingModel(app: self)
    /// The Switch Setup: engine, keys, environment and the Metal gate (`SetupModel`), observed on its own.
    private(set) lazy var setup = SetupModel(app: self)
    /// A built game's saved choices for its next launch (`RuntimeSettingsModel`).
    private(set) lazy var runtimeSettings = RuntimeSettingsModel(app: self)
    /// What a game's cheats are and what to do with added files (`CheatsModel`).
    private(set) lazy var cheats = CheatsModel(app: self)
    /// The game's app icon in Finder and the Dock (`AppIconModel`), observed by Change artwork.
    private(set) lazy var appIcon = AppIconModel(app: self)
    /// The Nintendo store's data for each game, in the app language (`StoreMetadataModel`), observed by the screens
    /// that show it.
    private(set) lazy var store = StoreMetadataModel(app: self)
    @Published var isBuilding: Bool = false
    /// The running (or just finished) porting folded into one overall fraction for the home.
    @Published var portingProgress: PortingProgress? = nil
    /// The game ported last in this session leads Spotlight's row until quit.
    @Published var frontGameID: UUID? = nil
    /// The Steam games seen downloading this session lead the row after it, until quit.
    @Published private(set) var sessionDownloads = SessionDownloads()
    /// Spotlight's Delete on a failed porting asks first.
    @Published var gameToRemove: PortedGame? = nil
    @Published var removeGameFocus: SeleneConfirmButton = .cancel
    @Published var logs: [LogEntry] = []
    /// The existing Selene dialog offers retrying the ready app, or closing it.
    @Published var gameWithInstallFailure: PortedGame? = nil
    @Published var installFailureFocus: SeleneConfirmButton = .cancel

    var canRetryReadyInstall: Bool {
        porting.buildState == .failed && porting.portingFailureReason == nil
            && (libraryGames.contains { $0.id == lastBuildGameID && $0.pendingInstall != nil }
                || catalogBuildRecoveries.values.contains { $0.id == lastBuildGameID && $0.pendingInstall != nil })
    }
    @Published var iconAppearanceMode: AppIconAppearanceMode = .auto {
        didSet {
            AppData.preferences.set(iconAppearanceMode.rawValue, forKey: StorageKeys.savedIconAppearanceMode)
            updateDockIcon()
        }
    }

    // MARK: - Navigation
    @Published var librarySelection = LibrarySelectionState()
    /// Spotlight's row selection and focus; lives here so it survives Details and back.
    @Published var spotlight = SpotlightState()
    var router: AppRouter?
    /// GameTDB box covers for Collection and More like this.
    lazy var boxArt = BoxArtService(artwork: ArtworkStore(),
                                           index: GameTDBStore(directory: core.appendingPathComponent("metadata")))
    /// Bumps when a new GameTDB index arrives, so covers that found nothing look again.
    @Published private(set) var boxArtIndexVersion = 0
    @Published var launchingGameId: UUID? = nil
    /// The launch screen: shown on Play, `isReady` once the game's window is up (or the probe gave up).
    @Published var launchOverlay: LaunchOverlayState? = nil {
        didSet {
            SoundEffectService.shared.isQuieted =
                launchOverlay != nil && (settingsStore?.settings.quietLaunch ?? true)
        }
    }
    private var launchProbeTask: Task<Void, Never>?

    var playSessionStore: PlaySessionStore?
    var settingsStore: AppSettingsStore?

    let availableLanguages: [(code: String, label: String)] = [
        ("auto", "Game Default"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("ja", "Japanese"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("zh-Hans", "Chinese (Simplified)"),
        ("ko", "Korean")
    ]

    let pinnedEngineCommit = "461a5f9f95fc9fc40a690bb2a82eb23f1f03bdca"
    let core = AppData.supportRoot
    let catalogRepository: CatalogRepository
    /// Sizes of built apps are remembered between launches, so a scan walks only new or rebuilt apps.
    private lazy var importService = ImportService(sizeCache: AppSizeCache(file: core.appendingPathComponent("app-sizes.json")))
    private let launchService = LaunchService()
    let developmentOperations = DevelopmentOperationStore()
    private lazy var storageManager = StorageManager()
    let sourceCatalog = SourceCatalog()
    lazy var workspaceManager = WorkspaceManager(root: core.appendingPathComponent("workspaces"))
    private var libraryRescanRequested = false

    init(settingsStore: AppSettingsStore, catalog: CatalogDocument, repository: CatalogRepository) {
        self.catalogRepository = repository
        self.settingsStore = settingsStore
        applyCatalog(catalog)
        saveGate.onActivityChange = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.hasActiveSaveOperations = self.saveGate.hasActiveOperations
            }
        }
        let startup = settingsStore.settings
        let didCompleteSetup = AppData.preferences.bool(forKey: StorageKeys.setupCompleted)
        self.firstRunSetup = FirstRunSetup(completed: didCompleteSetup,
                                           savedPage: AppData.preferences.string(forKey: StorageKeys.setupPage),
                                           savedSteamChoice: AppData.preferences.object(forKey: StorageKeys.setupSteamChoice) as? Bool)
        self.showSetupCheck = !didCompleteSetup

        // 1. Resolve safe root directory (anchored to SSD / Bundle, NEVER "/")
        let root = SystemDetector.shared.resolveRootDirectory()
        self.defaultInstallPath = root.path

        // The launcher's old ~/Games default is not a Mac-app library.
        let oldGamesDefault = root.appendingPathComponent("Games").standardized.path
        if let savedLib = AppData.preferences.string(forKey: StorageKeys.savedLibraryFolder),
           savedLib != oldGamesDefault, !savedLib.isEmpty, savedLib != "/" {
            self.libraryFolder = URL(fileURLWithPath: savedLib)
        } else {
            self.libraryFolder = root.appendingPathComponent("Applications")
            AppData.preferences.removeObject(forKey: StorageKeys.savedLibraryFolder)
        }

        // Restore user preferences
        if let savedMode = AppData.preferences.string(forKey: StorageKeys.savedIconAppearanceMode),
           let mode = AppIconAppearanceMode(rawValue: savedMode) {
            self.iconAppearanceMode = mode == .mono ? .mono : .auto
        }

        setup.restoreBuildInputs(automatic: true)
        if !AppData.profile.isDevelopment && (startup.checkEngineAtLaunch || !didCompleteSetup) { setup.refreshCompatibility() }

        // Keep Game files as a picker preference, not an active Add game draft.
        // Assigning selectedGameFolder scans it; launch refresh only concerns installed apps.

        recoverSavesAtStartup()
        if !setupCompleted && firstRunSetup.page == .games { prepareInitialGameAppsFolder() }
        if startup.refreshLibraryAtLaunch || (!setupCompleted && firstRunSetup.page == .games) { scanLibrary(using: catalog) }
        updateDockIcon()
        // Register notification-click routing at launch without asking for permission.
        _ = NotificationService.shared

        let held = PendingInstaller.keptFolders(libraryGames)
        let staging = AppData.profile.automaticStagingFolders(
            appFolders: [gameAppsFolder] + libraryGames.map { $0.url.deletingLastPathComponent() })
        DispatchQueue.global(qos: .utility).async {
            PortingModel.sweepStaleBuildTemp(in: staging, keeping: held)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.porting.buildService?.terminateNow()
            if let temp = self?.porting.buildTempDirectory {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-setup") {
            self.showSetupCheck = true
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-build") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.porting.previewBuild()
            }
        }
        #endif
    }

    // MARK: - Dynamic Dock Icon
    func updateDockIcon() {
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let resName: String
        switch iconAppearanceMode {
        case .light: resName = "AppIcon-Light"
        case .dark: resName = "AppIcon-Dark"
        case .mono: resName = "AppIcon-Mono"
        case .auto: resName = isDark ? "AppIcon-Dark" : "AppIcon-Light"
        }

        if let url = Bundle.main.url(forResource: resName, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = img
        }
    }

    /// Fetches GameTDB's index at launch when it is missing or 30 days old.
    func refreshBoxArtIndex() {
        let service = boxArt
        Task { @MainActor [weak self] in
            if await service.refreshIndexIfNeeded() { self?.boxArtIndexVersion += 1 }
        }
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func advanceSetupToGames() {
        guard showSetupCheck else { return }
        if !setupCompleted { prepareInitialGameAppsFolder() }
        importExistingBuilds()
        firstRunSetup.advance()
    }

    func returnToSetupRequirements() { firstRunSetup.goBack() }

    /// The Porting card on the first launch's `found` page.
    func openPortingFromFound() {
        guard showSetupCheck, !setupCompleted else { return }
        firstRunSetup.openPorting()
    }

    /// The Steam switch on `found`; the shell applies it when the first launch finishes.
    func chooseSteamOnFound(_ on: Bool) { firstRunSetup.chooseSteam(on) }

    /// Back from the requirements to `found`, during the first launch only.
    func returnToFound() { firstRunSetup.returnToFound() }

    /// Open library on `found`. Ported apps already in the Game apps folder join the library, which
    /// turns the Switch source on; without them it stays off until the player chooses Porting.
    func finishFromFound(importPorted: Bool) {
        guard showSetupCheck, !setupCompleted else { return }
        if importPorted {
            prepareInitialGameAppsFolder()
            importExistingBuilds()
        }
        completeSetup()
    }

    private func prepareInitialGameAppsFolder() {
        do {
            try GameAppDestination.prepareInitialFolder(gameAppsFolder,
                hasExplicitChoice: AppData.preferences.string(forKey: StorageKeys.savedLibraryFolder) != nil)
        } catch {
            logs.append(LogEntry(level: .warning, message: L10n.format("Could not prepare the default Game apps folder: %@", [String(describing: error.localizedDescription)])))
        }
    }

    func completeSetup() {
        AppData.preferences.set(gameAppsFolder.path, forKey: StorageKeys.savedLibraryFolder)
        firstRunSetup.finish()
        showSetupCheck = false
        logs.append(LogEntry(level: .success, message: L10n.text("Setup completed.")))
    }

    func reopenSetup() {
        guard !isBuilding, !isUpdatingApp else { return }
        firstRunSetup.goBack()
        showSetupCheck = true
    }

    func refreshStorageUsage() {
        guard !isCleaningStorage else { return }
        guard !isCalculatingStorage else { storageRefreshRequested = true; return }
        isCalculatingStorage = true
        let manager = storageManager
        let games = libraryGames
        let folder = gameAppsFolder
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot = manager.snapshot(games: games, applicationsFolder: folder)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCalculatingStorage = false
                if self.storageRefreshRequested || self.libraryGames != games || self.gameAppsFolder != folder {
                    self.storageRefreshRequested = false
                    self.refreshStorageUsage()
                } else {
                    self.storageSnapshot = snapshot
                }
            }
        }
    }

    func deleteCaches(for selected: PortedGame? = nil) {
        guard canCleanStorage else {
            showSettingsNotice(title: L10n.text("Cleanup unavailable"),
                               message: L10n.text("Wait for the current build, storage operation or app update to finish."))
            return
        }
        if let selected {
            guard let current = libraryGames.first(where: { $0.id == selected.id }),
                  current.buildCachePath == selected.buildCachePath,
                  current.workspacePath == selected.workspacePath else {
                showSettingsNotice(title: L10n.text("Cache changed"), message: L10n.text("Recalculate storage and choose the game again. Nothing was deleted."))
                refreshStorageUsage()
                return
            }
            cleanStorage(games: [current], caches: true)
        } else {
            cleanStorage(games: libraryGames, caches: true)
        }
    }

    func deleteLogs() {
        guard canCleanStorage else {
            showSettingsNotice(title: L10n.text("Cleanup unavailable"),
                               message: L10n.text("Wait for the current build, storage operation or app update to finish."))
            return
        }
        cleanStorage(games: libraryGames, caches: false)
    }

    private func cleanStorage(games: [PortedGame], caches: Bool) {
        isCleaningStorage = true
        storageCleanupMessage = nil
        let manager = storageManager
        let protectedGames = libraryGames
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var removed = 0
            var failures: [String] = []
            for game in games {
                do {
                    if caches {
                        if try manager.deleteCache(for: game, protecting: protectedGames) { removed += 1 }
                    } else {
                        if try manager.deleteLogs(for: game) { removed += 1 }
                    }
                } catch { failures.append("\(game.name): \(error.localizedDescription)") }
            }
            let message = caches
                ? (removed == 0 ? L10n.text("No build caches were deleted.") : L10n.count("Deleted %lld build caches. Future rebuilds may take longer.", removed, arguments: []))
                : (removed == 0 ? L10n.text("No logs were deleted.") : L10n.count("Deleted logs for %lld games.", removed, arguments: []))
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCleaningStorage = false
                self.storageCleanupMessage = message
                self.logs.append(LogEntry(level: .info, message: message))
                if !failures.isEmpty {
                    self.showSettingsNotice(title: L10n.text("Some files were not deleted"), message: failures.joined(separator: "\n"))
                }
                self.refreshStorageUsage()
            }
        }
    }

    // MARK: - Drag and Drop & ZIP
    func handleDroppedURLs(_ urls: [URL]) {
        dropErrorMessage = nil
        guard let first = urls.first else { return }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir) {
            if isDir.boolValue {
                self.porting.selectedGameFolder = first
            } else {
                let parent = first.deletingLastPathComponent()
                self.porting.selectedGameFolder = parent
            }
        }
    }

    // MARK: - Library
    func refreshLibrary() {
        loadLibrary()
    }

    func applyCatalog(_ document: CatalogDocument) {
        catalogGames = document.games
        // Published only when a game is new, so a rescan that changes nothing redraws nothing for it.
        var downloads = sessionDownloads
        if downloads.note(document.games) { sessionDownloads = downloads }
        catalogSourceConfigurations = document.sources
        personalizations = CatalogPersonalizations(document: document)
        libraryGames = document.nxnativeGames.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func loadLibrary() {
        guard !isScanningLibrary else { libraryRescanRequested = true; return }
        libraryRescanRequested = false
        do {
            let current = try catalogRepository.load()
            applyCatalog(current)
            scanLibrary(using: current)
        } catch { reportCatalogFailure(error) }
    }

    /// Startup consumes its already-validated document, without a second
    /// fallible read before publishing the shell or starting runtime hooks.
    private func scanLibrary(using current: CatalogDocument) {
        guard !isScanningLibrary else { return }
        let choosingSwitch = !setupCompleted && firstRunSetup.page == .games
        guard current.source(.nxnative)?.isEnabled == true || choosingSwitch else { return }
        let existing = current.nxnativeGames
        isScanningLibrary = true
        let fm = FileManager.default
        let directories = [gameAppsFolder]
        let importer = importService
        let folderSnapshot = libraryFolder?.standardizedFileURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanned = importer.scan(directories: directories)
            let scanWarnings = importer.scanWarnings
            let selected = importer.appsForLibrary(scanned: scanned, existing: existing)
            let importedGames = selected.map { importer.makeGame(from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.libraryFolder?.standardizedFileURL == folderSnapshot else {
                    self.isScanningLibrary = false
                    self.loadLibrary()
                    return
                }
                defer {
                    self.isScanningLibrary = false
                    if self.libraryRescanRequested {
                        self.libraryRescanRequested = false
                        self.loadLibrary()
                    }
                }
                var scannedByTitle: [String: ImportedApp] = [:]
                for app in selected {
                    if let titleId = app.titleId, scannedByTitle[titleId.uppercased()] == nil {
                        scannedByTitle[titleId.uppercased()] = app
                    }
                }
                do {
                    let catalog = try self.catalogRepository.mergeNXNative(scanned: importedGames, enableSource: choosingSwitch, observedFrom: existing) { games, acceptedIDs in
                        for index in games.indices where acceptedIDs.contains(games[index].id) {
                            let scannedApp = games[index].titleId
                                .flatMap { scannedByTitle[$0.uppercased()] }
                            if let scannedApp, !fm.fileExists(atPath: games[index].url.path),
                               fm.fileExists(atPath: scannedApp.appURL.path) {
                                games[index].url = scannedApp.appURL
                            }
                            if let scannedApp, fm.fileExists(atPath: scannedApp.appURL.path) {
                                games[index].sizeBytes = scannedApp.sizeBytes
                                games[index].versionString = scannedApp.version
                                    ?? games[index].versionString
                                games[index].bundleId = scannedApp.bundleId
                                    ?? games[index].bundleId
                            }
                            let appExists = fm.fileExists(atPath: games[index].url.path)
                            let sourcesExist = GameResourceState.sourcesAvailable(for: games[index], fileManager: fm)
                            games[index].status = GameResourceState.reconciledStatus(
                                for: games[index], appExists: appExists, sourcesAvailable: sourcesExist)
                        }
                    }
                    self.applyCatalog(catalog)
                    self.appIcon.reconcileAppIcons()
                } catch { self.reportCatalogFailure(error) }
                self.libraryScanWarnings = scanWarnings
                for warning in scanWarnings { self.logs.append(LogEntry(level: .warning, message: warning)) }
            }
        }
    }

    func importExistingBuilds() {
        do { applyCatalog(try catalogRepository.configureSource(.nxnative, enabled: true, root: nil)); loadLibrary() }
        catch { reportCatalogFailure(error) }
    }

    /// Attach source files to an already-imported app. The app URL, version and
    /// build metadata stay intact; the library entry is merged, never duplicated.
    func locateSources(for game: PortedGame) {
        guard let titleId = game.titleId, !titleId.isEmpty else {
            alertMessage = "This game has no title ID, so its sources cannot be matched."
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Locate Sources"
        panel.message = "Choose the folder holding the base, update and DLC files for \(game.name)."
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        porting.isScanningGameFolder = true
        let catalog = sourceCatalog
        let repo = URL(fileURLWithPath: setup.nxnativePath)
        let toolchain = setup.engineToolchain
        let keys = setup.isProdKeysValid ? setup.keyStore.keyURL : nil
        let developer = setup.resolvedDeveloperDir()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = ExtractedSourceCatalog.recognizes(folder) ? [] : PortingModel.sourceFileURLs(in: folder)
            let outcome = Result { try PortingModel.scanSources(in: folder, files: urls, catalog: catalog,
                repo: repo, toolchain: toolchain, keys: keys, developerDir: developer) }
            let detected = (try? outcome.get().games) ?? []
            let match = detected.first {
                String(format: "%016llX", $0.baseTitleId)
                    .caseInsensitiveCompare(titleId) == .orderedSame
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.porting.isScanningGameFolder = false
                guard let match, match.hasGame else {
                    if case .failure(let error) = outcome { self.alertMessage = error.localizedDescription }
                    else { self.alertMessage = "No base, update or DLC files for \(game.name) were found in that folder." }
                    self.logs.append(LogEntry(level: .warning, message: self.alertMessage!))
                    return
                }
                var selected = [match.base].compactMap { $0 }
                if let newest = match.updates.max(by: {
                    ($0.version ?? -1) < ($1.version ?? -1)
                }) {
                    selected.append(newest)
                }
                selected += match.dlcs
                do {
                    let updated = try self.porting.addGame(
                        detected: match,
                        selected: selected,
                        folder: nil,
                        bundleId: game.bundleId
                    )
                    self.librarySelection.selectedGameID = updated.id
                    self.logs.append(LogEntry(level: .success,
                        message: L10n.format("Sources attached to %@; rebuild is now available if the toolchain gate allows it.", [String(describing: game.name)])))
                } catch {
                    self.alertMessage = error.localizedDescription
                    self.logs.append(LogEntry(level: .error, message: error.localizedDescription))
                }
            }
        }
    }

    func selectLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = libraryFolder
        panel.prompt = "Choose folder"
        panel.message = GameFoldersCopy.appsPickerMessage

        if panel.runModal() == .OK, let url = panel.url {
            guard url.standardizedFileURL.path != "/" else {
                alertMessage = "Choose the folder containing your game apps, rather than a whole disk."
                return
            }
            self.libraryFolder = url
            loadLibrary()
        }
    }

    func launchGame(_ game: PortedGame) {
        // One launch at a time: the launch screen covers the library, and input reaching it changes nothing.
        guard launchingGameId == nil, launchOverlay == nil else { return }
        // A running game is brought forward, never started a second time.
        if let running = RunningGameMonitor.runningApplication(for: game) {
            RunningGameMonitor.activate(running)
            return
        }
        guard savesPermitPlay(game) else { return }
        // Installing a waiting build can itself start an icon update: check after installation too.
        let game = installingPendingBuild(of: game)
        // The app is being signed again with a new icon: starting it now could read a half-written bundle.
        guard !appIcon.appIconsInFlight.contains(game.id) else {
            appIcon.waitForAppIconBeforeLaunching(game)
            return
        }
        if !FileManager.default.fileExists(atPath: game.url.path),
           game.isPlayableLocally || game.status == .appMissing {
            let reason = GameUnavailableReason.appMissing
            lastError = reason.title + ". " + reason.detail
            alertMessage = lastError
            updateStoredStatus(.appMissing, for: game)
            SoundEffectService.shared.play(.error)
            return
        }
        guard game.isPlayableLocally else {
            let reason = GameResourceState.unavailableReason(for: game)
            let message = reason.map { $0.title + ". " + $0.detail }
                ?? L10n.text("This game is not built yet. Build it first.")
            lastError = message
            alertMessage = message
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: message))
            return
        }
        guard FileManager.default.fileExists(atPath: game.url.path) else {
            let reason = GameUnavailableReason.appMissing
            lastError = reason.title + ". " + reason.detail
            alertMessage = lastError
            updateStoredStatus(.appMissing, for: game)
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: lastError!))
            return
        }
        guard let titleId = game.titleId, !titleId.isEmpty else {
            lastError = NXLibraryError.missingTitleId.localizedDescription
            alertMessage = lastError
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: lastError!))
            return
        }

        guard let saveLaunchToken = saveGate.begin(titleID: titleId) else {
            alertMessage = SaveFailure.busy.localizedDescription
            return
        }
        launchingGameId = game.id
        launchOverlay = LaunchOverlayState(game: .nxnative(game))
        SoundEffectService.shared.play(.launch)

        // A saved-choices build reads the game's own store; only an older build takes env.txt and the environment.
        let gameSettings = runtimeSettings.gameSettings(for: game)
        let config = GameRuntimeConfig.load(for: game)
        do {
            if let gameSettings {
                try gameSettings.migrate()
            } else {
                try launchService.writeEnvironment(settings: config, titleId: titleId)
            }
        } catch {
            saveGate.end(titleID: titleId, token: saveLaunchToken)
            launchingGameId = nil
            launchOverlay = nil
            lastError = error.localizedDescription
            alertMessage = lastError
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error,
                                 message: L10n.format("Could not write the runtime environment: %@", [String(describing: error.localizedDescription)])))
            return
        }

        if let choice = settingsStore?.settings.cloudSaves, let domain = game.effectiveBundleId {
            do {
                try cloudSavesPreferences.applyBeforeLaunch(choice, domain: domain)
            } catch {
                logs.append(LogEntry(level: .warning, message: L10n.format("Cloud saves: %@", [String(describing: error.localizedDescription)])))
                showSettingsNotice(title: L10n.text("Cloud unavailable"),
                                   message: L10n.text("Cloud sync could not be updated for this launch. Check Games → Cloud saves."))
            }
        }

        // Play can come straight from the row. Reconcile removed mod folders before the game reads its overlay.
        if let store = modStore(for: game) { _ = performModChange { try store.sync() } }

        launchService.launch(appURL: game.url,
                             environment: gameSettings == nil ? config.toEnvironmentDict() : [:]) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveGate.end(titleID: titleId, token: saveLaunchToken)
                if success {
                    self.lastError = nil
                    self.playSessionStore?.start(for: game)
                    self.logs.append(LogEntry(level: .success, message: L10n.format("Launched game: %@", [String(describing: game.name)])))
                    self.watchLaunch(of: game)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if self.launchingGameId == game.id { self.launchingGameId = nil }
                    }
                } else {
                    let message = error ?? NXLibraryError.launchFailed(game.name).localizedDescription
                    self.launchingGameId = nil
                    self.launchOverlay = nil
                    self.lastError = message
                    self.alertMessage = message
                    SoundEffectService.shared.play(.error)
                    self.logs.append(LogEntry(level: .error, message: message))
                }
            }
        }
    }

    /// Marks the launch screen ready once the game shows a window, or after the probe times out.
    private func watchLaunch(of game: PortedGame) {
        launchProbeTask?.cancel()
        guard let bundleID = game.effectiveBundleId else {
            launchOverlay?.isReady = true
            return
        }
        launchProbeTask = Task { [weak self] in
            let visible = await LaunchReadinessProbe().waitUntilVisible(bundleID: bundleID)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.launchOverlay?.game.id == game.id else { return }
                if visible {
                    SoundEffectService.shared.play(.gameReady)
                } else {
                    self.logs.append(LogEntry(level: .warning,
                                              message: L10n.format("%@ showed no window within 60 s; launch screen closed.", [String(describing: game.name)])))
                }
                self.launchOverlay?.isReady = true
            }
        }
    }

    /// Called by the launch screen after its fade out.
    func dismissLaunchOverlay() {
        launchProbeTask?.cancel()
        launchProbeTask = nil
        launchOverlay = nil
    }

    /// Opens Game options for a game, remembering the screen it was opened from.
    func openGameOptions(_ game: PortedGame, from origin: GameOptionsOrigin, opensMods: Bool = false) {
        gameOptionsOrigin = origin
        gameOptionsOpensMods = opensMods
        steamOptionsGame = nil
        gameForSettingsSheet = game
    }

    /// Opens a Steam game's Options, remembering the screen it was opened from.
    func openSteamOptions(_ game: CatalogGame, from origin: GameOptionsOrigin) {
        guard game.integration == .steam else { return }
        gameOptionsOrigin = origin
        gameForSettingsSheet = nil
        steamOptionsGame = game
    }

    /// Flips the favorite heart and saves the library.
    func toggleFavorite(_ game: PortedGame) {
        updateStoredGame(game) { $0.isFavorite.toggle() }
    }

    /// Flips the hidden flag and saves the library. Hidden games leave Spotlight,
    /// Collection and Surprise me; the screens reconcile their selection on the change.
    var cloudSavesPreferences = CloudSavesPreferences()

    /// Gives the whole library one cloud saves folder (or none): written into every
    /// game's preferences now, and again before each start (see `launchGame`).
    func setCloudSaves(_ choice: CloudSaves) {
        guard let settingsStore else { return }
        do {
            try cloudSavesPreferences.apply(choice, to: libraryGames.compactMap(\.effectiveBundleId))
        } catch {
            let message = (error as? CloudSavesPreferences.Failure) == .iCloudDriveOff
                ? L10n.text("Turn on iCloud Drive or choose a sync folder.")
                : L10n.text("The sync folder is unavailable. Choose another folder.")
            showSettingsNotice(title: L10n.text("Cloud unavailable"), message: message)
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: error.localizedDescription))
            return
        }
        settingsStore.settings.cloudSaves = choice
        if case .folder(let path) = choice { settingsStore.settings.cloudSavesPickedFolder = path }
        logs.append(LogEntry(level: .info, message: L10n.format("Cloud saves: %@", [String(describing: choice.folderURL()?.path ?? "off")])))
    }

    /// Picks a folder for cloud saves; Cancel keeps the current choice.
    func chooseCloudSavesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use for Cloud Saves"
        panel.message = "Choose the folder every game syncs its save through, for example one in iCloud Drive."
        panel.directoryURL = CloudSaves.iCloudDriveRoot()
        if panel.runModal() == .OK, let url = panel.url {
            setCloudSaves(.folder(url.path))
        }
    }

    func toggleHidden(_ game: PortedGame) {
        updateStoredGame(game) { $0.isHidden.toggle() }
    }

    /// Applies one change to the stored game and saves the library, the same way for every flag.
    private func updateStoredGame(_ game: PortedGame, _ change: (inout PortedGame) -> Void) {
        do { applyCatalog(try catalogRepository.updateNXNative(id: game.id, change)) }
        catch { reportCatalogFailure(error) }
    }

    /// Opens the Close Game confirmation for a running game (Spotlight and Details).
    func askCloseGame(_ game: PortedGame) {
        closeGameFocus = .cancel
        gameToClose = game
    }

    func dismissCloseGame() {
        gameToClose = nil
        closeGameFocus = .cancel
    }

    /// Spotlight's Delete on a failed porting: the same confirmation as Game options' removal.
    func askRemoveGame(_ game: PortedGame) {
        removeGameFocus = .cancel
        gameToRemove = game
    }

    func dismissRemoveGame() {
        gameToRemove = nil
        removeGameFocus = .cancel
    }

    func confirmRemoveGame() {
        guard let game = gameToRemove else { return }
        dismissRemoveGame()
        deletePortedGame(game)
    }

    /// A library that could not be written: what the player sees would be gone at the next start, so say so once
    /// (in the log every time) instead of losing it in silence.
    func reportLibrarySaveFailure(_ error: Error) {
        let message = L10n.text("Arcane could not save your library, so recent changes may be lost when it quits: ")
            + error.localizedDescription
        logs.append(LogEntry(level: .error, message: message))
        if alertMessage == nil { alertMessage = message }
    }

    private func updateStoredStatus(_ status: GameStatus, for game: PortedGame) {
        updateStoredGame(game) { $0.status = status }
    }

    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// A human-readable summary for the destructive source-removal confirmation.
    func sourceRemovalSummary(for game: PortedGame) -> String {
        let fm = FileManager.default
        let existingSources = game.sources.filter {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: $0.url.path, isDirectory: &isDir) && !isDir.boolValue
        }
        let sourceBytes = existingSources.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let workspaceBytes: Int64
        if let path = game.workspacePath {
            let workspace = URL(fileURLWithPath: path).standardizedFileURL
            workspaceBytes = BuildScratch.isManaged(workspace, core: core)
                ? directorySize(workspace) : 0
        } else {
            workspaceBytes = 0
        }

        var parts: [String] = []
        if !existingSources.isEmpty {
            parts.append(L10n.count("%lld original source files (%@)", existingSources.count, arguments: [Self.formatBytes(sourceBytes)]))
        }
        if workspaceBytes > 0 {
            parts.append(L10n.format("Build cache (%@)", [Self.formatBytes(workspaceBytes)]))
        }
        let target = parts.isEmpty ? L10n.text("Remaining build data") : parts.joined(separator: ", ")
        return L10n.format("This permanently deletes: %@. The installed app, saves and logs stay. Rebuilds will be disabled until you attach the sources again. This cannot be undone.", [target])
    }

    func removeSources(for game: PortedGame) {
        guard !isBuilding else {
            alertMessage = L10n.text("Wait for the current build to finish before removing sources.")
            return
        }
        let fm = FileManager.default
        let current: CatalogDocument
        do { current = try catalogRepository.load() }
        catch { reportCatalogFailure(error); return }
        guard current.nxnativeGames.contains(where: { $0.id == game.id }) else {
            alertMessage = L10n.format("Could not load the library entry for %@.", [game.name])
            return
        }

        let appPath = game.url.standardizedFileURL.path
        let otherGames = current.nxnativeGames.filter { $0.id != game.id }
        var removedCount = 0
        var removedBytes: Int64 = 0
        var failures: [String] = []

        for source in game.sources {
            let url = source.url.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                failures.append(L10n.format("%@ is a folder", [url.lastPathComponent]))
                continue
            }
            if url.path.hasPrefix(appPath + "/") {
                failures.append(L10n.format("%@ is inside the app", [url.lastPathComponent]))
                continue
            }
            let shared = otherGames.contains { other in
                other.sources.contains { $0.url.standardizedFileURL == url }
            }
            if shared {
                failures.append(L10n.format("%@ is also used by another library entry", [url.lastPathComponent]))
                continue
            }
            do {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    .map(Int64.init) ?? source.sizeBytes
                try fm.removeItem(at: url)
                removedCount += 1
                removedBytes += size
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        var removedWorkspace = false
        if let path = game.workspacePath {
            let workspace = URL(fileURLWithPath: path).standardizedFileURL
            if BuildScratch.isManaged(workspace, core: core),
               fm.fileExists(atPath: workspace.path) {
                do {
                    try fm.removeItem(at: workspace)
                    removedWorkspace = true
                } catch {
                    failures.append(L10n.format("Build cache: %@", [error.localizedDescription]))
                }
            }
        }

        var updated = current.nxnativeGames.first { $0.id == game.id }!
        updated.sources = updated.sources.filter { source in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: source.url.path, isDirectory: &isDir)
                && !isDir.boolValue
        }
        if removedWorkspace || updated.workspacePath.map({
            !fm.fileExists(atPath: URL(fileURLWithPath: $0).path)
        }) == true {
            updated.workspacePath = nil
            updated.buildCachePath = nil
        }
        if updated.sources.isEmpty {
            updated.status = .builtSourcesMissing
        }
        do {
            applyCatalog(try catalogRepository.updateNXNative(id: game.id) { stored in
                stored.sources = updated.sources
                stored.workspacePath = updated.workspacePath
                stored.buildCachePath = updated.buildCachePath
                stored.status = updated.status
            })
        } catch {
            alertMessage = L10n.format("The sources were removed, but the library could not be saved: %@", [error.localizedDescription])
            logs.append(LogEntry(level: .error, message: alertMessage!))
            return
        }
        let removed = L10n.count("Removed %lld source files (%@).", removedCount, arguments: [Self.formatBytes(removedBytes)])
            + (removedWorkspace ? " " + L10n.text("The build cache was also removed.") : "")
        if failures.isEmpty {
            logs.append(LogEntry(level: .success,
                                 message: L10n.format("%@ The installed app and saves were kept.", [String(describing: removed)])))
            alertMessage = L10n.format("%@ The installed app and saves were kept. Rebuilds stay disabled until you attach the sources again.", [removed])
        } else {
            let detail = failures.joined(separator: "; ")
            logs.append(LogEntry(level: .warning,
                                 message: L10n.format("%@ Some items were kept: %@", [String(describing: removed), String(describing: detail)])))
            alertMessage = L10n.format("%@ Some items were kept: %@", [removed, detail])
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(Int64.init) ?? 0
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    static func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(L10n.context.formatLocale))
    }

    func deletePortedGame(_ game: PortedGame) {
        do {
            let deleteBundle = game.canDeleteAppBundle()
            if deleteBundle, FileManager.default.fileExists(atPath: game.url.path) {
                try FileManager.default.removeItem(at: game.url)
            }

            // Remove only the app-owned staged workspace. A folder-mode game's
            // workspace is the user's source folder and must never be touched.
            var removedWorkspace = false
            if let path = game.workspacePath {
                let workspace = URL(fileURLWithPath: path).standardizedFileURL
                if BuildScratch.isManaged(workspace, core: core),
                   FileManager.default.fileExists(atPath: workspace.path) {
                    try? FileManager.default.removeItem(at: workspace)
                    removedWorkspace = !FileManager.default.fileExists(atPath: workspace.path)
                }
            }

            applyCatalog(try catalogRepository.updateNXNativeGames { games in
                games.removeAll { $0.id == game.id }
            })
            if deleteBundle {
                logs.append(LogEntry(level: .warning,
                    message: L10n.format("Game app deleted: %@%@", [String(describing: game.name), String(describing: removedWorkspace ? "; staged workspace removed" : "")])))
            } else {
                logs.append(LogEntry(level: .warning,
                    message: L10n.format("Removed %@ from the library; its source folders were left in place.", [String(describing: game.name)])))
            }
        } catch {
            let message = L10n.format("Failed to delete game: %@", [String(describing: error.localizedDescription)])
            alertMessage = message
            logs.append(LogEntry(level: .error, message: message))
        }
    }

    // MARK: - File Pickers

    func selectRyujinxFolder() {
        guard !isBuilding, !isUpdatingApp else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Ryujinx Folder"
        panel.message = "Select your Ryujinx folder to automatically locate prod.keys."

        if panel.runModal() == .OK, let url = panel.url {
            setup.detectEnvironment(customRyujinxDir: url.path)
        }
    }

    func logURL(for game: PortedGame) -> URL? {
        if let path = game.lastBuild?.logPath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        guard let titleId = game.titleId, !titleId.isEmpty else { return nil }
        return launchService.logURL(for: titleId)
    }

    func revealLog(for game: PortedGame) {
        guard let url = logURL(for: game) else {
            logs.append(LogEntry(level: .warning, message: L10n.format("No log path is known for %@.", [String(describing: game.name)])))
            return
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
            logs.append(LogEntry(level: .info,
                                 message: L10n.format("No log yet for %@; opened the log folder.", [String(describing: game.name)])))
        }
    }

}
