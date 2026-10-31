import XCTest
@testable import NXLibraryCore

final class AppSizeCacheTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NXSizes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeApp(_ name: String, bytes: Int) throws -> URL {
        let app = root.appendingPathComponent("Games/\(name).app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": name, "CFBundleIdentifier": "org.nxnative.01007ef00011e000",
            "DMTitleID": "01007EF00011E000"], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data(count: bytes).write(to: app.appendingPathComponent("Contents/payload"))
        return app
    }

    func testRemembersASizeForTheSameDateAndKeepsItAcrossLaunches() {
        let file = root.appendingPathComponent("app-sizes.json")
        let app = URL(fileURLWithPath: "/Users/a/Applications/Game.app")
        let date = Date(timeIntervalSinceReferenceDate: 1234.5)
        let cache = AppSizeCache(file: file)
        cache.set(42, for: app, date: date)
        cache.save()
        let again = AppSizeCache(file: file)
        XCTAssertEqual(again.size(for: app, date: date), 42)
        XCTAssertNil(again.size(for: app, date: date.addingTimeInterval(1)), "a rebuilt app is measured again")
    }

    func testScanUsesTheRememberedSizeAndMeasuresAChangedApp() throws {
        let app = try makeApp("Game", bytes: 1000)
        let cache = AppSizeCache(file: root.appendingPathComponent("app-sizes.json"))
        let service = ImportService(sizeCache: cache)
        let first = try XCTUnwrap(service.scan(directories: [app.deletingLastPathComponent()]).first)
        XCTAssertGreaterThanOrEqual(first.sizeBytes, 1000)

        // Same date: the remembered value is used, without walking the app.
        cache.set(7, for: app, date: first.modificationDate)
        XCTAssertEqual(service.scan(directories: [app.deletingLastPathComponent()]).first?.sizeBytes, 7)

        // A different date (a new build): measured again.
        let later = first.modificationDate.addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: app.path)
        XCTAssertGreaterThanOrEqual(service.scan(directories: [app.deletingLastPathComponent()]).first?.sizeBytes ?? 0, 1000)
    }

    func testScanForgetsAppsThatAreGone() throws {
        let file = root.appendingPathComponent("app-sizes.json")
        let cache = AppSizeCache(file: file)
        let gone = root.appendingPathComponent("Games/Gone.app")
        cache.set(5, for: gone, date: Date(timeIntervalSinceReferenceDate: 1))
        let app = try makeApp("Game", bytes: 10)
        _ = ImportService(sizeCache: cache).scan(directories: [app.deletingLastPathComponent()])
        XCTAssertNil(AppSizeCache(file: file).size(for: gone, date: Date(timeIntervalSinceReferenceDate: 1)))
    }

    func testEmptyMessageWaitsForTheLibrary() {
        XCTAssertFalse(LibraryEmptyState.showsMessage(hasGames: false, isReadingLibrary: true))
        XCTAssertTrue(LibraryEmptyState.showsMessage(hasGames: false, isReadingLibrary: false))
        XCTAssertFalse(LibraryEmptyState.showsMessage(hasGames: true, isReadingLibrary: false))
    }
}
