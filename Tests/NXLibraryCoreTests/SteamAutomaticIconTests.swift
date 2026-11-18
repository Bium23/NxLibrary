import XCTest
import AppKit
@testable import NXLibraryCore

/// A Steam game with no app has no icon of its own: LaunchBox's Square for its PC entry, else nothing.
final class SteamAutomaticIconTests: XCTestCase {
    private final class Client: ArtworkHTTPClient, @unchecked Sendable {
        var routes: [String: Data] = [:]
        var asked: [String] = []
        private let lock = NSLock()
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!.absoluteString
            let body: Data? = lock.withLock { asked.append(url); return routes[url] }
            return (body ?? Data(), HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    private static let search = "https://gamesdb.launchbox-app.com/games/results/crimson%20desert%20enhanced"
    private static let details = "https://gamesdb.launchbox-app.com/games/details/436343-crimson-desert-enhanced"
    private static let square = "https://images.launchbox-app.com/square-full.png"

    private static var png: Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func store(_ client: Client) -> ArtworkStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SteamIcon-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return ArtworkStore(cacheDirectory: directory, client: client)
    }

    private func client(square: Bool) -> Client {
        let client = Client()
        // A console entry first, as LaunchBox lists it: never taken for a Steam game.
        client.routes[Self.search] = Data((LaunchBoxArtTests.card("438331-crimson-desert", "Crimson Desert Enhanced", "Sony Playstation 5")
            + LaunchBoxArtTests.card("436343-crimson-desert-enhanced", "Crimson Desert Enhanced", "Windows")).utf8)
        var images: [LaunchBoxArtTests.Image] = [("Box - Front", "World", "front.jpg", "front-full.jpg", 600, 900),
                                                 ("Fanart - Background", "World", "fan.jpg", "fan-full.jpg", 1920, 1080)]
        if square { images.append(("Square", "World", "square.png", "square-full.png", 512, 512)) }
        client.routes[Self.details] = Data(LaunchBoxArtTests.page(images).utf8)
        client.routes[Self.square] = Self.png
        return client
    }

    func testTheSquareIsTheFullSquareImageOnly() {
        let candidates = LaunchBoxArt.candidates(in: LaunchBoxArtTests.gamePage)
        XCTAssertEqual(LaunchBoxArt.square(in: candidates)?.lastPathComponent, "r2_square-full.jpg")
        XCTAssertNil(LaunchBoxArt.square(in: candidates.filter { $0.slot != .icon }))
    }

    func testTheComputerEntrySquareIsFetchedOnceAndKept() async throws {
        let client = client(square: true)
        let artwork = store(client)
        let first = await artwork.automaticSteamIcon(titleID: "steam-3321460", names: ["Crimson Desert Enhanced"])
        XCTAssertEqual(first, artwork.cachedURL(titleID: "steam-3321460", kind: .square))
        XCTAssertTrue(client.asked.contains(Self.square))
        let asked = client.asked.count
        let again = await artwork.automaticSteamIcon(titleID: "steam-3321460", names: ["Crimson Desert Enhanced"])
        XCTAssertEqual(again, first)
        XCTAssertEqual(client.asked.count, asked, "kept on disk: no new lookup")
    }

    func testNoSquareGivesNothingAndIsNotAskedAgainThisSession() async {
        let client = client(square: false)
        let artwork = store(client)
        let none = await artwork.automaticSteamIcon(titleID: "steam-3321460", names: ["Crimson Desert Enhanced"])
        XCTAssertNil(none)
        XCTAssertFalse(client.asked.contains(Self.square))
        let asked = client.asked.count
        let again = await artwork.automaticSteamIcon(titleID: "steam-3321460", names: ["Crimson Desert Enhanced"])
        XCTAssertNil(again)
        XCTAssertEqual(client.asked.count, asked)
    }
}
