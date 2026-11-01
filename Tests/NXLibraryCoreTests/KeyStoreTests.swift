import XCTest
@testable import NXLibraryCore

final class KeyStoreTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXKeys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func fakeKeys(header: Bool = true) -> String {
        var lines = ["key_area_key_application_00 = " + String(repeating: "00", count: 16)]
        if header { lines.append("header_key = " + String(repeating: "11", count: 32)) }
        return lines.joined(separator: "\n") + "\n"
    }

    func testImportSets0600AndKeepsOnlySummary() throws {
        let source = dir.appendingPathComponent("prod.keys")
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        let store = KeyStore(directory: dir.appendingPathComponent("keys"))
        let summary = try store.importKey(from: source)
        XCTAssertTrue(summary.hasHeaderKey)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.keyURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(String(describing: summary).contains("1111"))
    }

    func testMissingHeaderKeyThrows() throws {
        let source = dir.appendingPathComponent("bad.keys")
        try fakeKeys(header: false).write(to: source, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try KeyStore(directory: dir.appendingPathComponent("k2")).importKey(from: source))
    }

    func testFailedReplacementKeepsTheManagedKeyAndTheSource() throws {
        let source = dir.appendingPathComponent("source.keys")
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        let managed = dir.appendingPathComponent("managed")
        let original = KeyStore(directory: managed)
        try original.importKey(from: source)
        let before = try Data(contentsOf: original.keyURL)
        let store = KeyStore(directory: managed)
        store.publish = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertThrowsError(try store.importKey(from: source))
        XCTAssertEqual(try Data(contentsOf: store.keyURL), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: managed.path), ["prod.keys"])
    }

    func testSuccessfulReplacementPublishesTheNewKeyWithPrivatePermissions() throws {
        let source = dir.appendingPathComponent("source.keys")
        try fakeKeys().write(to: source, atomically: true, encoding: .utf8)
        let store = KeyStore(directory: dir.appendingPathComponent("managed"))
        try store.importKey(from: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.keyURL.path)
        let updated = fakeKeys() + "key_area_key_application_01 = " + String(repeating: "22", count: 16) + "\n"
        try updated.write(to: source, atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.importKey(from: source).applicationKeyGenerations, [0, 1])
        XCTAssertEqual(try Data(contentsOf: store.keyURL), try Data(contentsOf: source))
        let permissions = try FileManager.default.attributesOfItem(atPath: store.keyURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testMalformedLineDoesNotLeakContent() throws {
        let source = dir.appendingPathComponent("malformed.keys")
        try (fakeKeys() + "TOP_SECRET_KEY_MATERIAL\n")
            .write(to: source, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try KeyStore(directory: dir.appendingPathComponent("k3")).importKey(from: source)) { error in
            XCTAssertFalse(error.localizedDescription.contains("TOP_SECRET"))
        }
    }

    func testCRLFLineNumber() throws {
        let source = dir.appendingPathComponent("crlf.keys")
        try (fakeKeys().replacingOccurrences(of: "\n", with: "\r\n") + "BAD\r\n")
            .write(to: source, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try KeyStore(directory: dir.appendingPathComponent("k4")).importKey(from: source)) { error in
            XCTAssertTrue(error.localizedDescription.contains("3"), error.localizedDescription)
        }
    }
}
