import Foundation

public enum SavePresentation {
    public enum ImportAction: Equatable { case chooseFolder, cloudSettings, unavailable }
    /// Cloud prevents writes, but its row remains actionable so the player can resolve it.
    public static func importAction(available: Bool, busy: Bool, running: Bool, recovery: Bool, cloud: Bool) -> ImportAction {
        guard available, !busy, !running, !recovery else { return .unavailable }
        return cloud ? .cloudSettings : .chooseFolder
    }
    public static var closedNotice: String { L10n.text("Keep the game closed, including launches from Finder, until the operation finishes.") }
    public static var cloudNotice: String { L10n.text("Backups capture the local committed save, which may differ from a save not yet received from the cloud.") }
    public static var importWarning: String { L10n.text("A save from a newer game version may not load. Cloud saves may replace this local save if you turn sync on later.") }
    public static func slotName(_ slot: SaveSlot) -> String { slot == .account ? L10n.text("User save") : L10n.text("Device save") }
    public static func size(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file).locale(L10n.context.formatLocale)) }
    public static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.context.formatLocale
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    public static func restoreMessage(_ snapshot: SaveSnapshot, installedVersion: String?) -> String {
        let saved = snapshot.identity.version ?? L10n.text("Unknown")
        let current = installedVersion ?? L10n.text("Unknown")
        return L10n.format("Restore the backup from %@? The current save will be backed up first.\n\nBackup game version: %@ · Installed: %@. Different versions may be incompatible.\n\nCloud saves may replace the restored local save if sync is enabled later.", [date(snapshot.created), saved, current])
    }
    public static func importSummary(_ preview: SaveImportPreview, version: String?) -> String {
        let files = L10n.count("%lld files", preview.fileCount)
        return [files, size(preview.byteCount), version.map { L10n.format("Game v%@", [$0]) }]
            .compactMap { $0 }.joined(separator: " · ")
    }
    public static func reason(_ reason: SaveSnapshotReason) -> String {
        switch reason {
        case .manual: return L10n.text("Manual backup")
        case .beforeImport: return L10n.text("Before import")
        case .beforeRestore: return L10n.text("Before restore")
        }
    }
}
