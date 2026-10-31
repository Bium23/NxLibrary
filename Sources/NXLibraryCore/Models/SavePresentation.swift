import Foundation

public enum SavePresentation {
    public enum ImportAction: Equatable { case chooseFolder, cloudSettings, unavailable }
    /// Cloud prevents writes, but its row remains actionable so the player can resolve it.
    public static func importAction(available: Bool, busy: Bool, running: Bool, recovery: Bool, cloud: Bool) -> ImportAction {
        guard available, !busy, !running, !recovery else { return .unavailable }
        return cloud ? .cloudSettings : .chooseFolder
    }
    public static let closedNotice = "Keep the game closed, including launches from Finder, until the operation finishes."
    public static let cloudNotice = "Backups capture the local committed save, which may differ from a save not yet received from the cloud."
    public static let importWarning = "A save from a newer game version may not load. Cloud saves may replace this local save if you turn sync on later."
    public static func slotName(_ slot: SaveSlot) -> String { slot == .account ? "User save" : "Device save" }
    public static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    public static func date(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    public static func restoreMessage(_ snapshot: SaveSnapshot, installedVersion: String?) -> String {
        let saved = snapshot.identity.version ?? "unknown"
        let current = installedVersion ?? "unknown"
        return "Restore the backup from \(date(snapshot.created))? The current save will be backed up first.\n\nBackup game version: \(saved) · Installed: \(current). Different versions may be incompatible.\n\nCloud saves may replace the restored local save if sync is enabled later."
    }
    public static func importSummary(_ preview: SaveImportPreview, version: String?) -> String {
        let files = preview.fileCount == 1 ? "1 file" : "\(preview.fileCount) files"
        return [files, size(preview.byteCount), version.map { "Game v" + $0 }]
            .compactMap { $0 }.joined(separator: " · ")
    }
    public static func reason(_ reason: SaveSnapshotReason) -> String {
        switch reason { case .manual: return "Manual backup"; case .beforeImport: return "Before import"; case .beforeRestore: return "Before restore" }
    }
}
