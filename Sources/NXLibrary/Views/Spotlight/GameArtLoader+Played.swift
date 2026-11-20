import AppKit
import NXLibraryCore
import ArcanePorting

/// Art for a `PlayedGame`: an nxnative game's through the loader's own lookups, a Steam game's through the same
/// picks and automatic choices its pages use, decoded at the same sizes. Steam art is cached under the player's
/// pick revision, so a new pick is read the next time.
extension GameArtLoader {
    func cachedHero(for game: PlayedGame) -> NSImage? {
        switch game {
        case .nxnative(let game): return cachedHero(for: game)
        case .steam(let game): return steamArt.object(forKey: Self.steamKey(game, .hero))
        }
    }

    func cachedLogo(for game: PlayedGame) -> NSImage? {
        switch game {
        case .nxnative(let game): return cachedLogo(for: game)
        case .steam(let game): return steamArt.object(forKey: Self.steamKey(game, .logo))
        }
    }

    func hero(for game: PlayedGame, metadata: NintendoStoreMetadata?, artwork: ArtworkStore,
              personalizations: CatalogPersonalizations) async -> NSImage? {
        switch game {
        case .nxnative(let game):
            return await hero(for: game, metadata: metadata, artwork: artwork, personalizations: personalizations)
        case .steam(let game):
            if let cached = cachedHero(for: .steam(game)) { return cached }
            let key = Self.steamKey(game, .hero)
            guard let url = await Self.steamHeroURL(for: game, artwork: artwork),
                  let image = await Self.decodeHero(at: url) else { return nil }
            steamArt.setObject(image, forKey: key)
            return image
        }
    }

    func logo(for game: PlayedGame, metadata: NintendoStoreMetadata?, artwork: ArtworkStore,
              personalizations: CatalogPersonalizations) async -> NSImage? {
        switch game {
        case .nxnative(let game):
            return await logo(for: game, metadata: metadata, artwork: artwork, personalizations: personalizations)
        case .steam(let game):
            if let cached = cachedLogo(for: .steam(game)) { return cached }
            let key = Self.steamKey(game, .logo)
            guard let url = await Self.steamLogoURL(for: game),
                  let image = await Self.decodeLogo(at: url) else { return nil }
            steamArt.setObject(image, forKey: key)
            return image
        }
    }

    /// A Steam game's hero: the player's pick, else the automatic choice kept from last time, else a new one
    /// (`SteamBackdropChoice`: screen-shaped store art, LaunchBox's PC fan art, then the first screenshot, the
    /// library banner last).
    static func steamHeroURL(for game: CatalogGame, artwork: ArtworkStore) async -> URL? {
        let request = SteamArtworkRequest(game: game, role: .hero)
        let titleKey = game.personalizationReference.key
        if let url = request.localURL(picks: SteamPersonalizations.shared.artwork)
            ?? artwork.cachedURL(titleID: titleKey, kind: .hero) { return url }
        guard let id = request.appID else { return nil }
        await SteamGameFacts.shared.load(game, language: L10n.context.language)
        let shots = SteamGameFacts.shared.metadata(for: game)?.screenshots ?? []
        let banner = SteamStoreArt.candidates(appID: Int(id), slot: .background).first?.url
        let store = await SteamBackdropChoice.storeArt(names: [game.name])
        let order = SteamBackdropChoice.ordered(storeArt: store, screenshots: shots, libraryHero: banner)
        guard let chosen = await SteamBackdropChoice.choose(order, fallback: banner,
                                                            data: { await SteamBackdropChoice.download($0) }),
              !Task.isCancelled else { return nil }
        return await artwork.fetch(titleID: titleKey, remoteURL: chosen, kind: .hero)
    }

    /// A Steam game's logo: the player's pick, else the store's, as its pages show it.
    static func steamLogoURL(for game: CatalogGame) async -> URL? {
        let request = SteamArtworkRequest(game: game, role: .logo)
        if let local = request.localURL(picks: SteamPersonalizations.shared.artwork) { return local }
        guard let id = game.steamGame?.appID else { return nil }
        return await SteamMetadataService.shared.image(appID: id, slot: .logo, remote: nil)
    }

    private static func steamKey(_ game: CatalogGame, _ role: LibraryArtworkRole) -> NSString {
        "\(game.id.uuidString)|\(role.rawValue)|\(SteamPersonalizations.shared.artwork.revision)" as NSString
    }
}
