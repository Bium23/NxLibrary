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

    /// The ETA seed was read from the newest porting log once (`lastPortingFinishSeconds`).
    var didSeedFinishSeconds = false
}
