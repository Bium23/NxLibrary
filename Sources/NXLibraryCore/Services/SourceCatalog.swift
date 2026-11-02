import Foundation

public struct DetectedSource: Identifiable, Equatable {
    public var id: UUID
    public var url: URL
    public var kind: SourceKind
    public var titleId: UInt64
    public var version: Int?
    public var sizeBytes: Int64
    public var layout: SourceLayout
    public var requiresTitleSelection: Bool

    public init(id: UUID = UUID(), url: URL, kind: SourceKind,
                titleId: UInt64, version: Int? = nil, sizeBytes: Int64, layout: SourceLayout = .package,
                requiresTitleSelection: Bool = false) {
        self.id = id
        self.url = url
        self.kind = kind
        self.titleId = titleId
        self.version = version
        self.sizeBytes = sizeBytes
        self.layout = layout
        self.requiresTitleSelection = requiresTitleSelection
    }
}

public struct DetectedGame: Identifiable, Equatable {
    public var id: String { String(format: "%016llX", baseTitleId) }
    public var baseTitleId: UInt64
    public var name: String
    public var base: DetectedSource?
    public var updates: [DetectedSource]
    public var dlcs: [DetectedSource]
    public var allSources: [DetectedSource] { [base].compactMap { $0 } + updates + dlcs }
    public var totalSizeBytes: Int64 {
        var seen = Set<String>()
        return allSources.reduce(0) { total, source in
            total + (seen.insert(source.url.resolvingSymlinksInPath().path).inserted ? source.sizeBytes : 0)
        }
    }

    public init(baseTitleId: UInt64, name: String, base: DetectedSource?,
                updates: [DetectedSource] = [], dlcs: [DetectedSource] = []) {
        self.baseTitleId = baseTitleId
        self.name = name
        self.base = base
        self.updates = updates
        self.dlcs = dlcs
    }
}

public enum SourceCatalogError: Error, LocalizedError {
    case unreadable(URL)
    case tooLarge(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            return "No readable title ID in \(url.lastPathComponent)."
        case .tooLarge(let url):
            return "\(url.lastPathComponent) has an unsupported internal table size."
        }
    }
}

public final class SourceCatalog {
    private let fm: FileManager

    public init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    public static func classify(titleId: UInt64) -> SourceKind {
        switch titleId & 0xFFF {
        case 0: return .base
        case 0x800: return .update
        default: return .dlc
        }
    }

    public static func baseTitleId(for titleId: UInt64, kind: SourceKind) -> UInt64 {
        switch kind {
        case .base: return titleId
        case .update: return titleId & ~UInt64(0xFFF)
        case .dlc: return (titleId & ~UInt64(0xFFF)) &- 0x1000
        case .unknown: return titleId
        }
    }

