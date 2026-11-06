import XCTest
@testable import NXLibraryCore

final class BackdropArtRuleTests: XCTestCase {
    func testGameToGameKeepsTheArtOnTheFirstRenderOfTheNewSelection() {
        var rule = BackdropArtRule()
        rule.select("game:A", isGame: true)
        // The body sees game B before `onChange` records it: the art must not drop out for that render.
        XCTAssertTrue(rule.keepsOtherArt(selection: "game:B", isGame: true))
        rule.select("game:B", isGame: true)
        XCTAssertTrue(rule.keepsOtherArt(selection: "game:B", isGame: true))
    }

    func testCardToGameNeverKeepsAnotherGamesArt() {
        var rule = BackdropArtRule()
        rule.select("game:A", isGame: true)
        rule.select("card:mods", isGame: false)
        XCTAssertFalse(rule.keepsOtherArt(selection: "game:B", isGame: true))
        rule.select("game:B", isGame: true)
        XCTAssertFalse(rule.keepsOtherArt(selection: "game:B", isGame: true))
    }

    func testFirstSelectionKeepsNothing() {
        var rule = BackdropArtRule()
        XCTAssertFalse(rule.keepsOtherArt(selection: "game:A", isGame: true))
        rule.select("game:A", isGame: true)
        XCTAssertFalse(rule.keepsOtherArt(selection: "game:A", isGame: true))
    }

    func testRecordingTheSameSelectionAgainChangesNothing() {
        var rule = BackdropArtRule()
        rule.select("game:A", isGame: true)
        rule.select("game:B", isGame: true)
        rule.select("game:B", isGame: true)
        XCTAssertTrue(rule.keepsOtherArt(selection: "game:B", isGame: true))
    }

    func testACardKeepsNothing() {
        var rule = BackdropArtRule()
        rule.select("game:A", isGame: true)
        XCTAssertFalse(rule.keepsOtherArt(selection: "card:mods", isGame: false))
    }
}

final class OpacityFadeTests: XCTestCase {
    private let fade = OpacityFade(from: 0, to: 1, start: 10, duration: 0.8)

    func testEndsHoldTheirValues() {
        XCTAssertEqual(fade.value(at: 9), 0)
        XCTAssertEqual(fade.value(at: 10), 0)
        XCTAssertEqual(fade.value(at: 10.8), 1)
        XCTAssertEqual(fade.value(at: 20), 1)
    }

    /// Core Animation's ease-in-ease-out (0.42, 0, 0.58, 1), against a reference solved to 1e-12.
    func testFollowsCoreAnimationsEaseInEaseOut() {
        XCTAssertEqual(fade.value(at: 10 + 0.8 * 0.1), 0.019722, accuracy: 1e-4)
        XCTAssertEqual(fade.value(at: 10 + 0.8 * 0.25), 0.129162, accuracy: 1e-4)
        XCTAssertEqual(fade.value(at: 10.4), 0.5, accuracy: 1e-4)
        XCTAssertEqual(fade.value(at: 10 + 0.8 * 0.75), 0.870838, accuracy: 1e-4)
    }

    func testFadesDownFromWhereItStarted() {
        let out = OpacityFade(from: 0.6, to: 0, start: 0, duration: 0.5)
        XCTAssertEqual(out.value(at: 0.25), 0.3, accuracy: 1e-4)
    }

    func testZeroLengthIsAtItsEnd() {
        XCTAssertEqual(OpacityFade(from: 0, to: 1, start: 5, duration: 0).value(at: 5), 1)
    }
}

final class ArtStackTests: XCTestCase {
    func testNothingUnderAFullLayerShows() {
        // Bottom to top: the 0.3 layer is under a full one.
        XCTAssertEqual(ArtStack.hiddenCount([0.3, 1, 0.5]), 1)
    }

    func testQuickBrowsingKeepsOnlyWhatStillShows() {
        // Seven layers frozen near the end of their fade: 0.13⁴ lets less than half an 8-bit step through.
        XCTAssertEqual(ArtStack.hiddenCount(Array(repeating: 0.87, count: 7)), 3)
    }

    func testHalfFadedLayersAllStay() {
        XCTAssertEqual(ArtStack.hiddenCount([0.5, 0.5, 0.5]), 0)
    }

    func testTheBottomLayerHasNothingUnderIt() {
        XCTAssertEqual(ArtStack.hiddenCount([1]), 0)
        XCTAssertEqual(ArtStack.hiddenCount([]), 0)
    }
}
