import XCTest
@testable import NXLibraryCore

final class AvailableModsFinderTests: XCTestCase {
    private var dir: URL!
    private let http = FakeGameBananaHTTP()
    private let tid = "0100000000010000"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("GBFinder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func finder(want: Int = 12, maxScanned: Int = 60, perPage: Int = 20,
                        installed: [Int] = []) -> AvailableModsFinder {
        let client = GameBananaClient(http: http, cacheFolder: dir.appendingPathComponent("cache"), userAgent: "test")
        return AvailableModsFinder(client: client, titleID: tid, want: want, maxScanned: maxScanned, perPage: perPage,
                                   installed: installed)
    }

    private func summary(_ id: Int, rated: Bool = false) -> String {
        #"{"_idRow": \#(id), "_sName": "Mod \#(id)", "_bHasContentRatings": \#(rated), "_aSubmitter": {"_sName": "A"}}"#
    }

    private func page(_ ids: [Int], rated: Set<Int> = [], complete: Bool, number: Int = 1) {
        let records = ids.map { summary($0, rated: rated.contains($0)) }.joined(separator: ",")
        http.serve("_nPage=\(number)&", #"{"_aMetadata": {"_bIsComplete": \#(complete)}, "_aRecords": [\#(records)]}"#)
    }

    /// A profile whose files are `(fileID, paths)`; each file's listing is served too.
    private func profile(_ id: Int, files: [(Int, [String])], requirements: String = "[]") {
        let list = files.map { file in
            #"{"_idRow": \#(file.0), "_sFile": "f\#(file.0).zip", "_nFilesize": 10, "_tsDateAdded": \#(1_700_000_000 + file.0), "_sDownloadUrl": "https://gamebanana.com/dl/\#(file.0)", "_sMd5Checksum": "x"}"#
        }.joined(separator: ",")
        http.serve("Mod/\(id)/ProfilePage", #"""
        {"_idRow": \#(id), "_sName": "Mod \#(id)", "_sProfileUrl": "https://gamebanana.com/mods/\#(id)",
         "_sText": "Hello<br>world", "_aSubmitter": {"_sName": "Author \#(id)"},
         "_aPreviewMedia": {"_aImages": [{"_sBaseUrl": "https://images.gamebanana.com/img/ss/mods", "_sFile": "\#(id).jpg", "_sFile220": "220-\#(id).jpg"}]},
         "_aRequirements": \#(requirements), "_aFiles": [\#(list)]}
        """#)
        for file in files {
            let paths = file.1.map { "\"\($0)\"" }.joined(separator: ",")
            http.serve("itemid=\(file.0)&", "[[\(paths)]]")
        }
    }

    private func collect(_ finder: AvailableModsFinder, gameID: Int = 6376) async throws -> [AvailableMod] {
        var mods: [AvailableMod] = []
        for try await mod in finder.stream(gameID: gameID) { mods.append(mod) }
        return mods
    }

    func testYieldsOnlyWorkingModsInRankOrder() async throws {
        page([1, 2, 3, 4], rated: [3], complete: true)
        profile(1, files: [(11, ["romfs/a.bin"])])
        profile(2, files: [(21, ["exefs/main.npdm"])])
        profile(3, files: [(31, ["romfs/a.bin"])])
        profile(4, files: [(41, ["romfs/b.bin"]), (42, ["60fps.pchtxt"])])
        let mods = try await collect(finder())
        XCTAssertEqual(mods.map(\.id), [1, 4])
        XCTAssertEqual(mods[1].files.map(\.id), [41])
        XCTAssertEqual(mods[0].author, "Author 1")
        XCTAssertEqual(mods[0].description, "Hello\nworld")
        XCTAssertEqual(mods[0].pageURL, URL(string: "https://gamebanana.com/mods/1"))
        XCTAssertEqual(mods[0].thumbnailURL, URL(string: "https://images.gamebanana.com/img/ss/mods/220-1.jpg"))
        XCTAssertEqual(mods.map(\.rank), [0, 3])
        XCTAssertEqual(http.count("Mod/3/ProfilePage"), 0)
    }

    /// A mod that needs a loader is never listed; one with other requirements is, and carries them for its panel.
    func testModsNeedingALoaderAreLeftOutAndOthersCarryTheirRequirements() async throws {
        page([1, 2], complete: true)
        profile(1, files: [(11, ["romfs/a.bin"])], requirements: #"[["Trinity Mod Loader", "https://gamebanana.com/updates/1"]]"#)
        profile(2, files: [(21, ["romfs/a.bin"])], requirements: #"[["Hacked switch", ""], ["Super Mario Odyssey v1.3", ""]]"#)
        let mods = try await collect(finder())
        XCTAssertEqual(mods.map(\.id), [2])
        XCTAssertEqual(mods[0].requirements, [GameBananaRequirement(name: "Super Mario Odyssey v1.3", isOptional: false)])
        XCTAssertEqual(http.count("itemid=11&"), 0, "a hidden mod's files are not even listed")
    }

    /// An installed mod GameBanana's list leaves out for a while (an update waiting for approval) is read from its
    /// own page, so the player still sees it, and its Update. It comes after the listed mods.
    func testAnInstalledModMissingFromTheListIsReadFromItsPage() async throws {
        page([1], complete: true)
        profile(1, files: [(11, ["romfs/a.bin"])])
        profile(77, files: [(771, ["Pack/romfs/a.bin"])])
        let mods = try await collect(finder(installed: [77]))
        XCTAssertEqual(mods.map(\.id), [1, 77])
        XCTAssertGreaterThan(mods[1].rank, mods[0].rank)
        XCTAssertEqual(mods[1].files.map(\.id), [771])
    }

    /// An installed mod past the band's cut (twelve mods) is listed too, once.
    func testAnInstalledModPastTheCutIsListedOnce() async throws {
        page([1, 2], complete: true)
        profile(1, files: [(11, ["romfs/a.bin"])])
        profile(2, files: [(21, ["romfs/a.bin"])])
        let mods = try await collect(finder(want: 1, installed: [1, 2]))
        XCTAssertEqual(mods.map(\.id), [1, 2])
    }

    /// An installed mod that no longer works or is gone from GameBanana stays out, and the others still come.
    func testAnInstalledModThatNoLongerWorksOrIsGoneStaysOut() async throws {
        page([1], complete: true)
        profile(1, files: [(11, ["romfs/a.bin"])])
        profile(78, files: [(781, ["exefs/main.npdm"])])
        http.serve("Mod/79/ProfilePage", "gone", status: 404)
        let mods = try await collect(finder(installed: [78, 79]))
        XCTAssertEqual(mods.map(\.id), [1])
    }

    func testStopsAtWant() async throws {
        page([1, 2, 3, 4, 5], complete: false)
        for id in 1...5 { profile(id, files: [(id * 10, ["romfs/a"])]) }
        let mods = try await collect(finder(want: 2))
        XCTAssertEqual(mods.map(\.id), [1, 2])
        XCTAssertEqual(http.count("_nPage=2&"), 0)
    }

    func testStopsAtMaxScanned() async throws {
        page(Array(1...20), complete: false)
        for id in 1...20 { profile(id, files: [(id * 10, ["exefs/main.npdm"])]) }
        let mods = try await collect(finder(maxScanned: 20, perPage: 20))
        XCTAssertEqual(mods, [])
        XCTAssertEqual(http.count("_nPage=2&"), 0)
    }

    func testEndsWhenListIsComplete() async throws {
        page([1], complete: true)
        profile(1, files: [(10, ["File1.bin"])])
        let mods = try await collect(finder())
        XCTAssertEqual(mods, [])
        XCTAssertEqual(http.count("Mod/Index"), 1)
    }

    func testOfflineEndsStream() async throws {
        http.fail("Mod/Index", URLError(.notConnectedToInternet))
        do {
            _ = try await collect(finder())
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? GameBananaError, .offline)
        }
    }

    func testUpdateWhenInstalledFileIsGone() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let record = ModRecord(folderName: "Pack", isOn: true, gameBananaModID: 1, gameBananaFileID: 10, md5: "x", installedAt: t)
        func mod(_ files: [(Int, Date)]) -> AvailableMod {
            AvailableMod(id: 1, rank: 0, name: "Pack", author: "A", avatarURL: nil, images: [], thumbnailURL: nil, version: "",
                         updated: t, pageURL: URL(string: "https://gamebanana.com/mods/1")!, description: "", likes: 0,
                         downloads: 0, files: files.map {
                             GameBananaFile(id: $0.0, name: "f", size: 1, downloadURL: nil, md5: "", dateAdded: $0.1)
                         })
        }
        XCTAssertEqual(ModUpdateCheck.update(for: record, in: mod([(12, t + 86400)]))?.id, 12)
        XCTAssertNil(ModUpdateCheck.update(for: record, in: mod([(10, t), (12, t + 86400)])))
        XCTAssertNil(ModUpdateCheck.update(for: record, in: mod([(11, t - 86400)])))
    }

    func testInstalledModIsMarked() throws {
        let support = dir.appendingPathComponent("nxnative/\(tid)")
        let records = dir.appendingPathComponent("NXLibrary/mods/\(tid).json")
        let folder = support.appendingPathComponent("mods/Pack/romfs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: records.deletingLastPathComponent(), withIntermediateDirectories: true)
        let record = ModRecord(folderName: "Pack", isOn: false, gameBananaModID: 49049, gameBananaFileID: 7)
        try JSONEncoder().encode([record]).write(to: records)
        let store = ModStore(supportFolder: support, recordsFile: records, titleID: tid, canWrite: { true }, trash: { _ in })
        XCTAssertEqual(store.gameBananaRecords()[49049], record)
        try FileManager.default.removeItem(at: support.appendingPathComponent("mods/Pack"))
        XCTAssertNil(store.gameBananaRecords()[49049])
    }
}
