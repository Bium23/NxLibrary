import XCTest
@testable import NXLibraryCore

final class DetailsFactsTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    private func switchGame(version: String? = "1.2.0", size: Int64 = 4_000_000_000) -> PortedGame {
        PortedGame(name: "Zelda", url: URL(fileURLWithPath: "/tmp/Applications/Zelda.app"), platform: .macApp,
                   sizeBytes: size, modificationDate: Date(timeIntervalSince1970: 0), versionString: version)
    }

    private func meta(developers: [String], publishers: [String]) -> NintendoStoreMetadata {
        NintendoStoreMetadata(titleId: "0100", name: "X", description: "", developers: developers,
                              publishers: publishers, genres: [], releaseDate: nil,
                              storeURL: URL(string: "https://example.com")!, imageURL: nil,
                              headerImageURL: nil, nsuid: nil, fetchedAt: Date(timeIntervalSince1970: 0))
    }

    private func steamFacts(appID: UInt32 = 440, developers: [String] = ["Pearl Abyss"],
                            publishers: [String] = ["Pearl Abyss"]) -> SteamMetadata {
        SteamMetadata(appID: appID, language: "english", description: "", genres: [], developers: developers,
                      publishers: publishers, releaseDate: nil, screenshots: [], fetchedAt: Date(timeIntervalSince1970: 0))
    }

    private func steamGame(availability: CatalogInstallationAvailability = .available, size: Int64? = 140_000_000_000,
                           downloading: Bool = false) -> CatalogGame {
        var game = SteamCatalogGame(appID: 440, name: "Crimson Desert")
        let root = URL(fileURLWithPath: "/tmp/steam")
        game.installations = [SteamCatalogInstallation(libraryURL: root, contentURL: root, availability: availability,
                                                       reportedSizeBytes: size, buildID: "123",
                                                       isDownloading: downloading)]
        return CatalogGame(steam: game)
    }

    func testSwitchShowsEveryRowInOrder() {
        let rows = DetailsFacts.switchGame(switchGame(), metadata: meta(developers: ["Nintendo EPD"], publishers: ["Nintendo"]),
                                           folderName: "Applications", locale: en)
        XCTAssertEqual(rows.map(\.kind), [.developer, .publisher, .version, .size, .location])
        XCTAssertEqual(rows.map(\.value), ["Nintendo EPD", "Nintendo", "1.2.0", "4 GB", "Applications"])
    }

    func testSwitchHidesMissingValues() {
        let rows = DetailsFacts.switchGame(switchGame(version: nil, size: 0), metadata: nil, folderName: nil, locale: en)
        XCTAssertEqual(rows, [])
    }

    func testBlankNamesAndVersionAreHidden() {
        let rows = DetailsFacts.switchGame(switchGame(version: " "), metadata: meta(developers: ["  "], publishers: ["", "Sega"]),
                                           folderName: nil, locale: en)
        XCTAssertEqual(rows.map(\.kind), [.publisher, .size])
        XCTAssertEqual(rows.first?.value, "Sega")
    }

    func testSteamInstalledShowsSizeAndVolumeNeverVersion() {
        let rows = DetailsFacts.steamGame(steamGame(), metadata: steamFacts(), volumeName: "Macintosh HD", locale: en)
        XCTAssertEqual(rows.map(\.kind), [.developer, .publisher, .size, .location])
        XCTAssertEqual(rows.first { $0.kind == .size }?.value, "140 GB")
        XCTAssertEqual(rows.first { $0.kind == .location }?.value, "Steam · Macintosh HD")
    }

    func testSteamWithoutVolumeNameSaysSteam() {
        let rows = DetailsFacts.steamGame(steamGame(), metadata: steamFacts(), volumeName: nil, locale: en)
        XCTAssertEqual(rows.first { $0.kind == .location }?.value, "Steam")
    }

    func testSteamDownloadingShowsOnlyCredits() {
        let rows = DetailsFacts.steamGame(steamGame(availability: .unavailable, downloading: true), metadata: steamFacts(),
                                          volumeName: "Macintosh HD", locale: en)
        XCTAssertEqual(rows.map(\.kind), [.developer, .publisher])
    }

    func testSteamOverridesWinAndForeignFactsAreIgnored() {
        let rows = DetailsFacts.steamGame(steamGame(size: nil), metadata: steamFacts(appID: 999, developers: ["Other"]),
                                          overrides: [.developer: "Mine"], volumeName: nil, locale: en)
        XCTAssertEqual(rows.map(\.kind), [.developer, .location])
        XCTAssertEqual(rows.first?.value, "Mine")
    }

    func testRowsCarryTheirSymbols() {
        XCTAssertEqual(DetailsFact.Kind.allCases.map { DetailsFact(kind: $0, value: "x").symbol },
                       ["hammer", "building.2", "number", "internaldrive", "folder"])
    }
}
