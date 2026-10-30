import XCTest
import AppKit
@testable import NXLibraryCore

final class ArtworkStoreTests: XCTestCase {
    private final class FakeClient: ArtworkHTTPClient {
        var data: Data?
        var error: Error?
        var calls = 0
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            calls += 1
            if let error { throw error }
            return (data ?? Data(), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                    httpVersion: nil, headerFields: nil)!)
        }
    }

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXArt-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func imageData(width: Int, height: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
    }

    func testFetchCachesAndDoesNotRedownload() async throws {
        let client = FakeClient()
        client.data = imageData(width: 3000, height: 2000)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        let url = URL(string: "https://example.com/hero.jpg")!
        let first = await store.fetch(titleID: "0100", remoteURL: url, kind: .hero)
        XCTAssertNotNil(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first!.path))
        let second = await store.fetch(titleID: "0100", remoteURL: url, kind: .hero)
        XCTAssertEqual(first, second)
        XCTAssertEqual(client.calls, 1)
    }

    func testFailureReturnsNilWithoutCache() async {
        let client = FakeClient()
        client.error = URLError(.notConnectedToInternet)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        let url = URL(string: "https://example.com/hero.jpg")!
        let result = await store.fetch(titleID: "0100", remoteURL: url, kind: .hero)
        XCTAssertNil(result)
    }

    func testNilRemoteURLReturnsCachedFileWhenPresent() async {
        let client = FakeClient()
        client.data = imageData(width: 800, height: 600)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let url = URL(string: "https://example.com/cover.jpg")!
        let cached = await store.fetch(titleID: "0100", remoteURL: url, kind: .boxart)
        XCTAssertNotNil(cached)
        let offline = await store.fetch(titleID: "0100", remoteURL: nil, kind: .boxart)
        XCTAssertEqual(cached, offline)
    }

    func testClearRemovesFiles() async {
        let client = FakeClient()
        client.data = imageData(width: 800, height: 600)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        _ = await store.fetch(titleID: "0100",
                              remoteURL: URL(string: "https://example.com/cover.jpg"),
                              kind: .boxart)
        XCTAssertGreaterThan(store.cacheSize(), 0)
        store.clear()
        XCTAssertEqual(store.cacheSize(), 0)
    }

    func testTrimRemovesFilesOverCap() async {
        let client = FakeClient()
        client.data = imageData(width: 800, height: 600)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        _ = await store.fetch(titleID: "0100",
                              remoteURL: URL(string: "https://example.com/cover.jpg"),
                              kind: .boxart)
        XCTAssertGreaterThan(store.cacheSize(), 0)
        store.trimCache(maxBytes: 1)
        XCTAssertEqual(store.cacheSize(), 0)
    }

    func testDownsampleLimitsHeroAndCover() async {
        let client = FakeClient()
        client.data = imageData(width: 4000, height: 3000)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let hero = await store.fetch(titleID: "0100",
                                     remoteURL: URL(string: "https://example.com/h.jpg"),
                                     kind: .hero)!
        let cover = await store.fetch(titleID: "0100",
                                      remoteURL: URL(string: "https://example.com/c.jpg"),
                                      kind: .boxart)!
        let heroImage = NSImage(contentsOf: hero)!
        let coverImage = NSImage(contentsOf: cover)!
        XCTAssertLessThanOrEqual(max(heroImage.size.width, heroImage.size.height), 2560)
        XCTAssertLessThanOrEqual(max(coverImage.size.width, coverImage.size.height), 1400)
    }

    func testLogoPreservesPNG() async {
        let client = FakeClient()
        client.data = imageData(width: 800, height: 400)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let logo = await store.fetch(titleID: "0100",
                                     remoteURL: URL(string: "https://example.com/logo.png"),
                                     kind: .logo)!
        XCTAssertEqual(logo.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logo.path))
    }

    func testSquareKindFileURL() async {
        let client = FakeClient()
        client.data = imageData(width: 1024, height: 1024)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let url = await store.fetch(titleID: "0100ABC",
                                    remoteURL: URL(string: "https://example.com/s.png"),
                                    kind: .square)
        XCTAssertEqual(url, dir.appendingPathComponent("0100ABC").appendingPathComponent("square.png"))
        XCTAssertEqual(store.cachedURL(titleID: "0100ABC", kind: .square), url)
    }

    func testSquareMaxPixelSize512() async {
        XCTAssertEqual(ArtworkKind.square.maxPixelSize, 512)
        let client = FakeClient()
        client.data = imageData(width: 1024, height: 1024)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        let url = await store.fetch(titleID: "0100",
                                    remoteURL: URL(string: "https://example.com/s.png"),
                                    kind: .square)!
        let image = NSImage(contentsOf: url)!
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 512)
    }

    func testSquareKeepsAlpha() async {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        let client = FakeClient()
        client.data = png
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        let url = await store.fetch(titleID: "0100",
                                    remoteURL: URL(string: "https://example.com/s.png"),
                                    kind: .square)!
        XCTAssertEqual(url.pathExtension, "png")
        let rep = NSBitmapImageRep(data: try! Data(contentsOf: url))!
        XCTAssertTrue(rep.hasAlpha)
        XCTAssertEqual(rep.colorAt(x: 60, y: 30)?.alphaComponent ?? 1, 0, accuracy: 0.01)
    }

    func testScreenshotCachePath() async throws {
        let client = FakeClient()
        client.data = imageData(width: 3200, height: 1800)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let url = URL(string: "https://api.nlib.cc/nx/0100/screen/1")!
        let first = await store.screenshot(titleID: "0100", index: 1, remoteURL: url)
        XCTAssertEqual(first?.lastPathComponent, "screen-1.jpg")
        XCTAssertEqual(first?.deletingLastPathComponent().lastPathComponent, "0100")
        let image = NSImage(contentsOf: first!)!.representations[0]
        XCTAssertEqual(max(image.pixelsWide, image.pixelsHigh), 1600)
        let second = await store.screenshot(titleID: "0100", index: 1, remoteURL: url)
        XCTAssertEqual(first, second)
        XCTAssertEqual(client.calls, 1)
    }
}
