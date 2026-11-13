import Foundation
import NXLibraryCore

/// The game Change artwork and Change metadata personalize, whatever its source. nxnative
/// games keep their picks in `ArtworkPicks`/`MetadataPicks` and their Mac app icon flow;
/// Steam games keep theirs in `SteamPersonalizationStore` and never touch the installed app.
@MainActor
struct PersonalizationSubject {
    let id: UUID
    let name: String
    /// The picks' key: the nxnative personalization key, or "steam-<appid>".
    let key: String
    /// The nxnative game, for Switch sources (Title DB, GameTDB, Nintendo store) and the app icon.
    let ported: PortedGame?
    /// The Steam game, for Steam's own art and store facts.
    let steam: CatalogGame?

    init(_ game: PortedGame, viewModel: AppViewModel) {
        id = game.id; name = game.name; key = viewModel.personalizationKey(for: game)
        ported = game; steam = nil
    }

    init(steam game: CatalogGame) {
        id = game.id; name = game.name; key = game.personalizationReference.key
        ported = nil; steam = game
    }

    var titleId: String? { ported?.titleId }
    var steamAppID: UInt32? { steam?.steamGame?.appID }

    private var steamStore: SteamPersonalizationStore { SteamPersonalizations.shared.metadata }

    // MARK: Artwork picks

    func artworkURL(_ slot: ArtworkSlot) -> URL? {
        steam != nil ? steamStore.url(titleID: key, slot: slot) : ArtworkPicks.shared.url(titleID: key, slot: slot)
    }

    func saveArtwork(_ data: Data, slot: ArtworkSlot) throws {
        if steam != nil { try steamStore.save(fields: [:], images: [slot: data], automatic: [], titleID: key) }
        else { _ = try ArtworkPicks.shared.save(data, titleID: key, slot: slot) }
    }

    func removeArtwork(_ slot: ArtworkSlot) throws {
        if steam != nil { try steamStore.save(fields: [:], images: [:], automatic: [slot], titleID: key) }
        else { ArtworkPicks.shared.remove(titleID: key, slot: slot) }
    }

    // MARK: Metadata picks

    func metadataPick(_ field: MetadataField) -> String? {
        steam != nil ? steamStore.value(titleID: key, field: field) : MetadataPicks.shared.value(titleID: key, field: field)
    }

    /// Keeps the player's value, or (nil) goes back to the store's.
    func pickMetadata(_ value: String?, field: MetadataField, viewModel: AppViewModel) throws {
        if steam != nil { try steamStore.save(fields: [field: value ?? ""], images: [:], automatic: [], titleID: key) }
        else if let ported { viewModel.pickMetadata(value, field: field, for: ported) }
    }
}

extension SteamMetadata {
    /// The store's value for a Change metadata field, as one line (genres comma-separated).
    func value(_ field: MetadataField) -> String? {
        let text: String?
        switch field {
        case .description: text = description
        case .genres: text = genres.joined(separator: ", ")
        case .developer: text = developers.joined(separator: ", ")
        case .publisher: text = publishers.joined(separator: ", ")
        case .releaseDate: text = releaseDate
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
