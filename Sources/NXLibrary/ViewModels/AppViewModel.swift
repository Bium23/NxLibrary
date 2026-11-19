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

public final class AppViewModel: ObservableObject {
    /// Games whose app icon is being written (`AppViewModel+AppIcon`), and those asked again meanwhile.
    var appIconsInFlight = Set<UUID>()
    var appIconRerun = Set<UUID>()
    /// Finished build logs waiting for their separate icon preparation result.
    var appIconBuildLogs: [UUID: URL] = [:]
    var iconLaunchWait = IconLaunchWait()
    /// The last app icon change per game, for Change artwork's status line.
    @Published var appIconProgress: [UUID: AppIconProgress] = [:]
    let saveGate = SaveOperationGate()
    let saveQueue = DispatchQueue(label: L10n.text("local.nxlibrary.saves"), qos: .userInitiated)
    @Published var settingsNotice: SettingsNotice? {
        didSet {
            if let waitingGame = iconLaunchWait.gameID, settingsNotice?.id != iconLaunchWait.noticeID {
                iconLaunchWait.cancel()
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
    private enum StorageKeys {
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
    @Published public var defaultInstallPath: String = ""
    @Published public var nxnativePath: String = ""
    @Published public var isNxnativeValid: Bool = false
    @Published public var isCloningRepository: Bool = false
    @Published public var cloneErrorMessage: String? = nil
    
    // MARK: - Keys
    @Published public var prodKeysPath: String = "" {
        didSet {
            if !prodKeysPath.isEmpty {
                AppData.preferences.set(prodKeysPath, forKey: StorageKeys.savedProdKeysPath)
            }
        }
    }
    @Published public var prodKeysSource: String = ""
    @Published public var isProdKeysValid: Bool = false
    
    /// The last porting's command line, for Copy diagnostics (its environment is never kept).
    var lastPortingCommand: [String] = []
    /// Set by a failed porting's notification: the next Add game opens on that failure.
    var reviewsFailureOnAddGame = false
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
    
    // MARK: - Disk Capacity Pre-flight
    public func freeBytes(at url: URL) -> Int64? {
        let fm = FileManager.default
        // A folder not made yet (a build's staging folder) is on its nearest existing parent's volume.
        var target = url.standardizedFileURL
        while !fm.fileExists(atPath: target.path), target.path != "/" {
            target = target.deletingLastPathComponent()
        }
        var stat = statvfs()
        if statvfs(target.path, &stat) == 0 {
            return Int64(stat.f_bavail) * Int64(stat.f_frsize)
        }
        let values = try? target.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                      .volumeAvailableCapacityKey])
        if let cap = values?.volumeAvailableCapacityForImportantUsage {
            return cap
        }
        return values?.volumeAvailableCapacity.map { Int64($0) }
    }


    var gameAppsFolder: URL {
        libraryFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    }


    /// The folders a build writes to: its workspace (a player's own one beside the sources is kept), its staged app
    /// and the app's folder. They are on the app's drive when it can hold builds.
    func buildFolders(appFolder: URL, workspace: String?) -> [URL] {
        let existing = workspace.map { URL(fileURLWithPath: $0) }
        let scratch = BuildScratch.choose(core: core, appFolder: appFolder, existingWorkspace: existing)
        let own = existing.flatMap { BuildScratch.isManaged($0, core: core) ? nil : $0 }
        return [own ?? scratch.workspaces, scratch.temp, appFolder]
    }
    
    public var engineSourceCapabilities: EngineSourceCapabilities {
        EngineSourceCapabilities(repo: URL(fileURLWithPath: nxnativePath))
    }

    public func supportsSources(_ sources: [GameFileItem]) -> Bool {
        let capabilities = engineSourceCapabilities
        return SourceSelection.supported(sources, titleSelection: capabilities.titleSelection,
                                         extractedFolders: capabilities.extractedFolders,
                                         nupContainers: capabilities.nupContainers,
                                         nupPrograms: capabilities.nupPrograms)
    }
    
    
    // MARK: - Drag & Drop & ZIP
    @Published public var dropErrorMessage: String? = nil
    
    // MARK: - Library
    @Published public private(set) var libraryGames: [PortedGame] = []
    @Published public private(set) var catalogGames: [CatalogGame] = []
    @Published public private(set) var catalogSourceConfigurations: [CatalogSourceConfiguration] = []
    @Published private(set) var personalizations = CatalogPersonalizations.empty
    /// Finished file operations whose catalog save must still be retried.
    @Published var catalogBuildRecoveries = CatalogBuildRecoveries()
    @Published public var libraryFolder: URL? {
        didSet {
            if let folder = libraryFolder {
                AppData.preferences.set(folder.path, forKey: StorageKeys.savedLibraryFolder)
            }
        }
    }
    /// First use asks where to find existing games and install new ones; later visits keep that choice.
    public var requiresGameAppsFolderChoice: Bool {
        !setupCompleted && AppData.preferences.string(forKey: StorageKeys.savedLibraryFolder) == nil
    }
    @Published public var isScanningLibrary: Bool = false
    /// Non-blocking scan details shown beside Library refresh, never an automatic launch dialog.
    @Published public var libraryScanWarnings: [String] = []
    @Published public var gameForSettingsSheet: PortedGame? = nil
    /// The Steam game whose Options are open (`SteamOptionsView`); never open with `gameForSettingsSheet`.
    @Published var steamOptionsGame: CatalogGame? = nil
    /// Any game's Options are open: the screens underneath stop reading input.
    var isGameOptionsOpen: Bool { gameForSettingsSheet != nil || steamOptionsGame != nil }
    /// The game whose Options are open, for the panels' own key monitors.
    var optionsGameID: UUID? { gameForSettingsSheet?.id ?? steamOptionsGame?.id }
    /// Where the open Game options came from; decides its rows (Move is Spotlight-only).
    @Published public var gameOptionsOrigin: GameOptionsOrigin = .collection
    /// Game options opens straight on its Mods panel (the Details page's Mods band).
    @Published public var gameOptionsOpensMods = false
    /// The running game whose Close Game confirmation is open. The shell draws the dialog.
    @Published public var gameToClose: PortedGame? = nil
    @Published var closeGameFocus: SeleneConfirmButton = .cancel
    @Published public var pendingRuntimeConfig = GameRuntimeConfig()
    @Published public var importedApps: [ImportedApp] = []
    @Published public var environmentStatus: EnvironmentStatus? = nil
    @Published public var compatibilityReport: CompatibilityReport? = nil
    @Published public var keySummary: KeySummary? = nil
    @Published public var currentEngineCommit: String? = nil
    @Published public var upstreamState: UpstreamCheckState = .idle
    @Published public var storeMetadata: [UUID: NintendoStoreMetadata] = [:]
    @Published public var storeMetadataLoading: Set<UUID> = []
    @Published public var storeMetadataErrors: [UUID: String] = [:]
    @Published public var storageSnapshot: StorageSnapshot? = nil
    public var storageUsage: StorageUsage? { storageSnapshot?.total }
    @Published public var isCalculatingStorage: Bool = false
    @Published public private(set) var isCleaningStorage = false
    @Published public private(set) var storageCleanupMessage: String?
    private var storageRefreshRequested = false

    public var canCleanStorage: Bool { !isBuilding && !isCleaningStorage && !isCalculatingStorage && !isUpdatingApp }
    @Published public var showSetupCheck: Bool = false
    /// The Setup check's state and installs; lives with the app so an install survives closing the screen.
    lazy var setupModel = SetupCheckModel(viewModel: self)
    @Published public private(set) var firstRunSetup = FirstRunSetup() {
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
    public var setupCompleted: Bool { firstRunSetup.isCompleted }
    @Published public var lastError: String? = nil
    @Published public var alertMessage: String? = nil
    @Published public var buildLogURL: URL? = nil
    @Published public var currentBuildGameID: UUID? = nil
    @Published public var lastBuildGameID: UUID? = nil
    @Published public var allowUntestedToolchain: Bool = false {
        didSet {
            AppData.preferences.set(allowUntestedToolchain, forKey: StorageKeys.allowUntestedToolchain)
        }
    }
    /// The newest nxnative the player chose in Settings → Setup and engine; nil while the tested engine is in use.
    @Published public internal(set) var newestEngineChoice: NewestEngineChoice? = nil {
        didSet {
            if let choice = newestEngineChoice, let data = try? JSONEncoder().encode(choice) {
                AppData.preferences.set(data, forKey: StorageKeys.newestEngineChoice)
            } else {
                AppData.preferences.removeObject(forKey: StorageKeys.newestEngineChoice)
            }
        }
    }
    /// Whether upstream main can be used here, read from its lock after an Upstream check.
    @Published public internal(set) var newestEngineReadiness: NewestEngineReadiness? = nil
    @Published public internal(set) var isSwitchingEngine = false
    /// Why the last switch did not happen, shown calmly in the Newest engine row.
    @Published public internal(set) var newestEngineProblem: String? = nil
    
    
    // MARK: - Build State
    /// What Add Game and its Porting step show of a build; the home reads only the three values here.
    public private(set) lazy var porting = PortingModel(app: self)
    @Published public var isBuilding: Bool = false
    /// The running (or just finished) porting folded into one overall fraction for the home.
    @Published public var portingProgress: PortingProgress? = nil
    /// The game ported last in this session leads Spotlight's row until quit.
    @Published public var frontGameID: UUID? = nil
    /// The Steam games seen downloading this session lead the row after it, until quit.
    @Published public private(set) var sessionDownloads = SessionDownloads()
    /// Spotlight's Delete on a failed porting asks first.
    @Published public var gameToRemove: PortedGame? = nil
    @Published var removeGameFocus: SeleneConfirmButton = .cancel
    @Published public var logs: [LogEntry] = []
    /// The existing Selene dialog offers retrying the ready app, or closing it.
    @Published var gameWithInstallFailure: PortedGame? = nil
    @Published var installFailureFocus: SeleneConfirmButton = .cancel

    var canRetryReadyInstall: Bool {
        porting.buildState == .failed && porting.portingFailureReason == nil
            && (libraryGames.contains { $0.id == lastBuildGameID && $0.pendingInstall != nil }
                || catalogBuildRecoveries.values.contains { $0.id == lastBuildGameID && $0.pendingInstall != nil })
    }
    @Published public var iconAppearanceMode: AppIconAppearanceMode = .auto {
        didSet {
            AppData.preferences.set(iconAppearanceMode.rawValue, forKey: StorageKeys.savedIconAppearanceMode)
            updateDockIcon()
        }
    }
    
    // MARK: - Navigation
    @Published public var librarySelection = LibrarySelectionState()
    /// Spotlight's row selection and focus; lives here so it survives Details and back.
    @Published public var spotlight = SpotlightState()
    public var router: AppRouter?
    /// GameTDB box covers for Collection and More like this.
    public lazy var boxArt = BoxArtService(artwork: ArtworkStore(),
                                           index: GameTDBStore(directory: core.appendingPathComponent("metadata")))
    /// Bumps when a new GameTDB index arrives, so covers that found nothing look again.
    @Published public private(set) var boxArtIndexVersion = 0
    @Published public var launchingGameId: UUID? = nil
    /// The launch screen: shown on Play, `isReady` once the game's window is up (or the probe gave up).
    @Published var launchOverlay: LaunchOverlayState? = nil {
        didSet {
            SoundEffectService.shared.isQuieted =
                launchOverlay != nil && (settingsStore?.settings.quietLaunch ?? true)
        }
    }
    private var launchProbeTask: Task<Void, Never>?

    public var playSessionStore: PlaySessionStore?
    public var settingsStore: AppSettingsStore?
    
    public let availableLanguages: [(code: String, label: String)] = [
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
    
    /// The Python and PATH every engine process runs with (bundled runtime, else the venv).
    public var engineToolchain: EngineToolchain {
        .resolve(runtime: .locate(), repo: URL(fileURLWithPath: nxnativePath))
    }

    public let pinnedEngineCommit = "461a5f9f95fc9fc40a690bb2a82eb23f1f03bdca"
    let core = AppData.supportRoot
    let catalogRepository: CatalogRepository
    lazy var keyStore = KeyStore(directory: core.appendingPathComponent("keys"))
    /// Sizes of built apps are remembered between launches, so a scan walks only new or rebuilt apps.
    private lazy var importService = ImportService(sizeCache: AppSizeCache(file: core.appendingPathComponent("app-sizes.json")))
    private let launchService = LaunchService()
    private lazy var upstreamChecker = UpstreamChecker()
    private lazy var storeMetadataService = NintendoStoreMetadataService()
    let developmentOperations = DevelopmentOperationStore()
    private var metadataLocaleGeneration = UUID()
    private var localizedMetadataRefresh: Task<Void, Never>?
    private let upstreamCacheKey = "NXLibrary_UpstreamStatus"
    private lazy var storageManager = StorageManager()
    let sourceCatalog = SourceCatalog()
    lazy var workspaceManager = WorkspaceManager(root: core.appendingPathComponent("workspaces"))
    private var libraryRescanRequested = false
    var environmentCheckGeneration = UUID()
    
    public init(settingsStore: AppSettingsStore, catalog: CatalogDocument, repository: CatalogRepository) {
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
        if AppData.preferences.object(forKey: StorageKeys.allowUntestedToolchain) != nil {
            self.allowUntestedToolchain = AppData.preferences.bool(forKey: StorageKeys.allowUntestedToolchain)
        }
        if let data = AppData.preferences.data(forKey: StorageKeys.newestEngineChoice) {
            self.newestEngineChoice = try? JSONDecoder().decode(NewestEngineChoice.self, from: data)
        }
        
        restoreBuildInputs(automatic: true)
        if !AppData.profile.isDevelopment && (startup.checkEngineAtLaunch || !didCompleteSetup) { refreshCompatibility() }
        
        // Keep Game files as a picker preference, not an active Add game draft.
        // Assigning selectedGameFolder scans it; launch refresh only concerns installed apps.
        
        recoverSavesAtStartup()
        if !setupCompleted && firstRunSetup.page == .games { prepareInitialGameAppsFolder() }
        if startup.refreshLibraryAtLaunch || (!setupCompleted && firstRunSetup.page == .games) { scanLibrary(using: catalog) }
        if let data = AppData.preferences.data(forKey: upstreamCacheKey),
           let cached = try? JSONDecoder().decode(UpstreamStatus.self, from: data),
           cached.baseCommit == pinnedEngineCommit {
            self.upstreamState = .loaded(cached)
        }
        updateDockIcon()
        // Register notification-click routing at launch without asking for permission.
        _ = NotificationService.shared

        let held = PendingInstaller.keptFolders(libraryGames)
        let staging = AppData.profile.automaticStagingFolders(
            appFolders: [gameAppsFolder] + libraryGames.map { $0.url.deletingLastPathComponent() })
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.sweepStaleBuildTemp(in: staging, keeping: held)
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
    public func updateDockIcon() {
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
    
    // MARK: - Environment Detection
    public func detectEnvironment(customRyujinxDir: String? = nil) {
        guard !isBuilding, !isUpdatingApp else { return }
        restoreBuildInputs(customRyujinxDir: customRyujinxDir)
        refreshCompatibility()
    }

    private func restoreBuildInputs(customRyujinxDir: String? = nil, automatic: Bool = false) {
        let nxResult = SystemDetector.shared.detectNxnativeDirectory(
            saved: AppData.preferences.string(forKey: StorageKeys.savedEngineFolder))
        self.nxnativePath = nxResult.path
        self.isNxnativeValid = nxResult.isValid
        if !automatic || !AppData.profile.isDevelopment { ensureKeysImported(customRyujinxDir: customRyujinxDir) }
    }

    /// With launch checks off, inspecting a build screen performs the check on demand.
    public func prepareBuildEnvironmentIfNeeded() {
        if environmentStatus == nil, !isCheckingEnvironment { detectEnvironment() }
    }

    @Published public internal(set) var isCheckingEnvironment = false

    private func ensureKeysImported(customRyujinxDir: String? = nil) {
        let fm = FileManager.default
        if fm.fileExists(atPath: keyStore.keyURL.path) {
            do {
                let summary = try keyStore.validate(at: keyStore.keyURL)
                keySummary = summary
                isProdKeysValid = summary.hasHeaderKey
                prodKeysPath = keyStore.keyURL.path
                prodKeysSource = AppIdentity.name
            } catch {
                keySummary = nil
                isProdKeysValid = false
                prodKeysSource = "Invalid stored copy"
                logs.append(LogEntry(level: .error,
                                     message: L10n.format("Stored prod.keys is invalid: %@", [String(describing: (error.localizedDescription))])))
            }
            return
        }
        let saved = AppData.preferences.string(forKey: StorageKeys.savedProdKeysPath)
        let detected = SystemDetector.shared.detectProdKeys(additionalSearchDir: customRyujinxDir)
        let candidate = [saved, detected?.path].compactMap { $0 }.first {
            !$0.isEmpty && fm.fileExists(atPath: $0)
        }
        guard let candidate else {
            keySummary = nil
            isProdKeysValid = false
            prodKeysSource = "Not Found"
            prodKeysPath = ""
            return
        }
        importKeys(from: URL(fileURLWithPath: candidate))
    }

    public func importKeys(from url: URL) {
        guard !isBuilding, !isUpdatingApp else {
            showSettingsNotice(title: L10n.text("Porting in progress"), message: L10n.text("Change keys after the porting finishes."))
            return
        }
        do {
            let summary = try keyStore.importKey(from: url)
            keySummary = summary
            isProdKeysValid = summary.hasHeaderKey
            prodKeysPath = keyStore.keyURL.path
            prodKeysSource = "Imported once"
            porting.refreshKeyCheck()
            if let folder = porting.selectedGameFolder { porting.scanGameFolder(folder) }
            lastError = nil
            logs.append(LogEntry(
                level: .success,
                message: L10n.format("prod.keys imported: header key present, %@ application key generations.", [String(describing: (summary.applicationKeyGenerations.count))])
            ))
        } catch {
            keySummary = try? keyStore.validate(at: keyStore.keyURL)
            isProdKeysValid = keySummary?.hasHeaderKey == true
            prodKeysPath = isProdKeysValid ? keyStore.keyURL.path : ""
            lastError = error.localizedDescription
            showSettingsNotice(title: L10n.text("Keys not changed"), message: isProdKeysValid
                ? L10n.text("The key file could not be imported. Your previous copy is kept.")
                : L10n.text("The key file could not be imported. Choose a valid prod.keys file."))
            logs.append(LogEntry(level: .error,
                                 message: L10n.format("Could not import prod.keys: %@", [String(describing: (error.localizedDescription))])))
        }
    }

    public func refreshCompatibility() {
        guard !isBuilding, !isUpdatingApp else { return }
        let generation = UUID()
        environmentCheckGeneration = generation
        guard isNxnativeValid, !nxnativePath.isEmpty else {
            compatibilityReport = nil
            environmentStatus = nil
            isCheckingEnvironment = false
            return
        }
        isCheckingEnvironment = true
        environmentStatus = nil
        compatibilityReport = nil
        let repo = URL(fileURLWithPath: nxnativePath)
        let toolchain = engineToolchain
        let developerDir = resolvedDeveloperDir()
        let expected = activeEngineCommit
        let pinned = pinnedEngineCommit
        let choice = newestEngineChoice
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let environment = NXNativeEnvironment(repoURL: repo, toolchain: toolchain,
                                                  developerDir: developerDir)
            let status = environment.inspect()
            let includedInPin = choice.flatMap { NewestEngineSwitcher(repo: repo).isIncluded($0.commit, in: pinned) }
            let checker = CompatibilityChecker(repoURL: repo, toolchain: toolchain,
                                               developerDir: developerDir)
            let report = try? checker.check(expectedEngineCommit: expected)
            let currentCommit = report?.checks.first(where: { $0.id == "commit" })?.detail
                .components(separatedBy: ", expected").first?
                .replacingOccurrences(of: "current ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard let self, self.environmentCheckGeneration == generation,
                      self.nxnativePath == repo.path else { return }
                self.isCheckingEnvironment = false
                self.environmentStatus = status
                self.compatibilityReport = report
                self.currentEngineCommit = (currentCommit?.isEmpty == false) ? currentCommit : nil
                if let choice, !NewestEngine.keeps(choice, head: self.currentEngineCommit, pinned: pinned,
                                                    includedInPin: includedInPin) {
                    // The checkout moved (Setup, Back to tested, by hand) or an NX Library update tested this
                    // commit: the tested engine is in charge again.
                    self.forgetNewestEngine()
                    self.refreshCompatibility()
                    return
                }
                if let report, !report.ok {
                    let blocked = report.checks.filter { $0.status == .block }
                        .map { "\($0.title): \($0.detail)" }.joined(separator: " | ")
                    self.logs.append(LogEntry(level: .warning, message: L10n.format("Toolchain gate: %@", [String(describing: (blocked))])))
                }
            }
        }
    }

    public func checkUpstreamChangelog() {
        if case .checking = upstreamState { return }
        // Always against the tested pin, so the newest engine stays measurable from the engine NX Library tested.
        let base = pinnedEngineCommit
        upstreamState = .checking
        let checker = upstreamChecker
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let status = try await checker.check(from: base)
                self.upstreamState = .loaded(status)
                if let data = try? JSONEncoder().encode(status) {
                    AppData.preferences.set(data, forKey: self.upstreamCacheKey)
                }
                self.checkNewestEngineReadiness(status)
            } catch {
                self.upstreamState = .failed(Self.upstreamErrorMessage(error))
            }
        }
    }

    public func openUpstreamCompare() {
        guard case .loaded(let status) = upstreamState else { return }
        NSWorkspace.shared.open(status.compareURL)
    }

    public func loadStoreMetadata(for game: PortedGame) {
        Task { @MainActor [weak self] in await self?.fetchStoreMetadata(for: game) }
    }

    /// Returns once `game` has metadata in the app language, or the request failed; a request already running for
    /// it is not repeated. A language change while it runs discards the answer. True when the app language's
    /// description is settled (`languageResolved`), false after an outage.
    @discardableResult
    @MainActor private func fetchStoreMetadata(for game: PortedGame) async -> Bool {
        let locale = L10n.context
        let generation = metadataLocaleGeneration
        guard let titleId = game.titleId, !titleId.isEmpty else { return true }
        if storeMetadataLoading.contains(game.id) { return true }
        if let existing = storeMetadata[game.id], storeMetadataService.isFresh(existing, locale: locale) {
            loadFallbackScreenshots(for: game)
            return storeMetadataService.languageResolved(existing, locale: locale)
        }

        storeMetadataLoading.insert(game.id)
        storeMetadataErrors[game.id] = nil
        var resolved = false
        do {
            let metadata = try await storeMetadataService.metadata(for: game, locale: locale)
            guard metadataLocaleGeneration == generation else { return true }
            setStoreMetadata(metadata, for: game)
            resolved = storeMetadataService.languageResolved(metadata, locale: locale)
        } catch {
            guard metadataLocaleGeneration == generation else { return true }
            storeMetadataErrors[game.id] = error.localizedDescription
        }
        storeMetadataLoading.remove(game.id)
        loadFallbackScreenshots(for: game)
        return resolved
    }

    /// A language change only resets presentation metadata, never the library, personal picks or game settings.
    public func refreshLocalizedMetadata() {
        metadataLocaleGeneration = UUID()
        let generation = metadataLocaleGeneration
        localizedMetadataRefresh?.cancel()
        storeMetadataErrors.removeAll()
        storeMetadataLoading.removeAll()
        let games = libraryGames
        let locale = L10n.context
        let service = storeMetadataService
        // Keep a visible description while another language loads. Disk reads do not block the UI.
        localizedMetadataRefresh = Task { @MainActor [weak self] in
            let entries = await Task.detached(priority: .userInitiated) {
                games.compactMap { game -> (PortedGame, NintendoStoreMetadata)? in
                    guard let titleID = game.titleId,
                          let cached = service.cachedForDisplay(for: titleID, locale: locale) else { return nil }
                    return (game, cached)
                }
            }.value
            guard let self, !Task.isCancelled, self.metadataLocaleGeneration == generation else { return }
            for (game, metadata) in entries { self.setStoreMetadata(metadata, for: game) }
            // Every game gets the new language without being opened, the focused one first.
            let focused = self.currentFocusedGame
            self.languageFetchQueue = []
            self.languageFetchWaiting = []
            self.languageFetchRounds = 0
            self.languageFetchResume?.cancel()
            self.queueLanguageFetch((focused.map { [$0] } ?? []) + games.filter { $0.id != focused?.id })
        }
    }

    /// Games still to bring to the app language in the background, asked one request at a time.
    private var languageFetchQueue: [PortedGame] = []
    /// Games whose request met an outage; asked again when the connection returns or after `languageFetchPause`.
    private var languageFetchWaiting: [PortedGame] = []
    private var languageFetchTask: Task<Void, Never>?
    private var languageFetchResume: Task<Void, Never>?
    /// Timed retries since the last language change or reconnection: a game that always fails is not asked forever.
    private var languageFetchRounds = 0
    static let languageFetchRoundLimit = 3
    /// Three outages in a row mean the provider or the network is down: the pass stops instead of asking every game.
    static let languageFetchFailureLimit = 3
    static let languageFetchPause: UInt64 = 300_000_000_000
    private lazy var connectivity = ConnectivityWatcher { [weak self] in self?.connectionReturned() }

    /// Adds `games` to the background queue; one loop drains it and always asks in the current app language.
    private func queueLanguageFetch(_ games: [PortedGame]) {
        for game in games where !languageFetchQueue.contains(where: { $0.id == game.id }) { languageFetchQueue.append(game) }
        guard languageFetchTask == nil, !languageFetchQueue.isEmpty else { return }
        connectivity.start()
        languageFetchTask = Task { @MainActor [weak self] in
            var outages = 0
            while let self, !self.languageFetchQueue.isEmpty {
                let game = self.languageFetchQueue.removeFirst()
                if await self.fetchStoreMetadata(for: game) { outages = 0; continue }
                if !self.languageFetchWaiting.contains(where: { $0.id == game.id }) { self.languageFetchWaiting.append(game) }
                outages += 1
                if outages >= Self.languageFetchFailureLimit {
                    self.languageFetchWaiting += self.languageFetchQueue
                    self.languageFetchQueue = []
                }
            }
            guard let self else { return }
            self.languageFetchTask = nil
            if !self.languageFetchWaiting.isEmpty, self.languageFetchRounds < Self.languageFetchRoundLimit {
                self.languageFetchRounds += 1
                self.scheduleLanguageResume()
            }
        }
    }

    /// Asks the waiting games again after a pause, for a provider that was busy while the network stayed up.
    private func scheduleLanguageResume() {
        languageFetchResume?.cancel()
        languageFetchResume = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: Self.languageFetchPause) } catch { return }
            self?.resumeLanguageFetch()
        }
    }

