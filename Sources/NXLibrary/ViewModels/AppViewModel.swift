import Foundation
import SwiftUI
import AppKit
import NXLibraryCore

public final class AppViewModel: ObservableObject {
    // MARK: - Storage Keys for Persistence
    private enum StorageKeys {
        static let savedGameFolder = "NXNative_SavedGameFolder"
        static let lastPortingFinishSeconds = "NXLibrary.lastPortingFinishSeconds"
        static let savedLibraryFolder = "NXNative_SavedLibraryFolder"
        static let savedProdKeysPath = "NXNative_SavedProdKeysPath"
        static let savedIconAppearanceMode = "NXNative_SavedIconAppearanceMode"
        static let allowUntestedToolchain = "NXLibrary_AllowUntestedToolchain"
        static let setupCompleted = "NXLibrary_SetupCompleted"
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
                UserDefaults.standard.set(folder.path, forKey: StorageKeys.savedGameFolder)
                scanGameFolder(folder)
            } else {
                if !keepsRememberedGameFolder {
                    UserDefaults.standard.removeObject(forKey: StorageKeys.savedGameFolder)
                }
                scanGeneration = UUID()
                detectedGames = []
                selectedGame = nil
                selectedSourceIDs = []
                scanError = nil
                isScanningGameFolder = false
            }
        }
    }
    private var keepsRememberedGameFolder = false
    @Published public var detectedGames: [SelectableGame] = []
    @Published public var selectedGame: SelectableGame? = nil {
        didSet {
            if let game = selectedGame {
                self.appName = game.name
                self.bundleId = ""
                resetSourceSelection(for: game)
            } else {
                selectedSourceIDs = []
                appName = ""
                bundleId = ""
            }
        }
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
    @Published public var isScanningGameFolder: Bool = false
    @Published public var scanError: String? = nil
    
    // MARK: - Disk Capacity Pre-flight
    public func freeBytes(at url: URL) -> Int64? {
        let fm = FileManager.default
        let target = fm.fileExists(atPath: url.path)
            ? url
            : url.deletingLastPathComponent()
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

    public var availableOutputDiskBytes: Int64? {
        freeBytes(at: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications"))
    }

    /// The wizard reserves space for both the extracted cache and the temporary
    /// app. Use the tighter of the source/cache volume and the output volume.
    public var availableBuildDiskBytes: Int64? {
        [availableDiskBytes, availableOutputDiskBytes].compactMap { $0 }.min()
    }
    
    public var selectedSources: [GameFileItem] {
        guard let game = selectedGame else { return [] }
        return game.files.filter { selectedSourceIDs.contains($0.id) }
    }
    
    public var selectedSourcesSizeBytes: Int64 {
        selectedSources.reduce(0) { $0 + $1.sizeBytes }
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
        return game.hasBase
            && selectedSources.contains(where: { $0.type == .base })
            && selectedSourcesSizeBytes > 0
            && !isAddDiskSpaceLow
    }
    
    public func resetSourceSelection(for game: SelectableGame) {
        var ids = Set<UUID>()
        if let base = game.baseFile { ids.insert(base.id) }
        if let update = game.newestUpdate { ids.insert(update.id) }
        for dlc in game.files where dlc.type == .dlc && dlc.sizeBytes > 0 {
            ids.insert(dlc.id)
        }
        selectedSourceIDs = ids
    }
    
    public func toggleSource(_ item: GameFileItem) {
        guard let game = selectedGame,
              let file = game.files.first(where: { $0.id == item.id }) else { return }
        if file.type == .base { return }
        if selectedSourceIDs.contains(file.id) {
            selectedSourceIDs.remove(file.id)
        } else {
            if file.type == .update {
                selectedSourceIDs.subtract(
                    game.files.filter { $0.type == .update }.map(\.id)
                )
            }
            selectedSourceIDs.insert(file.id)
        }
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
    @Published public var isScanningLibrary: Bool = false
    @Published public var gameForSettingsSheet: PortedGame? = nil
    /// Where the open Game options came from; decides its rows (Move is Spotlight-only).
    @Published public var gameOptionsOrigin: GameOptionsOrigin = .collection
    /// The running game whose Close Game confirmation is open. The shell draws the dialog.
    @Published public var gameToClose: PortedGame? = nil
    @Published var closeGameFocus: SeleneConfirmButton = .cancel
    @Published public var pendingRuntimeConfig = GameRuntimeConfig()
    private var lastAddGameDefaults = GameRuntimeConfig()
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
    @Published public var setupCompleted: Bool = false
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
    
    // MARK: - Advanced Options
    @Published public var appName: String = ""
    @Published public var bundleId: String = ""
    @Published public var selectedLanguage: String = "auto"
    
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

    public let pinnedEngineCommit = "ee369f09984f23adbe003f55e94be5d81cd8c0e6"
    private let core = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NXLibrary")
    private lazy var libraryStore = LibraryStore(directory: core)
    lazy var keyStore = KeyStore(directory: core.appendingPathComponent("keys"))
    private let importService = ImportService()
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
    private var activeBuildToolchainVerified = false
    private var buildStartedAt: Date?
    private var buildTempDirectory: URL?
    
    public init() {
        let didCompleteSetup = UserDefaults.standard.bool(forKey: StorageKeys.setupCompleted)
        self.setupCompleted = didCompleteSetup
        self.showSetupCheck = !didCompleteSetup
        
        // 1. Resolve safe root directory (anchored to SSD / Bundle, NEVER "/")
        let root = SystemDetector.shared.resolveRootDirectory()
        self.defaultInstallPath = root.path
        
        // The launcher's old ~/Games default is not a Mac-app library.
        let oldGamesDefault = root.appendingPathComponent("Games").standardized.path
        if let savedLib = UserDefaults.standard.string(forKey: StorageKeys.savedLibraryFolder),
           savedLib != oldGamesDefault,
           FileManager.default.fileExists(atPath: savedLib) {
            self.libraryFolder = URL(fileURLWithPath: savedLib)
        } else {
            self.libraryFolder = root.appendingPathComponent("Applications")
            UserDefaults.standard.removeObject(forKey: StorageKeys.savedLibraryFolder)
        }
        
        // Restore user preferences
        if let savedMode = UserDefaults.standard.string(forKey: StorageKeys.savedIconAppearanceMode),
           let mode = AppIconAppearanceMode(rawValue: savedMode) {
            self.iconAppearanceMode = mode
        }
        if UserDefaults.standard.object(forKey: StorageKeys.allowUntestedToolchain) != nil {
            self.allowUntestedToolchain = UserDefaults.standard.bool(forKey: StorageKeys.allowUntestedToolchain)
        }
        
        detectEnvironment()
        
        // Restore saved game folder if it exists
        if let savedGamePath = UserDefaults.standard.string(forKey: StorageKeys.savedGameFolder) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: savedGamePath, isDirectory: &isDir), isDir.boolValue {
                self.selectedGameFolder = URL(fileURLWithPath: savedGamePath)
            }
        }
        
        loadLibrary()
        if let data = UserDefaults.standard.data(forKey: upstreamCacheKey),
           let cached = try? JSONDecoder().decode(UpstreamStatus.self, from: data),
           cached.baseCommit == pinnedEngineCommit {
            self.upstreamState = .loaded(cached)
        }
        updateDockIcon()
        
        NotificationService.shared.requestAuthorization()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.sweepStaleBuildTemp()
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
        let nxResult = SystemDetector.shared.detectNxnativeDirectory()
        self.nxnativePath = nxResult.path
        self.isNxnativeValid = nxResult.isValid
        ensureKeysImported(customRyujinxDir: customRyujinxDir)
        refreshCompatibility()
    }

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
        do {
            let summary = try keyStore.importKey(from: url)
            keySummary = summary
            isProdKeysValid = summary.hasHeaderKey
            prodKeysPath = keyStore.keyURL.path
            prodKeysSource = "Imported once"
            refreshKeyCheck()
            lastError = nil
            logs.append(LogEntry(
                level: .success,
                message: "prod.keys imported: header key present, \(summary.applicationKeyGenerations.count) application key generations."
            ))
        } catch {
            keySummary = nil
            isProdKeysValid = false
            lastError = error.localizedDescription
            logs.append(LogEntry(level: .error,
                                 message: "Could not import prod.keys: \(error.localizedDescription)"))
        }
    }

    public func refreshCompatibility() {
        guard isNxnativeValid, !nxnativePath.isEmpty else {
            compatibilityReport = nil
            environmentStatus = nil
            return
        }
        let repo = URL(fileURLWithPath: nxnativePath)
        let toolchain = engineToolchain
        let developerDir = resolvedDeveloperDir()
        let expected = pinnedEngineCommit
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let environment = NXNativeEnvironment(repoURL: repo, toolchain: toolchain,
                                                  developerDir: developerDir)
            let status = environment.inspect()
            let checker = CompatibilityChecker(repoURL: repo, toolchain: toolchain,
                                               developerDir: developerDir)
            let report = try? checker.check(expectedEngineCommit: expected)
            let currentCommit = report?.checks.first(where: { $0.id == "commit" })?.detail
                .components(separatedBy: ", expected").first?
                .replacingOccurrences(of: "current ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self?.environmentStatus = status
                self?.compatibilityReport = report
                self?.currentEngineCommit = (currentCommit?.isEmpty == false) ? currentCommit : nil
                if let report, !report.ok {
                    let blocked = report.checks.filter { $0.status == .block }
                        .map { "\($0.title): \($0.detail)" }.joined(separator: " | ")
                    self?.logs.append(LogEntry(level: .warning, message: "Toolchain gate: \(blocked)"))
                }
            }
        }
    }

    public func checkUpstreamChangelog() {
        if case .checking = upstreamState { return }
        let base = currentEngineCommit ?? pinnedEngineCommit
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
        storeMetadata[game.id] = MetadataPicks.shared.applied(to: metadata, titleID: game.titleId ?? game.uniqueKey)
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
            && isProdKeysValid
            && environmentStatus?.canBuild == true
            && libraryFolder != nil
    }

    public func completeSetup() {
        setupCompleted = true
        showSetupCheck = false
        UserDefaults.standard.set(true, forKey: StorageKeys.setupCompleted)
        logs.append(LogEntry(level: .success, message: "Setup completed."))
    }

    public func reopenSetup() {
        showSetupCheck = true
    }

    private func sweepStaleBuildTemp() {
        let temp = core.appendingPathComponent("Temp")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: temp, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for item in items {
            let date = (try? item.resourceValues(
                forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date.distantPast
            if date < cutoff { try? FileManager.default.removeItem(at: item) }
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

    public func backupSave(for game: PortedGame) {
        let profile = GameDetailsProfile.inspect(for: game)
        guard profile.saveExists else {
            lastError = "No save folder exists for \(game.name)."
            logs.append(LogEntry(level: .warning, message: lastError!))
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(game.name) save.zip"
        panel.title = "Back Up Save"
        panel.prompt = "Back Up"
        if panel.runModal() == .OK, let destination = panel.url {
            do {
                try storageManager.backupSave(for: game, to: destination)
                logs.append(LogEntry(level: .success,
                                     message: "Save backed up to \(destination.path)"))
            } catch {
                lastError = error.localizedDescription
                logs.append(LogEntry(level: .error,
                                     message: "Save backup failed: \(error.localizedDescription)"))
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

    public func loadLibrary() {
        guard !isScanningLibrary else { return }
        isScanningLibrary = true
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var directories = [home.appendingPathComponent("Applications")]
        if let libraryFolder, !libraryFolder.path.isEmpty, libraryFolder.path != "/",
           !directories.contains(where: { $0.standardizedFileURL == libraryFolder.standardizedFileURL }) {
            directories.append(libraryFolder)
        }
        let store = libraryStore
        let importer = importService
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = (try? store.load()) ?? LibraryFile()
            let scanned = importer.scan(directories: directories)
            let importedGames = scanned.map { importer.makeGame(from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.importedApps = scanned
                var scannedByTitle: [String: ImportedApp] = [:]
                for app in scanned {
                    if let titleId = app.titleId {
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
                    let sourcesExist = !library.games[index].sources.isEmpty
                        && library.games[index].sources.allSatisfy { fm.fileExists(atPath: $0.url.path) }
                    if !appExists {
                        library.games[index].status = .appMissing
                    } else if !sourcesExist {
                        if library.games[index].sources.isEmpty
                            || library.games[index].status == .built
                            || library.games[index].status == .builtSourcesMissing
                            || library.games[index].status == .needsRebuild {
                            library.games[index].status = .builtSourcesMissing
                        }
                    } else if library.games[index].status == .builtSourcesMissing
                                || library.games[index].status == .needsRebuild
                                || library.games[index].status == .appMissing {
                        library.games[index].status = .built
                    }
                }
                try? store.save(library)
                self.libraryGames = library.games.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                self.isScanningLibrary = false
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = Self.sourceFileURLs(in: folder)
            let readable = urls.filter { (try? catalog.inspect($0)) != nil }
            let detected = (try? catalog.scan(files: readable)) ?? []
            let match = detected.first {
                String(format: "%016llX", $0.baseTitleId)
                    .caseInsensitiveCompare(titleId) == .orderedSame
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanningGameFolder = false
                guard let match, let base = match.base else {
                    self.alertMessage = "No base, update or DLC files for \(game.name) were found in that folder."
                    self.logs.append(LogEntry(level: .warning, message: self.alertMessage!))
                    return
                }
                var selected = [base]
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
        panel.prompt = "Select Library Folder"
        panel.message = "Choose a folder containing built Mac apps."

        if panel.runModal() == .OK, let url = panel.url {
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
        guard game.isPlayableLocally else {
            let message = "This game is not built yet. Add sources and build it first."
            lastError = message
            alertMessage = message
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: message))
            return
        }
        guard FileManager.default.fileExists(atPath: game.url.path) else {
            lastError = NXLibraryError.appMissing(game.url.path).localizedDescription
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

        launchingGameId = game.id
        launchOverlay = LaunchOverlayState(game: game)
        SoundEffectService.shared.play(.launch)

        let config = GameRuntimeConfig.load(for: game)
        do {
            try launchService.writeEnvironment(settings: config, titleId: titleId)
        } catch {
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
                // The game still starts; it keeps its save where it was.
                logs.append(LogEntry(level: .warning, message: "Cloud saves: \(error.localizedDescription)"))
            }
        }

        launchService.launch(appURL: game.url,
                             environment: config.toEnvironmentDict()) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
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
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.launchOverlay?.game.id == game.id else { return }
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
    public func openGameOptions(_ game: PortedGame, from origin: GameOptionsOrigin) {
        gameOptionsOrigin = origin
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
            alertMessage = error.localizedDescription
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

    private func updateStoredStatus(_ status: GameStatus, for game: PortedGame) {
        guard var library = try? libraryStore.load(),
              let index = library.games.firstIndex(where: { $0.id == game.id }) else { return }
        library.games[index].status = status
        try? libraryStore.save(library)
        libraryGames = library.games.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func loadRuntimeConfig(for game: PortedGame) -> GameRuntimeConfig {
        GameRuntimeConfig.load(for: game)
    }

    public func supportsSetting(_ env: String, for game: PortedGame) -> Bool {
        LauncherSettingsReader.supports(env, for: game.url)
    }

    public func launcherSettings(for game: PortedGame) -> LauncherSettingsFile? {
        LauncherSettingsReader.load(for: game.url)
    }

    public func saveRuntimeConfig(_ config: GameRuntimeConfig, for game: PortedGame) {
        config.save(for: game)
        logs.append(LogEntry(level: .success, message: "Saved settings for \(game.name)"))
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
        let workspaceRoot = core.appendingPathComponent("workspaces").standardizedFileURL.path
        let workspaceBytes: Int64
        if let path = game.workspacePath {
            let workspace = URL(fileURLWithPath: path).standardizedFileURL
            workspaceBytes = workspace.path.hasPrefix(workspaceRoot + "/")
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
        let workspaceRoot = core.appendingPathComponent("workspaces").standardizedFileURL.path
        if let path = game.workspacePath {
            let workspace = URL(fileURLWithPath: path).standardizedFileURL
            if workspace.path.hasPrefix(workspaceRoot + "/"),
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
            let workspaceRoot = core.appendingPathComponent("workspaces")
                .standardizedFileURL.path
            if let path = game.workspacePath {
                let workspace = URL(fileURLWithPath: path).standardizedFileURL
                if workspace.path.hasPrefix(workspaceRoot + "/"),
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
        scanError = nil
        isScanningGameFolder = true
        selectedGame = nil
        selectedSourceIDs = []
        let generation = UUID()
        scanGeneration = generation
        let catalog = sourceCatalog
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = Self.sourceFileURLs(in: folder)
            let readable = urls.filter { (try? catalog.inspect($0)) != nil }
            let detected = (try? catalog.scan(files: readable)) ?? []
            let games = detected.map(Self.selectableGame(from:))
            DispatchQueue.main.async {
                guard let self,
                      self.scanGeneration == generation,
                      self.selectedGameFolder?.standardizedFileURL == folder.standardizedFileURL else {
                    return
                }
                self.isScanningGameFolder = false
                self.detectedGames = games
                self.selectedGame = games.first
                if games.isEmpty {
                    self.scanError = urls.isEmpty
                        ? "No NSP, XCI, NSZ or XCZ files were found in this folder."
                        : "No readable game files were found. Check that the files are complete and have a title ID or ticket."
                    self.logs.append(LogEntry(level: .warning, message: self.scanError!))
                } else {
                    self.logs.append(LogEntry(level: .info,
                        message: "Detected \(games.count) game\(games.count == 1 ? "" : "s") in \(folder.lastPathComponent)."))
                }
            }
        }
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
                    sizeBytes: source.sizeBytes
                )
            }
        )
    }
    
    // MARK: - File Pickers
    public func selectNxnativeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select nxnative Folder"
        panel.message = "Choose the directory containing the nxnative scripts and tools."
        
        if panel.runModal() == .OK, let url = panel.url {
            let res = SystemDetector.shared.detectNxnativeDirectory(customDir: url.path)
            self.nxnativePath = res.path
            self.isNxnativeValid = res.isValid
            if res.isValid {
                        refreshCompatibility()
            }
        }
    }
    
    public func selectGameFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Game Folder"
        panel.message = "Select a folder holding your game NSP, NSZ, or XCI files."
        
        if panel.runModal() == .OK, let url = panel.url {
            self.selectedGameFolder = url
        }
    }
    
    public func selectProdKeysFile() {
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
            && canAddSelectedGame
            && isProdKeysValid
            && !keyCheckBlocks
            && isNxnativeValid
            && environmentStatus?.canBuild == true
            && !isDiskSpaceLow
            && canPassToolchainGate
    }

    public func canBuild(_ game: PortedGame) -> Bool {
        guard !isBuilding,
              isProdKeysValid,
              isNxnativeValid,
              environmentStatus?.canBuild == true,
              !game.sources.isEmpty,
              game.sources.contains(where: { $0.kind == .base }),
              game.sources.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) }) else {
            return false
        }
        let required = game.sources.reduce(0) { $0 + $1.sizeBytes } * 2 + 10_000_000_000
        if let titleId = game.titleId {
            let parent = finalAppURL(for: game, titleId: titleId).deletingLastPathComponent()
            if let free = freeBytes(at: parent), free < required { return false }
        } else if let free = availableOutputDiskBytes, free < required {
            return false
        }
        if let path = game.workspacePath,
           let free = freeBytes(at: URL(fileURLWithPath: path)), free < required {
            return false
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
        guard let titleId = game.titleId, !titleId.isEmpty else { return true }
        guard !nxnativePath.isEmpty else { return true }
        var isDirectory: ObjCBool = false
        let path = URL(fileURLWithPath: nxnativePath)
            .appendingPathComponent("dm/games/\(titleId)").path
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
    public func addGameDidBecomeVisible(defaults: GameRuntimeConfig, returningFromBack: Bool) {
        if isBuilding {
            buildWizardStep = 3
            addGameSessionActive = true
            return
        }
        if returningFromBack, addGameSessionActive { return }
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
        selectedLanguage = lastAddGameDefaults.language
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
        guard let baseFile = files.first(where: { $0.type == .base }),
              let baseSource = Self.detectedSource(from: baseFile),
              let baseTitleId = UInt64(selection.titleId ?? "", radix: 16) else {
            presentBuildError(NXLibraryError.baseRequired)
            return
        }
        let sources = files.compactMap(Self.detectedSource(from:))
        guard sources.contains(where: { $0.kind == .base }) else {
            presentBuildError(NXLibraryError.baseRequired)
            return
        }
        var detected = DetectedGame(
            baseTitleId: baseTitleId,
            name: selection.name,
            base: baseSource,
            updates: sources.filter { $0.kind == .update },
            dlcs: sources.filter { $0.kind == .dlc }
        )
        let customName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customName.isEmpty { detected.name = customName }
        let titleId = String(format: "%016llX", baseTitleId)
        let isNewGame = !libraryGames.contains {
            $0.titleId?.caseInsensitiveCompare(titleId) == .orderedSame
        }
        let useFolderMode = selectedGameFolder != nil
            && detectedGames.count == 1
            && files.count == selection.files.count
        do {
            let game = try addGame(
                detected: detected,
                selected: sources,
                folder: useFolderMode ? selectedGameFolder : nil,
                bundleId: bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            // GameRuntimeConfig.load(for:) reads UserDefaults and the per-title
            // env file, not the library record, so persist the review-screen
            // defaults for a brand-new game. Existing games keep their config.
            if isNewGame {
                pendingRuntimeConfig.save(for: game)
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
        guard let base = selected.first(where: { $0.kind == .base }) else {
            throw NXLibraryError.baseRequired
        }
        let selectedGame = DetectedGame(
            baseTitleId: detected.baseTitleId,
            name: detected.name,
            base: base,
            updates: selected.filter { $0.kind == .update },
            dlcs: selected.filter { $0.kind == .dlc }
        )
        let mode: WorkspaceMode = folder.map { .folder($0) } ?? .staged
        let workspace = try workspaceManager.makeWorkspace(for: selectedGame, mode: mode)
        let titleId = String(format: "%016llX", detected.baseTitleId)
        let updateVersion = selected.filter { $0.kind == .update }
            .compactMap { $0.version }.max().map(String.init)

        var game = PortedGame(
            name: detected.name,
            url: workspace.buildCache.deletingLastPathComponent(),
            platform: .macApp,
            sizeBytes: selected.reduce(0) { $0 + $1.sizeBytes },
            modificationDate: Date(),
            bundleId: bundleId ?? "org.nxnative.\(titleId.lowercased())",
            titleId: titleId,
            versionString: updateVersion
        )
        game.sources = selected.map {
            GameFileItem(url: $0.url, kind: $0.kind,
                         titleId: String(format: "%016llX", $0.titleId),
                         versionString: $0.version.map(String.init),
                         sizeBytes: $0.sizeBytes, isSymlink: folder == nil)
        }
        game.workspacePath = workspace.directory.path
        game.buildCachePath = workspace.buildCache.path
        game.status = .notBuilt
        game.settings = pendingRuntimeConfig

        let library = try libraryStore.merge(scanned: [game])
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
        var target = libraryGames.first(where: { $0.id == game.id }) ?? game
        guard let titleId = target.titleId,
              UInt64(titleId, radix: 16) != nil else {
            throw NXLibraryError.missingTitleId
        }
        guard !target.sources.isEmpty,
              target.sources.contains(where: { $0.kind == .base }),
              target.sources.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) }) else {
            throw NXLibraryError.missingSources
        }
        guard isProdKeysValid,
              FileManager.default.fileExists(atPath: keyStore.keyURL.path) else {
            throw NXLibraryError.missingKeys
        }
        // A few kilobytes per file: keys that cannot open the game stop here, not minutes into the extraction.
        let keyOutcome = KeyCheck.run(keysURL: keyStore.keyURL,
                                      files: KeyCheck.parts(target.sources.map { ($0.kind, $0.url) }))
        if keyOutcome.blocks, let reason = PortingFailureReason.from(keyOutcome) {
            throw NXLibraryError.keyCheck(reason, game: target.name)
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
        let report = try? checker.check(expectedEngineCommit: pinnedEngineCommit)
        compatibilityReport = report
        if report?.ok != true && !allowUntestedToolchain {
            let reason = report?.checks.filter { $0.status == .block }
                .map { "\($0.title): \($0.detail)" }.joined(separator: "; ")
                ?? "the compatibility check is unavailable"
            throw NXLibraryError.incompatibleToolchain(reason)
        }
        activeBuildToolchainVerified = report?.ok == true

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
        if let directory = existingDirectory, existingLinksOK {
            let cache = target.buildCachePath.map(URL.init(fileURLWithPath:))
                ?? directory.appendingPathComponent("\(titleId)_build")
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            workspace = Workspace(directory: directory, buildCache: cache, links: [])
        } else {
            let detected = try detectedGame(from: target)
            workspace = try workspaceManager.makeWorkspace(for: detected, mode: .staged)
            target.workspacePath = workspace.directory.path
            target.buildCachePath = workspace.buildCache.path
        }

        if var library = try? libraryStore.load(),
           let index = library.games.firstIndex(where: { $0.id == target.id }) {
            library.games[index].workspacePath = target.workspacePath
            library.games[index].buildCachePath = target.buildCachePath
            try? libraryStore.save(library)
            libraryGames = library.games.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        let finalApp = finalAppURL(for: target, titleId: titleId)
        let requiredDisk = target.sources.reduce(0) { $0 + $1.sizeBytes } * 2 + 10_000_000_000
        for volume in [workspace.directory, finalApp.deletingLastPathComponent()] {
            if let free = freeBytes(at: volume), free < requiredDisk {
                let freeText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                let requiredText = ByteCountFormatter.string(
                    fromByteCount: requiredDisk, countStyle: .file)
                throw NXLibraryError.environmentBlocked(
                    "Not enough free space at \(volume.path): \(freeText) available, \(requiredText) needed.")
            }
        }

        let repo = URL(fileURLWithPath: nxnativePath)
        let toolchain = engineToolchain
        guard FileManager.default.isExecutableFile(atPath: toolchain.python.path) else {
            throw NXLibraryError.environmentBlocked(toolchain.isBundled
                ? "the bundled Python is missing; reinstall NX Library"
                : "the nxnative venv Python is missing")
        }

        let tempRoot = core.appendingPathComponent("Temp").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let tempApp = tempRoot.appendingPathComponent(finalApp.lastPathComponent)
        let logURL = core.appendingPathComponent("Logs").appendingPathComponent("\(titleId).log")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let command = BuildCommandBuilder.make(
            repo: repo,
            toolchain: toolchain,
            workspace: workspace.directory,
            keys: keyStore.keyURL,
            output: tempApp,
            developerDir: resolvedDeveloperDir(),
            appName: target.name,
            bundleId: target.bundleId ?? "org.nxnative.\(titleId.lowercased())",
            language: selectedLanguage == "auto" ? nil : selectedLanguage,
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

        case .stageEnd(let name, let ok, let elapsed, let summary):
            if let index = buildStages.firstIndex(where: { $0.name == name })
                ?? buildStages.firstIndex(where: { $0.isRunning }) {
                buildStages[index].isRunning = false
                buildStages[index].isCompleted = ok
                buildStages[index].isFailed = !ok
                buildStages[index].elapsedSeconds = elapsed
                buildStages[index].summary = summary
            }
            logs.append(LogEntry(
                level: ok ? .success : .error,
                message: "\(ok ? "✓" : "✗") \(name)\(summary.map { " — \($0)" } ?? "")"
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
        try? FileManager.default.removeItem(at: tempDir)
        buildTempDirectory = nil

        var library = (try? libraryStore.load()) ?? LibraryFile(games: libraryGames)
        if let index = library.games.firstIndex(where: { $0.id == gameID }) {
            var game = library.games[index]
            let verified = activeBuildToolchainVerified
            let record = BuildRecord(
                startedAt: buildStartedAt ?? Date(),
                endedAt: Date(),
                exitCode: result.exitCode,
                logPath: result.logURL.path,
                outputPath: result.success ? finalApp.path : nil,
                engineCommit: pinnedEngineCommit,
                metalVersion: environmentStatus?.metalVersion,
                xcodeVersion: environmentStatus?.xcodeVersion,
                toolchainVerified: verified,
                cancelled: result.cancelled
            )

            if result.success {
                game.status = .built
                game.url = finalApp
                game.modificationDate = Date()
                game.versionString = Self.appVersion(at: finalApp) ?? game.versionString
                game.toolchain = ToolchainInfo(
                    engineCommit: pinnedEngineCommit,
                    metalVersion: environmentStatus?.metalVersion,
                    xcodeVersion: environmentStatus?.xcodeVersion,
                    verified: verified,
                    note: verified ? "Certified toolchain"
                                   : "Untested toolchain (explicit override)"
                )
                game.lastBuild = record
                game.portingFailure = nil
                game.portingFailureReason = nil
                if let seconds = portingProgress?.finishingElapsed, seconds > 0 {
                    lastPortingFinishSeconds = seconds
                }
                progressFraction = 1
                currentStageName = "Build completed"
                buildState = .succeeded
                buildSuccessPath = finalApp.path
                buildError = nil
                lastError = nil
                logs.append(LogEntry(level: .success,
                                     message: "Build succeeded: \(finalApp.path)"))
                SoundEffectService.shared.play(.launch)
                notifyPortingEnded(game, success: true)
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
            try? libraryStore.save(library)
            libraryGames = library.games.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if result.success { loadLibrary() }
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
        activeBuildToolchainVerified = false
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
                                  version: version, sizeBytes: item.sizeBytes)
        }
        guard let base = sources.first(where: { $0.kind == .base }) else {
            throw NXLibraryError.baseRequired
        }
        guard let titleId = game.titleId.flatMap({ UInt64($0, radix: 16) }) else {
            throw NXLibraryError.missingTitleId
        }
        return DetectedGame(baseTitleId: titleId, name: game.name, base: base,
                            updates: sources.filter { $0.kind == .update },
                            dlcs: sources.filter { $0.kind == .dlc })
    }

    private static func detectedSource(from file: GameFileItem) -> DetectedSource? {
        guard let titleId = file.titleId.flatMap({ UInt64($0, radix: 16) }) else {
            return nil
        }
        let version = file.versionString.flatMap {
            Int($0.lowercased().hasPrefix("v") ? String($0.dropFirst()) : $0)
        }
        return DetectedSource(url: file.url, kind: file.type, titleId: titleId,
                              version: version, sizeBytes: file.sizeBytes)
    }

    private func finalAppURL(for game: PortedGame, titleId: String) -> URL {
        if game.url.pathExtension.lowercased() == "app",
           game.status != .notBuilt,
           game.canDeleteAppBundle(),
           FileManager.default.fileExists(atPath: game.url.path) {
            return game.url
        }
        let applications = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications")
        let base = Self.sanitizedAppFileName(game.name)
        let candidate = applications.appendingPathComponent(base + ".app")
        if FileManager.default.fileExists(atPath: candidate.path),
           Self.appTitleId(at: candidate)?.caseInsensitiveCompare(titleId) != .orderedSame {
            return applications.appendingPathComponent("\(base) (\(titleId)).app")
        }
        return candidate
    }

    private static func sanitizedAppFileName(_ name: String) -> String {
        var value = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = "Game" }
        return value
    }

    private static func appTitleId(at app: URL) -> String? {
        let info = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info),
              let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        if let title = object["DMTitleID"] as? String { return title }
        if let bundle = object["CFBundleIdentifier"] as? String,
           bundle.hasPrefix("org.nxnative.") {
            return bundle.split(separator: ".").last.map(String.init)
        }
        return nil
    }

    private static func appVersion(at app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return object["CFBundleShortVersionString"] as? String
    }


}
