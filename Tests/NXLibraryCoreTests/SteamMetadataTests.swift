import XCTest
import AppKit
@testable import NXLibraryCore

final class SteamMetadataTests: XCTestCase {
    private func payload(id: Int = 10) -> Data {
        Data("""
        {"10":{"success":true,"data":{"steam_appid":\(id),"name":"Fixture","short_description":"A &amp; B","genres":[{"id":"2","description":"Strategia"}],"developers":["Studio"],"publishers":["Publisher"],"release_date":{"date":"23 mag 2023"},"screenshots":[{"path_full":"https://shared.akamai.steamstatic.com/test.jpg"},{"path_full":"http://localhost/private"}]}}}
        """.utf8)
    }
    func testIdentityLocalizedFieldsAndSafeScreenshots() throws {
        let value = try SteamMetadata.decode(payload(), appID: 10, language: "italian")
        XCTAssertEqual(value.description, "A & B")
        XCTAssertEqual(value.genres, ["Strategia"])
        XCTAssertEqual(value.screenshots.count, 1)
        XCTAssertEqual(value.releaseDate, "23 mag 2023")
        XCTAssertThrowsError(try SteamMetadata.decode(payload(id: 20), appID: 10, language: "italian"))
        XCTAssertThrowsError(try SteamMetadata.decode(Data("{}".utf8), appID: 10, language: "italian"))
        XCTAssertNil(SteamMetadata.safeImage(URL(string: "https://steamstatic.com.attacker.test/x")))
    }
    func testLanguageMappingIsIndependentOfRegionalFormats() {
        XCTAssertEqual(SteamMetadata.language(.portugueseBrazil), "brazilian")
        XCTAssertEqual(SteamMetadata.language(.italian), "italian")
    }
    func testOfflineCacheAndPersonalDataAreIndependentOfRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let body = payload()
        let online = SteamMetadataService(directory: root, transport: { _ in body })
        let first = await online.metadata(appID: 10, language: "italian")
        XCTAssertEqual(first?.genres, ["Strategia"])
        let offline = SteamMetadataService(directory: root, transport: { _ in throw URLError(.notConnectedToInternet) })
        let retained = await offline.metadata(appID: 10, language: "italian", refresh: true)
        XCTAssertEqual(retained, first)
        let other = await offline.metadata(appID: 10, language: "english")
        XCTAssertNil(other)
        let picks = MetadataPicks(directory: root.appendingPathComponent("personal"))
        picks.set("My description", titleID: "10", field: .description)
        _ = await online.metadata(appID: 10, language: "italian", refresh: true)
        XCTAssertEqual(picks.value(titleID: "10", field: .description), "My description")
    }
    func testConcurrentMetadataRequestsShareOneTransport() async throws {
        actor Counter {
            var count = 0
            func bump() { count += 1 }
        }
        let counter = Counter(), body = payload()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SteamMetadataService(directory: root, transport: { _ in
            await counter.bump(); try await Task.sleep(nanoseconds: 30_000_000); return body
        })
        async let a = service.metadata(appID: 10, language: "english")
        async let b = service.metadata(appID: 10, language: "english")
        let values = await (a, b)
        XCTAssertNotNil(values.0); XCTAssertEqual(values.0?.description, values.1?.description)
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }
    func testFailedPersonalSaveDoesNotPublishUnsavedValues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a folder".utf8).write(to: root)
        let picks = SteamPersonalizationStore(directory: root)
        XCTAssertThrowsError(try picks.save(fields: [.description: "Lost"], images: [:], automatic: [], titleID: "10"))
        XCTAssertNil(picks.value(titleID: "10", field: .description))
        XCTAssertEqual(picks.revision, 0)
    }
    func testStoreFailuresAndNonHTTPSImagesAreRejected() throws {
        XCTAssertThrowsError(try SteamMetadata.decode(Data("{\"10\":{\"success\":false}}".utf8), appID: 10, language: "english"))
        for text in ["http://cdn.steamstatic.com/a", "https://user@cdn.steamstatic.com/a", "https://cdn.steamstatic.com:444/a", "file:///tmp/a"] {
            XCTAssertNil(SteamMetadata.safeImage(URL(string: text)))
        }
    }

    func testSemanticFailuresBackOffWithoutLosingTheLibrary() async {
        actor Calls { var count = 0; func bump() { count += 1 } }
        let calls = Calls()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SteamMetadataService(directory: root, transport: { _ in await calls.bump(); return Data("{}".utf8) })
        let first = await service.metadata(appID: 10, language: "english")
        let second = await service.metadata(appID: 10, language: "english")
        XCTAssertNil(first); XCTAssertNil(second)
        let count = await calls.count; XCTAssertEqual(count, 1)
    }
    func testCancellingSoleImageWaiterStopsTransportAndFallbacks() async {
        actor Calls { var count = 0; func bump() { count += 1 } }
        let calls = Calls(), started = expectation(description: "started"), stopped = expectation(description: "cancelled")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SteamMetadataService(directory: root, transport: { _ in
            await calls.bump(); started.fulfill()
            do { try await Task.sleep(nanoseconds: 10_000_000_000); return Data() }
            catch { stopped.fulfill(); throw error }
        })
        let request = Task { await service.image(appID: 10, slot: .cover) }
        await fulfillment(of: [started], timeout: 1)
        request.cancel()
        await fulfillment(of: [stopped], timeout: 1)
        let image = await request.value; XCTAssertNil(image)
        let count = await calls.count; XCTAssertEqual(count, 1)
    }
    func testCancelledSharedWaiterPreservesInterestedReader() async {
        let started = expectation(description: "started"), body = payload()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SteamMetadataService(directory: root, transport: { _ in
            started.fulfill(); try await Task.sleep(nanoseconds: 150_000_000); return body
        })
        let a = Task { await service.metadata(appID: 10, language: "english") }
        await fulfillment(of: [started], timeout: 1)
        let b = Task { await service.metadata(appID: 10, language: "english") }
        try? await Task.sleep(nanoseconds: 30_000_000)
        a.cancel()
        let result = await b.value; XCTAssertNotNil(result)
        let cancelled = await a.value; XCTAssertNil(cancelled)
    }
    func testFailedCombinedDraftKeepsAllPreviousPicksAndAutomaticReferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = image.representation(using: .png, properties: [:])!
        let initial = SteamPersonalizationStore(directory: root)
        try initial.save(fields: [.description: "Previous"], images: [.cover: png], automatic: [], titleID: "10")
        let original = initial.url(titleID: "10", slot: .cover)!
        let before = try Data(contentsOf: original)
        let failing = SteamPersonalizationStore(directory: root, publish: { _,_ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertThrowsError(try failing.save(fields: [.description: "New"], images: [.logo: png], automatic: [.cover], titleID: "10"))
        let restored = SteamPersonalizationStore(directory: root)
        XCTAssertEqual(restored.value(titleID: "10", field: .description), "Previous")
        XCTAssertEqual(restored.url(titleID: "10", slot: .cover), original)
        XCTAssertEqual(try Data(contentsOf: original), before)
        XCTAssertNil(restored.url(titleID: "10", slot: .logo))
        XCTAssertEqual(failing.revision, 0)
        try initial.save(fields: [:], images: [:], automatic: [.cover], titleID: "10")
        XCTAssertNil(SteamPersonalizationStore(directory: root).url(titleID: "10", slot: .cover))
    }

    func testRedirectIsRefusedBeforeSendingAnotherRequest() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let initial = URL(string: "https://store.steampowered.com/api/appdetails")!
        let task = session.dataTask(with: initial)
        let response = HTTPURLResponse(url: initial, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let delegate = SteamMetadataService.NoRedirects()
        var invoked = false
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "https://example.invalid/private")!)) { request in
            invoked = true; XCTAssertNil(request)
        }
        XCTAssertTrue(invoked)
        XCTAssertEqual(task.state, .suspended)
        XCTAssertFalse(SteamMetadataService.allowed(URL(string: "http://store.steampowered.com/a")!))
    }
    func testInvalidImageBytesAreBackedOffForBothCandidateURLs() async {
        actor Calls { var count = 0; func bump() { count += 1 } }
        let calls = Calls(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SteamMetadataService(directory: root, transport: { _ in await calls.bump(); return Data("invalid image".utf8) })
        _ = await service.image(appID: 10, slot: .cover)
        _ = await service.image(appID: 10, slot: .cover)
        let count = await calls.count; XCTAssertEqual(count, 2)
    }
    func testSelectionBurstBoundsOutstandingTransfers() async {
        actor Calls {
            var active = 0, peak = 0
            func enter() { active += 1; peak = max(peak, active) }
            func leave() { active -= 1 }
        }
        let calls = Calls(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SteamMetadataService(directory: root, transport: { _ in
            await calls.enter(); try await Task.sleep(nanoseconds: 100_000_000); await calls.leave(); return Data("{}".utf8)
        })
        await withTaskGroup(of: Void.self) { group in
            for id in 1...20 { group.addTask { _ = await service.metadata(appID: UInt32(id), language: "english") } }
        }
        let peak = await calls.peak; XCTAssertGreaterThan(peak, 0); XCTAssertLessThanOrEqual(peak, 6)
    }
    func testUnreadablePersonalManifestIsPreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("personal.json"), original = Data("damaged".utf8)
        try original.write(to: file)
        let store = SteamPersonalizationStore(directory: root)
        XCTAssertThrowsError(try store.save(fields: [.description: "New"], images: [:], automatic: [], titleID: "10"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

}
