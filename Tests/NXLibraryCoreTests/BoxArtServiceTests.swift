import XCTest
import AppKit
@testable import NXLibraryCore

final class BoxArtServiceTests: XCTestCase {
    /// Answers by URL; anything unknown is a 404.
    private final class RoutedClient: ArtworkHTTPClient {
        var routes: [String: Data] = [:]
        var requested: [String] = []
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!.absoluteString
            requested.append(url)
            let body = routes[url]
            return (body ?? Data(), HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200,
                                                    httpVersion: nil, headerFields: nil)!)
        }
    }

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BoxArt-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func jpeg(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .jpeg, properties: [:])!
    }

    private let zelda = GameTDBEntry(id: "AAAAA", title: "The Legend of Zelda: Breath of the Wild", region: "ALL")
    private let totk = GameTDBEntry(id: "AAAAB", title: "The Legend of Zelda: Tears of the Kingdom", region: "ALL")

    private func service(_ client: RoutedClient, now: @escaping () -> Date = Date.init,
                         unzip: @escaping (Data) throws -> Data = { $0 }) throws -> (BoxArtService, ArtworkStore, GameTDBStore) {
        let root = tempDir()
        let artwork = ArtworkStore(cacheDirectory: root.appendingPathComponent("artwork"), client: client)
        let index = GameTDBStore(directory: root.appendingPathComponent("metadata"))
        return (BoxArtService(artwork: artwork, index: index, client: client, unzip: unzip, now: now), artwork, index)
    }

    func testFindsCoverByNameAndWalksRegions() async throws {
        let client = RoutedClient()
        client.routes["https://art.gametdb.com/switch/coverHQ/EN/AAAAB.jpg"] = jpeg(width: 1166, height: 1888)
        let (boxArt, artwork, index) = try service(client)
        try index.save([zelda, totk])

        // The player's own name misses; the official name (second) finds it, US 404s, EN answers.
        let url = await boxArt.boxArt(titleID: "0100F2C0115B6000", names: ["TOTK", "The Legend of Zelda™: Tears of the Kingdom"])
        XCTAssertEqual(url, artwork.cachedURL(titleID: "0100F2C0115B6000", kind: .boxart))
        XCTAssertEqual(client.requested, ["https://art.gametdb.com/switch/coverHQ/US/AAAAB.jpg",
                                          "https://art.gametdb.com/switch/coverHQ/EN/AAAAB.jpg"])
        let image = NSBitmapImageRep(data: try Data(contentsOf: try XCTUnwrap(url)))!
        XCTAssertEqual(image.pixelsHigh, 1400)

        client.requested = []
        _ = await boxArt.boxArt(titleID: "0100F2C0115B6000", names: ["TOTK"])
        XCTAssertEqual(client.requested, [], "a cached cover needs no network")
    }

    func testMissIsRememberedForAWeek() async throws {
        let client = RoutedClient()
        var now = Date()
        let (boxArt, _, index) = try service(client, now: { now })
        try index.save([zelda])

        let none = await boxArt.boxArt(titleID: "01007EF00011E000", names: ["The Legend of Zelda: Breath of the Wild"])
        XCTAssertNil(none)
        XCTAssertEqual(client.requested.count, GameTDB.coverRegions.count)

        client.requested = []
        _ = await boxArt.boxArt(titleID: "01007EF00011E000", names: ["The Legend of Zelda: Breath of the Wild"])
        XCTAssertEqual(client.requested, [])

        now = now.addingTimeInterval(8 * 24 * 3600)
        _ = await boxArt.boxArt(titleID: "01007EF00011E000", names: ["The Legend of Zelda: Breath of the Wild"])
        XCTAssertEqual(client.requested.count, GameTDB.coverRegions.count)
    }

    func testNewNameRetriesAfterMiss() async throws {
        let client = RoutedClient()
        client.routes["https://art.gametdb.com/switch/coverHQ/US/AAAAB.jpg"] = jpeg(width: 400, height: 640)
        let (boxArt, _, index) = try service(client)
        try index.save([zelda, totk])

        let none = await boxArt.boxArt(titleID: "0100F2C0115B6000", names: ["TOTK"])
        XCTAssertNil(none)
        // The official name arrives later (store metadata): the miss must not block it.
        let found = await boxArt.boxArt(titleID: "0100F2C0115B6000",
                                        names: ["TOTK", "The Legend of Zelda: Tears of the Kingdom"])
        XCTAssertNotNil(found)
    }

    func testPickerEntriesPutExactTitlesFirst() async throws {
        let client = RoutedClient()
        let (boxArt, _, index) = try service(client)
        let totkJP = GameTDBEntry(id: "AAAAC", title: "The Legend of Zelda: Tears of the Kingdom", region: "NTSC-J")
        let echoes = GameTDBEntry(id: "AAAAD", title: "The Legend of Zelda: Echoes of Wisdom", region: "ALL")
        try index.save([zelda, echoes, totkJP, totk])

        let entries = await boxArt.pickerEntries(names: ["TOTK", "The Legend of Zelda: Tears of the Kingdom"])
        XCTAssertEqual(Array(entries.prefix(2).map(\.id)), ["AAAAB", "AAAAC"], "every region of the exact title, widest first")
        XCTAssertLessThanOrEqual(entries.count, BoxArtService.pickerLimit)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        let none = await boxArt.pickerEntries(names: ["Metroid Dread"])
        XCTAssertEqual(none, [])
    }

    func testNoIndexYetIsNotAMiss() async throws {
        let client = RoutedClient()
        let (boxArt, _, index) = try service(client)
        let none = await boxArt.boxArt(titleID: "01007EF00011E000", names: ["The Legend of Zelda: Breath of the Wild"])
        XCTAssertNil(none)
        try index.save([zelda])
        client.routes["https://art.gametdb.com/switch/coverHQ/US/AAAAA.jpg"] = jpeg(width: 400, height: 640)
        let found = await boxArt.boxArt(titleID: "01007EF00011E000", names: ["The Legend of Zelda: Breath of the Wild"])
        XCTAssertNotNil(found)
    }

    func testRefreshIndexDownloadsWhenStale() async throws {
        let client = RoutedClient()
        let xml = """
        <datafile><game name="x"><id>AAAAA</id><region>ALL</region>
        <locale lang="EN"><title>The Legend of Zelda: Breath of the Wild</title></locale></game></datafile>
        """
        client.routes[GameTDB.databaseURL.absoluteString] = Data(xml.utf8)
        let (boxArt, _, index) = try service(client)

        await boxArt.refreshIndexIfNeeded()
        XCTAssertEqual(index.load()?.map(\.id), ["AAAAA"])
        XCTAssertEqual(client.requested, [GameTDB.databaseURL.absoluteString])

        client.requested = []
        await boxArt.refreshIndexIfNeeded()
        XCTAssertEqual(client.requested, [], "a fresh index is not downloaded again")
    }
}
