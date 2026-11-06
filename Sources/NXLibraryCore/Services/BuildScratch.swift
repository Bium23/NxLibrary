import Foundation
import Darwin

/// Where a build's working files go: the workspace (links to the sources, the extracted game and the shader cache)
/// and the staged app, about twice the game's size together. They go on the drive the app goes to, so a game built
/// to an external drive needs no room on the Mac's own disk and the finished app is renamed into place instead of
/// copied. NX Library's own folders are used when they are already on that drive (the Mac's disk, or a workspaces
/// folder the player moved there) and when the drive can't hold builds: it must be a local APFS or Mac OS Extended
/// drive, not exFAT or a network share. Elsewhere the files go in a hidden folder beside the apps, where the
/// installer already keeps its own.
public struct BuildScratch: Equatable {
    public struct Volume: Equatable {
        public let device: UInt64
        /// APFS or Mac OS Extended, on a local drive (`holdsBuilds`).
        public let canHoldBuilds: Bool

        public init(device: UInt64, canHoldBuilds: Bool) {
            self.device = device
            self.canHoldBuilds = canHoldBuilds
        }

        /// The volume `url` is on, or would be on once made: its nearest existing folder's, links followed.
        public static func of(_ url: URL) -> Volume? {
            let fm = FileManager.default
            var probe = url.standardizedFileURL
            while !fm.fileExists(atPath: probe.path) {
                let parent = probe.deletingLastPathComponent()
                guard parent.path != probe.path else { return nil }
                probe = parent
            }
            let path = probe.resolvingSymlinksInPath().path
            // The device as `stat` gives it, as the installer compares volumes; the kind of drive from `statfs`.
            var node = stat()
            var drive = statfs()
            guard stat(path, &node) == 0, statfs(path, &drive) == 0 else { return nil }
            let fileSystem = withUnsafeBytes(of: drive.f_fstypename) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            return Volume(device: UInt64(node.st_dev),
                          canHoldBuilds: holdsBuilds(fileSystem: fileSystem, local: drive.f_flags & UInt32(MNT_LOCAL) != 0))
        }

        /// exFAT and FAT take symbolic links on macOS too, but keep extended attributes in `._` files that break an
        /// app's signature, and a network share is slow and may vanish: builds need the Mac's own file systems.
        public static func holdsBuilds(fileSystem: String, local: Bool) -> Bool {
            local && ["apfs", "hfs"].contains(fileSystem.lowercased())
        }
    }

    /// The hidden folder beside the apps.
    public static let folderName = ".nxlibrary-build"

    /// The folder holding the `<title ID>` workspaces.
    public let workspaces: URL
    /// The folder holding each build's staged app.
    public let temp: URL
    /// The app's drive can't hold builds, so they stay on the Mac's disk.
    public let appDriveUnsupported: Bool

    /// `core`: NX Library's Application Support folder. `appFolder`: the folder the app goes to. A managed
    /// `existingWorkspace` already on the app's drive keeps its place, and its cache.
    public static func choose(core: URL, appFolder: URL, existingWorkspace: URL? = nil,
                              volume: (URL) -> Volume? = Volume.of) -> BuildScratch {
        let ownWorkspaces = core.appendingPathComponent("workspaces")
        let ownTemp = core.appendingPathComponent("Temp")
        guard let target = volume(appFolder) else {
            return BuildScratch(workspaces: ownWorkspaces, temp: ownTemp, appDriveUnsupported: false)
        }
        let beside = appFolder.appendingPathComponent(folderName)
        func place(_ own: URL, _ name: String) -> URL {
            if volume(own)?.device == target.device || !target.canHoldBuilds { return own }
            return beside.appendingPathComponent(name)
        }
        var workspaces = place(ownWorkspaces, "workspaces")
        if let existing = existingWorkspace, isManaged(existing, core: core),
           volume(existing)?.device == target.device {
            workspaces = existing.standardizedFileURL.deletingLastPathComponent()
        }
        let unsupported = !target.canHoldBuilds && volume(ownWorkspaces)?.device != target.device
        return BuildScratch(workspaces: workspaces, temp: place(ownTemp, "Temp"), appDriveUnsupported: unsupported)
    }

    /// A workspace NX Library made and may delete: one under `<core>/workspaces`, or
    /// `<folder>/.nxlibrary-build/workspaces/<title ID>`. Never a folder of the player's.
    public static func isManaged(_ workspace: URL, core: URL) -> Bool {
        let path = workspace.standardizedFileURL
        let own = core.appendingPathComponent("workspaces").standardizedFileURL
        if path.path.hasPrefix(own.path + "/") { return true }
        let parent = path.deletingLastPathComponent()
        if parent.resolvingSymlinksInPath() == own.resolvingSymlinksInPath() { return true }
        let name = path.lastPathComponent
        return name.count == 16 && name.allSatisfy(\.isHexDigit)
            && parent.lastPathComponent == "workspaces"
            && parent.deletingLastPathComponent().lastPathComponent == folderName
    }

    /// The folders of staged apps the launch sweep looks in: NX Library's own, and the one beside each app folder.
    public static func tempFolders(core: URL, appFolders: [URL]) -> [URL] {
        var seen = Set<String>()
        let all = [core.appendingPathComponent("Temp")]
            + appFolders.map { $0.appendingPathComponent(folderName).appendingPathComponent("Temp") }
        return all.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
