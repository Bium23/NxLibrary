import Foundation

/// A GameBanana mod confirmed to work with the engine: at least one of its files is a single RomFS tree for this game.
public struct AvailableMod: Equatable, Identifiable, Sendable {
    public let id: Int
    /// Position in GameBanana's most-downloaded order, so tiles keep that order.
    public let rank: Int
    public let name: String
    public let author: String
    public let avatarURL: URL?
    public let images: [URL]
    public let thumbnailURL: URL?
    public let version: String
    public let updated: Date
    public let pageURL: URL
    public let description: String
    public let likes: Int
    public let downloads: Int
    /// The files that work, newest first.
    public let files: [GameBananaFile]

    public init(id: Int, rank: Int, name: String, author: String, avatarURL: URL?, images: [URL], thumbnailURL: URL?,
                version: String, updated: Date, pageURL: URL, description: String, likes: Int, downloads: Int,
                files: [GameBananaFile]) {
        self.id = id
        self.rank = rank
        self.name = name
        self.author = author
        self.avatarURL = avatarURL
        self.images = images
        self.thumbnailURL = thumbnailURL
        self.version = version
        self.updated = updated
        self.pageURL = pageURL
        self.description = description
        self.likes = likes
        self.downloads = downloads
        self.files = files
    }
}

/// Reads a game's mods page by page (most downloaded first) and yields the ones that work, checking each mod's
/// profile and the listing of each of its files. Stops at `want` mods, after `maxScanned` mods, or at the list's end.
/// Hidden mods (obsolete, content-rated, private…) are skipped before their profile is fetched where the index
/// already says so. A mod or file GameBanana cannot describe is skipped; no connection ends the stream.
public struct AvailableModsFinder: Sendable {
    public let client: GameBananaClient
    public let titleID: String
    public let want: Int
    public let maxScanned: Int
    public let perPage: Int

    public init(client: GameBananaClient, titleID: String, want: Int = 12, maxScanned: Int = 60, perPage: Int = 20) {
        self.client = client
        self.titleID = titleID
        self.want = want
        self.maxScanned = maxScanned
        self.perPage = perPage
    }

    public func stream(gameID: Int) -> AsyncThrowingStream<AvailableMod, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(gameID: gameID) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(gameID: Int, yield: (AvailableMod) -> Void) async throws {
        var found = 0, scanned = 0, page = 1
        while found < want, scanned < maxScanned, !Task.isCancelled {
            let result = try await client.modPage(gameID: gameID, page: page, perPage: perPage)
            let batch = Array(result.records.prefix(maxScanned - scanned))
            let start = scanned
            scanned += batch.count
            var confirmed: [AvailableMod] = []
            try await withThrowingTaskGroup(of: AvailableMod?.self) { group in
                for (offset, summary) in batch.enumerated() where ModSupport.isVisible(summary) {
                    group.addTask { try await check(summary, rank: start + offset) }
                }
                for try await mod in group { if let mod { confirmed.append(mod) } }
            }
            for mod in confirmed.sorted(by: { $0.rank < $1.rank }) where found < want {
                yield(mod)
                found += 1
            }
            if result.isComplete || result.records.isEmpty { break }
            page += 1
        }
    }

    private func check(_ summary: GameBananaModSummary, rank: Int) async throws -> AvailableMod? {
        let profile: GameBananaModProfile
        do { profile = try await client.profile(modID: summary.id) } catch GameBananaError.unavailable { return nil }
        guard ModSupport.isVisible(profile) else { return nil }
        var files: [GameBananaFile] = []
        for file in profile.files {
            do {
                let paths = try await client.archivePaths(fileID: file.id)
                if ModSupport.romfsRoot(in: paths, titleID: titleID) != nil { files.append(file) }
            } catch GameBananaError.unavailable {
                continue
            }
        }
        guard !files.isEmpty else { return nil }
        let images = profile.images.isEmpty ? summary.images : profile.images
        return AvailableMod(
            id: profile.id, rank: rank, name: profile.name.isEmpty ? summary.name : profile.name,
            author: profile.submitter.name.isEmpty ? summary.submitter.name : profile.submitter.name,
            avatarURL: profile.submitter.avatarURL ?? summary.submitter.avatarURL,
            images: Array(images.compactMap(\.url530).prefix(8)),
            thumbnailURL: images.first.flatMap { $0.url220 ?? $0.url530 },
            version: profile.version.isEmpty ? summary.version : profile.version,
            updated: profile.dateUpdated ?? profile.dateAdded ?? summary.dateUpdated ?? summary.dateAdded ?? Date(timeIntervalSince1970: 0),
            pageURL: profile.profileURL ?? summary.profileURL ?? URL(string: "https://gamebanana.com/mods/\(profile.id)")!,
            description: GameBananaAPI.plainText(fromHTML: profile.text),
            likes: max(profile.likes, summary.likes), downloads: profile.downloads,
            files: files.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) })
    }
}

/// Whether an installed GameBanana mod has a newer file: only when the installed file is gone from the mod and a
/// working file was added after the install. A badge only; updating is a reinstall.
public enum ModUpdateCheck {
    public static func update(for record: ModRecord, in mod: AvailableMod) -> GameBananaFile? {
        guard let installed = record.gameBananaFileID, !mod.files.contains(where: { $0.id == installed }) else { return nil }
        let newer = mod.files.filter { file in
            guard let installedAt = record.installedAt else { return true }
            return (file.dateAdded ?? .distantPast) > installedAt
        }
        return newer.max { ($0.dateAdded ?? .distantPast) < ($1.dateAdded ?? .distantPast) }
    }
}
