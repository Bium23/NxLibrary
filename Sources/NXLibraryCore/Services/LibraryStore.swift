import Foundation

public final class LibraryStore {
    public let directory: URL
    public let fileURL: URL
    private let backupURL: URL
    private let fm: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("library.json")
        self.backupURL = directory.appendingPathComponent("library.json.bak")
        self.fm = fileManager
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() throws -> LibraryFile {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            if fm.fileExists(atPath: backupURL.path),
               let backup = try? Self.decoder().decode(LibraryFile.self,
                                                       from: Data(contentsOf: backupURL)) {
                return backup
            }
            return LibraryFile()
        }
        do {
            return try Self.decoder().decode(LibraryFile.self, from: Data(contentsOf: fileURL))
        } catch {
            // Move the unreadable file aside so the next save cannot write over it; the backup (or an empty
            // library) carries on, and the games in it can still be recovered by hand.
            keepAside()
            if fm.fileExists(atPath: backupURL.path),
               let backup = try? Self.decoder().decode(LibraryFile.self, from: Data(contentsOf: backupURL)) {
                return backup
            }
            return LibraryFile()
        }
    }

    /// `library.json.damaged-<date>-<id>`, beside the library.
    private func keepAside() {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                                formatOptions: [.withYear, .withMonth, .withDay, .withTime])
        let id = UUID().uuidString.prefix(4)
        try? fm.moveItem(at: fileURL, to: directory.appendingPathComponent("library.json.damaged-\(stamp)-\(id)"))
    }

    public func save(_ library: LibraryFile) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // Never rotate a corrupt main file over the last known good backup.
        if let existing = try? Data(contentsOf: fileURL),
           (try? Self.decoder().decode(LibraryFile.self, from: existing)) != nil {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: fileURL, to: backupURL)
        }
        let data = try Self.encoder().encode(library)
        try data.write(to: fileURL, options: .atomic)
        // Keep a restore point even on the first save; later saves keep the
        // previous valid file because it was copied before the write.
        if !fm.fileExists(atPath: backupURL.path) {
            try? fm.copyItem(at: fileURL, to: backupURL)
        }
    }

    public func merge(scanned: [PortedGame], replacingSources: Bool = false) throws -> LibraryFile {
        var library = try load()
        library.games = NXNativeLibraryMerge.merge(scanned: scanned, into: library.games,
                                                    replacingSources: replacingSources, fileManager: fm)
        try save(library)
        return library
    }
}
