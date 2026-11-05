import Foundation

public struct PackageContent: Equatable {
    public var kind: SourceKind
    public var titleId: UInt64
    public var version: Int?

    public init(kind: SourceKind, titleId: UInt64, version: Int?) {
        self.kind = kind; self.titleId = titleId; self.version = version
    }

    public static func parse(_ output: String) throws -> [PackageContent] {
        try output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "content" else { return nil }
            let kinds: [String: SourceKind] = ["Application": .base, "Patch": .update, "AddOnContent": .dlc]
            guard fields.count == 4, fields[2].count == 16,
                  let title = UInt64(fields[2], radix: 16), title != 0,
                  let version = Int(fields[3]), version >= 0 else { throw EngineSourceError.invalidPackage }
            guard let kind = kinds[String(fields[1])] else { return nil }
            guard SourceCatalog.classify(titleId: title) == kind else { throw EngineSourceError.invalidPackage }
            return PackageContent(kind: kind, titleId: title, version: version)
        }
    }
}

public enum EngineSourceError: Error, LocalizedError {
    case invalidPackage, invalidDump(String), invalidContainer(String), containerNotAlone, missingProfile(String)
    public var errorDescription: String? {
        switch self {
        case .invalidPackage: return "The package contents could not be read. Check the files and imported keys."
        case .invalidDump(let detail): return "The extracted folder is incomplete: \(detail)."
        case .invalidContainer(let detail): return "The NUP file could not be read: \(detail)."
        case .containerNotAlone: return "Choose one NUP file on its own: it holds the whole game."
        case .missingProfile(let title): return "The selected engine has no registered profile for \(title). Extracted folders and NUP files need a registered profile."
        }
    }
}

/// Capabilities are read from the selected engine, not inferred from a newer hash.
public struct EngineSourceCapabilities {
    public let titleSelection: Bool
    public let extractedFolders: Bool
    /// Builds from a `.nup` file (scripts/pack_nup.py).
    public let nupContainers: Bool
    public init(repo: URL) {
        let text = (try? String(contentsOf: repo.appendingPathComponent("scripts/build_ipa_from_nsp.py"), encoding: .utf8)) ?? ""
        titleSelection = text.contains("'--title-id'") || text.contains("\"--title-id\"")
        extractedFolders = text.contains("import pack_dump") && titleSelection
        nupContainers = text.contains("import pack_nup") && titleSelection
    }
}

/// Reuses upstream's own content-meta reader and extractor preparation. It runs
/// off the UI thread; values of keys are never passed as arguments or captured.
public struct EnginePackageReader {
    public let repo: URL
    public let toolchain: EngineToolchain
    public let keys: URL
    public let developerDir: URL
    private let runner: CommandRunning

    public init(repo: URL, toolchain: EngineToolchain, keys: URL, developerDir: URL,
                runner: CommandRunning = SystemCommandRunner()) {
        self.repo = repo; self.toolchain = toolchain; self.keys = keys
        self.developerDir = developerDir; self.runner = runner
    }

    public func contents(of package: URL, alreadyIdentified: Bool) throws -> [PackageContent] {
        let script = #"""
import contextlib, importlib.util, io, os, sys
from pathlib import Path
repo, keys, package = map(Path, sys.argv[1:4])
spec = importlib.util.spec_from_file_location('nxlibrary_probe', repo / 'scripts/build_ipa_from_nsp.py')
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
if sys.argv[4] == 'known' and not engine.is_merged(package):
    sys.exit(0)
environment = dict(os.environ)
engine.configure_dotnet(environment)
with contextlib.redirect_stdout(io.StringIO()):
    with engine.package_title_reader(repo, keys, environment) as reader:
        rows = reader.contents(package)
if not rows:
    sys.exit('Could not read package content metadata')
for kind, title, version in rows:
    print(f'content {kind} {title:016X} {version}')
"""#
        let environment = toolchain.environment(base: ProcessInfo.processInfo.environment, developerDir: developerDir)
        let result = try runner.run(toolchain.python,
            ["-B", "-c", script, repo.path, keys.path, package.path, alreadyIdentified ? "known" : "unknown"],
            environment: environment, currentDirectory: repo)
        guard result.status == 0 else { throw EngineSourceError.invalidPackage }
        return try PackageContent.parse(result.stdout)
    }
}
