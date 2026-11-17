import XCTest
@testable import NXLibraryCore

final class MoonlightAppearanceTests: XCTestCase {
    func testParticlePreferenceDefaultsAndSurvivesSave() throws {
        XCTAssertEqual(AppSettings().particleStyle, .crystal)
        var settings = AppSettings()
        settings.particleStyle = .soft
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).particleStyle, .soft)
    }

    func testOlderAndFutureParticlePreferencesUseTheDefaultWithoutLosingOtherSettings() throws {
        for value in [nil, "future-effect"] as [String?] {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
            object["soundVolume"] = 0.25
            object["particleStyle"] = value
            let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(decoded.particleStyle, .crystal)
            XCTAssertEqual(decoded.soundVolume, 0.25)
        }
    }

    func testLookResetAndChangedIncludeTheParticlePreference() throws {
        var settings = AppSettings()
        settings.particleStyle = .soft
        settings.soundVolume = 0.25
        let row = try XCTUnwrap(SettingsCatalog.all.first { $0.id == "particleStyle" })
        XCTAssertEqual(row.group, .look)
        XCTAssertTrue(row.isChanged(settings))
        let reset = SettingsReset.reset(.look, in: settings)
        XCTAssertEqual(reset.particleStyle, .crystal)
        XCTAssertEqual(reset.soundVolume, 0.25)
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

    func testParticleChoiceIsReachableBeforeTheBackgroundStep() {
        var state = ThemePickerState(themeIndex: 11, backgroundIndex: 0)
        XCTAssertTrue(state.move(.down, count: 12))
        XCTAssertTrue(state.particlesFocused)
        XCTAssertEqual(state.step, .theme)
        XCTAssertFalse(state.move(.right, count: 12), "left/right is the setting's value, not another palette")
        XCTAssertEqual(state.themeIndex, 11)
        XCTAssertTrue(state.move(.up, count: 12))
        XCTAssertFalse(state.particlesFocused)
        XCTAssertEqual(state.themeIndex, 11)
        state.step = .background
        XCTAssertTrue(state.move(.right, count: 4))
        XCTAssertEqual(state.backgroundIndex, 1)
    }
}
