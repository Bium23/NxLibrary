import Foundation

/// The exact folder layout accepted by upstream pack_dump.py. This service reads
/// metadata only; it neither packs nor modifies the supplied files.
public struct ExtractedSourceCatalog {
    public let profiles: URL
    private let fm = FileManager.default
    public init(profiles: URL) { self.profiles = profiles }

    public static func recognizes(_ folder: URL) -> Bool {
        let packages = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        guard !packages.contains(where: { !$0.lastPathComponent.hasPrefix("._") && ["nsp", "xci", "nsz", "xcz"].contains($0.pathExtension.lowercased()) }) else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("base/exefs/main.npdm").path)
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent("base/romfs").path)
    }

    public func scan(folder: URL) throws -> DetectedGame {
        let baseFolder = folder.appendingPathComponent("base")
        let title = try programID(baseFolder)
        guard title != 0, title & 0xFFF == 0 else { throw EngineSourceError.invalidDump("invalid base program ID") }
        let identity = String(format: "%016llX", title)
        let profile = profiles.appendingPathComponent(identity).appendingPathComponent("game.tsv")
        guard let profileText = try? String(contentsOf: profile, encoding: .utf8) else {
            throw EngineSourceError.missingProfile(identity)
        }
        let name = profileText.split(separator: "\n").first(where: { $0.hasPrefix("name\t") })
            .map { String($0.dropFirst(5)) } ?? identity
        let base = try source(baseFolder, kind: .base, title: title, version: 0)
        var updates: [DetectedSource] = []
        for url in children(folder.appendingPathComponent("updates")) {
            guard let version = Int(url.lastPathComponent), version > 0 else { continue }
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
