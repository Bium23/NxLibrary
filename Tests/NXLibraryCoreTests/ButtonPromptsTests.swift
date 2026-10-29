import XCTest
@testable import NXLibraryCore

final class ButtonPromptsTests: XCTestCase {
    func testAutomaticFollowsPad() {
        XCTAssertEqual(ButtonPrompts.label(.lb, style: .automatic, connected: .nintendo), "L")
        XCTAssertEqual(ButtonPrompts.label(.view, style: .automatic, connected: .nintendo), "−")
        XCTAssertEqual(ButtonPrompts.label(.a, style: .automatic, connected: .playstation), "✕")
        XCTAssertEqual(ButtonPrompts.label(.lb, style: .automatic, connected: .none), "LB")
        XCTAssertEqual(ButtonPrompts.label(.lb, style: .automatic, connected: .other), "LB")
    }

    func testExplicitStyleOverridesPad() {
        XCTAssertEqual(ButtonPrompts.label(.lb, style: .xbox, connected: .nintendo), "LB")
        XCTAssertEqual(ButtonPrompts.label(.menu, style: .playstation, connected: .xbox), "Options")
    }

    func testAllButtonsHaveLabelsInAllStyles() {
        for style in ButtonNameStyle.allCases {
            for button in PromptButton.allCases {
                XCTAssertFalse(ButtonPrompts.label(button, style: style, connected: .none).isEmpty)
            }
        }
    }

    func testOldSettingsDecodeToAutomaticButtonNames() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.buttonNames, .automatic)
    }
}
