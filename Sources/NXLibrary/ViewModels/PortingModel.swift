import AppKit
import Foundation
import UniformTypeIdentifiers
import NXLibraryCore

/// What the Porting screens (Add Game and its Porting step) show of a build: the wizard step, the live stages and
/// how the last porting ended. Add Game observes it on its own, so a stage or progress change redraws only those
/// screens. What the rest of Arcane reads of a porting stays on `AppViewModel`: `isBuilding`, `currentBuildGameID`
/// and `portingProgress` (the home's tile).
public final class PortingModel: ObservableObject {
    // MARK: - Wizard
    @Published public var buildWizardStep: Int = 1 // 1: Select Game, 2: Configure & Output, 3: Porting
    @Published public var showLiveLogsInBuild: Bool = true

    // MARK: - Live build
    @Published public var buildState: BuildState = .idle
    @Published public var isCancellingBuild: Bool = false
    @Published public var currentStageName: String = ""
    @Published public var currentStepName: String = ""
    @Published public var stageIndex: Int = 0
    @Published public var totalStages: Int = 0
    @Published public var progressFraction: Double = 0.0
    @Published public var etaSeconds: Double? = nil
    @Published public var buildStages: [BuildStageItem] = []

    // MARK: - Outcome
    @Published public var buildError: String? = nil
    /// Why the porting on the Porting step failed, when recognised; nil otherwise.
    @Published public var portingFailureReason: PortingFailureReason? = nil
    @Published public var buildSuccessPath: String? = nil
    /// The game whose finished build waits for it to quit (`PendingInstall`).
    @Published var buildHeldGameID: UUID? = nil

    /// The coordinator: library, keys, engine, catalog and Game options' runtime values. The porting reaches
    /// Arcane only through it, so this list is what the Porting module will ask of the base.
    unowned let app: AppViewModel
    /// The remembered Game files folder (the picker's starting point), shared with Settings.
    static let savedGameFolderKey = "NXNative_SavedGameFolder"

    init(app: AppViewModel) { self.app = app }

