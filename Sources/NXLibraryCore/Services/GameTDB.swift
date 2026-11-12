import Foundation

/// One Switch game in GameTDB (gametdb.com): what NX Library keeps from its
/// English database for box covers and metadata.
public struct GameTDBEntry: Codable, Equatable {
    /// GameTDB's id, the product code without HAC- ("AAAAA" is one retail title).
    public var id: String
    public var title: String
    /// "ALL", "NTSC-U", "PAL", "NTSC-J"…
    public var region: String?
    public var synopsis: String?
    public var developer: String?
    public var publisher: String?
    /// "2017-03-03", or as much of it as GameTDB knows.
    public var releaseDate: String?
    public var genres: [String]

    public init(id: String, title: String, region: String? = nil, synopsis: String? = nil,
                developer: String? = nil, publisher: String? = nil, releaseDate: String? = nil,
                genres: [String] = []) {
        self.id = id
        self.title = title
        self.region = region
        self.synopsis = synopsis
        self.developer = developer
        self.publisher = publisher
        self.releaseDate = releaseDate
        self.genres = genres
    }
}

/// GameTDB's Switch database: box covers by product code, found by name, since
/// its file carries no title ID. GameTDB allows use in software with a link back.
public enum GameTDB {
    public static let databaseURL = URL(string: "https://www.gametdb.com/switchtdb.zip?LANG=EN")!
    public static let siteURL = URL(string: "https://www.gametdb.com")!
    /// Cover regions, most widely used art first.
    public static let coverRegions = ["US", "EN", "FR", "DE", "IT", "ES", "NL", "JA", "KO", "ZH"]

    public enum Failure: LocalizedError {
        case unreadable
        public var errorDescription: String? { L10n.text("GameTDB's database could not be read.") }
    }

    public static func parse(_ data: Data) throws -> [GameTDBEntry] {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw Failure.unreadable }
        return reader.entries
    }

    /// Lowercased, without ™ ® © and punctuation, "&" read as "and", single spaces.
    public static func normalize(_ name: String) -> String {
        var text = name.lowercased()
        for mark in ["™", "®", "©"] { text = text.replacingOccurrences(of: mark, with: "") }
        text = text.replacingOccurrences(of: "&", with: " and ")
        let words = text.split { !($0.isLetter || $0.isNumber) }
        return words.joined(separator: " ")
    }

    /// The one entry whose normalised title equals `name`'s; the widest region wins a tie.
    public static func exactMatch(for name: String, in entries: [GameTDBEntry]) -> GameTDBEntry? {
        exactMatches(for: name, in: entries).first
    }

    /// Every entry whose normalised title equals `name`'s, widest region first.
    public static func exactMatches(for name: String, in entries: [GameTDBEntry]) -> [GameTDBEntry] {
        let key = normalize(name)
        guard !key.isEmpty else { return [] }
        return entries.filter { normalize($0.title) == key }.sorted { regionRank($0) < regionRank($1) }
    }

    /// Entries worth showing for `name`: exact titles first, then titles that
    /// contain every word of it or share most of their words with it.
    public static func candidates(for name: String, in entries: [GameTDBEntry], limit: Int = 12) -> [GameTDBEntry] {
        let query = Set(normalize(name).split(separator: " "))
        guard !query.isEmpty else { return [] }
        var scored: [(entry: GameTDBEntry, score: Double)] = []
        for entry in entries {
            let words = Set(normalize(entry.title).split(separator: " "))
            guard !words.isEmpty else { continue }
            let shared = Double(query.intersection(words).count)
            let overlap = shared / Double(query.union(words).count)
            if overlap == 1 || query.isSubset(of: words) || overlap >= 0.6 {
                scored.append((entry, overlap))
            }
        }
        return scored.sorted {
            $0.score != $1.score ? $0.score > $1.score : regionRank($0.entry) < regionRank($1.entry)
        }.prefix(limit).map(\.entry)
    }

    /// High-quality covers (1166×1888) for `id`, one per region, to try in order.
    public static func coverURLs(id: String) -> [URL] {
        guard (4...6).contains(id.count), id.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return [] }
        return coverRegions.compactMap { URL(string: "https://art.gametdb.com/switch/coverHQ/\($0)/\(id).jpg") }
    }

    private static func regionRank(_ entry: GameTDBEntry) -> Int {
        switch entry.region {
        case "ALL": return 0
        case "NTSC-U": return 1
        case "PAL": return 2
        default: return 3
        }
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var entries: [GameTDBEntry] = []
        private var game: GameTDBEntry?
        private var locale: String?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            text = ""
            switch element {
            case "game": game = GameTDBEntry(id: "", title: "")
            case "locale": locale = attributes["lang"]
            case "date" where game != nil:
                let parts = [attributes["year"], attributes["month"], attributes["day"]]
                    .compactMap { $0 }.filter { !$0.isEmpty && $0 != "0" }
                if let year = parts.first {
                    game?.releaseDate = ([year] + parts.dropFirst().map { $0.count == 1 ? "0" + $0 : $0 })
                        .joined(separator: "-")
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            guard game != nil else { return }
            let english = locale == "EN"
            switch element {
            case "id": game?.id = value
            case "region": game?.region = value.isEmpty ? nil : value
            case "title" where english: game?.title = value
            case "synopsis" where english: game?.synopsis = value.isEmpty ? nil : value
            case "developer": game?.developer = value.isEmpty ? nil : value
            case "publisher": game?.publisher = value.isEmpty ? nil : value
            case "genre": game?.genres = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case "locale": locale = nil
            case "game":
                if let game, !game.id.isEmpty, !game.title.isEmpty { entries.append(game) }
                game = nil
            default: break
            }
        }
    }
}

/// The local copy of GameTDB's index, refreshed when older than 30 days.
public struct GameTDBStore {
    public static let maxAge: TimeInterval = 30 * 24 * 3600
    public let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("gametdb.json") }

    private struct Snapshot: Codable {
        var fetchedAt: Date
        var entries: [GameTDBEntry]
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() -> [GameTDBEntry]? {
        snapshot()?.entries
    }

    public func isStale(now: Date) -> Bool {
        guard let snapshot = snapshot() else { return true }
        return now.timeIntervalSince(snapshot.fetchedAt) > Self.maxAge
    }

    public func save(_ entries: [GameTDBEntry], at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Snapshot(fetchedAt: date, entries: entries)).write(to: fileURL, options: .atomic)
    }

    private func snapshot() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
