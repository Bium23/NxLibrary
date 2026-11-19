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

    /// A percent that is not a number (`"nan"`, `"inf"`) is no rarity: clamping left NaN as it was.
    func testANonFinitePercentIsLeftOut() throws {
        let body = Data(#"{"achievementpercentages":{"achievements":[{"name":"A","percent":"nan"},{"name":"B","percent":"inf"},{"name":"C","percent":"12.5"}]}}"#.utf8)
        XCTAssertEqual(try SteamAchievementRarity.decode(body), ["C": 12.5])
    }

    /// Offline in a new language, the page keeps the text Steam gave in another one.
    func testAnotherLanguageIsKeptForAnOfflinePage() async throws {
        let body = Data(#"{"10":{"success":true,"data":{"steam_appid":10,"short_description":"Testo italiano"}}}"#.utf8)
        _ = await SteamMetadataService(directory: root, transport: { _ in body }).metadata(appID: 10, language: "italian")
        let offline = SteamMetadataService(directory: root, transport: { _ in throw URLError(.notConnectedToInternet) })
        let spanish = await offline.metadata(appID: 10, language: "spanish")
        XCTAssertNil(spanish)
        let shown = await offline.cachedInAnyLanguage(appID: 10)
        XCTAssertEqual(shown?.description, "Testo italiano")
        let none = await offline.cachedInAnyLanguage(appID: 11)
        XCTAssertNil(none)
    }

    /// A file that failed a moment ago fails at once, without waiting for a free download behind six others.
    func testARecentFailureDoesNotWaitForASlot() async throws {
        let png = try Self.png()
        let failing = Calls()
        let service = SteamMetadataService(directory: root, transport: { url in
            if url.lastPathComponent == "bad.jpg" { await failing.bump(); throw URLError(.badServerResponse) }
            try await Task.sleep(nanoseconds: 400_000_000)
            return png
        })
        let first = await service.achievementIcon(appID: 7, file: "bad.jpg")
        XCTAssertNil(first)
        let busy = (0..<6).map { index in Task { await service.achievementIcon(appID: 7, file: "busy\(index).jpg") } }
        try await Task.sleep(nanoseconds: 50_000_000)
        let started = Date()
        let again = await service.achievementIcon(appID: 7, file: "bad.jpg")
        XCTAssertNil(again)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
        let count = await failing.count
        XCTAssertEqual(count, 1)
        for task in busy { _ = await task.value }
    }

    func testMalformedThrows() {
        XCTAssertThrowsError(try SteamAchievementRarity.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try SteamAchievementRarity.decode(Data("<html>".utf8)))
    }

    func testIconURLRefusesPaths() {
        XCTAssertEqual(SteamAchievementRarity.iconURL(appID: 7, file: "ab12.jpg")?.absoluteString,
                       "https://shared.akamai.steamstatic.com/community_assets/images/apps/7/ab12.jpg")
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

    /// A screen of icons asks for more than the six downloads at once: the rest wait their turn instead of
    /// failing, and no more than six run together.
    func testIconsBeyondTheConcurrencyLimitWaitTheirTurn() async throws {
        let gauge = Gauge(), png = try Self.png()
        let service = SteamMetadataService(directory: root, transport: { _ in
            await gauge.enter()
            try await Task.sleep(nanoseconds: 30_000_000)
            await gauge.leave()
            return png
        })
        let icons = await withTaskGroup(of: URL?.self) { group in
            for index in 0..<15 { group.addTask { await service.achievementIcon(appID: 7, file: "icon\(index).jpg") } }
            return await group.reduce(into: [URL?]()) { $0.append($1) }
        }
        XCTAssertEqual(icons.compactMap { $0 }.count, 15)
        let peak = await gauge.peak
        XCTAssertLessThanOrEqual(peak, 6)
    }

    /// A request still waiting for its turn ends when its row goes away.
    func testAWaitingIconRequestCanBeCancelled() async throws {
        let png = try Self.png()
        let service = SteamMetadataService(directory: root, transport: { _ in
            try await Task.sleep(nanoseconds: 300_000_000)
            return png
        })
        let busy = (0..<6).map { index in Task { await service.achievementIcon(appID: 7, file: "busy\(index).jpg") } }
        try await Task.sleep(nanoseconds: 50_000_000)
        let waiting = Task { await service.achievementIcon(appID: 7, file: "late.jpg") }
        try await Task.sleep(nanoseconds: 50_000_000)
        let started = Date()
        waiting.cancel()
        let late = await waiting.value
        XCTAssertNil(late)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
        for task in busy { _ = await task.value }
    }

    private actor Gauge {
        var current = 0, peak = 0
        func enter() { current += 1; peak = max(peak, current) }
        func leave() { current -= 1 }
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
