import AppKit
import NXLibraryCore

extension AppViewModel {
    func showAllSaveBackups() {
        do {
            try FileManager.default.createDirectory(at: saveBackupRoot, withIntermediateDirectories: true)
            NSWorkspace.shared.open(saveBackupRoot)
        } catch {
            showSettingsNotice(title: L10n.text("Folder unavailable"), message: L10n.text("The backup folder could not be opened."))
        }
    }

    var saveBackupRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NXLibrary/SaveBackups")
    }
    func saveContext(for game: PortedGame) throws -> SaveContext {
        guard let id = game.titleId else { throw SaveFailure.invalidTitleID }
        let libraryFolder: String? = Thread.isMainThread
            ? settingsStore?.settings.cloudSaves.folderURL()?.path
            : DispatchQueue.main.sync { self.settingsStore?.settings.cloudSaves.folderURL()?.path }
        var gameCloud: String?
        if let domain = game.effectiveBundleId {
            CFPreferencesAppSynchronize(domain as CFString)
            if let value = CFPreferencesCopyAppValue(CloudSaves.preferenceKey as CFString, domain as CFString) {
                guard let text = value as? String else { throw SaveFailure.unreadableConfiguration }
                gameCloud = text
            }
        }
        // The installed launcher's Info.plist decides its data directory. Do not redirect an inconsistent record.
        let plist = game.url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let installedID = info["DMTitleID"] as? String,
              SaveLocation.validID(installedID), installedID.uppercased() == id.uppercased() else {
            throw SaveFailure.invalidTitleID
        }
        return try SaveLocation.inspect(titleID: id, appURL: game.url,
            home: FileManager.default.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment,
            gameCloudFolder: gameCloud, libraryCloudFolder: libraryFolder)
    }
    func saveIdentity(for game: PortedGame) -> SaveIdentity {
        SaveIdentity(titleID: (game.titleId ?? "").uppercased(), gameName: game.name,
                     version: game.versionString, buildID: CheatLocator.buildID(appURL: game.url))
    }
    func defaultSaveLocation(for game: PortedGame) throws -> SaveLocation {
        try SaveLocation.defaultLocation(titleID: game.titleId ?? "", home: FileManager.default.homeDirectoryForCurrentUser)
    }
    /// Covers the complete replace operation, also when a successful build arrives from its background queue.
    func acquireSaveInstallLease(for game: PortedGame) -> (() -> Void)? {
        guard let tid = game.titleId else { return nil }
        if let location = try? defaultSaveLocation(for: game), SaveTransaction.needsRecovery(location: location) { return nil }
        guard let token = saveGate.begin(titleID: tid) else { return nil }
        if RunningGameMonitor.runningApplication(for: game) != nil {
            saveGate.end(titleID: tid, token: token); return nil
        }
        return { [saveGate] in saveGate.end(titleID: tid, token: token) }
    }
    func savesPermitPlay(_ game: PortedGame) -> Bool {
        guard let tid = game.titleId else { return true }
        if let location = try? defaultSaveLocation(for: game), SaveTransaction.needsRecovery(location: location) {
            recoverSavesAtStartup()
            alertMessage = "This game's save needs recovery. Wait for recovery to finish, then press Play again. Backups are in \(saveBackupRoot.path)."
            return false
        }
        if saveGate.isBusy(titleID: tid) {
            alertMessage = "This game's saves are being managed or need recovery. Finish that operation before Play."
            return false
        }
        return true
    }
    /// Only app-owned journals for known games; no startup walk through save contents.
    func recoverSavesAtStartup() {
        for game in libraryGames {
            guard let location = try? defaultSaveLocation(for: game), SaveTransaction.needsRecovery(location: location),
                  RunningGameMonitor.runningApplication(for: game) == nil,
                  let token = saveGate.begin(titleID: location.titleID, recovering: true) else { continue }
            saveGate.setRecoveryBlocked(true, titleID: location.titleID)
            let store = SaveSnapshotStore(root: saveBackupRoot)
            saveQueue.async { [weak self] in
                guard let self else { return }
                var failure: Error?
                do { try SaveTransaction(store: store, isRunning: { RunningGameMonitor.runningApplication(for: game) != nil }).recover(location: location) }
                catch { failure = error }
                self.saveGate.setRecoveryBlocked(failure != nil, titleID: location.titleID)
                self.saveGate.end(titleID: location.titleID, token: token)
                let message = failure?.localizedDescription
                DispatchQueue.main.async {
                    if let message {
                        self.logs.append(LogEntry(level: .error, message: L10n.format("Save recovery for %@: %@ Backups: %@", [String(describing: (game.name)), String(describing: (message)), String(describing: (self.saveBackupRoot.path))])))
                    } else {
                        self.logs.append(LogEntry(level: .info, message: L10n.format("Save recovery completed for %@.", [String(describing: (game.name))])))
                        self.installPendingBuilds()
                    }
                }
            }
        }
    }
}
