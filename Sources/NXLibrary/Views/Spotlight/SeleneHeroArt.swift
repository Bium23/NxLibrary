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
                  artwork: ArtworkStore,
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
            for: game, metadata: metadata, artwork: artwork)
        guard !Task.isCancelled, current() == game.id else { return }
        image = loaded
        key = loaded.map { loadedFor + "\(ObjectIdentifier($0).hashValue)" } ?? "none"
    }

    func loadLogo(game: PortedGame?, metadata: NintendoStoreMetadata?,
                  artwork: ArtworkStore) async {
        guard let game, GameArtLoader.shared.cachedLogo(for: game) == nil else { return }
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }
        let loaded = await GameArtLoader.shared.logo(
            for: game, metadata: metadata, artwork: artwork)
        guard loaded != nil, !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) { logoTick += 1 }
    }
}
