import Foundation

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
        var library: Int64 = 0
        var cache: Int64 = 0
        var logs: Int64 = 0
        for game in games {
            library += size(of: game.url)
            if let path = game.buildCachePath {
                cache += size(of: URL(fileURLWithPath: path))
            }
            if let titleId = game.titleId {
                logs += size(of: logsRoot.appendingPathComponent("\(titleId).log"))
                logs += size(of: buildLogURL(for: titleId))
            }
        }
        return StorageUsage(
            libraryBytes: library, cacheBytes: cache, logsBytes: logs,
            freeBytes: freeSpace(at: applicationsRoot)
        )
    }

    public func deleteCache(for game: PortedGame) throws {
        guard let path = game.buildCachePath else { return }
        let url = URL(fileURLWithPath: path)
        guard url.lastPathComponent.hasSuffix("_build") else { return }
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    public func deleteLogs(for game: PortedGame) throws {
        guard let titleId = game.titleId else { return }
        for url in [
            logsRoot.appendingPathComponent("\(titleId).log"),
            buildLogURL(for: titleId),
        ] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    public func backupSave(for game: PortedGame, to destination: URL) throws {
        guard let titleId = game.titleId else { return }
        let source = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/nxnative")
            .appendingPathComponent(titleId).appendingPathComponent("save")
        guard fm.fileExists(atPath: source.path) else { return }
        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
    }

    private func buildLogURL(for titleId: String) -> URL {
        supportRoot.appendingPathComponent("Logs").appendingPathComponent("\(titleId).log")
    }

    private func size(of url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    private func freeSpace(at url: URL) -> Int64 {
        let target = fm.fileExists(atPath: url.path) ? url : fm.homeDirectoryForCurrentUser
        let values = try? target.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
