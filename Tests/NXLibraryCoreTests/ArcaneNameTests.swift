import XCTest
@testable import NXLibraryCore

/// The app shows itself as Arcane everywhere a person or a web service can see a name.
final class ArcaneNameTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testCatalogShowsNoOldAppName() throws {
        let url = repository.appendingPathComponent("Sources/NXLibraryCore/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        var found: [String] = []
        for (key, entry) in strings {
            if key.contains("NX Library") { found.append(key) }
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (language, value) in localizations {
                let text = ((value as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                if text.contains("NX Library") { found.append("\(language): \(key)") }
            }
        }
        XCTAssertEqual(found.sorted(), [])
    }

    func testUserAgentNamesArcane() {
        XCTAssertEqual(AppIdentity.userAgent(version: "0.2"), "Arcane/0.2 (macOS; +https://github.com/Bium23/NxLibrary)")
    }

    func testProjectDocsOpenTheReadmeOnlineOnEveryMac() {
        XCTAssertEqual(AppIdentity.documentationPage.absoluteString, "https://github.com/Bium23/NxLibrary#readme")
    }

    func testNoSourceSendsTheOldUserAgent() throws {
        let sources = repository.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let offenders = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains("\"NXLibrary/") }
            .map(\.lastPathComponent)
        XCTAssertEqual(offenders, [])
    }
}
