import AppKit
import Foundation
import UniformTypeIdentifiers
import NXLibraryCore

/// What the Porting screens (Add Game and its Porting step) show of a build: the wizard step, the live stages and
/// how the last porting ended. Add Game observes it on its own, so a stage or progress change redraws only those
/// screens. What the rest of Arcane reads of a porting stays on `AppViewModel`: `isBuilding`, `currentBuildGameID`
/// and `portingProgress` (the home's tile).
final class PortingModel: ObservableObject {
    // MARK: - Wizard
    @Published var buildWizardStep: Int = 1 // 1: Select Game, 2: Configure & Output, 3: Porting
    @Published var showLiveLogsInBuild: Bool = true

    // MARK: - Live build
    @Published var buildState: BuildState = .idle
    @Published var isCancellingBuild: Bool = false
    @Published var currentStageName: String = ""
    @Published var currentStepName: String = ""
    @Published var stageIndex: Int = 0
    @Published var totalStages: Int = 0
    @Published var progressFraction: Double = 0.0
    @Published var etaSeconds: Double? = nil
    @Published var buildStages: [BuildStageItem] = []

    // MARK: - Outcome
    @Published var buildError: String? = nil
    /// Why the porting on the Porting step failed, when recognised; nil otherwise.
    @Published var portingFailureReason: PortingFailureReason? = nil
    @Published var buildSuccessPath: String? = nil
    /// The game whose finished build waits for it to quit (`PendingInstall`).
    @Published var buildHeldGameID: UUID? = nil

    /// The coordinator: library, keys, engine, catalog and Game options' runtime values. The porting reaches
    /// Arcane only through it, so this list is what the Porting module will ask of the base.
    unowned let app: AppViewModel

    // Build run state.
    var buildService: BuildService?
    var buildPreviousStatus: GameStatus?
    var activeBuildToolchain: ToolchainInfo?
    var buildStartedAt: Date?
    var buildTempDirectory: URL?
    var stageElapsedTimer: Timer?
    var currentStageStartedAt: Date?
    var currentBuildCacheURL: URL?
    var pipelinePollGeneration = UUID()
    var isPollingPipelineArchive = false
    /// The remembered Game files folder (the picker's starting point), shared with Settings.
    static let savedGameFolderKey = "NXNative_SavedGameFolder"

    init(app: AppViewModel) { self.app = app }

    /// The last porting's command line, for Copy diagnostics (its environment is never kept).
    var lastPortingCommand: [String] = []
    /// Set by a failed porting's notification: the next Add game opens on that failure.
    var reviewsFailureOnAddGame = false

    // MARK: - Game Selection
    @Published var selectedGameFolder: URL? {
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
    var gameFilesFolder: URL? {
        guard let path = AppData.preferences.string(forKey: Self.savedGameFolderKey),
              !path.isEmpty, path != "/" else { return nil }
        return URL(fileURLWithPath: path)
    }
    @Published var detectedGames: [SelectableGame] = []
    @Published var selectedGame: SelectableGame? = nil {
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
            pendingRuntimeConfig = selectedLibraryGame.map(app.runtimeSettings.loadRuntimeConfig) ?? lastAddGameDefaults
        }
    }
    var selectedLibraryGame: PortedGame? {
        guard let titleID = selectedGame?.titleId else { return nil }
        return app.libraryGames.first { $0.titleId?.caseInsensitiveCompare(titleID) == .orderedSame }
    }
    @Published var selectedSourceIDs: Set<UUID> = [] {
        didSet { refreshKeyCheck() }
    }
    /// The imported keys against the selected sources (`refreshKeyCheck`); nil while it runs.
    @Published var keyCheck: KeyCheck.Outcome? = nil
    /// What `keyCheck` was computed for; a result for an older token is dropped.
    var keyCheckToken: String? = nil

    @Published var isScanningGameFolder: Bool = false
    @Published var scanError: String? = nil

    var availableDiskBytes: Int64? {
        freeBytes(at: selectedGameFolder
            ?? URL(fileURLWithPath: app.defaultInstallPath.isEmpty
                ? NSHomeDirectory() : app.defaultInstallPath))
    }

    /// Review and the first-build space check use the same destination policy as the installer.
    var selectedBuildAppURL: URL {
        let customName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = customName.isEmpty ? selectedGame?.name ?? "Game" : customName
        if var existing = selectedLibraryGame {
            existing.name = name
            return finalAppURL(for: existing)
        }
        return GameAppDestination.url(name: name, titleId: selectedGame?.titleId, in: app.gameAppsFolder)
    }

    var buildDestinationProblem: String? {
        GameAppDestination.folderProblem(at: selectedBuildAppURL.deletingLastPathComponent())
    }

    /// The wizard reserves space for both the extracted cache and the temporary
    /// app: the tightest of the folders the build writes to (`BuildScratch`).
    var availableBuildDiskBytes: Int64? {
        buildFolders(appFolder: selectedBuildAppURL.deletingLastPathComponent(),
                     workspace: selectedLibraryGame?.workspacePath).compactMap(freeBytes(at:)).min()
    }

    var selectedSources: [GameFileItem] {
        guard let game = selectedGame else { return [] }
        return game.files.filter { selectedSourceIDs.contains($0.id) }
    }

    var selectedSourcesSizeBytes: Int64 {
        SourceSelection.uniqueSize(selectedSources)
    }

    var selectedSourcesRequireKeys: Bool { SourceSelection.requiresKeys(selectedSources) }

