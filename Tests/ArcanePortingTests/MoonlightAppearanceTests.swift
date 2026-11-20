import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

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

    func testLocalColorsStayNearTheirOwnHueOverTheWholeCycle() {
        let positions: [(Float, Float)] = [(0.18,0.77),(0.84,0.43),(0.5,0.3)]
        for (x,y) in positions {
            let initial = MoonlightChromatics.sample(x: x, y: y, time: 0)
            for t in stride(from: Float(0), to: 180, by: 5) {
                let value = MoonlightChromatics.sample(x: x, y: y, time: t)
                for k in 0..<3 { XCTAssertLessThan(abs(value[k]-initial[k]), 0.025) }
            }
        }
        let pink = MoonlightChromatics.sample(x: 0.18, y: 0.77, time: 0)
        let cyan = MoonlightChromatics.sample(x: 0.84, y: 0.43, time: 0)
        XCTAssertGreaterThan(pink.x, cyan.x)
        XCTAssertGreaterThan(cyan.y, pink.y)
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
