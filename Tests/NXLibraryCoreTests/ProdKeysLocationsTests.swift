import XCTest
@testable import NXLibraryCore

final class ProdKeysLocationsTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone")

    func testWellKnownPlacesOnly() {
        XCTAssertEqual(ProdKeysLocations.candidates(home: home, selected: nil).map(\.path), [
            "/Users/someone/Library/Application Support/Ryujinx/system/prod.keys",
            "/Users/someone/Library/Application Support/ryujinx/system/prod.keys",
            "/Users/someone/.switch/prod.keys",
        ])
    }

    func testAChosenFolderComesFirst() {
        let found = ProdKeysLocations.candidates(home: home, selected: URL(fileURLWithPath: "/Volumes/Emu/Ryujinx"))
        XCTAssertEqual(Array(found.prefix(2).map(\.path)), ["/Volumes/Emu/Ryujinx/system/prod.keys",
                                                             "/Volumes/Emu/Ryujinx/prod.keys"])
        XCTAssertEqual(found.count, 5)
    }

    func testNoPathOutsideHomeOrTheChosenFolder() {
        for candidate in ProdKeysLocations.candidates(home: home, selected: nil) {
            XCTAssertTrue(candidate.path.hasPrefix(home.path + "/"), candidate.path)
            XCTAssertFalse(candidate.path.contains("Riujinx"), candidate.path)
        }
    }
}
