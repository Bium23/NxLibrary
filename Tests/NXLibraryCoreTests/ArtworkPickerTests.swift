import XCTest
import AppKit
@testable import NXLibraryCore

final class ArtworkPickerTests: XCTestCase {
    private final class RoutedClient: ArtworkHTTPClient {
        var routes: [String: Data] = [:]
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let body = routes[request.url!.absoluteString]
            return (body ?? Data(), HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200,
                                                    httpVersion: nil, headerFields: nil)!)
        }
    }

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Picks-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func jpeg(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .jpeg, properties: [:])!
    }

    // MARK: - Title DB

    func testTitleDBInfoDecodesAndUpgradesToHTTPS() throws {
        let json = """
        {"id":"0100F2C0115B6000","name":"The Legend of Zelda™: Tears of the Kingdom",
         "icon":"http://api.nlib.cc/nx/0100F2C0115B6000/icon","banner":"http://api.nlib.cc/nx/0100F2C0115B6000/banner",
         "screens":{"count":2,"screenshots":["http://api.nlib.cc/nx/0100F2C0115B6000/screen/1",
                                              "http://api.nlib.cc/nx/0100F2C0115B6000/screen/2"]}}
        """
        let info = try TitleDBInfo.decode(Data(json.utf8))
        XCTAssertEqual(info.name, "The Legend of Zelda™: Tears of the Kingdom")
        XCTAssertEqual(info.icon?.absoluteString, "https://api.nlib.cc/nx/0100F2C0115B6000/icon")
        XCTAssertEqual(info.banner?.absoluteString, "https://api.nlib.cc/nx/0100F2C0115B6000/banner")
        XCTAssertEqual(info.screenshots.map(\.absoluteString).last, "https://api.nlib.cc/nx/0100F2C0115B6000/screen/2")

        let bare = try TitleDBInfo.decode(Data(#"{"id":"x","name":null,"icon":null,"banner":null}"#.utf8))
        XCTAssertNil(bare.icon)
        XCTAssertEqual(bare.screenshots, [])
    }

    // MARK: - Candidates

    private let totk = GameTDBEntry(id: "AAAAB", title: "The Legend of Zelda: Tears of the Kingdom", region: "ALL")
    private let totkJP = GameTDBEntry(id: "AAAAC", title: "The Legend of Zelda: Tears of the Kingdom", region: "NTSC-J")
    private var info: TitleDBInfo {
        TitleDBInfo(name: "Zelda", icon: URL(string: "https://api.nlib.cc/nx/T/icon"),
                    banner: URL(string: "https://api.nlib.cc/nx/T/banner"),
                    screenshots: [URL(string: "https://api.nlib.cc/nx/T/screen/1")!])
    }

    func testCoverCandidatesWalkEntriesAndRegions() {
        let list = ArtworkCandidates.list(for: .cover, entries: [totk, totkJP], titleDB: info,
                                          storeHeader: nil, storeImage: nil, storeLogo: nil)
        XCTAssertEqual(list.first?.url.absoluteString, "https://art.gametdb.com/switch/coverHQ/US/AAAAB.jpg")
        XCTAssertEqual(list.first?.source, "GameTDB · US")
        XCTAssertEqual(list.count, 2 * ArtworkCandidates.pickerRegions.count)
        XCTAssertTrue(list.contains { $0.url.absoluteString == "https://art.gametdb.com/switch/coverHQ/JA/AAAAC.jpg" })
        XCTAssertEqual(Set(list.map(\.url)).count, list.count, "no duplicates")
    }

    func testOtherSlotsUseTitleDBAndStore() {
        let header = URL(string: "https://img.example/header.jpg")!
        let backgrounds = ArtworkCandidates.list(for: .background, entries: [], titleDB: info,
                                                 storeHeader: header, storeImage: header, storeLogo: nil)
        XCTAssertEqual(backgrounds.map(\.source), ["Title DB banner", "Title DB screenshot 1", "Nintendo store"])

        let icons = ArtworkCandidates.list(for: .icon, entries: [totk], titleDB: info,
                                           storeHeader: nil, storeImage: nil, storeLogo: nil)
        XCTAssertEqual(icons.map(\.source), ["Title DB icon"])

        let logos = ArtworkCandidates.list(for: .logo, entries: [], titleDB: nil, storeHeader: nil, storeImage: nil,
                                           storeLogo: URL(string: "https://img.example/logo.png"))
        XCTAssertEqual(logos.map(\.source), ["Nintendo store"])
        XCTAssertEqual(ArtworkCandidates.list(for: .logo, entries: [], titleDB: nil, storeHeader: nil,
                                              storeImage: nil, storeLogo: nil), [])
    }

    func testLoadMeasuresAndDropsMisses() async {
        let client = RoutedClient()
        let good = URL(string: "https://art.gametdb.com/switch/coverHQ/US/AAAAB.jpg")!
        client.routes[good.absoluteString] = jpeg(width: 1166, height: 1888)
        client.routes["https://img.example/not-an-image"] = Data("<html>".utf8)

        let loaded = await ArtworkCandidates.load(ArtworkCandidate(slot: .cover, source: "GameTDB · US", url: good),
                                                  client: client)
        XCTAssertEqual(loaded?.pixelWidth, 1166)
        XCTAssertEqual(loaded?.pixelHeight, 1888)
        XCTAssertEqual(loaded?.resolution, "1166 × 1888")

        let missing = await ArtworkCandidates.load(ArtworkCandidate(slot: .cover, source: "x",
                                                                    url: URL(string: "https://nope.example/a.jpg")!),
                                                   client: client)
        XCTAssertNil(missing)
        let junk = await ArtworkCandidates.load(ArtworkCandidate(slot: .cover, source: "x",
                                                                 url: URL(string: "https://img.example/not-an-image")!),
                                                client: client)
        XCTAssertNil(junk)
    }

    // MARK: - Picks

    func testPicksSaveReplaceAndRemove() throws {
        let picks = ArtworkPicks(directory: tempDir())
        XCTAssertNil(picks.url(titleID: "0100F2C0115B6000", slot: .cover))
        XCTAssertEqual(picks.revision, 0)

        let saved = try picks.save(jpeg(width: 2000, height: 3238), titleID: "0100F2C0115B6000", slot: .cover)
        XCTAssertEqual(picks.url(titleID: "0100F2C0115B6000", slot: .cover), saved)
        XCTAssertEqual(NSBitmapImageRep(data: try Data(contentsOf: saved))?.pixelsHigh, 1400)
        XCTAssertEqual(picks.revision, 1)

        let logo = try picks.save(jpeg(width: 300, height: 100), titleID: "0100F2C0115B6000", slot: .logo)
        XCTAssertEqual(logo.pathExtension, "png", "logos keep transparency")

        picks.remove(titleID: "0100F2C0115B6000", slot: .cover)
        XCTAssertNil(picks.url(titleID: "0100F2C0115B6000", slot: .cover))
        XCTAssertNotNil(picks.url(titleID: "0100F2C0115B6000", slot: .logo))
        XCTAssertEqual(picks.revision, 3)

        XCTAssertThrowsError(try picks.save(Data("nope".utf8), titleID: "x", slot: .icon))
    }

    func testSlotsMapToCacheKinds() {
        XCTAssertEqual(ArtworkSlot.allCases.map(\.title), ["Cover", "Background", "Icon", "Logo"])
        XCTAssertEqual(ArtworkSlot.allCases.map(\.kind), [.boxart, .hero, .square, .logo])
    }
}
