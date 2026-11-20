import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

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
    var storageRefreshRequested = false

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
    var launchProbeTask: Task<Void, Never>?

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

    let pinnedEngineCommit = "e59c910ad5c36937e6bc6df9e3406fdc06645b38"
    let core = AppData.supportRoot
    let catalogRepository: CatalogRepository
    /// Sizes of built apps are remembered between launches, so a scan walks only new or rebuilt apps.
    lazy var importService = ImportService(sizeCache: AppSizeCache(file: core.appendingPathComponent("app-sizes.json")))
    let launchService = LaunchService()
    let developmentOperations = DevelopmentOperationStore()
    lazy var storageManager = StorageManager()
    let sourceCatalog = SourceCatalog()
    lazy var workspaceManager = WorkspaceManager(root: core.appendingPathComponent("workspaces"))
    var libraryRescanRequested = false

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

    func cleanStorage(games: [PortedGame], caches: Bool) {
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

    var cloudSavesPreferences = CloudSavesPreferences()
}
