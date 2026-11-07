import Foundation

/// GameBanana's public API: the apiv11 JSON endpoints for games, a game's mods and one mod, and the legacy Core API
/// for an archive's file list (one file per request: several ids return an empty body). Shapes verified 2026-11-06.
/// Optional keys are often missing, and PHP sends `[]` for an empty object, so every model decodes leniently.
public enum GameBananaAPI {
    static let base = "https://gamebanana.com/apiv11/"

    public static func gameSearchURL(_ name: String, page: Int = 1) -> URL {
        url(base + "Util/Search/Results", [("_sModelName", "Game"), ("_sSearchString", name), ("_nPage", "\(page)")])
    }

    public static func modIndexURL(gameID: Int, page: Int, perPage: Int) -> URL {
        url(base + "Mod/Index", [("_aFilters[Generic_Game]", "\(gameID)"), ("_nPage", "\(page)"),
                                 ("_nPerpage", "\(perPage)"), ("_sSort", "Generic_MostDownloaded")])
    }

    public static func profileURL(modID: Int) -> URL {
        URL(string: base + "Mod/\(modID)/ProfilePage")!
    }

    public static func archiveListURL(fileID: Int) -> URL {
        URL(string: "https://api.gamebanana.com/Core/Item/Data?itemtype=File&itemid=\(fileID)&fields=Metadata().aArchiveFilesList()")!
    }

    /// Only `https` on gamebanana.com or one of its subdomains: API, downloads (gamebanana.com/dl → files → filecacheNN)
    /// and images (images.gamebanana.com).
    public static func trusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "gamebanana.com" || host.hasSuffix(".gamebanana.com")
    }

    /// The paths inside an archive, from `[[path, …]]`; nil when the body is not that JSON.
    public static func archivePaths(in data: Data) -> [String]? {
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        guard let first = outer.first else { return [] }
        return (first as? [Any])?.compactMap { $0 as? String }
    }

    /// A mod description as plain text: line breaks and list items kept, every other tag dropped, entities decoded.
    /// A string pass only: nothing in the description is ever loaded.
    public static func plainText(fromHTML html: String) -> String {
        var text = html
        let rules: [(String, String)] = [
            ("<li[^>]*>", "\n• "),
            ("<br\\s*/?>|</p>|</div>|</li>|</h[1-6]>", "\n"),
            ("<[^>]*>", ""),
        ]
        for (pattern, replacement) in rules {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        text = decodeEntities(text)
        let lines = text.components(separatedBy: "\n").map { line -> String in
            var line = line
            while line.last == " " || line.last == "\t" { line.removeLast() }
            return line
        }
        text = lines.joined(separator: "\n")
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals

    private static let queryAllowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private static func url(_ path: String, _ items: [(String, String)]) -> URL {
        let query = items.map { name, value in
            "\(name.addingPercentEncoding(withAllowedCharacters: queryAllowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: queryAllowed)!)"
        }.joined(separator: "&")
        return URL(string: path + "?" + query)!
    }

    private static func decodeEntities(_ text: String) -> String {
        var text = text
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                ("&nbsp;", " "), ("&#160;", " ")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let whole = Range(match.range, in: text), let digits = Range(match.range(at: 2), in: text) else { continue }
                let hex = match.range(at: 1).length > 0
                if let code = UInt32(text[digits], radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    text.replaceSubrange(whole, with: String(Character(scalar)))
                }
            }
        }
        return text.replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - Models

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension KeyedDecodingContainer where Key == AnyKey {
    func value<T: Decodable>(_ key: String, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: AnyKey(key))) ?? fallback
    }
    func optional<T: Decodable>(_ key: String) -> T? {
        (try? decodeIfPresent(T.self, forKey: AnyKey(key))) ?? nil
    }
    func required<T: Decodable>(_ key: String) throws -> T {
        try decode(T.self, forKey: AnyKey(key))
    }
    func date(_ key: String) -> Date? {
        optional(key).map { (seconds: Int) in Date(timeIntervalSince1970: TimeInterval(seconds)) }
    }
    /// A GameBanana link: anything that is not https on a GameBanana host is dropped, so nothing from the API can
    /// make NX Library open or fetch somewhere else.
    func url(_ key: String) -> URL? {
        optional(key).flatMap { (string: String) in URL(string: string) }.flatMap { GameBananaAPI.trusted($0) ? $0 : nil }
    }
    /// `_aPreviewMedia._aImages`, or nothing when the media object is missing or `[]`.
    func previewImages<T: Decodable>() -> [T] {
        guard let media = try? nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("_aPreviewMedia")) else { return [] }
        return media.value("_aImages", [T]())
    }
}

