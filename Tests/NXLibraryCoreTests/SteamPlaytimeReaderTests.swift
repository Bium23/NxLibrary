import XCTest
@testable import NXLibraryCore

final class SteamPlaytimeReaderTests: XCTestCase {
    private static let base: UInt64 = 76_561_197_960_265_728

    private static func localConfig(apps: String, before: String = "") -> String {
        """
        "UserLocalConfigStore"
        {
        \(before)
            "apptickets" { "440" "c2VjcmV0" }
            "Software" { "Valve" { "Steam" { "apps" {
        \(apps)
            } } } }
        }
        """
    }

    private static func loginUsers(_ users: [(id: UInt64, mostRecent: Bool?, timestamp: Int)]) -> String {
        let body = users.map { user in
            let recent = user.mostRecent.map { "\"MostRecent\" \"\($0 ? 1 : 0)\"" } ?? ""
            return "\"\(user.id)\" { \"AccountName\" \"someone\" \(recent) \"timestamp\" \"\(user.timestamp)\" }"
        }.joined(separator: "\n")
        return "\"users\" {\n\(body)\n}"
    }

    func testEntriesReadOnlyPlaytimeAndLastPlayed() throws {
        let text = Self.localConfig(apps: """
            "7" { "cloud" { "last_sync_state" "synchronized" } }
            "440" { "LastPlayed" "1729257000" "Playtime" "75" "Playtime2wks" "3" }
            """)
        XCTAssertEqual(try SteamPlaytimeReader.entries(localConfig: text),
                       [440: SteamPlaytimeEntry(minutes: 75, lastPlayed: Date(timeIntervalSince1970: 1_729_257_000))])
    }

    func testZeroOrMissingLastPlayedIsNone() throws {
        let text = Self.localConfig(apps: """
            "10" { "LastPlayed" "0" "Playtime" "5" }
            "20" { "Playtime" "6" }
            "30" { "LastPlayed" "1729257000" }
            """)
        XCTAssertEqual(try SteamPlaytimeReader.entries(localConfig: text),
                       [10: SteamPlaytimeEntry(minutes: 5, lastPlayed: nil),
                        20: SteamPlaytimeEntry(minutes: 6, lastPlayed: nil)])
    }

    func testMostRecentUserWins() throws {
        let text = Self.loginUsers([(Self.base + 100, false, 900), (Self.base + 200, true, 100)])
        XCTAssertEqual(try SteamPlaytimeReader.accountID(loginUsers: text), 200)
    }

    func testLatestTimestampWinsWithoutMostRecent() throws {
        let text = Self.loginUsers([(Self.base + 100, nil, 900), (Self.base + 200, nil, 100)])
        XCTAssertEqual(try SteamPlaytimeReader.accountID(loginUsers: text), 100)
    }

    func testReadFindsTheAccountsLocalConfig() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        try write(Self.loginUsers([(Self.base + 42, true, 1)]), to: "config/loginusers.vdf", in: fixture.root)
        try write(Self.localConfig(apps: "\"440\" { \"Playtime\" \"9\" }"), to: "userdata/42/config/localconfig.vdf", in: fixture.root)
        XCTAssertEqual(try SteamPlaytimeReader.localConfigURL(root: fixture.root)?.lastPathComponent, "localconfig.vdf")
        XCTAssertEqual(try SteamPlaytimeReader.read(root: fixture.root),
                       SteamPlaytimeSnapshot(accountID: 42, entries: [440: SteamPlaytimeEntry(minutes: 9, lastPlayed: nil)]))
    }

    func testNoAccountOrNoFileReturnsNil() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        XCTAssertNil(try SteamPlaytimeReader.localConfigURL(root: fixture.root))
        XCTAssertNil(try SteamPlaytimeReader.read(root: fixture.root))
        try write(Self.loginUsers([(Self.base + 42, true, 1)]), to: "config/loginusers.vdf", in: fixture.root)
        XCTAssertNil(try SteamPlaytimeReader.read(root: fixture.root))
    }

    func testLargeConfigWithManyEntriesIsRead() throws {
        let filler = "\"WebStorage\" {\n" + (0..<30_000).map { "\"k\($0)\" \"v\"" }.joined(separator: "\n") + "\n}"
        let text = Self.localConfig(apps: "\"440\" { \"Playtime\" \"1\" }", before: filler)
        XCTAssertEqual(try SteamPlaytimeReader.entries(localConfig: text)[440]?.minutes, 1)
    }

    func testMalformedConfigThrows() {
        XCTAssertThrowsError(try SteamPlaytimeReader.entries(localConfig: "\"UserLocalConfigStore\" { \"Software\" {"))
    }

    // A file Steam is rewriting must fail the read, never look like an account with no playtime.
    func testEmptyOrRootlessConfigThrows() {
        for text in ["", "  \n", "\"Other\" { }"] {
            XCTAssertThrowsError(try SteamPlaytimeReader.entries(localConfig: text), text)
        }
    }

    func testAnAccountWithNoAppsHasNoEntries() throws {
        XCTAssertEqual(try SteamPlaytimeReader.entries(localConfig: "\"UserLocalConfigStore\" { }"), [:])
    }

    func testUnreadableLoginUsersFailsInsteadOfMeaningNoAccount() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        try write("\"users\" {", to: "config/loginusers.vdf", in: fixture.root)
        XCTAssertThrowsError(try SteamPlaytimeReader.localConfigURL(root: fixture.root))
        try write("\"users\" { }", to: "config/loginusers.vdf", in: fixture.root)
        XCTAssertNil(try SteamPlaytimeReader.localConfigURL(root: fixture.root))
    }

    func testDuplicatePathKeysUseTheFirst() throws {
        let text = """
            "UserLocalConfigStore" {
                "Software" { "Valve" { "Steam" { "apps" { "440" { "Playtime" "3" } } } } }
                "software" { "Other" "x" }
            }
            """
        XCTAssertEqual(try SteamPlaytimeReader.entries(localConfig: text)[440]?.minutes, 3)
    }

    func testHashKeysElsewhereDoNotFailTheRead() throws {
        let text = Self.localConfig(apps: "\"440\" { \"Playtime\" \"2\" }", before: "\"WebStorage\" { \"#tag\" \"x\" }")
        XCTAssertEqual(try SteamPlaytimeReader.entries(localConfig: text)[440]?.minutes, 2)
    }

    func testOversizedConfigThrows() throws {
        let fixture = try SteamTestFixture.temporary(in: self)
        try write(Self.loginUsers([(Self.base + 42, true, 1)]), to: "config/loginusers.vdf", in: fixture.root)
        let filler = String(repeating: " ", count: SteamPlaytimeReader.maximumBytes + 1)
        try write(Self.localConfig(apps: "") + filler, to: "userdata/42/config/localconfig.vdf", in: fixture.root)
        XCTAssertThrowsError(try SteamPlaytimeReader.read(root: fixture.root))
    }

    private func write(_ text: String, to relative: String, in root: URL) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
