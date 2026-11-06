import XCTest
@testable import NXLibraryCore

@MainActor
final class ModStoreModelTests: XCTestCase {
    private var dir: URL!
    private let http = FakeGameBananaHTTP()
    private let gameA = "0100000000010000"
    private let gameB = "0100000000020000"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private var matches: GameBananaMatchStore { GameBananaMatchStore(file: dir.appendingPathComponent("matches.json")) }
    private var snapshots: ModCatalogSnapshots { ModCatalogSnapshots(folder: dir.appendingPathComponent("store")) }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func model() -> ModStoreModel {
        let client = GameBananaClient(http: http, cacheFolder: dir.appendingPathComponent("cache"), userAgent: "test")
        let now = self.now
        return ModStoreModel(client: client, matches: matches, snapshots: snapshots, now: { now })
    }

    private func mod(_ id: Int) -> AvailableMod {
        AvailableMod(id: id, rank: 0, name: "Mod \(id)", author: "A", avatarURL: nil, images: [], thumbnailURL: nil,
                     version: "", updated: now, pageURL: URL(string: "https://gamebanana.com/mods/\(id)")!,
                     description: "", likes: 0, downloads: 0,
                     files: [GameBananaFile(id: id * 10, name: "f.zip", size: 1,
                                            downloadURL: URL(string: "https://gamebanana.com/dl/\(id * 10)"), md5: "x")])
    }

