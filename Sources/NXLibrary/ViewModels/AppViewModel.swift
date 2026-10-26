import Foundation
import SwiftUI
import AppKit
import NXLibraryCore

public final class AppViewModel: ObservableObject, InstallerServiceDelegate {
    // MARK: - Storage Keys for Persistence
    private enum StorageKeys {
        static let savedGameFolder = "NXNative_SavedGameFolder"
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
    @Published public var showCltInstallAlert: Bool = false
    
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
                UserDefaults.standard.removeObject(forKey: StorageKeys.savedGameFolder)
                detectedGames = []
                selectedGame = nil
                selectedSourceIDs = []
                scanError = nil
            }
        }
    }
    @Published public var detectedGames: [SelectableGame] = []
    @Published public var selectedGame: SelectableGame? = nil {
        didSet {
            if let game = selectedGame {
                self.appName = game.name
                resetSourceSelection(for: game)
            } else {
                selectedSourceIDs = []
            }
        }
    }
    @Published public var selectedSourceIDs: Set<UUID> = []
    @Published public var isScanningGameFolder: Bool = false
    @Published public var scanError: String? = nil
    
    // MARK: - Disk Capacity Pre-flight
    public var availableDiskBytes: Int64? {
        let checkPath = selectedGameFolder?.path ?? (defaultInstallPath.isEmpty ? NSHomeDirectory() : defaultInstallPath)
        var stat = statvfs()
        if statvfs(checkPath, &stat) == 0 {
            return Int64(stat.f_bavail) * Int64(stat.f_frsize)
        }
        let url = URL(fileURLWithPath: checkPath)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let cap = values?.volumeAvailableCapacityForImportantUsage {
            return cap
        }
        return values?.volumeAvailableCapacity.map { Int64($0) }
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
    
    public var isDiskSpaceLow: Bool {
        guard let avail = availableDiskBytes, selectedSourcesSizeBytes > 0 else { return false }
        return avail < requiredBuildDiskBytes
    }
    
    public var diskSpaceWarningMessage: String? {
        guard isDiskSpaceLow, let avail = availableDiskBytes else { return nil }
        let needed = requiredBuildDiskBytes - avail
        let availStr = ByteCountFormatter.string(fromByteCount: avail, countStyle: .file)
        let requiredStr = ByteCountFormatter.string(fromByteCount: requiredBuildDiskBytes, countStyle: .file)
        let neededStr = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
        return "Storage warning: this build needs ~\(requiredStr) free (twice the selected sources plus 10 GB), but only \(availStr) is available. Free at least \(neededStr) before adding it."
    }
    
    public var canAddSelectedGame: Bool {
        guard !isBuilding, let game = selectedGame else { return false }
        return game.hasBase
            && selectedSources.contains(where: { $0.type == .base })
            && selectedSourcesSizeBytes > 0
            && !isDiskSpaceLow
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
    @Published public var librarySearchText: String = ""
    @Published public var isScanningLibrary: Bool = false
    @Published public var gameForSettingsSheet: PortedGame? = nil
    @Published public var importedApps: [ImportedApp] = []
    @Published public var environmentStatus: EnvironmentStatus? = nil
    @Published public var compatibilityReport: CompatibilityReport? = nil
    @Published public var keySummary: KeySummary? = nil
    @Published public var currentEngineCommit: String? = nil
    @Published public var storageUsage: StorageUsage? = nil
    @Published public var isCalculatingStorage: Bool = false
    @Published public var showSetupSheet: Bool = false
    @Published public var setupCompleted: Bool = false
    @Published public var buildState: BuildState = .idle
    @Published public var lastError: String? = nil
    @Published public var isCancellingBuild: Bool = false
    @Published public var buildLogURL: URL? = nil
    @Published public var currentBuildGameID: UUID? = nil
    @Published public var lastBuildGameID: UUID? = nil
    @Published public var allowUntestedToolchain: Bool = false {
        didSet {
            UserDefaults.standard.set(allowUntestedToolchain, forKey: StorageKeys.allowUntestedToolchain)
        }
    }
    
    // MARK: - System Prerequisites & Installer
    @Published public var prerequisites: SystemPrerequisites = SystemPrerequisites()
    @Published public var isCheckingPrerequisites: Bool = false
    @Published public var isInstallingDependency: Bool = false
    @Published public var installerCurrentItem: String? = nil
    @Published public var installerLogs: [String] = []
    @Published public var showInstallerSheet: Bool = false
    @Published public var dependencyToUninstall: DependencyStatus? = nil
    @Published public var showUninstallConfirm: Bool = false
    
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
    @Published public var showLiveLogsInBuild: Bool = true
    @Published public var logs: [LogEntry] = []
    @Published public var buildError: String? = nil
    @Published public var buildSuccessPath: String? = nil
    @Published public var buildWizardStep: Int = 1 // 1: Select Game, 2: Configure & Output, 3: Porting
    @Published public var iconAppearanceMode: AppIconAppearanceMode = .auto {
        didSet {
            UserDefaults.standard.set(iconAppearanceMode.rawValue, forKey: StorageKeys.savedIconAppearanceMode)
            updateDockIcon()
        }
    }
    
    // MARK: - Navigation
    @Published public var selectedTab: Int = 0 // 0: Library, 1: Add Game, 2: Controls, 3: Settings, 4: Console
    @Published public var focusedGameIndex: Int = 0
    @Published public var isFocusOnDeck: Bool = false
    @Published public var launchingGameId: UUID? = nil
    
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
    
    public let pinnedEngineCommit = "06b7b3e56303bc67213a98cae61925f9253bdf89"
    private let core = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NXLibrary")
    private lazy var libraryStore = LibraryStore(directory: core)
    private lazy var keyStore = KeyStore(directory: core.appendingPathComponent("keys"))
    private let importService = ImportService()
    private let launchService = LaunchService()
    private lazy var storageManager = StorageManager()
    private let sourceCatalog = SourceCatalog()
    private lazy var workspaceManager = WorkspaceManager(root: core.appendingPathComponent("workspaces"))
    private var buildService: BuildService?
    private var buildPreviousStatus: GameStatus?
    private var buildStartedAt: Date?
    private var buildTempDirectory: URL?
    private let installer = InstallerService.shared
    
    public init() {
        installer.delegate = self
        let didCompleteSetup = UserDefaults.standard.bool(forKey: StorageKeys.setupCompleted)
        self.setupCompleted = didCompleteSetup
        self.showSetupSheet = !didCompleteSetup
        
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
        updateDockIcon()
        
        NotificationService.shared.requestAuthorization()
        setupControllerNavigation()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-setup") {
            self.showSetupSheet = true
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
        refreshPrerequisites()
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
        let python = repo.appendingPathComponent(".venv/bin/python")
        let developerDir = resolvedDeveloperDir()
        let expected = pinnedEngineCommit
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let environment = NXNativeEnvironment(repoURL: repo, pythonURL: python,
                                                  developerDir: developerDir)
            let status = environment.inspect()
            let checker = CompatibilityChecker(repoURL: repo, pythonURL: python,
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

    private func resolvedDeveloperDir() -> URL {
        let candidates = [
            "/Applications/Xcode-beta.app/Contents/Developer",
            "/Applications/Xcode.app/Contents/Developer",
            "/Library/Developer/CommandLineTools",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
    }

    public var requiredMetalVersion: String? {
        let lock = URL(fileURLWithPath: nxnativePath)
            .appendingPathComponent("dm/gfx/tools/dmsh_chain.lock")
        guard let text = try? String(contentsOf: lock, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("metal_macosx\t") {
            return line.split(separator: "\t").last.map(String.init)
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
        showSetupSheet = false
        UserDefaults.standard.set(true, forKey: StorageKeys.setupCompleted)
        logs.append(LogEntry(level: .success, message: "Setup completed."))
    }

    public func reopenSetup() {
        showSetupSheet = true
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
    
    public func installAppleCommandLineTools() {
        showCltInstallAlert = true
        installer.install(dependency: prerequisites.xcode) { [weak self] _ in
            self?.refreshPrerequisites()
        }
    }
    
    public func refreshPrerequisites() {
        isCheckingPrerequisites = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let res = SystemDetector.shared.checkPrerequisites()
            DispatchQueue.main.async {
                self?.prerequisites = res
                self?.isCheckingPrerequisites = false
            }
        }
    }
    
    // MARK: - Tool Installer / Repair / Uninstall
    public func installAllMissingDependencies() {
        let missing = prerequisites.missingList
        guard !missing.isEmpty else { return }
        showInstallerSheet = true
        isInstallingDependency = true
        installerLogs.removeAll()
        installerLogs.append("Installing \(missing.count) missing dependencies...")
        
        installer.installAll(dependencies: missing) { [weak self] success in
            self?.isInstallingDependency = false
            self?.refreshPrerequisites()
            if success {
                self?.logs.append(LogEntry(level: .success, message: "All missing dependencies installed successfully."))
            } else {
                self?.logs.append(LogEntry(level: .warning, message: "Some dependencies could not be installed."))
            }
        }
    }
    
    public func installDependency(_ dep: DependencyStatus) {
        showInstallerSheet = true
        isInstallingDependency = true
        installerLogs.removeAll()
        installerLogs.append("Installing \(dep.name)...")
        
        installer.install(dependency: dep) { [weak self] success in
            self?.isInstallingDependency = false
            self?.refreshPrerequisites()
            if success {
                self?.logs.append(LogEntry(level: .success, message: "\(dep.name) installed successfully."))
            } else {
                self?.logs.append(LogEntry(level: .error, message: "Failed to install \(dep.name)."))
            }
        }
    }
    
    public func repairDependency(_ dep: DependencyStatus) {
        showInstallerSheet = true
        isInstallingDependency = true
        installerLogs.removeAll()
        installerLogs.append("Repairing \(dep.name)...")
        
        installer.repair(dependency: dep) { [weak self] success in
            self?.isInstallingDependency = false
            self?.refreshPrerequisites()
            if success {
                self?.logs.append(LogEntry(level: .success, message: "\(dep.name) repaired successfully."))
            } else {
                self?.logs.append(LogEntry(level: .error, message: "Failed to repair \(dep.name)."))
            }
        }
    }
    
    public func confirmUninstall(_ dep: DependencyStatus) {
        self.dependencyToUninstall = dep
        self.showUninstallConfirm = true
    }
    
    public func executeUninstall() {
        guard let dep = dependencyToUninstall else { return }
        showUninstallConfirm = false
        showInstallerSheet = true
        isInstallingDependency = true
        installerLogs.removeAll()
        installerLogs.append("Uninstalling \(dep.name)...")
        
        installer.uninstall(dependency: dep) { [weak self] success in
            self?.isInstallingDependency = false
            self?.refreshPrerequisites()
            if success {
                self?.logs.append(LogEntry(level: .warning, message: "\(dep.name) was uninstalled."))
            } else {
                self?.logs.append(LogEntry(level: .error, message: "Failed to uninstall \(dep.name)."))
            }
        }
    }
    
    public func repairAllDependencies() {
        showInstallerSheet = true
        isInstallingDependency = true
        installerLogs.removeAll()
        installerLogs.append("Repairing all environment tools...")
        
        installer.repairAll(dependencies: prerequisites.list) { [weak self] success in
            self?.isInstallingDependency = false
            self?.refreshPrerequisites()
            if success {
                self?.logs.append(LogEntry(level: .success, message: "All environment tools repaired."))
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
        guard FileManager.default.fileExists(atPath: game.url.path) else {
            lastError = NXLibraryError.appMissing(game.url.path).localizedDescription
            updateStoredStatus(.appMissing, for: game)
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: lastError!))
            return
        }
        guard let titleId = game.titleId, !titleId.isEmpty else {
            lastError = NXLibraryError.missingTitleId.localizedDescription
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: lastError!))
            return
        }

        launchingGameId = game.id
        SoundEffectService.shared.play(.launch)

        let config = GameRuntimeConfig.load(for: game)
        do {
            try launchService.writeEnvironment(settings: config, titleId: titleId)
        } catch {
            launchingGameId = nil
            lastError = error.localizedDescription
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error,
                                 message: "Could not write the runtime environment: \(error.localizedDescription)"))
            return
        }

        guard launchService.launch(appURL: game.url) else {
            launchingGameId = nil
            lastError = NXLibraryError.launchFailed(game.name).localizedDescription
            SoundEffectService.shared.play(.error)
            logs.append(LogEntry(level: .error, message: lastError!))
            return
        }

        lastError = nil
        logs.append(LogEntry(level: .success, message: "Launched game: \(game.name)"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.launchingGameId == game.id { self?.launchingGameId = nil }
        }
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

    public func saveRuntimeConfig(_ config: GameRuntimeConfig, for game: PortedGame) {
        config.save(for: game)
        logs.append(LogEntry(level: .success, message: "Saved settings for \(game.name)"))
    }

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func deletePortedGame(_ game: PortedGame) {
        do {
            if FileManager.default.fileExists(atPath: game.url.path) {
                try FileManager.default.removeItem(at: game.url)
            }
            var library = try libraryStore.load()
            library.games.removeAll { $0.id == game.id }
            try libraryStore.save(library)
            libraryGames = library.games.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            logs.append(LogEntry(level: .warning, message: "Game removed: \(game.name)"))
        } catch {
            logs.append(LogEntry(level: .error, message: "Failed to delete game: \(error.localizedDescription)"))
        }
    }
    
    // MARK: - Game Scan
    private func scanGameFolder(_ folder: URL) {
        scanError = nil
        isScanningGameFolder = true
        let catalog = sourceCatalog
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = Self.sourceFileURLs(in: folder)
            let readable = urls.filter { (try? catalog.inspect($0)) != nil }
            let detected = (try? catalog.scan(files: readable)) ?? []
            let games = detected.map(Self.selectableGame(from:))
            DispatchQueue.main.async {
                guard let self else { return }
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
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) > 0 else { continue }
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
                refreshPrerequisites()
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
            && isNxnativeValid
            && environmentStatus?.canBuild == true
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
        return canPassToolchainGate
    }

    public var canPassToolchainGate: Bool {
        compatibilityReport?.ok == true || allowUntestedToolchain
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
        buildSuccessPath = nil
        buildState = .idle
        lastError = nil
    }

    #if DEBUG
    /// Feeds sample events through the same reducer as a real build, for
    /// SwiftUI previews and UI work without running nxnative.
    public func previewBuild() {
        isBuilding = true
        buildState = .running
        buildWizardStep = 3
        selectedTab = 1
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
            if let index = libraryGames.firstIndex(where: { $0.id == game.id }) {
                focusedGameIndex = index
            }
            logs.append(LogEntry(level: .success, message: "Added \(game.name) to the library."))
            if buildNow, canStartBuild {
                selectedTab = 1
                startBuild(for: game)
            } else {
                selectedTab = 0
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
        game.settings = GameRuntimeConfig()

        let library = try libraryStore.merge(scanned: [game])
        libraryGames = library.games.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return library.games.first(where: { $0.titleId == titleId }) ?? game
    }

    public func startBuild(for game: PortedGame) {
        do {
            try beginBuild(for: game)
        } catch {
            presentBuildError(error)
        }
    }

    private func beginBuild(for game: PortedGame) throws {
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
        guard isNxnativeValid else { throw NXLibraryError.engineMissing }
        guard let environmentStatus else {
            throw NXLibraryError.environmentBlocked("the environment check is still running")
        }
        guard environmentStatus.canBuild else {
            throw NXLibraryError.environmentBlocked(environmentStatus.issues.joined(separator: "; "))
        }

        let report = compatibilityReport ?? (try? CompatibilityChecker(
            repoURL: URL(fileURLWithPath: nxnativePath),
            pythonURL: URL(fileURLWithPath: nxnativePath).appendingPathComponent(".venv/bin/python"),
            developerDir: resolvedDeveloperDir()
        ).check(expectedEngineCommit: pinnedEngineCommit))
        if report?.ok != true && !allowUntestedToolchain {
            let reason = report?.checks.filter { $0.status == .block }
                .map { "\($0.title): \($0.detail)" }.joined(separator: "; ")
                ?? "the compatibility check is unavailable"
            throw NXLibraryError.incompatibleToolchain(reason)
        }

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
        let tempRoot = core.appendingPathComponent("Temp").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let tempApp = tempRoot.appendingPathComponent(finalApp.lastPathComponent)
        let logURL = core.appendingPathComponent("Logs").appendingPathComponent("\(titleId).log")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let repo = URL(fileURLWithPath: nxnativePath)
        let python = repo.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw NXLibraryError.environmentBlocked("the nxnative venv Python is missing")
        }
        let command = BuildCommandBuilder.make(
            repo: repo,
            python: python,
            workspace: workspace.directory,
            keys: keyStore.keyURL,
            output: tempApp,
            developerDir: resolvedDeveloperDir(),
            appName: target.name,
            bundleId: target.bundleId ?? "org.nxnative.\(titleId.lowercased())",
            language: selectedLanguage == "auto" ? nil : selectedLanguage
        )

        buildStartedAt = Date()
        buildTempDirectory = tempRoot
        buildLogURL = logURL
        buildWizardStep = 3
        isBuilding = true
        isCancellingBuild = false
        buildState = .running
        buildError = nil
        lastError = nil
        buildSuccessPath = nil
        progressFraction = 0
        currentStageName = "Preparing build"
        currentStepName = ""
        stageIndex = 0
        totalStages = 0
        etaSeconds = nil
        buildStages.removeAll()
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
        isBuilding = false
        isCancellingBuild = false
        buildService = nil
        try? FileManager.default.removeItem(at: tempDir)
        buildTempDirectory = nil

        var library = (try? libraryStore.load()) ?? LibraryFile(games: libraryGames)
        if let index = library.games.firstIndex(where: { $0.id == gameID }) {
            var game = library.games[index]
            let verified = compatibilityReport?.ok == true
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
                progressFraction = 1
                currentStageName = "Build completed"
                buildState = .succeeded
                buildSuccessPath = finalApp.path
                buildError = nil
                lastError = nil
                logs.append(LogEntry(level: .success,
                                     message: "Build succeeded: \(finalApp.path)"))
                SoundEffectService.shared.play(.launch)
                NotificationService.shared.sendPortSuccessNotification(
                    gameName: game.name, outputPath: finalApp.path)
            } else if result.cancelled {
                game.status = buildPreviousStatus
                    ?? (game.sources.isEmpty ? .builtSourcesMissing : .notBuilt)
                buildState = .cancelled
                buildError = nil
                lastError = "Build cancelled."
                logs.append(LogEntry(level: .warning, message: "Build cancelled."))
            } else {
                let message = result.error ?? "Build failed (exit code \(result.exitCode))."
                game.status = .failed
                buildState = .failed
                buildError = message
                lastError = message
                logs.append(LogEntry(level: .error, message: message))
                SoundEffectService.shared.play(.error)
                NotificationService.shared.sendPortErrorNotification(
                    gameName: game.name, error: message)
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
        lastError = message
        logs.append(LogEntry(level: .error, message: message))
        SoundEffectService.shared.play(.error)
    }

    private static func formatAmount(_ value: Double) -> String {
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

    public func installerDidProduceOutput(_ line: String) {
        installerLogs.append(line)
    }
    
    public func installerDidStartItem(_ name: String) {
        installerCurrentItem = name
    }
    
    public func installerDidFinishItem(_ name: String, success: Bool) {}
    
    public func installerDidCompleteAll(allSuccess: Bool) {
        installerCurrentItem = nil
    }
    
}
