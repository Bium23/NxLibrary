import Foundation

public enum SavePresentation {
    public static let closedNotice = "Keep the game closed, including launches from Finder, until the operation finishes."
    public static let cloudNotice = "Backups capture the local committed save, which may differ from a save not yet received from the cloud."
    public static let importWarning = "A save from a newer game version may not load. Cloud saves may replace this local save if you turn sync on later."
    public static func slotName(_ slot: SaveSlot) -> String { slot == .account ? "Account / device-only" : "Separate device save" }
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
    public static func importMessage(_ preview: SaveImportPreview, destination: URL, version: String?) -> String {
        "\(preview.fileCount) files · \(size(preview.byteCount))\n\nFrom: \(preview.source.path)\nTo: \(destination.path)\nInstalled version: \(version ?? "unknown")\n\nThe current save will be backed up first, then replaced without merging.\n\n\(importWarning)"
    }
    public static func reason(_ reason: SaveSnapshotReason) -> String {
        switch reason { case .manual: return "Manual backup"; case .beforeImport: return "Before import"; case .beforeRestore: return "Before restore" }
    }
}
