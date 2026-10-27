import Foundation

public struct GameDetailPresentation: Equatable {
    public let title: String
    public let eyebrow: String
    public let description: String
    public let genres: [String]
    public let publisher: String?
    public let releaseYear: String?
    public let playtime: String
    public let lastPlayed: String
    public let version: String
    public let size: String
    public let engineCommitShort: String
    public let toolchainVerified: Bool
    public let toolchainNote: String?
    public let canPlay: Bool
    public let canRebuild: Bool
    public let sourcesDetached: Bool
    public let hasBaseSource: Bool
    public let storeURL: URL?
    public let hltbURL: URL?
    public let appPath: String
    public let savePath: String

    public init(game: PortedGame, metadata: NintendoStoreMetadata?,
                totalPlaytime: TimeInterval, lastPlayed: Date?, now: Date = Date()) {
        title = game.name
        eyebrow = Self.eyebrow(from: metadata?.name ?? "")
        description = metadata?.description ?? ""
        genres = metadata?.genres ?? []
        publisher = metadata?.publishers.first
        releaseYear = metadata?.releaseYear
        playtime = LibraryPresentation.duration(totalPlaytime)
        self.lastPlayed = LibraryPresentation.relative(lastPlayed, now: now)
        version = game.versionString ?? "—"
        size = ByteCountFormatter.string(fromByteCount: game.sizeBytes, countStyle: .file)
        engineCommitShort = game.toolchain.engineCommit.map { String($0.prefix(7)) } ?? "—"
        toolchainVerified = game.toolchain.verified
        toolchainNote = game.toolchain.note
        canPlay = game.isPlayableLocally
        hasBaseSource = game.sources.contains { $0.type == .base }
        canRebuild = hasBaseSource
        sourcesDetached = !hasBaseSource
        storeURL = metadata?.storeURL
        hltbURL = Self.hltbURL(for: game.name)
        appPath = game.url.path
        if let titleID = game.titleId, !titleID.isEmpty {
            savePath = NSHomeDirectory() + "/Library/Application Support/nxnative/\(titleID)/save"
        } else if let bundleID = game.bundleId, !bundleID.isEmpty {
            savePath = NSHomeDirectory() + "/Library/Application Support/\(bundleID)/save"
        } else {
            let safe = game.name.replacingOccurrences(
                of: "[^a-zA-Z0-9._-]",
                with: "_",
                options: .regularExpression
            )
            savePath = NSHomeDirectory() + "/Library/Application Support/nxnative/\(safe)/save"
        }
    }

    private static func eyebrow(from name: String) -> String {
        guard !name.isEmpty else { return "" }
        let separators = [":", "™", " – "]
        for separator in separators {
            if let range = name.range(of: separator) {
                let prefix = name[..<range.lowerBound]
                    .replacingOccurrences(of: "™", with: "")
                    .replacingOccurrences(of: "®", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !prefix.isEmpty, prefix != name { return prefix }
            }
        }
        return ""
    }

    private static func hltbURL(for name: String) -> URL? {
        var components = URLComponents(string: "https://howlongtobeat.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: name)]
        return components?.url
    }
}
