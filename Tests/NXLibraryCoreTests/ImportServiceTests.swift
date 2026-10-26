import XCTest
@testable import NXLibraryCore

final class ImportServiceTests: XCTestCase {
    func testFindsOnlyNxnativeApps() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXImport-\(UUID().uuidString)")
        let nxnative = root.appendingPathComponent("Zelda.app/Contents")
        let other = root.appendingPathComponent("Other.app/Contents")
        try FileManager.default.createDirectory(at: nxnative, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try nxnativePlist().write(to: nxnative.appendingPathComponent("Info.plist"))
        try otherPlist().write(to: other.appendingPathComponent("Info.plist"))
        let apps = ImportService().scan(directories: [root])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.titleId, "01007EF00011E000")
        XCTAssertEqual(apps.first?.name, "The Legend of Zelda: Breath of the Wild")

        let game = ImportService().makeGame(from: try XCTUnwrap(apps.first))
        XCTAssertEqual(game.status, .builtSourcesMissing)
        XCTAssertEqual(game.titleId, "01007EF00011E000")
        XCTAssertEqual(game.bundleId, "org.nxnative.01007ef00011e000")
        XCTAssertEqual(game.versionString, "1.9.0")
        XCTAssertEqual(game.url.lastPathComponent, "Zelda.app")
    }

    private func nxnativePlist() -> Data {
        try! PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "The Legend of Zelda: Breath of the Wild",
            "CFBundleIdentifier": "org.nxnative.01007ef00011e000",
            "CFBundleShortVersionString": "1.9.0",
            "DMTitleID": "01007EF00011E000",
        ], format: .xml, options: 0)
    }

    private func otherPlist() -> Data {
        try! PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Other",
            "CFBundleIdentifier": "com.example.other",
        ], format: .xml, options: 0)
    }

    func testRejectsInvalidTitleIdsAndFallsBackToBundleSuffix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXImportIDs-\(UUID().uuidString)")
        let bad = root.appendingPathComponent("Bad.app/Contents")
        let suffixOnly = root.appendingPathComponent("Suffix.app/Contents")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: suffixOnly, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Bad",
            "CFBundleIdentifier": "org.nxnative.app",
            "DMTitleID": "../../../Documents/x",
        ], format: .xml, options: 0).write(to: bad.appendingPathComponent("Info.plist"))
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleName": "Suffix",
            "CFBundleIdentifier": "org.nxnative.01007ef00011e000",
        ], format: .xml, options: 0).write(to: suffixOnly.appendingPathComponent("Info.plist"))

        let apps = ImportService().scan(directories: [root])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.titleId, "01007EF00011E000")
        try? FileManager.default.removeItem(at: root)
    }
}