    private func connectionReturned() {
        guard !languageFetchWaiting.isEmpty else { return }
        storeMetadataService.forgetDescriptionRetries()
        languageFetchRounds = 0
        resumeLanguageFetch()
    }

    private func resumeLanguageFetch() {
        languageFetchResume?.cancel()
        languageFetchResume = nil
        let waiting = languageFetchWaiting
        languageFetchWaiting = []
        queueLanguageFetch(waiting)
    }

    /// Fills metadata from the disk cache without starting a network request, in
    /// another language when the app's is not cached yet (`cachedForDisplay`).
    /// The library uses this so a previously viewed game paints its title,
    /// description and hero immediately when selected.
    /// A game shown in another language (the language changed while the app was closed) is
    /// queued for the app's language in the background.
    public func preloadCachedStoreMetadata() {
        let locale = L10n.context
        var otherLanguage: [PortedGame] = []
        for game in libraryGames {
            guard storeMetadata[game.id] == nil,
                  let titleId = game.titleId,
                  !titleId.isEmpty,
                  let metadata = storeMetadataService.cachedForDisplay(for: titleId, locale: locale) else { continue }
            setStoreMetadata(metadata, for: game)
            if !storeMetadataService.isInLanguage(metadata, locale: locale) { otherLanguage.append(game) }
        }
        queueLanguageFetch(otherLanguage)
    }

