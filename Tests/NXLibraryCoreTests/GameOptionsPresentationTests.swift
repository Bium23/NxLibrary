import XCTest
@testable import NXLibraryCore

final class GameOptionsPresentationTests: XCTestCase {
    func testRenderScaleVisibilityFollowsSupport() {
        let p = GameOptionsPresentation(supportsRenderScale: true,
                                        isPlayable: true,
                                        sourcesDetached: false)
        XCTAssertTrue(p.showRenderScale)
        XCTAssertFalse(p.sourcesDetached)
    }

    func testUnsupportedRenderScaleShowsInfo() {
        let p = GameOptionsPresentation(supportsRenderScale: false,
                                        isPlayable: false,
                                        sourcesDetached: true)
        XCTAssertFalse(p.showRenderScale)
        XCTAssertFalse(p.canPlay)
        XCTAssertTrue(p.sourcesDetached)
        XCTAssertTrue(p.resolutionNote.contains("window/display"))
    }
}
