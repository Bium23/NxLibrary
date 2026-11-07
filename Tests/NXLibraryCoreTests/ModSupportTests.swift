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

    // MARK: - Requirements

    private func needs(_ name: String, optional: Bool = false) -> GameBananaRequirement {
        GameBananaRequirement(name: name, isOptional: optional)
    }

    /// A loader or a PC tool the engine cannot run hides the mod: it would install and then not work, or break the game.
    func testAModNeedingALoaderOrToolIsHidden() {
        for name in ["Trinity Mod Loader", "exlaunch", "Skyline", "ARCropolis 3.0", "TKMM", "TotK Mod Manager",
                     "TotK Recomp", "ReShade 5.8.0"] {
            XCTAssertTrue(ModRequirements.needsTool([needs("Super Mario Odyssey v1.3"), needs(name)]), name)
        }
    }

    /// A tool the author only recommends, a game version, another mod or the game itself never hides a mod.
    func testOptionalToolsVersionsAndOtherModsDoNotHide() {
        XCTAssertFalse(ModRequirements.needsTool([
            needs("TotK Recomp (Preferred, since it creates the sizetable automaticcally)"),
            needs("Trinity Mod Loader", optional: true),
            needs("ReShade (optional)"),
            needs("Game versions 1.1.0-1.4.3"),
            needs("Quick Flurry Rush"),
            needs("TOTK"),
        ]))
        XCTAssertFalse(ModRequirements.needsTool([]))
    }

    /// Notes about a modded Switch or an emulator say nothing to a Mac player and are left out of the panel.
    func testPlatformNotesAreLeftOut() {
        let shown = ModRequirements.shown([
            needs("Hacked switch"), needs("Or emulator"), needs("Computer"), needs("Have yuzu downloaded"),
            needs("Atmosphere or Ryujinx"), needs("Switch must be modded"), needs("Updated sdcard files for Nintendo Switch"),
            needs("Super Mario Odyssey v1.3"), needs("Quick Flurry Rush", optional: true),
        ])
        XCTAssertEqual(shown, [needs("Super Mario Odyssey v1.3"), needs("Quick Flurry Rush", optional: true)])
    }
}
