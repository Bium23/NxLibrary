import XCTest
import AppKit
@testable import NXLibraryCore

final class SteamBackdropChoiceTests: XCTestCase {
    private let shot = URL(string: "https://shared.akamai.steamstatic.com/shot.jpg")!
    private let hero = URL(string: "https://shared.akamai.steamstatic.com/library_hero.jpg")!

    func testScreenShapedArtOnly() {
        XCTAssertTrue(SteamBackdropChoice.suits(width: 1920, height: 1080))
        XCTAssertTrue(SteamBackdropChoice.suits(width: 1920, height: 1200))
        XCTAssertFalse(SteamBackdropChoice.suits(width: 3840, height: 1240), "Steam's library hero is a banner")
        XCTAssertFalse(SteamBackdropChoice.suits(width: 1024, height: 576), "too small for a full screen")
        XCTAssertFalse(SteamBackdropChoice.suits(width: 600, height: 900))
    }

    func testCleanStoreHeroesComeFirstThenTheExactScreenshotThenTheBanner() {
        let art = [
            ArtworkCandidate(slot: .background, source: "Xbox Store · titled", url: URL(string: "https://x/titled")!),
            ArtworkCandidate(slot: .background, source: "TheGamesDB fan art", url: URL(string: "https://t/fan")!),
            ArtworkCandidate(slot: .cover, source: "GOG", url: URL(string: "https://g/cover")!),
            ArtworkCandidate(slot: .background, source: "GOG", url: URL(string: "https://g/galaxy")!),
            ArtworkCandidate(slot: .background, source: "GOG", url: URL(string: "https://g/wide-cover")!),
            ArtworkCandidate(slot: .background, source: "Xbox Store", url: URL(string: "https://x/hero")!)
        ]
        let order = SteamBackdropChoice.ordered(storeArt: art, screenshots: [shot, URL(string: "https://s/2")!], libraryHero: hero)
        XCTAssertEqual(order.map(\.absoluteString), ["https://x/hero", "https://g/galaxy", "https://t/fan", shot.absoluteString, hero.absoluteString])
        XCTAssertEqual(SteamBackdropChoice.ordered(storeArt: [], screenshots: [], libraryHero: hero), [hero])
    }

    func testChoosesTheFirstScreenShapedImageAndFallsBackToTheBanner() async throws {
        let banner = try XCTUnwrap(Self.png(width: 1500, height: 484))
        let wide = try XCTUnwrap(Self.png(width: 1600, height: 900))
        var asked: [URL] = []
        let chosen = await SteamBackdropChoice.choose([URL(string: "https://x/missing")!, hero, shot]) { url in
            asked.append(url)
            return url == hero ? banner : url == self.shot ? wide : nil
        }
        XCTAssertEqual(chosen, shot)
        XCTAssertEqual(asked.count, 3)
        let fallback = await SteamBackdropChoice.choose([shot, hero]) { _ in banner }
        XCTAssertEqual(fallback, hero)
    }

    private static func png(width: Int, height: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
