import XCTest
import AppKit
@testable import NXLibraryCore

final class AutomaticIconTests: XCTestCase {
    private let switch1 = "0100F2C0115B6000"
    private let switch2 = "0400486024DEC000"
    private let html = """
    <tr><td><a href='./detail.php?id=828'><img src='./images/100/828.png'></a></td><td><center>Hollow Knight</center></td></tr>
    <tr><td><a href='./detail.php?id=13932'><img></a></td><td><center>Hollow Knight - Nintendo Switch 2 Edition</center></td></tr>
    <tr><td><a href='./detail.php?id=13670'><img></a></td><td><center>Hollow Knight: Silksong</center></td></tr>
    """

    func testExactGameWinsRatherThanFirstResultOrASequel() {
        let results = SwitchIconShowdown.results(in: html)
        XCTAssertEqual(SwitchIconShowdown.match(name: "Hollow Knight", titleID: switch1, results: results)?.id, 828)
        XCTAssertEqual(SwitchIconShowdown.match(name: "Hollow Knight - Nintendo Switch 2 Edition", titleID: switch2, results: results)?.id, 13932)
        XCTAssertNil(SwitchIconShowdown.match(name: "Hollow Knight", titleID: switch1,
            results: [SwitchIconShowdown.Result(id: 1, title: "Hollow Knight"), SwitchIconShowdown.Result(id: 2, title: "Hollow Knight")]), "Duplicate titles with different IDs are ambiguous")
        XCTAssertNil(SwitchIconShowdown.match(name: "Hollow Knight", titleID: switch2, results: results), "Switch 2 Title ID alone does not identify the edition")
        XCTAssertNil(SwitchIconShowdown.match(name: "Hollow Knight", titleID: switch1, results: Array(results.suffix(1))))
    }

    func testNormalizationAndMalformedResults() {
        let text = "<tr><td><a href='./detail.php?id=12'><img></a></td><td><center>Pokémon &amp; Friends</center></td></tr>"
        XCTAssertEqual(SwitchIconShowdown.match(name: "Pokemon & Friends", titleID: switch2, results: SwitchIconShowdown.results(in: text))?.id, 12)
        XCTAssertTrue(SwitchIconShowdown.results(in: "<script>detail.php?id=12</script>").isEmpty)
        XCTAssertNil(SwitchIconShowdown.match(name: "", titleID: switch2, results: SwitchIconShowdown.results(in: text)))
    }

    func testSpecificRobotsOptOutOverridesGeneralAllowAndUnknownPolicyIsDenied() {
        XCTAssertFalse(SwitchIconShowdown.allowsIcons(in: "<html>unavailable</html>", path: "/images/828.png"))
        XCTAssertFalse(SwitchIconShowdown.allowsIcons(in: "User-agent: *\nAllow: /images/\nUser-agent: NXLibrary\nDisallow: /\n", path: "/images/828.png"))
        XCTAssertTrue(SwitchIconShowdown.allowsIcons(in: "User-agent: *\nDisallow: /images/\nAllow: /images/828.png\n", path: "/images/828.png"))
    }

    private final class Client: ArtworkHTTPClient {
        var requests: [URL] = []
        var primaryStatus = 404
        var robots = "User-agent: *\nAllow: /\n"
        var searchHTML = ""
        var image: Data = Data()
        var offline = false
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!
            requests.append(url)
            if offline { throw URLError(.notConnectedToInternet) }
            let data: Data, status: Int
            if url.host == "api.nlib.cc" { data = image; status = primaryStatus }
            else if url.path == "/robots.txt" { data = Data(robots.utf8); status = 200 }
            else if url.path == "/search.php" { data = Data(searchHTML.utf8); status = 200 }
            else { data = image; status = 200 }
            return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private func folder() -> URL {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: f) }
        return f
    }

    private func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testPrimaryIconStopsTheFallback() async {
        let c = Client(); c.primaryStatus = 200; c.image = png()
        let store = ArtworkStore(cacheDirectory: folder(), client: c)
        let url = await store.automaticIcon(titleID: switch1, name: "Hollow Knight")
        XCTAssertNotNil(url)
        XCTAssertEqual(c.requests.map(\.host), ["api.nlib.cc"])
    }

    func testMissingPrimaryUsesMatchedIconAndCachesForOfflineUse() async {
        let c = Client(); c.searchHTML = html; c.image = png()
        let store = ArtworkStore(cacheDirectory: folder(), client: c)
        let first = await store.automaticIcon(titleID: switch1, name: "Hollow Knight")
        XCTAssertNotNil(first)
        XCTAssertEqual(c.requests.last?.path, "/images/828.png")
        c.offline = true
        let again = await store.automaticIcon(titleID: switch1, name: "Hollow Knight")
        XCTAssertEqual(first, again)
        XCTAssertEqual(c.requests.count, 4)
    }

    func testAmbiguousAndUnavailableSourcesLeaveNoIconAndDoNotRetryImmediately() async {
        let c = Client(); c.searchHTML = html; c.image = png()
        let store = ArtworkStore(cacheDirectory: folder(), client: c)
        let first = await store.automaticIcon(titleID: switch2, name: "Hollow Knight")
        XCTAssertNil(first)
        let second = await store.automaticIcon(titleID: switch2, name: "Hollow Knight")
        XCTAssertNil(second)
        XCTAssertEqual(c.requests.count, 3)
        XCTAssertTrue(c.requests.allSatisfy { !$0.path.hasPrefix("/images/") })
    }

    func testSiteOptOutStopsAutomaticImageDownloads() async {
        let c = Client(); c.searchHTML = html; c.image = png()
        c.robots = "User-agent: *\nDisallow: /images/\n"
        let store = ArtworkStore(cacheDirectory: folder(), client: c)
        let result = await store.automaticIcon(titleID: switch1, name: "Hollow Knight")
        XCTAssertNil(result)
        XCTAssertTrue(c.requests.allSatisfy { !$0.path.hasPrefix("/images/") })
    }

    func testInvalidImageIsNotCachedAsAnIcon() async {
        let c = Client(); c.primaryStatus = 200; c.searchHTML = html; c.image = Data("not an image".utf8)
        let store = ArtworkStore(cacheDirectory: folder(), client: c)
        let result = await store.automaticIcon(titleID: switch1, name: "Hollow Knight")
        XCTAssertNil(result)
        XCTAssertNil(store.cachedURL(titleID: switch1, kind: .square))
    }
}
