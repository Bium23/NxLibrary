import Foundation

/// The Python and build tools a released NX Library carries in
/// `Contents/Resources/Runtime` (scripts/bundle_runtime.sh). Read-only: a broken
/// one is fixed by reinstalling the app, never with pip.
public struct BundledRuntime: Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var python: URL { root.appendingPathComponent("python/bin/python3") }
    public var binDirectory: URL { root.appendingPathComponent("bin") }
    public var versionsURL: URL { root.appendingPathComponent("versions.json") }

    /// What `bundle_runtime.sh` pinned, for Settings; nil when versions.json is missing.
    public func versionSummary() -> String? {
        guard let data = try? Data(contentsOf: versionsURL),
              let versions = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        let order = [("python", "Python"), ("capstone", "capstone"), ("lz4", "lz4"),
                     ("fonttools", "fonttools"), ("zbic", "zbic"), ("nsz", "nsz"), ("zstd", "zstd"), ("glslang", "glslang")]
        return order.compactMap { key, name in versions[key].map { "\(name) \($0)" } }.joined(separator: " · ")
    }

    /// The running app's runtime; nil in a developer build without one.
    public static func locate(resourceURL: URL? = Bundle.main.resourceURL,
                              fileManager: FileManager = .default) -> BundledRuntime? {
        guard let resourceURL else { return nil }
        let runtime = BundledRuntime(root: resourceURL.appendingPathComponent("Runtime"))
        return fileManager.isExecutableFile(atPath: runtime.python.path) ? runtime : nil
    }
}

/// Which Python and which PATH every engine process runs with: the bundled
/// runtime when the app has one, else the engine checkout's own `.venv`.
public struct EngineToolchain: Equatable {
    /// Where Xcode, .NET and (in a developer build) Homebrew tools live.
    public static let standardPath = "/opt/homebrew/bin:/usr/local/bin:/usr/local/share/dotnet:/usr/bin:/bin:/usr/sbin:/sbin"

    public let python: URL
    public let extraPath: [String]
    public let isBundled: Bool

    public static func resolve(runtime: BundledRuntime?, repo: URL) -> EngineToolchain {
        if let runtime {
            return EngineToolchain(python: runtime.python, extraPath: [runtime.binDirectory.path], isBundled: true)
        }
        return EngineToolchain(python: repo.appendingPathComponent(".venv/bin/python"), extraPath: [], isBundled: false)
    }

    public func environment(base: [String: String], developerDir: URL?) -> [String: String] {
        var env = base
        // Microsoft's dotnet-install script puts .NET in ~/.dotnet, which the engine also searches (its TOOL_PATHS).
        let home = (base["HOME"] ?? NSHomeDirectory()) + "/.dotnet"
        let path = (extraPath + [Self.standardPath, home]).joined(separator: ":")
        env["PATH"] = path + (base["PATH"].map { ":" + $0 } ?? "")
        if isBundled {
            // The app bundle is read-only and must not pick up the player's own packages.
            env["PYTHONNOUSERSITE"] = "1"
            env["PYTHONDONTWRITEBYTECODE"] = "1"
        }
        if let developerDir { env["DEVELOPER_DIR"] = developerDir.path }
        return env
    }
}
