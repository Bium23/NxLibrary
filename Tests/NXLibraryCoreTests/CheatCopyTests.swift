import XCTest
@testable import NXLibraryCore

final class CheatCopyTests: XCTestCase {
    private let build = "B424BE150A8E7D78"
    private let file = CheatFile.parse("[A]\n04000000 00004000 00000001\n{M}\n04000000 00004004 00000001\n")

    func testHeader() {
        XCTAssertEqual(CheatCopy.header(version: "1.2.0", buildID: build), "Version 1.2.0 · build B424BE15…")
        XCTAssertEqual(CheatCopy.header(version: nil, buildID: build), "Build B424BE15…")
        XCTAssertEqual(CheatCopy.header(version: "1.2.0", buildID: nil), "Version 1.2.0")
        XCTAssertEqual(CheatCopy.header(version: nil, buildID: nil), "")
    }

    func testRefusals() {
        XCTAssertEqual(CheatCopy.refusal(.otherBuild("0123456789ABCDEF"), gameName: "Zelda", buildID: build),
                       "These cheats are for another version of Zelda (build 0123456789ABCDEF). Yours is build B424BE150A8E7D78.")
        XCTAssertEqual(CheatCopy.refusal(.otherTitle("01007EF00011E000"), gameName: "Zelda", buildID: build),
                       "These cheats are for another game (title ID 01007EF00011E000).")
        XCTAssertEqual(CheatCopy.refusal(.refused("The file holds no cheat."), gameName: "Zelda", buildID: build),
                       "The file holds no cheat.")
        XCTAssertNil(CheatCopy.refusal(.install(file), gameName: "Zelda", buildID: build))
        XCTAssertNil(CheatCopy.refusal(.confirmUnnamed(file), gameName: "Zelda", buildID: build))
    }

    func testConfirmShowsSummaryAndWarnsForUnnamed() {
        let named = CheatCopy.confirm(file: file, unnamed: false, replacing: false, version: "1.2.0", buildID: build)
        XCTAssertEqual(named.title, "Install cheats?")
        XCTAssertEqual(named.message, "1 cheat · 1 always on\n\nEvery cheat starts off.")
        XCTAssertEqual(named.confirm, "Install")
        let unnamed = CheatCopy.confirm(file: file, unnamed: true, replacing: false, version: "1.2.0", buildID: build)
        XCTAssertEqual(unnamed.title, "Install these cheats?")
        XCTAssertEqual(unnamed.message, "Install as cheats for version 1.2.0 (build B424BE150A8E7D78)? Cheats made for another version can crash the game.\n\n1 cheat · 1 always on\n\nEvery cheat starts off.")
        let noVersion = CheatCopy.confirm(file: file, unnamed: true, replacing: false, version: nil, buildID: build)
        XCTAssertTrue(noVersion.message.hasPrefix("Install as cheats for build B424BE150A8E7D78? "))
        let replace = CheatCopy.confirm(file: file, unnamed: false, replacing: true, version: "1.2.0", buildID: build)
        XCTAssertEqual(replace.title, "Replace cheats?")
        XCTAssertEqual(replace.message, "1 cheat · 1 always on\n\nCheats that were on and keep their name stay on; the rest start off.")
        XCTAssertEqual(replace.confirm, "Replace")
    }

    func testPairShowsItsBaseName() {
        let f = CheatFile.parse("[Moon Jump - on]\n04000000 00004000 00000001\n[Moon Jump - off]\n04000000 00004000 00000000\n[Max HP]\n04000000 00004004 00000001\n")
        XCTAssertEqual(f.switches.map(CheatCopy.title(of:)), ["Moon Jump", "Max HP"])
    }

    func testPickPrefersThisBuildThenOneUnnamed() {
        XCTAssertEqual(CheatInstall.pick([.otherBuild("X"), .install(file), .confirmUnnamed(file)]), .file(1, unnamed: false))
        XCTAssertEqual(CheatInstall.pick([.refused("r"), .confirmUnnamed(file)]), .file(1, unnamed: true))
        XCTAssertEqual(CheatInstall.pick([.confirmUnnamed(file), .confirmUnnamed(file)]), .several)
        XCTAssertEqual(CheatInstall.pick([.refused("r"), .otherTitle("T"), .otherBuild("X")]), .nothing(.otherBuild("X")))
        XCTAssertEqual(CheatInstall.pick([.refused("r"), .otherTitle("T")]), .nothing(.otherTitle("T")))
        XCTAssertEqual(CheatInstall.pick([]), .nothing(nil))
    }

    /// Under the header: what a cheat is, against a mod (players look for cheats among GameBanana's mods).
    func testAboutTellsCheatsFromMods() {
        XCTAssertEqual(CheatCopy.about,
                       "Cheats change values while you play, for this version only. New items, looks or gameplay are in Mods.")
    }
}
