import SwiftUI
import AppKit
import NXLibraryCore

/// Same source-qualified personal picks as metadata; downloaded art never writes
/// into Steam or its app bundles. Task identity includes locale-independent URL.
struct SteamArtwork: View {
    let game: CatalogGame
    let slot: ArtworkSlot
    var remote: URL? = nil
    @State private var image: NSImage?
    @State private var loadedKey = ""
    /// The installed app's own icon, the cover/icon fallback: read once per bundle, not on every redraw.
    @State private var appIcon: NSImage?
    @State private var appIconPath: String?
    /// The first look-up has ended (art found or not): a tile is ready for Spotlight's entrance.
    @State private var settled = false
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject private var picks = SteamPersonalizations.shared.artwork
    private var installedApp: CatalogNativeApplication? {
        game.steamGame?.firstAvailableInstallation?.primaryApplication
    }
    private var appBuildID: String? { game.steamGame?.firstAvailableInstallation?.buildID }
    private var appIconRequestKey: String { "\(installedApp?.url.path ?? "")|\(appBuildID ?? "")" }
    /// The installed app's path is part of it: an installation that moves brings its icon along.
    private var key: String {
        "\(game.id)|\(slot.rawValue)|\(remote?.absoluteString ?? "")|\(picks.revision)|\(appIconRequestKey)"
    }
    private var role: LibraryArtworkRole { LibraryArtworkRole.allCases.first { $0.slot == slot } ?? .hero }

    private var displayedImage: NSImage? {
        if loadedKey == key, let image { return image }
        return TileArtMemo.shared.object(forKey: "steam|\(key)" as NSString)
    }

    private var displayedAppIcon: NSImage? {
        guard let app = installedApp else { return nil }
        if appIconPath == appIconRequestKey, let appIcon { return appIcon }
        return SteamAppIconCache.cachedIcon(at: app.url, buildID: appBuildID)
    }

    var body: some View {
        ZStack {
            if let image = displayedImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: slot == .logo ? .fit : .fill)
            } else if slot == .cover || slot == .icon {
                if let appIcon = displayedAppIcon {
                    Image(nsImage: appIcon).resizable().scaledToFit().padding(canvas.u(16))
                } else if installedApp == nil, slot == .icon {
                    // No app yet (Steam still installing it): the store art is on its way; a generic controller
                    // under the download mark only looked broken.
                    Color.clear
                } else { Image(systemName: "gamecontroller.fill").resizable().scaledToFit().padding(canvas.u(30)) }
            } else { Color.clear }
        }
        .clipped()
        .preference(key: TileArtPendingKey.self, value: settled ? 0 : 1)
        .task(id: key) {
            defer { if !settled { settled = true } }
            let expected = key
            if slot == .cover || slot == .icon {
                appIcon = installedApp.map { SteamAppIconCache.icon(at: $0.url, buildID: appBuildID) }
                appIconPath = appIconRequestKey
            }
            guard let id = game.steamGame?.appID else { return }
            let request = SteamArtworkRequest(game: game, role: role)
            let url: URL?
            if remote == nil, let local = request.localURL(picks: picks) { url = local }
            // A square is always an icon, never store art cropped to a square: with no app yet (Steam still
            // installing the game), LaunchBox's Square, else nothing.
            else if remote == nil, request.wantsAutomaticIcon {
                url = await AppViewModel.automaticIconArtwork.automaticSteamIcon(titleID: game.personalizationReference.key,
                                                                                names: [game.name])
            } else if role == .square { url = nil }
            else { url = await SteamMetadataService.shared.image(appID: id, slot: slot, remote: remote) }
            guard !Task.isCancelled else { return }
            // Decoded off the main thread at the size its nxnative twin uses: a lazily decoded file cost the
            // first frame that drew it 40–60 ms.
            let decoded: NSImage? = if let url { await GameArtLoader.decode(at: url, maxPixelSize: slot.decodedSize) } else { nil }
            guard !Task.isCancelled else { return }
            if let decoded { TileArtMemo.store(decoded, for: "steam|\(expected)" as NSString) }
            else { TileArtMemo.shared.removeObject(forKey: "steam|\(expected)" as NSString) }
            image = decoded; loadedKey = expected
        }

        .accessibilityLabel(game.name)
    }
}

/// Installed apps' own icons by bundle path, shared by every tile that shows one.
@MainActor
private enum SteamAppIconCache {
    private static let icons = NSCache<NSString, NSImage>()
    private static func key(_ url: URL, _ buildID: String?) -> NSString { "\(url.path)|\(buildID ?? "")" as NSString }
    static func cachedIcon(at url: URL, buildID: String?) -> NSImage? { icons.object(forKey: key(url, buildID)) }
    static func icon(at url: URL, buildID: String?) -> NSImage {
        if let icon = cachedIcon(at: url, buildID: buildID) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: key(url, buildID))
        return icon
    }
}

private extension ArtworkSlot {
    /// The nxnative sizes: tiles' icons 512 px (`SpotlightTileArtwork`), box covers 900 (`SwitchBoxArtCover`),
    /// logos and heroes as `GameArtLoader`.
    var decodedSize: Int {
        switch self {
        case .icon: return 512
        case .cover: return 900
        case .logo: return 1600
        case .background: return 2560
        }
    }
}
