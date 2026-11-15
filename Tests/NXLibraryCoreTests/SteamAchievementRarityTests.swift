import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import NXLibraryCore

final class SteamAchievementRarityTests: XCTestCase {
    private var root: URL!
    private actor Calls { var count = 0; func bump() { count += 1 } }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SteamRarity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private let body = Data(#"{"achievementpercentages":{"achievements":[{"name":"A","percent":"80.0"},{"name":"B","percent":4.5}]}}"#.utf8)

    func testDecodesNumbersAndStrings() throws {
        XCTAssertEqual(try SteamAchievementRarity.decode(body), ["A": 80.0, "B": 4.5])
    }

    func testMalformedThrows() {
        XCTAssertThrowsError(try SteamAchievementRarity.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try SteamAchievementRarity.decode(Data("<html>".utf8)))
    }

    func testIconURLRefusesPaths() {
        XCTAssertEqual(SteamAchievementRarity.iconURL(appID: 7, file: "ab12.jpg")?.absoluteString,
                       "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/7/ab12.jpg")
        XCTAssertNil(SteamAchievementRarity.iconURL(appID: 7, file: "../x.jpg"))
        XCTAssertNil(SteamAchievementRarity.iconURL(appID: 7, file: "a/b.jpg"))
        XCTAssertNil(SteamAchievementRarity.iconURL(appID: 7, file: "x.exe"))
        XCTAssertNil(SteamAchievementRarity.iconURL(appID: 7, file: ".jpg"))
    }

    func testOnlyThePercentagesPathIsAllowed() {
        XCTAssertTrue(SteamMetadataService.allowed(SteamAchievementRarity.url(appID: 7)))
        XCTAssertFalse(SteamMetadataService.allowed(URL(string: "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/")!))
        XCTAssertFalse(SteamMetadataService.allowed(URL(string: "http://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=7")!))
    }

    func testPercentsAreCachedForADay() async {
        let calls = Calls(), body = body
        let service = SteamMetadataService(directory: root, transport: { _ in await calls.bump(); return body })
        let first = await service.achievementPercents(appID: 7)
        let second = await service.achievementPercents(appID: 7)
        XCTAssertEqual(first, ["A": 80, "B": 4.5])
        XCTAssertEqual(second, first)
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }

    func testOfflineKeepsTheStaleCache() async throws {
        let file = root.appendingPathComponent("7/achievement-percents.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"fetchedAt":0,"percents":{"A":12}}"#.utf8).write(to: file)
        let service = SteamMetadataService(directory: root, transport: { _ in throw URLError(.notConnectedToInternet) })
        let percents = await service.achievementPercents(appID: 7)
        XCTAssertEqual(percents, ["A": 12])
    }

    func testNothingCachedAndOfflineIsNil() async {
        let service = SteamMetadataService(directory: root, transport: { _ in throw URLError(.notConnectedToInternet) })
        let percents = await service.achievementPercents(appID: 7)
        XCTAssertNil(percents)
    }

    func testIconIsCachedAndReused() async throws {
        let calls = Calls(), png = try Self.png()
        let service = SteamMetadataService(directory: root, transport: { _ in await calls.bump(); return png })
        let first = await service.achievementIcon(appID: 7, file: "ab.jpg")
        let second = await service.achievementIcon(appID: 7, file: "ab.jpg")
        XCTAssertEqual(first?.lastPathComponent, "ab.jpg")
        XCTAssertEqual(second, first)
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }

    func testAnIconThatIsNotAnImageIsNotKept() async {
        let service = SteamMetadataService(directory: root, transport: { _ in Data("nope".utf8) })
        let icon = await service.achievementIcon(appID: 7, file: "ab.jpg")
        XCTAssertNil(icon)
    }

    private static func png() throws -> Data {
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
