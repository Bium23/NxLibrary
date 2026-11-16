import XCTest
@testable import NXLibraryCore

/// Made-up schemas and stats in Steam's layout; no Valve content.
final class SteamAchievementReaderTests: XCTestCase {
    private typealias E = [(String, Any)]
    private let app: UInt32 = 4242
    private let account: UInt32 = 1234

    private func bit(_ api: String, names: [String: String], descs: [String: String] = [:], hidden: Bool = false,
                     icon: String? = "c.jpg", gray: String? = "g.jpg") -> E {
        var display: E = [("name", names.map { ($0.key, $0.value as Any) }),
                          ("desc", descs.map { ($0.key, $0.value as Any) }),
                          ("hidden", hidden ? "1" : "0")]
        if let icon { display.append(("icon", icon)) }
        if let gray { display.append(("icon_gray", gray)) }
        return [("name", api), ("display", display)]
    }

    private func schema(_ stats: [(String, E)]) -> [KeyValuesEntry] {
        let tree: E = [("\(app)", [("stats", stats.map { ($0.0, $0.1 as Any) } as E), ("gamename", "Game"), ("version", Int32(3))] as E)]
        return try! SteamBinaryKeyValues.parse(BinaryKV.data(tree))
    }

    private func stats(_ times: [(stat: String, bit: String, time: Int32)], extra: Bool = false) -> [KeyValuesEntry] {
        var byStat: [String: E] = [:]
        for t in times { byStat[t.stat, default: []].append((t.bit, t.time)) }
        var cache: E = [("crc", Int32(99))]
        if extra { cache.append(("PendingChanges", Int32(0))) }
        for (stat, list) in byStat.sorted(by: { $0.key < $1.key }) {
            cache.append((stat, [("data", Int32(7)), ("AchievementTimes", list)] as E))
        }
        return try! SteamBinaryKeyValues.parse(BinaryKV.data([("cache", cache)]))
    }

    private func read(_ schema: [KeyValuesEntry], _ stats: [KeyValuesEntry], language: String = "italian") throws -> [SteamAchievement] {
        try SteamAchievementReader.achievements(schema: schema, stats: stats, appID: app, language: language)
    }

    func testReadsNamesInTheLanguageWithEnglishFallback() throws {
        let rows = try read(schema([("1", [("type", "4"), ("bits", [
            ("0", bit("A", names: ["english": "First", "italian": "Primo"], descs: ["english": "Do it", "italian": "Fallo"])),
            ("1", bit("B", names: ["english": "Second"], descs: ["english": "Again"])),
            ("2", bit("C", names: [:])),
        ] as E)])]), stats([]))
        XCTAssertEqual(rows.map(\.name), ["Primo", "Second", "C"])
        XCTAssertEqual(rows.map(\.description), ["Fallo", "Again", ""])
    }

