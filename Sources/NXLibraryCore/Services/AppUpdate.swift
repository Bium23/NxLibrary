// Adapted from NX2Apple's AppUpdate.swift (https://github.com/LNPANDY/NX2Apple), MIT License,
// Copyright (c) 2026 LNPANDY and NX2Apple contributors. See NOTICE.

import Foundation
import CryptoKit

/// The rules of NX Library's self-update: which release, what may be installed, which copy may
/// replace itself, and the swap. Everything works on paths it is given, so the tests run it on
/// bundles in a temporary folder, never on the running app or the network.
///
/// - What is installed is what GitHub says the release is: the zip's SHA-256 matches the asset's
///   `digest`, and the app inside carries this app's bundle identifier, an executable, the
///   release's version and the release marker.
/// - Only a release copy (`NXLibraryRelease` in its Info.plist, written by scripts/release.sh)
///   replaces itself; a developer's `build_app.sh` build never does.
/// - A failure anywhere leaves a working app where it was.
public enum AppUpdate {
    /// Public release source. Development copies still never replace themselves.
    public static let defaultRepository: String? = "Bium23/NxLibrary"
    /// A UserDefaults override of `defaultRepository`, for testing before publishing.
    public static let repositoryOverrideKey = "NXLibrary_UpdateRepository"
    /// The Info.plist key that marks a release copy.
    public static let releaseMarker = "NXLibraryRelease"
    static let interval: TimeInterval = 24 * 3600
    public static let maximumDownloadBytes: Int64 = 512 * 1024 * 1024

    /// The version as Settings shows it: a copy without the release marker is a development build
    /// of the version in progress, so it never reads like a published release.
    public static func versionLabel(_ info: [String: Any]?) -> String {
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        if info?[releaseMarker] as? Bool == true { return short }
        if info?["NXLibraryDevelopmentProfile"] as? Bool == true { return "\(short) (Dev · Launcher)" }
        return "\(short) (development build)"
    }

    public static func repository(defaults: UserDefaults = AppData.preferences) -> String? {
        if let value = defaults.string(forKey: repositoryOverrideKey)?.trimmingCharacters(in: .whitespaces),
           value.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return defaultRepository
    }

    // MARK: - The release

    public struct Release: Equatable, Sendable {
        public var tag: String
        public var version: String
        /// The notes as shown, without the requirements line.
        public var notes: String
        public var zipURL: URL
        /// "sha256:<hex>"; nil when GitHub gave none.
        public var digest: String?
        public var archiveBytes: Int64
        public var requirements = Requirements()
    }

    /// What a release needs on this Mac, from a hidden line scripts/release.sh adds to its notes.
    public struct Requirements: Equatable, Sendable {
        public var minimumXcode: String?
        public var engineCommit: String?

        public init(minimumXcode: String? = nil, engineCommit: String? = nil) {
            self.minimumXcode = minimumXcode
            self.engineCommit = engineCommit
        }
    }

    static let requirementsMarker = "nxlibrary-requires"

    /// "<!-- nxlibrary-requires xcode=27.1 engine=<commit> -->", the line scripts/release.sh writes.
    public static func requirementsLine(minimumXcode: String, engineCommit: String) -> String {
        "<!-- \(requirementsMarker) xcode=\(minimumXcode) engine=\(engineCommit) -->"
    }

