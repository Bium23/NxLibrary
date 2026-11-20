import AppKit
import Foundation
import UniformTypeIdentifiers
import NXLibraryCore

/// The build's folders, free space, supported sources and the timing of the last stages.
extension PortingModel {
    // MARK: - Folders, space and timing
    func freeBytes(at url: URL) -> Int64? {
        let fm = FileManager.default
        // A folder not made yet (a build's staging folder) is on its nearest existing parent's volume.
        var target = url.standardizedFileURL
        while !fm.fileExists(atPath: target.path), target.path != "/" {
            target = target.deletingLastPathComponent()
        }
        var stat = statvfs()
        if statvfs(target.path, &stat) == 0 {
            return Int64(stat.f_bavail) * Int64(stat.f_frsize)
        }
        let values = try? target.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                      .volumeAvailableCapacityKey])
        if let cap = values?.volumeAvailableCapacityForImportantUsage {
            return cap
        }
        return values?.volumeAvailableCapacity.map { Int64($0) }
    }
    /// The folders a build writes to: its workspace (a player's own one beside the sources is kept), its staged app
    /// and the app's folder. They are on the app's drive when it can hold builds.
    func buildFolders(appFolder: URL, workspace: String?) -> [URL] {
        let existing = workspace.map { URL(fileURLWithPath: $0) }
        let scratch = BuildScratch.choose(core: app.core, appFolder: appFolder, existingWorkspace: existing)
        let own = existing.flatMap { BuildScratch.isManaged($0, core: app.core) ? nil : $0 }
        return [own ?? scratch.workspaces, scratch.temp, appFolder]
    }
    func finalAppURL(for game: PortedGame) -> URL {
        GameAppDestination.url(for: game, in: app.gameAppsFolder)
    }
    func supportsSources(_ sources: [GameFileItem]) -> Bool {
        let capabilities = app.setup.engineSourceCapabilities
        return SourceSelection.supported(sources, titleSelection: capabilities.titleSelection,
                                         extractedFolders: capabilities.extractedFolders,
                                         nupContainers: capabilities.nupContainers,
                                         nupPrograms: capabilities.nupPrograms)
    }
    /// What the final stages took in the last successful porting on this Mac, for the ETA.
    /// Seeded once from the newest porting log when nothing is stored yet.
    var lastPortingFinishSeconds: Double? {
        get {
            let stored = AppData.preferences.double(forKey: AppViewModel.StorageKeys.lastPortingFinishSeconds)
            if stored > 0 { return stored }
            guard !didSeedFinishSeconds else { return nil }
            didSeedFinishSeconds = true
            guard let seeded = Self.finishSecondsFromNewestLog(in: app.core.appendingPathComponent("logs")) else {
                return nil
            }
            AppData.preferences.set(seeded, forKey: AppViewModel.StorageKeys.lastPortingFinishSeconds)
            return seeded
        }
        set { AppData.preferences.set(newValue ?? 0, forKey: AppViewModel.StorageKeys.lastPortingFinishSeconds) }
    }
    private static func finishSecondsFromNewestLog(in directory: URL) -> Double? {
        let fm = FileManager.default
        let logs = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension == "log" } ?? []
        let newest = logs.max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        guard let newest, let text = try? String(contentsOf: newest, encoding: .utf8) else { return nil }
        return PortingProgress.finishingSeconds(inLog: text)
    }
    /// `kept`: folders of builds that wait for their game to quit (standardized paths).
    static func sweepStaleBuildTemp(in folders: [URL], keeping kept: Set<String>) {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for temp in folders {
            sweepStaleBuildTemp(temp, before: cutoff, keeping: kept)
        }
    }
    private static func sweepStaleBuildTemp(_ temp: URL, before cutoff: Date, keeping kept: Set<String>) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: temp, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for item in items {
            let date = (try? item.resourceValues(
                forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date.distantPast
            if date < cutoff, !kept.contains(item.standardizedFileURL.path) {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }
}
