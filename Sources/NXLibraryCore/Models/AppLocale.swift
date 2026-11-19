import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case automatic = "auto", english = "en", italian = "it", french = "fr", german = "de", spanish = "es"
    case portugueseBrazil = "pt-BR"
    case chineseSimplified = "zh-Hans"

    public var id: String { rawValue }
    public var nativeName: String {
        switch self {
        case .automatic: return L10n.text("Automatic (Mac)")
        case .english: return "English"
        case .italian: return "Italiano"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .portugueseBrazil: return "Português (Brasil)"
        case .chineseSimplified: return "简体中文"
        }
    }
}

public struct AppLocale: Equatable {
    public let language: AppLanguage
    public let region: String
    public var metadataLanguage: String { String(language.rawValue.prefix(2)) }
    /// Simplified Chinese keeps its script in any region, so dates and numbers use Simplified characters.
    public var formatLocale: Locale {
        Locale(identifier: "\(language == .chineseSimplified ? "zh-Hans" : metadataLanguage)_\(region)")
    }
    public var cacheKey: String { "\(language.rawValue)_\(region)" }

    public init(language: AppLanguage, region: String?, preferredLanguages: [String] = Locale.preferredLanguages,
                systemLocale: Locale = .current) {
        if language != .automatic { self.language = language }
        else {
            self.language = preferredLanguages.lazy.compactMap(Self.supported).first ?? .english
        }
        self.region = Self.validRegion(region) ?? Self.validRegion(systemLocale.regionCode) ?? "US"
    }

    /// The offered language for one of the Mac's preferred languages, if any. Chinese means Simplified unless the
    /// tag names the Traditional script or a region that writes it (Taiwan, Hong Kong, Macao).
    static func supported(_ tag: String) -> AppLanguage? {
        let parts = tag.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
        guard let base = parts.first else { return nil }
        switch base {
        case "pt": return .portugueseBrazil
        case "zh":
            if parts.contains("hans") { return .chineseSimplified }
            return parts.contains { ["hant", "tw", "hk", "mo"].contains($0) } ? nil : .chineseSimplified
        default: return AppLanguage.allCases.first { $0 != .automatic && $0.rawValue == base }
        }
    }

    public static func validRegion(_ value: String?) -> String? {
        guard let value = value?.uppercased(), Locale.isoRegionCodes.contains(value) else { return nil }
        return value
    }
}

public struct AppRegionOption: Identifiable, Equatable {
    public let id: String
    public let name: String

    public static func matching(_ query: String, context: AppLocale) -> [AppRegionOption] {
        let locale = context.formatLocale
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Locale.isoRegionCodes.map { code in
            AppRegionOption(id: code, name: locale.localizedString(forRegionCode: code) ?? code)
        }.filter {
            needle.isEmpty || $0.id.localizedCaseInsensitiveContains(needle)
                || $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
        }.sorted { $0.name.compare($1.name, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) == .orderedAscending }
    }
}
