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

public enum EngineSourceError: Error, Equatable, LocalizedError {
    case invalidPackage, invalidDump(String), invalidContainer(String), containerNotAlone, missingProfile(String)
    /// The engine's own reason, such as keys that cannot open the packages (it names the missing key, never a value).
    case unreadablePackages(String)
    case unreadablePackage(String)
    public var errorDescription: String? {
        switch self {
        case .invalidPackage: return L10n.text("The package contents could not be read. Check the files and imported keys.")
        case .unreadablePackages(let detail): return "The packages could not be read: \(detail)"
        case .unreadablePackage(let detail): return "This package could not be read: \(detail)"
        case .invalidDump(let detail): return "The extracted folder is incomplete: \(detail)."
        case .invalidContainer(let detail): return "The NUP file could not be read: \(detail)."
        case .containerNotAlone: return L10n.text("Choose one NUP file on its own: it holds the whole game.")
        case .missingProfile(let title): return "The selected engine has no registered profile for \(title). With this engine, extracted folders and NUP files need a registered profile."
        }
    }
}

/// Capabilities are read from the selected engine, not inferred from a newer hash.
public struct EngineSourceCapabilities {
    public let titleSelection: Bool
    public let extractedFolders: Bool
    /// Builds from a `.nup` file (scripts/pack_nup.py).
    public let nupContainers: Bool
    /// A NUP or an extracted folder of a game with no registered profile gets a provisional one, as an NSP does
    /// (nxnative 056e41fe: survey_nup, survey_dump). Before it, such a game is refused.
    public let provisionalNUP: Bool
    public let provisionalDumps: Bool
    public init(repo: URL) {
        let text = (try? String(contentsOf: repo.appendingPathComponent("scripts/build_ipa_from_nsp.py"), encoding: .utf8)) ?? ""
        self.init(script: text)
    }

    init(script text: String) {
        titleSelection = text.contains("'--title-id'") || text.contains("\"--title-id\"")
        extractedFolders = text.contains("import pack_dump") && titleSelection
        nupContainers = text.contains("import pack_nup") && titleSelection
        provisionalNUP = nupContainers && text.contains("survey_nup")
        provisionalDumps = extractedFolders && text.contains("survey_dump")
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

    /// Every package's content metas, read the way the engine reads them for the build, so the title IDs and versions NX
    /// Library shows and packs (`-p`) are the engine's. nxnative 5c4dc18f reads all packages in one `package_reader` run and
    /// never trusts a file name; older engines read one package at a time, and only merged or unidentified ones (an
    /// identified one comes back with no rows: NX Library's own reading stands). A package the engine cannot read comes
    /// back unreadable with its reason; a run that stops (keys that cannot open the packages) throws the engine's line.
    public func contents(of packages: [(url: URL, alreadyIdentified: Bool)]) throws -> [URL: PackageReading] {
        guard !packages.isEmpty else { return [:] }
        let script = #"""
import contextlib, importlib.util, io, json, os, sys
from pathlib import Path
repo, keys = Path(sys.argv[1]), Path(sys.argv[2])
packages = [(Path(p), known) for p, known in json.loads(sys.argv[3])]
spec = importlib.util.spec_from_file_location('nxlibrary_probe', repo / 'scripts/build_ipa_from_nsp.py')
engine = importlib.util.module_from_spec(spec)
try:
    with contextlib.redirect_stdout(io.StringIO()):
        spec.loader.exec_module(engine)
        environment = dict(os.environ)
        if hasattr(engine, 'configure_dotnet'):   # engines before nxnative 641636e2 (.NET tools)
            engine.configure_dotnet(environment)
        if hasattr(engine, 'package_reader'):
            with engine.package_reader(repo, keys, environment) as reader:
                found = reader.contents([p for p, _ in packages])
            results = [found.get(p, 'not listed by the engine') for p, _ in packages]
        else:
            results = [[] for _ in packages]
            todo = [i for i, (p, known) in enumerate(packages) if not known or engine.is_merged(p)]
            if todo:
                with engine.package_title_reader(repo, keys, environment) as reader:
                    for i in todo: results[i] = reader.contents(packages[i][0]) or 'no content meta'
except Exception as e:
    sys.exit(' '.join(str(e).split()) or type(e).__name__)
for i, rows in enumerate(results):
    print(f'package {i}')
    if isinstance(rows, str):
        print('unreadable ' + ' '.join(rows.split()))
        continue
    for kind, title, version in rows:
        print(f'content {kind} {title:016X} {version}')
"""#
        let list = packages.map { [$0.url.path, $0.alreadyIdentified] as [Any] }
        let json = String(data: try JSONSerialization.data(withJSONObject: list), encoding: .utf8) ?? "[]"
        let environment = toolchain.environment(base: ProcessInfo.processInfo.environment, developerDir: developerDir)
        let result = try runner.run(toolchain.python, ["-B", "-c", script, repo.path, keys.path, json],
                                    environment: environment, currentDirectory: repo)
        guard result.status == 0 else {
            let line = result.stderr.split(separator: "\n").last.map { String($0).trimmingCharacters(in: .whitespaces) }
            throw line.map { EngineSourceError.unreadablePackages($0) } ?? EngineSourceError.invalidPackage
        }
        return try PackageReading.parse(result.stdout, packages: packages.map(\.url))
    }
}

/// What the engine read in one package.
public enum PackageReading: Equatable {
    case contents([PackageContent])
    case unreadable(String)

    /// The probe's output: `package <index>`, then that package's `content` lines or one `unreadable <why>` line.
    static func parse(_ output: String, packages: [URL]) throws -> [URL: PackageReading] {
        var blocks: [Int: [Substring]] = [:]
        var current: Int?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("package "), let index = Int(line.dropFirst("package ".count)), packages.indices.contains(index) {
                current = index
                blocks[index] = []
            } else if let current {
                blocks[current]?.append(line)
            }
        }
        var readings: [URL: PackageReading] = [:]
        for (index, lines) in blocks {
            if let why = lines.first(where: { $0.hasPrefix("unreadable ") }) {
                readings[packages[index]] = .unreadable(String(why.dropFirst("unreadable ".count)))
            } else {
                readings[packages[index]] = .contents(try PackageContent.parse(lines.joined(separator: "\n")))
            }
        }
        return readings
    }
}
