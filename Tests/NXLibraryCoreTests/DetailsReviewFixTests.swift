import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class DetailsReviewFixTests: XCTestCase {
    /// Play on a game not built yet builds it when its sources are there; the page has no Build button any more.
    func testPrimaryStepBuildsAnUnbuiltGameWithSources() {
        XCTAssertEqual(GamePrimaryStep.decide(unavailable: false, playable: true, sourcesAvailable: false), .play)
        XCTAssertEqual(GamePrimaryStep.decide(unavailable: false, playable: false, sourcesAvailable: true), .build)
        XCTAssertEqual(GamePrimaryStep.decide(unavailable: false, playable: false, sourcesAvailable: false), .refuse)
        XCTAssertEqual(GamePrimaryStep.decide(unavailable: true, playable: true, sourcesAvailable: true), .refuse)
    }

    /// A folder or volume name is read once per URL, not on every render (a sleeping disk would block each time).
    @MainActor
    func testDisplayNameCacheResolvesEachURLOnce() {
        var calls: [String] = []
        let cache = DisplayNameCache { url in calls.append(url.path); return url.path == "/a" ? "A" : nil }
        XCTAssertEqual(cache.name(for: URL(fileURLWithPath: "/a")), "A")
        XCTAssertEqual(cache.name(for: URL(fileURLWithPath: "/a")), "A")
        XCTAssertNil(cache.name(for: URL(fileURLWithPath: "/b")))
        XCTAssertNil(cache.name(for: URL(fileURLWithPath: "/b")))
        XCTAssertEqual(calls, ["/a", "/b"])
    }
}