    /// The store's metadata as fetched, before the player's choices are laid over it.
    private var storeMetadataOriginals: [UUID: NintendoStoreMetadata] = [:]

    /// Keeps the fetched metadata and shows it with the player's choices (`MetadataPicks`) over it.
    private func setStoreMetadata(_ metadata: NintendoStoreMetadata, for game: PortedGame) {
        storeMetadataOriginals[game.id] = metadata
        let shown = MetadataPicks.shared.applied(to: metadata, titleID: personalizationKey(for: game))
        storeMetadata[game.id] = screenshotFallback.filled(shown)
    }

    private let screenshotFallback = ScreenshotFallbackStore()
    /// Games whose LaunchBox screenshots are being looked up; Details waits before saying it has none.
    @Published public private(set) var screenshotLookups: Set<UUID> = []

    /// A game whose metadata has no screenshots (Title DB has none for Switch 2 games) asks LaunchBox once, when the
    /// game is selected or opened as its metadata is, and keeps the answer for 30 days. A scan never asks.
    public func loadFallbackScreenshots(for game: PortedGame) {
        guard let titleId = game.titleId, !titleId.isEmpty, let metadata = storeMetadata[game.id],
              !storeMetadataLoading.contains(game.id), screenshotFallback.wantsLookup(metadata),
              screenshotLookups.insert(game.id).inserted else { return }
        let names = [game.name, metadata.name].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let store = screenshotFallback
        Task { @MainActor [weak self] in
            let urls = await LaunchBoxArt.screenshots(names: names, switch2: game.isSwitch2)
            guard let self else { return }
            self.screenshotLookups.remove(game.id)
            // Unreachable: asked again next time Details opens.
            guard let urls else { return }
            try? store.save(.init(urls: urls, fetchedAt: Date()), for: titleId)
            if let original = self.storeMetadataOriginals[game.id] { self.setStoreMetadata(original, for: game) }
        }
    }

