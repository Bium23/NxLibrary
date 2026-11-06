import XCTest
@testable import NXLibraryCore

final class ModSupportTests: XCTestCase {
    private let tid = "0100000000010000"

    private func root(_ paths: [String], _ titleID: String? = nil) -> String? {
        ModSupport.romfsRoot(in: paths, titleID: titleID ?? tid)
    }

    func testPlainRomFSRoot() {
        XCTAssertEqual(root(["romfs/Model/a.bfres", "readme.txt"]), "romfs")
    }

    func testPrefixedRootKeepsFolderName() {
        XCTAssertEqual(root(["[NPC] Gown 1.4/romfs/Model/a", "[NPC] Gown 1.4/romfs/System/b"]), "[NPC] Gown 1.4/romfs")
    }

    func testAtmosphereRootForThisGame() {
        XCTAssertEqual(root(["atmosphere/contents/\(tid)/romfs/a"]), "atmosphere/contents/\(tid)/romfs")
        XCTAssertEqual(root(["Mod/contents/\(tid.lowercased())/romfs/a"]), "Mod/contents/\(tid.lowercased())/romfs")
    }

    func testOtherTitleIDIsUnsupported() {
        XCTAssertNil(root(["atmosphere/contents/\(tid)/romfs/a"], "01000000000A0000"))
    }

    func testCodeModsAreUnsupported() {
        XCTAssertNil(root(["romfs/a", "exefs/main.npdm"]))
        XCTAssertNil(root(["romfs/a", "atmosphere/exefs_patches/x/1.ips"]))
        XCTAssertNil(root(["romfs/a", "60fps.pchtxt"]))
        XCTAssertNil(root(["romfs/a", "Mod/main.npdm"]))
    }

    func testCheatsAreIgnored() {
        XCTAssertEqual(root(["romfs/a", "cheats/ABCDEF.txt"]), "romfs")
        XCTAssertEqual(root(["romfs/a", "Cheats/romfs/x.pchtxt"]), "romfs")
    }

    func testTwoRootsAreUnsupported() {
        XCTAssertNil(root(["Red/romfs/a", "Blue/romfs/a"]))
    }

    func testNoRomFSIsUnsupported() {
        XCTAssertNil(root(["File1.bin", "README.txt"]))
        XCTAssertNil(root([]))
    }

    func testCaseOfRomFSComponent() {
        XCTAssertEqual(root(["RomFS/a"]), "RomFS")
    }

    func testVisibility() {
        XCTAssertTrue(ModSupport.isVisible(GameBananaModSummary(id: 1, name: "A")))
        XCTAssertFalse(ModSupport.isVisible(GameBananaModSummary(id: 1, name: "A", isObsolete: true)))
        XCTAssertFalse(ModSupport.isVisible(GameBananaModSummary(id: 1, name: "A", hasContentRatings: true)))
        XCTAssertTrue(ModSupport.isVisible(GameBananaModProfile(id: 1, name: "A")))
        XCTAssertFalse(ModSupport.isVisible(GameBananaModProfile(id: 1, name: "A", isObsolete: true)))
        XCTAssertFalse(ModSupport.isVisible(GameBananaModProfile(id: 1, name: "A", isPrivate: true)))
        XCTAssertFalse(ModSupport.isVisible(GameBananaModProfile(id: 1, name: "A", isWithheld: true)))
        XCTAssertFalse(ModSupport.isVisible(GameBananaModProfile(id: 1, name: "A", isTrashed: true)))
        XCTAssertFalse(ModSupport.isVisible(GameBananaModProfile(id: 1, name: "A", contentRatings: ["sa": "Skimpy Attire"])))
    }

    func testFolderName() {
        XCTAssertEqual(ModFolderName.make(from: "Zelda: HD / Pack", modID: 1, existing: []), "Zelda HD Pack")
        XCTAssertEqual(ModFolderName.make(from: ".hidden", modID: 1, existing: []), "hidden")
        XCTAssertEqual(ModFolderName.make(from: ":/", modID: 9, existing: []), "Mod 9")
        XCTAssertEqual(ModFolderName.make(from: "Pack", modID: 1, existing: ["Pack", "pack 2"]), "Pack 3")
        XCTAssertEqual(ModFolderName.make(from: String(repeating: "a", count: 200), modID: 1, existing: []).count, 80)
        XCTAssertEqual(ModFolderName.make(from: "Line\nbreak\u{2028}x", modID: 1, existing: []), "Line break x")
    }
}