    public func scan(files: [URL], skippingUnreadable: Bool = false,
                     onUnreadable: ((URL, Error) -> Void)? = nil,
                     contentsReader: ((URL) throws -> [PackageContent])? = nil) throws -> [DetectedGame] {
        var groups: [UInt64: (base: DetectedSource?, updates: [DetectedSource], dlcs: [DetectedSource])] = [:]
        var firstError: Error?

        for url in files {
            guard !url.hasDirectoryPath else { continue }
            let sources: [DetectedSource]
            do {
                let contents = try contentsReader?(url) ?? []
                sources = contents.isEmpty ? [try inspect(url)] : contents.map {
                    DetectedSource(url: url, kind: $0.kind, titleId: $0.titleId, version: $0.version,
                                   sizeBytes: fileSize(url), requiresTitleSelection: contents.count > 1)
                }
            } catch {
                guard skippingUnreadable else { throw error }
                if firstError == nil { firstError = error }
                onUnreadable?(url, error)
                continue
            }
            for source in sources {
                let appId = Self.baseTitleId(for: source.titleId, kind: source.kind)
                var group = groups[appId] ?? (nil, [], [])
                switch source.kind {
                case .base:
                    if group.base == nil || (source.version ?? -1) > (group.base?.version ?? -1) {
                        group.base = source
                    }
                case .update:
                    group.updates.append(source)
                case .dlc:
                    group.dlcs.append(source)
                case .unknown:
                    continue
                }
                groups[appId] = group
            }
        }

        if groups.isEmpty, let firstError { throw firstError }
        return groups.map { appId, group in
            let named = group.base ?? group.updates.first ?? group.dlcs.first
            let name = named.map { Self.cleanName($0.url) } ?? String(format: "%016llX", appId)
            return DetectedGame(
                baseTitleId: appId,
                name: name,
                base: group.base,
                updates: group.updates.sorted {
                    ($0.version ?? -1, $0.url.lastPathComponent) < ($1.version ?? -1, $1.url.lastPathComponent)
                },
                dlcs: group.dlcs.sorted {
                    ($0.titleId, $0.url.lastPathComponent) < ($1.titleId, $1.url.lastPathComponent)
                }
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func inspect(_ url: URL) throws -> DetectedSource {
        let ext = url.pathExtension.lowercased()
        let size = fileSize(url)

        if ext == "xci" || ext == "xcz" {
            guard let titleId = Self.titleIdFromName(url) else {
                throw SourceCatalogError.unreadable(url)
            }
            return DetectedSource(url: url, kind: .base, titleId: titleId,
                                  version: Self.versionFromName(url), sizeBytes: size)
        }

        if let archive = try? PFS0Archive.open(url, fileManager: fm) {
            // Prefer the plaintext manifest. A ".cnmt.nca" entry is an NCA
            // container, not a raw CNMT header; parsing it as one yields a hash
            // for the title ID.
            let meta = archive.firstEntry(where: {
                $0.name.lowercased().hasSuffix(".cnmt.xml")
            }) ?? archive.firstEntry(where: {
                $0.name.lowercased().hasSuffix(".cnmt")
            })
            if let meta,
               let data = try? archive.read(meta, maxLength: 4 * 1024 * 1024),
               let parsed = Self.parseCNMT(data, url: url) {
                return DetectedSource(url: url, kind: parsed.kind, titleId: parsed.titleId,
                                      version: parsed.version, sizeBytes: size)
            }
            if let ticket = archive.firstEntry(where: { $0.name.lowercased().hasSuffix(".tik") }) {
                if let titleId = Self.titleIdFromTicketName(ticket.name)
                    ?? (try? archive.read(ticket, maxLength: 0x2A8)).flatMap(Self.titleIdFromTicketData) {
                    return DetectedSource(url: url, kind: Self.classify(titleId: titleId),
                                          titleId: titleId,
                                          version: Self.versionFromName(url), sizeBytes: size)
                }
            }
        }

        // A compressed NSZ/XCZ cannot be parsed without decompression; its
        // filename is the only title source. An ordinary NSP gets the same
        // fallback because nxnative itself trusts a filename tag when there
        // is no ticket.
        if let titleId = Self.titleIdFromName(url) {
            let kind: SourceKind = (ext == "xci" || ext == "xcz")
                ? .base : Self.classify(titleId: titleId)
            return DetectedSource(url: url, kind: kind, titleId: titleId,
                                  version: Self.versionFromName(url), sizeBytes: size)
        }

        throw SourceCatalogError.unreadable(url)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let target = url.resolvingSymlinksInPath()
        let values = try? target.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    static func titleIdFromName(_ url: URL) -> UInt64? {
        guard let value = firstCapture(#"\[([0-9A-Fa-f]{16})\]"#, in: url.lastPathComponent) else {
            return nil
        }
        return UInt64(value, radix: 16)
    }

    static func versionFromName(_ url: URL) -> Int? {
        firstCapture(#"\[v(\d+)\]"#, in: url.lastPathComponent).flatMap(Int.init)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captured])
    }

    static func cleanName(_ url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        let patterns = [
            #"\[[^\]]*\]"#,
            #"(?i)\([^)]*\.(com|net|org|fr|io|cc|me|tv|co|xyz|site)[^)]*\)"#,
            #"(?i)\((usa|europe|eur|jpn|japan|world|eshop|nsp|xci|nsz|xcz|update|dlc)\)"#,
        ]
        for pattern in patterns {
            while let range = name.range(of: pattern, options: .regularExpression) {
                name.removeSubrange(range)
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? url.lastPathComponent : name
    }

    private static func titleIdFromTicketName(_ name: String) -> UInt64? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.count >= 16 else { return nil }
        let prefix = String(stem.prefix(16))
        guard prefix.allSatisfy({ $0.isHexDigit }) else { return nil }
        return UInt64(prefix, radix: 16)
    }

    private static func titleIdFromTicketData(_ data: Data) -> UInt64? {
        guard data.count >= 0x2A8 else { return nil }
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return nil }
            var value: UInt64 = 0
            memcpy(&value, base.advanced(by: 0x2A0), 8)
            return UInt64(bigEndian: value)
        }
    }

    private static func parseCNMT(_ data: Data, url: URL) -> (kind: SourceKind, titleId: UInt64, version: Int?)? {
        if let text = String(data: data.prefix(4 * 1024 * 1024), encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            guard let idText = xmlTag("Id", in: text), let titleId = parseHexUInt64(idText) else {
                return nil
            }
            let version = xmlTag("Version", in: text).flatMap(Int.init)
            let type = xmlTag("Type", in: text)
            let kind = type.flatMap(kindForMetaType) ?? classify(titleId: titleId)
            return (kind, titleId, version)
        }

        guard data.count >= 0x10 else { return nil }
        let titleId = data.withUnsafeBytes { raw -> UInt64 in
            var value: UInt64 = 0
            memcpy(&value, raw.baseAddress!, 8)
            return UInt64(littleEndian: value)
        }
        let version = data.withUnsafeBytes { raw -> UInt32 in
            var value: UInt32 = 0
            memcpy(&value, raw.baseAddress!.advanced(by: 8), 4)
            return UInt32(littleEndian: value)
        }
        let type = data[12]
        let kind: SourceKind
        switch type {
        case 0x80, 1: kind = .base
        case 0x81, 2: kind = .update
        case 0x82, 3: kind = .dlc
        default: kind = classify(titleId: titleId)
        }
        return (kind, titleId, Int(version))
    }

    private static func kindForMetaType(_ type: String) -> SourceKind? {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "application": return .base
        case "patch": return .update
        case "addoncontent", "addoncontentmeta": return .dlc
        default: return nil
        }
    }

    private static func xmlTag(_ tag: String, in text: String) -> String? {
        guard let start = text.range(of: "<\(tag)>"),
              let end = text.range(of: "</\(tag)>", range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseHexUInt64(_ text: String) -> UInt64? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("0x") { value.removeFirst(2) }
        return UInt64(value, radix: 16)
    }
}

private struct PFS0Entry {
    var name: String
    var offset: UInt64
    var size: UInt64
}

private struct PFS0Archive {
    let fileURL: URL
    let dataStart: UInt64
    let entries: [PFS0Entry]
    let fileSize: UInt64

    static func open(_ url: URL, fileManager: FileManager) throws -> PFS0Archive {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize >= 16 else { throw SourceCatalogError.unreadable(url) }

        try handle.seek(toOffset: 0)
        guard let header = try handle.read(upToCount: 16), header.count == 16,
              header.prefix(4) == Data("PFS0".utf8) else {
            throw SourceCatalogError.unreadable(url)
        }
        let count = header.readUInt32LE(4)
        let stringTableSize = header.readUInt32LE(8)
        guard count < 100_000, stringTableSize < 32 * 1024 * 1024 else {
            throw SourceCatalogError.tooLarge(url)
        }
        let entriesSize = UInt64(count) * 0x18
        let tableSize = entriesSize + UInt64(stringTableSize)
        guard tableSize <= fileSize - 16 else { throw SourceCatalogError.unreadable(url) }
        guard let table = try handle.read(upToCount: Int(tableSize)), table.count == Int(tableSize) else {
            throw SourceCatalogError.unreadable(url)
        }
        let strings = table.subdata(in: Int(entriesSize)..<Int(tableSize))
        var entries: [PFS0Entry] = []
        entries.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let base = index * 0x18
            let offset = table.readUInt64LE(base)
            let size = table.readUInt64LE(base + 8)
            let stringOffset = Int(table.readUInt32LE(base + 0x10))
            guard stringOffset < strings.count else { continue }
            let tail = strings.subdata(in: stringOffset..<strings.count)
            let nameBytes = tail.prefix { $0 != 0 }
            let name = String(data: nameBytes, encoding: .utf8) ?? ""
            entries.append(PFS0Entry(name: name, offset: offset, size: size))
        }
        return PFS0Archive(fileURL: url, dataStart: 16 + tableSize,
                           entries: entries, fileSize: fileSize)
    }

    func firstEntry(where predicate: (PFS0Entry) -> Bool) -> PFS0Entry? {
        entries.first(where: predicate)
    }

    func read(_ entry: PFS0Entry, maxLength: UInt64) throws -> Data {
        guard entry.size <= maxLength, entry.offset <= fileSize,
              entry.size <= fileSize - entry.offset else {
            throw SourceCatalogError.unreadable(fileURL)
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: dataStart + entry.offset)
        guard let data = try handle.read(upToCount: Int(entry.size)), data.count == Int(entry.size) else {
            throw SourceCatalogError.unreadable(fileURL)
        }
        return data
    }
}

private extension Data {
    func readUInt32LE(_ offset: Int) -> UInt32 {
        withUnsafeBytes { raw in
            var value: UInt32 = 0
            memcpy(&value, raw.baseAddress!.advanced(by: offset), 4)
            return UInt32(littleEndian: value)
        }
    }

    func readUInt64LE(_ offset: Int) -> UInt64 {
        withUnsafeBytes { raw in
            var value: UInt64 = 0
            memcpy(&value, raw.baseAddress!.advanced(by: offset), 8)
            return UInt64(littleEndian: value)
        }
    }
}
