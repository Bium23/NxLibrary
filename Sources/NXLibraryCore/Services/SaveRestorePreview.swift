import Foundation

extension SaveSnapshotStore {
    public func stageRestore(_ snapshot: SaveSnapshot, location: SaveLocation) throws -> SaveRestorePreview {
        guard snapshot.identity.titleID == location.titleID else { throw SaveFailure.invalidSnapshot }
        let verified = try verify(snapshotID: snapshot.id, titleID: location.titleID)
        guard snapshot == verified else { throw SaveFailure.invalidSnapshot }
        let current = try currentInventory(location: location)
        try SaveFiles.checkSpace(at: location.root, bytes: snapshot.byteCount)
        try SaveFiles.makeDirectory(location.root)
        let id = UUID(); let staging = location.root.appendingPathComponent(".nxlibrary-save-restore-preview-\(id)")
        try SaveFiles.makeDirectory(staging)
        do {
            let source = try directory(snapshotID: snapshot.id, titleID: location.titleID)
            for slot in SaveSlot.allCases where snapshot.presentSlots.contains(slot) {
                let name = slot == .account ? "save" : "save_device"
                try io.copy(source.appendingPathComponent(name), staging.appendingPathComponent(name))
            }
            try verifyContents(snapshot, directory: staging)
            return SaveRestorePreview(id: id, snapshot: snapshot, staging: staging, currentEntries: current)
        } catch { try? SaveFiles.remove(staging); throw error }
    }
    public func validateRestore(_ preview: SaveRestorePreview, location: SaveLocation) throws {
        guard preview.staging.path == location.root.appendingPathComponent(".nxlibrary-save-restore-preview-\(preview.id)").path else { throw SaveFailure.unsafePath }
        try location.validate()
        guard preview.snapshot == (try verify(snapshotID: preview.snapshot.id, titleID: location.titleID)) else { throw SaveFailure.invalidSnapshot }
        try verifyContents(preview.snapshot, directory: preview.staging)
        guard try currentInventory(location: location) == preview.currentEntries else { throw SaveFailure.changed }
    }
    public func discardRestore(_ preview: SaveRestorePreview, location: SaveLocation) throws {
        guard preview.staging.path == location.root.appendingPathComponent(".nxlibrary-save-restore-preview-\(preview.id)").path else { throw SaveFailure.unsafePath }
        try location.validate(); try SaveFiles.remove(preview.staging)
    }
}
