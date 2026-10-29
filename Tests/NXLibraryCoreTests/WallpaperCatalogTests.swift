import XCTest
@testable import NXLibraryCore

final class WallpaperCatalogTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("Wallpapers-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func touch(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        return url
    }

    func testScanMergesRootsAndImportsWin() throws {
        _ = try touch("bundle/gruvbox/2-flower-basket.jpg")
        _ = try touch("bundle/gruvbox/notes.txt")
        let imported = try touch("imports/gruvbox/2-flower-basket.jpg")
        _ = try touch("imports/nord/1-aurora.png")
        let all = WallpaperCatalog.scan(roots: [root.appendingPathComponent("bundle"),
                                                root.appendingPathComponent("imports")])
        XCTAssertEqual(all.map(\.id), ["gruvbox/2-flower-basket", "nord/1-aurora"])
        XCTAssertEqual(all.first?.url.standardizedFileURL, imported.standardizedFileURL)
        XCTAssertEqual(all.first?.title, "Gruvbox · Flower basket")
    }

    func testResolve() throws {
        let a = Wallpaper(id: "nord/1-a", theme: "nord", url: URL(fileURLWithPath: "/a.jpg"))
        let b = Wallpaper(id: "nord/2-b", theme: "nord", url: URL(fileURLWithPath: "/b.jpg"))
        let all = [a, b]
        XCTAssertEqual(WallpaperCatalog.resolve(nil, themeID: "nord", in: all), a)
        XCTAssertNil(WallpaperCatalog.resolve(nil, themeID: "selene", in: all))
        XCTAssertNil(WallpaperCatalog.resolve("none", themeID: "nord", in: all))
        XCTAssertEqual(WallpaperCatalog.resolve("nord/2-b", themeID: "selene", in: all), b)
        XCTAssertNil(WallpaperCatalog.resolve("gone/1", themeID: "nord", in: all))
    }
}
