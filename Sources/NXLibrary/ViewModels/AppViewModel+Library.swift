import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// The library: dropped files, loading and scanning, importing existing builds, finding sources and the library folder (`applyCatalog`, which writes the published library, stays in the type).
extension AppViewModel {
    // MARK: - Drag and Drop & ZIP
    func handleDroppedURLs(_ urls: [URL]) {
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
    func refreshLibrary() {
        loadLibrary()
    }

    func loadLibrary() {
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
    func scanLibrary(using current: CatalogDocument) {
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
                    self.appIcon.reconcileAppIcons()
                } catch { self.reportCatalogFailure(error) }
                self.libraryScanWarnings = scanWarnings
                for warning in scanWarnings { self.logs.append(LogEntry(level: .warning, message: warning)) }
            }
        }
    }

    func importExistingBuilds() {
        do { applyCatalog(try catalogRepository.configureSource(.nxnative, enabled: true, root: nil)); loadLibrary() }
        catch { reportCatalogFailure(error) }
    }

    /// Attach source files to an already-imported app. The app URL, version and
    /// build metadata stay intact; the library entry is merged, never duplicated.
    func locateSources(for game: PortedGame) {
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
        let repo = URL(fileURLWithPath: setup.nxnativePath)
        let toolchain = setup.engineToolchain
        let keys = setup.isProdKeysValid ? setup.keyStore.keyURL : nil
        let developer = setup.resolvedDeveloperDir()
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
                        message: L10n.format("Sources attached to %@; rebuild is now available if the toolchain gate allows it.", [String(describing: game.name)])))
                } catch {
                    self.alertMessage = error.localizedDescription
                    self.logs.append(LogEntry(level: .error, message: error.localizedDescription))
                }
            }
        }
    }

    func selectLibraryFolder() {
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
}
