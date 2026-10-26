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
        guard fm.fileExists(atPath: fileURL.path) else { return LibraryFile() }
        do {
            return try Self.decoder().decode(LibraryFile.self, from: Data(contentsOf: fileURL))
        } catch {
            if fm.fileExists(atPath: backupURL.path),
               let backup = try? Self.decoder().decode(LibraryFile.self, from: Data(contentsOf: backupURL)) {
                return backup
            }
            return LibraryFile()
        }
    }

    public func save(_ library: LibraryFile) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: fileURL, to: backupURL)
        }
        let data = try Self.encoder().encode(library)
        try data.write(to: fileURL, options: .atomic)
        // Keep a restore point even on the first save; later saves keep the
        // previous file because it was copied before the write.
        if !fm.fileExists(atPath: backupURL.path) {
            try? fm.copyItem(at: fileURL, to: backupURL)
        }
    }

    public func merge(scanned: [PortedGame]) throws -> LibraryFile {
        var library = try load()
        for game in scanned {
            if let index = library.games.firstIndex(where: { $0.titleId == game.titleId }) {
                let old = library.games[index]
                var merged = game
                merged.id = old.id
                merged.settings = old.settings
                merged.sources = old.sources.isEmpty ? game.sources : old.sources
                merged.workspacePath = old.workspacePath ?? game.workspacePath
                merged.buildCachePath = old.buildCachePath ?? game.buildCachePath
                if old.status == .built || old.status == .builtSourcesMissing
                    || old.status == .needsRebuild {
                    let sourcesExist = !merged.sources.isEmpty
                        && merged.sources.allSatisfy { fm.fileExists(atPath: $0.url.path) }
                    merged.status = sourcesExist ? .built : .builtSourcesMissing
                    merged.toolchain = old.toolchain
                    merged.lastBuild = old.lastBuild
                }
                library.games[index] = merged
            } else {
                library.games.append(game)
            }
        }
        try save(library)
        return library
    }
}
