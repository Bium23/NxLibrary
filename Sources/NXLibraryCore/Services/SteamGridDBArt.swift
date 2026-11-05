import Foundation

/// The player's SteamGridDB API key (generated in their SteamGridDB profile), kept on this Mac in a private file
/// (mode 0600) beside NX Library's other data. Never logged and never sent anywhere but SteamGridDB's API.
public struct SteamGridDBKey {
    public let url: URL
    private let fm = FileManager.default

    public init(url: URL = SteamGridDBKey.defaultURL()) { self.url = url }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NXLibrary/steamgriddb-api-key")
    }

    /// A key as SteamGridDB writes it: letters and digits only (its keys are 32 hex digits).
    public static func normalized(_ text: String) -> String? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...128).contains(key.count), key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return key
    }

    public func load() -> String? {
        (try? String(contentsOf: url, encoding: .utf8)).flatMap(Self.normalized)
    }

    public func save(_ key: String) throws {
        guard let key = Self.normalized(key) else { throw SteamGridDBError.invalidKey }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard fm.createFile(atPath: tmp.path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw SteamGridDBError.notSaved
        }
        guard rename(tmp.path, url.path) == 0 else {
            try? fm.removeItem(at: tmp)
            throw SteamGridDBError.notSaved
        }
    }

    public func remove() throws {
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
    }
}

public enum SteamGridDBError: LocalizedError, Equatable {
    case invalidKey, rejected, unreachable, notSaved

    public var errorDescription: String? {
        switch self {
        case .invalidKey: return "That is not a SteamGridDB API key. Copy it from Preferences → API in your SteamGridDB profile."
        case .rejected: return "SteamGridDB did not accept that key. Check it in Preferences → API in your SteamGridDB profile."
        case .unreachable: return "SteamGridDB could not be reached. Check the connection and try again."
        case .notSaved: return "The key could not be saved on this Mac."
        }
    }
}

/// SteamGridDB (https://www.steamgriddb.com), through its official API v2 with the player's own key: community art
/// for covers (grids), backgrounds (heroes), logos and icons, browsed from Change artwork with each author's name.
/// Only still images; art tagged NSFW, humor or epilepsy is left out.
public enum SteamGridDBArt {
    static let api = URL(string: "https://www.steamgriddb.com/api/v2/")!
    public static let keyPage = URL(string: "https://www.steamgriddb.com/profile/preferences/api")!
    public static let site = URL(string: "https://www.steamgriddb.com")!
    /// Images kept per kind of art.
    static let limit = 12
    static let filters = "types=static&nsfw=false&humor=false&epilepsy=false&limit=\(limit)"

    static func request(_ url: URL, key: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("NXLibrary/0.1 (macOS; personal app)", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func searchURL(_ term: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let path = term.addingPercentEncoding(withAllowedCharacters: allowed), !path.isEmpty else { return nil }
        return URL(string: "search/autocomplete/\(path)", relativeTo: api)?.absoluteURL
    }

    /// Checks a key with one search: accepted, refused (401/403) or not reached.
    public static func check(key: String, client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> Result<Void, SteamGridDBError> {
        guard let url = searchURL("zelda") else { return .failure(.unreachable) }
        guard let (_, http) = try? await client.data(for: request(url, key: key)) else { return .failure(.unreachable) }
        switch http.statusCode {
        case 200..<300: return .success(())
        case 401, 403: return .failure(.rejected)
        default: return .failure(.unreachable)
        }
    }

    /// The SteamGridDB game whose name is one of the game's names (an edition counts, a sequel does not).
    /// `loose` (a name the player typed) takes SteamGridDB's first result when none matches.
    public static func gameID(in data: Data, matching names: [String], loose: Bool = false) -> Int? {
        struct Wire: Decodable { struct Game: Decodable { var id: Int; var name: String }; var data: [Game]? }
        guard let games = (try? JSONDecoder().decode(Wire.self, from: data))?.data else { return nil }
        return games.first { ArtworkNames.matches($0.name, names) }?.id ?? (loose ? games.first?.id : nil)
    }

    /// One listing (grids, heroes, logos, icons) → candidates, credited to their authors: the thumbnail as preview,
    /// the full file and its size for a choice.
    public static func candidates(in data: Data, slot: ArtworkSlot) -> [ArtworkCandidate] {
        struct Wire: Decodable {
            struct Author: Decodable { var name: String? }
            struct Item: Decodable { var url: String; var thumb: String?; var width: Int?; var height: Int?; var author: Author? }
            var data: [Item]?
        }
        let items = (try? JSONDecoder().decode(Wire.self, from: data))?.data ?? []
        return items.prefix(limit).compactMap { item in
            guard let url = URL(string: item.url), url.scheme == "https" else { return nil }
            let thumb = item.thumb.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            let author = item.author?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = author.map { $0.isEmpty ? "SteamGridDB" : "SteamGridDB · \($0)" } ?? "SteamGridDB"
            return ArtworkCandidate(slot: slot, source: source, url: thumb ?? url, full: thumb == nil ? nil : url,
                                    width: item.width, height: item.height)
        }
    }

    /// The listings each slot is filled from: covers are portrait grids, icons are SteamGridDB's icons then its
    /// square grids.
    static func listings(gameID: Int) -> [(ArtworkSlot, String)] {
        [(.cover, "grids/game/\(gameID)?dimensions=600x900,660x930&\(filters)"),
         (.background, "heroes/game/\(gameID)?\(filters)"),
         (.logo, "logos/game/\(gameID)?\(filters)"),
         (.icon, "icons/game/\(gameID)?\(filters)"),
         (.icon, "grids/game/\(gameID)?dimensions=512x512,1024x1024&\(filters)")]
    }

    /// The game's page on SteamGridDB, which X opens from Change artwork.
    public static func page(gameID: Int) -> URL { site.appendingPathComponent("game/\(gameID)") }

    /// A game SteamGridDB lists: its page and its art.
    public struct Game: Equatable, Sendable {
        public let page: URL
        public let candidates: [ArtworkCandidate]
    }

    public static func game(names: [String], key: String, slot: ArtworkSlot? = nil, loose: Bool = false,
                            client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> Game? {
        var id: Int?
        for name in names {
            guard let url = searchURL(name),
                  let (data, http) = try? await client.data(for: request(url, key: key)),
                  (200..<300).contains(http.statusCode) else { continue }
            if let found = gameID(in: data, matching: names, loose: loose) { id = found; break }
        }
        guard let id else { return nil }
        let wanted = listings(gameID: id).filter { slot == nil || $0.0 == slot }
        let candidates = await withTaskGroup(of: (Int, [ArtworkCandidate]).self) { group in
            for (index, listing) in wanted.enumerated() {
                group.addTask {
                    guard let url = URL(string: listing.1, relativeTo: api)?.absoluteURL,
                          let (data, http) = try? await client.data(for: request(url, key: key)),
                          (200..<300).contains(http.statusCode) else { return (index, []) }
                    return (index, candidates(in: data, slot: listing.0))
                }
            }
            var parts: [(Int, [ArtworkCandidate])] = []
            for await part in group { parts.append(part) }
            return parts.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
        return Game(page: page(gameID: id), candidates: candidates)
    }
}
