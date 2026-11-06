import XCTest
@testable import NXLibraryCore

final class CheatDatabaseTests: XCTestCase {
    private let json = #"""
    {
      "AAAAAAAAAAAAAAAA": { "[Old]": "[Old]\n04000000 00000000 00000001\n\n" },
      "B424BE150A8E7D78": {
        "{Master}": "{Master}\n580F0000 01234567\n\n",
        "[Zeta Health]": "[Zeta Health]\n04000000 00000000 00000063\n\n",
        "[01# Moon Jump]": "[01# Moon Jump]\n04000000 00000010 00000001",
        "loose": "04000000 00000020 00000001\n",
        "[Number]": 7
      },
      "attribution": { "x.txt": "credits" }
    }
    """#

    /// The game's cheats for exactly this build, in the database's own order (masters where it put them), each
    /// block whole; a value that is not a block (no [Name] or {Name} header) or not text is left out.
    func testCheatTextForTheBuildInTheDatabasesOrder() throws {
        let text = try XCTUnwrap(CheatDatabase.cheatText(json: Data(json.utf8), buildID: "b424be150a8e7d78"))
        XCTAssertEqual(text, "{Master}\n580F0000 01234567\n\n[Zeta Health]\n04000000 00000000 00000063\n\n"
                           + "[01# Moon Jump]\n04000000 00000010 00000001\n")
        let file = CheatFile.parse(text)
        XCTAssertEqual(file.summary.cheats, 2)
        XCTAssertEqual(file.summary.alwaysOn, 1)
    }

    func testNoTextForAnotherBuildOrABrokenFile() {
        XCTAssertNil(CheatDatabase.cheatText(json: Data(json.utf8), buildID: "CCCCCCCCCCCCCCCC"))
        XCTAssertNil(CheatDatabase.cheatText(json: Data("not json".utf8), buildID: "B424BE150A8E7D78"))
        XCTAssertNil(CheatDatabase.cheatText(json: Data("[1, 2]".utf8), buildID: "B424BE150A8E7D78"))
        XCTAssertNil(CheatDatabase.cheatText(json: Data(#"{"B424BE150A8E7D78": {"loose": "1"}}"#.utf8),
                                            buildID: "B424BE150A8E7D78"), "no block at all")
    }

    /// Only a title ID goes into the address, on the database's one https host.
    func testAddressIsOnlyForATitleID() {
        XCTAssertEqual(CheatDatabase.url(titleID: "0100000000010000")?.absoluteString,
                       "https://raw.githubusercontent.com/HamletDuFromage/switch-cheats-db/master/cheats/0100000000010000.json")
        XCTAssertEqual(CheatDatabase.url(titleID: "0100f2c0115b6000")?.lastPathComponent, "0100F2C0115B6000.json")
        for invalid in ["", "../etc/passwd", "0100000000010000/../x", "010000000001000", "zz00000000010000"] {
            XCTAssertNil(CheatDatabase.url(titleID: invalid), invalid)
        }
    }
}
