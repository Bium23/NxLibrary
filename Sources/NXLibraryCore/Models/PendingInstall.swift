import Foundation

/// A build that finished while its game was running. Replacing an app under a running game can crash it, so the new
/// app waits in its temporary folder and replaces the old one once the game quits.
public struct PendingInstall: Codable, Equatable {
    public var tempApp: URL
    public var finalApp: URL
    public var record: BuildRecord
    public var toolchain: ToolchainInfo

    public init(tempApp: URL, finalApp: URL, record: BuildRecord, toolchain: ToolchainInfo) {
        self.tempApp = tempApp
        self.finalApp = finalApp
        self.record = record
        self.toolchain = toolchain
    }

    /// The build's temporary folder, removed once the app is installed.
    public var folder: URL { tempApp.deletingLastPathComponent() }

    /// The porting screen's stage line, title and message while the new app waits.
    public static let stageName = "Ready: installs when you quit the game"
    public static let title = "Ready when you quit"
    public static func message(gameName: String) -> String {
        "\(gameName) is open, so the new app waits beside it and replaces it as soon as you quit the game."
    }
}

extension PortedGame {
    /// What a successful build changes in the library once its app is in place.
    public mutating func recordInstalledBuild(_ record: BuildRecord, toolchain: ToolchainInfo, at app: URL,
                                              version: String?, date: Date) {
        status = .built
        url = app
        modificationDate = date
        versionString = version ?? versionString
        self.toolchain = toolchain
        lastBuild = record
        portingFailure = nil
        portingFailureReason = nil
        pendingInstall = nil
    }
}

/// Holds and installs builds that finished while their game was running. The caller checks the game is not running
/// before `install`.
public enum PendingInstaller {
    public enum Outcome: Equatable {
        case installed
        /// The held app no longer exists; the pending install is dropped.
        case gone
    }

    /// Keeps `pending` for later; an earlier held build of the game is discarded.
    public static func hold(_ pending: PendingInstall, for game: inout PortedGame, fileManager: FileManager = .default) {
        if let old = game.pendingInstall, old.folder.standardizedFileURL != pending.folder.standardizedFileURL {
            try? fileManager.removeItem(at: old.folder)
        }
        game.pendingInstall = pending
    }

    /// A newer build was installed: the held one is no longer wanted.
    public static func discard(_ game: inout PortedGame, fileManager: FileManager = .default) {
        guard let old = game.pendingInstall else { return }
        try? fileManager.removeItem(at: old.folder)
        game.pendingInstall = nil
    }

    /// Nil when nothing is held. A failed install keeps the pending install, for the next try.
    public static func install(_ game: inout PortedGame, now: Date = Date(),
                               fileManager: FileManager = .default) throws -> Outcome? {
        guard let pending = game.pendingInstall else { return nil }
        do {
            // A completed install can be acknowledged even if staging was
            // cleaned before its new build record reached the library.
            try BuildOutputInstaller.install(tempApp: pending.tempApp, finalApp: pending.finalApp,
                                             fileManager: fileManager, requiresExistingParent: true)
        } catch BuildInstallError.invalidApp(let path) where path == pending.tempApp.standardizedFileURL.path
            && !fileManager.fileExists(atPath: pending.tempApp.path) {
            game.pendingInstall = nil
            return .gone
        }
        try? fileManager.removeItem(at: pending.folder)
        game.recordInstalledBuild(pending.record, toolchain: pending.toolchain, at: pending.finalApp,
                                  version: BuildOutputInstaller.version(of: pending.finalApp), date: now)
        return .installed
    }

    /// Temporary folders still needed by a held build (standardized paths), which the stale-temp sweep keeps.
    public static func keptFolders(_ games: [PortedGame]) -> Set<String> {
        Set(games.compactMap { $0.pendingInstall?.folder.standardizedFileURL.path })
    }
}
