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

    func testAutomaticWithoutControllerKeepsTextLabels() {
        XCTAssertNil(ButtonPrompts.symbol(.a, style: .automatic, connected: .none))
    }

    func testAutomaticPrefersWhatTheControllerReports() {
        let symbol = ButtonPrompts.symbol(.a, style: .automatic, connected: .nintendo,
                                          reported: [.a: "a.circle"])
        XCTAssertEqual(symbol, "a.circle")
    }

    func testAutomaticIgnoresGenericReportedGlyphs() {
        let viewSym = ButtonPrompts.symbol(.view, style: .automatic, connected: .playstation,
                                           reported: [.view: "circle"])
        XCTAssertEqual(viewSym, "square.and.arrow.up.circle")

        let menuSym = ButtonPrompts.symbol(.menu, style: .automatic, connected: .playstation,
                                           reported: [.menu: "circle.fill"])
        XCTAssertEqual(menuSym, "line.3.horizontal.circle")
    }

    func testGenericShapeDetection() {
        XCTAssertTrue(ButtonPrompts.isGenericShape("circle"))
        XCTAssertTrue(ButtonPrompts.isGenericShape("circle.fill"))
        XCTAssertTrue(ButtonPrompts.isGenericShape("capsule"))
        XCTAssertTrue(ButtonPrompts.isGenericShape("square"))
        XCTAssertFalse(ButtonPrompts.isGenericShape("xmark.circle"))
        XCTAssertFalse(ButtonPrompts.isGenericShape("square.and.arrow.up.circle"))
        XCTAssertFalse(ButtonPrompts.isGenericShape("line.3.horizontal.circle"))
    }

    func testAutomaticPlayStationRejectsDecoratedShapePlaceholders() {
        for name in ["capsule.portrait", "capsule.portrait.fill", "oval.portrait.fill",
                     "rectangle.portrait.fill", "rectangle.roundedtop.fill", "button.horizontal.fill"] {
            XCTAssertTrue(ButtonPrompts.isGenericShape(name), name)
            XCTAssertEqual(ButtonPrompts.symbol(.view, style: .automatic, connected: .playstation,
                                               reported: [.view: name]), "square.and.arrow.up.circle", name)
            XCTAssertEqual(ButtonPrompts.symbol(.menu, style: .automatic, connected: .playstation,
                                               reported: [.menu: name]), "line.3.horizontal.circle", name)
        }
        XCTAssertEqual(ButtonPrompts.symbol(.view, style: .automatic, connected: .xbox,
                                           reported: [.view: "capsule.portrait"]), "rectangle.on.rectangle.circle")
        XCTAssertEqual(ButtonPrompts.symbol(.menu, style: .automatic, connected: .nintendo,
                                           reported: [.menu: "button.horizontal.fill"]), "plus.circle")
    }

    func testGeometricFaceButtonsAndMeaningfulReportedGlyphsArePreserved() {
        for name in ["circle.circle", "circle.circle.fill", "square.circle", "square.circle.fill",
                     "rectangle.on.rectangle.circle", "square.and.arrow.up.circle.fill",
                     "l1.rectangle.roundedbottom", "triangle.circle.fill"] {
            XCTAssertFalse(ButtonPrompts.isGenericShape(name), name)
            XCTAssertEqual(ButtonPrompts.symbol(.a, style: .automatic, connected: .playstation,
                                               reported: [.a: name]), name)
        }
    }

    func testAutomaticFallsBackToTheBrandTable() {
        XCTAssertEqual(ButtonPrompts.symbol(.a, style: .automatic, connected: .playstation), "xmark.circle")
        XCTAssertEqual(ButtonPrompts.symbol(.lt, style: .automatic, connected: .nintendo), "zl.rectangle.roundedtop")
        XCTAssertEqual(ButtonPrompts.symbol(.menu, style: .automatic, connected: .other), "line.3.horizontal.circle")
    }

    func testChosenStyleIgnoresTheReportedGlyph() {
        let symbol = ButtonPrompts.symbol(.b, style: .playstation, connected: .xbox,
                                          reported: [.b: "b.circle"])
        XCTAssertEqual(symbol, "circle.circle")
    }

    func testEveryButtonHasASymbolInEveryStyle() {
        for style in ButtonNameStyle.allCases where style != .automatic {
            for button in PromptButton.allCases {
                XCTAssertNotNil(ButtonPrompts.symbol(button, style: style, connected: .none))
            }
        }
    }

    func testNoControllerShowsKeyboardKeys() {
        XCTAssertTrue(ButtonPrompts.usesKeyboard(style: .automatic, connected: .none))
        XCTAssertFalse(ButtonPrompts.usesKeyboard(style: .automatic, connected: .other))
        XCTAssertFalse(ButtonPrompts.usesKeyboard(style: .xbox, connected: .none))
        XCTAssertEqual(ButtonPrompts.keyboardKey(.a), .symbol("return"))
        XCTAssertEqual(ButtonPrompts.keyboardKey(.b), .text("esc"))
    }

    func testGenericControllerUsesXboxGlyphs() {
        XCTAssertEqual(ButtonPrompts.symbol(.lb, style: .automatic, connected: .other), "lb.rectangle.roundedbottom")
    }
}
