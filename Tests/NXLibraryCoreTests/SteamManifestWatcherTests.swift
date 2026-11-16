import XCTest
@testable import NXLibraryCore

final class SteamManifestWatcherTests: XCTestCase {
    func testOnlyManifestsAndTheLibraryIndexAreRelevant() {
        let root = "/Users/p/Library/Application Support/Steam", second = "/Volumes/Games/SteamLibrary"
        let libraries = [root, second]  // as `watch` keeps them: resolved paths
        func relevant(_ path: String) -> Bool { SteamManifestWatcher.isRelevant(path, libraries: libraries, root: root) }
        XCTAssertTrue(relevant(root + "/steamapps/appmanifest_3321460.acf"))
        XCTAssertTrue(relevant(second + "/steamapps/appmanifest_10.acf"))
        XCTAssertTrue(relevant(root + "/steamapps/libraryfolders.vdf"))
        XCTAssertFalse(relevant(second + "/steamapps/libraryfolders.vdf"))
        XCTAssertFalse(relevant(root + "/steamapps/downloading/3321460/data.bin"))
        XCTAssertFalse(relevant(root + "/steamapps/common/Game/appmanifest_1.acf"))
        XCTAssertFalse(relevant(root + "/steamapps/appmanifest_1.acf.tmp"))
        XCTAssertFalse(relevant(root + "/steamapps/appmanifest_x.acf"))
        XCTAssertFalse(relevant(root + "/steamapps/appmanifest_.acf"))
        XCTAssertFalse(relevant("/Volumes/Other/steamapps/appmanifest_1.acf"))
        XCTAssertFalse(relevant(root + "/steamapps"))
    }

    func testDroppedEventsCountOnlyForASteamappsFolderOrAbove() {
        let root = "/Users/p/Library/Application Support/Steam"
        func dropped(_ path: String) -> Bool { SteamManifestWatcher.isRelevant(path, dropped: true, libraries: [root], root: root) }
        // A drop inside a download's folder says nothing about the manifests: no rescan every batch.
        XCTAssertFalse(dropped(root + "/steamapps/downloading/3321460"))
        XCTAssertFalse(dropped(root + "/steamapps/common/Game"))
        XCTAssertTrue(dropped(root + "/steamapps"))
        XCTAssertTrue(dropped(root + "/steamapps/"))
        XCTAssertTrue(dropped("/Users/p/Library"))
        XCTAssertFalse(dropped("/Volumes/Other"))
        XCTAssertTrue(SteamManifestWatcher.isRelevant(root + "/steamapps/appmanifest_1.acf", dropped: false, libraries: [root], root: root))
    }

    @MainActor
    func testRetriesTheSameLibraryWhenItsFolderBecomesAvailable() async throws {
        let f = try SteamTestFixture.temporary(in: self)
        let library = f.root.appendingPathComponent("Later")
        let changed = expectation(description: "Newly available library is watched")
        let watcher = SteamManifestWatcher { changed.fulfill() }
        defer { watcher.stop() }
        watcher.watch([library], root: library)
        _ = try f.library("Later")
        watcher.watch([library], root: library)
        try f.manifest(in: library)
        await fulfillment(of: [changed], timeout: 6)
    }

    @MainActor
    func testAddsANewlyAvailableLibraryAlongsideAnExistingStream() async throws {
        let f = try SteamTestFixture.temporary(in: self)
        let root = try f.library()
        let library = f.root.appendingPathComponent("Later")
        let changed = expectation(description: "Additional library is watched")
        let watcher = SteamManifestWatcher { changed.fulfill() }
        defer { watcher.stop() }
        watcher.watch([root, library], root: root)
        _ = try f.library("Later")
        watcher.watch([root, library], root: root)
        try f.manifest(in: library)
        await fulfillment(of: [changed], timeout: 6)
    }

    @MainActor
    func testTheStreamKeepsItsWatcherAliveUntilStopped() throws {
        let f = try SteamTestFixture.temporary(in: self)
        let library = try f.library()
        weak var weakWatcher: SteamManifestWatcher?
        do {
            let watcher = SteamManifestWatcher()
            watcher.watch([library], root: library)
            weakWatcher = watcher
        }
        // A callback already queued must still find its watcher.
        XCTAssertNotNil(weakWatcher)
        weakWatcher?.stop()
        // The stream lets go of its context on its queue (the main one).
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(weakWatcher)
    }
}
