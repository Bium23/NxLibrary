import XCTest
@testable import NXLibraryCore

final class BuildScratchTests: XCTestCase {
    private let core = URL(fileURLWithPath: "/Users/me/Library/Application Support/NXLibrary")
    private let internalApps = URL(fileURLWithPath: "/Users/me/Applications")
    private let externalApps = URL(fileURLWithPath: "/Volumes/NVMe/Games")
    private let exFATApps = URL(fileURLWithPath: "/Volumes/STICK/Games")

    /// The Mac's disk is device 1, an APFS external drive 2, an exFAT stick 3. `moved` puts NX Library's workspaces
    /// folder on the external drive, as a player who linked it there has.
    private func volumes(moved: Bool = false) -> (URL) -> BuildScratch.Volume? {
        { url in
            let path = url.path
            if moved, path.hasPrefix(self.core.path + "/workspaces") { return .init(device: 2, canHoldBuilds: true) }
            if path.hasPrefix("/Volumes/NVMe") { return .init(device: 2, canHoldBuilds: true) }
            if path.hasPrefix("/Volumes/STICK") { return .init(device: 3, canHoldBuilds: false) }
            return .init(device: 1, canHoldBuilds: true)
        }
    }

    func testAnAppOnTheMacKeepsTheBuildInNXLibrarysFolders() {
        let scratch = BuildScratch.choose(core: core, appFolder: internalApps, volume: volumes())
        XCTAssertEqual(scratch.workspaces.path, core.path + "/workspaces")
        XCTAssertEqual(scratch.temp.path, core.path + "/Temp")
        XCTAssertFalse(scratch.appDriveUnsupported)
    }

    func testAnAppOnAnExternalDriveIsBuiltOnThatDrive() {
        let scratch = BuildScratch.choose(core: core, appFolder: externalApps, volume: volumes())
        XCTAssertEqual(scratch.workspaces.path, "/Volumes/NVMe/Games/.nxlibrary-build/workspaces")
        XCTAssertEqual(scratch.temp.path, "/Volumes/NVMe/Games/.nxlibrary-build/Temp")
        XCTAssertFalse(scratch.appDriveUnsupported)
    }

    func testADriveWithoutSymbolicLinksLeavesTheBuildOnTheMac() {
        let scratch = BuildScratch.choose(core: core, appFolder: exFATApps, volume: volumes())
        XCTAssertEqual(scratch.workspaces.path, core.path + "/workspaces")
        XCTAssertEqual(scratch.temp.path, core.path + "/Temp")
        XCTAssertTrue(scratch.appDriveUnsupported)
    }

    func testAWorkspacesFolderMovedToTheAppsDriveStaysWhereThePlayerPutIt() {
        let scratch = BuildScratch.choose(core: core, appFolder: externalApps, volume: volumes(moved: true))
        XCTAssertEqual(scratch.workspaces.path, core.path + "/workspaces")
        XCTAssertEqual(scratch.temp.path, "/Volumes/NVMe/Games/.nxlibrary-build/Temp")
    }

    func testAWorkspaceAlreadyOnTheAppsDriveKeepsItsCache() {
        let old = URL(fileURLWithPath: "/Volumes/NVMe/Old Games/.nxlibrary-build/workspaces/0100000000010000")
        let scratch = BuildScratch.choose(core: core, appFolder: externalApps, existingWorkspace: old, volume: volumes())
        XCTAssertEqual(scratch.workspaces.path, "/Volumes/NVMe/Old Games/.nxlibrary-build/workspaces")
    }

    func testAWorkspaceOnAnotherDriveIsNotKept() {
        let old = core.appendingPathComponent("workspaces/0100000000010000")
        let scratch = BuildScratch.choose(core: core, appFolder: externalApps, existingWorkspace: old, volume: volumes())
        XCTAssertEqual(scratch.workspaces.path, "/Volumes/NVMe/Games/.nxlibrary-build/workspaces")
    }

    func testAPlayersFolderIsNeverKeptAsAWorkspaceRoot() {
        let folder = URL(fileURLWithPath: "/Volumes/NVMe/Dumps/0100000000010000")
        let scratch = BuildScratch.choose(core: core, appFolder: externalApps, existingWorkspace: folder, volume: volumes())
        XCTAssertEqual(scratch.workspaces.path, "/Volumes/NVMe/Games/.nxlibrary-build/workspaces")
    }

    func testOnlyWorkspacesNXLibraryMadeAreManaged() {
        XCTAssertTrue(BuildScratch.isManaged(core.appendingPathComponent("workspaces/0100000000010000"), core: core))
        XCTAssertTrue(BuildScratch.isManaged(
            URL(fileURLWithPath: "/Volumes/NVMe/Games/.nxlibrary-build/workspaces/0400C3F00006E000"), core: core))
        XCTAssertFalse(BuildScratch.isManaged(URL(fileURLWithPath: "/Volumes/NVMe/Dumps/0100000000010000"), core: core))
        XCTAssertFalse(BuildScratch.isManaged(
            URL(fileURLWithPath: "/Volumes/NVMe/Games/.nxlibrary-build/workspaces/My Game"), core: core))
        XCTAssertFalse(BuildScratch.isManaged(
            URL(fileURLWithPath: "/Volumes/NVMe/Games/.nxlibrary-build/workspaces"), core: core))
        XCTAssertFalse(BuildScratch.isManaged(
            URL(fileURLWithPath: "/Volumes/NVMe/workspaces/0100000000010000"), core: core))
        XCTAssertFalse(BuildScratch.isManaged(core.appendingPathComponent("workspaces"), core: core))
    }

    func testTheSweepLooksInEveryAppFolderOnce() {
        let folders = BuildScratch.tempFolders(core: core, appFolders: [externalApps, internalApps, externalApps])
        XCTAssertEqual(folders.map(\.path), [
            core.path + "/Temp",
            "/Volumes/NVMe/Games/.nxlibrary-build/Temp",
            "/Users/me/Applications/.nxlibrary-build/Temp",
        ])
    }

    /// exFAT and FAT take symbolic links on macOS too, but keep extended attributes in `._` files that break an app's
    /// signature: only the Mac's own file systems, on a local drive, hold builds.
    func testOnlyAppleFileSystemsOnALocalDriveHoldBuilds() {
        XCTAssertTrue(BuildScratch.Volume.holdsBuilds(fileSystem: "apfs", local: true))
        XCTAssertTrue(BuildScratch.Volume.holdsBuilds(fileSystem: "hfs", local: true))
        for other in ["exfat", "msdos", "ntfs", "smbfs", "nfs", "afpfs", "webdav"] {
            XCTAssertFalse(BuildScratch.Volume.holdsBuilds(fileSystem: other, local: true), other)
        }
        XCTAssertFalse(BuildScratch.Volume.holdsBuilds(fileSystem: "apfs", local: false))
    }

    func testTheVolumeOfAFolderNotMadeYetIsItsNearestParents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let made = try XCTUnwrap(BuildScratch.Volume.of(root))
        XCTAssertEqual(BuildScratch.Volume.of(root.appendingPathComponent("a/b/c")), made)
        XCTAssertTrue(made.canHoldBuilds)
    }
}
