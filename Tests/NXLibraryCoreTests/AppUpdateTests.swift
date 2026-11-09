import XCTest
@testable import NXLibraryCore

final class AppUpdateTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    /// A minimal app bundle: Info.plist and an executable script.
    @discardableResult
    private func makeApp(_ name: String = "NXLibrary.app", in folder: URL? = nil, id: String = "local.nxlibrary",
                         version: String = "0.2.0", release: Bool = true, minimumOS: String? = nil,
                         executable: Bool = true, marker: String = "new") throws -> URL {
        let app = (folder ?? dir).appendingPathComponent(name)
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "NXLibrary",
                                   "CFBundleShortVersionString": version]
        if release { info[AppUpdate.releaseMarker] = true }
        if let minimumOS { info["LSMinimumSystemVersion"] = minimumOS }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        if executable {
            let exe = macOS.appendingPathComponent("NXLibrary")
            try Data("#!/bin/sh\n# \(marker)\n".utf8).write(to: exe)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        }
        return app
    }

    private let os = OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0)

    func testDevelopmentCopySaysSo() {
        XCTAssertEqual(AppUpdate.versionLabel(["CFBundleShortVersionString": "0.1.3", "NXLibraryRelease": true]), "0.1.3")
        XCTAssertEqual(AppUpdate.versionLabel(["CFBundleShortVersionString": "0.1.3"]), "0.1.3 (development build)")
    }

    /// The development version is the one in progress, and a release never ships under another number.
    func testVersionFileIsTheVersionInProgress() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let version = try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotNil(version.range(of: #"^[0-9]+(\.[0-9]+){1,3}$"#, options: .regularExpression))
    }

    func testVersionCompareIsNumeric() {
        XCTAssertTrue(AppUpdate.isNewer("0.10.0", than: "0.9.3"))
        XCTAssertFalse(AppUpdate.isNewer("0.2", than: "0.2.0"))
        XCTAssertFalse(AppUpdate.isNewer("0.1.9", than: "0.2.0"))
        XCTAssertFalse(AppUpdate.isNewer("dev", than: "0.2.0"))
        XCTAssertEqual(AppUpdate.version(fromTag: "v1.0.0"), "1.0.0")
        XCTAssertEqual(AppUpdate.version(fromTag: "1.2"), "1.2")
        XCTAssertNil(AppUpdate.version(fromTag: "v1.0-beta"))
    }

    private let releaseJSON = """
    {"tag_name": "v0.3.0", "body": "Fixes.", "assets": [
      {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt", "digest": null},
      {"name": "NXLibrary-0.3.0.zip", "browser_download_url": "https://github.com/Bium23/NxLibrary/releases/download/v0.3.0/NXLibrary-0.3.0.zip", "size": 1024,
       "digest": "sha256:\(String(repeating: "a", count: 64))"}
    ]}
    """

    func testParseReleasePicksNamedAsset() throws {
        let release = try XCTUnwrap(AppUpdate.parseRelease(Data(releaseJSON.utf8)))
        XCTAssertEqual(release.tag, "v0.3.0")
        XCTAssertEqual(release.version, "0.3.0")
        XCTAssertEqual(release.notes, "Fixes.")
        XCTAssertEqual(release.zipURL.lastPathComponent, "NXLibrary-0.3.0.zip")
        XCTAssertEqual(release.digest, "sha256:" + String(repeating: "a", count: 64))
    }

    private func changingAsset(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(releaseJSON.utf8)) as? [String: Any])
        var assets = try XCTUnwrap(object["assets"] as? [[String: Any]])
        change(&assets[1])
        object["assets"] = assets
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testDownloadSourceIsPublicProjectRepository() {
        XCTAssertEqual(AppUpdate.defaultRepository, "Bium23/NxLibrary")
    }

    func testRejectsReleaseWithoutDigest() throws {
        XCTAssertNil(AppUpdate.parseRelease(try changingAsset { $0.removeValue(forKey: "digest") }))
    }

    func testRejectsReleaseWithoutDownloadSize() throws {
        XCTAssertNil(AppUpdate.parseRelease(try changingAsset { $0.removeValue(forKey: "size") }))
    }

    func testRejectsOversizedOrEmptyDownload() throws {
        for size: Int64 in [0, -1, 536_870_913] {
            XCTAssertNil(AppUpdate.parseRelease(try changingAsset { $0["size"] = size }))
        }
    }

    func testRejectsDownloadFromAnotherRepositoryOrHost() throws {
        for url in [
            "http://github.com/Bium23/NxLibrary/releases/download/v0.3.0/NXLibrary-0.3.0.zip",
            "https://github.com/other/project/releases/download/v0.3.0/NXLibrary-0.3.0.zip",
            "https://github.com.evil.example/Bium23/NxLibrary/releases/download/v0.3.0/NXLibrary-0.3.0.zip",
            "https://user:password@github.com/Bium23/NxLibrary/releases/download/v0.3.0/NXLibrary-0.3.0.zip",
            "https://github.com/Bium23/NxLibrary/releases/download/v0.2.0/NXLibrary-0.3.0.zip"
        ] {
            XCTAssertNil(AppUpdate.parseRelease(try changingAsset { $0["browser_download_url"] = url }), url)
        }
    }

    func testDownloadBudgetAndGitHubRedirectBoundary() {
        XCTAssertTrue(AppUpdate.downloadWithinLimit(received: 1024, expected: 1024))
        XCTAssertFalse(AppUpdate.downloadWithinLimit(received: 1025, expected: 1024))
        XCTAssertFalse(AppUpdate.downloadWithinLimit(received: 1, expected: 536_870_913))
        XCTAssertFalse(AppUpdate.downloadWithinLimit(received: 0, expected: 0))
        XCTAssertTrue(AppUpdate.trustedDownloadURL(URL(string: "https://release-assets.githubusercontent.com/example?signature=test")!))
        XCTAssertFalse(AppUpdate.trustedDownloadURL(URL(string: "https://release-assets.githubusercontent.com.evil.example/example")!))
        XCTAssertFalse(AppUpdate.trustedDownloadURL(URL(string: "https://github.com:444/example")!))
    }

    func testSignatureRejectsUnsignedAndTamperedBundle() throws {
        let app = try makeApp("Signed.app")
        XCTAssertFalse(AppUpdate.validCodeSignature(app))
        let executable = app.appendingPathComponent("Contents/MacOS/NXLibrary")
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let resource = app.appendingPathComponent("Contents/Resources/check.txt")
        try FileManager.default.createDirectory(at: resource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: resource)
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", app.path]
        signer.standardOutput = FileHandle.nullDevice
        signer.standardError = FileHandle.nullDevice
        try signer.run(); signer.waitUntilExit()
        XCTAssertEqual(signer.terminationStatus, 0)
        XCTAssertTrue(AppUpdate.validCodeSignature(app))
        try Data("changed".utf8).write(to: resource)
        XCTAssertFalse(AppUpdate.validCodeSignature(app))
    }

    func testRequirementsAreReadFromTheNotesAndHidden() {
        let notes = "Faster loading.\n\n<!-- nxlibrary-requires xcode=27.2 engine=2716f78f01e90a9f9bbf0d09e7a798903525962f -->\n"
        let (requirements, shown) = AppUpdate.requirements(in: notes)
        XCTAssertEqual(requirements, AppUpdate.Requirements(minimumXcode: "27.2",
                                                            engineCommit: "2716f78f01e90a9f9bbf0d09e7a798903525962f"))
        XCTAssertEqual(shown, "Faster loading.")
        XCTAssertEqual(AppUpdate.requirements(in: "Just notes.").0, AppUpdate.Requirements())
        XCTAssertEqual(AppUpdate.requirements(in: "Just notes.").1, "Just notes.")
    }

    func testRequirementsLineRoundTrips() {
        let line = AppUpdate.requirementsLine(minimumXcode: "27.1", engineCommit: "abc")
        XCTAssertEqual(line, "<!-- nxlibrary-requires xcode=27.1 engine=abc -->")
        XCTAssertEqual(AppUpdate.requirements(in: line).0, AppUpdate.Requirements(minimumXcode: "27.1", engineCommit: "abc"))
    }

    func testParseReleaseSplitsRequirementsFromNotes() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(releaseJSON.utf8)) as? [String: Any])
        object["body"] = "Notes.\n<!-- nxlibrary-requires xcode=27.2 engine=abc -->"
        let release = try XCTUnwrap(AppUpdate.parseRelease(JSONSerialization.data(withJSONObject: object)))
        XCTAssertEqual(release.notes, "Notes.")
        XCTAssertEqual(release.requirements.minimumXcode, "27.2")
    }

    func testRequirementNotes() {
        let r = AppUpdate.Requirements(minimumXcode: "27.2", engineCommit: "2716f78f01e90a9f9bbf0d09e7a798903525962f")
        XCTAssertEqual(AppUpdate.requirementNotes(r, installedXcode: "27.1", currentEngine: "ee369f09984f"), [
            "New portings need Xcode 27.2; this Mac has 27.1. Update Xcode from the App Store first. Your games keep playing.",
            "It comes with nxnative 2716f78: after the restart, Setup downloads it in one step.",
        ])
        XCTAssertEqual(AppUpdate.requirementNotes(r, installedXcode: "27.2", currentEngine: "2716f78f01e90a9f9bbf0d09e7a798903525962f"), [])
        XCTAssertEqual(AppUpdate.requirementNotes(AppUpdate.Requirements(), installedXcode: nil, currentEngine: "x"), [])
        XCTAssertEqual(AppUpdate.requirementNotes(r, installedXcode: nil, currentEngine: "2716f78f01e90a9f9bbf0d09e7a798903525962f"), [],
                       "no Xcode at all is the Setup check's job")
        XCTAssertEqual(AppUpdate.neededXcode(r, installedXcode: "27.1"), "27.2")
        XCTAssertNil(AppUpdate.neededXcode(r, installedXcode: "27.2.1"))
    }

    /// The app reads the installed Xcode as `xcodebuild -version`'s first line, "Xcode 27.2": the word before
    /// the number must not make a current Xcode look older (0.1.4 asked to update Xcode 27.2 to 27.2).
    func testRequirementNotesReadXcodebuildsOwnLine() {
        let r = AppUpdate.Requirements(minimumXcode: "27.2", engineCommit: nil)
        XCTAssertNil(AppUpdate.neededXcode(r, installedXcode: "Xcode 27.2"))
        XCTAssertNil(AppUpdate.neededXcode(r, installedXcode: "Xcode 27.3"))
        XCTAssertEqual(AppUpdate.neededXcode(r, installedXcode: "Xcode 27.1"), "27.2")
        XCTAssertEqual(AppUpdate.requirementNotes(r, installedXcode: "Xcode 27.2", currentEngine: "x"), [])
    }

    /// scripts/release.sh reads these two values from the sources with sed; a reformat must not break it.
    func testReleaseScriptCanReadTheRequirements() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let requirements = try String(contentsOf: root.appendingPathComponent("Sources/NXLibraryCore/Models/ToolchainRequirements.swift"), encoding: .utf8)
        XCTAssertNotNil(requirements.range(of: #"minimumXcode: "[0-9.]+""#, options: .regularExpression))
        let viewModel = try String(contentsOf: root.appendingPathComponent("Sources/NXLibrary/ViewModels/AppViewModel.swift"), encoding: .utf8)
        XCTAssertNotNil(viewModel.range(of: #"public let pinnedEngineCommit = "[0-9a-f]{40}""#, options: .regularExpression))
        let script = try String(contentsOf: root.appendingPathComponent("scripts/release.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("nxlibrary-requires"))
    }

    func testParseReleaseWithoutAssetIsNil() {
        let json = #"{"tag_name": "v0.3.0", "body": "", "assets": [{"name": "Other.zip", "browser_download_url": "https://e.com/o.zip"}]}"#
        XCTAssertNil(AppUpdate.parseRelease(Data(json.utf8)))
        XCTAssertNil(AppUpdate.parseRelease(Data("not json".utf8)))
    }

    func testDigestMatchMismatchMissing() throws {
        let file = dir.appendingPathComponent("a.zip")
        try Data("hello".utf8).write(to: file)
        let sha = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        XCTAssertEqual(AppUpdate.checkDigest(file, expected: "sha256:" + sha), .match)
        XCTAssertEqual(AppUpdate.checkDigest(file, expected: "sha256:" + String(repeating: "0", count: 64)), .mismatch)
        XCTAssertEqual(AppUpdate.checkDigest(file, expected: nil), .missing)
        XCTAssertEqual(AppUpdate.checkDigest(file, expected: "md5:abc"), .missing)
    }

    func testBundleChecks() throws {
        let good = try makeApp("Good.app")
        XCTAssertNil(AppUpdate.bundleProblem(good, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os))
        let other = try makeApp("Other.app", id: "com.example")
        XCTAssertEqual(AppUpdate.bundleProblem(other, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os),
                       .wrongIdentifier)
        let noExe = try makeApp("NoExe.app", executable: false)
        XCTAssertEqual(AppUpdate.bundleProblem(noExe, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os),
                       .noExecutable)
        XCTAssertEqual(AppUpdate.bundleProblem(good, expectedID: "local.nxlibrary", version: "0.3.0", runningOS: os),
                       .wrongVersion)
        let future = try makeApp("Future.app", minimumOS: "28.0")
        XCTAssertEqual(AppUpdate.bundleProblem(future, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os),
                       .needsNewerMacOS("28.0"))
        XCTAssertEqual(AppUpdate.bundleProblem(dir.appendingPathComponent("Missing.app"), expectedID: "local.nxlibrary",
                                               version: "0.2.0", runningOS: os), .noInfo)
    }

    func testBundleWithoutMarkerIsRefused() throws {
        let dev = try makeApp("Dev.app", release: false)
        XCTAssertEqual(AppUpdate.bundleProblem(dev, expectedID: "local.nxlibrary", version: "0.2.0", runningOS: os),
                       .notRelease)
    }

    func testInstallabilityDeveloperWithoutMarker() throws {
        XCTAssertEqual(AppUpdate.installability(try makeApp("Dev.app", release: false)), .developer)
        XCTAssertEqual(AppUpdate.installability(try makeApp("Rel.app")), .ok)
        XCTAssertEqual(AppUpdate.installability(dir.appendingPathComponent("bare-binary")), .developer)
    }

    func testInstallabilityReadOnlyFolder() throws {
        let folder = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = try makeApp(in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        XCTAssertEqual(AppUpdate.installability(app), .readOnly)
    }

    func testSwapReplacesAndKeepsName() throws {
        let installed = dir.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let current = try makeApp(in: installed, version: "0.1.0", marker: "old")
        let stagedFolder = dir.appendingPathComponent("staged")
        try FileManager.default.createDirectory(at: stagedFolder, withIntermediateDirectories: true)
        let staged = try makeApp(in: stagedFolder, version: "0.2.0", marker: "new")
        let placed = try AppUpdate.install(staged, over: current, trashOld: false)
        XCTAssertEqual(placed.standardizedFileURL, current.standardizedFileURL)
        let exe = try String(contentsOf: current.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8)
        XCTAssertTrue(exe.contains("new"))
        let left = try FileManager.default.contentsOfDirectory(atPath: installed.path)
        XCTAssertEqual(left, ["NXLibrary.app"], "no (new) or (old) copy left behind")
    }

    func testSwapFailureKeepsCurrent() throws {
        let current = try makeApp(version: "0.1.0", marker: "old")
        XCTAssertThrowsError(try AppUpdate.install(dir.appendingPathComponent("gone/NXLibrary.app"), over: current,
                                                   trashOld: false))
        let exe = try String(contentsOf: current.appendingPathComponent("Contents/MacOS/NXLibrary"), encoding: .utf8)
        XCTAssertTrue(exe.contains("old"))
    }

    func testLaterIsPerVersion() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let hourAgo = now.addingTimeInterval(-3600)
        XCTAssertFalse(AppUpdate.shouldOffer("0.2.0", laterVersion: "0.2.0", laterAt: hourAgo, now: now))
        XCTAssertTrue(AppUpdate.shouldOffer("0.2.1", laterVersion: "0.2.0", laterAt: hourAgo, now: now))
        XCTAssertTrue(AppUpdate.shouldOffer("0.2.0", laterVersion: "0.2.0", laterAt: now.addingTimeInterval(-25 * 3600), now: now))
        XCTAssertTrue(AppUpdate.shouldOffer("0.2.0", laterVersion: nil, laterAt: nil, now: now))
    }

    func testCheckEvery24Hours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(AppUpdate.shouldCheck(lastCheck: nil, now: now))
        XCTAssertFalse(AppUpdate.shouldCheck(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(AppUpdate.shouldCheck(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
    }

    func testRepositoryOverride() throws {
        let suite = "AppUpdateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppUpdate.repository(defaults: defaults), AppUpdate.defaultRepository)
        defaults.set("someone/NXLibrary", forKey: AppUpdate.repositoryOverrideKey)
        XCTAssertEqual(AppUpdate.repository(defaults: defaults), "someone/NXLibrary")
        defaults.set("not a repo", forKey: AppUpdate.repositoryOverrideKey)
        XCTAssertEqual(AppUpdate.repository(defaults: defaults), AppUpdate.defaultRepository)
    }
}
