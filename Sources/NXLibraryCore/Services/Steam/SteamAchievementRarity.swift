import Foundation

/// Steam's public achievement data that needs no key: how many players have each achievement
/// (`GetGlobalAchievementPercentagesForApp`) and the icons on Steam's CDN. Fetched and cached by
/// `SteamMetadataService.achievementPercents` and `.achievementIcon`.
public enum SteamAchievementRarity {
    static let host = "api.steampowered.com"
    static let path = "/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/"
    /// How long the percentages are reused before Steam is asked again.
    public static let freshFor: TimeInterval = 86_400

    public static func url(appID: UInt32) -> URL {
        URL(string: "https://\(host)\(path)?gameid=\(appID)")!
    }

    /// `achievementpercentages.achievements[{name, percent}]`, the percent as a number or a numeric string.
    public static func decode(_ data: Data) throws -> [String: Double] {
        struct Body: Decodable {
            struct Inner: Decodable { let achievements: [Entry] }
            struct Entry: Decodable {
                let name: String
                let percent: Double
                enum Keys: String, CodingKey { case name, percent }
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: Keys.self)
                    name = try container.decode(String.self, forKey: .name)
                    if let number = try? container.decode(Double.self, forKey: .percent) {
                        percent = number
                    } else if let number = Double(try container.decode(String.self, forKey: .percent)) {
                        percent = number
                    } else {
                        throw DecodingError.dataCorruptedError(forKey: .percent, in: container, debugDescription: "percent")
                    }
                }
            }
            let achievementpercentages: Inner
        }
        let entries = try JSONDecoder().decode(Body.self, from: data).achievementpercentages.achievements
        // "nan" and "inf" parse as numbers but are no rarity; clamping would keep NaN and turn infinity into 100.
        return Dictionary(entries.filter { $0.percent.isFinite }.map { ($0.name, min(max($0.percent, 0), 100)) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// An icon's address on Steam's CDN, for a plain file name from Steam's schema (`<hash>.jpg`); anything else is refused.
    /// Steam's community-assets host: the older `steamcommunity/public/images` path answers 404 for icons added
    /// recently (17 of Crimson Desert's 82, 16 Nov 2026), and this one serves both those and older games' icons.
    public static func iconURL(appID: UInt32, file: String) -> URL? {
        let lower = file.lowercased()
        guard file.count > 4, file.count <= 128, !file.contains("/"), !file.contains("\\"), !file.hasPrefix("."),
              file.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }),
              lower.hasSuffix(".jpg") || lower.hasSuffix(".png") else { return nil }
        return SteamMetadata.safeImage(URL(string: "https://shared.akamai.steamstatic.com/community_assets/images/apps/\(appID)/\(file)"))
    }
}

/// The percentages as cached on disk.
struct SteamAchievementPercentsCache: Codable {
    let fetchedAt: Date
    let percents: [String: Double]
}
