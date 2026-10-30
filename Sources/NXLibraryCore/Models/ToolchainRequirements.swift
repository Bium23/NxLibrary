import Foundation

/// What this NX Library is tested with, in one place. An upgrade edits this
/// table (and `AppViewModel.pinnedEngineCommit`), never the Setup check's code.
public struct ToolchainRequirements: Equatable {
    /// The oldest Xcode the engine's Metal toolchain runs with.
    public var minimumXcode: String
    /// The .NET SDK major the engine's extractor builds with; any patch of it works.
    public var dotnetMajor: Int
    /// The certified Metal compiler before an engine exists to name one in its lock.
    public var fallbackMetal: String
    /// Metal compiler version → Apple's MetalToolchain asset build, so NX Library can
    /// download exactly the compiler the engine certifies, not just the newest one.
    public var metalAssets: [String: String]

    public init(minimumXcode: String, dotnetMajor: Int, fallbackMetal: String, metalAssets: [String: String]) {
        self.minimumXcode = minimumXcode
        self.dotnetMajor = dotnetMajor
        self.fallbackMetal = fallbackMetal
        self.metalAssets = metalAssets
    }

    public static let current = ToolchainRequirements(
        minimumXcode: "27.1",
        dotnetMajor: 10,
        fallbackMetal: "32023.921",
        metalAssets: ["32023.921": "27A266a"])

    /// For /usr/bin/xcodebuild: whatever Metal toolchain matches this Xcode.
    public static let anyMetalDownload = ["-downloadComponent", "MetalToolchain"]

    /// For /usr/bin/xcodebuild: the asset that carries `metal`; nil when the table does not know it.
    public func metalDownload(for metal: String) -> [String]? {
        metalAssets[metal].map { Self.anyMetalDownload + ["-buildVersion", $0] }
    }

    /// "Xcode 27.1\nBuild version …" → "27.1".
    public static func xcodeVersion(from text: String) -> String? {
        guard let line = text.split(separator: "\n").first, line.hasPrefix("Xcode ") else { return nil }
        return String(line.dropFirst("Xcode ".count)).trimmingCharacters(in: .whitespaces)
    }

    /// The newest SDK of `major` in `dotnet --list-sdks` output.
    public static func newestSDK(major: Int, in lines: [String]) -> String? {
        lines.compactMap { $0.split(separator: " ").first.map(String.init) }
            .filter { $0.hasPrefix("\(major).") }
            .max { VersionNumber.isOlder($0, than: $1) }
    }
}

public enum VersionNumber {
    /// Dotted numbers compared part by part; a missing part counts as 0.
    public static func isOlder(_ a: String, than b: String) -> Bool {
        let left = parts(a), right = parts(b)
        for i in 0..<max(left.count, right.count) {
            let x = i < left.count ? left[i] : 0
            let y = i < right.count ? right[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
