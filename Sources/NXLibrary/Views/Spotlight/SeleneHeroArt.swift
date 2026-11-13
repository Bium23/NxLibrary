import SwiftUI
import AppKit
import NXLibraryCore

/// The selected game's backdrop art and logo for a screen: loads them after a
/// 150 ms settle (a held stick does not load every game it passes) and
/// publishes the hero for `SeleneArtBackground` and `logoTick` so the screen
/// redraws when a logo lands in `GameArtLoader`'s cache. Shared by Spotlight,
/// Collection (and Details).
@MainActor
final class SeleneHeroArt: ObservableObject {
    @Published private(set) var image: NSImage?
    /// Changes whenever `image` does; drives the crossfade.
    @Published private(set) var key = "none"
    @Published private(set) var logoTick = 0

    func heroTaskKey(_ game: PortedGame?, metadata: NintendoStoreMetadata?) -> String {
        guard let game else { return "none" }
        let remote = metadata?.headerImageURL ?? metadata?.imageURL
        return "hero|\(game.id)|\(remote?.absoluteString ?? "")|\(ArtworkPicks.shared.revision)"
    }

    func logoTaskKey(_ game: PortedGame?, metadata: NintendoStoreMetadata?) -> String {
        guard let game else { return "none" }
        return "logo|\(game.id)|\(metadata?.logoURL?.absoluteString ?? "")|\(ArtworkPicks.shared.revision)"
    }

    /// The cached logo; reading `logoTick` makes the caller's body depend on it.
    func logo(for game: PortedGame) -> NSImage? {
        _ = logoTick
        return GameArtLoader.shared.cachedLogo(for: game)
    }

    /// `current` re-reads the screen's selected game after each await.
    /// `settle` is the pause before loading; Collection waits longer so its logo leads.
    func loadHero(game: PortedGame?, current: () -> UUID?, metadata: NintendoStoreMetadata?,
                  artwork: ArtworkStore, personalizations: CatalogPersonalizations,
                  settle: UInt64 = 150_000_000, keepsWithoutGame: Bool = false) async {
        guard let game else {
            // Spotlight keeps the last game's art over a card, so coming back to that game needs no reload.
            if !keepsWithoutGame {
                image = nil
                key = "none"
            }
            return
        }
        // Loaded already, unless the player has picked new art since.
        let loadedFor = "\(game.id.uuidString)|r\(ArtworkPicks.shared.revision)|"
        if key.hasPrefix(loadedFor) { return }
        try? await Task.sleep(nanoseconds: settle)
        guard !Task.isCancelled else { return }
        let loaded = await GameArtLoader.shared.hero(
            for: game, metadata: metadata, artwork: artwork, personalizations: personalizations)
        guard !Task.isCancelled, current() == game.id else { return }
        image = loaded
        key = loaded.map { loadedFor + "\(ObjectIdentifier($0).hashValue)" } ?? "none"
    }

    func steamHeroTaskKey(_ game: CatalogGame?) -> String {
        guard let game, game.integration == .steam else { return "none" }
        return "steam-hero|\(game.id)|\(SteamPersonalizations.shared.artwork.revision)"
    }

    /// A Steam game's hero through the same image, key and crossfade as an nxnative one: the
    /// player's pick, else the automatic choice kept from last time, else a new one (`SteamBackdropChoice`:
    /// screen-shaped store art, then the first screenshot, the library banner last). No game (or an
    /// nxnative one) leaves the image to `loadHero`.
    func loadSteamHero(game: CatalogGame?, current: () -> UUID?, artwork: ArtworkStore,
                       settle: UInt64 = 150_000_000) async {
        guard let game, game.integration == .steam else { return }
        let picks = SteamPersonalizations.shared.artwork
        let loadedFor = "\(game.id.uuidString)|s\(picks.revision)|"
        if key.hasPrefix(loadedFor) { return }
        try? await Task.sleep(nanoseconds: settle)
        guard !Task.isCancelled else { return }
        let request = SteamArtworkRequest(game: game, role: .hero)
        let titleKey = game.personalizationReference.key
        var url = request.localURL(picks: picks) ?? artwork.cachedURL(titleID: titleKey, kind: .hero)
        if url == nil, let id = request.appID {
            await SteamGameFacts.shared.load(game, language: L10n.context.language)
            let shots = SteamGameFacts.shared.metadata(for: game)?.screenshots ?? []
            let banner = SteamStoreArt.candidates(appID: Int(id), slot: .background).first?.url
            let store = await SteamBackdropChoice.storeArt(names: [game.name])
            let order = SteamBackdropChoice.ordered(storeArt: store, screenshots: shots, libraryHero: banner)
            if let chosen = await SteamBackdropChoice.choose(order, data: { await SteamBackdropChoice.download($0) }), !Task.isCancelled {
                url = await artwork.fetch(titleID: titleKey, remoteURL: chosen, kind: .hero)
            }
        }
        guard !Task.isCancelled else { return }
        let loaded: NSImage? = if let url { await Self.decodeBackdrop(at: url) } else { nil }
        guard !Task.isCancelled, current() == game.id else { return }
        image = loaded
        key = loaded.map { loadedFor + "\(ObjectIdentifier($0).hashValue)" } ?? "none"
    }

    private static func decodeBackdrop(at url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
    }

    func loadLogo(game: PortedGame?, metadata: NintendoStoreMetadata?,
                  artwork: ArtworkStore, personalizations: CatalogPersonalizations) async {
        guard let game, GameArtLoader.shared.cachedLogo(for: game) == nil else { return }
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }
        let loaded = await GameArtLoader.shared.logo(
            for: game, metadata: metadata, artwork: artwork, personalizations: personalizations)
        guard loaded != nil, !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) { logoTick += 1 }
    }
}
