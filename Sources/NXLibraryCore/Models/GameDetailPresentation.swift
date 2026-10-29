import Foundation

public struct GameDetailPresentation: Equatable {
    public let title: String
    public let eyebrow: String
    public let description: String
    public let genres: [String]
    public let released: String?
    public let developerLine: String?
    public let thisWeek: String
    public let rank: String?
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
                totalPlaytime: TimeInterval, lastPlayed: Date?, now: Date = Date(),
                sessions: [PlaySession] = [], libraryGames: [PortedGame] = [],
                playtimeByGame: [UUID: TimeInterval] = [:],
                calendar: Calendar = .current, locale: Locale = .current,
                timeZone: TimeZone = .current) {
        title = game.name
        eyebrow = Self.eyebrow(from: metadata?.name ?? "")
        description = metadata?.description ?? ""
        var seenGenres = Set<String>()
        genres = (metadata?.genres ?? []).filter {
            let g = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !g.isEmpty && g.caseInsensitiveCompare("Other") != .orderedSame && seenGenres.insert(g).inserted
        }
        released = Self.released(metadata?.releaseDate, locale: locale, timeZone: timeZone)
        developerLine = Self.credit(metadata)
        let week = Activity.summary(sessions: sessions.filter { $0.gameID == game.id }, now: now, calendar: calendar)
        thisWeek = LibraryPresentation.duration(week.thisWeek)
        rank = Self.rank(game: game, total: totalPlaytime, library: libraryGames, playtimes: playtimeByGame)
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

    private static func released(_ raw: String?, locale: Locale, timeZone: TimeZone) -> String? {
        guard let raw else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(raw.prefix(10))) else { return nil }
        let out = DateFormatter()
        out.locale = locale
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateStyle = .short
        out.timeStyle = .none
        return out.string(from: date)
    }

    private static func credit(_ metadata: NintendoStoreMetadata?) -> String? {
        guard let metadata else { return nil }
        for list in [metadata.developers, metadata.publishers] {
            let names = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !names.isEmpty { return names.joined(separator: ", ") }
        }
        return nil
    }

    private static func rank(game: PortedGame, total: TimeInterval, library: [PortedGame],
                             playtimes: [UUID: TimeInterval]) -> String? {
        guard total > 0 else { return nil }
        var entries: [(name: String, time: TimeInterval)] = [(game.name, total)]
        for other in library where other.id != game.id && !other.isHidden {
            if let t = playtimes[other.id], t > 0 { entries.append((other.name, t)) }
        }
        entries.sort { a, b in
            a.time != b.time ? a.time > b.time
                : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        let position = (entries.firstIndex { $0.name == game.name && $0.time == total } ?? 0) + 1
        return "#\(position) of \(entries.count)"
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
