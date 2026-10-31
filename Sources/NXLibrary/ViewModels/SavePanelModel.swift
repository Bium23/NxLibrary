import AppKit
import Combine
import NXLibraryCore

/// One panel's state; filesystem work runs on the library's serial save queue.
final class SavePanelModel: ObservableObject {
    enum Activity { case refresh, backup, importSave, restore }
    @Published private(set) var busy = false
    @Published private(set) var activity: Activity = .refresh
    @Published private(set) var failed = false
    @Published private(set) var message: String?
    @Published private(set) var context: SaveContext?
    @Published private(set) var snapshots: [SaveSnapshot] = []
    @Published private(set) var preview: SaveImportPreview?
    @Published private(set) var restorePreview: SaveRestorePreview?
    @Published private(set) var currentBytes: Int64 = 0
    @Published private(set) var currentDate: Date?
    @Published private(set) var running = false
    @Published private(set) var recoveryRequired = false
    let game: PortedGame
    private let viewModel: AppViewModel
    private let store: SaveSnapshotStore
    private var lease: UUID?
    private var abandoned = false
    var backupsURL: URL { viewModel.saveBackupRoot.appendingPathComponent((game.titleId ?? "").uppercased()) }
    var canMutate: Bool { !busy && !running && !recoveryRequired && context != nil && context?.cloudReason == nil }
    init(viewModel: AppViewModel, game: PortedGame) {
        self.viewModel = viewModel; self.game = game
        self.store = SaveSnapshotStore(root: viewModel.saveBackupRoot)
    }
    var importAction: SavePresentation.ImportAction {
        SavePresentation.importAction(available: context != nil, busy: busy, running: running,
                                      recovery: recoveryRequired, cloud: context?.cloudReason != nil)
    }
    var statusTitle: String? {
        if failed {
            switch activity {
            case .backup: return "Backup failed"
            case .refresh: return "Refresh failed"
            case .importSave: return "Import failed"
            case .restore: return "Restore failed"
            }
        }
        return message
    }
    private func acquire(activity: Activity = .refresh, recovering: Bool = false) -> Bool {
        guard !busy, lease == nil, let tid = game.titleId,
              let token = viewModel.saveGate.begin(titleID: tid, recovering: recovering) else {
            message = SaveFailure.busy.localizedDescription; failed = true; return false
        }
        lease = token; busy = true; message = nil; failed = false; self.activity = activity
        return true
    }
    private func release() {
        if let lease, let tid = game.titleId { viewModel.saveGate.end(titleID: tid, token: lease) }
        lease = nil; busy = false
        viewModel.installPendingBuilds()
    }
    private func transaction() -> SaveTransaction {
        SaveTransaction(store: store, isRunning: { RunningGameMonitor.runningApplication(for: self.game) != nil },
            validateAccess: {
                try self.viewModel.saveContext(for: self.game).requireWrites()
            })
    }
    func refresh(resultMessage: String? = nil) {
        guard lease == nil, !busy else { return }
        guard acquire(recovering: true) else { return }
        viewModel.saveQueue.async {
            var context: SaveContext?; var list: [SaveSnapshot] = []; var bytes: Int64 = 0; var date: Date?; var error: Error?
            let running = RunningGameMonitor.runningApplication(for: self.game) != nil
            do {
                let location = try self.viewModel.defaultSaveLocation(for: self.game)
                if SaveTransaction.needsRecovery(location: location) {
                    try self.transaction().recover(location: location)
                }
                context = try self.viewModel.saveContext(for: self.game)
                list = try self.store.list(titleID: location.titleID)
                if !running {
                    let inventory = try self.currentInventory(location)
                    bytes = inventory.reduce(0) { $0 + $1.byteCount }
                    date = SaveSlot.allCases.compactMap { try? location.directory($0).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
                }
            } catch let caught { error = caught }
            let recovery = (try? self.viewModel.defaultSaveLocation(for: self.game)).map { SaveTransaction.needsRecovery(location: $0) } ?? false
            self.viewModel.saveGate.setRecoveryBlocked(recovery, titleID: self.game.titleId ?? "")
            DispatchQueue.main.async {
                self.context = context; self.snapshots = list; self.currentBytes = bytes; self.currentDate = date
                self.running = running; self.recoveryRequired = recovery; self.failed = error != nil; self.message = error?.localizedDescription ?? resultMessage
                self.release()
            }
        }
    }
    private func currentInventory(_ location: SaveLocation) throws -> [SaveInventoryEntry] {
        // Inventory is exposed through the same validation used by snapshot creation.
        try store.currentInventory(location: location)
    }
    func backUp() {
        guard acquire(activity: .backup) else { return }
        viewModel.saveQueue.async {
            do {
                guard RunningGameMonitor.runningApplication(for: self.game) == nil else { throw SaveFailure.running }
                let context = try self.viewModel.saveContext(for: self.game)
                let snapshot = try self.store.create(location: context.location, identity: self.viewModel.saveIdentity(for: self.game), reason: .manual)
                DispatchQueue.main.async { self.snapshots.insert(snapshot, at: 0); self.message = "Backup saved"; self.release() }
            } catch { self.finishFailure(error) }
        }
    }
    func chooseImport(slot: SaveSlot) {
        guard canMutate else { return }
        let panel = NSOpenPanel()
        panel.title = "Import a save for \(game.name)"
        panel.message = "Choose the folder containing the actual save files for this game and user, not the emulator's whole save directory."
        panel.prompt = "Preview"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url, acquire(activity: .importSave) else { return }
        viewModel.saveQueue.async {
            do {
                guard RunningGameMonitor.runningApplication(for: self.game) == nil else { throw SaveFailure.running }
                let context = try self.viewModel.saveContext(for: self.game); try context.requireWrites()
                let preview = try self.store.stageImport(source: source, slot: slot, location: context.location)
                DispatchQueue.main.async {
                    self.context = context
                    if self.abandoned { self.preview = preview; self.busy = false; self.cancelPreview() }
                    else { self.preview = preview; self.busy = false } // retain lease through confirmation
                }
            } catch { self.finishFailure(error) }
        }
    }
    func cancelPreview() {
        guard !busy, let context, preview != nil || restorePreview != nil else { return }
        let imported = preview; let restored = restorePreview
        preview = nil; restorePreview = nil; busy = true
        viewModel.saveQueue.async {
            if let imported { try? self.store.discard(imported, location: context.location) }
            if let restored { try? self.store.discardRestore(restored, location: context.location) }
            DispatchQueue.main.async { self.release() }
        }
    }
    func confirmImport() {
        guard let preview, let context, !busy else { return }
        busy = true
        viewModel.saveQueue.async {
            do {
                let backup = try self.transaction().importSave(preview, location: context.location, identity: self.viewModel.saveIdentity(for: self.game))
                try? self.store.discard(preview, location: context.location)
                DispatchQueue.main.async {
                    self.preview = nil; self.snapshots.insert(backup, at: 0); self.message = "Save imported"
                    self.release(); self.refreshAfterSuccess()
                }
            } catch {
                try? self.store.discard(preview, location: context.location)
                self.finishFailure(error, clearPreview: true)
            }
        }
    }
    func prepareRestore(_ snapshot: SaveSnapshot) {
        guard canMutate, acquire(activity: .restore) else { return }
        viewModel.saveQueue.async {
            do {
                guard RunningGameMonitor.runningApplication(for: self.game) == nil else { throw SaveFailure.running }
                let context = try self.viewModel.saveContext(for: self.game); try context.requireWrites()
                let preview = try self.store.stageRestore(snapshot, location: context.location)
                DispatchQueue.main.async {
                    self.context = context; self.restorePreview = preview; self.busy = false
                    if self.abandoned { self.cancelPreview() }
                }
            } catch { self.finishFailure(error) }
        }
    }
    func confirmRestore() {
        guard let preview = restorePreview, let context, !busy else { return }
        busy = true
        viewModel.saveQueue.async {
            do {
                let backup = try self.transaction().restore(preview, location: context.location, identity: self.viewModel.saveIdentity(for: self.game))
                try? self.store.discardRestore(preview, location: context.location)
                DispatchQueue.main.async {
                    self.restorePreview = nil; self.snapshots.insert(backup, at: 0); self.message = "Save restored"
                    self.release(); self.refreshAfterSuccess()
                }
            } catch {
                try? self.store.discardRestore(preview, location: context.location)
                self.finishFailure(error, clearPreview: true)
            }
        }
    }
    private func refreshAfterSuccess() {
        refresh(resultMessage: message)
    }
    private func finishFailure(_ error: Error, clearPreview: Bool = false) {
        var recovery = false
        if let location = try? viewModel.defaultSaveLocation(for: game), SaveTransaction.needsRecovery(location: location) {
            do { try transaction().recover(location: location) } catch { recovery = true }
        }
        viewModel.saveGate.setRecoveryBlocked(recovery, titleID: game.titleId ?? "")
        DispatchQueue.main.async {
            self.failed = true
            self.message = error.localizedDescription
            if clearPreview { self.preview = nil; self.restorePreview = nil }
            self.recoveryRequired = recovery; self.release()
        }
    }
    func showFolder() {
        guard let context else { return }
        let url = context.location.directory(.account)
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: url.path) ? url : context.location.root])
    }
    func showBackups(_ snapshot: SaveSnapshot? = nil) {
        viewModel.saveQueue.async {
            let url = snapshot.flatMap { try? self.store.directory(snapshotID: $0.id, titleID: self.game.titleId ?? "") } ?? self.backupsURL
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
    func close() {
        abandoned = true
        if (preview != nil || restorePreview != nil) && !busy { cancelPreview() }
    }
}
