import XCTest
import CryptoKit
@testable import NXLibraryCore

final class DotnetReleaseTests: XCTestCase {
    // Trimmed from releases.json for 10.0: two releases, the latest SDK's files in
    // every shape the picker must skip.
    private let json = """
    {"channel-version": "10.0", "latest-sdk": "10.0.403", "releases": [
      {"release-version": "10.0.14",
       "sdk": {"version": "10.0.403", "files": [
         {"name": "dotnet-sdk-osx-arm64.tar.gz", "rid": "osx-arm64",
          "url": "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-osx-arm64.tar.gz", "hash": "aa"},
         {"name": "dotnet-sdk-osx-x64.pkg", "rid": "osx-x64",
          "url": "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-osx-x64.pkg", "hash": "bb"},
         {"name": "dotnet-sdk-osx-arm64.pkg", "rid": "osx-arm64",
          "url": "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-osx-arm64.pkg", "hash": "\(String(repeating: "71", count: 64))"}]}},
      {"release-version": "10.0.13",
       "sdk": {"version": "10.0.402", "files": [
         {"name": "dotnet-sdk-osx-arm64.pkg", "rid": "osx-arm64",
          "url": "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.402/dotnet-sdk-10.0.402-osx-arm64.pkg", "hash": "cc"}]}}
    ]}
    """

    func testPicksLatestArm64Pkg() throws {
        let package = try DotnetRelease.latestSDKPackage(from: Data(json.utf8))
        XCTAssertEqual(package.version, "10.0.403")
        XCTAssertEqual(package.url.absoluteString,
                       "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-osx-arm64.pkg")
        XCTAssertEqual(package.sha512, String(repeating: "71", count: 64))
    }

    func testMissingPackageThrows() {
        let noArm = json.replacingOccurrences(of: "dotnet-sdk-10.0.403-osx-arm64.pkg", with: "dotnet-sdk-10.0.403-osx-arm64.zip")
        XCTAssertThrowsError(try DotnetRelease.latestSDKPackage(from: Data(noArm.utf8)))
        XCTAssertThrowsError(try DotnetRelease.latestSDKPackage(from: Data("{}".utf8)))
    }

    func testRejectsInstallerURLsOutsideTheOfficialHTTPSHosts() {
        let official = "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-osx-arm64.pkg"
        for url in ["http://builds.dotnet.microsoft.com/a.pkg", "file:///tmp/a.pkg",
                    "https://example.invalid/a.pkg", "https://builds.dotnet.microsoft.com.example.invalid/a.pkg",
                    "https://user:password@builds.dotnet.microsoft.com/a.pkg"] {
            let data = Data(json.replacingOccurrences(of: official, with: url).utf8)
            XCTAssertThrowsError(try DotnetRelease.latestSDKPackage(from: data), url)
        }
    }

    func testRejectsMissingOrMalformedPublishedHash() {
        for invalid in ["", "71CB3E", String(repeating: "z", count: 128)] {
            let data = Data(json.replacingOccurrences(of: String(repeating: "71", count: 64), with: invalid).utf8)
            XCTAssertThrowsError(try DotnetRelease.latestSDKPackage(from: data))
        }
    }

    func testInstallerRedirectCannotLeaveOfficialHTTPSHosts() throws {
        let policy = DotnetDownloadPolicy()
        let original = URL(string: "https://builds.dotnet.microsoft.com/a.pkg")!
        let task = URLSession.shared.dataTask(with: original)
        defer { task.cancel() }
        let response = try XCTUnwrap(HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil))
        for target in ["https://download.visualstudio.microsoft.com/a.pkg", "https://example.invalid/a.pkg",
                       "http://builds.dotnet.microsoft.com/a.pkg"] {
            let request = URLRequest(url: URL(string: target)!)
            var followed: URLRequest?
            policy.urlSession(.shared, task: task, willPerformHTTPRedirection: response, newRequest: request) { followed = $0 }
            XCTAssertEqual(followed != nil, target.hasPrefix("https://download.visualstudio.microsoft.com/"))
        }
    }

    func testVerify() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dotnet-\(UUID().uuidString).pkg")
        defer { try? FileManager.default.removeItem(at: file) }
        let content = Data((0..<3_000_000).map { UInt8($0 % 251) })
        try content.write(to: file)
        let hex = SHA512.hash(data: content).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(try DotnetRelease.verify(file: file, sha512: hex.uppercased()))

        var changed = content
        changed[1_500_000] ^= 1
        try changed.write(to: file)
        XCTAssertFalse(try DotnetRelease.verify(file: file, sha512: hex))
    }
}
