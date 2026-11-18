import XCTest
@testable import NXLibraryCore

/// Serves a fixed body in several chunks, or a redirect, without the network.
private final class ChunkedStub: URLProtocol {
    nonisolated(unsafe) static var chunks: [Data] = []
    nonisolated(unsafe) static var declaredLength: Int?
    nonisolated(unsafe) static var redirect: URL?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        if let target = Self.redirect, url != target {
            // A refused redirect leaves the 302 as the final response; followed, the target would load with 200.
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var headers: [String: String] = [:]
        if let length = Self.declaredLength { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in Self.chunks { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class BoundedDownloadTests: XCTestCase {
    private let url = URL(string: "https://example.invalid/page")!
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChunkedStub.self]
        return URLSession(configuration: config)
    }
    override func setUp() {
        ChunkedStub.chunks = []; ChunkedStub.declaredLength = nil; ChunkedStub.redirect = nil
    }

    func testCollectsEveryChunkUpToTheLimit() async throws {
        ChunkedStub.chunks = [Data(repeating: 1, count: 4), Data(repeating: 2, count: 4), Data(repeating: 3, count: 2)]
        let (data, response) = try await BoundedDownload.data(for: URLRequest(url: url), session: session(), limit: 10)
        XCTAssertEqual(data, Data([1, 1, 1, 1, 2, 2, 2, 2, 3, 3]))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(response.url, url)
    }

    func testStopsWhenTheBodyGrowsPastTheLimit() async {
        ChunkedStub.chunks = [Data(repeating: 1, count: 6), Data(repeating: 2, count: 6)]
        do {
            _ = try await BoundedDownload.data(for: URLRequest(url: url), session: session(), limit: 10)
            XCTFail("An oversized body must not be returned")
        } catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
    }

    func testRefusesADeclaredLengthPastTheLimit() async {
        ChunkedStub.chunks = [Data(repeating: 1, count: 4)]
        ChunkedStub.declaredLength = 11
        do {
            _ = try await BoundedDownload.data(for: URLRequest(url: url), session: session(), limit: 10)
            XCTFail("A declared oversized body must not be read")
        } catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
    }

    func testNeverFollowsARedirect() async throws {
        ChunkedStub.redirect = URL(string: "https://elsewhere.invalid/")!
        let (_, response) = try await BoundedDownload.data(for: URLRequest(url: url), session: session(), limit: 10)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 302)
        XCTAssertEqual(response.url, url)
    }

    func testCancellationStopsTheRead() async {
        ChunkedStub.chunks = [Data(repeating: 1, count: 4)]
        let session = session()
        let task = Task { try await BoundedDownload.data(for: URLRequest(url: self.url), session: session, limit: 10) }
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled read must not return data") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
