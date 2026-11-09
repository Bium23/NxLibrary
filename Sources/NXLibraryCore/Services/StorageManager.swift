import Foundation
import Darwin

public enum StorageCleanupError: LocalizedError {
    case unsafeCache, unavailable

    public var errorDescription: String? {
        switch self {
        case .unsafeCache: return L10n.text("The cache folder could not be safely identified. Nothing was deleted.")
        case .unavailable: return L10n.text("The folder is unavailable. Connect its drive and check folder access, then recalculate storage.")
        }
    }
}

public struct StorageUsage: Equatable {
    public var libraryBytes: Int64
    public var cacheBytes: Int64
    public var logsBytes: Int64
    public var freeBytes: Int64

    public init(libraryBytes: Int64, cacheBytes: Int64,
                logsBytes: Int64, freeBytes: Int64) {
        self.libraryBytes = libraryBytes
        self.cacheBytes = cacheBytes
        self.logsBytes = logsBytes
        self.freeBytes = freeBytes
    }
}

public final class StorageManager {
    private let supportRoot: URL
    private let applicationsRoot: URL
    private let logsRoot: URL
    private let fm: FileManager

    public init(
        supportRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NXLibrary"),
        applicationsRoot: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications"),
        logsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/nxnative"),
        fileManager: FileManager = .default
    ) {
        self.supportRoot = supportRoot
        self.applicationsRoot = applicationsRoot
        self.logsRoot = logsRoot
        self.fm = fileManager
    }

    public func usage(games: [PortedGame]) -> StorageUsage {
        snapshot(games: games).total
    }

    /// Logical file sizes, including hidden files, without traversing links. A path shared by library entries
    /// is measured and counted once in the totals, but remains visible on each entry that uses it.
    public func snapshot(games: [PortedGame], applicationsFolder: URL? = nil) -> StorageSnapshot {
        var sizes: [String: StorageSize] = [:]
        var apps = Set<String>(), caches = Set<String>(), logs = Set<String>()
        func key(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
        func measure(_ url: URL, in paths: inout Set<String>) -> StorageSize {
            let path = key(url)
            paths.insert(path)
            if let value = sizes[path] { return value }
            let value = size(of: URL(fileURLWithPath: path))
            sizes[path] = value
            return value
        }
        let rows = games.map { game -> GameStorageUsage in
            let app = game.url.pathExtension.lowercased() == "app" ? measure(game.url, in: &apps) : .missing
            var cache: StorageSize = .missing
            var shared: [String] = []
            if game.buildCachePath != nil {
                if let url = try? cacheURL(for: game, protecting: games) {
                    cache = measure(url, in: &caches)
                    shared = games.filter {
                        $0.id != game.id && $0.buildCachePath.map { key(URL(fileURLWithPath: $0)) == key(url) } == true
                    }.map(\.name)
                } else { cache = .unavailable }
            }
            let logSizes = logURLs(for: game).map { measure($0, in: &logs) }
            let logSize: StorageSize = logSizes.contains(.unavailable) ? .unavailable
                : .bytes(logSizes.reduce(0) { $0 + ($1.knownBytes ?? 0) })
            return GameStorageUsage(id: game.id, name: game.name, app: app, cache: cache, logs: logSize,
                                    canDeleteCache: (cache.knownBytes ?? 0) > 0, sharedCacheWith: shared)
        }.sorted {
            let left = $0.cache.knownBytes ?? 0, right = $1.cache.knownBytes ?? 0
            if left != right { return left > right }
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
        func total(_ paths: Set<String>) -> Int64 { paths.reduce(0) { $0 + (sizes[$1]?.knownBytes ?? 0) } }
        let free = freeSpace(at: applicationsFolder ?? applicationsRoot)
        return StorageSnapshot(games: rows,
                               total: StorageUsage(libraryBytes: total(apps), cacheBytes: total(caches),
                                                   logsBytes: total(logs), freeBytes: free ?? 0), freeBytes: free)
    }

    @discardableResult
    public func deleteCache(for game: PortedGame, protecting games: [PortedGame] = []) throws -> Bool {
        guard game.buildCachePath != nil else { return false }
        let url = try cacheURL(for: game, protecting: games)
        switch size(of: url) {
        case .missing: return false
        case .unavailable: throw StorageCleanupError.unavailable
        case .bytes: break
        }
        try fm.removeItem(at: url)
        return true
    }

    private func cacheURL(for game: PortedGame, protecting games: [PortedGame]) throws -> URL {
        guard let title = game.titleId, title.count == 16, title.allSatisfy(\.isHexDigit),
              let path = game.buildCachePath, path.hasPrefix("/"),
              let workspace = game.workspacePath, workspace.hasPrefix("/") else {
            throw StorageCleanupError.unsafeCache
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.lastPathComponent.lowercased() == "\(title.lowercased())_build",
              url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
                == URL(fileURLWithPath: workspace).resolvingSymlinksInPath().standardizedFileURL.path,
              (try? fm.destinationOfSymbolicLink(atPath: url.path)) == nil else {
            throw StorageCleanupError.unsafeCache
        }
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw StorageCleanupError.unsafeCache
        }
        let cache = url.resolvingSymlinksInPath().path
        for entry in games + [game] {
            let protected = [entry.url] + entry.sources.map(\.url)
                + [entry.pendingInstall?.tempApp, entry.pendingInstall?.finalApp].compactMap { $0 }
            guard !protected.contains(where: {
                let path = $0.resolvingSymlinksInPath().path
                return path == cache || path.hasPrefix(cache + "/")
            }) else { throw StorageCleanupError.unsafeCache }
        }
        return url
    }

    @discardableResult
    public func deleteLogs(for game: PortedGame) throws -> Bool {
        var removed = false
        for url in logURLs(for: game) where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
            removed = true
        }
        return removed
    }

    private func logURLs(for game: PortedGame) -> [URL] {
        guard let title = game.titleId, title.count == 16, title.allSatisfy(\.isHexDigit) else { return [] }
        return [logsRoot.appendingPathComponent("\(title).log"), buildLogURL(for: title)]
    }

    private func buildLogURL(for titleId: String) -> URL {
        supportRoot.appendingPathComponent("Logs").appendingPathComponent("\(titleId).log")
    }

    private func size(of url: URL) -> StorageSize {
        let parts = url.standardizedFileURL.pathComponents
        if parts.count > 2, parts[1] == "Volumes",
           !fm.fileExists(atPath: "/Volumes/\(parts[2])") { return .unavailable }
        var node = stat()
        guard lstat(url.path, &node) == 0 else {
            return errno == ENOENT ? .missing : .unavailable
        }
        if node.st_mode & S_IFMT == S_IFREG { return .bytes(Int64(node.st_size)) }
        guard node.st_mode & S_IFMT == S_IFDIR else { return .unavailable }
        var total: Int64 = 0
        var failed = false
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let root = strdup(path) else { failed = true; return }
            defer { free(root) }
            var roots: [UnsafeMutablePointer<CChar>?] = [root, nil]
            guard let tree = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { failed = true; return }
            defer { fts_close(tree) }
            while let entry = fts_read(tree) {
                switch Int32(entry.pointee.fts_info) {
                case FTS_F:
                    if let stat = entry.pointee.fts_statp { total += Int64(stat.pointee.st_size) }
                case FTS_DNR, FTS_ERR, FTS_NS: failed = true
                default: break
                }
            }
        }
        return failed ? .unavailable : .bytes(total)
    }

    private func freeSpace(at url: URL) -> Int64? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
