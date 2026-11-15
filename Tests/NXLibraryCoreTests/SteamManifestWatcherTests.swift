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
}
