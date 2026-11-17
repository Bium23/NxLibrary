import XCTest
@testable import NXLibraryCore

final class MoonlightAppearanceTests: XCTestCase {
    func testRemovedParticlePreferenceIsIgnoredWithoutLosingOtherSettings() throws {
        for value in [nil, "soft", "crystal", "future-effect"] as [String?] {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
            object["soundVolume"] = 0.25
            object["particleStyle"] = value
            let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(decoded.soundVolume, 0.25)
            let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
            XCTAssertNil(saved["particleStyle"])
        }
    }

    func testLookHasNoParticleChoice() {
        XCTAssertFalse(SettingsCatalog.all.contains { $0.id == "particleStyle" })
    }

    func testColorCycleIsContinuousBoundedAndSpatial() {
        let period = MoonlightChromatics.period
        for t: Float in [0, 1, 8, 16, 24.999] {
            let color = MoonlightChromatics.sample(x: 0.4, y: 0.6, time: t)
            let looped = MoonlightChromatics.sample(x: 0.4, y: 0.6, time: t + period)
            for i in 0..<3 {
                XCTAssertTrue((0...1).contains(color[i]))
                XCTAssertEqual(color[i], looped[i], accuracy: 0.00001)
            }
        }
        let near = MoonlightChromatics.sample(x: 0.4, y: 0.6, time: period - 0.0001)
        let after = MoonlightChromatics.sample(x: 0.4, y: 0.6, time: period + 0.0001)
        for i in 0..<3 { XCTAssertEqual(near[i], after[i], accuracy: 0.0001) }
        XCTAssertNotEqual(MoonlightChromatics.sample(x: 0, y: 0, time: 0),
                          MoonlightChromatics.sample(x: 1, y: 1, time: 0))
    }

    func testThemeGridStopsAtItsEdgesBeforeTheBackgroundStep() {
        var state = ThemePickerState(themeIndex: 11, backgroundIndex: 0)
        XCTAssertFalse(state.move(.down, count: 12))
        XCTAssertEqual(state.step, .theme)
        XCTAssertFalse(state.move(.right, count: 12))
        XCTAssertEqual(state.themeIndex, 11)
        XCTAssertTrue(state.move(.up, count: 12))
        XCTAssertEqual(state.themeIndex, 6)
        state.step = .background
        XCTAssertTrue(state.move(.right, count: 4))
        XCTAssertEqual(state.backgroundIndex, 1)
    }
}
