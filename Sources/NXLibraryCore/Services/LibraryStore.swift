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
            if fm.fileExists(atPath: backupURL.path),
               let backup = try? Self.decoder().decode(LibraryFile.self, from: Data(contentsOf: backupURL)) {
                return backup
            }
            return LibraryFile()
        }
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

    public func merge(scanned: [PortedGame]) throws -> LibraryFile {
        var library = try load()
        for game in scanned {
            if let index = library.games.firstIndex(where: { existing in
                guard let target = game.titleId else { return existing.titleId == nil }
                return existing.titleId?.caseInsensitiveCompare(target) == .orderedSame
            }) {
                let old = library.games[index]
                var merged = game
                merged.id = old.id
                merged.settings = old.settings
                if old.sources.isEmpty {
                    merged.sources = game.sources
                } else {
                    let oldSourcesExist = old.sources.allSatisfy {
                        fm.fileExists(atPath: $0.url.path)
                    }
                    merged.sources = (oldSourcesExist || game.sources.isEmpty)
                        ? old.sources : game.sources
                }
                merged.workspacePath = old.workspacePath ?? game.workspacePath
                merged.buildCachePath = old.buildCachePath ?? game.buildCachePath
                if (old.status == .built || old.status == .builtSourcesMissing
                    || old.status == .needsRebuild),
                   old.url.pathExtension.lowercased() == "app",
                   fm.fileExists(atPath: old.url.path) {
                    merged.url = old.url
                    merged.sizeBytes = old.sizeBytes
                    merged.bundleId = old.bundleId ?? merged.bundleId
                    merged.versionString = old.versionString ?? merged.versionString
                }
                if old.status == .built || old.status == .builtSourcesMissing
                    || old.status == .needsRebuild {
                    if merged.sources.isEmpty {
                        merged.status = game.status == .built ? .built : .builtSourcesMissing
                    } else {
                        let sourcesExist = merged.sources.allSatisfy {
                            fm.fileExists(atPath: $0.url.path)
                        }
                        merged.status = sourcesExist ? .built : .builtSourcesMissing
                    }
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
