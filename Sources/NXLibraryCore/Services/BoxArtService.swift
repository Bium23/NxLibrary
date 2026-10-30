import Foundation

/// Finds each game's Switch box cover on GameTDB and caches it as `.boxart`.
/// GameTDB has no title IDs, so a cover is found by exact normalised name: the
/// player's name first, then the official one. A miss is not retried for a week
/// unless a name it did not try comes along.
public actor BoxArtService {
    public static let missRetry: TimeInterval = 7 * 24 * 3600

    private let artwork: ArtworkStore
    private let index: GameTDBStore
    private let client: ArtworkHTTPClient
    private let unzip: (Data) throws -> Data
    private let now: () -> Date
    private var entries: [GameTDBEntry]?
    private var misses: [String: Date]?

    public init(artwork: ArtworkStore, index: GameTDBStore,
                client: ArtworkHTTPClient = URLSessionArtworkClient(),
                unzip: @escaping (Data) throws -> Data = BoxArtService.unzipDatabase,
                now: @escaping () -> Date = Date.init) {
        self.artwork = artwork
        self.index = index
        self.client = client
        self.unzip = unzip
        self.now = now
    }

    /// The cached cover, or one fetched now; nil when GameTDB has none.
    public func boxArt(titleID: String, names: [String]) async -> URL? {
        if let cached = artwork.cachedURL(titleID: titleID, kind: .boxart) { return cached }
        guard let entries = loadEntries() else { return nil }
        let missKey = ([titleID] + names.map(GameTDB.normalize)).joined(separator: "|")
        if let missed = missTable()[missKey], now().timeIntervalSince(missed) < Self.missRetry { return nil }

        let match = names.lazy.compactMap { GameTDB.exactMatch(for: $0, in: entries) }.first
        for url in match.map({ GameTDB.coverURLs(id: $0.id) }) ?? [] {
            if let found = await artwork.fetch(titleID: titleID, remoteURL: url, kind: .boxart) { return found }
        }
        recordMiss(missKey)
        return nil
    }

    /// Downloads GameTDB's database when the local index is missing or 30 days old;
    /// true when a new index is in place.
    @discardableResult
    public func refreshIndexIfNeeded() async -> Bool {
        guard index.isStale(now: now()) else { return false }
        var request = URLRequest(url: GameTDB.databaseURL)
        request.timeoutInterval = 60
        request.setValue("NXLibrary/0.1 (macOS; personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, http) = try? await client.data(for: request), (200..<300).contains(http.statusCode),
              let xml = try? unzip(data), let parsed = try? GameTDB.parse(xml), !parsed.isEmpty else { return false }
        try? index.save(parsed, at: now())
        entries = parsed
        // A new index may know games that missed before.
        misses = [:]
        saveMisses()
        return true
    }

    /// `switchtdb.xml` out of GameTDB's zip, read with the system's unzip.
    public static func unzipDatabase(_ zip: Data) throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gametdb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appendingPathComponent("switchtdb.zip")
        try zip.write(to: archive)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, "switchtdb.xml"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let xml = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !xml.isEmpty else { throw GameTDB.Failure.unreadable }
        return xml
    }

    private func loadEntries() -> [GameTDBEntry]? {
        if entries == nil { entries = index.load() }
        return entries
    }

    private var missesURL: URL { index.directory.appendingPathComponent("boxart-misses.json") }

    private func missTable() -> [String: Date] {
        if let misses { return misses }
        let loaded = (try? Data(contentsOf: missesURL))
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        misses = loaded
        return loaded
    }

    private func recordMiss(_ key: String) {
        var table = missTable()
        table[key] = now()
        misses = table
        saveMisses()
    }

    private func saveMisses() {
        guard let data = try? JSONEncoder().encode(misses ?? [:]) else { return }
        try? FileManager.default.createDirectory(at: index.directory, withIntermediateDirectories: true)
        try? data.write(to: missesURL, options: .atomic)
    }
}