    /// The metadata as the store gave it: what Automatic means in Change metadata.
    public func storeMetadataAsFetched(for game: PortedGame) -> NintendoStoreMetadata? {
        storeMetadataOriginals[game.id]
    }

    /// Keeps the player's value for a field, or (nil) goes back to the store's.
    public func pickMetadata(_ value: String?, field: MetadataField, for game: PortedGame) {
        let key = personalizationKey(for: game)
        if let value { MetadataPicks.shared.set(value, titleID: key, field: field) }
        else { MetadataPicks.shared.remove(titleID: key, field: field) }
        if let original = storeMetadataOriginals[game.id] { setStoreMetadata(original, for: game) }
    }

    /// Fetches GameTDB's index at launch when it is missing or 30 days old.
    public func refreshBoxArtIndex() {
        let service = boxArt
        Task { @MainActor [weak self] in
            if await service.refreshIndexIfNeeded() { self?.boxArtIndexVersion += 1 }
        }
    }

    public func metadataCacheSize() -> Int64 {
        storeMetadataService.cacheSize() + WikipediaDescriptionService.shared.cacheSize()
    }

    public func clearMetadataCache() {
        storeMetadataService.clearCache()
        WikipediaDescriptionService.shared.clearCache()
        storeMetadata.removeAll()
        storeMetadataOriginals.removeAll()
    }

