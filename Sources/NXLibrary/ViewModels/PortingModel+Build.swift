import AppKit
import Foundation
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// Starting a porting: the keys against the selection, adding the game, the build and its controls.
extension PortingModel {
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
            // A workspace Arcane left on another drive is only a cache now: that drive gets its room back.
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
}
