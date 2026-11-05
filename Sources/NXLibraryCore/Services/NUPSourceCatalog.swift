import Foundation

/// A Switch 2 game in one NUP container (a `.nup` file, https://github.com/a55uka/nup): its base game, updates and
/// DLC, read by upstream's own scripts/pack_nup.py so the checks are the engine's. Reads metadata only; the file is
/// never modified. Every package shares the file, so the workspace links it once and the build packs the version
/// chosen with `--package`, with every DLC the container holds. A NUP may hold no base game (nxnative 777a5f6c):
/// then there is no v0, and the selected update is taken as the whole game.
public struct NUPSourceCatalog {
    public let repo: URL
    public let toolchain: EngineToolchain
    public let developerDir: URL
    private let runner: CommandRunning

    public init(repo: URL, toolchain: EngineToolchain, developerDir: URL,
                runner: CommandRunning = SystemCommandRunner()) {
        self.repo = repo; self.toolchain = toolchain; self.developerDir = developerDir; self.runner = runner
    }

    /// A file that starts with the NUP magic (pack_nup.is_nup).
    public static func isNUP(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "nup", !url.lastPathComponent.hasPrefix("._"),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 3)) == Data("NUP".utf8)
    }

    /// The folder's one `.nup` file, when it holds no game package beside it (build_ipa_from_nsp.nup_file).
    public static func container(in folder: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let visible = items.filter { !$0.lastPathComponent.hasPrefix("._") }
        guard !visible.contains(where: { ["nsp", "xci", "nsz", "xcz"].contains($0.pathExtension.lowercased()) }) else { return nil }
        let nups = visible.filter(isNUP)
        return nups.count == 1 ? nups[0] : nil
    }

    public func scan(nup: URL) throws -> DetectedGame {
        let script = #"""
import sys
from pathlib import Path
repo, path = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(repo / 'scripts'))
import pack_nup
try:
    with pack_nup.Nup(path) as n:
        app, base, vers, dlc = pack_nup.scan(n)
        newest = vers[max(vers)] if vers else base
        name = ''
        # No base game (nxnative 777a5f6c): the name comes from the newest update, else the metadata record.
        for k in (newest, base if base is not None else pack_nup.app_package(n)):
            if k is None: continue
            nacp = k.meta().get(pack_nup.T_NACP, b'')
            for i in range(16):
                raw = nacp[i * 0x300:i * 0x300 + 0x200].split(b'\0', 1)[0]
                if raw:
                    name = raw.decode('utf-8', 'replace'); break
            if name: break
        print(f'title {app:016X}')
        print('name ' + name.encode().hex())
        if base is not None: print(f'base {n.tree_bytes(base.root)}')
        for v, k in sorted(vers.items()): print(f'update {v} {n.tree_bytes(k.root)}')
        for t, k in sorted(dlc.items()): print(f'dlc {t:016X} {n.tree_bytes(k.root)}')
except pack_nup.Error as e:
    sys.exit(str(e))
"""#
        let environment = toolchain.environment(base: ProcessInfo.processInfo.environment, developerDir: developerDir)
        let result = try runner.run(toolchain.python, ["-B", "-c", script, repo.path, nup.path],
                                    environment: environment, currentDirectory: repo)
        guard result.status == 0 else {
            let detail = result.stderr.split(separator: "\n").last.map(String.init) ?? ""
            throw EngineSourceError.invalidContainer(detail.isEmpty ? "it could not be read" : detail)
        }
        let fileSize = (try? nup.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return try Self.parse(result.stdout, nup: nup, fileSize: fileSize,
                              profiles: repo.appendingPathComponent("dm/games"),
                              provisional: EngineSourceCapabilities(repo: repo).provisionalNUP)
    }

    /// The probe's lines → the game. The base carries the file's size, so the unique source size is the file's (with no
    /// base game, each update carries it, as the selected update stands in for the base); the name is the profile's,
    /// else the container's NACP. A game without a registered profile is refused, as a dump is,
    /// unless the engine makes a provisional profile for it (`provisional`).
    static func parse(_ output: String, nup: URL, fileSize: Int64, profiles: URL, provisional: Bool = false) throws -> DetectedGame {
        var title: UInt64?
        var nacpName = ""
        var hasBase = false
        var updates: [DetectedSource] = []
        var dlcs: [DetectedSource] = []
        let lines = output.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
        for fields in lines where fields.first == "title" {
            guard fields.count == 2, let id = UInt64(fields[1], radix: 16), id != 0, id & 0xFFF == 0 else {
                throw EngineSourceError.invalidContainer("invalid base title ID")
            }
            title = id
        }
        guard let title else { throw EngineSourceError.invalidContainer("no base title ID") }
        for fields in lines {
            switch fields.first {
            case "name":
                if fields.count == 2, let data = Data(hex: fields[1]) { nacpName = String(decoding: data, as: UTF8.self) }
            case "base":
                hasBase = true
            case "update":
                guard fields.count == 3, let version = Int(fields[1]), version > 0, let bytes = Int64(fields[2]) else {
                    throw EngineSourceError.invalidContainer("invalid update record")
                }
                updates.append(DetectedSource(url: nup, kind: .update, titleId: title + 0x800, version: version,
                                              sizeBytes: bytes, layout: .container))
            case "dlc":
                guard fields.count == 3, let id = UInt64(fields[1], radix: 16), id > title + 0x1000,
                      id - title - 0x1000 <= 2000, let bytes = Int64(fields[2]) else {
                    throw EngineSourceError.invalidContainer("invalid DLC record")
                }
                dlcs.append(DetectedSource(url: nup, kind: .dlc, titleId: id, sizeBytes: bytes, layout: .container))
            default:
                break
            }
        }
        guard hasBase || !updates.isEmpty else { throw EngineSourceError.invalidContainer("no base game or update") }
        if !hasBase { updates = updates.map { var update = $0; update.sizeBytes = fileSize; return update } }
        let identity = String(format: "%016llX", title)
        let profile = try? String(contentsOf: profiles.appendingPathComponent(identity).appendingPathComponent("game.tsv"),
                                  encoding: .utf8)
        guard profile != nil || provisional else { throw EngineSourceError.missingProfile(identity) }
        let profileName = profile?.split(separator: "\n").first(where: { $0.hasPrefix("name\t") }).map { String($0.dropFirst(5)) }
        let name = profileName ?? (nacpName.isEmpty ? identity : nacpName)
        let base = hasBase
            ? DetectedSource(url: nup, kind: .base, titleId: title, version: 0, sizeBytes: fileSize, layout: .container)
            : nil
        return DetectedGame(baseTitleId: title, name: name, base: base,
                            updates: updates.sorted { ($0.version ?? 0) < ($1.version ?? 0) }, dlcs: dlcs)
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
