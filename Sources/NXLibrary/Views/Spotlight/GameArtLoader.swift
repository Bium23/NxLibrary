import AppKit
import ImageIO
import NXLibraryCore

/// Loads and caches a game's hero art and logo for Spotlight (and, until it is
/// replaced, the legacy library). Every lookup goes through the shared
/// `ArtworkStore` disk cache and the shared `SteamGridDBService`.
@MainActor
final class GameArtLoader {
    static let shared = GameArtLoader()

    private let heroes = NSCache<NSUUID, NSImage>()
    private let logos = NSCache<NSUUID, NSImage>()

    private init() {
        heroes.countLimit = 24
        logos.countLimit = 64
    }

    func cachedHero(for game: PortedGame) -> NSImage? { heroes.object(forKey: game.id as NSUUID) }
    func cachedLogo(for game: PortedGame) -> NSImage? { logos.object(forKey: game.id as NSUUID) }

    /// Local hero files, the disk cache, SteamGridDB, a known community
    /// wallpaper, then the store / titledb banner.
    func hero(for game: PortedGame, metadata: NintendoStoreMetadata?, artwork: ArtworkStore,
              steamGridDB: SteamGridDBService, apiKey: String) async -> NSImage? {
        if let cached = cachedHero(for: game) { return cached }
        let titleKey = game.titleId ?? game.uniqueKey
        var image: NSImage?

        let names = ["hero.jpg", "hero.png", "background.jpg", "background.png", "wallpaper.jpg"]
        var folders: [URL] = []
        if let source = game.sources.first { folders.append(source.url.deletingLastPathComponent()) }
        folders.append(game.url.appendingPathComponent("Contents/Resources"))
        search: for folder in folders {
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
        if image == nil, !Task.isCancelled, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let remote = await steamGridDB.fetchHeroURL(gameName: game.name, apiKey: apiKey),
           let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .hero) {
            image = await Self.decodeHero(at: url)
        }
        if image == nil, !Task.isCancelled,
           let remote = Self.communityWallpaperURL(gameName: game.name, titleId: game.titleId),
           let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .hero) {
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

    /// The disk cache, a local logo.png, SteamGridDB, the store logo, then a known community logo.
    func logo(for game: PortedGame, metadata: NintendoStoreMetadata?, artwork: ArtworkStore,
              steamGridDB: SteamGridDBService, apiKey: String) async -> NSImage? {
        if let cached = cachedLogo(for: game) { return cached }
        let titleKey = game.titleId ?? game.uniqueKey
        var image: NSImage?

        // Every read and decode runs off the main thread (`decodeLogo`); a
        // missing local file simply decodes to nil.
        if let url = artwork.cachedURL(titleID: titleKey, kind: .logo) {
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
        if image == nil, !Task.isCancelled, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let remote = await steamGridDB.fetchLogoURL(gameName: game.name, apiKey: apiKey),
           let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .logo) {
            image = await Self.decodeLogo(at: url)
        }
        if image == nil, !Task.isCancelled, let remote = metadata?.logoURL,
           let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .logo) {
            image = await Self.decodeLogo(at: url)
        }
        if image == nil, !Task.isCancelled,
           let remote = Self.communityLogoURL(gameName: game.name, titleId: game.titleId),
           let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .logo) {
            image = await Self.decodeLogo(at: url)
        }
        if let image { logos.setObject(image, forKey: game.id as NSUUID) }
        return image
    }

    nonisolated static func communityLogoURL(gameName: String, titleId: String?) -> URL? {
        let name = gameName.lowercased()
        if name.contains("wonder") || titleId == "010015100B514000" {
            return URL(string: "https://upload.wikimedia.org/wikipedia/commons/3/36/Super_Mario_Bros._Wonder_Logo.png")
        }
        if name.contains("odyssey") || titleId == "0100000000010000" {
            return URL(string: "https://upload.wikimedia.org/wikipedia/it/2/27/Super_Mario_Odyssey_logo.png")
        }
        if name.contains("breath of the wild") || titleId == "01007EF00011E000" {
            return URL(string: "https://cdn.wikimg.net/en/zeldawiki/images/0/06/BotW_English_Logo.png")
        }
        if name.contains("tears of the kingdom") || name.contains("totk") || titleId == "0100F2C0115B6000" {
            return URL(string: "https://cdn.wikimg.net/en/zeldawiki/images/4/4c/TotK_English_Logo.png")
        }
        return nil
    }

    nonisolated static func communityWallpaperURL(gameName: String, titleId: String?) -> URL? {
        let name = gameName.lowercased()
        if name.contains("wonder") || titleId == "010015100B514000" {
            return URL(string: "https://catwithmonocle.com/wp-content/uploads/2023/11/smb-wonder-artwork-01-3840x2160-1.jpg")
        }
        if name.contains("odyssey") || titleId == "0100000000010000" {
            return URL(string: "https://catwithmonocle.com/wp-content/uploads/2017/12/smo-wallpaper-pc.jpg")
        }
        if name.contains("breath of the wild") || titleId == "01007EF00011E000" {
            return URL(string: "https://wallpapercat.com/w/full/a/e/e/904567-3840x2160-desktop-4k-legend-of-zelda-breath-of-the-wild-wallpaper.jpg")
        }
        if name.contains("tears of the kingdom") || name.contains("totk") || titleId == "0100F2C0115B6000" {
            return URL(string: "https://catwithmonocle.com/wp-content/uploads/2023/12/zelda-tearskingdom-artwork-02-3840x2160-1.jpg")
        }
        return nil
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
