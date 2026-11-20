import Foundation

/// Each game's mods that work, as last found, so the store opens from disk at once
/// (`~/Library/Caches/NXLibrary/gamebanana/store/<title ID>.json`). Links are checked again on the way in: only
/// GameBanana's survive, and a mod without a GameBanana page or a file to install is dropped.
public struct ModCatalogSnapshots: Sendable {
    public struct Snapshot: Equatable, Sendable {
        /// The game's title ID, upper case.
        public let titleID: String
        public let savedAt: Date
        public let gameName: String
        /// The GameBanana game the mods were found for: a snapshot of another one is not shown.
        public let gameBananaID: Int?
        public let mods: [AvailableMod]
    }

    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    public func load(titleID: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: file(titleID)),
              let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data), stored.version == 1 else { return nil }
        return Snapshot(titleID: titleID.uppercased(), savedAt: stored.savedAt, gameName: stored.gameName,
                        gameBananaID: stored.gameBananaID,
                        mods: stored.mods.compactMap(\.mod))
    }

    /// Every game's snapshot, for the Mods card's cover; a game whose GameBanana page is now another, or none,
    /// is left out.
    public func loadAll(matches: GameBananaMatchStore) -> [Snapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            let titleID = file.deletingPathExtension().lastPathComponent
            guard let snapshot = load(titleID: titleID),
                  case .game(let id, _, _) = matches.choice(titleID: titleID), id == snapshot.gameBananaID else { return nil }
            return snapshot
        }
    }

    public func save(_ mods: [AvailableMod], gameName: String, titleID: String, gameBananaID: Int,
                     at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stored = StoredSnapshot(version: 1, savedAt: date, gameName: gameName, gameBananaID: gameBananaID,
                                    mods: mods.map(StoredMod.init))
        try JSONEncoder().encode(stored).write(to: file(titleID), options: .atomic)
    }

    private func file(_ titleID: String) -> URL {
        let safe = titleID.uppercased().filter { $0.isLetter || $0.isNumber }
        return folder.appendingPathComponent(safe.isEmpty ? "unknown" : safe).appendingPathExtension("json")
    }
}

private struct StoredSnapshot: Codable {
    let version: Int
    let savedAt: Date
    let gameName: String
    let gameBananaID: Int?
    let mods: [StoredMod]
}

private func trusted(_ text: String?) -> URL? {
    guard let text, let url = URL(string: text), GameBananaAPI.trusted(url) else { return nil }
    return url
}

private struct StoredFile: Codable {
    let id: Int
    let name: String
    let size: Int64
    let downloadURL: String?
    let md5: String
    let dateAdded: Date?
    let downloads: Int
    let description: String

    init(_ file: GameBananaFile) {
        id = file.id
        name = file.name
        size = file.size
        downloadURL = file.downloadURL?.absoluteString
        md5 = file.md5
        dateAdded = file.dateAdded
        downloads = file.downloads
        description = file.description
    }

    var file: GameBananaFile? {
        guard let url = trusted(downloadURL) else { return nil }
        return GameBananaFile(id: id, name: name, size: size, downloadURL: url, md5: md5, dateAdded: dateAdded,
                              downloads: downloads, description: description)
    }
}

private struct StoredMod: Codable {
    let id: Int
    let rank: Int
    let name: String
    let author: String
    let avatarURL: String?
    let images: [String]
    let thumbnailURL: String?
    let version: String
    let updated: Date
    let pageURL: String
    let description: String
    let likes: Int
    let downloads: Int
    let files: [StoredFile]
    let category: String
    let added: Date?
    /// Missing in snapshots written before 0.1.4.1.
    let requirements: [GameBananaRequirement]?

    init(_ mod: AvailableMod) {
        id = mod.id
        rank = mod.rank
        name = mod.name
        author = mod.author
        avatarURL = mod.avatarURL?.absoluteString
        images = mod.images.map(\.absoluteString)
        thumbnailURL = mod.thumbnailURL?.absoluteString
        version = mod.version
        updated = mod.updated
        pageURL = mod.pageURL.absoluteString
        description = mod.description
        likes = mod.likes
        downloads = mod.downloads
        files = mod.files.map(StoredFile.init)
        category = mod.category
        added = mod.added
        requirements = mod.requirements
    }

    var mod: AvailableMod? {
        let files = self.files.compactMap(\.file)
        guard let page = trusted(pageURL), !files.isEmpty else { return nil }
        return AvailableMod(id: id, rank: rank, name: name, author: author, avatarURL: trusted(avatarURL),
                            images: images.compactMap { trusted($0) }, thumbnailURL: trusted(thumbnailURL),
                            version: version, updated: updated, pageURL: page, description: description,
                            likes: likes, downloads: downloads, files: files, category: category, added: added,
                            requirements: requirements ?? [])
    }
}