public struct GameBananaGame: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let profileURL: URL?
    public let iconURL: URL?
    public let hasContentRatings: Bool

    public init(id: Int, name: String, profileURL: URL? = nil, iconURL: URL? = nil, hasContentRatings: Bool = false) {
        self.id = id
        self.name = name
        self.profileURL = profileURL
        self.iconURL = iconURL
        self.hasContentRatings = hasContentRatings
    }

    private struct Media: Decodable {
        let type: String?
        let url: String?
        enum CodingKeys: String, CodingKey { case type = "_sType", url = "_sUrl" }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try c.required("_idRow")
        name = try c.required("_sName")
        profileURL = c.url("_sProfileUrl")
        let images: [Media] = c.previewImages()
        iconURL = (images.first { $0.type == "icon" } ?? images.first)?.url.flatMap(URL.init(string:))
        hasContentRatings = c.value("_bHasContentRatings", false)
    }
}

public struct GameBananaGamePage: Decodable, Sendable {
    public let records: [GameBananaGame]
    public let isComplete: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        records = c.value("_aRecords", [GameBananaGame]())
        isComplete = (try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("_aMetadata")))?.value("_bIsComplete", true) ?? true
    }
}

public struct GameBananaImage: Decodable, Equatable, Sendable {
    public let baseURL: String?
    public let file: String?
    public let file220: String?
    public let file530: String?

    public init(baseURL: String?, file: String?, file220: String? = nil, file530: String? = nil) {
        self.baseURL = baseURL
        self.file = file
        self.file220 = file220
        self.file530 = file530
    }

    enum CodingKeys: String, CodingKey {
        case baseURL = "_sBaseUrl", file = "_sFile", file220 = "_sFile220", file530 = "_sFile530"
    }

    public var url530: URL? { join(file530 ?? file) }
    public var url220: URL? { join(file220 ?? file530 ?? file) }

    private func join(_ name: String?) -> URL? {
        guard let baseURL, let name, !name.isEmpty else { return nil }
        return URL(string: baseURL + "/" + name)
    }
}

public struct GameBananaSubmitter: Decodable, Equatable, Sendable {
    public let name: String
    public let avatarURL: URL?

    public init(name: String, avatarURL: URL? = nil) {
        self.name = name
        self.avatarURL = avatarURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.value("_sName", "")
        avatarURL = c.url("_sAvatarUrl")
    }
}

public struct GameBananaModSummary: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let profileURL: URL?
    public let version: String
    public let isObsolete: Bool
    public let hasContentRatings: Bool
    public let images: [GameBananaImage]
    public let submitter: GameBananaSubmitter
    public let likes: Int
    public let dateAdded: Date?
    public let dateUpdated: Date?
    /// The root category's name in the game ("Skins", "Maps"…).
    public let rootCategory: String

    public init(id: Int, name: String, profileURL: URL? = nil, version: String = "", isObsolete: Bool = false,
                hasContentRatings: Bool = false, images: [GameBananaImage] = [],
                submitter: GameBananaSubmitter = GameBananaSubmitter(name: ""), likes: Int = 0,
                dateAdded: Date? = nil, dateUpdated: Date? = nil, rootCategory: String = "") {
        self.id = id
        self.name = name
        self.profileURL = profileURL
        self.version = version
        self.isObsolete = isObsolete
        self.hasContentRatings = hasContentRatings
        self.images = images
        self.submitter = submitter
        self.likes = likes
        self.dateAdded = dateAdded
        self.dateUpdated = dateUpdated
        self.rootCategory = rootCategory
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try c.required("_idRow")
        name = c.value("_sName", "")
        profileURL = c.url("_sProfileUrl")
        version = c.value("_sVersion", "")
        isObsolete = c.value("_bIsObsolete", false)
        hasContentRatings = c.value("_bHasContentRatings", false)
        images = c.previewImages()
        submitter = c.value("_aSubmitter", GameBananaSubmitter(name: ""))
        likes = c.value("_nLikeCount", 0)
        dateAdded = c.date("_tsDateAdded")
        dateUpdated = c.date("_tsDateUpdated")
        rootCategory = (try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("_aRootCategory")))?.value("_sName", "") ?? ""
    }
}

public struct GameBananaModPage: Decodable, Sendable {
    public let records: [GameBananaModSummary]
    public let isComplete: Bool

    public init(records: [GameBananaModSummary], isComplete: Bool) {
        self.records = records
        self.isComplete = isComplete
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        records = c.value("_aRecords", [GameBananaModSummary]())
        isComplete = (try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("_aMetadata")))?.value("_bIsComplete", true) ?? true
    }
}

