import Foundation

/// Screenshots from LaunchBox for a game Title DB has none for (every Switch 2 game, for now), looked up once when
/// the player opens the game's Details and kept on this Mac, an empty answer included, for 30 days. Nothing is asked
/// while browsing the library.
public struct ScreenshotFallbackStore: Sendable {
    public static let source = "LaunchBox"
    static let ttl: TimeInterval = 30 * 24 * 60 * 60

    public struct Entry: Codable, Equatable, Sendable {
        public var urls: [URL]
        public var fetchedAt: Date

        public init(urls: [URL], fetchedAt: Date) {
            self.urls = urls
            self.fetchedAt = fetchedAt
        }
    }

    public let directory: URL

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/NXLibrary/metadata/launchbox-screenshots")) {
        self.directory = directory
    }

    public func entry(for titleID: String) -> Entry? {
        guard let data = try? Data(contentsOf: url(for: titleID)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    public func isFresh(_ entry: Entry, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.fetchedAt) < Self.ttl
    }

    public func save(_ entry: Entry, for titleID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: url(for: titleID), options: .atomic)
    }

    /// Lays the kept screenshots over metadata that has none of its own.
    public func filled(_ metadata: NintendoStoreMetadata) -> NintendoStoreMetadata {
        guard metadata.screenshotURLs.isEmpty, let entry = entry(for: metadata.titleId), !entry.urls.isEmpty else {
            return metadata
        }
        var filled = metadata
        filled.screenshotURLs = entry.urls
        filled.screenshotSource = Self.source
        return filled
    }

    /// Whether opening Details should ask LaunchBox: the game has no screenshots and none were looked up lately.
    public func wantsLookup(_ metadata: NintendoStoreMetadata, now: Date = Date()) -> Bool {
        guard metadata.screenshotURLs.isEmpty else { return false }
        guard let entry = entry(for: metadata.titleId) else { return true }
        return !isFresh(entry, now: now)
    }

    private func url(for titleID: String) -> URL {
        let safe = titleID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
        return directory.appendingPathComponent("\(safe.isEmpty ? "unknown" : safe).json")
    }
}
