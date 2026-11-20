import Foundation
import ImageIO

/// The automatic full-screen background of a Steam game. Steam's library hero is a wide banner
/// (about 3:1) made for the top of Steam's own page: filling a 16:9 screen enlarges and crops it.
/// So clean 16:9 art comes first: the stores' hero backgrounds found by the game's name (Xbox,
/// GOG Galaxy, TheGamesDB fan art, each matched by `ArtworkNames`), then Steam's own first
/// screenshot for the exact AppID, and the library hero only when nothing else fits.
/// The player's own pick always comes before all of this, outside this type.
public enum SteamBackdropChoice {
    /// Screen-shaped: between 3:2 and 2:1, and wide enough not to be blown up on a large display.
    public static func suits(width: Int, height: Int) -> Bool {
        guard width >= 1280, height > 0 else { return false }
        let ratio = Double(width) / Double(height)
        return ratio >= 1.5 && ratio <= 2.0
    }

    /// Candidates in trial order. Only each store's own clean hero is taken (not titled heroes,
    /// wide covers or their screenshots); Steam's art is the exact AppID's, never a name match.
    public static func ordered(storeArt: [ArtworkCandidate], screenshots: [URL], libraryHero: URL?) -> [URL] {
        func first(_ source: String) -> [URL] {
            storeArt.first { $0.slot == .background && $0.source == source }.map { [$0.url] } ?? []
        }
        // LaunchBox's fan art for the game's computer entry, at full size: only one whose stated size suits a
        // screen (a size it does not state is checked by `choose`).
        let fanart = storeArt.first { candidate in
            guard candidate.slot == .background, candidate.source.hasPrefix(LaunchBoxArt.fanartSource) else { return false }
            guard let width = candidate.width, let height = candidate.height else { return true }
            return suits(width: width, height: height)
        }.map { $0.full ?? $0.url }
        var urls = first("Xbox Store") + first("GOG") + first("TheGamesDB fan art") + (fanart.map { [$0] } ?? [])
        urls += screenshots.prefix(1)
        if let libraryHero { urls.append(libraryHero) }
        var seen: Set<URL> = []
        return urls.filter { seen.insert($0).inserted }
    }

    /// The first candidate whose image suits a full screen. When none does: `fallback` (Steam's library
    /// banner, shown cropped), else the first candidate that loaded at all. Nothing is kept here: the caller
    /// caches the choice.
    public static func choose(_ urls: [URL], fallback: URL?, data: (URL) async -> Data?) async -> URL? {
        var loaded: URL?
        for url in urls {
            guard !Task.isCancelled else { return nil }
            guard let bytes = await data(url), let size = pixelSize(bytes) else { continue }
            if suits(width: size.width, height: size.height) { return url }
            if loaded == nil { loaded = url }
        }
        return fallback ?? loaded
    }

    /// Store art for the name, from the sources that publish clean 16:9 heroes, and LaunchBox's fan art for
    /// the game's Mac or Windows entry (never a console's).
    public static func storeArt(names: [String], client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> [ArtworkCandidate] {
        async let xbox = XboxStoreArt.find(names: names, client: client)
        async let gog = GOGArt.find(names: names, client: client)
        async let gamesDB = TheGamesDBArt.find(names: names, client: client)
        async let launchBox = LaunchBoxArt.game(names: names, switch2: false, computer: true, client: client)
        return await xbox + gog + gamesDB + (launchBox?.candidates ?? [])
    }

    /// Fetches a candidate for `choose`.
    public static func download(_ url: URL, client: ArtworkHTTPClient = URLSessionArtworkClient()) async -> Data? {
        await OnlineArtworkRequest.data(url, client: client)
    }

    static func pixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}
