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
    /// The last app icon change per game, for Change artwork's status line.
    @Published var appIconProgress: [UUID: AppIconProgress] = [:]
    let saveGate = SaveOperationGate()
    let saveQueue = DispatchQueue(label: "local.nxlibrary.saves", qos: .userInitiated)
    @Published var settingsNotice: SettingsNotice?
    @Published var settingsNoticeFocus = 0
    /// A SteamGridDB API key is saved (Settings → Look → SteamGridDB), so Change artwork searches it.
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
                UserDefaults.standard.set(prodKeysPath, forKey: StorageKeys.savedProdKeysPath)
            }
        }
    }
    @Published public var prodKeysSource: String = ""
    @Published public var isProdKeysValid: Bool = false
    
    // MARK: - Game Selection
    @Published public var selectedGameFolder: URL? {
        didSet {
            if let folder = selectedGameFolder {
                if !keepsRememberedGameFolder {
                    UserDefaults.standard.set(folder.path, forKey: StorageKeys.savedGameFolder)
                }
                if !restoringGameFolder {
                    selectedPackageURLs = nil
                    scanGameFolder(folder)
                }
            } else {
                if !keepsRememberedGameFolder {
                    UserDefaults.standard.removeObject(forKey: StorageKeys.savedGameFolder)
                }
                scanGeneration = UUID()
                selectedPackageURLs = nil
                detectedGames = []
                selectedGame = nil
                selectedSourceIDs = []
                scanError = nil
                isScanningGameFolder = false
            }
        }
    }
    private var keepsRememberedGameFolder = false
    private var restoringGameFolder = false
    /// Explicit file picks must not silently include other packages in their parent folder.
    private var selectedPackageURLs: [URL]?
    /// The global source-folder preference is independent of the current Add Game draft.
    public var gameFilesFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: StorageKeys.savedGameFolder),
              !path.isEmpty, path != "/" else { return nil }
        return URL(fileURLWithPath: path)
    }
    @Published public var detectedGames: [SelectableGame] = []
    @Published public var selectedGame: SelectableGame? = nil {
        didSet {
            if let game = selectedGame {
                self.appName = selectedLibraryGame?.name ?? game.name
                self.bundleId = selectedLibraryGame?.bundleId ?? ""
                resetSourceSelection(for: game)
            } else {
                selectedSourceIDs = []
                appName = ""
                bundleId = ""
            }
            pendingRuntimeConfig = selectedLibraryGame.map(loadRuntimeConfig) ?? lastAddGameDefaults
        }
    }
    var selectedLibraryGame: PortedGame? {
        guard let titleID = selectedGame?.titleId else { return nil }
        return libraryGames.first { $0.titleId?.caseInsensitiveCompare(titleID) == .orderedSame }
    }
    @Published public var selectedSourceIDs: Set<UUID> = [] {
        didSet { refreshKeyCheck() }
    }
    /// The imported keys against the selected sources (`refreshKeyCheck`); nil while it runs.
    @Published public var keyCheck: KeyCheck.Outcome? = nil
    /// What `keyCheck` was computed for; a result for an older token is dropped.
    var keyCheckToken: String? = nil
    /// The last porting's command line, for Copy diagnostics (its environment is never kept).
    var lastPortingCommand: [String] = []
    /// Set by a failed porting's notification: the next Add game opens on that failure.
    var reviewsFailureOnAddGame = false
    /// The update dialog is up (set by the shell); screens leave input to it.
    var isUpdateOfferOpen = false
    @Published public var isScanningGameFolder: Bool = false
    @Published public var scanError: String? = nil
    
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

    public var availableDiskBytes: Int64? {
        freeBytes(at: selectedGameFolder
            ?? URL(fileURLWithPath: defaultInstallPath.isEmpty
                ? NSHomeDirectory() : defaultInstallPath))
    }

    var gameAppsFolder: URL {
        libraryFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    }

    /// Review and the first-build space check use the same destination policy as the installer.
    var selectedBuildAppURL: URL {
        let customName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = customName.isEmpty ? selectedGame?.name ?? "Game" : customName
        if var existing = selectedLibraryGame {
            existing.name = name
            return finalAppURL(for: existing)
        }
        return GameAppDestination.url(name: name, titleId: selectedGame?.titleId, in: gameAppsFolder)
    }

    var buildDestinationProblem: String? {
        GameAppDestination.folderProblem(at: selectedBuildAppURL.deletingLastPathComponent())
    }

    /// The wizard reserves space for both the extracted cache and the temporary
    /// app: the tightest of the folders the build writes to (`BuildScratch`).
    public var availableBuildDiskBytes: Int64? {
        buildFolders(appFolder: selectedBuildAppURL.deletingLastPathComponent(),
                     workspace: selectedLibraryGame?.workspacePath).compactMap(freeBytes(at:)).min()
    }

    /// The folders a build writes to: its workspace (a player's own one beside the sources is kept), its staged app
    /// and the app's folder. They are on the app's drive when it can hold builds.
    func buildFolders(appFolder: URL, workspace: String?) -> [URL] {
        let existing = workspace.map { URL(fileURLWithPath: $0) }
        let scratch = BuildScratch.choose(core: core, appFolder: appFolder, existingWorkspace: existing)
        let own = existing.flatMap { BuildScratch.isManaged($0, core: core) ? nil : $0 }
        return [own ?? scratch.workspaces, scratch.temp, appFolder]
    }
    
    public var selectedSources: [GameFileItem] {
        guard let game = selectedGame else { return [] }
        return game.files.filter { selectedSourceIDs.contains($0.id) }
    }
    
    public var selectedSourcesSizeBytes: Int64 {
        SourceSelection.uniqueSize(selectedSources)
    }

    public var selectedSourcesRequireKeys: Bool { SourceSelection.requiresKeys(selectedSources) }
    public var engineSourceCapabilities: EngineSourceCapabilities {
        EngineSourceCapabilities(repo: URL(fileURLWithPath: nxnativePath))
    }

    public func supportsSources(_ sources: [GameFileItem]) -> Bool {
        let capabilities = engineSourceCapabilities
        return SourceSelection.supported(sources, titleSelection: capabilities.titleSelection,
                                         extractedFolders: capabilities.extractedFolders,
                                         nupContainers: capabilities.nupContainers)
    }
    
    public var formattedSelectedSourcesSize: String {
        ByteCountFormatter.string(fromByteCount: selectedSourcesSizeBytes, countStyle: .file)
    }
    
    /// The build keeps an extracted copy and writes a temporary app before the
    /// atomic install, so plan for roughly twice the source size plus 10 GB.
    public var requiredBuildDiskBytes: Int64 {
        selectedSourcesSizeBytes * 2 + 10_000_000_000
    }
    
    public var isAddDiskSpaceLow: Bool {
        guard let avail = availableDiskBytes, selectedSourcesSizeBytes > 0 else { return false }
        return avail < requiredBuildDiskBytes
    }

    public var isDiskSpaceLow: Bool {
        guard let avail = availableBuildDiskBytes, selectedSourcesSizeBytes > 0 else { return false }
        return avail < requiredBuildDiskBytes
    }
    
    public var diskSpaceWarningMessage: String? {
        guard isDiskSpaceLow, let avail = availableBuildDiskBytes else { return nil }
        let needed = requiredBuildDiskBytes - avail
        let availStr = ByteCountFormatter.string(fromByteCount: avail, countStyle: .file)
        let requiredStr = ByteCountFormatter.string(fromByteCount: requiredBuildDiskBytes, countStyle: .file)
        let neededStr = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
        return "Storage warning: this build needs ~\(requiredStr) free (twice the selected sources plus 10 GB), but only \(availStr) is available. Free at least \(neededStr) before adding it."
    }
    
    public var canAddSelectedGame: Bool {
        guard !isBuilding, !isScanningGameFolder, let game = selectedGame else { return false }
        return game.hasGame
            && SourceSelection.hasGame(selectedSources)
            && selectedSourcesSizeBytes > 0
            && !isAddDiskSpaceLow
    }
    
    public func resetSourceSelection(for game: SelectableGame) {
        selectedSourceIDs = SourceSelection.initial(in: game.files)
    }
    
    public func toggleSource(_ item: GameFileItem) {
        guard let game = selectedGame else { return }
        selectedSourceIDs = SourceSelection.toggling(item.id, in: game.files, selected: selectedSourceIDs)
    }
    
    // MARK: - Drag & Drop & ZIP
    @Published public var dropErrorMessage: String? = nil
    
    // MARK: - Library
    @Published public var libraryGames: [PortedGame] = []
    @Published public var libraryFolder: URL? {
        didSet {
            if let folder = libraryFolder {
                UserDefaults.standard.set(folder.path, forKey: StorageKeys.savedLibraryFolder)
            }
        }
    }
    /// First use asks where to find existing games and install new ones; later visits keep that choice.
    public var requiresGameAppsFolderChoice: Bool {
        !setupCompleted && UserDefaults.standard.string(forKey: StorageKeys.savedLibraryFolder) == nil
    }
    @Published public var isScanningLibrary: Bool = false
    /// Non-blocking scan details shown beside Library refresh, never an automatic launch dialog.
    @Published public var libraryScanWarnings: [String] = []
    @Published public var gameForSettingsSheet: PortedGame? = nil
    /// Where the open Game options came from; decides its rows (Move is Spotlight-only).
    @Published public var gameOptionsOrigin: GameOptionsOrigin = .collection
    /// Game options opens straight on its Mods panel (the Details page's Mods band).
    @Published public var gameOptionsOpensMods = false
    /// The running game whose Close Game confirmation is open. The shell draws the dialog.
    @Published public var gameToClose: PortedGame? = nil
    @Published var closeGameFocus: SeleneConfirmButton = .cancel
    @Published public var pendingRuntimeConfig = GameRuntimeConfig()
    private var lastAddGameDefaults = GameRuntimeConfig()
    private var preparedSourceReview = FirstRunSetup.ReviewEntry()
    var addGameSessionActive = false
    @Published public var importedApps: [ImportedApp] = []
    @Published public var environmentStatus: EnvironmentStatus? = nil
    @Published public var compatibilityReport: CompatibilityReport? = nil
    @Published public var keySummary: KeySummary? = nil
    @Published public var currentEngineCommit: String? = nil
    @Published public var upstreamState: UpstreamCheckState = .idle
    @Published public var storeMetadata: [UUID: NintendoStoreMetadata] = [:]
    @Published public var storeMetadataLoading: Set<UUID> = []
    @Published public var storeMetadataErrors: [UUID: String] = [:]
    @Published public var storageUsage: StorageUsage? = nil
    @Published public var isCalculatingStorage: Bool = false
    @Published public var showSetupCheck: Bool = false
    /// The Setup check's state and installs; lives with the app so an install survives closing the screen.
    lazy var setupModel = SetupCheckModel(viewModel: self)
    @Published public private(set) var firstRunSetup = FirstRunSetup() {
        didSet {
            UserDefaults.standard.set(firstRunSetup.isCompleted, forKey: StorageKeys.setupCompleted)
            if let page = firstRunSetup.pageToRemember {
                UserDefaults.standard.set(page, forKey: StorageKeys.setupPage)
            } else {
                UserDefaults.standard.removeObject(forKey: StorageKeys.setupPage)
            }
        }
    }
    public var setupCompleted: Bool { firstRunSetup.isCompleted }
    @Published public var buildState: BuildState = .idle
    @Published public var lastError: String? = nil
    @Published public var alertMessage: String? = nil
    @Published public var isCancellingBuild: Bool = false
    @Published public var buildLogURL: URL? = nil
    @Published public var currentBuildGameID: UUID? = nil
    @Published public var lastBuildGameID: UUID? = nil
    @Published public var allowUntestedToolchain: Bool = false {
        didSet {
            UserDefaults.standard.set(allowUntestedToolchain, forKey: StorageKeys.allowUntestedToolchain)
        }
    }
    /// The newest nxnative the player chose in Settings → Engine; nil while the tested engine is in use.
    @Published public internal(set) var newestEngineChoice: NewestEngineChoice? = nil {
        didSet {
            if let choice = newestEngineChoice, let data = try? JSONEncoder().encode(choice) {
                UserDefaults.standard.set(data, forKey: StorageKeys.newestEngineChoice)
            } else {
                UserDefaults.standard.removeObject(forKey: StorageKeys.newestEngineChoice)
            }
        }
    }
    /// Whether upstream main can be used here, read from its lock after an Upstream check.
    @Published public internal(set) var newestEngineReadiness: NewestEngineReadiness? = nil
    @Published public internal(set) var isSwitchingEngine = false
    /// Why the last switch did not happen, shown calmly in the Newest engine row.
    @Published public internal(set) var newestEngineProblem: String? = nil
    
    // MARK: - Advanced Options
    @Published public var appName: String = ""
    @Published public var bundleId: String = ""
    
    // MARK: - Build State
    @Published public var isBuilding: Bool = false
    @Published public var currentStageName: String = ""
    @Published public var currentStepName: String = ""
    @Published public var stageIndex: Int = 0
    @Published public var totalStages: Int = 0
    @Published public var progressFraction: Double = 0.0
    @Published public var etaSeconds: Double? = nil
    @Published public var buildStages: [BuildStageItem] = []
    /// The running (or just finished) porting folded into one overall fraction for the home.
    @Published public var portingProgress: PortingProgress? = nil
    /// The game ported last in this session leads Spotlight's row until quit.
    @Published public var frontGameID: UUID? = nil
    /// Spotlight's Delete on a failed porting asks first.
    @Published public var gameToRemove: PortedGame? = nil
    @Published var removeGameFocus: SeleneConfirmButton = .cancel
    @Published public var showLiveLogsInBuild: Bool = true
    @Published public var logs: [LogEntry] = []
    @Published public var buildError: String? = nil
    /// Why the porting on the Porting step failed, when recognised; nil otherwise.
    @Published public var portingFailureReason: PortingFailureReason? = nil
    @Published public var buildSuccessPath: String? = nil
    /// The game whose finished build waits for it to quit (`PendingInstall`).
    @Published var buildHeldGameID: UUID? = nil
    /// The existing Selene dialog offers retrying the ready app, or closing it.
    @Published var gameWithInstallFailure: PortedGame? = nil
    @Published var installFailureFocus: SeleneConfirmButton = .cancel

    var canRetryReadyInstall: Bool {
        buildState == .failed && portingFailureReason == nil
            && libraryGames.contains { $0.id == lastBuildGameID && $0.pendingInstall != nil }
    }
    @Published public var buildWizardStep: Int = 1 // 1: Select Game, 2: Configure & Output, 3: Porting
    @Published public var iconAppearanceMode: AppIconAppearanceMode = .auto {
        didSet {
            UserDefaults.standard.set(iconAppearanceMode.rawValue, forKey: StorageKeys.savedIconAppearanceMode)
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
    @Published public var launchOverlay: LaunchOverlayState? = nil {
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

    public let pinnedEngineCommit = "e5f03403bfd2ca9c07b890f1cf33bd65230b5103"
    private let core = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NXLibrary")
    lazy var libraryStore = LibraryStore(directory: core)
    lazy var keyStore = KeyStore(directory: core.appendingPathComponent("keys"))
    /// Sizes of built apps are remembered between launches, so a scan walks only new or rebuilt apps.
    private lazy var importService = ImportService(sizeCache: AppSizeCache(file: core.appendingPathComponent("app-sizes.json")))
    private let launchService = LaunchService()
    private lazy var upstreamChecker = UpstreamChecker()
    private lazy var storeMetadataService = NintendoStoreMetadataService()
    private let upstreamCacheKey = "NXLibrary_UpstreamStatus"
    private lazy var storageManager = StorageManager()
    private let sourceCatalog = SourceCatalog()
    private lazy var workspaceManager = WorkspaceManager(root: core.appendingPathComponent("workspaces"))
    private var scanGeneration = UUID()
    private var buildService: BuildService?
    private var buildPreviousStatus: GameStatus?
    private var activeBuildToolchain: ToolchainInfo?
    private var environmentCheckGeneration = UUID()
    private var buildStartedAt: Date?
    private var buildTempDirectory: URL?
    
    public init(settingsStore: AppSettingsStore = AppSettingsStore()) {
        self.settingsStore = settingsStore
        saveGate.onActivityChange = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.hasActiveSaveOperations = self.saveGate.hasActiveOperations
            }
        }
        let startup = settingsStore.settings
        let didCompleteSetup = UserDefaults.standard.bool(forKey: StorageKeys.setupCompleted)
        self.firstRunSetup = FirstRunSetup(completed: didCompleteSetup,
                                           savedPage: UserDefaults.standard.string(forKey: StorageKeys.setupPage))
        self.showSetupCheck = !didCompleteSetup
        
        // 1. Resolve safe root directory (anchored to SSD / Bundle, NEVER "/")
        let root = SystemDetector.shared.resolveRootDirectory()
        self.defaultInstallPath = root.path
        
        // The launcher's old ~/Games default is not a Mac-app library.
        let oldGamesDefault = root.appendingPathComponent("Games").standardized.path
        if let savedLib = UserDefaults.standard.string(forKey: StorageKeys.savedLibraryFolder),
           savedLib != oldGamesDefault, !savedLib.isEmpty, savedLib != "/" {
            self.libraryFolder = URL(fileURLWithPath: savedLib)
        } else {
            self.libraryFolder = root.appendingPathComponent("Applications")
            UserDefaults.standard.removeObject(forKey: StorageKeys.savedLibraryFolder)
        }
        
        // Restore user preferences
        if let savedMode = UserDefaults.standard.string(forKey: StorageKeys.savedIconAppearanceMode),
           let mode = AppIconAppearanceMode(rawValue: savedMode) {
            self.iconAppearanceMode = mode == .mono ? .mono : .auto
        }
        if UserDefaults.standard.object(forKey: StorageKeys.allowUntestedToolchain) != nil {
            self.allowUntestedToolchain = UserDefaults.standard.bool(forKey: StorageKeys.allowUntestedToolchain)
        }
        if let data = UserDefaults.standard.data(forKey: StorageKeys.newestEngineChoice) {
            self.newestEngineChoice = try? JSONDecoder().decode(NewestEngineChoice.self, from: data)
        }
        
        restoreBuildInputs()
        if startup.checkEngineAtLaunch || !didCompleteSetup { refreshCompatibility() }
        
        // Restore saved game folder if it exists
        if let savedGamePath = UserDefaults.standard.string(forKey: StorageKeys.savedGameFolder) {
            if !savedGamePath.isEmpty, savedGamePath != "/" {
                restoringGameFolder = !startup.refreshLibraryAtLaunch
                self.selectedGameFolder = URL(fileURLWithPath: savedGamePath)
                restoringGameFolder = false
            }
        }
        
        restoreLibraryFromDisk()
        if !setupCompleted && firstRunSetup.page == .games { prepareInitialGameAppsFolder() }
        if startup.refreshLibraryAtLaunch || (!setupCompleted && firstRunSetup.page == .games) { loadLibrary() }
        if let data = UserDefaults.standard.data(forKey: upstreamCacheKey),
           let cached = try? JSONDecoder().decode(UpstreamStatus.self, from: data),
           cached.baseCommit == pinnedEngineCommit {
            self.upstreamState = .loaded(cached)
        }
        updateDockIcon()
        
        NotificationService.shared.requestAuthorization()
        let held = PendingInstaller.keptFolders(libraryGames)
        let staging = BuildScratch.tempFolders(
            core: core, appFolders: [gameAppsFolder] + libraryGames.map { $0.url.deletingLastPathComponent() })
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.sweepStaleBuildTemp(in: staging, keeping: held)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.buildService?.terminateNow()
            if let temp = self?.buildTempDirectory {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-setup") {
            self.showSetupCheck = true
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-build") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.previewBuild()
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

    private func restoreBuildInputs(customRyujinxDir: String? = nil) {
        let nxResult = SystemDetector.shared.detectNxnativeDirectory(
            saved: UserDefaults.standard.string(forKey: StorageKeys.savedEngineFolder))
        self.nxnativePath = nxResult.path
        self.isNxnativeValid = nxResult.isValid
        ensureKeysImported(customRyujinxDir: customRyujinxDir)
    }

    /// With launch checks off, inspecting a build screen performs the check on demand.
    public func prepareBuildEnvironmentIfNeeded() {
        if environmentStatus == nil, !isCheckingEnvironment { detectEnvironment() }
    }

    @Published public private(set) var isCheckingEnvironment = false

    private func ensureKeysImported(customRyujinxDir: String? = nil) {
        let fm = FileManager.default
        if fm.fileExists(atPath: keyStore.keyURL.path) {
            do {
                let summary = try keyStore.validate(at: keyStore.keyURL)
                keySummary = summary
                isProdKeysValid = summary.hasHeaderKey
                prodKeysPath = keyStore.keyURL.path
                prodKeysSource = "NX Library"
            } catch {
                keySummary = nil
                isProdKeysValid = false
                prodKeysSource = "Invalid stored copy"
                logs.append(LogEntry(level: .error,
                                     message: "Stored prod.keys is invalid: \(error.localizedDescription)"))
            }
            return
        }
        let saved = UserDefaults.standard.string(forKey: StorageKeys.savedProdKeysPath)
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
            showSettingsNotice(title: "Porting in progress", message: "Change keys after the porting finishes.")
            return
        }
        do {
            let summary = try keyStore.importKey(from: url)
            keySummary = summary
            isProdKeysValid = summary.hasHeaderKey
            prodKeysPath = keyStore.keyURL.path
            prodKeysSource = "Imported once"
            refreshKeyCheck()
            if let folder = selectedGameFolder { scanGameFolder(folder) }
            lastError = nil
            logs.append(LogEntry(
                level: .success,
                message: "prod.keys imported: header key present, \(summary.applicationKeyGenerations.count) application key generations."
            ))
        } catch {
            keySummary = try? keyStore.validate(at: keyStore.keyURL)
            isProdKeysValid = keySummary?.hasHeaderKey == true
            prodKeysPath = isProdKeysValid ? keyStore.keyURL.path : ""
            lastError = error.localizedDescription
            showSettingsNotice(title: "Keys not changed", message: isProdKeysValid
                ? "The key file could not be imported. Your previous copy is kept."
                : "The key file could not be imported. Choose a valid prod.keys file.")
            logs.append(LogEntry(level: .error,
                                 message: "Could not import prod.keys: \(error.localizedDescription)"))
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
                    self.logs.append(LogEntry(level: .warning, message: "Toolchain gate: \(blocked)"))
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
                    UserDefaults.standard.set(data, forKey: self.upstreamCacheKey)
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
        guard let titleId = game.titleId, !titleId.isEmpty else { return }
        if storeMetadataLoading.contains(game.id) { return }
        if let existing = storeMetadata[game.id], storeMetadataService.isFresh(existing) {
            loadFallbackScreenshots(for: game)
            return
        }

        storeMetadataLoading.insert(game.id)
        storeMetadataErrors[game.id] = nil
        let service = storeMetadataService
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let metadata = try await service.metadata(for: game)
                self.setStoreMetadata(metadata, for: game)
            } catch {
                self.storeMetadataErrors[game.id] = error.localizedDescription
            }
            self.storeMetadataLoading.remove(game.id)
            self.loadFallbackScreenshots(for: game)
        }
    }

    /// Fills metadata from the seven-day disk cache without starting a network
    /// request. The library uses this so a previously viewed game paints its
    /// title, description and hero immediately when selected.
    public func preloadCachedStoreMetadata() {
        for game in libraryGames {
            guard storeMetadata[game.id] == nil,
                  let titleId = game.titleId,
                  !titleId.isEmpty,
                  let metadata = storeMetadataService.cached(for: titleId) else { continue }
            setStoreMetadata(metadata, for: game)
        }
    }

    /// The store's metadata as fetched, before the player's choices are laid over it.
    private var storeMetadataOriginals: [UUID: NintendoStoreMetadata] = [:]

    /// Keeps the fetched metadata and shows it with the player's choices (`MetadataPicks`) over it.
    private func setStoreMetadata(_ metadata: NintendoStoreMetadata, for game: PortedGame) {
        storeMetadataOriginals[game.id] = metadata
        let shown = MetadataPicks.shared.applied(to: metadata, titleID: game.titleId ?? game.uniqueKey)
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
        let key = game.titleId ?? game.uniqueKey
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
        storeMetadataService.cacheSize()
    }

    public func clearMetadataCache() {
        storeMetadataService.clearCache()
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

    func resolvedDeveloperDir() -> URL {
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
        loadLibrary()
        firstRunSetup.advance()
    }

    public func returnToSetupRequirements() { firstRunSetup.goBack() }

    private func prepareInitialGameAppsFolder() {
        do {
            try GameAppDestination.prepareInitialFolder(gameAppsFolder,
                hasExplicitChoice: UserDefaults.standard.string(forKey: StorageKeys.savedLibraryFolder) != nil)
        } catch {
            logs.append(LogEntry(level: .warning, message: "Could not prepare the default Game apps folder: \(error.localizedDescription)"))
        }
    }

    public func completeSetup() {
        UserDefaults.standard.set(gameAppsFolder.path, forKey: StorageKeys.savedLibraryFolder)
        firstRunSetup.finish()
        showSetupCheck = false
        logs.append(LogEntry(level: .success, message: "Setup completed."))
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
        guard !isCalculatingStorage else { return }
        isCalculatingStorage = true
        let manager = storageManager
        let games = libraryGames
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let usage = manager.usage(games: games)
            DispatchQueue.main.async {
                self?.storageUsage = usage
                self?.isCalculatingStorage = false
            }
        }
    }

    public func deleteCaches() {
        guard !isBuilding else {
            alertMessage = "Finish or cancel the active build before cleaning caches."
            return
        }
        var removed = 0
        for game in libraryGames {
            do {
                try storageManager.deleteCache(for: game)
                removed += 1
            } catch {
                logs.append(LogEntry(level: .error,
                                     message: "Could not delete the cache for \(game.name): \(error.localizedDescription)"))
            }
        }
        logs.append(LogEntry(level: .info, message: "Cleaned build caches for \(removed) game\(removed == 1 ? "" : "s")."))
        refreshStorageUsage()
    }

    public func deleteLogs() {
        guard !isBuilding else {
            alertMessage = "Finish or cancel the active build before deleting logs."
            return
        }
        var removed = 0
        for game in libraryGames {
            do {
                try storageManager.deleteLogs(for: game)
                removed += 1
            } catch {
                logs.append(LogEntry(level: .error,
                                     message: "Could not delete the logs for \(game.name): \(error.localizedDescription)"))
            }
        }
        logs.append(LogEntry(level: .info, message: "Deleted logs for \(removed) game\(removed == 1 ? "" : "s")."))
        refreshStorageUsage()
    }

    
    // MARK: - Drag and Drop & ZIP
    public func handleDroppedURLs(_ urls: [URL]) {
        dropErrorMessage = nil
        guard let first = urls.first else { return }
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir) {
            if isDir.boolValue {
                self.selectedGameFolder = first
            } else {
                let parent = first.deletingLastPathComponent()
                self.selectedGameFolder = parent
            }
        }
    }
    
    // MARK: - Library
    public func refreshLibrary() {
        loadLibrary()
    }

    private func restoreLibraryFromDisk() {
        do {
            libraryGames = try libraryStore.load().games.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            recoverSavesAtStartup()
        } catch {
            lastError = error.localizedDescription
            logs.append(LogEntry(level: .error, message: "Could not read the library: \(error.localizedDescription)"))
        }
    }

    public func loadLibrary() {
        guard !isScanningLibrary else { return }
        isScanningLibrary = true
        // At launch the saved library shows at once; the folder scan below then brings in new and changed apps.
        if libraryGames.isEmpty, let stored = try? libraryStore.load(), !stored.games.isEmpty {
            libraryGames = stored.games.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        let fm = FileManager.default
        let directories = [gameAppsFolder]
        let store = libraryStore
        let importer = importService
        let folderSnapshot = libraryFolder?.standardizedFileURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = (try? store.load()) ?? LibraryFile()
            let scanned = importer.scan(directories: directories)
            let scanWarnings = importer.scanWarnings
            let selected = importer.appsForLibrary(scanned: scanned, existing: loaded.games)
            let importedGames = selected.map { importer.makeGame(from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                // A folder chosen during the startup scan gets its own scan before results appear.
                guard self.libraryFolder?.standardizedFileURL == folderSnapshot else {
                    self.isScanningLibrary = false
                    self.loadLibrary()
                    return
                }
                self.importedApps = selected
                var scannedByTitle: [String: ImportedApp] = [:]
                for app in selected {
                    if let titleId = app.titleId, scannedByTitle[titleId.uppercased()] == nil {
                        scannedByTitle[titleId.uppercased()] = app
                    }
                }
                var library = loaded
                do {
                    library = try store.merge(scanned: importedGames)
                } catch {
                    self.lastError = error.localizedDescription
                    self.logs.append(LogEntry(level: .error,
                                              message: "Could not update the library: \(error.localizedDescription)"))
                }
                for index in library.games.indices {
                    let scannedApp = library.games[index].titleId
                        .flatMap { scannedByTitle[$0.uppercased()] }
                    if let scannedApp, !fm.fileExists(atPath: library.games[index].url.path),
                       fm.fileExists(atPath: scannedApp.appURL.path) {
                        library.games[index].url = scannedApp.appURL
                    }
                    if let scannedApp, fm.fileExists(atPath: scannedApp.appURL.path) {
                        library.games[index].sizeBytes = scannedApp.sizeBytes
                        library.games[index].versionString = scannedApp.version
                            ?? library.games[index].versionString
                        library.games[index].bundleId = scannedApp.bundleId
                            ?? library.games[index].bundleId
                    }
                    let appExists = fm.fileExists(atPath: library.games[index].url.path)
                    let sourcesExist = GameResourceState.sourcesAvailable(for: library.games[index], fileManager: fm)
                    library.games[index].status = GameResourceState.reconciledStatus(
                        for: library.games[index], appExists: appExists, sourcesAvailable: sourcesExist)
                }
                do { try store.save(library) } catch { self.reportLibrarySaveFailure(error) }
                self.libraryGames = library.games.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                self.libraryScanWarnings = scanWarnings
                self.isScanningLibrary = false
                // Paths are known again: icons chosen while an app was elsewhere, or left half done, go on now.
                self.reconcileAppIcons()
                if !scanWarnings.isEmpty {
                    for warning in scanWarnings {
                        self.logs.append(LogEntry(level: .warning, message: warning))
                    }
                }
            }
        }
    }

    public func importExistingBuilds() {
        loadLibrary()
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

        isScanningGameFolder = true
        let catalog = sourceCatalog
        let repo = URL(fileURLWithPath: nxnativePath)
        let toolchain = engineToolchain
        let keys = isProdKeysValid ? keyStore.keyURL : nil
        let developer = resolvedDeveloperDir()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = ExtractedSourceCatalog.recognizes(folder) ? [] : Self.sourceFileURLs(in: folder)
            let outcome = Result { try Self.scanSources(in: folder, files: urls, catalog: catalog,
                repo: repo, toolchain: toolchain, keys: keys, developerDir: developer) }
            let detected = (try? outcome.get().games) ?? []
            let match = detected.first {
                String(format: "%016llX", $0.baseTitleId)
                    .caseInsensitiveCompare(titleId) == .orderedSame
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanningGameFolder = false
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
                    let updated = try self.addGame(
                        detected: match,
                        selected: selected,
                        folder: nil,
                        bundleId: game.bundleId
                    )
                    self.librarySelection.selectedGameID = updated.id
                    self.logs.append(LogEntry(level: .success,
                        message: "Sources attached to \(game.name); rebuild is now available if the toolchain gate allows it."))
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
        guard launchingGameId == nil else { return }
        // A running game is brought forward, never started a second time.
        if let running = RunningGameMonitor.runningApplication(for: game) {
            RunningGameMonitor.activate(running)
            return
        }
        guard savesPermitPlay(game) else { return }
        // The app is being signed again with a new icon: starting it now could read a half-written bundle.
        guard !appIconsInFlight.contains(game.id) else {
            alertMessage = "\(game.name)'s app icon is being updated. Play again in a moment."
            SoundEffectService.shared.play(.error)
            return
        }
        // A build that waited for the game to quit goes in first.
        let game = installingPendingBuild(of: game)
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
                ?? "This game is not built yet. Build it first."
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
        launchOverlay = LaunchOverlayState(game: game)
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
                                 message: "Could not write the runtime environment: \(error.localizedDescription)"))
            return
        }

        if let choice = settingsStore?.settings.cloudSaves, let domain = game.effectiveBundleId {
            do {
                try cloudSavesPreferences.applyBeforeLaunch(choice, domain: domain)
            } catch {
                logs.append(LogEntry(level: .warning, message: "Cloud saves: \(error.localizedDescription)"))
                showSettingsNotice(title: "Cloud unavailable",
                                   message: "Cloud sync could not be updated for this launch. Check Games → Cloud saves.")
            }
        }

        launchService.launch(appURL: game.url,
                             environment: gameSettings == nil ? config.toEnvironmentDict() : [:]) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveGate.end(titleID: titleId, token: saveLaunchToken)
                if success {
                    self.lastError = nil
                    self.playSessionStore?.start(for: game)
                    self.logs.append(LogEntry(level: .success, message: "Launched game: \(game.name)"))
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
                                              message: "\(game.name) showed no window within 60 s; launch screen closed."))
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
        gameForSettingsSheet = game
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
                ? "Turn on iCloud Drive or choose a sync folder."
                : "The sync folder is unavailable. Choose another folder."
            showSettingsNotice(title: "Cloud unavailable", message: message)
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: error.localizedDescription))
            return
        }
        settingsStore.settings.cloudSaves = choice
        if case .folder(let path) = choice { settingsStore.settings.cloudSavesPickedFolder = path }
        logs.append(LogEntry(level: .info, message: "Cloud saves: \(choice.folderURL()?.path ?? "off")"))
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
        guard var library = try? libraryStore.load(),
              let index = library.games.firstIndex(where: { $0.id == game.id }) else { return }
        change(&library.games[index])
        do {
            try libraryStore.save(library)
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        libraryGames = library.games.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
            let stored = UserDefaults.standard.double(forKey: StorageKeys.lastPortingFinishSeconds)
            if stored > 0 { return stored }
            guard !didSeedFinishSeconds else { return nil }
            didSeedFinishSeconds = true
            guard let seeded = Self.finishSecondsFromNewestLog(in: core.appendingPathComponent("logs")) else {
                return nil
            }
            UserDefaults.standard.set(seeded, forKey: StorageKeys.lastPortingFinishSeconds)
            return seeded
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: StorageKeys.lastPortingFinishSeconds) }
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
        let message = "NX Library could not save your library, so recent changes may be lost when it quits: "
            + error.localizedDescription
        logs.append(LogEntry(level: .error, message: message))
        if alertMessage == nil { alertMessage = message }
    }

    private func updateStoredStatus(_ status: GameStatus, for game: PortedGame) {
        guard var library = try? libraryStore.load(),
              let index = library.games.firstIndex(where: { $0.id == game.id }) else { return }
        library.games[index].status = status
        do { try libraryStore.save(library) } catch { reportLibrarySaveFailure(error) }
        libraryGames = library.games.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
        logs.append(LogEntry(level: .error, message: "Could not save settings for \(game.name): \(error.localizedDescription)"))
        showSettingsNotice(title: "Options not saved", message: "Your game options could not be saved. Try again.")
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
            logs.append(LogEntry(level: .success, message: "Saved settings for \(game.name)"))
            return true
        } catch {
            logs.append(LogEntry(level: .error, message: "Could not save settings for \(game.name): \(error.localizedDescription)"))
            showSettingsNotice(title: "Options not saved", message: "Your game options could not be saved. Try again.") { [weak self] in
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
            parts.append("\(existingSources.count) original source file\(existingSources.count == 1 ? "" : "s") (\(Self.formatBytes(sourceBytes)))")
        }
        if workspaceBytes > 0 {
            parts.append("the build cache (\(Self.formatBytes(workspaceBytes)))")
        }
        let target = parts.isEmpty ? "the remaining build data" : parts.joined(separator: " and ")
        return "This permanently deletes \(target). The installed app, saves and logs stay. Rebuilds will be disabled until you attach the sources again. This cannot be undone."
    }

    public func removeSources(for game: PortedGame) {
        guard !isBuilding else {
            alertMessage = "Wait for the current build to finish before removing sources."
            return
        }
        let fm = FileManager.default
        guard var library = try? libraryStore.load(),
              let index = library.games.firstIndex(where: { $0.id == game.id }) else {
            alertMessage = "Could not load the library entry for \(game.name)."
            return
        }

        let appPath = game.url.standardizedFileURL.path
        let otherGames = library.games.filter { $0.id != game.id }
        var removedCount = 0
        var removedBytes: Int64 = 0
        var failures: [String] = []

        for source in game.sources {
            let url = source.url.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                failures.append("\(url.lastPathComponent) is a folder")
                continue
            }
            if url.path.hasPrefix(appPath + "/") {
                failures.append("\(url.lastPathComponent) is inside the app")
                continue
            }
            let shared = otherGames.contains { other in
                other.sources.contains { $0.url.standardizedFileURL == url }
            }
            if shared {
                failures.append("\(url.lastPathComponent) is also used by another library entry")
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
                    failures.append("build cache: \(error.localizedDescription)")
                }
            }
        }

        var updated = library.games[index]
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
        library.games[index] = updated

        do {
            try libraryStore.save(library)
        } catch {
            alertMessage = "The sources were removed, but the library could not be saved: \(error.localizedDescription)"
            logs.append(LogEntry(level: .error, message: alertMessage!))
            return
        }
        libraryGames = library.games.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let removed = "Removed \(removedCount) source file\(removedCount == 1 ? "" : "s") (\(Self.formatBytes(removedBytes)))\(removedWorkspace ? " and the build cache" : "")."
        if failures.isEmpty {
            logs.append(LogEntry(level: .success,
                                 message: "\(removed) The installed app and saves were kept."))
            alertMessage = "\(removed) The installed app and saves were kept. Rebuilds stay disabled until you attach the sources again."
        } else {
            let detail = failures.joined(separator: "; ")
            logs.append(LogEntry(level: .warning,
                                 message: "\(removed) Some items were kept: \(detail)"))
            alertMessage = "\(removed) Some items were kept: \(detail)"
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

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

            var library = try libraryStore.load()
            library.games.removeAll { $0.id == game.id }
            try libraryStore.save(library)
            libraryGames = library.games.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if deleteBundle {
                logs.append(LogEntry(level: .warning,
                    message: "Game app deleted: \(game.name)\(removedWorkspace ? "; staged workspace removed" : "")"))
            } else {
                logs.append(LogEntry(level: .warning,
                    message: "Removed \(game.name) from the library; its source folders were left in place."))
            }
        } catch {
            let message = "Failed to delete game: \(error.localizedDescription)"
            alertMessage = message
            logs.append(LogEntry(level: .error, message: message))
        }
    }
    
    // MARK: - Game Scan
    private func scanGameFolder(_ folder: URL) {
        let previousTitle = selectedGame?.id
        let previousFiles = selectedGame?.files ?? []
        let previousSelection = selectedSourceIDs
        let previousName = appName
        let previousBundle = bundleId
        let previousConfig = pendingRuntimeConfig
        scanError = nil
        isScanningGameFolder = true
        selectedGame = nil
        selectedSourceIDs = []
        let generation = UUID()
        scanGeneration = generation
        let catalog = sourceCatalog
        let repo = URL(fileURLWithPath: nxnativePath)
        let toolchain = engineToolchain
        let keys = isProdKeysValid ? keyStore.keyURL : nil
        let developer = resolvedDeveloperDir()
        let explicitFiles = selectedPackageURLs
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = explicitFiles ?? (ExtractedSourceCatalog.recognizes(folder) ? [] : Self.sourceFileURLs(in: folder))
            let outcome = Result { try Self.scanSources(in: folder, files: urls, catalog: catalog,
                repo: repo, toolchain: toolchain, keys: keys, developerDir: developer,
                allowExtractedFolder: explicitFiles == nil) }
            let detected = (try? outcome.get().games) ?? []
            let games = detected.map(Self.selectableGame(from:))
            DispatchQueue.main.async {
                guard let self,
                      self.scanGeneration == generation,
                      self.selectedGameFolder?.standardizedFileURL == folder.standardizedFileURL else {
                    return
                }
                self.isScanningGameFolder = false
                self.detectedGames = games
                let selectedID = SourceSelection.initialTitleID(available: games.map(\.id), previous: previousTitle)
                self.selectedGame = games.first { $0.id == selectedID }
                if let previousTitle, self.selectedGame?.id == previousTitle {
                    self.selectedSourceIDs = SourceSelection.restoredSelection(previous: previousFiles,
                        selected: previousSelection, current: self.selectedGame?.files ?? [])
                    self.appName = previousName
                    self.bundleId = previousBundle
                    self.pendingRuntimeConfig = previousConfig
                }
                if let skipped = try? outcome.get().skipped, !skipped.isEmpty {
                    self.scanError = "Unreadable packages: " + skipped.joined(separator: ", ")
                }
                if games.isEmpty {
                    if case .failure(let error) = outcome {
                        self.scanError = error.localizedDescription
                    } else { self.scanError = urls.isEmpty
                        ? "No game was found in this folder: no NSP, XCI, NSZ, XCZ or NUP file, and no extracted game (a folder with exefs and romfs, or with base/exefs and base/romfs)."
                        : "No readable game files were found. Check that the files are complete and have a title ID or ticket." }
                    self.logs.append(LogEntry(level: .warning, message: self.scanError!))
                } else {
                    self.logs.append(LogEntry(level: .info,
                        message: "Detected \(games.count) game\(games.count == 1 ? "" : "s") in \(folder.lastPathComponent)."))
                }
            }
        }
    }

    private struct ScannedSources {
        var games: [DetectedGame]
        var skipped: [String] = []
    }

    private static func scanSources(in folder: URL, files: [URL], catalog: SourceCatalog,
                                    repo: URL, toolchain: EngineToolchain, keys: URL?, developerDir: URL,
                                    allowExtractedFolder: Bool = true) throws -> ScannedSources {
        let capabilities = EngineSourceCapabilities(repo: repo)
        if allowExtractedFolder && ExtractedSourceCatalog.recognizes(folder) {
            guard capabilities.extractedFolders else {
                throw NXLibraryError.environmentBlocked("This engine does not support extracted folders.")
            }
            let catalog = ExtractedSourceCatalog(profiles: repo.appendingPathComponent("dm/games"),
                                                 provisional: capabilities.provisionalDumps)
            return ScannedSources(games: [try catalog.scan(folder: folder)])
        }
        // A Switch 2 NUP file holds the whole game: picked on its own, or the one .nup in a folder without packages.
        let pickedNUPs = files.filter { $0.pathExtension.lowercased() == "nup" }
        guard pickedNUPs.isEmpty || (files.count == 1 && NUPSourceCatalog.isNUP(files[0])) else {
            throw EngineSourceError.containerNotAlone
        }
        if let nup = pickedNUPs.first ?? (allowExtractedFolder ? NUPSourceCatalog.container(in: folder) : nil) {
            guard capabilities.nupContainers else {
                throw NXLibraryError.environmentBlocked("This engine does not support NUP files.")
            }
            let reader = NUPSourceCatalog(repo: repo, toolchain: toolchain, developerDir: developerDir)
            return ScannedSources(games: [try reader.scan(nup: nup)])
        }
        var detected: [DetectedGame]
        var skipped: [String] = []
        if capabilities.titleSelection, let keys {
            let reader = EnginePackageReader(repo: repo, toolchain: toolchain, keys: keys, developerDir: developerDir)
            let readings = try reader.contents(of: files.filter { !$0.hasDirectoryPath }.map {
                (url: $0, alreadyIdentified: (try? catalog.inspect($0)) != nil)
            })
            detected = try catalog.scan(files: files, skippingUnreadable: true,
                onUnreadable: { url, _ in skipped.append(url.lastPathComponent) }) { file in
                switch readings[file] {
                case .contents(let rows)?: return rows
                case .unreadable(let why)?: throw EngineSourceError.unreadablePackage(why)
                case nil: return []
                }
            }
        } else {
            detected = try catalog.scan(files: files.filter { (try? catalog.inspect($0)) != nil })
        }
        for index in detected.indices {
            let title = detected[index].id
            let profile = repo.appendingPathComponent("dm/games/\(title)/game.tsv")
            if let text = try? String(contentsOf: profile, encoding: .utf8),
               let name = text.split(separator: "\n").first(where: { $0.hasPrefix("name\t") }) {
                detected[index].name = String(name.dropFirst(5))
            }
        }
        return ScannedSources(games: detected, skipped: skipped)
    }
    
    private static func sourceFileURLs(in folder: URL) -> [URL] {
        let allowed = Set(["nsp", "nsz", "xci", "xcz"])
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard allowed.contains(url.pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            let isLink = values?.isSymbolicLink == true
            guard values?.isRegularFile == true || isLink else { continue }
            // A symlink must point at a real, non-empty file; its own file size
            // is just the length of the link path.
            let target = isLink ? url.resolvingSymlinksInPath() : url
            let targetValues = try? target.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey])
            guard targetValues?.isRegularFile == true,
                  (targetValues?.fileSize ?? 0) > 0 else { continue }
            urls.append(url)
        }
        return urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
    
    private static func selectableGame(from game: DetectedGame) -> SelectableGame {
        var ordered = [game.base].compactMap { $0 }
        ordered += game.updates.sorted {
            ($0.version ?? -1) > ($1.version ?? -1)
        }
        ordered += game.dlcs.sorted {
            $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
        return SelectableGame(
            id: String(format: "%016llX", game.baseTitleId),
            name: game.name,
            titleId: String(format: "%016llX", game.baseTitleId),
            files: ordered.map { source in
                GameFileItem(
                    url: source.url,
                    kind: source.kind,
                    titleId: String(format: "%016llX", source.titleId),
                    versionString: source.version.map { "v\($0)" },
                    sizeBytes: source.sizeBytes, sourceLayout: source.layout,
                    requiresTitleSelection: source.requiresTitleSelection
                )
            }
        )
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
                UserDefaults.standard.set(saved, forKey: StorageKeys.savedEngineFolder)
            } else {
                UserDefaults.standard.removeObject(forKey: StorageKeys.savedEngineFolder)
            }
            self.nxnativePath = url.path
            self.isNxnativeValid = true
            refreshCompatibility()
        }
    }
    
    @discardableResult
    public func selectGameFolder(startingNewGameWith defaults: GameRuntimeConfig? = nil) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedGameFolder
        panel.prompt = "Choose folder"
        panel.message = GameFoldersCopy.sourcesPickerMessage(extractedFolders: engineSourceCapabilities.extractedFolders)
        
        if panel.runModal() == .OK, let url = panel.url {
            if let defaults { startNewAddGame(defaults: defaults) }
            self.selectedGameFolder = url
            return true
        }
        return false
    }

    @discardableResult
    public func selectGameFiles(startingNewGameWith defaults: GameRuntimeConfig? = nil) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["nsp", "xci", "nsz", "xcz", "nup"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Choose files"
        panel.message = "Choose NSP, XCI, NSZ or XCZ files, or one Switch 2 NUP file."
        guard panel.runModal() == .OK, let first = panel.urls.first else { return false }
        if let defaults { startNewAddGame(defaults: defaults) }
        let folder = first.deletingLastPathComponent()
        restoringGameFolder = true
        keepsRememberedGameFolder = true
        selectedGameFolder = folder
        keepsRememberedGameFolder = false
        restoringGameFolder = false
        selectedPackageURLs = panel.urls
        scanGameFolder(folder)
        return true
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
    public var canStartBuild: Bool {
        !isBuilding
            && !isUpdatingApp
            && canAddSelectedGame
            && supportsSources(selectedSources)
            && (!selectedSourcesRequireKeys || isProdKeysValid)
            && !keyCheckBlocks
            && isNxnativeValid
            && environmentStatus?.canBuild == true
            && !isDiskSpaceLow
            && buildDestinationProblem == nil
            && canPassToolchainGate
    }

    public func canBuild(_ game: PortedGame) -> Bool {
        guard !isBuilding,
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

    private func buildLogTail(_ url: URL, maxBytes: Int = 64 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public var buildProgress: Double { progressFraction }
    public var buildETA: Double? { etaSeconds }
    public var buildLog: [LogEntry] { logs }

    public func goToWizardStep(_ step: Int) {
        guard step >= 1 && step <= 3 else { return }
        if step == 2 && selectedGame == nil { return }
        buildWizardStep = step
    }

    public func resetWizard() {
        buildWizardStep = 1
        buildError = nil
        portingFailureReason = nil
        buildSuccessPath = nil
        buildState = .idle
        lastError = nil
    }

    /// Called when the Add Game route becomes visible. A build in progress always
    /// resumes on the live step; returning with Back keeps the draft; any other
    /// entry starts clean so an old success or failure screen never comes back.
    func consumePreparedReviewEntry(_ id: UUID?) -> Bool {
        guard buildWizardStep == 1 else { return false }
        return preparedSourceReview.consume(id, isReady: canAddSelectedGame, titleCount: detectedGames.count)
    }

    public func addGameDidBecomeVisible(defaults: GameRuntimeConfig, returningFromBack: Bool,
                                        preservingSelection: Bool = false) {
        prepareBuildEnvironmentIfNeeded()
        if isBuilding {
            buildWizardStep = 3
            addGameSessionActive = true
            return
        }
        if (returningFromBack || preservingSelection), addGameSessionActive { return }
        if reviewsFailureOnAddGame {
            reviewsFailureOnAddGame = false
            if restoreLastFailure() || buildError != nil { return }
        }
        startNewAddGame(defaults: defaults)
    }

    /// Ends the draft when the user leaves Add Game for a non-overlay route.
    public func addGameDidLeave() {
        guard !isBuilding else { return }
        addGameSessionActive = false
    }

    /// Starts a clean wizard while remembering the folder preference for next launch.
    public func startNewAddGame(defaults: GameRuntimeConfig? = nil) {
        guard !isBuilding else {
            buildWizardStep = 3
            addGameSessionActive = true
            return
        }
        if let defaults {
            lastAddGameDefaults = defaults
        }
        keepsRememberedGameFolder = true
        selectedGameFolder = nil
        keepsRememberedGameFolder = false
        detectedGames = []
        selectedGame = nil
        selectedSourceIDs = []
        scanError = nil
        appName = ""
        bundleId = ""
        pendingRuntimeConfig = lastAddGameDefaults
        resetWizard()
        addGameSessionActive = true
    }

    #if DEBUG
    /// Feeds sample events through the same reducer as a real build, for
    /// SwiftUI previews and UI work without running nxnative.
    public func previewBuild() {
        isBuilding = true
        buildState = .running
        buildWizardStep = 3
        currentBuildGameID = libraryGames.first?.id
        logs.removeAll()
        buildStages.removeAll()
        currentStageName = "Preparing build"
        currentStepName = ""
        progressFraction = 0
        etaSeconds = nil
        handleBuildEvent(.stage(k: 1, n: 8, name: "extract", step: "reading NSP"))
        handleBuildEvent(.stageEnd(name: "extract", ok: true, elapsed: 1.2, summary: "done"))
        handleBuildEvent(.stage(k: 2, n: 8, name: "translate shaders", step: "metal"))
        handleBuildEvent(.progress(fraction: 0.34, done: 120, total: 350, unit: "MB", eta: 42))
        handleBuildEvent(.say("Sample event: this is the live build reducer."))
    }
    #endif

    public func addSelectedGame(buildNow: Bool = false) {
        guard let selection = selectedGame else {
            presentBuildError(NXLibraryError.noSelectedGame)
            return
        }
        let files = selectedSources
        let sources = files.compactMap(Self.detectedSource(from:))
        // A NUP with no base game has only its updates: the selected one is taken as the whole game.
        guard SourceSelection.hasGame(files),
              let baseTitleId = UInt64(selection.titleId ?? "", radix: 16) else {
            presentBuildError(NXLibraryError.baseRequired)
            return
        }
        var detected = DetectedGame(
            baseTitleId: baseTitleId,
            name: selection.name,
            base: sources.first(where: { $0.kind == .base }),
            updates: sources.filter { $0.kind == .update },
            dlcs: sources.filter { $0.kind == .dlc }
        )
        let customName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customName.isEmpty { detected.name = customName }
        let useFolderMode = selectedGameFolder != nil
            && selectedPackageURLs == nil
            && detectedGames.count == 1
            && files.count == selection.files.count
            && files.allSatisfy { $0.layout == .package }
        do {
            let game = try addGame(
                detected: detected,
                selected: sources,
                folder: useFolderMode ? selectedGameFolder : nil,
                bundleId: bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            // Existing titles start Review with their saved settings. The
            // values the user confirms are the values used at the next launch.
            if let gameSettings = gameSettings(for: game) {
                try gameSettings.migrate()
                try gameSettings.apply(pendingRuntimeConfig, changedFrom: gameSettings.runtimeConfig())
            } else {
                try pendingRuntimeConfig.save(for: game)
            }
            librarySelection.selectedGameID = game.id
            logs.append(LogEntry(level: .success, message: "Added \(game.name) to the library."))
            if buildNow, canStartBuild {
                startBuild(for: game)
            } else {
                resetWizard()
            }
        } catch {
            presentBuildError(error)
        }
    }

    @discardableResult
    public func addGame(detected: DetectedGame, selected: [DetectedSource],
                        folder: URL?, bundleId: String? = nil) throws -> PortedGame {
        let selectedGame = DetectedGame(
            baseTitleId: detected.baseTitleId,
            name: detected.name,
            base: selected.first(where: { $0.kind == .base }),
            updates: selected.filter { $0.kind == .update },
            dlcs: selected.filter { $0.kind == .dlc }
        )
        guard selectedGame.hasGame else { throw NXLibraryError.baseRequired }
        let mode: WorkspaceMode = folder.map { .folder($0) } ?? .staged
        // Made where its build will run (`BuildScratch`), so the first build never moves it.
        let root = BuildScratch.choose(core: core, appFolder: gameAppsFolder).workspaces
        let workspace = try WorkspaceManager(root: root).makeWorkspace(for: selectedGame, mode: mode)
        let titleId = String(format: "%016llX", detected.baseTitleId)
        let updateVersion = selected.filter { $0.kind == .update }
            .compactMap { $0.version }.max().map(String.init)

        var game = PortedGame(
            name: detected.name,
            url: workspace.buildCache.deletingLastPathComponent(),
            platform: .macApp,
            sizeBytes: selectedGame.totalSizeBytes,
            modificationDate: Date(),
            bundleId: bundleId ?? "org.nxnative.\(titleId.lowercased())",
            titleId: titleId,
            versionString: updateVersion
        )
        game.sources = selected.map {
            GameFileItem(url: $0.url, kind: $0.kind,
                         titleId: String(format: "%016llX", $0.titleId),
                         versionString: $0.version.map(String.init),
                         sizeBytes: $0.sizeBytes, isSymlink: folder == nil, sourceLayout: $0.layout,
                         requiresTitleSelection: $0.requiresTitleSelection)
        }
        game.workspacePath = workspace.directory.path
        game.buildCachePath = workspace.buildCache.path
        game.status = .notBuilt
        game.settings = pendingRuntimeConfig

        let library = try libraryStore.merge(scanned: [game], replacingSources: true)
        libraryGames = library.games.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return library.games.first(where: { $0.titleId == titleId }) ?? game
    }

    public func startBuild(for game: PortedGame, extraArguments: [String] = []) {
        do {
            try beginBuild(for: game, extraArguments: extraArguments)
        } catch {
            presentBuildError(error)
        }
    }

    private func beginBuild(for game: PortedGame, extraArguments: [String] = []) throws {
        guard !isBuilding else { throw NXLibraryError.buildAlreadyRunning }
        guard !isUpdatingApp else { throw NXLibraryError.environmentBlocked("wait for the app update to finish") }
        guard !appIconsInFlight.contains(game.id) else {
            throw NXLibraryError.environmentBlocked("wait for the app icon update to finish")
        }
        var target = libraryGames.first(where: { $0.id == game.id }) ?? game
        guard let titleId = target.titleId,
              UInt64(titleId, radix: 16) != nil else {
            throw NXLibraryError.missingTitleId
        }
        guard !target.sources.isEmpty,
              SourceSelection.hasGame(target.sources),
              target.sources.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) }) else {
            throw NXLibraryError.missingSources
        }
        // Snapshot the destination before any build work. Changing folders later cannot redirect this build.
        let finalApp = finalAppURL(for: target)
        if let problem = GameAppDestination.folderProblem(at: finalApp.deletingLastPathComponent()) {
            throw NXLibraryError.environmentBlocked(problem)
        }
        let requiresKeys = SourceSelection.requiresKeys(target.sources)
        guard supportsSources(target.sources) else {
            throw NXLibraryError.environmentBlocked("These sources need an engine with extracted-folder or multi-title support.")
        }
        if requiresKeys {
            guard isProdKeysValid, FileManager.default.fileExists(atPath: keyStore.keyURL.path) else {
                throw NXLibraryError.missingKeys
            }
            // A few kilobytes per file: keys that cannot open the game stop here, not minutes into the extraction.
            let keyOutcome = KeyCheck.run(keysURL: keyStore.keyURL,
                                          files: KeyCheck.parts(target.sources.map { ($0.kind, $0.url) }))
            if keyOutcome.blocks, let reason = PortingFailureReason.from(keyOutcome) {
                throw NXLibraryError.keyCheck(reason, game: target.name)
            }
        } else if !engineSourceCapabilities.extractedFolders {
            throw NXLibraryError.environmentBlocked("This engine does not support extracted folders.")
        }
        guard isNxnativeValid else { throw NXLibraryError.engineMissing }
        guard let environmentStatus else {
            throw NXLibraryError.environmentBlocked("the environment check is still running")
        }
        guard environmentStatus.canBuild else {
            throw NXLibraryError.environmentBlocked(environmentStatus.issues.joined(separator: "; "))
        }

        // Re-check at build time: the engine tree, Metal compiler or CLI may
        // have changed since the last Settings/launch check.
        let checker = CompatibilityChecker(
            repoURL: URL(fileURLWithPath: nxnativePath),
            toolchain: engineToolchain,
            developerDir: resolvedDeveloperDir()
        )
        let report = try? checker.check(expectedEngineCommit: activeEngineCommit)
        compatibilityReport = report
        if report?.ok != true && !allowUntestedToolchain {
            let reason = report?.checks.filter { $0.status == .block }
                .map { "\($0.title): \($0.detail)" }.joined(separator: "; ")
                ?? "the compatibility check is unavailable"
            throw NXLibraryError.incompatibleToolchain(reason)
        }
        environmentCheckGeneration = UUID()
        isCheckingEnvironment = false
        let certified = report?.ok == true && !allowUntestedToolchain && !usesNewestEngine
        activeBuildToolchain = ToolchainInfo(engineCommit: activeEngineCommit,
            metalVersion: environmentStatus.metalVersion, xcodeVersion: environmentStatus.xcodeVersion,
            verified: certified,
            note: certified ? "Certified toolchain"
                : usesNewestEngine ? "Newest engine, not yet tested by NX Library"
                : "Untested toolchain (explicit override)")

        let merged = try libraryStore.merge(scanned: [target])
        libraryGames = merged.games.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard let stored = merged.games.first(where: { $0.titleId == titleId }) else {
            throw NXLibraryError.missingSources
        }
        target = stored
        buildPreviousStatus = target.status
        currentBuildGameID = target.id
        lastBuildGameID = target.id

        let workspace: Workspace
        let existingDirectory = target.workspacePath.map { URL(fileURLWithPath: $0) }
        let existingNames = Set(existingDirectory.flatMap {
            (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? []
        } ?? [])
        let expectedNames = target.sources.map { $0.url.lastPathComponent }
        let existingLinksOK = existingDirectory.map { directory in
            FileManager.default.fileExists(atPath: directory.path)
                && workspaceManager.brokenLinks(in: directory).isEmpty
                && expectedNames.allSatisfy { existingNames.contains($0) }
        } ?? false
        // On the app's drive when it can hold builds: the Mac's disk needs no room, the install is a rename.
        let scratch = BuildScratch.choose(core: core, appFolder: finalApp.deletingLastPathComponent(),
                                          existingWorkspace: existingDirectory)
        let managed = existingDirectory.map { BuildScratch.isManaged($0, core: core) } ?? false
        if let directory = existingDirectory, existingLinksOK, !managed,
           target.sources.allSatisfy({ $0.layout == .package }) {
            let cache = target.buildCachePath.map(URL.init(fileURLWithPath:))
                ?? directory.appendingPathComponent("\(titleId)_build")
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            workspace = Workspace(directory: directory, buildCache: cache, links: [])
        } else {
            let detected = try detectedGame(from: target)
            workspace = try WorkspaceManager(root: scratch.workspaces).makeWorkspace(for: detected, mode: .staged)
            // A workspace NX Library left on another drive is only a cache now: that drive gets its room back.
            // A game not built yet still points at its workspace, which then stays.
            if let old = existingDirectory, managed,
               old.resolvingSymlinksInPath() != workspace.directory.resolvingSymlinksInPath(),
               !target.url.standardizedFileURL.path.hasPrefix(old.standardizedFileURL.path) {
                DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: old) }
            }
            target.workspacePath = workspace.directory.path
            target.buildCachePath = workspace.buildCache.path
        }

        if var library = try? libraryStore.load(),
           let index = library.games.firstIndex(where: { $0.id == target.id }) {
            library.games[index].workspacePath = target.workspacePath
            library.games[index].buildCachePath = target.buildCachePath
            do { try libraryStore.save(library) } catch { reportLibrarySaveFailure(error) }
            libraryGames = library.games.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        let requiredDisk = SourceSelection.uniqueSize(target.sources) * 2 + 10_000_000_000
        var measured = Set<UInt64>()
        for volume in [workspace.directory, scratch.temp, finalApp.deletingLastPathComponent()] {
            if let device = BuildScratch.Volume.of(volume)?.device, !measured.insert(device).inserted { continue }
            if let free = freeBytes(at: volume), free < requiredDisk {
                let freeText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                let requiredText = ByteCountFormatter.string(
                    fromByteCount: requiredDisk, countStyle: .file)
                let why = scratch.appDriveUnsupported
                    ? " The Game apps folder's drive can't hold build files (it needs APFS or Mac OS Extended), so the build uses this Mac's disk."
                    : ""
                throw NXLibraryError.environmentBlocked(
                    "Not enough free space at \(volume.path): \(freeText) available, \(requiredText) needed.\(why)")
            }
        }

        let repo = URL(fileURLWithPath: nxnativePath)
        let toolchain = engineToolchain
        guard FileManager.default.isExecutableFile(atPath: toolchain.python.path) else {
            throw NXLibraryError.environmentBlocked(toolchain.isBundled
                ? "the bundled Python is missing; reinstall NX Library"
                : "the nxnative venv Python is missing")
        }

        let tempRoot = scratch.temp.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let tempApp = tempRoot.appendingPathComponent(finalApp.lastPathComponent)
        let logURL = core.appendingPathComponent("Logs").appendingPathComponent("\(titleId).log")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let command = BuildCommandBuilder.make(
            repo: repo,
            toolchain: toolchain,
            workspace: workspace.directory,
            keys: requiresKeys ? keyStore.keyURL : nil,
            output: tempApp,
            developerDir: resolvedDeveloperDir(),
            appName: target.name,
            bundleId: target.bundleId ?? "org.nxnative.\(titleId.lowercased())",
            language: loadRuntimeConfig(for: target).languageForBuild,
            titleId: engineSourceCapabilities.titleSelection ? titleId : nil,
            packageVersion: engineSourceCapabilities.titleSelection ? SourceSelection.versionForBuild(target.sources) : nil,
            allowUntestedToolchain: allowUntestedToolchain,
            extraArguments: extraArguments
        )
        lastPortingCommand = [command.executable.path] + command.arguments

        buildStartedAt = Date()
        buildTempDirectory = tempRoot
        buildLogURL = logURL
        buildWizardStep = 3
        isBuilding = true
        isCancellingBuild = false
        buildState = .running
        buildError = nil
        portingFailureReason = nil
        lastError = nil
        buildSuccessPath = nil
        buildHeldGameID = nil
        progressFraction = 0
        currentStageName = "Preparing build"
        currentStepName = ""
        stageIndex = 0
        totalStages = 0
        etaSeconds = nil
        buildStages.removeAll()
        portingProgress = PortingProgress()
        frontGameID = target.id
        logs.append(LogEntry(level: .info,
                             message: "Build started for \(target.name) (\(titleId))."))
        logs.append(LogEntry(level: .info,
                             message: "Workspace: \(workspace.directory.path)"))
        logs.append(LogEntry(
            level: .info,
            message: report?.ok == true
                ? "Toolchain gate: certified."
                : "Toolchain gate: overridden; this build will be recorded as untested."
        ))

        let service = BuildService()
        buildService = service
        service.start(
            command: command,
            logURL: logURL,
            tempApp: tempApp,
            finalApp: finalApp,
            // Replacing the app under its running game can crash it: the new app waits for the game to quit.
            holdInstall: { RunningGameMonitor.runningApplication(for: target) != nil },
            acquireInstall: { [weak self] in self?.acquireSaveInstallLease(for: target) },
            eventHandler: { [weak self] event in
                DispatchQueue.main.async { self?.handleBuildEvent(event) }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    self?.finishBuild(result, gameID: target.id,
                                      finalApp: finalApp, tempDir: tempRoot)
                }
            }
        )
    }

    public func cancelBuild() {
        guard isBuilding, let buildService else { return }
        isCancellingBuild = true
        currentStageName = "Cancelling build..."
        logs.append(LogEntry(level: .warning, message: "Cancelling build..."))
        buildService.cancel()
    }

    public func openOutputInFinder() {
        guard let path = buildSuccessPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    public func openBuildLog() {
        guard let url = buildLogURL else {
            lastError = "No build log is available yet."
            logs.append(LogEntry(level: .warning, message: lastError!))
            return
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        }
    }

    public func retryLastBuild() {
        guard let id = lastBuildGameID,
              let game = libraryGames.first(where: { $0.id == id }) else {
            lastError = "The last built game is no longer in the library."
            logs.append(LogEntry(level: .error, message: lastError!))
            return
        }
        if canRetryReadyInstall {
            installPendingBuilds(only: id)
            return
        }
        startBuild(for: game)
    }

    private func handleBuildEvent(_ event: BuildEvent) {
        portingProgress?.apply(event)
        switch event {
        case .stage(let k, let n, let name, let step):
            currentStageName = name
            stageIndex = k
            totalStages = n
            for index in buildStages.indices
            where buildStages[index].id < k && buildStages[index].isRunning {
                buildStages[index].isRunning = false
                buildStages[index].isCompleted = true
            }
            if let index = buildStages.firstIndex(where: { $0.id == k }) {
                buildStages[index].isRunning = true
                buildStages[index].step = step ?? ""
            } else {
                buildStages.append(BuildStageItem(id: k, name: name,
                                                  step: step ?? "", isRunning: true))
            }
            if let step, !step.isEmpty { currentStepName = step }
            logs.append(LogEntry(level: .step, message: "[\(k)/\(n)] \(name)"))

        case .step(let step):
            currentStepName = step
            if let index = buildStages.firstIndex(where: { $0.id == stageIndex }) {
                buildStages[index].step = step
            }
            logs.append(LogEntry(level: .info, message: "↳ \(step)"))

        case .progress(let fraction, let done, let total, let unit, let eta):
            progressFraction = min(max(fraction, 0), 1)
            etaSeconds = eta
            if let done, let total, total > 0 {
                if let unit, !unit.isEmpty,
                   unit.lowercased() != "b", unit.lowercased() != "bytes" {
                    currentStepName = "\(Self.formatAmount(done)) / \(Self.formatAmount(total)) \(unit)"
                } else {
                    let doneText = ByteCountFormatter.string(
                        fromByteCount: Int64(done), countStyle: .file)
                    let totalText = ByteCountFormatter.string(
                        fromByteCount: Int64(total), countStyle: .file)
                    currentStepName = "\(doneText) / \(totalText)"
                }
            }

        case .stageEnd(let name, let ok, let elapsed, let summary, let warn):
            let warned = ok && warn
            if let index = buildStages.firstIndex(where: { $0.name == name })
                ?? buildStages.firstIndex(where: { $0.isRunning }) {
                buildStages[index].isRunning = false
                buildStages[index].isCompleted = ok
                buildStages[index].isFailed = !ok
                buildStages[index].hasWarning = warned
                buildStages[index].elapsedSeconds = elapsed
                buildStages[index].summary = summary
            }
            logs.append(LogEntry(
                level: warned ? .warning : ok ? .success : .error,
                message: "\(warned ? "⚠" : ok ? "✓" : "✗") \(name)\(summary.map { " — \($0)" } ?? "")"
            ))

        case .say(let message):
            logs.append(LogEntry(level: .info, message: message))

        case .log(let line):
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                logs.append(LogEntry(level: .info, message: trimmed))
            }
        }
    }

    private func finishBuild(_ result: BuildResult, gameID: UUID,
                             finalApp: URL, tempDir: URL) {
        portingProgress?.finish(success: result.success)
        isBuilding = false
        isCancellingBuild = false
        buildService = nil
        if result.heldApp == nil { try? FileManager.default.removeItem(at: tempDir) }
        buildTempDirectory = nil

        var library = (try? libraryStore.load()) ?? LibraryFile(games: libraryGames)
        if let index = library.games.firstIndex(where: { $0.id == gameID }) {
            var game = library.games[index]
            let toolchain = activeBuildToolchain ?? ToolchainInfo(engineCommit: activeEngineCommit, verified: false)
            let verified = toolchain.verified
            let record = BuildRecord(
                startedAt: buildStartedAt ?? Date(),
                endedAt: Date(),
                exitCode: result.exitCode,
                logPath: result.logURL.path,
                outputPath: result.success || result.installationFailed ? finalApp.path : nil,
                engineCommit: toolchain.engineCommit ?? activeEngineCommit,
                metalVersion: toolchain.metalVersion,
                xcodeVersion: toolchain.xcodeVersion,
                toolchainVerified: verified,
                cancelled: result.cancelled
            )

            if result.success || result.installationFailed {
                if let held = result.heldApp {
                    PendingInstaller.hold(PendingInstall(tempApp: held, finalApp: finalApp,
                                                         record: record, toolchain: toolchain), for: &game)
                    buildHeldGameID = game.id
                } else {
                    PendingInstaller.discard(&game)
                    game.recordInstalledBuild(record, toolchain: toolchain, at: finalApp,
                                              version: Self.appVersion(at: finalApp), date: Date())
                    // A new app has the build's icon: the player's goes back on (AppViewModel+AppIcon).
                    game.appIconPending = true
                }
                if let seconds = portingProgress?.finishingElapsed, seconds > 0 {
                    lastPortingFinishSeconds = seconds
                }
                progressFraction = 1
                currentStageName = result.heldApp == nil ? "Build completed" : PendingInstall.stageName
                if result.installationFailed {
                    currentStageName = "Installation failed"
                    buildState = .failed
                    buildSuccessPath = nil
                    buildError = "The build is ready. Retry installation."
                    portingFailureReason = nil
                    lastError = result.error
                    presentInstallFailure(for: game, error: result.error ?? "Installation failed.")
                } else {
                    buildState = .succeeded
                    buildSuccessPath = finalApp.path
                    buildError = nil
                    lastError = nil
                    logs.append(LogEntry(level: .success, message: result.heldApp == nil
                        ? "Build succeeded: \(finalApp.path)"
                        : "Build succeeded while \(game.name) is open: it installs when the game quits."))
                    SoundEffectService.shared.play(.launch)
                    notifyPortingEnded(game, success: true, held: result.heldApp != nil)
                }
            } else if result.cancelled {
                game.status = buildPreviousStatus
                    ?? (game.sources.isEmpty ? .builtSourcesMissing : .notBuilt)
                game.portingFailure = .cancelled
                game.portingFailureReason = nil
                buildState = .cancelled
                buildError = nil
                portingFailureReason = nil
                lastError = "Build cancelled."
                logs.append(LogEntry(level: .warning, message: "Build cancelled."))
            } else {
                let reason = PortingFailureClassifier.classify(
                    log: buildLogTail(result.logURL),
                    keysPath: keyStore.keyURL.path,
                    sourcePaths: game.sources.map(\.url.path)
                )
                let message = reason.what(game: game.name)
                game.status = .failed
                game.portingFailure = .failed
                game.portingFailureReason = reason
                buildState = .failed
                buildError = message
                portingFailureReason = reason
                lastError = message
                logs.append(LogEntry(level: .error,
                                     message: result.error ?? "Build failed (exit code \(result.exitCode))."))
                logs.append(LogEntry(level: .error, message: "\(reason.title). \(message) \(reason.next)"))
                SoundEffectService.shared.play(.error)
                notifyPortingEnded(game, success: false)
            }

            library.games[index] = game
            var saved = true
            do {
                try libraryStore.save(library)
            } catch {
                saved = false
                if game.pendingInstall != nil {
                    presentInstallFailure(for: game, error: error.localizedDescription)
                } else {
                    logs.append(LogEntry(level: .error, message: "Could not save the library: \(error.localizedDescription)"))
                }
            }
            libraryGames = library.games.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if result.success && saved {
                loadLibrary()
                syncPendingAppIcons()
            }
        } else {
            buildState = result.success ? .succeeded
                : (result.cancelled ? .cancelled : .failed)
            if !result.success && !result.cancelled {
                buildError = result.error
                lastError = result.error
            }
        }

        buildStartedAt = nil
        buildPreviousStatus = nil
        currentBuildGameID = nil
        activeBuildToolchain = nil
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
            logs.append(LogEntry(level: .warning, message: "No log path is known for \(game.name)."))
            return
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
            logs.append(LogEntry(level: .info,
                                 message: "No log yet for \(game.name); opened the log folder."))
        }
    }

    private func presentBuildError(_ error: Error) {
        let message = error.localizedDescription
        buildState = .failed
        buildError = message
        if case .keyCheck(let reason, _) = error as? NXLibraryError {
            portingFailureReason = reason
        } else {
            portingFailureReason = nil
        }
        lastError = message
        alertMessage = message
        logs.append(LogEntry(level: .error, message: message))
        SoundEffectService.shared.play(.error)
    }

    private static func formatAmount(_ value: Double) -> String {
        if value.rounded() == value { return String(format: "%.0f", value) }
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    private func detectedGame(from game: PortedGame) throws -> DetectedGame {
        let sources = game.sources.compactMap { item -> DetectedSource? in
            guard let titleId = item.titleId.flatMap({ UInt64($0, radix: 16) }) else {
                return nil
            }
            let version = item.versionString.flatMap {
                Int($0.lowercased().hasPrefix("v") ? String($0.dropFirst()) : $0)
            }
            return DetectedSource(url: item.url, kind: item.kind, titleId: titleId,
                                  version: version, sizeBytes: item.sizeBytes, layout: item.layout,
                                  requiresTitleSelection: item.requiresTitleSelection == true)
        }
        guard let titleId = game.titleId.flatMap({ UInt64($0, radix: 16) }) else {
            throw NXLibraryError.missingTitleId
        }
        let detected = DetectedGame(baseTitleId: titleId, name: game.name,
                                    base: sources.first(where: { $0.kind == .base }),
                                    updates: sources.filter { $0.kind == .update },
                                    dlcs: sources.filter { $0.kind == .dlc })
        guard detected.hasGame else { throw NXLibraryError.baseRequired }
        return detected
    }

    private static func detectedSource(from file: GameFileItem) -> DetectedSource? {
        guard let titleId = file.titleId.flatMap({ UInt64($0, radix: 16) }) else {
            return nil
        }
        let version = file.versionString.flatMap {
            Int($0.lowercased().hasPrefix("v") ? String($0.dropFirst()) : $0)
        }
        return DetectedSource(url: file.url, kind: file.type, titleId: titleId,
                              version: version, sizeBytes: file.sizeBytes, layout: file.layout,
                              requiresTitleSelection: file.requiresTitleSelection == true)
    }

    private func finalAppURL(for game: PortedGame) -> URL {
        GameAppDestination.url(for: game, in: gameAppsFolder)
    }

    private static func appVersion(at app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return object["CFBundleShortVersionString"] as? String
    }


}
