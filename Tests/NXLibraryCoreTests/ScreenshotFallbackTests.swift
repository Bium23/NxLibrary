import XCTest
@testable import NXLibraryCore

final class ScreenshotFallbackTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shots-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func metadata(_ titleId: String, screenshots: [URL] = []) -> NintendoStoreMetadata {
        NintendoStoreMetadata(titleId: titleId, name: "Donkey Kong Bananza", description: "", developers: [], publishers: [],
                              genres: [], releaseDate: nil, storeURL: URL(string: "https://www.nintendo.com")!,
                              imageURL: nil, headerImageURL: nil, nsuid: nil, fetchedAt: Date(), screenshotURLs: screenshots)
    }

    func testAGameWithoutScreenshotsIsLookedUpOnceThenKept() throws {
        let store = ScreenshotFallbackStore(directory: dir)
        let meta = metadata("04007EE01C1A2000")
        XCTAssertTrue(store.wantsLookup(meta))
        let shot = URL(string: "https://images.launchbox-app.com/shot.png")!
        try store.save(.init(urls: [shot], fetchedAt: Date()), for: meta.titleId)
        XCTAssertFalse(store.wantsLookup(meta))
        let filled = store.filled(meta)
        XCTAssertEqual(filled.screenshotURLs, [shot])
        XCTAssertEqual(filled.screenshotSource, "LaunchBox")
        XCTAssertFalse(store.wantsLookup(filled))
    }

    func testAnEmptyAnswerIsKeptTooUntilItIsOld() throws {
        let store = ScreenshotFallbackStore(directory: dir)
        let meta = metadata("04007EE01C1A2000")
        try store.save(.init(urls: [], fetchedAt: Date()), for: meta.titleId)
        XCTAssertFalse(store.wantsLookup(meta), "LaunchBox had none: not asked every time")
        XCTAssertEqual(store.filled(meta), meta)
        XCTAssertTrue(store.wantsLookup(meta, now: Date().addingTimeInterval(31 * 24 * 60 * 60)))
    }

    func testTheGamesOwnScreenshotsWin() throws {
        let store = ScreenshotFallbackStore(directory: dir)
        let own = URL(string: "https://img-eshop.cdn.nintendo.net/x.jpg")!
        let meta = metadata("0100000000010000", screenshots: [own])
        try store.save(.init(urls: [URL(string: "https://images.launchbox-app.com/shot.png")!], fetchedAt: Date()),
                       for: meta.titleId)
        XCTAssertFalse(store.wantsLookup(meta))
        XCTAssertEqual(store.filled(meta).screenshotURLs, [own])
        XCTAssertNil(store.filled(meta).screenshotSource)
    }

    func testTheSourceIsNeverSavedWithTheMetadata() throws {
        var meta = metadata("04007EE01C1A2000")
        meta.screenshotSource = "LaunchBox"
        let back = try JSONDecoder().decode(NintendoStoreMetadata.self, from: JSONEncoder().encode(meta))
        XCTAssertNil(back.screenshotSource)
    }

    func testAChoiceSavesTheFullFileAndShowsItsSize() async {
        final class Client: ArtworkHTTPClient, @unchecked Sendable {
            let png: Data
            init(png: Data) { self.png = png }
            var asked: [URL] = []
            func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                asked.append(request.url!)
                return (png, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        let client = Client(png: png)
        let candidate = ArtworkCandidate(slot: .cover, source: "LaunchBox · Box - Front", url: URL(string: "https://images.launchbox-app.com/p.png")!,
                                         full: URL(string: "https://images.launchbox-app.com/f.png")!, width: 1164, height: 1902)
        guard let loaded = await ArtworkCandidates.load(candidate, client: client) else { return XCTFail("preview") }
        XCTAssertEqual(loaded.resolution, "1164 × 1902", "the full size, not the preview's")
        let chosen = await ArtworkCandidates.chosenData(loaded, client: client)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(client.asked.map(\.lastPathComponent), ["p.png", "f.png"])
    }
}

final class ConsoleNameTests: XCTestCase {
    func testSwitch2TitlesSaySo() {
        var game = PortedGame(name: "Donkey Kong Bananza", url: URL(fileURLWithPath: "/tmp/x.app"), platform: .macApp,
                              sizeBytes: 0, modificationDate: Date(), titleId: "04007EE01C1A2000")
        XCTAssertEqual(game.consoleName, "Nintendo Switch 2")
        game.titleId = "0100000000010000"
        XCTAssertEqual(game.consoleName, "Nintendo Switch")
        game.titleId = nil
        XCTAssertEqual(game.consoleName, "Nintendo Switch")
    }
}