    public func howLongToBeatURL(for game: PortedGame) -> URL? {
        var components = URLComponents(string: "https://howlongtobeat.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: game.name)]
        return components?.url
    }

    public func nintendoStoreSearchURL(for game: PortedGame) -> URL? {
        var components = URLComponents(string: "https://www.nintendo.com/us/search/")
        components?.fragment = "q=\(game.name)&p=1&cat=gme&sort=df"
        return components?.url
    }

    public func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static func upstreamErrorMessage(_ error: Error) -> String {
        if let checkerError = error as? UpstreamCheckerError {
            return checkerError.localizedDescription
        }
        if let urlError = error as? URLError {
            return "Network error: \(urlError.localizedDescription)"
        }
        return error.localizedDescription
    }

    func resolvedDeveloperDir() -> URL { Self.resolveDeveloperDir() }

    /// Reads no state of the view model, so it can run off the main thread (it runs `xcode-select`).
    static func resolveDeveloperDir() -> URL {
        let fm = FileManager.default
        // An explicit DEVELOPER_DIR always wins.
        if let env = ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
           fm.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        // Respect xcode-select when it points at a full Xcode, not the CLT.
        if let selected = try? SystemCommandRunner().run(
            URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"],
            environment: nil, currentDirectory: nil
        ), selected.status == 0 {
            let path = selected.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.contains(".app/Contents/Developer"), fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Prefer a normal Xcode install over the beta when xcode-select is CLT.
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer",
            "/Applications/Xcode-beta.app/Contents/Developer",
            "/Library/Developer/CommandLineTools",
        ]
        for path in candidates where fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
    }

    public var requiredMetalVersion: String? {
        let lock = URL(fileURLWithPath: nxnativePath)
            .appendingPathComponent("dm/gfx/tools/dmsh_chain.lock")
        guard let text = try? String(contentsOf: lock, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("metal_macosx\t") {
            guard let raw = line.split(separator: "\t").last.map(String.init) else { return nil }
            return MetalVersion.parse(raw) ?? raw
        }
        return nil
    }

    public var installedMetalVersion: String? { environmentStatus?.metalVersion }

    public var canCompleteSetup: Bool {
        isNxnativeValid
            && (isProdKeysValid || engineSourceCapabilities.extractedFolders)
            && environmentStatus?.canBuild == true
    }

    public func advanceSetupToGames() {
        guard showSetupCheck else { return }
        if !setupCompleted { prepareInitialGameAppsFolder() }
        importExistingBuilds()
        firstRunSetup.advance()
    }

    public func returnToSetupRequirements() { firstRunSetup.goBack() }

    /// The Porting card on the first launch's `found` page.
    public func openPortingFromFound() {
        guard showSetupCheck, !setupCompleted else { return }
        firstRunSetup.openPorting()
    }

    /// The Steam switch on `found`; the shell applies it when the first launch finishes.
    public func chooseSteamOnFound(_ on: Bool) { firstRunSetup.chooseSteam(on) }

    /// Back from the requirements to `found`, during the first launch only.
    public func returnToFound() { firstRunSetup.returnToFound() }

    /// Open library on `found`. Ported apps already in the Game apps folder join the library, which
    /// turns the Switch source on; without them it stays off until the player chooses Porting.
    public func finishFromFound(importPorted: Bool) {
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
            logs.append(LogEntry(level: .warning, message: L10n.format("Could not prepare the default Game apps folder: %@", [String(describing: (error.localizedDescription))])))
        }
    }

    public func completeSetup() {
        AppData.preferences.set(gameAppsFolder.path, forKey: StorageKeys.savedLibraryFolder)
        firstRunSetup.finish()
        showSetupCheck = false
        logs.append(LogEntry(level: .success, message: L10n.text("Setup completed.")))
    }

    public func reopenSetup() {
        guard !isBuilding, !isUpdatingApp else { return }
        firstRunSetup.goBack()
        showSetupCheck = true
    }

    /// `kept`: folders of builds that wait for their game to quit (standardized paths).
    private func sweepStaleBuildTemp(in folders: [URL], keeping kept: Set<String>) {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for temp in folders {
            sweepStaleBuildTemp(temp, before: cutoff, keeping: kept)
        }
    }

    private func sweepStaleBuildTemp(_ temp: URL, before cutoff: Date, keeping kept: Set<String>) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: temp, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for item in items {
            let date = (try? item.resourceValues(
                forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date.distantPast
            if date < cutoff, !kept.contains(item.standardizedFileURL.path) {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    public func refreshStorageUsage() {
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

    public func deleteCaches(for selected: PortedGame? = nil) {
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

    public func deleteLogs() {
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
    public func handleDroppedURLs(_ urls: [URL]) {
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
    public func refreshLibrary() {
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

    public func loadLibrary() {
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
                self.importedApps = selected
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
                    self.reconcileAppIcons()
                } catch { self.reportCatalogFailure(error) }
                self.libraryScanWarnings = scanWarnings
                for warning in scanWarnings { self.logs.append(LogEntry(level: .warning, message: warning)) }
            }
        }
    }

    public func importExistingBuilds() {
        do { applyCatalog(try catalogRepository.configureSource(.nxnative, enabled: true, root: nil)); loadLibrary() }
        catch { reportCatalogFailure(error) }
    }

    /// Attach source files to an already-imported app. The app URL, version and
    /// build metadata stay intact; the library entry is merged, never duplicated.
    public func locateSources(for game: PortedGame) {
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
        let repo = URL(fileURLWithPath: nxnativePath)
        let toolchain = engineToolchain
        let keys = isProdKeysValid ? keyStore.keyURL : nil
        let developer = resolvedDeveloperDir()
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
                        message: L10n.format("Sources attached to %@; rebuild is now available if the toolchain gate allows it.", [String(describing: (game.name))])))
                } catch {
                    self.alertMessage = error.localizedDescription
                    self.logs.append(LogEntry(level: .error, message: error.localizedDescription))
                }
            }
        }
    }

    public func selectLibraryFolder() {
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

    public func launchGame(_ game: PortedGame) {
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
        guard !appIconsInFlight.contains(game.id) else {
            waitForAppIconBeforeLaunching(game)
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
        let gameSettings = gameSettings(for: game)
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
                                 message: L10n.format("Could not write the runtime environment: %@", [String(describing: (error.localizedDescription))])))
            return
        }

        if let choice = settingsStore?.settings.cloudSaves, let domain = game.effectiveBundleId {
            do {
                try cloudSavesPreferences.applyBeforeLaunch(choice, domain: domain)
            } catch {
                logs.append(LogEntry(level: .warning, message: L10n.format("Cloud saves: %@", [String(describing: (error.localizedDescription))])))
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
                    self.logs.append(LogEntry(level: .success, message: L10n.format("Launched game: %@", [String(describing: (game.name))])))
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
                                              message: L10n.format("%@ showed no window within 60 s; launch screen closed.", [String(describing: (game.name))])))
                }
                self.launchOverlay?.isReady = true
            }
        }
    }

    /// Called by the launch screen after its fade out.
    public func dismissLaunchOverlay() {
        launchProbeTask?.cancel()
        launchProbeTask = nil
        launchOverlay = nil
    }

    /// Opens Game options for a game, remembering the screen it was opened from.
    public func openGameOptions(_ game: PortedGame, from origin: GameOptionsOrigin, opensMods: Bool = false) {
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
    public func toggleFavorite(_ game: PortedGame) {
        updateStoredGame(game) { $0.isFavorite.toggle() }
    }

    /// Flips the hidden flag and saves the library. Hidden games leave Spotlight,
    /// Collection and Surprise me; the screens reconcile their selection on the change.
    public var cloudSavesPreferences = CloudSavesPreferences()

    /// Gives the whole library one cloud saves folder (or none): written into every
    /// game's preferences now, and again before each start (see `launchGame`).
    public func setCloudSaves(_ choice: CloudSaves) {
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
        logs.append(LogEntry(level: .info, message: L10n.format("Cloud saves: %@", [String(describing: (choice.folderURL()?.path ?? "off"))])))
    }

    /// Picks a folder for cloud saves; Cancel keeps the current choice.
    public func chooseCloudSavesFolder() {
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

    public func toggleHidden(_ game: PortedGame) {
        updateStoredGame(game) { $0.isHidden.toggle() }
    }

    /// Applies one change to the stored game and saves the library, the same way for every flag.
    private func updateStoredGame(_ game: PortedGame, _ change: (inout PortedGame) -> Void) {
        do { applyCatalog(try catalogRepository.updateNXNative(id: game.id, change)) }
        catch { reportCatalogFailure(error) }
    }

    /// Opens the Close Game confirmation for a running game (Spotlight and Details).
    public func askCloseGame(_ game: PortedGame) {
        closeGameFocus = .cancel
        gameToClose = game
    }

    public func dismissCloseGame() {
        gameToClose = nil
        closeGameFocus = .cancel
    }

    /// Spotlight's Delete on a failed porting: the same confirmation as Game options' removal.
    public func askRemoveGame(_ game: PortedGame) {
        removeGameFocus = .cancel
        gameToRemove = game
    }

    public func dismissRemoveGame() {
        gameToRemove = nil
        removeGameFocus = .cancel
    }

    public func confirmRemoveGame() {
        guard let game = gameToRemove else { return }
        dismissRemoveGame()
        deletePortedGame(game)
    }

    private var didSeedFinishSeconds = false

    /// What the final stages took in the last successful porting on this Mac, for the ETA.
    /// Seeded once from the newest porting log when nothing is stored yet.
    public var lastPortingFinishSeconds: Double? {
        get {
            let stored = AppData.preferences.double(forKey: StorageKeys.lastPortingFinishSeconds)
            if stored > 0 { return stored }
            guard !didSeedFinishSeconds else { return nil }
            didSeedFinishSeconds = true
            guard let seeded = Self.finishSecondsFromNewestLog(in: core.appendingPathComponent("logs")) else {
                return nil
            }
            AppData.preferences.set(seeded, forKey: StorageKeys.lastPortingFinishSeconds)
            return seeded
        }
        set { AppData.preferences.set(newValue ?? 0, forKey: StorageKeys.lastPortingFinishSeconds) }
    }

    private static func finishSecondsFromNewestLog(in directory: URL) -> Double? {
        let fm = FileManager.default
        let logs = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension == "log" } ?? []
        let newest = logs.max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        guard let newest, let text = try? String(contentsOf: newest, encoding: .utf8) else { return nil }
        return PortingProgress.finishingSeconds(inLog: text)
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

    public func loadRuntimeConfig(for game: PortedGame) -> GameRuntimeConfig {
        gameSettings(for: game)?.runtimeConfig() ?? GameRuntimeConfig.load(for: game)
    }

    /// The game's saved-choices store, or nil for a build from before saved choices (env.txt).
    public func gameSettings(for game: PortedGame) -> NXNativeGameSettings? {
        NXNativeGameSettings.forGame(game)
    }

    public func settingsSnapshot(for game: PortedGame) -> GameSettingsSnapshot? {
        gameSettings(for: game)?.snapshot()
    }

    /// One saved choice; false (with a notice) when it could not be kept.
    @discardableResult public func setGameSetting(_ env: String, to value: String, for game: PortedGame) -> Bool {
        guard let settings = gameSettings(for: game) else { return false }
        do {
            try settings.set(env, to: value)
            return true
        } catch {
            settingsNotSaved(game, error)
            return false
        }
    }

    /// Use new game defaults: every setting to the build's default, then NX Library's new-game defaults.
    public func restoreGameDefaults(for game: PortedGame) {
        guard let settings = gameSettings(for: game) else { return }
        do {
            try settings.resetAll()
            let base = settings.runtimeConfig()
            try settings.apply(settingsStore?.settings.gameDefaults ?? GameRuntimeConfig(), changedFrom: base)
        } catch {
            settingsNotSaved(game, error)
        }
    }

    private func settingsNotSaved(_ game: PortedGame, _ error: Error) {
        logs.append(LogEntry(level: .error, message: L10n.format("Could not save settings for %@: %@", [String(describing: (game.name)), String(describing: (error.localizedDescription))])))
        showSettingsNotice(title: L10n.text("Options not saved"), message: L10n.text("Your game options could not be saved. Try again."))
    }

    public func supportsSetting(_ env: String, for game: PortedGame) -> Bool {
        LauncherSettingsReader.supports(env, for: game.url)
    }

    public func launcherSettings(for game: PortedGame) -> LauncherSettingsFile? {
        LauncherSettingsReader.load(for: game.url)
    }

    @discardableResult public func saveRuntimeConfig(_ config: GameRuntimeConfig, for game: PortedGame) -> Bool {
        do {
            try config.save(for: game)
            logs.append(LogEntry(level: .success, message: L10n.format("Saved settings for %@", [String(describing: (game.name))])))
            return true
        } catch {
            logs.append(LogEntry(level: .error, message: L10n.format("Could not save settings for %@: %@", [String(describing: (game.name)), String(describing: (error.localizedDescription))])))
            showSettingsNotice(title: L10n.text("Options not saved"), message: L10n.text("Your game options could not be saved. Try again.")) { [weak self] in
                self?.saveRuntimeConfig(config, for: game)
            }
            return false
        }
    }

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// A human-readable summary for the destructive source-removal confirmation.
    public func sourceRemovalSummary(for game: PortedGame) -> String {
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

    public func removeSources(for game: PortedGame) {
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
                                 message: L10n.format("%@ The installed app and saves were kept.", [String(describing: (removed))])))
            alertMessage = L10n.format("%@ The installed app and saves were kept. Rebuilds stay disabled until you attach the sources again.", [removed])
        } else {
            let detail = failures.joined(separator: "; ")
            logs.append(LogEntry(level: .warning,
                                 message: L10n.format("%@ Some items were kept: %@", [String(describing: (removed)), String(describing: (detail))])))
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

    public func deletePortedGame(_ game: PortedGame) {
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
                    message: L10n.format("Game app deleted: %@%@", [String(describing: (game.name)), String(describing: (removedWorkspace ? "; staged workspace removed" : ""))])))
            } else {
                logs.append(LogEntry(level: .warning,
                    message: L10n.format("Removed %@ from the library; its source folders were left in place.", [String(describing: (game.name))])))
            }
        } catch {
            let message = L10n.format("Failed to delete game: %@", [String(describing: (error.localizedDescription))])
            alertMessage = message
            logs.append(LogEntry(level: .error, message: message))
        }
    }
    
    
    // MARK: - File Pickers
    public func selectNxnativeFolder() {
        guard !isBuilding, !isUpdatingApp else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select nxnative Folder"
        panel.message = "Choose the directory containing the nxnative scripts and tools."
        
        if panel.runModal() == .OK, let url = panel.url {
            guard EngineLocation.isEngine(url) else {
                alertMessage = "\(url.path) is not an nxnative checkout: it has no scripts/build_ipa_from_nsp.py and dm folder."
                SoundEffectService.shared.play(.error)
                return
            }
            // Remembered, so launch and every check use it; ~/nxnative itself needs nothing stored.
            if let saved = EngineLocation.savedValue(for: url, home: SystemDetector.shared.resolveRootDirectory()) {
                AppData.preferences.set(saved, forKey: StorageKeys.savedEngineFolder)
            } else {
                AppData.preferences.removeObject(forKey: StorageKeys.savedEngineFolder)
            }
            self.nxnativePath = url.path
            self.isNxnativeValid = true
            refreshCompatibility()
        }
    }
    
    
    public func selectProdKeysFile() {
        guard !isBuilding, !isUpdatingApp else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.prompt = "Select prod.keys"
        panel.message = "Choose your Nintendo Switch prod.keys file."
        
        if panel.runModal() == .OK, let url = panel.url {
            importKeys(from: url)
        }
    }
    
    public func selectRyujinxFolder() {
        guard !isBuilding, !isUpdatingApp else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Ryujinx Folder"
        panel.message = "Select your Ryujinx folder to automatically locate prod.keys."
        
        if panel.runModal() == .OK, let url = panel.url {
            detectEnvironment(customRyujinxDir: url.path)
        }
    }
    
    // MARK: - Build Actions
    public func canBuild(_ game: PortedGame) -> Bool {
        guard !isBuilding,
              !isCleaningStorage,
              !isUpdatingApp,
              (!SourceSelection.requiresKeys(game.sources) || isProdKeysValid),
              supportsSources(game.sources),
              isNxnativeValid,
              environmentStatus?.canBuild == true,
              !game.sources.isEmpty,
              SourceSelection.hasGame(game.sources),
              game.sources.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) }) else {
            return false
        }
        let required = SourceSelection.uniqueSize(game.sources) * 2 + 10_000_000_000
        let parent = finalAppURL(for: game).deletingLastPathComponent()
        guard GameAppDestination.folderProblem(at: parent) == nil else { return false }
        for folder in buildFolders(appFolder: parent, workspace: game.workspacePath) {
            if let free = freeBytes(at: folder), free < required { return false }
        }
        return canPassToolchainGate
    }

    public var canPassToolchainGate: Bool {
        compatibilityReport?.ok == true || allowUntestedToolchain
    }

    /// A profile in `dm/games/<title ID>` is the engine's verified support for
    /// a title. Without one the engine builds from a provisional profile and
    /// may fail in the rewrite or at run time.
    public func hasVerifiedEngineProfile(for game: PortedGame) -> Bool {
        hasVerifiedEngineProfile(titleId: game.titleId)
    }

    public func hasVerifiedEngineProfile(titleId: String?) -> Bool {
        guard let titleId, !titleId.isEmpty else { return true }
        guard !nxnativePath.isEmpty else { return true }
        var isDirectory: ObjCBool = false
        let path = URL(fileURLWithPath: nxnativePath)
            .appendingPathComponent("dm/games/\(titleId.uppercased())").path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public func logURL(for game: PortedGame) -> URL? {
        if let path = game.lastBuild?.logPath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        guard let titleId = game.titleId, !titleId.isEmpty else { return nil }
        return launchService.logURL(for: titleId)
    }

    public func revealLog(for game: PortedGame) {
        guard let url = logURL(for: game) else {
            logs.append(LogEntry(level: .warning, message: L10n.format("No log path is known for %@.", [String(describing: (game.name))])))
            return
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
            logs.append(LogEntry(level: .info,
                                 message: L10n.format("No log yet for %@; opened the log folder.", [String(describing: (game.name))])))
        }
    }

    func finalAppURL(for game: PortedGame) -> URL {
        GameAppDestination.url(for: game, in: gameAppsFolder)
    }


}
