import Foundation

/// One line of a game's Details panel: a player-facing fact with its label and grey icon.
public struct DetailsFact: Equatable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case developer, publisher, version, size, location }

    public let kind: Kind
    public let value: String
    public var id: String { kind.rawValue }

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    public var label: String {
        switch kind {
        case .developer: return L10n.text("Developer")
        case .publisher: return L10n.text("Publisher")
        case .version: return L10n.text("Version")
        case .size: return L10n.text("Size on disk")
        case .location: return L10n.text("Installed in")
        }
    }

    /// The SF Symbol beside the label.
    public var symbol: String {
        switch kind {
        case .developer: return "hammer"
        case .publisher: return "building.2"
        case .version: return "number"
        case .size: return "internaldrive"
        case .location: return "folder"
        }
    }
}

/// The Details panel's rows for any source, in `Kind` order. A fact with no value has no row (never "—").
/// Nothing technical: no engine, build, sources or Steam build ID. The two display names that need the
/// file system (the app's folder, the Steam library's volume) come from the caller.
public enum DetailsFacts {
    public static func switchGame(_ game: PortedGame, metadata: NintendoStoreMetadata?,
                                  folderName: String?, locale: Locale = L10n.context.formatLocale) -> [DetailsFact] {
        rows([.developer: names(metadata?.developers),
              .publisher: names(metadata?.publishers),
              .version: text(game.versionString),
              .size: size(game.sizeBytes, locale: locale),
              .location: text(folderName)])
    }

    /// A Steam game without an available installation (still downloading, not detected) shows only its credits.
    public static func steamGame(_ game: CatalogGame, metadata: SteamMetadata?,
                                 overrides: [MetadataField: String] = [:], volumeName: String?,
                                 locale: Locale = L10n.context.formatLocale) -> [DetailsFact] {
        let appID = game.steamGame?.appID
        let facts = metadata.flatMap { $0.appID == appID ? $0 : nil }
        let installation = game.steamGame?.firstAvailableInstallation
        return rows([.developer: names(overrides[.developer].map { [$0] } ?? facts?.developers),
                     .publisher: names(overrides[.publisher].map { [$0] } ?? facts?.publishers),
                     .size: installation.flatMap { size($0.reportedSizeBytes, locale: locale) },
                     .location: installation.map { _ in text(volumeName).map { "Steam · " + $0 } ?? "Steam" }])
    }

    private static func rows(_ values: [DetailsFact.Kind: String?]) -> [DetailsFact] {
        DetailsFact.Kind.allCases.compactMap { kind in
            (values[kind] ?? nil).map { DetailsFact(kind: kind, value: $0) }
        }
    }

    private static func names(_ list: [String]?) -> String? {
        let names = (list ?? []).compactMap(text)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    private static func text(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func size(_ bytes: Int64?, locale: Locale) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        return bytes.formatted(.byteCount(style: .file).locale(locale))
    }
}
