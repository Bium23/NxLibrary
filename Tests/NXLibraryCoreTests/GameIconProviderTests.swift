import AppKit
import XCTest
@testable import NXLibraryCore

final class GameIconProviderTests: XCTestCase {
    private func game() -> PortedGame {
        PortedGame(name: "Fixture", url: URL(fileURLWithPath: "/Volumes/Test/Example.app", isDirectory: true),
                   platform: .macApp, sizeBytes: 1, modificationDate: Date(timeIntervalSince1970: 1000))
    }

    @MainActor
    func testSlowSourceDoesNotBlockAndNextLaunchCanUseDiskOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let game = game()
        let png = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32)?.representation(using: .png, properties: [:]))
        let gate = DispatchSemaphore(value: 0)
        let read = expectation(description: "one source read")
        let provider = GameIconProvider(directory: directory) { _ in
            XCTAssertFalse(Thread.isMainThread)
            read.fulfill()
            guard gate.wait(timeout: .now() + 3) == .success else { return nil }
            return png
        }
        XCTAssertNil(provider.squareArt(for: game))
        await fulfillment(of: [read], timeout: 2)
        XCTAssertNil(provider.squareArt(for: game))
        gate.signal()
        let file = directory.appendingPathComponent(game.id.uuidString)
        for _ in 0..<200 where provider.squareArt(for: game) == nil || !FileManager.default.fileExists(atPath: file.path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(provider.squareArt(for: game))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let changed = expectation(description: "changed bundle gets a fresh lookup")
        let initialDate = game.modificationDate
        let nextLaunch = GameIconProvider(directory: directory) { request in
            XCTAssertNotEqual(request.date, initialDate, "matching cached icon must not open the share")
            changed.fulfill()
            return nil
        }
        for _ in 0..<200 where nextLaunch.squareArt(for: game) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(nextLaunch.squareArt(for: game))
        var rebuilt = game
        rebuilt.modificationDate = game.modificationDate.addingTimeInterval(60)
        XCTAssertNil(nextLaunch.squareArt(for: rebuilt))
        await fulfillment(of: [changed], timeout: 2)
    }
}
