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
    /// The installed Metal compiler against the engine's lock.
    public var metal: MetalStanding

    public init(ok: Bool, checks: [CompatibilityCheck], metal: MetalStanding = .unknown) {
        self.ok = ok
        self.checks = checks
        self.metal = metal
    }
}

/// The installed Metal compiler against the one the engine's lock certifies. Only `.same` passes the gate; the others
/// need the untested-toolchain override, but say different things (ToolchainGateCopy).
public enum MetalStanding: Equatable, Sendable {
    case same
    case newer(installed: String, required: String)
    case older(installed: String, required: String)
    /// No compiler, or a version that cannot be read.
    case unknown
}

public final class CompatibilityChecker {
    private let repoURL: URL
    private let toolchain: EngineToolchain
    private let developerDir: URL?
    private let runner: CommandRunning

    private var pythonURL: URL { toolchain.python }

    public init(repoURL: URL, toolchain: EngineToolchain,
                developerDir: URL?, runner: CommandRunning = SystemCommandRunner()) {
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

    /// `git status --porcelain` lines that make the engine tree dirty: build output,
    /// logs, the venv and the generated shader chain header do not count.
    public static func relevantChanges(_ porcelain: String) -> [String] {
        porcelain.split(separator: "\n").map(String.init)
            .filter { !$0.hasSuffix("dm/gfx/nvn/dmsh_chain.h") }
            .filter { !$0.contains("_build/") }
            .filter { !$0.contains(".venv/") }
            .filter { !$0.contains("/logs/") }
            .filter { !$0.hasSuffix(".DS_Store") }
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
        checks.append(.init(id: "commit", title: L10n.text("Engine commit"),
                            status: head == expectedEngineCommit ? .pass : .block,
                            detail: L10n.format("current %@, expected %@", [String(describing: (head)), String(describing: (expectedEngineCommit))])))

        let dirty = Self.relevantChanges(run("/usr/bin/git", ["status", "--porcelain"]).stdout)
        checks.append(.init(id: "tree", title: L10n.text("Working tree"),
                            status: dirty.isEmpty ? .pass : .block,
                            detail: dirty.joined(separator: "\n")))

        let metal = run("/usr/bin/xcrun", ["metal", "--version"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let required = requiredMetalVersion() ?? "unknown"
        let standing = Self.metalStanding(installed: metal, required: required)
        let installedNumber = Self.metalNumber(metal) ?? (metal.isEmpty ? "not found" : metal)
        checks.append(.init(id: "metal", title: L10n.text("Metal compiler"),
                            status: standing == .same ? .pass : .block,
                            detail: L10n.format("installed %@, tested %@", [String(describing: (installedNumber)), String(describing: (Self.metalNumber(required) ?? required))])))

        let pythonVersion = run(pythonURL.path, [
            "-c", "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"
        ]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionParts = pythonVersion.split(separator: ".").compactMap { Int($0) }
        let pythonOK = versionParts.count >= 2
            && (versionParts[0] > 3 || (versionParts[0] == 3 && versionParts[1] >= 12))
        checks.append(.init(id: "python", title: L10n.text("Python venv"),
                            status: pythonOK ? .pass : .block,
                            detail: pythonVersion.isEmpty ? L10n.text("version unavailable (requires 3.12+)")
                                                          : L10n.format("%@ (requires 3.12+)", [String(describing: (pythonVersion))])))

        let help = run(pythonURL.path, [
            repoURL.appendingPathComponent("scripts/build_ipa_from_nsp.py").path, "-h"
        ]).stdout
        let requiredFlags = ["--platform", "--progress", "-o", "-k", "--app-name", "--bundle-id"]
        let missing = requiredFlags.filter { !help.contains($0) }
        checks.append(.init(id: "cli", title: L10n.text("nxnative CLI"),
                            status: missing.isEmpty ? .pass : .block,
                            detail: missing.isEmpty ? L10n.text("required options present") : L10n.format("missing %@", [String(describing: (missing.joined(separator: ", ")))])))

        return CompatibilityReport(ok: checks.allSatisfy { $0.status != .block }, checks: checks, metal: standing)
    }

    /// The first dotted version number in `xcrun metal --version` output or a lock line ("32023.921").
    static func metalNumber(_ text: String) -> String? {
        guard let range = text.range(of: #"\d+(\.\d+)+"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    /// Compares version numbers component by component (32023.1000 is newer than 32023.921; missing parts are 0).
    public static func metalStanding(installed: String, required: String) -> MetalStanding {
        guard let have = metalNumber(installed), let need = metalNumber(required) else { return .unknown }
        let a = have.split(separator: ".").map { Int($0) ?? 0 }
        let b = need.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x > y { return .newer(installed: have, required: need) }
            if x < y { return .older(installed: have, required: need) }
        }
        return .same
    }
}