    /// The requirements line's values, and the notes without it.
    public static func requirements(in notes: String) -> (Requirements, String) {
        guard let range = notes.range(of: #"<!--\s*nxlibrary-requires\s+([^>]*?)\s*-->"#, options: .regularExpression)
        else { return (Requirements(), notes.trimmingCharacters(in: .whitespacesAndNewlines)) }
        var requirements = Requirements()
        let body = notes[range].dropFirst(4).dropLast(3)
        for pair in body.split(whereSeparator: \.isWhitespace) {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "xcode": requirements.minimumXcode = parts[1]
            case "engine": requirements.engineCommit = parts[1]
            default: break
            }
        }
        var shown = notes
        shown.removeSubrange(range)
        return (requirements, shown.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The Xcode version this Mac must update to for new portings with the release; nil when it has it (or has
    /// none, the Setup check's job).
    public static func neededXcode(_ requirements: Requirements, installedXcode: String?) -> String? {
        guard let minimum = requirements.minimumXcode, let installed = installedXcode,
              VersionNumber.isOlder(installed, than: minimum) else { return nil }
        return minimum
    }

    /// What the update dialog says before installing: an Xcode this Mac must update first (new portings wait for
    /// it), and a new engine that Setup brings after the restart.
    public static func requirementNotes(_ requirements: Requirements, installedXcode: String?,
                                        currentEngine: String) -> [String] {
        var notes: [String] = []
        if let minimum = neededXcode(requirements, installedXcode: installedXcode), let installed = installedXcode {
            notes.append("New portings need Xcode \(minimum); this Mac has \(installed). Update Xcode from the App Store first. Your games keep playing.")
        }
        if let engine = requirements.engineCommit, !engine.isEmpty, engine != currentEngine {
            notes.append("It comes with nxnative \(engine.prefix(7)): after the restart, Setup downloads it in one step.")
        }
        return notes
    }

    /// GitHub's `releases/latest` answer, with the asset named `NXLibrary-<version>.zip`.
    public static func parseRelease(_ json: Data, repository: String = "Bium23/NxLibrary") -> Release? {
        guard json.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tag = object["tag_name"] as? String, let version = version(fromTag: tag),
              let assets = object["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == "NXLibrary-\(version).zip" }),
              let link = asset["browser_download_url"] as? String, let url = URL(string: link),
              trustedDownloadURL(url), url.host?.lowercased() == "github.com",
              url.path == "/\(repository)/releases/download/\(tag)/NXLibrary-\(version).zip",
              url.query == nil, url.fragment == nil,
              let bytes = asset["size"] as? Int64, bytes > 0, bytes <= maximumDownloadBytes,
              let digest = asset["digest"] as? String,
              digest.range(of: #"^sha256:[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil
        else { return nil }
        let (requirements, notes) = requirements(in: object["body"] as? String ?? "")
        return Release(tag: tag, version: version, notes: notes, zipURL: url, digest: digest, archiveBytes: bytes,
                       requirements: requirements)
    }

    /// GitHub's release redirect stays within its HTTPS download infrastructure.
    public static func trustedDownloadURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
            && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"]
                .contains(url.host?.lowercased() ?? "")
    }

    public static func downloadWithinLimit(received: Int64, expected: Int64) -> Bool {
        expected > 0 && expected <= maximumDownloadBytes && received >= 0 && received <= expected
    }

    /// Validate the sealed bundle before it can replace the installed copy.
    public static func validCodeSignature(_ app: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", app.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }

    /// "v1.2.3" or "1.2.3" → "1.2.3"; nil when it is not dotted numbers.
    public static func version(fromTag tag: String) -> String? {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return numbers(version) == nil ? nil : version
    }

    private static func numbers(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        let values = parts.map { part in part.allSatisfy(\.isASCII) ? Int(part) : nil }
        return values.contains(where: { $0 == nil || $0! < 0 }) ? nil : values.map { $0! }
    }

    /// Field by field, a missing field counting as 0: "0.10.0" is newer than "0.9.3", "0.2" equals "0.2.0".
    public static func isNewer(_ candidate: String, than running: String) -> Bool {
        guard let a = numbers(candidate), let b = numbers(running) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - When

    public static func shouldCheck(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// Later hides one version for 24 hours; a newer version is offered at once.
    public static func shouldOffer(_ version: String, laterVersion: String?, laterAt: Date?, now: Date) -> Bool {
        guard laterVersion == version, let laterAt else { return true }
        return now.timeIntervalSince(laterAt) >= interval
    }

    // MARK: - What was downloaded

    public enum DigestCheck: Equatable { case match, mismatch, missing }

    /// The SHA-256 of a file as lowercase hex, read in pieces.
    static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A digest in another algorithm, or none, is missing: there is nothing to compare with.
    public static func checkDigest(_ file: URL, expected: String?) -> DigestCheck {
        guard let expected, expected.lowercased().hasPrefix("sha256:") else { return .missing }
        let want = expected.dropFirst("sha256:".count).trimmingCharacters(in: .whitespaces).lowercased()
        guard want.count == 64, let have = sha256(of: file) else { return want.isEmpty ? .missing : .mismatch }
        return have == want ? .match : .mismatch
    }

    public enum BundleProblem: Error, Equatable {
        case noInfo, wrongIdentifier, noExecutable, wrongVersion, notRelease
        case needsNewerMacOS(String)
    }

    private static func info(_ app: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// Whether `app` is NX Library `version` as a release copy that opens on `runningOS`.
    public static func bundleProblem(_ app: URL, expectedID: String, version: String,
                                     runningOS: OperatingSystemVersion) -> BundleProblem? {
        guard let info = info(app) else { return .noInfo }
        guard !expectedID.isEmpty, info["CFBundleIdentifier"] as? String == expectedID else { return .wrongIdentifier }
        guard let exe = info["CFBundleExecutable"] as? String, !exe.isEmpty, !exe.contains("/"),
              FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/" + exe).path)
        else { return .noExecutable }
        guard info["CFBundleShortVersionString"] as? String == version else { return .wrongVersion }
        guard info[releaseMarker] as? Bool == true, info["NXLibraryDevelopmentProfile"] as? Bool != true else { return .notRelease }
        if let text = info["LSMinimumSystemVersion"] as? String, let minimum = numbers(text) {
            let running = [runningOS.majorVersion, runningOS.minorVersion, runningOS.patchVersion]
            let padded = minimum + Array(repeating: 0, count: max(0, 3 - minimum.count))
            if running.lexicographicallyPrecedes(padded.prefix(3)) { return .needsNewerMacOS(text) }
        }
        return nil
    }

    // MARK: - Which copy may replace itself

    public enum Installability: Equatable {
        case ok
        /// Not a release copy: a developer's build never replaces itself.
        case developer
        /// A release copy that cannot be replaced where it is (App Translocation, a read-only folder).
        case readOnly
    }

    public static func installability(_ bundle: URL) -> Installability {
        guard bundle.pathExtension == "app", let metadata = info(bundle), metadata[releaseMarker] as? Bool == true, metadata["NXLibraryDevelopmentProfile"] as? Bool != true else { return .developer }
        let standardized = bundle.standardizedFileURL
        if standardized.path.contains("/AppTranslocation/") { return .readOnly }
        if !FileManager.default.isWritableFile(atPath: standardized.deletingLastPathComponent().path) { return .readOnly }
        return .ok
    }

    // MARK: - The swap

    public enum InstallError: Error, Equatable { case failed(String) }

    /// Copies `staged` beside `current`, then exchanges the two in one replace, so a failure
    /// anywhere leaves a working app at `current`. The old copy goes to the Trash (`trashOld`; the
    /// tests remove it), and the new one loses the quarantine flag (releases are ad-hoc signed).
    @discardableResult
    public static func install(_ staged: URL, over current: URL, trashOld: Bool = true) throws -> URL {
        let fm = FileManager.default
        let folder = current.deletingLastPathComponent()
        let name = current.deletingPathExtension().lastPathComponent
        let incoming = folder.appendingPathComponent(name + " (new).app")
        let backupName = name + " (old).app"
        let backup = folder.appendingPathComponent(backupName)
        try? fm.removeItem(at: incoming)
        try? fm.removeItem(at: backup)
        do {
            try fm.copyItem(at: staged, to: incoming)
            let placed = try fm.replaceItemAt(current, withItemAt: incoming, backupItemName: backupName,
                                              options: [.withoutDeletingBackupItem])
            if fm.fileExists(atPath: backup.path) {
                if trashOld { try? fm.trashItem(at: backup, resultingItemURL: nil) } else { try? fm.removeItem(at: backup) }
            }
            clearQuarantine(placed ?? current)
            return placed ?? current
        } catch {
            try? fm.removeItem(at: incoming)
            throw InstallError.failed(error.localizedDescription)
        }
    }

    /// Waits until `$1` (a pid) has exited, at most `$3` ticks of 0.2 s, then opens `$2` with `$4`.
    /// The paths arrive as arguments, never spliced into the script.
    static let relaunchScript = """
        n=0
        while kill -0 "$1" 2>/dev/null && [ "$n" -lt "$3" ]; do sleep 0.2; n=$((n+1)); done
        sleep 0.5
        exec "$4" "$2"
        """

    /// Starts the new copy once this one is gone (LaunchServices would only activate the running
    /// instance of the same bundle id). The caller terminates the app right after.
    @discardableResult
    public static func relaunch(_ app: URL, afterExitOf pid: Int32 = ProcessInfo.processInfo.processIdentifier,
                                timeout: TimeInterval = 30, opener: String = "/usr/bin/open") -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", relaunchScript, "sh", String(pid), app.path, String(Int(timeout / 0.2)), opener]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); return true } catch { return false }
    }

    private static func clearQuarantine(_ app: URL) {
        let x = Process()
        x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        x.arguments = ["-dr", "com.apple.quarantine", app.path]
        x.standardOutput = FileHandle.nullDevice
        x.standardError = FileHandle.nullDevice
        try? x.run()
        x.waitUntilExit()
    }
}
