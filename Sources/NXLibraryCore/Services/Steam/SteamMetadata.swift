import Foundation

/// Store facts are distinct from installation observations and personal choices.
public struct SteamMetadata: Codable, Equatable, Sendable {
    public let appID: UInt32
    public let language: String
    public let description: String
    public let genres: [String]
    public let developers: [String]
    public let publishers: [String]
    public let releaseDate: String?
    public let screenshots: [URL]
    public let fetchedAt: Date

    public static func language(_ language: AppLanguage) -> String {
        switch language {
        case .italian: return "italian"
        case .french: return "french"
        case .german: return "german"
        case .spanish: return "spanish"
        case .portugueseBrazil: return "brazilian"
        default: return "english"
        }
    }
    public static func safeImage(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              ["steamstatic.com", "steamusercontent.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return url
    }
    public static func decode(_ data: Data, appID: UInt32, language: String) throws -> Self {
        struct Envelope: Decodable {
            struct Body: Decodable {
                struct Genre: Decodable { let description: String }
                struct Shot: Decodable { let path_full: URL }
                struct Release: Decodable { let date: String? }
                let steam_appid: UInt32
                let short_description: String?
                let genres: [Genre]?
                let developers: [String]?
                let publishers: [String]?
                let release_date: Release?
                let screenshots: [Shot]?
            }
            let success: Bool
            let data: Body?
        }
        guard data.count <= 2_097_152, appID > 0,
              let envelope = try JSONDecoder().decode([String: Envelope].self, from: data)[String(appID)],
              envelope.success, let body = envelope.data, body.steam_appid == appID else { throw URLError(.cannotParseResponse) }
        return Self(appID: appID, language: language,
                    description: GameBananaAPI.plainText(fromHTML: body.short_description ?? ""),
                    genres: Array((body.genres ?? []).prefix(24)).map(\.description),
                    developers: Array((body.developers ?? []).prefix(12)), publishers: Array((body.publishers ?? []).prefix(12)),
                    releaseDate: body.release_date?.date,
                    screenshots: Array((body.screenshots ?? []).compactMap { safeImage($0.path_full) }.prefix(12)), fetchedAt: Date())
    }
}
