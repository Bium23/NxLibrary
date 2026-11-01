import XCTest
@testable import NXLibraryCore

final class SettingsRowActionTests: XCTestCase {
    func testGamesWithTheSameNameKeepSeparateReachableActions() {
        var activated: [String] = []
        let rows = SettingsRowAction.primaryActions([
            .init(id: "show-a", title: "Same game", rowID: "hidden-a") { activated.append("a") },
            .init(id: "show-b", title: "Same game", rowID: "hidden-b") { activated.append("b") }
        ])
        XCTAssertEqual(rows.map(\.rowID), ["hidden-a", "hidden-b"])
        rows.forEach { $0.activate() }
        XCTAssertEqual(activated, ["a", "b"])
    }

    func testSecondaryButtonsDoNotAddASecondFocusStopToTheirRow() {
        var activated: [String] = []
        let rows = SettingsRowAction.primaryActions([
            .init(id: "choose", title: "Choose", rowID: "keys") { activated.append("choose") },
            .init(id: "remove", title: "Remove", rowID: "keys") { activated.append("remove") }
        ])
        XCTAssertEqual(rows.count, 1)
        rows.first?.activate()
        XCTAssertEqual(activated, ["choose"])
    }
}