    /// Game A is GameBanana game 6376, which has one mod that works.
    private func serveGameA() throws {
        try matches.set(.game(id: 6376, name: "A", profileURL: URL(string: "https://gamebanana.com/games/6376")!), titleID: gameA)
        http.serve("_nPage=1&", #"{"_aMetadata": {"_bIsComplete": true}, "_aRecords": [{"_idRow": 1, "_sName": "Mod 1", "_aSubmitter": {"_sName": "A"}, "_aRootCategory": {"_sName": "Skins"}}]}"#)
        http.serve("Mod/1/ProfilePage", #"""
        {"_idRow": 1, "_sName": "Mod 1", "_sProfileUrl": "https://gamebanana.com/mods/1", "_aSubmitter": {"_sName": "A"},
         "_aFiles": [{"_idRow": 11, "_sFile": "f.zip", "_nFilesize": 10, "_tsDateAdded": 1700000000,
                      "_sDownloadUrl": "https://gamebanana.com/dl/11", "_sMd5Checksum": "x"}]}
        """#)
        http.serve("itemid=11&", #"[["romfs/a.bin"]]"#)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    func testOpensFromAFreshSnapshotWithoutAsking() async throws {
        try matches.set(.game(id: 6376, name: "A", profileURL: URL(string: "https://gamebanana.com/games/6376")!), titleID: gameA)
        try snapshots.save([mod(5)], gameName: "Old name", titleID: gameA, gameBananaID: 6376, at: now.addingTimeInterval(-60))
        let store = model()
        store.open([ModStoreGame(titleID: gameA, name: "A", names: ["A"])])
        await waitUntil { store.phase == .ready }
        XCTAssertEqual(store.games.map(\.name), ["A"], "the library's name, not the snapshot's")
        XCTAssertEqual(store.games.first?.mods.map(\.id), [5])
        XCTAssertEqual(http.requests.count, 0)
    }

    func testAStaleSnapshotShowsAtOnceThenRefreshes() async throws {
        try serveGameA()
        try snapshots.save([mod(5)], gameName: "A", titleID: gameA, gameBananaID: 6376, at: now.addingTimeInterval(-7 * 3600))
        let store = model()
        store.open([ModStoreGame(titleID: gameA, name: "A", names: ["A"])])
        await waitUntil { store.games.first?.mods.map(\.id) == [5] || store.games.first?.mods.map(\.id) == [1] }
        await waitUntil { store.phase == .ready && store.games.first?.mods.map(\.id) == [1] }
        XCTAssertEqual(store.games.first?.mods.first?.category, "Skins")
        XCTAssertEqual(snapshots.load(titleID: gameA)?.mods.map(\.id), [1])
        XCTAssertEqual(snapshots.load(titleID: gameA)?.savedAt, now)
    }

    func testAnUncertainMatchIsLeftToTheGamesBand() async throws {
        http.serve("Util/Search", #"{"_aRecords": [{"_idRow": 7, "_sName": "B Deluxe"}, {"_idRow": 8, "_sName": "B Remastered"}]}"#)
        let store = model()
        store.open([ModStoreGame(titleID: gameB, name: "B", names: ["B"])])
        await waitUntil { store.phase == .ready }
        XCTAssertNil(matches.choice(titleID: gameB))
        XCTAssertEqual(store.games, [])
    }

    func testACertainMatchIsRememberedAndItsModsFound() async throws {
        try serveGameA()
        try matches.set(nil, titleID: gameA)
        http.serve("Util/Search", #"{"_aRecords": [{"_idRow": 6376, "_sName": "A", "_sProfileUrl": "https://gamebanana.com/games/6376"}]}"#)
        let store = model()
        store.open([ModStoreGame(titleID: gameA, name: "A", names: ["A"])])
        await waitUntil { store.phase == .ready && !store.games.isEmpty }
        XCTAssertEqual(matches.choice(titleID: gameA), .game(id: 6376, name: "A", profileURL: URL(string: "https://gamebanana.com/games/6376")!))
        XCTAssertEqual(store.games.first?.mods.map(\.id), [1])
    }

    func testGamesKeepTheLibrarysOrder() async throws {
        let page = URL(string: "https://gamebanana.com/games/1")!
        try matches.set(.game(id: 1, name: "A", profileURL: page), titleID: gameA)
        try matches.set(.game(id: 2, name: "B", profileURL: page), titleID: gameB)
        try snapshots.save([mod(1)], gameName: "A", titleID: gameA, gameBananaID: 1, at: now)
        try snapshots.save([mod(2)], gameName: "B", titleID: gameB, gameBananaID: 2, at: now)
        let store = model()
        store.open([ModStoreGame(titleID: gameB, name: "B", names: ["B"]), ModStoreGame(titleID: gameA, name: "A", names: ["A"])])
        await waitUntil { store.phase == .ready }
        XCTAssertEqual(store.games.map(\.titleID), [gameB, gameA])
    }

    func testASnapshotOfAnotherGameBananaGameIsNotShown() async throws {
        // The player picked another GameBanana game in the game's band since the snapshot was saved.
        try serveGameA()
        try snapshots.save([mod(5)], gameName: "A", titleID: gameA, gameBananaID: 999, at: now)
        let store = model()
        store.open([ModStoreGame(titleID: gameA, name: "A", names: ["A"])])
        await waitUntil { store.phase == .ready && !store.refreshing }
        XCTAssertEqual(store.games.first?.mods.map(\.id), [1])
        XCTAssertEqual(snapshots.load(titleID: gameA)?.gameBananaID, 6376)
    }

    func testNoneOfTheseHidesTheGamesSavedMods() async throws {
        try matches.set(.noPage, titleID: gameA)
        try snapshots.save([mod(5)], gameName: "A", titleID: gameA, gameBananaID: 6376, at: now)
        let store = model()
        store.open([ModStoreGame(titleID: gameA, name: "A", names: ["A"])])
        await waitUntil { store.phase == .ready && !store.refreshing }
        XCTAssertEqual(store.games, [])
    }

    func testCloseStopsAndForgetsNothingOnDisk() async throws {
        try serveGameA()
        http.delayNanoseconds = 300_000_000
        let store = model()
        store.open([ModStoreGame(titleID: gameA, name: "A", names: ["A"])])
        store.close()
        XCTAssertEqual(store.phase, .idle)
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(snapshots.load(titleID: gameA), "a stopped refresh saves nothing")
    }
}
