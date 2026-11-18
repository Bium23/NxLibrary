import XCTest
@testable import NXLibraryCore

final class SteamDiscoveryConsistencyTests: XCTestCase {
    func testManifestAddedAfterInventoryInvalidatesTheSource() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        let source = SteamLibrarySource(root: root, directoryReader: { url, limit, cancelled in
            let read = try InstallationDirectorySnapshot.read(at: url, maximumEntries: limit, cancelled: cancelled)
            if url.path == root.appendingPathComponent("steamapps").path {
                try f.manifest(in: root, id: "20", directory: "Second")
                try f.app(at: "Steam/steamapps/common/Second/Game.app")
            }
            return read
        })
        XCTAssertThrowsError(try source.scan()) { XCTAssertEqual($0 as? SteamSourceError, .sourceChanged) }
    }

    func testPreviouslyAbsentIndexAppearingBeforeInventoryIsDetected() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library(), external = try f.library("External")
        let source = SteamLibrarySource(root: root, directoryReader: { url, limit, cancelled in
            if url.path == root.appendingPathComponent("steamapps").path {
                try Data("libraryfolders { 1 \(SteamTestFixture.quote(external.path)) }".utf8)
                    .write(to: root.appendingPathComponent("steamapps/libraryfolders.vdf"))
            }
            return try InstallationDirectorySnapshot.read(at: url, maximumEntries: limit, cancelled: cancelled)
        })
        XCTAssertThrowsError(try source.scan()) { XCTAssertEqual($0 as? SteamSourceError, .sourceChanged) }
    }

    func testNativeMetadataAndExecutableAreRecheckedAfterOtherGamesAreRead() throws {
        for removeExecutable in [false, true] {
            let f = try SteamTestFixture.temporary(in: self)
            let root = try f.library()
            try f.manifest(in: root)
            try f.manifest(in: root, id: "20", directory: "Second")
            let first = try f.app(at: "Steam/steamapps/common/First/Game.app")
            try f.app(at: "Steam/steamapps/common/Second/Game.app")
            let second = root.appendingPathComponent("steamapps/common/Second")
            let source = SteamLibrarySource(root: root, directoryReader: { url, limit, cancelled in
                let read = try InstallationDirectorySnapshot.read(at: url, maximumEntries: limit, cancelled: cancelled)
                if url.path == second.path {
                    if removeExecutable {
                        try FileManager.default.removeItem(at: first.appendingPathComponent("Contents/MacOS/fixture"))
                    } else {
                        let file = first.appendingPathComponent("Contents/Info.plist")
                        var info = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any])
                        info["LSApplicationCategoryType"] = "public.app-category.developer-tools"
                        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: file)
                    }
                }
                return read
            })
            XCTAssertThrowsError(try source.scan()) { XCTAssertEqual($0 as? SteamSourceError, .sourceChanged) }
        }
    }

    func testDirectoryReadEnforcesTheEntryBudget() throws {
        let f = try SteamTestFixture.temporary(in: self)
        for i in 0..<12 { try Data().write(to: f.root.appendingPathComponent("item\(i)")) }
        let result = try InstallationDirectorySnapshot.read(at: f.root, maximumEntries: 3, cancelled: { false })
        XCTAssertEqual(result.entries.count, 3)
        XCTAssertFalse(result.isComplete)
    }

    func testDirectoryReadHonorsCancellationWhileCollectingEntries() throws {
        let f = try SteamTestFixture.temporary(in: self)
        for i in 0..<12 { try Data().write(to: f.root.appendingPathComponent("item\(i)")) }
        var checkpoints = 0
        XCTAssertThrowsError(try InstallationDirectorySnapshot.read(at: f.root, maximumEntries: 100, cancelled: {
            checkpoints += 1
            return checkpoints >= 2
        })) { XCTAssertTrue($0 is CancellationError) }
    }

    func testHiddenEntriesAlsoConsumeTheDirectoryReadBudget() throws {
        let f = try SteamTestFixture.temporary(in: self)
        for i in 0..<12 { try Data().write(to: f.root.appendingPathComponent(".hidden\(i)")) }
        let result = try InstallationDirectorySnapshot.read(at: f.root, maximumEntries: 3, cancelled: { false })
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertFalse(result.isComplete)
    }

    func testWideInstallationRemainsPartialWhenItsEntryBudgetIsReached() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        try f.manifest(in: root)
        try f.app(at: "Steam/steamapps/common/First/Game.app")
        for i in 0..<12 {
            try Data().write(to: root.appendingPathComponent("steamapps/common/First/item\(i)"))
        }
        var limits = SteamScanLimits.standard
        limits.maximumDirectoryEntries = 4
        let result = try SteamLibrarySource(root: root, limits: limits).scan()
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.games.first?.state, .requiresReview)
        XCTAssertTrue(result.issues.contains { $0.reason == .directoryLimit })
    }

    func testCancellationFromInventoryReaderIsNotSwallowedAsUnavailable() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        let source = SteamLibrarySource(root: root, directoryReader: { url, limit, _ in
            try InstallationDirectorySnapshot.read(at: url, maximumEntries: limit, cancelled: { true })
        })
        XCTAssertThrowsError(try source.scan()) { XCTAssertTrue($0 is CancellationError) }
    }
}