public struct GameBananaFile: Decodable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let size: Int64
    public let downloadURL: URL?
    public let md5: String
    public let dateAdded: Date?
    public let downloads: Int
    public let description: String

    public init(id: Int, name: String, size: Int64, downloadURL: URL?, md5: String, dateAdded: Date? = nil,
                downloads: Int = 0, description: String = "") {
        self.id = id
        self.name = name
        self.size = size
        self.downloadURL = downloadURL
        self.md5 = md5
        self.dateAdded = dateAdded
        self.downloads = downloads
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try c.required("_idRow")
        name = c.value("_sFile", "")
        size = c.value("_nFilesize", Int64(0))
        downloadURL = c.url("_sDownloadUrl")
        md5 = c.value("_sMd5Checksum", "")
        dateAdded = c.date("_tsDateAdded")
        downloads = c.value("_nDownloadCount", 0)
        description = c.value("_sDescription", "")
    }
}

/// One line of a mod's Requirements on GameBanana: free text by the author ("Trinity Mod Loader", "SMO v1.3"),
/// optional when the author labels it Recommended or Optional.
public struct GameBananaRequirement: Codable, Hashable, Sendable {
    public let name: String
    public let isOptional: Bool

    public init(name: String, isOptional: Bool) {
        self.name = name
        self.isOptional = isOptional
    }
}

/// `_aRequirements` holds `[name, link, label, colour, label, colour…]`; anything else in the list is skipped.
private struct RequirementEntry: Decodable {
    let requirement: GameBananaRequirement?

    private struct Part: Decodable {
        let text: String?
        init(from decoder: Decoder) throws { text = try? decoder.singleValueContainer().decode(String.self) }
    }

    init(from decoder: Decoder) throws {
        let parts = ((try? decoder.singleValueContainer().decode([Part].self)) ?? []).map(\.text)
        guard let name = parts.first??.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            requirement = nil
            return
        }
        let labels = parts.dropFirst(2).compactMap { $0?.lowercased() }
        requirement = GameBananaRequirement(name: name,
                                            isOptional: labels.contains("recommended") || labels.contains("optional"))
    }
}

public struct GameBananaModProfile: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let profileURL: URL?
    public let version: String
    public let text: String
    public let isObsolete: Bool
    public let isPrivate: Bool
    public let isWithheld: Bool
    public let isTrashed: Bool
    public let contentRatings: [String: String]
    public let images: [GameBananaImage]
    public let submitter: GameBananaSubmitter
    public let files: [GameBananaFile]
    public let likes: Int
    public let downloads: Int
    public let dateAdded: Date?
    public let dateUpdated: Date?
    public let requirements: [GameBananaRequirement]

    public init(id: Int, name: String, profileURL: URL? = nil, version: String = "", text: String = "",
                isObsolete: Bool = false, isPrivate: Bool = false, isWithheld: Bool = false, isTrashed: Bool = false,
                contentRatings: [String: String] = [:], images: [GameBananaImage] = [],
                submitter: GameBananaSubmitter = GameBananaSubmitter(name: ""), files: [GameBananaFile] = [],
                likes: Int = 0, downloads: Int = 0, dateAdded: Date? = nil, dateUpdated: Date? = nil,
                requirements: [GameBananaRequirement] = []) {
        self.id = id
        self.name = name
        self.profileURL = profileURL
        self.version = version
        self.text = text
        self.isObsolete = isObsolete
        self.isPrivate = isPrivate
        self.isWithheld = isWithheld
        self.isTrashed = isTrashed
        self.contentRatings = contentRatings
        self.images = images
        self.submitter = submitter
        self.files = files
        self.likes = likes
        self.downloads = downloads
        self.dateAdded = dateAdded
        self.dateUpdated = dateUpdated
        self.requirements = requirements
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try c.required("_idRow")
        name = c.value("_sName", "")
        profileURL = c.url("_sProfileUrl")
        version = c.value("_sVersion", "")
        text = c.value("_sText", "")
        requirements = c.value("_aRequirements", [RequirementEntry]()).compactMap(\.requirement)
        isObsolete = c.value("_bIsObsolete", false)
        isPrivate = c.value("_bIsPrivate", false)
        isWithheld = c.value("_bIsWithheld", false)
        isTrashed = c.value("_bIsTrashed", false)
        contentRatings = c.value("_aContentRatings", [String: String]())
        images = c.previewImages()
        submitter = c.value("_aSubmitter", GameBananaSubmitter(name: ""))
        files = c.value("_aFiles", [GameBananaFile]())
        likes = c.value("_nLikeCount", 0)
        downloads = c.value("_nDownloadCount", 0)
        dateAdded = c.date("_tsDateAdded")
        dateUpdated = c.date("_tsDateUpdated")
    }
}
