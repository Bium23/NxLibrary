import AppKit
import ImageIO
import NXLibraryCore

/// Loads and caches a game's hero art and logo for Spotlight (and, until it is
/// replaced, the legacy library). Every lookup goes through the shared
/// `ArtworkStore` disk cache.
@MainActor
final class GameArtLoader {
    static let shared = GameArtLoader()

    private let heroes = NSCache<NSUUID, NSImage>()
    private let logos = NSCache<NSUUID, NSImage>()
    /// Games already looked up online this launch, found or not.
    private var searchedOnline: Set<UUID> = []

    private init() {
        heroes.countLimit = 24
        logos.countLimit = 64
    }

    func cachedHero(for game: PortedGame) -> NSImage? { heroes.object(forKey: game.id as NSUUID) }
    func cachedLogo(for game: PortedGame) -> NSImage? { logos.object(forKey: game.id as NSUUID) }

    /// Drops a game's decoded art, so the next load reads a new pick.
    func forget(_ game: PortedGame) {
        heroes.removeObject(forKey: game.id as NSUUID)
        logos.removeObject(forKey: game.id as NSUUID)
    }

    /// The player's pick, local hero files, the disk cache, then the store /
    /// titledb banner.
    func hero(for game: PortedGame, metadata: NintendoStoreMetadata?, artwork: ArtworkStore) async -> NSImage? {
        if let cached = cachedHero(for: game) { return cached }
        let titleKey = game.titleId ?? game.uniqueKey
        var image: NSImage?

        if let picked = ArtworkPicks.shared.url(titleID: titleKey, slot: .background) {
            image = await Self.decodeHero(at: picked)
        }

        let names = ["hero.jpg", "hero.png", "background.jpg", "background.png", "wallpaper.jpg"]
        var folders: [URL] = []
        if let source = game.sources.first { folders.append(source.url.deletingLastPathComponent()) }
        folders.append(game.url.appendingPathComponent("Contents/Resources"))
        search: for folder in folders where image == nil {
            for name in names {
                let url = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path),
                   let decoded = await Self.decodeHero(at: url) {
                    image = decoded
                    break search
                }
            }
        }

        if image == nil, let url = artwork.cachedURL(titleID: titleKey, kind: .hero) {
            image = await Self.decodeHero(at: url)
        }
        if image == nil, !Task.isCancelled {
            let remote = metadata?.headerImageURL ?? metadata?.imageURL
                ?? game.titleId.flatMap { URL(string: "https://api.nlib.cc/nx/\($0)/banner") }
            if let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .hero) {
                image = await Self.decodeHero(at: url)
            }
        }
        if let image { heroes.setObject(image, forKey: game.id as NSUUID) }
        return image
    }

    /// The player's pick, the disk cache, a local logo.png, the store logo then
    /// the online sources' logos in their order (Steam, GOG, TheGamesDB,
    /// Wikidata, Commons, the fan wikis).
    func logo(for game: PortedGame, metadata: NintendoStoreMetadata?, artwork: ArtworkStore) async -> NSImage? {
        if let cached = cachedLogo(for: game) { return cached }
        let titleKey = game.titleId ?? game.uniqueKey
        var image: NSImage?

        // Every read and decode runs off the main thread (`decodeLogo`); a
        // missing local file simply decodes to nil.
        if let picked = ArtworkPicks.shared.url(titleID: titleKey, slot: .logo) {
            image = await Self.decodeLogo(at: picked)
        }
        if image == nil, let url = artwork.cachedURL(titleID: titleKey, kind: .logo) {
            image = await Self.decodeLogo(at: url)
        }
        if image == nil {
            var candidates: [URL] = []
            if let source = game.sources.first {
                candidates.append(source.url.deletingLastPathComponent().appendingPathComponent("logo.png"))
            }
            candidates.append(game.url.appendingPathComponent("Contents/Resources/logo.png"))
            for url in candidates where image == nil && !Task.isCancelled {
                image = await Self.decodeLogo(at: url)
            }
        }
        if image == nil, !Task.isCancelled, let remote = metadata?.logoURL,
           let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .logo) {
            image = await Self.decodeLogo(at: url)
        }
        if image == nil, !Task.isCancelled, searchedOnline.insert(game.id).inserted {
            let names = [game.name, metadata?.name].compactMap { $0 }
            let found = await OnlineArtwork.find(names: names, slot: .logo)
            for remote in found.flatMap({ [$0.url, $0.fallback] }) where image == nil && !Task.isCancelled {
                if let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .logo) {
                    image = await Self.decodeLogo(at: url)
                }
            }
        }
        if let image { logos.setObject(image, forKey: game.id as NSUUID) }
        return image
    }

    /// Decodes off the main thread, capped at 2560 px.
    nonisolated static func decodeHero(at url: URL) async -> NSImage? {
        await decode(at: url, maxPixelSize: 2560)
    }

    /// Logos fit 620 × 215; 1600 px keeps them sharp at 2× on a large window.
    nonisolated static func decodeLogo(at url: URL) async -> NSImage? {
        await decode(at: url, maxPixelSize: 1600)
    }

    nonisolated static func decode(at url: URL, maxPixelSize: Int) async -> NSImage? {
        let box = await Task.detached(priority: .utility) { () -> ImageBox? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return ImageBox(image: NSImage(cgImage: image,
                                           size: NSSize(width: CGFloat(image.width),
                                                        height: CGFloat(image.height))))
        }.value
        return box?.image
    }
}

private struct ImageBox: @unchecked Sendable {
    let image: NSImage
}
