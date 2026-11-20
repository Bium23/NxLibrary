import AppKit
import Foundation
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// Add Game: reading the chosen folder or files, the selection and the wizard's steps.
extension PortingModel {
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
        guard Self.wizardStepReachable(step, hasSelectedGame: selectedGame != nil) else { return }
        self.buildWizardStep = step
    }

    /// Options need a chosen game; Files and Porting are always reachable.
    static func wizardStepReachable(_ step: Int, hasSelectedGame: Bool) -> Bool {
        (1...3).contains(step) && (step != 2 || hasSelectedGame)
    }

    /// The step Back (Esc, B) returns to, or nil when Back closes Add Game. A running porting goes on
    /// behind the home; a finished one has spent its choices; a Rebuild never filled the steps before Porting.
    static func stepBack(from step: Int, isBuilding: Bool, succeeded: Bool, hasSelectedGame: Bool) -> Int? {
        guard !isBuilding, !succeeded, step > 1, wizardStepReachable(step - 1, hasSelectedGame: hasSelectedGame) else {
            return nil
        }
        return step - 1
    }

    /// Whether closing Add Game asks before dropping the chosen files: never while a porting runs
    /// or after it succeeded, since nothing is lost then.
    static func closingAsks(isBuilding: Bool, succeeded: Bool, hasDraft: Bool) -> Bool {
        !isBuilding && !succeeded && hasDraft
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
}
