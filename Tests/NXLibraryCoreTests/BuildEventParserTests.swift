import XCTest
@testable import NXLibraryCore

final class BuildEventParserTests: XCTestCase {
    func testStageAndProgress() {
        XCTAssertEqual(
            BuildEventParser.parse(#"{"ev":"stage","k":2,"n":7,"name":"extract","step":"files"}"#),
            .stage(k: 2, n: 7, name: "extract", step: "files")
        )
        XCTAssertEqual(
            BuildEventParser.parse(#"{"ev":"progress","frac":0.5,"done":1,"total":2,"unit":"GB","eta":10}"#),
            .progress(fraction: 0.5, done: 1, total: 2, unit: "GB", eta: 10)
        )
    }

    func testNonJSONBecomesLog() {
        XCTAssertEqual(BuildEventParser.parse("hello"), .log("hello"))
    }
}
