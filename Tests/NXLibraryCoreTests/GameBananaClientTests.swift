import XCTest
@testable import NXLibraryCore

/// Serves canned bodies by URL (exact string, else by substring), records requests, and can fail or suspend.
final class FakeGameBananaHTTP: ArtworkHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [(String, Data, Int)] = []
    private var failures: [String: URLError] = [:]
    private(set) var requestLog: [URLRequest] = []
    private var inFlight = 0
    private(set) var highWater = 0
    var delayNanoseconds: UInt64 = 0

    func serve(_ match: String, _ body: String, status: Int = 200) { locked { routes.append((match, Data(body.utf8), status)) } }
    func fail(_ match: String, _ error: URLError) { locked { failures[match] = error } }
    func clearFailures() { locked { failures = [:] } }
    var requests: [URLRequest] { locked { requestLog } }
    func count(_ match: String) -> Int { requests.filter { $0.url!.absoluteString.contains(match) }.count }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private func begin(_ request: URLRequest) -> Result<(Data, Int), URLError>? {
        locked {
            requestLog.append(request)
            inFlight += 1
            highWater = max(highWater, inFlight)
            let url = request.url!.absoluteString
            if let failure = failures.first(where: { url.contains($0.key) }) { return .failure(failure.value) }
            if let exact = routes.last(where: { $0.0 == url }) ?? routes.last(where: { url.contains($0.0) }) {
                return .success((exact.1, exact.2))
            }
            return nil
        }
    }

    private func end() { locked { inFlight -= 1 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let outcome = begin(request)
        if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
        end()
        let url = request.url!
        switch outcome {
        case .failure(let error): throw error
        case .success(let (data, status)):
            return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case nil:
            return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
    }
}

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

final class GameBananaClientTests: XCTestCase {
    private var dir: URL!
    private let http = FakeGameBananaHTTP()
    private let clock = TestClock()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("GBClient-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func client() -> GameBananaClient {
        let clock = clock
        return GameBananaClient(http: http, cacheFolder: dir.appendingPathComponent("cache"),
                                userAgent: GameBananaClient.userAgent(version: "0.1.4"), now: { clock.now })
    }

    private let profile = #"{"_idRow": 5, "_sName": "Mod", "_aSubmitter": {"_sName": "A"}}"#

    func testSendsUserAgentAndTimeout() async throws {
        http.serve("Mod/5/ProfilePage", profile)
        _ = try await client().profile(modID: 5)
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "NXLibrary/0.1.4 (macOS; personal app)")
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    func testProfileIsCachedForSixHours() async throws {
        http.serve("Mod/5/ProfilePage", profile)
        let first = try await client().profile(modID: 5)
        XCTAssertEqual(first.name, "Mod")
        clock.now += 6 * 3600 - 1
        _ = try await client().profile(modID: 5)
        XCTAssertEqual(http.count("ProfilePage"), 1)
        clock.now += 2
        _ = try await client().profile(modID: 5)
        XCTAssertEqual(http.count("ProfilePage"), 2)
    }

    func testListingIsCachedForever() async throws {
        http.serve("itemid=7&", #"[["romfs/a"]]"#)
        let paths = try await client().archivePaths(fileID: 7)
        XCTAssertEqual(paths, ["romfs/a"])
        clock.now += 365 * 86400
        _ = try await client().archivePaths(fileID: 7)
        XCTAssertEqual(http.count("Core/Item/Data"), 1)
    }

    func testEmptyListingIsAskedAgain() async throws {
        http.serve("itemid=8&", "[]")
        let first = try await client().archivePaths(fileID: 8)
        XCTAssertEqual(first, [])
        http.serve("itemid=8&", #"[["romfs/a"]]"#)
        let second = try await client().archivePaths(fileID: 8)
        XCTAssertEqual(second, ["romfs/a"])
    }

    func testOfflineFallsBackToExpiredCache() async throws {
        http.serve("Mod/5/ProfilePage", profile)
        _ = try await client().profile(modID: 5)
        clock.now += 86400
        http.fail("ProfilePage", URLError(.notConnectedToInternet))
        let cached = try await client().profile(modID: 5)
        XCTAssertEqual(cached.name, "Mod")
        do {
            _ = try await client().profile(modID: 6)
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? GameBananaError, .offline)
        }
    }

    func testServerErrorIsUnavailable() async throws {
        http.serve("Mod/5/ProfilePage", "busy", status: 503)
        http.serve("Mod/6/ProfilePage", "<html>maintenance</html>")
        for id in [5, 6] {
            do {
                _ = try await client().profile(modID: id)
                XCTFail("expected unavailable")
            } catch {
                XCTAssertEqual(error as? GameBananaError, .unavailable)
            }
        }
        let profiles = dir.appendingPathComponent("cache/profile")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: profiles.path)) ?? [], [])
    }

    func testConcurrencyIsLimited() async throws {
        http.serve("Core/Item/Data", #"[["romfs/a"]]"#)
        http.delayNanoseconds = 30_000_000
        let client = client()
        try await withThrowingTaskGroup(of: [String].self) { group in
            for id in 1...10 { group.addTask { try await client.archivePaths(fileID: id) } }
            for try await _ in group {}
        }
        XCTAssertEqual(http.count("Core/Item/Data"), 10)
        XCTAssertLessThanOrEqual(http.highWater, 4)
        XCTAssertGreaterThan(http.highWater, 1)
    }

    func testImageCacheRefusesUntrustedHost() async throws {
        let images = GameBananaImageCache(http: http, folder: dir.appendingPathComponent("images"),
                                          userAgent: GameBananaClient.userAgent(version: "0.1.4"))
        let bad = await images.file(for: URL(string: "https://example.com/a.jpg")!)
        XCTAssertNil(bad)
        XCTAssertEqual(http.requests.count, 0)
        http.serve("images.gamebanana.com", "jpegbytes")
        let url = URL(string: "https://images.gamebanana.com/img/ss/mods/530-90_x.jpg")!
        let fetched = await images.file(for: url)
        let file = try XCTUnwrap(fetched)
        XCTAssertEqual(try Data(contentsOf: file), Data("jpegbytes".utf8))
        XCTAssertEqual(file.pathExtension, "jpg")
        _ = await images.file(for: url)
        XCTAssertEqual(http.requests.count, 1)
    }
}
