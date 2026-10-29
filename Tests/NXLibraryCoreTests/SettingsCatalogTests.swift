import XCTest
@testable import NXLibraryCore

final class SettingsCatalogTests: XCTestCase {
    func testDefaultSettingsHaveNoChanges() {
        XCTAssertEqual(SettingsCatalog.changed(in: AppSettings()).map(\.id), [])
    }

    func testChangedListsFlippedRows() {
        var settings = AppSettings()
        settings.interfaceSounds = false
        XCTAssertTrue(SettingsCatalog.changed(in: settings).map(\.id).contains("interfaceSounds"))
    }

    func testSearchMatchesAboutText() {
        let titles = SettingsCatalog.search("crops").map(\.title)
        XCTAssertTrue(titles.contains("Background sizing"))
    }

    func testEmptySearchReturnsNothing() {
        XCTAssertEqual(SettingsCatalog.search("").count, 0)
        XCTAssertEqual(SettingsCatalog.search("   ").count, 0)
    }

    func testEveryGroupExceptSearchChangedAboutHasRows() {
        let groups = Set(SettingsCatalog.all.map(\.group))
        for section in SettingsSection.allCases {
            if [.search, .changed, .about].contains(section) {
                XCTAssertFalse(groups.contains(section), "\(section) should have no rows")
            } else {
                XCTAssertTrue(groups.contains(section), "\(section) has no rows")
            }
        }
    }
}
