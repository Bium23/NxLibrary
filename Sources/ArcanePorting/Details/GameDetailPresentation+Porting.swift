import Foundation
import NXLibraryCore

extension GameDetailPresentation {
    /// A ported game's page: the Nintendo store's facts, the build's engine and toolchain, its sources and save folder.
    public init(game: PortedGame, metadata: NintendoStoreMetadata?,
                totalPlaytime: TimeInterval, lastPlayed: Date?, now: Date = Date(),
                sessions: [PlaySession] = [], libraryGames: [PortedGame] = [],
                playtimeByGame: [UUID: TimeInterval] = [:],
                calendar: Calendar = .current, locale: Locale = L10n.context.formatLocale) {
        let title = game.name
        let console = game.consoleName
        let eyebrow = Self.eyebrow(from: metadata?.name ?? "")
        let description = metadata?.description ?? ""
        let descriptionIsEnglishFallback = L10n.context.metadataLanguage != "en" && metadata?.descriptionLanguage == "en" && !description.isEmpty
        let descriptionLanguage = metadata?.descriptionLanguage
        let descriptionSettled = metadata?.languageResolved(for: L10n.context) ?? true
        let descriptionLanguageNote: String?
        if let language = metadata?.descriptionLanguage, language != "custom",
           language != L10n.context.metadataLanguage, !description.isEmpty {
            let name = L10n.context.formatLocale.localizedString(forLanguageCode: language) ?? language
            descriptionLanguageNote = L10n.format("Description in %@.", [name])
        } else { descriptionLanguageNote = nil }
        let genres = GameGenre.list(metadata?.genres ?? [])
        let released = Self.released(metadata?.releaseDate, locale: locale)
        let developerLine = Self.credit(metadata)
        let week = Activity.summary(sessions: sessions.filter { $0.gameID == game.id }, now: now, calendar: calendar)
        let thisWeek = LibraryPresentation.duration(week.thisWeek)
        let rank = Self.rank(game: game, total: totalPlaytime, library: libraryGames, playtimes: playtimeByGame)
        let publisher = metadata?.publishers.first
        let releaseYear = metadata?.releaseYear
        let playtime = LibraryPresentation.duration(totalPlaytime)
        let lastPlayedText = LibraryPresentation.relative(lastPlayed, now: now)
        let version = game.versionString ?? "—"
        let size = game.sizeBytes.formatted(.byteCount(style: .file).locale(locale))
        let engineCommitShort = game.toolchain.engineCommit.map { String($0.prefix(7)) } ?? "—"
        let toolchainVerified = game.toolchain.verified
        let toolchainNote = game.toolchain.note
        let canPlay = game.isPlayableLocally
        let hasBaseSource = game.sources.contains { $0.type == .base }
        let canRebuild = GameResourceState.sourcesAvailable(for: game)
        let sourcesDetached = !canRebuild
        let storeURL = metadata?.storeURL
        let hltbURL = Self.hltbURL(for: game.name)
        let appPath = game.url.path
        let savePath: String
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
        self.init(title: title, console: console, eyebrow: eyebrow, description: description,
                  descriptionIsEnglishFallback: descriptionIsEnglishFallback,
                  descriptionLanguageNote: descriptionLanguageNote, descriptionLanguage: descriptionLanguage,
                  descriptionSettled: descriptionSettled, genres: genres, released: released,
                  developerLine: developerLine, thisWeek: thisWeek, rank: rank, publisher: publisher,
                  releaseYear: releaseYear, playtime: playtime, lastPlayed: lastPlayedText, version: version,
                  size: size, engineCommitShort: engineCommitShort, toolchainVerified: toolchainVerified,
                  toolchainNote: toolchainNote, canPlay: canPlay, canRebuild: canRebuild,
                  sourcesDetached: sourcesDetached, hasBaseSource: hasBaseSource, storeURL: storeURL,
                  hltbURL: hltbURL, appPath: appPath, savePath: savePath)
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
        rank(id: game.id, name: game.name, total: total,
             others: library.filter { !$0.isHidden }.map { ($0.id, $0.name) }, playtimes: playtimes)
    }
}
