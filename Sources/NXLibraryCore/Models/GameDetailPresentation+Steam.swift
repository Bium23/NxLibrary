import Foundation

extension GameDetailPresentation {
    /// A Steam game's page facts, for the same About, activity and stats views as an nxnative game.
    /// Facts delivered for another AppID are ignored; personal fields win. Nothing nxnative is
    /// claimed: no engine, build, sources or save folder, and Play waits for the Steam launch step.
    public init(steamRecord game: CatalogGame, metadata: SteamMetadata?,
                overrides: [MetadataField: String] = [:],
                totalPlaytime: TimeInterval, lastPlayed: Date?, now: Date = Date(),
                sessions: [PlaySession] = [], libraryGames: [CatalogGame] = [],
                playtimeByGame: [UUID: TimeInterval] = [:], calendar: Calendar = .current) {
        let appID = game.steamGame?.appID
        let facts = metadata.flatMap { $0.appID == appID ? $0 : nil }
        title = game.name
        console = "Mac"
        eyebrow = ""
        description = overrides[.description] ?? facts?.description ?? ""
        descriptionIsEnglishFallback = false
        descriptionLanguageNote = nil
        let genreNames = overrides[.genres].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            ?? facts?.genres ?? []
        genres = GameGenre.list(genreNames)
        // Steam's dates are display text in the store's language: shown as given, never re-parsed.
        let release = (overrides[.releaseDate] ?? facts?.releaseDate)?.trimmingCharacters(in: .whitespaces)
        released = release.flatMap { $0.isEmpty ? nil : $0 }
        releaseYear = release.flatMap { text in
            text.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression).map { String(text[$0]) }
        }
        let developers = overrides[.developer].map { [$0] } ?? facts?.developers ?? []
        let publishers = overrides[.publisher].map { [$0] } ?? facts?.publishers ?? []
        developerLine = [developers, publishers]
            .map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
            .first { !$0.isEmpty }?.joined(separator: ", ")
        publisher = publishers.first
        let week = Activity.summary(sessions: sessions.filter { $0.gameID == game.id }, now: now, calendar: calendar)
        thisWeek = LibraryPresentation.duration(week.thisWeek)
        rank = Self.rank(id: game.id, name: game.name, total: totalPlaytime,
                         others: libraryGames.filter { !$0.isHidden }.map { ($0.id, $0.name) }, playtimes: playtimeByGame)
        playtime = LibraryPresentation.duration(totalPlaytime)
        self.lastPlayed = LibraryPresentation.relative(lastPlayed, now: now)
        version = "—"
        size = "—"
        engineCommitShort = "—"
        toolchainVerified = false
        toolchainNote = nil
        canPlay = false
        canRebuild = false
        sourcesDetached = false
        hasBaseSource = false
        storeURL = appID.flatMap { URL(string: "https://store.steampowered.com/app/\($0)/") }
        hltbURL = Self.hltbURL(for: game.name)
        appPath = game.steamGame?.installations.first { $0.availability == .available }?.primaryApplication?.url.path ?? ""
        savePath = ""
    }
}