    var formattedSelectedSourcesSize: String {
        selectedSourcesSizeBytes.formatted(.byteCount(style: .file).locale(L10n.context.formatLocale))
    }

    /// The build keeps an extracted copy and writes a temporary app before the
    /// atomic install, so plan for roughly twice the source size plus 10 GB.
    var requiredBuildDiskBytes: Int64 {
        selectedSourcesSizeBytes * 2 + 10_000_000_000
    }

    var isAddDiskSpaceLow: Bool {
        guard let avail = availableDiskBytes, selectedSourcesSizeBytes > 0 else { return false }
        return avail < requiredBuildDiskBytes
    }

    var isDiskSpaceLow: Bool {
        guard let avail = availableBuildDiskBytes, selectedSourcesSizeBytes > 0 else { return false }
        return avail < requiredBuildDiskBytes
    }

    var diskSpaceWarningMessage: String? {
        guard isDiskSpaceLow, let avail = availableBuildDiskBytes else { return nil }
        let needed = requiredBuildDiskBytes - avail
        let availStr = AppViewModel.formatBytes(avail)
        let requiredStr = AppViewModel.formatBytes(requiredBuildDiskBytes)
        let neededStr = AppViewModel.formatBytes(needed)
        return L10n.format("Storage warning: this build needs ~%@ free (twice the selected sources plus 10 GB), but only %@ is available. Free at least %@ before adding it.", [requiredStr, availStr, neededStr])
    }

    var canAddSelectedGame: Bool {
        guard !app.isBuilding, !isScanningGameFolder, let game = selectedGame else { return false }
        return game.hasGame
            && SourceSelection.hasGame(selectedSources)
            && selectedSourcesSizeBytes > 0
            && !isAddDiskSpaceLow
    }

    func resetSourceSelection(for game: SelectableGame) {
        selectedSourceIDs = SourceSelection.initial(in: game.files)
    }

    func toggleSource(_ item: GameFileItem) {
        guard let game = selectedGame else { return }
        selectedSourceIDs = SourceSelection.toggling(item.id, in: game.files, selected: selectedSourceIDs)
    }

    /// The Add Game draft's choices for the game's first launch; a rebuild starts from the game's saved ones.
    @Published var pendingRuntimeConfig = GameRuntimeConfig()
    var lastAddGameDefaults = GameRuntimeConfig()
    var preparedSourceReview = FirstRunSetup.ReviewEntry()
    var addGameSessionActive = false

    // MARK: - Advanced Options
    @Published var appName: String = ""
    @Published var bundleId: String = ""

    var scanGeneration = UUID()

    // MARK: - Game Scan
    func scanGameFolder(_ folder: URL) {
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
        let catalog = app.sourceCatalog
        let repo = URL(fileURLWithPath: app.setup.nxnativePath)
        let toolchain = app.setup.engineToolchain
        let keys = app.setup.isProdKeysValid ? app.setup.keyStore.keyURL : nil
        let developer = app.setup.resolvedDeveloperDir()
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
                    self.app.logs.append(LogEntry(level: .warning, message: self.scanError!))
                } else {
                    self.app.logs.append(LogEntry(level: .info,
                        message: L10n.count("Detected %lld games in %@.", games.count, arguments: [String(describing: folder.lastPathComponent)])))
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
    func selectGameFolder(startingNewGameWith defaults: GameRuntimeConfig? = nil) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedGameFolder ?? gameFilesFolder
        panel.prompt = "Choose folder"
        panel.message = GameFoldersCopy.sourcesPickerMessage(extractedFolders: app.setup.engineSourceCapabilities.extractedFolders)

        if panel.runModal() == .OK, let url = panel.url {
            if let defaults { startNewAddGame(defaults: defaults) }
            self.selectedGameFolder = url
            return true
        }
        return false
    }