    func testUnlockTimesComeFromTheStatsFile() throws {
        let rows = try read(schema([("1", [("bits", [("0", bit("A", names: [:])), ("1", bit("B", names: [:]))] as E)])]),
                            stats([("1", "0", 1_700_000_000)]))
        XCTAssertEqual(rows[0].unlockedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(rows[1].unlockedAt)
    }

    func testStatsWithoutBitsAreSkipped() throws {
        let rows = try read(schema([("1", [("type", "1"), ("name", "kills")]), ("2", [("bits", [("0", bit("A", names: [:]))] as E)])]),
                            stats([]))
        XCTAssertEqual(rows.map(\.apiName), ["A"])
    }

    func testHiddenAndIcons() throws {
        let rows = try read(schema([("1", [("bits", [("0", bit("A", names: [:], hidden: true, icon: "x.jpg", gray: "y.jpg")),
                                                     ("1", bit("B", names: [:], icon: nil, gray: nil))] as E)])]), stats([]))
        XCTAssertEqual(rows[0].hidden, true)
        XCTAssertEqual(rows[0].icon, "x.jpg")
        XCTAssertEqual(rows[0].grayIcon, "y.jpg")
        XCTAssertEqual(rows[1].hidden, false)
        XCTAssertNil(rows[1].icon)
    }

    func testOrderIsStatThenBitNumerically() throws {
        let rows = try read(schema([
            ("10", [("bits", [("0", bit("S10B0", names: [:]))] as E)]),
            ("2", [("bits", [("10", bit("S2B10", names: [:])), ("9", bit("S2B9", names: [:]))] as E)]),
        ]), stats([]))
        XCTAssertEqual(rows.map(\.apiName), ["S2B9", "S2B10", "S10B0"])
    }

    func testOtherStatsKeysAreIgnored() throws {
        let rows = try read(schema([("1", [("bits", [("0", bit("A", names: [:]))] as E)])]), stats([("1", "0", 5)], extra: true))
        XCTAssertEqual(rows.count, 1)
        XCTAssertNotNil(rows[0].unlockedAt)
    }

    func testAZeroTimeIsLocked() throws {
        let rows = try read(schema([("1", [("bits", [("0", bit("A", names: [:]))] as E)])]), stats([("1", "0", 0)]))
        XCTAssertNil(rows[0].unlockedAt)
    }

    func testLookupSkipsWrongTypesAndKeepsTheFirstMatchingTypedValue() throws {
        let fields: E = [("name", [] as E), ("NAME", "FIRST"), ("name", "SECOND"),
                         ("display", "wrong type"), ("DISPLAY", [
                            ("name", [("italian", [] as E), ("ITALIAN", "Primo"), ("italian", "Secondo")] as E)
                         ] as E)]
        let game: E = [("stats", "wrong type"), ("STATS", [("1", [
            ("bits", "wrong type"), ("BITS", [("0", fields)] as E)
        ] as E)] as E)]
        let schema = try SteamBinaryKeyValues.parse(BinaryKV.data([("\(app)", "wrong type"), ("\(app)", game)]))
        let rows = try read(schema, stats([("1", "0", 5)]))
        XCTAssertEqual(rows.map(\.apiName), ["FIRST"])
        XCTAssertEqual(rows.map(\.name), ["Primo"])
        XCTAssertEqual(rows.first?.unlockedAt, Date(timeIntervalSince1970: 5))
    }

    func testEmptyFirstLocalizedStringFallsBackToEnglishRatherThanADuplicate() throws {
        let fields: E = [("name", "A"), ("display", [("name", [
            ("italian", ""), ("ITALIAN", "Ignored duplicate"), ("english", "English fallback")
        ] as E)] as E)]
        let rows = try read(schema([("1", [("bits", [("0", fields)] as E)])]), stats([]))
        XCTAssertEqual(rows.map(\.name), ["English fallback"])
    }

    // MARK: - Files

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SteamAchievements-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("appcache/stats"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
        let id = 76_561_197_960_265_728 + UInt64(account)
        try "\"users\" { \"\(id)\" { \"AccountName\" \"someone\" \"MostRecent\" \"1\" \"timestamp\" \"1\" } }"
            .write(to: root.appendingPathComponent("config/loginusers.vdf"), atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func writeSchema(_ data: Data) throws {
        try data.write(to: SteamAchievementReader.schemaURL(root: root, appID: app))
    }

    private func writeStats(_ data: Data) throws {
        try data.write(to: SteamAchievementReader.statsURL(root: root, account: account, appID: app))
    }

    private var schemaData: Data {
        BinaryKV.data([("\(app)", [("stats", [("1", [("bits", [("0", bit("A", names: ["english": "First"]))] as E)] as E)] as E)] as E)])
    }

    func testFileNamesFollowSteam() {
        XCTAssertEqual(SteamAchievementReader.schemaURL(root: root, appID: app).lastPathComponent, "UserGameStatsSchema_4242.bin")
        XCTAssertEqual(SteamAchievementReader.statsURL(root: root, account: account, appID: app).lastPathComponent, "UserGameStats_1234_4242.bin")
    }

    func testNoStatsFileForTheAccountIsNil() throws {
        try writeSchema(schemaData)
        XCTAssertNil(try SteamAchievementReader.read(root: root, appID: app, language: "english"))
    }

    func testNoUnlockIsZeroNotNil() throws {
        try writeSchema(schemaData)
        try writeStats(BinaryKV.data([("cache", [("crc", Int32(1))] as E)]))
        let rows = try XCTUnwrap(SteamAchievementReader.read(root: root, appID: app, language: "english"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].unlockedAt)
    }

    func testNoSchemaIsNil() throws {
        try writeStats(BinaryKV.data([("cache", [("crc", Int32(1))] as E)]))
        XCTAssertNil(try SteamAchievementReader.read(root: root, appID: app, language: "english"))
    }

    func testCorruptSchemaThrows() throws {
        try writeSchema(schemaData.dropLast(4))
        try writeStats(BinaryKV.data([("cache", [("crc", Int32(1))] as E)]))
        XCTAssertThrowsError(try SteamAchievementReader.read(root: root, appID: app, language: "english"))
    }

    func testSchemaSymlinkIsRejected() throws {
        let target = root.appendingPathComponent("schema.bin")
        try schemaData.write(to: target)
        try FileManager.default.createSymbolicLink(at: SteamAchievementReader.schemaURL(root: root, appID: app),
                                                  withDestinationURL: target)
        try writeStats(BinaryKV.data([("cache", [] as E)]))
        XCTAssertThrowsError(try SteamAchievementReader.read(root: root, appID: app, language: "english"))
    }

    func testStatsSymlinkIsRejected() throws {
        try writeSchema(schemaData)
        let target = root.appendingPathComponent("stats.bin")
        try BinaryKV.data([("cache", [] as E)]).write(to: target)
        try FileManager.default.createSymbolicLink(at: SteamAchievementReader.statsURL(root: root, account: account, appID: app),
                                                  withDestinationURL: target)
        XCTAssertThrowsError(try SteamAchievementReader.read(root: root, appID: app, language: "english"))
    }

    func testASchemaForAnotherGameReadsNothing() throws {
        try writeSchema(BinaryKV.data([("999", [("stats", [] as E)] as E)]))
        try writeStats(BinaryKV.data([("cache", [("crc", Int32(1))] as E)]))
        XCTAssertEqual(try SteamAchievementReader.read(root: root, appID: app, language: "english"), [])
    }
}
