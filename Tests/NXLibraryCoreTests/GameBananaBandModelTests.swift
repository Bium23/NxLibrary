import XCTest
@testable import NXLibraryCore

@MainActor
final class GameBananaBandModelTests: XCTestCase {
    private var dir: URL!
    private let http = FakeGameBananaHTTP()
    private let gameA = "0100000000010000"
    private let gameB = "0100000000020000"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("GBBand-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private var matches: GameBananaMatchStore { GameBananaMatchStore(file: dir.appendingPathComponent("matches.json")) }

    private func band() -> GameBananaBandModel {
        let client = GameBananaClient(http: http, cacheFolder: dir.appendingPathComponent("cache"), userAgent: "test")
        return GameBananaBandModel(client: client, matches: matches, userAgent: "test")
    }

    private func store(_ titleID: String) -> ModStore {
        ModStore(supportFolder: dir.appendingPathComponent("nxnative/\(titleID)"),
                 recordsFile: dir.appendingPathComponent("NXLibrary/mods/\(titleID).json"), titleID: titleID,
                 canWrite: { true }, trash: { try FileManager.default.removeItem(at: $0) })
    }

    /// Game A is matched to GameBanana game 6376, which has one mod that works.
    private func serveGameA() throws {
        try matches.set(.game(id: 6376, name: "A", profileURL: URL(string: "https://gamebanana.com/games/6376")!),
                        titleID: gameA)
        http.serve("_nPage=1&", #"{"_aMetadata": {"_bIsComplete": true}, "_aRecords": [{"_idRow": 1, "_sName": "Mod 1", "_aSubmitter": {"_sName": "A"}}]}"#)
        http.serve("Mod/1/ProfilePage", #"""
        {"_idRow": 1, "_sName": "Mod 1", "_sProfileUrl": "https://gamebanana.com/mods/1", "_aSubmitter": {"_sName": "A"},
         "_aFiles": [{"_idRow": 11, "_sFile": "f.zip", "_nFilesize": 10, "_tsDateAdded": 1700000000,
                      "_sDownloadUrl": "https://gamebanana.com/dl/11", "_sMd5Checksum": "x"}]}
        """#)
        http.serve("itemid=11&", #"[["romfs/a.bin"]]"#)
        http.serve("Util/Search", #"{"_aRecords": []}"#)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    func testAnotherGameNeverShowsThePreviousGamesMods() async throws {
        try serveGameA()
        let model = band()
        model.start(names: ["A"], store: store(gameA))
        await waitUntil { model.phase == .ready }
        XCTAssertEqual(model.available.map(\.id), [1])
        model.start(names: ["B"], store: store(gameB))
        XCTAssertEqual(model.available.map(\.id), [])
    }

    func testStopForgetsTheGamesMods() async throws {
        try serveGameA()
        let model = band()
        model.start(names: ["A"], store: store(gameA))
        await waitUntil { model.phase == .ready }
        model.stop()
        XCTAssertEqual(model.available.map(\.id), [])
        XCTAssertNil(model.match)
    }

    func testStartClearsLeftoversOfAnInterruptedInstall() async throws {
        // A title no other test starts: leftovers are cleared once per game per run.
        let gameC = "0100000000030000"
        http.serve("Util/Search", #"{"_aRecords": []}"#)
        let mods = store(gameC).modsFolder
        try FileManager.default.createDirectory(at: mods.appendingPathComponent(".installing-OLD/romfs"),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: mods.appendingPathComponent(".installing-OLD.download"))
        band().start(names: ["C"], store: store(gameC))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: mods.path), [])
    }

    // MARK: - Find the game

    func testNoneOfTheseWaitsForTheSearch() async throws {
        http.serve("Util/Search", #"{"_aRecords": []}"#)
        http.delayNanoseconds = 300_000_000
        let model = band()
        model.start(names: ["B"], store: store(gameB))
        let find = GameBananaFindModel()
        find.open(name: "B", using: model)
        find.activate(find.focus, using: model)
        XCTAssertNil(matches.choice(titleID: gameB))
        XCTAssertTrue(find.isOpen)
    }

    func testUpFromTheFirstRowEditsTheName() {
        let find = GameBananaFindModel()
        XCTAssertFalse(find.editing)
        XCTAssertTrue(find.move(by: -1))
        XCTAssertTrue(find.editing)
        XCTAssertTrue(find.move(by: 1))
        XCTAssertFalse(find.editing)
        XCTAssertEqual(find.focus, 0)
    }

    func testConfirmWhileEditingSearches() {
        http.delayNanoseconds = 300_000_000
        let model = band()
        model.start(names: ["B"], store: store(gameB))
        let find = GameBananaFindModel()
        find.open(name: "B", using: model)
        _ = find.move(by: -1)
        find.query = "Other name"
        find.confirm(using: model)
        XCTAssertFalse(find.editing)
        XCTAssertTrue(find.searching)
        XCTAssertTrue(find.isOpen)
    }
}
