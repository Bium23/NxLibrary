import Foundation

public struct LibraryPresentation: Equatable {
    public let title: String
    public let eyebrow: String
    public let genres: [String]
    public let publisher: String?
    public let releaseYear: String?
    public let playtime: String
    public let lastPlayed: String
    public let platform: String
    /// "Nintendo Switch 2" for a Switch 2 title (ID starting 04), else "Nintendo Switch".
    public let console: String
    public let sourcesDetached: Bool
    public let summary: String

    public init(game: PortedGame, metadata: NintendoStoreMetadata?,
                totalPlaytime: TimeInterval, lastPlayed: Date?, now: Date = Date()) {
        title = game.name
        eyebrow = metadata.map { Self.eyebrow(from: $0.name) } ?? ""
        genres = Array(GameGenre.list(metadata?.genres ?? []).prefix(3))
        publisher = metadata?.publishers.first
        releaseYear = metadata?.releaseYear
        playtime = Self.duration(totalPlaytime)
        self.lastPlayed = Self.relative(lastPlayed, now: now)
        platform = "nxnative"
        console = game.consoleName
        sourcesDetached = !SourceSelection.hasGame(game.sources)
        summary = (metadata?.description ?? "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func eyebrow(from name: String) -> String {
        let separators = [":", " – "]
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

    static func duration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "—" }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return L10n.format("%@m", [minutes.formatted(.number.locale(L10n.context.formatLocale))]) }
        return L10n.format("%@h %@m", [hours.formatted(.number.locale(L10n.context.formatLocale)), minutes.formatted(.number.locale(L10n.context.formatLocale))])
    }

    static func relative(_ date: Date?, now: Date) -> String {
        guard let date else { return L10n.text("Never") }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return L10n.text("Just now") }
        if seconds < 3_600 { return L10n.format("%@m ago", [String(describing: (Int(seconds / 60)))]) }
        if seconds < 86_400 { return L10n.format("%@h ago", [String(describing: (Int(seconds / 3_600)))]) }
        if seconds < 604_800 { return L10n.format("%@d ago", [String(describing: (Int(seconds / 86_400)))]) }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.context.formatLocale))
    }
}
