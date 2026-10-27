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
    public let sourcesDetached: Bool

    public init(game: PortedGame, metadata: NintendoStoreMetadata?,
                totalPlaytime: TimeInterval, lastPlayed: Date?, now: Date = Date()) {
        title = game.name
        eyebrow = metadata.map { Self.eyebrow(from: $0.name) } ?? ""
        genres = Array((metadata?.genres ?? []).prefix(3))
        publisher = metadata?.publishers.first
        releaseYear = metadata?.releaseYear
        playtime = Self.duration(totalPlaytime)
        self.lastPlayed = Self.relative(lastPlayed, now: now)
        platform = "nxnative"
        sourcesDetached = !game.sources.contains { $0.type == .base }
    }

    private static func eyebrow(from name: String) -> String {
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

    static func duration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "—" }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }

    static func relative(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))d ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