    @discardableResult
    func selectGameFiles(startingNewGameWith defaults: GameRuntimeConfig? = nil) -> Bool {
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

    func goToWizardStep(_ step: Int) {
        guard step >= 1 && step <= 3 else { return }
        if step == 2 && selectedGame == nil { return }
        self.buildWizardStep = step
    }

    func resetWizard() {
        self.buildWizardStep = 1
        self.buildError = nil
        self.portingFailureReason = nil
        self.buildSuccessPath = nil
        self.buildState = .idle
        app.lastError = nil
    }

    /// Called when the Add Game route becomes visible. A build in progress always
    /// resumes on the live step; returning with Back keeps the draft; any other
    /// entry starts clean so an old success or failure screen never comes back.
    func consumePreparedReviewEntry(_ id: UUID?) -> Bool {
        guard self.buildWizardStep == 1 else { return false }
        return preparedSourceReview.consume(id, isReady: canAddSelectedGame, titleCount: detectedGames.count)
    }

    func addGameDidBecomeVisible(defaults: GameRuntimeConfig, returningFromBack: Bool,
                                        preservingSelection: Bool = false) {
        app.setup.prepareBuildEnvironmentIfNeeded()
        if app.isBuilding {
            self.buildWizardStep = 3
            addGameSessionActive = true
            return
        }
        if (returningFromBack || preservingSelection), addGameSessionActive { return }
        if reviewsFailureOnAddGame {
            reviewsFailureOnAddGame = false
            if restoreLastFailure() || self.buildError != nil { return }
        }
        startNewAddGame(defaults: defaults)
    }

    /// Ends the draft when the user leaves Add Game for a non-overlay route.
    func addGameDidLeave() {
        guard !app.isBuilding else { return }
        addGameSessionActive = false
    }

    /// Starts a clean wizard while remembering the folder preference for next launch.
    func startNewAddGame(defaults: GameRuntimeConfig? = nil) {
        guard !app.isBuilding else {
            self.buildWizardStep = 3
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

    // MARK: - Keys against the selection
    /// Keys that are too old or do not open the game disable Add and port.
    var keyCheckBlocks: Bool { keyCheck?.blocks == true }

    /// Re-runs the check off the main thread when the keys file or the selected sources changed;
    /// a result that arrives after a newer change is dropped.
    func refreshKeyCheck() {
        let sources = selectedSources
        let files = KeyCheck.parts(sources.map { ($0.kind, $0.url) })
        guard SourceSelection.requiresKeys(sources), app.setup.isProdKeysValid, !files.isEmpty else {
            keyCheck = nil
            keyCheckToken = nil
            return
        }
        let keysURL = app.setup.keyStore.keyURL
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

    // MARK: - Build run
    var canStartBuild: Bool {
        !app.isBuilding
            && !app.isCleaningStorage
            && !app.isUpdatingApp
            && self.canAddSelectedGame
            && supportsSources(self.selectedSources)
            && (!self.selectedSourcesRequireKeys || app.setup.isProdKeysValid)
            && !self.keyCheckBlocks
            && app.setup.isNxnativeValid
            && app.setup.environmentStatus?.canBuild == true
            && !self.isDiskSpaceLow
            && self.buildDestinationProblem == nil
            && app.setup.canPassToolchainGate
    }

    func buildLogTail(_ url: URL, maxBytes: Int = 64 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    #if DEBUG
    /// Feeds sample events through the same reducer as a real build, for
    /// SwiftUI previews and UI work without running nxnative.
    func previewBuild() {
        app.isBuilding = true
        self.buildState = .running
        self.buildWizardStep = 3
        app.currentBuildGameID = app.libraryGames.first?.id
        app.logs.removeAll()
        self.buildStages.removeAll()
        self.currentStageName = "Preparing build"
        self.currentStepName = ""
        self.progressFraction = 0
        self.etaSeconds = nil
        handleBuildEvent(.stage(k: 1, n: 8, name: "extract", step: "reading NSP"))
        handleBuildEvent(.stageEnd(name: "extract", ok: true, elapsed: 1.2, summary: L10n.text("done")))
        handleBuildEvent(.stage(k: 2, n: 8, name: "translate shaders", step: "metal"))
        handleBuildEvent(.progress(fraction: 0.34, done: 120, total: 350, unit: "MB", eta: 42))
        handleBuildEvent(.say("Sample event: this is the live build reducer."))
    }
    #endif

    func addSelectedGame(buildNow: Bool = false) {
        guard let selection = self.selectedGame else {
            presentBuildError(NXLibraryError.noSelectedGame)
            return
        }
        let files = self.selectedSources
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
        let customName = self.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customName.isEmpty { detected.name = customName }
        let useFolderMode = self.selectedGameFolder != nil
            && self.selectedPackageURLs == nil
            && self.detectedGames.count == 1
            && files.count == selection.files.count
            && files.allSatisfy { $0.layout == .package }
        do {
            let game = try addGame(
                detected: detected,
                selected: sources,
                folder: useFolderMode ? self.selectedGameFolder : nil,
                bundleId: self.bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : self.bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            // Existing titles start Review with their saved settings. The
            // values the user confirms are the values used at the next launch.
            if let gameSettings = app.runtimeSettings.gameSettings(for: game) {
                try gameSettings.migrate()
                try gameSettings.apply(pendingRuntimeConfig, changedFrom: gameSettings.runtimeConfig())
            } else {
                try pendingRuntimeConfig.save(for: game)
            }
            app.librarySelection.selectedGameID = game.id
            app.logs.append(LogEntry(level: .success, message: L10n.format("Added %@ to the library.", [String(describing: game.name)])))
            if buildNow, canStartBuild {
                startBuild(for: game)
            } else {
                self.resetWizard()
            }
        } catch {
            presentBuildError(error)
        }
    }

    @discardableResult
    func addGame(detected: DetectedGame, selected: [DetectedSource],
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
        let root = BuildScratch.choose(core: app.core, appFolder: app.gameAppsFolder).workspaces
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
                         requiresTitleSelection: $0.requiresTitleSelection, nupProgram: $0.nupProgram)
        }
        game.workspacePath = workspace.directory.path
        game.buildCachePath = workspace.buildCache.path
        game.status = .notBuilt
        game.settings = pendingRuntimeConfig

        let catalog = try app.catalogRepository.mergeNXNative(scanned: [game], replacingSources: true, enableSource: true)
        app.applyCatalog(catalog)
        return catalog.nxnativeGames.first(where: { $0.titleId == titleId }) ?? game
    }

    func startBuild(for game: PortedGame, extraArguments: [String] = []) {
        do {
            try beginBuild(for: game, extraArguments: extraArguments)
        } catch {
            presentBuildError(error)
        }
    }

    func beginBuild(for game: PortedGame, extraArguments: [String] = []) throws {
        guard !app.isBuilding else { throw NXLibraryError.buildAlreadyRunning }
        guard !app.isCleaningStorage else { throw NXLibraryError.environmentBlocked(L10n.text("wait for storage cleanup to finish")) }
        guard !app.isUpdatingApp else { throw NXLibraryError.environmentBlocked(L10n.text("wait for the app update to finish")) }
        guard !app.appIcon.appIconsInFlight.contains(game.id) else {
            throw NXLibraryError.environmentBlocked(L10n.text("wait for the app icon update to finish"))
        }
        var target = app.libraryGames.first(where: { $0.id == game.id }) ?? game
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
            throw NXLibraryError.environmentBlocked(L10n.text("These sources need an engine with extracted-folder or multi-title support."))
        }
        guard SourceSelection.matchesNUPProgram(target.sources, titleID: titleId) else {
            throw NXLibraryError.environmentBlocked(L10n.text("The selected NUP program no longer matches this game. Choose the source again."))
        }
        if requiresKeys {
            guard app.setup.isProdKeysValid, FileManager.default.fileExists(atPath: app.setup.keyStore.keyURL.path) else {
                throw NXLibraryError.missingKeys
            }
            // A few kilobytes per file: keys that cannot open the game stop here, not minutes into the extraction.
            let keyOutcome = KeyCheck.run(keysURL: app.setup.keyStore.keyURL,
                                          files: KeyCheck.parts(target.sources.map { ($0.kind, $0.url) }))
            if keyOutcome.blocks, let reason = PortingFailureReason.from(keyOutcome) {
                throw NXLibraryError.keyCheck(reason, game: target.name)
            }
        } else if !app.setup.engineSourceCapabilities.extractedFolders {
            throw NXLibraryError.environmentBlocked(L10n.text("This engine does not support extracted folders."))
        }
        guard app.setup.isNxnativeValid else { throw NXLibraryError.engineMissing }
        guard let environmentStatus = app.setup.environmentStatus else {
            throw NXLibraryError.environmentBlocked(L10n.text("the environment check is still running"))
        }
        guard environmentStatus.canBuild else {
            throw NXLibraryError.environmentBlocked(environmentStatus.issues.joined(separator: "; "))
        }

        // Re-check at build time: the engine tree, Metal compiler or CLI may
        // have changed since the last Settings/launch check.
        let checker = CompatibilityChecker(
            repoURL: URL(fileURLWithPath: app.setup.nxnativePath),
            toolchain: app.setup.engineToolchain,
            developerDir: app.setup.resolvedDeveloperDir()
        )
        let report = try? checker.check(expectedEngineCommit: app.setup.activeEngineCommit)
        app.setup.compatibilityReport = report
        if report?.ok != true && !app.setup.allowUntestedToolchain {
            let reason = report?.checks.filter { $0.status == .block }
                .map { "\($0.title): \($0.detail)" }.joined(separator: "; ")
                ?? "the compatibility check is unavailable"
            throw NXLibraryError.incompatibleToolchain(reason)
        }
        app.setup.environmentCheckGeneration = UUID()
        app.setup.isCheckingEnvironment = false
        let certified = report?.ok == true && !app.setup.allowUntestedToolchain && !app.setup.usesNewestEngine
        activeBuildToolchain = ToolchainInfo(engineCommit: app.setup.activeEngineCommit,
            metalVersion: environmentStatus.metalVersion, xcodeVersion: environmentStatus.xcodeVersion,
            verified: certified,
            note: certified ? "Certified toolchain"
                : app.setup.usesNewestEngine ? "Newest engine, not yet tested by Arcane"
                : "Untested toolchain (explicit override)")

        let merged = try app.catalogRepository.mergeNXNative(scanned: [target], enableSource: true)
        app.applyCatalog(merged)
        guard let stored = merged.nxnativeGames.first(where: { $0.titleId == titleId }) else {
            throw NXLibraryError.missingSources
        }
        target = stored
        buildPreviousStatus = target.status
        app.currentBuildGameID = target.id
        app.lastBuildGameID = target.id

        let workspace: Workspace
        let existingDirectory = target.workspacePath.map { URL(fileURLWithPath: $0) }
        let existingNames = Set(existingDirectory.flatMap {
            (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? []
        } ?? [])
        let expectedNames = target.sources.map { $0.url.lastPathComponent }
        let existingLinksOK = existingDirectory.map { directory in
            FileManager.default.fileExists(atPath: directory.path)
                && app.workspaceManager.brokenLinks(in: directory).isEmpty
                && expectedNames.allSatisfy { existingNames.contains($0) }
        } ?? false
        // On the app's drive when it can hold builds: the Mac's disk needs no room, the install is a rename.
        let scratch = BuildScratch.choose(core: app.core, appFolder: finalApp.deletingLastPathComponent(),
                                          existingWorkspace: existingDirectory)
        let managed = existingDirectory.map { BuildScratch.isManaged($0, core: app.core) } ?? false
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

        do {
            app.applyCatalog(try app.catalogRepository.updateNXNative(id: target.id) {
                $0.workspacePath = target.workspacePath
                $0.buildCachePath = target.buildCachePath
            })
        } catch { app.reportCatalogFailure(error); throw error }

        let requiredDisk = SourceSelection.uniqueSize(target.sources) * 2 + 10_000_000_000
        var measured = Set<UInt64>()
        for volume in [workspace.directory, scratch.temp, finalApp.deletingLastPathComponent()] {
            if let device = BuildScratch.Volume.of(volume)?.device, !measured.insert(device).inserted { continue }
            if let free = freeBytes(at: volume), free < requiredDisk {
                let freeText = AppViewModel.formatBytes(free)
                let requiredText = AppViewModel.formatBytes(requiredDisk)
                let why = scratch.appDriveUnsupported
                    ? L10n.text(" The Game apps folder's drive can't hold build files (it needs APFS or Mac OS Extended), so the build uses this Mac's disk.")
                    : ""
                throw NXLibraryError.environmentBlocked(
                    L10n.format("Not enough free space at %@: %@ available, %@ needed.%@", [String(describing: volume.path), String(describing: freeText), String(describing: requiredText), String(describing: why)]))
            }
        }

        let repo = URL(fileURLWithPath: app.setup.nxnativePath)
        let toolchain = app.setup.engineToolchain
        guard FileManager.default.isExecutableFile(atPath: toolchain.python.path) else {
            throw NXLibraryError.environmentBlocked(toolchain.isBundled
                ? L10n.text("the bundled Python is missing; reinstall Arcane")
                : L10n.text("the nxnative venv Python is missing"))
        }

        let tempRoot = scratch.temp.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let tempApp = tempRoot.appendingPathComponent(finalApp.lastPathComponent)
        let logURL = app.core.appendingPathComponent("Logs").appendingPathComponent("\(titleId).log")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let command = BuildCommandBuilder.make(
            repo: repo,
            toolchain: toolchain,
            workspace: workspace.directory,
            keys: requiresKeys ? app.setup.keyStore.keyURL : nil,
            output: tempApp,
            developerDir: app.setup.resolvedDeveloperDir(),
            appName: target.name,
            bundleId: target.bundleId ?? "org.nxnative.\(titleId.lowercased())",
            language: app.runtimeSettings.loadRuntimeConfig(for: target).languageForBuild,
            titleId: app.setup.engineSourceCapabilities.titleSelection ? titleId : nil,
            programIndex: SourceSelection.programIndex(for: target.sources, titleID: titleId,
                                                       nupPrograms: app.setup.engineSourceCapabilities.nupPrograms),
            packageVersion: app.setup.engineSourceCapabilities.titleSelection
                ? SourceSelection.packageVersion(for: target.sources, stagedSelection: !workspace.links.isEmpty) : nil,
            allowUntestedToolchain: app.setup.allowUntestedToolchain,
            extraArguments: extraArguments
        )
        lastPortingCommand = [command.executable.path] + command.arguments

        stopStageElapsedTimer()
        buildStartedAt = Date()
        buildTempDirectory = tempRoot
        app.buildLogURL = logURL
        currentBuildCacheURL = workspace.buildCache
        isPollingPipelineArchive = false
        self.buildWizardStep = 3
        app.isBuilding = true
        // The request belongs to an accepted porting, never to startup or Steam-only use.
        NotificationService.shared.requestAuthorization()
        self.isCancellingBuild = false
        self.buildState = .running
        self.buildError = nil
        self.portingFailureReason = nil
        app.lastError = nil
        self.buildSuccessPath = nil
        self.buildHeldGameID = nil
        self.progressFraction = 0
        self.currentStageName = "Preparing build"
        self.currentStepName = ""
        self.stageIndex = 0
        self.totalStages = 0
        self.etaSeconds = nil
        self.buildStages.removeAll()
        app.portingProgress = PortingProgress()
        app.frontGameID = target.id
        app.logs.append(LogEntry(level: .info,
                             message: L10n.format("Build started for %@ (%@).", [String(describing: target.name), String(describing: titleId)])))
        app.logs.append(LogEntry(level: .info,
                             message: L10n.format("Workspace: %@", [String(describing: workspace.directory.path)])))
        app.logs.append(LogEntry(
            level: .info,
            message: report?.ok == true
                ? L10n.text("Toolchain gate: certified.")
                : L10n.text("Toolchain gate: overridden; this build will be recorded as untested.")
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
            acquireInstall: { [weak self] in self?.app.acquireSaveInstallLease(for: target) },
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

    func cancelBuild() {
        guard app.isBuilding, let buildService else { return }
        stopStageElapsedTimer()
        self.isCancellingBuild = true
        self.currentStageName = "Cancelling build..."
        app.logs.append(LogEntry(level: .warning, message: L10n.text("Cancelling build...")))
        buildService.cancel()
    }

    func openOutputInFinder() {
        guard let path = self.buildSuccessPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openBuildLog() {
        guard let url = app.buildLogURL else {
            app.lastError = "No build log is available yet."
            app.logs.append(LogEntry(level: .warning, message: app.lastError!))
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

    func retryLastBuild() {
        guard let id = app.lastBuildGameID,
              let game = app.libraryGames.first(where: { $0.id == id }) else {
            app.lastError = "The last built game is no longer in the library."
            app.logs.append(LogEntry(level: .error, message: app.lastError!))
            return
        }
        if app.canRetryReadyInstall {
            app.installPendingBuilds(only: id, automatic: false)
            return
        }
        startBuild(for: game)
    }

    func handleBuildEvent(_ event: BuildEvent) {
        app.portingProgress?.apply(event)
        switch event {
        case .stage(let k, let n, let name, let step):
            let now = Date()
            pipelinePollGeneration = UUID()
            isPollingPipelineArchive = false
            currentStageStartedAt = now
            self.currentStageName = name
            self.stageIndex = k
            self.totalStages = n
            for index in self.buildStages.indices
            where self.buildStages[index].id < k && self.buildStages[index].isRunning {
                self.buildStages[index].isRunning = false
                self.buildStages[index].isCompleted = true
            }
            if let index = self.buildStages.firstIndex(where: { $0.id == k }) {
                self.buildStages[index].isRunning = true
                self.buildStages[index].step = step ?? ""
                if self.buildStages[index].elapsedSeconds == nil {
                    self.buildStages[index].elapsedSeconds = 0
                }
            } else {
                self.buildStages.append(BuildStageItem(id: k, name: name,
                                                  step: step ?? "", isRunning: true,
                                                  elapsedSeconds: 0))
            }
            startStageElapsedTimerIfNeeded()
            if let step, !step.isEmpty { self.currentStepName = step }
            app.logs.append(LogEntry(level: .step, message: "[\(k)/\(n)] \(name)"))

        case .step(let step):
            self.currentStepName = step
            if let index = self.buildStages.firstIndex(where: { $0.id == self.stageIndex }) {
                self.buildStages[index].step = step
            }
            app.logs.append(LogEntry(level: .info, message: "↳ \(step)"))

        case .progress(let fraction, let done, let total, let unit, let eta, let elapsed):
            self.progressFraction = min(max(fraction, 0), 1)
            self.etaSeconds = eta
            if let elapsed,
               let index = self.buildStages.firstIndex(where: { $0.id == self.stageIndex && $0.isRunning }) {
                self.buildStages[index].elapsedSeconds = elapsed
                currentStageStartedAt = Date().addingTimeInterval(-elapsed)
            }
            if let done, let total, total > 0 {
                if let unit, !unit.isEmpty,
                   unit.lowercased() != "b", unit.lowercased() != "bytes" {
                    let percent = Int((min(1, max(0, done / total)) * 100).rounded(.down))
                    self.currentStepName = "\(Self.formatAmount(done)) / \(Self.formatAmount(total)) \(unit) (\(percent)%)"
                } else {
                    let doneText = AppViewModel.formatBytes(Int64(done))
                    let totalText = AppViewModel.formatBytes(Int64(total))
                    self.currentStepName = "\(doneText) / \(totalText)"
                }
            }

        case .stageEnd(let name, let ok, let elapsed, let summary, let warn):
            pipelinePollGeneration = UUID()
            isPollingPipelineArchive = false
            let warned = ok && warn
            if let index = self.buildStages.firstIndex(where: { $0.name == name })
                ?? self.buildStages.firstIndex(where: { $0.isRunning }) {
                self.buildStages[index].isRunning = false
                self.buildStages[index].isCompleted = ok
                self.buildStages[index].isFailed = !ok
                self.buildStages[index].hasWarning = warned
                self.buildStages[index].elapsedSeconds = elapsed ?? self.buildStages[index].elapsedSeconds
                self.buildStages[index].summary = summary
            }
            app.logs.append(LogEntry(
                level: warned ? .warning : ok ? .success : .error,
                message: "\(warned ? "⚠" : ok ? "✓" : "✗") \(name)\(summary.map { " — \($0)" } ?? "")"
            ))

        case .say(let message):
            app.logs.append(LogEntry(level: .info, message: message))

        case .log(let line):
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                app.logs.append(LogEntry(level: .info, message: trimmed))
            }
        }
    }

    func startStageElapsedTimerIfNeeded() {
        guard !self.isCancellingBuild, stageElapsedTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tickStageElapsed() }
        stageElapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopStageElapsedTimer() {
        pipelinePollGeneration = UUID()
        stageElapsedTimer?.invalidate()
        stageElapsedTimer = nil
        currentStageStartedAt = nil
        isPollingPipelineArchive = false
    }

    func tickStageElapsed() {
        guard app.isBuilding, !self.isCancellingBuild, let started = currentStageStartedAt,
              let index = self.buildStages.firstIndex(where: { $0.id == self.stageIndex && $0.isRunning }) else { return }
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(started))
        self.buildStages[index].elapsedSeconds = elapsed

        if self.currentStageName == PortingProgress.pipelineArchiveStageName,
           let cacheURL = currentBuildCacheURL,
           !isPollingPipelineArchive {
            isPollingPipelineArchive = true
            let logURL = cacheURL.appendingPathComponent("logs/pso_offline_mac.log")
            let generation = pipelinePollGeneration
            let architectures = self.buildStages[index].step.split(separator: " ").first?
                .split(separator: ",").map { $0.hasPrefix("applegpu_") ? String($0) : "applegpu_" + $0 } ?? []
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let event = PipelineArchiveProgress().poll(logURL: logURL, architectures: architectures,
                                                           stageStartedAt: started, now: Date())
                DispatchQueue.main.async {
                    guard let self, self.pipelinePollGeneration == generation else { return }
                    self.isPollingPipelineArchive = false
                    if let event, self.app.isBuilding, !self.isCancellingBuild, self.currentStageName == PortingProgress.pipelineArchiveStageName {
                        self.handleBuildEvent(event)
                    }
                }
            }
        }
    }

    func finishBuild(_ result: BuildResult, gameID: UUID,
                             finalApp: URL, tempDir: URL) {
        stopStageElapsedTimer()
        currentBuildCacheURL = nil
        app.portingProgress?.finish(success: result.success)
        app.isBuilding = false
        self.isCancellingBuild = false
        buildService = nil
        if result.heldApp == nil { try? FileManager.default.removeItem(at: tempDir) }
        buildTempDirectory = nil

        // Displayed state can retain a finished result for an explicit retry,
        // but is never serialized as a replacement catalog.
        if var game = app.libraryGames.first(where: { $0.id == gameID }) {
            let toolchain = activeBuildToolchain ?? ToolchainInfo(engineCommit: app.setup.activeEngineCommit, verified: false)
            let verified = toolchain.verified
            let record = BuildRecord(
                startedAt: buildStartedAt ?? Date(),
                endedAt: Date(),
                exitCode: result.exitCode,
                logPath: result.logURL.path,
                outputPath: result.success || result.installationFailed ? finalApp.path : nil,
                engineCommit: toolchain.engineCommit ?? app.setup.activeEngineCommit,
                metalVersion: toolchain.metalVersion,
                xcodeVersion: toolchain.xcodeVersion,
                toolchainVerified: verified,
                cancelled: result.cancelled
            )

            if result.success || result.installationFailed {
                _ = app.authorizeDevelopmentOperation(.build, game: game)
                _ = app.authorizeDevelopmentOperation(.icon, game: game)
                if let held = result.heldApp {
                    PendingInstaller.hold(PendingInstall(tempApp: held, finalApp: finalApp,
                                                         record: record, toolchain: toolchain), for: &game)
                    self.buildHeldGameID = game.id
                } else {
                    PendingInstaller.discard(&game)
                    game.recordInstalledBuild(record, toolchain: toolchain, at: finalApp,
                                              version: Self.appVersion(at: finalApp), date: Date())
                    // A new app has the build's icon: the player's goes back on (AppIconModel).
                    game.appIconPending = true
                }
                if let seconds = app.portingProgress?.finishingElapsed, seconds > 0 {
                    lastPortingFinishSeconds = seconds
                }
                self.progressFraction = 1
                self.currentStageName = result.heldApp == nil ? "Build completed" : PendingInstall.stageName
                if result.installationFailed {
                    self.currentStageName = "Installation failed"
                    self.buildState = .failed
                    self.buildSuccessPath = nil
                    self.buildError = "The build is ready. Retry installation."
                    self.portingFailureReason = nil
                    app.lastError = result.error
                    app.presentInstallFailure(for: game, error: result.error ?? "Installation failed.")
                } else {
                    self.buildState = .succeeded
                    self.buildSuccessPath = finalApp.path
                    self.buildError = nil
                    app.lastError = nil
                    app.logs.append(LogEntry(level: .success, message: result.heldApp == nil
                        ? L10n.format("Build succeeded: %@", [String(describing: finalApp.path)])
                        : L10n.format("Build succeeded while %@ is open: it installs when the game quits.", [String(describing: game.name)])))
                    SoundEffectService.shared.play(.launch)
                    notifyPortingEnded(game, success: true, held: result.heldApp != nil)
                }
            } else if result.cancelled {
                game.status = buildPreviousStatus
                    ?? (game.sources.isEmpty ? .builtSourcesMissing : .notBuilt)
                game.portingFailure = .cancelled
                game.portingFailureReason = nil
                self.buildState = .cancelled
                self.buildError = nil
                self.portingFailureReason = nil
                app.lastError = "Build cancelled."
                app.logs.append(LogEntry(level: .warning, message: L10n.text("Build cancelled.")))
            } else {
                let reason = PortingFailureClassifier.classify(
                    log: buildLogTail(result.logURL),
                    keysPath: SourceSelection.requiresKeys(game.sources) ? app.setup.keyStore.keyURL.path : "",
                    sourcePaths: game.sources.map(\.url.path)
                )
                let message = reason.what(game: game.name)
                game.status = .failed
                game.portingFailure = .failed
                game.portingFailureReason = reason
                self.buildState = .failed
                self.buildError = message
                self.portingFailureReason = reason
                app.lastError = message
                app.logs.append(LogEntry(level: .error,
                                     message: result.error ?? L10n.format("Build failed (exit code %@).", [String(describing: result.exitCode)])))
                app.logs.append(LogEntry(level: .error, message: "\(reason.title). \(message) \(reason.next)"))
                SoundEffectService.shared.play(.error)
                notifyPortingEnded(game, success: false)
            }

            let saved = app.persistBuildOutcome(game)
            if result.success && saved {
                if result.heldApp == nil { app.appIcon.appIconBuildLogs[gameID] = result.logURL }
                app.loadLibrary()
                app.appIcon.syncPendingAppIcons()
            }
        } else {
            self.buildState = result.success ? .succeeded
                : (result.cancelled ? .cancelled : .failed)
            if !result.success && !result.cancelled {
                self.buildError = result.error
                app.lastError = result.error
            }
        }

        buildStartedAt = nil
        buildPreviousStatus = nil
        app.currentBuildGameID = nil
        activeBuildToolchain = nil
    }

    func presentBuildError(_ error: Error) {
        let message = error.localizedDescription
        self.buildState = .failed
        self.buildError = message
        if case .keyCheck(let reason, _) = error as? NXLibraryError {
            self.portingFailureReason = reason
        } else {
            self.portingFailureReason = nil
        }
        app.lastError = message
        app.alertMessage = message
        app.logs.append(LogEntry(level: .error, message: message))
        SoundEffectService.shared.play(.error)
    }

    static func formatAmount(_ value: Double) -> String {
        if value.rounded() == value { return String(format: "%.0f", value) }
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    func detectedGame(from game: PortedGame) throws -> DetectedGame {
        let sources = game.sources.compactMap { item -> DetectedSource? in
            guard let titleId = item.titleId.flatMap({ UInt64($0, radix: 16) }) else {
                return nil
            }
            let version = item.versionString.flatMap {
                Int($0.lowercased().hasPrefix("v") ? String($0.dropFirst()) : $0)
            }
            return DetectedSource(url: item.url, kind: item.kind, titleId: titleId,
                                  version: version, sizeBytes: item.sizeBytes, layout: item.layout,
                                  requiresTitleSelection: item.requiresTitleSelection == true, nupProgram: item.nupProgram)
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

    static func detectedSource(from file: GameFileItem) -> DetectedSource? {
        guard let titleId = file.titleId.flatMap({ UInt64($0, radix: 16) }) else {
            return nil
        }
        let version = file.versionString.flatMap {
            Int($0.lowercased().hasPrefix("v") ? String($0.dropFirst()) : $0)
        }
        return DetectedSource(url: file.url, kind: file.type, titleId: titleId,
                              version: version, sizeBytes: file.sizeBytes, layout: file.layout,
                              requiresTitleSelection: file.requiresTitleSelection == true, nupProgram: file.nupProgram)
    }

    static func appVersion(at app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return object["CFBundleShortVersionString"] as? String
    }

    // MARK: - Failure actions
    /// Restarts the failed porting once with the reason's one `--allow-*` flag; the flag is not
    /// remembered, and the Metal gate's flag still comes from the persisted override.
    func portAnyway() {
        guard case .portAnyway(let flag) = self.portingFailureReason?.action,
              let id = app.lastBuildGameID,
              let game = app.libraryGames.first(where: { $0.id == id }) else { return }
        startBuild(for: game, extraArguments: PortingFailureClassifier.arguments([], adding: flag))
    }

    func notifyPortingEnded(_ game: PortedGame, success: Bool, held: Bool = false) {
        let appActive = NSApp?.isActive ?? true
        guard PortingNotice.shouldNotify(success: success, cancelled: false,
                                         enabled: app.settingsStore?.settings.notifyPortingEnds ?? true,
                                         appActive: appActive) else { return }
        NotificationService.shared.sendPortingEnded(gameID: game.id, gameName: game.name, success: success,
                                                    reason: game.portingFailureReason, held: held)
    }

    /// Puts the Porting step back on the last failed porting, from what the game saved.
    func restoreLastFailure() -> Bool {
        guard let id = app.lastBuildGameID, let game = app.libraryGames.first(where: { $0.id == id }),
              game.portingFailure == .failed else { return false }
        let reason = game.portingFailureReason ?? PortingFailureReason(kind: .unknown)
        self.portingFailureReason = reason
        self.buildError = reason.what(game: game.name)
        self.buildSuccessPath = nil
        self.buildState = .failed
        self.buildWizardStep = 3
        self.addGameSessionActive = true
        return true
    }

    func performFailureAction(_ action: PortingFailureAction, router: AppRouter) {
        switch action {
        case .portAnyway: portAnyway()
        case .openEngineSettings: router.openSettings(.engine)
        case .openSetup: app.reopenSetup()
        case .importKeys: app.setup.selectProdKeysFile()
        case .openStorage: router.openSettings(.portingStorage)
        case .none: break
        }
    }

    // MARK: - Folders, space and timing
    func freeBytes(at url: URL) -> Int64? {
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
    /// The folders a build writes to: its workspace (a player's own one beside the sources is kept), its staged app
    /// and the app's folder. They are on the app's drive when it can hold builds.
    func buildFolders(appFolder: URL, workspace: String?) -> [URL] {
        let existing = workspace.map { URL(fileURLWithPath: $0) }
        let scratch = BuildScratch.choose(core: app.core, appFolder: appFolder, existingWorkspace: existing)
        let own = existing.flatMap { BuildScratch.isManaged($0, core: app.core) ? nil : $0 }
        return [own ?? scratch.workspaces, scratch.temp, appFolder]
    }
    func finalAppURL(for game: PortedGame) -> URL {
        GameAppDestination.url(for: game, in: app.gameAppsFolder)
    }
    func supportsSources(_ sources: [GameFileItem]) -> Bool {
        let capabilities = app.setup.engineSourceCapabilities
        return SourceSelection.supported(sources, titleSelection: capabilities.titleSelection,
                                         extractedFolders: capabilities.extractedFolders,
                                         nupContainers: capabilities.nupContainers,
                                         nupPrograms: capabilities.nupPrograms)
    }
    private var didSeedFinishSeconds = false
    /// What the final stages took in the last successful porting on this Mac, for the ETA.
    /// Seeded once from the newest porting log when nothing is stored yet.
    var lastPortingFinishSeconds: Double? {
        get {
            let stored = AppData.preferences.double(forKey: AppViewModel.StorageKeys.lastPortingFinishSeconds)
            if stored > 0 { return stored }
            guard !didSeedFinishSeconds else { return nil }
            didSeedFinishSeconds = true
            guard let seeded = Self.finishSecondsFromNewestLog(in: app.core.appendingPathComponent("logs")) else {
                return nil
            }
            AppData.preferences.set(seeded, forKey: AppViewModel.StorageKeys.lastPortingFinishSeconds)
            return seeded
        }
        set { AppData.preferences.set(newValue ?? 0, forKey: AppViewModel.StorageKeys.lastPortingFinishSeconds) }
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
    /// `kept`: folders of builds that wait for their game to quit (standardized paths).
    static func sweepStaleBuildTemp(in folders: [URL], keeping kept: Set<String>) {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for temp in folders {
            sweepStaleBuildTemp(temp, before: cutoff, keeping: kept)
        }
    }
    private static func sweepStaleBuildTemp(_ temp: URL, before cutoff: Date, keeping kept: Set<String>) {
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
}
