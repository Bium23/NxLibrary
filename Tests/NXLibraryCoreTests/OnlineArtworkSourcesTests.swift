import XCTest
import AppKit
@testable import NXLibraryCore

final class OnlineArtworkSourcesTests: XCTestCase {
    private final class RoutedClient: ArtworkHTTPClient {
        var routes: [String: Data] = [:]
        var asked: [URL] = []
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            asked.append(request.url!)
            let body = routes[request.url!.absoluteString]
            return (body ?? Data(), HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200,
                                                    httpVersion: nil, headerFields: nil)!)
        }
    }

    private func query(_ url: URL?) -> [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Steam

    // Trimmed from a real store search for "LumenTale".
    private let lumenSearch = Data("""
    {"total":3,"items":[
     {"type":"app","name":"LumenTale: Memories of Trey - Deluxe DLC","id":3976090},
     {"type":"app","name":"LumenTale: Memories of Trey","id":2261430},
     {"type":"app","name":"LumenTale: Memories of Trey Soundtrack","id":3976091}]}
    """.utf8)

    func testSteamSearchesTheStoreByName() {
        let url = SteamStoreArt.searchURL(for: "LumenTale™: Memories of Trey")
        XCTAssertTrue(url!.absoluteString.hasPrefix("https://store.steampowered.com/api/storesearch/?"))
        XCTAssertEqual(query(url)["term"], "LumenTale: Memories of Trey", "trademark signs dropped")
        XCTAssertNil(SteamStoreArt.searchURL(for: " ™ "))
    }

    /// Only the game whose name is the same: never its DLC or soundtrack, never a near miss.
    func testSteamTakesOnlyAnExactName() {
        XCTAssertEqual(SteamStoreArt.appID(in: lumenSearch, matching: ["LumenTale™: Memories of Trey"]), 2261430)
        XCTAssertEqual(SteamStoreArt.appID(in: lumenSearch, matching: ["Other", "lumentale memories of trey"]), 2261430)
        XCTAssertNil(SteamStoreArt.appID(in: lumenSearch, matching: ["LumenTale"]))
        XCTAssertNil(SteamStoreArt.appID(in: Data("not json".utf8), matching: ["LumenTale"]))
    }

    func testSteamOffersLogoCoverAndBackgroundAtTwiceTheSize() {
        let logo = SteamStoreArt.candidates(appID: 2261430, slot: .logo)
        XCTAssertEqual(logo.map(\.source), ["Steam"])
        XCTAssertEqual(logo[0].url.absoluteString,
                       "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2261430/logo_2x.png")
        XCTAssertEqual(logo[0].fallback?.lastPathComponent, "logo.png")
        XCTAssertEqual(SteamStoreArt.candidates(appID: 1, slot: .cover)[0].url.lastPathComponent, "library_600x900_2x.jpg")
        XCTAssertEqual(SteamStoreArt.candidates(appID: 1, slot: .cover)[0].fallback?.lastPathComponent, "library_600x900.jpg")
        XCTAssertEqual(SteamStoreArt.candidates(appID: 1, slot: .background)[0].url.lastPathComponent, "library_hero_2x.jpg")
        XCTAssertEqual(SteamStoreArt.candidates(appID: 1, slot: .icon), [])
    }

    func testSteamFindAsksOnceForTheFirstNameThatMatches() async {
        let client = RoutedClient()
        let first = SteamStoreArt.searchURL(for: "Lumen Tale")!
        let second = SteamStoreArt.searchURL(for: "LumenTale: Memories of Trey")!
        client.routes[first.absoluteString] = Data(#"{"total":0,"items":[]}"#.utf8)
        client.routes[second.absoluteString] = lumenSearch
        let id = await SteamStoreArt.findAppID(names: ["Lumen Tale", "LumenTale: Memories of Trey",
                                                      "LumenTale: Memories of Trey"], client: client)
        XCTAssertEqual(id, 2261430)
        XCTAssertEqual(client.asked, [first, second], "the same name is not searched twice")
    }

    // MARK: - Wikimedia Commons

    // Trimmed from a real Commons search for "Hollow Knight logo".
    private let commonsSearch = Data("""
    {"query":{"pages":[
     {"title":"File:Hollow Knight Silksong Logo.svg","index":1,"imageinfo":[{"mime":"image/svg+xml","width":1000,"height":290,
      "url":"https://upload.wikimedia.org/wikipedia/commons/0/08/Hollow_Knight_Silksong_Logo.svg",
      "thumburl":"https://upload.wikimedia.org/wikipedia/commons/thumb/0/08/Hollow_Knight_Silksong_Logo.svg/1920px-Hollow_Knight_Silksong_Logo.svg.png"}]},
     {"title":"File:Hollow Knight Logo.svg","index":2,"imageinfo":[{"mime":"image/svg+xml","width":1000,"height":290,
      "url":"https://upload.wikimedia.org/wikipedia/commons/1/11/Hollow_Knight_Logo.svg",
      "thumburl":"https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Hollow_Knight_Logo.svg/1920px-Hollow_Knight_Logo.svg.png"}]},
     {"title":"File:Hollow Knight text-only logo black.svg","index":3,"imageinfo":[{"mime":"image/svg+xml","width":721,"height":93,
      "url":"https://upload.wikimedia.org/wikipedia/commons/9/95/a.svg","thumburl":"https://upload.wikimedia.org/x/a.png"}]},
     {"title":"File:Hollow Knight Textlogo.png","index":4,"imageinfo":[{"mime":"image/png","width":800,"height":119,
      "url":"https://upload.wikimedia.org/wikipedia/commons/f/f2/Hollow_Knight_Textlogo.png?utm_source=commons",
      "thumburl":"https://upload.wikimedia.org/wikipedia/commons/f/f2/Hollow_Knight_Textlogo.png?utm_source=commons"}]},
     {"title":"File:Hollow Knight booth at PAX.jpg","index":5,"imageinfo":[{"mime":"image/jpeg","width":4000,"height":3000,
      "url":"https://upload.wikimedia.org/b.jpg","thumburl":"https://upload.wikimedia.org/b-1920.jpg"}]},
     {"title":"File:Hollow Knight gameplay.png","index":6,"imageinfo":[{"mime":"image/png","width":1920,"height":1080,
      "url":"https://upload.wikimedia.org/c.png","thumburl":"https://upload.wikimedia.org/c-1920.png"}]},
     {"title":"File:Deadlock logo - Hollow Knight.png","index":7,"imageinfo":[{"mime":"image/png","width":600,"height":300,
      "url":"https://upload.wikimedia.org/d.png","thumburl":"https://upload.wikimedia.org/d.png"}]},
     {"title":"File:Hollow Knight logo large.png","index":8,"imageinfo":[{"mime":"image/png","width":5000,"height":2000,
      "url":"https://upload.wikimedia.org/e.png","thumburl":"https://upload.wikimedia.org/e-1920.png"}]}
    ]}}
    """.utf8)

    func testCommonsSearchesFilesForTheNameAndLogo() {
        let url = CommonsLogos.searchURL(for: "Hollow Knight™")
        XCTAssertEqual(url?.host, "commons.wikimedia.org")
        let items = query(url)
        XCTAssertEqual(items["gsrsearch"], "Hollow Knight logo")
        XCTAssertEqual(items["gsrnamespace"], "6", "files only")
        XCTAssertEqual(items["prop"], "imageinfo")
        XCTAssertNil(CommonsLogos.searchURL(for: "™"))
    }

    /// A logo of this game: its name first, then nothing or a logo word; never a sequel,
    /// a photo, a screenshot, someone else's logo or a black one that vanishes on the dark.
    func testCommonsKeepsOnlyThisGamesLogos() {
        let urls = CommonsLogos.parse(commonsSearch, gameNames: ["Hollow Knight™"])
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Hollow_Knight_Logo.svg/1920px-Hollow_Knight_Logo.svg.png",
            "https://upload.wikimedia.org/wikipedia/commons/f/f2/Hollow_Knight_Textlogo.png",
            "https://upload.wikimedia.org/e-1920.png"
        ])
        XCTAssertEqual(CommonsLogos.parse(Data("{}".utf8), gameNames: ["Hollow Knight"]), [])
    }

    func testCommonsTakesAFileNamedJustLikeTheGame() {
        let zelda = Data("""
        {"query":{"pages":[{"title":"File:The Legend of Zelda Tears of the Kingdom.svg","index":1,
         "imageinfo":[{"mime":"image/svg+xml","width":1900,"height":828,"url":"https://upload.wikimedia.org/z.svg",
         "thumburl":"https://upload.wikimedia.org/z-1920.png"}]}]}}
        """.utf8)
        XCTAssertEqual(CommonsLogos.parse(zelda, gameNames: ["The Legend of Zelda™: Tears of the Kingdom"]).count, 1)
    }

    // MARK: - The picker

    func testPickerListsSteamAndCommonsAfterTheStore() {
        let store = URL(string: "https://img.example/logo.png")!
        let commons = ArtworkCandidate(slot: .logo, source: "Wikimedia Commons", url: URL(string: "https://upload.wikimedia.org/z.png")!)
        let online = ArtworkSlot.allCases.flatMap { SteamStoreArt.candidates(appID: 7, slot: $0) } + [commons]
        let logos = ArtworkCandidates.list(for: .logo, entries: [], titleDB: nil, storeHeader: nil, storeImage: nil,
                                           storeLogo: store, online: online)
        XCTAssertEqual(logos.map(\.source), ["Nintendo store", "Steam", "Wikimedia Commons"])
        let backgrounds = ArtworkCandidates.list(for: .background, entries: [], titleDB: nil, storeHeader: nil,
                                                 storeImage: nil, storeLogo: nil, online: online)
        XCTAssertEqual(backgrounds.map(\.source), ["Steam"], "Commons gives logos only")
    }

    func testLoadFallsBackWhenTheLargeFileIsMissing() async {
        let client = RoutedClient()
        let small = URL(string: "https://img.example/logo.png")!
        client.routes[small.absoluteString] = png
        let candidate = ArtworkCandidate(slot: .logo, source: "Steam", url: URL(string: "https://img.example/logo_2x.png")!,
                                         fallback: small)
        let loaded = await ArtworkCandidates.load(candidate, client: client)
        XCTAssertEqual(loaded?.pixelWidth, 4)
        let missing = await ArtworkCandidates.load(ArtworkCandidate(slot: .logo, source: "x",
                                                                    url: URL(string: "https://img.example/none.png")!),
                                                   client: client)
        XCTAssertNil(missing)
    }

    private var png: Data {
        let context = CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }
}
