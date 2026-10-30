import Foundation

/// Gathers what the Setup check shows. Every command is cheap, so the screen can
/// run it every few seconds off the main thread.
public struct SetupProbe {
    private let runner: CommandRunning
    private let fileManager: FileManager
    private let toolchain: EngineToolchain
    private let developerDir: URL?
    private let engineFolder: URL
    private let pinnedCommit: String
    private let certifiedMetal: String
    private let allowUntested: Bool
    private let keyStore: KeyStore
    private let libraryFolder: URL?

    public init(runner: CommandRunning, fileManager: FileManager = .default, toolchain: EngineToolchain,
                developerDir: URL?, engineFolder: URL, pinnedCommit: String, certifiedMetal: String,
                allowUntested: Bool, keyStore: KeyStore, libraryFolder: URL?) {
        self.runner = runner
        self.fileManager = fileManager
        self.toolchain = toolchain
        self.developerDir = developerDir
        self.engineFolder = engineFolder
        self.pinnedCommit = pinnedCommit
        self.certifiedMetal = certifiedMetal
        self.allowUntested = allowUntested
        self.keyStore = keyStore
        self.libraryFolder = libraryFolder
    }

    public func facts() -> SetupFacts {
        var keys: KeySummary?
        var keysError: String?
        if fileManager.fileExists(atPath: keyStore.keyURL.path) {
            do { keys = try keyStore.validate(at: keyStore.keyURL) } catch { keysError = error.localizedDescription }
        }
        return SetupFacts(
            xcodeStatus: xcodeStatus(),
            metalVersion: MetalVersion.parse(run("/usr/bin/xcrun", ["metal", "--version"]).stdout),
            certifiedMetal: certifiedMetal, allowUntested: allowUntested,
            dotnetSDKs: run("/usr/bin/env", ["dotnet", "--list-sdks"]).stdout
                .split(separator: "\n").map(String.init).filter { !$0.isEmpty },
            engine: engine(), engineFolder: engineFolder, pinnedCommit: pinnedCommit,
            runtimeProblem: runtimeProblem(),
            keys: keys, keysError: keysError,
            libraryWritable: libraryFolder.map { fileManager.isWritableFile(atPath: $0.path) })
    }

    private func run(_ executable: String, _ args: [String], in directory: URL? = nil) -> CommandResult {
        let env = toolchain.environment(base: ProcessInfo.processInfo.environment, developerDir: developerDir)
        return (try? runner.run(URL(fileURLWithPath: executable), args, environment: env, currentDirectory: directory))
            ?? CommandResult(status: -1, stdout: "", stderr: "failed")
    }

    private func xcodeStatus() -> Int32? {
        if let developerDir, !fileManager.fileExists(atPath: developerDir.path) { return nil }
        let status = run("/usr/bin/xcodebuild", ["-version"]).status
        // 69 (EX_UNAVAILABLE) is xcodebuild's answer before the licence is accepted.
        return status == 0 || status == 69 ? status : nil
    }

    private func engine() -> EngineFacts {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: engineFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }
        guard fileManager.fileExists(atPath: engineFolder.appendingPathComponent(".git").path) else {
            return .notACheckout
        }
        let head = run("/usr/bin/git", ["-C", engineFolder.path, "rev-parse", "HEAD"])
        guard head.status == 0 else { return .notACheckout }
        let status = run("/usr/bin/git", ["-C", engineFolder.path, "status", "--porcelain"]).stdout
        return .checkout(head: head.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                         dirty: !CompatibilityChecker.relevantChanges(status).isEmpty)
    }

    private func runtimeProblem() -> String? {
        let modules = run(toolchain.python.path,
                          ["-I", "-c", "import capstone, lz4.block, fontTools; assert capstone.cs_version()[0] == 5"])
        if modules.status != 0 { return "Python or its modules (capstone 5, lz4, fontTools) did not start" }
        for tool in ["zstd", "glslangValidator"] where run("/usr/bin/env", [tool, "--version"]).status != 0 {
            return "\(tool) did not run"
        }
        return nil
    }
}
