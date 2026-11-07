import XCTest
@testable import NXLibraryCore

/// A row with two buttons (Update and Back to tested): Left and Right move between them, A presses the one in focus.
final class SettingsRowButtonsTests: XCTestCase {
    func testRightMovesToTheSecondButtonAndStopsThere() {
        XCTAssertEqual(SettingsRowAction.sideways(from: 0, by: 1, buttons: 2), .button(1))
        XCTAssertEqual(SettingsRowAction.sideways(from: 1, by: 1, buttons: 2), .stay)
    }

    func testLeftReturnsToTheFirstButtonThenLeavesTheRows() {
        XCTAssertEqual(SettingsRowAction.sideways(from: 1, by: -1, buttons: 2), .button(0))
        XCTAssertEqual(SettingsRowAction.sideways(from: 0, by: -1, buttons: 2), .leaveRows)
    }

    func testOneButtonRowKeepsLeftToLeave() {
        XCTAssertEqual(SettingsRowAction.sideways(from: 0, by: -1, buttons: 1), .leaveRows)
        XCTAssertEqual(SettingsRowAction.sideways(from: 0, by: 1, buttons: 1), .stay)
    }

    func testConfirmPressesTheButtonInFocus() {
        var pressed: [String] = []
        let row = SettingsRowAction(id: "newest", title: "Newest engine",
                                    secondary: (title: "Back to tested", activate: { pressed.append("back") })) {
            pressed.append("update")
        }
        XCTAssertEqual(row.buttonCount, 2)
        row.press(button: 1)
        row.press(button: 0)
        row.press(button: 5)
        XCTAssertEqual(pressed, ["back", "update", "update"])
    }
}
