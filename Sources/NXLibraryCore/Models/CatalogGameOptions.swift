import Foundation

/// Shared library operations are ordered once. Integration handlers still enforce
/// CatalogGamePresentation capabilities before performing an operation.
public enum CatalogGameOptions {
    /// The main list's rows every source offers, in the order nxnative's Game options shows them.
    /// The store page sits in Edit details for every source.
    public static func commonRows(for integration: CatalogIntegration, origin: GameOptionsOrigin) -> [GameOptionsRow] {
        var rows: [GameOptionsRow] = [.play, .editDetails]
        if origin == .spotlight { rows.append(.move) }
        rows += [.favorite, .hidden, .showInFinder]
        return rows
    }
    public static func specificRows(for integration: CatalogIntegration) -> [GameOptionsRow] {
        switch integration {
        case .steam: return []
        case .nxnative: return [.cheats, .mods, .openSaves, .rebuild, .attachSources, .openLog, .removeSources]
        }
    }
}

/// A Steam game's Options: only what NX Library can do for it. The shared rows keep
/// nxnative's order and look; nothing about engines, builds, saves or sources.
public struct SteamOptionsPresentation: Equatable, Sendable {
    /// One available, recognized installation in an enabled source.
    public let canPlay: Bool
    /// The installation's app was found, so Finder has something to reveal.
    public let hasApp: Bool

    public init(canPlay: Bool, hasApp: Bool) {
        self.canPlay = canPlay
        self.hasApp = hasApp
    }

    public func entries(level: GameOptionsLevel, origin: GameOptionsOrigin) -> [GameOptionsEntry] {
        switch level {
        case .main:
            return CatalogGameOptions.commonRows(for: .steam, origin: origin).map(GameOptionsEntry.row)
        case .editDetails:
            return [.heading("Edit details"), .row(.changeArtwork), .row(.changeMetadata), .row(.storePage)]
        }
    }

    public func focusableRows(level: GameOptionsLevel, origin: GameOptionsOrigin) -> [GameOptionsRow] {
        entries(level: level, origin: origin).compactMap { entry in
            if case .row(let row) = entry { return row }
            return nil
        }
    }

    /// Dim rows still take focus; their action explains itself (Play shows why in the head).
    public func isDimmed(_ row: GameOptionsRow) -> Bool {
        switch row {
        case .play: return !canPlay
        case .showInFinder: return !hasApp
        default: return false
        }
    }

    public func about(_ row: GameOptionsRow) -> String? {
        switch row {
        case .play: return L10n.text("Start the game through Steam.")
        case .editDetails: return L10n.text("Artwork, metadata and the store page.")
        case .changeArtwork: return L10n.text("Cover, background, icon and logo, from Steam, online sources or a file.")
        case .storePage: return L10n.text("Open the game’s Steam store page.")
        case .move, .favorite, .hidden, .showInFinder, .changeMetadata:
            return GameOptionsPresentation(supportsRenderScale: false, isPlayable: false, sourcesDetached: false).about(row)
        default: return nil
        }
    }
}
