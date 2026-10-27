import Foundation

public enum CheckStatus: String, Equatable { case pass, warn, block }

public struct CompatibilityCheck: Equatable {
    public var id: String
    public var title: String
    public var status: CheckStatus
    public var detail: String
}

public struct CompatibilityReport: Equatable {
    public var ok: Bool
    public var checks: [CompatibilityCheck]
}

public final class CompatibilityChecker {
    private let repoURL: URL
    private let pythonURL: URL
    private let developerDir: URL?
    private let runner: CommandRunning

    public init(repoURL: URL, pythonURL: URL,
                developerDir: URL?, runner: CommandRunning = SystemCommandRunner()) {
        self.repoURL = repoURL
        self.pythonURL = pythonURL
        self.developerDir = developerDir
        self.runner = runner
    }

    private func run(_ executable: String, _ args: [String]) -> CommandResult {
        var env = ProcessInfo.processInfo.environment
        if let developerDir { env["DEVELOPER_DIR"] = developerDir.path }
        return (try? runner.run(URL(fileURLWithPath: executable), args,
                                environment: env, currentDirectory: repoURL))
            ?? CommandResult(status: -1, stdout: "", stderr: "failed")
    }

    public func requiredMetalVersion() -> String? {
        let lock = repoURL.appendingPathComponent("dm/gfx/tools/dmsh_chain.lock")
        guard let text = try? String(contentsOf: lock, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("metal_macosx\t") {
            return line.split(separator: "\t").last.map(String.init)
        }
        return nil
    }

    public func check(expectedEngineCommit: String) throws -> CompatibilityReport {
        var checks: [CompatibilityCheck] = []

        let head = run("/usr/bin/git", ["rev-parse", "HEAD"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        checks.append(.init(id: "commit", title: "Engine commit",
                            status: head == expectedEngineCommit ? .pass : .block,
                            detail: "current \(head), expected \(expectedEngineCommit)"))

        let dirty = run("/usr/bin/git", ["status", "--porcelain"]).stdout
            .split(separator: "\n").map(String.init)
            .filter { !$0.hasSuffix("dm/gfx/nvn/dmsh_chain.h") }
            .filter { !$0.contains("_build/") }
            .filter { !$0.contains(".venv/") }
            .filter { !$0.contains("/logs/") }
            .filter { !$0.hasSuffix(".DS_Store") }
        checks.append(.init(id: "tree", title: "Working tree",
                            status: dirty.isEmpty ? .pass : .block,
                            detail: dirty.joined(separator: "\n")))

        let metal = run("/usr/bin/xcrun", ["metal", "--version"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let required = requiredMetalVersion() ?? "unknown"
        let metalOK = metal.contains("32023.921")
        checks.append(.init(id: "metal", title: "Metal compiler",
                            status: metalOK ? .pass : .block,
                            detail: "installed \(metal), required \(required)"))

        let pythonVersion = run(pythonURL.path, [
            "-c", "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"
        ]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionParts = pythonVersion.split(separator: ".").compactMap { Int($0) }
        let pythonOK = versionParts.count >= 2
            && (versionParts[0] > 3 || (versionParts[0] == 3 && versionParts[1] >= 12))
        checks.append(.init(id: "python", title: "Python venv",
                            status: pythonOK ? .pass : .block,
                            detail: pythonVersion.isEmpty ? "version unavailable (requires 3.12+)"
                                                          : "\(pythonVersion) (requires 3.12+)"))

        let help = run(pythonURL.path, [
            repoURL.appendingPathComponent("scripts/build_ipa_from_nsp.py").path, "-h"
        ]).stdout
        let requiredFlags = ["--platform", "--progress", "-o", "-k", "--app-name", "--bundle-id"]
        let missing = requiredFlags.filter { !help.contains($0) }
        checks.append(.init(id: "cli", title: "nxnative CLI",
                            status: missing.isEmpty ? .pass : .block,
                            detail: missing.isEmpty ? "required options present" : "missing \(missing.joined(separator: ", "))"))

        return CompatibilityReport(ok: checks.allSatisfy { $0.status != .block }, checks: checks)
    }
}
