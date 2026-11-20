import Foundation

extension GameDetailPresentation {
    /// A ported game's page: the Nintendo store's facts, the build's engine and toolchain, its sources and save folder.
    public init(game: PortedGame, metadata: NintendoStoreMetadata?,
                totalPlaytime: TimeInterval, lastPlayed: Date?, now: Date = Date(),
                sessions: [PlaySession] = [], libraryGames: [PortedGame] = [],
                playtimeByGame: [UUID: TimeInterval] = [:],
                calendar: Calendar = .current, locale: Locale = L10n.context.formatLocale) {
        title = game.name
        console = game.consoleName
        eyebrow = Self.eyebrow(from: metadata?.name ?? "")
        description = metadata?.description ?? ""
        descriptionIsEnglishFallback = L10n.context.metadataLanguage != "en" && metadata?.descriptionLanguage == "en" && !description.isEmpty
        descriptionLanguage = metadata?.descriptionLanguage
        descriptionSettled = metadata?.languageResolved(for: L10n.context) ?? true
        if let language = metadata?.descriptionLanguage, language != "custom",
           language != L10n.context.metadataLanguage, !description.isEmpty {
            let name = L10n.context.formatLocale.localizedString(forLanguageCode: language) ?? language
            descriptionLanguageNote = L10n.format("Description in %@.", [name])
        } else { descriptionLanguageNote = nil }
        genres = GameGenre.list(metadata?.genres ?? [])
        released = Self.released(metadata?.releaseDate, locale: locale)
        developerLine = Self.credit(metadata)
        let week = Activity.summary(sessions: sessions.filter { $0.gameID == game.id }, now: now, calendar: calendar)
        thisWeek = LibraryPresentation.duration(week.thisWeek)
        rank = Self.rank(game: game, total: totalPlaytime, library: libraryGames, playtimes: playtimeByGame)
        publisher = metadata?.publishers.first
        releaseYear = metadata?.releaseYear
        playtime = LibraryPresentation.duration(totalPlaytime)
        self.lastPlayed = LibraryPresentation.relative(lastPlayed, now: now)
        version = game.versionString ?? "—"
        size = game.sizeBytes.formatted(.byteCount(style: .file).locale(locale))
        engineCommitShort = game.toolchain.engineCommit.map { String($0.prefix(7)) } ?? "—"
        toolchainVerified = game.toolchain.verified
        toolchainNote = game.toolchain.note
        canPlay = game.isPlayableLocally
        hasBaseSource = game.sources.contains { $0.type == .base }
        canRebuild = GameResourceState.sourcesAvailable(for: game)
        sourcesDetached = !canRebuild
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
