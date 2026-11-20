import Foundation

public struct GameDetailPresentation: Equatable {
    public let title: String
    /// "Nintendo Switch 2" for a Switch 2 title, else "Nintendo Switch".
    public let console: String
    public let eyebrow: String
    public let description: String
    public let descriptionIsEnglishFallback: Bool
    public let descriptionLanguageNote: String?
    /// The store's word on the description's language ("en", "it"), "custom" for the player's own choice, or nil when
    /// the store does not say (Steam). `WikipediaDescriptions.wanted` reads it with the text.
    public let descriptionLanguage: String?
    /// The store's answer in the app language is final (`NintendoStoreMetadata.languageResolved`); until then the
    /// page shows the old text and Wikipedia is not asked, so the text changes once, not twice.
    public let descriptionSettled: Bool
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

    static func released(_ raw: String?, locale: Locale) -> String? {
        // Release dates are timezone-neutral: parse and format in UTC.
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

    /// "#2 of 5" among the visible games with play time, whatever their source.
    static func rank(id: UUID, name: String, total: TimeInterval, others: [(id: UUID, name: String)],
                     playtimes: [UUID: TimeInterval]) -> String? {
        guard total > 0 else { return nil }
        var entries: [(id: UUID, name: String, time: TimeInterval)] = [(id, name, total)]
        for other in others where other.id != id {
            if let t = playtimes[other.id], t > 0 { entries.append((other.id, other.name, t)) }
        }
        let game = (id: id, name: name)
        entries.sort { a, b in
            if a.time != b.time { return a.time > b.time }
            let c = a.name.localizedCaseInsensitiveCompare(b.name)
            return c != .orderedSame ? c == .orderedAscending : a.id.uuidString < b.id.uuidString
        }
        let position = (entries.firstIndex { $0.id == game.id } ?? 0) + 1
        return "#\(position) of \(entries.count)"
    }

    static func eyebrow(from name: String) -> String {
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

    static func hltbURL(for name: String) -> URL? {
        var components = URLComponents(string: "https://howlongtobeat.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: name)]
        return components?.url
    }
}
