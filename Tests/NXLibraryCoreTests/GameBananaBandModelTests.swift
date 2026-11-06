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

    /// Game A with twelve mods that work, six on each of two pages, each with its art.
    private func serveTwelveMods() throws {
        try matches.set(.game(id: 6376, name: "A", profileURL: URL(string: "https://gamebanana.com/games/6376")!),
                        titleID: gameA)
        func page(_ ids: ClosedRange<Int>, number: Int, complete: Bool) {
            let records = ids.map { #"{"_idRow": \#($0), "_sName": "Mod \#($0)", "_aSubmitter": {"_sName": "A"}}"# }
            http.serve("_nPage=\(number)&", #"{"_aMetadata": {"_bIsComplete": \#(complete)}, "_aRecords": [\#(records.joined(separator: ","))]}"#)
        }
        page(1...6, number: 1, complete: false)
        page(7...12, number: 2, complete: true)
        for id in 1...12 {
            http.serve("Mod/\(id)/ProfilePage", #"""
            {"_idRow": \#(id), "_sName": "Mod \#(id)", "_sProfileUrl": "https://gamebanana.com/mods/\#(id)", "_aSubmitter": {"_sName": "A"},
             "_aPreviewMedia": {"_aImages": [{"_sBaseUrl": "https://images.gamebanana.com/img/ss/mods", "_sFile": "\#(id).jpg", "_sFile220": "220-\#(id).jpg"}]},
             "_aFiles": [{"_idRow": \#(id * 10 + 1), "_sFile": "f.zip", "_nFilesize": 10, "_tsDateAdded": 1700000000,
                          "_sDownloadUrl": "https://gamebanana.com/dl/\#(id * 10 + 1)", "_sMd5Checksum": "x"}]}
            """#)
            http.serve("itemid=\(id * 10 + 1)&", #"[["romfs/a.bin"]]"#)
        }
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

    // MARK: - Installing

    /// A mod with two files, neither with a download address: an install of either fails without the network.
    private func twoFileMod() -> AvailableMod {
        AvailableMod(id: 7, rank: 0, name: "Pack", author: "A", avatarURL: nil, images: [], thumbnailURL: nil,
                     version: "", updated: Date(timeIntervalSince1970: 1_700_000_000),
                     pageURL: URL(string: "https://gamebanana.com/mods/7")!, description: "", likes: 0, downloads: 0,
                     files: [GameBananaFile(id: 71, name: "a.zip", size: 1, downloadURL: nil, md5: ""),
                             GameBananaFile(id: 72, name: "b.zip", size: 1, downloadURL: nil, md5: "")])
    }

    /// An install is for one of the mod's files: only that file shows it, while it runs and once it has ended.
    /// Shown for the whole mod, every file of a mod with eight looked as if it were downloading.
    func testAnInstallShowsOnlyOnTheFileItIsFor() async {
        let model = band()
        model.attach(store: store(gameA))
        let mod = twoFileMod()
        model.install(mod, file: mod.files[1])
        XCTAssertEqual(model.installState(mod: mod.id, file: 72), .downloading(0))
        XCTAssertNil(model.installState(mod: mod.id, file: 71))
        XCTAssertTrue(model.isInstalling(mod.id))
        await waitUntil { model.installs[mod.id] != .downloading(0) }
        XCTAssertEqual(model.installState(mod: mod.id, file: 72), .failed(ModInstallError.download.message))
        XCTAssertNil(model.installState(mod: mod.id, file: 71))
        XCTAssertFalse(model.isInstalling(mod.id))
    }

    /// After a failed file, another file of the same mod starts its own install; the failure leaves with it.
    func testAnotherFileAfterAFailureShowsOnlyItsOwnInstall() async {
        let model = band()
        model.attach(store: store(gameA))
        let mod = twoFileMod()
        model.install(mod, file: mod.files[1])
        await waitUntil { !model.isInstalling(mod.id) }
        model.install(mod, file: mod.files[0])
        XCTAssertEqual(model.installState(mod: mod.id, file: 71), .downloading(0))
        XCTAssertNil(model.installState(mod: mod.id, file: 72))
    }

    // MARK: - Arrival

    /// The band fills calmly: a row's worth of mods beside Add mods as soon as there are five, the rest together
    /// once the search has ended, never one tile after another.
    func testModsArriveInTwoGroupsAtMost() async throws {
        try serveTwelveMods()
        let model = band()
        var counts: [Int] = []
        let watch = model.$available.sink { counts.append($0.count) }
        model.start(names: ["A"], store: store(gameA))
        await waitUntil { model.phase == .ready }
        watch.cancel()
        XCTAssertEqual(counts.filter { $0 > 0 }, [5, 12])
        XCTAssertEqual(model.available.map(\.id), Array(1...12))
    }

    /// Each group shows with its art already decoded, so no tile fills in after the others.
    func testEachGroupsArtIsReadyBeforeItShows() async throws {
        try serveTwelveMods()
        let model = band()
        var asked: [[URL]] = []
        var shownWhenAsked: [Int] = []
        model.prepareImages = { urls in
            asked.append(urls)
            shownWhenAsked.append(model.available.count)
        }
        model.start(names: ["A"], store: store(gameA))
        await waitUntil { model.phase == .ready }
        XCTAssertEqual(shownWhenAsked, [0, 5])
        XCTAssertEqual(asked.flatMap { $0 }, model.available.compactMap(\.thumbnailURL))
        XCTAssertEqual(asked.first?.count, 5)
    }

    /// Slow art holds the mods back only briefly: they show, and the art fades in when it comes.
    func testSlowArtHoldsTheModsOnlyBriefly() async throws {
        try serveTwelveMods()
        let model = band()
        model.imageWait = 0.05
        model.prepareImages = { _ in try? await Task.sleep(nanoseconds: 30_000_000_000) }
        model.start(names: ["A"], store: store(gameA))
        await waitUntil { model.phase == .ready }
        XCTAssertEqual(model.available.count, 12)
    }

    /// Art that arrives after the player moved to another game never brings the previous game's mods back.
    func testArtArrivingAfterAnotherGameStartedShowsNothing() async throws {
        try serveTwelveMods()
        let model = band()
        var release: CheckedContinuation<Void, Never>?
        model.prepareImages = { _ in await withCheckedContinuation { release = $0 } }
        model.start(names: ["A"], store: store(gameA))
        await waitUntil { release != nil }
        model.start(names: ["B"], store: store(gameB))
        release?.resume()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.available.map(\.id), [])
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