    // MARK: - Game Selection
    @Published public var selectedGameFolder: URL? {
        didSet {
            if let folder = selectedGameFolder {
                if !keepsRememberedGameFolder {
                    AppData.preferences.set(folder.path, forKey: Self.savedGameFolderKey)
                }
                if !restoringGameFolder {
                    selectedPackageURLs = nil
                    scanGameFolder(folder)
                }
            } else {
                if !keepsRememberedGameFolder {
                    AppData.preferences.removeObject(forKey: Self.savedGameFolderKey)
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
    var keepsRememberedGameFolder = false
    var restoringGameFolder = false
    /// Explicit file picks must not silently include other packages in their parent folder.
    var selectedPackageURLs: [URL]?
    /// The global source-folder preference is independent of the current Add Game draft.
    public var gameFilesFolder: URL? {
        guard let path = AppData.preferences.string(forKey: Self.savedGameFolderKey),
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
            app.pendingRuntimeConfig = selectedLibraryGame.map(app.loadRuntimeConfig) ?? lastAddGameDefaults
        }
    }
    var selectedLibraryGame: PortedGame? {
        guard let titleID = selectedGame?.titleId else { return nil }
        return app.libraryGames.first { $0.titleId?.caseInsensitiveCompare(titleID) == .orderedSame }
    }
    @Published public var selectedSourceIDs: Set<UUID> = [] {
        didSet { refreshKeyCheck() }
    }
    /// The imported keys against the selected sources (`refreshKeyCheck`); nil while it runs.
    @Published public var keyCheck: KeyCheck.Outcome? = nil
    /// What `keyCheck` was computed for; a result for an older token is dropped.
    var keyCheckToken: String? = nil

    @Published public var isScanningGameFolder: Bool = false
    @Published public var scanError: String? = nil

    public var availableDiskBytes: Int64? {
        app.freeBytes(at: selectedGameFolder
            ?? URL(fileURLWithPath: app.defaultInstallPath.isEmpty
                ? NSHomeDirectory() : app.defaultInstallPath))
    }

    /// Review and the first-build space check use the same destination policy as the installer.
    var selectedBuildAppURL: URL {
        let customName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = customName.isEmpty ? selectedGame?.name ?? "Game" : customName
        if var existing = selectedLibraryGame {
            existing.name = name
            return app.finalAppURL(for: existing)
        }
        return GameAppDestination.url(name: name, titleId: selectedGame?.titleId, in: app.gameAppsFolder)
    }

    var buildDestinationProblem: String? {
        GameAppDestination.folderProblem(at: selectedBuildAppURL.deletingLastPathComponent())
    }

    /// The wizard reserves space for both the extracted cache and the temporary
    /// app: the tightest of the folders the build writes to (`BuildScratch`).
    public var availableBuildDiskBytes: Int64? {
        app.buildFolders(appFolder: selectedBuildAppURL.deletingLastPathComponent(),
                     workspace: selectedLibraryGame?.workspacePath).compactMap(app.freeBytes(at:)).min()
    }

    public var selectedSources: [GameFileItem] {
        guard let game = selectedGame else { return [] }
        return game.files.filter { selectedSourceIDs.contains($0.id) }
    }
    
    public var selectedSourcesSizeBytes: Int64 {
        SourceSelection.uniqueSize(selectedSources)
    }

    public var selectedSourcesRequireKeys: Bool { SourceSelection.requiresKeys(selectedSources) }

    public var formattedSelectedSourcesSize: String {
        selectedSourcesSizeBytes.formatted(.byteCount(style: .file).locale(L10n.context.formatLocale))
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
        let availStr = AppViewModel.formatBytes(avail)
        let requiredStr = AppViewModel.formatBytes(requiredBuildDiskBytes)
        let neededStr = AppViewModel.formatBytes(needed)
        return L10n.format("Storage warning: this build needs ~%@ free (twice the selected sources plus 10 GB), but only %@ is available. Free at least %@ before adding it.", [requiredStr, availStr, neededStr])
    }
    
    public var canAddSelectedGame: Bool {
        guard !app.isBuilding, !isScanningGameFolder, let game = selectedGame else { return false }
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

    var lastAddGameDefaults = GameRuntimeConfig()
    var preparedSourceReview = FirstRunSetup.ReviewEntry()
    var addGameSessionActive = false

    // MARK: - Advanced Options
    @Published public var appName: String = ""
    @Published public var bundleId: String = ""

    var scanGeneration = UUID()

    // MARK: - Game Scan
    func scanGameFolder(_ folder: URL) {
        let previousTitle = selectedGame?.id
        let previousFiles = selectedGame?.files ?? []
        let previousSelection = selectedSourceIDs
        let previousName = appName
        let previousBundle = bundleId
        let previousConfig = app.pendingRuntimeConfig
        scanError = nil
        isScanningGameFolder = true
        selectedGame = nil
        selectedSourceIDs = []
        let generation = UUID()
        scanGeneration = generation
        let catalog = app.sourceCatalog
        let repo = URL(fileURLWithPath: app.nxnativePath)
        let toolchain = app.engineToolchain
        let keys = app.isProdKeysValid ? app.keyStore.keyURL : nil
        let developer = app.resolvedDeveloperDir()
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
                    self.app.pendingRuntimeConfig = previousConfig
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
                    self.app.logs.append(LogEntry(level: .warning, message: self.scanError!))
                } else {
                    self.app.logs.append(LogEntry(level: .info,
                        message: L10n.count("Detected %lld games in %@.", games.count, arguments: [String(describing: (folder.lastPathComponent))])))
                }
            }
        }
    }

    struct ScannedSources {
        var games: [DetectedGame]
        var skipped: [String] = []
    }

    static func scanSources(in folder: URL, files: [URL], catalog: SourceCatalog,
                                    repo: URL, toolchain: EngineToolchain, keys: URL?, developerDir: URL,
                                    allowExtractedFolder: Bool = true) throws -> ScannedSources {
        let capabilities = EngineSourceCapabilities(repo: repo)
        if allowExtractedFolder && ExtractedSourceCatalog.recognizes(folder) {
            guard capabilities.extractedFolders else {
                throw NXLibraryError.environmentBlocked(L10n.text("This engine does not support extracted folders."))
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
                throw NXLibraryError.environmentBlocked(L10n.text("This engine does not support NUP files."))
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
    
    static func sourceFileURLs(in folder: URL) -> [URL] {
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
    
    static func selectableGame(from game: DetectedGame) -> SelectableGame {
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
                    requiresTitleSelection: source.requiresTitleSelection, nupProgram: source.nupProgram
                )
            }
        )
    }

    @discardableResult
    public func selectGameFolder(startingNewGameWith defaults: GameRuntimeConfig? = nil) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedGameFolder ?? gameFilesFolder
        panel.prompt = "Choose folder"
        panel.message = GameFoldersCopy.sourcesPickerMessage(extractedFolders: app.engineSourceCapabilities.extractedFolders)
        
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

    public func goToWizardStep(_ step: Int) {
        guard step >= 1 && step <= 3 else { return }
        if step == 2 && selectedGame == nil { return }
        app.porting.buildWizardStep = step
    }

    public func resetWizard() {
        app.porting.buildWizardStep = 1
        app.porting.buildError = nil
        app.porting.portingFailureReason = nil
        app.porting.buildSuccessPath = nil
        app.porting.buildState = .idle
        app.lastError = nil
    }

    /// Called when the Add Game route becomes visible. A build in progress always
    /// resumes on the live step; returning with Back keeps the draft; any other
    /// entry starts clean so an old success or failure screen never comes back.
    func consumePreparedReviewEntry(_ id: UUID?) -> Bool {
        guard app.porting.buildWizardStep == 1 else { return false }
        return preparedSourceReview.consume(id, isReady: canAddSelectedGame, titleCount: detectedGames.count)
    }

    public func addGameDidBecomeVisible(defaults: GameRuntimeConfig, returningFromBack: Bool,
                                        preservingSelection: Bool = false) {
        app.prepareBuildEnvironmentIfNeeded()
        if app.isBuilding {
            app.porting.buildWizardStep = 3
            addGameSessionActive = true
            return
        }
        if (returningFromBack || preservingSelection), addGameSessionActive { return }
        if app.reviewsFailureOnAddGame {
            app.reviewsFailureOnAddGame = false
            if app.restoreLastFailure() || app.porting.buildError != nil { return }
        }
        startNewAddGame(defaults: defaults)
    }

    /// Ends the draft when the user leaves Add Game for a non-overlay route.
    public func addGameDidLeave() {
        guard !app.isBuilding else { return }
        addGameSessionActive = false
    }

    /// Starts a clean wizard while remembering the folder preference for next launch.
    public func startNewAddGame(defaults: GameRuntimeConfig? = nil) {
        guard !app.isBuilding else {
            app.porting.buildWizardStep = 3
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
        app.pendingRuntimeConfig = lastAddGameDefaults
        resetWizard()
        addGameSessionActive = true
    }

    // MARK: - Keys against the selection
    /// Keys that are too old or do not open the game disable Add and port.
    var keyCheckBlocks: Bool { keyCheck?.blocks == true }

    /// Re-runs the check off the main thread when the keys file or the selected sources changed;
    /// a result that arrives after a newer change is dropped.
    func refreshKeyCheck() {
        let sources = selectedSources
        let files = KeyCheck.parts(sources.map { ($0.kind, $0.url) })
        guard SourceSelection.requiresKeys(sources), app.isProdKeysValid, !files.isEmpty else {
            keyCheck = nil
            keyCheckToken = nil
            return
        }
        let keysURL = app.keyStore.keyURL
        let modified = (try? FileManager.default.attributesOfItem(atPath: keysURL.path)[.modificationDate]) as? Date
        let token = ([String(modified?.timeIntervalSince1970 ?? 0)]
            + sources.map { "\($0.url.path)|\($0.sizeBytes)" }.sorted()).joined(separator: "\n")
        guard token != keyCheckToken else { return }
        keyCheckToken = token
        keyCheck = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = KeyCheck.run(keysURL: keysURL, files: files)
            guard let self else { return }
            await MainActor.run {
                guard self.keyCheckToken == token else { return }
                self.keyCheck = outcome
            }
        }
    }
}
