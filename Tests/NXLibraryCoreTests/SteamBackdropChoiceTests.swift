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

    func testLaunchBoxComputerFanartComesAfterTheStoresAndBeforeScreenshots() {
        let fanart = { (name: String, w: Int?, h: Int?) in
            ArtworkCandidate(slot: .background, source: "LaunchBox · Fanart - Background", url: URL(string: "https://l/\(name)-preview")!,
                             full: URL(string: "https://l/\(name)"), width: w, height: h)
        }
        let art = [
            ArtworkCandidate(slot: .background, source: "LaunchBox · Screenshot - Gameplay", url: URL(string: "https://l/play")!,
                             full: URL(string: "https://l/play-full"), width: 1920, height: 1080),
            fanart("banner", 3840, 1240),
            fanart("small", 1024, 576),
            fanart("wide", 2560, 1440),
            ArtworkCandidate(slot: .background, source: "GOG", url: URL(string: "https://g/galaxy")!)
        ]
        let order = SteamBackdropChoice.ordered(storeArt: art, screenshots: [shot], libraryHero: hero)
        // The full file, not its preview; only a screen-shaped one; gameplay shots are not fan art.
        XCTAssertEqual(order.map(\.absoluteString), ["https://g/galaxy", "https://l/wide", shot.absoluteString, hero.absoluteString])
        let unsized = SteamBackdropChoice.ordered(storeArt: [fanart("unknown", nil, nil)], screenshots: [], libraryHero: nil)
        XCTAssertEqual(unsized.map(\.absoluteString), ["https://l/unknown"], "a size the page does not state is checked when chosen")
    }

    func testChoosesTheFirstScreenShapedImageAndFallsBackToTheBanner() async throws {
        let banner = try XCTUnwrap(Self.png(width: 1500, height: 484))
        let wide = try XCTUnwrap(Self.png(width: 1600, height: 900))
        var asked: [URL] = []
        let chosen = await SteamBackdropChoice.choose([URL(string: "https://x/missing")!, hero, shot], fallback: hero) { url in
            asked.append(url)
            return url == hero ? banner : url == self.shot ? wide : nil
        }
        XCTAssertEqual(chosen, shot)
        XCTAssertEqual(asked.count, 3)
        let fallback = await SteamBackdropChoice.choose([shot, hero], fallback: hero) { _ in banner }
        XCTAssertEqual(fallback, hero)
    }

    func testWithoutAScreenShapedImageOrBannerTheFirstImageThatLoadsIsShown() async throws {
        let small = try XCTUnwrap(Self.png(width: 1024, height: 576))
        let missing = URL(string: "https://x/missing")!
        let chosen = await SteamBackdropChoice.choose([missing, shot], fallback: nil) { $0 == self.shot ? small : nil }
        XCTAssertEqual(chosen, shot, "never the last URL just for being last: one that loads")
        let none = await SteamBackdropChoice.choose([missing], fallback: nil) { _ in nil }
        XCTAssertNil(none)
    }

    private static func png(width: Int, height: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
