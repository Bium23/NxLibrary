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
    private let sourcesFolder: URL?
    private let libraryNeedsConfirmation: Bool
    private let newestEngine: NewestEngineChoice?

    public init(runner: CommandRunning, fileManager: FileManager = .default, toolchain: EngineToolchain,
                developerDir: URL?, engineFolder: URL, pinnedCommit: String, certifiedMetal: String,
                allowUntested: Bool, keyStore: KeyStore, libraryFolder: URL?,
                sourcesFolder: URL? = nil, libraryNeedsConfirmation: Bool = false,
                newestEngine: NewestEngineChoice? = nil) {
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
        self.sourcesFolder = sourcesFolder
        self.libraryNeedsConfirmation = libraryNeedsConfirmation
        self.newestEngine = newestEngine
    }

    public func facts() -> SetupFacts {
        var keys: KeySummary?
        var keysError: String?
        if fileManager.fileExists(atPath: keyStore.keyURL.path) {
            do { keys = try keyStore.validate(at: keyStore.keyURL) } catch { keysError = error.localizedDescription }
        }
        let xcode = xcode()
        let engine = engine()
        var facts = SetupFacts(
            xcodeStatus: xcode.status,
            metalVersion: MetalVersion.parse(run("/usr/bin/xcrun", ["metal", "--version"]).stdout),
            certifiedMetal: certifiedMetal, allowUntested: allowUntested,
            dotnetSDKs: run("/usr/bin/env", ["dotnet", "--list-sdks"]).stdout
                .split(separator: "\n").map(String.init).filter { !$0.isEmpty },
            engine: engine, engineFolder: engineFolder, pinnedCommit: pinnedCommit,
            runtimeProblem: runtimeProblem(),
            keys: keys, keysError: keysError,
            libraryReadable: libraryFolder.map { readableDirectory($0) },
            xcodeVersion: xcode.version, engineBehind: behind(engine))
        let capabilities = EngineSourceCapabilities(repo: engineFolder)
        facts.keysOptional = capabilities.extractedFolders
        facts.libraryFolder = libraryFolder
        facts.libraryWritable = libraryFolder.map { GameAppDestination.folderProblem(at: $0) == nil }
        facts.libraryNeedsConfirmation = libraryNeedsConfirmation
        facts.newestEngine = newestEngine
        facts.sourcesFolder = sourcesFolder
        facts.sourcesReadable = sourcesFolder.map { readableDirectory($0) }
        facts.extractedFoldersSupported = capabilities.extractedFolders
        return facts
    }

    private func readableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue && fileManager.isReadableFile(atPath: url.path)
    }

    /// Whether the checkout's HEAD is an ancestor of the pin (`git merge-base --is-ancestor`); nil when git cannot
    /// tell, as when the pin is not fetched yet.
    private func behind(_ engine: EngineFacts) -> Bool? {
        guard case .checkout(let head, _) = engine, head != pinnedCommit else { return nil }
        switch run("/usr/bin/git", ["-C", engineFolder.path, "merge-base", "--is-ancestor", head, pinnedCommit]).status {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }

    private func run(_ executable: String, _ args: [String], in directory: URL? = nil) -> CommandResult {
        let env = toolchain.environment(base: ProcessInfo.processInfo.environment, developerDir: developerDir)
        return (try? runner.run(URL(fileURLWithPath: executable), args, environment: env, currentDirectory: directory))
            ?? CommandResult(status: -1, stdout: "", stderr: "failed")
    }

    private func xcode() -> (status: Int32?, version: String?) {
        if let developerDir, !fileManager.fileExists(atPath: developerDir.path) { return (nil, nil) }
        let result = run("/usr/bin/xcodebuild", ["-version"])
        // 69 (EX_UNAVAILABLE) is xcodebuild's answer before the licence is accepted.
        guard result.status == 0 || result.status == 69 else { return (nil, nil) }
        return (result.status, ToolchainRequirements.xcodeVersion(from: result.stdout))
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
        // -I ignores PYTHONDONTWRITEBYTECODE; -B keeps __pycache__ out of a bundled runtime,
        // whose new files would break the app's code signature.
        let modules = run(toolchain.python.path,
                          ["-I", "-B", "-c", "import capstone, lz4.block, fontTools, zbic; assert capstone.cs_version()[0] == 5"])
        if modules.status != 0 { return "Python or its modules (capstone 5, lz4, fontTools, zbic) did not start" }
        for tool in ["zstd", "glslangValidator"] where run("/usr/bin/env", [tool, "--version"]).status != 0 {
            return "\(tool) did not run"
        }
        return nil
    }
}
