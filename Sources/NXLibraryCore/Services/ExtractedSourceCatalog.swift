import Foundation

/// The exact folder layout accepted by upstream pack_dump.py. This service reads
/// metadata only; it neither packs nor modifies the supplied files.
public struct ExtractedSourceCatalog {
    public let profiles: URL
    /// The engine makes a provisional profile for a game without one (`EngineSourceCapabilities.provisionalDumps`).
    public let provisional: Bool
    private let fm = FileManager.default
    public init(profiles: URL, provisional: Bool = false) { self.profiles = profiles; self.provisional = provisional }

    /// The engine's `pack_dump.is_dump` (nxnative 4a0551e4): a base game's code with a RomFS beside it or in an
    /// update, or an update with its code and RomFS and no base. The base is `base/`, or the folder itself when
    /// exefs/ and romfs/ are directly in it (`nup extract`, or the `base` folder chosen).
    public static func recognizes(_ folder: URL) -> Bool {
        let packages = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        guard !packages.contains(where: { !$0.lastPathComponent.hasPrefix("._") && ["nsp", "xci", "nsz", "xcz"].contains($0.pathExtension.lowercased()) }) else { return false }
        let updates = updateFolders(folder).map(\.url)
        if let base = baseFolder(folder) {
            return isDirectory(base.appendingPathComponent("romfs")) || updates.contains { isDirectory($0.appendingPathComponent("romfs")) }
        }
        return updates.contains(where: isVersion)
    }

    private static func hasCode(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("exefs/main.npdm").path)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private static func isVersion(_ folder: URL) -> Bool {
        hasCode(folder) && isDirectory(folder.appendingPathComponent("romfs"))
    }

    /// `pack_dump.base_of`: base/ with its code, else the folder itself when it holds one whole version.
    private static func baseFolder(_ folder: URL) -> URL? {
        let base = folder.appendingPathComponent("base")
        if hasCode(base) { return base }
        return isVersion(folder) ? folder : nil
    }

    /// updates/<version>/ folders, by version.
    private static func updateFolders(_ folder: URL) -> [(version: Int, url: URL)] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("updates"),
                                                                   includingPropertiesForKeys: [.isDirectoryKey],
                                                                   options: .skipsHiddenFiles)) ?? []
        return entries.compactMap { url in
            guard isDirectory(url), url.lastPathComponent.allSatisfy(\.isNumber), let version = Int(url.lastPathComponent),
                  version > 0 else { return nil }
            return (version, url)
        }.sorted { $0.version < $1.version }
    }

    public func scan(folder: URL) throws -> DetectedGame {
        // The `base` folder of a full dump chosen: the dump is the folder holding it, with its updates and DLC.
        let parent = folder.deletingLastPathComponent()
        if folder.lastPathComponent.lowercased() == "base", Self.hasCode(folder),
           Self.isDirectory(parent.appendingPathComponent("updates")) || Self.isDirectory(parent.appendingPathComponent("dlc")),
           Self.recognizes(parent) {
            return try scan(folder: parent)
        }
        guard Self.recognizes(folder) else { throw EngineSourceError.invalidDump("no game code with a RomFS") }
        let baseFolder = Self.baseFolder(folder)
        let versions = Self.updateFolders(folder)
        // The title is the base's program ID, else the newest whole update's (pack_dump.scan).
        guard let identifying = baseFolder ?? versions.last(where: { Self.isVersion($0.url) })?.url else {
            throw EngineSourceError.invalidDump("no game code with a RomFS")
        }
        let title = try programID(identifying)
        guard title != 0, title & 0xFFF == 0 else { throw EngineSourceError.invalidDump("invalid base program ID") }
        let identity = String(format: "%016llX", title)
        let profile = profiles.appendingPathComponent(identity).appendingPathComponent("game.tsv")
        let profileText = try? String(contentsOf: profile, encoding: .utf8)
        guard profileText != nil || provisional else { throw EngineSourceError.missingProfile(identity) }
        // A dump has no control data, so without a profile its name is the folder's (the one holding a chosen `base`).
        let folderName = folder.lastPathComponent.lowercased() == "base"
            ? folder.deletingLastPathComponent().lastPathComponent : folder.lastPathComponent
        let name = profileText?.split(separator: "\n").first(where: { $0.hasPrefix("name\t") })
            .map { String($0.dropFirst(5)) } ?? (profileText == nil ? folderName : identity)
        // A base without its RomFS adds nothing to an update whose RomFS is whole: the dump is that update's.
        let base = try baseFolder.flatMap { folder in
            Self.isDirectory(folder.appendingPathComponent("romfs")) ? try source(folder, kind: .base, title: title, version: 0) : nil
        }
        var updates: [DetectedSource] = []
        for (version, url) in versions {
            guard try programID(url) == title else { throw EngineSourceError.invalidDump("update program ID differs from the base") }
            updates.append(try source(url, kind: .update, title: title + 0x800, version: version))
        }
        var dlcs: [DetectedSource] = []
        for url in children(folder.appendingPathComponent("dlc")) {
            guard url.lastPathComponent.count == 16, let id = UInt64(url.lastPathComponent, radix: 16),
                  id > title + 0x1000, id - title - 0x1000 <= 2000 else {
                throw EngineSourceError.invalidDump("invalid DLC title ID")
            }
            let direct = url.appendingPathComponent("romfs")
            let romfs = fm.fileExists(atPath: direct.path) ? [direct]
                : children(url).map { $0.appendingPathComponent("romfs") }.filter { fm.fileExists(atPath: $0.path) }
            guard romfs.count == 1 else { throw EngineSourceError.invalidDump("each DLC needs one RomFS folder") }
            dlcs.append(DetectedSource(url: romfs[0], kind: .dlc, titleId: id, sizeBytes: size(romfs[0]), layout: .extracted))
        }
        return DetectedGame(baseTitleId: title, name: name, base: base,
                            updates: updates.sorted { ($0.version ?? 0) < ($1.version ?? 0) }, dlcs: dlcs)
    }

    private func programID(_ folder: URL) throws -> UInt64 {
        let data = try Data(contentsOf: folder.appendingPathComponent("exefs/main.npdm"))
        guard data.count >= 0x78, data.prefix(4) == Data("META".utf8) else { throw EngineSourceError.invalidDump("invalid main.npdm") }
        let offset = Int(number(data, at: 0x70, count: 4))
        let length = number(data, at: 0x74, count: 4)
        guard length >= 0x18, offset <= data.count - 0x18,
              data.subdata(in: offset..<offset + 4) == Data("ACI0".utf8) else { throw EngineSourceError.invalidDump("invalid ACI0 section") }
        return number(data, at: offset + 0x10, count: 8)
    }

    private func number(_ data: Data, at offset: Int, count: Int) -> UInt64 {
        (0..<count).reduce(0) { $0 | UInt64(data[offset + $1]) << (8 * $1) }
    }

    private func source(_ folder: URL, kind: SourceKind, title: UInt64, version: Int) throws -> DetectedSource {
        guard fm.fileExists(atPath: folder.appendingPathComponent("exefs/main").path),
              fm.fileExists(atPath: folder.appendingPathComponent("romfs").path) else {
            throw EngineSourceError.invalidDump("missing ExeFS or RomFS")
        }
        return DetectedSource(url: folder, kind: kind, titleId: title, version: version, sizeBytes: size(folder), layout: .extracted)
    }

    private func children(_ folder: URL) -> [URL] {
        ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func size(_ folder: URL) -> Int64 {
        let items = fm.enumerator(at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: .skipsHiddenFiles)
        var total: Int64 = 0
        while let url = items?.nextObject() as? URL {
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}
