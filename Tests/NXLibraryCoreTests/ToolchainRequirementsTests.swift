import XCTest
@testable import NXLibraryCore

final class ToolchainRequirementsTests: XCTestCase {
    func testVersionCompareIsNumeric() {
        XCTAssertTrue(VersionNumber.isOlder("10.0.401", than: "10.0.403"))
        XCTAssertTrue(VersionNumber.isOlder("27.1", than: "27.10"))
        XCTAssertTrue(VersionNumber.isOlder("27", than: "27.0.1"))
        XCTAssertFalse(VersionNumber.isOlder("27.1", than: "27.1.0"))
        XCTAssertFalse(VersionNumber.isOlder("10.0.403", than: "10.0.401"))
        XCTAssertFalse(VersionNumber.isOlder("26.4", than: "26.4"))
    }

    func testMetalDownloadPinsTheCertifiedAsset() {
        let requirements = ToolchainRequirements(minimumXcode: "27.1", dotnetMajor: 10, fallbackMetal: "32023.921",
                                                 metalAssets: ["32023.921": "27A266a"])
        XCTAssertEqual(requirements.metalDownload(for: "32023.921"),
                       ["-downloadComponent", "MetalToolchain", "-buildVersion", "27A266a"])
        XCTAssertNil(requirements.metalDownload(for: "32024.1"))
        XCTAssertEqual(ToolchainRequirements.anyMetalDownload, ["-downloadComponent", "MetalToolchain"])
    }

    func testCurrentCoversItsOwnFallback() {
        let current = ToolchainRequirements.current
        XCTAssertNotNil(current.metalAssets[current.fallbackMetal])
        XCTAssertEqual(current.dotnetMajor, 10)
    }

    func testXcodeVersionParse() {
        XCTAssertEqual(ToolchainRequirements.xcodeVersion(from: "Xcode 27.1\nBuild version 27A9275\n"), "27.1")
        XCTAssertNil(ToolchainRequirements.xcodeVersion(from: "xcode-select: error"))
    }

    func testNewestDotnetSDKForMajor() {
        let lines = ["8.0.414 [/usr/local/share/dotnet/sdk]", "10.0.401 [/usr/local/share/dotnet/sdk]",
                     "10.0.100 [/usr/local/share/dotnet/sdk]"]
        XCTAssertEqual(ToolchainRequirements.newestSDK(major: 10, in: lines), "10.0.401")
        XCTAssertNil(ToolchainRequirements.newestSDK(major: 10, in: ["8.0.414 [/x]"]))
    }
}
