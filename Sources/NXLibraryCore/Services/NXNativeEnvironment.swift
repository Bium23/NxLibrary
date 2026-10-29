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
    public let pythonURL: URL
    public let developerDir: URL?
    private let runner: CommandRunning

    public init(
        repoURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("nxnative"),
        pythonURL: URL? = nil,
        developerDir: URL? = nil,
        runner: CommandRunning = SystemCommandRunner()
    ) {
        self.repoURL = repoURL
        self.pythonURL = pythonURL ?? repoURL.appendingPathComponent(".venv/bin/python")
        self.developerDir = developerDir
        self.runner = runner
    }

    private func run(_ executable: String, _ args: [String]) -> CommandResult {
        var env = ProcessInfo.processInfo.environment
        let base = "/opt/homebrew/bin:/usr/local/bin:/usr/local/share/dotnet:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = base + ":" + (env["PATH"] ?? "")
        if let developerDir { env["DEVELOPER_DIR"] = developerDir.path }
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
            let probe = run(pythonURL.path, ["-c", "import lz4.block, capstone, fontTools\nimport sys\ntry:\n import compression.zstd\nexcept ImportError:\n import backports.zstd"])
            if probe.status != 0 { issues.append("venv is missing lz4/capstone/fontTools or zstd (stdlib on Python 3.14, backports.zstd before)") }
        }

        let xcode = run("/usr/bin/xcodebuild", ["-version"])
        let xcodeVersion = xcode.stdout.split(separator: "\n").first.map(String.init)
        if xcode.status != 0 { issues.append("xcodebuild is not available") }

        let metal = MetalVersion.parse(run("/usr/bin/xcrun", ["metal", "--version"]).stdout)
        if metal == nil { issues.append("Metal compiler not found") }

        let dotnet = run("/usr/bin/env", ["dotnet", "--list-runtimes"]).stdout
        let dotnetOK = dotnet.contains("NETCore.App 10.")
        if !dotnetOK { issues.append("the .NET 10 runtime is missing") }

        var tools: [ToolStatus] = []
        for tool in ["xcodegen", "zstd", "spirv-cross", "glslang"] {
            // spirv-cross exits 1 for --version/-h but 0 for --help.
            let flag = tool == "spirv-cross" ? "--help" : "--version"
            let result = run("/usr/bin/env", [tool, flag])
            let ok = result.status == 0
            tools.append(ToolStatus(id: tool, name: tool, ok: ok,
                                    detail: ok ? "available" : "missing"))
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
