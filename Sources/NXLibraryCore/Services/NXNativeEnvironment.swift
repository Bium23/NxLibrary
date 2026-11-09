import Foundation

public struct ToolStatus: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var ok: Bool
    public var detail: String
}

public struct EnvironmentStatus: Equatable {
    public var repoURL: URL
    public var pythonURL: URL?
    public var developerDir: URL?
    public var metalVersion: String?
    public var xcodeVersion: String?
    public var tools: [ToolStatus]
    public var issues: [String]
    public var canBuild: Bool { issues.isEmpty }
}

public enum MetalVersion {
    public static func parse(_ text: String) -> String? {
        guard let range = text.range(of: "version ") else { return nil }
        return text[range.upperBound...]
            .split(whereSeparator: { $0.isWhitespace })
            .first.map(String.init)
    }
}

public final class NXNativeEnvironment {
    public let repoURL: URL
    public let toolchain: EngineToolchain
    public let developerDir: URL?
    private let runner: CommandRunning

    public var pythonURL: URL { toolchain.python }

    public init(
        repoURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("nxnative"),
        toolchain: EngineToolchain,
        developerDir: URL? = nil,
        runner: CommandRunning = SystemCommandRunner()
    ) {
        self.repoURL = repoURL
        self.toolchain = toolchain
        self.developerDir = developerDir
        self.runner = runner
    }

    private func run(_ executable: String, _ args: [String]) -> CommandResult {
        let env = toolchain.environment(base: ProcessInfo.processInfo.environment, developerDir: developerDir)
        return (try? runner.run(URL(fileURLWithPath: executable), args,
                                environment: env, currentDirectory: repoURL))
            ?? CommandResult(status: -1, stdout: "", stderr: "failed")
    }

    private static func pythonAtLeast312(_ version: String) -> Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return parts[0] > 3 || (parts[0] == 3 && parts[1] >= 12)
    }

    public func inspect() -> EnvironmentStatus {
        var issues: [String] = []
        let fm = FileManager.default
        let script = repoURL.appendingPathComponent("scripts/build_ipa_from_nsp.py")
        let dm = repoURL.appendingPathComponent("dm")
        if !fm.fileExists(atPath: script.path) || !fm.fileExists(atPath: dm.path) {
            issues.append("nxnative repo not found at \(repoURL.path)")
        }
        if !fm.fileExists(atPath: pythonURL.path) {
            issues.append("venv Python not found at \(pythonURL.path)")
        } else {
            let version = run(pythonURL.path, ["-c", "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"])
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty, !Self.pythonAtLeast312(version) {
                issues.append("venv Python \(version) is too old; nxnative needs Python 3.12+ for RomFS image builds (3.14 recommended)")
            }
            // The engine README's packages: zbic reads system 22.0.0+ code, nsz converts NSZ / XCZ files.
            let probe = run(pythonURL.path, ["-c", "import lz4.block, capstone, fontTools, zbic, nsz\nimport sys\ntry:\n import compression.zstd\nexcept ImportError:\n import backports.zstd"])
            if probe.status != 0 {
                issues.append("Python is missing lz4/capstone/fontTools/zbic/nsz or zstd (stdlib on Python 3.14, backports.zstd before)")
            } else {
                // nxnative's rewriter needs Capstone 5.x; Capstone 6 renamed the ARM64 names it uses.
                let capstone = run(pythonURL.path, ["-c", "import capstone; print(capstone.cs_version()[0], capstone.__version__)"])
                    .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if let major = capstone.split(separator: " ").first, major != "5" {
                    let installed = capstone.split(separator: " ").dropFirst().joined()
                    issues.append("venv has Capstone \(installed); nxnative needs 5.x (pip install 'capstone>=5,<6')")
                }
            }
        }

        let xcode = run("/usr/bin/xcodebuild", ["-version"])
        let xcodeVersion = xcode.stdout.split(separator: "\n").first.map(String.init)
        if xcode.status != 0 { issues.append("xcodebuild is not available") }

        let metal = MetalVersion.parse(run("/usr/bin/xcrun", ["metal", "--version"]).stdout)
        if metal == nil { issues.append("Metal compiler not found") }

        // The engine's script runs `dotnet build` itself, so it needs the SDK, not only the runtime.
        let sdks = run("/usr/bin/env", ["dotnet", "--list-sdks"]).stdout
        let dotnetOK = sdks.split(separator: "\n").contains { $0.hasPrefix("10.") }
        if !dotnetOK { issues.append("the .NET 10 SDK is missing") }

        // A Mac build needs no xcodegen, and SPIRV-Cross is the engine's own in-repo build.
        var tools: [ToolStatus] = []
        // make builds the engine's Mac host (it comes with Xcode).
        for tool in ["zstd", "glslangValidator", "make"] {
            let result = run("/usr/bin/env", [tool, "--version"])
            let ok = result.status == 0
            tools.append(ToolStatus(id: tool, name: tool, ok: ok,
                                    detail: ok ? L10n.text("available") : L10n.text("missing")))
            if !ok { issues.append("\(tool) is missing") }
        }

        let developer = developerDir ?? URL(fileURLWithPath:
            run("/usr/bin/xcode-select", ["-p"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines))

        return EnvironmentStatus(
            repoURL: repoURL, pythonURL: pythonURL, developerDir: developer,
            metalVersion: metal, xcodeVersion: xcodeVersion,
            tools: tools, issues: issues
        )
    }
}
