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

    /// Both are followed by a `say` with the same news (nxnative docs/frontends.md): the raw JSON stays out of the log.
    func testGameAndStaleShaderEventsAreNotLogged() {
        XCTAssertNil(BuildEventParser.parse(#"{"ev":"game","title_id":"0100000000010000","name":"Game","version":"1.1.0","bundle_id":"org.nxnative.0100000000010000","out":"/tmp/Game.app","icon":null}"#))
        XCTAssertNil(BuildEventParser.parse(#"{"ev":"shaders_stale","reason":"chain","old":["b-1"],"new":"b-2","count":3}"#))
    }
}
