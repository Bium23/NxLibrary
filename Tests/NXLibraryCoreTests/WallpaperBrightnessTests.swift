import XCTest
@testable import NXLibraryCore

final class WallpaperBrightnessTests: XCTestCase {
    private let samples = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }

    func testOlderSettingsOpenOnTheRight() throws {
        let old = Data(#"{"backgroundShade":"deep","colorThemeID":"selene"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: old).wallpaperBrightness, .balanced)
        XCTAssertEqual(AppSettings().wallpaperBrightness, .balanced)
    }

    func testTheSettingSurvivesASave() throws {
        var settings = AppSettings()
        settings.wallpaperBrightness = .bright
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).wallpaperBrightness, .bright)
    }

    /// Selene draws its wallpaper at an even 0.6.
    func testLikeSeleneIsAnEvenSixtyPercent() {
        for x in samples { XCTAssertEqual(WallpaperBrightness.dim.opacity(at: x), 0.6, accuracy: 1e-9) }
    }

    /// The text on the left keeps Selene's 0.6; the right shows the picture at full light.
    func testBalancedKeepsTheLeftForTextAndOpensTheRight() {
        let level = WallpaperBrightness.balanced
        XCTAssertEqual(level.opacity(at: 0), 0.6, accuracy: 1e-9)
        XCTAssertEqual(level.opacity(at: 0.25), 0.6, accuracy: 1e-9)
        XCTAssertEqual(level.opacity(at: 0.8), 1, accuracy: 1e-9)
        XCTAssertEqual(level.opacity(at: 1), 1, accuracy: 1e-9)
        for (a, b) in zip(samples, samples.dropFirst()) {
            XCTAssertLessThanOrEqual(level.opacity(at: a), level.opacity(at: b), "never darker further right")
        }
    }

    func testEachLevelIsNoDimmerThanTheOneBefore() {
        for x in samples {
            XCTAssertLessThanOrEqual(WallpaperBrightness.dim.opacity(at: x), WallpaperBrightness.balanced.opacity(at: x))
            XCTAssertLessThanOrEqual(WallpaperBrightness.balanced.opacity(at: x), WallpaperBrightness.bright.opacity(at: x))
            XCTAssertLessThanOrEqual(WallpaperBrightness.bright.opacity(at: x), 1)
        }
        XCTAssertEqual(WallpaperBrightness.allCases, [.dim, .balanced, .bright])
        XCTAssertEqual(WallpaperBrightness.allCases.map(\.title), ["Like Selene", "Bright on the right", "Bright"])
    }
}
