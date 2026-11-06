import XCTest
@testable import NXLibraryCore

/// Synthetic responses shaped like GameBanana's apiv11 and legacy Core API (verified 2026-11-06).
final class GameBananaAPITests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testModIndexDecodesWithMissingOptionalKeys() throws {
        let page = try decode(GameBananaModPage.self, """
        {"_aMetadata": {"_nRecordCount": 2, "_bIsComplete": false, "_nPerpage": 20},
         "_aRecords": [
          {"_idRow": 1, "_sName": "Skin", "_sProfileUrl": "https://gamebanana.com/mods/1", "_sVersion": "",
           "_tsDateAdded": 1599231491, "_tsDateModified": 1599231491, "_bIsObsolete": false,
           "_bHasContentRatings": false, "_nLikeCount": 3,
           "_aPreviewMedia": {"_aImages": [{"_sType": "screenshot", "_sBaseUrl": "https://images.gamebanana.com/img/ss/mods",
                                           "_sFile": "a.jpg", "_sFile220": "220-90_a.jpg", "_sFile530": "530-90_a.jpg"}]},
           "_aSubmitter": {"_idRow": 9, "_sName": "Author", "_sAvatarUrl": "https://images.gamebanana.com/img/av/9.png"}},
          {"_idRow": 2, "_sName": "Bare", "_sProfileUrl": "https://gamebanana.com/mods/2",
           "_tsDateAdded": 1599231491, "_bIsObsolete": true,
           "_aPreviewMedia": {}, "_aSubmitter": {"_sName": "Other"}}
         ]}
        """)
        XCTAssertFalse(page.isComplete)
        XCTAssertEqual(page.records.count, 2)
        XCTAssertEqual(page.records[0].likes, 3)
        XCTAssertEqual(page.records[0].submitter.name, "Author")
        XCTAssertEqual(page.records[0].dateAdded, Date(timeIntervalSince1970: 1599231491))
        XCTAssertEqual(page.records[1].likes, 0)
        XCTAssertNil(page.records[1].dateUpdated)
        XCTAssertEqual(page.records[1].version, "")
        XCTAssertEqual(page.records[1].images, [])
        XCTAssertTrue(page.records[1].isObsolete)
        XCTAssertFalse(page.records[1].hasContentRatings)
        XCTAssertNil(page.records[1].submitter.avatarURL)
    }

    func testProfileDecodesFilesAndRatings() throws {
        let rated = try decode(GameBananaModProfile.self, """
        {"_idRow": 455219, "_sName": "Gown", "_sProfileUrl": "https://gamebanana.com/mods/455219", "_sVersion": "1.4",
         "_sText": "<b>Hi</b>", "_bIsPrivate": false, "_bIsWithheld": false, "_bIsTrashed": false, "_bIsObsolete": false,
         "_aContentRatings": {"sa": "Skimpy Attire"}, "_nLikeCount": 5, "_nDownloadCount": 70,
         "_tsDateAdded": 1600000000, "_tsDateUpdated": 1700000000,
         "_aPreviewMedia": {"_aImages": []}, "_aSubmitter": {"_sName": "Maker"},
         "_aFiles": [{"_idRow": 1017504, "_sFile": "gown.zip", "_nFilesize": 1234, "_tsDateAdded": 1700000000,
                      "_nDownloadCount": 12, "_sDownloadUrl": "https://gamebanana.com/dl/1017504",
                      "_sMd5Checksum": "abcdef0123456789abcdef0123456789", "_sDescription": "Main", "_aAnalysisWarnings": null}]}
        """)
        XCTAssertEqual(rated.contentRatings, ["sa": "Skimpy Attire"])
        XCTAssertEqual(rated.version, "1.4")
        XCTAssertEqual(rated.downloads, 70)
        XCTAssertEqual(rated.files.count, 1)
        let file = rated.files[0]
        XCTAssertEqual(file.id, 1017504)
        XCTAssertEqual(file.size, 1234)
        XCTAssertEqual(file.downloadURL, URL(string: "https://gamebanana.com/dl/1017504"))
        XCTAssertEqual(file.md5, "abcdef0123456789abcdef0123456789")
        XCTAssertEqual(file.description, "Main")

        let clean = try decode(GameBananaModProfile.self, """
        {"_idRow": 49049, "_sName": "Plain", "_sProfileUrl": "https://gamebanana.com/mods/49049",
         "_tsDateAdded": 1599231491, "_aSubmitter": {"_sName": "Maker"}}
        """)
        XCTAssertEqual(clean.contentRatings, [:])
        XCTAssertEqual(clean.files, [])
        XCTAssertFalse(clean.isPrivate || clean.isWithheld || clean.isTrashed || clean.isObsolete)
        XCTAssertEqual(clean.text, "")
    }

    func testImageURLJoinsBaseAndFile() throws {
        let image = try decode(GameBananaImage.self, """
        {"_sBaseUrl": "https://images.gamebanana.com/img/ss/mods", "_sFile": "x.jpg", "_sFile220": "220-90_x.jpg", "_sFile530": "530-90_x.jpg"}
        """)
        XCTAssertEqual(image.url530, URL(string: "https://images.gamebanana.com/img/ss/mods/530-90_x.jpg"))
        XCTAssertEqual(image.url220, URL(string: "https://images.gamebanana.com/img/ss/mods/220-90_x.jpg"))
        let small = try decode(GameBananaImage.self, """
        {"_sBaseUrl": "https://images.gamebanana.com/img/ss/mods", "_sFile": "x.jpg"}
        """)
        XCTAssertEqual(small.url530, URL(string: "https://images.gamebanana.com/img/ss/mods/x.jpg"))
    }

    func testArchivePathsReadsFirstInnerArray() {
        let data = Data(#"[["A\/romfs\/x.bin","A\/readme.txt"]]"#.utf8)
        XCTAssertEqual(GameBananaAPI.archivePaths(in: data), ["A/romfs/x.bin", "A/readme.txt"])
        XCTAssertEqual(GameBananaAPI.archivePaths(in: Data("[]".utf8)), [])
        XCTAssertEqual(GameBananaAPI.archivePaths(in: Data("[[]]".utf8)), [])
        XCTAssertNil(GameBananaAPI.archivePaths(in: Data()))
        XCTAssertNil(GameBananaAPI.archivePaths(in: Data("<html></html>".utf8)))
    }

    func testUntrustedPageURLsAreDropped() throws {
        let profile = try JSONDecoder().decode(GameBananaModProfile.self,
                                               from: Data(#"{"_idRow": 5, "_sName": "X", "_sProfileUrl": "file:///etc/hosts"}"#.utf8))
        XCTAssertNil(profile.profileURL)
        let game = try JSONDecoder().decode(GameBananaGame.self,
                                            from: Data(#"{"_idRow": 6, "_sName": "G", "_sProfileUrl": "http://gamebanana.com/games/6"}"#.utf8))
        XCTAssertNil(game.profileURL)
    }

    func testTrustedHosts() {
        for good in ["https://gamebanana.com/dl/1", "https://files.gamebanana.com/x", "https://filecache20.gamebanana.com/x",
                     "https://images.gamebanana.com/x"] {
            XCTAssertTrue(GameBananaAPI.trusted(URL(string: good)!), good)
        }
        for bad in ["http://gamebanana.com/x", "https://gamebanana.com.evil.net/x", "https://evilgamebanana.com/x"] {
            XCTAssertFalse(GameBananaAPI.trusted(URL(string: bad)!), bad)
        }
    }

    func testURLsEncodeQuery() {
        let search = GameBananaAPI.gameSearchURL("Zelda: Tears & Kingdom").absoluteString
        XCTAssertTrue(search.hasPrefix("https://gamebanana.com/apiv11/Util/Search/Results?"))
        XCTAssertTrue(search.contains("_sModelName=Game"))
        XCTAssertTrue(search.contains("%26"), search)
        XCTAssertFalse(search.contains(" "))
        let index = GameBananaAPI.modIndexURL(gameID: 6376, page: 2, perPage: 20).absoluteString
        XCTAssertTrue(index.hasPrefix("https://gamebanana.com/apiv11/Mod/Index?"))
        XCTAssertTrue(index.contains("_aFilters%5BGeneric_Game%5D=6376"), index)
        XCTAssertTrue(index.contains("_nPage=2"))
        XCTAssertTrue(index.contains("_nPerpage=20"))
        XCTAssertTrue(index.contains("_sSort=Generic_MostDownloaded"))
        XCTAssertEqual(GameBananaAPI.profileURL(modID: 49049).absoluteString, "https://gamebanana.com/apiv11/Mod/49049/ProfilePage")
        XCTAssertEqual(GameBananaAPI.archiveListURL(fileID: 7).absoluteString,
                       "https://api.gamebanana.com/Core/Item/Data?itemtype=File&itemid=7&fields=Metadata().aArchiveFilesList()")
    }

    func testPlainTextFromHTML() {
        let html = "Line<br />two<br><b>bold</b> &amp; <a href='x'>link</a><ul><li>a</li></ul>"
        XCTAssertEqual(GameBananaAPI.plainText(fromHTML: html), "Line\ntwo\nbold & link\n• a")
        XCTAssertEqual(GameBananaAPI.plainText(fromHTML: "&quot;a&#39;b&lt;c&gt;&nbsp;d"), "\"a'b<c> d")
        XCTAssertEqual(GameBananaAPI.plainText(fromHTML: "a<br><br><br><br>b"), "a\n\nb")
    }
}
